# Base for every policy (ADR 0008): denies an action unless the subclass
# overrides it. A policy only ever sees records already scoped to the
# current organization (ADR 0003); it never re-checks tenancy.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  %i[index? show? create? update? destroy?].each do |action|
    define_method(action) { false }
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end
  end
end
