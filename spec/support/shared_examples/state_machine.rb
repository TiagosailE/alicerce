# Every model with a TRANSITIONS table joins this (ADR 0009): each allowed
# transition succeeds and every other pair raises, from every state.
#
#   it_behaves_like "a state machine" do
#     let(:model_class) { Purchasing::Order } # defaults to described_class
#     def record_in(status) = create(:purchasing_order, status:)
#   end
RSpec.shared_examples "a state machine" do
  let(:model_class) { described_class }
  let(:transitions) { model_class::TRANSITIONS }
  let(:states) { (transitions.keys + transitions.values.flatten).uniq }

  it "lists every state it can reach as a state of its own" do
    expect(transitions.values.flatten - transitions.keys).to be_empty
  end

  it "allows exactly the transitions in the table" do
    states.each do |from|
      states.each do |to|
        record = record_in(from)
        allowed = transitions.fetch(from).include?(to)

        expect(record.can_transition_to?(to)).to eq(allowed), "#{from} -> #{to}: expected can_transition_to? to be #{allowed}"
        if allowed
          expect { record.transition_to!(to) }.not_to raise_error
          expect(record.reload.status).to eq(to)
        else
          expect { record.transition_to!(to) }.to raise_error(HasStateMachine::InvalidTransition)
          expect(record.reload.status).to eq(from)
        end
      end
    end
  end

  it "does not let update! skip the table" do
    record = record_in(states.first)

    expect { record.update!(status: states.last) }.to raise_error(ActiveRecord::RecordInvalid, /can only change through a transition/)
    expect(record.reload.status).to eq(states.first)
  end
end
