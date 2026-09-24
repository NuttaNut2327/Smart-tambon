require "csv"
require "digest"

class DataLayersController < ApplicationController
  before_action :require_importer!, only: :link_village_boundaries

  def show
    @can_upload = current_user.system_admin? || current_user.subdistrict_admin?
    @imported_datasets = ImportedDataset.visible_to(current_user).order_by(updated_at: :desc).to_a
    visible_system_types = %w[population village_boundaries resources consumables workforce teams agencies]
    @selected_type = visible_system_types.include?(params[:data_type]) ? params[:data_type] : "population"
    @form_schema = ImportedDataset.schema_for(@selected_type)
    @selected_schema = @form_schema.reject { |field| field["hidden"] }
    @selected_datasets = @imported_datasets.select { |dataset| dataset.data_type == @selected_type }
    active_assignment_keys = Incident.visible_to(current_user).where(:status.ne => "completed").pluck(:active_assignments)
      .flatten.compact.select { |assignment| assignment["released_at"].blank? }.map { |assignment| assignment["key"] }.to_set
    all_fixed_records = @selected_datasets.flat_map do |dataset|
      Array(dataset.current_version&.records).each_with_index.map do |source_record, position|
        record = source_record.deep_dup
        if @selected_type == "resources" && record["code"].present?
          key = Digest::SHA256.hexdigest(["resource", dataset.id.to_s, record["code"]].join("\0"))[0, 20]
          record["status"] = "กำลังใช้งาน" if active_assignment_keys.include?(key)
        elsif @selected_type == "workforce" && record["personnel_code"].present?
          key = Digest::SHA256.hexdigest(["workforce", dataset.id.to_s, record["personnel_code"]].join("\0"))[0, 20]
          record["availability_status"] = "กำลังปฏิบัติงาน" if active_assignment_keys.include?(key)
        end
        if @selected_type == "village_boundaries" && record["boundary_source"].blank?
          record["boundary_source"] = dataset.current_version&.source_kind == "file" ? "อัปโหลดไฟล์" : "วาดขอบเขตเอง"
        end
        @selected_schema.select { |field| field["type"] == "integer" }.each do |field|
          record[field["key"]] = record[field["key"]].to_i if record[field["key"]].present?
        end
        can_edit = current_user.system_admin? || dataset.user_id == current_user.id ||
          (current_user.subdistrict_admin? && current_user.accessible_subdistrict_ids.include?(dataset.subdistrict_id))
        { dataset: dataset, record: record, position: position, editable: can_edit }
      end
    end
    @fixed_record_total = all_fixed_records.size
    @fixed_page_size = 10
    @fixed_total_pages = [(@fixed_record_total.to_f / @fixed_page_size).ceil, 1].max
    @fixed_page = params[:page].to_i
    @fixed_page = 1 if @fixed_page < 1
    @fixed_page = @fixed_total_pages if @fixed_page > @fixed_total_pages
    @fixed_records = all_fixed_records.slice((@fixed_page - 1) * @fixed_page_size, @fixed_page_size) || []
    @editable_datasets = @selected_datasets.select do |dataset|
      current_user.system_admin? || dataset.user_id == current_user.id ||
        (current_user.subdistrict_admin? && current_user.accessible_subdistrict_ids.include?(dataset.subdistrict_id))
    end
    @population_datasets = @imported_datasets.select { |dataset| dataset.data_type == "population" }
    @boundary_datasets = @imported_datasets.select { |dataset| dataset.data_type == "village_boundaries" }
    @agency_options = @imported_datasets.select { |dataset| dataset.data_type == "agencies" }
      .flat_map { |dataset| Array(dataset.current_version&.records) }
      .filter_map { |record| [record["agency_name"].to_s.strip, record["agency_code"].to_s.strip] if record["agency_name"].present? }
      .uniq.sort_by(&:first)
    @team_options = @imported_datasets.select { |dataset| dataset.data_type == "teams" }
      .flat_map { |dataset| Array(dataset.current_version&.records) }
      .filter_map { |record| [record["team_name"].to_s.strip, record["team_code"].to_s.strip] if record["team_name"].present? }
      .uniq.sort_by(&:first)
    if %w[population village_boundaries].include?(@selected_type)
      population_records = @population_datasets.flat_map { |dataset| Array(dataset.current_version&.records) }
      @linked_population_count = population_records.count { |record| record["boundary_status"] == "เชื่อมแล้ว" }
      @unlinked_population_count = population_records.size - @linked_population_count
    end
    @dataset_summaries = @selected_datasets.map do |dataset|
      { dataset: dataset, current_version: dataset.current_version }
    end
    @current_dataset_summary = @dataset_summaries.max_by do |item|
      [item[:current_version]&.record_count.to_i, item[:current_version]&.created_at || Time.at(0)]
    end
    if @selected_type == "consumables"
      @consumable_movements = ConsumableMovement.where(:imported_dataset_id.in => @selected_datasets.map(&:id))
        .desc(:created_at).limit(100).to_a
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

  def link_village_boundaries
    scope = ImportedDataset.visible_to(current_user)
    population = scope.where(id: params[:population_dataset_id], data_type: "population").first
    boundary = ImportedDataset.visible_to(current_user).where(id: params[:boundary_dataset_id], data_type: "village_boundaries").first
    raise ArgumentError, "ไม่พบชุดข้อมูลประชากรหรือขอบเขตหมู่บ้านที่เลือก" unless population && boundary

    result = VillageBoundaryLinkService.new(population_dataset: population, boundary_dataset: boundary, user: current_user).link!
    redirect_to data_layers_path(data_type: "village_boundaries"), notice: "เชื่อมขอบเขตสำเร็จ #{result[:matched]} รายการ · ต้องตรวจสอบ #{result[:suggested]} รายการ · ยังไม่พบ #{result[:unmatched]} รายการ"
  rescue ArgumentError, Mongoid::Errors::Validations => error
    redirect_to data_layers_path(data_type: "village_boundaries"), alert: error.message
  end

  def population_villages
    villages = ImportedDataset.visible_to(current_user).where(data_type: "population").flat_map do |dataset|
      Array(dataset.current_version&.records).map do |record|
        record.slice("subdistrict_code", "subdistrict", "village_code", "village_number", "village_name")
      end
    end
    villages = villages.reject { |record| record["village_number"].blank? && record["village_name"].blank? }
      .uniq { |record| [record["subdistrict_code"].presence || record["subdistrict"], record["village_code"].presence || record["village_number"]] }
      .sort_by { |record| [record["subdistrict"].to_s, record["village_number"].to_i, record["village_name"].to_s] }
    render json: { villages: villages }
  end


  def template
    type = params[:data_type].to_s
    schema = ImportedDataset.schema_for(type)
    return head :not_found unless schema

    input_schema = schema.reject { |field| field["generated"] }
    csv = CSV.generate(write_headers: true, headers: input_schema.map { |field| field["label"] }) { |output| output << input_schema.map { nil } }
    send_data "\uFEFF#{csv}", filename: "#{type}_template.csv", type: "text/csv; charset=utf-8"
  end

  private

  def require_importer!
    return if current_user.system_admin? || current_user.subdistrict_admin?
    redirect_to data_layers_path, alert: "บัญชีนี้ไม่มีสิทธิ์แก้ไขข้อมูล"
  end
end
