module Tools
  class SalaryBookSseController < SalaryBookController
    include Datastar

    # GET /tools/salary-book/sse/switch-team?team=BOS&year=2025
    # One-request, multi-region team swap:
    # - patch #salarybook-team-frame (main canvas)
    # - patch #rightpanel-base (sidebar base)
    # This preserves overlay state while keeping main + base in sync.
    def switch_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      with_sse_stream do |sse|
        begin
          players = fetch_team_players(team_code)
          payload = fetch_team_support_payload(team_code, base_year: year)
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
  end
end
