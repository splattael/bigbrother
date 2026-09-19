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
    # By default no data connection is opened, so neither PASV nor the passive
    # port range has to be reachable. Setting `transfer_path` adds a full
    # round trip -- upload, download, compare, delete -- which does need the
    # passive range, and which is the only way to catch a server that
    # authenticates fine but cannot actually move bytes (a full disk, a
    # read-only mount, an unreachable passive port range).
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
        transfer_path: {
          type:    String,
          nilable: true,
          default: nil,
        },
        transfer_content: {
          type:    String,
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
          transfer(socket) if @transfer_path

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

      # Uploads a payload, reads it back, compares it, and deletes it again.
      # This is the part of the check that needs a data connection.
      private def transfer(socket)
        path = @transfer_path.not_nil!("transfer_path missing")

        if tls?
          # RFC 4217: the data channel has its own protection level, and it
          # defaults to Clear even on a TLS control connection. pure-ftpd
          # refuses PROT P unless PBSZ was sent first.
          send_command(socket, "PBSZ 0")
          expect(socket, 200, "PBSZ 0")
          send_command(socket, "PROT P")
          expect(socket, 200, "PROT P")
        end

        send_command(socket, "TYPE I")
        expect(socket, 200, "TYPE I")

        # Unique per run: a leftover file from an earlier run would otherwise
        # let RETR succeed even when STOR silently wrote nothing.
        payload = @transfer_content || "bigbrother probe #{Time.utc.to_rfc3339} #{Random::Secure.hex(8)}\n"

        deleted = false
        begin
          with_data_connection(socket, "STOR #{path}", &.print(payload))

          retrieved = with_data_connection(socket, "RETR #{path}", &.gets_to_end)
          unless retrieved == payload
            fail "RETR returned #{retrieved.bytesize} bytes, stored #{payload.bytesize}"
          end

          send_command(socket, "DELE #{path}")
          expect(socket, 250, "DELE")
          deleted = true
        ensure
          # Clean up whenever the delete above did not happen -- including when
          # STOR itself failed. A server creates the file when it accepts STOR
          # and only then moves the bytes, so a transfer that dies in between
          # (an unreachable passive port, a disk filling up) leaves the probe
          # behind. These accounts are chrooted into live document roots; a
          # monitoring check must not litter them.
          unless deleted
            begin
              send_command(socket, "DELE #{path}")
              read_reply(socket)
            rescue IO::Error | Failure
              # best effort -- the failure that matters is already being raised
            end
          end
        end
      end

      # Opens a passive data connection, issues *command* on the control
      # connection, yields the data socket, and waits for the transfer to be
      # confirmed.
      private def with_data_connection(socket, command, &)
        port = passive_port(socket)
        verb = command.partition(' ').first

        # Connect to the host we are already talking to rather than the address
        # the server advertises. Behind NAT -- or in a container -- PASV
        # routinely returns something unroutable: pure-ftpd in docker answers
        # with its bridge address even when PUBLICHOST is set.
        data = TCPSocket.new(@host, port, connect_timeout: @connect_timeout.seconds)
        data.read_timeout = @read_timeout.seconds
        data.sync = true

        data_io = nil

        begin
          send_command(socket, command)

          # 125 and 150 both mean "go ahead"; the handshake on a protected data
          # connection only happens once the server has agreed to the transfer.
          code, message = read_reply(socket)
          unless code == 150 || code == 125
            fail "#{verb}: #{message.lines.first?}"
          end

          data_io = tls? ? start_tls(data, verify_expiry: false) : data
          result = yield data_io

          # The server only reports the outcome once the data connection is
          # closed, so this cannot wait until the ensure block.
          close_data(data_io)
          data_io = nil
          expect(socket, 226, verb)

          result
        ensure
          close_data(data_io) if data_io
          data.close rescue nil
        end
      end

      # Asks for a passive port. EPSV (RFC 2428) is tried first because it
      # answers with a bare port number; PASV's six-number form encodes an
      # address that is routinely wrong, and is only used as a fallback for
      # servers too old to know EPSV.
      private def passive_port(socket)
        send_command(socket, "EPSV")
        code, message = read_reply(socket)

        if code == 229
          if match = message.match(/\((.)\1\1(\d+)\1\)/)
            return match[2].to_i
          end
          fail "EPSV: cannot parse #{message.lines.first?}"
        end

        send_command(socket, "PASV")
        message = expect(socket, 227, "PASV")

        unless match = message.match(/(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)/)
          fail "PASV: cannot parse #{message.lines.first?}"
        end

        match[5].to_i * 256 + match[6].to_i
      end

      private def close_data(data_io)
        data_io.close
      rescue IO::Error | OpenSSL::SSL::Error
        # the server may have closed first; the control connection has the
        # authoritative answer either way
      end

      private def tls?
        !@tls.none?
      end

      # *verify_expiry* is false for data connections: they present the same
      # certificate as the control connection, which has already been checked.
      private def start_tls(tcp_socket, verify_expiry = true)
        context = OpenSSL::SSL::Context::Client.new
        context.verify_mode = OpenSSL::SSL::VerifyMode::NONE unless @ssl_verify

        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: @host)
        ssl_socket.sync = true

        if verify_expiry && @ssl_min_days_valid
          @cert_expires_at = verify_not_after_expiry(@ssl_min_days_valid, ssl_socket)
        end

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
