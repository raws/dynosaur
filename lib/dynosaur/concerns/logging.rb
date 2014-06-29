require 'logger'

module Dynosaur
  module Concerns
    module Logging
      def logger
        Dynosaur.logger
      end

      class LogFormatter
        FORMAT = "[%s] %s\n"

        def call(severity, time, program, message)
          FORMAT % [severity, message]
        end
      end
    end
  end

  class << self
    attr_accessor :logger
  end

  self.logger = Logger.new(STDOUT).tap do |logger|
    logger.formatter = Concerns::Logging::LogFormatter.new
  end
end
