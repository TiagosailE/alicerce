module Api
  module V1
    class ProductsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Catalog::Product)
        query = Catalog::ProductsQuery.new(
          policy_scope(Catalog::Product),
          **pagination_params,
          category_id: scalar_param(:category_id), active: scalar_param(:active), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |product| Catalog::ProductSerializer.new(product).as_json }, meta: query.meta }
      end

      def show
        product = find_product
        authorize(product)
        render json: { data: Catalog::ProductSerializer.new(product).as_json }
      end

      def create
        authorize(Catalog::Product)
        sku, name, stock_unit_id, purchase_unit_id, factor = params.expect(:sku, :name, :stock_unit_id, :purchase_unit_id, :factor)

        result = Catalog::CreateProduct.call(
          organization: Current.organization, sku:, name:, category_id: params[:category_id].presence,
          stock_unit_id:, purchase_unit_id:, factor:, actor: Current.user
        )
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::ProductSerializer.new(result.value).as_json }, status: :created
      end

      def update
        product = find_product
        authorize(product)
        sku, name, stock_unit_id, purchase_unit_id, factor, active =
          params.expect(:sku, :name, :stock_unit_id, :purchase_unit_id, :factor, :active)

        result = Catalog::UpdateProduct.call(
          product:,
          attributes: { sku:, name:, category_id: params[:category_id].presence, stock_unit_id:, active: },
          conversion_attributes: { purchase_unit_id:, factor: },
          actor: Current.user
        )
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::ProductSerializer.new(result.value).as_json }
      end

      private
        def find_product
          Catalog::Product.find(params[:id])
        end
    end
  end
end
