class NoahQueries
  def initialize(connection: ActiveRecord::Base.connection)
    @connection = connection
  end

  def fetch_kpis
    conn.exec_query(<<~SQL).to_a
      SELECT
        kpi,
        display_name,
        description,
        category,
        value,
        value_format,
        unit,
        data,
        metadata,
        updated_at
      FROM noah.kpis
      ORDER BY
        CASE category
          WHEN 'core' THEN 1
          WHEN 'season' THEN 2
          ELSE 3
        END,
        kpi
    SQL
  end

  def fetch_player_summary(start_date:, end_date:, include_predraft:, exclude_player_ids:, is_three:, shot_type:, is_corner_three:)
    where_sql = shot_base_where_sql(
      start_date: start_date,
      end_date: end_date,
      is_three: is_three,
      shot_type: shot_type,
      is_corner_three: is_corner_three,
      table_alias: "s"
    )

    predraft_clause = include_predraft ? "AND p.email ILIKE '%predraft%'" : ""
    exclude_clause = noah_id_exclusion_clause(exclude_player_ids)

    conn.exec_query(<<~SQL).to_a
      SELECT
        s.noah_id,
        p.nba_id,
        p.player_name,
        p.roster_group,
        COUNT(s.made)::integer AS count,
        AVG(s.made)::float AS made_mean,
        AVG(s.is_swish)::float AS is_swish_mean,
        AVG(s.angle)::float AS angle_mean,
        STDDEV(s.angle)::float AS angle_std,
        AVG(s.depth)::float AS depth_mean,
        STDDEV(s.depth)::float AS depth_std,
        AVG(s.left_right)::float AS left_right_mean,
        STDDEV(s.left_right)::float AS left_right_std
      FROM noah.shots s
      LEFT JOIN noah.players p
        ON p.noah_id = s.noah_id
      WHERE #{where_sql}
        AND p.noah_id != 1248674
        #{predraft_clause}
        #{exclude_clause}
      GROUP BY s.noah_id, p.nba_id, p.player_name, p.roster_group
      ORDER BY count DESC, p.player_name ASC
    SQL
  end

  def fetch_player_weekly(start_date:, end_date:, noah_id:, is_three:, shot_type:, is_corner_three:)
    where_sql = shot_base_where_sql(
      start_date: start_date,
      end_date: end_date,
      is_three: is_three,
      shot_type: shot_type,
      is_corner_three: is_corner_three,
      table_alias: "s"
    )

    conn.exec_query(<<~SQL).to_a
      SELECT
        DATE_TRUNC('week', s.shot_date)::date AS week,
        COUNT(s.made)::integer AS shots,
        AVG(s.made)::float AS make_pct,
        AVG(s.is_swish)::float AS swish_pct,
        AVG(s.angle)::float AS angle_mean,
        AVG(s.depth)::float AS depth_mean,
        AVG(s.left_right)::float AS left_right_mean,
        STDDEV(s.depth)::float AS depth_std,
        STDDEV(s.left_right)::float AS left_right_std
      FROM noah.shots s
      WHERE #{where_sql}
        AND s.noah_id = #{conn.quote(noah_id.to_i)}
      GROUP BY DATE_TRUNC('week', s.shot_date)
      ORDER BY week ASC
    SQL
  end

  def fetch_player_shot_type_breakdown(start_date:, end_date:, noah_id:, is_three:, shot_type:, is_corner_three:)
    where_sql = shot_base_where_sql(
      start_date: start_date,
      end_date: end_date,
      is_three: is_three,
      shot_type: shot_type,
      is_corner_three: is_corner_three,
      table_alias: "s"
    )

    conn.exec_query(<<~SQL).to_a
      SELECT
        COALESCE(NULLIF(s.shot_type, ''), 'Unlabeled') AS shot_type,
        COUNT(s.made)::integer AS shots,
        AVG(s.made)::float AS make_pct,
        AVG(s.is_swish)::float AS swish_pct
      FROM noah.shots s
      WHERE #{where_sql}
        AND s.noah_id = #{conn.quote(noah_id.to_i)}
      GROUP BY COALESCE(NULLIF(s.shot_type, ''), 'Unlabeled')
      ORDER BY shots DESC, shot_type ASC
    SQL
  end

  def fetch_zone_summary(start_date:, end_date:, noah_id:, is_three:, shot_type:, is_corner_three:)
    where_sql = shot_base_where_sql(
      start_date: start_date,
      end_date: end_date,
      is_three: is_three,
      shot_type: shot_type,
      is_corner_three: is_corner_three,
      table_alias: "s"
    )

    conn.exec_query(<<~SQL).to_a
      WITH classified AS (
        SELECT
          CASE
            WHEN s.is_three = 1 AND COALESCE(s.shot_length, 0) >= 30 THEN 'far-three'
            WHEN s.is_three = 1 AND COALESCE(s.is_corner_three, 0) = 1 AND COALESCE(s.shot_origin_x, 0) < 0 THEN 'left-corner-three'
            WHEN s.is_three = 1 AND COALESCE(s.is_corner_three, 0) = 1 THEN 'right-corner-three'
            WHEN s.is_three = 1 AND COALESCE(s.shot_origin_x, 0) < -7 THEN 'left-wing-three'
            WHEN s.is_three = 1 AND COALESCE(s.shot_origin_x, 0) > 7 THEN 'right-wing-three'
            WHEN s.is_three = 1 THEN 'middle-three'
            WHEN s.is_three = 0 AND COALESCE(s.shot_length, 0) <= 5 THEN 'rim'
            WHEN s.is_three = 0 AND COALESCE(s.shot_length, 0) <= 12 THEN 'paint'
            WHEN s.is_three = 0 AND ABS(COALESCE(s.shot_origin_x, 0)) >= 19 AND COALESCE(s.shot_origin_y, 0) <= 8 AND COALESCE(s.shot_origin_x, 0) < 0 THEN 'left-corner-two'
            WHEN s.is_three = 0 AND ABS(COALESCE(s.shot_origin_x, 0)) >= 19 AND COALESCE(s.shot_origin_y, 0) <= 8 THEN 'right-corner-two'
            WHEN s.is_three = 0 AND COALESCE(s.shot_origin_x, 0) < -5 THEN 'left-wing-two'
            WHEN s.is_three = 0 AND COALESCE(s.shot_origin_x, 0) > 5 THEN 'right-wing-two'
            ELSE 'middle-two'
          END AS zone_name,
          COALESCE(s.made, 0)::integer AS made
        FROM noah.shots s
        WHERE #{where_sql}
          AND s.noah_id = #{conn.quote(noah_id.to_i)}
      )
      SELECT
        zone_name,
        COUNT(*)::integer AS attempts,
        SUM(made)::integer AS made
      FROM classified
      GROUP BY zone_name
      ORDER BY zone_name ASC
    SQL
  end

  private

  attr_reader :connection

  def conn
    connection
  end

  def shot_base_where_sql(start_date:, end_date:, is_three:, shot_type:, is_corner_three:, table_alias:)
    conditions = [
      "#{table_alias}.is_layup = 0",
      "#{table_alias}.is_free_throw = 0",
      "#{table_alias}.shot_date >= #{conn.quote(start_date)}::date",
      "#{table_alias}.shot_date <= #{conn.quote(end_date)}::date"
    ]

    conditions << "#{table_alias}.is_three = #{conn.quote(is_three.to_i)}" unless is_three.nil?
    conditions << "#{table_alias}.shot_type = #{conn.quote(shot_type.to_s)}" if shot_type.present?
    conditions << "#{table_alias}.is_corner_three = #{conn.quote(is_corner_three.to_i)}" unless is_corner_three.nil?

    conditions.join(" AND ")
  end

  def noah_id_exclusion_clause(ids)
    normalized = Array(ids).filter_map do |id|
      Integer(id)
    rescue ArgumentError, TypeError
      nil
    end.uniq

    return "" if normalized.empty?

    quoted = normalized.map { |id| conn.quote(id) }.join(", ")
    "AND p.noah_id NOT IN (#{quoted})"
  end
end
