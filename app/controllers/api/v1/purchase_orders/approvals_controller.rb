module Api
  module V1
    module PurchaseOrders
      class ApprovalsController < BaseController
        include LedgerWriteLimits
        before_action :require_authentication!
        before_action :verify_csrf_token!

        # POST /purchase_orders/:purchase_order_id/approval (a state change is a
        # sub-resource, never a writable status).
        def create
          authorize(Purchasing::Order, :approve?)
          order = Purchasing::Order.find(params[:purchase_order_id])
          result = Purchasing::ApproveOrder.call(order:, actor: Current.user, revision: IntegerString.parse(params.expect(:revision)))
          return render_result_error(result) unless result.success?

          personal = policy(result.value).view_personal_data?
          render json: { data: Purchasing::OrderSerializer.new(result.value, personal_data_visible: personal).as_json }
        end
      end
    end
  end
end
