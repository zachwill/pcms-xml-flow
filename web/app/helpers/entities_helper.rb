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

  # Use numeric fallback when a team_id is present (handles non-NBA team codes safely).
  def safe_team_href(team_code:, team_id:)
    if team_id.present?
      return entity_href(entity_type: "team", entity_id: team_id)
    end

    team_href(team_code: team_code)
  end
end
