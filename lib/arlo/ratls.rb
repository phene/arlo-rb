require 'openssl'
require 'net/http'
require 'json'
require 'ostruct'

module Arlo
  # Remote Access To Local Storage
  class Ratls
    include Arlo::Requests

    PATHS = OpenStruct.new(
      generate_token: '/hmsweb/users/device/ratls/token',
      get_status: '/hmsweb/users/device/ratls/status',
      create_device_certs: '/hmsweb/users/devices/v2/security/cert/create',

      # Paths on the base station
      download_path: '/hmsls/download',
      library_path: '/hmsls/list' # /list/YYYYMMDD/YYYYMMDD(/device_id)
    )

    attr_reader :base_station
    attr_reader :account

    attr_reader :device_id
    attr_reader :user_id
    attr_reader :unique_id
    attr_reader :bearer_token

    attr_reader :port
    attr_reader :private_host
    attr_reader :public_host

    def initialize(base_station, public_endpoint: false)
      @base_station = base_station
      @account = base_station.account
      @unique_id = base_station.unique_id
      @device_id = base_station.device_id
      @user_id = base_station.user_id
      @expires_at = Time.at(0)

      @public_endpoint = public_endpoint

      check_device_certs
      open_port
    end

    def open_port(tries: 3)
      # load_session if tries == 3

      status = get_status

      unless status['ratlsEnabled'] && status['remoteAccessEnabled'] == public_endpoint?
        enable_ratls
        sleep 5
      end

      return unless expired? || tries < 3

      @bearer_token = fetch_bearer_token
      @expires_at = Time.now + 600

      Arlo.logger.info("Requesting port opening from #{base_station}")

      Timeout.timeout(300) do
        response = account.session.notify(
          base_station,
          params: {
            action: 'open',
            resource: 'storage/ratls',
            from: user_id,
            publishResponse: true
          },
          wait_for: :event
        )

        properties = response['properties']
        @private_host = properties['privateIP']
        @public_host = properties['publicIP']
        @port = properties['port']
      end

      Arlo.logger.debug "Checking connectivity to #{url}..."

      response = nil
      begin
        response = Timeout.timeout(5) do
          get('/hmsls/connectivity', raw: true)
        end
      rescue Timeout::Error
        response = Timeout::Error.new
      end

      case response
      when Errno::ECONNREFUSED, Timeout::Error
        Arlo.logger.warn "#{base_station} was not accessible. jiggling (#{tries} tries remaining)..."
        disable_ratls
        sleep 10
        return open_port(tries: tries - 1) if tries.positive?

        raise "Failed to open port on #{base_station}!"
      end

      Arlo.logger.info("#{base_station} is now accessible!")

      # save_session

      true
    rescue Timeout::Error
      raise 'Failed to open ratls port!'
    end

    # def session_file
    #   @session_file ||= File.join(Arlo.configuration.config_dir, "#{device_id}.yml")
    # end

    # def load_session
    #   return unless File.exist? session_file
    #   properties = YAML.load_file(session_file)

    #   @bearer_token = properties['ratlsToken']
    #   @private_host = properties['privateIP']
    #   @public_host = properties['publicIP']
    #   @port = properties['port']
    #   @expires_at = Time.at(properties['expires_at'])
    # end

    # def save_session
    #   properties = {
    #     'ratlsToken' => bearer_token,
    #     'expires_at' => @expires_at.to_i,
    #     'privateIP' => @private_host,
    #     'publicIP' => @public_host,
    #     'port' => @port,
    #   }

    #   File.open(session_file, 'w') do |f|
    #     f.write properties.to_yaml
    #   end
    # end

    def expired?
      Time.now > @expires_at
    end

    def get_status
      account.session.get(
        File.join(PATHS.get_status, device_id),
      )
    end

    def fetch_bearer_token
      Arlo.logger.debug("Fetching bearer token to talk to #{base_station}")
      response = account.session.get(
        File.join(PATHS.generate_token, device_id)
      )
      raise "Failed to get base station token for #{base_station.device_name}: #{response}" unless response.key? 'ratlsToken'
      response['ratlsToken']
    end

    def check_device_certs
      unless certificates.exists?
        certificates.generate_key_pair unless certificates.private_key

        response = account.session.post(
          PATHS.create_device_certs,
          params: {
            uuid: device_id,
            uniqueIds: [ unique_id ],
            publicKey: certificates.format_key_for_api(certificates.private_key.public_key.to_pem),
          },
          headers: { 'xcloudId' => base_station.xcloud_id },
        )

        raise "Error signing key: #{response['message']} - #{response['reason']}" unless response['certsData']

        certificates.update_certs(
          intermediate_cert: certificates.convert_api_response_to_pem(response['certsData'][0]['deviceCert']),
          client_cert: certificates.convert_api_response_to_pem(response['certsData'][0]['peerCert']),
          ca_cert: certificates.convert_api_response_to_pem(response['icaCert'])
        )
      end
    end

    def default_headers
      {
        "Authorization" => "Bearer #{bearer_token}",
        "Accept" => "application/json; charset=utf-8;",
        "Accept-Language" => "en-US,en;q=0.9",
        "Origin" => "https://my.arlo.com",
        "SchemaVersion" => "1",
        "User-Agent" => user_agent,
      }
    end

    def disable_ratls
      Arlo.logger.debug "Disabling RATLS on #{base_station}..."
      account.session.post(
        "/hmsweb/users/device/ratls/enable/#{device_id}",
        params: {
          enable: false
        },
      )

      account.session.post(
        "/hmsweb/users/device/ratls/remoteaccess/enable/#{device_id}",
        params: {
          enableRemoteAccess: false,
          refreshPort: false,
        }
      )
    end

    def enable_ratls
      Arlo.logger.debug "Enabling RATLS on #{base_station}..."
      response = account.session.post(
        "/hmsweb/users/device/ratls/enable/#{device_id}",
        params: {
          enable: true
        },
        raw: true
      )
      raise 'Failed to enable ratls' unless response

      response = account.session.post(
        "/hmsweb/users/device/ratls/remoteaccess/enable/#{device_id}",
        params: {
          enableRemoteAccess: public_endpoint?,
          refreshPort: true,
        },
        raw: true
      )
      raise 'Failed to enable remote access to ratls' unless response
    end

    def client_options
      @client_options ||= ssl_options.merge(use_ssl: true)
    end

    def certificates
      @certificates ||= Arlo::Ratls::Certificates.new(unique_id)
    end

    def ssl_options
      @ssl_options ||= {
        key: certificates.private_key,
        cert: certificates.client_cert,
        extra_chain_cert: [certificates.intermediate_cert],
        ca_file: certificates.ca_cert_path,
        verify_mode: OpenSSL::SSL::VERIFY_NONE, # We can't verify the base station's cert, but instead need it to trust ours
      }
    end

    def with_client
      Net::HTTP.start(host, port, client_options) do |client|
        yield client
      end
    end

    def public_endpoint?
      @public_endpoint
    end

    def host
      if public_endpoint?
        public_host
      else
        private_host
      end
    end

    def url
      "https://#{host}:#{port}"
    end
  end
end
