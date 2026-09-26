module Api
  module V1
    module PurchaseOrders
      class ReceiptsController < BaseController
        include LedgerWriteLimits
        include IdempotentWrite
        before_action :require_authentication!
        before_action :verify_csrf_token!
        before_action :require_idempotency_key!
        RECEIPTS_PER_TEN_MINUTES = 20

        # A receipt is the heaviest write here (a line, a movement and a balance
        # update for every line, none of it deletable), so it has a tighter
        # ceiling for the organization on top of the shared ones.
        organization_budget to: RECEIPTS_PER_TEN_MINUTES, within: 10.minutes, name: "receipts_organization", scope: "receipts"

        # POST /purchase_orders/:purchase_order_id/receipts (ADR 0017). The order,
        # the warehouse and the order lines are looked up through the tenant scope,
        # so another organization's id answers 404. The caller is authorized before
        # anything is looked up, so a role without access learns nothing about which
        # ids exist. The lines are read whole by the command, which parses only the
        # two fields it knows from each, strictly.
        def create
          authorize(Purchasing::Receipt, :create?)
          order = Purchasing::Order.find(params[:purchase_order_id])
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
