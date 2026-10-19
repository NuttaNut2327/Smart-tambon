# Who did what in sensitive system-admin actions (approving registrations, switching into an อบต. account).
class AdminAuditLog
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  field :actor_id, type: Integer
  field :actor_username, type: String
  field :action, type: String
  field :target, type: String
  field :details, type: Hash, default: {}
  field :ip, type: String

  index({ created_at: -1 })
  index({ action: 1, created_at: -1 })

  def self.record!(actor, action, target, request: nil, **details)
    create!(actor_id: actor&.id, actor_username: actor&.username, action:, target: target.to_s, details:, ip: request&.remote_ip)
  rescue Mongo::Error => error
    Rails.logger.error("Audit log failed: #{error.class}: #{error.message}")
  end
end
