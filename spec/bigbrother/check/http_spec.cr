require "../../spec_helper"

module Bigbrother::Check
  describe Http do
    it "succeeds when the status code and body match" do
      with_http_server(body: "hello world") do |url|
        check = Http.from_yaml <<-YAML
          type: "http"
          url: "#{url}"
          match_body: "hello"
          YAML

        check.run.ok?.should be_true
      end
    end

    it "fails when the status code does not match" do
      with_http_server(status_code: 500) do |url|
        check = Http.from_yaml <<-YAML
          type: "http"
          url: "#{url}"
          YAML

        response = check.run
        response.error?.should be_true
        response.exception.to_s.should contain "status_code=500"
      end
    end

    it "fails when the body does not match" do
      with_http_server(body: "nothing useful here") do |url|
        check = Http.from_yaml <<-YAML
          type: "http"
          url: "#{url}"
          match_body: "not_present"
          YAML

        check.run.error?.should be_true
      end
    end

    it "scrubs invalid UTF-8 before matching the body" do
      invalid_utf8 = String.new(Bytes[0x68, 0x65, 0xFF, 0x6C, 0x6F]) # "he\xFFlo"

      with_http_server(body: invalid_utf8) do |url|
        check = Http.from_yaml <<-YAML
          type: "http"
          url: "#{url}"
          match_body: "he.?lo"
          YAML

        check.run.ok?.should be_true
      end
    end
  end
end
