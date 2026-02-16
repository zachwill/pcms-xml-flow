class TransactionsController < ApplicationController
  # GET /transactions
  def index
    load_index_state!
    render :index
  end

  # GET /transactions/pane (Datastar partial refresh)
  def pane
    load_index_state!
    render partial: "transactions/results"
  end

  # GET /transactions/sidebar/base
  def sidebar_base
    load_index_state!
    render partial: "transactions/rightpanel_base"
  end

  # GET /transactions/sidebar/:id
  def sidebar
    transaction_id = Integer(params[:id])
    raise ActiveRecord::RecordNotFound if transaction_id <= 0

    render partial: "transactions/rightpanel_overlay_transaction", locals: load_sidebar_transaction_payload(transaction_id)
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  # GET /transactions/sidebar/clear
  def sidebar_clear
    render partial: "transactions/rightpanel_clear"
  end

  # GET /transactions/:id
  def show
    id = Integer(params[:id])

    @transaction = queries.fetch_transaction(id)
    raise ActiveRecord::RecordNotFound unless @transaction

    @ledger_entries = queries.fetch_ledger_entries(id)
    @draft_selection = queries.fetch_draft_selection(id)

    @trade = nil
    @trade_transactions = []
    @endnotes = []

    if @transaction["trade_id"].present?
      trade_id = @transaction["trade_id"]
      @trade = queries.fetch_trade_summary(trade_id)
      @trade_transactions = queries.fetch_trade_transactions(trade_id)
      @endnotes = queries.fetch_endnotes(trade_id)
    end

    @cap_exception_usage_rows = queries.fetch_cap_exception_usage_rows(id)
    @cap_dead_money_rows = queries.fetch_cap_dead_money_rows(id)
    @cap_budget_snapshot_rows = queries.fetch_cap_budget_snapshot_rows(id)

    render :show
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  def queries
    @queries ||= ::TransactionQueries.new(connection: ActiveRecord::Base.connection)
  end

  def load_index_state!
    state = ::Transactions::IndexWorkspaceState.new(
      params: params,
      queries: queries
    ).build

    state.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
  end

  def load_sidebar_transaction_payload(transaction_id)
    transaction = queries.fetch_sidebar_transaction(transaction_id)
    raise ActiveRecord::RecordNotFound unless transaction

    ledger_summary = queries.fetch_sidebar_ledger_summary(transaction_id)
    artifact_summary = queries.fetch_sidebar_artifact_summary(transaction_id)

    trade_summary = if transaction["trade_id"].present?
      queries.fetch_sidebar_trade_summary(transaction["trade_id"])
    end

    {
      transaction:,
      ledger_summary:,
      artifact_summary:,
      trade_summary:
    }
  end

  def selected_overlay_visible?(overlay_type:, overlay_id:)
    return false unless overlay_type.to_s == "transaction"

    normalized_id = overlay_id.to_i
    return false if normalized_id <= 0

    Array(@transactions).any? { |row| row["transaction_id"].to_i == normalized_id }
  end
end
