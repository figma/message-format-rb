require 'twitter_cldr'
require_relative 'message_format/version'
require_relative 'message_format/parser'
require_relative 'message_format/interpreter'

module MessageFormat
  class MessageFormat

    def initialize ( pattern, locale=nil, require_all_args=false)
      @locale = (locale || TwitterCldr.locale).to_sym
      @format = Interpreter.interpret(
        Parser.parse(pattern),
        { :locale => @locale, :require_all_args => require_all_args },
        )
    end

    def format ( args=nil )
      @format.call(args)
    end

  end

  class << self

    def new ( pattern, locale=nil, require_all_args=false)
      MessageFormat.new(pattern, locale, require_all_args)
    end

    def format_message ( pattern, args=nil, locale=nil )
      locale ||= TwitterCldr.locale
      Interpreter.interpret(
        Parser.parse(pattern),
        { :locale => locale.to_sym }
      ).call(args)
    end

  end
end
