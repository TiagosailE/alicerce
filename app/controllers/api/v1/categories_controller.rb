module Api
  module V1
    class CategoriesController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Catalog::Category)
        query = Catalog::CategoriesQuery.new(policy_scope(Catalog::Category), page: params[:page], per_page: params[:per_page])
        render json: { data: query.results.map { |category| Catalog::CategorySerializer.new(category).as_json }, meta: query.meta }
      end

      def show
        category = find_category
        authorize(category)
        render json: { data: Catalog::CategorySerializer.new(category).as_json }
      end

      def create
        authorize(Catalog::Category)
        name = params.expect(:name)

        result = Catalog::CreateCategory.call(organization: Current.organization, name:, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::CategorySerializer.new(result.value).as_json }, status: :created
      end

      def update
        category = find_category
        authorize(category)
        name, active = params.expect(:name, :active)

        result = Catalog::UpdateCategory.call(category:, attributes: { name:, active: }, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::CategorySerializer.new(result.value).as_json }
      end

      private
        def find_category
          Catalog::Category.find(params[:id])
        end
    end
  end
end
