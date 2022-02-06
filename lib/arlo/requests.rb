require 'net/http'

module Arlo
  module Requests
    USER_AGENTS = {
      arlo: [
        'Mozilla/5.0 (iPhone; CPU iPhone OS 11_1_2 like Mac OS X) ',
        'AppleWebKit/604.3.5 (KHTML, like Gecko) Mobile/15B202 NETGEAR/v1 ',
        '(iOS Vuezone)',
      ].join(''),
      iphone: [
        'Mozilla/5.0 (iPhone; CPU iPhone OS 13_1_3 like Mac OS X) ',
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.1 Mobile/15E148 Safari/604.1',
      ].join(''),
      ipad: [
        'Mozilla/5.0 (iPad; CPU OS 12_2 like Mac OS X) ',
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1 Mobile/15E148 Safari/604.1',
      ].join(''),
      mac: [
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) ',
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1.2 Safari/605.1.15',
      ].join(''),
      firefox: [
        'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:85.0) ',
        'Gecko/20100101 Firefox/85.0',
      ].join(''),
      linux: [
        'Mozilla/5.0 (X11; Linux x86_64) ',
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/88.0.4324.96 Safari/537.36',
      ].join(''),
      android: [
        'Mozilla/5.0 (Linux; Android 9; SM-G950U)',
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/3.0.4577.75 Safari/537.36',
      ]
    }

    def get(path, **kwargs, &block)
      request(Net::HTTP::Get.new(path), **kwargs, &block)
    end

    def put(path, **kwargs, &block)
      request(Net::HTTP::Put.new(path), **kwargs, &block)
    end

    def post(path, **kwargs, &block)
      request(Net::HTTP::Post.new(path), **kwargs, &block)
    end

    def request(req, params: {}, headers: {}, raw: false, timeout: 60, raise_on_failure: false, &block)
      response = nil

      (1..10).each do
        default_headers.merge(headers).each do |header, value|
          req[header] = value #&.strip
        end
        req.body = params.to_json unless params.empty?

        response = with_client do |client|
          Arlo.logger.debug("Making request to #{client.address}:#{client.port}#{req.path}")
          Timeout.timeout(timeout, Net::ReadTimeout) do
            if block_given?
              response = client.request(req, &block)
              cookies = []
              (response.get_fields('set-cookie') || []).each do |cookie|
                next unless cookie
                cookies << cookie.split('; ')[0]
              end
              default_headers['Cookie'] = cookies.join('; ') if cookies.any?
              return
            end

            client.request(req)
          end
        end

        case response
        when Net::HTTPOK
          if response['set-cookie']
            cookies = []
            (response.get_fields('set-cookie') || []).each do |cookie|
              next unless cookie
              cookies << cookie.split('; ')[0]
            end
            default_headers['Cookie'] = cookies.join('; ') if cookies.any?
          end
          break
        when Net::HTTPForbidden # CloudFlare bullshit
          message = 'Received Net::HTTPForbidden'
          raise message if raise_on_failure
          Arlo.logger.warn message
          Arlo.logger.debug response.body
          default_headers['User-Agent'] = random_user_agent
          sleep(2)
        else
          message = "Received #{response.class}"
          raise message if raise_on_failure
          Arlo.logger.warn message
          Arlo.logger.debug response.body
          break
        end
      end

      return response if raw

      body = JSON.parse(response.body)

      if body['meta']
        if body['meta']['code'] == 200
          return body['data']
        else
          raise "Failed response: #{body}" if raise_on_failure
          Arlo.logger.warn "Failed response: #{body}"
        end
      elsif body.key?('success') && body['success']
        return body['data']
      else
        body
      end
    rescue JSON::ParserError
      raise "Failed to parse output as json: #{body}"
    end

    def user_agent(agent = Arlo.configuration.user_agent.to_sym)
      USER_AGENTS[agent]
    end

    def random_user_agent
      USER_AGENTS[USER_AGENTS.keys.sample(1).first]
    end
  end
end
