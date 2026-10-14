module Ai
  # JSON endpoints behind the AI assistant tab. Sessions are private to their owner; snippets are the owner's
  # plus those shared inside the same organisation.
  class BaseController < ApplicationController
    rescue_from Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId do
      render json: { error: "ไม่พบข้อมูล หรือไม่มีสิทธิ์เข้าถึง" }, status: :not_found
    end

    private

    def render_error(message, status: :unprocessable_entity) = render(json: { error: message }, status: status)

    def find_session(id) = AiChatSession.owned_by(current_user).find(id)
  end
end
