require "rails_helper"

RSpec.describe "Health check" do
  it "reports the application as up" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end
end
