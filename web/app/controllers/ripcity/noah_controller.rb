module RipCity
  class NoahController < ApplicationController
    ZONE_ORDER = [
      "left-corner-three",
      "left-wing-three",
      "middle-three",
      "right-wing-three",
      "right-corner-three",
      "left-corner-two",
      "left-wing-two",
      "middle-two",
      "right-wing-two",
      "right-corner-two",
      "paint",
      "rim",
      "far-three"
    ].freeze

    TIMEFRAME_OPTIONS = [
      { key: "past-24-hours", label: "Past 24 Hours" },
      { key: "past-3-days", label: "Past 3 Days" },
      { key: "past-week", label: "Past Week" },
      { key: "past-month", label: "Past Month" },
      { key: "25-26-season", label: "25-26 Season" },
      { key: "24-25-season", label: "24-25 Season" },
      { key: "2025-draft-workouts", label: "2025 Draft Workouts" },
      { key: "2024-draft-workouts", label: "2024 Draft Workouts" },
      { key: "2023-draft-workouts", label: "2023 Draft Workouts" }
    ].freeze

    SHOT_LENS_OPTIONS = {
      "all-3pa" => {
        label: "All 3PA",
        caption: "All 3PA includes catch-and-shoot, form shooting, and off-dribble jumpers.",
        is_three: 1,
        shot_type: nil,
        is_corner_three: nil
      },
      "catch-shoot-3pa" => {
        label: "Catch & Shoot 3PA",
        caption: "Catch & Shoot 3PA includes Noah tagged spot-up jumpers only.",
        is_three: 1,
        shot_type: "Catch And Shoot",
        is_corner_three: nil
      },
      "cs-above-break-3pa" => {
        label: "C&S Above Break 3PA",
        caption: "Catch & Shoot above-break attempts (corner threes removed).",
        is_three: 1,
        shot_type: "Catch And Shoot",
        is_corner_three: 0
      },
      "cs-corner-3pa" => {
        label: "C&S Corner 3PA",
        caption: "Catch & Shoot corner threes only.",
        is_three: 1,
        shot_type: "Catch And Shoot",
        is_corner_three: 1
      },
      "off-dribble-3pa" => {
        label: "Off-Dribble 3PA",
        caption: "Noah tagged off-the-dribble three-point attempts.",
        is_three: 1,
        shot_type: "Off The Dribble",
        is_corner_three: nil
      },
      "corner-3pa" => {
        label: "Corner 3PA",
        caption: "All corner three-point attempts.",
        is_three: 1,
        shot_type: nil,
        is_corner_three: 1
      },
      "form-shooting" => {
        label: "Form Shooting",
        caption: "Form shooting attempts (mostly short-range drill reps).",
        is_three: nil,
        shot_type: "Form Shooting",
        is_corner_three: nil
      },
      "all-fga" => {
        label: "All FGA",
        caption: "All tracked jumpers (threes + twos, free throws excluded).",
        is_three: nil,
        shot_type: nil,
        is_corner_three: nil
      }
    }.freeze

    GRADE_LENS_OPTIONS = [
      { key: "joe-stats", label: "Joe's Stats" },
      { key: "raw-values", label: "Raw Values" },
      { key: "noah-grades", label: "Noah Grades" },
      { key: "consistency", label: "Consistency Lens" }
    ].freeze

    DEFAULT_TIMEFRAME = "25-26-season"
    DEFAULT_SHOT_LENS = "catch-shoot-3pa"
    DEFAULT_GRADE_LENS = "joe-stats"

    NOAH_GRADE_THRESHOLDS = [
      [1.0, "A+"],
      [2.0, "A"],
      [3.0, "A-"],
      [4.0, "B+"],
      [5.0, "B"],
      [6.0, "B-"],
      [7.0, "C+"],
      [8.0, "C"],
      [9.0, "C-"],
      [10.0, "D+"],
      [11.0, "D"],
      [12.0, "D-"],
      [99.0, "F"]
    ].freeze

    CONSISTENCY_THRESHOLDS = [
      [6.36, "A+"],
      [7.04, "A"],
      [7.45, "B+"],
      [7.87, "B"],
      [8.24, "C+"],
      [8.63, "C"],
      [9.15, "D+"],
      [9.78, "D"],
      [99.0, "F"]
    ].freeze

    DEPTH_CONSISTENCY_THRESHOLDS = [
      [3.12, "A+"],
      [3.62, "A"],
      [3.93, "B+"],
      [4.18, "B"],
      [4.44, "C+"],
      [4.70, "C"],
      [4.99, "D+"],
      [5.42, "D"],
      [99.0, "F"]
    ].freeze

    LEFT_RIGHT_CONSISTENCY_THRESHOLDS = [
      [2.81, "A+"],
      [3.22, "A"],
      [3.41, "B+"],
      [3.58, "B"],
      [3.77, "C+"],
      [3.96, "C"],
      [4.19, "D+"],
      [4.49, "D"],
      [99.0, "F"]
    ].freeze

    # GET /ripcity/noah
    def show
      load_workspace_state!
    rescue ActiveRecord::StatementInvalid => e
      assign_workspace_fallback!(error: e)
    end

    # GET /ripcity/noah/refresh
    # One-response multi-region patch set for main + sidebar.
    def refresh
      load_workspace_state!

      main_html = render_fragment(partial: "ripcity/noah/maincanvas")
      sidebar_html = render_fragment(partial: "ripcity/noah/sidebar_base")

      no_cache_headers!
      render html: [main_html, sidebar_html].join("\n").html_safe, layout: false
    rescue ActiveRecord::StatementInvalid => e
      no_cache_headers!
      render html: %(<div id="flash">Noah refresh failed: #{ERB::Util.h(e.message.to_s.truncate(160))}</div>).html_safe,
        layout: false,
        status: :unprocessable_entity
    end

    private

    def load_workspace_state!
      @timeframe_options = TIMEFRAME_OPTIONS
      @shot_lens_options = SHOT_LENS_OPTIONS
      @grade_lens_options = GRADE_LENS_OPTIONS

      @timeframe_lens = resolve_timeframe(params[:timeframe])
      @shot_lens = resolve_shot_lens(params[:shot_lens])
      @grade_lens = resolve_grade_lens(params[:grade_lens])

      window = timeframe_window(@timeframe_lens)
      @start_date = window.fetch(:start_date)
      @end_date = window.fetch(:end_date)
      @window_label = window.fetch(:label)
      @include_predraft = window.fetch(:include_predraft, false)
      @exclude_player_ids = window.fetch(:exclude_player_ids, [])

      @min_attempts = normalize_min_attempts(
        params[:min_attempts],
        default_min_attempts_for(@timeframe_lens)
      )

      shot_lens = SHOT_LENS_OPTIONS.fetch(@shot_lens)
      @shot_lens_label = shot_lens.fetch(:label)
      @shot_lens_caption = shot_lens.fetch(:caption)
      @shot_volume_label = shot_volume_label_for(@shot_lens)
      @shot_pct_label = shot_pct_label_for(@shot_lens)
      @metric_headers = metric_headers_for(@grade_lens)

      filters = {
        is_three: shot_lens[:is_three],
        shot_type: shot_lens[:shot_type],
        is_corner_three: shot_lens[:is_corner_three]
      }

      @kpis_by_key = queries.fetch_kpis.index_by { |row| row["kpi"].to_s }
      @kpi_updated_at = @kpis_by_key.values.filter_map { |row| row["updated_at"] }.max

      raw_players = queries.fetch_player_summary(
        start_date: @start_date,
        end_date: @end_date,
        include_predraft: @include_predraft,
        exclude_player_ids: @exclude_player_ids,
        **filters
      )

      @players = build_player_rows(raw_players).select { |row| row["attempts"].to_i >= @min_attempts }

      selected_player_id = normalize_selected_player_id(params[:selected_player])
      @selected_player = select_player(@players, selected_player_id)
      @selected_player_id = @selected_player&.dig("noah_id")

      if @selected_player.present?
        raw_zones = queries.fetch_zone_summary(
          start_date: @start_date,
          end_date: @end_date,
          noah_id: @selected_player["noah_id"],
          **filters
        )
        @zone_rows = build_zone_rows(raw_zones)

        @weekly_rows = queries.fetch_player_weekly(
          start_date: @start_date,
          end_date: @end_date,
          noah_id: @selected_player["noah_id"],
          **filters
        ).last(12).reverse

        @shot_type_rows = queries.fetch_player_shot_type_breakdown(
          start_date: @start_date,
          end_date: @end_date,
          noah_id: @selected_player["noah_id"],
          **filters
        ).first(8)
      else
        @zone_rows = build_zone_rows([])
        @weekly_rows = []
        @shot_type_rows = []
      end

      @shotchart_payload = {
        zones: @zone_rows.map { |row| { name: row[:name], attempts: row[:attempts], made: row[:made] } },
        player_name: @selected_player&.dig("player_name"),
        updated_at: Time.current.iso8601
      }
    end

    def assign_workspace_fallback!(error:)
      @timeframe_options = TIMEFRAME_OPTIONS
      @shot_lens_options = SHOT_LENS_OPTIONS
      @grade_lens_options = GRADE_LENS_OPTIONS

      @timeframe_lens = DEFAULT_TIMEFRAME
      @shot_lens = DEFAULT_SHOT_LENS
      @grade_lens = DEFAULT_GRADE_LENS
      @start_date = Date.current - 7
      @end_date = Date.current
      @window_label = "Fallback window"
      @include_predraft = false
      @exclude_player_ids = []

      @min_attempts = 10
      @shot_lens_label = SHOT_LENS_OPTIONS.fetch(@shot_lens).fetch(:label)
      @shot_lens_caption = "Noah workspace fallback rendered due to a query error."
      @shot_volume_label = shot_volume_label_for(@shot_lens)
      @shot_pct_label = shot_pct_label_for(@shot_lens)
      @metric_headers = metric_headers_for(@grade_lens)

      @kpis_by_key = {}
      @kpi_updated_at = nil
      @players = []
      @selected_player = nil
      @selected_player_id = nil
      @zone_rows = build_zone_rows([])
      @weekly_rows = []
      @shot_type_rows = []
      @shotchart_payload = {
        zones: @zone_rows.map { |row| { name: row[:name], attempts: row[:attempts], made: row[:made] } },
        updated_at: Time.current.iso8601
      }

      flash.now[:alert] = "Noah workspace failed to load: #{error.message.to_s.truncate(160)}"
    end

    def resolve_timeframe(raw)
      key = raw.to_s.strip
      TIMEFRAME_OPTIONS.any? { |option| option[:key] == key } ? key : DEFAULT_TIMEFRAME
    end

    def resolve_shot_lens(raw)
      key = raw.to_s.strip
      SHOT_LENS_OPTIONS.key?(key) ? key : DEFAULT_SHOT_LENS
    end

    def resolve_grade_lens(raw)
      key = raw.to_s.strip
      GRADE_LENS_OPTIONS.any? { |option| option[:key] == key } ? key : DEFAULT_GRADE_LENS
    end

    def normalize_min_attempts(raw, fallback)
      value = Integer(raw)
      value.clamp(1, 500)
    rescue ArgumentError, TypeError
      fallback
    end

    def default_min_attempts_for(timeframe)
      case timeframe.to_s
      when "past-24-hours", "past-3-days", "past-week"
        5
      else
        10
      end
    end

    def normalize_selected_player_id(raw)
      id = Integer(raw)
      id.positive? ? id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def select_player(rows, selected_player_id)
      normalized = selected_player_id.to_i
      return rows.first if normalized <= 0

      rows.find { |row| row["noah_id"].to_i == normalized } || rows.first
    end

    def timeframe_window(key)
      now = Time.current.utc

      case key.to_s
      when "past-24-hours"
        {
          label: "Past 24 hours",
          start_date: (now - 36.hours).to_date,
          end_date: now.to_date
        }
      when "past-3-days"
        {
          label: "Past 3 days",
          start_date: (now - 3.days - 6.hours).to_date,
          end_date: now.to_date
        }
      when "past-week"
        {
          label: "Past week",
          start_date: (now - 7.days - 6.hours).to_date,
          end_date: now.to_date
        }
      when "past-month"
        {
          label: "Past month",
          start_date: (now - 1.month - 6.hours).to_date,
          end_date: now.to_date
        }
      when "24-25-season"
        {
          label: "24-25 season",
          start_date: Date.new(2024, 8, 1),
          end_date: Date.new(2025, 4, 15)
        }
      when "2025-draft-workouts"
        {
          label: "2025 draft workouts",
          start_date: Date.new(2025, 5, 1),
          end_date: Date.new(2025, 6, 25),
          include_predraft: true,
          exclude_player_ids: [1262385, 1262390, 1262395]
        }
      when "2024-draft-workouts"
        {
          label: "2024 draft workouts",
          start_date: Date.new(2024, 5, 1),
          end_date: Date.new(2024, 6, 25),
          include_predraft: true,
          exclude_player_ids: [1262385, 1262390, 1262395]
        }
      when "2023-draft-workouts"
        {
          label: "2023 draft workouts",
          start_date: Date.new(2023, 5, 1),
          end_date: Date.new(2023, 6, 25),
          include_predraft: true,
          exclude_player_ids: []
        }
      else
        {
          label: "25-26 season",
          start_date: Date.new(2025, 8, 1),
          end_date: Date.new(2026, 4, 15)
        }
      end
    end

    def shot_volume_label_for(shot_lens)
      %w[all-fga form-shooting].include?(shot_lens.to_s) ? "FGA" : "3PA"
    end

    def shot_pct_label_for(shot_lens)
      %w[all-fga form-shooting].include?(shot_lens.to_s) ? "FG%" : "3P%"
    end

    def metric_headers_for(grade_lens)
      case grade_lens.to_s
      when "noah-grades"
        {
          one: "Angle Grade",
          two: "Depth Grade",
          three: "L/R Grade"
        }
      when "consistency"
        {
          one: "Depth σ Grade",
          two: "L/R σ Grade",
          three: "Consistency"
        }
      else
        {
          one: "Angle",
          two: "Depth",
          three: "L/R"
        }
      end
    end

    def build_player_rows(raw_rows)
      Array(raw_rows).map do |row|
        angle = as_float(row["angle_mean"])
        depth = as_float(row["depth_mean"])
        left_right = as_float(row["left_right_mean"])
        depth_std = as_float(row["depth_std"])
        left_right_std = as_float(row["left_right_std"])

        consistency_score = if depth_std || left_right_std
          depth_std.to_f + left_right_std.to_f
        end

        {
          "noah_id" => row["noah_id"].to_i,
          "nba_id" => row["nba_id"].presence&.to_i,
          "player_name" => row["player_name"].presence || "Unknown Player",
          "roster_group" => row["roster_group"].presence,
          "attempts" => row["count"].to_i,
          "fg_pct" => as_float(row["made_mean"]) || 0.0,
          "swish_pct" => as_float(row["is_swish_mean"]) || 0.0,
          "angle" => angle,
          "depth" => depth,
          "left_right" => left_right,
          "angle_std" => as_float(row["angle_std"]),
          "depth_std" => depth_std,
          "left_right_std" => left_right_std,
          "consistency_score" => consistency_score,
          "angle_grade" => noah_angle_grade(angle),
          "depth_grade" => noah_depth_grade(depth),
          "left_right_grade" => noah_left_right_grade(left_right),
          "depth_consistency_grade" => consistency_grade_for(depth_std, DEPTH_CONSISTENCY_THRESHOLDS),
          "left_right_consistency_grade" => consistency_grade_for(left_right_std, LEFT_RIGHT_CONSISTENCY_THRESHOLDS),
          "consistency_grade" => consistency_grade_for(consistency_score, CONSISTENCY_THRESHOLDS)
        }
      end
    end

    def build_zone_rows(raw_zone_rows)
      rows_by_zone = Array(raw_zone_rows).index_by { |row| row["zone_name"].to_s }

      ZONE_ORDER.map do |zone_name|
        row = rows_by_zone[zone_name] || {}
        attempts = row["attempts"].to_i
        made = row["made"].to_i

        {
          name: zone_name,
          attempts: attempts,
          made: made,
          fg_pct: attempts.positive? ? ((made.to_f / attempts) * 100.0).round(1) : 0.0
        }
      end
    end

    def as_float(value)
      return nil if value.nil?

      value.to_f
    end

    def noah_angle_grade(angle)
      return "—" if angle.nil?

      score = (angle - 45.0).abs + 1.0
      noah_grade_from_score(score)
    end

    def noah_depth_grade(depth)
      return "—" if depth.nil?

      score = (depth - 11.0).abs + 1.0
      noah_grade_from_score(score)
    end

    def noah_left_right_grade(left_right)
      return "—" if left_right.nil?

      score = left_right.abs + 1.0
      noah_grade_from_score(score)
    end

    def noah_grade_from_score(score)
      threshold = NOAH_GRADE_THRESHOLDS.min_by { |row| (score - row.first).abs }
      threshold ? threshold.last : "—"
    end

    def consistency_grade_for(value, thresholds)
      return "—" if value.nil?

      point = value.to_f
      row = thresholds.find { |threshold, _grade| point <= threshold }
      row ? row.last : "F"
    end

    def queries
      @queries ||= ::NoahQueries.new(connection: ActiveRecord::Base.connection)
    end

    def render_fragment(partial:, locals: {})
      without_view_annotations do
        render_to_string(partial: partial, locals: locals)
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
end

# Route/controller lookup for "ripcity/noah" resolves Ripcity::NoahController.
# Keep this alias so we can use RipCity in code while satisfying Zeitwerk cpath checks.
module Ripcity
  NoahController = RipCity::NoahController
end
