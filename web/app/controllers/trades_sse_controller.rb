class TradesSseController < TradesController
  include Datastar

  # GET /trades/sse/refresh
  # One-request multi-region refresh for trades index controls.
  # Patches:
  # - #trades-results
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
        render_to_string(partial: "trades/results")
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "trades/rightpanel_base")
      end

      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        tradedaterange: @daterange,
        tradeteam: @team.to_s,
        tradesort: @sort,
        tradelens: @lens,
        tradecomposition: @composition,
        overlaytype: resolved_overlay_type,
        overlayid: resolved_overlay_id
      )
    end
  end

  private

  def requested_overlay_context
    overlay_type = params[:selected_type].to_s.strip.downcase
    return [nil, nil] unless overlay_type == "trade"

    overlay_id = Integer(params[:selected_id], 10)
    return [nil, nil] if overlay_id <= 0

    [overlay_type, overlay_id]
  rescue ArgumentError, TypeError
    [nil, nil]
  end

  def refreshed_overlay_payload(requested_type:, requested_id:)
    return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_type: requested_type, overlay_id: requested_id)

    html = without_view_annotations do
      render_to_string(
        partial: "trades/rightpanel_overlay_trade",
        locals: load_sidebar_trade_payload(requested_id).merge(
          overlay_trade_id: requested_id.to_s
        )
      )
    end

    [html, "trade", requested_id.to_s]
  rescue ActiveRecord::RecordNotFound
    [overlay_clear_html, "none", ""]
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
