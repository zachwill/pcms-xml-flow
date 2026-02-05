Rails.application.routes.draw do
  # Health endpoint (200 if app boots).
  get "up" => "rails/health#show", as: :rails_health_check

  # Tools (dense instruments)
  namespace :tools do
    # Primary tool surface
    get "salary-book", to: "salary_book#show"

    # Datastar HTML fragment endpoints (patch targets)
    get "salary-book/teams/:teamcode/section", to: "salary_book#team_section", as: :salary_book_team_section
    get "salary-book/sidebar/team", to: "salary_book#sidebar_team", as: :salary_book_sidebar_team
    get "salary-book/sidebar/player/:id", to: "salary_book#sidebar_player", as: :salary_book_sidebar_player
    get "salary-book/sidebar/agent/:id", to: "salary_book#sidebar_agent", as: :salary_book_sidebar_agent
    get "salary-book/sidebar/pick", to: "salary_book#sidebar_pick", as: :salary_book_sidebar_pick
    get "salary-book/sidebar/clear", to: "salary_book#sidebar_clear", as: :salary_book_sidebar_clear

    # SSE demo endpoints (prove Rails ActionController::Live + Datastar framing)
    get "salary-book/sse/demo", to: "salary_book_sse#demo", as: :salary_book_sse_demo
  end

  # Entities (Bricklink-style navigation; clean top-level URLs)
  scope module: :entities do
    get "players", to: "players#index"

    # Numeric fallback (NBA/PCMS shared id) → redirects to canonical slug.
    get "players/:id", to: "players#redirect", constraints: { id: /\d+/ }

    # Canonical route.
    get "players/:slug", to: "players#show", as: :player
  end

  root "tools/salary_book#show"
end
