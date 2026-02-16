class TwoWayUtilityController < ApplicationController
  include Datastar

  RISK_LENSES = %w[all warning critical estimate].freeze
  CONFERENCE_LENSES = ["all", "Eastern", "Western"].freeze

  # GET /two-way-utility
  def show
    load_workspace_state!
  rescue ActiveRecord::StatementInvalid => e
    assign_state!(workspace_state.fallback(error: e))
  end

  # GET /two-way-utility/sidebar/:id
  def sidebar
    load_workspace_state!

    payload = overlay_state.sidebar_player(player_id: params[:id])
    raise ActiveRecord::RecordNotFound unless payload

    @sidebar_player = payload.fetch(:sidebar_player)
    @sidebar_team_meta = payload.fetch(:sidebar_team_meta)

    render partial: "two_way_utility/rightpanel_overlay_player", layout: false
  rescue ActiveRecord::StatementInvalid => e
    render html: <<~HTML.html_safe, layout: false
      <div id="rightpanel-overlay" class="h-full p-4">
        <div class="rounded border border-border bg-muted/20 p-3">
          <div class="text-sm font-medium text-destructive">Two-Way sidebar failed</div>
          <pre class="mt-2 text-xs text-muted-foreground overflow-x-auto">#{ERB::Util.h(e.message)}</pre>
        </div>
      </div>
    HTML
  end

  # GET /two-way-utility/sidebar/agent/:id
  def sidebar_agent
    load_workspace_state!

    agent_id = positive_integer_param!(params[:id])
    source_player_id = overlay_state.normalize_player_id(params[:player_id])
    source_player = overlay_state.source_player(player_id: source_player_id) if source_player_id.present?

    agent = queries.fetch_agent(agent_id)
    raise ActiveRecord::RecordNotFound unless agent

    clients = queries.fetch_agent_clients(agent_id)
    rollup = queries.fetch_agent_rollup(agent_id)

    render partial: "salary_book/sidebar_agent", locals: {
      agent:,
      clients:,
      rollup:,
      sidebar_back_button_partial: "two_way_utility/sidebar_back_button",
      sidebar_back_button_locals: {
        source_player_id: source_player_id,
        source_player_name: source_player&.dig("player_name"),
        state_query: @state_query
      }
    }, layout: false
  rescue ActiveRecord::StatementInvalid => e
    render html: <<~HTML.html_safe, layout: false
      <div id="rightpanel-overlay" class="h-full p-4">
        <div class="rounded border border-border bg-muted/20 p-3">
          <div class="text-sm font-medium text-destructive">Two-Way agent sidebar failed</div>
          <pre class="mt-2 text-xs text-muted-foreground overflow-x-auto">#{ERB::Util.h(e.message)}</pre>
        </div>
      </div>
    HTML
  end

  # GET /two-way-utility/sidebar/clear
  def sidebar_clear
    render partial: "two_way_utility/rightpanel_clear", layout: false
  end

  # GET /two-way-utility/sse/refresh
  # One-request multi-region update for commandbar + board + sidebars.
  # Patches:
  # - #commandbar
  # - #maincanvas
  # - #rightpanel-base
  # - #rightpanel-overlay (preserved when selected row remains visible)
  def refresh
    load_workspace_state!

    requested_overlay_id = overlay_state.requested_overlay_id(raw_selected_id: params[:selected_id])
    overlay_payload = overlay_state.refresh_sidebar_player(requested_overlay_id: requested_overlay_id)

    overlay_html = if overlay_payload.present?
      @sidebar_player = overlay_payload.fetch(:sidebar_player)
      @sidebar_team_meta = overlay_payload.fetch(:sidebar_team_meta)

      without_view_annotations do
        render_to_string(partial: "two_way_utility/rightpanel_overlay_player", layout: false)
      end
    else
      overlay_clear_html
    end

    resolved_overlay_type = overlay_payload.present? ? "player" : "none"
    resolved_overlay_id = overlay_payload.present? ? requested_overlay_id.to_s : ""

    with_sse_stream do |sse|
      commandbar_html = without_view_annotations do
        render_to_string(partial: "two_way_utility/commandbar", layout: false)
      end

      main_html = without_view_annotations do
        render_to_string(partial: "two_way_utility/workspace_main", layout: false)
      end

      sidebar_html = without_view_annotations do
        render_to_string(partial: "two_way_utility/rightpanel_base", layout: false)
      end

      patch_elements_by_id(sse, commandbar_html)
      patch_elements_by_id(sse, main_html)
      patch_elements_by_id(sse, sidebar_html)
      patch_elements_by_id(sse, overlay_html)
      patch_signals(
        sse,
        twconference: @conference,
        twteam: @team.to_s,
        twrisk: @risk,
        overlaytype: resolved_overlay_type,
        overlayid: resolved_overlay_id
      )
    end
  rescue ActiveRecord::StatementInvalid => e
    with_sse_stream do |sse|
      patch_flash(sse, "Two-Way refresh failed: #{e.message.to_s.truncate(160)}")
    end
  end

  private

  def assign_state!(state)
    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def queries
    @queries ||= ::TwoWayUtilityQueries.new(connection: ActiveRecord::Base.connection)
  end

  def workspace_state
    @workspace_state ||= ::TwoWayUtility::WorkspaceState.new(
      params: params,
      queries: queries,
      conference_lenses: CONFERENCE_LENSES,
      risk_lenses: RISK_LENSES
    )
  end

  def overlay_state
    @overlay_state ||= ::TwoWayUtility::OverlayState.new(
      rows: @rows,
      team_meta_by_code: @team_meta_by_code,
      selected_player_id: @selected_player_id,
      queries: queries
    )
  end

  def load_workspace_state!
    assign_state!(workspace_state.build)
  end

  def positive_integer_param!(raw)
    value = Integer(raw.to_s.strip, 10)
    raise ActiveRecord::RecordNotFound unless value.positive?

    value
  rescue ArgumentError, TypeError
    raise ActiveRecord::RecordNotFound
  end

  def overlay_clear_html
    '<div id="rightpanel-overlay"></div>'
  end

  def without_view_annotations
    original = ActionView::Base.annotate_rendered_view_with_filenames
    ActionView::Base.annotate_rendered_view_with_filenames = false
    yield
  ensure
    ActionView::Base.annotate_rendered_view_with_filenames = original
  end
end
