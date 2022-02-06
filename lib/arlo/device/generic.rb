module Arlo
  module Device
    class Generic
      extend AttributeMapper

      ATTRS = {
        device_id: 'deviceId',
        device_name: 'deviceName',
        device_type: 'deviceType',
        user_id: 'userId',
        unique_id: 'uniqueId',
        xcloud_id: 'xCloudId',
        model_id: 'modelId',
        parent_id: 'parentId',
        last_modified_epoch_ms: 'lastModified',
        date_created_epoch_ms: 'dateCreated',
        time_zone: 'timeZone',
      }

      map_attributes ATTRS

      attr_reader :data
      attr_reader :account

      def initialize(data, account)
        @data = data
        @account = account
      end

      def last_modified_at
        @last_modified_at ||= Time.at(last_modified_epoch_ms / 1000.0)
      end

      def created_at
        @created_at ||= Time.at(date_created_epoch_ms / 1000.0)
      end

      def resource_id
        "#{resource_type}/#{device_id}"
      end

      def to_s
        "<#{self.class.name.split('::').last} device_name=#{device_name} device_id=#{device_id}>"
      end
    end
  end
end
