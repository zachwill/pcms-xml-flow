module SalaryBookHelper
  SALARY_YEARS = (2025..2030).to_a.freeze

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
end
