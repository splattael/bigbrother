require "openssl"

module Bigbrother
  module Helper
    module SSLCertExpiry
      private def verify_not_after_expiry(ssl_min_days_valid, tcp_socket, hostname)
        context = OpenSSL::SSL::Context::Client.new
        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: hostname)
        cert = ssl_socket.peer_certificate
        cert_expires_at = cert.not_after

        if cert_expires_at.not_nil! - Time::Span.new(days: ssl_min_days_valid.not_nil!) < Time.utc
          fail "SSL certificate expires in < #{ssl_min_days_valid} days at #{cert_expires_at}"
        end

        cert_expires_at
      end
    end
  end
end
