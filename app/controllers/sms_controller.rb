# send_sms?id=<incident_id>&mode=<tracking|video>&ajax=1 (contract carried over from SmartEMS).
# GET returns a preview without sending; POST sends. Sending over GET (as SmartEMS allowed) is refused because a
# plain link or image tag could otherwise spend SMS credit on the user's behalf.
class SmsController < ApplicationController
  rescue_from Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId do
    respond_error("ไม่พบเรื่องนี้ หรือไม่มีสิทธิ์เข้าถึง", :not_found)
  end

  def create
    incident = Incident.visible_to(current_user).find(params[:id])
    sender = Sms::IncidentLinkSender.new(incident: incident, user: current_user)
    return render(json: payload(sender.preview(params[:mode])).merge(ok: true, preview: true, status: nil, provider: {})) if request.get?

    preview, result = sender.deliver(params[:mode])
    if ajax?
      render json: payload(preview).merge(ok: result.ok?, status: result.http_status, code: result.code, error: result.error, provider: result.body),
             status: result.ok? ? :ok : :bad_gateway
    else
      redirect_back fallback_location: general_incidents_path(incident_id: incident.id),
                    **(result.ok? ? { notice: "ส่ง SMS ถึง #{preview.phone} แล้ว" } : { alert: "ส่ง SMS ไม่สำเร็จ: #{result.error}" })
    end
  rescue Sms::IncidentLinkSender::Error => error
    respond_error(error.message, :unprocessable_entity)
  end

  private

  def ajax? = params[:ajax].to_s == "1" || request.format.json?

  def payload(preview) = { mode: preview.mode, phone: preview.phone, link: preview.link, template: preview.template }

  def respond_error(message, status)
    return render(json: { ok: false, error: message }, status: status) if ajax? || request.get?

    redirect_back fallback_location: general_incidents_path, alert: message
  end
end
