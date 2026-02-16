module DraftSelections
  class ShowWorkspaceData
    def initialize(queries:, draft_selection_id:)
      @queries = queries
      @draft_selection_id = draft_selection_id
    end

    def build
      draft_selection = queries.fetch_show_selection(draft_selection_id)
      raise ActiveRecord::RecordNotFound unless draft_selection

      current_team = fetch_current_team(draft_selection["player_id"])
      pick_provenance_rows = queries.fetch_pick_provenance_rows(
        draft_year: draft_selection["draft_year"],
        draft_round: draft_selection["draft_round"],
        drafting_team_code: draft_selection["drafting_team_code"]
      )

      {
        draft_selection: draft_selection,
        current_team: current_team,
        pick_provenance_rows: pick_provenance_rows
      }
    end

    private

    attr_reader :queries, :draft_selection_id

    def fetch_current_team(player_id)
      return nil if player_id.blank?

      queries.fetch_current_team(player_id)
    end
  end
end
