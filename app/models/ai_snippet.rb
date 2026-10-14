# A kept AI result: the charts' query specs plus the report text, so it can be re-run later on fresh data.
# Re-running executes the specs with the *viewer's* scope, never the owner's, so sharing never widens access.
class AiSnippet
  include Mongoid::Document
  include Mongoid::Timestamps

  field :user_id, type: Integer
  field :owner_name, type: String
  field :organization_key, type: String
  field :session_id, type: BSON::ObjectId
  field :title, type: String
  field :question, type: String
  field :report, type: String, default: ""
  field :artifacts, type: Array, default: []
  field :shared, type: Boolean, default: false
  field :last_run_at, type: Time
  field :run_count, type: Integer, default: 0

  index({ user_id: 1, updated_at: -1 })
  index({ organization_key: 1, shared: 1 })

  validates :user_id, :title, presence: true
  validate :must_have_content

  scope :visible_to, lambda { |user|
    any_of({ user_id: user.id }, { shared: true, organization_key: user.organization_key })
  }

  def mine?(user) = user_id == user.id

  # Specs only: rows are rebuilt on every run so a snippet never serves stale data.
  def self.artifact_definitions(artifacts)
    Array(artifacts).first(8).map do |artifact|
      artifact.to_h.stringify_keys.slice("key", "title", "kind", "spec", "x", "y", "series_by")
    end
  end

  def as_snippet_json(user)
    { id: id.to_s, title: title, question: question, report: report, artifacts: artifacts, shared: shared,
      mine: mine?(user), owner_name: owner_name, session_id: session_id&.to_s,
      created_at: created_at, updated_at: updated_at, last_run_at: last_run_at, run_count: run_count }
  end

  private

  def must_have_content
    errors.add(:base, "ไม่มีผลลัพธ์ให้บันทึก") if artifacts.blank? && report.blank?
  end
end
