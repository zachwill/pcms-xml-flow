module TwoWayUtility
  class WorkspaceState
      class << self
        def decorate_row(row)
          used = row["games_on_active_list"]&.to_f
          limit = row["active_list_games_limit"]&.to_f
          remaining = row["remaining_active_list_games"]&.to_i
          estimate = truthy?(row["active_list_games_limit_is_estimate"])

          row["games_used_pct"] = if used && limit && limit.positive?
            used / limit
          end

          row["limit_status_chip"] = estimate ? "EST" : nil
          row["risk_tier"] = if remaining.present? && remaining <= 10
            "critical"
          elsif remaining.present? && remaining <= 20
            "warning"
          elsif estimate
            "estimate"
          else
            "stable"
          end

          row
        end

        def truthy?(value)
          case value
          when true, 1, "1", "t", "T", "true", "TRUE", "yes", "YES", "y", "Y"
            true
          else
            false
          end
        end
      end

      def initialize(params:, queries:, conference_lenses:, risk_lenses:)
        @params = params
        @queries = queries
        @conference_lenses = conference_lenses
        @risk_lenses = risk_lenses
      end

      def build
        @conference = resolve_conference(params[:conference])
        @team = resolve_team(params[:team])
        @risk = resolve_risk(params[:risk])

        @rows = fetch_rows(conference: @conference, team: @team, risk: @risk)
        @rows_by_team = @rows.group_by { |row| row["team_code"] }

        @teams_by_conference, @team_meta_by_code = fetch_teams
        @team_capacity_by_code = queries.fetch_team_capacity_by_code
        @team_options = build_team_options(@teams_by_conference, @rows_by_team.keys)
        @team_codes = resolve_team_codes(@team_options, @rows_by_team.keys, @team)
        @team_records_by_code = queries.fetch_team_records_by_code(@rows_by_team.keys)

        @state_query = build_state_query
        @selected_player_id = normalize_selected_player_id_param(params[:selected_id])
        build_sidebar_summary!(selected_player_id: @selected_player_id)

        {
          conference: @conference,
          team: @team,
          risk: @risk,
          rows: @rows,
          rows_by_team: @rows_by_team,
          teams_by_conference: @teams_by_conference,
          team_meta_by_code: @team_meta_by_code,
          team_capacity_by_code: @team_capacity_by_code,
          team_options: @team_options,
          team_codes: @team_codes,
          team_records_by_code: @team_records_by_code,
          state_query: @state_query,
          selected_player_id: @selected_player_id,
          sidebar_summary: @sidebar_summary
        }
      end

      private

      attr_reader :params, :queries, :conference_lenses, :risk_lenses

      def resolve_conference(value)
        normalized = value.to_s.strip
        conference_lenses.include?(normalized) ? normalized : "all"
      end

      def resolve_team(value)
        code = value.to_s.strip.upcase
        code.match?(/\A[A-Z]{3}\z/) ? code : nil
      end

      def resolve_risk(value)
        normalized = value.to_s.strip
        risk_lenses.include?(normalized) ? normalized : "all"
      end

      def normalize_player_id_param(raw)
        player_id = Integer(raw.to_s.strip, 10)
        player_id.positive? ? player_id : nil
      rescue ArgumentError, TypeError
        nil
      end

      def normalize_selected_player_id_param(raw)
        normalize_player_id_param(raw)
      end

      def build_state_query
        Rack::Utils.build_query(
          conference: @conference.to_s,
          team: @team.to_s,
          risk: @risk.to_s
        )
      end

      def resolve_team_codes(team_options, rows_team_codes, selected_team)
        options = Array(team_options).map { |row| row[:code] }
        row_codes = Array(rows_team_codes).compact.map(&:to_s)

        if selected_team.present?
          return [selected_team]
        end

        (options & row_codes) + (row_codes - options)
      end

      def fetch_rows(conference:, team:, risk:)
        queries.fetch_rows(conference:, team:, risk:).map { |row| self.class.decorate_row(row) }
      end

      def fetch_teams
        rows = queries.fetch_teams

        grouped = { "Eastern" => [], "Western" => [] }
        by_code = {}

        rows.each do |row|
          conf = row["conference_name"]
          next unless grouped.key?(conf)

          grouped[conf] << { code: row["team_code"], name: row["team_name"] }
          by_code[row["team_code"]] = row
        end

        [grouped, by_code]
      end

      def build_team_options(teams_by_conference, warehouse_team_codes)
        ordered_codes = %w[Eastern Western].flat_map do |conference|
          teams_by_conference.fetch(conference, []).map { |team| team[:code] }
        end

        extras = Array(warehouse_team_codes).compact.uniq - ordered_codes

        (ordered_codes + extras.sort).map do |code|
          meta = @team_meta_by_code[code] || {}
          {
            code:,
            name: meta["team_name"].presence || code,
            conference: meta["conference_name"].presence || "—"
          }
        end
      end

      def build_sidebar_summary!(selected_player_id: nil)
        rows = Array(@rows)
        critical_count = rows.count { |row| row["risk_tier"] == "critical" }
        warning_count = rows.count { |row| row["risk_tier"] == "warning" }
        low_remaining_count = rows.count { |row| row["remaining_active_list_games"].present? && row["remaining_active_list_games"].to_i <= 20 }
        estimate_count = rows.count { |row| self.class.truthy?(row["active_list_games_limit_is_estimate"]) }

        quick_rows = rows
          .select { |row| row["risk_tier"] != "stable" }
          .sort_by do |row|
            [
              risk_sort_priority(row["risk_tier"]),
              row["remaining_active_list_games"].presence || 999,
              -(row["games_used_pct"] || 0).to_f,
              row["team_code"].to_s,
              row["player_name"].to_s
            ]
          end
          .first(14)

        selected_id = selected_player_id.to_i
        if selected_id.positive?
          selected_row = rows.find { |row| row["player_id"].to_i == selected_id }
          if selected_row.present? && quick_rows.none? { |row| row["player_id"].to_i == selected_id }
            quick_rows = [selected_row] + quick_rows.first(13)
          end
        end

        active_filters = []
        active_filters << "Conference: #{@conference}" unless @conference == "all"
        active_filters << "Team: #{@team}" if @team.present?
        active_filters << "Risk: #{risk_filter_label(@risk)}" unless @risk == "all"

        @sidebar_summary = {
          row_count: rows.size,
          team_count: @rows_by_team.keys.size,
          critical_count:,
          warning_count:,
          low_remaining_count:,
          estimate_count:,
          active_filters:,
          quick_rows:
        }
      end

      def risk_sort_priority(tier)
        case tier.to_s
        when "critical" then 0
        when "warning" then 1
        when "estimate" then 2
        else 3
        end
      end

      def risk_filter_label(risk)
        case risk.to_s
        when "critical" then "≤10 games remaining"
        when "warning" then "≤20 games remaining"
        when "estimate" then "Estimated limits"
        else "All"
        end
      end
  end
end
