module PlayerService
  module_function

  URGENCY_DEFINITIONS = {
    "urgent" => {
      title: "Urgent decisions",
      subtitle: "Lock-now posture or immediate horizon triggers"
    },
    "upcoming" => {
      title: "Upcoming pressure",
      subtitle: "Future options/guarantees or pathway pressure"
    },
    "stable" => {
      title: "Stable commitments",
      subtitle: "No immediate option/expiry pressure"
    }
  }.freeze

  def annotate_player_urgency!(rows:, cap_horizon:)
    next_horizon_year = cap_horizon.to_i + 1

    Array(rows).each do |row|
      urgency_key, urgency_reason = player_row_urgency(row, next_horizon_year: next_horizon_year, cap_horizon: cap_horizon)
      row["urgency_key"] = urgency_key
      row["urgency_label"] = urgency_lane_label(urgency_key, URGENCY_DEFINITIONS)
      row["urgency_reason"] = urgency_reason
      row["urgency_rank"] = urgency_rank(urgency_key)
    end
  end

  def player_row_urgency(row, next_horizon_year:, cap_horizon:)
    if truthy_row_value?(row["has_lock_now"])
      return ["urgent", "Lock now posture (TR/consent/no-trade)"]
    end

    if truthy_row_value?(row["expires_after_horizon"])
      return ["urgent", "Expires after #{cap_horizon_label(cap_horizon)}"]
    end

    if truthy_row_value?(row["has_next_horizon_option"])
      option_code = row["next_horizon_option"].to_s.presence || "Option"
      return ["urgent", "#{option_code} decision before #{cap_horizon_label(next_horizon_year)}"]
    end

    if truthy_row_value?(row["has_next_horizon_non_guaranteed"])
      return ["urgent", "Non-guaranteed salary in #{cap_horizon_label(next_horizon_year)}"]
    end

    if truthy_row_value?(row["has_future_option"])
      return ["upcoming", "Option decision window in forward years"]
    end

    if truthy_row_value?(row["has_non_guaranteed"])
      return ["upcoming", "Guarantee pressure in forward years"]
    end

    if truthy_row_value?(row["is_trade_bonus"])
      return ["upcoming", "Trade kicker leverage"]
    end

    if truthy_row_value?(row["is_two_way"])
      return ["upcoming", "Two-way conversion runway"]
    end

    ["stable", "No immediate horizon trigger"]
  end

  def urgency_rank(key)
    case key.to_s
    when "urgent" then 0
    when "upcoming" then 1
    else 2
    end
  end

  def urgency_lane_label(key, definitions = URGENCY_DEFINITIONS)
    definitions.dig(key.to_s, :title) || definitions.dig("stable", :title)
  end

  def constrained_row?(row)
    truthy_row_value?(row["has_lock_now"]) || truthy_row_value?(row["is_trade_bonus"]) || truthy_row_value?(row["has_future_option"]) || truthy_row_value?(row["has_non_guaranteed"])
  end

  def truthy_row_value?(value)
    value == true || value.to_s == "t" || value.to_s.casecmp("true").zero? || value.to_s == "1"
  end

  def matches_urgency_sub_lens?(row, lens:)
    case lens.to_s
    when "option_only"
      truthy_row_value?(row["has_next_horizon_option"]) || truthy_row_value?(row["has_future_option"])
    when "expiring_only"
      truthy_row_value?(row["expires_after_horizon"])
    when "non_guaranteed_only"
      truthy_row_value?(row["has_next_horizon_non_guaranteed"]) || truthy_row_value?(row["has_non_guaranteed"])
    else
      true
    end
  end

  def status_lens_label(status_lens)
    case status_lens
    when "two_way" then "Two-Way"
    when "restricted" then "Trade restricted"
    when "no_trade" then "No-trade"
    else "All"
    end
  end

  def constraint_lens_label(constraint_lens)
    case constraint_lens
    when "lock_now" then "Lock now"
    when "options" then "Options ahead"
    when "non_guaranteed" then "Non-guaranteed"
    when "trade_kicker" then "Trade kicker"
    when "expiring" then "Expiring after horizon"
    else "All commitments"
    end
  end

  def urgency_lens_label(urgency_lens)
    case urgency_lens.to_s
    when "urgent" then "Urgent decisions"
    when "upcoming" then "Upcoming pressure"
    when "stable" then "Stable commitments"
    else "All urgency lanes"
    end
  end

  def urgency_sub_lens_label(urgency_sub_lens)
    case urgency_sub_lens.to_s
    when "option_only" then "Option-only"
    when "expiring_only" then "Expiring-only"
    when "non_guaranteed_only" then "Non-guaranteed-only"
    else "All triggers"
    end
  end

  def cap_horizon_label(horizon_year)
    year = horizon_year.to_i
    "#{year.to_s[-2..]}-#{(year + 1).to_s[-2..]}"
  end

  def sort_lens_label(sort_lens, cap_horizon:)
    case sort_lens
    when "cap_asc" then "Cap #{cap_horizon_label(cap_horizon)} ascending"
    when "name_asc" then "Name A→Z"
    when "name_desc" then "Name Z→A"
    else "Cap #{cap_horizon_label(cap_horizon)} descending"
    end
  end

  def constraint_lens_match_key(constraint_lens, valid_lenses: nil)
    return nil if constraint_lens.to_s == "all"

    valid = valid_lenses || %w[all lock_now options non_guaranteed trade_kicker expiring]
    valid.include?(constraint_lens.to_s) ? constraint_lens.to_s : nil
  end

  def constraint_lens_match_chip_label(constraint_lens, cap_horizon:)
    case constraint_lens.to_s
    when "lock_now" then "Match: Lock now"
    when "options" then "Match: Options ahead"
    when "non_guaranteed" then "Match: Non-Gtd"
    when "trade_kicker" then "Match: Trade kicker"
    when "expiring" then "Match: Expires #{cap_horizon.to_i + 1}"
    end
  end

  def constraint_lens_match_reason(constraint_lens, cap_horizon:)
    case constraint_lens.to_s
    when "lock_now"
      "Lock now posture (TR/NTC/consent required)"
    when "options"
      "Options ahead (PO/TO/ETO)"
    when "non_guaranteed"
      "Non-guaranteed years on file"
    when "trade_kicker"
      "Trade kicker clause on file"
    when "expiring"
      "Cap #{cap_horizon_label(cap_horizon)} > 0 and Cap #{cap_horizon_label(cap_horizon.to_i + 1)} = 0"
    end
  end

  def index_sort_sql(sort_lens, horizon_cap_column:)
    case sort_lens
    when "cap_asc"
      "#{horizon_cap_column} ASC NULLS LAST, sbw.player_name ASC"
    when "name_asc"
      "sbw.player_name ASC"
    when "name_desc"
      "sbw.player_name DESC"
    else
      "#{horizon_cap_column} DESC NULLS LAST, sbw.player_name ASC"
    end
  end

  def build_index_sql_fragments(cap_horizon)
    horizon_cap_column = "sbw.cap_#{cap_horizon}"
    next_horizon_year = cap_horizon + 1
    next_cap_column = "sbw.cap_#{next_horizon_year}"
    next_option_sql = "NULLIF(UPPER(COALESCE(sbw.option_#{next_horizon_year}, '')), 'NONE')"
    next_non_guaranteed_sql = "COALESCE(sbw.is_non_guaranteed_#{next_horizon_year}, false)"

    option_presence_sql = (2026..2030).map do |year|
      "NULLIF(UPPER(COALESCE(sbw.option_#{year}, '')), 'NONE') IS NOT NULL"
    end.join(" OR ")

    non_guaranteed_presence_sql = (2025..2030).map do |year|
      "COALESCE(sbw.is_non_guaranteed_#{year}, false) = true"
    end.join(" OR ")

    lock_now_sql = "(COALESCE(sbw.is_trade_restricted_now, false) = true OR COALESCE(sbw.is_trade_consent_required_now, false) = true OR COALESCE(sbw.is_no_trade, false) = true)"

    expiring_sql = "COALESCE(#{horizon_cap_column}, 0) > 0 AND COALESCE(#{next_cap_column}, 0) = 0"

    {
      horizon_cap_column: horizon_cap_column,
      next_horizon_year: next_horizon_year,
      next_option_sql: next_option_sql,
      next_non_guaranteed_sql: next_non_guaranteed_sql,
      option_presence_sql: option_presence_sql,
      non_guaranteed_presence_sql: non_guaranteed_presence_sql,
      lock_now_sql: lock_now_sql,
      expiring_sql: expiring_sql
    }
  end

  def build_index_where_clauses(query:, team_lens:, status_lens:, constraint_lens:, fragments:, conn:)
    where_clauses = []

    if query.present?
      if query.match?(/\A\d+\z/)
        where_clauses << "sbw.player_id = #{conn.quote(query.to_i)}"
      else
        where_clauses << "sbw.player_name ILIKE #{conn.quote("%#{query}%")}"
      end
    end

    case team_lens
    when "FA"
      where_clauses << "NULLIF(TRIM(COALESCE(sbw.team_code, '')), '') IS NULL"
    when /\A[A-Z]{3}\z/
      where_clauses << "sbw.team_code = #{conn.quote(team_lens)}"
    end

    case status_lens
    when "two_way"
      where_clauses << "COALESCE(sbw.is_two_way, false) = true"
    when "restricted"
      where_clauses << "COALESCE(sbw.is_trade_restricted_now, false) = true"
    when "no_trade"
      where_clauses << "COALESCE(sbw.is_no_trade, false) = true"
    end

    case constraint_lens
    when "lock_now"
      where_clauses << fragments[:lock_now_sql]
    when "options"
      where_clauses << "(#{fragments[:option_presence_sql]})"
    when "non_guaranteed"
      where_clauses << "(#{fragments[:non_guaranteed_presence_sql]})"
    when "trade_kicker"
      where_clauses << "COALESCE(sbw.is_trade_bonus, false) = true"
    when "expiring"
      where_clauses << "(#{fragments[:expiring_sql]})"
    end

    where_clauses.any? ? where_clauses.join(" AND ") : "1 = 1"
  end

  def build_urgency_lanes(rows:, urgency_lens:, urgency_order:, urgency_definitions:, lane_row_limit: nil)
    grouped_rows = Hash.new { |hash, key| hash[key] = [] }
    Array(rows).each do |row|
      grouped_rows[row["urgency_key"].to_s.presence || "stable"] << row
    end

    lane_order = urgency_lens == "all" ? urgency_order : [urgency_lens]

    lane_order.filter_map do |urgency_key|
      lane_rows = Array(grouped_rows[urgency_key])
      next if lane_rows.blank?

      lane_rows = lane_rows.first(lane_row_limit) if lane_row_limit.present?
      definition = urgency_definitions.fetch(urgency_key.to_s)

      {
        key: urgency_key,
        title: definition[:title],
        subtitle: definition[:subtitle],
        row_count: lane_rows.size,
        team_count: lane_rows.map { |row| row["team_code"].presence }.compact.uniq.size,
        cap_lens_total: lane_rows.sum { |row| row["cap_lens_value"].to_f },
        cap_next_total: lane_rows.sum { |row| row["cap_next_value"].to_f },
        total_salary_total: lane_rows.sum { |row| row["total_salary_from_2025"].to_f },
        rows: lane_rows
      }
    end
  end
end
