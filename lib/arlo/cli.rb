module Arlo
  class CLI < Thor
    desc 'backup', 'Back up recordings from base station or cloud'
    def backup
      Arlo.logger.info 'Connecting to Arlo...'
      account = Arlo::Account.new
      base_station = account.devices.find { |d| d.is_a? Arlo::Device::BaseStation }

      if base_station
        begin
          Arlo.logger.info "Connecting to #{base_station.device_name} to download recordings..."
          download_videos(base_station)
          library = base_station.fetch_media_library
          library.download_videos
        rescue => e
          Arlo.logger.error("#{e.class}: #{e.message} - #{e.backtrace.join("\n")}")
          Arlo.logger.warn "Failed to download from base station, falling back to cloud..."
          download_videos(base_station)
        end
      else
        Arlo.logger.info "Connecting to #{account} to download recordings..."
        download_videos(base_station)
      end
      Arlo.logger.info 'Completed!'
    end

    desc 'list', 'Lists cameras'
    def list
      account.devices.each do |device|
        puts device
      end
    end

    desc 'watch CAMERA', 'Starts video stream for camera'
    method_option :light, aliases: ['-l'], type: :boolean, default: false
    def watch(camera_name)
      camera = account.cameras.find { |d| d.device_name == camera_name }
      puts "Starting stream on #{camera.device_name}"
      stream = camera.start_stream
      if options[:light]
        puts 'Turning on spotlight'
        camera.spotlight.on!
      end

      stream.play_remote_with_ffmpeg
    ensure
      puts "Stopping stream on #{camera.device_name}"
      camera.spotlight.off! if camera.spotlight.on? && options[:light]
      stream.stop if stream
    end

    desc 'listen', 'Listen for events'
    def listen
      account
      sleep
    end

    no_tasks do
      def account
        @account ||= Arlo::Account.new
      end

      def download_videos(source)
        library = source.fetch_media_library
        library.download_videos
      end
    end
  end
end
