class PlayersSseController < PlayersController
  include Datastar

  SECTION_PARTIALS = [
    "players/section_vitals",
    "players/section_constraints",
    "players/section_next_decisions",
    "players/section_connections",
    "players/section_contract",
    "players/section_contract_history",
    "players/section_guarantees",
    "players/section_incentives",
    "players/section_ledger",
    "players/section_team_history"
  ].freeze

  # GET /players/sse/refresh
  # One-request multi-region refresh for players index filters/sorting.
  # Patches:
  # - #maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_index_workspace_state!

    requested_overlay_id = requested_overlay_id_param
    overlay_html, resolved_overlay_type, resolved_selected_player_id = refreshed_overlay_payload(requested_overlay_id: requested_overlay_id)

    with_sse_stream do |sse|
      main_html = without_view_annotations do
        render_to_string(partial: "players/workspace_main")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "players/rightpanel_base")
      end

      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        playerquery: @query,
        playerteam: @team_lens.to_s,
        playerstatus: @status_lens.to_s,
        playerconstraint: @constraint_lens.to_s,
        playerurgency: @urgency_lens.to_s,
        playerurgencysub: @urgency_sub_lens.to_s,
        playerhorizon: @cap_horizon.to_s,
        playersort: @sort_lens.to_s,
        overlaytype: resolved_overlay_type,
        selectedplayerid: resolved_selected_player_id
      )
    end
  end

  # GET /players/:slug/sse/bootstrap
  # Returns text/html with all player workspace sections for Datastar morph-by-id.
  # Datastar matches each top-level element by its `id` attribute and morphs it
  # into the existing DOM, replacing skeleton loaders with real content.
  def bootstrap
    resolve_player_from_slug!(params[:slug], redirect_on_canonical_miss: false)
    return head(:not_found) if performed?

    load_player_decision_lens!
    load_player_workspace_data!

    html_parts = []
    without_view_annotations do
      SECTION_PARTIALS.each do |partial|
        html_parts << render_to_string(partial: partial)
      end
      html_parts << render_to_string(partial: "players/rightpanel_base")
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

  def requested_overlay_id_param
    overlay_id = Integer(params[:selected_id], 10)
    overlay_id.positive? ? overlay_id : nil
  rescue ArgumentError, TypeError
    nil
  end

  def refreshed_overlay_payload(requested_overlay_id:)
    return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_id: requested_overlay_id)

    html = without_view_annotations do
      player_payload = load_sidebar_player_payload(requested_overlay_id)
      render_to_string(
        partial: "players/rightpanel_overlay_player",
        locals: {
          player: player_payload,
          overlay_player_id: requested_overlay_id.to_s
        }
      )
    end

    [html, "player", requested_overlay_id.to_s]
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
