#encoding:utf-8
require 'zlib'

module EventMachine
  module Wslp
    class Connection < EventMachine::Connection
      attr_reader :long_polling
      
      def onopen(&blk);     @onopen = blk;    end
      def onclose(&blk);    @onclose = blk;   end
      def onerror(&blk);    @onerror = blk;   end
      def onmessage(&blk);  @onmessage = blk; end
      def onping(&blk);     @onping = blk;    end
      def onpong(&blk);     @onpong = blk;    end

      def trigger_on_message(msg);     @onmessage.call(msg)    if defined? @onmessage; end
      def trigger_on_open(handshake);  @onopen.call(handshake) if defined? @onopen;    end
      def trigger_on_close(event = {});@onclose.call(event)    if defined? @onclose;   end
      def trigger_on_ping(data);       @onping.call(data)      if defined? @onping;    end
      def trigger_on_pong(data);       @onpong.call(data)      if defined? @onpong;    end
      def trigger_on_error(reason);    return false unless defined? @onerror;@onerror.call(reason);true; end
      
      def initialize(options)
      end

      def close(code = nil, body = nil)
        unless @long_polling
          if code && !(code == 1000 || (3000..4999).include?(code))
            raise "Application code may only use codes from 1000, 3000-4999"
          end
          close_websocket_private(code, body)
        else
          close_connection_after_writing
        end
      end

      def receive_data(data)
        if @handler
          @long_polling ? super(data) : @handler.receive_data(data)
        else
          @handshake ||= begin
            handshake = Handshake.new

            handshake.callback { |upgrade_response, handler_klass|
              if handler_klass
                self.send_data(upgrade_response)
                @handler = handler_klass.new(self)
                @long_polling = false
              else
                @long_polling = @handler = true
              end
              trigger_on_open(handshake)
              @handshake = nil
            }

            handshake.errback { |e|
              trigger_on_error(e)
              # Handshake errors require the connection to be aborted
              abort
            }

            handshake
          end
          @long_polling ? super(data) : @handshake.receive_data(data)
        end
      rescue WSProtocolError => e
        trigger_on_error(e)
        close_websocket_private(e.code, e.message)
      rescue => e
        close_websocket_private(3000, "Application error")
        trigger_on_error(e) || raise(e)
      end

      def unbind
        unless @long_polling
          @handler.unbind if @handler
        else
          trigger_on_close()
          super
        end
      rescue => e
        trigger_on_error(e) || raise(e)
      end

      UTF8 = Encoding.find("UTF-8")
      BINARY = Encoding.find("BINARY")
      
      def send_close(data)
        send_text(data)
        close_connection_after_writing
      end
      
      def send_raw(data , long_polling_data)
        if @handler
          if @long_polling
            send_data packaged_data
            close_connection_after_writing
          else
            #unless (data.encoding == UTF8 && data.valid_encoding?) || data.ascii_only?
            #  raise WebSocketError, "Data sent to WebSocket must be valid UTF-8 but was #{data.encoding} (valid: #{data.valid_encoding?})"
            #end
            data.force_encoding(BINARY)
            @handler.send_text_frame(data)
            data.force_encoding(UTF8)
          end
        else
          raise WebSocketError, "Cannot send data before onopen callback"
        end
        return nil
      end
      
      def send_empty
        if @long_polling
          send_data "HTTP/1.1 200 OK\r\n"
        end
      end
      
      def send_text(data)
        if @handler
          if @long_polling
            data = StringIO.new.tap do |io|
              gz = Zlib::GzipWriter.new(io)
              begin
                gz.write(data)
              ensure
                gz.close
              end
            end.string
            
            ans =  "HTTP/1.1 200 OK\r\n"
            ans << "Content-Encoding: gzip\r\n"
            ans << "Content-Type: text/plain\r\n"
            #for HTTP(CORS)fix
            ans << "Access-Control-Allow-Origin: *\r\n"
            ans << "Access-Control-Allow-Methods: *\r\n"
            ans << "X-Frame-Options: DENY\r\n"
            ans << "Cache-Control: private, no-store, no-cache, must-revalidate, post-check=0, pre-check=0\r\n"
            ans << "Pragma: no-cache\r\n"
            ans << "Connection: keep-alive\r\n"
            ans << "Content-Length: #{data.bytesize}\r\n"
            ans << "\r\n#{data}"
            send_data ans
            
            close_connection_after_writing
          else
            data.force_encoding(BINARY)
            @handler.send_text_frame(data)
            data.force_encoding(UTF8)
          end
        else
          raise WebSocketError, "Cannot send data before onopen callback"
        end
        
        
        return nil
      end

      alias :send :send_text
      
      def send_binary(data)
        if @handler
          @long_polling ? super(data) : @handler.send_frame(:binary, data)
        else
          raise WebSocketError, "Cannot send binary before onopen callback"
        end
      end
      
      #addon
      def send_not_found
        send_data "HTTP/1.1 400 Bad request\r\nConnection: close\r\nContent-type: text/plain\r\n\r\nDetected error: HTTP code 400"
        close_connection_after_writing
      end
      def send_error
        send_data "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-type: text/plain\r\n\r\nDetected error: HTTP code 500"
        close_connection_after_writing
      end
      
      def ping(body = '')
        return true if @long_polling
        if @handler
          @handler.pingable? ? @handler.send_frame(:ping, body) && true : false
        else
          raise WebSocketError, "Cannot ping before onopen callback"
        end
      end
      
      def pong(body = '')
        return true if @long_polling
        if @handler
          @handler.pingable? ? @handler.send_frame(:pong, body) && true : false
        else
          raise WebSocketError, "Cannot ping before onopen callback"
        end
      end

      def pingable?
        return false if @long_polling
        if @handler
          @handler.pingable?
        else
          raise WebSocketError, "Cannot test whether pingable before onopen callback"
        end
      end

      def supports_close_codes?
        return false if @long_polling
        if @handler
          @handler.supports_close_codes?
        else
          raise WebSocketError, "Cannot test before onopen callback"
        end
      end

      def state
        return false if @long_polling
        @handler ? @handler.state : :handshake
      end

      private

      def abort
        close_connection
      end

      def close_websocket_private(code, body)
        return true if @long_polling
        if @handler
          @handler.close_websocket(code, body)
        else
          abort
        end
      end
    end
  end
end