module Api
  module V1
    class WarehousesController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Inventory::Warehouse)
        query = Inventory::WarehousesQuery.new(policy_scope(Inventory::Warehouse), page: params[:page], per_page: params[:per_page])
        render json: { data: query.results.map { |warehouse| Inventory::WarehouseSerializer.new(warehouse).as_json }, meta: query.meta }
      end

      def show
        warehouse = find_warehouse
        authorize(warehouse)
        render json: { data: Inventory::WarehouseSerializer.new(warehouse).as_json }
      end

      def create
        authorize(Inventory::Warehouse)
        name = params.expect(:name)

        result = Inventory::CreateWarehouse.call(organization: Current.organization, name:, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Inventory::WarehouseSerializer.new(result.value).as_json }, status: :created
      end

      def update
        warehouse = find_warehouse
        authorize(warehouse)
        name, active = params.expect(:name, :active)

        result = Inventory::UpdateWarehouse.call(warehouse:, attributes: { name:, active: }, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Inventory::WarehouseSerializer.new(result.value).as_json }
      end

      private
        def find_warehouse
          Inventory::Warehouse.find(params[:id])
        end
    end
  end
end
