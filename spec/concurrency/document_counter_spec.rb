require "rails_helper"

RSpec.describe "concurrent document numbers (ADR 0017)" do
  self.use_transactional_tests = false

  before do
    @organization = create(:organization)
    set_current_tenant(@organization)
  end

  after do
    set_current_tenant(@organization)
    DocumentCounter.delete_all
  end

  def run_concurrently(*jobs)
    barrier = Queue.new
    threads = jobs.map { |job| Thread.new { barrier.pop; job.call } }
    jobs.size.times { barrier << true }
    threads.map(&:value)
  end

  it "hands every one of four documents created at once a different number, with no gap" do
    numbers = run_concurrently(*Array.new(4) do
      lambda do
        set_current_tenant(@organization)
        ApplicationRecord.transaction do
          number = DocumentCounter.next!(organization: @organization, kind: "receipt")
          sleep 0.05 # the number is held until the document's transaction ends
          number
        end
      end
    end)

    expect(numbers.sort).to eq([ 1, 2, 3, 4 ])
  end

  it "returns the number of a document that failed, so the next one takes it" do
    results = run_concurrently(
      lambda do
        set_current_tenant(@organization)
        ApplicationRecord.transaction do
          DocumentCounter.next!(organization: @organization, kind: "receipt")
          raise ActiveRecord::Rollback
        end
        :rolled_back
      end
    )
    expect(results).to eq([ :rolled_back ])

    set_current_tenant(@organization)
    expect(DocumentCounter.next!(organization: @organization, kind: "receipt")).to eq(1)
  end
end
