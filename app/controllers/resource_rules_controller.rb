class ResourceRulesController < ApplicationController
  def create
    rule = ResourceRule.new(user_id: current_user.id)
    assign_payload(rule)

    if rule.save
      render json: { id: rule.id.to_s, redirect_url: resource_rules_path }, status: :created
    else
      render json: { error: rule.errors.full_messages.join(" · ") }, status: :unprocessable_entity
    end
  rescue JSON::ParserError, ActionController::ParameterMissing => error
    render json: { error: "ข้อมูลกฎไม่ถูกต้อง: #{error.message}" }, status: :unprocessable_entity
  end

  def update
    rule = ResourceRule.visible_to(current_user).find(params[:id])
    assign_payload(rule)

    if rule.save
      render json: { id: rule.id.to_s, redirect_url: resource_rules_path }
    else
      render json: { error: rule.errors.full_messages.join(" · ") }, status: :unprocessable_entity
    end
  rescue Mongoid::Errors::DocumentNotFound
    render json: { error: "ไม่พบกฎที่ต้องการแก้ไข" }, status: :not_found
  rescue JSON::ParserError, ActionController::ParameterMissing => error
    render json: { error: "ข้อมูลกฎไม่ถูกต้อง: #{error.message}" }, status: :unprocessable_entity
  end

  private

  def assign_payload(rule)
    payload = JSON.parse(params.require(:resource_rule_payload))
    rule.assign_attributes(
      name: payload["name"], disaster_type: payload["disaster_type"],
      description: payload["description"], severity: payload["severity"],
      conditions: Array(payload["conditions"]), formulas: Array(payload["formulas"]),
      active: ActiveModel::Type::Boolean.new.cast(payload["active"])
    )
  end
end
