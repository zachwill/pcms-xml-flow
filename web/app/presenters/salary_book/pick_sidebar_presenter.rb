module SalaryBook
  class PickSidebarPresenter
    TEAM_COMBO_CHIP_CLASSES = "cursor-pointer inline-flex items-center gap-0.5 px-1.5 rounded border border-border bg-background hover:border-foreground/20".freeze
    TEAM_COMBO_CHIP_STYLE = "width: 78px; height: 24px;".freeze
    TEAM_COMBO_LOGO_WRAP_CLASSES = "inline-flex items-center justify-center w-4 h-4 overflow-hidden rounded-[3px] bg-muted/20".freeze
    TEAM_COMBO_LOGO_IMAGE_CLASSES = "w-full h-full object-cover object-center scale-[1.12]".freeze
    TEAM_COMBO_CODE_CLASSES = "flex-1 text-xs font-semibold tabular-nums leading-none text-center".freeze

    def initialize(team_code:, year:, round:, salary_year:, picks:, team_meta:, team_meta_by_code:, helpers:)
      @team_code = team_code.to_s.strip.upcase
      @year = year.to_i
      @round = round.to_i
      @salary_year = salary_year.to_i
      @picks = Array(picks)
      @team_meta = team_meta || {}
      @team_meta_by_code = team_meta_by_code || {}
      @helpers = helpers
    end

    def state
      @state ||= begin
        primary = picks.first || {}
        asset_type = primary["asset_type"].to_s.upcase

        origin_codes = resolve_origin_codes
        via_codes = resolve_via_codes
        is_own = origin_codes.empty? && asset_type != "TO"

        trade_history = resolve_trade_history
        status_badge = resolve_status_badge(asset_type: asset_type, is_own: is_own)
        flow_label = asset_type == "TO" ? "To" : "From"

        {
          round_i: round,
          salary_book_year: salary_year,
          team_name: team_meta["team_name"] || team_code,
          team_id: team_meta["team_id"],
          logo_url: helpers.team_logo_url(team_meta["team_id"]),
          is_swap: picks.any? { |pick| pick["is_swap"] || pick["endnote_is_swap"] },
          is_conditional: picks.any? { |pick| pick["is_conditional"] || pick["endnote_is_conditional"] },
          origin_codes: origin_codes,
          via_codes: via_codes,
          is_own: is_own,
          descriptions: picks.map { |pick| pick["description"].to_s.strip }.reject(&:blank?).uniq,
          explanations: picks.map { |pick| pick["endnote_explanation"].to_s.strip }.reject(&:blank?).uniq,
          trade_date_count: trade_history.fetch(:count),
          latest_trade_date_label: trade_history.fetch(:latest_label),
          trade_history_summary: trade_history.fetch(:summary),
          trade_history_title: trade_history.fetch(:title),
          status_badge: status_badge,
          flow_label: flow_label,
          flow_value: resolve_flow_value(flow_label: flow_label, origin_codes: origin_codes, is_own: is_own),
          source_rows: build_source_rows,
          team_combo_chip_classes: TEAM_COMBO_CHIP_CLASSES,
          team_combo_chip_style: TEAM_COMBO_CHIP_STYLE,
          team_combo_logo_wrap_classes: TEAM_COMBO_LOGO_WRAP_CLASSES,
          team_combo_logo_image_classes: TEAM_COMBO_LOGO_IMAGE_CLASSES,
          team_combo_code_classes: TEAM_COMBO_CODE_CLASSES
        }
      end
    end

    def team_logo_for_code(code)
      meta = team_meta_by_code[normalize_team_code(code)] || {}
      helpers.team_logo_url(meta["team_id"])
    end

    def switch_team_onclick(code)
      normalized = normalize_team_code(code)
      "el.dispatchEvent(new CustomEvent('salarybook-switch-team', { bubbles: true, detail: { team: '#{normalized}', year: '#{salary_year}' } }));"
    end

    private

    attr_reader :team_code, :year, :round, :salary_year, :picks, :team_meta, :team_meta_by_code, :helpers

    def parse_pg_array(value)
      return [] if value.nil?
      return value.map { |entry| normalize_team_code(entry) }.reject(&:blank?) if value.is_a?(Array)

      raw = value.to_s
      return [] if raw.blank? || raw == "{}"

      raw.gsub(/[{}\"]/, "")
        .split(",")
        .map { |entry| normalize_team_code(entry) }
        .reject(&:blank?)
    end

    def normalize_team_code(value)
      value.to_s.strip.upcase
    end

    def resolve_origin_codes
      direct_codes = picks.map { |pick| normalize_team_code(pick["origin_team_code"]).presence }.compact
      counterparty_codes = picks.flat_map { |pick| parse_pg_array(pick["counterparty_team_codes"]) }

      (direct_codes + counterparty_codes)
        .uniq
        .reject { |code| code == team_code }
    end

    def resolve_via_codes
      picks
        .flat_map { |pick| parse_pg_array(pick["via_team_codes"]) }
        .uniq
        .reject { |code| code == team_code }
    end

    def resolve_trade_history
      raw_dates = picks.map { |pick| pick["endnote_trade_date"].presence }.compact.uniq
      entries = raw_dates.map { |raw| trade_date_entry(raw) }.uniq { |entry| entry[:label] }

      parsed = entries.select { |entry| entry[:sortable].present? }.sort_by { |entry| entry[:sortable] }
      unparsed = entries.reject { |entry| entry[:sortable].present? }

      labels = parsed.map { |entry| entry[:label] } + unparsed.map { |entry| entry[:label] }
      count = labels.length

      summary = if count <= 0
        nil
      elsif count == 1
        labels.first
      else
        "#{count} events"
      end

      {
        count: count,
        latest_label: parsed.last&.fetch(:label, nil) || labels.last,
        summary: summary,
        title: labels.join(", ")
      }
    end

    def trade_date_entry(raw)
      parsed_date = Date.parse(raw.to_s)
      {
        sortable: parsed_date,
        label: parsed_date.strftime("%b %-d, %Y")
      }
    rescue Date::Error, ArgumentError
      {
        sortable: nil,
        label: raw.to_s
      }
    end

    def resolve_status_badge(asset_type:, is_own:)
      if is_own
        { label: "Own Pick", klass: "bg-emerald-100/70 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300" }
      elsif asset_type == "TO"
        { label: "Traded Away", klass: "bg-violet-100/70 text-violet-700 dark:bg-violet-900/30 dark:text-violet-300" }
      else
        { label: "Acquired", klass: "bg-blue-100/70 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300" }
      end
    end

    def resolve_flow_value(flow_label:, origin_codes:, is_own:)
      if origin_codes.empty?
        is_own ? team_code : "—"
      elsif origin_codes.one?
        origin_codes.first
      else
        "Multi"
      end
    end

    def build_source_rows
      picks.map do |pick|
        flags = []
        flags << "swap" if pick["is_swap"] || pick["endnote_is_swap"]
        flags << "conditional" if pick["is_conditional"] || pick["endnote_is_conditional"]

        {
          slot: "#{pick['asset_slot']}.#{pick['sub_asset_slot']}",
          asset_type: pick["asset_type"].presence || "—",
          flags_text: flags.any? ? flags.join(" · ") : "—"
        }
      end
    end
  end
end
