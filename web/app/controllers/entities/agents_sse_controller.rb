module Entities
  class AgentsSseController < AgentsController
    include Datastar

    # GET /agents/sse/refresh
    # One-request multi-region refresh for the Agents workspace.
    # Patches:
    # - #agents-maincanvas
    # - #rightpanel-base
    # - #rightpanel-overlay (preserved when selected row remains visible)
    def refresh
      setup_directory_filters!
      load_directory_rows!
      build_sidebar_summary!

      requested_overlay_type, requested_overlay_id = requested_overlay_context
      overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(
        requested_type: requested_overlay_type,
        requested_id: requested_overlay_id
      )

      with_sse_stream do |sse|
        main_html = without_view_annotations do
          render_to_string(partial: "entities/agents/workspace_main")
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "entities/agents/rightpanel_base")
        end

        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, overlay_html)
        patch_signals(
          sse,
          entitykind: @directory_kind,
          activeonly: @active_only,
          certifiedonly: @certified_only,
          withclients: @with_clients,
          withbook: @with_book,
          withrestrictions: @with_restrictions,
          withexpiring: @with_expiring,
          bookyear: @book_year.to_s,
          sortkey: @sort_key,
          sortdir: @sort_dir,
          overlaytype: resolved_overlay_type,
          overlayid: resolved_overlay_id
        )
      end
    end

    private

    def requested_overlay_context
      overlay_type = params[:selected_type].to_s.strip.downcase
      return [nil, nil] unless OVERLAY_TYPES.include?(overlay_type)

      overlay_id = Integer(params[:selected_id], 10)
      return [nil, nil] if overlay_id <= 0

      [overlay_type, overlay_id]
    rescue ArgumentError, TypeError
      [nil, nil]
    end

    def refreshed_overlay_payload(requested_type:, requested_id:)
      return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_type: requested_type, overlay_id: requested_id)

      html = without_view_annotations do
        render_overlay_for_refresh(overlay_type: requested_type, overlay_id: requested_id)
      end

      [html, requested_type, requested_id.to_s]
    rescue ActiveRecord::RecordNotFound
      [overlay_clear_html, "none", ""]
    end

    def render_overlay_for_refresh(overlay_type:, overlay_id:)
      case overlay_type
      when "agent"
        render_to_string(partial: "entities/agents/rightpanel_overlay_agent", locals: load_sidebar_agent_payload(overlay_id))
      when "agency"
        render_to_string(partial: "entities/agents/rightpanel_overlay_agency", locals: load_sidebar_agency_payload(overlay_id))
      else
        overlay_clear_html
      end
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
