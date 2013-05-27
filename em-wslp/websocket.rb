#encoding:utf-8
module EventMachine
  module Wslp
    MAX_FRAMS_SIZE = 10 * 1024 * 1024 # 10MB
    
    class WebSocketError < RuntimeError; end
    class HandshakeError < WebSocketError; end
    class WSProtocolError < WebSocketError
      def code; 1002; end
    end
    class InvalidDataError < WSProtocolError
      def code; 1007; end
    end
    class WSMessageTooBigError < WSProtocolError
      def code; 1009; end
    end
    
    def self.start(options, &blk)
      EM.epoll
      EM.run {
        trap("TERM"){ stop }
        trap("INT" ){ stop }
        run(options, &blk)
      }
    end

    def self.run(options)
      host, port = options.values_at(:host, :port)
      EM.start_server(host, port, Connection, options) do |c|
        yield c
      end
    end

    def self.stop
      EM.stop
    end
  end
end
