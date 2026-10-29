# Decides which announcements a signed-in user sees on this page view.
# Per-session state lives in the Rails session, which Devise resets on sign-out,
# so "always" announcements come back on every login.
class AnnouncementFeed
  SEEN_KEY = :announcement_seen_ids
  DISMISSED_KEY = :announcement_dismissed_ids

  def initialize(user, session, except: [])
    @user = user
    @session = session
    @except = Array(except).map(&:to_s)
  end

  def visible
    @visible ||= begin
      announcements = Announcement.for_user(@user).reject { |announcement| @except.include?(announcement.id.to_s) }
      receipts = AnnouncementReceipt.where(user_id: @user.id, :announcement_id.in => announcements.map(&:id)).index_by(&:announcement_id)
      announcements.select { |announcement| visible?(announcement, receipts[announcement.id]) }.each do |announcement|
        AnnouncementReceipt.for(announcement, @user) unless receipts[announcement.id]
        remember(SEEN_KEY, announcement)
      end
    end
  end

  def modals = visible.reject(&:corner?)
  def corners = visible.select(&:corner?)

  def acknowledge!(announcement)
    receipt = AnnouncementReceipt.for(announcement, @user)
    receipt.update!(acknowledged_at: Time.current) unless receipt.acknowledged_at
    remember(DISMISSED_KEY, announcement)
  end

  private

  def visible?(announcement, receipt)
    if announcement.corner?
      # Corner boxes cannot be closed; "once" limits them to the first session they appeared in.
      !announcement.once? || receipt.nil? || session_ids(SEEN_KEY).include?(announcement.id.to_s)
    elsif announcement.once?
      receipt&.acknowledged_at.nil?
    else
      !session_ids(DISMISSED_KEY).include?(announcement.id.to_s)
    end
  end

  def session_ids(key) = Array(@session[key])

  def remember(key, announcement)
    @session[key] = (session_ids(key) | [announcement.id.to_s]).last(50)
  end
end
