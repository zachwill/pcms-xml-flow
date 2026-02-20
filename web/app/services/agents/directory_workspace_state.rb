module Agents
  class DirectoryWorkspaceState
    def initialize(
      params:,
      queries:,
      book_years:,
      agent_sort_keys:,
      agency_sort_keys:
    )
      @params = params
      @queries = queries
      @book_years = book_years
      @agent_sort_keys = agent_sort_keys
      @agency_sort_keys = agency_sort_keys
    end

    def build
      setup_directory_filters!
      load_filter_options!
      load_directory_rows!
      build_sidebar_summary!

      {
        directory_kind: @directory_kind,
        query: @query,
        active_only: @active_only,
        certified_only: @certified_only,
        with_clients: @with_clients,
        with_book: @with_book,
        with_restrictions: @with_restrictions,
        with_expiring: @with_expiring,
        book_year: @book_year,
        sort_key: @sort_key,
        sort_dir: @sort_dir,
        agency_filter_id: @agency_filter_id,
        agency_filter_options: @agency_filter_options,
        agency_scope_active: @agency_scope_active,
        agency_scope_id: @agency_scope_id,
        agents: @agents,
        agencies: @agencies,
        sidebar_summary: @sidebar_summary
      }
    end

    private

    attr_reader :params, :queries, :book_years, :agent_sort_keys, :agency_sort_keys

    def setup_directory_filters!
      @directory_kind = "agents"
      @query = params[:q].to_s.strip

      @active_only = cast_bool(params[:active_only])
      @certified_only = cast_bool(params[:certified_only])
      @with_clients = cast_bool(params[:with_clients])
      @with_book = cast_bool(params[:with_book])
      @with_restrictions = cast_bool(params[:with_restrictions])
      @with_expiring = cast_bool(params[:with_expiring])

      year = begin
        Integer(params[:year])
      rescue ArgumentError, TypeError
        nil
      end
      @book_year = book_years.include?(year) ? year : book_years.first

      @sort_dir = params[:dir].to_s == "asc" ? "asc" : "desc"

      allowed_sort_keys = @directory_kind == "agencies" ? agency_sort_keys : agent_sort_keys
      @sort_key = params[:sort].to_s
      @sort_key = "book" unless allowed_sort_keys.include?(@sort_key)

      @agency_filter_id = parse_positive_integer(params[:agency_id])

      @agency_scope_active = cast_bool(params[:agency_scope])
      @agency_scope_id = parse_positive_integer(params[:agency_scope_id])

      if @agency_scope_active && @directory_kind == "agents"
        @agency_scope_id ||= parse_overlay_agency_id_from_params
        @agency_scope_active = false unless @agency_scope_id.present?
      else
        @agency_scope_active = false
        @agency_scope_id = nil
      end
    end

    def load_filter_options!
      @agency_filter_options = queries.fetch_agency_filter_options(limit: 400)
    end

    def load_directory_rows!
      conn = ActiveRecord::Base.connection
      book_total_sql = sql_book_total("w")
      book_percentile_sql = sql_book_percentile("w")
      expiring_sql = sql_expiring_in_window("w")

      if @directory_kind == "agencies"
        sort_sql = sql_sort_for_agencies(book_total_sql:, expiring_sql:)
        where_clauses = ["1 = 1"]
        where_clauses << "COALESCE(w.is_active, true) = true" if @active_only
        where_clauses << "COALESCE(w.client_count, 0) > 0" if @with_clients
        where_clauses << "COALESCE(#{book_total_sql}, 0) > 0" if @with_book
        where_clauses << "COALESCE(#{expiring_sql}, 0) > 0" if @with_expiring
        where_clauses << "(COALESCE(w.no_trade_count, 0) > 0 OR COALESCE(w.trade_kicker_count, 0) > 0 OR COALESCE(w.trade_restricted_count, 0) > 0)" if @with_restrictions
        where_clauses << "w.agency_id = #{conn.quote(@agency_filter_id)}" if @agency_filter_id.present?

        if @query.present?
          query_sql = conn.quote("%#{@query}%")
          query_clauses = [
            "w.agency_name ILIKE #{query_sql}",
            "EXISTS (SELECT 1 FROM pcms.agents_warehouse aw WHERE aw.agency_id = w.agency_id AND aw.full_name ILIKE #{query_sql})"
          ]
          if @query.match?(/\A\d+\z/)
            query_id_sql = conn.quote(@query.to_i)
            query_clauses << "w.agency_id = #{query_id_sql}"
            query_clauses << "EXISTS (SELECT 1 FROM pcms.agents_warehouse aw WHERE aw.agency_id = w.agency_id AND aw.agent_id = #{query_id_sql})"
          end

          where_clauses << "(#{query_clauses.join(" OR ")})"
        end

        @agencies = queries.fetch_directory_agencies(
          where_sql: where_clauses.join(" AND "),
          sort_sql: sort_sql,
          sort_direction: sql_sort_direction_for_key,
          book_total_sql: book_total_sql,
          book_percentile_sql: book_percentile_sql,
          expiring_sql: expiring_sql
        )

        @agents = []
      else
        sort_sql = sql_sort_for_agents(book_total_sql:, expiring_sql:)
        where_clauses = ["1 = 1"]
        where_clauses << "COALESCE(w.client_count, 0) > 0"
        where_clauses << "COALESCE(w.is_active, true) = true" if @active_only
        where_clauses << "COALESCE(w.is_certified, false) = true" if @certified_only
        where_clauses << "COALESCE(#{book_total_sql}, 0) > 0" if @with_book
        where_clauses << "COALESCE(#{expiring_sql}, 0) > 0" if @with_expiring
        where_clauses << "(COALESCE(w.no_trade_count, 0) > 0 OR COALESCE(w.trade_kicker_count, 0) > 0 OR COALESCE(w.trade_restricted_count, 0) > 0)" if @with_restrictions
        where_clauses << "w.agency_id = #{conn.quote(@agency_filter_id)}" if @agency_filter_id.present?
        where_clauses << "w.agency_id = #{conn.quote(@agency_scope_id)}" if @agency_scope_active && @agency_scope_id.present?

        if @query.present?
          query_sql = conn.quote("%#{@query}%")
          query_clauses = [
            "w.full_name ILIKE #{query_sql}",
            "COALESCE(w.agency_name, '') ILIKE #{query_sql}"
          ]
          if @query.match?(/\A\d+\z/)
            query_id_sql = conn.quote(@query.to_i)
            query_clauses << "w.agent_id = #{query_id_sql}"
            query_clauses << "w.agency_id = #{query_id_sql}"
          end

          where_clauses << "(#{query_clauses.join(" OR ")})"
        end

        @agents = queries.fetch_directory_agents(
          where_sql: where_clauses.join(" AND "),
          sort_sql: sort_sql,
          sort_direction: sql_sort_direction_for_key,
          book_total_sql: book_total_sql,
          book_percentile_sql: book_percentile_sql,
          expiring_sql: expiring_sql
        )

        attach_top_clients_preview_for_agents!(book_total_sql: sql_client_book_total("sbw"))
        attach_top_teams_preview_for_agents!(book_total_sql: sql_client_book_total("sbw"))

        @agencies = []
      end
    end

    def attach_top_clients_preview_for_agents!(book_total_sql:)
      rows = Array(@agents)
      return if rows.empty?

      agent_ids = rows.map { |row| row["agent_id"].to_i }.select(&:positive?).uniq
      preview_rows = queries.fetch_index_top_clients_for_agents(
        agent_ids,
        limit_per_agent: 3,
        book_total_sql: book_total_sql
      )
      previews_by_agent = preview_rows.group_by { |row| row["agent_id"].to_i }

      rows.each do |row|
        row["top_clients_preview"] = Array(previews_by_agent[row["agent_id"].to_i]).map do |preview|
          {
            "player_id" => preview["player_id"],
            "player_name" => preview["player_name"],
            "team_code" => preview["team_code"],
            "is_two_way" => preview["is_two_way"],
            "book_total" => preview["book_total"]
          }
        end
      end
    end

    def attach_top_teams_preview_for_agents!(book_total_sql:)
      rows = Array(@agents)
      return if rows.empty?

      agent_ids = rows.map { |row| row["agent_id"].to_i }.select(&:positive?).uniq
      preview_rows = queries.fetch_index_top_teams_for_agents(
        agent_ids,
        limit_per_agent: 3,
        book_total_sql: book_total_sql
      )
      previews_by_agent = preview_rows.group_by { |row| row["agent_id"].to_i }

      rows.each do |row|
        row["top_teams_preview"] = Array(previews_by_agent[row["agent_id"].to_i]).map do |preview|
          {
            "team_id" => preview["team_id"],
            "team_code" => preview["team_code"],
            "player_count" => preview["player_count"],
            "book_total" => preview["book_total"]
          }
        end
      end
    end

    def build_sidebar_summary!
      rows = @directory_kind == "agencies" ? @agencies : @agents

      @sidebar_summary = {
        kind: @directory_kind,
        year: @book_year,
        query: @query,
        sort_key: @sort_key,
        sort_dir: @sort_dir,
        agency_filter_id: @agency_filter_id,
        agency_filter_name: active_agency_filter_name,
        row_count: rows.size,
        active_count: rows.count { |row| row["is_active"] != false },
        client_total: rows.sum { |row| row["client_count"].to_i },
        standard_total: rows.sum { |row| row["standard_count"].to_i },
        two_way_total: rows.sum { |row| row["two_way_count"].to_i },
        team_total: rows.sum { |row| row["team_count"].to_i },
        max_total: rows.sum { |row| row["max_contract_count"].to_i },
        expiring_total: rows.sum { |row| row["expiring_in_window"].to_i },
        restricted_total: rows.sum { |row| row["trade_restricted_count"].to_i },
        option_total: rows.sum { |row| row["player_option_count"].to_i + row["team_option_count"].to_i },
        book_total: rows.sum { |row| row["book_total"].to_i },
        agency_scope_active: @agency_scope_active,
        agency_scope_id: @agency_scope_id,
        agency_scope_name: active_agency_scope_name(rows),
        filters: sidebar_filter_labels,
        top_rows: sidebar_top_rows(rows)
      }
    end

    def sidebar_top_rows(rows)
      rows.first(14).map do |row|
        if @directory_kind == "agencies"
          {
            type: "agency",
            id: row["agency_id"],
            title: row["agency_name"],
            subtitle: "#{row['agent_count'].to_i} agents · #{row['client_count'].to_i} clients",
            book_total: row["book_total"].to_i,
            percentile: row["book_total_percentile"]
          }
        else
          {
            type: "agent",
            id: row["agent_id"],
            title: row["full_name"],
            subtitle: "#{row['client_count'].to_i} clients · #{row['team_count'].to_i} teams",
            book_total: row["book_total"].to_i,
            percentile: row["book_total_percentile"]
          }
        end
      end
    end

    def sidebar_filter_labels
      labels = []
      labels << %(Search: "#{@query}") if @query.present?
      labels << "Active only" if @active_only
      labels << "Certified only" if @certified_only && @directory_kind == "agents"
      labels << "With clients" if @with_clients
      labels << "With book" if @with_book
      labels << "With restrictions" if @with_restrictions
      labels << "With expirings" if @with_expiring
      if @agency_filter_id.present?
        labels << "Agency: #{active_agency_filter_name || "##{@agency_filter_id}"}"
      end
      labels << "Scoped to agency ##{@agency_scope_id}" if @agency_scope_active && @agency_scope_id.present?
      labels
    end

    def active_agency_filter_name
      return nil unless @agency_filter_id.present?

      @active_agency_filter_name ||= begin
        option_row = Array(@agency_filter_options).find { |row| row["agency_id"].to_i == @agency_filter_id }
        option_row&.dig("agency_name") || queries.fetch_agency_name(@agency_filter_id)
      end
    end

    def active_agency_scope_name(rows)
      return nil unless @directory_kind == "agents" && @agency_scope_active && @agency_scope_id.present?

      rows.find { |row| row["agency_id"].to_i == @agency_scope_id }&.dig("agency_name")
    end

    def parse_positive_integer(raw_value)
      parsed = Integer(raw_value, 10)
      parsed.positive? ? parsed : nil
    rescue ArgumentError, TypeError
      nil
    end

    def parse_overlay_agency_id_from_params
      return nil unless params[:selected_type].to_s.strip.downcase == "agency"

      parse_positive_integer(params[:selected_id])
    end

    def cast_bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def sql_book_total(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.cap_2026_total"
      when 2027 then "#{table_alias}.cap_2027_total"
      else "#{table_alias}.cap_2025_total"
      end
    end

    def sql_client_book_total(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.cap_2026"
      when 2027 then "#{table_alias}.cap_2027"
      else "#{table_alias}.cap_2025"
      end
    end

    def sql_book_percentile(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.cap_2026_total_percentile"
      when 2027 then "#{table_alias}.cap_2027_total_percentile"
      else "#{table_alias}.cap_2025_total_percentile"
      end
    end

    def sql_expiring_in_window(table_alias)
      case @book_year
      when 2026 then "#{table_alias}.expiring_2026"
      when 2027 then "#{table_alias}.expiring_2027"
      else "#{table_alias}.expiring_2025"
      end
    end

    def sql_sort_for_agents(book_total_sql:, expiring_sql:)
      case @sort_key
      when "clients" then "w.client_count"
      when "teams" then "w.team_count"
      when "max" then "w.max_contract_count"
      when "expirings" then expiring_sql
      when "options" then "(COALESCE(w.player_option_count, 0) + COALESCE(w.team_option_count, 0))"
      when "name" then "w.full_name"
      else book_total_sql
      end
    end

    def sql_sort_for_agencies(book_total_sql:, expiring_sql:)
      case @sort_key
      when "clients" then "w.client_count"
      when "agents" then "w.agent_count"
      when "teams" then "w.team_count"
      when "max" then "w.max_contract_count"
      when "expirings" then expiring_sql
      when "options" then "(COALESCE(w.player_option_count, 0) + COALESCE(w.team_option_count, 0))"
      when "name" then "w.agency_name"
      else book_total_sql
      end
    end

    def sql_sort_direction_for_key
      if @sort_key == "name"
        @sort_dir == "desc" ? "DESC" : "ASC"
      else
        @sort_dir == "asc" ? "ASC" : "DESC"
      end
    end
  end
end
