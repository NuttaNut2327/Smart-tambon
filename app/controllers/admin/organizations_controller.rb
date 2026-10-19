module Admin
  # Every local organisation in the system (one per User#organization_key), with its area, admins and how it
  # joined. The system admin can switch into an organisation's admin account to support it.
  class OrganizationsController < BaseController
    Organization = Struct.new(:key, :name, :type_label, :area, :admins, :users_count, :joined_at, :registration, keyword_init: true)

    def index
      @query = params[:q].to_s.strip
      @organizations = organizations
      @organizations = @organizations.select { |org| [org.name, org.area, *org.admins.map(&:username)].join(" ").include?(@query) } if @query.present?
      @pending_count = OrganizationRegistration.pending.count
    end

    def show
      @organization = organizations.find { |org| org.key == params[:id] } or return redirect_to(admin_organizations_path, alert: "ไม่พบหน่วยงาน")
      @users = User.where(organization_key: @organization.key).order(:role, :username).to_a
      @logs = AdminAuditLog.where(target: @organization.key).order_by(created_at: :desc).limit(20).to_a
    end

    # Sign in as the organisation's admin; the real admin's id stays in the session for switching back.
    def switch
      target = User.where(organization_key: params[:id]).where.not(role: :system_admin).order(:role, :id).first
      return redirect_to(admin_organizations_path, alert: "หน่วยงานนี้ยังไม่มีบัญชีผู้ใช้") unless target

      admin = current_user
      AdminAuditLog.record!(admin, "switch_account", target.organization_key, request:, user_id: target.id, username: target.username)
      sign_in(:user, target)
      session[:impersonator_id] = admin.id
      redirect_to root_path, notice: "กำลังใช้งานในฐานะ #{target.username} (#{organization_name(target)})"
    end

    private

    def organizations
      users = User.where.not(role: User.roles[:system_admin]).where.not(organization_key: [nil, ""]).includes(subdistrict: :province, access_area: nil).to_a
      settings = OrganizationSetting.where(:organization_key.in => users.map(&:organization_key).uniq).index_by(&:organization_key)
      registrations = OrganizationRegistration.where(status: "approved", :user_id.in => users.map(&:id)).index_by(&:user_id)
      users.group_by(&:organization_key).map do |key, members|
        admins = members.select(&:subdistrict_admin?)
        lead = admins.first || members.first
        area = lead.subdistrict
        Organization.new(
          key:, name: settings[key]&.organization_name.presence || lead.access_area&.name.presence || (area && "อบต.#{area.name_th}") || key,
          type_label: lead.access_area&.organization_type_label || UserAccessArea::ORGANIZATION_TYPES["subdistrict_administrative_organization"],
          area: area ? "ต.#{area.name_th} อ.#{area.district_name_th} จ.#{area.province&.name_th}" : (lead.access_area ? "#{Array(lead.access_area.subdistrict_ids).size} ตำบล" : "-"),
          admins:, users_count: members.size, joined_at: members.map(&:created_at).min,
          registration: members.filter_map { |member| registrations[member.id] }.first
        )
      end.sort_by { |org| -org.joined_at.to_i }
    end

    def organization_name(user)
      OrganizationSetting.where(organization_key: user.organization_key).pick(:organization_name).presence || user.subdistrict&.name_th
    end
  end
end
