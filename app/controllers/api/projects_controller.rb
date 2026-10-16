module Api
  class ProjectsController < ApplicationController
    def index
      projects = Project.visible_to(current_user)
      projects = projects.where(fiscal_year: params[:fiscal_year].to_i) if params[:fiscal_year].present?
      photo_url = ->(project, photo) { photo_project_path(project, photo["id"]) }
      render json: projects.order_by(fiscal_year: :desc, name: :asc).map { |project| project.as_map_json(photo_url:) }
    end
  end
end
