# frozen_string_literal: true

class GithubWebhookSignatureService
  class << self
    def valid_signature?(signature_header, payload_body, secret: nil)
      return false unless signature_header.present?

      secret_to_use = secret || ENV["GITHUB_WEBHOOK_SECRET"]
      return false unless secret_to_use.present?

      # GitHub sends signature as "sha256=<hash>"
      expected_signature = signature_header.split("=", 2).last
      computed_signature = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha256"),
        secret_to_use,
        payload_body
      )

      ActiveSupport::SecurityUtils.secure_compare(computed_signature, expected_signature)
    end
  end
end
