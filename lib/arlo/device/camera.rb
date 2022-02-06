module Arlo
  module Device
    class Camera < Generic
      extend AttributeMapper

      ATTRS = {
        last_image_uploaded: 'lastImageUploaded',
        last_image_url: 'presignedLastImageUrl',
        snapshot_url: 'presignedSnapshotUrl',
        full_frame_snapshot_url: 'presignedFullFrameSnapshotUrl',
      }

      map_attributes ATTRS

      def start_stream(local: false)
        params = {
          action: 'set',
          from: web_id,
          properties: {
            activityState: 'startUserStream',
            cameraId: device_id,
          },
          publishResponse: true,
          responseUrl: '',
          resource: self.resource_id,
          to: parent_id,
          transId: account.session.generate_transaction_id
        }

        Arlo.logger.info "Starting stream from #{self}"
        response = account.session.post(
          '/hmsweb/users/devices/startStream',
          params: params,
          headers: { 'xcloudId' => xcloud_id }
        )

        url = if local
          tls_params = {
            cert: File.join(Arlo.configuration.cert_path, base_station.unique_id, 'peer.crt'),
            key: File.join(Arlo.configuration.cert_path, 'private.pem'),
            cafile: File.join(Arlo.configuration.cert_path, 'ica.crt'),
            verify: '0'
          }.map { |k,v| "#{k}=#{v}" }.join('&')

          "tls://#{base_station.ratls.host}:554/#{device_id}/tcp/avc?#{tls_params}"
        else
          response['url'].sub('rtsp://', 'rtsps://')
        end

        Arlo::Stream.new(self, url)
      end

      def stop_stream
        Arlo.logger.info("Stopping stream from #{self}")
        account.session.notify(
          base_station,
          params: {
            action: 'set',
            properties: {
              activityState: 'idle',
            },
            publishResponse: true,
            resource: resource_id
          },
          wait_for: :response
        )
      end

      def web_id
        @web_id ||= user_id + '_web'
      end

      def resource_type
        'cameras'
      end

      def base_station
        @base_stations ||= account.base_stations.find do |base_station|
          base_station.device_id == parent_id
        end
      end

      def spotlight
        @spotlight ||= Spotlight.new(self)
      end

      class Spotlight
        attr_reader :camera
        attr_reader :base_station
        attr_reader :session

        def initialize(camera)
          @camera = camera
          @session = camera.account.session
          @base_station = camera.base_station
        end

        def on!
          @on = true
          Arlo.logger.info "Enabling spotlight on #{camera}"
          session.notify(
            base_station,
            params: {
              action: 'set',
              properties: {
                spotlight: {
                  enabled: true,
                },
              },
              publishResponse: true,
              resource_id: camera.resource_id,
            },
            wait_for: :response
          )
        end

        def off!
          @on = false
          Arlo.logger.info "Disabling spotlight on #{camera}"
          session.notify(
            base_station,
            params: {
              action: 'set',
              properties: {
                spotlight: {
                  enabled: false,
                },
              },
              publishResponse: true,
              resource_id: camera.resource_id
            },
            wait_for: :response
          )
        end

        def on?
          @on
        end
      end
    end
  end
end
