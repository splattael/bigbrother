require "http/client"

module Bigbrother
  module Check
    class Http
      include Check

      config "http",
        url: String,
        match_body: {
          type:    Regex,
          nilable: true,
          default: /.*/,
        },
        status_code: {
          type:    Int32,
          nilable: true,
          default: 200,
        },
        dns_timeout: {
          type:    Int32,
          nilable: true,
          default: 10,
        },
        connect_timeout: {
          type:    Int32,
          nilable: true,
          default: 120,
        },
        read_timeout: {
          type:    Int32,
          nilable: true,
          default: 120,
        }

      def label
        @url
      end

      def check
        uri = URI.parse(@url)
        uri = URI.parse("http://#{@url}") unless uri.scheme

        HTTP::Client.new(uri) do |client|
          client.dns_timeout = @dns_timeout.not_nil!
          client.connect_timeout = @connect_timeout.not_nil!
          client.read_timeout = @read_timeout.not_nil!

          response = client.get(uri.full_path)

          unless @status_code == response.status_code
            fail "status_code=#{response.status_code}"
          end
          unless @match_body.not_nil!.match(response.body.to_s)
            fail "match_body=#{response.body[0, 500]}"
          end
        end
      end
    end
  end
end
