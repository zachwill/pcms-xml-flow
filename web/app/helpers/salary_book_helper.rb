module SalaryBookHelper
  SALARY_YEARS = (2025..2030).to_a.freeze
  SUBSECTION_YEARS = (2025..2029).to_a.freeze  # Sub-sections only show 5 years

  # Format year as "YY-YY" label (e.g., 2025 → "25-26")
  def format_year_label(year)
    start_year = year.to_s[-2..]
    end_year = (year + 1).to_s[-2..]
    "#{start_year}-#{end_year}"
  end

  # Format salary as compact string (e.g., $25.3M, $4.8M, $500K)
  def format_salary(amount)
    return "—" if amount.nil?

    amount = amount.to_f
    return "$0K" if amount == 0

    millions = amount / 1_000_000
    return "$#{format("%.1f", millions)}M" if millions >= 1

    thousands = amount / 1_000
    "$#{thousands.round}K"
  end

  # Format salary even more compactly for KPI cells (e.g., 25.3M, 4.8M, 500K)
  def format_compact_currency(amount)
    return "—" if amount.nil?

    amount = amount.to_f
    return "—" if amount == 0

    millions = amount / 1_000_000
    return "#{format("%.1f", millions)}M" if millions >= 1

    thousands = amount / 1_000
    "#{thousands.round}K"
  end

  # Get salary for a specific year
  def player_salary(player, year)
    player["cap_#{year}"]
  end

  # Get option for a specific year (PO, TO, ETO, or nil)
  def player_option(player, year)
    player["option_#{year}"]
  end

  # Get guarantee type for a specific year
  def player_guarantee_type(player, year)
    if player["is_fully_guaranteed_#{year}"]
      :gtd
    elsif player["is_partially_guaranteed_#{year}"]
      :partial
    elsif player["is_non_guaranteed_#{year}"]
      :non_gtd
    else
      :gtd  # Default to guaranteed if no flags set
    end
  end

  # Determine if year is the current season
  def current_season?(year)
    year == SALARY_YEARS.first
  end

  # Get CSS classes for a salary cell based on guarantee/option/trade status
  def salary_cell_classes(player, year)
    salary = player_salary(player, year)
    return "" if salary.nil?

    option = player_option(player, year)
    guarantee = player_guarantee_type(player, year)
    is_current = current_season?(year)

    bg_class = ""
    text_class = ""

    # Guarantee colors (base layer)
    case guarantee
    when :non_gtd
      bg_class = "bg-yellow-100/60 dark:bg-yellow-900/30"
      text_class = "text-yellow-700 dark:text-yellow-300"
    end

    # Option colors (override guarantee if present, except current season)
    if option.present? && !is_current
      case option
      when "PO"
        bg_class = "bg-blue-100/60 dark:bg-blue-900/30"
        text_class = "text-blue-700 dark:text-blue-300"
      when "TO"
        bg_class = "bg-purple-100/60 dark:bg-purple-900/30"
        text_class = "text-purple-700 dark:text-purple-300"
      when "ETO"
        bg_class = "bg-orange-100/60 dark:bg-orange-900/30"
        text_class = "text-orange-700 dark:text-orange-300"
      end
    end

    # Trade bonus styling (if no option override)
    if player["is_trade_bonus"] && bg_class.blank?
      bg_class = "bg-orange-100/60 dark:bg-orange-900/30"
      text_class = "text-orange-700 dark:text-orange-300"
    end

    # No-Trade Clause
    if player["is_no_trade"] && (option.blank? || is_current)
      bg_class = "bg-red-100/60 dark:bg-red-900/30"
      text_class = "text-red-700 dark:text-red-300"
    end

    # Current-season trade restrictions (override all other coloring)
    if is_current
      if player["is_trade_consent_required_now"] || player["is_trade_restricted_now"] || player["is_poison_pill"]
        bg_class = "bg-red-100/60 dark:bg-red-900/30"
        text_class = "text-red-700 dark:text-red-300"
      end
    end

    "#{bg_class} #{text_class}".strip
  end

  # Build tooltip text for salary cell
  def salary_cell_tooltip(player, year)
    tooltips = []

    guarantee = player_guarantee_type(player, year)
    option = player_option(player, year)
    is_current = current_season?(year)

    # Guarantee tooltip
    case guarantee
    when :gtd
      tooltips << "Fully Guaranteed" if option.blank? || is_current
    when :partial
      tooltips << "Partially Guaranteed"
    when :non_gtd
      tooltips << "Non-Guaranteed"
    end

    # Option tooltip
    if option.present? && !is_current
      case option
      when "PO"
        tooltips << "Player Option"
      when "TO"
        tooltips << "Team Option"
      when "ETO"
        tooltips << "Early Termination Option"
      end
    end

    # Trade bonus
    if player["is_trade_bonus"]
      pct = player["trade_bonus_percent"]
      if pct.present? && pct.to_f > 0
        tooltips << "#{pct.to_f % 1 == 0 ? pct.to_i : pct}% Trade Kicker"
      else
        tooltips << "Trade Kicker"
      end
    end

    # No-Trade
    tooltips << "No-Trade Clause" if player["is_no_trade"]

    # Current season restrictions
    if is_current
      tooltips << "Player Consent Required" if player["is_trade_consent_required_now"]
      tooltips << "Trade Restricted" if player["is_trade_restricted_now"]
      tooltips << "Poison Pill" if player["is_poison_pill"]
    end

    tooltips.join("\n").presence
  end

  # Format percent of cap with optional blocks for percentile
  def format_pct_cap(player, year)
    return nil if player["is_min_contract"]

    pct = player["pct_cap_#{year}"]
    return nil if pct.nil? || pct.to_f <= 0

    pct_value = (pct.to_f * 100).round(1)
    "#{pct_value}%"
  end

  # Calculate total salary across years
  def player_total_salary(player)
    SALARY_YEARS.sum { |year| player_salary(player, year).to_f }
  end

  # Get age display (e.g., "26.5 YRS")
  def player_age_display(player)
    age = player["age"]
    return nil if age.nil?

    "#{format("%.1f", age.to_f)} YRS"
  end

  # NBA CDN headshot URL
  def player_headshot_url(player_id)
    "https://cdn.nba.com/headshots/nba/latest/1040x760/#{player_id}.png"
  end

  # Fallback headshot SVG (data URI)
  def fallback_headshot_data_uri
    "data:image/svg+xml;utf8," \
      "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>" \
      "<rect width='100%25' height='100%25' fill='%23e5e7eb'/>" \
      "<text x='50%25' y='52%25' dominant-baseline='middle' text-anchor='middle' " \
      "fill='%239ca3af' font-family='ui-sans-serif,system-ui' font-size='10'>" \
      "NBA" \
      "</text>" \
      "</svg>"
  end

  # -------------------------------------------------------------------------
  # Exception helpers
  # -------------------------------------------------------------------------

  EXCEPTION_LABEL_MAP = {
    "BIEXC" => "Bi-Annual",
    "BAE" => "Bi-Annual",
    "MLE" => "MLE",
    "TAXMLE" => "Tax MLE",
    "ROOMMLE" => "Room MLE",
    "RMEXC" => "Room MLE",
    "NTMLE" => "MLE",
    "NTMDL" => "MLE",
    "CNTMD" => "C-MLE"
  }.freeze

  def exception_label(row)
    # Use player last name if it's a trade exception
    player_name = row["trade_exception_player_name"]
    if player_name.present?
      last_name = extract_last_name(player_name)
      return last_name if last_name.present?
    end

    raw_type = row["exception_type_lk"] || row["exception_type_name"]
    return "Exception" unless raw_type

    normalized = raw_type.gsub(/[\s\-_]/, "").upcase
    EXCEPTION_LABEL_MAP[normalized] || raw_type
  end

  def exception_primary_amount(row)
    SUBSECTION_YEARS.each do |year|
      amt = row["remaining_#{year}"]
      return amt.to_f if amt.present? && amt.to_f > 0
    end
    nil
  end

  def exception_title(row)
    parts = []
    if disabled_player_exception?(row)
      parts << "DPE"
      parts << row["trade_exception_player_name"] if row["trade_exception_player_name"].present?
    else
      parts << (row["exception_type_name"] || row["exception_type_lk"] || "Exception")
    end

    if row["expiration_date"].present?
      formatted = format_date_short(row["expiration_date"])
      parts << "Expires #{formatted}" if formatted
    end

    parts.join(" • ")
  end

  def disabled_player_exception?(row)
    raw = row["exception_type_lk"] || row["exception_type_name"] || ""
    normalized = raw.gsub(/[\s\-_]/, "").upcase
    normalized.include?("DPE") || normalized.include?("DLEXC") || normalized.include?("DISABLEDPLAYER")
  end

  # -------------------------------------------------------------------------
  # Draft pick helpers
  # -------------------------------------------------------------------------

  def pick_round_label(round)
    round == 1 ? "FRP" : "SRP"
  end

  def pick_status(pick)
    desc = pick["description"]&.downcase || ""

    return "Frozen" if desc.include?("frozen")
    return "Swap" if pick["is_swap"]
    return "Conditional" if pick["is_conditional"] || desc.include?("conditional")

    pick_round_label(pick["round"])
  end

  def pick_label(pick)
    status = pick_status(pick)
    if status == "FRP" || status == "SRP"
      "#{(pick['year'].to_i + 1) % 100} #{status}"
    else
      status
    end
  end

  def pick_value(pick)
    return "To #{pick['origin_team_code']}" if pick["asset_type"] == "TO"
    return "Own" if pick["origin_team_code"] == pick["team_code"] || pick["origin_team_code"].blank?

    pick["origin_team_code"]
  end

  def pick_title(pick)
    round_label = pick["round"] == 1 ? "1st Round" : "2nd Round"
    parts = ["#{pick['year']} #{round_label} pick"]
    parts << "from #{pick['origin_team_code']}" if pick["origin_team_code"].present?
    parts << "(Swap)" if pick["is_swap"]
    parts.join(" ")
  end

  def pick_card_classes(pick)
    desc = pick["description"]&.downcase || ""

    if desc.include?("frozen")
      { bg: "subsection-pick--frozen", round: nil }
    elsif pick["round"] == 1
      { bg: "subsection-pick--frp", round: 1 }
    else
      { bg: "subsection-pick--srp", round: 2 }
    end
  end

  # -------------------------------------------------------------------------
  # Shared helpers
  # -------------------------------------------------------------------------

  def extract_last_name(name)
    return nil unless name.present?

    trimmed = name.strip
    return nil if trimmed.empty?

    if trimmed.include?(",")
      trimmed.split(",").first&.strip
    else
      parts = trimmed.split(/\s+/).reject(&:empty?)
      parts.last
    end
  end

  def format_date_short(value)
    return nil unless value.present?

    parsed = value.is_a?(Date) ? value : Date.parse(value.to_s)
    parsed.strftime("%b %d, %Y")
  rescue ArgumentError
    value.to_s
  end

  def cap_hold_amount(row, year)
    row["cap_#{year}"]
  end

  def dead_money_amount(row, year)
    row["cap_#{year}"]
  end

  # -------------------------------------------------------------------------
  # Team Header KPI helpers
  # -------------------------------------------------------------------------

  # Format room amounts with +/- sign (e.g., +5.2M, -3.8M)
  def format_room_amount(value)
    return "—" if value.nil?

    amount = value.to_f
    sign = amount >= 0 ? "+" : ""
    "#{sign}#{format_compact_currency(amount)}"
  end

  # NBA CDN team logo URL (uses 10-digit team_id)
  def team_logo_url(team_id)
    return nil if team_id.nil?

    "https://cdn.nba.com/logos/nba/#{team_id}/primary/L/logo.svg"
  end

  # Determine KPI variant based on value sign
  def kpi_variant(value)
    return "muted" if value.nil?

    value.to_f >= 0 ? "positive" : "negative"
  end

  # Get tax/apron status for a year
  def tax_status(summary)
    return { label: "—", value: "—", variant: "muted" } if summary.nil?

    room_tax = summary["room_under_tax"]&.to_f
    room_a1 = summary["room_under_first_apron"]&.to_f
    room_a2 = summary["room_under_second_apron"]&.to_f

    # Check apron levels first (most restrictive)
    if room_a2.present? && room_a2 < 0
      return { label: "Apron 2", value: format_room_amount(room_a2), variant: "negative" }
    end

    if room_a1.present? && room_a1 < 0
      return { label: "Apron 1", value: format_room_amount(room_a1), variant: "negative" }
    end

    if room_tax.present? && room_tax < 0
      return { label: "Tax", value: format_room_amount(room_tax), variant: "negative" }
    end

    { label: "Under Tax", value: format_room_amount(room_tax), variant: "positive" }
  end

  # Get color class for "room under" values:
  # - Green if under by $10M+
  # - Neutral (no color) if under by less than $10M
  # - Red if negative (over)
  def room_under_color_class(value)
    return "" if value.nil?

    val = value.to_f
    if val < 0
      "sidebar-stat-value--negative"
    elsif val >= 10_000_000
      "sidebar-stat-value--positive"
    else
      "" # neutral
    end
  end
end
