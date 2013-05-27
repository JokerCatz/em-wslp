#encoding:utf-8
module EventMachine
  module Wslp

    class Handler
      def self.klass_factory(version)
        case version
        when 75
          Handler75
        when 76
          Handler76
        when 1..3
          Handler03
        when 5
          Handler05
        when 6
          Handler06
        when 7
          Handler07
        when 8
          Handler08
        when 13
          Handler13
        else
          raise HandshakeError, "Protocol version #{version} not supported"
        end
      end
      attr_reader :request, :state
      def initialize(connection)
        @connection = connection
        @state = :connected
        initialize_framing
      end
      def receive_data(data)
        @data << data
        process_data(data)
      end
      def close_websocket(code, body)
      end
      def unbind
        @state = :closed
        @close_info = defined?(@close_info) ? @close_info : {
          :code => 1006,
          :was_clean => false,
        }
        @connection.trigger_on_close(@close_info )
      end
      def ping
        false
      end
      def pingable?
        false
      end
    end
    class Handler03 < Handler
      include Framing03
      include MessageProcessor03
      include Close03
    end
    class Handler05 < Handler
      include Framing05
      include MessageProcessor03
      include Close05
    end
    class Handler06 < Handler
      include Framing05
      include MessageProcessor06
      include Close06
    end
    class Handler07 < Handler
      include Framing07
      include MessageProcessor06
      include Close06
    end
    class Handler08 < Handler
      include Framing07
      include MessageProcessor06
      include Close06
    end
    class Handler13 < Handler
      include Framing07
      include MessageProcessor06
      include Close06
    end
    class Handler75 < Handler
      include Handshake75
      include Framing76
      include Close75
    end
    class Handler76 < Handler
      include Handshake76
      include Framing76
      include Close75
      TERMINATE_STRING = "\xff\x00"
    end
  end
end
