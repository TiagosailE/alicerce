# A uniqueness validation checks with a SELECT, which two concurrent requests
# can both pass before either INSERT commits; the loser then hits the unique
# index itself. Writes run in a savepoint so that failure cannot poison an
# enclosing transaction, and validating again afterwards lets the same
# validator report the winner's row as an ordinary :taken error, in the shape
# every other validation failure has, instead of an unhandled 500. When
# validation still passes (the winner rolled back, or the index has no
# validator behind it) the violation is unexpected and is raised as before.
# save! covers create! and update! too.
module RaceSafeUniqueness
  extend ActiveSupport::Concern

  def save(*, **, &)
    in_savepoint { super }
  rescue ActiveRecord::RecordNotUnique => error
    raise error if valid?

    false
  end

  def save!(*, **, &)
    in_savepoint { super }
  rescue ActiveRecord::RecordNotUnique => error
    raise error if valid?

    raise ActiveRecord::RecordInvalid, self
  end

  private

  def in_savepoint(&) = self.class.transaction(requires_new: true, &)
end
