require 'yaml'

module Arlo
  class Configuration
    ATTRS = %i[
      username
      password
      tfa_type
      tfa_host
      tfa_username
      tfa_password
      user_agent
      library_days
    ]

    ATTRS.each do |attr|
      define_method attr do
        @config[attr.to_s]
      end
    end

    def initialize(config_path)
      @config_path = config_path
      @config = YAML.load_file(config_path)['arlo']
    end

    def config_dir
      @config_dir ||= File.dirname(@config_path)
    end

    def session_file
      @session_file ||= File.join(config_dir, 'session.yml')
    end

    def cert_path
      @cert_path ||= File.join(config_dir, 'certs')
    end

    def save_media_to
      @save_media_to ||= @config['save_media_to'].gsub(/\$\{(\w+)\}/, '%\1')
    end
  end

  def self.configuration(path = File.expand_path('~/.arlo/config.yml'))
    @configuration ||= Configuration.new(path)
  end
end
