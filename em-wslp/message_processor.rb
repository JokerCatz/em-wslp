# encoding: BINARY

module EventMachine
  module Wslp
    module MessageProcessor03
      def message(message_type, extension_data, application_data)
        case message_type
        when :close
          @close_info = {
            :code => 1005,
            :reason => "",
            :was_clean => true,
          }
          if @state == :closing
            @connection.close_connection
          else
            send_frame(:close, application_data)
            @connection.close_connection_after_writing
          end
        when :ping
          send_frame(:pong, application_data)
          @connection.trigger_on_ping(application_data)
        when :pong
          @connection.trigger_on_pong(application_data)
        when :text
          if application_data.respond_to?(:force_encoding)
            application_data.force_encoding("UTF-8")
          end
          @connection.trigger_on_message(application_data)
        when :binary
          @connection.trigger_on_message(application_data)
        end
      end
      def pingable?
        true
      end
    end
    module MessageProcessor06
      def message(message_type, extension_data, application_data)
        case message_type
        when :close
          status_code = case application_data.length
          when 0
            nil
          when 1
            raise WSProtocolError, "Close frames with a body must contain a 2 byte status code"
          else
            application_data.slice!(0, 2).unpack('n').first
          end
          
          @close_info = {
            :code => status_code || 1005,
            :reason => application_data,
            :was_clean => true,
          }

          if @state == :closing
            @connection.close_connection
          elsif @state == :connected
            close_data = [status_code || 1000].pack('n')
            send_frame(:close, close_data)
            @connection.close_connection_after_writing
          end
        when :ping
          send_frame(:pong, application_data)
          @connection.trigger_on_ping(application_data)
        when :pong
          @connection.trigger_on_pong(application_data)
        when :text
          if application_data.respond_to?(:force_encoding)
            application_data.force_encoding("UTF-8")
            unless application_data.valid_encoding?
              raise InvalidDataError, "Invalid UTF8 data"
            end
          end
          @connection.trigger_on_message(application_data)
        when :binary
          @connection.trigger_on_message(application_data)
        end
      end
      def pingable?
        true
      end
    end
  end
end
