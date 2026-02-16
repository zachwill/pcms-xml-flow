class DraftSelectionsController < ApplicationController
  INDEX_ROUNDS = %w[all 1 2].freeze
  INDEX_SORTS = %w[provenance board trade].freeze
  INDEX_LENSES = %w[all with_trade deep_chain].freeze

  # GET /draft-selections
  def index
    load_index_workspace_state!
    hydrate_initial_overlay_from_params!
    render :index
  end

  # GET /draft-selections/pane
  def pane
    load_index_workspace_state!
    render partial: "draft_selections/workspace_main"
  end

  # GET /draft-selections/sidebar/base
  def sidebar_base
    load_index_workspace_state!
    render partial: "draft_selections/rightpanel_base"
  end

  # GET /draft-selections/sidebar/:id
  def sidebar
    transaction_id = normalize_required_transaction_id!(params[:id])

    render partial: "draft_selections/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(transaction_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /draft-selections/sidebar/clear
  def sidebar_clear
    render partial: "draft_selections/rightpanel_clear"
  end

  # GET /draft-selections/:slug
  def show
    resolve_draft_selection_from_slug!(params[:slug])
    return if performed?

    load_show_workspace_data!
    render :show
  end

  # GET /draft-selections/:id (numeric fallback)
  def redirect
    id = normalize_required_transaction_id!(params[:id])

    canonical = Slug.find_by(entity_type: "draft_selection", entity_id: id, canonical: true)
    if canonical
      redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
      return
    end

    row = queries.fetch_redirect_slug_seed(id)
    raise ActiveRecord::RecordNotFound unless row

    base_slug = build_redirect_slug_seed(id:, row: row)
    slug = build_unique_slug(base_slug, entity_type: "draft_selection")

    Slug.create!(entity_type: "draft_selection", entity_id: id, slug: slug, canonical: true)

    redirect_to draft_selection_path(slug), status: :moved_permanently
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::DraftSelectionQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_workspace_state!
    state = ::DraftSelections::IndexWorkspaceState.new(
      params: params,
      index_rounds: INDEX_ROUNDS,
      index_sorts: INDEX_SORTS,
      index_lenses: INDEX_LENSES
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def load_show_workspace_data!
    state = ::DraftSelections::ShowWorkspaceData.new(
      queries: queries,
      draft_selection_id: @draft_selection_id
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def resolve_draft_selection_from_slug!(raw_slug)
    slug = raw_slug.to_s.strip.downcase
    raise ActiveRecord::RecordNotFound if slug.blank?

    record = Slug.find_by!(entity_type: "draft_selection", slug: slug)

    canonical = Slug.find_by(entity_type: "draft_selection", entity_id: record.entity_id, canonical: true)
    if canonical && canonical.slug != record.slug
      redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
      return
    end

    @draft_selection_id = record.entity_id
    @draft_selection_slug = record.slug
  end

  def hydrate_initial_overlay_from_params!
    @initial_overlay_type = "none"
    @initial_overlay_id = ""
    @initial_overlay_partial = nil
    @initial_overlay_locals = {}

    requested_overlay_id = requested_overlay_id_param
    return if requested_overlay_id.blank?
    return unless selected_overlay_visible?(overlay_id: requested_overlay_id)

    @initial_overlay_partial = "draft_selections/rightpanel_overlay_selection"
    @initial_overlay_locals = load_sidebar_selection_payload(requested_overlay_id)
    @initial_overlay_type = "selection"
    @initial_overlay_id = requested_overlay_id.to_s
  rescue ActiveRecord::RecordNotFound
    @initial_overlay_type = "none"
    @initial_overlay_id = ""
    @initial_overlay_partial = nil
    @initial_overlay_locals = {}
  end

  def requested_overlay_id_param
    overlay_id = Integer(params[:selected_id], 10)
    overlay_id.positive? ? overlay_id : nil
  rescue ArgumentError, TypeError
    nil
  end

  def load_sidebar_selection_payload(transaction_id)
    ::DraftSelections::SidebarSelectionPayload.new(
      queries: queries,
      transaction_id: transaction_id
    ).build
  end

  def selected_overlay_visible?(overlay_id:)
    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    @results.any? { |row| row["transaction_id"].to_i == normalized_id }
  end

  def normalize_required_transaction_id!(raw)
    id = Integer(raw)
    raise ActiveRecord::RecordNotFound unless id.positive?

    id
  end

  def build_redirect_slug_seed(id:, row:)
    parts = [
      "draft",
      row["draft_year"],
      "r#{row['draft_round']}",
      "p#{row['pick_number']}",
      row["player_name"].to_s.parameterize.presence,
    ].compact

    base = parts.join("-")
    base = "draft-selection-#{id}" if base.blank?
    base
  end

  def build_unique_slug(base_slug, entity_type:)
    slug = base_slug
    i = 2

    while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: entity_type, slug: slug)
      slug = "#{base_slug}-#{i}"
      i += 1
    end

    slug
  end
end
