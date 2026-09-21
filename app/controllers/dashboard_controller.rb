class DashboardController < ApplicationController
  def index
    @page_mode = :overview
    load_area_context
  end

  def map
    redirect_to area_analysis_path
  end

  def area_analysis
    @page_mode = :analysis
    load_area_context
    render :index
  end

  def disasters
    @page_mode = :disasters
    load_area_context
    @incident_category = params[:category].presence_in(Incident::CATEGORIES)
    all_incidents = Incident.visible_to(current_user).desc(:created_at).to_a
    @incident_summary = {
      total: all_incidents.size,
      pending: all_incidents.count { |incident| incident.status == "pending" },
      in_progress: all_incidents.count { |incident| %w[assessing in_progress].include?(incident.status) },
      completed: all_incidents.count { |incident| incident.status == "completed" }
    }
    category_incidents = if @incident_category
      all_incidents.select { |incident| incident.category == @incident_category }
    else
      all_incidents
    end
    @incident_status_counts = {
      all: category_incidents.size,
      pending: category_incidents.count { |incident| incident.status == "pending" },
      in_progress: category_incidents.count { |incident| %w[assessing in_progress].include?(incident.status) },
      completed: category_incidents.count { |incident| incident.status == "completed" }
    }
    @incidents = category_incidents
    workforce_datasets = ImportedDataset.visible_to(current_user).where(data_type: "workforce").to_a
    @incident_team_options = workforce_datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map { |record| record["team_name"].presence || record["name"].presence }
    end.uniq.sort
    @incident_usage_options = IncidentUsageCatalog.for(current_user)
    @selected_incident = @incidents.find { |incident| incident.id.to_s == params[:incident_id] } || @incidents.first
    requested_version = params[:plan_version].to_i
    @selected_plan = if @selected_incident
      @selected_incident.response_plan_versions.find { |version| version["version"].to_i == requested_version } ||
        @selected_incident.active_plan || @selected_incident.response_plan_versions.max_by { |version| version["version"].to_i }
    end
    render :index
  end

  def resource_rules
    load_area_context
    @resource_rules = ResourceRule.visible_to(current_user).desc(:created_at).to_a
    datasets = ImportedDataset.visible_to(current_user).where(:data_type.in => %w[resources workforce]).to_a
    @rule_resource_options = datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).filter_map do |record|
        label = record["name"].presence || record["team_name"].presence
        next if label.blank?

        { label: label, source_type: dataset.data_type }
      end
    end.uniq { |item| [item[:label], item[:source_type]] }
  end

  private

  def load_area_context
    @assigned_subdistrict = current_user.subdistrict unless system_admin?
    @provinces = if global_viewer?
      Province.alphabetical
    elsif @assigned_subdistrict
      [@assigned_subdistrict.province]
    else
      []
    end
  end
end
