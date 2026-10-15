# Encrypted-at-rest string fields for Mongoid documents. `encrypted_secret :token` stores `token_ciphertext`
# and adds token / token? / masked_token / assign_token(value, clear:). Blank input keeps the stored value.
module EncryptedSecrets
  extend ActiveSupport::Concern

  class_methods do
    def encrypted_secret(name, purpose: "#{model_name.singular}-secrets")
      field :"#{name}_ciphertext", type: String

      define_method(name) { EncryptedSecrets.decrypt(self[:"#{name}_ciphertext"], purpose) }
      define_method(:"#{name}?") { self[:"#{name}_ciphertext"].present? }
      define_method(:"masked_#{name}") do
        value = public_send(name)
        value.present? ? "••••••#{value.last(4)}" : nil
      end
      define_method(:"assign_#{name}") do |value, clear: false|
        next self[:"#{name}_ciphertext"] = nil if clear
        next if value.blank?

        self[:"#{name}_ciphertext"] = EncryptedSecrets.encryptor(purpose).encrypt_and_sign(value.to_s.strip)
      end
    end
  end

  def self.encryptor(purpose)
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(purpose, 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def self.decrypt(ciphertext, purpose)
    ciphertext.present? ? encryptor(purpose).decrypt_and_verify(ciphertext) : nil
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
