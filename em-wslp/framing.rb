# encoding: BINARY

module EventMachine
  module Wslp
    module Framing03
      def initialize_framing
        @data = ''
        @application_data_buffer = '' # Used for MORE frames
        @frame_type = nil
      end
      def process_data(newdata)
        error = false
        while !error && @data.size > 1
          pointer = 0
          more = ((@data.getbyte(pointer) & 0b10000000) == 0b10000000) ^ fin
          opcode = @data.getbyte(0) & 0b00001111
          pointer += 1
          length = @data.getbyte(pointer) & 0b01111111
          pointer += 1
          payload_length = case length
          when 127
            if @data.getbyte(pointer+8-1) == nil
              error = true
              next
            end
            l = @data[(pointer+4)..(pointer+7)].unpack('N').first
            pointer += 8
            l
          when 126
            if @data.getbyte(pointer+2-1) == nil
              error = true
              next
            end
            l = @data[pointer..(pointer+1)].unpack('n').first
            pointer += 2
            l
          else
            length
          end
          if payload_length > Wslp::MAX_FRAMS_SIZE
            raise WSMessageTooBigError, "Frame length too long (#{payload_length} bytes)"
          end
          if @data.getbyte(pointer+payload_length-1) == nil
            error = true
            next
          end
          @data.slice!(0...pointer)
          application_data = @data.slice!(0...payload_length)
          frame_type = opcode_to_type(opcode)
          if frame_type == :continuation && !@frame_type
            raise WSProtocolError, 'Continuation frame not expected'
          end
          if more
            @application_data_buffer << application_data
            @frame_type ||= frame_type
          else
            if frame_type == :continuation
              @application_data_buffer << application_data
              message(@frame_type, '', @application_data_buffer)
              @application_data_buffer = ''
              @frame_type = nil
            else
              message(frame_type, '', application_data)
            end
          end
        end
      end
      
      def send_frame(frame_type, application_data)
        if @state == :closing && data_frame?(frame_type)
          raise WebSocketError, "Cannot send data frame since connection is closing"
        end
        frame = ''
        opcode = type_to_opcode(frame_type)
        byte1 = opcode
        frame << byte1
        length = application_data.size
        if length <= 125
          byte2 = length
          frame << byte2
        elsif length < 65536
          frame << 126
          frame << [length].pack('n')
        else
          frame << 127
          frame << [length >> 32, length & 0xFFFFFFFF].pack("NN")
        end
        frame << application_data
        @connection.send_data(frame)
      end
      def send_text_frame(data)
        send_frame(:text, data)
      end
      private
      def fin; false; end
      FRAME_TYPES = {
        :continuation => 0,
        :close => 1,
        :ping => 2,
        :pong => 3,
        :text => 4,
        :binary => 5
      }
      FRAME_TYPES_INVERSE = FRAME_TYPES.invert
      # Frames are either data frames or control frames
      DATA_FRAMES = [:text, :binary, :continuation]

      def type_to_opcode(frame_type)
        FRAME_TYPES[frame_type] || raise("Unknown frame type")
      end

      def opcode_to_type(opcode)
        FRAME_TYPES_INVERSE[opcode] || raise(WSProtocolError, "Unknown opcode #{opcode}")
      end

      def data_frame?(type)
        DATA_FRAMES.include?(type)
      end
    end
    module Framing04
      include Framing03
      private
      def fin; true; end
    end
    module Framing05
      def initialize_framing
        @data = MaskedString.new
        @application_data_buffer = '' # Used for MORE frames
        @frame_type = nil
      end
      def process_data(newdata)
        error = false
        while !error && @data.size > 5 # mask plus first byte present
          pointer = 0
          @data.read_mask
          pointer += 4
          fin = (@data.getbyte(pointer) & 0b10000000) == 0b10000000
          opcode = @data.getbyte(pointer) & 0b00001111
          pointer += 1
          length = @data.getbyte(pointer) & 0b01111111
          pointer += 1
          payload_length = case length
          when 127
            if @data.getbyte(pointer+8-1) == nil
              error = true
              next
            end
            l = @data.getbytes(pointer+4, 4).unpack('N').first
            pointer += 8
            l
          when 126
            if @data.getbyte(pointer+2-1) == nil
              error = true
              next
            end
            l = @data.getbytes(pointer, 2).unpack('n').first
            pointer += 2
            l
          else
            length
          end
          if payload_length > Wslp::MAX_FRAMS_SIZE
            raise WSMessageTooBigError, "Frame length too long (#{payload_length} bytes)"
          end
          if @data.getbyte(pointer+payload_length-1) == nil
            error = true
            next
          end
          application_data = @data.getbytes(pointer, payload_length)
          pointer += payload_length
          @data.unset_mask
          @data.slice!(0...pointer)
          frame_type = opcode_to_type(opcode)
          if frame_type == :continuation && !@frame_type
            raise WSProtocolError, 'Continuation frame not expected'
          end
          if !fin
            @application_data_buffer << application_data
            @frame_type = frame_type
          else
            if frame_type == :continuation
              @application_data_buffer << application_data
              message(@frame_type, '', @application_data_buffer)
              @application_data_buffer = ''
              @frame_type = nil
            else
              message(frame_type, '', application_data)
            end
          end
        end
      end
      def send_frame(frame_type, application_data)
        if @state == :closing && data_frame?(frame_type)
          raise WebSocketError, "Cannot send data frame since connection is closing"
        end
        frame = ''
        opcode = type_to_opcode(frame_type)
        byte1 = opcode | 0b10000000 # fin bit set, rsv1-3 are 0
        frame << byte1
        length = application_data.size
        if length <= 125
          byte2 = length
          frame << byte2
        elsif length < 65536
          frame << 126
          frame << [length].pack('n')
        else
          frame << 127
          frame << [length >> 32, length & 0xFFFFFFFF].pack("NN")
        end
        frame << application_data
        @connection.send_data(frame)
      end
      def send_text_frame(data)
        send_frame(:text, data)
      end
      private
      FRAME_TYPES = {
        :continuation => 0,
        :close => 1,
        :ping => 2,
        :pong => 3,
        :text => 4,
        :binary => 5
      }
      FRAME_TYPES_INVERSE = FRAME_TYPES.invert
      DATA_FRAMES = [:text, :binary, :continuation]
      def type_to_opcode(frame_type)
        FRAME_TYPES[frame_type] || raise("Unknown frame type")
      end
      def opcode_to_type(opcode)
        FRAME_TYPES_INVERSE[opcode] || raise(WSProtocolError, "Unknown opcode #{opcode}")
      end
      def data_frame?(type)
        DATA_FRAMES.include?(type)
      end
    end
    module Framing07
      def initialize_framing
        @data = MaskedString.new
        @application_data_buffer = ''
        @frame_type = nil
      end
      def process_data(newdata)
        error = false
        while !error && @data.size >= 2
          pointer = 0
          fin = (@data.getbyte(pointer) & 0b10000000) == 0b10000000
          opcode = @data.getbyte(pointer) & 0b00001111
          pointer += 1
          mask = (@data.getbyte(pointer) & 0b10000000) == 0b10000000
          length = @data.getbyte(pointer) & 0b01111111
          pointer += 1
          payload_length = case length
          when 127
            if @data.getbyte(pointer+8-1) == nil
              error = true
              next
            end
            l = @data.getbytes(pointer+4, 4).unpack('N').first
            pointer += 8
            l
          when 126
            if @data.getbyte(pointer+2-1) == nil
              error = true
              next
            end
            l = @data.getbytes(pointer, 2).unpack('n').first
            pointer += 2
            l
          else
            length
          end
          frame_length = pointer + payload_length
          frame_length += 4 if mask
          if frame_length > Wslp::MAX_FRAMS_SIZE
            raise WSMessageTooBigError, "Frame length too long (#{frame_length} bytes)"
          end
          if @data.getbyte(frame_length - 1) == nil
            error = true
            next
          end
          @data.slice!(0...pointer)
          pointer = 0
          @data.read_mask if mask
          pointer += 4 if mask
          application_data = @data.getbytes(pointer, payload_length)
          pointer += payload_length
          @data.unset_mask if mask
          @data.slice!(0...pointer)
          frame_type = opcode_to_type(opcode)
          if frame_type == :continuation && !@frame_type
            raise WSProtocolError, 'Continuation frame not expected'
          end
          if !fin
            @application_data_buffer << application_data
            @frame_type ||= frame_type
          else
            if frame_type == :continuation
              @application_data_buffer << application_data
              message(@frame_type, '', @application_data_buffer)
              @application_data_buffer = ''
              @frame_type = nil
            else
              message(frame_type, '', application_data)
            end
          end
        end
      end
      def send_frame(frame_type, application_data)
        if @state == :closing && data_frame?(frame_type)
          raise WebSocketError, "Cannot send data frame since connection is closing"
        end
        frame = ''
        opcode = type_to_opcode(frame_type)
        byte1 = opcode | 0b10000000
        frame << byte1
        length = application_data.size
        if length <= 125
          byte2 = length
          frame << byte2
        elsif length < 65536
          frame << 126
          frame << [length].pack('n')
        else
          frame << 127
          frame << [length >> 32, length & 0xFFFFFFFF].pack("NN")
        end
        frame << application_data
        @connection.send_data(frame)
      end
      def send_text_frame(data)
        send_frame(:text, data)
      end
      private
      FRAME_TYPES = {
        :continuation => 0,
        :text => 1,
        :binary => 2,
        :close => 8,
        :ping => 9,
        :pong => 10,
      }
      FRAME_TYPES_INVERSE = FRAME_TYPES.invert
      DATA_FRAMES = [:text, :binary, :continuation]
      def type_to_opcode(frame_type)
        FRAME_TYPES[frame_type] || raise("Unknown frame type")
      end
      def opcode_to_type(opcode)
        FRAME_TYPES_INVERSE[opcode] || raise(WSProtocolError, "Unknown opcode #{opcode}")
      end
      def data_frame?(type)
        DATA_FRAMES.include?(type)
      end
    end
    module Framing76
      def initialize_framing
        @data = ''
      end
      def process_data(newdata)
        error = false
        while !error
          return if @data.size == 0
          pointer = 0
          frame_type = @data.getbyte(pointer)
          pointer += 1
          if (frame_type & 0x80) == 0x80
            length = 0
            loop do
              return false if !@data.getbyte(pointer)
              b = @data.getbyte(pointer)
              pointer += 1
              b_v = b & 0x7F
              length = length * 128 + b_v
              break unless (b & 0x80) == 0x80
            end
            if length > Wslp::MAX_FRAMS_SIZE
              raise WSMessageTooBigError, "Frame length too long (#{length} bytes)"
            end
            if @data.getbyte(pointer+length-1) == nil
              error = true
            else
              @data = @data[(pointer+length)..-1]
              if length == 0
                @connection.send_data("\xff\x00")
                @state = :closing
                @connection.close_connection_after_writing
              else
                error = true
              end
            end
          else
            if @data.getbyte(0) != 0x00
              raise WSProtocolError, "Invalid frame received"
            end
            if @data.size > Wslp::MAX_FRAMS_SIZE
              raise WSMessageTooBigError, "Frame length too long (#{@data.size} bytes)"
            end
            error = true and next unless newdata =~ /\xff/
            msg = @data.slice!(/\A\x00[^\xff]*\xff/)
            if msg
              msg.gsub!(/\A\x00|\xff\z/, '')
              if @state != :closing
                msg.force_encoding('UTF-8') if msg.respond_to?(:force_encoding)
                @connection.trigger_on_message(msg)
              end
            else
              error = true
            end
          end
        end
        false
      end
      def send_text_frame(data)
        ary = ["\x00", data, "\xff"]
        ary.collect{ |s| s.force_encoding('UTF-8') if s.respond_to?(:force_encoding) }
        @connection.send_data(ary.join)
      end
    end
  end
end