module Sms
  # Thai mobile numbers in the 08xxxxxxxx form smsmkt expects. Accepts dashes, spaces, dots, brackets and
  # +66 / 66 / 0066 prefixes; anything that is not a 10-digit 06/08/09 mobile number is rejected.
  module PhoneNumber
    MOBILE = /\A0[689]\d{8}\z/

    def self.normalize(raw)
      digits = raw.to_s.gsub(/[^\d+]/, "")
      digits = digits.sub(/\A(\+66|0066|66)(?=\d{9}\z)/, "0")
      digits = digits.delete("+")
      digits.match?(MOBILE) ? digits : nil
    end

    def self.valid?(raw) = normalize(raw).present?
  end
end
