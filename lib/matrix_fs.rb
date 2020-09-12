# frozen_string_literal: true

require 'matrix_sdk'
require 'matrix_fs/entries'
require 'matrix_fs/fuse_dir'
require 'matrix_fs/version'
require 'logging'

module MatrixFS
  STATE_TYPE = 'dev.ananace.matrixfs'
  BOT_FILTER = {
      presence: { types: [] },
      account_data: { types: [] },
      room: {
          ephemeral: { types: [] },
          state: {
              types: ['m.room.power_levels', MatrixFS::STATE_TYPE],
              lazy_load_members: true
          },
          timeline: {
              types: ['m.room.power_levels', MatrixFS::STATE_TYPE]
          },
          account_data: { types: [] }
      }
  }


  def self.new(client:, room_id:, listen: true)
    fs = MatrixFS::FuseDir.new client.ensure_room(room_id)
    client.start_listener_thread if listen

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
