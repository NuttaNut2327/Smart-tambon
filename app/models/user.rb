class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  belongs_to :subdistrict, optional: true
  has_one :access_area, class_name: "UserAccessArea", dependent: :destroy
  attr_accessor :access_area_file_pending

  enum :role, { system_admin: 0, subdistrict_admin: 1, subdistrict_user: 2 }, default: :subdistrict_user

  validates :subdistrict, presence: true, if: -> { (subdistrict_admin? || subdistrict_user?) && !access_area_file_pending? && access_area.blank? }
  validates :username, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[a-z0-9._-]+\z/, message: "ใช้ตัวอักษรอังกฤษ ตัวเลข จุด ขีดกลาง หรือขีดล่างเท่านั้น" }

  before_validation :normalize_username
  before_validation :assign_organization_key

  def role_label
    {
      "system_admin" => "ผู้ดูแลระบบ",
      "subdistrict_admin" => "ผู้ดูแลประจำ อบต.",
      "subdistrict_user" => "เจ้าหน้าที่ประจำ อบต."
    }.fetch(role, "ยังไม่กำหนดสิทธิ์")
  end

  def access_boundary
    access_area&.boundary || subdistrict&.boundary
  end

  def accessible_subdistrict_ids
    return Subdistrict.pluck(:id) if system_admin?
    ids = Array(access_area&.subdistrict_ids).map(&:to_i)
    (ids + [subdistrict_id]).compact.uniq
  end

  def organization_user_ids
    return User.pluck(:id) if system_admin?
    return [id].compact if organization_key.blank?

    User.where(organization_key: organization_key).where.not(role: :system_admin).pluck(:id)
  end

  def can_manage_organization_data?(owner_user_id)
    return true if system_admin? || id == owner_user_id.to_i

    subdistrict_admin? && organization_user_ids.include?(owner_user_id.to_i)
  end

  def access_area_file_pending?
    ActiveModel::Type::Boolean.new.cast(access_area_file_pending)
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase
    self.email = "#{username}@smartcity.local" if username.present? && email.blank?
  end

  def assign_organization_key
    self.organization_key ||= if system_admin?
      "system:#{SecureRandom.uuid}"
    elsif subdistrict_id.present?
      "subdistrict:#{subdistrict_id}"
    else
      "account:#{SecureRandom.uuid}"
    end
  end
end
