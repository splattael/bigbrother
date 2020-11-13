require "http/client"

module Bigbrother
  module Check
    class Http
      include Check

      enum Method
        GET
        POST
        PUT
        HEAD
        DELETE
        PATCH
      end

      config "http",
        url: String,
        method: {
          type:    Method,
          nilable: true,
          default: Method::GET,
        },
        body: {
          type:    String | Hash(String, String),
          nilable: true,
          default: nil,
        },
        headers: {
          type:    HTTP::Headers,
          default: HTTP::Headers.new,
        },
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

      def label : String
        "#{http_method} #{@url}"
      end

      def check
        uri = URI.parse(@url)
        uri = URI.parse("http://#{@url}") unless uri.scheme

        HTTP::Client.new(uri) do |client|
          client.dns_timeout = @dns_timeout.not_nil!
          client.connect_timeout = @connect_timeout.not_nil!
          client.read_timeout = @read_timeout.not_nil!

          response = client.exec(
            method: http_method,
            path: uri.full_path,
            body: as_body(@body),
            headers: headers
          )

          unless @status_code == response.status_code
            fail "status_code=#{response.status_code}"
          end
          unless @match_body.not_nil!.match(response.body.to_s)
            fail "match_body=#{response.body[0, 500]}"
          end
        end
      end

      private def headers
        headers = @headers.dup
        if headers.empty?
          headers["Content-Type"] = "application/x-www-form-urlencoded"
        end
        headers
      end

      private def as_body(body : String?)
        body
      end

      private def as_body(body : Hash(String, String))
        HTTP::Params.encode(@body.as(Hash(String, String)))
      end

      private def http_method
        @method.to_s
      end
    end
  end
end
