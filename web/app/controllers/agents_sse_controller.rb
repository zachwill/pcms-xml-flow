class AgentsSseController < AgentsController
  include Datastar

  # GET /agents/sse/refresh
  # One-request multi-region refresh for the Agents workspace.
  # Patches:
  # - #commandbar
  # - #agents-maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_directory_workspace_state!

    requested_overlay_type, requested_overlay_id = requested_overlay_context
    requested_return_type, requested_return_id = requested_overlay_return_context(current_overlay_type: requested_overlay_type)

    overlay_html, resolved_overlay_type, resolved_overlay_id, resolved_return_type, resolved_return_id = refreshed_overlay_payload(
      requested_type: requested_overlay_type,
      requested_id: requested_overlay_id,
      requested_return_type: requested_return_type,
      requested_return_id: requested_return_id
    )

    with_sse_stream do |sse|
      commandbar_html = without_view_annotations do
        render_to_string(partial: "agents/commandbar")
      end

      main_html = without_view_annotations do
        render_to_string(partial: "agents/workspace_main")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "agents/rightpanel_base")
      end

      patch_elements_by_id(sse, commandbar_html)
      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        agentquery: @query,
        entitykind: @directory_kind,
        activeonly: @active_only,
        certifiedonly: @certified_only,
        withclients: @with_clients,
        withbook: @with_book,
        withrestrictions: @with_restrictions,
        withexpiring: @with_expiring,
        agencyfilterid: @agency_filter_id.to_s,
        agencyscopeactive: @agency_scope_active,
        agencyscopeid: @agency_scope_id.to_s,
        bookyear: @book_year.to_s,
        sortkey: @sort_key,
        sortdir: @sort_dir,
        overlaytype: resolved_overlay_type,
        overlayid: resolved_overlay_id,
        overlayreturntype: resolved_return_type,
        overlayreturnid: resolved_return_id
      )
    end
  end

  private

  def requested_overlay_context
    overlay_context_from_params(type_param: :selected_type, id_param: :selected_id)
  end

  def requested_overlay_return_context(current_overlay_type:)
    overlay_context_from_params(
      type_param: :selected_return_type,
      id_param: :selected_return_id,
      disallow_type: current_overlay_type
    )
  end

  def refreshed_overlay_payload(requested_type:, requested_id:, requested_return_type:, requested_return_id:)
    return [overlay_clear_html, "none", "", "none", ""] unless selected_overlay_visible?(overlay_type: requested_type, overlay_id: requested_id)

    resolved_return_type, resolved_return_id = resolved_overlay_return_context(
      requested_type: requested_return_type,
      requested_id: requested_return_id
    )

    html = without_view_annotations do
      render_overlay_for_refresh(
        overlay_type: requested_type,
        overlay_id: requested_id,
        return_overlay_type: resolved_return_type,
        return_overlay_id: resolved_return_id
      )
    end

    [html, requested_type, requested_id.to_s, resolved_return_type, resolved_return_id]
  rescue ActiveRecord::RecordNotFound
    [overlay_clear_html, "none", "", "none", ""]
  end

  def resolved_overlay_return_context(requested_type:, requested_id:)
    return ["none", ""] unless selected_overlay_visible?(overlay_type: requested_type, overlay_id: requested_id)

    [requested_type, requested_id.to_s]
  end

  def render_overlay_for_refresh(overlay_type:, overlay_id:, return_overlay_type:, return_overlay_id:)
    case overlay_type
    when "agent"
      render_to_string(
        partial: "agents/rightpanel_overlay_agent",
        locals: load_sidebar_agent_payload(overlay_id).merge(
          return_overlay_type:,
          return_overlay_id:
        )
      )
    when "agency"
      render_to_string(
        partial: "agents/rightpanel_overlay_agency",
        locals: load_sidebar_agency_payload(overlay_id).merge(
          return_overlay_type:,
          return_overlay_id:
        )
      )
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
