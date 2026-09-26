module Api
  module V1
    class PartnersController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Catalog::Partner)
        query = Catalog::PartnersQuery.new(
          policy_scope(Catalog::Partner),
          **pagination_params,
          customer: scalar_param(:customer), supplier: scalar_param(:supplier), active: scalar_param(:active), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |partner| Catalog::PartnerSerializer.new(partner).as_json }, meta: query.meta }
      end

      def show
        partner = find_partner
        authorize(partner)
        render json: { data: Catalog::PartnerSerializer.new(partner).as_json }
      end

      def create
        authorize(Catalog::Partner)
        name, document_type, document_number, customer, supplier =
          params.expect(:name, :document_type, :document_number, :customer, :supplier)

        result = Catalog::CreatePartner.call(
          organization: Current.organization, name:, document_type:, document_number:, customer:, supplier:,
          email: params[:email].presence, phone: params[:phone].presence, actor: Current.user
        )
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::PartnerSerializer.new(result.value).as_json }, status: :created
      end

      def update
        partner = find_partner
        authorize(partner)
        name, document_type, document_number, customer, supplier, active =
          params.expect(:name, :document_type, :document_number, :customer, :supplier, :active)

        result = Catalog::UpdatePartner.call(
          partner:,
          attributes: {
            name:, document_type:, document_number:, customer:, supplier:, active:,
            email: params[:email].presence, phone: params[:phone].presence
          },
          actor: Current.user
        )
        return render_result_error(result) unless result.success?

        render json: { data: Catalog::PartnerSerializer.new(result.value).as_json }
      end

      private
        def find_partner
          Catalog::Partner.find(params[:id])
        end
    end
  end
end
