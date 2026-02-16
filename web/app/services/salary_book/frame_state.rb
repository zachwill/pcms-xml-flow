module SalaryBook
  class FrameState
    def initialize(
      params:,
      queries:,
      salary_years:,
      current_salary_year:,
      available_views:,
      default_view:
    )
      @params = params
      @queries = queries
      @salary_years = salary_years
      @current_salary_year = current_salary_year
      @available_views = available_views
      @default_view = default_view
    end

    # Returns: { partial: "...", locals: {...} }
    # Optional overrides let sibling controllers (ex: switch-team) reuse the
    # exact same frame payload logic without duplicating branch logic.
    def build(team_code: nil, year: nil, view: nil)
      resolved_team_code = resolve_required_team_code(team_code || params[:team])
      resolved_year = resolve_salary_year(year || params[:year])
      resolved_view = resolve_view(view || params[:view])

      case resolved_view
      when "tankathon"
        build_tankathon_frame_payload(team_code: resolved_team_code, year: resolved_year)
      when "injuries"
        build_injuries_frame_payload(team_code: resolved_team_code, year: resolved_year)
      else
        build_team_frame_payload(team_code: resolved_team_code, year: resolved_year)
      end
    end

    def fallback(error:, team_code: nil, year: nil, view: nil)
      resolved_year = resolve_salary_year(year || params[:year])
      resolved_view = resolve_view(view || params[:view])
      resolved_team_code = normalize_team_code(team_code || params[:team])

      case resolved_view
      when "tankathon"
        {
          partial: "salary_book/maincanvas_tankathon_frame",
          locals: {
            team_code: resolved_team_code,
            year: resolved_year,
            standings_rows: [],
            standing_date: nil,
            season_year: nil,
            season_label: nil,
            error_message: error.to_s
          }
        }
      when "injuries"
        {
          partial: "salary_book/maincanvas_injuries_frame",
          locals: {
            team_code: resolved_team_code,
            team_codes: [],
            team_meta_by_code: {},
            year: resolved_year,
            error_message: error.to_s
          }
        }
      else
        {
          partial: "salary_book/maincanvas_team_frame",
          locals: {
            boot_error: error.to_s,
            team_code: nil,
            players: [],
            cap_holds: [],
            exceptions: [],
            dead_money: [],
            picks: [],
            team_summaries: {},
            team_meta: {},
            year: resolved_year,
            salary_years: salary_years,
            empty_message: nil
          }
        }
      end
    end

    private

    attr_reader :params, :queries, :salary_years, :current_salary_year, :available_views, :default_view

    def resolve_salary_year(raw)
      year = Integer(raw)
      salary_years.include?(year) ? year : current_salary_year
    rescue ArgumentError, TypeError
      current_salary_year
    end

    def resolve_view(raw)
      view = raw.to_s.strip.downcase
      available_views.include?(view) ? view : default_view
    end

    def normalize_team_code(raw)
      team_code = raw.to_s.strip.upcase
      return nil unless team_code.match?(/\A[A-Z]{3}\z/)

      team_code
    end

    def resolve_required_team_code(raw)
      team_code = normalize_team_code(raw)
      raise ActiveRecord::RecordNotFound unless team_code.present?

      team_code
    end

    def build_tankathon_frame_payload(team_code:, year:)
      tankathon_payload = queries.fetch_tankathon_payload(year)

      {
        partial: "salary_book/maincanvas_tankathon_frame",
        locals: {
          team_code: team_code,
          year: year,
          standings_rows: tankathon_payload[:rows],
          standing_date: tankathon_payload[:standing_date],
          season_year: tankathon_payload[:season_year],
          season_label: tankathon_payload[:season_label],
          error_message: nil
        }
      }
    end

    def build_injuries_frame_payload(team_code:, year:)
      team_rows = queries.fetch_team_index_rows(year)
      team_codes = team_rows.map { |row| row["team_code"] }.compact
      _, team_meta_by_code = queries.build_team_maps(team_rows)

      {
        partial: "salary_book/maincanvas_injuries_frame",
        locals: {
          team_code: team_code,
          team_codes: team_codes,
          team_meta_by_code: team_meta_by_code,
          year: year,
          error_message: nil
        }
      }
    end

    def build_team_frame_payload(team_code:, year:)
      players = queries.fetch_team_players(team_code)
      payload = queries.fetch_team_support_payload(team_code, base_year: year)

      {
        partial: "salary_book/maincanvas_team_frame",
        locals: {
          boot_error: nil,
          team_code: team_code,
          players: players,
          cap_holds: payload[:cap_holds],
          exceptions: payload[:exceptions],
          dead_money: payload[:dead_money],
          picks: payload[:picks],
          team_summaries: payload[:team_summaries],
          team_meta: payload[:team_meta],
          year: year,
          salary_years: salary_years,
          empty_message: nil
        }
      }
    end
  end
end
