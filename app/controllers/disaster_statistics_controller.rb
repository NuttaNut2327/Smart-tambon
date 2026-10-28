# Demo page for the DisasterEvent archive: statistics charts and the seasonal outlook, both read from /api/disaster_events.
class DisasterStatisticsController < ApplicationController
  def show
    @area_name = current_user.access_area&.name.presence || current_user.subdistrict&.name_th || "ประเทศไทย"
    @simulated = DisasterEvent.visible_to(current_user).where(simulated: true).exists?
  end
end
