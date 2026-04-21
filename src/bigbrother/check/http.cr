require "http/client"

require "../helper/ssl_cert_expiry"

module Bigbrother
  module Check
    class Http
      include Check
      include Helper::SSLCertExpiry

      @cert_expires_at : Time?

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
          type:    Regex | Array(Regex),
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
        },
        ssl_min_days_valid: {
          type: Int32,
          nilable: true,
          default: 7
        }

      def endpoint
        "#{http_method} #{@url}"
      end

      def label
        if @cert_expires_at
          "#{http_method} #{@url} cert_expires_at=#{@cert_expires_at}"
        else
          endpoint
        end
      end

      def check
        uri = URI.parse(@url)
        uri = URI.parse("http://#{@url}") unless uri.scheme

        @cert_expires_at = verify_not_after_expiry(uri) if uri.scheme == "https" && @ssl_min_days_valid
        match_http_body(uri)
      end

      private def verify_not_after_expiry(uri)
        hostname = uri.host || "unknown"
        port = uri.port || 443

        TCPSocket.open(hostname, port) do |tcp_socket|
          verify_not_after_expiry(@ssl_min_days_valid, tcp_socket, hostname)
        end
      end

      private def match_http_body(uri)
        HTTP::Client.new(uri) do |client|
          client.dns_timeout = @dns_timeout.not_nil!("dns_timeout missing").seconds
          client.connect_timeout = @connect_timeout.not_nil!("connect_timeout missing").seconds
          client.read_timeout = @read_timeout.not_nil!("read_timeout missing").seconds

          response = client.exec(
            method: http_method,
            path: uri.to_s,
            body: as_body(@body),
            headers: headers
          )

          unless @status_code == response.status_code
            fail "status_code=#{response.status_code}"
          end

          matcher = \
            if @match_body.is_a?(Array)
              @match_body.as(Array(Regex))
            elsif @match_body
              [@match_body.as(Regex)]
            else
              [] of Regex
            end

          matcher.each do |regex|
            fail "regex=#{regex}, match_body=#{response.body[0, 500]}" unless regex.match(response.body.to_s)
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
