class TwoWayUtilityController < ApplicationController
    include Datastar

    RISK_LENSES = %w[all warning critical estimate].freeze
    CONFERENCE_LENSES = ["all", "Eastern", "Western"].freeze

    # GET /two-way-utility
    def show
      load_workspace_state!
    rescue ActiveRecord::StatementInvalid => e
      apply_boot_error!(e)
    end

    # GET /two-way-utility/sidebar/:id
    def sidebar
      load_workspace_state!

      player_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if player_id <= 0

      @sidebar_player = @rows.find { |row| row["player_id"].to_i == player_id } || fetch_player_row(player_id)
      raise ActiveRecord::RecordNotFound unless @sidebar_player

      @sidebar_team_meta = @team_meta_by_code[@sidebar_player["team_code"].to_s] || {}

      render partial: "two_way_utility/rightpanel_overlay_player", layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
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

      agent_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if agent_id <= 0

      source_player_id = normalize_player_id_param(params[:player_id])
      source_player = if source_player_id.present?
        @rows.find { |row| row["player_id"].to_i == source_player_id } || fetch_player_row(source_player_id)
      end

      agent = fetch_agent(agent_id)
      raise ActiveRecord::RecordNotFound unless agent

      clients = fetch_agent_clients(agent_id)
      rollup = fetch_agent_rollup(agent_id)

      render partial: "salary_book/sidebar_agent", locals: {
        agent:,
        clients:,
        rollup:,
        sidebar_back_button_partial: "two_way_utility/sidebar_back_button",
        sidebar_back_button_locals: {
          source_player_id:,
          source_player_name: source_player&.dig("player_name"),
          state_query: @state_query
        }
      }, layout: false
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
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

      requested_overlay_id = requested_overlay_id_param
      overlay_html, resolved_overlay_type, resolved_overlay_id = refreshed_overlay_payload(
        requested_overlay_id: requested_overlay_id
      )

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

    def queries
      @queries ||= ::TwoWayUtilityQueries.new(connection: ActiveRecord::Base.connection)
    end

    def load_workspace_state!
      state = ::TwoWayUtility::WorkspaceState.new(
        params: params,
        queries: queries,
        conference_lenses: CONFERENCE_LENSES,
        risk_lenses: RISK_LENSES
      ).build

      state.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
    end

    def apply_boot_error!(error)
      @boot_error = error.message
      @conference = "all"
      @team = nil
      @risk = "all"
      @rows = []
      @rows_by_team = {}
      @teams_by_conference = { "Eastern" => [], "Western" => [] }
      @team_meta_by_code = {}
      @team_capacity_by_code = {}
      @team_options = []
      @team_codes = []
      @team_records_by_code = {}
      @state_query = Rack::Utils.build_query(conference: @conference.to_s, team: @team.to_s, risk: @risk.to_s)
      @selected_player_id = nil
      @sidebar_summary = {
        row_count: 0,
        team_count: 0,
        critical_count: 0,
        warning_count: 0,
        low_remaining_count: 0,
        estimate_count: 0,
        active_filters: [],
        quick_rows: []
      }
    end

    def normalize_player_id_param(raw)
      player_id = Integer(raw.to_s.strip, 10)
      player_id.positive? ? player_id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def fetch_player_row(player_id)
      row = queries.fetch_player_row(player_id)
      row.present? ? ::TwoWayUtility::WorkspaceState.decorate_row(row) : nil
    end

    def fetch_agent(agent_id)
      queries.fetch_agent(agent_id)
    end

    def fetch_agent_clients(agent_id)
      queries.fetch_agent_clients(agent_id)
    end

    def fetch_agent_rollup(agent_id)
      queries.fetch_agent_rollup(agent_id)
    end

    def normalize_selected_player_id_param(raw)
      normalize_player_id_param(raw)
    end

    def requested_overlay_id_param
      @selected_player_id || normalize_selected_player_id_param(params[:selected_id])
    end

    def selected_overlay_visible?(overlay_id:)
      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      Array(@rows).any? { |row| row["player_id"].to_i == normalized_id }
    end

    def refreshed_overlay_payload(requested_overlay_id:)
      return [overlay_clear_html, "none", ""] unless selected_overlay_visible?(overlay_id: requested_overlay_id)

      @sidebar_player = @rows.find { |row| row["player_id"].to_i == requested_overlay_id.to_i }
      return [overlay_clear_html, "none", ""] unless @sidebar_player.present?

      @sidebar_team_meta = @team_meta_by_code[@sidebar_player["team_code"].to_s] || {}

      html = without_view_annotations do
        render_to_string(partial: "two_way_utility/rightpanel_overlay_player", layout: false)
      end

      [html, "player", requested_overlay_id.to_s]
    rescue ActiveRecord::RecordNotFound
      [overlay_clear_html, "none", ""]
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
