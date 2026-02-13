module Entities
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

      requested_context = requested_overlay_context
      overlay_html, resolved_overlay_type, resolved_overlay_key = refreshed_overlay_payload(requested_context:)

      with_sse_stream do |sse|
        main_html = without_view_annotations do
          render_to_string(partial: "entities/drafts/results")
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "entities/drafts/rightpanel_base")
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

    def refreshed_overlay_payload(requested_context:)
      return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(context: requested_context)

      case requested_context[:type]
      when "pick"
        render_pick_overlay_payload(requested_context)
      when "selection"
        render_selection_overlay_payload(requested_context)
      else
        [overlay_clear_html, "none", ""]
      end
    rescue ActiveRecord::RecordNotFound
      [overlay_clear_html, "none", ""]
    end

    def render_pick_overlay_payload(context)
      team_code = context[:team_code]
      draft_year = context[:draft_year]
      draft_round = context[:draft_round]

      html = without_view_annotations do
        render_to_string(
          partial: "entities/drafts/rightpanel_overlay_pick",
          locals: load_sidebar_pick_payload(
            team_code:,
            draft_year:,
            draft_round:
          )
        )
      end

      [html, "pick", overlay_key_for_pick(team_code:, draft_year:, draft_round:)]
    end

    def render_selection_overlay_payload(context)
      transaction_id = context[:transaction_id].to_i

      html = without_view_annotations do
        render_to_string(
          partial: "entities/drafts/rightpanel_overlay_selection",
          locals: load_sidebar_selection_payload(transaction_id)
        )
      end

      [html, "selection", "selection-#{transaction_id}"]
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
