module Broadcasts
  # The broadcast worker's loop body: start scheduled programmes that are due, then work through queued tasks
  # (generate → synthesize → publish). Run every few seconds by `bin/rails broadcasts:work`.
  class Runner
    def self.tick(now: Time.current, logger: Rails.logger)
      start_due_programs(now, logger)
      Broadcast.where(:pending_tasks.ne => []).asc(:updated_at).limit(5).each { |broadcast| new(broadcast, logger).process }
    end

    def self.start_due_programs(now, logger)
      BroadcastProgram.enabled.where(schedule_enabled: true).each do |program|
        program.due_slots(now).each do |slot|
          broadcast = queue(program, trigger: "schedule", slot_key: slot)
          logger.info("[broadcast] scheduled #{program.name} #{slot} -> #{broadcast.id}")
        rescue Mongo::Error::OperationFailure
          # Another worker already created this slot (unique index on program + slot_key).
        end
      end
    end

    # Creates a broadcast for a programme and queues generation; auto-publish programmes also voice and publish it.
    def self.queue(program, trigger:, slot_key: nil, user: nil)
      tasks = %w[generate]
      tasks += %w[synthesize publish] if program.auto_publish? && trigger == "schedule"
      Broadcast.create!(broadcast_program: program, organization_key: program.organization_key, subdistrict_id: program.subdistrict_id,
                        status: "queued", trigger:, slot_key:, pending_tasks: tasks, auto_publish: program.auto_publish?,
                        channel_ids: program.channel_ids, created_by: user&.username || "ระบบ")
    end

    def initialize(broadcast, logger)
      @broadcast = broadcast
      @logger = logger
    end

    # Tasks run in order; a failure stops the chain so nothing half-made gets published.
    def process
      Broadcast::TASKS.each do |task|
        next unless @broadcast.reload.pending_tasks.include?(task)

        send(task)
        @broadcast.pull(pending_tasks: task)
      end
    rescue StandardError => error
      @logger.error("[broadcast] #{@broadcast.id} failed: #{error.class}: #{error.message}")
      @broadcast.set(pending_tasks: [], status: @broadcast.script.present? ? "draft" : "failed", error_message: error.message.to_s.truncate(500))
    end

    private

    def generate
      program = @broadcast.broadcast_program or raise "ไม่พบรายการข่าวของข่าวนี้"
      @broadcast.set(status: "generating", error_message: nil)
      context = Context.for(program)
      result = Writer.call(program, context)
      @broadcast.set(title: result.title.presence || "#{program.name} #{context['today']}", bullets: result.bullets, script: result.script,
                     prompt_used: program.prompt, context_snapshot: context, ai_model: result.model, generated_at: Time.current, status: "draft")
    end

    def synthesize
      text = @broadcast.spoken_text
      raise "ยังไม่มีข้อความสำหรับสร้างเสียง" if text.blank?

      program = @broadcast.broadcast_program
      result = Tts::Synthesizer.call(text, provider: program&.tts_provider || TtsProvider.default, voice: program&.tts_voice)
      Media.store(@broadcast, :audio, data: result.audio, content_type: result.content_type, filename: "broadcast-#{@broadcast.id}.mp3")
      @broadcast.set(audio_text_digest: Digest::SHA256.hexdigest(text), error_message: nil)
    end

    def publish
      Publisher.call(@broadcast.reload)
    end
  end
end
