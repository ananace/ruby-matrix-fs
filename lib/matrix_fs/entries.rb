# frozen_string_literal: true

require 'base64'

module MatrixFS
  class Entry
    MAX_FRAG_SIZE = 56 * 1024 # 56kb to stay inside the 64k max event size
    XATTR_SAVE_DELAY = 1 # Save changes one second after the last xattr change

    attr_accessor :modes, :timestamp, :atime
    attr_reader :fs, :path, :xattr, :xattr_wrapper

    def initialize(fs, event:, path:, timestamp:, atime: nil, xattr: nil)
      @fs = fs
      @event = event.dup
      @event.delete :content
      @path = path
      @timestamp = timestamp
      @atime = atime || Time.now

      @xattr = xattr || {}
      @xattr_wrapper = XattrWrapper.new entry: self, xattr: @xattr
    end

    def save!(from_xattr = false)
      Logging.logger[self].debug "Saving changes to entry #{path}"
      @timestamp = Time.now
      @xattr_wrapper.stop_save_timer unless from_xattr
      fs.room.client.api.send_state_event fs.room.id, MatrixFS::STATE_TYPE, to_h, state_key: path
    end

    def delete!
      Logging.logger[self].debug "Deleting entry #{path}"
      @xattr_wrapper.stop_save_timer
      fs.room.client.api.send_state_event fs.room.id, MatrixFS::STATE_TYPE, {}, state_key: path
    end

    def reload!(data = nil)
      Logging.logger[self].debug "Reloading entry #{path}"

      data ||= fs.room.client.api.get_room_state fs.room.id, MatrixFS::STATE_TYPE, key: path

      raise NotImplementedError, "Can't change type of #{path} from #{type} to #{data[:type]}" if data.key?(:type) && data[:type] != type

      @clean = false

      yield data if block_given?
      return self if is_a? FileFragmentEntry

      @type = data[:type] if data.key? :type
      return self unless data.key? :xattr

      @xattr.merge!(data[:xattr] || {})
      @xattr_wrapper.stop_save_timer

      self
    end

    def clear!
      return unless @event

      @event.delete :content
    ensure
      @clean = true
    end

    def clean?
      @clean
    end

    def type; end

    def size
      0
    end

    def to_h
      {
        type: type,
        xattr: xattr
      }.compact
    end

    def global_xattrs
      %w[matrixfs.eventid matrixfs.sender matrixfs.fragmented]
    end

    def global_xattr(key)
      case key
      when 'matrixfs.eventid'
        @event&.event_id
      when 'matrixfs.sender'
        @event&.sender
      when 'matrixfs.fragmented'
        is_a? FileFragmentEntry
      end
    end

    def self.new_from_data(fs, type:, **data)
      raise 'Needs a path' unless data.key? :path

      data[:event] ||= nil
      data[:timestamp] ||= Time.now
      data.delete :ctime

      if type == 'd'
        MatrixFS::DirEntry.new fs, **data
      elsif type == 'f'
        MatrixFS::FileEntry.new fs, **data
      elsif type == 'F'
        MatrixFS::FileFragmentEntry.new fs, **data
      else
        Logging.logger[self].error "Tried to create unknown type of entry (#{data})"
      end
    end

    def self.new_from_event(fs, state_event)
      raise 'Dangerous data in state event content' unless (state_event[:content].keys & %i[path timestamp]).empty?

      data = {
        event: state_event,
        path: state_event[:state_key],
        timestamp: Time.at(state_event[:origin_server_ts] / 1000.0)
      }.merge(state_event[:content])

      type = data.delete :type

      new_from_data(fs, type: type, **data)
    end
  end

  class FileEntry < Entry
    attr_accessor :executable

    def initialize(room, executable: nil, size: nil, fragments: nil, fragmented: nil, data: '', encoding: nil, **params)
      super room, **params

      @encoding = encoding
      @executable = executable
      if fragmented
        raise 'ArgumentError (missing keyword: size)' unless size
        raise 'ArgumentError (missing keyword: fragments)' unless fragments

        @data = ''
        @size = size
        @fragments = fragments
        @fragmented = true
      else
        raise 'ArgumentError (missing keyword: data)' unless data

        @data = data
        @size = @data.bytesize
      end
    end

    def reload!(inp = nil)
      super do |data|
        @encoding = data[:encoding] if data.key? :encoding
        @executable = data[:executable] if data.key? :executable
        if data[:fragmented]
          @size = data[:size]
          @fragments = data[:fragments]
          @fragmented = true
        else
          @data.replace data[:data]
          @size = @data&.bytesize || 0
        end
      end
    end

    def clear!
      super
      @data.replace ''
    end

    def type
      'f'
    end

    def fragmented?
      @fragmented
    end

    def size
      @size || @data&.bytesize
    end

    def data
      if @fragmented
        data = each_fragment.map(&:data).join
        if @encoding == 'base64'
          data = Base64.strict_decode64 data
        end
        @data.replace data
      else
        reload! if clean?
        @data
      end
    ensure
      @atime = Time.now
    end

    def data=(data)
      size = data.bytesize
      encoding = nil
      if data.encoding != Encoding::UTF_8
        begin
          data = data.encode(Encoding::UTF_8)
        rescue Encoding::UndefinedConversionError
          data = Base64.strict_encode64 data
          encoding = 'base64'
        end
      elsif !data.valid_encoding?
        data = Base64.strict_encode64 data
        encoding = 'base64'
      end
      @encoding = encoding

      if data.size > Entry::MAX_FRAG_SIZE
        @fragmented = true
        @old_fragments = [@fragments || 0, @old_fragments || 0].max
        @fragments = (data.size / Entry::MAX_FRAG_SIZE.to_f).ceil
        @size = size

        each_fragment(:ensure, type: 'F').map.with_index do |entry, index|
          chunk = data[index * Entry::MAX_FRAG_SIZE, Entry::MAX_FRAG_SIZE]
          entry.data = chunk
        end
      else
        @data.replace data
        @old_fragments = [@fragments || 0, @old_fragments || 0].max
        @fragmented = nil
        @fragments = nil
        @size = @data.bytesize
      end
    end

    def save!(*arg)
      super(*arg)
      return unless @fragmented

      if (@old_fragments || 0) > @fragments
        (@old_fragments - @fragments).times do |old_fragment|
          fragment = @old_fragments + old_fragment
          fragment_path = @path + "/.fragments/#{fragment}"
          entry = @fs.send :get_entry, fragment_path
          entry&.delete!
        end
      end

      each_fragment(&:save!)
    ensure
      @clean = false
      @timestamp = Time.now
    end

    def delete!
      super
      return unless @fragmented

      each_fragment(&:delete!)
    end

    def to_h
      h = super
      h[:encoding] = @encoding unless @encoding.nil?
      if @fragmented
        h.merge!(
          fragmented: @fragmented,
          fragments: @fragments,
          size: @size
        ).compact
      else
        h[:data] = data unless data.nil?
      end
      h
    end

    def each_fragment(method = :get, **params)
      raise 'Not fragmented' unless @fragmented

      return to_enum(:each_fragment, method, **params) unless block_given?

      @fragments.times do |fragment|
        fragment_path = @path + "/.fragments/#{fragment}"
        entry = nil
        if method == :head
          entry = @fs.send :get_entry, fragment_path
        elsif method == :get
          entry = @fs.send :get_entry, fragment_path
          if entry.clean?
            entry.reload!
            @clean = false
          end
        elsif method == :ensure
          entry = @fs.send :ensure_entry, fragment_path, **params
        end

        yield entry if entry
      end
    end
  end

  class FileFragmentEntry < Entry
    attr_accessor :data

    def initialize(room, data: '', **params)
      super room, **params

      @data = data
    end

    def clear!
      super

      @data.replace ''
    end

    def reload!(inp = nil)
      super do |data|
        @data.replace data.data
      end
    end

    def type
      'F'
    end

    def to_h
      {
        type: 'F',
        data: data
      }
    end
  end

  class DirEntry < Entry
    def initialize(*params)
      super

      @clean = true
    end

    def type
      'd'
    end
  end
end
