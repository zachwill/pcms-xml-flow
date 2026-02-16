class AgenciesController < ApplicationController
  BOOK_YEARS = [2025, 2026, 2027].freeze
  ACTIVITY_LENSES = %w[all active inactive inactive_live_book live_book_risk].freeze
  SORT_KEYS = %w[book clients agents teams max expirings options name].freeze
  AGENT_LENS_SORT_KEYS = %w[book clients teams max expirings options name].freeze
  SHOW_COHORT_FILTERS = %w[max expiring restricted option_heavy].freeze

  helper_method :agents_lens_pivot_href, :agents_lens_pivot_sort_key

  # GET /agencies
  def index
    load_index_workspace_state!
    render :index
  end

  # GET /agencies/pane
  # Datastar patch target for main canvas only.
  def pane
    load_index_workspace_state!
    render partial: "agencies/workspace_main"
  end

  # GET /agencies/sidebar/base
  def sidebar_base
    load_index_workspace_state!
    render partial: "agencies/rightpanel_base"
  end

  # GET /agencies/sidebar/:id
  def sidebar
    setup_index_filters!

    agency_id = Integer(params[:id])
    render partial: "agencies/rightpanel_overlay_agency", locals: load_sidebar_agency_payload(agency_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /agencies/sidebar/clear
  def sidebar_clear
    render partial: "agencies/rightpanel_clear"
  end

  # GET /agencies/:slug
  # Canonical route.
  def show
    slug = params[:slug].to_s.strip.downcase
    raise ActiveRecord::RecordNotFound if slug.blank?

    record = Slug.find_by!(entity_type: "agency", slug: slug)

    canonical = Slug.find_by(entity_type: "agency", entity_id: record.entity_id, canonical: true)
    if canonical && canonical.slug != record.slug
      redirect_to agency_path(canonical.slug, **request.query_parameters), status: :moved_permanently
      return
    end

    @agency_id = record.entity_id
    @agency_slug = record.slug
    load_show_cohort_filters!

    conn = ActiveRecord::Base.connection
    id_sql = conn.quote(@agency_id)

    @agency = conn.exec_query(<<~SQL).first
      SELECT agency_id, agency_name, is_active
      FROM pcms.agencies
      WHERE agency_id = #{id_sql}
      LIMIT 1
    SQL
    raise ActiveRecord::RecordNotFound unless @agency

    @agents = conn.exec_query(<<~SQL).to_a
      SELECT
        ag.agent_id,
        ag.full_name,
        ag.is_active,
        COALESCE(w.client_count, 0)::integer AS client_count,
        COALESCE(w.cap_2025_total, 0)::bigint AS cap_2025_total,
        COALESCE(w.total_salary_from_2025, 0)::bigint AS total_salary_from_2025
      FROM pcms.agents ag
      LEFT JOIN pcms.agents_warehouse w
        ON w.agent_id = ag.agent_id
      WHERE ag.agency_id = #{id_sql}
      ORDER BY w.cap_2025_total DESC NULLS LAST, ag.full_name
    SQL

    @agency_rollup = conn.exec_query(<<~SQL).first || {}
      SELECT
        agent_count,
        client_count,
        team_count,
        cap_2025_total,
        total_salary_from_2025,
        two_way_count,
        min_contract_count,
        max_contract_count,
        rookie_scale_count,
        no_trade_count,
        trade_kicker_count,
        trade_restricted_count,
        expiring_2025,
        expiring_2026,
        expiring_2027,
        player_option_count,
        team_option_count,
        prior_year_nba_now_free_agent_count,
        agent_count_percentile,
        client_count_percentile,
        cap_2025_total_percentile
      FROM pcms.agencies_warehouse
      WHERE agency_id = #{id_sql}
      LIMIT 1
    SQL

    @team_distribution = conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.team_code,
        t.team_id,
        t.team_name,
        COUNT(sbw.player_id)::integer AS client_count,
        COALESCE(SUM(sbw.cap_2025), 0)::bigint AS cap_2025_total
      FROM pcms.agents ag
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.agent_id = ag.agent_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE ag.agency_id = #{id_sql}
      GROUP BY sbw.team_code, t.team_id, t.team_name
      ORDER BY cap_2025_total DESC NULLS LAST, sbw.team_code
      LIMIT 12
    SQL

    @clients = conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        ag.full_name AS agent_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.cap_2026::numeric AS cap_2026,
        sbw.cap_2027::numeric AS cap_2027,
        sbw.cap_2028::numeric AS cap_2028,
        sbw.cap_2029::numeric AS cap_2029,
        sbw.cap_2030::numeric AS cap_2030,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        sbw.pct_cap_2025,
        COALESCE(sbw.is_two_way, false)::boolean AS is_two_way,
        COALESCE(sbw.is_no_trade, false)::boolean AS is_no_trade,
        COALESCE(sbw.is_trade_bonus, false)::boolean AS is_trade_bonus,
        COALESCE(sbw.is_trade_restricted_now, false)::boolean AS is_trade_restricted_now,
        sbw.option_2025,
        sbw.option_2026,
        sbw.option_2027,
        sbw.option_2028
      FROM pcms.agents ag
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.agent_id = ag.agent_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE ag.agency_id = #{id_sql}
      ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
    SQL

    @client_yearly_footprint = conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sby.salary_year,
        sby.cap_amount::numeric AS cap_amount,
        sby.tax_amount::numeric AS tax_amount,
        sby.apron_amount::numeric AS apron_amount
      FROM pcms.agents ag
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.agent_id = ag.agent_id
      JOIN pcms.salary_book_yearly sby
        ON sby.player_id = sbw.player_id
      WHERE ag.agency_id = #{id_sql}
        AND sby.salary_year BETWEEN 2025 AND 2030
      ORDER BY sby.salary_year, sbw.player_id
    SQL

    render :show
  end

  # GET /agencies/:id (numeric fallback)
  def redirect
    id = Integer(params[:id])

    canonical = Slug.find_by(entity_type: "agency", entity_id: id, canonical: true)
    if canonical
      redirect_to agency_path(canonical.slug), status: :moved_permanently
      return
    end

    conn = ActiveRecord::Base.connection
    id_sql = conn.quote(id)

    row = conn.exec_query(<<~SQL).first
      SELECT agency_name
      FROM pcms.agencies
      WHERE agency_id = #{id_sql}
      LIMIT 1
    SQL
    raise ActiveRecord::RecordNotFound unless row

    base = row["agency_name"].to_s.parameterize
    base = "agency-#{id}" if base.blank?

    slug = base
    i = 2
    while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "agency", slug: slug)
      slug = "#{base}-#{i}"
      i += 1
    end

    Slug.create!(entity_type: "agency", entity_id: id, slug: slug, canonical: true)

    redirect_to agency_path(slug), status: :moved_permanently
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def agents_lens_pivot_href(agency_id)
    agency_id = agency_id.to_i
    agency_id = nil unless agency_id.positive?

    query = {
      kind: "agents",
      year: agents_lens_pivot_year,
      sort: agents_lens_pivot_sort_key,
      dir: agents_lens_pivot_sort_dir,
      agency_scope: 1,
      agency_scope_id: agency_id
    }.compact

    "/agents?#{query.to_query}"
  end

  def agents_lens_pivot_sort_key
    sort_key = @sort_key.to_s
    AGENT_LENS_SORT_KEYS.include?(sort_key) ? sort_key : "book"
  end

  private

  def load_show_cohort_filters!
    @show_cohort_filters = normalize_show_cohort_filters(params[:cohorts])
  end

  def normalize_show_cohort_filters(raw_filters)
    tokens = Array(raw_filters)
    tokens = [raw_filters] if tokens.empty?

    tokens
      .flat_map { |value| value.to_s.split(",") }
      .map { |value| value.to_s.strip.downcase.tr("-", "_") }
      .reject(&:blank?)
      .select { |value| SHOW_COHORT_FILTERS.include?(value) }
      .uniq
  end

  def load_index_workspace_state!
    setup_index_filters!
    load_index_rows!
    build_sidebar_summary!
  end

  def agents_lens_pivot_year
    year = @book_year.to_i
    BOOK_YEARS.include?(year) ? year : BOOK_YEARS.first
  end

  def agents_lens_pivot_sort_dir
    @sort_dir.to_s == "asc" ? "asc" : "desc"
  end

  def setup_index_filters!
    @query = params[:q].to_s.strip

    requested_activity = params[:activity].to_s.strip
    @activity_lens = ACTIVITY_LENSES.include?(requested_activity) ? requested_activity : "all"

    year = begin
      Integer(params[:year])
    rescue ArgumentError, TypeError
      nil
    end
    @book_year = BOOK_YEARS.include?(year) ? year : BOOK_YEARS.first

    requested_sort = params[:sort].to_s.strip
    @sort_key = SORT_KEYS.include?(requested_sort) ? requested_sort : "book"

    @sort_dir = params[:dir].to_s == "asc" ? "asc" : "desc"
  end

  def load_index_rows!
    conn = ActiveRecord::Base.connection
    book_total_sql = sql_book_total("w")
    book_percentile_sql = sql_book_percentile("w")
    expiring_sql = sql_expiring_in_window("w")
    where_clauses = ["1 = 1"]

    case @activity_lens
    when "active"
      where_clauses << "COALESCE(w.is_active, true) = true"
    when "inactive"
      where_clauses << "COALESCE(w.is_active, true) = false"
    when "inactive_live_book"
      where_clauses << "COALESCE(w.is_active, true) = false"
      where_clauses << "COALESCE(#{book_total_sql}, 0) > 0"
    when "live_book_risk"
      where_clauses << "COALESCE(#{book_total_sql}, 0) > 0"
      where_clauses << "#{sql_restrictions_total('w')} > 0"
    end

    if @query.present?
      query_sql = conn.quote("%#{@query}%")
      if @query.match?(/\A\d+\z/)
        where_clauses << "(w.agency_name ILIKE #{query_sql} OR w.agency_id = #{conn.quote(@query.to_i)})"
      else
        where_clauses << "w.agency_name ILIKE #{query_sql}"
      end
    end

    sort_sql = sql_sort_for_agencies(book_total_sql:, expiring_sql:)

    @agencies = conn.exec_query(<<~SQL).to_a
      SELECT
        w.agency_id,
        w.agency_name,
        w.is_active,

        COALESCE(w.agent_count, 0)::integer AS agent_count,
        COALESCE(w.client_count, 0)::integer AS client_count,
        COALESCE(w.standard_count, 0)::integer AS standard_count,
        COALESCE(w.two_way_count, 0)::integer AS two_way_count,
        COALESCE(w.team_count, 0)::integer AS team_count,

        COALESCE(#{book_total_sql}, 0)::bigint AS book_total,
        #{book_percentile_sql} AS book_total_percentile,
        COALESCE(w.cap_2025_total, 0)::bigint AS cap_2025_total,
        COALESCE(w.cap_2026_total, 0)::bigint AS cap_2026_total,
        COALESCE(w.cap_2027_total, 0)::bigint AS cap_2027_total,
        COALESCE(w.total_salary_from_2025, 0)::bigint AS total_salary_from_2025,

        COALESCE(w.max_contract_count, 0)::integer AS max_contract_count,
        COALESCE(w.rookie_scale_count, 0)::integer AS rookie_scale_count,
        COALESCE(w.min_contract_count, 0)::integer AS min_contract_count,

        COALESCE(w.no_trade_count, 0)::integer AS no_trade_count,
        COALESCE(w.trade_kicker_count, 0)::integer AS trade_kicker_count,
        COALESCE(w.trade_restricted_count, 0)::integer AS trade_restricted_count,

        COALESCE(#{expiring_sql}, 0)::integer AS expiring_in_window,
        COALESCE(w.expiring_2025, 0)::integer AS expiring_2025,
        COALESCE(w.expiring_2026, 0)::integer AS expiring_2026,
        COALESCE(w.expiring_2027, 0)::integer AS expiring_2027,

        COALESCE(w.player_option_count, 0)::integer AS player_option_count,
        COALESCE(w.team_option_count, 0)::integer AS team_option_count,

        w.agent_count_percentile,
        w.client_count_percentile,
        w.max_contract_count_percentile
      FROM pcms.agencies_warehouse w
      WHERE #{where_clauses.join(" AND ")}
      ORDER BY #{sort_sql} #{sql_sort_direction_for_key} NULLS LAST,
               w.agency_name ASC
      LIMIT 260
    SQL
  end

  def build_sidebar_summary!
    rows = Array(@agencies)

    @sidebar_summary = {
      year: @book_year,
      query: @query,
      activity_lens: @activity_lens,
      sort_key: @sort_key,
      sort_dir: @sort_dir,
      row_count: rows.size,
      active_count: rows.count { |row| row["is_active"] != false },
      inactive_count: rows.count { |row| row["is_active"] == false },
      live_book_count: rows.count { |row| row["book_total"].to_i.positive? },
      inactive_live_book_count: rows.count { |row| row["is_active"] == false && row["book_total"].to_i.positive? },
      live_book_risk_count: rows.count { |row| row["book_total"].to_i.positive? && row_restrictions_total(row).positive? },
      agent_total: rows.sum { |row| row["agent_count"].to_i },
      client_total: rows.sum { |row| row["client_count"].to_i },
      team_total: rows.sum { |row| row["team_count"].to_i },
      max_total: rows.sum { |row| row["max_contract_count"].to_i },
      expiring_total: rows.sum { |row| row["expiring_in_window"].to_i },
      restricted_total: rows.sum { |row| row_restrictions_total(row) },
      option_total: rows.sum { |row| row["player_option_count"].to_i + row["team_option_count"].to_i },
      book_total: rows.sum { |row| row["book_total"].to_i },
      filters: sidebar_filter_labels,
      top_rows: sidebar_top_rows(rows)
    }
  end

  def sidebar_filter_labels
    labels = []
    labels << %(Search: "#{@query}") if @query.present?
    labels << "Posture: #{activity_lens_label(@activity_lens)}" unless @activity_lens == "all"
    labels << "Sort: #{@sort_key.humanize} #{@sort_dir.upcase}" unless @sort_key == "book" && @sort_dir == "desc"
    labels
  end

  def sidebar_top_rows(rows)
    rows.first(14).map do |row|
      posture_tokens = []
      posture_tokens << "inactive + live" if row["is_active"] == false && row["book_total"].to_i.positive?
      posture_tokens << "#{row_restrictions_total(row)} restrictions" if row_restrictions_total(row).positive?

      {
        id: row["agency_id"],
        title: row["agency_name"],
        subtitle: [
          "#{row['agent_count'].to_i} agents · #{row['client_count'].to_i} clients",
          posture_tokens.join(" · ").presence
        ].compact.join(" · "),
        book_total: row["book_total"].to_i,
        percentile: row["book_total_percentile"]
      }
    end
  end

  def selected_overlay_visible?(overlay_id:)
    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    @agencies.any? { |row| row["agency_id"].to_i == normalized_id }
  end

  def load_sidebar_agency_payload(agency_id)
    conn = ActiveRecord::Base.connection
    id_sql = conn.quote(agency_id)

    agency = conn.exec_query(<<~SQL).first
      SELECT
        w.agency_id,
        w.agency_name,
        w.is_active,
        w.agent_count,
        w.client_count,
        w.standard_count,
        w.two_way_count,
        w.team_count,
        w.cap_2025_total,
        w.cap_2026_total,
        w.cap_2027_total,
        w.total_salary_from_2025,
        w.max_contract_count,
        w.rookie_scale_count,
        w.min_contract_count,
        w.no_trade_count,
        w.trade_kicker_count,
        w.trade_restricted_count,
        w.expiring_2025,
        w.expiring_2026,
        w.expiring_2027,
        w.player_option_count,
        w.team_option_count,
        w.prior_year_nba_now_free_agent_count,
        w.cap_2025_total_percentile,
        w.cap_2026_total_percentile,
        w.cap_2027_total_percentile,
        w.client_count_percentile,
        w.max_contract_count_percentile,
        w.agent_count_percentile
      FROM pcms.agencies_warehouse w
      WHERE w.agency_id = #{id_sql}
      LIMIT 1
    SQL
    raise ActiveRecord::RecordNotFound unless agency

    top_agents = conn.exec_query(<<~SQL).to_a
      SELECT
        w.agent_id,
        w.full_name,
        w.client_count,
        w.team_count,
        w.cap_2025_total,
        w.cap_2025_total_percentile,
        w.client_count_percentile,
        w.max_contract_count,
        w.expiring_2025
      FROM pcms.agents_warehouse w
      WHERE w.agency_id = #{id_sql}
      ORDER BY w.cap_2025_total DESC NULLS LAST, w.full_name
      LIMIT 60
    SQL

    top_clients = conn.exec_query(<<~SQL).to_a
      SELECT
        sbw.player_id,
        sbw.player_name,
        sbw.team_code,
        t.team_id,
        t.team_name,
        sbw.agent_id,
        a.full_name AS agent_name,
        sbw.cap_2025::numeric AS cap_2025,
        sbw.total_salary_from_2025::numeric AS total_salary_from_2025,
        COALESCE(sbw.is_two_way, false)::boolean AS is_two_way
      FROM pcms.agents a
      JOIN pcms.salary_book_warehouse sbw
        ON sbw.agent_id = a.agent_id
      LEFT JOIN pcms.teams t
        ON t.team_code = sbw.team_code
       AND t.league_lk = 'NBA'
      WHERE a.agency_id = #{id_sql}
      ORDER BY sbw.cap_2025 DESC NULLS LAST, sbw.player_name
      LIMIT 80
    SQL

    {
      agency:,
      top_agents:,
      top_clients:
    }
  end

  def sql_restrictions_total(table_alias)
    "(COALESCE(#{table_alias}.no_trade_count, 0) + " \
      "COALESCE(#{table_alias}.trade_kicker_count, 0) + " \
      "COALESCE(#{table_alias}.trade_restricted_count, 0))"
  end

  def row_restrictions_total(row)
    row["no_trade_count"].to_i + row["trade_kicker_count"].to_i + row["trade_restricted_count"].to_i
  end

  def sql_book_total(table_alias)
    case @book_year
    when 2026 then "#{table_alias}.cap_2026_total"
    when 2027 then "#{table_alias}.cap_2027_total"
    else "#{table_alias}.cap_2025_total"
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

  def activity_lens_label(activity_lens)
    case activity_lens
    when "active"
      "Active"
    when "inactive"
      "Inactive"
    when "inactive_live_book"
      "Inactive + live book"
    when "live_book_risk"
      "Live book risk"
    else
      "All"
    end
  end
end
