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
        }

      def label
        @url
      end

      def check
        response = HTTP::Client.get @url
        unless @status_code == response.status_code
          fail "status_code=#{response.status_code}"
        end
        unless @match_body.not_nil!.match(response.body.to_s)
          fail "match_body=#{response.body}"
        end
      end
    end
  end
end
