# Public status page for the reporter, reached from the SMS link (/t/<token>). No login; shows only the reference,
# category, status and the titles of progress steps — never descriptions, names or phone numbers.
class IncidentTrackingsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!
  layout false

  def show
    @incident = Incident.where(tracking_token: params[:token].to_s, deleted_at: nil).first if params[:token].to_s.length >= 16
    return render(:not_found, status: :not_found) unless @incident

    owner_key = User.where(id: @incident.owner_user_id).pick(:organization_key)
    @organization = OrganizationSetting.where(organization_key: owner_key).first if owner_key
    @steps = Array(@incident.histories).reject { |step| step["kind"] == "sms" }
                                       .sort_by { |step| step["occurred_at"].to_s }
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
