class TeamSummaryQueries
  def initialize(connection: ActiveRecord::Base.connection)
    @connection = connection
  end

  private attr_reader :connection

  def conn
    connection
  end

  def fetch_rows(year:, conference:, pressure:, sort:, sort_sql:, team_codes: nil, apply_filters: true)
    where_clauses = [
      "tsw.salary_year = #{conn.quote(year)}",
      "t.league_lk = 'NBA'",
      "t.team_name NOT LIKE 'Non-NBA%'"
    ]

    if apply_filters && conference.to_s != "all"
      where_clauses << "t.conference_name = #{conn.quote(conference)}"
    end

    if apply_filters
      case pressure.to_s
      when "over_tax"
        where_clauses << "COALESCE(tsw.room_under_tax, 0) < 0"
      when "over_apron1"
        where_clauses << "COALESCE(tsw.room_under_apron1, 0) < 0"
      when "over_apron2"
        where_clauses << "COALESCE(tsw.room_under_apron2, 0) < 0"
      end
    end

    codes = Array(team_codes).map { |code| code.to_s.strip.upcase }.select { |code| code.match?(/\A[A-Z]{3}\z/) }.uniq
    if codes.any?
      quoted_codes = codes.map { |code| conn.quote(code) }.join(", ")
      where_clauses << "tsw.team_code IN (#{quoted_codes})"
    end

    order_sql = if codes.any?
      "tsw.team_code ASC"
    else
      sort_sql.fetch(sort)
    end

    conn.exec_query(<<~SQL).to_a
      SELECT
        tsw.team_code,
        t.team_name,
        t.team_id,
        t.conference_name,
        tsw.salary_year,
        tsw.cap_total,
        tsw.cap_total_hold,
        tsw.tax_total,
        tsw.apron_total,
        tsw.salary_cap_amount,
        tsw.tax_level_amount,
        tsw.tax_apron_amount,
        tsw.tax_apron2_amount,
        (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0))::bigint AS cap_space,
        (COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0))::bigint AS tax_overage,
        tsw.room_under_tax,
        tsw.room_under_apron1,
        tsw.room_under_apron2,
        tsw.is_taxpayer,
        tsw.is_repeater_taxpayer,
        tsw.is_subject_to_apron,
        tsw.apron_level_lk,
        tsw.roster_row_count,
        tsw.two_way_row_count,
        CASE
          WHEN COALESCE(tsw.room_under_apron2, 0) < 0 THEN 'over_apron2'
          WHEN COALESCE(tsw.room_under_apron1, 0) < 0 THEN 'over_apron1'
          WHEN COALESCE(tsw.room_under_tax, 0) < 0 THEN 'over_tax'
          WHEN (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) < 0 THEN 'over_cap'
          ELSE 'under_cap'
        END AS pressure_bucket,
        CASE
          WHEN COALESCE(tsw.room_under_apron2, 0) < 0 THEN 4
          WHEN COALESCE(tsw.room_under_apron1, 0) < 0 THEN 3
          WHEN COALESCE(tsw.room_under_tax, 0) < 0 THEN 2
          WHEN (COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) < 0 THEN 1
          ELSE 0
        END AS pressure_rank,
        pcms.fn_luxury_tax_amount(
          tsw.salary_year,
          GREATEST(0::bigint, COALESCE(tsw.tax_total, 0) - COALESCE(tsw.tax_level_amount, 0)),
          COALESCE(tsw.is_repeater_taxpayer, false)
        ) AS luxury_tax_owed,
        tsw.refreshed_at
      FROM pcms.team_salary_warehouse tsw
      JOIN pcms.teams t
        ON t.team_code = tsw.team_code
      WHERE #{where_clauses.join(" AND ")}
      ORDER BY #{order_sql}
    SQL
  end
end
