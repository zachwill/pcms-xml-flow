class DraftsSseController < DraftsController
  include Datastar

  # GET /drafts/sse/refresh
  # One-request multi-region refresh for drafts index controls.
  # Patches:
  # - #drafts-results
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row/cell remains visible)
  def refresh
    load_index_state!

    overlay_state_payload = overlay_state.initial_overlay_state
    overlay_html, resolved_overlay_type, resolved_overlay_key = resolve_overlay_refresh_payload(overlay_state_payload)

    with_sse_stream do |sse|
      main_html = without_view_annotations do
        render_to_string(partial: "drafts/results")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "drafts/rightpanel_base")
      end

      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        draftview: @view,
        draftyear: @year.to_s,
        draftround: @round.to_s,
        draftteam: @team.to_s,
        draftsort: @sort,
        draftlens: @lens,
        overlaytype: resolved_overlay_type,
        overlaykey: resolved_overlay_key
      )
    end
  end

  private

  def resolve_overlay_refresh_payload(overlay_state_payload)
    partial = overlay_state_payload[:initial_overlay_partial]
    locals = overlay_state_payload[:initial_overlay_locals]

    return [overlay_clear_html, "none", ""] if partial.blank?

    html = without_view_annotations do
      render_to_string(partial: partial, locals: locals)
    end

    [
      html,
      overlay_state_payload[:initial_overlay_type].presence || "none",
      overlay_state_payload[:initial_overlay_key].to_s
    ]
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
end
