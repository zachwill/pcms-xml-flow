module Entities
  class PlayersController < ApplicationController
    INDEX_CAP_HORIZONS = [2025, 2026, 2027].freeze

    PLAYER_STATUS_LENSES = %w[all two_way restricted no_trade].freeze
    PLAYER_CONSTRAINT_LENSES = %w[all lock_now options non_guaranteed trade_kicker expiring].freeze
    PLAYER_URGENCY_LENSES = %w[all urgent upcoming stable].freeze
    PLAYER_URGENCY_SUB_LENSES = %w[all option_only expiring_only non_guaranteed_only].freeze
    PLAYER_SORT_LENSES = %w[cap_desc cap_asc name_asc name_desc].freeze
    PLAYER_DECISION_LENSES = %w[all urgent upcoming later].freeze

    PLAYER_URGENCY_DEFINITIONS = PlayerService::URGENCY_DEFINITIONS
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
      player = PlayerQueries.fetch_sidebar_player(player_id)

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
      row = conn.exec_query(
        "SELECT COALESCE(display_first_name, first_name) AS first_name, COALESCE(display_last_name, last_name) AS last_name FROM pcms.people WHERE person_id = #{conn.quote(id)} LIMIT 1"
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
        @compare_a_id = nil if slot == "a"
        @compare_b_id = nil if slot == "b"
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
      fragments = PlayerService.build_index_sql_fragments(@cap_horizon)
      where_sql = PlayerService.build_index_where_clauses(
        query: @query, team_lens: @team_lens, status_lens: @status_lens,
        constraint_lens: @constraint_lens, fragments: fragments, conn: ActiveRecord::Base.connection
      )
      sort_sql = PlayerService.index_sort_sql(@sort_lens, horizon_cap_column: fragments[:horizon_cap_column])

      @players = PlayerQueries.fetch_index_players(
        where_sql: where_sql, sort_sql: sort_sql, limit: @query.present? ? 240 : 140,
        **fragments.slice(:horizon_cap_column, :next_horizon_year, :option_presence_sql,
          :non_guaranteed_presence_sql, :lock_now_sql, :expiring_sql, :next_option_sql, :next_non_guaranteed_sql)
      )

      PlayerService.annotate_player_urgency!(rows: @players, cap_horizon: @cap_horizon)
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
      active_filters << "Status: #{PlayerService.status_lens_label(@status_lens)}" unless @status_lens == "all"
      active_filters << "Constraint: #{PlayerService.constraint_lens_label(@constraint_lens)}" unless @constraint_lens == "all"
      active_filters << "Urgency: #{PlayerService.urgency_lens_label(@urgency_lens)}" unless @urgency_lens == "all"
      active_filters << "Urgency focus: #{PlayerService.urgency_sub_lens_label(@urgency_sub_lens)}" unless @urgency_sub_lens == "all"
      active_filters << "Horizon: #{PlayerService.cap_horizon_label(@cap_horizon)}" unless @cap_horizon == INDEX_CAP_HORIZONS.first
      active_filters << "Sort: #{PlayerService.sort_lens_label(@sort_lens, cap_horizon: @cap_horizon)}" unless @sort_lens == "cap_desc"

      top_rows = rows
                 .sort_by { |row| [PlayerService.urgency_rank(row["urgency_key"]), -(row["cap_lens_value"].to_f), row["player_name"].to_s] }
                 .first(18)

      selected_id = selected_player_id.to_i
      if selected_id.positive?
        selected_row = rows.find { |row| row["player_id"].to_i == selected_id }
        if selected_row.present? && top_rows.none? { |row| row["player_id"].to_i == selected_id }
          top_rows = (top_rows + [selected_row]).uniq { |row| row["player_id"].to_i }
            .sort_by { |row| [PlayerService.urgency_rank(row["urgency_key"]), -(row["cap_lens_value"].to_f), row["player_name"].to_s] }
            .first(18)
        end
      end

      top_row_lanes = PlayerService.build_urgency_lanes(
        rows: top_rows, urgency_lens: @urgency_lens,
        urgency_order: PLAYER_URGENCY_ORDER, urgency_definitions: PLAYER_URGENCY_DEFINITIONS,
        lane_row_limit: 5
      )

      @sidebar_summary = {
        row_count: rows.size,
        team_count: rows.map { |row| row["team_code"].presence }.compact.uniq.size,
        two_way_count: rows.count { |row| row["is_two_way"] },
        restricted_count: rows.count { |row| row["is_trade_restricted_now"] },
        no_trade_count: rows.count { |row| row["is_no_trade"] },
        constrained_count: rows.count { |row| PlayerService.constrained_row?(row) },
        urgent_count: rows.count { |row| row["urgency_key"].to_s == "urgent" },
        upcoming_count: rows.count { |row| row["urgency_key"].to_s == "upcoming" },
        stable_count: rows.count { |row| row["urgency_key"].to_s == "stable" },
        cap_horizon: @cap_horizon,
        cap_horizon_label: PlayerService.cap_horizon_label(@cap_horizon),
        urgency_lens: @urgency_lens,
        urgency_lens_label: PlayerService.urgency_lens_label(@urgency_lens),
        urgency_sub_lens: @urgency_sub_lens,
        urgency_sub_lens_label: PlayerService.urgency_sub_lens_label(@urgency_sub_lens),
        constraint_lens: @constraint_lens,
        constraint_lens_label: PlayerService.constraint_lens_label(@constraint_lens),
        constraint_lens_match_key: PlayerService.constraint_lens_match_key(@constraint_lens, valid_lenses: PLAYER_CONSTRAINT_LENSES),
        constraint_lens_match_chip_label: PlayerService.constraint_lens_match_chip_label(@constraint_lens, cap_horizon: @cap_horizon),
        constraint_lens_match_reason: PlayerService.constraint_lens_match_reason(@constraint_lens, cap_horizon: @cap_horizon),
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
      @compare_b_id = nil if @compare_a_id.present? && @compare_b_id.present? && @compare_a_id == @compare_b_id
    end

    def build_index_player_sections!
      @player_sections = PlayerService.build_urgency_lanes(
        rows: Array(@players), urgency_lens: @urgency_lens,
        urgency_order: PLAYER_URGENCY_ORDER, urgency_definitions: PLAYER_URGENCY_DEFINITIONS
      )
    end

    def apply_urgency_filter!
      return if @urgency_lens == "all"
      @players = Array(@players).select { |row| row["urgency_key"].to_s == @urgency_lens }
    end

    def apply_urgency_sub_filter!
      return if @urgency_sub_lens == "all"
      @players = Array(@players).select { |row| PlayerService.matches_urgency_sub_lens?(row, lens: @urgency_sub_lens) }
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
      normalized_id.positive? && Array(@players).any? { |row| row["player_id"].to_i == normalized_id }
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
      @player = PlayerQueries.fetch_player_person(@player_id)
      raise ActiveRecord::RecordNotFound unless @player
      @salary_book_row = PlayerQueries.fetch_player_salary_book_context(@player_id)
      @draft_selection = PlayerQueries.fetch_player_draft_selection(@player_id)
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
      @team_history_rows = PlayerQueries.fetch_player_team_history(@player_id)
      @salary_book_yearly_rows = PlayerQueries.fetch_player_salary_book_yearly(@player_id)
      @contract_chronology_rows = PlayerQueries.fetch_player_contract_chronology(@player_id)
      @contract_version_rows = PlayerQueries.fetch_player_contract_versions(@player_id)

      @salary_rows = []
      @protection_rows = []
      @protection_condition_rows = []
      @bonus_rows = []
      @bonus_max_rows = []
      @payment_schedule_rows = []

      if @salary_book_row.present? && @salary_book_row["contract_id"].present? && @salary_book_row["version_number"].present?
        cid = @salary_book_row["contract_id"]
        vn = @salary_book_row["version_number"]
        @salary_rows = PlayerQueries.fetch_player_salaries(cid, vn)
        @protection_rows = PlayerQueries.fetch_player_protections(cid, vn)
        @protection_condition_rows = PlayerQueries.fetch_player_protection_conditions(cid, vn)
        @bonus_rows = PlayerQueries.fetch_player_bonuses(cid, vn)
        @bonus_max_rows = PlayerQueries.fetch_player_bonus_maximums(cid, vn)
        @payment_schedule_rows = PlayerQueries.fetch_player_payment_schedules(cid, vn)
      end
      @ledger_entries = PlayerQueries.fetch_player_ledger_entries(@player_id)
    end
  end
end
