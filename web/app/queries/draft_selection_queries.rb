class DraftSelectionQueries
  def initialize(connection: ActiveRecord::Base.connection)
    @connection = connection
  end

  private attr_reader :connection

  def conn
    connection
  end

  def fetch_show_selection(transaction_id)
    id_sql = conn.quote(transaction_id)

    conn.exec_query(<<~SQL).first
      SELECT
        ds.transaction_id,
        ds.draft_year,
        ds.draft_round,
        ds.pick_number,
        ds.player_id,
        ds.drafting_team_id,
        ds.drafting_team_code,
        ds.draft_amount,
        ds.transaction_date,
        tx.trade_id,
        tx.transaction_type_lk,
        tx.transaction_description_lk,
        COALESCE(
          NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
          NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
          ''
        ) AS player_name,
        t.team_name
      FROM pcms.draft_selections ds
      LEFT JOIN pcms.transactions tx ON tx.transaction_id = ds.transaction_id
      LEFT JOIN pcms.people p ON p.person_id = ds.player_id
      LEFT JOIN pcms.teams t ON t.team_id = ds.drafting_team_id
      WHERE ds.transaction_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_sidebar_selection(transaction_id)
    id_sql = conn.quote(transaction_id)

    conn.exec_query(<<~SQL).first
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
        tx.transaction_description_lk
      FROM pcms.draft_selections ds
      LEFT JOIN pcms.transactions tx
        ON tx.transaction_id = ds.transaction_id
      LEFT JOIN pcms.people p
        ON p.person_id = ds.player_id
      LEFT JOIN pcms.teams t
        ON t.team_code = ds.drafting_team_code
       AND t.league_lk = 'NBA'
      WHERE ds.transaction_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_current_team(player_id)
    player_sql = conn.quote(player_id)

    conn.exec_query(<<~SQL).first
      SELECT
        sbw.team_code,
        t.team_id,
        t.team_name
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE sbw.player_id = #{player_sql}
      LIMIT 1
    SQL
  end

  def fetch_pick_provenance_rows(draft_year:, draft_round:, drafting_team_code:)
    year_sql = conn.quote(draft_year)
    round_sql = conn.quote(draft_round)
    team_sql = conn.quote(drafting_team_code)

    conn.exec_query(<<~SQL).to_a
      SELECT
        dpt.id,
        dpt.trade_id,
        tr.trade_date,
        dpt.draft_year,
        dpt.draft_round,
        dpt.from_team_id,
        dpt.from_team_code,
        dpt.to_team_id,
        dpt.to_team_code,
        dpt.original_team_id,
        dpt.original_team_code,
        dpt.is_swap,
        dpt.is_future,
        dpt.is_conditional,
        dpt.conditional_type_lk,
        dpt.is_draft_year_plus_two
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
      LIMIT 120
    SQL
  end

  def fetch_redirect_slug_seed(transaction_id)
    id_sql = conn.quote(transaction_id)

    conn.exec_query(<<~SQL).first
      SELECT
        ds.draft_year,
        ds.draft_round,
        ds.pick_number,
        ds.player_id,
        COALESCE(
          NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
          NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
          ''
        ) AS player_name
      FROM pcms.draft_selections ds
      LEFT JOIN pcms.people p ON p.person_id = ds.player_id
      WHERE ds.transaction_id = #{id_sql}
      LIMIT 1
    SQL
  end
end
