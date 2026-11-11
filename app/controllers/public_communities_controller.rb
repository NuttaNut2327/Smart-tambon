class PublicCommunitiesController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!

  def show
    @setting = OrganizationSetting.where(public_community_slug: params[:slug]).first
    return head :not_found unless @setting&.public_community_enabled?

    @owner = User.where(organization_key: @setting.organization_key, role: User.roles[:subdistrict_admin]).first ||
      User.where(organization_key: @setting.organization_key).first
    return head :not_found unless @owner

    access_area = @owner.access_area
    subdistrict = @owner.subdistrict
    @boundary_feature = access_area ? access_area.as_geojson : subdistrict&.as_geojson
    return head :not_found unless @boundary_feature

    @area_name = access_area&.name.presence || "ตำบล#{subdistrict&.name_th}"
    report_scope = access_area ? { scope: "access_area", id: access_area.id } : { scope: "account", id: @owner.id }
    report_scope.merge!(version: @setting.public_report_version, source_type: "citizen", source_name: "ประชาชน")
    @report_url = public_incident_report_path(token: Rails.application.message_verifier(:public_incident_form).generate(report_scope))
    scope = Incident.visible_to(@owner).where(deleted_at: nil)
    active = scope.where(:status.in => %w[assessing in_progress]).desc(:updated_at).limit(300).to_a
    @map_items = active.filter_map { |incident| public_incident(incident) if incident.latitude && incident.longitude }
    completed_scope = scope.where(status: "completed", :updated_at.gte => 30.days.ago)
    @completed_count = completed_scope.count
    @completed_items = completed_scope.desc(:updated_at).map { |incident| public_completed_incident(incident) }
    public_news_scope = Broadcast.for_organization(@setting.organization_key)
      .where(status: "published", publish_to_public_web: true)
    @news = public_news_scope.desc(:published_at).limit(30).map { |broadcast| public_news(broadcast) }
    archived_news = public_news_scope.where(:published_at.gte => 30.days.ago).map { |broadcast| public_archived_news(broadcast) }
    @archive_items = (@completed_items + archived_news).sort_by { |item| item[:displayed_at].to_s }.reverse
    @counts = {
      accepted: active.count { |incident| incident.status == "assessing" },
      in_progress: active.count { |incident| incident.status == "in_progress" },
      activities: active.count(&:activity?),
      completed: @completed_count
    }
  end

  private

  def public_incident(incident)
    {
      id: incident.id.to_s,
      reference_code: incident.reference_code,
      category: incident.category,
      category_label: incident.category_label,
      incident_type: incident.activity? ? incident.activity_type_label : incident.incident_type,
      title: incident.title.to_s.truncate(120),
      summary: sanitized_summary(incident.description),
      status: incident.status,
      status_label: incident.status == "assessing" ? "เจ้าหน้าที่รับเรื่องแล้ว" : "กำลังดำเนินการ",
      location_name: incident.location_name.to_s.truncate(100),
      latitude: incident.latitude,
      longitude: incident.longitude,
      reported_at: incident.created_at&.iso8601,
      updated_at: incident.updated_at&.iso8601,
      confirmations: Array(incident.duplicate_confirmations).size,
      starts_at: incident.starts_at&.iso8601,
      ends_at: incident.ends_at&.iso8601
    }
  end

  def public_news(broadcast)
    {
      id: broadcast.id.to_s,
      title: broadcast.title.to_s.truncate(160),
      summary: broadcast.bullets.first(4).join(" · ").presence || broadcast.script.to_s.truncate(320),
      published_at: broadcast.published_at&.iso8601
    }
  end

  def public_completed_incident(incident)
    {
      id: incident.id.to_s,
      reference_code: incident.reference_code,
      category_label: incident.category_label,
      category: incident.category,
      incident_type: incident.activity? ? incident.activity_type_label : incident.incident_type,
      title: incident.title.to_s.truncate(120),
      summary: sanitized_summary(incident.description),
      location_name: incident.location_name.to_s.truncate(100),
      reported_at: incident.created_at&.iso8601,
      completed_at: incident.updated_at&.iso8601,
      displayed_at: incident.updated_at&.iso8601,
      confirmations: Array(incident.duplicate_confirmations).size
    }
  end

  def public_archived_news(broadcast)
    {
      id: broadcast.id.to_s,
      category: "news",
      category_label: "ข่าวประชาสัมพันธ์",
      incident_type: "ข่าวประชาสัมพันธ์",
      title: broadcast.title.to_s.truncate(160),
      summary: broadcast.bullets.first(4).join(" · ").presence || broadcast.script.to_s.truncate(320),
      displayed_at: broadcast.published_at&.iso8601,
      completed_at: nil,
      reported_at: nil,
      reference_code: nil,
      location_name: nil,
      confirmations: 0
    }
  end

  def sanitized_summary(value)
    value.to_s
      .gsub(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/, "[ข้อมูลติดต่อ]")
      .gsub(/(?:\+?66|0)[\d\s-]{8,12}/, "[ข้อมูลติดต่อ]")
      .squish.truncate(240)
  end
end
