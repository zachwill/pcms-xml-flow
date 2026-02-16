class SalaryBookSwitchController < SalaryBookController
    # GET /salary-book/switch-team?team=BOS&year=2025&view=salary-book
    # One-request, multi-region team swap via text/html morph-by-id patch set.
    # Response body contains two top-level roots:
    # - #salarybook-team-frame
    # - #rightpanel-base
    # This preserves overlay state while keeping main + base in sync.
    def switch_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param
      view = salary_book_view_param

      main_html, sidebar_html = build_switch_team_sections(team_code:, year:, view:)
      no_cache_headers!
      render html: [main_html, sidebar_html].join("\n").html_safe, layout: false
    rescue ActiveRecord::StatementInvalid => e
      error_main_html = build_maincanvas_error_html(year:, message: e.message, view:, team_code:)
      flash_html = %(<div id="flash">Salary Book team switch failed.</div>)
      no_cache_headers!
      render html: [error_main_html, flash_html].join("\n").html_safe, layout: false, status: :unprocessable_entity
    end

    private

    def build_switch_team_sections(team_code:, year:, view:)
      payload = fetch_team_support_payload(team_code, base_year: year)
      summaries_by_year = payload[:team_summaries]
      summary = summaries_by_year[year] || {}
      team_meta = payload[:team_meta]

      main_html = if view == "tankathon"
        build_tankathon_main_html(team_code:, year:)
      elsif view == "injuries"
        build_injuries_main_html(team_code:, year:)
      else
        players = fetch_team_players(team_code)
        build_salary_book_main_html(
          team_code:,
          year:,
          players:,
          cap_holds: payload[:cap_holds],
          exceptions: payload[:exceptions],
          dead_money: payload[:dead_money],
          picks: payload[:picks],
          summaries_by_year:,
          team_meta:
        )
      end

      sidebar_html = without_view_annotations do
        render_to_string(
          partial: "salary_book/sidebar_team",
          locals: {
            team_code:,
            summary:,
            team_meta:,
            summaries_by_year:,
            year:
          },
        )
      end

      [main_html, sidebar_html]
    end

    def build_maincanvas_error_html(year:, message:, view:, team_code:)
      if view == "tankathon"
        without_view_annotations do
          render_to_string(
            partial: "salary_book/maincanvas_tankathon_frame",
            locals: {
              team_code:,
              year:,
              standings_rows: [],
              standing_date: nil,
              season_year: nil,
              season_label: nil,
              error_message: message
            },
          )
        end
      elsif view == "injuries"
        without_view_annotations do
          render_to_string(
            partial: "salary_book/maincanvas_injuries_frame",
            locals: {
              team_code:,
              team_codes: [],
              team_meta_by_code: {},
              year:,
              error_message: message
            },
          )
        end
      else
        without_view_annotations do
          render_to_string(
            partial: "salary_book/maincanvas_team_frame",
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
      end
    end

    def build_salary_book_main_html(team_code:, year:, players:, cap_holds:, exceptions:, dead_money:, picks:, summaries_by_year:, team_meta:)
      without_view_annotations do
        render_to_string(
          partial: "salary_book/maincanvas_team_frame",
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
    end

    def build_tankathon_main_html(team_code:, year:)
      tankathon_payload = fetch_tankathon_payload(year)

      without_view_annotations do
        render_to_string(
          partial: "salary_book/maincanvas_tankathon_frame",
          locals: {
            team_code:,
            year:,
            standings_rows: tankathon_payload[:rows],
            standing_date: tankathon_payload[:standing_date],
            season_year: tankathon_payload[:season_year],
            season_label: tankathon_payload[:season_label],
            error_message: nil
          },
        )
      end
    end

    def build_injuries_main_html(team_code:, year:)
      team_rows = fetch_team_index_rows(year)
      team_codes = team_rows.map { |row| row["team_code"] }.compact
      _, team_meta_by_code = build_team_maps(team_rows)

      without_view_annotations do
        render_to_string(
          partial: "salary_book/maincanvas_injuries_frame",
          locals: {
            team_code:,
            team_codes:,
            team_meta_by_code:,
            year:,
            error_message: nil
          },
        )
      end
    end

    def without_view_annotations
      original = ActionView::Base.annotate_rendered_view_with_filenames
      ActionView::Base.annotate_rendered_view_with_filenames = false
      yield
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = original
    end

    def no_cache_headers!
      response.headers["Cache-Control"] = "no-store"
      response.headers.delete("ETag")
    end
end
