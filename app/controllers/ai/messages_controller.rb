module Ai
  # Sends one question and waits for the full answer (no streaming); the browser shows a progress state meanwhile.
  class MessagesController < BaseController
    MAX_LENGTH = 4000

    def create
      session = find_session(params[:session_id])
      text = params[:content].to_s.strip
      return render_error("กรุณาพิมพ์คำถาม") if text.blank?
      return render_error("คำถามยาวเกิน #{MAX_LENGTH} ตัวอักษร") if text.length > MAX_LENGTH
      return render_error("แชตนี้ยาวถึงขีดจำกัดแล้ว กรุณาเริ่มแชตใหม่") if session.full?

      provider = session.provider
      seq = session.messages.max(:seq).to_i
      session.messages.create!(seq: seq + 1, role: "user", content: text)
      session.title = text.lines.first.to_s.strip.truncate(60) if session.default_title?

      begin
        result = Agent.new(user: current_user, provider: provider).reply(session, text)
        session.messages.create!(seq: seq + 2, role: "assistant", **result)
      rescue Llm::Error => error
        session.messages.create!(seq: seq + 2, role: "assistant", error: error.message, model: provider&.model)
      end
      session.message_count = session.messages.count
      session.ai_provider_id ||= provider&.id
      session.save!
      render json: session.as_detail_json
    end
  end
end
