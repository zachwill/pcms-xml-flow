class AgentsController < ApplicationController
  BOOK_YEARS = [2025, 2026, 2027].freeze
  AGENT_SORT_KEYS = %w[book clients teams max expirings options name].freeze
  AGENCY_SORT_KEYS = %w[book clients agents teams max expirings options name].freeze
  OVERLAY_TYPES = %w[agent agency].freeze
  SHOW_COHORT_FILTERS = %w[max expiring restricted two_way].freeze

  # GET /agents
  def index
    load_directory_workspace_state!

    render :index
  end

  # GET /agents/pane
  # Datastar patch target for main canvas only.
  def pane
    load_directory_workspace_state!

    render partial: "agents/workspace_main"
  end

  # GET /agents/sidebar/base
  def sidebar_base
    load_directory_workspace_state!

    render partial: "agents/rightpanel_base"
  end

  # GET /agents/sidebar/agent/:id
  def sidebar_agent
    agent_id = Integer(params[:id])
    render partial: "agents/rightpanel_overlay_agent", locals: load_sidebar_agent_payload(agent_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /agents/sidebar/agency/:id
  def sidebar_agency
    agency_id = Integer(params[:id])
    render partial: "agents/rightpanel_overlay_agency", locals: load_sidebar_agency_payload(agency_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /agents/sidebar/clear
  def sidebar_clear
    render partial: "agents/rightpanel_clear"
  end

  # GET /agents/:slug
  # Canonical route.
  def show
    slug = params[:slug].to_s.strip.downcase
    raise ActiveRecord::RecordNotFound if slug.blank?

    record = Slug.find_by!(entity_type: "agent", slug: slug)

    canonical = Slug.find_by(entity_type: "agent", entity_id: record.entity_id, canonical: true)
    if canonical && canonical.slug != record.slug
      redirect_to agent_path(canonical.slug, **request.query_parameters), status: :moved_permanently
      return
    end

    @agent_id = record.entity_id
    @agent_slug = record.slug
    load_show_cohort_filters!

    state = ::Agents::ShowWorkspaceData.new(
      queries: queries,
      agent_id: @agent_id
    ).build
    state.each { |key, value| instance_variable_set("@#{key}", value) }

    render :show
  end

  # GET /agents/:id (numeric fallback)
  def redirect
    id = Integer(params[:id])

    canonical = Slug.find_by(entity_type: "agent", entity_id: id, canonical: true)
    if canonical
      redirect_to agent_path(canonical.slug), status: :moved_permanently
      return
    end

    row = queries.fetch_agent_name_for_redirect(id)
    raise ActiveRecord::RecordNotFound unless row

    base = row["full_name"].to_s.parameterize
    base = "agent-#{id}" if base.blank?

    slug = base
    i = 2
    while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "agent", slug: slug)
      slug = "#{base}-#{i}"
      i += 1
    end

    Slug.create!(entity_type: "agent", entity_id: id, slug: slug, canonical: true)

    redirect_to agent_path(slug), status: :moved_permanently
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::AgentQueries.new(connection: ActiveRecord::Base.connection)
  end

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

  def load_directory_workspace_state!
    state = ::Agents::DirectoryWorkspaceState.new(
      params: params,
      queries: queries,
      book_years: BOOK_YEARS,
      agent_sort_keys: AGENT_SORT_KEYS,
      agency_sort_keys: AGENCY_SORT_KEYS
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def selected_overlay_visible?(overlay_type:, overlay_id:)
    normalized_type = overlay_type.to_s
    return false unless OVERLAY_TYPES.include?(normalized_type)

    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    case normalized_type
    when "agent"
      agent_overlay_visible_in_scope?(normalized_id)
    when "agency"
      agency_overlay_visible_in_scope?(normalized_id)
    else
      false
    end
  end

  def agent_overlay_visible_in_scope?(agent_id)
    if @directory_kind == "agents"
      @agents.any? { |row| row["agent_id"].to_i == agent_id }
    else
      agency_id = agency_id_for_agent(agent_id)
      agency_id.present? && visible_agency_ids.include?(agency_id)
    end
  end

  def agency_overlay_visible_in_scope?(agency_id)
    return true if @directory_kind == "agents" && @agency_scope_active && @agency_scope_id.present? && @agency_scope_id == agency_id

    visible_agency_ids.include?(agency_id)
  end

  def visible_agency_ids
    @visible_agency_ids ||= begin
      rows = @directory_kind == "agencies" ? @agencies : @agents
      rows.map { |row| row["agency_id"].to_i }.select(&:positive?)
    end
  end

  def agency_id_for_agent(agent_id)
    @agency_ids_by_agent_id ||= {}
    return @agency_ids_by_agent_id[agent_id] if @agency_ids_by_agent_id.key?(agent_id)

    row = queries.fetch_agency_id_for_agent(agent_id)
    resolved_id = row&.dig("agency_id").to_i
    @agency_ids_by_agent_id[agent_id] = resolved_id.positive? ? resolved_id : nil
  end

  def load_sidebar_agent_payload(agent_id)
    agent = queries.fetch_sidebar_agent(agent_id)
    raise ActiveRecord::RecordNotFound unless agent

    clients = queries.fetch_sidebar_agent_clients(agent_id)

    {
      agent:,
      clients:
    }
  end

  def load_sidebar_agency_payload(agency_id)
    agency = queries.fetch_sidebar_agency(agency_id)
    raise ActiveRecord::RecordNotFound unless agency

    top_agents = queries.fetch_sidebar_agency_top_agents(agency_id)
    top_clients = queries.fetch_sidebar_agency_top_clients(agency_id)

    {
      agency:,
      top_agents:,
      top_clients:
    }
  end
end
