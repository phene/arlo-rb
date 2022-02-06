require 'net/http'

# patch Net::HTTP to support extra_chain_cert
class Net::HTTP
  SSL_IVNAMES << :@extra_chain_cert unless SSL_IVNAMES.include?(:@extra_chain_cert)
  SSL_ATTRIBUTES << :extra_chain_cert unless SSL_ATTRIBUTES.include?(:extra_chain_cert)

  attr_accessor :extra_chain_cert
end
