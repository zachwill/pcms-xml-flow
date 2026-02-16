module TwoWayUtility
  class OverlayState
    def initialize(rows:, team_meta_by_code:, selected_player_id:, queries:)
      @rows = rows
      @team_meta_by_code = team_meta_by_code || {}
      @selected_player_id = selected_player_id
      @queries = queries
    end

    def requested_overlay_id(raw_selected_id:)
      @selected_player_id || normalize_player_id(raw_selected_id)
    end

    def normalize_player_id(raw)
      player_id = Integer(raw.to_s.strip, 10)
      player_id.positive? ? player_id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def sidebar_player(player_id:)
      normalized_id = normalize_player_id(player_id)
      return nil unless normalized_id

      row = Array(@rows).find { |candidate| candidate["player_id"].to_i == normalized_id } || fetch_player_row(normalized_id)
      return nil unless row

      {
        sidebar_player: row,
        sidebar_team_meta: @team_meta_by_code[row["team_code"].to_s] || {}
      }
    end

    def source_player(player_id:)
      normalized_id = normalize_player_id(player_id)
      return nil unless normalized_id

      Array(@rows).find { |candidate| candidate["player_id"].to_i == normalized_id } || fetch_player_row(normalized_id)
    end

    # Preserve current behavior: refresh only keeps overlay when the selected row
    # remains visible in the currently filtered table rows.
    def refresh_sidebar_player(requested_overlay_id:)
      normalized_id = normalize_player_id(requested_overlay_id)
      return nil unless normalized_id

      row = Array(@rows).find { |candidate| candidate["player_id"].to_i == normalized_id }
      return nil unless row

      {
        sidebar_player: row,
        sidebar_team_meta: @team_meta_by_code[row["team_code"].to_s] || {}
      }
    end

    private

    def fetch_player_row(player_id)
      row = @queries.fetch_player_row(player_id)
      row.present? ? ::TwoWayUtility::WorkspaceState.decorate_row(row) : nil
    end
  end
end
