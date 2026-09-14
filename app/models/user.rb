class User < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  belongs_to :subdistrict, optional: true
  has_one :access_area, class_name: "UserAccessArea", dependent: :destroy
  attr_accessor :access_area_file_pending

  enum :role, { system_admin: 0, subdistrict_admin: 1, subdistrict_user: 2 }, default: :subdistrict_user

  validates :subdistrict, presence: true, if: -> { (subdistrict_admin? || subdistrict_user?) && !access_area_file_pending? && access_area.blank? }
  validates :username, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[a-z0-9._-]+\z/, message: "ใช้ตัวอักษรอังกฤษ ตัวเลข จุด ขีดกลาง หรือขีดล่างเท่านั้น" }

  before_validation :normalize_username

  def role_label
    {
      "system_admin" => "ผู้ดูแลระบบ",
      "subdistrict_admin" => "ผู้ดูแลประจำตำบล",
      "subdistrict_user" => "ผู้ใช้งานประจำตำบล (อ่านข้อมูล)"
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

  def access_area_file_pending?
    ActiveModel::Type::Boolean.new.cast(access_area_file_pending)
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase
    self.email = "#{username}@smartcity.local" if username.present? && email.blank?
  end
end
