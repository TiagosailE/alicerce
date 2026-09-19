require "rails_helper"

RSpec.describe "JSON decoding" do
  it "works through ActiveSupport, which Solid Queue and JSON request bodies depend on" do
    expect(ActiveSupport::JSON.decode('{"total_cents":125000}')).to eq("total_cents" => 125_000)
  end
end
