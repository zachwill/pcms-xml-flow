module Entities
  class DraftSelectionsSseController < DraftSelectionsController
    include Datastar

    # GET /draft-selections/sse/refresh
    # One-request multi-region refresh for the Draft Selections workspace.
    # Patches:
    # - #draft-selections-maincanvas
    # - #rightpanel-base
    # - #rightpanel-overlay (preserved when selected row remains visible)
    def refresh
      load_index_workspace_state!

      requested_overlay_id = requested_overlay_id_param
      overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(requested_overlay_id: requested_overlay_id)

      with_sse_stream do |sse|
        main_html = without_view_annotations do
          render_to_string(partial: "entities/draft_selections/workspace_main")
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "entities/draft_selections/rightpanel_base")
        end

        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          draftselectionquery: @query,
          draftselectionyear: @year_lens.to_s,
          draftselectionround: @round_lens.to_s,
          draftselectionteam: @team_lens.to_s,
          overlaytype: resolved_overlay_type,
          overlayid: resolved_overlay_id
        )
      end
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
        render_to_string(partial: "entities/draft_selections/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(requested_overlay_id))
      end

      [html, "selection", requested_overlay_id.to_s]
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
end
