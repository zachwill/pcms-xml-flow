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
end
