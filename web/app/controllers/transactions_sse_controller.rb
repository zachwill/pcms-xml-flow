class TransactionsSseController < TransactionsController
  include Datastar

  # GET /transactions/sse/refresh
  # One-request multi-region refresh for transactions index controls.
  # Patches:
  # - #transactions-results
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_index_state!

    requested_overlay_type, requested_overlay_id = requested_overlay_context
    overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(
      requested_type: requested_overlay_type,
      requested_id: requested_overlay_id
    )

    with_sse_stream do |sse|
      main_html = without_view_annotations do
        render_to_string(partial: "transactions/results")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "transactions/rightpanel_base")
      end

      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        txnquery: @query.to_s,
        txndaterange: @daterange,
        txnteam: @team.to_s,
        txnsignings: @signings,
        txnwaivers: @waivers,
        txnextensions: @extensions,
        txnother: @other,
        txnimpact: @impact,
        overlaytype: resolved_overlay_type,
        overlayid: resolved_overlay_id
      )
    end
  end

  private

  def requested_overlay_context
    overlay_type = params[:selected_type].to_s.strip.downcase
    return [nil, nil] unless overlay_type == "transaction"

    overlay_id = Integer(params[:selected_id], 10)
    return [nil, nil] if overlay_id <= 0

    [overlay_type, overlay_id]
  rescue ArgumentError, TypeError
    [nil, nil]
  end

  def refreshed_overlay_payload(requested_type:, requested_id:)
    return [overlay_clear_html, "", ""] unless selected_overlay_visible?(overlay_type: requested_type, overlay_id: requested_id)

    html = without_view_annotations do
      render_to_string(
        partial: "transactions/rightpanel_overlay_transaction",
        locals: load_sidebar_transaction_payload(requested_id).merge(
          overlay_transaction_id: requested_id.to_s
        )
      )
    end

    [html, "transaction", requested_id.to_s]
  rescue ActiveRecord::RecordNotFound
    [overlay_clear_html, "", ""]
  end

  def overlay_clear_html
    '<div id="rightpanel-overlay" class="absolute inset-0 z-20 pointer-events-none"></div>'
  end

  def without_view_annotations
    original = ActionView::Base.annotate_rendered_view_with_filenames
    ActionView::Base.annotate_rendered_view_with_filenames = false
    yield
  ensure
    ActionView::Base.annotate_rendered_view_with_filenames = original
  end
end
