require "../../spec_helper"

module Bigbrother::Check
  describe Ftp do
    describe "without TLS" do
      it "succeeds on a 220 greeting" do
        with_ftp_server(["220 ProFTPD Server ready."]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            YAML

          check.run.ok?.should be_true
        end
      end

      it "reads a multi-line greeting up to its terminating line" do
        commands = [] of String
        greeting = "220-Welcome\n220-to the\n220 machine"

        with_ftp_server([greeting, "221 Goodbye."], commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            match_banner: "to the"
            YAML

          check.run.ok?.should be_true
          commands.should eq ["QUIT"]
        end
      end

      it "fails when the greeting is not 220" do
        with_ftp_server(["421 Service not available, closing connection."]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "greeting: 421"
        end
      end

      it "fails when the server hangs up before greeting" do
        server = TCPServer.new("127.0.0.1", 0)
        spawn { server.accept?.try(&.close) }

        check = Ftp.from_yaml <<-YAML
          type: "ftp"
          host: "127.0.0.1"
          port: #{server.local_address.port}
          tls: "none"
          YAML

        begin
          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "connection closed by server"
        ensure
          server.close
        end
      end

      it "fails when the greeting is not a reply at all" do
        with_ftp_server(["HTTP/1.1 400 Bad Request"]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "malformed reply"
        end
      end

      it "fails when the banner does not match" do
        with_ftp_server(["220 ProFTPD Server ready."]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            match_banner: "Pure-FTPd"
            YAML

          check.run.error?.should be_true
        end
      end
    end

    describe "login" do
      it "sends USER and PASS and succeeds on 230" do
        commands = [] of String
        script = [
          "220 ready",
          "331 User name okay, need password.",
          "230 User logged in, proceed.",
          "221 Goodbye.",
        ]

        with_ftp_server(script, commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "alice"
            password: "s3cret"
            YAML

          check.run.ok?.should be_true
          commands.should eq ["USER alice", "PASS s3cret", "QUIT"]
        end
      end

      it "skips PASS when USER already logs the user in" do
        commands = [] of String

        with_ftp_server(["220 ready", "230 User logged in.", "221 Goodbye."], commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "anonymous"
            password: "anonymous"
            YAML

          check.run.ok?.should be_true
          commands.should eq ["USER anonymous", "QUIT"]
        end
      end

      it "fails when the password is rejected" do
        script = [
          "220 ready",
          "331 User name okay, need password.",
          "530 Login authentication failed.",
        ]

        with_ftp_server(script) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "alice"
            password: "wrong"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "PASS: 530"
        end
      end

      it "does not leak the password into the failure message" do
        with_ftp_server(["220 ready", "331 need password", "530 nope"]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "alice"
            password: "hunter2"
            YAML

          check.run.exception.to_s.should_not contain "hunter2"
        end
      end

      it "fails when USER is rejected outright" do
        with_ftp_server(["220 ready", "530 Sorry, no anonymous."]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "alice"
            password: "s3cret"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "USER: 530"
        end
      end
    end

    describe "explicit TLS" do
      it "upgrades after AUTH TLS and logs in over the encrypted session" do
        with_self_signed_cert do |cert|
          commands = [] of String
          script = [
            "220 ready",
            "234 AUTH TLS successful.",
            "331 User name okay, need password.",
            "230 User logged in, proceed.",
            "221 Goodbye.",
          ]

          with_ftp_server(script, commands, tls_after: "AUTH TLS", tls_cert: cert) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              user: "alice"
              password: "s3cret"
              ssl_verify: false
              YAML

            check.run.ok?.should be_true
            commands.should eq ["AUTH TLS", "USER alice", "PASS s3cret", "QUIT"]
          end
        end
      end

      it "is the default TLS mode" do
        Ftp.from_yaml(<<-YAML).tls.should eq Ftp::Tls::Explicit
          type: "ftp"
          host: "example.com"
          YAML
      end

      it "fails when the server refuses AUTH TLS" do
        with_ftp_server(["220 ready", "500 AUTH not understood."]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "AUTH TLS: 500"
        end
      end

      it "fails when the server accepts AUTH TLS but never handshakes" do
        # 234 without switching to TLS: the failure mode of a server whose
        # certificate is missing. A plain `host_ip` check would stay green.
        with_ftp_server(["220 ready", "234 AUTH TLS successful.", "500 what"]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            read_timeout: 2
            ssl_verify: false
            YAML

          check.run.error?.should be_true
        end
      end

      it "fails when the certificate cannot be verified" do
        with_self_signed_cert do |cert|
          script = ["220 ready", "234 AUTH TLS successful.", "221 Goodbye."]

          with_ftp_server(script, tls_after: "AUTH TLS", tls_cert: cert) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              ssl_verify: true
              YAML

            check.run.error?.should be_true
          end
        end
      end

      it "fails when the certificate expires too soon" do
        with_self_signed_cert(not_after: Time.utc + 3.days) do |cert|
          script = ["220 ready", "234 AUTH TLS successful.", "221 Goodbye."]

          with_ftp_server(script, tls_after: "AUTH TLS", tls_cert: cert) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              ssl_verify: false
              ssl_min_days_valid: 7
              YAML

            response = check.run
            response.error?.should be_true
            response.exception.to_s.should contain "SSL certificate expires in < 7 days"
          end
        end
      end

      it "reports the expiry date in its label" do
        not_after = Time.utc + 30.days

        with_self_signed_cert(not_after: not_after) do |cert|
          script = ["220 ready", "234 AUTH TLS successful.", "221 Goodbye."]

          with_ftp_server(script, tls_after: "AUTH TLS", tls_cert: cert) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              ssl_verify: false
              YAML

            check.run.ok?.should be_true
            check.label.should contain "cert_expires_at=#{not_after.to_s("%Y-%m-%d")}"
          end
        end
      end
    end

    describe "implicit TLS" do
      it "handshakes before reading the greeting" do
        with_self_signed_cert do |cert|
          commands = [] of String
          script = ["220 ready", "221 Goodbye."]

          with_ftp_server(script, commands, implicit_tls: true, tls_cert: cert) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              tls: "implicit"
              ssl_verify: false
              YAML

            check.run.ok?.should be_true
            commands.should eq ["QUIT"]
          end
        end
      end

      it "fails against a server that speaks plain FTP" do
        with_ftp_server(["220 ready"]) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "implicit"
            read_timeout: 2
            ssl_verify: false
            YAML

          check.run.error?.should be_true
        end
      end
    end

    describe "#endpoint" do
      it "describes the scheme, user and address" do
        Ftp.from_yaml(<<-YAML).endpoint.should eq "ftps://alice@example.com:21"
          type: "ftp"
          host: "example.com"
          user: "alice"
          YAML

        Ftp.from_yaml(<<-YAML).endpoint.should eq "ftp://example.com:2121"
          type: "ftp"
          host: "example.com"
          port: 2121
          tls: "none"
          YAML
      end
    end

    describe "transfer_path" do
      it "uploads, reads back, compares and deletes" do
        files = {} of String => String
        commands = [] of String

        with_ftp_store_server(files, commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            user: "alice"
            password: "s3cret"
            transfer_path: "probe.txt"
            YAML

          check.run.ok?.should be_true

          files.should be_empty
          commands.should eq [
            "USER alice", "PASS s3cret", "TYPE I",
            "EPSV", "STOR probe.txt",
            "EPSV", "RETR probe.txt",
            "DELE probe.txt", "QUIT",
          ]
        end
      end

      it "leaves the rest of the directory alone" do
        files = {"keep.txt" => "not mine"}

        with_ftp_store_server(files) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          check.run.ok?.should be_true
          files.should eq({"keep.txt" => "not mine"})
        end
      end

      it "sends a unique payload so a stale file cannot fake a pass" do
        uploads = [] of String

        2.times do
          with_ftp_store_server(uploads: uploads) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              tls: "none"
              transfer_path: "probe.txt"
              YAML

            check.run.ok?.should be_true
          end
        end

        uploads.size.should eq 2
        uploads[0].should_not eq uploads[1]
      end

      it "honours transfer_content when given" do
        uploads = [] of String

        with_ftp_store_server(uploads: uploads) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            transfer_content: "exactly this"
            YAML

          check.run.ok?.should be_true
        end

        uploads.should eq ["exactly this"]
      end

      it "negotiates PBSZ and PROT before transferring over TLS" do
        with_self_signed_cert do |cert_path, key_path|
          commands = [] of String

          with_ftp_store_server(commands: commands, tls_cert: {cert_path, key_path}) do |host, port|
            check = Ftp.from_yaml <<-YAML
              type: "ftp"
              host: "#{host}"
              port: #{port}
              ssl_verify: false
              transfer_path: "probe.txt"
              YAML

            check.run.ok?.should be_true
            commands.should contain "PBSZ 0"
            commands.should contain "PROT P"
          end
        end
      end

      it "does not negotiate PBSZ and PROT without TLS" do
        commands = [] of String

        with_ftp_store_server(commands: commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          check.run.ok?.should be_true
          commands.should_not contain "PBSZ 0"
        end
      end

      it "falls back to PASV when the server does not know EPSV" do
        commands = [] of String

        with_ftp_store_server(commands: commands, epsv: false) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          check.run.ok?.should be_true
          commands.should contain "PASV"
        end
      end

      it "fails when the server refuses the upload" do
        with_ftp_store_server(reject: {"STOR" => "553 Can't open that file"}) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "STOR: 553"
        end
      end

      it "fails when the data connection cannot be reached" do
        # A firewalled passive port range: the control connection is healthy,
        # which is exactly what a plain port check would report.
        with_ftp_store_server(dead_passive_port: true) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          check.run.error?.should be_true
        end
      end

      it "fails when the bytes read back differ from the bytes written" do
        with_ftp_store_server(corrupt_retr: "something else entirely") do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "RETR returned"
        end
      end

      it "deletes the probe even when reading it back fails" do
        files = {} of String => String

        with_ftp_store_server(files, corrupt_retr: "wrong") do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          check.run.error?.should be_true
          files.should be_empty
        end
      end

      it "fails when the probe cannot be deleted" do
        with_ftp_store_server(reject: {"DELE" => "550 Permission denied"}) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            transfer_path: "probe.txt"
            YAML

          response = check.run
          response.error?.should be_true
          response.exception.to_s.should contain "DELE: 550"
        end
      end

      it "opens no data connection when transfer_path is unset" do
        commands = [] of String

        with_ftp_store_server(commands: commands) do |host, port|
          check = Ftp.from_yaml <<-YAML
            type: "ftp"
            host: "#{host}"
            port: #{port}
            tls: "none"
            YAML

          check.run.ok?.should be_true
          commands.should eq ["QUIT"]
        end
      end
    end

    it "defaults to port 21" do
      Ftp.from_yaml(<<-YAML).port.should eq 21
        type: "ftp"
        host: "example.com"
        YAML
    end
  end
end
