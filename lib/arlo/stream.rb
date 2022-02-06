require 'open3'
require 'fileutils'

class Arlo::Stream
  include Arlo::Requests

  VLC = '/Applications/VLC.app/Contents/MacOS/VLC'
  STREAM_DIR = File.expand_path('~/Downloads/stream')

  attr_reader :uri
  attr_reader :url
  attr_reader :session
  attr_reader :account
  attr_reader :camera

  def initialize(camera, url)
    @camera = camera
    @account = camera.account
    @session = camera.account.session
    @url = url
    @uri = URI(url)
    @account.add_stream(self)
  end

  def play
    if local?
      play_local
    else
      play_remote
    end
  end

  def play_local
    raise NotImplemented, 'Streaming from the base station is not yet supported'
  end

  def play_remote
    play_remote_with_ffmpeg
  end

  def play_remote_with_rtsp(debug: false)
    with_local_stream_file('stream.m3u8') do |stream_file|
      client = rtsp_client

      puts client.server_uri                   # => #<URI::Generic:0x00000100ba4db0 URL:rtsp://64.202.98.91:554/sa.sdp>
      puts client.session_state                # => :init
      puts client.cseq                         # => 1
      puts client.capturer.ip_addressing_type  # => :unicast
      puts client.capturer.rtp_port            # => 6970
      puts client.capturer.capture_file        # => #<File:/var/folders/tg/j9jxvvfs4qn9cg4vztzyy2gc0000gp/T/rtp_capture.raw-59901-1l8dgv2>
      puts client.capturer.transport_protocol  # => :UDP

      debugger

      response = client.options
      puts response.class             # => RTSP::Response
      puts response.code              # => 200
      puts response.message           # => "OK"
      puts client.cseq                # => 2
      debugger
      puts
    rescue => e
      debugger
      puts

    end
  end

  def rtsp_client
    RTSP::Client.new(url)
  end

  def play_remote_with_ffmpeg(debug: false)
    with_local_stream_file('stream.m3u8') do |stream_file|
      Arlo.logger.info "Streaming #{camera} to ffmpeg..."
      ffmpeg = Thread.new do
        system("ffmpeg -i '#{url}' -fflags flush_packets -max_delay 2 -flags -global_header -hls_time 2 -hls_list_size 3 -vcodec copy #{'-loglevel debug' if debug} -y #{stream_file} #{'2> /dev/null' unless debug}")
      end

      stream_data_file = File.join(File.dirname(stream_file), 'stream0.ts')

      sleep(0.25) until File.exist? stream_data_file

      vlc = Thread.new do
        Arlo.logger.info "Sending #{camera} stream to VLC..."
        system("#{VLC} #{stream_file} > /dev/null 2>/dev/null")
      end

      yield if block_given?

      vlc.join
    ensure
      ffmpeg.kill
    end
  end

  def with_local_stream_file(stream_name = 'stream.m3u8')
    FileUtils.mkdir_p STREAM_DIR
    yield File.join(STREAM_DIR, stream_name)
  ensure
    FileUtils.rm_r STREAM_DIR, force: true
  end

  def stop
    camera.stop_stream
  end

  def local?
    uri.host == base_station.ratls.host
  end

  def base_station
    camera.base_station
  end
end
