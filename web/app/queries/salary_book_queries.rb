require "json"

module SalaryBookQueries
  module_function

  # Team index rows for the selected salary year (single query).
  # Includes all metadata needed by the shell command bar + logos map.
  def fetch_team_index_rows(year)
    year_sql = conn.quote(year)

    conn.exec_query(<<~SQL).to_a
      SELECT
        tsw.team_code,
        t.team_name,
        t.conference_name,
        t.team_id
      FROM pcms.team_salary_warehouse tsw
      LEFT JOIN pcms.teams t
        ON t.team_code = tsw.team_code
       AND t.league_lk = 'NBA'
      WHERE tsw.salary_year = #{year_sql}
      ORDER BY tsw.team_code
    SQL
  end

  # Tankathon-style standings board sourced from nba.standings.
  # For a requested salary year, use that season_year when present;
  # otherwise gracefully fall back to the latest available season.
  def fetch_tankathon_payload(year)
    year_sql = conn.quote(year.to_i)

    rows = conn.exec_query(<<~SQL).to_a
      WITH target_season AS (
        SELECT COALESCE(
          (
            SELECT s.season_year
            FROM nba.standings s
            WHERE s.league_id = '00'
              AND s.season_type = 'Regular Season'
              AND s.season_year = #{year_sql}
            LIMIT 1
          ),
          (
            SELECT MAX(s.season_year)
            FROM nba.standings s
            WHERE s.league_id = '00'
              AND s.season_type = 'Regular Season'
          )
        ) AS season_year
      ),
      latest_dates AS (
        SELECT
          s.team_id,
          MAX(s.standing_date) AS standing_date
        FROM nba.standings s
        JOIN target_season ts
          ON ts.season_year = s.season_year
        WHERE s.league_id = '00'
          AND s.season_type = 'Regular Season'
        GROUP BY s.team_id
      ),
      latest AS (
        SELECT s.*
        FROM nba.standings s
        JOIN target_season ts
          ON ts.season_year = s.season_year
        JOIN latest_dates ld
          ON ld.team_id = s.team_id
         AND ld.standing_date = s.standing_date
        WHERE s.league_id = '00'
          AND s.season_type = 'Regular Season'
      ),
      ranked AS (
        SELECT
          COALESCE(t.team_code, l.team_tricode) AS team_code,
          COALESCE(t.team_name, CONCAT_WS(' ', l.team_city, l.team_name), l.team_tricode) AS team_name,
          COALESCE(t.team_id, l.team_id) AS team_id,
          l.team_tricode,
          l.conference,
          l.playoff_rank AS conference_rank,
          l.league_rank,
          l.wins,
          l.losses,
          l.win_pct,
          l.record,
          l.l10,
          l.current_streak_text,
          l.conference_games_back,
          l.league_games_back,
          l.diff_pts_per_game,
          l.season_year,
          l.season_label,
          l.standing_date,
          ROW_NUMBER() OVER (
            ORDER BY
              l.win_pct ASC NULLS LAST,
              l.wins ASC NULLS LAST,
              l.losses DESC NULLS LAST,
              COALESCE(t.team_code, l.team_tricode) ASC
          ) AS lottery_rank
        FROM latest l
        LEFT JOIN pcms.teams t
          ON t.team_id = l.team_id
         AND t.league_lk = 'NBA'
      )
      SELECT
        team_code,
        team_name,
        team_id,
        team_tricode,
        conference,
        conference_rank,
        league_rank,
        wins,
        losses,
        win_pct,
        record,
        l10,
        current_streak_text,
        conference_games_back,
        league_games_back,
        diff_pts_per_game,
        season_year,
        season_label,
        standing_date,
        lottery_rank
      FROM ranked
      ORDER BY lottery_rank ASC
    SQL

    first_row = rows.first || {}

    {
      rows:,
      season_year: first_row["season_year"],
      season_label: first_row["season_label"],
      standing_date: first_row["standing_date"]
    }
  end

  def build_team_maps(rows)
    teams_by_conference = { "Eastern" => [], "Western" => [] }
    team_meta_by_code = {}

    rows.each do |row|
      code = row["team_code"]
      next if code.blank?

      team_meta_by_code[code] = row

      conf = row["conference_name"]
      next unless teams_by_conference.key?(conf)

      teams_by_conference[conf] << {
        code:,
        name: (row["team_name"].presence || code)
      }
    end

    [teams_by_conference, team_meta_by_code]
  end

  def fetch_combobox_players(team_code:, query:, limit:)
    q = query.to_s.strip
    limit_i = [[limit.to_i, 1].max, 50].min

    # Blank query defaults to active-team roster. If no team context is provided,
    # return no rows (avoid expensive unscoped blank searches).
    where_clauses = []
    q_prefix = nil
    q_token_prefix = nil

    if q.blank?
      return [] if team_code.blank?

      where_clauses << "sbw.team_code = #{conn.quote(team_code)}"
    else
      q_like = conn.quote("%#{q}%")
      q_prefix = conn.quote("#{q.downcase}%")
      q_token_prefix = conn.quote("% #{q.downcase}%")

      where_clauses << "sbw.player_name ILIKE #{q_like}"
    end

    order_rank_sql = if q.present?
      <<~SQL.squish
        CASE
          WHEN LOWER(sbw.player_name) LIKE #{q_prefix} THEN 0
          WHEN LOWER(sbw.player_name) LIKE #{q_token_prefix} THEN 1
          ELSE 2
        END
      SQL
    end

    where_sql = where_clauses.join(" AND ")

    order_parts = []
    order_parts << order_rank_sql if order_rank_sql.present?
    order_parts << "sbw.cap_2025 DESC NULLS LAST"
    order_parts << "sbw.player_name ASC"
    order_parts << "sbw.player_id ASC"
    order_sql = order_parts.join(",\n          ")

    conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        sbw.agent_name,
        sbw.age,
        p.years_of_service,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.is_two_way,
        t.team_id
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.people p
        ON p.person_id = sbw.player_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE #{where_sql}
      ORDER BY
        #{order_sql}
      LIMIT #{limit_i}
    SQL
  end

  def fetch_team_players(team_code)
    team_sql = conn.quote(team_code)

    conn.exec_query(player_columns_sql("sbw.team_code = #{team_sql}")).to_a
  end

  def player_columns_sql(where_clause)
    <<~SQL
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        sbw.age,
        p.years_of_service,
        sbw.agent_name,
        sbw.agent_id,
        a.agency_name,
        epm_latest.season AS epm_season,
        epm_latest.epm AS epm_value,
        epm_latest.epm_pctl AS epm_percentile,
        sbw.cap_2025, sbw.cap_2026, sbw.cap_2027, sbw.cap_2028, sbw.cap_2029, sbw.cap_2030,
        sbw.cap_hold_2025, sbw.cap_hold_2026, sbw.cap_hold_2027, sbw.cap_hold_2028, sbw.cap_hold_2029, sbw.cap_hold_2030,
        sbw.pct_cap_2025, sbw.pct_cap_2026, sbw.pct_cap_2027, sbw.pct_cap_2028, sbw.pct_cap_2029, sbw.pct_cap_2030,
        sbw.total_salary_from_2025,
        sbw.option_2025, sbw.option_2026, sbw.option_2027, sbw.option_2028, sbw.option_2029, sbw.option_2030,
        sbw.is_two_way,
        sbw.is_no_trade,
        sbw.is_trade_bonus,
        sbw.trade_bonus_percent,
        sbw.trade_kicker_display,
        sbw.is_trade_consent_required_now,
        sbw.is_trade_restricted_now,
        sbw.is_poison_pill,
        sbw.is_min_contract,
        sbw.is_fully_guaranteed_2025, sbw.is_fully_guaranteed_2026, sbw.is_fully_guaranteed_2027,
        sbw.is_fully_guaranteed_2028, sbw.is_fully_guaranteed_2029, sbw.is_fully_guaranteed_2030,
        sbw.is_partially_guaranteed_2025, sbw.is_partially_guaranteed_2026, sbw.is_partially_guaranteed_2027,
        sbw.is_partially_guaranteed_2028, sbw.is_partially_guaranteed_2029, sbw.is_partially_guaranteed_2030,
        sbw.is_non_guaranteed_2025, sbw.is_non_guaranteed_2026, sbw.is_non_guaranteed_2027,
        sbw.is_non_guaranteed_2028, sbw.is_non_guaranteed_2029, sbw.is_non_guaranteed_2030,
        sbw.pct_cap_percentile_2025, sbw.pct_cap_percentile_2026, sbw.pct_cap_percentile_2027,
        sbw.pct_cap_percentile_2028, sbw.pct_cap_percentile_2029, sbw.pct_cap_percentile_2030,
        sbw.contract_type_code,
        sbw.contract_type_lookup_value
      FROM pcms.salary_book_warehouse sbw
      LEFT JOIN pcms.people p
        ON p.person_id = sbw.player_id
      LEFT JOIN pcms.agents a
        ON a.agent_id = sbw.agent_id
      LEFT JOIN LATERAL (
        SELECT
          e.season,
          e.epm,
          e.epm_pctl
        FROM dunks.epm e
        WHERE e.nba_id = sbw.player_id
          AND e.season_type = 2
        ORDER BY (e.epm IS NULL), e.season DESC
        LIMIT 1
      ) epm_latest
        ON true
      WHERE #{where_clause}
      ORDER BY sbw.team_code, sbw.cap_2025 DESC NULLS LAST, sbw.total_salary_from_2025 DESC NULLS LAST, sbw.player_name
    SQL
  end

  def fetch_player(player_id)
    id_sql = conn.quote(player_id)

    conn.exec_query(
      <<~SQL
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_name,
          sbw.agent_id,
          sbw.age,
          p.years_of_service,
          epm_latest.season AS epm_season,
          epm_latest.epm AS epm_value,
          epm_latest.epm_pctl AS epm_percentile,
          sbw.cap_2025,
          sbw.cap_2026,
          sbw.cap_2027,
          sbw.cap_2028,
          sbw.cap_2029,
          sbw.cap_2030,
          sbw.cap_hold_2025,
          sbw.cap_hold_2026,
          sbw.cap_hold_2027,
          sbw.cap_hold_2028,
          sbw.cap_hold_2029,
          sbw.cap_hold_2030,
          sbw.total_salary_from_2025,
          sbw.option_2025,
          sbw.option_2026,
          sbw.option_2027,
          sbw.option_2028,
          sbw.option_2029,
          sbw.option_2030,
          sbw.is_two_way,
          sbw.is_no_trade,
          sbw.is_trade_bonus,
          sbw.trade_bonus_percent,
          sbw.trade_kicker_display,
          sbw.is_poison_pill,
          sbw.is_trade_consent_required_now,
          sbw.is_trade_preconsented,
          sbw.is_trade_restricted_now,
          sbw.trade_restriction_lookup_value,
          sbw.is_min_contract,
          sbw.min_contract_lookup_value,
          sbw.contract_type_code,
          sbw.contract_type_lookup_value,
          sbw.signed_method_code,
          sbw.signed_method_lookup_value,
          sbw.exception_type_lookup_value,
          sbw.guaranteed_amount_2025,
          sbw.guaranteed_amount_2026,
          sbw.guaranteed_amount_2027,
          sbw.guaranteed_amount_2028,
          sbw.guaranteed_amount_2029,
          sbw.guaranteed_amount_2030,
          sbw.is_fully_guaranteed_2025,
          sbw.is_fully_guaranteed_2026,
          sbw.is_fully_guaranteed_2027,
          sbw.is_fully_guaranteed_2028,
          sbw.is_fully_guaranteed_2029,
          sbw.is_fully_guaranteed_2030,
          sbw.is_partially_guaranteed_2025,
          sbw.is_partially_guaranteed_2026,
          sbw.is_partially_guaranteed_2027,
          sbw.is_partially_guaranteed_2028,
          sbw.is_partially_guaranteed_2029,
          sbw.is_partially_guaranteed_2030,
          sbw.is_non_guaranteed_2025,
          sbw.is_non_guaranteed_2026,
          sbw.is_non_guaranteed_2027,
          sbw.is_non_guaranteed_2028,
          sbw.is_non_guaranteed_2029,
          sbw.is_non_guaranteed_2030,
          sbw.likely_bonus_2025,
          sbw.likely_bonus_2026,
          sbw.likely_bonus_2027,
          sbw.likely_bonus_2028,
          sbw.likely_bonus_2029,
          sbw.likely_bonus_2030,
          sbw.unlikely_bonus_2025,
          sbw.unlikely_bonus_2026,
          sbw.unlikely_bonus_2027,
          sbw.unlikely_bonus_2028,
          sbw.unlikely_bonus_2029,
          sbw.unlikely_bonus_2030,
          sbw.refreshed_at
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.people p
          ON p.person_id = sbw.player_id
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        LEFT JOIN LATERAL (
          SELECT
            e.season,
            e.epm,
            e.epm_pctl
          FROM dunks.epm e
          WHERE e.nba_id = sbw.player_id
            AND e.season_type = 2
          ORDER BY (e.epm IS NULL), e.season DESC
          LIMIT 1
        ) epm_latest
          ON true
        WHERE sbw.player_id = #{id_sql}
        LIMIT 1
      SQL
    ).first
  end

  # One-query payload for a single team's non-player sections.
  # Reduces request latency on remote Postgres by collapsing multiple round-trips.
  # Returns:
  # {
  #   cap_holds: [...],
  #   exceptions: [...],
  #   dead_money: [...],
  #   picks: [...],
  #   team_summaries: { 2025 => {...}, ... },
  #   team_meta: {...}
  # }
  def fetch_team_support_payload(team_code, base_year:, salary_years:)
    team_sql = conn.quote(team_code)
    base_year_int = base_year.to_i
    next_year_int = [base_year_int + 1, salary_years.last].min
    base_year_sql = conn.quote(base_year_int)
    next_year_sql = conn.quote(next_year_int)
    draft_from_year_sql = conn.quote(salary_years.first + 1)
    draft_to_year_sql = conn.quote(salary_years.last + 1)

    row = conn.exec_query(<<~SQL).first || {}
      WITH
      cap_holds AS (
        SELECT
          MIN(chw.non_contract_amount_id) AS id,
          chw.team_code,
          chw.player_id,
          chw.player_name,
          MAX(
            CASE
              WHEN p.birth_date IS NULL THEN NULL
              ELSE ROUND((EXTRACT(EPOCH FROM age(current_date, p.birth_date)) / 31557600.0)::numeric, 1)
            END
          ) AS age,
          MAX(chw.years_of_service)::integer AS years_of_service,
          MAX(p.agent_id)::integer AS agent_id,
          MAX(ag.full_name) AS agent_name,
          MAX(ag.agency_name) AS agency_name,
          'UFA'::text AS amount_type_lk,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2025)::numeric AS cap_2025,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2026)::numeric AS cap_2026,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2027)::numeric AS cap_2027,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2028)::numeric AS cap_2028,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2029)::numeric AS cap_2029,
          MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = 2030)::numeric AS cap_2030,
          GREATEST(
            COALESCE(MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = #{base_year_sql}), 0),
            COALESCE(MAX(chw.cap_amount) FILTER (WHERE chw.salary_year = #{next_year_sql}), 0)
          )::numeric AS cap_sort
        FROM pcms.cap_holds_warehouse chw
        LEFT JOIN pcms.people p
          ON p.person_id = chw.player_id
        LEFT JOIN pcms.agents ag
          ON ag.agent_id = p.agent_id
        WHERE chw.team_code = #{team_sql}
          AND chw.free_agent_status_lk = 'UFA'
          AND chw.salary_year BETWEEN #{base_year_sql} AND #{next_year_sql}
          AND NOT EXISTS (
            SELECT 1
            FROM pcms.salary_book_warehouse sbw
            WHERE sbw.team_code = chw.team_code
              AND sbw.player_id = chw.player_id
          )
        GROUP BY chw.team_code, chw.player_id, chw.player_name
      ),
      exceptions AS (
        SELECT
          team_exception_id AS id,
          team_code,
          exception_type_lk,
          exception_type_name,
          trade_exception_player_id,
          trade_exception_player_name,
          expiration_date,
          is_expired,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2025)::numeric AS remaining_2025,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2026)::numeric AS remaining_2026,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2027)::numeric AS remaining_2027,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2028)::numeric AS remaining_2028,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2029)::numeric AS remaining_2029,
          MAX(remaining_amount) FILTER (WHERE salary_year = 2030)::numeric AS remaining_2030
        FROM pcms.exceptions_warehouse
        WHERE team_code = #{team_sql}
          AND salary_year BETWEEN 2025 AND 2030
          AND COALESCE(is_expired, false) = false
        GROUP BY
          team_exception_id,
          team_code,
          exception_type_lk,
          exception_type_name,
          trade_exception_player_id,
          trade_exception_player_name,
          expiration_date,
          is_expired
      ),
      dead_money AS (
        SELECT
          MIN(dm.transaction_waiver_amount_id) AS id,
          dm.team_code,
          dm.player_id,
          MAX(dm.player_name) AS player_name,
          MAX(dm.waive_date) AS waive_date,
          MAX(p.agent_id)::integer AS agent_id,
          MAX(ag.full_name) AS agent_name,
          MAX(ag.agency_name) AS agency_name,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2025)::numeric AS cap_2025,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2026)::numeric AS cap_2026,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2027)::numeric AS cap_2027,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2028)::numeric AS cap_2028,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2029)::numeric AS cap_2029,
          SUM(dm.cap_value) FILTER (WHERE dm.salary_year = 2030)::numeric AS cap_2030
        FROM pcms.dead_money_warehouse dm
        LEFT JOIN pcms.people p
          ON p.person_id = dm.player_id
        LEFT JOIN pcms.agents ag
          ON ag.agent_id = p.agent_id
        WHERE dm.team_code = #{team_sql}
          AND dm.salary_year BETWEEN 2025 AND 2030
        GROUP BY dm.team_code, dm.player_id
        HAVING BOOL_OR(COALESCE(dm.cap_value, 0) <> 0)
      ),
      picks AS (
        SELECT
          team_code,
          draft_year AS year,
          draft_round AS round,
          asset_slot,
          sub_asset_slot,
          asset_type,
          is_conditional,
          is_swap,
          counterparty_team_code AS origin_team_code,
          raw_part AS description
        FROM pcms.draft_pick_summary_assets
        WHERE team_code = #{team_sql}
          AND draft_year BETWEEN #{draft_from_year_sql} AND #{draft_to_year_sql}
      ),
      two_way_contract_counts AS (
        SELECT
          sby.team_code,
          sby.salary_year,
          COUNT(DISTINCT sby.player_id) FILTER (
            WHERE COALESCE(sby.is_two_way, false)
              AND (sby.cap_amount IS NOT NULL OR sby.tax_amount IS NOT NULL OR sby.apron_amount IS NOT NULL)
          )::int AS two_way_row_count
        FROM pcms.salary_book_yearly sby
        WHERE sby.salary_year BETWEEN 2025 AND 2030
        GROUP BY sby.team_code, sby.salary_year
      ),
      team_summaries_ranked AS (
        SELECT
          tsw.team_code,
          tsw.salary_year,
          tsw.cap_total,
          COALESCE(
            tsw.cap_total_percentile,
            PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.cap_total)
          ) AS cap_total_percentile,
          tsw.cap_total_hold,
          tsw.tax_total,
          tsw.apron_total,
          tsw.roster_row_count,
          COALESCE(twc.two_way_row_count, 0)::int AS two_way_row_count,
          tsw.salary_cap_amount,
          tsw.tax_level_amount,
          tsw.tax_apron_amount,
          tsw.tax_apron2_amount,
          pcms.fn_luxury_tax_amount(
            tsw.salary_year,
            GREATEST(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0), 0),
            COALESCE(tsw.is_repeater_taxpayer, false)
          ) AS luxury_tax_owed,
          (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))::bigint AS cap_space,
          tsw.room_under_tax,
          tsw.room_under_apron1 AS room_under_first_apron,
          tsw.room_under_apron2 AS room_under_second_apron,
          PERCENT_RANK() OVER (
            PARTITION BY tsw.salary_year
            ORDER BY (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))
          ) AS cap_space_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_tax) AS room_under_tax_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_apron1) AS room_under_first_apron_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_apron2) AS room_under_second_apron_percentile,
          tsw.is_taxpayer AS is_over_tax,
          COALESCE(tsw.is_repeater_taxpayer, false) AS is_repeater_taxpayer,
          COALESCE(tsw.is_subject_to_apron, false) AS is_subject_to_apron,
          tsw.is_subject_to_apron AS is_over_first_apron,
          tsw.apron_level_lk,
          tsw.refreshed_at
        FROM pcms.team_salary_warehouse tsw
        LEFT JOIN two_way_contract_counts twc
          ON twc.team_code = tsw.team_code
         AND twc.salary_year = tsw.salary_year
        WHERE tsw.salary_year BETWEEN 2025 AND 2030
      ),
      team_summaries AS (
        SELECT *
        FROM team_summaries_ranked
        WHERE team_code = #{team_sql}
      ),
      team_meta AS (
        SELECT
          team_code,
          team_name,
          conference_name,
          team_id
        FROM pcms.teams
        WHERE team_code = #{team_sql}
          AND league_lk = 'NBA'
        LIMIT 1
      )
      SELECT
        COALESCE(
          (SELECT jsonb_agg(to_jsonb(ch) ORDER BY ch.cap_sort DESC NULLS LAST, ch.player_name ASC NULLS LAST) FROM cap_holds ch),
          '[]'::jsonb
        ) AS cap_holds,
        COALESCE(
          (SELECT jsonb_agg(to_jsonb(ex) ORDER BY ex.remaining_2025 DESC NULLS LAST, ex.exception_type_name ASC NULLS LAST) FROM exceptions ex),
          '[]'::jsonb
        ) AS exceptions,
        COALESCE(
          (SELECT jsonb_agg(to_jsonb(dm) ORDER BY dm.cap_2025 DESC NULLS LAST, dm.player_name ASC NULLS LAST) FROM dead_money dm),
          '[]'::jsonb
        ) AS dead_money,
        COALESCE(
          (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.year, p.round, p.asset_slot, p.sub_asset_slot) FROM picks p),
          '[]'::jsonb
        ) AS picks,
        COALESCE(
          (SELECT jsonb_agg(to_jsonb(ts) ORDER BY ts.salary_year) FROM team_summaries ts),
          '[]'::jsonb
        ) AS team_summaries,
        COALESCE(
          (SELECT to_jsonb(tm) FROM team_meta tm),
          '{}'::jsonb
        ) AS team_meta
    SQL

    cap_holds = parse_jsonb_array(row["cap_holds"])
    exceptions = parse_jsonb_array(row["exceptions"])
    dead_money = parse_jsonb_array(row["dead_money"])
    picks = parse_jsonb_array(row["picks"])
    team_meta = parse_jsonb_object(row["team_meta"])

    picks.each do |pick|
      pick["id"] = "#{pick['team_code']}-#{pick['year']}-#{pick['round']}-#{pick['asset_slot']}-#{pick['sub_asset_slot']}"
    end

    team_summaries = {}
    parse_jsonb_array(row["team_summaries"]).each do |summary|
      next unless summary.is_a?(Hash)

      year = summary["salary_year"]
      next if year.nil?

      team_summaries[year.to_i] = summary
    end

    {
      cap_holds:,
      exceptions:,
      dead_money:,
      picks:,
      team_summaries:,
      team_meta:
    }
  end

  def parse_jsonb_array(value)
    parsed = value.is_a?(String) ? JSON.parse(value) : value
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def parse_jsonb_object(value)
    parsed = value.is_a?(String) ? JSON.parse(value) : value
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # -------------------------------------------------------------------------
  # Sidebar tab data (team context)
  # -------------------------------------------------------------------------

  def fetch_sidebar_draft_assets(team_code, start_year:)
    team_sql = conn.quote(team_code)
    from_year = start_year.to_i

    rows = conn.exec_query(<<~SQL).to_a
      SELECT
        team_code,
        draft_year AS year,
        draft_round AS round,
        asset_slot,
        sub_asset_slot,
        asset_type,
        is_conditional,
        is_swap,
        counterparty_team_code AS origin_team_code,
        raw_part AS description
      FROM pcms.draft_pick_summary_assets
      WHERE team_code = #{team_sql}
        AND draft_year >= #{conn.quote(from_year)}
      ORDER BY draft_year, draft_round, asset_slot, sub_asset_slot
    SQL

    rows.each do |row|
      row["id"] = "#{row['team_code']}-#{row['year']}-#{row['round']}-#{row['asset_slot']}-#{row['sub_asset_slot']}"
    end

    rows
  end

  def fetch_sidebar_rights_by_kind(team_code)
    team_sql = conn.quote(team_code)

    rows = conn.exec_query(<<~SQL).to_a
      SELECT
        player_id,
        player_name,
        rights_kind,
        rights_source,
        source_trade_id,
        source_trade_date,
        draft_year,
        draft_round,
        draft_pick,
        draft_team_code,
        needs_review,
        refreshed_at
      FROM pcms.player_rights_warehouse
      WHERE rights_team_code = #{team_sql}
      ORDER BY rights_kind, draft_year DESC NULLS LAST, draft_round ASC NULLS LAST, draft_pick ASC NULLS LAST, player_name
    SQL

    rows.group_by { |row| row["rights_kind"] }
  end

  # -------------------------------------------------------------------------
  # Team summary data (for header KPIs + sidebar ledger)
  # -------------------------------------------------------------------------

  # Fetch all team salary summaries for all years, grouped by team_code.
  # Returns: { "BOS" => { 2025 => {...}, 2026 => {...}, ... }, "LAL" => {...} }
  def fetch_all_team_summaries(team_codes)
    return {} if team_codes.empty?

    in_list = team_codes.map { |c| conn.quote(c) }.join(",")

    rows = conn.exec_query(<<~SQL).to_a
      WITH two_way_contract_counts AS (
        SELECT
          sby.team_code,
          sby.salary_year,
          COUNT(DISTINCT sby.player_id) FILTER (
            WHERE COALESCE(sby.is_two_way, false)
              AND (sby.cap_amount IS NOT NULL OR sby.tax_amount IS NOT NULL OR sby.apron_amount IS NOT NULL)
          )::int AS two_way_row_count
        FROM pcms.salary_book_yearly sby
        WHERE sby.salary_year BETWEEN 2025 AND 2030
        GROUP BY sby.team_code, sby.salary_year
      ),
      ranked AS (
        SELECT
          tsw.team_code,
          tsw.salary_year,
          tsw.cap_total,
          COALESCE(
            tsw.cap_total_percentile,
            PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.cap_total)
          ) AS cap_total_percentile,
          tsw.cap_total_hold,
          tsw.tax_total,
          tsw.apron_total,
          tsw.roster_row_count,
          COALESCE(twc.two_way_row_count, 0)::int AS two_way_row_count,
          tsw.salary_cap_amount,
          tsw.tax_level_amount,
          tsw.tax_apron_amount,
          tsw.tax_apron2_amount,
          pcms.fn_luxury_tax_amount(
            tsw.salary_year,
            GREATEST(COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0), 0),
            COALESCE(tsw.is_repeater_taxpayer, false)
          ) AS luxury_tax_owed,
          (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))::bigint AS cap_space,
          tsw.room_under_tax,
          tsw.room_under_apron1 AS room_under_first_apron,
          tsw.room_under_apron2 AS room_under_second_apron,
          PERCENT_RANK() OVER (
            PARTITION BY tsw.salary_year
            ORDER BY (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))
          ) AS cap_space_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_tax) AS room_under_tax_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_apron1) AS room_under_first_apron_percentile,
          PERCENT_RANK() OVER (PARTITION BY tsw.salary_year ORDER BY tsw.room_under_apron2) AS room_under_second_apron_percentile,
          tsw.is_taxpayer AS is_over_tax,
          COALESCE(tsw.is_repeater_taxpayer, false) AS is_repeater_taxpayer,
          COALESCE(tsw.is_subject_to_apron, false) AS is_subject_to_apron,
          tsw.is_subject_to_apron AS is_over_first_apron,
          tsw.apron_level_lk,
          tsw.refreshed_at
        FROM pcms.team_salary_warehouse tsw
        LEFT JOIN two_way_contract_counts twc
          ON twc.team_code = tsw.team_code
         AND twc.salary_year = tsw.salary_year
        WHERE tsw.salary_year BETWEEN 2025 AND 2030
      )
      SELECT *
      FROM ranked
      WHERE team_code IN (#{in_list})
      ORDER BY team_code, salary_year
    SQL

    result = {}
    rows.each do |row|
      team_code = row["team_code"]
      year = row["salary_year"]
      result[team_code] ||= {}
      result[team_code][year] = row
    end
    result
  end

  # Fetch team metadata (name, conference, team_id) for a single team
  def fetch_team_meta(team_code)
    team_sql = conn.quote(team_code)

    conn.exec_query(<<~SQL).first || {}
      SELECT
        team_code,
        team_name,
        conference_name,
        team_id
      FROM pcms.teams
      WHERE team_code = #{team_sql}
        AND league_lk = 'NBA'
      LIMIT 1
    SQL
  end

  # Fetch team metadata keyed by code (for compact inline logo+code displays).
  def fetch_team_meta_by_codes(team_codes)
    codes = Array(team_codes).map { |c| c.to_s.strip.upcase }.reject(&:blank?).uniq
    return {} if codes.empty?

    in_list = codes.map { |c| conn.quote(c) }.join(",")

    rows = conn.exec_query(<<~SQL).to_a
      SELECT
        team_code,
        team_name,
        conference_name,
        team_id
      FROM pcms.teams
      WHERE league_lk = 'NBA'
        AND team_code IN (#{in_list})
    SQL

    rows.each_with_object({}) { |row, h| h[row["team_code"]] = row }
  end

  def parse_pg_text_array(value)
    return [] if value.nil?
    return value.map { |v| v.to_s.strip.upcase }.reject(&:blank?) if value.is_a?(Array)

    s = value.to_s
    return [] if s.blank? || s == "{}"

    s.gsub(/[{}\"]/, "")
      .split(",")
      .map { |v| v.to_s.strip.upcase }
      .reject(&:blank?)
  end

  def extract_pick_related_team_codes(picks)
    rows = Array(picks)

    direct_codes = rows.map { |row| row["origin_team_code"].to_s.strip.upcase.presence }.compact
    counterparty_codes = rows.flat_map { |row| parse_pg_text_array(row["counterparty_team_codes"]) }
    via_codes = rows.flat_map { |row| parse_pg_text_array(row["via_team_codes"]) }

    (direct_codes + counterparty_codes + via_codes).uniq
  end

  # -------------------------------------------------------------------------
  # Agent data (for sidebar overlay)
  # -------------------------------------------------------------------------

  def fetch_agent(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first
      SELECT
        agent_id,
        full_name AS name,
        agency_id,
        agency_name
      FROM pcms.agents
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  def fetch_agent_clients(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).to_a
      SELECT
        s.player_id,
        COALESCE(
          NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
          s.player_name
        ) AS player_name,
        p.display_first_name,
        p.display_last_name,
        COALESCE(NULLIF(s.person_team_code, ''), s.team_code) AS team_code,
        s.age,
        p.years_of_service,
        s.cap_2025::numeric,
        s.cap_2026::numeric,
        s.cap_2027::numeric,
        s.cap_2028::numeric,
        s.cap_2029::numeric,
        s.cap_2030::numeric,
        COALESCE(s.is_two_way, false)::boolean AS is_two_way,
        COALESCE(s.is_no_trade, false)::boolean AS is_no_trade,
        COALESCE(s.is_trade_bonus, false)::boolean AS is_trade_bonus,
        COALESCE(s.is_min_contract, false)::boolean AS is_min_contract,
        COALESCE(s.is_trade_restricted_now, false)::boolean AS is_trade_restricted_now,
        s.option_2025,
        s.option_2026,
        s.option_2027,
        s.option_2028,
        s.option_2029,
        s.option_2030,
        s.is_non_guaranteed_2025,
        s.is_non_guaranteed_2026,
        s.is_non_guaranteed_2027,
        s.is_non_guaranteed_2028,
        s.is_non_guaranteed_2029,
        s.is_non_guaranteed_2030,
        s.contract_type_code,
        t.team_id,
        t.team_name
      FROM pcms.salary_book_warehouse s
      LEFT JOIN pcms.people p ON s.player_id = p.person_id
      LEFT JOIN pcms.teams t ON s.team_code = t.team_code AND t.league_lk = 'NBA'
      WHERE s.agent_id = #{id_sql}
      ORDER BY s.cap_2025 DESC NULLS LAST, player_name
    SQL
  end

  def fetch_agent_rollup(agent_id)
    id_sql = conn.quote(agent_id)

    conn.exec_query(<<~SQL).first || {}
      SELECT
        standard_count,
        two_way_count,
        client_count AS total_count,
        team_count,

        cap_2025_total AS book_2025,
        cap_2026_total AS book_2026,
        cap_2027_total AS book_2027,

        rookie_scale_count,
        min_contract_count,
        no_trade_count,
        trade_kicker_count,
        trade_restricted_count,

        expiring_2025,
        expiring_2026,
        expiring_2027,

        player_option_count,
        team_option_count,

        max_contract_count,
        prior_year_nba_now_free_agent_count,

        cap_2025_total_percentile,
        cap_2026_total_percentile,
        cap_2027_total_percentile,
        client_count_percentile,
        max_contract_count_percentile,
        team_count_percentile,
        standard_count_percentile,
        two_way_count_percentile
      FROM pcms.agents_warehouse
      WHERE agent_id = #{id_sql}
      LIMIT 1
    SQL
  end

  # -------------------------------------------------------------------------
  # Pick data (for sidebar overlay)
  # -------------------------------------------------------------------------

  def fetch_pick_assets(team_code, year, round)
    team_sql = conn.quote(team_code)
    year_sql = conn.quote(year)
    round_sql = conn.quote(round)

    conn.exec_query(<<~SQL).to_a
      SELECT
        team_code,
        draft_year AS year,
        draft_round AS round,
        asset_slot,
        sub_asset_slot,
        asset_type,
        is_conditional,
        is_swap,
        counterparty_team_code AS origin_team_code,
        counterparty_team_codes,
        via_team_codes,
        raw_part AS description,
        raw_round_text,
        raw_fragment,
        endnote_explanation,
        endnote_trade_date,
        endnote_is_swap,
        endnote_is_conditional,
        refreshed_at
      FROM pcms.draft_pick_summary_assets
      WHERE team_code = #{team_sql}
        AND draft_year = #{year_sql}
        AND draft_round = #{round_sql}
      ORDER BY asset_slot, sub_asset_slot
    SQL
  end

  class << self
    private

    def conn
      ActiveRecord::Base.connection
    end
  end
end
