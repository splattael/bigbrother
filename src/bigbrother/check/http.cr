require "http/client"
require "openssl"

module Bigbrother
  module Check
    class Http
      include Check

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

      def label
        if @cert_expires_at
          "#{http_method} #{@url} cert_expires_at=#{@cert_expires_at}"
        else
          "#{http_method} #{@url}"
        end
      end

      def check
        uri = URI.parse(@url)
        uri = URI.parse("http://#{@url}") unless uri.scheme

        match_not_after_validity(uri) if uri.scheme == "https" && @ssl_min_days_valid
        match_http_body(uri)
      end

      private def match_not_after_validity(uri)
        hostname = uri.host || "unknown"
        port = uri.port || 443

        context = OpenSSL::SSL::Context::Client.new
        tcp_socket = TCPSocket.new(hostname, port)
        ssl_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, context, hostname: hostname)
        cert = ssl_socket.peer_certificate
        @cert_expires_at = cert.not_after

        if @cert_expires_at.not_nil! - Time::Span.new(days: @ssl_min_days_valid.not_nil!) < Time.utc
          fail "SSL certificate expires in < #{@ssl_min_days_valid} days"
        end
      end

      private def match_http_body(uri)
        HTTP::Client.new(uri) do |client|
          client.dns_timeout = @dns_timeout.not_nil!.seconds
          client.connect_timeout = @connect_timeout.not_nil!.seconds
          client.read_timeout = @read_timeout.not_nil!.seconds

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
