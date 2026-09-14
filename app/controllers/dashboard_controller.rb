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
