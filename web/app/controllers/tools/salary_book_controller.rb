module Tools
  class SalaryBookController < ApplicationController
    CURRENT_SALARY_YEAR = 2025

    # GET /tools/salary-book
    def show
      @salary_year = salary_year_param

      @team_codes = fetch_team_codes(@salary_year)
      @players_by_team = fetch_players_by_team(@team_codes)

      requested = params[:team]
      @initial_team = if requested.present? && valid_team_code?(requested)
        requested.to_s.strip.upcase
      else
        @team_codes.first
      end

      @initial_team_summary = @initial_team ? fetch_team_summary(@initial_team, @salary_year) : nil
    rescue ActiveRecord::StatementInvalid => e
      # Useful when a dev DB hasn't been hydrated with the pcms.* schema yet.
      @boot_error = e.message
      @salary_year = salary_year_param
      @team_codes = []
      @players_by_team = {}
      @initial_team = nil
      @initial_team_summary = nil
    end

    # GET /tools/salary-book/teams/:teamcode/section
    def team_section
      team_code = normalize_team_code(params[:teamcode])
      year = salary_year_param
      players = fetch_team_players(team_code)

      render partial: "tools/salary_book/team_section", locals: { team_code:, players:, year: }, layout: false
    end

    # GET /tools/salary-book/sidebar/team?team=BOS
    def sidebar_team
      team_code = normalize_team_code(params[:team])
      year = salary_year_param

      summary = fetch_team_summary(team_code, year)

      render partial: "tools/salary_book/sidebar_team", locals: { team_code:, summary:, year: }, layout: false
    end

    # GET /tools/salary-book/sidebar/player/:id
    def sidebar_player
      player_id = Integer(params[:id])
      player = fetch_player(player_id)
      raise ActiveRecord::RecordNotFound unless player

      render partial: "tools/salary_book/sidebar_player", locals: { player: }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /tools/salary-book/sidebar/clear
    def sidebar_clear
      render partial: "tools/salary_book/sidebar_clear", layout: false
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def salary_year_param
      raw = params[:year].presence
      return CURRENT_SALARY_YEAR unless raw

      Integer(raw)
    rescue ArgumentError
      CURRENT_SALARY_YEAR
    end

    def valid_team_code?(raw)
      raw.to_s.strip.upcase.match?(/\A[A-Z]{3}\z/)
    end

    def normalize_team_code(raw)
      team = raw.to_s.strip.upcase
      raise ActiveRecord::RecordNotFound unless team.match?(/\A[A-Z]{3}\z/)

      team
    end

    def fetch_team_codes(year)
      year_sql = conn.quote(year)

      conn.exec_query(
        "SELECT team_code FROM pcms.team_salary_warehouse WHERE salary_year = #{year_sql} ORDER BY team_code"
      ).rows.flatten.compact
    end

    def fetch_players_by_team(team_codes)
      return {} if team_codes.empty?

      in_list = team_codes.map { |c| conn.quote(c) }.join(",")

      rows = conn.exec_query(
        <<~SQL
          SELECT
            player_id,
            player_name,
            team_code,
            cap_2025,
            cap_2026,
            total_salary_from_2025
          FROM pcms.salary_book_warehouse
          WHERE team_code IN (#{in_list})
          ORDER BY team_code, player_name
        SQL
      ).to_a

      rows.group_by { |r| r["team_code"] }
    end

    def fetch_team_players(team_code)
      team_sql = conn.quote(team_code)

      conn.exec_query(
        <<~SQL
          SELECT
            player_id,
            player_name,
            team_code,
            cap_2025,
            cap_2026,
            total_salary_from_2025
          FROM pcms.salary_book_warehouse
          WHERE team_code = #{team_sql}
          ORDER BY player_name
        SQL
      ).to_a
    end

    def fetch_team_summary(team_code, year)
      team_sql = conn.quote(team_code)
      year_sql = conn.quote(year)

      conn.exec_query(
        <<~SQL
          SELECT *
          FROM pcms.team_salary_warehouse
          WHERE team_code = #{team_sql}
            AND salary_year = #{year_sql}
          LIMIT 1
        SQL
      ).first
    end

    def fetch_player(player_id)
      id_sql = conn.quote(player_id)

      conn.exec_query(
        <<~SQL
          SELECT
            sbw.player_id,
            sbw.player_name,
            sbw.team_code,
            sbw.agent_name,
            sbw.age,
            sbw.cap_2025,
            sbw.cap_2026,
            sbw.total_salary_from_2025,
            sbw.option_2025,
            sbw.option_2026,
            sbw.is_two_way,
            sbw.is_no_trade,
            sbw.trade_kicker_display,
            sbw.refreshed_at
          FROM pcms.salary_book_warehouse sbw
          WHERE sbw.player_id = #{id_sql}
          LIMIT 1
        SQL
      ).first
    end
  end
end
