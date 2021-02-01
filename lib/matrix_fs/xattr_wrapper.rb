# frozen_string_literal: true

module MatrixFS
  class Entry
    class XattrWrapper
      attr_accessor :xattr

      def initialize(entry:, xattr:)
        @main_entry = entry
        @xattr = xattr
      end

      def start_save_timer
        stop_save_timer
        @save_timer = Thread.new do
          sleep XATTR_SAVE_DELAY
          @main_entry.save!(true)
        end
      end

      def stop_save_timer
        @save_timer&.exit
        @save_timer = nil
      end

      def [](key)
        return @main_entry.global_xattr(key) if key.start_with? 'matrixfs.'

        @xattr[key]
      end

      def []=(key, data)
        return if key.start_with? 'matrixfs.'

        start_save_timer
        @xattr[key] = data
      end

      def keys
        @xattr.keys + @main_entry.global_xattrs
      end

      def delete(key)
        return if key.start_with? 'matrixfs.'

        start_save_timer
        @xattr.delete(key)
      end

      def inspect
        @xattr.inspect
      end

      def to_s
        @xattr.to_s
      end
    end
  end
end
