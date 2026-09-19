require "spec"
require "http/server"
require "openssl"
require "process"

require "../src/ext"
require "../src/bigbrother/**"

# Starts an `HTTP::Server` on an unused local port, yields its base URL to the
# block, and closes the server afterwards. Used to exercise `Check::Http`
# against a real HTTP response instead of stubbing `HTTP::Client`.
def with_http_server(status_code = 200, body = "OK", &)
  server = HTTP::Server.new do |context|
    context.response.status_code = status_code
    context.response.print body
  end

  address = server.bind_unused_port("127.0.0.1")
  spawn { server.listen }
  Fiber.yield

  begin
    yield "http://#{address}"
  ensure
    server.close
  end
end

# Generates a temporary self-signed certificate (with a `127.0.0.1` IP SAN)
# with exact `notBefore`/`notAfter` timestamps, serves it via TLS on an
# unused local port, trusts it as OpenSSL's default CA for the duration of
# the block, and yields the host and port. Cleans up the certificate, trust
# override, and server afterwards.
#
# Uses `openssl ca -selfsign -startdate/-enddate`, supported since ancient
# OpenSSL releases, rather than `req -x509 -not_after` (unsupported by the
# OpenSSL shipped in some CI images) or a negative `-days` (rejected outright
# by some OpenSSL versions when backdating an already-expired certificate).
def with_trusted_tls_server(not_after : Time, not_before : Time = Time.utc - 1.day, &)
  dir = File.tempname("bigbrother-spec-ca", "")
  Dir.mkdir(dir)

  key_path = File.join(dir, "key.pem")
  csr_path = File.join(dir, "csr.pem")
  cert_path = File.join(dir, "cert.pem")
  config_path = File.join(dir, "openssl.cnf")

  begin
    File.write(File.join(dir, "index.txt"), "")
    File.write(File.join(dir, "serial"), "1000\n")
    File.write(config_path, <<-CONF)
      [ca]
      default_ca = CA_default

      [CA_default]
      dir = #{dir}
      database = #{dir}/index.txt
      new_certs_dir = #{dir}
      serial = #{dir}/serial
      default_md = sha256
      policy = policy_anything
      email_in_dn = no
      unique_subject = no

      [policy_anything]
      commonName = optional

      [v3_ext]
      subjectAltName = IP:127.0.0.1
      CONF

    csr_status = Process.run("openssl", [
      "req", "-new", "-newkey", "rsa:2048", "-nodes",
      "-keyout", key_path, "-out", csr_path,
      "-subj", "/CN=127.0.0.1",
    ])
    raise "openssl req -new failed" unless csr_status.success?

    timestamp_format = "%Y%m%d%H%M%SZ"
    ca_status = Process.run("openssl", [
      "ca", "-config", config_path, "-selfsign", "-batch",
      "-keyfile", key_path, "-in", csr_path, "-out", cert_path,
      "-extensions", "v3_ext",
      "-startdate", not_before.to_utc.to_s(timestamp_format),
      "-enddate", not_after.to_utc.to_s(timestamp_format),
    ])
    raise "openssl ca -selfsign failed" unless ca_status.success?

    server = TCPServer.new("127.0.0.1", 0)
    context = OpenSSL::SSL::Context::Server.new
    context.certificate_chain = cert_path
    context.private_key = key_path

    spawn do
      if io = server.accept?
        begin
          OpenSSL::SSL::Socket::Server.open(io, context) { }
        rescue
          # the client may abort the handshake (e.g. an expired certificate);
          # that path is asserted from the client side, nothing to do here
        end
      end
    end

    previous_ca_file = ENV["SSL_CERT_FILE"]?
    ENV["SSL_CERT_FILE"] = cert_path

    begin
      yield server.local_address.address, server.local_address.port
    ensure
      server.close
      previous_ca_file ? (ENV["SSL_CERT_FILE"] = previous_ca_file) : ENV.delete("SSL_CERT_FILE")
    end
  ensure
    Process.run("rm", ["-rf", dir])
  end
end

