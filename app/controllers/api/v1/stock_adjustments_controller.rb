module Api
  module V1
    class StockAdjustmentsController < BaseController
      before_action :require_authentication!
      before_action :verify_csrf_token!
      before_action :require_idempotency_key!

      # A count adjustment (ADR 0016). The product and warehouse are looked up
      # through the tenant scope, so another organization's id answers 404.
      def create
        authorize(Inventory::Balance, :adjust?)
        product_id, warehouse_id, counted_quantity, reason =
          params.expect(:product_id, :warehouse_id, :counted_quantity, :reason)

        result = Inventory::AdjustStock.call(
          organization: Current.organization, actor: Current.user,
          product: Catalog::Product.find(product_id), warehouse: Inventory::Warehouse.find(warehouse_id),
          counted_quantity:, reason:, note: params[:note], unit_cost: params[:unit_cost],
          idempotency_key: @idempotency_key, request_digest: request_digest
        )
        return render_result_error(result) unless result.success?

        adjustment = result.value
        render json: {
          data: {
            movement: adjustment.movement && Inventory::MovementSerializer.new(adjustment.movement).as_json,
            balance: Inventory::BalanceSerializer.new(adjustment.balance).as_json
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

        def request_digest
          Idempotency.digest(method: request.request_method, path: request.path, params: request.request_parameters)
        end
    end
  end
end
