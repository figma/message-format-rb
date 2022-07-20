require 'twitter_cldr'

#
# Interpreter
#
# Turns this:
#  [ "You have ", [ "numBananas", "plural", 0, {
#       "=0": [ "no bananas" ],
#      "one": [ "a banana" ],
#    "other": [ [ '#' ], " bananas" ]
#  } ], " for sale." ]
#
# into this:
#  format({ numBananas:0 })
#  "You have no bananas for sale."
#
module MessageFormat
  class Interpreter

    def initialize ( options=nil )
      if options and options.has_key?(:locale)
        @locale = options[:locale]
      else
        @locale = TwitterCldr.locale
      end
      @require_all_args = !!options[:require_all_args]
    end

    def assert_arg_exists(args, id)
      if @require_all_args && args[id].nil?
        raise MissingArgError.new "Require #{id} in the arguments, which were #{args}"
      end
      return !args[id].nil?
    end

    def interpret ( elements )
      interpret_subs(elements)
    end

    def interpret_subs ( elements, parent=nil )
      elements = elements.map do |element|
        interpret_element(element, parent)
      end

      # optimize common case
      if elements.length == 1
        return elements[0]
      end

      lambda do |args|
        elements.map { |element| element.call(args) }.join ''
      end
    end

    def interpret_element ( element, parent=nil )
      if element.is_a?(String)
        return lambda { |_=nil| element }
      end

      id, type, style = element
      offset = 0

      if id == '#'
        id = parent[0]
        type = 'number'
        offset = parent[2] || 0
        style = nil
      end

      id = id.to_sym # actual arguments should always be keyed by symbols

      case type
      when 'number'
        interpret_number(id, offset, style)
      when 'date', 'time'
        interpret_date_time(id, type, style)
      when 'plural', 'selectordinal'
        offset = element[2]
        options = element[3]
        interpret_plural(id, type, offset, options)
      when 'select'
        interpret_select(id, style)
      when 'spellout', 'ordinal', 'duration'
        interpret_number(id, offset, type)
      else
        interpret_simple(id)
      end
    end

    def interpret_number ( id, offset, style )
      locale = @locale
      lambda do |args|
        return '' if !assert_arg_exists(args, id)
        number = TwitterCldr::Localized::LocalizedNumber.new(args[id] - offset, locale)
        if style == 'integer'
          number.to_decimal.to_s(:precision => 0)
        elsif style == 'percent'
          number.to_percent.to_s
        elsif style == 'currency'
          number.to_currency.to_s
        elsif style == 'spellout'
          number.spellout
        elsif style == 'ordinal'
          number.to_rbnf_s('OrdinalRules', 'digits-ordinal')
        else
          number.to_s
        end
      end
    end

    def interpret_date_time ( id, type, style='medium' )
      locale = @locale
      lambda do |args|
        return '' if !assert_arg_exists(args, id)
        datetime = TwitterCldr::Localized::LocalizedDateTime.new(args[id], locale)
        datetime = type == 'date' ? datetime.to_date : datetime.to_time
        if style == 'medium'
          datetime.to_medium_s
        elsif style == 'long'
          datetime.to_long_s
        elsif style == 'short'
          datetime.to_short_s
        elsif style == 'full'
          datetime.to_full_s
        else
          datetime.to_additional_s(style)
        end
      end
    end

    def interpret_plural ( id, type, offset, children )
      parent = [ id, type, offset ]
      options = {}
      children.each do |key, value|
        options[key.to_sym] = interpret_subs(value, parent)
      end

      locale = @locale
      plural_type = type == 'selectordinal' ? :ordinal : :cardinal
      lambda do |args|
        return '' if !assert_arg_exists(args, id)
        arg = args[id]
        exactSelector = ('=' + arg.to_s).to_sym
        keywordSelector = TwitterCldr::Formatters::Plurals::Rules.rule_for(arg - offset, locale, plural_type)
        func =
          options[exactSelector] ||
            options[keywordSelector] ||
            options[:other]
        func.call(args)
      end
    end

    def interpret_select ( id, children )
      options = {}
      children.each do |key, value|
        options[key.to_sym] = interpret_subs(value, nil)
      end
      lambda do |args|
        return '' if !assert_arg_exists(args, id)
        selector = args[id].to_sym
        func =
          options[selector] ||
            options[:other]
        func.call(args)
      end
    end

    def interpret_simple ( id )
      lambda do |args|
        assert_arg_exists(args, id)
        args[id].to_s
      end
    end

    def self.interpret ( elements, options=nil )
      Interpreter.new(options).interpret(elements)
    end

    class MissingArgError < RuntimeError
    end
  end
end
