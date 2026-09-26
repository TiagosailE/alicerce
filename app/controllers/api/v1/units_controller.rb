module Api
  module V1
    class UnitsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Catalog::Unit)
        query = Catalog::UnitsQuery.new(policy_scope(Catalog::Unit), **pagination_params)
        render json: { data: query.results.map { |unit| Catalog::UnitSerializer.new(unit).as_json }, meta: query.meta }
      end

      def show
        unit = find_unit
        authorize(unit)
        render json: { data: Catalog::UnitSerializer.new(unit).as_json }
      end

      def create
        authorize(Catalog::Unit)
        code, name = params.expect(:code, :name)

        result = Catalog::CreateUnit.call(organization: Current.organization, code:, name:, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::UnitSerializer.new(result.value).as_json }, status: :created
      end

      def update
        unit = find_unit
        authorize(unit)
        code, name, active = params.expect(:code, :name, :active)

        result = Catalog::UpdateUnit.call(unit:, attributes: { code:, name:, active: }, actor: Current.user)
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::UnitSerializer.new(result.value).as_json }
      end

      private
        # TenantScoped already keeps this to the current organization; the
        # policy is the only thing left to authorize (view_master_data? is
        # true for every real membership today, so this always finds or
        # 404s, never 403s, but that stays exact if the matrix ever adds a
        # role without read access).
        def find_unit
          Catalog::Unit.find(params[:id])
        end
    end
  end
end
