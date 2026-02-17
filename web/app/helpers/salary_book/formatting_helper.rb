module SalaryBook
  module FormattingHelper
    # Format year as "YY-YY" label (e.g., 2025 → "25-26")
    def format_year_label(year)
      start_year = year.to_s[-2..]
      end_year = (year + 1).to_s[-2..]
      "#{start_year}-#{end_year}"
    end

    # EPM seasons are end-year keyed (e.g., 2025 means 24-25).
    # Normalize to the app's short season label style: "YY-YY".
    def format_epm_season_label(season)
      return nil if season.nil?

      s = season.to_s.strip
      return nil if s.blank?

      if s.match?(/\A\d{4}\z/)
        end_year = s.to_i
        start_year = end_year - 1
        return "#{start_year.to_s[-2..]}-#{end_year.to_s[-2..]}"
      end

      if (m = s.match(/\A(\d{4})-(\d{2}|\d{4})\z/))
        start_yy = m[1][-2..]
        end_yy = m[2].length == 4 ? m[2][-2..] : m[2]
        return "#{start_yy}-#{end_yy}"
      end

      s
    end

    # Format salary as compact string (e.g., $25.3M, $4.8M, $500K)
    # Also supports signed values (e.g., -$87.7M) for "room" metrics.
    def format_salary(amount)
      return "—" if amount.nil?

      amount = amount.to_f
      return "$0K" if amount == 0

      sign = amount < 0 ? "-" : ""
      abs = amount.abs

      millions = abs / 1_000_000
      return "#{sign}$#{format("%.1f", millions)}M" if millions >= 1

      thousands = abs / 1_000
      "#{sign}$#{thousands.round}K"
    end

    # Compact currency formatter (prototype parity; keeps the "$" prefix).
    def format_compact_currency(amount)
      format_salary(amount)
    end

    # Salary values that compact-format to "$0K" should usually be rendered as em-dash
    # in roster/total contexts ("no salary to be had").
    def salary_amount_present_for_display?(amount)
      return false if amount.nil?

      amount.to_f.abs >= 500
    end

    def format_epm_value(value)
      return "—" if value.nil?

      v = value.to_f
      sign = v.positive? ? "+" : ""
      "#{sign}#{format('%.1f', v)}"
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

    def format_date_short(value)
      return nil unless value.present?

      parsed = value.is_a?(Date) ? value : Date.parse(value.to_s)
      "#{parsed.strftime('%b')} #{parsed.day}, #{parsed.year}"
    rescue ArgumentError
      value.to_s
    end

    # Date formatter for compact table cells:
    # - line 1: "Feb 17, 2026"
    # - line 2: "3 days ago" (or "Today", "in 2 days")
    def format_date_with_days_ago(value, today: Date.current)
      return [nil, nil] unless value.present?

      parsed = value.is_a?(Date) ? value : Date.parse(value.to_s)
      formatted = "#{parsed.strftime('%b')} #{parsed.day}, #{parsed.year}"
      [formatted, days_ago_label(parsed, today: today)]
    rescue ArgumentError
      [value.to_s, nil]
    end

    def days_ago_label(date, today: Date.current)
      delta_days = (today - date).to_i
      return "Today" if delta_days.zero?
      return "1 day ago" if delta_days == 1
      return "#{delta_days} days ago" if delta_days.positive?

      future_days = delta_days.abs
      return "Tomorrow" if future_days == 1

      "in #{future_days} days"
    end

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
  end
end
