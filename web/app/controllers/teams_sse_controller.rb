class TeamsSseController < TeamsController
  include Datastar

  SECTION_PARTIALS = [
    "teams/section_vitals",
    "teams/section_constraints",
    "teams/section_roster",
    "teams/section_draft_assets",
    "teams/section_cap_horizon",
    "teams/section_activity",
    "teams/section_two_way",
    "teams/section_apron_provenance"
  ].freeze

  # GET /teams/sse/refresh
  # One-request multi-region refresh for teams index filters/sorting.
  # Patches:
  # - #commandbar
  # - #maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_index_workspace_state!(apply_compare_action: true)

    requested_overlay_id = requested_overlay_id_param
    overlay_html, resolved_overlay_type, resolved_selected_team_id = refreshed_overlay_payload(requested_overlay_id: requested_overlay_id)

    with_sse_stream do |sse|
      commandbar_html = without_view_annotations do
        render_to_string(partial: "teams/commandbar")
      end

      main_html = without_view_annotations do
        render_to_string(partial: "teams/workspace_main")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "teams/rightpanel_base")
      end

      patch_elements_by_id(sse, commandbar_html)
      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        teamsquery: @query,
        teamsconference: @conference_lens.to_s,
        teamspressure: @pressure_lens.to_s,
        teamssort: @sort_lens.to_s,
        comparea: @compare_a_id.to_s,
        compareb: @compare_b_id.to_s,
        overlaytype: resolved_overlay_type,
        selectedteamid: resolved_selected_team_id
      )
    end
  end

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
      html_parts << render_to_string(partial: "teams/rightpanel_base")
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

  def requested_overlay_id_param
    overlay_id = Integer(params[:selected_id], 10)
    overlay_id.positive? ? overlay_id : nil
  rescue ArgumentError, TypeError
    nil
  end

  def refreshed_overlay_payload(requested_overlay_id:)
    return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_id: requested_overlay_id)

    html = without_view_annotations do
      load_index_team_row!(requested_overlay_id)
      render_to_string(partial: "teams/rightpanel_overlay_team", locals: { team_row: @sidebar_team_row })
    end

    [html, "team", requested_overlay_id.to_s]
  rescue ActiveRecord::RecordNotFound
    [overlay_clear_html, "none", ""]
  end

  def overlay_clear_html
    '<div id="rightpanel-overlay"></div>'
  end

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
