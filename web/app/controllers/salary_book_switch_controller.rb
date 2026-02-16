class SalaryBookSwitchController < SalaryBookController
  # GET /salary-book/switch-team?team=BOS&year=2025&view=salary-book
  # One-request, multi-region team swap via text/html morph-by-id patch set.
  # Response body contains two top-level roots:
  # - #salarybook-team-frame
  # - #rightpanel-base
  # This preserves overlay state while keeping main + base in sync.
  def switch_team
    team_code = normalize_team_code(params[:team])
    year = salary_year_param
    view = salary_book_view_param

    main_payload = frame_state.build(team_code:, year:, view:)
    sidebar_locals = team_sidebar_state.build(team_code:, year:)

    main_html = render_fragment(partial: main_payload.fetch(:partial), locals: main_payload.fetch(:locals))
    sidebar_html = render_fragment(partial: "salary_book/sidebar_team", locals: sidebar_locals)

    no_cache_headers!
    render html: [main_html, sidebar_html].join("\n").html_safe, layout: false
  rescue ActiveRecord::StatementInvalid => e
    error_main_payload = frame_state.fallback(error: e, team_code:, year:, view:)
    error_main_html = render_fragment(partial: error_main_payload.fetch(:partial), locals: error_main_payload.fetch(:locals))
    flash_html = %(<div id="flash">Salary Book team switch failed.</div>)

    no_cache_headers!
    render html: [error_main_html, flash_html].join("\n").html_safe, layout: false, status: :unprocessable_entity
  end

  private

  def render_fragment(partial:, locals: {})
    without_view_annotations do
      render_to_string(partial:, locals: locals)
    end
  end

  def without_view_annotations
    original = ActionView::Base.annotate_rendered_view_with_filenames
    ActionView::Base.annotate_rendered_view_with_filenames = false
    yield
  ensure
    ActionView::Base.annotate_rendered_view_with_filenames = original
  end

  def no_cache_headers!
    response.headers["Cache-Control"] = "no-store"
    response.headers.delete("ETag")
  end
end
