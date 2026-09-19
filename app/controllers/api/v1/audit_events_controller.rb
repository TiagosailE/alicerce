module Api
  module V1
    class AuditEventsController < BaseController
      before_action :require_authentication!

      def index
        authorize(Audit::Event)
        query = Audit::EventsQuery.new(policy_scope(Audit::Event), page: params[:page], per_page: params[:per_page])
        render json: { data: query.results.map { |event| Audit::EventSerializer.new(event).as_json }, meta: query.meta }
      end
    end
  end
end
