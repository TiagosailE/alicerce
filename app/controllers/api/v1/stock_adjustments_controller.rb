module Api
  module V1
    class StockAdjustmentsController < BaseController
      include IdempotentWrite
      include LedgerWriteLimits
      before_action :require_authentication!
      before_action :verify_csrf_token!
      before_action :require_idempotency_key!

      # A count adjustment (ADR 0016). The product and warehouse are looked up
      # through the tenant scope, so another organization's id answers 404.
      def create
        authorize(Inventory::Balance, :adjust?)
        product_id, warehouse_id, counted_quantity, expected_on_hand, reason =
          params.expect(:product_id, :warehouse_id, :counted_quantity, :expected_on_hand, :reason)

        result = Inventory::AdjustStock.call(
          organization: Current.organization, actor: Current.user,
          product: Catalog::Product.find(product_id), warehouse: Inventory::Warehouse.find(warehouse_id),
          counted_quantity:, expected_on_hand:, reason:, note: params[:note], unit_cost_cents: params[:unit_cost_cents],
          idempotency_key: @idempotency_key, request_digest: request_digest
        )
        return render_result_error(result) unless result.success?

        adjustment = result.value
        # Whoever may adjust may also read values and the ledger.
        render json: {
          data: {
            movement: adjustment.movement && Inventory::MovementSerializer.new(adjustment.movement, receipt_visible: true).as_json,
            balance: Inventory::BalanceSerializer.new(adjustment.balance, value_visible: true).as_json
          }
        }, status: adjustment.status
      end

      private
        def counts_toward_organization_limit?
          Identity::Capabilities.adjust_stock?(Current.user&.membership_in(Current.organization))
        end
    end
  end
end
