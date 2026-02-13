module Entities
  class DraftsController < ApplicationController
    INDEX_VIEWS = %w[picks selections grid].freeze
    INDEX_ROUNDS = %w[all 1 2].freeze
    INDEX_SORTS = %w[board risk provenance].freeze
    INDEX_LENSES = %w[all at_risk critical].freeze

    # GET /drafts
    # Unified workspace for draft picks (future assets), draft selections (historical),
    # and pick grid (team × year × round ownership matrix).
    def index
      load_index_state!
      render :index
    end

    # GET /drafts/pane (Datastar partial refresh)
    def pane
      load_index_state!
      render partial: "entities/drafts/results"
    end

    # GET /drafts/sidebar/base
    def sidebar_base
      load_index_state!
      render partial: "entities/drafts/rightpanel_base"
    end

    # GET /drafts/sidebar/pick?team=XXX&year=YYYY&round=R
    def sidebar_pick
      team_code = normalize_team_code_param(params[:team])
      year = normalize_year_param(params[:year])
      round = normalize_round_param(params[:round])

      raise ActiveRecord::RecordNotFound if team_code.blank? || year.nil? || round.nil?

      render partial: "entities/drafts/rightpanel_overlay_pick", locals: load_sidebar_pick_payload(
        team_code:,
        draft_year: year,
        draft_round: round
      )
    end

    # GET /drafts/sidebar/selection/:id
    def sidebar_selection
      transaction_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if transaction_id <= 0

      render partial: "entities/drafts/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(transaction_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /drafts/sidebar/clear
    def sidebar_clear
      render partial: "entities/drafts/rightpanel_clear"
    end

    private

    def load_index_state!
      conn = ActiveRecord::Base.connection

      @view = params[:view].to_s.strip
      @view = "picks" unless INDEX_VIEWS.include?(@view)

      @round = normalize_round_param(params[:round])&.to_s || "all"
      @team = normalize_team_code_param(params[:team])
      @sort = normalize_sort_param(params[:sort]) || "board"
      @lens = normalize_lens_param(params[:lens]) || "all"

      @sort_label = drafts_sort_label(view: @view, sort: @sort)
      @lens_label = drafts_lens_label(@lens)

      current_year = Date.today.year
      default_picks_year = Date.today.month >= 7 ? current_year + 1 : current_year
      default_selections_year = Date.today.month >= 7 ? current_year : current_year - 1

      requested_year = normalize_year_param(params[:year])
      @year = (requested_year || (@view == "selections" ? default_selections_year : default_picks_year)).to_s

      case @view
      when "grid"
        load_grid(conn)
      when "picks"
        load_picks(conn)
      else
        load_selections(conn)
      end

      selection_years = conn.exec_query(<<~SQL).rows.flatten.map(&:to_i)
        SELECT DISTINCT draft_year FROM pcms.draft_selections ORDER BY draft_year DESC
      SQL

      base_years = ((current_year - 5)..(current_year + 7)).to_a
      @available_years = (selection_years + base_years + [@year.to_i]).uniq.sort.reverse

      @team_options = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
        ORDER BY team_code
      SQL

      build_sidebar_summary!
    end

    def load_picks(conn)
      year_sql = conn.quote(@year.to_i)

      round_filter_sql = if @round.present? && @round != "all"
        "AND v.draft_round = #{conn.quote(@round.to_i)}"
      else
        ""
      end

      team_filter_sql = if @team.present?
        "(ranked_picks.original_team_code = #{conn.quote(@team)} OR ranked_picks.current_team_code = #{conn.quote(@team)})"
      else
        "1=1"
      end

      @results = conn.exec_query(<<~SQL).to_a
        WITH picks AS (
          SELECT
            v.draft_year,
            v.draft_round,
            v.team_code AS original_team_code,
            COALESCE(
              MAX(
                CASE
                  WHEN v.asset_type = 'TO' THEN
                    COALESCE(
                      (regexp_match(v.display_text, '^To\\s+([A-Z]{3})\\s*:'))[1],
                      NULLIF(v.counterparty_team_code, '')
                    )
                END
              ),
              v.team_code
            ) AS current_team_code,
            BOOL_OR(v.is_swap) AS is_swap,
            BOOL_OR(v.is_conditional) AS has_conditional,
            BOOL_OR(v.is_forfeited) AS has_forfeited,
            STRING_AGG(DISTINCT v.display_text, '; ')
              FILTER (WHERE v.asset_type <> 'OWN') AS protections_summary,
            CASE
              WHEN BOOL_OR(v.is_forfeited) THEN 'Forfeited'
              WHEN BOOL_OR(v.is_conditional) THEN 'Conditional'
              WHEN BOOL_OR(v.asset_type = 'TO') THEN 'Traded'
              ELSE 'Own'
            END AS pick_status,
            COUNT(*)::integer AS asset_line_count,
            COUNT(*) FILTER (WHERE v.asset_type = 'TO')::integer AS outgoing_line_count,
            COUNT(*) FILTER (WHERE v.is_conditional)::integer AS conditional_line_count
          FROM pcms.vw_draft_pick_assets v
          WHERE v.draft_year = #{year_sql}
            #{round_filter_sql}
          GROUP BY v.draft_year, v.draft_round, v.team_code
        ),
        pick_rank AS (
          SELECT
            picks.*,
            (
              SELECT COUNT(*)::integer
              FROM pcms.draft_pick_trades dpt
              WHERE dpt.draft_year = picks.draft_year
                AND dpt.draft_round = picks.draft_round
                AND (
                  dpt.original_team_code = picks.original_team_code
                  OR dpt.from_team_code = picks.original_team_code
                  OR dpt.to_team_code = picks.original_team_code
                )
            ) AS provenance_trade_count
          FROM picks
        ),
        ranked_picks AS (
          SELECT
            pick_rank.*,
            (
              CASE WHEN pick_rank.has_forfeited THEN 7 ELSE 0 END
              + CASE WHEN pick_rank.has_conditional THEN 4 ELSE 0 END
              + CASE WHEN pick_rank.is_swap THEN 2 ELSE 0 END
              + CASE WHEN pick_rank.pick_status = 'Traded' THEN 2 ELSE 0 END
              + LEAST(COALESCE(pick_rank.provenance_trade_count, 0), 6)
            )::integer AS ownership_risk_score
          FROM pick_rank
        )
        SELECT
          ranked_picks.draft_year,
          ranked_picks.draft_round,
          ranked_picks.original_team_code,
          ranked_picks.current_team_code,
          ot.team_name AS original_team_name,
          ct.team_name AS current_team_name,
          ranked_picks.is_swap,
          ranked_picks.has_conditional,
          ranked_picks.has_forfeited,
          ranked_picks.protections_summary,
          ranked_picks.pick_status,
          ranked_picks.asset_line_count,
          ranked_picks.outgoing_line_count,
          ranked_picks.conditional_line_count,
          ranked_picks.provenance_trade_count,
          ranked_picks.ownership_risk_score
        FROM ranked_picks
        LEFT JOIN pcms.teams ot
          ON ot.team_code = ranked_picks.original_team_code
         AND ot.league_lk = 'NBA'
         AND ot.is_active = TRUE
        LEFT JOIN pcms.teams ct
          ON ct.team_code = ranked_picks.current_team_code
         AND ct.league_lk = 'NBA'
         AND ct.is_active = TRUE
        WHERE #{team_filter_sql}
          AND #{picks_lens_sql(alias_name: "ranked_picks")}
        ORDER BY #{picks_order_sql}
      SQL
    end

    def load_selections(conn)
      year_sql = conn.quote(@year.to_i)

      where_clauses = ["ds.draft_year = #{year_sql}"]
      where_clauses << "ds.draft_round = #{conn.quote(@round.to_i)}" if @round.present? && @round != "all"
      where_clauses << "ds.drafting_team_code = #{conn.quote(@team)}" if @team.present?

      @results = conn.exec_query(<<~SQL).to_a
        WITH selection_rows AS (
          SELECT
            ds.transaction_id,
            ds.draft_year,
            ds.draft_round,
            ds.pick_number,
            ds.player_id,
            COALESCE(
              NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
              NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
              ds.player_id::text
            ) AS player_name,
            ds.drafting_team_id,
            ds.drafting_team_code,
            t.team_name AS drafting_team_name,
            ds.transaction_date,
            tx.trade_id,
            tx.transaction_type_lk,
            (
              SELECT COUNT(*)::integer
              FROM pcms.draft_pick_trades dpt
              WHERE dpt.draft_year = ds.draft_year
                AND dpt.draft_round = ds.draft_round
                AND (
                  dpt.original_team_code = ds.drafting_team_code
                  OR dpt.from_team_code = ds.drafting_team_code
                  OR dpt.to_team_code = ds.drafting_team_code
                )
            ) AS provenance_trade_count
          FROM pcms.draft_selections ds
          LEFT JOIN pcms.transactions tx
            ON tx.transaction_id = ds.transaction_id
          LEFT JOIN pcms.people p
            ON p.person_id = ds.player_id
          LEFT JOIN pcms.teams t
            ON t.team_code = ds.drafting_team_code
           AND t.league_lk = 'NBA'
          WHERE #{where_clauses.join(" AND ")}
        )
        SELECT
          selection_rows.*,
          (
            COALESCE(selection_rows.provenance_trade_count, 0)
            + CASE WHEN selection_rows.trade_id IS NOT NULL THEN 1 ELSE 0 END
            + CASE WHEN selection_rows.draft_round = 1 THEN 1 ELSE 0 END
          )::integer AS provenance_risk_score
        FROM selection_rows
        WHERE #{selections_lens_sql(alias_name: "selection_rows")}
        ORDER BY #{selections_order_sql}
      SQL
    end

    def load_grid(conn)
      year_start = @year.to_i
      year_end = year_start + 6

      round_clauses = []
      round_clauses << "v.draft_round = #{conn.quote(@round.to_i)}" if @round.present? && @round != "all"
      team_clauses = []
      team_clauses << "v.team_code = #{conn.quote(@team)}" if @team.present?

      where_sql = "v.draft_year BETWEEN #{conn.quote(year_start)} AND #{conn.quote(year_end)}"
      where_sql += " AND #{round_clauses.join(' AND ')}" if round_clauses.any?
      where_sql += " AND #{team_clauses.join(' AND ')}" if team_clauses.any?

      rows = conn.exec_query(<<~SQL).to_a
        SELECT
          v.team_code,
          t.team_name,
          v.draft_year,
          v.draft_round,
          STRING_AGG(v.display_text, '; ' ORDER BY v.asset_slot, v.sub_asset_slot) AS cell_text,
          BOOL_OR(v.asset_type = 'TO') AS has_outgoing,
          BOOL_OR(v.is_swap) AS has_swap,
          BOOL_OR(v.is_conditional) AS has_conditional,
          BOOL_OR(v.is_forfeited) AS has_forfeited,
          (
            SELECT COUNT(*)::integer
            FROM pcms.draft_pick_trades dpt
            WHERE dpt.draft_year = v.draft_year
              AND dpt.draft_round = v.draft_round
              AND (
                dpt.original_team_code = v.team_code
                OR dpt.from_team_code = v.team_code
                OR dpt.to_team_code = v.team_code
              )
          ) AS provenance_trade_count
        FROM pcms.vw_draft_pick_assets v
        LEFT JOIN pcms.teams t ON t.team_code = v.team_code AND t.league_lk = 'NBA'
        WHERE #{where_sql}
        GROUP BY v.team_code, t.team_name, v.draft_year, v.draft_round
        ORDER BY v.team_code, v.draft_round, v.draft_year
      SQL

      rows = apply_grid_lens(rows)

      @grid_rows = rows
      @grid_data = {}
      @grid_teams = {}

      rows.each do |row|
        team = row["team_code"]
        year = row["draft_year"]
        round = row["draft_round"]

        @grid_teams[team] ||= row["team_name"]

        @grid_data[team] ||= {}
        @grid_data[team][round] ||= {}
        @grid_data[team][round][year] = {
          text: row["cell_text"],
          has_outgoing: row["has_outgoing"],
          has_swap: row["has_swap"],
          has_conditional: row["has_conditional"],
          has_forfeited: row["has_forfeited"],
          provenance_trade_count: row["provenance_trade_count"],
          ownership_risk_score: grid_cell_risk_score(row)
        }
      end

      @grid_years = (year_start..year_end).to_a
      @grid_teams = sort_grid_teams(@grid_teams, rows)
    end

    def build_sidebar_summary!
      filters = []
      filters << "View: #{@view.titleize}"
      filters << "Year: #{@year}"
      filters << "Round: #{@round == 'all' ? 'All' : "R#{@round}"}"
      filters << "Team: #{@team}" if @team.present?
      filters << "Sort: #{@sort_label}"
      filters << "Lens: #{@lens_label}" unless @lens == "all"

      case @view
      when "picks"
        rows = Array(@results)
        @sidebar_summary = {
          view: "picks",
          sort_label: @sort_label,
          lens_label: @lens_label,
          row_count: rows.size,
          traded_count: rows.count { |row| row["pick_status"].to_s == "Traded" },
          conditional_count: rows.count { |row| truthy?(row["has_conditional"]) },
          swap_count: rows.count { |row| truthy?(row["is_swap"]) },
          forfeited_count: rows.count { |row| truthy?(row["has_forfeited"]) },
          at_risk_count: rows.count { |row| picks_row_at_risk?(row) },
          critical_count: rows.count { |row| picks_row_critical?(row) },
          provenance_trade_total: rows.sum { |row| row["provenance_trade_count"].to_i },
          filters:,
          top_rows: rows.first(12)
        }
      when "selections"
        rows = Array(@results)
        @sidebar_summary = {
          view: "selections",
          sort_label: @sort_label,
          lens_label: @lens_label,
          row_count: rows.size,
          first_round_count: rows.count { |row| row["draft_round"].to_i == 1 },
          with_trade_count: rows.count { |row| row["trade_id"].present? },
          with_player_count: rows.count { |row| row["player_id"].present? },
          at_risk_count: rows.count { |row| selections_row_at_risk?(row) },
          critical_count: rows.count { |row| selections_row_critical?(row) },
          provenance_trade_total: rows.sum { |row| row["provenance_trade_count"].to_i },
          filters:,
          top_rows: rows.first(12)
        }
      else
        rows = Array(@grid_rows)
        @sidebar_summary = {
          view: "grid",
          sort_label: @sort_label,
          lens_label: @lens_label,
          team_count: @grid_teams.size,
          year_count: @grid_years.size,
          cell_count: rows.size,
          outgoing_count: rows.count { |row| truthy?(row["has_outgoing"]) },
          conditional_count: rows.count { |row| truthy?(row["has_conditional"]) },
          swap_count: rows.count { |row| truthy?(row["has_swap"]) },
          at_risk_count: rows.count { |row| grid_row_at_risk?(row) },
          critical_count: rows.count { |row| grid_row_critical?(row) },
          provenance_trade_total: rows.sum { |row| row["provenance_trade_count"].to_i },
          filters:
        }
      end
    end

    def load_sidebar_pick_payload(team_code:, draft_year:, draft_round:)
      conn = ActiveRecord::Base.connection
      team_sql = conn.quote(team_code)
      year_sql = conn.quote(draft_year)
      round_sql = conn.quote(draft_round)

      pick = conn.exec_query(<<~SQL).first
        WITH pick AS (
          SELECT
            v.draft_year,
            v.draft_round,
            v.team_code AS original_team_code,
            COALESCE(
              MAX(
                CASE
                  WHEN v.asset_type = 'TO' THEN
                    COALESCE(
                      (regexp_match(v.display_text, '^To\\s+([A-Z]{3})\\s*:'))[1],
                      NULLIF(v.counterparty_team_code, '')
                    )
                END
              ),
              v.team_code
            ) AS current_team_code,
            BOOL_OR(v.is_swap) AS is_swap,
            BOOL_OR(v.is_conditional) AS has_conditional,
            BOOL_OR(v.is_forfeited) AS has_forfeited,
            STRING_AGG(DISTINCT v.display_text, '; ')
              FILTER (WHERE v.asset_type <> 'OWN') AS protections_summary,
            CASE
              WHEN BOOL_OR(v.is_forfeited) THEN 'Forfeited'
              WHEN BOOL_OR(v.is_conditional) THEN 'Conditional'
              WHEN BOOL_OR(v.asset_type = 'TO') THEN 'Traded'
              ELSE 'Own'
            END AS pick_status
          FROM pcms.vw_draft_pick_assets v
          WHERE v.team_code = #{team_sql}
            AND v.draft_year = #{year_sql}
            AND v.draft_round = #{round_sql}
          GROUP BY v.draft_year, v.draft_round, v.team_code
        )
        SELECT
          pick.*,
          ot.team_name AS original_team_name,
          ct.team_name AS current_team_name
        FROM pick
        LEFT JOIN pcms.teams ot
          ON ot.team_code = pick.original_team_code
         AND ot.league_lk = 'NBA'
        LEFT JOIN pcms.teams ct
          ON ct.team_code = pick.current_team_code
         AND ct.league_lk = 'NBA'
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless pick

      assets = conn.exec_query(<<~SQL).to_a
        SELECT
          asset_slot,
          sub_asset_slot,
          asset_type,
          display_text,
          raw_part,
          counterparty_team_code,
          is_swap,
          is_conditional,
          is_forfeited,
          endnote_explanation,
          trade_id
        FROM pcms.vw_draft_pick_assets
        WHERE team_code = #{team_sql}
          AND draft_year = #{year_sql}
          AND draft_round = #{round_sql}
        ORDER BY asset_slot, sub_asset_slot
      SQL

      provenance_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          dpt.id,
          dpt.trade_id,
          tr.trade_date,
          dpt.from_team_code,
          dpt.to_team_code,
          dpt.original_team_code,
          dpt.is_swap,
          dpt.is_future,
          dpt.is_conditional,
          dpt.conditional_type_lk
        FROM pcms.draft_pick_trades dpt
        LEFT JOIN pcms.trades tr
          ON tr.trade_id = dpt.trade_id
        WHERE dpt.draft_year = #{year_sql}
          AND dpt.draft_round = #{round_sql}
          AND (
            dpt.original_team_code = #{team_sql}
            OR dpt.from_team_code = #{team_sql}
            OR dpt.to_team_code = #{team_sql}
          )
        ORDER BY tr.trade_date NULLS LAST, dpt.id
        LIMIT 80
      SQL

      current_team_sql = conn.quote(pick["current_team_code"])
      related_selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.player_id,
          ds.pick_number,
          ds.transaction_date
        FROM pcms.draft_selections ds
        WHERE ds.draft_year = #{year_sql}
          AND ds.draft_round = #{round_sql}
          AND ds.drafting_team_code = #{current_team_sql}
        LIMIT 1
      SQL

      {
        pick:,
        assets:,
        provenance_rows:,
        related_selection:
      }
    end

    def load_sidebar_selection_payload(transaction_id)
      conn = ActiveRecord::Base.connection
      tx_sql = conn.quote(transaction_id)

      selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ds.player_id::text
          ) AS player_name,
          ds.drafting_team_id,
          ds.drafting_team_code,
          t.team_name AS drafting_team_name,
          ds.transaction_date,
          tx.trade_id,
          tx.transaction_type_lk
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.transactions tx
          ON tx.transaction_id = ds.transaction_id
        LEFT JOIN pcms.people p
          ON p.person_id = ds.player_id
        LEFT JOIN pcms.teams t
          ON t.team_code = ds.drafting_team_code
         AND t.league_lk = 'NBA'
        WHERE ds.transaction_id = #{tx_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless selection

      year_sql = conn.quote(selection["draft_year"])
      round_sql = conn.quote(selection["draft_round"])
      team_sql = conn.quote(selection["drafting_team_code"])

      provenance_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          dpt.id,
          dpt.trade_id,
          tr.trade_date,
          dpt.from_team_code,
          dpt.to_team_code,
          dpt.original_team_code,
          dpt.is_swap,
          dpt.is_future,
          dpt.is_conditional,
          dpt.conditional_type_lk
        FROM pcms.draft_pick_trades dpt
        LEFT JOIN pcms.trades tr
          ON tr.trade_id = dpt.trade_id
        WHERE dpt.draft_year = #{year_sql}
          AND dpt.draft_round = #{round_sql}
          AND (
            dpt.original_team_code = #{team_sql}
            OR dpt.from_team_code = #{team_sql}
            OR dpt.to_team_code = #{team_sql}
          )
        ORDER BY tr.trade_date NULLS LAST, dpt.id
        LIMIT 80
      SQL

      {
        selection:,
        provenance_rows:
      }
    end

    def picks_order_sql
      case @sort
      when "risk"
        "ranked_picks.ownership_risk_score DESC, ranked_picks.provenance_trade_count DESC, ranked_picks.outgoing_line_count DESC, ranked_picks.draft_round ASC, ranked_picks.original_team_code ASC"
      when "provenance"
        "ranked_picks.provenance_trade_count DESC, ranked_picks.ownership_risk_score DESC, ranked_picks.draft_round ASC, ranked_picks.original_team_code ASC"
      else
        "ranked_picks.draft_round ASC, ranked_picks.original_team_code ASC"
      end
    end

    def picks_lens_sql(alias_name:)
      case @lens
      when "at_risk"
        "(#{alias_name}.has_conditional OR #{alias_name}.is_swap OR #{alias_name}.has_forfeited OR #{alias_name}.pick_status = 'Traded' OR #{alias_name}.provenance_trade_count > 0)"
      when "critical"
        "(#{alias_name}.has_forfeited OR #{alias_name}.conditional_line_count >= 1 OR #{alias_name}.provenance_trade_count >= 2)"
      else
        "1=1"
      end
    end

    def selections_order_sql
      case @sort
      when "risk"
        "provenance_risk_score DESC, selection_rows.provenance_trade_count DESC, selection_rows.draft_round ASC, selection_rows.pick_number ASC"
      when "provenance"
        "selection_rows.provenance_trade_count DESC, provenance_risk_score DESC, selection_rows.draft_round ASC, selection_rows.pick_number ASC"
      else
        "selection_rows.draft_round ASC, selection_rows.pick_number ASC"
      end
    end

    def selections_lens_sql(alias_name:)
      case @lens
      when "at_risk"
        "(#{alias_name}.provenance_trade_count > 0 OR #{alias_name}.trade_id IS NOT NULL)"
      when "critical"
        "(#{alias_name}.provenance_trade_count >= 2)"
      else
        "1=1"
      end
    end

    def apply_grid_lens(rows)
      case @lens
      when "at_risk"
        rows.select { |row| grid_row_at_risk?(row) }
      when "critical"
        rows.select { |row| grid_row_critical?(row) }
      else
        rows
      end
    end

    def grid_row_at_risk?(row)
      truthy?(row["has_outgoing"]) || truthy?(row["has_conditional"]) || truthy?(row["has_swap"]) || row["provenance_trade_count"].to_i.positive?
    end

    def grid_row_critical?(row)
      truthy?(row["has_forfeited"]) || truthy?(row["has_conditional"]) || row["provenance_trade_count"].to_i >= 2
    end

    def picks_row_at_risk?(row)
      truthy?(row["has_conditional"]) || truthy?(row["is_swap"]) || truthy?(row["has_forfeited"]) || row["pick_status"].to_s == "Traded" || row["provenance_trade_count"].to_i.positive?
    end

    def picks_row_critical?(row)
      truthy?(row["has_forfeited"]) || truthy?(row["has_conditional"]) || row["provenance_trade_count"].to_i >= 2
    end

    def selections_row_at_risk?(row)
      row["provenance_trade_count"].to_i.positive? || row["trade_id"].present?
    end

    def selections_row_critical?(row)
      row["provenance_trade_count"].to_i >= 2
    end

    def grid_cell_risk_score(row)
      (
        (truthy?(row["has_forfeited"]) ? 7 : 0) +
        (truthy?(row["has_conditional"]) ? 4 : 0) +
        (truthy?(row["has_swap"]) ? 2 : 0) +
        (truthy?(row["has_outgoing"]) ? 2 : 0) +
        [row["provenance_trade_count"].to_i, 6].min
      ).to_i
    end

    def sort_grid_teams(team_map, rows)
      return [] if team_map.blank?

      grouped = rows.group_by { |row| row["team_code"].to_s }

      ranked = team_map.map do |team_code, team_name|
        team_rows = grouped[team_code.to_s] || []

        risk_total = team_rows.sum { |row| grid_cell_risk_score(row) }
        provenance_total = team_rows.sum { |row| row["provenance_trade_count"].to_i }
        outgoing_count = team_rows.count { |row| truthy?(row["has_outgoing"]) }

        {
          team_code: team_code.to_s,
          team_name: team_name,
          risk_total:,
          provenance_total:,
          outgoing_count:
        }
      end

      sorted = case @sort
      when "risk"
        ranked.sort_by { |row| [-row[:risk_total], -row[:outgoing_count], -row[:provenance_total], row[:team_code]] }
      when "provenance"
        ranked.sort_by { |row| [-row[:provenance_total], -row[:risk_total], -row[:outgoing_count], row[:team_code]] }
      else
        ranked.sort_by { |row| row[:team_code] }
      end

      sorted.map { |row| [row[:team_code], row[:team_name]] }
    end

    def drafts_sort_label(view:, sort:)
      case view.to_s
      when "grid"
        case sort.to_s
        when "risk" then "Most encumbered teams"
        when "provenance" then "Most provenance-active teams"
        else "Team code"
        end
      when "selections"
        case sort.to_s
        when "risk" then "Highest contest risk"
        when "provenance" then "Deepest provenance chain"
        else "Board order"
        end
      else
        case sort.to_s
        when "risk" then "Ownership risk first"
        when "provenance" then "Deepest provenance chain"
        else "Board order"
        end
      end
    end

    def drafts_lens_label(lens)
      case lens.to_s
      when "at_risk"
        "At-risk only"
      when "critical"
        "Critical only"
      else
        "All rows"
      end
    end

    def requested_overlay_context
      overlay_type = params[:selected_type].to_s.strip.downcase
      overlay_key = params[:selected_key].to_s.strip

      case overlay_type
      when "pick"
        parse_pick_overlay_key(overlay_key)
      when "selection"
        parse_selection_overlay_key(overlay_key)
      else
        nil
      end
    end

    def selected_overlay_visible?(context:)
      return false if context.blank?

      case context[:type]
      when "pick"
        return false unless %w[picks grid].include?(@view)

        selected_pick_visible?(
          team_code: context[:team_code],
          draft_year: context[:draft_year],
          draft_round: context[:draft_round]
        )
      when "selection"
        return false unless @view == "selections"

        Array(@results).any? { |row| row["transaction_id"].to_i == context[:transaction_id].to_i }
      else
        false
      end
    end

    def overlay_key_for_pick(team_code:, draft_year:, draft_round:)
      key_prefix = @view == "grid" ? "grid" : "pick"
      "#{key_prefix}-#{team_code}-#{draft_year}-#{draft_round}"
    end

    def parse_pick_overlay_key(raw_key)
      match = raw_key.match(/\A(?:pick|grid)-([A-Za-z]{3})-(\d{4})-(\d+)\z/)
      return nil unless match

      team_code = match[1].to_s.upcase
      draft_year = match[2].to_i
      draft_round = match[3].to_i

      return nil if team_code.blank? || draft_year <= 0 || draft_round <= 0

      {
        type: "pick",
        team_code:,
        draft_year:,
        draft_round:
      }
    end

    def parse_selection_overlay_key(raw_key)
      match = raw_key.match(/\Aselection-(\d+)\z/)
      return nil unless match

      transaction_id = match[1].to_i
      return nil if transaction_id <= 0

      {
        type: "selection",
        transaction_id:
      }
    end

    def selected_pick_visible?(team_code:, draft_year:, draft_round:)
      if @view == "grid"
        @grid_data.dig(team_code, draft_round.to_i, draft_year.to_i).present?
      else
        Array(@results).any? do |row|
          row["original_team_code"].to_s.upcase == team_code.to_s.upcase &&
            row["draft_year"].to_i == draft_year.to_i &&
            row["draft_round"].to_i == draft_round.to_i
        end
      end
    end

    def normalize_team_code_param(raw)
      code = raw.to_s.strip.upcase
      return nil if code.blank?
      return nil unless code.match?(/\A[A-Z]{3}\z/)

      code
    end

    def normalize_year_param(raw)
      year = Integer(raw.to_s.strip)
      return nil if year <= 0

      year
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_round_param(raw)
      round = raw.to_s.strip
      round = "all" if round.blank?
      return round if INDEX_ROUNDS.include?(round)

      nil
    end

    def normalize_sort_param(raw)
      sort = raw.to_s.strip
      sort = "board" if sort.blank?
      return sort if INDEX_SORTS.include?(sort)

      nil
    end

    def normalize_lens_param(raw)
      lens = raw.to_s.strip
      lens = "all" if lens.blank?
      return lens if INDEX_LENSES.include?(lens)

      nil
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
