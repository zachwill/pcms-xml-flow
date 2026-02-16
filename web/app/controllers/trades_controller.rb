class TradesController < ApplicationController
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

    render partial: "trades/rightpanel_overlay_trade", locals: load_sidebar_trade_payload(trade_id)
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

  def selected_overlay_visible?(overlay_type:, overlay_id:)
    return false unless overlay_type.to_s == "trade"
    return false unless overlay_id.to_i.positive?

    Array(@trades).any? { |row| row["trade_id"].to_i == overlay_id.to_i }
  end
end
