module Entities
  class PlayersSseController < PlayersController
    include Datastar

    SECTION_PARTIALS = [
      "entities/players/section_vitals",
      "entities/players/section_constraints",
      "entities/players/section_connections",
      "entities/players/section_contract",
      "entities/players/section_contract_history",
      "entities/players/section_guarantees",
      "entities/players/section_incentives",
      "entities/players/section_ledger",
      "entities/players/section_team_history"
    ].freeze

    # GET /players/:slug/sse/bootstrap
    # One-off SSE bootstrap for progressive player workspace hydration.
    def bootstrap
      with_sse_stream do |sse|
        patch_signals(sse, bootstrapstatus: "loading", playersseticks: 0)
        patch_flash(sse, "Loading player workspace…")

        resolve_player_from_slug!(params[:slug], redirect_on_canonical_miss: false)
        if performed?
          patch_signals(sse, bootstrapstatus: "error")
          return
        end

        load_player_workspace_data!
        patch_signals(sse, bootstrapstatus: "streaming", playersseticks: 0)

        without_view_annotations do
          total = SECTION_PARTIALS.length

          SECTION_PARTIALS.each_with_index do |partial, idx|
            section_html = render_to_string(partial: partial)
            patch_elements_by_id(sse, section_html)
            patch_signals(sse, playersseticks: idx + 1)

            if ((idx + 1) % 2).zero? || idx == total - 1
              patch_flash(sse, "Rendering sections… #{idx + 1}/#{total}")
            end
          end

          patch_elements_by_id(sse, render_to_string(partial: "entities/players/rightpanel_base"))
          patch_elements_by_id(sse, '<div id="rightpanel-overlay"></div>')
        end

        patch_flash(sse, "")
        patch_signals(sse, bootstrapstatus: "done", playersseticks: SECTION_PARTIALS.length)
      rescue ActiveRecord::RecordNotFound
        patch_flash(sse, "Player bootstrap failed: player not found.")
        patch_signals(sse, bootstrapstatus: "error")
      rescue ActiveRecord::StatementInvalid => e
        patch_flash(sse, "Player bootstrap failed: #{e.message}")
        patch_signals(sse, bootstrapstatus: "error")
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
