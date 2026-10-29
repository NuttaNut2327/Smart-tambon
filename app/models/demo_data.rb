# Demo (simulated) records stay in the database but are hidden from every list, map, chart and statistic
# while "show demo data" is switched off in system settings, so they never mix into real figures.
# The flag is read once per request.
class DemoData < ActiveSupport::CurrentAttributes
  KINDS = {
    "projects" => { model: "Project", label: "โครงการ", task: "projects:simulate" },
    "disaster_events" => { model: "DisasterEvent", label: "ประวัติภัยพิบัติ", task: "disasters:simulate" }
  }.freeze

  attribute :visible_flag

  def self.visible?
    self.visible_flag = SystemSetting.current.demo_data_visible != false if visible_flag.nil?
    visible_flag
  end

  # Applies the switch to a Mongoid criteria of a model that has a `simulated` field.
  def self.filter(criteria) = visible? ? criteria : criteria.where(:simulated.ne => true)

  def self.counts = KINDS.transform_values { |kind| kind[:model].constantize.where(simulated: true).count }

  def self.purge!(kind)
    model = KINDS.fetch(kind)[:model].constantize
    records = model.where(simulated: true)
    records.each { |project| ProjectPhotoUploadService.purge_for(project) } if model == Project
    records.delete_all
  end
end
