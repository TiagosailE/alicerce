# Serves the built SPA shell for every browser route outside /api, so the
# response goes through the CSP and Permissions-Policy middleware.
class SpaController < ActionController::API
  def show
    index = Rails.configuration.x.spa_index

    if index.file?
      response.headers["Cache-Control"] = "no-cache"
      render plain: index.read, content_type: "text/html"
    else
      render plain: "Frontend not built. Run: npm --prefix frontend run build", status: :service_unavailable
    end
  end
end
