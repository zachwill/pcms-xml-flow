class SalaryBookQueries
  def initialize(connection:)
    @connection = connection
  end

  # Team index rows for the selected salary year (single query).
  # Includes all metadata needed by the shell command bar + logos map.
  def team_index_rows(year)
    year_sql = @connection.quote(year)

    @connection.exec_query(<<~SQL).to_a
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
  def tankathon_payload(year)
    year_sql = @connection.quote(year.to_i)

    rows = @connection.exec_query(<<~SQL).to_a
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
end
