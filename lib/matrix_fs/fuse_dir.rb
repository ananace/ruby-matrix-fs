# frozen_string_literal: true

require 'fusefs'

module MatrixFS
  class FuseDir < FuseFS::FuseDir
    include MatrixSdk::Logging

    attr_reader :room

    def initialize(room)
      raise 'Must be given a valid MatrixSdk::Room instance' unless room.is_a? MatrixSdk::Room

      @room = room
      @state = {}
      room.on_state_event.add_handler(MatrixFS::STATE_TYPE, 'entries') { |event| state_change(event) }
      room.on_state_event.add_handler('m.room.power_levels', 'powerlevels') { |event| check_permissions(event) }

      logger.info 'Getting initial state, please wait...'

      get_initial_data

      logger.info "Startup finished, finalizing mount.#{rand(10) == 0 ? ' Have a pleasant day.' : nil}"
    end

    def directory?(path)
      return result = false unless path_valid?(path)
      return result = true if path == '/'

      result = get_entry(path)&.class == MatrixFS::DirEntry
    ensure
      logger.debug "#{path} directory? #{result}"
    end

    def file?(path)
      return result = false unless path_valid?(path)

      result = get_entry(path)&.class == MatrixFS::FileEntry
    ensure
      logger.debug "#{path} file? #{result}"
    end

    def contents(path)
      return result = [] unless directory? path

      result = @state.select do |p, f|
        f.type != 'F' && p != path && File.dirname(p) == path
      end.map { |_, f| f.path.delete_prefix(path).delete_prefix('/') }.sort
    ensure
      logger.debug "#{path} dirents => #{result}"
    end

    def executable?(path)
      return result = false unless path_valid?(path)

      entry = get_entry(path)
      return result = true if entry&.class == MatrixFS::DirEntry
      return result = true if entry&.class == MatrixFS::FileEntry && entry&.executable
      result = false
    ensure
      logger.debug "#{path} executable? #{result}"
    end

    def size(path)
      result = get_entry(path)&.size
    ensure
      logger.debug "#{path} size => #{result}"
    end

    def times(path)
      return result = [Time.now, Time.now, Time.now] if path == '/'

      entry = get_entry(path)
      result = [ entry&.timestamp || 0, entry&.timestamp || 0, entry&.timestamp || 0 ]
    ensure
      logger.debug "#{path} times => #{result}"
    end

    def read_file(path)
      result = get_entry(path)&.data
    ensure
      logger.debug "#{path} read #{result.bytesize}b"
    end

    def can_write?(path)
      return result = false unless @can_write
      return result = false unless path_valid?(path)
      return result = false if get_entry(path)&.class == MatrixFS::DirEntry
      result = true
    ensure
      logger.debug "#{path} writable? #{result}"
    end

    def write_to(path, data)
      return result = '' unless can_write?(path)

      entry = ensure_entry(path, type: 'f')
      result = entry.data = data
      entry.save!
    ensure
      logger.debug "#{path} wrote #{result.bytesize}b"
    end

    def can_delete?(path)
      return result = false unless @can_write
      return result = false unless path_valid?(path)
      return result = false unless has_entry?(path)
      result = true
    ensure
      logger.debug "#{path} deletable? #{result}"
    end

    def delete(path)
      get_entry(path)&.delete!
    ensure
      logger.debug "#{path} deleted"
    end

    def can_mkdir?(path)
      return result = false unless @can_write
      return result = false unless path_valid?(path)
      return result = false if has_entry?(path)
      result = true
    ensure
      logger.debug "#{path} mkdir? #{result}"
    end

    def mkdir(path)
      ensure_entry(path, type: 'd').save!
    ensure
      logger.debug "#{path} mkdir"
    end

    def can_rmdir?(path)
      return result = false unless @can_write
      return result = false unless path_valid?(path)
      return result = false unless get_entry(path)&.class == MatrixFS::DirEntry
      result = true
    ensure
      logger.debug "#{path} rmdir? #{result}"
    end

    def rmdir(path)
      get_entry(path)&.delete!
    ensure
      logger.debug "#{path} rmdir"
    end

    def touch(path, _mtime)
      return unless @can_write

      ensure_entry(path, type: 'f').save!
    ensure
      logger.debug "#{path} touch"
    end

    def xattr(path)
      return result = {} unless @can_write

      result = get_entry(path)&.xattr_wrapper || {}
    ensure
      logger.debug "#{path} xattr => #{result}"
    end

    private

    def path_valid?(path)
      path.length < 255
    end

    def has_entry?(path)
      @state.key? path
    end

    def ensure_entry(path, **params)
      logger.debug "Ensuring entry #{path} with #{params}"
      @state[path] ||= MatrixFS::Entry.new_from_data(self, path: path, **params)
    end

    def get_entry(path)
      logger.debug "Getting entry #{path}"
      return nil unless has_entry?(path)
      @state[path]
    end

    def get_initial_data
      logger.debug 'Getting initial sync data'
      room.client.sync

      if @can_write.nil?
        logger.debug 'No PL in initial sync, using side-request'
        check_permissions
      end
    end

    def check_permissions(event = nil)
      return if !event.nil?

      logger.info "Received updated power levels, refreshing write status."
      event ||= { content: room.client.api.get_room_power_levels(room.id) }

      current_pl = event.dig(:content, :users, room.client.mxid.to_s.to_sym) || event.dig(:content, :users_default) || 0
      needed_pl = event.dig(:content, :events, MatrixFS::STATE_TYPE.to_sym) || event.dig(:content, :state_default) || 50

      logger.debug "User #{room.client.mxid} has PL #{current_pl}, can_write? #{current_pl > needed_pl}"

      @can_write = current_pl >= needed_pl
    end

    def state_change(event)
      return unless event.type == MatrixFS::STATE_TYPE

      if event.content.empty?
        logger.info "Received delete for #{event.state_key}"
        @state.delete event.state_key
      else
        cur = @state[event.state_key] 
        return if !cur.nil? && cur.timestamp >= event.timestamp

        logger.info "Received updated data for #{event.state_key}"
        @state[event.state_key] = MatrixFS::Entry.new_from_event(self, event)
      end
    end
  end
end
