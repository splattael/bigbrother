require "socket"

require "../helper/ssl_cert_expiry"

module Bigbrother
  module Check
    class HostIp
      include Check
      include Helper::SSLCertExpiry

      @cert_expires_at : Time?

      config "host_ip",
        host: String,
        port: Int32,
        ssl_min_days_valid: {
          type: Int32,
          nilable: true,
          default: 7
        }

      def check
        TCPSocket.open(@host, @port) do |tcp_socket|
          if @ssl_min_days_valid
            @cert_expires_at = verify_not_after_expiry(@ssl_min_days_valid, tcp_socket, @host)
          else
            tcp_socket.connect(@host, @port, 1.0)
          end
        end
      end

      def label
        if @cert_expires_at
          "#{@host}:#{@port} cert_expires_at=#{@cert_expires_at}"
        else
          "#{@host}:#{@port}"
        end
      end
    end
  end
end
