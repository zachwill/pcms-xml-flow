class TradeQueries
  def initialize(connection: ActiveRecord::Base.connection)
    @connection = connection
  end

  private attr_reader :connection

  def conn
    connection
  end

  def fetch_trade_show(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).first
      SELECT
        tr.trade_id,
        tr.trade_date,
        tr.trade_finalized_date,
        tr.league_lk,
        tr.record_status_lk,
        tr.trade_comments
      FROM pcms.trades tr
      WHERE tr.trade_id = #{id_sql}
        AND tr.league_lk = 'NBA'
      LIMIT 1
    SQL
  end

  def fetch_trade_teams(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_player_details(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_pick_details(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_cash_details(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_draft_pick_trades(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_transactions(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_endnotes(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_trade_group_rows(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_trade_group_exception_rows(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_team_options
    conn.exec_query(<<~SQL).to_a
      SELECT team_code, team_name
      FROM pcms.teams
      WHERE league_lk = 'NBA'
        AND team_name NOT LIKE 'Non-NBA%'
      ORDER BY team_code
    SQL
  end

  def fetch_index_trades(where_sql:, lens_sql:, composition_sql:, order_sql:)
    conn.exec_query(<<~SQL).to_a
      WITH filtered_trades AS (
        SELECT
          tr.trade_id,
          tr.trade_date,
          tr.trade_finalized_date,
          tr.trade_comments
        FROM pcms.trades tr
        WHERE tr.league_lk = 'NBA'
          AND EXISTS (
            SELECT 1
            FROM pcms.trade_teams tt
            JOIN pcms.teams team
              ON team.team_id = tt.team_id
            WHERE tt.trade_id = tr.trade_id
              AND team.league_lk = 'NBA'
          )
          AND NOT EXISTS (
            SELECT 1
            FROM pcms.trade_teams tt
            JOIN pcms.teams team
              ON team.team_id = tt.team_id
            WHERE tt.trade_id = tr.trade_id
              AND COALESCE(team.league_lk, '') <> 'NBA'
          )
          AND #{where_sql}
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
            JOIN pcms.teams team
              ON team.team_id = tt.team_id
             AND team.league_lk = 'NBA'
            WHERE tt.trade_id = ft.trade_id
          ) AS teams_involved,
          (
            SELECT COUNT(DISTINCT tt.team_id)::integer
            FROM pcms.trade_teams tt
            JOIN pcms.teams team
              ON team.team_id = tt.team_id
             AND team.league_lk = 'NBA'
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
        AND #{composition_sql}
      ORDER BY #{order_sql}
      LIMIT 200
    SQL
  end

  def fetch_trade_team_impacts(trade_ids:)
    ids = Array(trade_ids).map(&:to_i).select(&:positive?).uniq
    return [] if ids.empty?

    ids_sql = ids.join(",")

    conn.exec_query(<<~SQL).to_a
      SELECT
        tt.trade_id,
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
      JOIN pcms.teams team
        ON team.team_id = tt.team_id
       AND team.league_lk = 'NBA'
      LEFT JOIN pcms.trade_team_details ttd
        ON ttd.trade_id = tt.trade_id
       AND ttd.team_id = tt.team_id
      WHERE tt.trade_id IN (#{ids_sql})
      GROUP BY tt.trade_id, tt.team_id, tt.team_code, team.team_name, tt.seqno
      ORDER BY tt.trade_id, tt.seqno, tt.team_code
    SQL
  end

  def fetch_trade_player_previews(trade_ids:)
    ids = Array(trade_ids).map(&:to_i).select(&:positive?).uniq
    return [] if ids.empty?

    ids_sql = ids.join(",")

    conn.exec_query(<<~SQL).to_a
      WITH distinct_players AS (
        SELECT DISTINCT ON (ttd.trade_id, ttd.player_id)
          ttd.trade_id,
          ttd.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ttd.player_id::text
          ) AS player_name,
          ttd.seqno,
          ttd.trade_team_detail_id
        FROM pcms.trade_team_details ttd
        JOIN pcms.trade_teams tt
          ON tt.trade_id = ttd.trade_id
         AND tt.team_id = ttd.team_id
        JOIN pcms.teams team
          ON team.team_id = tt.team_id
         AND team.league_lk = 'NBA'
        LEFT JOIN pcms.people p
          ON p.person_id = ttd.player_id
        WHERE ttd.trade_id IN (#{ids_sql})
          AND ttd.player_id IS NOT NULL
        ORDER BY
          ttd.trade_id,
          ttd.player_id,
          ttd.seqno NULLS LAST,
          ttd.trade_team_detail_id
      ),
      ranked_players AS (
        SELECT
          distinct_players.*,
          ROW_NUMBER() OVER (
            PARTITION BY distinct_players.trade_id
            ORDER BY distinct_players.seqno NULLS LAST, distinct_players.trade_team_detail_id, distinct_players.player_name
          ) AS trade_player_rank
        FROM distinct_players
      )
      SELECT
        trade_id,
        player_id,
        player_name,
        trade_player_rank
      FROM ranked_players
      WHERE trade_player_rank <= 3
      ORDER BY trade_id, trade_player_rank
    SQL
  end

  def fetch_sidebar_trade(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).first
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
        AND tr.league_lk = 'NBA'
      LIMIT 1
    SQL
  end

  def fetch_sidebar_team_anatomy_rows(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_sidebar_asset_rows(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end

  def fetch_sidebar_related_transactions(trade_id)
    id_sql = conn.quote(trade_id)

    conn.exec_query(<<~SQL).to_a
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
  end
end
