module EntitiesHelper
  # Room amount color class (for cap vitals threshold rooms).
  #
  # - Green if positive (under threshold)
  # - Red if negative (over threshold)
  def room_amount_color(value)
    return "" if value.nil?

    val = value.to_f
    if val < 0
      "text-red-600 dark:text-red-400"
    elsif val >= 10_000_000
      "text-emerald-600 dark:text-emerald-400"
    else
      ""
    end
  end

  def format_height_inches(raw_inches)
    return "—" if raw_inches.blank?

    inches = raw_inches.to_i
    feet = inches / 12
    remainder = inches % 12

    "#{feet}'#{remainder}\""
  end

  def format_weight_lbs(raw_weight)
    return "—" if raw_weight.blank?

    "#{raw_weight.to_i} lbs"
  end

  def format_plain_date(value)
    return "—" if value.blank?

    parsed = value.is_a?(Date) ? value : Date.parse(value.to_s)
    parsed.strftime("%b %-d, %Y")
  rescue ArgumentError
    value.to_s
  end

  def yes_no(value)
    return "—" if value.nil?

    value ? "Yes" : "No"
  end

  # Compact tokenization used by trades list + quick deals.
  # Example: 2P + 1K + $2.5M cash + 1 TPE
  def trade_impact_flow_label(impact_row, direction:)
    return "—" if impact_row.blank?

    players = trade_impact_value(impact_row, direction, :players)
    picks = trade_impact_value(impact_row, direction, :picks)
    cash = trade_impact_value(impact_row, direction, :cash)
    tpe = trade_impact_value(impact_row, direction, :tpe)

    tokens = []
    tokens << "#{players}P" if players.positive?
    tokens << "#{picks}K" if picks.positive?
    tokens << "#{format_salary(cash)} cash" if cash.positive?
    tokens << "#{tpe} TPE" if tpe.positive?

    tokens.any? ? tokens.join(" + ") : "—"
  end

  def trade_impact_net_variant(impact_row)
    return :balanced if impact_row.blank?

    outgoing_weight = trade_impact_weight(impact_row, direction: :out)
    incoming_weight = trade_impact_weight(impact_row, direction: :in)

    return :net_in if incoming_weight > outgoing_weight
    return :net_out if outgoing_weight > incoming_weight

    :balanced
  end

  def trade_impact_net_label(impact_row)
    case trade_impact_net_variant(impact_row)
    when :net_in then "Net in"
    when :net_out then "Net out"
    else "Balanced"
    end
  end

  def trade_impact_weight(impact_row, direction:)
    players = trade_impact_value(impact_row, direction, :players)
    picks = trade_impact_value(impact_row, direction, :picks)
    cash = trade_impact_value(impact_row, direction, :cash)
    tpe = trade_impact_value(impact_row, direction, :tpe)

    players + picks + tpe + (cash.positive? ? 1 : 0)
  end

  def trade_impact_value(impact_row, direction, type)
    suffix = direction.to_s == "out" ? "out" : "in"
    key = "#{type}_#{suffix}"

    value = impact_row[key] || impact_row[key.to_sym]
    type == :cash ? value.to_f : value.to_i
  end

  # Use numeric fallback when a team_id is present (handles non-NBA team codes safely).
  def safe_team_href(team_code:, team_id:)
    if team_id.present?
      return entity_href(entity_type: "team", entity_id: team_id)
    end

    team_href(team_code: team_code)
  end

  PLAYER_DECISION_LENS_ORDER = %w[all urgent upcoming later].freeze

  def normalize_player_decision_lens(raw_lens)
    lens = raw_lens.to_s.strip.downcase
    PLAYER_DECISION_LENS_ORDER.include?(lens) ? lens : "all"
  end

  def filter_player_decision_items(decision_items:, lens:)
    normalized_lens = normalize_player_decision_lens(lens)
    items = Array(decision_items)
    return items if normalized_lens == "all"

    items.select { |item| item.dig(:urgency, :key).to_s == normalized_lens }
  end

  def player_decision_lens_rows(decision_items:, active_lens:)
    items = Array(decision_items)
    normalized_active_lens = normalize_player_decision_lens(active_lens)

    PLAYER_DECISION_LENS_ORDER.map do |lens_key|
      count = if lens_key == "all"
        items.size
      else
        items.count { |item| item.dig(:urgency, :key).to_s == lens_key }
      end

      {
        key: lens_key,
        label: lens_key == "all" ? "All" : lens_key.titleize,
        count: count,
        active: normalized_active_lens == lens_key
      }
    end
  end

  # Decision rail model for player entity pages.
  #
  # Outputs dense, link-ready items used by:
  # - /players/:slug main "next decisions" rail
  # - /players/:slug right panel quick rail
  def player_next_decision_items(salary_book_row:, protection_condition_rows:, ledger_entries:, horizon_years: SalaryBookHelper::SALARY_YEARS)
    salary_row = salary_book_row.presence || {}
    years = Array(horizon_years).map(&:to_i).select(&:positive?).uniq.sort
    return [] if years.empty?

    ledger_rows = Array(ledger_entries)
    ledger_by_year = ledger_rows.group_by { |entry| entry["salary_year"].to_i }
    fallback_ledger = ledger_rows.find { |entry| entry["transaction_id"].present? || entry["trade_id"].present? }

    team_code = salary_row["team_code"].to_s.strip.presence
    team_id = salary_row["team_id"].presence

    active_years = years.select { |year| salary_row["cap_#{year}"].to_f.positive? }
    base_year = active_years.first || years.first

    items = []

    years.drop(1).each do |year|
      option = normalize_contract_option(salary_row["option_#{year}"])
      next if option.blank?

      cap_amount = salary_row["cap_#{year}"]
      ledger_ref = decision_ledger_reference(ledger_by_year[year], fallback: fallback_ledger)

      items << {
        key: "option-#{year}-#{option}",
        kind: "option",
        priority: 20,
        year: year,
        season_label: format_year_label(year),
        category_label: option,
        category_variant: "accent",
        urgency: decision_urgency_for_year(year: year, base_year: base_year, kind: "option"),
        headline: "#{option} decision window",
        detail: cap_amount.to_f.positive? ? "#{format_year_label(year)} salary #{format_salary(cap_amount)}" : "#{format_year_label(year)} option season",
        value_label: cap_amount.to_f.positive? ? format_salary(cap_amount) : "—",
        team_code: team_code,
        team_id: team_id,
        transaction_id: ledger_ref&.fetch("transaction_id", nil),
        trade_id: ledger_ref&.fetch("trade_id", nil),
        source_anchor: "contract"
      }
    end

    years.each_cons(2) do |year, next_year|
      current_cap = salary_row["cap_#{year}"].to_f
      next_cap = salary_row["cap_#{next_year}"].to_f
      next unless current_cap.positive? && next_cap.zero?

      ledger_ref = decision_ledger_reference(ledger_by_year[year], fallback: fallback_ledger)

      items << {
        key: "expiry-#{next_year}",
        kind: "expiring",
        priority: 40,
        year: next_year,
        season_label: format_year_label(next_year),
        category_label: "EXP",
        category_variant: "warning",
        urgency: decision_urgency_for_year(year: next_year, base_year: base_year, kind: "expiring"),
        headline: "Potential free-agency branch",
        detail: "Cap drops from #{format_salary(current_cap)} to — entering #{format_year_label(next_year)}",
        value_label: format_salary(current_cap),
        team_code: team_code,
        team_id: team_id,
        transaction_id: ledger_ref&.fetch("transaction_id", nil),
        trade_id: ledger_ref&.fetch("trade_id", nil),
        source_anchor: "contract"
      }

      break
    end

    years.each do |year|
      cap_amount = salary_row["cap_#{year}"].to_f
      next unless cap_amount.positive?

      is_partial = salary_row["is_partially_guaranteed_#{year}"]
      is_non_guaranteed = salary_row["is_non_guaranteed_#{year}"]
      next unless is_partial || is_non_guaranteed

      guaranteed_amount = salary_row["guaranteed_amount_#{year}"]
      ledger_ref = decision_ledger_reference(ledger_by_year[year], fallback: fallback_ledger)

      detail = if is_partial
        "Guaranteed #{format_salary(guaranteed_amount)} of #{format_salary(cap_amount)}"
      else
        "Non-guaranteed season with #{format_salary(cap_amount)} cap exposure"
      end

      items << {
        key: "guarantee-#{year}-#{is_partial ? 'partial' : 'non'}",
        kind: "guarantee",
        priority: 30,
        year: year,
        season_label: format_year_label(year),
        category_label: is_partial ? "PARTIAL" : "NON",
        category_variant: is_partial ? "warning" : "danger",
        urgency: decision_urgency_for_year(year: year, base_year: base_year, kind: "guarantee"),
        headline: is_partial ? "Partial guarantee trigger" : "Non-guaranteed decision",
        detail: detail,
        value_label: is_partial ? format_salary(guaranteed_amount) : format_salary(cap_amount),
        team_code: team_code,
        team_id: team_id,
        transaction_id: ledger_ref&.fetch("transaction_id", nil),
        trade_id: ledger_ref&.fetch("trade_id", nil),
        source_anchor: "guarantees"
      }
    end

    Array(protection_condition_rows).each do |row|
      year = row["salary_year"].to_i
      next unless year.positive?

      clause_label = row["clause_name"].presence || row["criteria_description"].presence || "Guarantee condition"
      earned_text = format_plain_date(row["earned_date"]) if row["earned_date"].present?
      trigger_type = row["earned_type_lk"].presence
      detail_tokens = []
      detail_tokens << "Trigger #{earned_text}" if earned_text.present?
      detail_tokens << trigger_type if trigger_type.present?

      ledger_ref = decision_ledger_reference(ledger_by_year[year], fallback: fallback_ledger)

      items << {
        key: "condition-#{row['condition_id'] || "row"}-#{year}",
        kind: "guarantee",
        priority: 10,
        year: year,
        season_label: format_year_label(year),
        category_label: "TRIGGER",
        category_variant: "danger",
        urgency: decision_urgency_for_year(year: year, base_year: base_year, kind: "guarantee"),
        headline: clause_label,
        detail: detail_tokens.presence&.join(" · ") || "Guarantee condition on file",
        value_label: format_salary(row["amount"]),
        team_code: team_code,
        team_id: team_id,
        transaction_id: ledger_ref&.fetch("transaction_id", nil),
        trade_id: ledger_ref&.fetch("trade_id", nil),
        source_anchor: "guarantees"
      }
    end

    items
      .group_by { |item| item[:key] }
      .values
      .map(&:first)
      .sort_by { |item| [item[:year].to_i, item[:priority].to_i, item[:headline].to_s] }
      .first(18)
  end

  private

  def decision_ledger_reference(candidates, fallback:)
    Array(candidates).find { |entry| entry["transaction_id"].present? || entry["trade_id"].present? } || fallback
  end

  def decision_urgency_for_year(year:, base_year:, kind:)
    distance = year.to_i - base_year.to_i
    lens_key = if distance <= 1
      "urgent"
    elsif distance == 2
      "upcoming"
    else
      "later"
    end

    if distance <= 1
      if kind.to_s == "option"
        return { key: lens_key, label: "Next", variant: "warning" }
      end

      return { key: lens_key, label: "Urgent", variant: "danger" }
    end

    if distance == 2
      return { key: lens_key, label: "Upcoming", variant: "accent" }
    end

    { key: lens_key, label: "Later", variant: "muted" }
  end
end
