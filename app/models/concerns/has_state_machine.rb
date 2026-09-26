# Explicit transition tables on the model, enforced by the domain (ADR 0009).
#
#   class Order < ApplicationRecord
#     include HasStateMachine
#     TRANSITIONS = { "draft" => %w[approved cancelled], "approved" => [], "cancelled" => [] }.freeze
#   end
#
# The status column is a string with a CHECK listing the valid states; the
# table says which move between them. transition_to! is the only writer of an
# existing record's status: a change made any other way (`update!(status:)`)
# fails validation instead of skipping the table. A record may still be created
# in a given state, which is how a spec or a seed builds a document mid-life. A
# side effect never lives here: it belongs to the command that calls
# transition_to! inside its transaction, after its locks (ADR 0004).
module HasStateMachine
  extend ActiveSupport::Concern

  class InvalidTransition < StandardError
    attr_reader :from, :to

    def initialize(record, from, to)
      @from = from
      @to = to
      super("#{record.class.name} cannot go from #{from.inspect} to #{to.inspect}")
    end
  end

  included do
    validate :status_changes_only_through_a_transition, on: :update
  end

  # Where the record is according to the database, not to an unsaved assignment:
  # `order.status = "received"; order.transition_to!(:cancelled)` must be judged
  # from what is stored.
  def current_status = persisted? ? status_in_database : status

  def can_transition_to?(next_status)
    self.class::TRANSITIONS.fetch(current_status, []).include?(next_status.to_s)
  end

  def transition_to!(next_status, **attributes)
    next_status = next_status.to_s
    raise InvalidTransition.new(self, current_status, next_status) unless can_transition_to?(next_status)

    assign_attributes(attributes)
    @transitioning = true
    self.status = next_status
    save!
    self
  ensure
    @transitioning = false
  end

  private
    def status_changes_only_through_a_transition
      errors.add(:status, :changed_outside_a_transition, message: "can only change through a transition") if status_changed? && !@transitioning
    end
end
