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

  # Sets data-theme on <html> before first paint (design-system skill): a
  # plain script tag, not inline, since the CSP has no unsafe-inline.
  def theme_init
    script = Rails.configuration.x.theme_init_script

    if script.file?
      response.headers["Cache-Control"] = "no-cache"
      render plain: script.read, content_type: "application/javascript"
    else
      head :not_found
    end
  end
end
