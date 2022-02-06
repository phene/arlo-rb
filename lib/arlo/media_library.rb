require 'parallel'
require 'fileutils'
require 'net/http'
require 'tempfile'

module Arlo
  class Video
    attr_reader :library
    attr_reader :data

    def initialize(data, library)
      @data = data
      @library = library
    end

    def unique_id
      data['uniqueId']
    end

    def created_at
      if data['utcCreatedDate'] > 10000000000 # Probably in ms
        Time.at(data['utcCreatedDate'] / 1000)
      else
        Time.at(data['utcCreatedDate'])
      end
    end

    def content_url
      data['presignedContentUrl']
    end

    def camera_device_id
      data['deviceId']
    end

    def camera
      @camera ||= library.account.devices.find { |c| c.device_id == camera_device_id }
    end

    def download_path
      @download_path ||= begin
        destination = Arlo.configuration.save_media_to + '.mp4'
        destination.gsub!('%SN', camera.device_id)
        destination.gsub!('%N', camera.device_name)
        destination = created_at.strftime(destination)
        FileUtils.mkdir_p(File.dirname(destination))
        destination
      end
    end
  end

  class MediaLibrary
    attr_reader :source
    attr_reader :videos
    attr_reader :account

    def initialize(source, account)
      @source = source
      @account = account
      @videos = []
    end

    def add_video(data)
      Video.new(data, self).tap do |video|
        videos << video
      end
    end

    def download_videos(threads: 0)
      requesters = {}
      Arlo.logger.debug "Downloading media library in #{threads} threads..."

      Parallel.each(videos, in_threads: threads) do |video|
        next if File.exist? video.download_path

        url = video.content_url
        requester = source

        if source.is_a? Device::BaseStation
          url = URI(File.join(Ratls::PATHS.download_path, url))
          requester = source.ratls
        else
          url = URI(url)
          requesters[url.host] ||= CloudDownloader.new(account.session, url.host, url.port)
          requester = requesters[url.host]
        end

        Arlo.logger.info "Downloading #{video.download_path} from #{source}"

        requester.get("#{url.path}#{"?#{url.query}" if url.query}", raw: true) do |response|
          raise "Could not fetch video: #{response.class}" unless response.is_a? Net::HTTPOK
          tmp = Tempfile.new(File.basename(video.download_path))
          File.open(tmp.path, 'w') do |f|
            response.read_body do |part|
              f.write part
            end
          end
          FileUtils.mv(tmp.path, video.download_path)
        end
      end
    end
  end

  class CloudDownloader
    include Requests

    attr_reader :session
    attr_reader :host
    attr_reader :port

    def initialize(session, host, port)
      @session = session
      @host = host
      @port = port
    end

    def with_client
      yield Net::HTTP.start(host, port, ssl: true)
    end

    def default_headers
      @default_headers ||= {}
    end
  end
end
