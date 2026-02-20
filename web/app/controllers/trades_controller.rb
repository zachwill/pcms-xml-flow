class TradesController < ApplicationController
  LONG_IMPACT_MAP_THRESHOLD = 4
  LONG_IMPACT_MAP_VISIBLE_COUNT = 2

  # GET /trades
  def index
    load_index_state!
    render :index
  end

  # GET /trades/pane (Datastar partial refresh)
  def pane
    load_index_state!
    render partial: "trades/results"
  end

  # GET /trades/sidebar/base
  def sidebar_base
    load_index_state!
    render partial: "trades/rightpanel_base"
  end

  # GET /trades/sidebar/:id
  def sidebar
    trade_id = Integer(params[:id])
    raise ActiveRecord::RecordNotFound if trade_id <= 0

    render partial: "trades/rightpanel_overlay_trade", locals: load_sidebar_trade_payload(trade_id).merge(
      overlay_trade_id: trade_id.to_s
    )
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /trades/sidebar/clear
  def sidebar_clear
    render partial: "trades/rightpanel_clear"
  end

  # GET /trades/:id
  def show
    id = Integer(params[:id])

    @trade = queries.fetch_trade_show(id)
    raise ActiveRecord::RecordNotFound unless @trade

    @trade_teams = queries.fetch_trade_teams(id)
    @player_details = queries.fetch_player_details(id)
    @pick_details = queries.fetch_pick_details(id)
    @cash_details = queries.fetch_cash_details(id)
    @draft_pick_trades = queries.fetch_draft_pick_trades(id)
    @transactions = queries.fetch_transactions(id)
    @endnotes = queries.fetch_endnotes(id)
    @trade_group_rows = queries.fetch_trade_group_rows(id)
    @trade_group_exception_rows = queries.fetch_trade_group_exception_rows(id)

    render :show
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::TradeQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_state!
    state = ::Trades::IndexWorkspaceState.new(
      params: params,
      queries: queries
    ).build

    prepare_trade_scan_impacts!(rows: state[:trades], focus_team_code: state[:team])

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def load_sidebar_trade_payload(trade_id)
    trade = queries.fetch_sidebar_trade(trade_id)
    raise ActiveRecord::RecordNotFound unless trade

    team_anatomy_rows = queries.fetch_sidebar_team_anatomy_rows(trade_id)
    asset_rows = queries.fetch_sidebar_asset_rows(trade_id)
    related_transactions = queries.fetch_sidebar_related_transactions(trade_id)

    {
      trade:,
      team_anatomy_rows:,
      asset_rows:,
      related_transactions:
    }
  end

  def prepare_trade_scan_impacts!(rows:, focus_team_code:)
    normalized_focus_code = focus_team_code.to_s.upcase.presence

    Array(rows).each do |row|
      ordered_impacts = order_trade_team_impacts(
        Array(row["team_impacts"]),
        focus_team_code: normalized_focus_code
      )

      visible_count = if ordered_impacts.size >= LONG_IMPACT_MAP_THRESHOLD
        LONG_IMPACT_MAP_VISIBLE_COUNT
      else
        ordered_impacts.size
      end

      row["scan_team_impacts"] = ordered_impacts.first(visible_count)
      row["scan_additional_team_impact_count"] = [ordered_impacts.size - visible_count, 0].max
    end
  end

  def order_trade_team_impacts(impacts, focus_team_code:)
    normalized_impacts = Array(impacts)
    return normalized_impacts if normalized_impacts.empty?
    return normalized_impacts if focus_team_code.blank?

    focus_rows, non_focus_rows = normalized_impacts.partition do |impact|
      impact["team_code"].to_s.upcase == focus_team_code
    end

    focus_rows + non_focus_rows.sort_by { |impact| trade_team_impact_sort_key(impact) }
  end

  def trade_team_impact_sort_key(impact)
    normalized_code = impact["team_code"].to_s.upcase
    [normalized_code.present? ? 0 : 1, normalized_code.presence || "ZZZ", impact["team_id"].to_i]
  end

  def selected_overlay_visible?(overlay_type:, overlay_id:)
    return false unless overlay_type.to_s == "trade"
    return false unless overlay_id.to_i.positive?

    Array(@trades).any? { |row| row["trade_id"].to_i == overlay_id.to_i }
  end
end
