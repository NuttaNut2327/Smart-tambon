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
