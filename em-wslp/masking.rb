#encoding:utf-8
module EventMachine
  module Wslp
    class MaskedString < String
      def read_mask
        if respond_to?(:encoding) && encoding.name != "ASCII-8BIT"
          raise "MaskedString only operates on BINARY strings"
        end
        raise "Too short" if bytesize < 4 # TODO - change
        @masking_key = String.new(self[0..3])
      end

      def unset_mask
        @masking_key = nil
      end

      def getbyte(index)
        if defined?(@masking_key) && @masking_key
          masked_char = super
          masked_char ? masked_char ^ @masking_key.getbyte(index % 4) : nil
        else
          super
        end
      end

      def getbytes(start_index, count)
        data = ''
        data.force_encoding('ASCII-8BIT') if data.respond_to?(:force_encoding)
        count.times do |i|
          data << getbyte(start_index + i)
        end
        data
      end
    end
  end
end
