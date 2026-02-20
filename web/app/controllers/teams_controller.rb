class TeamsController < ApplicationController
  INDEX_SALARY_YEAR = 2025

  INDEX_CONFERENCE_LENSES = {
    "ALL" => nil,
    "Eastern" => "Eastern",
    "Western" => "Western"
  }.freeze

  INDEX_PRESSURE_LENSES = %w[all over_cap over_tax over_apron1 over_apron2].freeze

  INDEX_PRESSURE_SECTION_DEFINITIONS = [
    {
      key: "over_apron2",
      title: "Apron 2 red zone",
      subtitle: "Most restrictive pressure posture"
    },
    {
      key: "over_apron1",
      title: "Apron 1 pressure",
      subtitle: "Above apron line, below second apron"
    },
    {
      key: "over_tax",
      title: "Tax pressure",
      subtitle: "Taxpayer but under apron lines"
    },
    {
      key: "over_cap",
      title: "Over cap runway",
      subtitle: "Over cap, under tax"
    },
    {
      key: "under_cap",
      title: "Under cap flex",
      subtitle: "Cap-space preserving posture"
    }
  ].freeze

  INDEX_SORT_SQL = {
    "pressure_desc" => "pressure_rank DESC, COALESCE(tsw.room_under_apron2, 0) ASC, COALESCE(tsw.room_under_apron1, 0) ASC, COALESCE(tsw.room_under_tax, 0) ASC, t.team_code ASC",
    "cap_space_asc" => "(COALESCE(tsw.salary_cap_amount, 0) - COALESCE(tsw.cap_total_hold, 0)) ASC, t.team_code ASC",
    "tax_room_asc" => "COALESCE(tsw.room_under_tax, 0) ASC, t.team_code ASC",
    "team_asc" => "t.team_code ASC"
  }.freeze

  # GET /teams
  def index
    load_index_workspace_state!
    load_index_overlay_state!
    render :index
  end

  # GET /teams/pane
  def pane
    load_index_workspace_state!
    render partial: "teams/workspace_main"
  end

  # GET /teams/sidebar/:id
  def sidebar
    team_id = Integer(params[:id])
    load_index_team_row!(team_id)

    render partial: "teams/rightpanel_overlay_team", locals: { team_row: @sidebar_team_row }
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /teams/sidebar/clear
  def sidebar_clear
    render partial: "teams/rightpanel_clear"
  end

  # GET /teams/:slug
  # Canonical route.
  def show
    @defer_heavy_load = params[:full].to_s != "1"

    resolve_team_from_slug!(params[:slug])
    return if performed?

    load_team_show_workspace_data!

    render :show
  end

  # GET /teams/:id (numeric fallback)
  def redirect
    id = Integer(params[:id])

    canonical = Slug.find_by(entity_type: "team", entity_id: id, canonical: true)
    if canonical
      redirect_to team_path(canonical.slug), status: :moved_permanently
      return
    end

    row = queries.fetch_team_for_redirect(id)
    raise ActiveRecord::RecordNotFound unless row

    base = row["team_code"].to_s.strip.downcase
    base = row["team_name"].to_s.parameterize if base.blank?
    base = "team-#{id}" if base.blank?

    slug = base
    i = 2
    while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "team", slug: slug)
      slug = "#{base}-#{i}"
      i += 1
    end

    Slug.create!(entity_type: "team", entity_id: id, slug: slug, canonical: true)

    redirect_to team_path(slug), status: :moved_permanently
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::TeamQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_workspace_state!(apply_compare_action: false)
    state = ::Teams::IndexWorkspaceState.new(
      params: params,
      request_query_parameters: request.query_parameters,
      queries: queries,
      index_salary_year: INDEX_SALARY_YEAR,
      conference_lenses: INDEX_CONFERENCE_LENSES,
      pressure_lenses: INDEX_PRESSURE_LENSES,
      pressure_section_definitions: INDEX_PRESSURE_SECTION_DEFINITIONS,
      sort_sql: INDEX_SORT_SQL
    ).build(apply_compare_action: apply_compare_action)

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def load_index_team_row!(team_id)
    @sidebar_team_row = fetch_index_team_row(team_id)
    raise ActiveRecord::RecordNotFound unless @sidebar_team_row
  end

  def load_index_overlay_state!
    @sidebar_team_row = nil

    selected_id = @selected_team_id.to_i
    if selected_id <= 0 || !selected_overlay_visible?(overlay_id: selected_id)
      @selected_team_id = nil
      return
    end

    load_index_team_row!(selected_id)
    @selected_team_id = selected_id
  rescue ActiveRecord::RecordNotFound
    @sidebar_team_row = nil
    @selected_team_id = nil
  end

  def fetch_index_team_row(team_id)
    queries.fetch_index_team_row(team_id: team_id, year: INDEX_SALARY_YEAR)
  end

  def selected_overlay_visible?(overlay_id:)
    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    Array(@teams).any? { |row| row["team_id"].to_i == normalized_id }
  end

  def resolve_team_from_slug!(raw_slug, redirect_on_canonical_miss: true)
    slug = raw_slug.to_s.strip.downcase
    raise ActiveRecord::RecordNotFound if slug.blank?

    # Teams are special: team_code is stable + guessable.
    # If we don't have a slug record yet, try to bootstrap it from pcms.teams.
    record = Slug.find_by(entity_type: "team", slug: slug)
    record ||= bootstrap_team_slug_from_code!(slug)

    canonical = Slug.find_by(entity_type: "team", entity_id: record.entity_id, canonical: true)
    if canonical && canonical.slug != record.slug
      if redirect_on_canonical_miss
        redirect_to team_path(canonical.slug), status: :moved_permanently
        return
      end

      record = canonical
    end

    @team_id = record.entity_id
    @team_slug = record.slug

    @team = queries.fetch_team_by_id(@team_id)
    raise ActiveRecord::RecordNotFound unless @team
  end

  def load_team_show_workspace_data!
    state = ::Teams::ShowWorkspaceData.new(
      queries: queries,
      team: @team,
      team_id: @team_id,
      index_salary_year: INDEX_SALARY_YEAR
    ).build(defer_heavy_load: @defer_heavy_load)

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def bootstrap_team_slug_from_code!(slug)
    code = slug.to_s.strip.upcase
    raise ActiveRecord::RecordNotFound if Slug.reserved_slug?(slug)
    raise ActiveRecord::RecordNotFound unless code.match?(/\A[A-Z]{3}\z/)

    row = queries.fetch_team_id_by_code(code)
    raise ActiveRecord::RecordNotFound unless row

    team_id = row["team_id"]

    # If another team already owns this slug, don't overwrite.
    existing = Slug.find_by(entity_type: "team", slug: slug)
    return existing if existing

    canonical = Slug.find_by(entity_type: "team", entity_id: team_id, canonical: true)
    return canonical if canonical

    Slug.create!(entity_type: "team", entity_id: team_id, slug: slug, canonical: true)
  end
end
