module Entities
  class PlayersController < ApplicationController
    INDEX_CAP_HORIZONS = [2025, 2026, 2027].freeze

    PLAYER_STATUS_LENSES = %w[all two_way restricted no_trade].freeze
    PLAYER_CONSTRAINT_LENSES = %w[all lock_now options non_guaranteed trade_kicker expiring].freeze
    PLAYER_URGENCY_LENSES = %w[all urgent upcoming stable].freeze
    PLAYER_URGENCY_SUB_LENSES = %w[all option_only expiring_only non_guaranteed_only].freeze
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

      requested_urgency_sub = params[:urgency_sub].to_s.strip
      @urgency_sub_lens = PLAYER_URGENCY_SUB_LENSES.include?(requested_urgency_sub) ? requested_urgency_sub : "all"

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
      @team_options = PlayerQueries.fetch_team_options
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
      apply_urgency_sub_filter!
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
      active_filters << "Urgency focus: #{urgency_sub_lens_label(@urgency_sub_lens)}" unless @urgency_sub_lens == "all"
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
        urgency_sub_lens: @urgency_sub_lens,
        urgency_sub_lens_label: urgency_sub_lens_label(@urgency_sub_lens),
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

    def urgency_sub_lens_label(urgency_sub_lens)
      case urgency_sub_lens.to_s
      when "option_only" then "Option-only"
      when "expiring_only" then "Expiring-only"
      when "non_guaranteed_only" then "Non-guaranteed-only"
      else "All triggers"
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

    def apply_urgency_sub_filter!
      return if @urgency_sub_lens == "all"

      @players = Array(@players).select { |row| matches_urgency_sub_lens?(row, lens: @urgency_sub_lens) }
    end

    def matches_urgency_sub_lens?(row, lens:)
      case lens.to_s
      when "option_only"
        truthy_row_value?(row["has_next_horizon_option"]) || truthy_row_value?(row["has_future_option"])
      when "expiring_only"
        truthy_row_value?(row["expires_after_horizon"])
      when "non_guaranteed_only"
        truthy_row_value?(row["has_next_horizon_non_guaranteed"]) || truthy_row_value?(row["has_non_guaranteed"])
      else
        true
      end
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

      player = PlayerQueries.fetch_sidebar_player(normalized_id)
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
      @player = PlayerQueries.fetch_player_header(@player_id)
      raise ActiveRecord::RecordNotFound unless @player

      # Salary-book context (team + agent + contract flags) to enable link graph pivots.
      @salary_book_row = PlayerQueries.fetch_salary_book_row(@player_id)

      # Draft selection (historical) — player → draft → team link.
      @draft_selection = PlayerQueries.fetch_draft_selection(@player_id)
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

      # Team history (derived from transactions) — track stints with each team.
      # Uses key transaction types that indicate team changes (SIGN, TRADE, DRAFT, etc.)
      @team_history_rows = PlayerQueries.fetch_team_history(@player_id)

      # Salary warehouse yearly rows (cap/tax/apron) for salary-book parity.
      @salary_book_yearly_rows = PlayerQueries.fetch_salary_book_yearly(@player_id)

      @contract_chronology_rows = PlayerQueries.fetch_contract_chronology(@player_id)

      @contract_version_rows = PlayerQueries.fetch_contract_versions(@player_id)

      @salary_rows = []
      @protection_rows = []
      @protection_condition_rows = []
      @bonus_rows = []
      @bonus_max_rows = []
      @payment_schedule_rows = []

      if @salary_book_row.present? && @salary_book_row["contract_id"].present? && @salary_book_row["version_number"].present?
        cid = @salary_book_row["contract_id"]
        vnum = @salary_book_row["version_number"]

        @salary_rows = PlayerQueries.fetch_salary_rows(cid, vnum)
        @protection_rows = PlayerQueries.fetch_protection_rows(cid, vnum)
        @protection_condition_rows = PlayerQueries.fetch_protection_condition_rows(cid, vnum)
        @bonus_rows = PlayerQueries.fetch_bonus_rows(cid, vnum)
        @bonus_max_rows = PlayerQueries.fetch_bonus_max_rows(cid, vnum)
        @payment_schedule_rows = PlayerQueries.fetch_payment_schedule_rows(cid, vnum)
      end

      @ledger_entries = PlayerQueries.fetch_ledger_entries(@player_id)
    end
  end
end
