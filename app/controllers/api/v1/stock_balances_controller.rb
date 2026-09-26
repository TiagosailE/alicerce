module Api
  module V1
    class StockBalancesController < BaseController
      before_action :require_authentication!

      def index
        authorize(Inventory::Balance)
        query = Inventory::BalancesQuery.new(
          policy_scope(Inventory::Balance), **pagination_params,
          warehouse_id: scalar_param(:warehouse_id), product_id: scalar_param(:product_id), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |balance| Inventory::BalanceSerializer.new(balance).as_json }, meta: query.meta }
      end
    end
  end
end
