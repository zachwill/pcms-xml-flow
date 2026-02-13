module Entities
  class TradesController < ApplicationController
    # GET /trades
    def index
      load_index_state!
      render :index
    end

    # GET /trades/pane (Datastar partial refresh)
    def pane
      load_index_state!
      render partial: "entities/trades/results"
    end

    # GET /trades/sidebar/base
    def sidebar_base
      load_index_state!
      render partial: "entities/trades/rightpanel_base"
    end

    # GET /trades/sidebar/:id
    def sidebar
      trade_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if trade_id <= 0

      render partial: "entities/trades/rightpanel_overlay_trade", locals: load_sidebar_trade_payload(trade_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /trades/sidebar/clear
    def sidebar_clear
      render partial: "entities/trades/rightpanel_clear"
    end

    # GET /trades/:id
    def show
      id = Integer(params[:id])
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      @trade = conn.exec_query(<<~SQL).first
        SELECT
          tr.trade_id,
          tr.trade_date,
          tr.trade_finalized_date,
          tr.league_lk,
          tr.record_status_lk,
          tr.trade_comments
        FROM pcms.trades tr
        WHERE tr.trade_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @trade

      @trade_teams = conn.exec_query(<<~SQL).to_a
        SELECT
          tt.trade_team_id,
          tt.team_id,
          tt.team_code,
          t.team_name,
          tt.seqno,
          tt.team_salary_change,
          tt.total_cash_received,
          tt.total_cash_sent,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.player_id IS NOT NULL)::integer AS player_line_item_count,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.draft_pick_year IS NOT NULL)::integer AS pick_line_item_count,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.trade_entry_lk = 'TREX')::integer AS tpe_line_item_count,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.trade_entry_lk = 'CASH' OR COALESCE(ttd.cash_amount, 0) <> 0)::integer AS cash_line_item_count
        FROM pcms.trade_teams tt
        LEFT JOIN pcms.teams t
          ON t.team_id = tt.team_id
        LEFT JOIN pcms.trade_team_details ttd
          ON ttd.trade_id = tt.trade_id
         AND ttd.team_id = tt.team_id
        WHERE tt.trade_id = #{id_sql}
        GROUP BY
          tt.trade_team_id,
          tt.team_id,
          tt.team_code,
          t.team_name,
          tt.seqno,
          tt.team_salary_change,
          tt.total_cash_received,
          tt.total_cash_sent
        ORDER BY tt.seqno, tt.team_code
      SQL

      @player_details = conn.exec_query(<<~SQL).to_a
        SELECT
          ttd.trade_team_detail_id,
          ttd.team_id,
          ttd.team_code,
          t.team_name,
          ttd.seqno,
          ttd.group_number,
          ttd.is_sent,
          ttd.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ttd.player_id::text
          ) AS player_name,
          ttd.contract_id,
          ttd.version_number,
          ttd.is_sign_and_trade,
          ttd.is_trade_bonus,
          ttd.is_no_trade,
          ttd.is_player_consent,
          ttd.is_poison_pill,
          ttd.base_year_amount,
          ttd.is_base_year,
          ttd.trade_entry_lk
        FROM pcms.trade_team_details ttd
        LEFT JOIN pcms.people p
          ON p.person_id = ttd.player_id
        LEFT JOIN pcms.teams t
          ON t.team_id = ttd.team_id
        WHERE ttd.trade_id = #{id_sql}
          AND ttd.player_id IS NOT NULL
        ORDER BY ttd.team_code, ttd.seqno, player_name
        LIMIT 400
      SQL

      @pick_details = conn.exec_query(<<~SQL).to_a
        SELECT
          ttd.trade_team_detail_id,
          ttd.team_id,
          ttd.team_code,
          t.team_name,
          ttd.seqno,
          ttd.group_number,
          ttd.is_sent,
          ttd.draft_pick_year,
          ttd.draft_pick_round,
          ttd.is_draft_pick_future,
          ttd.is_draft_pick_swap,
          ttd.draft_pick_conditional_lk,
          ttd.is_draft_year_plus_two,
          ttd.trade_entry_lk
        FROM pcms.trade_team_details ttd
        LEFT JOIN pcms.teams t
          ON t.team_id = ttd.team_id
        WHERE ttd.trade_id = #{id_sql}
          AND ttd.draft_pick_year IS NOT NULL
        ORDER BY ttd.team_code, ttd.seqno, ttd.draft_pick_year, ttd.draft_pick_round
      SQL

      @cash_details = conn.exec_query(<<~SQL).to_a
        SELECT
          ttd.trade_team_detail_id,
          ttd.team_id,
          ttd.team_code,
          t.team_name,
          ttd.seqno,
          ttd.group_number,
          ttd.is_sent,
          ttd.trade_entry_lk,
          ttd.cash_amount
        FROM pcms.trade_team_details ttd
        LEFT JOIN pcms.teams t
          ON t.team_id = ttd.team_id
        WHERE ttd.trade_id = #{id_sql}
          AND (ttd.trade_entry_lk = 'CASH' OR COALESCE(ttd.cash_amount, 0) <> 0)
        ORDER BY ttd.team_code, ttd.seqno
      SQL

      @draft_pick_trades = conn.exec_query(<<~SQL).to_a
        SELECT
          id,
          draft_year,
          draft_round,
          from_team_id,
          from_team_code,
          to_team_id,
          to_team_code,
          original_team_id,
          original_team_code,
          is_swap,
          is_future,
          is_conditional,
          conditional_type_lk,
          is_draft_year_plus_two
        FROM pcms.draft_pick_trades
        WHERE trade_id = #{id_sql}
        ORDER BY draft_year, draft_round, id
      SQL

      @transactions = conn.exec_query(<<~SQL).to_a
        SELECT
          t.transaction_id,
          t.transaction_date,
          t.transaction_type_lk,
          t.transaction_description_lk,
          t.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            t.player_id::text
          ) AS player_name,
          t.from_team_id,
          t.from_team_code,
          from_team.team_name AS from_team_name,
          t.to_team_id,
          t.to_team_code,
          to_team.team_name AS to_team_name,
          t.contract_id,
          t.version_number,
          t.signed_method_lk
        FROM pcms.transactions t
        LEFT JOIN pcms.people p ON p.person_id = t.player_id
        LEFT JOIN pcms.teams from_team ON from_team.team_id = t.from_team_id
        LEFT JOIN pcms.teams to_team ON to_team.team_id = t.to_team_id
        WHERE t.trade_id = #{id_sql}
        ORDER BY t.transaction_date, t.transaction_id
        LIMIT 300
      SQL

      @endnotes = conn.exec_query(<<~SQL).to_a
        SELECT
          endnote_id,
          trade_id,
          trade_date,
          status_lk,
          explanation,
          conveyance_text,
          protections_text,
          contingency_text,
          exercise_text,
          is_swap,
          is_conditional,
          from_team_code,
          to_team_code,
          draft_year_start,
          draft_year_end,
          draft_rounds
        FROM pcms.endnotes
        WHERE trade_id = #{id_sql}
           OR trade_ids @> ARRAY[#{id_sql}]::integer[]
        ORDER BY endnote_id
        LIMIT 200
      SQL

      @trade_group_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          tg.trade_group_id,
          tg.trade_group_number,
          tg.team_id,
          team.team_code,
          team.team_name,
          tg.signed_method_lk,
          COALESCE(signed_lk.short_description, signed_lk.description) AS signed_method_label,
          tg.generated_team_exception_id,
          tg.acquired_team_exception_id,
          gen_te.exception_type_lk AS generated_exception_type_lk,
          COALESCE(gen_exc_lk.short_description, gen_exc_lk.description) AS generated_exception_type_label,
          acq_te.exception_type_lk AS acquired_exception_type_lk,
          COALESCE(acq_exc_lk.short_description, acq_exc_lk.description) AS acquired_exception_type_label,
          tg.trade_group_comments
        FROM pcms.trade_groups tg
        LEFT JOIN pcms.teams team
          ON team.team_id = tg.team_id
         AND team.league_lk = 'NBA'
        LEFT JOIN pcms.lookups signed_lk
          ON signed_lk.lookup_type = 'lk_signed_methods'
         AND signed_lk.lookup_code = tg.signed_method_lk
        LEFT JOIN pcms.team_exceptions gen_te
          ON gen_te.team_exception_id = tg.generated_team_exception_id
        LEFT JOIN pcms.lookups gen_exc_lk
          ON gen_exc_lk.lookup_type = 'lk_exception_types'
         AND gen_exc_lk.lookup_code = gen_te.exception_type_lk
        LEFT JOIN pcms.team_exceptions acq_te
          ON acq_te.team_exception_id = tg.acquired_team_exception_id
        LEFT JOIN pcms.lookups acq_exc_lk
          ON acq_exc_lk.lookup_type = 'lk_exception_types'
         AND acq_exc_lk.lookup_code = acq_te.exception_type_lk
        WHERE tg.trade_id = #{id_sql}
        ORDER BY tg.trade_group_number, COALESCE(team.team_code, tg.team_id::text), tg.trade_group_id
      SQL

      @trade_group_exception_rows = conn.exec_query(<<~SQL).to_a
        WITH exception_ids AS (
          SELECT tg.generated_team_exception_id AS team_exception_id
          FROM pcms.trade_groups tg
          WHERE tg.trade_id = #{id_sql}
            AND tg.generated_team_exception_id IS NOT NULL
          UNION
          SELECT tg.acquired_team_exception_id AS team_exception_id
          FROM pcms.trade_groups tg
          WHERE tg.trade_id = #{id_sql}
            AND tg.acquired_team_exception_id IS NOT NULL
        )
        SELECT
          te.team_exception_id,
          te.team_id,
          COALESCE(team.team_code, te.team_code) AS team_code,
          team.team_name,
          te.salary_year,
          te.exception_type_lk,
          COALESCE(exc_lk.short_description, exc_lk.description) AS exception_type_label,
          te.original_amount,
          te.remaining_amount,
          te.effective_date,
          te.expiration_date,
          te.trade_id
        FROM pcms.team_exceptions te
        LEFT JOIN pcms.teams team
          ON team.team_id = te.team_id
        LEFT JOIN pcms.lookups exc_lk
          ON exc_lk.lookup_type = 'lk_exception_types'
         AND exc_lk.lookup_code = te.exception_type_lk
        WHERE te.team_exception_id IN (SELECT team_exception_id FROM exception_ids)
        ORDER BY te.team_exception_id
      SQL

      render :show
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def load_index_state!
      conn = ActiveRecord::Base.connection

      @daterange = params[:daterange].to_s.strip.presence || "season"
      @daterange = "season" unless %w[today week month season all].include?(@daterange)

      @team = params[:team].to_s.strip.upcase.presence
      @team = nil unless @team&.match?(/\A[A-Z]{3}\z/)

      @sort = params[:sort].to_s.strip.presence || "newest"
      @sort = "newest" unless %w[newest most_teams most_assets].include?(@sort)

      @lens = params[:lens].to_s.strip.presence || "all"
      @lens = "all" unless %w[all complex mega].include?(@lens)

      @sort_label = trades_sort_label(@sort)
      @lens_label = trades_lens_label(@lens)

      @team_options = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
        ORDER BY team_code
      SQL

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
            WHERE tt.trade_id = tr.trade_id
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

      order_sql = case @sort
      when "most_teams"
        "ranked_trades.team_count DESC, ranked_trades.complexity_asset_count DESC, ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      when "most_assets"
        "ranked_trades.complexity_asset_count DESC, ranked_trades.team_count DESC, ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      else
        "ranked_trades.trade_date DESC, ranked_trades.trade_id DESC"
      end

      @trades = conn.exec_query(<<~SQL).to_a
        WITH filtered_trades AS (
          SELECT
            tr.trade_id,
            tr.trade_date,
            tr.trade_finalized_date,
            tr.trade_comments
          FROM pcms.trades tr
          WHERE #{where_sql}
        ),
        trade_rollup AS (
          SELECT
            ft.trade_id,
            ft.trade_date,
            ft.trade_finalized_date,
            ft.trade_comments,
            (
              SELECT string_agg(tt.team_code, ', ' ORDER BY tt.seqno)
              FROM pcms.trade_teams tt
              WHERE tt.trade_id = ft.trade_id
            ) AS teams_involved,
            (
              SELECT COUNT(DISTINCT tt.team_id)::integer
              FROM pcms.trade_teams tt
              WHERE tt.trade_id = ft.trade_id
            ) AS team_count,
            (
              SELECT COUNT(DISTINCT ttd.player_id)::integer
              FROM pcms.trade_team_details ttd
              WHERE ttd.trade_id = ft.trade_id
                AND ttd.player_id IS NOT NULL
            ) AS player_count,
            (
              SELECT COUNT(*)::integer
              FROM pcms.trade_team_details ttd
              WHERE ttd.trade_id = ft.trade_id
                AND ttd.draft_pick_year IS NOT NULL
            ) AS pick_count,
            (
              SELECT COUNT(*)::integer
              FROM pcms.trade_team_details ttd
              WHERE ttd.trade_id = ft.trade_id
                AND (ttd.trade_entry_lk = 'CASH' OR COALESCE(ttd.cash_amount, 0) <> 0)
            ) AS cash_line_count,
            (
              SELECT COUNT(*)::integer
              FROM pcms.trade_team_details ttd
              WHERE ttd.trade_id = ft.trade_id
                AND ttd.trade_entry_lk = 'TREX'
            ) AS tpe_line_count
          FROM filtered_trades ft
        ),
        ranked_trades AS (
          SELECT
            trade_rollup.*,
            (trade_rollup.player_count + trade_rollup.pick_count + trade_rollup.cash_line_count + trade_rollup.tpe_line_count)::integer AS complexity_asset_count
          FROM trade_rollup
        )
        SELECT
          ranked_trades.trade_id,
          ranked_trades.trade_date,
          ranked_trades.trade_finalized_date,
          ranked_trades.trade_comments,
          ranked_trades.teams_involved,
          ranked_trades.team_count,
          ranked_trades.player_count,
          ranked_trades.pick_count,
          ranked_trades.cash_line_count,
          ranked_trades.tpe_line_count,
          ranked_trades.complexity_asset_count
        FROM ranked_trades
        WHERE #{lens_sql}
        ORDER BY #{order_sql}
        LIMIT 200
      SQL

      build_sidebar_summary!
    end

    def build_sidebar_summary!
      rows = Array(@trades)
      filters = ["Date: #{daterange_label(@daterange)}"]
      filters << "Team: #{@team}" if @team.present?
      filters << "Lens: #{@lens_label}" unless @lens == "all"
      filters << "Sort: #{@sort_label}"

      @sidebar_summary = {
        row_count: rows.size,
        player_assets_total: rows.sum { |row| row["player_count"].to_i },
        pick_assets_total: rows.sum { |row| row["pick_count"].to_i },
        complexity_asset_total: rows.sum { |row| row["complexity_asset_count"].to_i },
        complex_deal_count: rows.count { |row| row["team_count"].to_i >= 3 || row["complexity_asset_count"].to_i >= 4 },
        filters:,
        top_rows: rows.first(14)
      }
    end

    def load_sidebar_trade_payload(trade_id)
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(trade_id)

      trade = conn.exec_query(<<~SQL).first
        SELECT
          tr.trade_id,
          tr.trade_date,
          tr.trade_comments,
          (
            SELECT string_agg(tt.team_code, ', ' ORDER BY tt.seqno)
            FROM pcms.trade_teams tt
            WHERE tt.trade_id = tr.trade_id
          ) AS teams_involved,
          (
            SELECT COUNT(DISTINCT tt.team_id)::integer
            FROM pcms.trade_teams tt
            WHERE tt.trade_id = tr.trade_id
          ) AS team_count,
          (
            SELECT COUNT(DISTINCT ttd.player_id)::integer
            FROM pcms.trade_team_details ttd
            WHERE ttd.trade_id = tr.trade_id
              AND ttd.player_id IS NOT NULL
          ) AS player_count,
          (
            SELECT COUNT(*)::integer
            FROM pcms.trade_team_details ttd
            WHERE ttd.trade_id = tr.trade_id
              AND ttd.draft_pick_year IS NOT NULL
          ) AS pick_count,
          (
            SELECT COUNT(*)::integer
            FROM pcms.trade_team_details ttd
            WHERE ttd.trade_id = tr.trade_id
              AND (ttd.trade_entry_lk = 'CASH' OR COALESCE(ttd.cash_amount, 0) <> 0)
          ) AS cash_line_count,
          (
            SELECT COUNT(*)::integer
            FROM pcms.trade_team_details ttd
            WHERE ttd.trade_id = tr.trade_id
              AND ttd.trade_entry_lk = 'TREX'
          ) AS tpe_line_count
        FROM pcms.trades tr
        WHERE tr.trade_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless trade

      team_anatomy_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          tt.team_id,
          tt.team_code,
          team.team_name,
          tt.seqno,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.player_id IS NOT NULL AND ttd.is_sent = TRUE)::integer AS players_out,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.player_id IS NOT NULL AND ttd.is_sent = FALSE)::integer AS players_in,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.draft_pick_year IS NOT NULL AND ttd.is_sent = TRUE)::integer AS picks_out,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.draft_pick_year IS NOT NULL AND ttd.is_sent = FALSE)::integer AS picks_in,
          SUM(COALESCE(ttd.cash_amount, 0)) FILTER (WHERE COALESCE(ttd.cash_amount, 0) <> 0 AND ttd.is_sent = TRUE) AS cash_out,
          SUM(COALESCE(ttd.cash_amount, 0)) FILTER (WHERE COALESCE(ttd.cash_amount, 0) <> 0 AND ttd.is_sent = FALSE) AS cash_in,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.trade_entry_lk = 'TREX' AND ttd.is_sent = TRUE)::integer AS tpe_out,
          COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.trade_entry_lk = 'TREX' AND ttd.is_sent = FALSE)::integer AS tpe_in
        FROM pcms.trade_teams tt
        LEFT JOIN pcms.trade_team_details ttd
          ON ttd.trade_id = tt.trade_id
         AND ttd.team_id = tt.team_id
        LEFT JOIN pcms.teams team
          ON team.team_id = tt.team_id
        WHERE tt.trade_id = #{id_sql}
        GROUP BY tt.team_id, tt.team_code, team.team_name, tt.seqno
        ORDER BY tt.seqno, tt.team_code
      SQL

      asset_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          ttd.trade_team_detail_id,
          ttd.team_code,
          team.team_name,
          ttd.seqno,
          ttd.is_sent,
          ttd.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ttd.player_id::text
          ) AS player_name,
          ttd.draft_pick_year,
          ttd.draft_pick_round,
          ttd.is_draft_pick_swap,
          ttd.draft_pick_conditional_lk,
          ttd.is_draft_year_plus_two,
          ttd.trade_entry_lk,
          ttd.cash_amount
        FROM pcms.trade_team_details ttd
        LEFT JOIN pcms.people p
          ON p.person_id = ttd.player_id
        LEFT JOIN pcms.teams team
          ON team.team_id = ttd.team_id
        WHERE ttd.trade_id = #{id_sql}
        ORDER BY ttd.team_code, ttd.seqno, ttd.trade_team_detail_id
        LIMIT 120
      SQL

      related_transactions = conn.exec_query(<<~SQL).to_a
        SELECT
          t.transaction_id,
          t.transaction_date,
          t.transaction_type_lk,
          t.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            t.player_id::text
          ) AS player_name
        FROM pcms.transactions t
        LEFT JOIN pcms.people p
          ON p.person_id = t.player_id
        WHERE t.trade_id = #{id_sql}
        ORDER BY t.transaction_date, t.transaction_id
        LIMIT 24
      SQL

      {
        trade:,
        team_anatomy_rows:,
        asset_rows:,
        related_transactions:
      }
    end

    def selected_overlay_visible?(overlay_type:, overlay_id:)
      return false unless overlay_type.to_s == "trade"
      return false unless overlay_id.to_i.positive?

      Array(@trades).any? { |row| row["trade_id"].to_i == overlay_id.to_i }
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
  end
end
