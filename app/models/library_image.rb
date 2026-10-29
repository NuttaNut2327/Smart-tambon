# One picture in the image library (คลังข้อมูลภาพ). Every image attached in the app (incidents, activities, projects,
# resource rows, logos) is stored here once as WebP plus a thumbnail. Attachments copy the object keys together with
# library_image_id, so the library owns the objects in MinIO and removing an attachment never deletes the picture.
class LibraryImage
  include Mongoid::Document
  include Mongoid::Timestamps

  SOURCES = {
    "library" => "อัปโหลดในคลังภาพ", "incident" => "แจ้งเหตุ", "activity" => "กิจกรรม", "project" => "โครงการ",
    "dataset_record" => "ข้อมูลทรัพยากร", "logo" => "โลโก้"
  }.freeze

  field :title, type: String
  field :original_filename, type: String
  field :original_content_type, type: String
  field :original_byte_size, type: Integer
  field :source, type: String, default: "library"
  field :owner_user_id, type: Integer
  field :subdistrict_id, type: Integer
  field :uploaded_by, type: String
  field :checksum, type: String
  field :width, type: Integer
  field :height, type: Integer
  field :image, type: Hash
  field :thumbnail, type: Hash

  index({ owner_user_id: 1, created_at: -1 })
  index({ subdistrict_id: 1, created_at: -1 })
  index({ checksum: 1 })

  validates :title, :image, presence: true
  validates :source, inclusion: { in: SOURCES.keys }

  # Same rule as projects: the organisation's own uploads plus anything filed under an area the user can access
  # (public incident reports have no owner).
  scope :visible_to, lambda { |user|
    user.system_admin? ? all : any_of(
      { :owner_user_id.in => user.organization_user_ids },
      { :subdistrict_id.in => user.accessible_subdistrict_ids }
    )
  }
  scope :matching, ->(query) { query.present? ? where(title: /#{Regexp.escape(query.strip)}/i) : all }

  def source_label = SOURCES.fetch(source, source)

  def editable_by?(user)
    user.can_manage_organization_data?(owner_user_id) ||
      (user.subdistrict_admin? && user.accessible_subdistrict_ids.include?(subdistrict_id))
  end

  def variant(name) = name.to_s == "thumb" && thumbnail.present? ? thumbnail : image

  # The hash stored in Incident#photos, Project#photos, logos, ... The keys match the legacy photo records so existing
  # download and display code keeps working; thumbnail_key adds the small variant.
  def attachment
    {
      "id" => id.to_s, "library_image_id" => id.to_s, "key" => image["key"], "thumbnail_key" => thumbnail&.dig("key"),
      "filename" => image["filename"], "content_type" => image["content_type"], "byte_size" => image["byte_size"],
      "uploaded_at" => created_at || Time.current
    }
  end

  # Where each image is attached: { "image id" => [{ label:, kind: }, ...] }. Soft-deleted incidents don't count.
  def self.usages_for(images)
    ids = images.map { |image| image.id.to_s }
    usages = Hash.new { |hash, key| hash[key] = [] }
    return usages if ids.empty?

    Incident.where(deleted_at: nil, :"photos.library_image_id".in => ids).only(:title, :category, :photos).each do |incident|
      kind = incident.category == "activity" ? "กิจกรรม" : "เหตุการณ์"
      referenced_ids(incident.photos, ids).each { |id| usages[id] << { kind:, label: incident.title.presence || kind } }
    end
    Project.where(:"photos.library_image_id".in => ids).only(:name, :photos).each do |project|
      referenced_ids(project.photos, ids).each { |id| usages[id] << { kind: "โครงการ", label: project.name } }
    end
    DatasetRecordPhoto.where(:library_image_id.in => ids).each do |photo|
      usages[photo.library_image_id] << { kind: "ข้อมูลทรัพยากร", label: "รายการ #{photo.record_id}" }
    end
    OrganizationSetting.where(:"logo.library_image_id".in => ids).each do |setting|
      usages[setting.logo["library_image_id"]] << { kind: "โลโก้", label: setting.organization_name.presence || "โลโก้ อบต." }
    end
    SystemSetting.where(:"logo.library_image_id".in => ids).each do |setting|
      usages[setting.logo["library_image_id"]] << { kind: "โลโก้", label: "โลโก้ระบบ" }
    end
    usages
  end

  def self.referenced_ids(photos, ids) = Array(photos).filter_map { |photo| photo["library_image_id"] if ids.include?(photo["library_image_id"]) }.uniq

  def usages = self.class.usages_for([self])[id.to_s]
  def in_use? = usages.any?
end
