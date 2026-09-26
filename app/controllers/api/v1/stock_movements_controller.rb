module Api
  module V1
    class StockMovementsController < BaseController
      before_action :require_authentication!

      def index
        authorize(Inventory::Movement)
        query = Inventory::MovementsQuery.new(
          policy_scope(Inventory::Movement), **pagination_params,
          warehouse_id: scalar_param(:warehouse_id), product_id: scalar_param(:product_id), reason: scalar_param(:reason)
        )
        receipt_visible = Identity::Capabilities.view_purchasing?(Current.user&.membership_in(Current.organization))
        render json: {
          data: query.results.map { |movement| Inventory::MovementSerializer.new(movement, receipt_visible:).as_json },
          meta: query.meta
        }
      end
    end
  end
end
