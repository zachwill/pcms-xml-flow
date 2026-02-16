module DraftSelections
  class SidebarSelectionPayload
    def initialize(queries:, transaction_id:)
      @queries = queries
      @transaction_id = transaction_id
    end

    def build
      selection = queries.fetch_sidebar_selection(transaction_id)
      raise ActiveRecord::RecordNotFound unless selection

      {
        selection: selection,
        current_team: fetch_current_team(selection["player_id"]),
        provenance_rows: queries.fetch_pick_provenance_rows(
          draft_year: selection["draft_year"],
          draft_round: selection["draft_round"],
          drafting_team_code: selection["drafting_team_code"]
        )
      }
    end

    private

    attr_reader :queries, :transaction_id

    def fetch_current_team(player_id)
      return nil if player_id.blank?

      queries.fetch_current_team(player_id)
    end
  end
end
