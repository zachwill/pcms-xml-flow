module Entities
  class PlayersSseController < PlayersController
    include Datastar

    SECTION_PARTIALS = [
      "entities/players/section_vitals",
      "entities/players/section_constraints",
      "entities/players/section_connections",
      "entities/players/section_contract",
      "entities/players/section_contract_history",
      "entities/players/section_guarantees",
      "entities/players/section_incentives",
      "entities/players/section_ledger",
      "entities/players/section_team_history"
    ].freeze

    # GET /players/sse/refresh
    # One-request multi-region refresh for players index filters/sorting.
    # Patches:
    # - #maincanvas
    # - #rightpanel-base
    # - #rightpanel-overlay (cleared)
    def refresh
      load_index_workspace_state!

      with_sse_stream do |sse|
        main_html = without_view_annotations do
          render_to_string(partial: "entities/players/workspace_main")
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "entities/players/rightpanel_base")
        end

        clear_overlay_html = '<div id="rightpanel-overlay"></div>'

        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, clear_overlay_html)
        patch_signals(sse, overlaytype: "none", selectedplayerid: "")
      end
    end

    # GET /players/:slug/sse/bootstrap
    # Returns text/html with all player workspace sections for Datastar morph-by-id.
    # Datastar matches each top-level element by its `id` attribute and morphs it
    # into the existing DOM, replacing skeleton loaders with real content.
    def bootstrap
      resolve_player_from_slug!(params[:slug], redirect_on_canonical_miss: false)
      return head(:not_found) if performed?

      load_player_workspace_data!

      html_parts = []
      without_view_annotations do
        SECTION_PARTIALS.each do |partial|
          html_parts << render_to_string(partial: partial)
        end
        html_parts << render_to_string(partial: "entities/players/rightpanel_base")
        html_parts << '<div id="rightpanel-overlay"></div>'
      end

      no_cache_headers!
      render html: html_parts.join("\n").html_safe, layout: false
    rescue ActiveRecord::RecordNotFound
      render html: %(<div id="flash">Player not found.</div>).html_safe, layout: false
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error("Player bootstrap failed: #{e.message}")
      render html: %(<div id="flash">Player bootstrap failed.</div>).html_safe, layout: false
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
