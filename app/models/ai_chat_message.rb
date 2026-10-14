# A visible turn in an AI chat. An assistant turn keeps:
# - content: the Markdown answer, with [[artifact:N]] markers where a chart/table belongs
# - artifacts: [{ key, title, kind, spec, x, y, series_by, rows, total }] built by the show_chart tool
# - queries: every query_data call made while answering, for the "based on N queries" panel
# - transcript: the provider-level exchange (tool calls and results) replayed as history on later turns.
#   For Claude this holds the raw content blocks, including thinking blocks, so history stays append-only.
class AiChatMessage
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  belongs_to :session, class_name: "AiChatSession", inverse_of: :messages

  field :seq, type: Integer
  field :role, type: String
  field :content, type: String, default: ""
  field :artifacts, type: Array, default: []
  field :queries, type: Array, default: []
  field :transcript, type: Array, default: []
  field :api_format, type: String
  field :model, type: String
  field :error, type: String
  field :usage, type: Hash, default: {}

  index({ session_id: 1, seq: 1 }, unique: true)

  validates :role, inclusion: { in: %w[user assistant] }

  def as_chat_json
    { id: id.to_s, seq: seq, role: role, content: content, artifacts: artifacts, error: error, model: model,
      queries: queries.map { |query| query.slice("name", "spec", "total", "error") }, created_at: created_at }
  end
end
