class DraftsController < ApplicationController
  INDEX_VIEWS = %w[picks selections grid].freeze
  INDEX_ROUNDS = %w[all 1 2].freeze
  INDEX_SORTS = %w[board risk provenance].freeze
  INDEX_LENSES = %w[all at_risk critical].freeze

  # GET /drafts
  # Unified workspace for draft picks (future assets), draft selections (historical),
  # and pick grid (team × year × round ownership matrix).
  def index
    load_index_state!
    assign_state!(overlay_state.initial_overlay_state)
    render :index
  end

  # GET /drafts/pane (Datastar partial refresh)
  def pane
    load_index_state!
    render partial: "drafts/results"
  end

  # GET /drafts/sidebar/base
  def sidebar_base
    load_index_state!
    render partial: "drafts/rightpanel_base"
  end

  # GET /drafts/sidebar/pick?team=XXX&year=YYYY&round=R
  def sidebar_pick
    team_code = normalize_team_code_param(params[:team])
    year = normalize_year_param(params[:year])
    round = normalize_round_param(params[:round])

    raise ActiveRecord::RecordNotFound if team_code.blank? || year.nil? || round.nil?

    render partial: "drafts/rightpanel_overlay_pick", locals: load_sidebar_pick_payload(
      team_code: team_code,
      draft_year: year,
      draft_round: round
    )
  end

  # GET /drafts/sidebar/selection/:id
  def sidebar_selection
    transaction_id = normalize_required_id!(params[:id])
    render partial: "drafts/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(transaction_id)
  end

  # GET /drafts/sidebar/clear
  def sidebar_clear
    render partial: "drafts/rightpanel_clear"
  end

  private

  def assign_state!(state)
    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def queries
    @queries ||= ::DraftQueries.new(connection: ActiveRecord::Base.connection)
  end

  def overlay_state
    ::Drafts::OverlayState.new(
      params: params,
      view: @view,
      results: @results,
      grid_data: @grid_data,
      queries: queries
    )
  end

  def load_index_state!
    assign_state!(
      ::Drafts::IndexWorkspaceState.new(
        params: params,
        queries: queries,
        index_views: INDEX_VIEWS,
        index_rounds: INDEX_ROUNDS,
        index_sorts: INDEX_SORTS,
        index_lenses: INDEX_LENSES
      ).build
    )
  end

  def load_sidebar_pick_payload(team_code:, draft_year:, draft_round:)
    payload = queries.fetch_sidebar_pick_payload(team_code: team_code, draft_year: draft_year, draft_round: draft_round)
    raise ActiveRecord::RecordNotFound unless payload

    payload
  end

  def load_sidebar_selection_payload(transaction_id)
    payload = queries.fetch_sidebar_selection_payload(transaction_id)
    raise ActiveRecord::RecordNotFound unless payload

    payload
  end

  def normalize_required_id!(raw)
    id = Integer(raw.to_s.strip, 10)
    raise ActiveRecord::RecordNotFound unless id.positive?

    id
  rescue ArgumentError, TypeError
    raise ActiveRecord::RecordNotFound
  end

  def normalize_team_code_param(raw)
    code = raw.to_s.strip.upcase
    return nil if code.blank?
    return nil unless code.match?(/\A[A-Z]{3}\z/)

    code
  end

  def normalize_year_param(raw)
    year = Integer(raw.to_s.strip)
    return nil if year <= 0

    year
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_round_param(raw)
    round = raw.to_s.strip
    round = "all" if round.blank?
    return round if INDEX_ROUNDS.include?(round)

    nil
  end
end
