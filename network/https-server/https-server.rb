#! /usr/bin/env ruby

require "openssl"
require "webrick"

cert = File.join(__dir__, "cert.pem")
key = File.join(__dir__, "key.pem")

server = WEBrick::HTTPServer.new(
  :DocumentRoot => ".",
  :Port => 4433,
  :SSLEnable => true,
  :SSLCertificate => OpenSSL::X509::Certificate.new(File.read(cert)),
  :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.read(key))
)

# cleanly shutdown the server after pressing Ctrl+C
trap "INT" do
  server.shutdown
end

puts "Starting HTTPS server on port 4433..."
server.start
