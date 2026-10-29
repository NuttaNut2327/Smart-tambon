module Admin
  class WebhooksController < BaseController
    PER_PAGE = 50

    def index
      @query = params[:q].to_s.strip
      @event_type = params[:event_type].to_s.strip
      @page = [params[:page].to_i, 1].max
      scope = LineWebhookLog.newest_first
      scope = scope.where(event_types: @event_type) if @event_type.present?
      if @query.present?
        pattern = /#{Regexp.escape(@query)}/i
        scope = scope.any_of({ group_ids: pattern }, { destination: pattern }, { request_id: pattern })
      end
      @total = scope.count
      @logs = scope.skip((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      @total_pages = [(@total.to_f / PER_PAGE).ceil, 1].max
    end
  end
end
