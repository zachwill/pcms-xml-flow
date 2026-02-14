module Entities
  class PlayersController < ApplicationController
    INDEX_CAP_HORIZONS = [2025, 2026, 2027].freeze

    PLAYER_STATUS_LENSES = %w[all two_way restricted no_trade].freeze
    PLAYER_CONSTRAINT_LENSES = %w[all lock_now options non_guaranteed trade_kicker expiring].freeze
    PLAYER_URGENCY_LENSES = %w[all urgent upcoming stable].freeze
    PLAYER_SORT_LENSES = %w[cap_desc cap_asc name_asc name_desc].freeze
    PLAYER_DECISION_LENSES = %w[all urgent upcoming later].freeze

    PLAYER_URGENCY_DEFINITIONS = {
      "urgent" => {
        title: "Urgent decisions",
        subtitle: "Lock-now posture or immediate horizon triggers"
      },
      "upcoming" => {
        title: "Upcoming pressure",
        subtitle: "Future options/guarantees or pathway pressure"
      },
      "stable" => {
        title: "Stable commitments",
        subtitle: "No immediate option/expiry pressure"
      }
    }.freeze

    PLAYER_URGENCY_ORDER = %w[urgent upcoming stable].freeze

    # GET /players
    def index
      load_index_workspace_state!
      render :index
    end

    # GET /players/pane
    def pane
      load_index_workspace_state!
      render partial: "entities/players/workspace_main"
    end

    # GET /players/sidebar/:id
    def sidebar
      player_id = Integer(params[:id])
      player = load_sidebar_player_payload(player_id)

      render partial: "entities/players/rightpanel_overlay_player", locals: { player: player }
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /players/sidebar/clear
    def sidebar_clear
      render partial: "entities/players/rightpanel_clear"
    end

    # GET /players/:slug
    # Canonical route.
    def show
      @defer_heavy_load = params[:full].to_s != "1"
      load_player_decision_lens!

      resolve_player_from_slug!(params[:slug])
      return if performed?

      if @defer_heavy_load
        load_player_header_snapshot!
        seed_empty_player_workspace!
      else
        load_player_workspace_data!
      end

      render :show
    end

    # GET /players/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "player", entity_id: id, canonical: true)
      if canonical
        redirect_to player_path(canonical.slug), status: :moved_permanently
        return
      end

      # Create a default canonical slug on-demand, using PCMS name.
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(
        "SELECT COALESCE(display_first_name, first_name) AS first_name, COALESCE(display_last_name, last_name) AS last_name FROM pcms.people WHERE person_id = #{id_sql} LIMIT 1"
      ).first

      raise ActiveRecord::RecordNotFound unless row

      base = [row["first_name"], row["last_name"]].compact.join(" ").parameterize
      base = "player-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "player", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "player", entity_id: id, slug: slug, canonical: true)

      redirect_to player_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def load_index_workspace_state!(apply_compare_action: false)
      setup_index_filters!
      apply_index_compare_action! if apply_compare_action
      load_player_team_lenses!
      load_index_players!
      build_index_compare_state!
      build_index_player_sections!
      build_player_sidebar_summary!(selected_player_id: @selected_player_id)
    end

    def setup_index_filters!
      @query = params[:q].to_s.strip

      requested_team = params[:team].to_s.strip.upcase
      @team_lens = if requested_team.blank? || requested_team == "ALL"
        "ALL"
      elsif requested_team == "FA"
        "FA"
      elsif requested_team.match?(/\A[A-Z]{3}\z/)
        requested_team
      else
        "ALL"
      end

      requested_status = params[:status].to_s.strip
      @status_lens = PLAYER_STATUS_LENSES.include?(requested_status) ? requested_status : "all"

      requested_constraint = params[:constraint].to_s.strip
      @constraint_lens = PLAYER_CONSTRAINT_LENSES.include?(requested_constraint) ? requested_constraint : "all"

      requested_urgency = params[:urgency].to_s.strip
      @urgency_lens = PLAYER_URGENCY_LENSES.include?(requested_urgency) ? requested_urgency : "all"

      requested_horizon = normalize_cap_horizon_param(params[:horizon])
      @cap_horizon = requested_horizon || INDEX_CAP_HORIZONS.first

      requested_sort = params[:sort].to_s.strip
      @sort_lens = PLAYER_SORT_LENSES.include?(requested_sort) ? requested_sort : "cap_desc"

      @selected_player_id = normalize_selected_player_id_param(params[:selected_id])
      @compare_a_id = normalize_selected_player_id_param(params[:compare_a])
      @compare_b_id = normalize_selected_player_id_param(params[:compare_b])
      normalize_compare_slots!
    end

    def apply_index_compare_action!
      action = resolve_compare_action(params[:compare_action] || params[:action])
      slot = resolve_compare_slot(params[:compare_slot] || params[:slot])
      player_id = normalize_selected_player_id_param(params[:player_id])

      case action
      when "pin"
        return if slot.blank? || player_id.blank?

        if slot == "a"
          @compare_a_id = (@compare_a_id == player_id ? nil : player_id)
          @compare_b_id = nil if @compare_b_id == @compare_a_id
        else
          @compare_b_id = (@compare_b_id == player_id ? nil : player_id)
          @compare_a_id = nil if @compare_a_id == @compare_b_id
        end
      when "clear_slot"
        return if slot.blank?

        if slot == "a"
          @compare_a_id = nil
        else
          @compare_b_id = nil
        end
      when "clear_all"
        @compare_a_id = nil
        @compare_b_id = nil
      end

      normalize_compare_slots!
    end

    def load_player_team_lenses!
      conn = ActiveRecord::Base.connection

      @team_options = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
        ORDER BY team_code
      SQL
    end

    def load_index_players!
      conn = ActiveRecord::Base.connection
      where_clauses = []

      horizon_cap_column = "sbw.cap_#{@cap_horizon}"
      next_horizon_year = @cap_horizon + 1
      next_cap_column = "sbw.cap_#{next_horizon_year}"
      next_option_sql = "NULLIF(UPPER(COALESCE(sbw.option_#{next_horizon_year}, '')), 'NONE')"
      next_non_guaranteed_sql = "COALESCE(sbw.is_non_guaranteed_#{next_horizon_year}, false)"

      option_presence_sql = (2026..2030).map do |year|
        "NULLIF(UPPER(COALESCE(sbw.option_#{year}, '')), 'NONE') IS NOT NULL"
      end.join(" OR ")

      non_guaranteed_presence_sql = (2025..2030).map do |year|
        "COALESCE(sbw.is_non_guaranteed_#{year}, false) = true"
      end.join(" OR ")

      lock_now_sql = <<~SQL.squish
        (
          COALESCE(sbw.is_trade_restricted_now, false) = true
          OR COALESCE(sbw.is_trade_consent_required_now, false) = true
          OR COALESCE(sbw.is_no_trade, false) = true
        )
      SQL

      expiring_sql = "COALESCE(#{horizon_cap_column}, 0) > 0 AND COALESCE(#{next_cap_column}, 0) = 0"

      if @query.present?
        if @query.match?(/\A\d+\z/)
          where_clauses << "sbw.player_id = #{conn.quote(@query.to_i)}"
        else
          where_clauses << "sbw.player_name ILIKE #{conn.quote("%#{@query}%")}"
        end
      end

      case @team_lens
      when "FA"
        where_clauses << "NULLIF(TRIM(COALESCE(sbw.team_code, '')), '') IS NULL"
      when /\A[A-Z]{3}\z/
        where_clauses << "sbw.team_code = #{conn.quote(@team_lens)}"
      end

      case @status_lens
      when "two_way"
        where_clauses << "COALESCE(sbw.is_two_way, false) = true"
      when "restricted"
        where_clauses << "COALESCE(sbw.is_trade_restricted_now, false) = true"
      when "no_trade"
        where_clauses << "COALESCE(sbw.is_no_trade, false) = true"
      end

      case @constraint_lens
      when "lock_now"
        where_clauses << lock_now_sql
      when "options"
        where_clauses << "(#{option_presence_sql})"
      when "non_guaranteed"
        where_clauses << "(#{non_guaranteed_presence_sql})"
      when "trade_kicker"
        where_clauses << "COALESCE(sbw.is_trade_bonus, false) = true"
      when "expiring"
        where_clauses << "(#{expiring_sql})"
      end

      where_sql = where_clauses.any? ? where_clauses.join(" AND ") : "1 = 1"
      sort_sql = index_sort_sql(horizon_cap_column: horizon_cap_column)
      limit = @query.present? ? 240 : 140

      @players = conn.exec_query(<<~SQL).to_a
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_id,
          sbw.agent_name,
          sbw.is_two_way,
          sbw.is_trade_restricted_now,
          sbw.is_trade_consent_required_now,
          sbw.is_no_trade,
          sbw.is_trade_bonus,
          (#{option_presence_sql}) AS has_future_option,
          (#{non_guaranteed_presence_sql}) AS has_non_guaranteed,
          (#{next_option_sql} IS NOT NULL) AS has_next_horizon_option,
          #{next_option_sql} AS next_horizon_option,
          (#{next_non_guaranteed_sql}) AS has_next_horizon_non_guaranteed,
          #{lock_now_sql} AS has_lock_now,
          (#{expiring_sql}) AS expires_after_horizon,
          #{horizon_cap_column}::numeric AS cap_lens_value,
          #{next_cap_column}::numeric AS cap_next_value,
          sbw.cap_2025::numeric AS cap_2025,
          sbw.cap_2026::numeric AS cap_2026,
          sbw.cap_2027::numeric AS cap_2027,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
          p.years_of_service,
          p.player_status_lk,
          status_lk.short_description AS player_status_name
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        LEFT JOIN pcms.people p
          ON p.person_id = sbw.player_id
        LEFT JOIN pcms.lookups status_lk
          ON status_lk.lookup_type = 'lk_player_statuses'
         AND status_lk.lookup_code = p.player_status_lk
        WHERE #{where_sql}
        ORDER BY #{sort_sql}
        LIMIT #{limit}
      SQL

      annotate_player_urgency!(rows: @players)
      apply_urgency_filter!
    end

    def build_index_compare_state!
      @players_by_id = Array(@players).index_by { |row| row["player_id"].to_i }

      @compare_a_row = compare_row_from_workspace(@compare_a_id)
      @compare_b_row = compare_row_from_workspace(@compare_b_id)

      @compare_a_id = nil if @compare_a_id.present? && @compare_a_row.blank?
      @compare_b_id = nil if @compare_b_id.present? && @compare_b_row.blank?
      normalize_compare_slots!
    end

    def build_player_sidebar_summary!(selected_player_id: nil)
      rows = Array(@players)
      active_filters = []
      active_filters << %(Search: "#{@query}") if @query.present?
      active_filters << "Team: #{team_lens_label(@team_lens)}" unless @team_lens == "ALL"
      active_filters << "Status: #{status_lens_label(@status_lens)}" unless @status_lens == "all"
      active_filters << "Constraint: #{constraint_lens_label(@constraint_lens)}" unless @constraint_lens == "all"
      active_filters << "Urgency: #{urgency_lens_label(@urgency_lens)}" unless @urgency_lens == "all"
      active_filters << "Horizon: #{cap_horizon_label(@cap_horizon)}" unless @cap_horizon == INDEX_CAP_HORIZONS.first
      active_filters << "Sort: #{sort_lens_label(@sort_lens)}" unless @sort_lens == "cap_desc"

      top_rows = rows
                 .sort_by { |row| [urgency_rank(row["urgency_key"]), -(row["cap_lens_value"].to_f), row["player_name"].to_s] }
                 .first(18)

      selected_id = selected_player_id.to_i
      if selected_id.positive?
        selected_row = rows.find { |row| row["player_id"].to_i == selected_id }
        if selected_row.present? && top_rows.none? { |row| row["player_id"].to_i == selected_id }
          top_rows = (top_rows + [selected_row]).uniq { |row| row["player_id"].to_i }
            .sort_by { |row| [urgency_rank(row["urgency_key"]), -(row["cap_lens_value"].to_f), row["player_name"].to_s] }
            .first(18)
        end
      end

      top_row_lanes = build_player_urgency_lanes(rows: top_rows, assign: false, lane_row_limit: 5)

      @sidebar_summary = {
        row_count: rows.size,
        team_count: rows.map { |row| row["team_code"].presence }.compact.uniq.size,
        two_way_count: rows.count { |row| row["is_two_way"] },
        restricted_count: rows.count { |row| row["is_trade_restricted_now"] },
        no_trade_count: rows.count { |row| row["is_no_trade"] },
        constrained_count: rows.count { |row| constrained_row?(row) },
        urgent_count: rows.count { |row| row["urgency_key"].to_s == "urgent" },
        upcoming_count: rows.count { |row| row["urgency_key"].to_s == "upcoming" },
        stable_count: rows.count { |row| row["urgency_key"].to_s == "stable" },
        cap_horizon: @cap_horizon,
        cap_horizon_label: cap_horizon_label(@cap_horizon),
        urgency_lens: @urgency_lens,
        urgency_lens_label: urgency_lens_label(@urgency_lens),
        constraint_lens: @constraint_lens,
        constraint_lens_label: constraint_lens_label(@constraint_lens),
        constraint_lens_match_key: constraint_lens_match_key(@constraint_lens),
        constraint_lens_match_chip_label: constraint_lens_match_chip_label(@constraint_lens, cap_horizon: @cap_horizon),
        constraint_lens_match_reason: constraint_lens_match_reason(@constraint_lens, cap_horizon: @cap_horizon),
        total_cap: rows.sum { |row| row["cap_lens_value"].to_f },
        filters: active_filters,
        top_rows: top_rows,
        top_row_lanes: top_row_lanes,
        compare_a_id: @compare_a_id,
        compare_b_id: @compare_b_id,
        compare_a_row: @compare_a_row,
        compare_b_row: @compare_b_row
      }
    end

    def team_lens_label(team_lens)
      return "Free agents" if team_lens == "FA"

      team = Array(@team_options).find { |row| row["team_code"].to_s.upcase == team_lens.to_s.upcase }
      return team_lens if team.blank?

      "#{team['team_code']} · #{team['team_name']}"
    end

    def status_lens_label(status_lens)
      case status_lens
      when "two_way" then "Two-Way"
      when "restricted" then "Trade restricted"
      when "no_trade" then "No-trade"
      else "All"
      end
    end

    def constraint_lens_label(constraint_lens)
      case constraint_lens
      when "lock_now" then "Lock now"
      when "options" then "Options ahead"
      when "non_guaranteed" then "Non-guaranteed"
      when "trade_kicker" then "Trade kicker"
      when "expiring" then "Expiring after horizon"
      else "All commitments"
      end
    end

    def urgency_lens_label(urgency_lens)
      case urgency_lens.to_s
      when "urgent" then "Urgent decisions"
      when "upcoming" then "Upcoming pressure"
      when "stable" then "Stable commitments"
      else "All urgency lanes"
      end
    end

    def constraint_lens_match_key(constraint_lens)
      return nil if constraint_lens.to_s == "all"

      PLAYER_CONSTRAINT_LENSES.include?(constraint_lens.to_s) ? constraint_lens.to_s : nil
    end

    def constraint_lens_match_chip_label(constraint_lens, cap_horizon:)
      case constraint_lens.to_s
      when "lock_now" then "Match: Lock now"
      when "options" then "Match: Options ahead"
      when "non_guaranteed" then "Match: Non-Gtd"
      when "trade_kicker" then "Match: Trade kicker"
      when "expiring" then "Match: Expires #{cap_horizon.to_i + 1}"
      end
    end

    def constraint_lens_match_reason(constraint_lens, cap_horizon:)
      case constraint_lens.to_s
      when "lock_now"
        "Lock now posture (TR/NTC/consent required)"
      when "options"
        "Options ahead (PO/TO/ETO)"
      when "non_guaranteed"
        "Non-guaranteed years on file"
      when "trade_kicker"
        "Trade kicker clause on file"
      when "expiring"
        "Cap #{cap_horizon_label(cap_horizon)} > 0 and Cap #{cap_horizon_label(cap_horizon.to_i + 1)} = 0"
      end
    end

    def cap_horizon_label(horizon_year)
      year = horizon_year.to_i
      "#{year.to_s[-2..]}-#{(year + 1).to_s[-2..]}"
    end

    def sort_lens_label(sort_lens)
      case sort_lens
      when "cap_asc" then "Cap #{cap_horizon_label(@cap_horizon)} ascending"
      when "name_asc" then "Name A→Z"
      when "name_desc" then "Name Z→A"
      else "Cap #{cap_horizon_label(@cap_horizon)} descending"
      end
    end

    def compare_row_from_workspace(player_id)
      normalized_id = player_id.to_i
      return nil if normalized_id <= 0

      @players_by_id[normalized_id]
    end

    def resolve_compare_action(raw)
      action = raw.to_s.strip
      %w[pin clear_slot clear_all].include?(action) ? action : nil
    end

    def resolve_compare_slot(raw)
      slot = raw.to_s.strip.downcase
      %w[a b].include?(slot) ? slot : nil
    end

    def normalize_compare_slots!
      if @compare_a_id.present? && @compare_b_id.present? && @compare_a_id == @compare_b_id
        @compare_b_id = nil
      end
    end

    def index_sort_sql(horizon_cap_column:)
      case @sort_lens
      when "cap_asc"
        "#{horizon_cap_column} ASC NULLS LAST, sbw.player_name ASC"
      when "name_asc"
        "sbw.player_name ASC"
      when "name_desc"
        "sbw.player_name DESC"
      else
        "#{horizon_cap_column} DESC NULLS LAST, sbw.player_name ASC"
      end
    end

    def build_index_player_sections!
      @player_sections = build_player_urgency_lanes(rows: Array(@players), assign: false)
    end

    def build_player_urgency_lanes(rows:, assign: true, lane_row_limit: nil)
      grouped_rows = Hash.new { |hash, key| hash[key] = [] }
      Array(rows).each do |row|
        grouped_rows[row["urgency_key"].to_s.presence || "stable"] << row
      end

      lane_order = @urgency_lens == "all" ? PLAYER_URGENCY_ORDER : [@urgency_lens]

      lanes = lane_order.filter_map do |urgency_key|
        lane_rows = Array(grouped_rows[urgency_key])
        next if lane_rows.blank?

        lane_rows = lane_rows.first(lane_row_limit) if lane_row_limit.present?
        definition = PLAYER_URGENCY_DEFINITIONS.fetch(urgency_key.to_s)

        {
          key: urgency_key,
          title: definition[:title],
          subtitle: definition[:subtitle],
          row_count: lane_rows.size,
          team_count: lane_rows.map { |row| row["team_code"].presence }.compact.uniq.size,
          cap_lens_total: lane_rows.sum { |row| row["cap_lens_value"].to_f },
          cap_next_total: lane_rows.sum { |row| row["cap_next_value"].to_f },
          total_salary_total: lane_rows.sum { |row| row["total_salary_from_2025"].to_f },
          rows: lane_rows
        }
      end

      @player_sections = lanes if assign
      lanes
    end

    def annotate_player_urgency!(rows:)
      next_horizon_year = @cap_horizon.to_i + 1

      Array(rows).each do |row|
        urgency_key, urgency_reason = player_row_urgency(row, next_horizon_year: next_horizon_year)
        row["urgency_key"] = urgency_key
        row["urgency_label"] = urgency_lane_label(urgency_key)
        row["urgency_reason"] = urgency_reason
        row["urgency_rank"] = urgency_rank(urgency_key)
      end
    end

    def apply_urgency_filter!
      return if @urgency_lens == "all"

      @players = Array(@players).select { |row| row["urgency_key"].to_s == @urgency_lens }
    end

    def player_row_urgency(row, next_horizon_year:)
      if truthy_row_value?(row["has_lock_now"])
        return ["urgent", "Lock now posture (TR/consent/no-trade)"]
      end

      if truthy_row_value?(row["expires_after_horizon"])
        return ["urgent", "Expires after #{cap_horizon_label(@cap_horizon)}"]
      end

      if truthy_row_value?(row["has_next_horizon_option"])
        option_code = row["next_horizon_option"].to_s.presence || "Option"
        return ["urgent", "#{option_code} decision before #{cap_horizon_label(next_horizon_year)}"]
      end

      if truthy_row_value?(row["has_next_horizon_non_guaranteed"])
        return ["urgent", "Non-guaranteed salary in #{cap_horizon_label(next_horizon_year)}"]
      end

      if truthy_row_value?(row["has_future_option"])
        return ["upcoming", "Option decision window in forward years"]
      end

      if truthy_row_value?(row["has_non_guaranteed"])
        return ["upcoming", "Guarantee pressure in forward years"]
      end

      if truthy_row_value?(row["is_trade_bonus"])
        return ["upcoming", "Trade kicker leverage"]
      end

      if truthy_row_value?(row["is_two_way"])
        return ["upcoming", "Two-way conversion runway"]
      end

      ["stable", "No immediate horizon trigger"]
    end

    def urgency_rank(key)
      case key.to_s
      when "urgent" then 0
      when "upcoming" then 1
      else 2
      end
    end

    def urgency_lane_label(key)
      PLAYER_URGENCY_DEFINITIONS.dig(key.to_s, :title) || PLAYER_URGENCY_DEFINITIONS.dig("stable", :title)
    end

    def constrained_row?(row)
      truthy_row_value?(row["has_lock_now"]) || truthy_row_value?(row["is_trade_bonus"]) || truthy_row_value?(row["has_future_option"]) || truthy_row_value?(row["has_non_guaranteed"])
    end

    def truthy_row_value?(value)
      value == true || value.to_s == "t" || value.to_s.casecmp("true").zero? || value.to_s == "1"
    end

    def normalize_cap_horizon_param(raw)
      horizon = Integer(raw.to_s.strip, 10)
      INDEX_CAP_HORIZONS.include?(horizon) ? horizon : nil
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_selected_player_id_param(raw)
      selected_id = Integer(raw.to_s.strip, 10)
      selected_id.positive? ? selected_id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def load_player_decision_lens!
      requested_lens = params[:decision_lens].to_s.strip.downcase
      @decision_lens = PLAYER_DECISION_LENSES.include?(requested_lens) ? requested_lens : "all"
    end

    def selected_overlay_visible?(overlay_id:)
      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      Array(@players).any? { |row| row["player_id"].to_i == normalized_id }
    end

    def load_sidebar_player_payload(player_id)
      normalized_id = Integer(player_id)
      raise ActiveRecord::RecordNotFound if normalized_id <= 0

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(normalized_id)

      player = conn.exec_query(<<~SQL).first
        SELECT
          sbw.player_id,
          sbw.player_name,
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_id,
          sbw.agent_name,
          sbw.is_two_way,
          sbw.is_trade_restricted_now,
          sbw.is_no_trade,
          sbw.cap_2025::numeric AS cap_2025,
          sbw.cap_2026::numeric AS cap_2026,
          sbw.cap_2027::numeric AS cap_2027,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
          p.years_of_service,
          p.player_status_lk,
          status_lk.short_description AS player_status_name
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        LEFT JOIN pcms.people p
          ON p.person_id = sbw.player_id
        LEFT JOIN pcms.lookups status_lk
          ON status_lk.lookup_type = 'lk_player_statuses'
         AND status_lk.lookup_code = p.player_status_lk
        WHERE sbw.player_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless player

      player
    end

    def resolve_player_from_slug!(raw_slug, redirect_on_canonical_miss: true)
      slug = raw_slug.to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.empty?

      record = Slug.find_by!(entity_type: "player", slug: slug)

      canonical = Slug.find_by(entity_type: "player", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        if redirect_on_canonical_miss
          redirect_to player_path(canonical.slug), status: :moved_permanently
          return
        end

        record = canonical
      end

      @player_id = record.entity_id
      @player_slug = record.slug
    end

    def load_player_header_snapshot!
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@player_id)

      @player = conn.exec_query(<<~SQL).first
        SELECT
          p.person_id,
          COALESCE(p.display_first_name, p.first_name) AS first_name,
          COALESCE(p.display_last_name, p.last_name) AS last_name,
          p.birth_date,
          p.height,
          p.weight,
          p.uniform_number,
          p.years_of_service,
          p.draft_year,
          p.draft_round,
          p.draft_pick,
          p.draft_team_id,
          p.draft_team_code,
          p.player_status_lk,
          status_lk.short_description AS player_status_name,
          p.birth_country_lk,
          p.team_id AS person_team_id,
          p.team_code AS person_team_code,
          p.is_two_way AS person_is_two_way
        FROM pcms.people p
        LEFT JOIN pcms.lookups status_lk
          ON status_lk.lookup_type = 'lk_player_statuses'
         AND status_lk.lookup_code = p.player_status_lk
        WHERE p.person_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @player

      # Salary-book context (team + agent + contract flags) to enable link graph pivots.
      @salary_book_row = conn.exec_query(<<~SQL).first
        SELECT
          sbw.team_code,
          t.team_id,
          t.team_name,
          sbw.agent_id,
          sbw.agent_name,
          agency.agency_id,
          agency.agency_name,
          sbw.cap_2025::numeric AS cap_2025,
          sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
          sbw.contract_id,
          sbw.version_number,
          sbw.contract_type_lookup_value,
          sbw.signed_method_lookup_value,
          sbw.exception_type_lookup_value,
          sbw.min_contract_lookup_value,
          sbw.player_consent_lk,
          consent_lk.short_description AS player_consent_label,
          sbw.player_consent_end_date,
          sbw.is_trade_consent_required_now,
          sbw.is_trade_preconsented,
          sbw.trade_restriction_code,
          sbw.trade_restriction_lookup_value,
          sbw.trade_restriction_end_date,
          sbw.is_trade_restricted_now,
          sbw.is_no_trade,
          sbw.is_trade_bonus,
          sbw.trade_bonus_percent,
          sbw.trade_kicker_display,
          sbw.is_poison_pill,
          sbw.is_two_way,
          sbw.is_min_contract,
          sbw.guaranteed_amount_2025,
          sbw.guaranteed_amount_2026,
          sbw.guaranteed_amount_2027,
          sbw.guaranteed_amount_2028,
          sbw.guaranteed_amount_2029,
          sbw.guaranteed_amount_2030,
          sbw.is_fully_guaranteed_2025,
          sbw.is_fully_guaranteed_2026,
          sbw.is_fully_guaranteed_2027,
          sbw.is_fully_guaranteed_2028,
          sbw.is_fully_guaranteed_2029,
          sbw.is_fully_guaranteed_2030,
          sbw.is_partially_guaranteed_2025,
          sbw.is_partially_guaranteed_2026,
          sbw.is_partially_guaranteed_2027,
          sbw.is_partially_guaranteed_2028,
          sbw.is_partially_guaranteed_2029,
          sbw.is_partially_guaranteed_2030,
          sbw.is_non_guaranteed_2025,
          sbw.is_non_guaranteed_2026,
          sbw.is_non_guaranteed_2027,
          sbw.is_non_guaranteed_2028,
          sbw.is_non_guaranteed_2029,
          sbw.is_non_guaranteed_2030
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        LEFT JOIN pcms.agents agent
          ON agent.agent_id = sbw.agent_id
        LEFT JOIN pcms.agencies agency
          ON agency.agency_id = agent.agency_id
        LEFT JOIN pcms.lookups consent_lk
          ON consent_lk.lookup_type = 'lk_player_consents'
         AND consent_lk.lookup_code = sbw.player_consent_lk
        WHERE sbw.player_id = #{id_sql}
        LIMIT 1
      SQL

      # Draft selection (historical) — player → draft → team link.
      @draft_selection = conn.exec_query(<<~SQL).first
        SELECT
          transaction_id,
          draft_year,
          draft_round,
          pick_number,
          drafting_team_id,
          drafting_team_code,
          transaction_date
        FROM pcms.draft_selections
        WHERE player_id = #{id_sql}
        LIMIT 1
      SQL
    end

    def seed_empty_player_workspace!
      @team_history_rows = []
      @salary_book_yearly_rows = []
      @contract_chronology_rows = []
      @contract_version_rows = []
      @salary_rows = []
      @protection_rows = []
      @protection_condition_rows = []
      @bonus_rows = []
      @bonus_max_rows = []
      @payment_schedule_rows = []
      @ledger_entries = []
    end

    def load_player_workspace_data!
      load_player_header_snapshot!

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@player_id)

      # Team history (derived from transactions) — track stints with each team.
      # Uses key transaction types that indicate team changes (SIGN, TRADE, DRAFT, etc.)
      @team_history_rows = conn.exec_query(<<~SQL).to_a
        WITH team_transactions AS (
          SELECT
            tx.transaction_id,
            tx.transaction_date,
            tx.transaction_type_lk,
            COALESCE(to_team.team_id, from_team.team_id) AS team_id,
            COALESCE(to_team.team_code, from_team.team_code) AS team_code,
            COALESCE(to_team.team_name, from_team.team_name) AS team_name,
            tx.trade_id
          FROM pcms.transactions tx
          LEFT JOIN pcms.teams from_team ON from_team.team_id = tx.from_team_id AND from_team.league_lk = 'NBA'
          LEFT JOIN pcms.teams to_team ON to_team.team_id = tx.to_team_id AND to_team.league_lk = 'NBA'
          WHERE tx.player_id = #{id_sql}
            AND tx.transaction_type_lk IN ('SIGN', 'TRADE', 'DRAFT', 'DDRFT', 'WSIGN', 'REAQC', 'REAQT', 'CLLUP', '2WCNV')
        )
        SELECT
          team_code,
          team_id,
          team_name,
          MIN(transaction_date) AS start_date,
          MAX(transaction_date) AS last_date,
          array_agg(DISTINCT transaction_type_lk ORDER BY transaction_type_lk) AS tx_types,
          COUNT(*)::integer AS tx_count
        FROM team_transactions
        WHERE team_code IS NOT NULL
        GROUP BY team_code, team_id, team_name
        ORDER BY start_date
      SQL

      # Salary warehouse yearly rows (cap/tax/apron) for salary-book parity.
      @salary_book_yearly_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          salary_year,
          cap_amount,
          tax_amount,
          apron_amount,
          incoming_cap_amount,
          incoming_tax_amount,
          incoming_apron_amount,
          trade_kicker_amount,
          is_two_way,
          refreshed_at
        FROM pcms.salary_book_yearly
        WHERE player_id = #{id_sql}
          AND salary_year BETWEEN 2025 AND 2030
        ORDER BY salary_year
      SQL

      @contract_chronology_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          c.contract_id,
          c.signing_date,
          c.contract_end_date,
          c.start_year,
          c.record_status_lk,
          c.signed_method_lk,
          COALESCE(signed_lk.short_description, signed_lk.description) AS signed_method_label,
          c.team_exception_id,
          te.exception_type_lk,
          COALESCE(exc_lk.short_description, exc_lk.description) AS exception_type_label,
          c.is_sign_and_trade,
          c.sign_and_trade_date,
          c.sign_and_trade_id,
          c.two_way_service_limit,
          c.convert_date,
          c.team_code,
          c.signing_team_id,
          signing_team.team_code AS signing_team_code,
          signing_team.team_name AS signing_team_name,
          c.sign_and_trade_to_team_id,
          sat_team.team_code AS sign_and_trade_to_team_code,
          sat_team.team_name AS sign_and_trade_to_team_name,
          COUNT(cv.contract_version_id)::integer AS version_count,
          MIN(cv.start_salary_year) AS min_version_start_year,
          MAX(cv.version_number) AS latest_version_number
        FROM pcms.contracts c
        LEFT JOIN pcms.lookups signed_lk
          ON signed_lk.lookup_type = 'lk_signed_methods'
         AND signed_lk.lookup_code = c.signed_method_lk
        LEFT JOIN pcms.team_exceptions te
          ON te.team_exception_id = c.team_exception_id
        LEFT JOIN pcms.lookups exc_lk
          ON exc_lk.lookup_type = 'lk_exception_types'
         AND exc_lk.lookup_code = te.exception_type_lk
        LEFT JOIN pcms.teams signing_team
          ON signing_team.team_id = c.signing_team_id
        LEFT JOIN pcms.teams sat_team
          ON sat_team.team_id = c.sign_and_trade_to_team_id
        LEFT JOIN pcms.contract_versions cv
          ON cv.contract_id = c.contract_id
        WHERE c.player_id = #{id_sql}
        GROUP BY
          c.contract_id,
          c.signing_date,
          c.contract_end_date,
          c.start_year,
          c.record_status_lk,
          c.signed_method_lk,
          signed_lk.short_description,
          signed_lk.description,
          c.team_exception_id,
          te.exception_type_lk,
          exc_lk.short_description,
          exc_lk.description,
          c.is_sign_and_trade,
          c.sign_and_trade_date,
          c.sign_and_trade_id,
          c.two_way_service_limit,
          c.convert_date,
          c.team_code,
          c.signing_team_id,
          signing_team.team_code,
          signing_team.team_name,
          c.sign_and_trade_to_team_id,
          sat_team.team_code,
          sat_team.team_name
        ORDER BY c.signing_date DESC NULLS LAST, c.contract_id DESC
      SQL

      @contract_version_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          cv.contract_id,
          cv.version_number,
          cv.version_date,
          cv.start_salary_year,
          cv.contract_length,
          cv.contract_type_lk,
          COALESCE(contract_type_lk.short_description, contract_type_lk.description) AS contract_type_label,
          cv.record_status_lk,
          cv.is_rookie_scale_extension,
          cv.is_veteran_extension,
          cv.is_exhibit_10,
          cv.exhibit_10_bonus_amount,
          cv.is_poison_pill,
          cv.poison_pill_amount,
          cv.is_trade_bonus,
          cv.trade_bonus_percent,
          cv.trade_bonus_amount,
          cv.is_no_trade,
          cv.is_protected_contract,
          cv.is_full_protection
        FROM pcms.contract_versions cv
        JOIN pcms.contracts c
          ON c.contract_id = cv.contract_id
        LEFT JOIN pcms.lookups contract_type_lk
          ON contract_type_lk.lookup_type = 'lk_contract_types'
         AND contract_type_lk.lookup_code = cv.contract_type_lk
        WHERE c.player_id = #{id_sql}
        ORDER BY c.signing_date DESC NULLS LAST, cv.contract_id DESC, cv.version_number DESC
        LIMIT 400
      SQL

      @salary_rows = []
      @protection_rows = []
      @protection_condition_rows = []
      @bonus_rows = []
      @bonus_max_rows = []
      @payment_schedule_rows = []

      if @salary_book_row.present? && @salary_book_row["contract_id"].present? && @salary_book_row["version_number"].present?
        contract_sql = conn.quote(@salary_book_row["contract_id"])
        version_sql = conn.quote(@salary_book_row["version_number"])

        @salary_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            salary_year,
            total_salary,
            current_base_comp,
            contract_cap_salary,
            contract_tax_salary,
            contract_tax_apron_salary,
            signing_bonus,
            likely_bonus,
            unlikely_bonus,
            trade_bonus_amount,
            option_lk,
            option_decision_lk
          FROM pcms.salaries
          WHERE contract_id = #{contract_sql}
            AND version_number = #{version_sql}
            AND salary_year BETWEEN 2024 AND 2031
          ORDER BY salary_year
        SQL

        @protection_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            salary_year,
            SUM(protection_amount)::bigint AS protection_amount,
            SUM(effective_protection_amount)::bigint AS effective_protection_amount,
            BOOL_OR(COALESCE(is_conditional_protection, false)) AS has_conditional,
            STRING_AGG(DISTINCT protection_coverage_lk, ', ' ORDER BY protection_coverage_lk) AS coverage_codes,
            COUNT(*)::integer AS row_count
          FROM pcms.contract_protections
          WHERE contract_id = #{contract_sql}
            AND version_number = #{version_sql}
          GROUP BY salary_year
          ORDER BY salary_year
        SQL

        @protection_condition_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            cpc.condition_id,
            cp.salary_year,
            cpc.amount,
            cpc.earned_type_lk,
            cpc.earned_date,
            cpc.is_full_condition,
            cpc.clause_name,
            cpc.criteria_description
          FROM pcms.contract_protection_conditions cpc
          LEFT JOIN pcms.contract_protections cp
            ON cp.protection_id = cpc.protection_id
           AND cp.contract_id = cpc.contract_id
           AND cp.version_number = cpc.version_number
          WHERE cpc.contract_id = #{contract_sql}
            AND cpc.version_number = #{version_sql}
          ORDER BY cp.salary_year, cpc.amount DESC NULLS LAST, cpc.condition_id
          LIMIT 120
        SQL

        @bonus_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            bonus_id,
            salary_year,
            bonus_type_lk,
            is_likely,
            bonus_amount,
            earned_lk,
            paid_by_date,
            clause_name,
            criteria_description
          FROM pcms.contract_bonuses
          WHERE contract_id = #{contract_sql}
            AND version_number = #{version_sql}
          ORDER BY salary_year, is_likely DESC, bonus_amount DESC NULLS LAST, bonus_id
          LIMIT 200
        SQL

        @bonus_max_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            salary_year,
            bonus_type_lk,
            is_likely,
            max_amount
          FROM pcms.contract_bonus_maximums
          WHERE contract_id = #{contract_sql}
            AND version_number = #{version_sql}
          ORDER BY salary_year, max_amount DESC NULLS LAST
        SQL

        @payment_schedule_rows = conn.exec_query(<<~SQL).to_a
          SELECT
            ps.payment_schedule_id,
            ps.salary_year,
            ps.payment_amount,
            ps.payment_start_date,
            ps.schedule_type_lk,
            ps.payment_type_lk,
            ps.is_default_schedule,
            COALESCE(detail_agg.detail_count, 0)::integer AS detail_count,
            detail_agg.first_payment_date,
            detail_agg.last_payment_date
          FROM pcms.payment_schedules ps
          LEFT JOIN (
            SELECT
              payment_schedule_id,
              COUNT(*)::integer AS detail_count,
              MIN(payment_date) AS first_payment_date,
              MAX(payment_date) AS last_payment_date
            FROM pcms.payment_schedule_details
            GROUP BY payment_schedule_id
          ) detail_agg
            ON detail_agg.payment_schedule_id = ps.payment_schedule_id
          WHERE ps.contract_id = #{contract_sql}
            AND ps.version_number = #{version_sql}
          ORDER BY ps.salary_year, ps.payment_start_date NULLS LAST, ps.payment_schedule_id
        SQL
      end

      @ledger_entries = conn.exec_query(<<~SQL).to_a
        SELECT
          le.ledger_date,
          le.salary_year,
          le.transaction_id,
          tx.trade_id,
          le.transaction_type_lk,
          le.transaction_description_lk,
          le.team_id,
          t.team_code,
          t.team_name,
          le.cap_amount,
          le.cap_change,
          le.tax_change,
          le.apron_change,
          le.mts_change
        FROM pcms.ledger_entries le
        LEFT JOIN pcms.transactions tx
          ON tx.transaction_id = le.transaction_id
        LEFT JOIN pcms.teams t
          ON t.team_id = le.team_id
         AND t.league_lk = 'NBA'
        WHERE le.player_id = #{id_sql}
          AND le.league_lk = 'NBA'
        ORDER BY le.ledger_date DESC, le.transaction_ledger_entry_id DESC
        LIMIT 80
      SQL
    end
  end
end
