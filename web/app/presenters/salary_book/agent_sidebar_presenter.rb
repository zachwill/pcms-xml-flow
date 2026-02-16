module SalaryBook
  class AgentSidebarPresenter
    def initialize(agent:, rollup:, helpers:, salary_years: SalaryBookHelper::SALARY_YEARS)
      @agent = agent
      @rollup = rollup || {}
      @helpers = helpers
      @salary_years = salary_years
    end

    def state
      @state ||= begin
        {
          salary_years: salary_years,
          compact: ->(value) { helpers.format_salary(value) },
          agent_id: agent["agent_id"],
          agent_name: agent["name"],
          agency_name: agent["agency_name"],
          initials: helpers.agent_initials(agent["name"]),
          total_count: rollup_int("total_count"),
          standard_count: rollup_int("standard_count"),
          two_way_count: rollup_int("two_way_count"),
          team_count: rollup_int("team_count"),
          book_2025: rollup_int("book_2025"),
          book_2026: rollup_int("book_2026"),
          book_2027: rollup_int("book_2027"),
          rookie_scale_count: rollup_int("rookie_scale_count"),
          min_contract_count: rollup_int("min_contract_count"),
          max_contract_count: rollup_int("max_contract_count"),
          no_trade_count: rollup_int("no_trade_count"),
          trade_kicker_count: rollup_int("trade_kicker_count"),
          trade_restricted_count: rollup_int("trade_restricted_count"),
          expiring_2025: rollup_int("expiring_2025"),
          total_expiring: rollup_int("expiring_2025"),
          player_option_count: rollup_int("player_option_count"),
          team_option_count: rollup_int("team_option_count"),
          prior_year_nba_now_free_agent_count: rollup_int("prior_year_nba_now_free_agent_count"),
          book_2025_percentile: rollup["cap_2025_total_percentile"],
          book_2026_percentile: rollup["cap_2026_total_percentile"],
          book_2027_percentile: rollup["cap_2027_total_percentile"],
          client_count_percentile: rollup["client_count_percentile"],
          team_count_percentile: rollup["team_count_percentile"],
          standard_count_percentile: rollup["standard_count_percentile"],
          two_way_count_percentile: rollup["two_way_count_percentile"],
          has_options: rollup_int("player_option_count") > 0 || rollup_int("team_option_count") > 0,
          has_restrictions: rollup_int("no_trade_count") > 0 || rollup_int("trade_kicker_count") > 0 || rollup_int("trade_restricted_count") > 0,
          has_prior_year_now_fa: rollup_int("prior_year_nba_now_free_agent_count") > 0
        }
      end
    end

    def client_row_name(client)
      last = client["display_last_name"].to_s.strip
      first = client["display_first_name"].to_s.strip

      return "#{last}, #{first}" if last.present? && first.present?
      return last if last.present?
      return first if first.present?

      client["player_name"].to_s
    end

    # Next contract inflection marker shown in the row meta line.
    # Priority rules:
    # 1) Earliest year wins
    # 2) For the same year: option > non-guaranteed > free agency
    def next_contract_marker(client)
      return nil if client["is_two_way"]

      markers = []

      salary_years.drop(1).each do |year|
        option = helpers.normalize_contract_option(client["option_#{year}"])
        if option.present?
          option_classes = case option
          when "PO"
            "text-blue-600 dark:text-blue-400"
          when "TO"
            "text-purple-600 dark:text-purple-400"
          when "ETO"
            "text-orange-600 dark:text-orange-400"
          end

          if option_classes.present?
            markers << {
              year: year,
              priority: 1,
              label: "#{option} #{short_year(year)}",
              classes: option_classes
            }
          end
        end

        if client["is_non_guaranteed_#{year}"] && client["cap_#{year}"].to_f > 0
          markers << {
            year: year,
            priority: 2,
            label: "NG #{short_year(year)}",
            classes: "text-amber-600 dark:text-amber-400"
          }
        end
      end

      salary_years.each_cons(2) do |year, next_year|
        next unless client["cap_#{year}"].to_f > 0 && client["cap_#{next_year}"].to_f == 0

        markers << {
          year: next_year,
          priority: 3,
          label: "FA #{short_year(next_year)}",
          classes: (next_year == salary_years[1] ? "text-red-600 dark:text-red-400" : "text-muted-foreground")
        }
        break
      end

      markers.min_by { |marker| [marker[:year], marker[:priority]] }
    end

    def total_contract_value(client)
      salary_years.sum { |year| client["cap_#{year}"].to_f }
    end

    private

    attr_reader :agent, :rollup, :helpers, :salary_years

    def rollup_int(key)
      rollup[key].to_i
    end

    def short_year(year)
      year.to_i.to_s[-2..]
    end
  end
end
