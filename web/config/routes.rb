Rails.application.routes.draw do
  # Health endpoint (200 if app boots).
  get "up" => "rails/health#show", as: :rails_health_check

  # Tools (dense instruments)
  namespace :tools do
    # Primary tool surface
    get "salary-book", to: "salary_book#show"
    get "two-way-utility", to: "two_way_utility#show"

    # Datastar HTML fragment endpoints (patch targets)
    get "salary-book/teams/:teamcode/section", to: "salary_book#team_section", as: :salary_book_team_section
    get "salary-book/sidebar/team", to: "salary_book#sidebar_team", as: :salary_book_sidebar_team
    get "salary-book/sidebar/player/:id", to: "salary_book#sidebar_player", as: :salary_book_sidebar_player
    get "salary-book/sidebar/agent/:id", to: "salary_book#sidebar_agent", as: :salary_book_sidebar_agent
    get "salary-book/sidebar/pick", to: "salary_book#sidebar_pick", as: :salary_book_sidebar_pick
    get "salary-book/sidebar/clear", to: "salary_book#sidebar_clear", as: :salary_book_sidebar_clear

    # SSE bootstrap + patch template endpoints (canonical one-off SSE pattern)
    get "salary-book/sse/bootstrap", to: "salary_book_sse#bootstrap", as: :salary_book_sse_bootstrap
    get "salary-book/sse/patch-template", to: "salary_book_sse#demo", as: :salary_book_sse_patch_template
    # Legacy alias
    get "salary-book/sse/demo", to: "salary_book_sse#demo", as: :salary_book_sse_demo
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
    get "players/sidebar/:id", to: "players#sidebar", constraints: { id: /\d+/ }
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
    get "teams/sidebar/:id", to: "teams#sidebar", constraints: { id: /\d+/ }
    get "teams/:slug/sse/bootstrap", to: "teams_sse#bootstrap"
    get "teams/:id", to: "teams#redirect", constraints: { id: /\d+/ }
    get "teams/:slug", to: "teams#show", as: :team, constraints: slug_route_constraint

    # ---------------------------------------------------------------------
    # Agents
    # ---------------------------------------------------------------------
    get "agents", to: "agents#index"
    get "agents/pane", to: "agents#pane"
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
    get "trades/:id", to: "trades#show", as: :trade, constraints: { id: /\d+/ }

    # ---------------------------------------------------------------------
    # Transactions
    # ---------------------------------------------------------------------
    get "transactions", to: "transactions#index"
    get "transactions/pane", to: "transactions#pane"
    get "transactions/:id", to: "transactions#show", as: :transaction, constraints: { id: /\d+/ }
  end

  root "tools/salary_book#show"
end
