module Tools
  class SalaryBookSseController < SalaryBookController
    include Datastar

    # GET /tools/salary-book/sse/bootstrap
    # One-off SSE bootstrap stream for the Salary Book root shell:
    # - patches #flash quickly (loading/progress)
    # - streams each team section patch by id (smaller events, progressive paint)
    # - clears #flash + marks bootstrapstatus done
    def bootstrap
      year = salary_year_param

      with_sse_stream do |sse|
        patch_signals(sse, bootstrapstatus: "loading", sseticks: 0)
        patch_flash(sse, "Loading teams…")

        team_rows = fetch_team_index_rows(year)
        team_codes = team_rows.map { |row| row["team_code"] }.compact
        _teams_by_conference, team_meta_by_code = build_team_maps(team_rows)

        if team_codes.empty?
          patch_maincanvas_error(sse, year:, message: nil)
          patch_flash(sse, "")
          patch_signals(sse, bootstrapstatus: "done", sseticks: 0)
          return
        end

        patch_flash(sse, "Loading players…")
        players_by_team = fetch_players_by_team(team_codes)

        patch_flash(sse, "Loading cap holds…")
        cap_holds_by_team = fetch_cap_holds_by_team(team_codes)

        patch_flash(sse, "Loading exceptions…")
        exceptions_by_team = fetch_exceptions_by_team(team_codes)

        patch_flash(sse, "Loading dead money…")
        dead_money_by_team = fetch_dead_money_by_team(team_codes)

        patch_flash(sse, "Loading draft assets…")
        picks_by_team = fetch_picks_by_team(team_codes)

        patch_flash(sse, "Loading team summaries…")
        team_summaries = fetch_all_team_summaries(team_codes)

        patch_signals(sse, bootstrapstatus: "streaming", sseticks: 0)

        without_view_annotations do
          total = team_codes.length
          team_codes.each_with_index do |team_code, idx|
            section_html = render_to_string(
              partial: "tools/salary_book/team_section",
              locals: {
                team_code:,
                players: (players_by_team[team_code] || []),
                cap_holds: (cap_holds_by_team[team_code] || []),
                exceptions: (exceptions_by_team[team_code] || []),
                dead_money: (dead_money_by_team[team_code] || []),
                picks: (picks_by_team[team_code] || []),
                team_summaries: (team_summaries[team_code] || {}),
                team_meta: (team_meta_by_code[team_code] || {}),
                year:,
                salary_years: SALARY_YEARS
              },
            )

            patch_elements_by_id(sse, section_html)
            patch_signals(sse, sseticks: idx + 1)

            if ((idx + 1) % 5).zero? || idx == total - 1
              patch_flash(sse, "Rendering teams… #{idx + 1}/#{total}")
            end
          end
        end

        patch_flash(sse, "")
        patch_signals(sse, bootstrapstatus: "done", sseticks: team_codes.length)
      rescue ActiveRecord::StatementInvalid => e
        patch_maincanvas_error(sse, year:, message: e.message)
        patch_flash(sse, "Salary Book bootstrap failed.")
        patch_signals(sse, bootstrapstatus: "error")
      end
    end

    # GET /tools/salary-book/sse/switch-team?team=BOS&year=2025
    # One-request, multi-region team swap:
    # - patch #salarybook-team-frame (main canvas)
    # - patch #rightpanel-base (sidebar base)
    # This preserves overlay state while keeping main + base in sync.
    def switch_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      with_sse_stream do |sse|
        players = fetch_team_players(team_code)
        payload = fetch_team_support_payload(team_code)
        cap_holds = payload[:cap_holds]
        exceptions = payload[:exceptions]
        dead_money = payload[:dead_money]
        picks = payload[:picks]
        summaries_by_year = payload[:team_summaries]
        summary = summaries_by_year[year] || {}
        team_meta = payload[:team_meta]

        main_html = without_view_annotations do
          render_to_string(
            partial: "tools/salary_book/maincanvas_team_frame",
            locals: {
              boot_error: nil,
              team_code:,
              players:,
              cap_holds:,
              exceptions:,
              dead_money:,
              picks:,
              team_summaries: summaries_by_year,
              team_meta:,
              year:,
              salary_years: SALARY_YEARS,
              empty_message: nil
            },
          )
        end

        sidebar_html = without_view_annotations do
          render_to_string(
            partial: "tools/salary_book/sidebar_team",
            locals: {
              team_code:,
              summary:,
              team_meta:,
              summaries_by_year:,
              year:
            },
          )
        end

        patch_elements_by_id(sse, main_html)
        patch_elements_by_id(sse, sidebar_html)
      rescue ActiveRecord::StatementInvalid => e
        patch_maincanvas_error(sse, year:, message: e.message)
        patch_flash(sse, "Salary Book team switch failed.")
      end
    end

    # GET /tools/salary-book/sse/patch-template
    # GET /tools/salary-book/sse/demo (legacy alias)
    #
    # Canonical one-off SSE template for this repo:
    # - Rails ActionController::Live streaming
    # - Datastar SSE event framing (patch-signals + patch-elements)
    # - multi-region patch sequencing in a single request/response
    def demo
      with_sse_stream do |sse|
        patch_signals(sse, ssestatus: "connected", sseticks: 0)
        patch_flash(sse, "SSE connected (streaming 5 ticks)…")

        1.upto(5) do |i|
          sleep 0.6
          patch_signals(sse, ssestatus: "streaming", sseticks: i)
          append_log(sse, "tick #{i} @ #{Time.now.strftime('%H:%M:%S')}")
        end

        patch_signals(sse, ssestatus: "done")
        patch_flash(sse, "SSE done.")
      end
    end

    private

    def patch_maincanvas_error(sse, year:, message:)
      html = without_view_annotations do
        render_to_string(
          partial: "tools/salary_book/maincanvas_team_frame",
          locals: {
            boot_error: message,
            team_code: nil,
            players: [],
            cap_holds: [],
            exceptions: [],
            dead_money: [],
            picks: [],
            team_summaries: {},
            team_meta: {},
            year: year,
            salary_years: SALARY_YEARS,
            empty_message: nil
          },
        )
      end

      patch_elements_by_id(sse, html)
    end

    def without_view_annotations
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false
      yield
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end

    def append_log(sse, message)
      html = "<div class=\"sse-log-line\">#{ERB::Util.h(message)}</div>"
      patch_elements(sse, selector: "#sse-log", html:, mode: "append")
    end
  end
end
