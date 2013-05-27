#encoding:utf-8

require "http/parser"
require 'rack/utils'
require 'base64'

module EventMachine
  module Wslp
    class Handshake99
      include EM::Deferrable
      def initialize
        (@parser = Http::Parser.new).on_headers_complete = proc { |headers|
          @headers = Hash[headers.map { |k,v| [k.downcase, v] }]
        }
      end
      def headers
        @parser.headers
      end
      def headers_downcased
        @headers
      end
      def path
        @parser.request_path
      end
      def self.handshake(headers,path)
        return ''
      end
    end
    module Handshake04
      def self.handshake(headers, _)
        unless key = headers['sec-websocket-key']
          raise HandshakeError, "sec-websocket-key header is required"
        end
        return "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{Base64.encode64(Digest::SHA1.digest("#{key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11")).chomp}\r\n\r\n"
      end
    end
    module Handshake75
      def self.handshake(headers, path)
        return "HTTP/1.1 101 Web Socket Protocol Handshake\r\nUpgrade: WebSocket\r\nConnection: Upgrade\r\nWebSocket-Origin: #{headers['origin']}\r\nWebSocket-Location: ws://#{headers['host']}#{path}\r\n\r\n"
      end
    end
    module Handshake76
      class << self
        def handshake(headers, path)

          upgrade =  "HTTP/1.1 101 WebSocket Protocol Handshake\r\nUpgrade: WebSocket\r\nConnection: Upgrade\r\nSec-WebSocket-Location: ws://#{headers['host']}#{path}\r\nSec-WebSocket-Origin: #{headers['origin']}\r\n"
          if protocol = headers['sec-websocket-protocol']
            validate_protocol!(protocol)
            upgrade << "Sec-WebSocket-Protocol: #{protocol}\r\n"
          end
          
          return upgrade + "\r\n#{solve_challenge(headers['sec-websocket-key1'],headers['sec-websocket-key2'],headers['third-key'])}"
        end

        private

        def solve_challenge(first, second, third)
          Digest::MD5.digest([numbers_over_spaces(first)].pack("N*") + [numbers_over_spaces(second)].pack("N*") + third)
        end

        def numbers_over_spaces(string)
          numbers = string.scan(/[0-9]/).join.to_i

          spaces = string.scan(/ /).size
          raise HandshakeError, "Websocket Key1 or Key2 does not contain spaces - this is a symptom of a cross-protocol attack" if spaces == 0

          if numbers % spaces != 0
            raise HandshakeError, "Invalid Key #{string.inspect}"
          end

          quotient = numbers / spaces

          if quotient > 2**32-1
            raise HandshakeError, "Challenge computation out of range for key #{string.inspect}"
          end

          return quotient
        end

        def validate_protocol!(protocol)
          raise HandshakeError, "Invalid WebSocket-Protocol: empty" if protocol.empty?
        end
      end
    end

    #mask to support body query
    class Http::Parser
      attr_reader :body
    end
    
    class Handshake
      include EM::Deferrable

      attr_reader :parser, :protocol_version , :body

      def initialize
        (@parser = Http::Parser.new).on_headers_complete = proc { |headers , body|
          @headers = Hash[headers.map { |k,v| [k.downcase, v] }]
          
        }
        @parser.on_body = proc{ |chunk|
          @body = Rack::Utils.parse_nested_query(chunk)
        }
      end

      def receive_data(data)
        @parser << data
        if defined? @headers
          process(@headers, @parser.upgrade_data)
        end
      rescue HTTP::Parser::Error => e
        fail(HandshakeError.new("Invalid HTTP header: #{e.message}"))
      end
      def params
        return query.merge(body)
      end
      def body
        return @body || {}
      end
      def headers
        return @parser.headers
      end

      def headers_downcased
        return @headers
      end

      def path
        return @parser.request_path
      end

      def query_string
        return @parser.query_string
      end

      def query
        return Hash[query_string.split('&').map{|c| c.split('=',2) }]
      end

      def origin
        return @headers["origin"] || @headers["sec-websocket-origin"]
      end

      private

      def process(headers, remains)
        version = nil
        if @parser.upgrade? && @headers['upgrade'].kind_of?(String) && @headers['upgrade'].downcase == 'websocket'
          unless @parser.http_method == "GET"
            raise HandshakeError, "Must be GET request"
          end
          
          version = if @headers['sec-websocket-version']
            @headers['sec-websocket-version'].to_i
          elsif @headers['sec-websocket-draft']
            @headers['sec-websocket-draft'].to_i
          elsif @headers['sec-websocket-key1']
            76
          else
            75
          end
        else
          version = 99
        end
        case version
        when 75
          if !remains.empty?
            raise HandshakeError, "Extra bytes after header"
          end
        when 76, 1..3
          if remains.length < 8
            return nil
          elsif remains.length > 8
            raise HandshakeError, "Extra bytes after third key"
          end
          @headers['third-key'] = remains
        end
        handshake_klass = case version
        when 75
          Handshake75
        when 76, 1..3
          Handshake76
        when 5, 6, 7, 8, 13
          Handshake04
        when 99
          Handshake99
        else
          raise HandshakeError, "Protocol version #{version} not supported"
        end
        upgrade_response = handshake_klass.handshake(@headers, @parser.request_url)
        @protocol_version = version
        if version != 99
          succeed(upgrade_response , Handler.klass_factory(version))
        else
          succeed(upgrade_response)
        end
      rescue HandshakeError => e
        fail(e)
      end
    end
  end
end
