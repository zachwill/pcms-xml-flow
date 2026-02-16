module Drafts
  class OverlayState
    def initialize(params:, view:, results:, grid_data:, queries:)
      @params = params
      @view = view
      @results = Array(results)
      @grid_data = grid_data || {}
      @queries = queries
    end

    def initial_overlay_state
      state = empty_overlay_state
      context = requested_overlay_context
      return state if context.blank?
      return state unless selected_overlay_visible?(context: context)

      case context[:type]
      when "pick"
        payload = @queries.fetch_sidebar_pick_payload(
          team_code: context[:team_code],
          draft_year: context[:draft_year],
          draft_round: context[:draft_round]
        )
        raise ActiveRecord::RecordNotFound unless payload

        state.merge(
          initial_overlay_type: "pick",
          initial_overlay_key: overlay_key_for_pick(
            team_code: context[:team_code],
            draft_year: context[:draft_year],
            draft_round: context[:draft_round]
          ),
          initial_overlay_partial: "drafts/rightpanel_overlay_pick",
          initial_overlay_locals: payload
        )
      when "selection"
        transaction_id = context[:transaction_id].to_i
        payload = @queries.fetch_sidebar_selection_payload(transaction_id)
        raise ActiveRecord::RecordNotFound unless payload

        state.merge(
          initial_overlay_type: "selection",
          initial_overlay_key: "selection-#{transaction_id}",
          initial_overlay_partial: "drafts/rightpanel_overlay_selection",
          initial_overlay_locals: payload
        )
      else
        state
      end
    rescue ActiveRecord::RecordNotFound
      empty_overlay_state
    end

    private

    def empty_overlay_state
      {
        initial_overlay_type: "none",
        initial_overlay_key: "",
        initial_overlay_partial: nil,
        initial_overlay_locals: {}
      }
    end

    def requested_overlay_context
      overlay_type = @params[:selected_type].to_s.strip.downcase
      overlay_key = @params[:selected_key].to_s.strip

      case overlay_type
      when "pick"
        parse_pick_overlay_key(overlay_key)
      when "selection"
        parse_selection_overlay_key(overlay_key)
      else
        nil
      end
    end

    def selected_overlay_visible?(context:)
      return false if context.blank?

      case context[:type]
      when "pick"
        return false unless %w[picks grid].include?(@view)

        selected_pick_visible?(
          team_code: context[:team_code],
          draft_year: context[:draft_year],
          draft_round: context[:draft_round]
        )
      when "selection"
        return false unless @view == "selections"

        @results.any? { |row| row["transaction_id"].to_i == context[:transaction_id].to_i }
      else
        false
      end
    end

    def overlay_key_for_pick(team_code:, draft_year:, draft_round:)
      key_prefix = @view == "grid" ? "grid" : "pick"
      "#{key_prefix}-#{team_code}-#{draft_year}-#{draft_round}"
    end

    def parse_pick_overlay_key(raw_key)
      match = raw_key.match(/\A(?:pick|grid)-([A-Za-z]{3})-(\d{4})-(\d+)\z/)
      return nil unless match

      team_code = match[1].to_s.upcase
      draft_year = match[2].to_i
      draft_round = match[3].to_i

      return nil if team_code.blank? || draft_year <= 0 || draft_round <= 0

      {
        type: "pick",
        team_code: team_code,
        draft_year: draft_year,
        draft_round: draft_round
      }
    end

    def parse_selection_overlay_key(raw_key)
      match = raw_key.match(/\Aselection-(\d+)\z/)
      return nil unless match

      transaction_id = match[1].to_i
      return nil if transaction_id <= 0

      {
        type: "selection",
        transaction_id: transaction_id
      }
    end

    def selected_pick_visible?(team_code:, draft_year:, draft_round:)
      if @view == "grid"
        @grid_data.dig(team_code, draft_round.to_i, draft_year.to_i).present?
      else
        @results.any? do |row|
          row["original_team_code"].to_s.upcase == team_code.to_s.upcase &&
            row["draft_year"].to_i == draft_year.to_i &&
            row["draft_round"].to_i == draft_round.to_i
        end
      end
    end
  end
end
