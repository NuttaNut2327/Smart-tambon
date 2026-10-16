class AnnouncementsController < ApplicationController
  before_action :require_announcement_admin!, except: :acknowledge
  before_action :set_announcement, only: %i[edit update destroy toggle]

  def index
    @announcements = Announcement.order_by(created_at: :desc).to_a
    @receipt_counts = AnnouncementReceipt.collection.aggregate([
      { "$match" => { "announcement_id" => { "$in" => @announcements.map(&:id) } } },
      { "$group" => { "_id" => "$announcement_id", "seen" => { "$sum" => 1 },
                      "acknowledged" => { "$sum" => { "$cond" => [{ "$ifNull" => ["$acknowledged_at", false] }, 1, 0] } } } }
    ]).to_h { |row| [row["_id"], row] }
  end

  def new
    @announcement = Announcement.new(starts_at: Time.current.beginning_of_minute)
  end

  def create
    @announcement = Announcement.new(announcement_params.merge(created_by_id: current_user.id))
    return render(:new, status: :unprocessable_entity) unless @announcement.save

    redirect_to announcements_path, notice: "สร้างประกาศ #{@announcement.title} เรียบร้อยแล้ว"
  end

  def edit; end

  def update
    return render(:edit, status: :unprocessable_entity) unless @announcement.update(announcement_params)

    redirect_to announcements_path, notice: "อัปเดตประกาศ #{@announcement.title} เรียบร้อยแล้ว"
  end

  def toggle
    @announcement.update!(active: !@announcement.active?)
    redirect_to announcements_path, notice: "#{@announcement.active? ? 'เปิด' : 'ปิด'}ใช้งานประกาศ #{@announcement.title} แล้ว"
  end

  def destroy
    @announcement.destroy
    redirect_to announcements_path, notice: "ลบประกาศ #{@announcement.title} เรียบร้อยแล้ว"
  end

  # Called from the popup's "รับทราบ" button by any signed-in user the announcement targets.
  def acknowledge
    announcement = Announcement.current.find(params[:id])
    return head(:not_found) unless announcement.targets?(current_user) && !announcement.corner?

    AnnouncementFeed.new(current_user, session).acknowledge!(announcement)
    head :no_content
  rescue Mongoid::Errors::DocumentNotFound
    head :not_found
  end

  private

  def require_announcement_admin!
    return if system_admin?

    redirect_to root_path, alert: "เฉพาะผู้ดูแลระบบเท่านั้นที่จัดการประกาศได้"
  end

  def set_announcement
    @announcement = Announcement.find(params[:id])
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to announcements_path, alert: "ไม่พบประกาศที่ต้องการ"
  end

  def announcement_params
    params.require(:announcement).permit(
      :title, :body, :level, :frequency, :display_mode, :active, :starts_at, :ends_at,
      :target_subdistrict_codes, target_roles: []
    )
  end
end
