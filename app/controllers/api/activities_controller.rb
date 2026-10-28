module Api
  class ActivitiesController < ApplicationController
    def index
      Incident.finish_expired_activities!
      scope = Incident.visible_to(current_user).activities.where(:latitude.ne => nil, :longitude.ne => nil)
      scope = scope.where(:status.ne => "completed") unless params[:include_finished] == "1"
      render json: scope.asc(:starts_at).map { |activity| activity_json(activity) }
    end

    private

    def activity_json(activity)
      cover = activity.cover_photo
      {
        id: activity.id.to_s, reference_code: activity.reference_code, title: activity.title,
        activity_type: activity.incident_type, activity_type_label: activity.activity_type_label, icon: activity.activity_icon,
        phase: activity.activity_phase, phase_label: activity.activity_phase_label,
        status: activity.status, status_label: activity.activity_status_label,
        starts_at: activity.starts_at&.iso8601, ends_at: activity.ends_at&.iso8601,
        location_name: activity.location_name, organizer: activity.organizer, expected_attendees: activity.expected_attendees,
        description: activity.description.to_s.truncate(240),
        latitude: activity.latitude, longitude: activity.longitude,
        cover_url: cover && incident_photo_path(activity, cover["id"], variant: "thumb"),
        url: activities_path(filter: activity.status == "completed" ? "finished" : "current", anchor: "activity-#{activity.id}")
      }
    end
  end
end
