class AgenciesSseController < AgenciesController
  include Datastar

  # GET /agencies/sse/refresh
  # One-request multi-region refresh for the Agencies workspace.
  # Patches:
  # - #agencies-maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_index_workspace_state!

    requested_overlay_id = requested_overlay_id_param
    overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(requested_overlay_id:)

    with_sse_stream do |sse|
      main_html = without_view_annotations do
        render_to_string(partial: "agencies/workspace_main")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "agencies/rightpanel_base")
      end

      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        agencyquery: @query,
        agencyactivity: @activity_lens,
        agencyyear: @book_year.to_s,
        agencysort: @sort_key,
        agencydir: @sort_dir,
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
      render_to_string(partial: "agencies/rightpanel_overlay_agency", locals: load_sidebar_agency_payload(requested_overlay_id))
    end

    [html, "agency", requested_overlay_id.to_s]
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
