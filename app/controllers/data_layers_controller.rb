require "csv"

class DataLayersController < ApplicationController
  def show
    @can_upload = current_user.system_admin? || current_user.subdistrict_admin?
    @imported_datasets = ImportedDataset.visible_to(current_user).order_by(updated_at: :desc).to_a
    visible_system_types = %w[population resources workforce agencies]
    @selected_type = visible_system_types.include?(params[:data_type]) ? params[:data_type] : "population"
    @selected_schema = ImportedDataset.schema_for(@selected_type)
    @selected_datasets = @imported_datasets.select { |dataset| dataset.data_type == @selected_type }
    all_fixed_records = @selected_datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).each_with_index.map do |source_record, position|
        record = source_record.deep_dup
        @selected_schema.select { |field| field["type"] == "integer" }.each do |field|
          record[field["key"]] = record[field["key"]].to_i if record[field["key"]].present?
        end
        { dataset: dataset, record: record, position: position,
          editable: current_user.system_admin? || dataset.user_id == current_user.id }
      end
    end
    @fixed_record_total = all_fixed_records.size
    @fixed_page_size = 10
    @fixed_total_pages = [(@fixed_record_total.to_f / @fixed_page_size).ceil, 1].max
    @fixed_page = params[:page].to_i
    @fixed_page = 1 if @fixed_page < 1
    @fixed_page = @fixed_total_pages if @fixed_page > @fixed_total_pages
    @fixed_records = all_fixed_records.slice((@fixed_page - 1) * @fixed_page_size, @fixed_page_size) || []
    @editable_datasets = current_user.system_admin? ? @selected_datasets : @selected_datasets.select { |dataset| dataset.user_id == current_user.id }
    @dataset_summaries = @selected_datasets.map do |dataset|
      { dataset: dataset, current_version: dataset.current_version }
    end
    @version_history = @selected_datasets.flat_map do |dataset|
      dataset.versions.desc(:version_number).to_a.map { |version| { dataset: dataset, version: version } }
    end.sort_by { |item| item[:version].created_at }.reverse
    @subdistricts = if current_user.system_admin?
      Subdistrict.includes(:province).alphabetical
    else
      Subdistrict.where(id: current_user.accessible_subdistrict_ids).includes(:province).alphabetical
    end
    @area_label = if current_user.access_area&.name.present?
                    current_user.access_area.name
                  elsif current_user.subdistrict
                    "#{current_user.subdistrict.name_th}, #{current_user.subdistrict.province.name_th}"
                  else
                    "ทุกพื้นที่"
                  end
    if params[:data_type] == "file_library"
      @file_versions = @imported_datasets.flat_map do |dataset|
        dataset.versions.desc(:created_at).to_a.filter_map do |version|
          { dataset: dataset, version: version } if version.downloadable?
        end
      end.sort_by { |item| item[:version].created_at }.reverse
      render :file_library
    end
  end


  def template
    type = params[:data_type].to_s
    schema = ImportedDataset.schema_for(type)
    return head :not_found unless schema

    input_schema = schema.reject { |field| field["generated"] }
    csv = CSV.generate(write_headers: true, headers: input_schema.map { |field| field["label"] }) { |output| output << input_schema.map { nil } }
    send_data "\uFEFF#{csv}", filename: "#{type}_template.csv", type: "text/csv; charset=utf-8"
  end
end
