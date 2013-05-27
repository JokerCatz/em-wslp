#encoding:utf-8
module EventMachine
  module Wslp
    module Close03
      def close_websocket(code , body)
        send_frame(:close, '')
        @state = :closing
      end
      def supports_close_codes? ; false ; end
    end
    module Close05
      def close_websocket(code , body)
        send_frame(:close, "\x53")
        @state = :closing
      end
      def supports_close_codes? ; false ; end
    end
    module Close06
      def close_websocket(code , body)
        if code
          close_data = [code].pack('n')
          close_data << body if body
          send_frame(:close, close_data)
        else
          send_frame(:close, '')
        end
        @state = :closing
      end
      def supports_close_codes? ; true ; end
    end
    module Close75
      def close_websocket(code, body)
        @connection.close_connection_after_writing
      end
      def supports_close_codes? ; false ; end
    end
  end
end
