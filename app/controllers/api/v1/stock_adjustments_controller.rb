module Api
  module V1
    class StockAdjustmentsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!
      before_action :require_idempotency_key!
      # Each request writes a permanent ledger row, an audit event and a key,
      # and the demo accounts are shared and public: a per-user ceiling well
      # above real counting keeps a loop from filling the database.
      rate_limit to: 60, within: 1.minute, name: "stock_adjustment_user", only: :create,
        by: -> { Current.user&.id || request.remote_ip }

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
        value_visible = policy(Inventory::Balance).view_value?
        render json: {
          data: {
            movement: adjustment.movement && Inventory::MovementSerializer.new(adjustment.movement, value_visible:).as_json,
            balance: Inventory::BalanceSerializer.new(adjustment.balance, value_visible:).as_json
          }
        }, status: adjustment.status
      end

      private
        def require_idempotency_key!
          @idempotency_key = request.headers["Idempotency-Key"]
          return if Idempotency.valid_key?(@idempotency_key)

          render_error(status: :bad_request, code: "idempotency_key_required",
            message: "Send an Idempotency-Key header of 8 to 100 characters (letters, digits, . _ : -)")
        end

        # Digests what the action actually reads: params merges the query string
        # into the body, so a request that differs only in its query string is
        # a different request. The routing keys are in the path already.
        def request_digest
          Idempotency.digest(method: request.request_method, path: request.path,
            params: request.parameters.except(*request.path_parameters.keys.map(&:to_s)))
        end
    end
  end
end
