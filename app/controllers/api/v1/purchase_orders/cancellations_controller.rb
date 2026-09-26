module Api
  module V1
    module PurchaseOrders
      class CancellationsController < BaseController
        include LedgerWriteLimits
        before_action :require_authentication!
        before_action :verify_csrf_token!

        # POST /purchase_orders/:purchase_order_id/cancellation
        def create
          authorize(Purchasing::Order, :cancel?)
          order = Purchasing::Order.find(params[:purchase_order_id])
          result = Purchasing::CancelOrder.call(order:, actor: Current.user)
          return render_result_error(result) unless result.success?

          personal = policy(result.value).view_personal_data?
          render json: { data: Purchasing::OrderSerializer.new(result.value, personal_data_visible: personal).as_json }
        end
      end
    end
  end
end
