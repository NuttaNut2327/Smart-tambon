namespace :broadcasts do
  desc "Run the news broadcast worker: start scheduled programmes and process queued broadcasts (BROADCAST_POLL_SECONDS, default 10)"
  task work: :environment do
    $stdout.sync = true
    logger = ActiveSupport::Logger.new($stdout)
    interval = Integer(ENV.fetch("BROADCAST_POLL_SECONDS", "10"))
    stopping = false
    %w[TERM INT].each { |signal| Signal.trap(signal) { stopping = true } }
    logger.info("[broadcast] worker started (every #{interval}s)")
    until stopping
      begin
        Rails.application.executor.wrap { Broadcasts::Runner.tick(logger:) }
      rescue StandardError => error
        logger.error("[broadcast] tick failed: #{error.class}: #{error.message}")
      end
      interval.times { break if stopping; sleep 1 }
    end
    logger.info("[broadcast] worker stopped")
  end

  desc "Process due and queued broadcasts once"
  task tick: :environment do
    Broadcasts::Runner.tick(logger: ActiveSupport::Logger.new($stdout))
  end
end
