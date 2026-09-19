require "rails_helper"

RSpec.describe RouteInventory do
  describe ".entry_for" do
    it "keys a route by its controller and action" do
      route = instance_double(ActionDispatch::Journey::Route, defaults: { controller: "api/v1/widgets", action: "show" })

      expect(described_class.entry_for(route)).to eq(controller: "api/v1/widgets", action: "show", key: "api/v1/widgets#show")
    end

    it "ignores routes outside /api/v1" do
      route = instance_double(ActionDispatch::Journey::Route, defaults: { controller: "spa", action: "show" })

      expect(described_class.entry_for(route)).to be_nil
    end
  end

  describe ".missing_from" do
    let(:route) { { controller: "api/v1/widgets", action: "index", key: "api/v1/widgets#index" } }

    before { allow(described_class).to receive(:api_v1_routes).and_return([ route ]) }

    it "flags a route that is in neither the matrix nor the exempt list" do
      expect(described_class.missing_from({})).to eq([ route ])
    end

    it "accepts a route the matrix has an entry for" do
      expect(described_class.missing_from({ "api/v1/widgets#index" => :anything })).to be_empty
    end

    it "accepts a route that is explicitly exempt" do
      expect(described_class.missing_from({}, exempt: [ "api/v1/widgets#index" ])).to be_empty
    end
  end
end
