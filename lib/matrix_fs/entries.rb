# frozen_string_literal: true

require 'base64'

module MatrixFS
  class Entry
    MAX_FRAG_SIZE = 56 * 1024 # 56kb to stay inside the 64k max event size
    XATTR_SAVE_DELAY = 1 # Save changes one second after the last xattr change

    attr_accessor :modes
    attr_reader :fs, :path, :timestamp, :xattr, :xattr_wrapper

    def initialize(fs, event:, path:, timestamp:, xattr: nil)
      @fs = fs
      @event = event
      @path = path
      @timestamp = timestamp

      @xattr = xattr || {}
      @xattr_wrapper = Object.new
      @xattr_wrapper.instance_variable_set :@main_entry, self
      @xattr_wrapper.instance_variable_set :@xattr, @xattr

      @xattr_wrapper.instance_eval do
        def start_save_timer
          stop_save_timer
          @save_timer = Thread.new { sleep XATTR_SAVE_DELAY; @main_entry.save!(true) }
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

        def inspect; @xattr.inspect end
        def to_s; @xattr.to_s end
      end
    end

    def save!(from_xattr = false)
      Logging.logger[self].debug "Saving changes to entry #{path}"
      @xattr_wrapper.stop_save_timer unless from_xattr
      fs.room.client.api.send_state_event fs.room.id, MatrixFS::STATE_TYPE, to_h, state_key: path
    end

    def delete!
      Logging.logger[self].debug "Deleting entry #{path}"
      @xattr_wrapper.stop_save_timer
      fs.room.client.api.send_state_event fs.room.id, MatrixFS::STATE_TYPE, {}, state_key: path
    end

    def type; end
    def size; 0 end

    def to_h
      {
        type: type,
        xattr: xattr
      }.compact
    end

    def global_xattrs
      %w[matrixfs.eventid matrixfs.sender]
    end
    
    def global_xattr(key)
      case key
      when 'matrixfs.eventid'
        @event&.event_id
      when 'matrixfs.sender'
        @event&.sender
      end
    end

    def self.new_from_data(fs, type:, **data)
      raise 'Needs a path' unless data.key? :path

      data[:event] = nil

      data[:timestamp] ||= Time.now
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
      raise 'Dangerous data in state event content' unless (state_event.content.keys & %i[path timestamp]).empty?

      data = {
        event: state_event,
        path: state_event.state_key,
        timestamp: Time.at(state_event.origin_server_ts / 1000.0),
      }.merge(state_event.content)

      data.delete :ctime
      type = data.delete :type

      if type == 'd'
        MatrixFS::DirEntry.new fs, **data
      elsif type == 'f'
        MatrixFS::FileEntry.new fs, **data
      elsif type == 'F'
        MatrixFS::FileFragmentEntry.new fs, **data
      else
        Logging.logger[self].error "Tried to create unknown type of entry (#{data}, type #{type.inspect})"
      end
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

        @size = size
        @fragments = fragments
        @fragmented = fragmented
      else
        raise 'ArgumentError (missing keyword: data)' unless data

        @data = data
      end
    end

    def type
      'f'
    end

    def size
      @size || @data.bytesize
    end

    def data
      if @fragmented
        data = each_fragment.map(&:data).join
        if @encoding == 'base64'
          data = Base64.strict_decode64 data
        end
        data
      else
        @data
      end
    end

    def data=(data)
      size = data.bytesize
      encoding = nil
      if data.encoding != Encoding::UTF_8
        begin
          data = data.encode(Encoding::UTF_8)
        rescue
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
        @data = data
        @old_fragments = [@fragments || 0, @old_fragments || 0].max
        @fragmented = nil
        @fragments = nil
        @size = nil
      end
    end

    def save!(*arg)
      super *arg
      return unless @fragmented

      if (@old_fragments || 0) > @fragments
        (@old_fragments - @fragments).times do |old_fragment|
          fragment = @old_fragments + old_fragment
          fragment_path = @path + "/.fragments/#{fragment}"
          entry = @fs.send :get_entry, fragment_path
          entry&.delete!
        end
      end

      each_fragment do |entry|
        entry.save!
      end
    end

    def delete!
      super
      return unless @fragmented

      each_fragment do |entry|
        entry.delete!
      end
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

    private

    def each_fragment(method = :get, **params)
      return to_enum(:each_fragment, method, **params) unless block_given?

      @fragments.times do |fragment|
        fragment_path = @path + "/.fragments/#{fragment}"
        entry = @fs.send :get_entry, fragment_path if method == :get
        entry = @fs.send :ensure_entry, fragment_path, **params if method == :ensure

        yield entry
      end
    end
  end

  class FileFragmentEntry < Entry
    attr_accessor :data

    def initialize(room, data: '', **params)
      super room, **params

      @data = data
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
    def type
      'd'
    end
  end
end
