require "../../spec_helper"

module Bigbrother::Check
  describe HostIp do
    it "succeeds when the TCP connection can be established" do
      server = TCPServer.new("127.0.0.1", 0)
      begin
        spawn { server.accept? }

        check = HostIp.from_yaml <<-YAML
          type: "host_ip"
          host: "127.0.0.1"
          port: #{server.local_address.port}
          ssl_min_days_valid: null
          YAML

        check.run.ok?.should be_true
      ensure
        server.close
      end
    end

    it "fails when nothing is listening on the port" do
      server = TCPServer.new("127.0.0.1", 0)
      port = server.local_address.port
      server.close

      check = HostIp.from_yaml <<-YAML
        type: "host_ip"
        host: "127.0.0.1"
        port: #{port}
        ssl_min_days_valid: null
        YAML

      check.run.error?.should be_true
    end
  end
end