# Serves a canned FTP dialogue on an unused local port and yields host and
# port. *script* is a list of replies: the first is sent unprompted as the
# greeting, every later one is sent after a command has been read. The command
# a reply answers is recorded in *commands*, so specs can assert on what the
# check actually sent. A reply may span several lines (for RFC 959
# continuations); each line is sent CRLF terminated.
#
# When *tls_after* is given (e.g. `"AUTH TLS"`), the connection is upgraded to
# TLS with *tls_cert* right after that command has been answered, which is how
# RFC 4217 explicit FTPS works. With *implicit_tls*, the handshake happens
# before the greeting instead.
def with_ftp_server(
  script : Array(String),
  commands : Array(String) = [] of String,
  tls_after : String? = nil,
  implicit_tls : Bool = false,
  tls_cert : {String, String}? = nil,
  &
)
  server = TCPServer.new("127.0.0.1", 0)

  spawn do
    next unless client = server.accept?

    begin
      io = client.as(IO)

      if implicit_tls && (cert = tls_cert)
        io = upgrade_ftp_spec_socket(client, cert)
      end

      replies = script.dup

      if greeting = replies.shift?
        send_ftp_spec_reply(io, greeting)
      end

      while command = io.gets(chomp: true)
        commands << command

        reply = replies.shift?
        break unless reply

        send_ftp_spec_reply(io, reply)

        if tls_after && command == tls_after && (cert = tls_cert)
          io = upgrade_ftp_spec_socket(client, cert)
        end
      end
    rescue
      # the client may hang up mid-dialogue; every assertion is client side
    ensure
      client.close rescue nil
    end
  end

  begin
    yield server.local_address.address, server.local_address.port
  ensure
    server.close
  end
end

private def send_ftp_spec_reply(io, reply)
  reply.each_line { |line| io.print("#{line}\r\n") }
  io.flush
end

private def upgrade_ftp_spec_socket(client, cert)
  cert_path, key_path = cert
  context = OpenSSL::SSL::Context::Server.new
  context.certificate_chain = cert_path
  context.private_key = key_path
  socket = OpenSSL::SSL::Socket::Server.new(client, context, sync_close: false)
  # Unlike a TCPSocket an SSL socket buffers, and this server announces a
  # transfer and then blocks accepting the data connection -- the client would
  # never see the announcement.
  socket.sync = true
  socket
end

# Generates a self-signed certificate valid for *not_before*..*not_after* with
# a `127.0.0.1` IP SAN and yields its certificate and key paths. Unlike
# `with_trusted_tls_server` it starts no server and installs no trust
# override -- callers serve it themselves and decide whether to verify it.
def with_self_signed_cert(
  not_after : Time = Time.utc + 365.days,
  not_before : Time = Time.utc - 1.day,
  &
)
  dir = File.tempname("bigbrother-spec-cert", "")
  Dir.mkdir(dir)

  key_path = File.join(dir, "key.pem")
  csr_path = File.join(dir, "csr.pem")
  cert_path = File.join(dir, "cert.pem")
  config_path = File.join(dir, "openssl.cnf")

  begin
    File.write(File.join(dir, "index.txt"), "")
    File.write(File.join(dir, "serial"), "1000\n")
    File.write(config_path, <<-CONF)
      [ca]
      default_ca = CA_default

      [CA_default]
      dir = #{dir}
      database = #{dir}/index.txt
      new_certs_dir = #{dir}
      serial = #{dir}/serial
      default_md = sha256
      policy = policy_anything
      email_in_dn = no
      unique_subject = no

      [policy_anything]
      commonName = optional

      [v3_ext]
      subjectAltName = IP:127.0.0.1
      CONF

    csr_status = Process.run("openssl", [
      "req", "-new", "-newkey", "rsa:2048", "-nodes",
      "-keyout", key_path, "-out", csr_path,
      "-subj", "/CN=127.0.0.1",
    ])
    raise "openssl req -new failed" unless csr_status.success?

    timestamp_format = "%Y%m%d%H%M%SZ"
    ca_status = Process.run("openssl", [
      "ca", "-config", config_path, "-selfsign", "-batch",
      "-keyfile", key_path, "-in", csr_path, "-out", cert_path,
      "-extensions", "v3_ext",
      "-startdate", not_before.to_utc.to_s(timestamp_format),
      "-enddate", not_after.to_utc.to_s(timestamp_format),
    ])
    raise "openssl ca -selfsign failed" unless ca_status.success?

    yield({cert_path, key_path})
  ensure
    Process.run("rm", ["-rf", dir])
  end
