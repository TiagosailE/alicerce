require "rails_helper"

RSpec.describe Idempotency do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:key) { SecureRandom.uuid }

  before { set_current_tenant(organization) }

  def run(digest: "digest-a", key: self.key, on_replay: ->(record) { Result.success(record) }, &block)
    described_class.run(organization:, user:, key:, request_digest: digest, on_replay:, &block)
  end

  describe ".run" do
    it "runs the block for a new key and stores the outcome when the block completes it" do
      resource = create(:unit, organization:)

      result = run do |claim|
        claim.complete!(status: 201, resource:)
        Result.success(:done)
      end

      expect(result).to be_success
      stored = IdempotencyKey.sole
      expect(stored).to have_attributes(key:, response_status: 201, resource_type: "Catalog::Unit", resource_id: resource.id, user_id: user.id)
    end

    it "does not run the block again for a repeated request, and hands the stored record to on_replay" do
      resource = create(:unit, organization:)
      run { |claim| claim.complete!(status: 201, resource:) && Result.success(:first) }
      runs = 0

      result = run(on_replay: ->(record) { Result.success(record.resource_id) }) do |_claim|
        runs += 1
        Result.success(:second)
      end

      expect(runs).to eq(0)
      expect(result.value).to eq(resource.id)
    end

    it "rejects the same key for a different request" do
      resource = create(:unit, organization:)
      run { |claim| claim.complete!(status: 201, resource:) && Result.success(:first) }

      result = run(digest: "digest-b") { |_claim| Result.success(:second) }

      expect(result.error).to eq(:idempotency_key_reused)
    end

    it "keeps the same key apart for another user" do
      resource = create(:unit, organization:)
      run { |claim| claim.complete!(status: 201, resource:) && Result.success(:first) }
      other = described_class.run(organization:, user: create(:user), key:, request_digest: "digest-a", on_replay: ->(record) { Result.success(record) }) do |claim|
        claim.complete!(status: 201, resource:)
        Result.success(:other_user_runs)
      end

      expect(other.value).to eq(:other_user_runs)
    end

    it "raises when the block succeeds without completing its claim, since that would commit a key that replays as a 404" do
      expect { run { |_claim| Result.success(:forgot) } }.to raise_error(/never completed/)
    end

    it "does not care whether a failing block completed anything" do
      expect(run { |_claim| Result.failure(:nope) }.error).to eq(:nope)
    end
  end

  describe ".digest" do
    it "is the same for the same request whatever the order of the keys" do
      a = described_class.digest(method: "post", path: "/x", params: { "b" => 1, "a" => { "d" => 2, "c" => [ 3, { "f" => 4, "e" => 5 } ] } })
      b = described_class.digest(method: "POST", path: "/x", params: { "a" => { "c" => [ 3, { "e" => 5, "f" => 4 } ], "d" => 2 }, "b" => 1 })

      expect(a).to eq(b)
    end

    it "changes with the method, the path or any value" do
      base = described_class.digest(method: "POST", path: "/x", params: { "a" => 1 })

      expect(described_class.digest(method: "PUT", path: "/x", params: { "a" => 1 })).not_to eq(base)
      expect(described_class.digest(method: "POST", path: "/y", params: { "a" => 1 })).not_to eq(base)
      expect(described_class.digest(method: "POST", path: "/x", params: { "a" => 2 })).not_to eq(base)
    end
  end

  describe ".valid_key?" do
    it "accepts 8 to 100 characters of letters, digits and . _ : -" do
      expect(described_class.valid_key?(SecureRandom.uuid)).to be(true)
      expect(described_class.valid_key?("a" * 8)).to be(true)
      expect(described_class.valid_key?("a" * 100)).to be(true)
    end

    it "refuses anything else" do
      [ nil, "", "short", "a" * 101, "has space in it", "semi;colon-key", "new\nline-key" ].each do |bad|
        expect(described_class.valid_key?(bad)).to be(false), "expected #{bad.inspect} to be refused"
      end
    end
  end
end
