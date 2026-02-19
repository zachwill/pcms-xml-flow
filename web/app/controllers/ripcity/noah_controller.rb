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
      { key: "23-24-season", label: "23-24 Season" },
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
        caption: "Catch & Shoot 3PA only includes Noah tagged spot-up jumpers.",
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
      "above-break-3pa" => {
        label: "Above Break 3PA",
        caption: "All above-break three-point attempts (corner threes removed).",
        is_three: 1,
        shot_type: nil,
        is_corner_three: 0
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
      { key: "stat-values", label: "Stat Values" },
      { key: "consistency-grades", label: "Consistency Grades" }
    ].freeze

    SORT_OPTIONS = [
      { key: "attempts-desc", label: "Shot Volume" },
      { key: "fg-pct-desc", label: "Shot %" },
      { key: "swish-desc", label: "Swish %" },
      { key: "name-asc", label: "A → Z" },
      { key: "angle-close", label: "Angle" },
      { key: "depth-close", label: "Depth" },
      { key: "lr-close", label: "L/R" },
      { key: "consistency-best", label: "Consistency" }
    ].freeze

    # Static shotchart calibration by lens (p10..p90 FG% across player-zone cells, attempts >= 10).
    # This keeps colors comparable across players for the same lens.
    SHOTCHART_HEAT_SCALE_BY_SHOT_LENS = {
      "all-3pa" => { min: 37.5, max: 68.8 },
      "catch-shoot-3pa" => { min: 40.0, max: 71.1 },
      "cs-above-break-3pa" => { min: 38.9, max: 70.0 },
      "cs-corner-3pa" => { min: 42.4, max: 71.9 },
      "off-dribble-3pa" => { min: 30.9, max: 63.6 },
      "corner-3pa" => { min: 40.7, max: 70.2 },
      "above-break-3pa" => { min: 35.1, max: 67.3 },
      "form-shooting" => { min: 50.0, max: 88.0 },
      "all-fga" => { min: 41.7, max: 77.8 }
    }.freeze

    DEFAULT_TIMEFRAME = "25-26-season"
    DEFAULT_SHOT_LENS = "catch-shoot-3pa"
    DEFAULT_GRADE_LENS = "stat-values"
    DEFAULT_PERCENTILE_LENS = "consistency"
    DEFAULT_SORT = "attempts-desc"
    SPARKLINE_SHOT_LENS = "all-3pa"
    SPARKLINE_POINT_LIMIT = 18

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

    ANGLE_CONSISTENCY_THRESHOLDS = [
      [1.34, "A+"],
      [1.45, "A"],
      [1.51, "B+"],
      [1.61, "B"],
      [1.71, "C+"],
      [1.84, "C"],
      [1.98, "D+"],
      [2.10, "D"],
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
      @sort_options = SORT_OPTIONS

      @timeframe_lens = resolve_timeframe(params[:timeframe])
      @shot_lens = resolve_shot_lens(params[:shot_lens])
      @grade_lens = resolve_grade_lens(params[:grade_lens])
      @percentile_lens = resolve_percentile_lens(params[:percentile_lens])
      @sort_lens = resolve_sort(params[:sort])

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

      sparkline_lens = SHOT_LENS_OPTIONS.fetch(SPARKLINE_SHOT_LENS)
      sparkline_filters = {
        is_three: sparkline_lens[:is_three],
        shot_type: sparkline_lens[:shot_type],
        is_corner_three: sparkline_lens[:is_corner_three]
      }

      all_time_3pa_by_noah_id = queries.fetch_player_lens_totals(
        include_predraft: @include_predraft,
        exclude_player_ids: @exclude_player_ids,
        **sparkline_filters
      ).each_with_object({}) do |row, memo|
        memo[row["noah_id"].to_i] = row["total_attempts"].to_i
      end

      player_rows = build_player_rows(
        raw_players,
        all_time_attempts_by_noah_id: all_time_3pa_by_noah_id
      ).select { |row| row["attempts"].to_i >= @min_attempts }
      player_rows = sort_player_rows(player_rows, @sort_lens)
      player_rows = attach_percentiles(player_rows, percentile_lens: @percentile_lens)

      sparkline_points_by_noah_id = build_sparkline_points_by_noah_id(
        queries.fetch_player_lens_weekly_totals(
          include_predraft: @include_predraft,
          exclude_player_ids: @exclude_player_ids,
          noah_ids: player_rows.map { |row| row["noah_id"] },
          **sparkline_filters
        )
      )

      @players = player_rows.map do |row|
        noah_id = row["noah_id"].to_i
        row.merge("sparkline_points" => sparkline_points_by_noah_id.fetch(noah_id, []))
      end

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
        shot_lens: @shot_lens,
        heat_scale: shotchart_heat_scale_for(@shot_lens),
        player_name: @selected_player&.dig("player_name"),
        updated_at: Time.current.iso8601
      }
    end

    def assign_workspace_fallback!(error:)
      @timeframe_options = TIMEFRAME_OPTIONS
      @shot_lens_options = SHOT_LENS_OPTIONS
      @grade_lens_options = GRADE_LENS_OPTIONS
      @sort_options = SORT_OPTIONS

      @timeframe_lens = DEFAULT_TIMEFRAME
      @shot_lens = DEFAULT_SHOT_LENS
      @grade_lens = DEFAULT_GRADE_LENS
      @percentile_lens = DEFAULT_PERCENTILE_LENS
      @sort_lens = DEFAULT_SORT
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
        shot_lens: @shot_lens,
        heat_scale: shotchart_heat_scale_for(@shot_lens),
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

      normalized = case key
      when "stat-values", "joe-stats", "raw-values", "noah-grades"
        "stat-values"
      when "consistency-grades", "consistency"
        "consistency-grades"
      else
        nil
      end

      GRADE_LENS_OPTIONS.any? { |option| option[:key] == normalized } ? normalized : DEFAULT_GRADE_LENS
    end

    def resolve_percentile_lens(raw)
      key = raw.to_s.strip

      case key
      when "noah", "noah-system", "noah-ideals", "ideal-values"
        "noah-ideals"
      when "consistency", "consistency-based"
        "consistency"
      else
        DEFAULT_PERCENTILE_LENS
      end
    end

    def resolve_sort(raw)
      key = raw.to_s.strip
      SORT_OPTIONS.any? { |option| option[:key] == key } ? key : DEFAULT_SORT
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
          label: "24-25 Season",
          start_date: Date.new(2024, 8, 1),
          end_date: Date.new(2025, 4, 15)
        }
      when "23-24-season"
        {
          label: "23-24 Season",
          start_date: Date.new(2023, 8, 1),
          end_date: Date.new(2024, 4, 15)
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
          label: "25-26 Season",
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
      when "consistency-grades"
        {
          one: "ANGLE Σ",
          two: "DEPTH Σ",
          three: "L/R Σ",
          consistency: "CONSISTENCY Σ"
        }
      else
        {
          one: "Angle",
          two: "Depth",
          three: "L/R",
          consistency: "Consistency"
        }
      end
    end

    def shotchart_heat_scale_for(shot_lens)
      scale = SHOTCHART_HEAT_SCALE_BY_SHOT_LENS.fetch(shot_lens.to_s, SHOTCHART_HEAT_SCALE_BY_SHOT_LENS.fetch(DEFAULT_SHOT_LENS))

      {
        min: scale.fetch(:min).to_f,
        max: scale.fetch(:max).to_f
      }
    end

    def build_player_rows(raw_rows, all_time_attempts_by_noah_id: {})
      Array(raw_rows).map do |row|
        noah_id = row["noah_id"].to_i
        angle = as_float(row["angle_mean"])
        depth = as_float(row["depth_mean"])
        left_right = as_float(row["left_right_mean"])
        angle_std = as_float(row["angle_std"])
        depth_std = as_float(row["depth_std"])
        left_right_std = as_float(row["left_right_std"])

        consistency_score = if depth_std || left_right_std
          depth_std.to_f + left_right_std.to_f
        end

        {
          "noah_id" => noah_id,
          "nba_id" => row["nba_id"].presence&.to_i,
          "player_name" => row["player_name"].presence || "Unknown Player",
          "roster_group" => row["roster_group"].presence,
          "attempts" => row["count"].to_i,
          "all_time_attempts" => all_time_attempts_by_noah_id.fetch(noah_id, 0),
          "fg_pct" => as_float(row["made_mean"]) || 0.0,
          "swish_pct" => as_float(row["is_swish_mean"]) || 0.0,
          "angle" => angle,
          "depth" => depth,
          "left_right" => left_right,
          "angle_std" => angle_std,
          "depth_std" => depth_std,
          "left_right_std" => left_right_std,
          "consistency_score" => consistency_score,
          "angle_grade" => noah_angle_grade(angle),
          "depth_grade" => noah_depth_grade(depth),
          "left_right_grade" => noah_left_right_grade(left_right),
          "angle_consistency_grade" => consistency_grade_for(angle_std, ANGLE_CONSISTENCY_THRESHOLDS),
          "depth_consistency_grade" => consistency_grade_for(depth_std, DEPTH_CONSISTENCY_THRESHOLDS),
          "left_right_consistency_grade" => consistency_grade_for(left_right_std, LEFT_RIGHT_CONSISTENCY_THRESHOLDS),
          "consistency_grade" => consistency_grade_for(consistency_score, CONSISTENCY_THRESHOLDS)
        }
      end
    end

    def sort_player_rows(rows, sort_lens)
      case sort_lens.to_s
      when "fg-pct-desc"
        rows.sort_by do |row|
          value = row["fg_pct"]
          [value.nil? ? 1 : 0, -(value || 0.0).to_f, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "swish-desc"
        rows.sort_by do |row|
          value = row["swish_pct"]
          [value.nil? ? 1 : 0, -(value || 0.0).to_f, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "angle-close"
        rows.sort_by do |row|
          angle = row["angle"]
          [angle.nil? ? 1 : 0, (angle.to_f - 45.0).abs, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "depth-close"
        rows.sort_by do |row|
          depth = row["depth"]
          [depth.nil? ? 1 : 0, (depth.to_f - 11.0).abs, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "lr-close"
        rows.sort_by do |row|
          left_right = row["left_right"]
          [left_right.nil? ? 1 : 0, left_right.to_f.abs, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "consistency-best"
        rows.sort_by do |row|
          consistency = row["consistency_score"]
          [consistency.nil? ? 1 : 0, consistency.to_f, -row["attempts"].to_i, row["player_name"].to_s]
        end
      when "name-asc"
        rows.sort_by { |row| [row["player_name"].to_s, -row["attempts"].to_i] }
      else
        rows.sort_by { |row| [-row["attempts"].to_i, row["player_name"].to_s] }
      end
    end

    def attach_percentiles(rows, percentile_lens:)
      metric_one_percentiles, metric_two_percentiles, metric_three_percentiles = metric_percentile_maps(rows, percentile_lens: percentile_lens)

      attempts_percentiles = percentile_map(rows) { |row| row["attempts"] }
      fg_pct_percentiles = percentile_map(rows) { |row| row["fg_pct"] }
      swish_pct_percentiles = percentile_map(rows) { |row| row["swish_pct"] }
      consistency_percentiles = percentile_map(rows) { |row| row["consistency_score"].nil? ? nil : -row["consistency_score"].to_f }

      rows.map do |row|
        noah_id = row["noah_id"].to_i

        row.merge(
          "percentiles" => {
            "attempts" => attempts_percentiles[noah_id],
            "fg_pct" => fg_pct_percentiles[noah_id],
            "swish_pct" => swish_pct_percentiles[noah_id],
            "metric_one" => metric_one_percentiles[noah_id],
            "metric_two" => metric_two_percentiles[noah_id],
            "metric_three" => metric_three_percentiles[noah_id],
            "consistency" => consistency_percentiles[noah_id]
          }
        )
      end
    end

    def metric_percentile_maps(rows, percentile_lens:)
      case percentile_lens.to_s
      when "noah-ideals"
        [
          percentile_map(rows) { |row| row["angle"].nil? ? nil : -(row["angle"].to_f - 45.0).abs },
          percentile_map(rows) { |row| row["depth"].nil? ? nil : -(row["depth"].to_f - 11.0).abs },
          percentile_map(rows) { |row| row["left_right"].nil? ? nil : -row["left_right"].to_f.abs }
        ]
      else
        [
          percentile_map(rows) { |row| row["angle_std"].nil? ? nil : -row["angle_std"].to_f },
          percentile_map(rows) { |row| row["depth_std"].nil? ? nil : -row["depth_std"].to_f },
          percentile_map(rows) { |row| row["left_right_std"].nil? ? nil : -row["left_right_std"].to_f }
        ]
      end
    end

    def percentile_map(rows)
      scored_rows = Array(rows).filter_map do |row|
        noah_id = row["noah_id"].to_i
        value = yield(row)
        next if noah_id <= 0 || value.nil?

        [noah_id, value.to_f]
      end

      return {} if scored_rows.empty?
      return { scored_rows.first.first => 1.0 } if scored_rows.length == 1

      ranked_rows = scored_rows.sort_by { |_noah_id, value| value }
      denominator = (ranked_rows.length - 1).to_f

      ranked_rows.each_with_index.each_with_object({}) do |((noah_id, _value), index), result|
        result[noah_id] = (index.to_f / denominator).round(4)
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

    def build_sparkline_points_by_noah_id(raw_rows, point_limit: SPARKLINE_POINT_LIMIT)
      grouped = Array(raw_rows).group_by { |row| row["noah_id"].to_i }

      grouped.each_with_object({}) do |(noah_id, rows), memo|
        next if noah_id <= 0

        shots = rows.map { |row| row["shots"].to_i }
        memo[noah_id] = compress_sparkline_points(shots, point_limit: point_limit)
      end
    end

    def compress_sparkline_points(points, point_limit: SPARKLINE_POINT_LIMIT)
      values = Array(points).map { |value| [value.to_i, 0].max }
      return values if values.length <= point_limit
      return [] if point_limit <= 0
      return [values.first] if point_limit == 1

      step = (values.length - 1).to_f / (point_limit - 1)

      Array.new(point_limit) do |index|
        values[(index * step).round]
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
