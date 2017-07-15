require "socket"

module Bigbrother
  module Check
    class HostIp
      include Check

      config "host_ip",
        host: String,
        port: Int32

      def check
        socket = Socket.tcp(Socket::Family::INET)
        socket.connect(@host, @port, 1.0)
      end

      def target
        "#{@host}:#{@port}"
      end
    end
  end
end
