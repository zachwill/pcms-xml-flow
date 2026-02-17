module SalaryBook
  module PercentileHelper
    # Convert a percentile (0..1) into a 0..4 bucket (for a 4-block display).
    def pct_cap_percentile_bucket(percentile)
      return 0 if percentile.nil?

      p = percentile.to_f
      return 0 if p < 0
      return 4 if p >= 1

      (p * 5).floor.clamp(0, 4)
    end

    def pct_cap_blocks(percentile)
      return "" if percentile.nil?

      # Use parallelograms (easier to scan on iPad than small square glyphs).
      filled = "▰"
      empty = "▱"
      bucket = pct_cap_percentile_bucket(percentile)

      (filled * bucket) + (empty * (4 - bucket))
    end

    # Returns a hash: { label: "30%", blocks: "▰▰▱▱" }
    def format_pct_cap_with_blocks(player, year)
      return nil if player["is_min_contract"]

      pct = player["pct_cap_#{year}"]
      return nil if pct.nil? || pct.to_f <= 0

      pct_value = (pct.to_f * 100).round
      label = pct_value < 10 ? "\u00A0#{pct_value}%" : "#{pct_value}%"

      percentile = player["pct_cap_percentile_#{year}"]
      blocks = pct_cap_blocks(percentile)

      { label: label, blocks: blocks }
    end

    # Back-compat: return label-only string.
    def format_pct_cap(player, year)
      formatted = format_pct_cap_with_blocks(player, year)
      formatted ? formatted[:label] : nil
    end

    # Dunks EPM percentiles are stored on a 0..100 scale.
    # Gracefully accepts 0..1 input too.
    def normalize_percentile_01(percentile)
      return nil if percentile.nil?

      p = percentile.to_f
      p = p / 100.0 if p > 1
      p.clamp(0.0, 1.0)
    end

    def epm_percentile_blocks(percentile, bucket_count: 4)
      p01 = normalize_percentile_01(percentile)
      return "" if p01.nil?

      filled = "▰"
      empty = "▱"
      filled_count = (p01 * bucket_count).round.clamp(0, bucket_count)

      (filled * filled_count) + (empty * (bucket_count - filled_count))
    end

    def epm_percentile_int(percentile)
      p01 = normalize_percentile_01(percentile)
      return nil if p01.nil?

      (p01 * 100).round.clamp(0, 100)
    end

    def format_percentile_label(percentile)
      p_int = epm_percentile_int(percentile)
      return nil if p_int.nil?

      "#{p_int} percentile"
    end

    def epm_percentile_color_class(percentile)
      p_int = epm_percentile_int(percentile)
      return nil if p_int.nil?

      return "text-green-700 dark:text-green-300" if p_int >= 80
      return "text-red-700 dark:text-red-300" if p_int <= 20

      "text-zinc-700 dark:text-zinc-300"
    end

    # Younger players should read as better (higher percentile -> younger).
    # Returns { player_id => percentile_01 } using age ranks inside the provided roster.
    def age_percentiles_by_player_id(players)
      rows = Array(players).filter_map do |player|
        player_id = player["player_id"]
        age_raw = player["age"]
        next if player_id.blank? || age_raw.nil? || age_raw.to_s.strip.empty?

        age = age_raw.to_f
        next if age.nan?

        { player_id:, age: }
      end

      return {} if rows.empty?

      sorted = rows.sort_by { |row| [row[:age], row[:player_id].to_s] }
      count = sorted.length

      if count == 1
        only_player_id = sorted.first[:player_id]
        return { only_player_id => 0.5 }
      end

      grouped_by_age = sorted.group_by { |row| row[:age] }
      running_index = 0
      result = {}

      grouped_by_age.keys.sort.each do |age|
        group = grouped_by_age[age]
        start_idx = running_index
        end_idx = running_index + group.length - 1
        avg_idx = (start_idx + end_idx) / 2.0
        percentile = 1.0 - (avg_idx / (count - 1))

        group.each { |row| result[row[:player_id]] = percentile }
        running_index = end_idx + 1
      end

      result
    end

    def age_percentile_color_class(percentile)
      p_int = epm_percentile_int(percentile)
      return nil if p_int.nil?

      return "text-emerald-600 dark:text-emerald-400" if p_int >= 80
      return "text-red-700/80 dark:text-red-400/80" if p_int <= 20

      nil
    end

    # Representation KPI percentile helpers (agents/agencies)
    def representation_percentile_int(percentile)
      p01 = normalize_percentile_01(percentile)
      return nil if p01.nil?

      (p01 * 100).round.clamp(0, 100)
    end

    def representation_percentile_blocks(percentile, bucket_count: 5)
      p01 = normalize_percentile_01(percentile)
      return "" if p01.nil?

      filled = "▰"
      empty = "▱"
      filled_count = (p01 * bucket_count).round.clamp(0, bucket_count)

      (filled * filled_count) + (empty * (bucket_count - filled_count))
    end

    def representation_percentile_label(percentile)
      p_int = representation_percentile_int(percentile)
      return nil if p_int.nil?

      if p_int >= 50
        top = [100 - p_int, 1].max
        "P#{p_int} · Top #{top}%"
      else
        bottom = [p_int, 1].max
        "P#{p_int} · Bottom #{bottom}%"
      end
    end

    def representation_percentile_color_class(percentile)
      p_int = representation_percentile_int(percentile)
      return "text-muted-foreground/70" if p_int.nil?

      return "text-violet-700 dark:text-violet-300" if p_int >= 95
      return "text-violet-600 dark:text-violet-400" if p_int >= 80
      return "text-violet-500 dark:text-violet-500" if p_int >= 60
      return "text-muted-foreground/90" if p_int >= 40
      return "text-muted-foreground/80" if p_int >= 20

      "text-muted-foreground/70"
    end
  end
end
