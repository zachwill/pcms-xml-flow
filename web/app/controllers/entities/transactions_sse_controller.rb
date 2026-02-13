module Entities
  class TransactionsSseController < TransactionsController
    include Datastar

    # GET /transactions/sse/refresh
    # One-request multi-region refresh for transactions index controls.
    # Patches:
    # - #transactions-results
    # - #rightpanel-base
    # - #rightpanel-overlay (cleared)
    def refresh
      load_index_state!

      with_sse_stream do |sse|
        main_html = without_view_annotations do
          render_to_string(partial: "entities/transactions/results")
        end

        sidebar_html = without_view_annotations do
          render_to_string(partial: "entities/transactions/rightpanel_base")
        end

        clear_overlay_html = '<div id="rightpanel-overlay"></div>'

        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
        patch_elements_by_id(sse, clear_overlay_html)
        patch_signals(
          sse,
          txndaterange: @daterange,
          txnteam: @team.to_s,
          txnsignings: @signings,
          txnwaivers: @waivers,
          txnextensions: @extensions,
          txnother: @other,
          overlaytype: "none",
          overlayid: ""
        )
      end
    end

    private

    def without_view_annotations
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false
      yield
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end
  end
end
