module MatrixFS
  class YEnc
    CRITICAL = [
      0x00, # NULL
      0x0A, # LF
      0x0D, # CR
      0x3D  # =
    ]

    def self.encode(string)
      result = ''
      string.each_byte do |byte|
        encoded = (byte + 42) % 256
        if CRITICAL.include? encoded
          result = result + '='
          encoded = (encoded + 64) % 256
        end
        result = result + encoded.chr
      end
      result
    end

    def self.decode(string)
      result = ''
      critical = false
      string.each_byte do |byte|
        critical = true if byte == 0x3D
        if critical
          critical = false
          byte = (byte - 64) % 256
        end
        decoded = (byte - 42) % 256
        result = result.decoded.chr
      end
      result
    end
  end
end
