require 'base64'
require 'dynosaur/concerns/logging'
require 'em-http-request'
require 'json'

module Dynosaur
  class HerokuApiClient
    include Concerns::Logging

    BASE_URL = 'https://api.heroku.com'

    def initialize(app, token)
      @app = app
      @token = token
    end

    def dynos(&callback)
      request = request('/dynos').get(head: headers)

      request.callback do
        dynos = JSON.parse(request.response).map { |dyno| dyno['name'] }
        callback.call dynos
      end

      request.errback do
        logger.error "Couldn't list dynos for #{@app}"
      end
    end

    def logs(&callback)
      log_stream_url do |log_stream_url|
        request = EventMachine::HttpRequest.new(log_stream_url).get
        request.stream &callback

        request.errback do
          logger.error "Couldn't open log stream from #{log_stream_url}"
        end
      end
    end

    private

    def encoded_token
      Base64.encode64(":#{@token}").chomp
    end

    def headers
      @headers ||= {
        'Accept' => 'application/vnd.heroku+json; version=3',
        'Authorization' => encoded_token
      }
    end

    def log_stream_url(&callback)
      body = JSON.generate(lines: 10, source: 'app', tail: true)
      request = request('/log-sessions').post(head: headers, body: body)

      request.callback do
        log_stream_url = JSON.parse(request.response)['logplex_url']
        callback.call log_stream_url
      end

      request.errback do
        logger.error "Couldn't acquire log stream URL"
      end
    end

    def request(path)
      url = BASE_URL + "/apps/#{@app}/#{path}".squeeze('/')
      EventMachine::HttpRequest.new url
    end
  end
end
