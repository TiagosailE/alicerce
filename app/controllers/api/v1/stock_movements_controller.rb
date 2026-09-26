module Api
  module V1
    class StockMovementsController < BaseController
      before_action :require_authentication!

      def index
        authorize(Inventory::Movement)
        value_visible = policy(Inventory::Balance).view_value?
        query = Inventory::MovementsQuery.new(
          policy_scope(Inventory::Movement), **pagination_params,
          warehouse_id: scalar_param(:warehouse_id), product_id: scalar_param(:product_id), reason: scalar_param(:reason)
        )
        render json: {
          data: query.results.map { |movement| Inventory::MovementSerializer.new(movement, value_visible:).as_json },
          meta: query.meta
        }
      end
    end
  end
end
