module Ai
  # Kept results. Re-running executes the stored query specs with the viewer's own scope.
  class SnippetsController < BaseController
    before_action :set_snippet, only: %i[update destroy run summarize]
    before_action :require_owner!, only: %i[update destroy]

    def index
      render json: AiSnippet.visible_to(current_user).desc(:updated_at).limit(200).map { |snippet| snippet.as_snippet_json(current_user) }
    end

    # Keeps an assistant answer (its report and charts), or a single chart when artifact_key is given.
    def create
      session = find_session(params[:session_id])
      message = session.messages.where(role: "assistant").find(params[:message_id])
      question = session.messages.where(role: "user", seq: message.seq - 1).first&.content
      artifacts = message.artifacts
      artifacts = artifacts.select { |artifact| artifact["key"].to_s == params[:artifact_key].to_s } if params[:artifact_key].present?
      single = params[:artifact_key].present?
      title = params[:title].to_s.strip.presence || (single ? artifacts.first&.dig("title") : nil) || question.to_s.lines.first.to_s.strip
      snippet = AiSnippet.new(
        user_id: current_user.id, owner_name: current_user.username, organization_key: current_user.organization_key,
        session_id: session.id, title: title.truncate(100), question: question,
        report: single ? "[[artifact:#{artifacts.first&.dig('key')}]]" : message.content,
        artifacts: AiSnippet.artifact_definitions(artifacts), last_run_at: message.created_at
      )
      return render_error(snippet.errors.full_messages.to_sentence) unless snippet.save

      render json: snippet.as_snippet_json(current_user), status: :created
    end

    def update
      @snippet.title = params[:title].to_s.strip.truncate(100) if params[:title].present?
      @snippet.shared = ActiveModel::Type::Boolean.new.cast(params[:shared]) if params.key?(:shared)
      @snippet.report = params[:report].to_s if params.key?(:report)
      return render_error(@snippet.errors.full_messages.to_sentence) unless @snippet.save

      render json: @snippet.as_snippet_json(current_user)
    end

    def destroy
      @snippet.destroy
      head :no_content
    end

    def run
      artifacts = Agent.new(user: current_user, provider: nil).run_artifacts(@snippet.artifacts, params: period_params)
      if @snippet.mine?(current_user)
        @snippet.set(last_run_at: Time.current)
        @snippet.inc(run_count: 1)
      end
      render json: { id: @snippet.id.to_s, artifacts: artifacts, ran_at: Time.current, period: period_params }
    end

    # Rewrites the report over freshly re-run data; saved back only for the owner.
    def summarize
      provider = AiProvider.enabled.where(id: params[:ai_provider_id]).first || AiProvider.default_for_chat
      agent = Agent.new(user: current_user, provider: provider)
      artifacts = agent.run_artifacts(@snippet.artifacts, params: period_params)
      report = agent.summarize(question: @snippet.question, report: @snippet.report, artifacts: artifacts)
      @snippet.update(report: report) if @snippet.mine?(current_user) && params[:save] != "0"
      render json: { report: report, artifacts: artifacts }
    rescue Llm::Error => error
      render_error(error.message, status: :bad_gateway)
    end

    private

    def set_snippet = @snippet = AiSnippet.visible_to(current_user).find(params[:id])

    def require_owner!
      render_error("แก้ไขได้เฉพาะเจ้าของรายการ", status: :forbidden) unless @snippet.mine?(current_user)
    end

    def period_params = params.permit(:from, :to).to_h.compact_blank
  end
end
