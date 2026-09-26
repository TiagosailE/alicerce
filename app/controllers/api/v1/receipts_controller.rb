module Api
  module V1
    class ReceiptsController < BaseController
      before_action :require_authentication!

      def index
        authorize(Purchasing::Receipt)
        query = Purchasing::ReceiptsQuery.new(
          policy_scope(Purchasing::Receipt), **pagination_params,
          order_id: scalar_param(:order_id), warehouse_id: scalar_param(:warehouse_id), q: scalar_param(:q)
        )
        render json: { data: query.results.map { |receipt| Purchasing::ReceiptSummarySerializer.new(receipt).as_json }, meta: query.meta }
      end

      def show
        authorize(Purchasing::Receipt, :show?)
        receipt = Purchasing::Receipt.includes(:lines, :order, :warehouse, :created_by_user, title: %i[installments receipt]).find(params[:id])
        authorize(receipt)
        render json: { data: Purchasing::ReceiptSerializer.new(receipt, payable_visible: policy(receipt).view_payable?).as_json }
      end
    end
  end
end
