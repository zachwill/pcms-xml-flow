class DraftSelectionsController < ApplicationController
  INDEX_ROUNDS = %w[all 1 2].freeze
  INDEX_SORTS = %w[provenance board trade].freeze
  INDEX_LENSES = %w[all with_trade deep_chain].freeze

  SEVERITY_LANE_ORDER = %w[deep_chain with_trade clean].freeze
  SEVERITY_LANE_META = {
    "deep_chain" => {
      headline: "Contested · Deep chain",
      subline: "P2+ ownership chain (2+ provenance trades)"
    },
    "with_trade" => {
      headline: "Contested · With trade",
      subline: "Single-link contest signal (direct trade or P1)"
    },
    "clean" => {
      headline: "Clean ownership",
      subline: "No trade-linked provenance signal"
    }
  }.freeze

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

    build_severity_grouping_payload!
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

  def build_severity_grouping_payload!
    rows = Array(@results)

    row_rank_lookup = {}
    grouped_rows = Hash.new { |hash, key| hash[key] = [] }

    rows.each_with_index do |row, index|
      row_id = row["transaction_id"].to_s
      row_rank_lookup[row_id] = index + 1 if row_id.present?

      severity = normalize_provenance_severity(row["provenance_severity"])
      grouped_rows[severity] << row
    end

    severity_counts = normalized_severity_counts(@sidebar_summary)
    contested_count = severity_counts.fetch("with_trade", 0) + severity_counts.fetch("deep_chain", 0)

    lens_focus = severity_lens_focus_payload(@lens)

    @workspace_severity_snapshot = {
      clean_count: severity_counts.fetch("clean", 0),
      with_trade_count: severity_counts.fetch("with_trade", 0),
      deep_chain_count: severity_counts.fetch("deep_chain", 0),
      contested_count: contested_count,
      total_count: rows.size,
      lens_label: lens_focus[:label],
      lens_focus: lens_focus
    }

    @workspace_severity_lanes = SEVERITY_LANE_ORDER.filter_map do |severity_key|
      lane_rows = grouped_rows.fetch(severity_key, [])
      next if lane_rows.empty?

      lane_meta = SEVERITY_LANE_META.fetch(severity_key)
      {
        key: severity_key,
        headline: lane_meta[:headline],
        subline: lane_meta[:subline],
        row_count: lane_rows.size,
        rows: lane_rows
      }
    end

    @workspace_row_rank_lookup = row_rank_lookup
  end

  def normalized_severity_counts(summary)
    summary_hash = summary.is_a?(Hash) ? summary : {}
    severity_counts = summary_hash[:severity_counts].is_a?(Hash) ? summary_hash[:severity_counts] : {}

    {
      "clean" => severity_counts.fetch("clean", summary_hash[:clean_count].to_i).to_i,
      "with_trade" => severity_counts.fetch("with_trade", summary_hash[:with_trade_count].to_i).to_i,
      "deep_chain" => severity_counts.fetch("deep_chain", summary_hash[:deep_chain_count].to_i).to_i
    }
  end

  def normalize_provenance_severity(raw)
    severity = raw.to_s
    return severity if SEVERITY_LANE_ORDER.include?(severity)

    "clean"
  end

  def severity_lens_focus_payload(raw_lens)
    case raw_lens.to_s
    when "with_trade"
      {
        key: "with_trade",
        label: "Contested lanes only",
        note: "Clean lane excluded; contested rows stay in scope."
      }
    when "deep_chain"
      {
        key: "deep_chain",
        label: "Deep-contested lane only",
        note: "Only deep-chain rows (P2+) remain in scope."
      }
    else
      {
        key: "all",
        label: "All severity lanes",
        note: "Clean and contested rows are both in scope."
      }
    end
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
