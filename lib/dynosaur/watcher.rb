require 'active_support/core_ext/numeric/time'
require 'dynosaur/chunk_scanner'
require 'dynosaur/heroku_api_client'
require 'dynosaur/concerns/logging'
require 'em-hiredis'

module Dynosaur
  class Watcher
    include Concerns::Logging

    DYNO_HISTORY_SIZE = 10
    REFRESH_DYNOS_EVERY = 5.minutes

    def initialize(app, token, dyno_types)
      @app = app
      @dyno_types = dyno_types
      @dynos = []

      @heroku = HerokuApiClient.new(app, token)
      @redis = EventMachine::Hiredis.connect(ENV['REDIS_URL'])
    end

    def boot
      logger.info "Watching #{@dyno_types.join(', ')} dynos"

      EventMachine.add_periodic_timer(REFRESH_DYNOS_EVERY) { refresh_dynos }
      refresh_dynos
      watch_log_stream
    end

    private

    def persist_dynos
      key = "dynosaur:#{@app}:dynos"

      @redis.multi
      @redis.del key
      @redis.sadd key, *@dynos
      @redis.publish key, JSON.generate(@dynos)
      @redis.exec
    end

    def persist_sightings(sightings)
      @redis.multi

      sightings.each do |dyno, details|
        key = "dynosaur:#{@app}:dynos:#{dyno}"
        @redis.rpush key, JSON.generate(details)
        @redis.ltrim key, DYNO_HISTORY_SIZE
      end

      @redis.publish "dynosaur:#{@app}:sightings", JSON.generate(sightings)
      @redis.exec
    end

    def refresh_dynos
      @heroku.dynos do |dynos|
        @dynos = dynos.select { |dyno| watch_dyno?(dyno) }
        persist_dynos
        logger.info "Refreshed dynos: #{@dynos.sort.join(', ')}"
      end
    end

    def watch_dyno?(dyno)
      type = dyno[/\A(\w+)\./, 1]
      @dyno_types.include? type
    end

    def watch_log_stream
      @heroku.logs do |chunk|
        sightings = {}

        ChunkScanner.new(chunk).scan do |time, dyno, message|
          if @dynos.include?(dyno)
            sightings[dyno] = { at: time, message: message }
          end
        end

        unless sightings.empty?
          persist_sightings sightings
          logger.debug "Saw #{sightings.keys.join(', ')}"
        end
      end
    end
  end
end
