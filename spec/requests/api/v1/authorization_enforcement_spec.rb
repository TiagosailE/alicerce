require "rails_helper"

# Proves the ADR 0008 safety net actually fires: a route that never calls
# authorize, or an index route that never calls policy_scope, fails loudly.
# No real endpoint does either (yet), so this exercises the mechanism
# through a throwaway controller mounted only for this spec.
class ProbePolicy < ApplicationPolicy
  def index? = true
end

module Api
  module V1
    class PunditProbeController < BaseController
      def show
        render json: { data: {} }
      end

      def index
        authorize(:probe)
        render json: { data: [] }
      end
    end
  end
end

RSpec.describe "Pundit enforcement" do
  around do |example|
    Rails.application.routes.draw do
      get "/api/v1/__pundit_probe/show", to: "api/v1/pundit_probe#show"
      get "/api/v1/__pundit_probe", to: "api/v1/pundit_probe#index"
    end
    example.run
  ensure
    Rails.application.reload_routes!
  end

  it "raises when an action never calls authorize" do
    expect { get "/api/v1/__pundit_probe/show" }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end

  it "raises when an index action authorizes but never scopes its query" do
    expect { get "/api/v1/__pundit_probe" }.to raise_error(Pundit::PolicyScopingNotPerformedError)
  end
end
