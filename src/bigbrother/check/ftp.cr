require "socket"
require "openssl"

require "../helper/ssl_cert_expiry"

module Bigbrother
  module Check
    # Speaks just enough of RFC 959 (and RFC 4217 for FTPS) to tell a healthy
    # FTP server from a broken one: read the greeting, optionally upgrade to
    # TLS, optionally log in, then hang up.
    #
    # A plain TCP check on port 21 only proves that something accepts
    # connections. It stays green while the TLS handshake is broken or while
    # every login fails because the user database was never built -- which is
    # exactly how an FTP server tends to break. This check walks far enough
    # into the session to catch those.
    #
    # No data connection is opened, so neither PASV nor the passive port range
    # has to be reachable for the check to pass.
    class Ftp
      include Check
      include Helper::SSLCertExpiry

      # How TLS is negotiated.
      #
      # - `none` -- plain FTP, nothing is encrypted.
      # - `explicit` -- connect in the clear on the regular port (21) and
      #   upgrade via `AUTH TLS` (RFC 4217). This is what "FTPS" normally
      #   means today and what `pure-ftpd --tls` serves.
      # - `implicit` -- TLS from the first byte, conventionally on port 990.
      enum Tls
        None
        Explicit
        Implicit
      end

      # Guards against a server that never stops sending continuation lines.
      # `read_timeout` catches a stalled connection; this catches a fast one.
      MAX_REPLY_LINES = 64

      @cert_expires_at : Time?

      config "ftp",
        host: String,
        port: {
          type:    Int32,
          default: 21,
        },
        tls: {
          type:    Tls,
          default: Tls::Explicit,
        },
        user: {
          type:    String,
          nilable: true,
          default: nil,
        },
        password: {
          type:    String,
          nilable: true,
          default: nil,
        },
        match_banner: {
          type:    Regex,
          nilable: true,
          default: nil,
        },
        connect_timeout: {
          type:    Int32,
          default: 10,
        },
        read_timeout: {
          type:    Int32,
          default: 10,
        },
        ssl_verify: {
          type:    Bool,
          default: true,
        },
        ssl_min_days_valid: {
          type:    Int32,
          nilable: true,
          default: 7,
        }

      def endpoint
        String.build do |io|
          io << (@tls.none? ? "ftp" : "ftps")
          io << "://"
          io << @user << '@' if @user
          io << @host << ':' << @port
        end
      end

      def label
        if cert_expires_at = @cert_expires_at
          "#{endpoint} cert_expires_at=#{cert_expires_at}"
        else
          endpoint
        end
      end

      def check
        @cert_expires_at = nil

        # `TCPSocket.open` has no timeout parameters, so the socket is built
        # and closed by hand.
        tcp_socket = TCPSocket.new(@host, @port, connect_timeout: @connect_timeout.seconds)
        tcp_socket.read_timeout = @read_timeout.seconds
        tcp_socket.sync = true

        ssl_socket = nil

        begin
          if @tls.implicit?
            # Nothing is exchanged in the clear, so the greeting only arrives
            # once the handshake is through.
            socket = ssl_socket = start_tls(tcp_socket)
            banner = expect(socket, 220, "greeting")
          else
            socket = tcp_socket
            banner = expect(socket, 220, "greeting")

            if @tls.explicit?
              send_command(socket, "AUTH TLS")
              expect(socket, 234, "AUTH TLS")
              socket = ssl_socket = start_tls(tcp_socket)
            end
          end

          if match_banner = @match_banner
            unless match_banner.match(banner)
              fail "match_banner=#{match_banner}, banner=#{banner.lines.first?}"
            end
          end

          login(socket) if @user

          # Politeness, not a health signal: the session already proved what
          # the check cares about, so a server that hangs up rudely here
          # should not page anyone.
          begin
            send_command(socket, "QUIT")
            read_reply(socket)
          rescue IO::Error | Failure
          end
        ensure
          begin
            ssl_socket.try(&.close)
          rescue IO::Error | OpenSSL::SSL::Error
            # the server may already be gone; the check is over either way
          end
          tcp_socket.close
        end
      end

      private def start_tls(tcp_socket)
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE unless @ssl_verify

        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: @host)
        ssl_socket.sync = true

        @cert_expires_at = verify_not_after_expiry(@ssl_min_days_valid, ssl_socket) if @ssl_min_days_valid

        ssl_socket
      end

      private def login(socket)
        send_command(socket, "USER #{@user}")
        code, message = read_reply(socket)

        case code
        when 230
          # Already logged in -- this server wants no password for this user.
          return
        when 331
          # Password expected, fall through.
        else
          fail "USER: #{message.lines.first?}"
        end

        send_command(socket, "PASS #{@password}")
        expect(socket, 230, "PASS")
      end

      private def send_command(socket, command)
        socket << command << "\r\n"
        socket.flush
      end

      # Consumes one reply, including its continuation lines, and fails unless
      # it carries *expected_code*.
      private def expect(socket, expected_code, what)
        code, message = read_reply(socket)
        # The reply text already starts with its code, so it is not repeated.
        fail "#{what}: #{message.lines.first?}" unless code == expected_code
        message
      end

      # Reads a reply as defined by RFC 959: either a single `NNN text` line or
      # an `NNN-text` line followed by continuation lines up to one starting
      # with `NNN ` (the code plus a space).
      private def read_reply(socket) : {Int32, String}
        line = read_line(socket)
        code = line[0, 3]?.try(&.to_i?)
        fail "malformed reply: #{line.inspect}" unless code

        return {code, line} unless line[3]? == '-'

        terminator = "#{line[0, 3]} "
        lines = [line]

        until lines.last.starts_with?(terminator)
          if lines.size >= MAX_REPLY_LINES
            fail "reply exceeds #{MAX_REPLY_LINES} lines"
          end
          lines << read_line(socket)
        end

        {code, lines.join('\n')}
      end

      private def read_line(socket)
        socket.gets(chomp: true) || fail("connection closed by server")
      end
    end
  end
end
