module Tools
  class TwoWayUtilityController < ApplicationController
    # GET /tools/two-way-utility
    def show
      @rows = fetch_rows
      @rows_by_team = @rows.group_by { |row| row["team_code"] }

      @teams_by_conference, @team_meta_by_code = fetch_teams
      @team_capacity_by_code = fetch_team_capacity_by_code
      @team_codes = ordered_team_codes(@teams_by_conference, @rows_by_team.keys)
    rescue ActiveRecord::StatementInvalid => e
      @boot_error = e.message
      @rows = []
      @rows_by_team = {}
      @teams_by_conference = { "Eastern" => [], "Western" => [] }
      @team_meta_by_code = {}
      @team_capacity_by_code = {}
      @team_codes = []
    end

    private

    def conn
      ActiveRecord::Base.connection
    end

    def fetch_rows
      conn.exec_query(<<~SQL).to_a.map { |row| decorate_row(row) }
        SELECT
          tw.team_code,
          tw.team_name,
          tw.conference_name,
          tw.team_current_contract_count,
          tw.team_games_remaining_context,
          tw.team_is_under_15_contracts,
          tw.team_two_way_contract_count,
          tw.player_id,
          tw.player_name,
          tw.years_of_service,
          tw.games_on_active_list,
          tw.active_list_games_limit,
          tw.remaining_active_list_games,
          tw.active_list_games_limit_is_estimate,
          tw.signing_date,
          tw.last_game_date_est,
          sbw.age,
          sbw.cap_2025,
          sbw.cap_2026,
          sbw.agent_id,
          sbw.agent_name,
          ag.agency_name,
          COALESCE(sbw.is_two_way, true) AS is_two_way,
          COALESCE(sbw.is_trade_consent_required_now, false) AS is_trade_consent_required_now,
          COALESCE(sbw.is_trade_restricted_now, false) AS is_trade_restricted_now,
          COALESCE(sbw.is_poison_pill, false) AS is_poison_pill
        FROM pcms.two_way_utility_warehouse tw
        LEFT JOIN LATERAL (
          SELECT
            s.age,
            s.cap_2025,
            s.cap_2026,
            s.agent_id,
            s.agent_name,
            s.is_two_way,
            s.is_trade_consent_required_now,
            s.is_trade_restricted_now,
            s.is_poison_pill
          FROM pcms.salary_book_warehouse s
          WHERE s.player_id = tw.player_id
            AND s.team_code = tw.team_code
          ORDER BY s.cap_2025 DESC NULLS LAST
          LIMIT 1
        ) sbw ON true
        LEFT JOIN pcms.agents ag
          ON ag.agent_id = sbw.agent_id
        ORDER BY tw.team_code, tw.games_on_active_list DESC NULLS LAST, tw.player_name
      SQL
    end

    def decorate_row(row)
      used = row["games_on_active_list"]&.to_f
      limit = row["active_list_games_limit"]&.to_f

      row["games_used_pct"] = if used && limit && limit.positive?
        used / limit
      end

      row["limit_status_chip"] = row["active_list_games_limit_is_estimate"] ? "EST" : nil
      row
    end

    def fetch_teams
      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_id,
          team_code,
          team_name,
          conference_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
          AND conference_name IS NOT NULL
        ORDER BY team_code
      SQL

      grouped = { "Eastern" => [], "Western" => [] }
      by_code = {}

      rows.each do |row|
        conf = row["conference_name"]
        next unless grouped.key?(conf)

        grouped[conf] << { code: row["team_code"], name: row["team_name"] }
        by_code[row["team_code"]] = row
      end

      [ grouped, by_code ]
    end

    def fetch_team_capacity_by_code
      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          team_code,
          current_contract_count AS team_current_contract_count,
          CASE
            WHEN COALESCE(current_contract_count, 0) < 15 THEN under_15_games_remaining
            ELSE games_remaining
          END AS team_games_remaining_context,
          (COALESCE(current_contract_count, 0) < 15) AS team_is_under_15_contracts
        FROM pcms.team_two_way_capacity
      SQL

      rows.each_with_object({}) { |row, by_code| by_code[row["team_code"]] = row }
    end

    def ordered_team_codes(teams_by_conference, warehouse_team_codes)
      ordered = %w[Eastern Western].flat_map do |conference|
        teams_by_conference.fetch(conference, []).map { |team| team[:code] }
      end

      extras = warehouse_team_codes.compact.uniq - ordered
      ordered + extras.sort
    end
  end
end
