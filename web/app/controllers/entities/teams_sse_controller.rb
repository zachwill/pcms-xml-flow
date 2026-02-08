module Entities
  class TeamsSseController < TeamsController
    include Datastar

    SECTION_PARTIALS = [
      "entities/teams/section_vitals",
      "entities/teams/section_constraints",
      "entities/teams/section_roster",
      "entities/teams/section_draft_assets",
      "entities/teams/section_cap_horizon",
      "entities/teams/section_apron_provenance",
      "entities/teams/section_two_way",
      "entities/teams/section_activity"
    ].freeze

    # GET /teams/:slug/sse/bootstrap
    # One-off SSE bootstrap for progressive team workspace hydration.
    def bootstrap
      with_sse_stream do |sse|
        patch_signals(sse, bootstrapstatus: "loading", teamsseticks: 0)
        patch_flash(sse, "Loading team workspace…")

        resolve_team_from_slug!(params[:slug], redirect_on_canonical_miss: false)
        if performed?
          patch_signals(sse, bootstrapstatus: "error")
          return
        end

        load_team_workspace_data!
        patch_signals(sse, bootstrapstatus: "streaming", teamsseticks: 0)

        without_view_annotations do
          total = SECTION_PARTIALS.length

          SECTION_PARTIALS.each_with_index do |partial, idx|
            section_html = render_to_string(partial: partial)
            patch_elements_by_id(sse, section_html)
            patch_signals(sse, teamsseticks: idx + 1)

            if ((idx + 1) % 2).zero? || idx == total - 1
              patch_flash(sse, "Rendering sections… #{idx + 1}/#{total}")
            end
          end

          patch_elements_by_id(sse, render_to_string(partial: "entities/teams/rightpanel_base"))
          patch_elements_by_id(sse, '<div id="rightpanel-overlay"></div>')
        end

        patch_flash(sse, "")
        patch_signals(sse, bootstrapstatus: "done", teamsseticks: SECTION_PARTIALS.length)
      rescue ActiveRecord::RecordNotFound
        patch_flash(sse, "Team bootstrap failed: team not found.")
        patch_signals(sse, bootstrapstatus: "error")
      rescue ActiveRecord::StatementInvalid => e
        patch_flash(sse, "Team bootstrap failed: #{e.message}")
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
