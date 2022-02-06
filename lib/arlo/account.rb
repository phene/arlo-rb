module Arlo
  class Account
    attr_reader :session
    attr_reader :devices
    attr_reader :streams

    PATHS = OpenStruct.new(
      devices: '/hmsweb/v2/users/devices',
      library: '/hmsweb/users/library'
    )

    def initialize
      @session = Session.new
      @streams = []
    end

    def devices
      @devices ||= fetch_devices
    end

    def refresh_devices
      @devices = nil
      devices
    end

    def fetch_devices
      Arlo.logger.debug("Fetching devices for account")
      devices_data = session.get("#{PATHS.devices}?t=#{Time.now.to_i}")
      devices_data.map do |device_data|
        Device.create(device_data, self)
      end
    end

    def fetch_media_library(start_date = (Date.today - Arlo.configuration.library_days.to_i),
                            end_date = Date.today)
      Arlo.logger.debug "Fetching #{self} media_library from #{start_date} to #{end_date}"
      MediaLibrary.new(self, self).tap do |media_library|
        (start_date.to_date..end_date.to_date).each do |date|
          datestamp = date.strftime('%Y%m%d')
          Arlo.logger.debug "Fetching #{self} media library from #{datestamp}"
          results = session.post(
            PATHS.library,
            params: {
              dateFrom: datestamp,
              dateTo: datestamp,
            }
          )
          (results || []).each do |video_data|
            media_library.add_video(video_data)
          end
        end
      end
    end

    def cameras
      devices.select do |device|
        device.is_a? Arlo::Device::Camera
      end
    end

    def base_stations
      devices.select do |device|
        device.is_a? Arlo::Device::BaseStation
      end
    end

    def add_stream(stream)
      @streams << stream
    end

    def remove_stream(stream)
      @streams.delete stream
    end
  end
end
