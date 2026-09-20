module Identity
  # Pagination for the pending-invitations list (CONTRIBUTING.md: page,
  # per_page, default 25, max 100), newest offer first.
  class PendingInvitationsQuery
    include Pagination

    def results
      paginated(@scope.order(created_at: :desc, id: :desc))
    end
  end
end
