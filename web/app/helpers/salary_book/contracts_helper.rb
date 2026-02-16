module SalaryBook
  module ContractsHelper
    # Get salary for a specific year
    def player_salary(player, year)
      player["cap_#{year}"]
    end

    # Get cap hold for a specific year (parallel to salary columns)
    def player_cap_hold(player, year)
      player["cap_hold_#{year}"]
    end

    # Normalize option values coming from `pcms.salary_book_warehouse`.
    #
    # Observed values:
    # - "NONE" / "" / nil
    # - "TEAM" (team option)
    # - "PLYR" (player option)
    # - "PLYTF" (early termination option)
    def normalize_contract_option(value)
      return nil if value.nil?

      v = value.to_s.strip.upcase
      return nil if v.blank? || v == "NONE"

      return "TO" if v == "TEAM" || v == "TO"
      return "PO" if v == "PLYR" || v == "PO"
      return "ETO" if v == "PLYTF" || v == "ETO"

      # Unknown value: hide rather than rendering arbitrary text.
      nil
    end

    # Get option for a specific year (PO, TO, ETO, or nil)
    def player_option(player, year)
      normalize_contract_option(player["option_#{year}"])
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
        :gtd # Default to guaranteed if no flags set
      end
    end

    # Determine if year is the current season
    def current_season?(year)
      year == SalaryBookHelper::SALARY_YEARS.first
    end

    # Years of service (YOS) helpers
    def years_of_service_for_year(player, year)
      base = player["years_of_service"]
      return nil if base.nil?

      base.to_i + (year.to_i - SalaryBookHelper::SALARY_YEARS.first)
    end

    def max_pct_for_years_of_service(yos)
      return nil if yos.nil?

      y = yos.to_i
      return 0.25 if y <= 6
      return 0.30 if y <= 9

      0.35
    end

    # Returns true/false/nil (nil = unknown) for whether a trade bonus has room to apply.
    #
    # If a player's salary is already at/over their max-salary threshold, the trade kicker
    # effectively can't increase their outgoing salary.
    def trade_bonus_has_room?(player, year)
      return nil unless player["is_trade_bonus"]

      pct_cap_raw = player["pct_cap_#{year}"]
      pct_cap = pct_cap_raw&.to_f
      return nil if pct_cap.nil? || pct_cap <= 0

      salary_raw = player_salary(player, year)
      salary = salary_raw&.to_f
      return nil if salary.nil? || salary <= 0

      yos_this_year = years_of_service_for_year(player, year)
      return nil if yos_this_year.nil?

      yos_max_pct = max_pct_for_years_of_service(yos_this_year)
      return nil if yos_max_pct.nil?

      # Derive implied cap for this year from salary + pct_cap.
      cap_this_year = salary / pct_cap
      return nil unless cap_this_year.finite? && cap_this_year > 0

      # 105% fallback (uses prior year's salary if available in the horizon)
      prior_salary = player_salary(player, year.to_i - 1)
      fallback_pct = if prior_salary.present?
        (1.05 * prior_salary.to_f) / cap_this_year
      end

      max_allowed_pct = [yos_max_pct, (fallback_pct || 0)].max

      pct_cap < max_allowed_pct
    end

    # Poison Pill only meaningfully applies in the current season and only for 2–3 YOS players.
    # (Warehouse flag can be historically true even when it's no longer relevant.)
    def poison_pill_now?(player, year)
      return false unless current_season?(year)
      return false unless player["is_poison_pill"]

      yos = years_of_service_for_year(player, year)
      return false if yos.nil?

      y = yos.to_i
      y == 2 || y == 3
    end

    # Current-season trade restrictions used by Two-Way badges and salary-cell overrides.
    def trade_restricted_now?(player, year = SalaryBookHelper::SALARY_YEARS.first)
      return false unless current_season?(year)

      player["is_trade_consent_required_now"] ||
        player["is_trade_restricted_now"] ||
        poison_pill_now?(player, year)
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

      # Trade bonus styling
      if player["is_trade_bonus"] && bg_class.blank?
        has_room = trade_bonus_has_room?(player, year)

        if has_room == false
          # Trade bonus exists, but salary is already at/over max threshold → show orange text only.
          text_class = "text-orange-700 dark:text-orange-300"
        else
          # Unknown or has room → show orange background.
          bg_class = "bg-orange-100/60 dark:bg-orange-900/30"
          text_class = "text-orange-700 dark:text-orange-300"
        end
      end

      # No-Trade Clause
      if player["is_no_trade"] && (option.blank? || is_current)
        bg_class = "bg-red-100/60 dark:bg-red-900/30"
        text_class = "text-red-700 dark:text-red-300"
      end

      # Current-season trade restrictions (override all other coloring)
      if trade_restricted_now?(player, year)
        bg_class = "bg-red-100/60 dark:bg-red-900/30"
        text_class = "text-red-700 dark:text-red-300"
      end

      "#{bg_class} #{text_class}".strip
    end

    # Text color classes used by the salary value (e.g. option/restriction states).
    def salary_cell_text_class(player, year)
      salary_cell_classes(player, year)
        .to_s
        .split
        .select { |token| token.start_with?("text-", "dark:text-") }
        .join(" ")
        .presence
    end

    # Build tooltip text for salary cell
    def salary_cell_tooltip(player, year)
      return nil if player_salary(player, year).nil?

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
        tooltips << "Poison Pill" if poison_pill_now?(player, year)
      end

      tooltips.join("\n").presence
    end

    # Calculate total salary across years
    def player_total_salary(player)
      SalaryBookHelper::SALARY_YEARS.sum { |year| player_salary(player, year).to_f }
    end

    # Get age display (e.g., "26.5 YRS")
    def player_age_display(player)
      age = player["age"]
      return nil if age.nil?

      "#{format("%.1f", age.to_f)} YRS"
    end

    # Get years-of-service display (e.g., "7 YOS" / "Rookie")
    def player_years_of_service_display(player)
      raw = player["years_of_service"]
      return nil if raw.nil? || raw.to_s.strip.empty?

      yos = raw.to_i
      yos <= 0 ? "Rookie" : "#{yos} YOS"
    end

    # Combined age + YOS metadata display used in Salary Book rows/sidebar.
    def player_age_yos_display(player, separator: " · ")
      [player_age_display(player), player_years_of_service_display(player)].compact.join(separator).presence
    end
  end
end
