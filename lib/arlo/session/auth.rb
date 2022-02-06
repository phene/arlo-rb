module Arlo
  class Session
    class Auth
      include Requests

      PATHS = OpenStruct.new(
        auth: '/api/auth',
        start: '/api/startAuth',
        finish: '/api/finishAuth',
        get_factors: '/api/getFactors',
        validate: '/api/validateAccessToken'
      )

      attr_reader :token
      attr_reader :token64
      attr_reader :user_id
      attr_reader :web_id
      attr_reader :sub_id

      def load_existing_session
        if File.exist?(Arlo.configuration.session_file)
          session_info = YAML.load_file(Arlo.configuration.session_file)
          update_auth_info(session_info)
        end
      end

      def save_session(session_info)
        File.open(Arlo.configuration.session_file, 'w') do |f|
          f.write session_info.to_yaml
        end
      end

      def expires_at
        Time.at(@expires_at || 0)
      end

      def expired?
        Time.now > expires_at
      end

      def valid?
        !expired? and !!get(
          PATHS.validate + "?data=#{Time.now.to_i}",
        )
      end

      def start
        config = Arlo.configuration

        Arlo.logger.info 'Authenticating with Arlo...'

        body = post(
          PATHS.auth,
          params: {
            email: config.username,
            password: Base64.strict_encode64(config.password),
            language: 'en',
            EnvSource: 'prod',
          }
        )

        update_auth_info(body)

        if !body['authCompleted']
          Arlo.logger.debug 'Fetching MFA options...'
          factors = get(PATHS.get_factors + "?data=#{Time.now.to_i}")
          chosen_factor = factors['items'].find do |factor|
            factor['factorType'].downcase() == config.tfa_type && factor['factorNickname'] == config.tfa_username
          end
          chosen_factor_id = chosen_factor['factorId']

          raise 'No suitable MFA option!' unless chosen_factor_id

          mfa = Arlo::Session::MFA.mfa

          Arlo.logger.debug "Starting MFA verification with #{chosen_factor['factorNickname']}..."
          auth_start_response = post(
            PATHS.start,
            params: {
              factorId: chosen_factor_id,
            }
          )

          raise 'Failed to start MFA auth!' unless auth_start_response['factorAuthCode']

          otp = mfa.get_token

          raise 'Failed to fetch MFA token' unless otp

          auth_finish_response = post(
            PATHS.finish,
            params: {
              factorAuthCode: auth_start_response['factorAuthCode'],
              otp: otp
            }
          )

          Arlo.logger.debug 'Completed MFA verification'

          update_auth_info(auth_finish_response)

          raise 'Failed to validate token!' unless valid?

          save_session(auth_finish_response)
        end
      end

      def update_auth_info(auth_response)
        @token = auth_response['token']
        @user_id = auth_response['userId']
        @expires_at = auth_response['expiresIn']

        @token64 = Base64.strict_encode64(@token)
        @web_id = @user_id + '_web'
        @sub_id = "subscriptions/#{@web_id}"

        default_headers['Authorization'] = @token64
      end

      def with_client
        auth_uri = URI(HOSTS.auth)
        Net::HTTP.start(auth_uri.host, auth_uri.port, use_ssl: (auth_uri.scheme == 'https')) do |client|
          yield client
        end
      end

      def default_headers
        @default_headers ||= {
          'Accept' => 'application/json, text/plain, */*',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Content-Type' => 'application/json',
          'Origin' => HOSTS.origin,
          'Referer' => HOSTS.referer,
          'Source' => 'arloCamWeb',
          'User-Agent' => user_agent,
        }
      end
    end
  end
end
