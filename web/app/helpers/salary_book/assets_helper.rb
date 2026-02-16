module SalaryBook
  module AssetsHelper
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
      SalaryBookHelper::SALARY_YEARS.each do |year|
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
        "#{pick['year'].to_i % 100} #{status}"
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

    def cap_hold_amount(row, year)
      row["cap_#{year}"]
    end

    def dead_money_amount(row, year)
      row["cap_#{year}"]
    end

    # Coerce warehouse booleans (true/false, t/f, 1/0) into a Ruby boolean.
    def warehouse_bool(value)
      case value
      when true, 1, "1", "t", "T", "true", "TRUE", "yes", "YES", "y", "Y"
        true
      else
        false
      end
    end

    # Human label for hard-cap status in team header KPIs.
    # Returns: "Apron 1", "Apron 2", "None", or "—" (no snapshot)
    def hard_cap_label(summary)
      return "—" if summary.blank?

      raw_level = (summary["apron_level_lk"] || summary[:apron_level_lk]).to_s.strip
      normalized_level = raw_level.upcase
      is_subject_to_apron = warehouse_bool(summary["is_subject_to_apron"] || summary[:is_subject_to_apron] || summary["is_over_first_apron"] || summary[:is_over_first_apron])

      return "Apron 2" if normalized_level.include?("2") || normalized_level.include?("SECOND")
      return "Apron 1" if normalized_level.include?("1") || normalized_level.include?("FIRST")
      return "Apron 1" if is_subject_to_apron
      return "None" if normalized_level.blank? || normalized_level == "NONE"

      raw_level
    end

    # Returns the active hard-cap room metric for the team/year snapshot.
    # Apron 1 hard-cap -> room_under_first_apron
    # Apron 2 hard-cap -> room_under_second_apron
    # None/unknown -> nil
    def hard_cap_room(summary)
      return nil if summary.blank?

      case hard_cap_label(summary)
      when "Apron 1"
        summary["room_under_first_apron"] || summary[:room_under_first_apron]
      when "Apron 2"
        summary["room_under_second_apron"] || summary[:room_under_second_apron]
      else
        nil
      end
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

    # Get initials from agent name (e.g., "Rich Paul" → "RP")
    def agent_initials(name)
      return "??" unless name.present?

      name.split(/\s+/)
          .map { |word| word[0] }
          .join
          .upcase
          .slice(0, 2)
    end
  end
end
