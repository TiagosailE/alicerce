module Identity
  # Pagination for the members list (CONTRIBUTING.md: page, per_page,
  # default 25, max 100). Ordered by name, not join order, since that is
  # what a person scanning the list for a name expects.
  class MembersQuery
    include Pagination

    def results
      paginated(@scope.joins(:user).order(identity_users: { name: :asc }, id: :asc))
    end
  end
end
