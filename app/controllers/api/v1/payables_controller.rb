module Api
  module V1
    class PayablesController < BaseController
      before_action :require_authentication!

      def index
        authorize(Finance::Title)
        query = Finance::PayablesQuery.new(
          policy_scope(Finance::Title), **pagination_params, status: scalar_param(:status), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |title| Finance::TitleSerializer.new(title).as_json }, meta: query.meta }
      end
    end
  end
end
