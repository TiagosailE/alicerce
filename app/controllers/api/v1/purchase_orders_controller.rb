module Api
  module V1
    class PurchaseOrdersController < BaseController
      include PurchasingWriteLimits
      before_action :require_authentication!
      before_action :verify_csrf_token!, only: %i[create update]

      def index
        authorize(Purchasing::Order)
        query = Purchasing::OrdersQuery.new(
          policy_scope(Purchasing::Order), **pagination_params,
          status: scalar_param(:status), supplier_id: scalar_param(:supplier_id), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |order| Purchasing::OrderSummarySerializer.new(order).as_json }, meta: query.meta }
      end

      def show
        order = find_order
        authorize(order)
        render_order(order)
      end

      def create
        authorize(Purchasing::Order)
        result = Purchasing::CreateOrder.call(
          organization: Current.organization, actor: Current.user, supplier: find_supplier,
          lines: params[:lines], note: scalar_param(:note), **term_params
        )
        return render_result_error(result) unless result.success?

        render_order(result.value, status: :created)
      end

      def update
        order = find_order
        authorize(order)
        result = Purchasing::UpdateOrder.call(
          order:, actor: Current.user, revision: revision_param, supplier: find_supplier,
          lines: params[:lines], note: scalar_param(:note), **term_params
        )
        return render_result_error(result) unless result.success?

        render_order(result.value)
      end

      private
        def find_order = Purchasing::Order.find(params[:id])

        # The supplier is looked up through the tenant scope, so another
        # organization's partner answers 404.
        def find_supplier = Catalog::Partner.find(params.expect(:supplier_id))

        def term_params
          { installments: integer_param(:installments, 1), first_due_days: integer_param(:first_due_days, 30),
            interval_days: integer_param(:interval_days, 30) }
        end

        # A term the client did not send takes its default; one that is not a
        # plain whole number is passed on as sent and refused by the model.
        def integer_param(key, default)
          value = params[key]
          value.nil? ? default : (IntegerString.parse(value) || value)
        end

        def revision_param = IntegerString.parse(params.expect(:revision))

        def render_order(order, status: :ok)
          personal = policy(order).view_personal_data?
          render json: { data: Purchasing::OrderSerializer.new(order, personal_data_visible: personal).as_json }, status:
        end
    end
  end
end
