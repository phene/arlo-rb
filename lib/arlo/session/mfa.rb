require 'net/imap'

module Arlo
  class Session
    module MFA
      def self.mfa(type = Arlo.configuration.tfa_type)
        case type.to_sym
        when :email
          IMAP.new(
            host: Arlo.configuration.tfa_host,
            username: Arlo.configuration.tfa_username,
            password: Arlo.configuration.tfa_password
          )
        when :console
          Console.new
        else
          raise "Unkown MFA type: #{type}"
        end
      end

      class Console
        def start
        end

        def get_token
          print "MFA Token Code: "
          gets.strip
        end
      end

      class IMAP
        ARLO_MFA_SENDER = 'do_not_reply@arlo.com'
        TIMEOUT = 60
        DELAY = 5

        def initialize(host:, username:, password:)
          @host = host
          @username = username
          @password = password
          start
        end

        def start
          @start_time = Time.now
          Arlo.logger.debug "Logging into #{@username} mailbox..."
          imap.login(@username, @password)
          imap.examine('INBOX')
          @existing_message_ids = fetch_message_ids
        end

        def get_token
          Timeout.timeout(TIMEOUT) do
            loop do
              sleep DELAY

              message_ids = fetch_message_ids

              next if message_ids == @existing_message_ids

              Arlo.logger.debug 'Checking for e-mails with MFA token...'

              (message_ids - @existing_message_ids).each do |message_id|
                body = fetch_message_body(message_id)
                if body =~ /^\W*(\d{6})\W*$/
                  Arlo.logger.debug 'MFA token found!'
                  delete_message(message_id)
                  return $1
                end
              end

              @existing_message_ids = message_ids
            end
          end
        ensure
          imap.close
          imap.logout
        end

        def fetch_message_body(message_id)
          message = imap.fetch(message_id, 'BODY[TEXT]').first
          message.attr['BODY[TEXT]']
        end

        def delete_message(message_id)
          imap.store(message_id, '+FLAGS', [:Deleted])
        end

        def fetch_message_ids
          imap.search(['FROM', ARLO_MFA_SENDER])
        end

        def imap
          @imap ||= Net::IMAP.new(@host, ssl: true)
        end
      end
    end
  end
end
