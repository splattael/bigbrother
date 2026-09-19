require "openssl"

module Bigbrother
  module Helper
    module SSLCertExpiry
      # Wraps *tcp_socket* in a TLS client session and checks the peer's
      # certificate. The session is only used for the handshake -- callers that
      # need to keep talking over TLS build their own socket and use the
      # two-argument overload below.
      private def verify_not_after_expiry(ssl_min_days_valid, tcp_socket, hostname)
        context = OpenSSL::SSL::Context::Client.new
        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: hostname)
        verify_not_after_expiry(ssl_min_days_valid, ssl_socket)
      end

      private def verify_not_after_expiry(ssl_min_days_valid, ssl_socket : OpenSSL::SSL::Socket)
        cert = ssl_socket.peer_certificate
        cert_expires_at = cert.not_after

        if cert_expires_at.not_nil!("cert_expires_at missing") - Time::Span.new(days: ssl_min_days_valid.not_nil!("ssl_min_days_valid missing")) < Time.utc
          fail "SSL certificate expires in < #{ssl_min_days_valid} days at #{cert_expires_at}"
        end

        cert_expires_at
      end
    end
  end
end
