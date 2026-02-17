module SalaryBook
  class PlayerSidebarPresenter
    TEAM_COMBO_CHIP_CLASSES = "cursor-pointer inline-flex items-center gap-0.5 px-1.5 rounded border border-border bg-background hover:border-foreground/20".freeze
    TEAM_COMBO_CHIP_STYLE = "width: 78px; height: 24px;".freeze
    TEAM_COMBO_LOGO_WRAP_CLASSES = "inline-flex items-center justify-center w-4 h-4 overflow-hidden rounded-[3px] bg-muted/20".freeze
    TEAM_COMBO_LOGO_IMAGE_CLASSES = "w-full h-full object-cover object-center scale-[1.12]".freeze
    TEAM_COMBO_CODE_CLASSES = "flex-1 text-xs font-semibold tabular-nums leading-none text-center".freeze

    def initialize(player:, helpers:, salary_years: SalaryBookHelper::SALARY_YEARS)
      @player = player
      @helpers = helpers
      @salary_years = salary_years
    end

    def state
      @state ||= begin
        team_code = player["team_code"].presence || "—"
        team_id = player["team_id"]
        team_name = player["team_name"].presence || team_code
        team_switchable = team_code.match?(/\A[A-Z]{3}\z/)
        is_two_way = player["is_two_way"]

        years_data = salary_years.map { |year| year_row(year) }
        active_years = years_data.select { |row| row[:salary].present? && row[:salary].to_f > 0 }

        next_option = resolve_next_option
        fa_year = resolve_fa_year(is_two_way: is_two_way)
        next_decision_variant = resolve_next_decision_variant(next_option:, fa_year:, is_two_way:)

        epm_percentile = player["epm_percentile"]
        epm_percentile_int_value = helpers.epm_percentile_int(epm_percentile)

        {
          salary_years: salary_years,
          compact: ->(value) { helpers.format_salary(value) },
          player_id: player["player_id"],
          player_name: player["player_name"],
          team_code: team_code,
          team_id: team_id,
          team_name: team_name,
          team_logo: helpers.team_logo_url(team_id),
          agent_name: player["agent_name"],
          agent_id: player["agent_id"],
          age_display: helpers.player_age_display(player),
          years_of_service_display: helpers.player_years_of_service_display(player),
          age_percentile: player["age_percentile"],
          age_color_class: helpers.age_percentile_color_class(player["age_percentile"]),
          is_two_way: is_two_way,
          team_switchable: team_switchable,
          team_combo_chip_classes: TEAM_COMBO_CHIP_CLASSES,
          team_combo_chip_style: TEAM_COMBO_CHIP_STYLE,
          team_combo_logo_wrap_classes: TEAM_COMBO_LOGO_WRAP_CLASSES,
          team_combo_logo_image_classes: TEAM_COMBO_LOGO_IMAGE_CLASSES,
          team_combo_code_classes: TEAM_COMBO_CODE_CLASSES,
          team_row_onclick: team_row_onclick(team_switchable: team_switchable, team_code: team_code),
          years_data: years_data,
          active_years: active_years,
          total_value: active_years.sum { |row| row[:salary].to_f },
          contract_years: active_years.size,
          cap_2025: player["cap_2025"],
          next_option: next_option,
          fa_year: fa_year,
          next_decision_label: resolve_next_decision_label(next_option:, fa_year:, is_two_way:),
          next_decision_variant: next_decision_variant,
          header_contract_label: resolve_header_contract_label(next_option:, fa_year:, is_two_way:),
          header_contract_classes: header_contract_classes(next_decision_variant),
          status_chips: build_status_chips(is_two_way: is_two_way),
          contract_type: player["contract_type_lookup_value"] || player["contract_type_code"],
          signed_using: player["signed_method_lookup_value"],
          exception_type: player["exception_type_lookup_value"],
          epm_value: player["epm_value"],
          epm_percentile: epm_percentile,
          epm_season: player["epm_season"],
          epm_season_label: helpers.format_epm_season_label(player["epm_season"]),
          epm_percentile_int_value: epm_percentile_int_value,
          epm_has_percentile: epm_percentile_int_value.present?,
          epm_badge_class: epm_badge_class(epm_percentile_int_value)
        }
      end
    end

    private

    attr_reader :player, :helpers, :salary_years

    def year_row(year)
      guarantee_status = if player["is_fully_guaranteed_#{year}"]
        "FULL"
      elsif player["is_partially_guaranteed_#{year}"]
        "PARTIAL"
      elsif player["is_non_guaranteed_#{year}"]
        "NONE"
      end

      {
        year: year,
        salary: player["cap_#{year}"],
        option: helpers.normalize_contract_option(player["option_#{year}"]),
        guaranteed_amount: player["guaranteed_amount_#{year}"],
        guarantee_status: guarantee_status,
        likely_bonus: player["likely_bonus_#{year}"],
        unlikely_bonus: player["unlikely_bonus_#{year}"]
      }
    end

    def team_row_onclick(team_switchable:, team_code:)
      return nil unless team_switchable

      "const effectiveyear = String($sidebarcapyearloaded || '#{salary_years.first}'); " \
        "el.dispatchEvent(new CustomEvent('salarybook-switch-team', { bubbles: true, detail: { team: '#{team_code}', year: effectiveyear } }));"
    end

    def resolve_next_option
      salary_years.drop(1).map do |year|
        option = helpers.normalize_contract_option(player["option_#{year}"])
        next nil if option.blank?

        {
          year: year,
          option: option
        }
      end.compact.first
    end

    def resolve_fa_year(is_two_way:)
      return nil if is_two_way

      salary_years.each_cons(2) do |year, next_year|
        if player["cap_#{year}"].to_f > 0 && player["cap_#{next_year}"].to_f == 0
          return year
        end
      end

      nil
    end

    def resolve_next_decision_label(next_option:, fa_year:, is_two_way:)
      if next_option.present?
        "#{next_option[:option]} #{helpers.format_year_label(next_option[:year])}"
      elsif fa_year.present?
        "FA #{helpers.format_year_label(fa_year + 1)}"
      elsif is_two_way
        "Two-Way"
      else
        "—"
      end
    end

    def resolve_next_decision_variant(next_option:, fa_year:, is_two_way:)
      if next_option.present?
        case next_option[:option]
        when "PO" then "option_po"
        when "TO" then "option_to"
        when "ETO" then "option_eto"
        else "muted"
        end
      elsif fa_year.present?
        "default"
      elsif is_two_way
        "muted"
      else
        "muted"
      end
    end

    def resolve_header_contract_label(next_option:, fa_year:, is_two_way:)
      if next_option.present?
        "#{next_option[:option]} #{helpers.format_year_label(next_option[:year])}"
      elsif fa_year.present?
        "FA #{helpers.format_year_label(fa_year + 1)}"
      elsif is_two_way
        "2W"
      end
    end

    def header_contract_classes(next_decision_variant)
      case next_decision_variant
      when "option_po"
        "text-blue-600 dark:text-blue-400"
      when "option_to"
        "text-purple-600 dark:text-purple-400"
      when "option_eto"
        "text-orange-600 dark:text-orange-400"
      else
        "text-muted-foreground"
      end
    end

    def build_status_chips(is_two_way:)
      chips = []
      chips << { label: "Two-Way", classes: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800/60 dark:text-zinc-300" } if is_two_way

      if player["is_min_contract"]
        min_label = player["min_contract_lookup_value"].presence
        chips << {
          label: min_label.present? ? "Min · #{min_label}" : "Minimum",
          classes: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800/60 dark:text-zinc-300"
        }
      end

      chips.concat(active_restrictions)
      chips
    end

    def active_restrictions
      restrictions = [
        { label: trade_kicker_label, active: player["is_trade_bonus"], classes: "bg-orange-100 text-orange-700 dark:bg-orange-900/50 dark:text-orange-300" },
        { label: "No-Trade", active: player["is_no_trade"], classes: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300" },
        { label: "Consent Required", active: player["is_trade_consent_required_now"], classes: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300" },
        { label: "Restricted", active: player["is_trade_restricted_now"], classes: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300" },
        { label: "Poison Pill", active: player["is_poison_pill"], classes: "bg-red-100 text-red-700 dark:bg-red-900/50 dark:text-red-300 italic" },
        { label: "Pre-consented", active: player["is_trade_preconsented"], classes: "bg-green-100 text-green-700 dark:bg-green-900/50 dark:text-green-300" }
      ]

      restrictions.select { |restriction| restriction[:active] }
    end

    def trade_kicker_label
      trade_bonus_percent = player["trade_bonus_percent"]
      return "Trade Kicker" unless trade_bonus_percent.present? && trade_bonus_percent.to_f > 0

      pct = trade_bonus_percent.to_f
      pct_str = pct % 1 == 0 ? pct.to_i.to_s : pct.to_s
      "TK #{pct_str}%"
    end

    def epm_badge_class(epm_percentile_int_value)
      if epm_percentile_int_value.present? && epm_percentile_int_value >= 80
        "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300"
      elsif epm_percentile_int_value.present? && epm_percentile_int_value <= 20
        "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300"
      else
        "bg-muted text-foreground"
      end
    end
  end
end