end

# A minimal but real FTP server: it opens passive data connections and keeps
# an in-memory file map, so `transfer_path` can be exercised end to end
# without docker. Only the verbs `Check::Ftp` uses are implemented.
#
# *files* is both the initial content and the assertion target -- after a
# successful round trip it must be back to what it started as. *reject* maps a
# verb to the reply to send instead of doing the work ("STOR" => "553 nope").
# *corrupt_retr* serves different bytes than were stored, *epsv* disables EPSV
# to exercise the PASV fallback, and *dead_passive_port* advertises a port
# nothing listens on.
def with_ftp_store_server(
  files : Hash(String, String) = {} of String => String,
  commands : Array(String) = [] of String,
  uploads : Array(String) = [] of String,
  tls_cert : {String, String}? = nil,
  epsv : Bool = true,
  reject : Hash(String, String) = {} of String => String,
  corrupt_retr : String? = nil,
  dead_passive_port : Bool = false,
  &
)
  server = TCPServer.new("127.0.0.1", 0)

  spawn do
    next unless client = server.accept?

    io = client.as(IO)
    listener : TCPServer? = nil
    prot_p = false

    begin
      io.print("220 spec server ready\r\n")

      while line = io.gets(chomp: true)
        commands << line
        verb, _, argument = line.partition(' ')
        verb = verb.upcase

        if replacement = reject[verb]?
          io.print("#{replacement}\r\n")
          next
        end

        case verb
        when "AUTH"
          if cert = tls_cert
            io.print("234 AUTH TLS successful.\r\n")
            io = upgrade_ftp_spec_socket(client, cert)
          else
            io.print("500 AUTH not understood.\r\n")
          end
        when "USER" then io.print("331 need password\r\n")
        when "PASS" then io.print("230 logged in\r\n")
        when "PBSZ" then io.print("200 PBSZ=0\r\n")
        when "PROT"
          prot_p = argument.upcase == "P"
          io.print("200 protection level set\r\n")
        when "TYPE" then io.print("200 type set\r\n")
        when "EPSV", "PASV"
          if verb == "EPSV" && !epsv
            io.print("500 EPSV not understood.\r\n")
            next
          end

          listener.try(&.close)
          listener = TCPServer.new("127.0.0.1", 0)
          port = listener.not_nil!.local_address.port

          if dead_passive_port
            # Advertise a port that has just stopped listening.
            listener.not_nil!.close
            listener = nil
          end

          if verb == "EPSV"
            io.print("229 Entering Extended Passive Mode (|||#{port}|)\r\n")
          else
            io.print("227 Entering Passive Mode (127,0,0,1,#{port // 256},#{port % 256})\r\n")
          end
        when "STOR"
          io.print("150 ok to send\r\n")
          if data = accept_ftp_spec_data(listener, prot_p, tls_cert)
            content = data.gets_to_end
            files[argument] = content
            uploads << content
            data.close rescue nil
          end
          listener.try(&.close)
          listener = nil
          io.print("226 transfer complete\r\n")
        when "RETR"
          unless content = files[argument]?
            io.print("550 no such file\r\n")
            next
          end
          io.print("150 opening data connection\r\n")
          if data = accept_ftp_spec_data(listener, prot_p, tls_cert)
            data.print(corrupt_retr || content)
            data.flush
            data.close rescue nil
          end
          listener.try(&.close)
          listener = nil
          io.print("226 transfer complete\r\n")
        when "DELE"
          if files.delete(argument)
            io.print("250 deleted\r\n")
          else
            io.print("550 no such file\r\n")
          end
        when "QUIT"
          io.print("221 bye\r\n")
          break
        else
          io.print("500 unknown\r\n")
        end

        io.flush
      end
    rescue
      # the client may hang up mid-dialogue; every assertion is client side
    ensure
      listener.try(&.close)
      client.close rescue nil
    end
  end

  begin
    yield server.local_address.address, server.local_address.port
  ensure
    server.close
  end
end

private def accept_ftp_spec_data(listener, prot_p, tls_cert)
  return nil unless listener
  return nil unless socket = listener.accept?

  if prot_p && (cert = tls_cert)
    upgrade_ftp_spec_socket(socket, cert)
  else
    socket
  end
end
