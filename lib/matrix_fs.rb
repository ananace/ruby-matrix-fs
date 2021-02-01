# frozen_string_literal: true

require 'matrix_sdk'
require 'matrix_fs/entries'
require 'matrix_fs/fuse_dir'
require 'matrix_fs/version'
require 'matrix_fs/xattr_wrapper'
require 'logging'

module MatrixFS
  STATE_TYPE = 'dev.ananace.matrixfs'
  BOT_FILTER = {
      event_fields: %w[
        type
        event_id
        sender
        content
        state_key
        origin_server_ts
      ],
      presence: { types: [] },
      account_data: { types: [] },
      room: {
          ephemeral: { types: [] },
          state: { types: [] },
          timeline: {
              types: ['m.room.power_levels', MatrixFS::STATE_TYPE]
          },
          account_data: { types: [] }
      }
  }


  def self.new(client:, room_id:, listen: true, gc: nil)
    fs = MatrixFS::FuseDir.new client.ensure_room(room_id)
    fs.gc_timer = gc if gc
    
    if listen
      filter = client.api.create_filter client.mxid, client.sync_filter
      client.start_listener_thread filter: filter.filter_id
    end

    fs
  end

  def self.debug!
    logger.level = :debug
  end

  def self.info!
    logger.level = :info
  end

  def self.logger
    @logger ||= ::Logging.logger[self].tap do |logger|
      logger.add_appenders ::Logging.appenders.stdout
      logger.level = :error
    end
  end

  class Error < StandardError; end
end
