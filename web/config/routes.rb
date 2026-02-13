Rails.application.routes.draw do
  # Health endpoint (200 if app boots).
  get "up" => "rails/health#show", as: :rails_health_check

  # Tools (dense instruments)
  namespace :tools do
    # Primary tool surface
    get "salary-book", to: "salary_book#show"
    get "two-way-utility", to: "two_way_utility#show"
    get "system-values", to: "system_values#show"
    get "team-summary", to: "team_summary#show"
    get "team-summary/sidebar/clear", to: "team_summary#sidebar_clear", as: :team_summary_sidebar_clear
    get "team-summary/sidebar/:team_code", to: "team_summary#sidebar", as: :team_summary_sidebar, constraints: { team_code: /[A-Za-z]{3}/ }
    get "team-summary/sse/compare", to: "team_summary#compare", as: :team_summary_sse_compare

    # Datastar HTML fragment endpoints (patch targets)
    get "salary-book/frame", to: "salary_book#frame", as: :salary_book_frame
    get "salary-book/sidebar/team", to: "salary_book#sidebar_team", as: :salary_book_sidebar_team
    get "salary-book/sidebar/team/cap", to: "salary_book#sidebar_team_cap", as: :salary_book_sidebar_team_cap
    get "salary-book/sidebar/team/draft", to: "salary_book#sidebar_team_draft", as: :salary_book_sidebar_team_draft
    get "salary-book/sidebar/team/rights", to: "salary_book#sidebar_team_rights", as: :salary_book_sidebar_team_rights
    get "salary-book/sidebar/player/:id", to: "salary_book#sidebar_player", as: :salary_book_sidebar_player
    get "salary-book/sidebar/agent/:id", to: "salary_book#sidebar_agent", as: :salary_book_sidebar_agent
    get "salary-book/sidebar/pick", to: "salary_book#sidebar_pick", as: :salary_book_sidebar_pick
    get "salary-book/sidebar/clear", to: "salary_book#sidebar_clear", as: :salary_book_sidebar_clear

    # Salary Book combobox fragments (server-rendered HTML options)
    get "salary-book/combobox/players/search", to: "salary_book#combobox_players_search", as: :salary_book_combobox_players_search

    # SSE multi-region team switch (main canvas + sidebar in one request)
    get "salary-book/sse/switch-team", to: "salary_book_sse#switch_team", as: :salary_book_sse_switch_team
  end

  # Entities (Bricklink-style navigation; clean top-level URLs)
  scope module: :entities do
    reserved_slug_segments = %w[pane sidebar sse bootstrap up tools].freeze
    slug_route_constraint = lambda do |req|
      slug = req.params[:slug].to_s.strip.downcase
      slug.present? && !reserved_slug_segments.include?(slug)
    end

    # ---------------------------------------------------------------------
    # Players
    # ---------------------------------------------------------------------
    get "players", to: "players#index"
    get "players/pane", to: "players#pane"
    get "players/sidebar/clear", to: "players#sidebar_clear", as: :players_sidebar_clear
    get "players/sidebar/:id", to: "players#sidebar", constraints: { id: /\d+/ }
    get "players/sse/refresh", to: "players_sse#refresh", as: :players_sse_refresh
    get "players/:slug/sse/bootstrap", to: "players_sse#bootstrap"

    # Numeric fallback (NBA/PCMS shared id) → redirects to canonical slug.
    get "players/:id", to: "players#redirect", constraints: { id: /\d+/ }

    # Canonical route.
    get "players/:slug", to: "players#show", as: :player, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Teams
    # ---------------------------------------------------------------------
    get "teams", to: "teams#index"
    get "teams/pane", to: "teams#pane"
    get "teams/sidebar/clear", to: "teams#sidebar_clear", as: :teams_sidebar_clear
    get "teams/sidebar/:id", to: "teams#sidebar", constraints: { id: /\d+/ }
    get "teams/sse/refresh", to: "teams_sse#refresh", as: :teams_sse_refresh
    get "teams/:slug/sse/bootstrap", to: "teams_sse#bootstrap"
    get "teams/:id", to: "teams#redirect", constraints: { id: /\d+/ }
    get "teams/:slug", to: "teams#show", as: :team, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Agents
    # ---------------------------------------------------------------------
    get "agents", to: "agents#index"
    get "agents/pane", to: "agents#pane"
    get "agents/sidebar/base", to: "agents#sidebar_base", as: :agents_sidebar_base
    get "agents/sidebar/agent/:id", to: "agents#sidebar_agent", as: :agents_sidebar_agent, constraints: { id: /\d+/ }
    get "agents/sidebar/agency/:id", to: "agents#sidebar_agency", as: :agents_sidebar_agency, constraints: { id: /\d+/ }
    get "agents/sidebar/clear", to: "agents#sidebar_clear", as: :agents_sidebar_clear
    get "agents/sse/refresh", to: "agents_sse#refresh", as: :agents_sse_refresh
    get "agents/:id", to: "agents#redirect", constraints: { id: /\d+/ }
    get "agents/:slug", to: "agents#show", as: :agent, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Agencies
    # ---------------------------------------------------------------------
    get "agencies", to: "agencies#index"
    get "agencies/:id", to: "agencies#redirect", constraints: { id: /\d+/ }
    get "agencies/:slug", to: "agencies#show", as: :agency, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Drafts (unified workspace for picks + selections)
    # ---------------------------------------------------------------------
    get "drafts", to: "drafts#index"
    get "drafts/pane", to: "drafts#pane"
    get "drafts/sidebar/base", to: "drafts#sidebar_base", as: :drafts_sidebar_base
    get "drafts/sidebar/pick", to: "drafts#sidebar_pick", as: :drafts_sidebar_pick
    get "drafts/sidebar/selection/:id", to: "drafts#sidebar_selection", as: :drafts_sidebar_selection, constraints: { id: /\d+/ }
    get "drafts/sidebar/clear", to: "drafts#sidebar_clear", as: :drafts_sidebar_clear
    get "drafts/sse/refresh", to: "drafts_sse#refresh", as: :drafts_sse_refresh

    # ---------------------------------------------------------------------
    # Draft selections (historical drafts) — show pages
    # ---------------------------------------------------------------------
    get "draft-selections/:id", to: "draft_selections#redirect", constraints: { id: /\d+/ }
    get "draft-selections/:slug", to: "draft_selections#show", as: :draft_selection, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Draft picks (future pick assets) — natural key, no slug registry yet.
    # ---------------------------------------------------------------------
    get "draft-picks/:team_code/:year/:round", to: "draft_picks#show", as: :draft_pick,
      constraints: { team_code: /[A-Za-z]{3}/, year: /\d{4}/, round: /1|2/ }

    # ---------------------------------------------------------------------
    # Trades
    # ---------------------------------------------------------------------
    get "trades", to: "trades#index"
    get "trades/pane", to: "trades#pane"
    get "trades/sidebar/base", to: "trades#sidebar_base", as: :trades_sidebar_base
    get "trades/sidebar/clear", to: "trades#sidebar_clear", as: :trades_sidebar_clear
    get "trades/sidebar/:id", to: "trades#sidebar", constraints: { id: /\d+/ }
    get "trades/sse/refresh", to: "trades_sse#refresh", as: :trades_sse_refresh
    get "trades/:id", to: "trades#show", as: :trade, constraints: { id: /\d+/ }

    # ---------------------------------------------------------------------
    # Transactions
    # ---------------------------------------------------------------------
    get "transactions", to: "transactions#index"
    get "transactions/pane", to: "transactions#pane"
    get "transactions/sidebar/base", to: "transactions#sidebar_base", as: :transactions_sidebar_base
    get "transactions/sidebar/clear", to: "transactions#sidebar_clear", as: :transactions_sidebar_clear
    get "transactions/sidebar/:id", to: "transactions#sidebar", constraints: { id: /\d+/ }
    get "transactions/sse/refresh", to: "transactions_sse#refresh", as: :transactions_sse_refresh
    get "transactions/:id", to: "transactions#show", as: :transaction, constraints: { id: /\d+/ }
  end

  # Rip City stubs
  get "rip-city/noah", to: "rip_city/noah#show", as: :rip_city_noah

  root "tools/salary_book#show"
end
