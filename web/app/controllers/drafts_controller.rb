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
    hydrate_initial_overlay_from_params!
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
      team_code:,
      draft_year: year,
      draft_round: round
    )
  end

  # GET /drafts/sidebar/selection/:id
  def sidebar_selection
    transaction_id = Integer(params[:id])
    raise ActiveRecord::RecordNotFound if transaction_id <= 0

    render partial: "drafts/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(transaction_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /drafts/sidebar/clear
  def sidebar_clear
    render partial: "drafts/rightpanel_clear"
  end

  private

  def queries
    @queries ||= ::DraftQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_state!
    state = ::Drafts::IndexWorkspaceState.new(
      params: params,
      queries: queries,
      index_views: INDEX_VIEWS,
      index_rounds: INDEX_ROUNDS,
      index_sorts: INDEX_SORTS,
      index_lenses: INDEX_LENSES
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def load_sidebar_pick_payload(team_code:, draft_year:, draft_round:)
    payload = queries.fetch_sidebar_pick_payload(team_code:, draft_year:, draft_round:)
    raise ActiveRecord::RecordNotFound unless payload

    payload
  end

  def load_sidebar_selection_payload(transaction_id)
    payload = queries.fetch_sidebar_selection_payload(transaction_id)
    raise ActiveRecord::RecordNotFound unless payload

    payload
  end

  def hydrate_initial_overlay_from_params!
    @initial_overlay_type = "none"
    @initial_overlay_key = ""
    @initial_overlay_partial = nil
    @initial_overlay_locals = {}

    context = requested_overlay_context
    return if context.blank?
    return unless selected_overlay_visible?(context: context)

    case context[:type]
    when "pick"
      @initial_overlay_partial = "drafts/rightpanel_overlay_pick"
      @initial_overlay_locals = load_sidebar_pick_payload(
        team_code: context[:team_code],
        draft_year: context[:draft_year],
        draft_round: context[:draft_round]
      )
      @initial_overlay_type = "pick"
      @initial_overlay_key = overlay_key_for_pick(
        team_code: context[:team_code],
        draft_year: context[:draft_year],
        draft_round: context[:draft_round]
      )
    when "selection"
      transaction_id = context[:transaction_id].to_i
      @initial_overlay_partial = "drafts/rightpanel_overlay_selection"
      @initial_overlay_locals = load_sidebar_selection_payload(transaction_id)
      @initial_overlay_type = "selection"
      @initial_overlay_key = "selection-#{transaction_id}"
    end
  rescue ActiveRecord::RecordNotFound
    @initial_overlay_type = "none"
    @initial_overlay_key = ""
    @initial_overlay_partial = nil
    @initial_overlay_locals = {}
  end

  def requested_overlay_context
    overlay_type = params[:selected_type].to_s.strip.downcase
    overlay_key = params[:selected_key].to_s.strip

    case overlay_type
    when "pick"
      parse_pick_overlay_key(overlay_key)
    when "selection"
      parse_selection_overlay_key(overlay_key)
    else
      nil
    end
  end

  def selected_overlay_visible?(context:)
    return false if context.blank?

    case context[:type]
    when "pick"
      return false unless %w[picks grid].include?(@view)

      selected_pick_visible?(
        team_code: context[:team_code],
        draft_year: context[:draft_year],
        draft_round: context[:draft_round]
      )
    when "selection"
      return false unless @view == "selections"

      Array(@results).any? { |row| row["transaction_id"].to_i == context[:transaction_id].to_i }
    else
      false
    end
  end

  def overlay_key_for_pick(team_code:, draft_year:, draft_round:)
    key_prefix = @view == "grid" ? "grid" : "pick"
    "#{key_prefix}-#{team_code}-#{draft_year}-#{draft_round}"
  end

  def parse_pick_overlay_key(raw_key)
    match = raw_key.match(/\A(?:pick|grid)-([A-Za-z]{3})-(\d{4})-(\d+)\z/)
    return nil unless match

    team_code = match[1].to_s.upcase
    draft_year = match[2].to_i
    draft_round = match[3].to_i

    return nil if team_code.blank? || draft_year <= 0 || draft_round <= 0

    {
      type: "pick",
      team_code:,
      draft_year:,
      draft_round:
    }
  end

  def parse_selection_overlay_key(raw_key)
    match = raw_key.match(/\Aselection-(\d+)\z/)
    return nil unless match

    transaction_id = match[1].to_i
    return nil if transaction_id <= 0

    {
      type: "selection",
      transaction_id:
    }
  end

  def selected_pick_visible?(team_code:, draft_year:, draft_round:)
    if @view == "grid"
      @grid_data.dig(team_code, draft_round.to_i, draft_year.to_i).present?
    else
      Array(@results).any? do |row|
        row["original_team_code"].to_s.upcase == team_code.to_s.upcase &&
          row["draft_year"].to_i == draft_year.to_i &&
          row["draft_round"].to_i == draft_round.to_i
      end
    end
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
