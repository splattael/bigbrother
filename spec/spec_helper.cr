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
