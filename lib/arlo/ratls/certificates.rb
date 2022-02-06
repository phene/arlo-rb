require 'openssl'

module Arlo
  class Ratls
    class Certificates
      attr_reader :private_key_path
      attr_reader :unsigned_public_key_path
      attr_reader :ca_cert_path

      attr_reader :unique_id
      attr_reader :device_cert_path
      attr_reader :client_cert_path
      attr_reader :intermediate_cert_path

      def initialize(unique_id)
        @unique_id = unique_id
        @device_cert_path = File.join(Arlo.configuration.cert_path, unique_id)
        @client_cert_path = File.join(@device_cert_path, 'client.crt')
        @intermediate_cert_path = File.join(@device_cert_path, 'intermediate.crt')
        @private_key_path = File.join(Arlo.configuration.cert_path, 'private.pem')
        @unsigned_public_key_path = File.join(Arlo.configuration.cert_path, 'public.pem')
        @ca_cert_path = File.join(@device_cert_path, 'ica.crt')
      end

      def format_key_for_api(pem)
        pem.gsub(/-+[\w\s]+-+/, '').gsub("\n", '')
      end

      def convert_api_response_to_pem(cert)
        cert = StringIO.new(cert)
        pem = StringIO.new
        pem.puts '-----BEGIN CERTIFICATE-----'
        while line = cert.read(64)
          pem.puts line
        end
        pem.puts '-----END CERTIFICATE-----'
        pem.rewind
        pem.read
      end

      def fetch_cert(path)
        OpenSSL::X509::Certificate.new(File.read(path))
      end

      def exists?
        File.exist?(client_cert_path) && File.exist?(intermediate_cert_path)
      end

      def private_key
        @private_key ||= OpenSSL::PKey::RSA.new(File.read(private_key_path)) if File.exist? private_key_path
      end

      def client_cert
        @client_cert ||= fetch_cert(client_cert_path) if File.exist? client_cert_path
      end

      def intermediate_cert
        @intermediate_cert ||= fetch_cert(intermediate_cert_path) if File.exist? intermediate_cert_path
      end

      def generate_key_pair
        @private_key = OpenSSL::PKey::RSA.generate(2048, 65537)

        FileUtils.mkdir_p Arlo.configuration.cert_path

        File.open(private_key_path, 'w') do |f|
          f.write @private_key.to_pem
        end

        File.open(unsigned_public_key_path, 'w') do |f|
          f.write @private_key.public_key.to_pem
        end
      end

      def update_certs(intermediate_cert:, client_cert:, ca_cert:)
        FileUtils.mkdir_p device_cert_path

        File.open(intermediate_cert_path, 'w') do |f|
          f.write intermediate_cert
        end
        @intermediate_cert = nil

        File.open(client_cert_path, 'w') do |f|
          f.write client_cert
        end
        @client_cert = nil

        File.open(ca_cert_path, 'w') do |f|
          f.write ca_cert
        end
        @ca_cert = nil
      end
    end
  end
end
