require "net/http"

# The only outbound HTTP call in the app: Brevo's transactional email HTTPS
# API, since Render's free tier blocks outbound SMTP ports (ADR 0002).
# HOST is a fixed constant, never built from input, so there is no user
# controlled destination for an allow list to guard against. Always called
# from a job, never inside a database transaction (CONTRIBUTING's security
# rules).
module BrevoClient
  HOST = "api.brevo.com"
  ENDPOINT = URI("https://#{HOST}/v3/smtp/email")
  TIMEOUT = 5 # seconds
  SENDER_NAME = "Alicerce"

  Error = Class.new(StandardError)

  module_function

  def deliver(to:, to_name:, subject:, html_content:)
    request = Net::HTTP::Post.new(ENDPOINT)
    request["api-key"] = ENV.fetch("BREVO_API_KEY")
    request["content-type"] = "application/json"
    request["accept"] = "application/json"
    request.body = {
      sender: { email: ENV.fetch("BREVO_SENDER_EMAIL"), name: SENDER_NAME },
      to: [ { email: to, name: to_name } ],
      subject:,
      htmlContent: html_content
    }.to_json

    response = Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end

    # response.body is never interpolated here: a validation error from
    # Brevo could echo back the recipient address or other request details,
    # and this message ends up in job failure logs and the
    # solid_queue_failed_executions table, outside this app's own log
    # filtering (docs/security.md: personal data filtered from logs).
    raise Error, "Brevo delivery failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response
  end
end
