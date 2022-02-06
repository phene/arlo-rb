require 'ostruct'
require 'net/http'

module Arlo
  class SSEClient
    attr_reader :session
    attr_reader :event_client_id
    attr_reader :last_message_id

    PATHS = OpenStruct.new(
      subscribe: '/hmsweb/client/subscribe'
    )

    def initialize(session)
      @session = session
      @transaction_lock = Mutex.new
      @transactions = {}
    end

    def connect
      headers = session.default_headers.dup.merge(
        'Cache-Control' => 'no-cache',
        'Accept' => 'text/event-stream',
      )
      headers.delete('Content-Type')
      headers['Last-Event-ID'] = last_message_id if last_message_id

      req = Net::HTTP::Get.new(PATHS.subscribe)
      headers.each do |header, value|
        req[header] = value
      end

      Arlo.logger.debug 'SSE Client establishing connection...'

      session.with_client do |client|
        client.request(req) do |response|
          buffer = ''
          response.read_body do |chunk|
            buffer += chunk
            while index = buffer.index(/\r\n\r\n|\n\n/)
              stream = buffer.slice!(0..index).strip
              next if stream.empty?
              event = parse_stream(stream)
              handle_event event
            end
          end
        end
      end
    end

    def handle_event(event)
      @last_message_id = event[:id] if event.key? :id
      case event[:event]
      when 'message'
        Arlo.logger.debug "Received event: #{event.to_json}"
        @transaction_lock.synchronize do
          if event[:data].key? 'status'
            cv = @transactions['status']
            @transactions['status'] = event[:data]['status']
            if cv.is_a? ConditionVariable
              cv.signal
            end
          elsif event[:data]['transId']
            cv = @transactions[event[:data]['transId']]
            @transactions[event[:data]['transId']] = event[:data]
            if cv.is_a? ConditionVariable
              cv.signal
            end
          end
        end
      end
    end

    def parse_stream(stream)
      {}.tap do |event|
        stream.split(/\r?\n/).each do |part|
          if part =~ /^(\w+):'?(.+)'?$/
            event[$1.to_sym] = $2.strip
          end
        end
        event[:data] = JSON.parse(event[:data])
      end
    end

    def wait_for_transaction(transaction_id)
      Arlo.logger.debug "Waiting for SSE transaction #{transaction_id}"
      @transaction_lock.synchronize do
        unless @transactions[transaction_id]
          @transactions[transaction_id] = ConditionVariable.new
          @transactions[transaction_id].wait(@transaction_lock)
        end
        Arlo.logger.debug "Returning SSE transaction response for #{transaction_id}"
        return @transactions.delete(transaction_id)
      end
    end

    def start
      raise "Already started SSEClient thread!" if @thread
      @thread = Thread.new do
        loop do
          connect
        rescue Net::ReadTimeout
        rescue => e
          Arlo.logger.warn "SSE disconnected due to #{e}"
        end
      end
    end

    def stop
      raise 'SSEClient thread is not running' unless @thread
      @thread.kill
      @thread = nil
    end
  end
end
