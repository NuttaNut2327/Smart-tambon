# Public self-registration wizard for local governments (/register). The application is kept server-side and found
# through a token in the session; each step validates and advances. After OTP verification it waits for approval.
class OrganizationRegistrationsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_access_configuration!
  before_action :require_registration_open
  before_action :load_registration, except: %i[start lookup check]
  layout "registration"

  MAX_STARTS_PER_IP_PER_HOUR = 10

  # GET /register — resume the applicant's draft or show the first step.
  def show
    return render(:submitted) if @registration&.status.in?(%w[pending_review approved rejected])

    @registration ||= OrganizationRegistration.new
    @step = params[:step].presence_in(OrganizationRegistration::STEPS) || @registration.step
    @step = @registration.step unless @registration.persisted? ? @registration.reached?(@step) : @step == "area"
  end

  # POST /register — step 1 creates the draft (rate-limited per IP).
  def start
    return redirect_to(organization_registration_path) if params[:website].present? # honeypot
    if OrganizationRegistration.where(ip: request.remote_ip, :created_at.gte => 1.hour.ago).count >= MAX_STARTS_PER_IP_PER_HOUR
      return redirect_to(organization_registration_path, alert: "มีการเริ่มลงทะเบียนจากเครือข่ายนี้บ่อยเกินไป กรุณาลองใหม่ภายหลัง")
    end

    @registration = OrganizationRegistration.new(ip: request.remote_ip, user_agent: request.user_agent.to_s.truncate(300))
    save_area
  end

  # PATCH /register — save the current step and move on.
  def update
    return redirect_to(organization_registration_path) unless @registration&.status == "draft"

    case params[:step]
    when "area" then save_area
    when "organization" then save_organization
    when "account" then save_account
    when "consent" then save_consent
    else redirect_to organization_registration_path
    end
  end

  def send_otp
    return redirect_to(organization_registration_path) unless @registration&.step == "verify"

    Registrations::Otp.new(@registration).deliver(params[:channel].to_s)
    redirect_to organization_registration_path(step: "verify"), notice: "ส่งรหัสยืนยันไปที่ #{@registration.reload.masked_otp_target} แล้ว"
  rescue Registrations::Otp::Error => error
    redirect_to organization_registration_path(step: "verify"), alert: error.message
  end

  def verify_otp
    return redirect_to(organization_registration_path) unless @registration&.step == "verify"

    Registrations::Otp.new(@registration).verify!(params[:code])
    # Final re-check: the area or identifiers may have been taken while the applicant was filling the form.
    problem = final_conflict
    return redirect_to(organization_registration_path(step: problem[:step]), alert: problem[:message]) if problem

    @registration.set(status: "pending_review", submitted_at: Time.current)
    redirect_to organization_registration_path
  rescue Registrations::Otp::Error => error
    redirect_to organization_registration_path(step: "verify"), alert: error.message
  end

  # Start over (clears the draft from this browser).
  def reset
    session.delete(:registration_token)
    redirect_to organization_registration_path
  end

  # GET /register/lookup?province_id= | ?district_code= — cascading area pickers with availability.
  def lookup
    if params[:district_code].present?
      areas = Subdistrict.where(district_code: params[:district_code].to_s).order(:name_th).select(:id, :name_th, :code)
      render json: areas.map { |area| { id: area.id, name: area.name_th, code: area.code, status: OrganizationRegistration.area_status(area.id) } }
    elsif params[:province_id].present?
      districts = Subdistrict.where(province_id: params[:province_id]).group(:district_code, :district_name_th).order(:district_name_th).pluck(:district_code, :district_name_th)
      render json: districts.map { |code, name| { code:, name: } }
    else
      render json: Province.alphabetical.map { |province| { id: province.id, name: province.name_th } }
    end
  end

  # GET /register/check?field=username&value= — live duplicate checks for the account step.
  def check
    token = session[:registration_token]
    except = token && OrganizationRegistration.where(token:).pick(:_id)
    error = case params[:field]
            when "username" then OrganizationRegistration.username_error(params[:value], except:)
            when "email" then OrganizationRegistration.email_error(params[:value], except:)
            when "phone" then OrganizationRegistration.phone_error(params[:value], except:)
            end
    render json: { ok: error.nil?, message: error || "ใช้ได้" }
  end

  private

  def require_registration_open
    return if SystemSetting.current.registration_enabled != false

    render :closed, status: :service_unavailable
  end

  def load_registration
    token = session[:registration_token]
    @registration = token && OrganizationRegistration.where(token:).first
  end

  def advance!(next_step)
    @registration.step = next_step if OrganizationRegistration::STEPS.index(next_step) > @registration.step_index
    @registration.save!
    session[:registration_token] = @registration.token
    redirect_to organization_registration_path(step: next_step)
  end

  def fail_step(step, message)
    @step = step
    @error = message
    render :show, status: :unprocessable_entity
  end

  def save_area
    subdistrict = Subdistrict.find_by(id: params[:subdistrict_id])
    return fail_step("area", "กรุณาเลือกตำบลของหน่วยงาน") unless subdistrict

    status = OrganizationRegistration.area_status(subdistrict.id, except: @registration.id)
    return fail_step("area", "ตำบล#{subdistrict.name_th} มีผู้ดูแลในระบบแล้ว หากต้องการเข้าร่วม โปรดติดต่อผู้ดูแลของหน่วยงานหรือผู้ดูแลระบบ") if status == "taken"
    return fail_step("area", "ตำบล#{subdistrict.name_th} มีคำขอลงทะเบียนที่รออนุมัติอยู่แล้ว") if status == "pending"

    @registration.subdistrict_id = subdistrict.id
    @registration.organization_name ||= "องค์การบริหารส่วนตำบล#{subdistrict.name_th}"
    advance!("organization")
  end

  def save_organization
    attrs = params.require(:registration).permit(:organization_type, :organization_name, :office_phone, :address)
    @registration.assign_attributes(attrs.to_h.transform_values { |value| value.to_s.strip.presence })
    return fail_step("organization", "กรุณาเลือกประเภทหน่วยงาน") unless UserAccessArea::ORGANIZATION_TYPES.key?(@registration.organization_type)
    return fail_step("organization", "กรุณากรอกชื่อหน่วยงาน") if @registration.organization_name.blank?

    advance!("account")
  end

  def save_account
    attrs = params.require(:registration).permit(:admin_full_name, :admin_position, :username, :email, :phone, :password, :password_confirmation)
    @registration.assign_attributes(admin_full_name: attrs[:admin_full_name].to_s.strip.presence, admin_position: attrs[:admin_position].to_s.strip.presence,
                                    username: attrs[:username].to_s.strip.downcase, email: attrs[:email].to_s.strip.downcase,
                                    phone: Sms::PhoneNumber.normalize(attrs[:phone]) || attrs[:phone].to_s.strip)
    return fail_step("account", "กรุณากรอกชื่อ-นามสกุลผู้ดูแล") if @registration.admin_full_name.blank?

    error = OrganizationRegistration.username_error(@registration.username, except: @registration.id) ||
            OrganizationRegistration.email_error(@registration.email, except: @registration.id) ||
            OrganizationRegistration.phone_error(@registration.phone, except: @registration.id)
    return fail_step("account", error) if error

    if attrs[:password].present? || @registration.password_digest.blank?
      error = OrganizationRegistration.password_error(attrs[:password], attrs[:password_confirmation])
      return fail_step("account", error) if error

      # Store only the Devise/bcrypt digest; the plain password never touches the database.
      @registration.password_digest = User.new(password: attrs[:password]).encrypted_password
    end
    # Changing contact details invalidates a previous OTP verification.
    @registration.verified_at = nil if @registration.email_changed? || @registration.phone_changed?
    advance!("consent")
  end

  def save_consent
    return fail_step("consent", "กรุณายอมรับข้อตกลงการใช้บริการและประกาศความเป็นส่วนตัว (PDPA)") unless params[:accept_terms] == "1" && params[:accept_pdpa] == "1"
    # The texts may have changed since the page was rendered; the applicant must accept the current wording.
    unless params[:terms_version] == RegistrationPolicy.terms_version && params[:pdpa_version] == RegistrationPolicy.pdpa_version
      return fail_step("consent", "ข้อตกลงมีการปรับปรุง กรุณาอ่านและยอมรับฉบับล่าสุดอีกครั้ง")
    end

    @registration.assign_attributes(terms_version: RegistrationPolicy.terms_version, pdpa_version: RegistrationPolicy.pdpa_version,
                                    consented_at: Time.current, marketing_consent: params[:marketing_consent] == "1", ip: request.remote_ip)
    advance!("verify")
  end

  def final_conflict
    status = OrganizationRegistration.area_status(@registration.subdistrict_id, except: @registration.id)
    return { step: "area", message: "ตำบลนี้มีผู้ดูแลหรือคำขอที่รออนุมัติแล้ว กรุณาตรวจสอบอีกครั้ง" } unless status == "available"

    error = OrganizationRegistration.username_error(@registration.username, except: @registration.id) ||
            OrganizationRegistration.email_error(@registration.email, except: @registration.id) ||
            OrganizationRegistration.phone_error(@registration.phone, except: @registration.id)
    error && { step: "account", message: error }
  end
end
