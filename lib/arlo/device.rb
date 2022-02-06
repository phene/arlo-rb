module Arlo
  module Device
    def self.create(data, account)
      case data['deviceType']
      when 'basestation'
        BaseStation.new(data, account)
      when 'camera'
        Camera.new(data, account)
      else
        Generic.new(data, account)
      end
    end

    module AttributeMapper
      def map_attributes(attrs)
        attrs.each do |attr, json_key|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{attr}
              data['#{json_key}']
            end

            def #{attr}=(value)
              data['#{json_key}'] = value
            end
          RUBY
        end
      end
    end
  end
end
