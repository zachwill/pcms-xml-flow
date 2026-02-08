module Entities
  class TeamsSseController < TeamsController
    SECTION_PARTIALS = [
      "entities/teams/section_vitals",
      "entities/teams/section_constraints",
      "entities/teams/section_roster",
      "entities/teams/section_draft_assets",
      "entities/teams/section_cap_horizon",
      "entities/teams/section_apron_provenance",
      "entities/teams/section_two_way",
      "entities/teams/section_activity"
    ].freeze

    # GET /teams/:slug/sse/bootstrap
    # Returns text/html with all team workspace sections for Datastar morph-by-id.
    # Datastar matches each top-level element by its `id` attribute and morphs it
    # into the existing DOM, replacing skeleton loaders with real content.
    def bootstrap
      resolve_team_from_slug!(params[:slug], redirect_on_canonical_miss: false)
      return head(:not_found) if performed?

      load_team_workspace_data!

      html_parts = []
      without_view_annotations do
        SECTION_PARTIALS.each do |partial|
          html_parts << render_to_string(partial: partial)
        end
        html_parts << render_to_string(partial: "entities/teams/rightpanel_base")
        html_parts << '<div id="rightpanel-overlay"></div>'
      end

      no_cache_headers!
      render html: html_parts.join("\n").html_safe, layout: false
    rescue ActiveRecord::RecordNotFound
      render html: %(<div id="flash">Team not found.</div>).html_safe, layout: false
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error("Team bootstrap failed: #{e.message}")
      render html: %(<div id="flash">Team bootstrap failed.</div>).html_safe, layout: false
    end

    private

    def without_view_annotations
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false
      yield
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end

    def no_cache_headers!
      response.headers["Cache-Control"] = "no-store"
      response.headers.delete("ETag")
    end
  end
end
