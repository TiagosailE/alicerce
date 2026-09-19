require "rails_helper"

RSpec.describe BrevoClient do
  around do |example|
    original_api_key = ENV["BREVO_API_KEY"]
    original_sender = ENV["BREVO_SENDER_EMAIL"]
    ENV["BREVO_API_KEY"] = "test-brevo-key"
    ENV["BREVO_SENDER_EMAIL"] = "alicerce@example.com"
    example.run
    ENV["BREVO_API_KEY"] = original_api_key
    ENV["BREVO_SENDER_EMAIL"] = original_sender
  end

  def stub_brevo_response(response)
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start)
      .with("api.brevo.com", 443, hash_including(use_ssl: true))
      .and_yield(http)
    allow(http).to receive(:request) { |request| @sent_request = request; response }
  end

  it "posts the transactional email payload to Brevo with the api-key header" do
    stub_brevo_response(Net::HTTPCreated.new("1.1", "201", "Created"))

    described_class.deliver(to: "pessoa@alicerce.example", to_name: "Pessoa", subject: "Assunto", html_content: "<p>Oi</p>")

    expect(@sent_request["api-key"]).to eq("test-brevo-key")
    expect(@sent_request.uri.to_s).to eq("https://api.brevo.com/v3/smtp/email")
    body = JSON.parse(@sent_request.body)
    expect(body).to eq(
      "sender" => { "email" => "alicerce@example.com", "name" => "Alicerce" },
      "to" => [ { "email" => "pessoa@alicerce.example", "name" => "Pessoa" } ],
      "subject" => "Assunto",
      "htmlContent" => "<p>Oi</p>"
    )
  end

  it "raises on a non-success response without including the response body in the message" do
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    allow(response).to receive(:body).and_return('{"code":"invalid_parameter","message":"pessoa@alicerce.example is not a valid recipient"}')
    stub_brevo_response(response)

    expect {
      described_class.deliver(to: "pessoa@alicerce.example", to_name: "Pessoa", subject: "Assunto", html_content: "<p>Oi</p>")
    }.to raise_error(BrevoClient::Error) { |error| expect(error.message).to eq("Brevo delivery failed: 400") }
  end
end
