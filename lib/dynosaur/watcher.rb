require 'active_support/core_ext/numeric/time'
require 'dynosaur/chunk_scanner'
require 'dynosaur/heroku_api_client'
require 'dynosaur/concerns/logging'

module Dynosaur
  class Watcher
    include Concerns::Logging

    REFRESH_DYNOS_EVERY = 5.minutes

    def initialize(app, token)
      @heroku = HerokuApiClient.new(app, token)
    end

    def boot
      EventMachine.add_periodic_timer(REFRESH_DYNOS_EVERY) { refresh_dynos }
      refresh_dynos
      watch_log_stream
    end

    private

    def refresh_dynos
      @heroku.dynos do |dynos|
        logger.info "Refreshed dynos: #{dynos.sort.join(', ')}"
      end
    end

    def watch_log_stream
      @heroku.logs do |chunk|
        ChunkScanner.new(chunk).scan do |time, dyno, message|
          logger.info "Saw #{dyno} at #{time}"
        end
      end
    end
  end
end
