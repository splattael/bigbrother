require "../../spec_helper"

# Exercised through `Check::HostIp`, the simplest includer of
# `Helper::SSLCertExpiry`, against a real local TLS server with a
# purpose-generated certificate.
module Bigbrother::Check
  describe Bigbrother::Helper::SSLCertExpiry do
    it "succeeds when the certificate is valid beyond the threshold" do
      with_trusted_tls_server(not_after: Time.utc + 8.days) do |host, port|
        check = HostIp.from_yaml <<-YAML
          type: "host_ip"
          host: "#{host}"
          port: #{port}
          ssl_min_days_valid: 7
          YAML

        response = check.run
        response.ok?.should be_true
        response.label.should contain "cert_expires_at="
      end
    end

    it "fails when the certificate expires within ssl_min_days_valid" do
      with_trusted_tls_server(not_after: Time.utc + 6.days) do |host, port|
        check = HostIp.from_yaml <<-YAML
          type: "host_ip"
          host: "#{host}"
          port: #{port}
          ssl_min_days_valid: 7
          YAML

        response = check.run
        response.error?.should be_true
        response.exception.to_s.should contain "SSL certificate expires in < 7 days"
      end
    end

    it "fails when the certificate has already expired" do
      with_trusted_tls_server(not_before: Time.utc, not_after: Time.utc - 1.day) do |host, port|
        check = HostIp.from_yaml <<-YAML
          type: "host_ip"
          host: "#{host}"
          port: #{port}
          ssl_min_days_valid: 7
          YAML

        check.run.error?.should be_true
      end
    end
  end
end
