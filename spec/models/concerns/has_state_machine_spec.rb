require "rails_helper"

RSpec.describe HasStateMachine do
  # A throwaway table and model: the concern is proven on its own here, and each
  # document model then joins the shared examples with its real table.
  before do
    ActiveRecord::Base.connection.create_table(:state_machine_probes, temporary: true) do |t|
      t.string :status, null: false, default: "draft"
      t.string :note
    end
    probe = Class.new(ApplicationRecord) do
      self.table_name = "state_machine_probes"
      include HasStateMachine
    end
    probe.const_set(:TRANSITIONS, { "draft" => %w[approved cancelled], "approved" => %w[done cancelled], "done" => [], "cancelled" => [] }.freeze)
    stub_const("StateMachineProbe", probe)
  end

  it_behaves_like "a state machine" do
    let(:model_class) { StateMachineProbe }

    def record_in(status) = StateMachineProbe.create!(status:)
  end

  it "writes extra attributes together with the transition" do
    probe = StateMachineProbe.create!

    probe.transition_to!(:approved, note: "ok")

    expect(probe.reload).to have_attributes(status: "approved", note: "ok")
  end

  it "changes nothing when the transition is refused" do
    probe = StateMachineProbe.create!

    expect { probe.transition_to!(:done, note: "skipped") }.to raise_error(HasStateMachine::InvalidTransition, /"draft" to "done"/)
    expect(probe.reload).to have_attributes(status: "draft", note: nil)
  end
end
