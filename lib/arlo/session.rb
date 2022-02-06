require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'ostruct'
require 'base64'
require 'securerandom'

module Arlo
  HOSTS = OpenStruct.new(
    default: 'https://myapi.arlo.com',
    origin: 'https://my.arlo.com',
    referer: 'https://my.arlo.com/',
    auth: 'https://ocapi-app.arlo.com',
    tfa: 'https://pyaarlo-tfa.appspot.com',
    mqqt: 'mqtt-cluster.arloxcld.com'
  ).freeze

  class Session
    include Requests
    attr_reader :current_session

    TRANSID_PREFIX = "web"
    PATHS = OpenStruct.new(
      notify: '/hmsweb/users/devices/notify', # + /base_station_device_id
      v2_session: '/hmsweb/users/session/v2'
    )

    def initialize
      start
      sse_client.start
    end

    def start
      auth.load_existing_session
      auth.start if auth.expired?
      Arlo.logger.debug 'Starting session...'
      @current_session = get(PATHS.v2_session, raw: true, timeout: 10)
    end

    def auth
      @auth ||= Session::Auth.new
    end

    def sse_client
      @sse_client ||= SSEClient.new(self)
    end

    def with_client
      uri = URI(HOSTS.default)
      Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https')) do |client|
        yield client
      end
    end

    def notify(base_station, params: , timeout: nil, wait_for: :event)
      tx_id = send_notification(base_station, params: params)

      case wait_for
      when :event
        return wait_for_transaction(tx_id, timeout: timeout)
      when :response
        tx_id
      else
        raise 'only event supported'
      end
    end

    def wait_for_transaction(tx_id, **)
      sse_client.wait_for_transaction(tx_id)
    end

    def send_notification(base_station, params: {}, tx_id: generate_transaction_id, timeout: nil)
      params[:to] = base_station.device_id
      params[:from] ||= auth.web_id
      params[:transId] = tx_id

      response = post(
        File.join(PATHS.notify, base_station.device_id),
        params: params,
        headers: { 'xcloudId' => base_station.xcloud_id },
        raw: true
      )

      return tx_id if response.is_a? Net::HTTPOK
    end

    def generate_transaction_id(prefix = TRANSID_PREFIX)
      "#{prefix}!#{SecureRandom.uuid}"
    end

    def reset_client
      @default_headers = nil
      default_headers
    end

    def default_headers
      @default_headers ||= {
        'User-Agent' => user_agent,
        'Accept' => 'application/json',
        'Accept-Language' => 'en-US,en;q=0.9',
        'Auth-Version' => '2',
        'Authorization' => auth.token,
        'Content-Type' => 'application/json; charset=utf-8;',
        'Origin' => HOSTS.origin,
        'Pragma': 'no-cache',
        'Referer' => HOSTS.referer,
        'SchemaVersion' => '1',
      }
    end
  end
end
