require 'ext/net_http'
require 'logger'
require 'time'

require 'arlo/version'
require 'arlo/configuration'
require 'arlo/requests'
require 'arlo/sse_client'
require 'arlo/session'
require 'arlo/session/auth'
require 'arlo/session/mfa'
require 'arlo/stream'
require 'arlo/account'
require 'arlo/media_library'
require 'arlo/ratls'
require 'arlo/ratls/certificates'
require 'arlo/device'
require 'arlo/device/generic'
require 'arlo/device/camera'
require 'arlo/device/base_station'

module Arlo
  class << self
    attr_accessor :log_destination

    def logger
      @logger ||= Logger.new(@log_destination).tap do |logger|
        logger.formatter = lambda do |sev, time, progname, msg|
          "[#{time.strftime('%F %T.%3N')}] #{sev.to_s.ljust(5)} -- #{msg}\n"
        end
        logger.level = ENV['LOG_LEVEL'] || :info
      end
    end
  end

  Arlo.log_destination = $stdout
end
