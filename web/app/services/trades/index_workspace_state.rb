module Trades
  class IndexWorkspaceState
    DATERANGE_LENSES = %w[today week month season all].freeze
    SORT_LENSES = %w[newest most_teams most_assets].freeze
    COMPLEXITY_LENSES = %w[all complex mega].freeze
    COMPOSITION_LENSES = %w[all player_heavy pick_heavy cash_tpe].freeze

    def initialize(params:, queries:)
      @params = params
      @queries = queries
    end

    def build
      setup_filters!
      load_team_options!
      load_trades!
      annotate_trade_rows!(@trades)
      attach_trade_team_impacts!(@trades)
      attach_trade_player_previews!(@trades)
      build_sidebar_summary!

      {
        daterange: @daterange,
        team: @team,
        sort: @sort,
        lens: @lens,
        composition: @composition,
        sort_label: @sort_label,
        lens_label: @lens_label,
        composition_label: @composition_label,
        team_options: @team_options,
        trades: @trades,
        sidebar_summary: @sidebar_summary
      }
    end

    private

    attr_reader :params, :queries

    def setup_filters!
      @daterange = params[:daterange].to_s.strip.presence || "season"
      @daterange = "season" unless DATERANGE_LENSES.include?(@daterange)

      @team = params[:team].to_s.strip.upcase.presence
      @team = nil unless @team&.match?(/\A[A-Z]{3}\z/)

      @sort = params[:sort].to_s.strip.presence || "newest"
      @sort = "newest" unless SORT_LENSES.include?(@sort)

      @lens = params[:lens].to_s.strip.presence || "all"
      @lens = "all" unless COMPLEXITY_LENSES.include?(@lens)

      @composition = params[:composition].to_s.strip.presence || "all"
      @composition = "all" unless COMPOSITION_LENSES.include?(@composition)

      @sort_label = trades_sort_label(@sort)
      @lens_label = trades_lens_label(@lens)
      @composition_label = trades_composition_label(@composition)
    end

    def load_team_options!
      @team_options = queries.fetch_team_options
    end

    def load_trades!
      conn = ActiveRecord::Base.connection
      today = Date.today
      season_start = today.month >= 7 ? Date.new(today.year, 7, 1) : Date.new(today.year - 1, 7, 1)

      where_clauses = []
      case @daterange
      when "today"
        where_clauses << "tr.trade_date = #{conn.quote(today)}"
      when "week"
        where_clauses << "tr.trade_date >= #{conn.quote(today - 7)}"
      when "month"
        where_clauses << "tr.trade_date >= #{conn.quote(today - 30)}"
      when "season"
        where_clauses << "tr.trade_date >= #{conn.quote(season_start)}"
      end

      if @team.present?
        where_clauses << <<~SQL
          EXISTS (
            SELECT 1
            FROM pcms.trade_teams tt
            JOIN pcms.teams team
              ON team.team_id = tt.team_id
            WHERE tt.trade_id = tr.trade_id
              AND team.league_lk = 'NBA'
              AND tt.team_code = #{conn.quote(@team)}
          )
        SQL
      end

      where_sql = where_clauses.any? ? where_clauses.join(" AND ") : "1=1"

      lens_sql = case @lens
      when "complex"
        "(ranked_trades.team_count >= 3 OR ranked_trades.complexity_asset_count >= 4)"
      when "mega"
        "(ranked_trades.team_count >= 4 OR ranked_trades.complexity_asset_count >= 6)"
      else
        "1=1"
      end

      composition_sql = case @composition
      when "player_heavy"
        "(ranked_trades.player_count >= 2 AND ranked_trades.player_count >= ranked_trades.pick_count + 1)"
      when "pick_heavy"
        "(ranked_trades.pick_count >= 2 AND ranked_trades.pick_count >= ranked_trades.player_count + 1)"
      when "cash_tpe"
        "(ranked_trades.cash_line_count > 0 OR ranked_trades.tpe_line_count > 0)"
      else
        "1=1"
      end

      order_sql = case @sort
      when "most_teams"
        "ranked_trades.team_count DESC, ranked_trades.complexity_asset_count DESC, ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      when "most_assets"
        "ranked_trades.complexity_asset_count DESC, ranked_trades.team_count DESC, ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      else
        "ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      end

      @trades = queries.fetch_index_trades(
        where_sql: where_sql,
        lens_sql: lens_sql,
        composition_sql: composition_sql,
        order_sql: order_sql
      )
    end

    def build_sidebar_summary!
      rows = Array(@trades)
      filters = ["Date: #{daterange_label(@daterange)}"]
      filters << "Team: #{@team}" if @team.present?
      filters << "Complexity: #{@lens_label}" unless @lens == "all"
      filters << "Composition: #{@composition_label}" unless @composition == "all"
      filters << "Sort: #{@sort_label}"

      @sidebar_summary = {
        row_count: rows.size,
        player_assets_total: rows.sum { |row| row["player_count"].to_i },
        pick_assets_total: rows.sum { |row| row["pick_count"].to_i },
        complexity_asset_total: rows.sum { |row| row["complexity_asset_count"].to_i },
        complex_deal_count: rows.count { |row| row["team_count"].to_i >= 3 || row["complexity_asset_count"].to_i >= 4 },
        player_heavy_deal_count: rows.count { |row| row["is_player_heavy"] },
        pick_heavy_deal_count: rows.count { |row| row["is_pick_heavy"] },
        cash_tpe_deal_count: rows.count { |row| row["is_cash_tpe_involved"] },
        filters:,
        top_rows: rows.first(14)
      }
    end

    def annotate_trade_rows!(rows)
      Array(rows).each { |row| annotate_trade_row!(row) }
    end

    def annotate_trade_row!(row)
      player_count = row["player_count"].to_i
      pick_count = row["pick_count"].to_i
      cash_line_count = row["cash_line_count"].to_i
      tpe_line_count = row["tpe_line_count"].to_i

      is_player_heavy = player_count >= 2 && player_count >= pick_count + 1
      is_pick_heavy = pick_count >= 2 && pick_count >= player_count + 1
      is_cash_tpe_involved = cash_line_count.positive? || tpe_line_count.positive?

      labels = []
      labels << "Player-heavy" if is_player_heavy
      labels << "Pick-heavy" if is_pick_heavy
      labels << "Cash/TPE" if is_cash_tpe_involved
      labels << "Balanced" if labels.empty?

      row["is_player_heavy"] = is_player_heavy
      row["is_pick_heavy"] = is_pick_heavy
      row["is_cash_tpe_involved"] = is_cash_tpe_involved
      row["composition_labels"] = labels
    end

    def attach_trade_team_impacts!(rows)
      trade_rows = Array(rows)
      trade_ids = trade_rows.map { |row| row["trade_id"].to_i }.select(&:positive?).uniq
      return if trade_ids.empty?

      impact_rows = queries.fetch_trade_team_impacts(trade_ids: trade_ids)
      grouped = impact_rows.group_by { |row| row["trade_id"].to_i }

      trade_rows.each do |trade_row|
        impacts = Array(grouped[trade_row["trade_id"].to_i]).map do |impact_row|
          {
            "team_id" => impact_row["team_id"],
            "team_code" => impact_row["team_code"],
            "team_name" => impact_row["team_name"],
            "players_out" => impact_row["players_out"].to_i,
            "players_in" => impact_row["players_in"].to_i,
            "picks_out" => impact_row["picks_out"].to_i,
            "picks_in" => impact_row["picks_in"].to_i,
            "cash_out" => impact_row["cash_out"],
            "cash_in" => impact_row["cash_in"],
            "tpe_out" => impact_row["tpe_out"].to_i,
            "tpe_in" => impact_row["tpe_in"].to_i
          }
        end

        trade_row["team_impacts"] = impacts
        trade_row["primary_team_impacts"] = impacts.first(2)
        trade_row["additional_team_impact_count"] = [impacts.size - 2, 0].max
      end
    end

    def attach_trade_player_previews!(rows)
      trade_rows = Array(rows)
      trade_ids = trade_rows.map { |row| row["trade_id"].to_i }.select(&:positive?).uniq
      return if trade_ids.empty?

      preview_rows = queries.fetch_trade_player_previews(trade_ids: trade_ids)
      grouped = preview_rows.group_by { |row| row["trade_id"].to_i }

      trade_rows.each do |trade_row|
        previews = Array(grouped[trade_row["trade_id"].to_i]).first(3).map do |preview_row|
          {
            "player_id" => preview_row["player_id"].to_i,
            "player_name" => preview_row["player_name"],
            "rank" => preview_row["trade_player_rank"].to_i
          }
        end

        trade_row["player_previews"] = previews
        trade_row["additional_player_preview_count"] = [trade_row["player_count"].to_i - previews.size, 0].max
      end
    end

    def daterange_label(value)
      case value.to_s
      when "today" then "Today"
      when "week" then "This week"
      when "month" then "This month"
      when "season" then "This season"
      else "All dates"
      end
    end

    def trades_sort_label(value)
      case value.to_s
      when "most_teams" then "Most teams"
      when "most_assets" then "Most assets"
      else "Newest"
      end
    end

    def trades_lens_label(value)
      case value.to_s
      when "complex" then "3+ teams or 4+ assets"
      when "mega" then "4+ teams or 6+ assets"
      else "All deals"
      end
    end

    def trades_composition_label(value)
      case value.to_s
      when "player_heavy" then "Player-heavy"
      when "pick_heavy" then "Pick-heavy"
      when "cash_tpe" then "Cash/TPE involved"
      else "All archetypes"
      end
    end
  end
end
