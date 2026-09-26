module Api
  module V1
    module PurchaseOrders
      class ReceiptsController < BaseController
        include PurchasingWriteLimits
        include IdempotentWrite
        before_action :require_authentication!
        before_action :verify_csrf_token!
        before_action :require_idempotency_key!

        # POST /purchase_orders/:purchase_order_id/receipts (ADR 0017). The order,
        # the warehouse and the order lines are looked up through the tenant scope,
        # so another organization's id answers 404.
        def create
          order = Purchasing::Order.find(params[:purchase_order_id])
          authorize(Purchasing::Receipt, :create?)
          warehouse = Inventory::Warehouse.find(params.expect(:warehouse_id))
          result = Purchasing::ReceiveGoods.call(
            organization: Current.organization, actor: Current.user, order:, warehouse:, lines: params[:lines],
            received_on: scalar_param(:received_on), supplier_invoice_number: scalar_param(:supplier_invoice_number),
            idempotency_key: @idempotency_key, request_digest:
          )
          return render_result_error(result) unless result.success?

          receipt = Purchasing::Receipt.includes(:lines, :order, :warehouse, :created_by_user, title: %i[installments receipt]).find(result.value.id)
          render json: { data: Purchasing::ReceiptSerializer.new(receipt, payable_visible: policy(receipt).view_payable?).as_json },
            status: :created
        end
      end
    end
  end
end
