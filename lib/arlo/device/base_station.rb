require 'date'

module Arlo
  module Device
    class BaseStation < Generic
      extend AttributeMapper

      ATTRS = {
        state: 'state',
        cvr_enabled: 'cvrEnabled',
        interface_version: 'interfaceVersion',
        interfaceSchemaVer: 'interfaceSchemaVer',
        owner: 'owner',
        connectivity: 'connectivity',
        cert_available: 'certAvailable',
        automation_revision: 'automationRevision',
        properties: 'properties',
        media_object_count: 'mediaObjectCount',
      }

      map_attributes ATTRS

      def initialize(data, account)
        super
        # Notifies backend that we want to listen for events
        Arlo.logger.debug "Setting up event subscriptions for #{self}"
        account.session.notify(
          self,
          params: {
            action: 'set',
            resource: "subscriptions/#{user_id}",
            properties: {
              devices: [device_id]
            }
          },
          wait_for: :response
        )
      end

      def fetch_media_library(start_date = (Date.today - Arlo.configuration.library_days.to_i),
                              end_date = Date.today)
        Arlo.logger.debug "Fetching #{self} media_library from #{start_date} to #{end_date}"
        MediaLibrary.new(self, account).tap do |media_library|
          (start_date.to_date..end_date.to_date).each do |date|
            datestamp = date.strftime('%Y%m%d')
            cameras.each do |camera|
              results = ratls.get(
                File.join(Ratls::PATHS.library_path, datestamp, datestamp, camera.device_id)
              )
              (results || []).each do |video_data|
                media_library.add_video(video_data)
              end
            end
          end
        end
      end

      def cameras
        @cameras ||= devices.select { |device| device.is_a? Arlo::Device::Camera }
      end

      def devices
        @devices ||= account.devices.select { |device| device.parent_id == device_id }
      end

      def ratls
        @ratls ||= Ratls.new(self)
      end

      def resource_type
        'basestations'
      end
    end
  end
end
