# Lists routes under /api/v1 so a spec can fail the moment one has no entry
# in a matrix (the isolation matrix, the role matrix), instead of an
# endpoint quietly shipping without the coverage CONTRIBUTING.md requires.
module RouteInventory
  module_function

  def api_v1_routes
    Rails.application.routes.routes.filter_map { |route| entry_for(route) }
  end

  def entry_for(route)
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    return unless controller&.start_with?("api/v1/") && action

    { controller:, action:, key: "#{controller}##{action}" }
  end

  def missing_from(matrix, exempt: [])
    api_v1_routes.reject { |route| exempt.include?(route[:key]) || matrix.key?(route[:key]) }
  end
end
