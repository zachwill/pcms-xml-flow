module Entities
  class TransactionsController < ApplicationController
    # GET /transactions
    def index
      load_index_state!
      render :index
    end

    # GET /transactions/pane (Datastar partial refresh)
    def pane
      load_index_state!
      render partial: "entities/transactions/results"
    end

    # GET /transactions/sidebar/base
    def sidebar_base
      load_index_state!
      render partial: "entities/transactions/rightpanel_base"
    end

    # GET /transactions/sidebar/:id
    def sidebar
      transaction_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if transaction_id <= 0

      render partial: "entities/transactions/rightpanel_overlay_transaction", locals: load_sidebar_transaction_payload(transaction_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /transactions/sidebar/clear
    def sidebar_clear
      render partial: "entities/transactions/rightpanel_clear"
    end

    # GET /transactions/:id
    def show
      id = Integer(params[:id])
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      @transaction = conn.exec_query(<<~SQL).first
        SELECT
          t.transaction_id,
          t.transaction_date,
          t.trade_finalized_date,
          t.transaction_type_lk,
          t.transaction_description_lk,
          t.record_status_lk,
          t.league_lk,
          t.salary_year,
          t.is_in_season,
          t.seqno,
          t.trade_id,
          t.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            t.player_id::text
          ) AS player_name,
          t.from_team_id,
          t.from_team_code,
          from_team.team_name AS from_team_name,
          t.to_team_id,
          t.to_team_code,
          to_team.team_name AS to_team_name,
          t.rights_team_id,
          t.rights_team_code,
          rights_team.team_name AS rights_team_name,
          t.sign_and_trade_team_id,
          t.sign_and_trade_team_code,
          sat_team.team_name AS sign_and_trade_team_name,
          t.contract_id,
          t.version_number,
          t.contract_type_lk,
          t.min_contract_lk,
          t.signed_method_lk,
          t.team_exception_id,
          t.free_agent_status_lk,
          t.free_agent_designation_lk,
          t.from_player_status_lk,
          t.to_player_status_lk,
          t.option_year,
          t.adjustment_amount,
          t.bonus_true_up_amount,
          t.draft_amount,
          t.draft_year,
          t.draft_round,
          t.draft_pick,
          t.comments
        FROM pcms.transactions t
        LEFT JOIN pcms.people p ON p.person_id = t.player_id
        LEFT JOIN pcms.teams from_team ON from_team.team_id = t.from_team_id
        LEFT JOIN pcms.teams to_team ON to_team.team_id = t.to_team_id
        LEFT JOIN pcms.teams rights_team ON rights_team.team_id = t.rights_team_id
        LEFT JOIN pcms.teams sat_team ON sat_team.team_id = t.sign_and_trade_team_id
        WHERE t.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @transaction

      @ledger_entries = conn.exec_query(<<~SQL).to_a
        SELECT
          le.transaction_ledger_entry_id,
          le.ledger_date,
          le.salary_year,
          le.team_id,
          team.team_code,
          team.team_name,
          le.transaction_type_lk,
          le.transaction_description_lk,
          le.cap_amount,
          le.cap_change,
          le.cap_value,
          le.tax_amount,
          le.tax_change,
          le.tax_value,
          le.apron_amount,
          le.apron_change,
          le.apron_value,
          le.mts_amount,
          le.mts_change,
          le.mts_value,
          le.trade_bonus_amount
        FROM pcms.ledger_entries le
        LEFT JOIN pcms.teams team
          ON team.team_id = le.team_id
        WHERE le.transaction_id = #{id_sql}
        ORDER BY le.ledger_date DESC, le.transaction_ledger_entry_id DESC
      SQL

      @draft_selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          ds.drafting_team_id,
          ds.drafting_team_code,
          ds.transaction_date
        FROM pcms.draft_selections ds
        WHERE ds.transaction_id = #{id_sql}
        LIMIT 1
      SQL

      @trade = nil
      @trade_transactions = []
      if @transaction["trade_id"].present?
        trade_sql = conn.quote(@transaction["trade_id"])

        @trade = conn.exec_query(<<~SQL).first
          SELECT
            tr.trade_id,
            tr.trade_date,
            tr.trade_finalized_date,
            tr.record_status_lk,
            COUNT(DISTINCT tt.team_id)::integer AS team_count,
            COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.player_id IS NOT NULL)::integer AS player_line_item_count,
            COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.draft_pick_year IS NOT NULL)::integer AS pick_line_item_count
          FROM pcms.trades tr
          LEFT JOIN pcms.trade_teams tt
            ON tt.trade_id = tr.trade_id
          LEFT JOIN pcms.trade_team_details ttd
            ON ttd.trade_id = tr.trade_id
          WHERE tr.trade_id = #{trade_sql}
          GROUP BY tr.trade_id, tr.trade_date, tr.trade_finalized_date, tr.record_status_lk
          LIMIT 1
        SQL

        @trade_transactions = conn.exec_query(<<~SQL).to_a
          SELECT
            t.transaction_id,
            t.transaction_date,
            t.transaction_type_lk,
            t.transaction_description_lk,
            t.player_id,
            COALESCE(
              NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
              NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
              t.player_id::text
            ) AS player_name,
            t.from_team_code,
            t.to_team_code
          FROM pcms.transactions t
          LEFT JOIN pcms.people p ON p.person_id = t.player_id
          WHERE t.trade_id = #{trade_sql}
          ORDER BY t.transaction_date, t.transaction_id
          LIMIT 80
        SQL
      end

      @endnotes = []
      if @transaction["trade_id"].present?
        trade_sql = conn.quote(@transaction["trade_id"])
        @endnotes = conn.exec_query(<<~SQL).to_a
          SELECT
            endnote_id,
            trade_id,
            trade_date,
            status_lk,
            explanation,
            conveyance_text,
            protections_text,
            contingency_text,
            exercise_text,
            is_swap,
            is_conditional
          FROM pcms.endnotes
          WHERE trade_id = #{trade_sql}
             OR trade_ids @> ARRAY[#{trade_sql}]::integer[]
          ORDER BY endnote_id
          LIMIT 50
        SQL
      end

      @cap_exception_usage_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          teu.team_exception_detail_id,
          teu.effective_date,
          teu.exception_action_lk,
          COALESCE(action_lk.short_description, action_lk.description) AS exception_action_label,
          teu.transaction_type_lk,
          COALESCE(tx_type_lk.short_description, tx_type_lk.description) AS transaction_type_label,
          teu.transaction_id,
          teu.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            teu.player_id::text
          ) AS player_name,
          teu.contract_id,
          teu.change_amount,
          teu.remaining_exception_amount,
          te.team_exception_id,
          te.team_id,
          team.team_code,
          team.team_name,
          te.exception_type_lk,
          COALESCE(exc_lk.short_description, exc_lk.description) AS exception_type_label,
          te.trade_id
        FROM pcms.team_exception_usage teu
        JOIN pcms.team_exceptions te
          ON te.team_exception_id = teu.team_exception_id
        LEFT JOIN pcms.teams team
          ON team.team_id = te.team_id
        LEFT JOIN pcms.people p
          ON p.person_id = teu.player_id
        LEFT JOIN pcms.lookups action_lk
          ON action_lk.lookup_type = 'lk_exception_actions'
         AND action_lk.lookup_code = teu.exception_action_lk
        LEFT JOIN pcms.lookups tx_type_lk
          ON tx_type_lk.lookup_type = 'lk_transaction_types'
         AND tx_type_lk.lookup_code = teu.transaction_type_lk
        LEFT JOIN pcms.lookups exc_lk
          ON exc_lk.lookup_type = 'lk_exception_types'
         AND exc_lk.lookup_code = te.exception_type_lk
        WHERE teu.transaction_id = #{id_sql}
        ORDER BY teu.effective_date DESC NULLS LAST, teu.seqno DESC NULLS LAST
        LIMIT 250
      SQL

      @cap_dead_money_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          twa.transaction_waiver_amount_id,
          twa.salary_year,
          twa.team_id,
          COALESCE(team.team_code, twa.team_code) AS team_code,
          team.team_name,
          twa.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            twa.player_id::text
          ) AS player_name,
          twa.contract_id,
          twa.version_number,
          twa.waive_date,
          twa.cap_value,
          twa.tax_value,
          twa.apron_value,
          twa.mts_value
        FROM pcms.transaction_waiver_amounts twa
        LEFT JOIN pcms.teams team
          ON team.team_id = twa.team_id
        LEFT JOIN pcms.people p
          ON p.person_id = twa.player_id
        WHERE twa.transaction_id = #{id_sql}
        ORDER BY twa.salary_year, COALESCE(team.team_code, twa.team_code), player_name
      SQL

      @cap_budget_snapshot_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          tbs.team_budget_snapshot_id,
          tbs.salary_year,
          tbs.team_id,
          COALESCE(team.team_code, tbs.team_code) AS team_code,
          team.team_name,
          tbs.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            tbs.player_id::text
          ) AS player_name,
          tbs.contract_id,
          tbs.version_number,
          tbs.transaction_type_lk,
          tbs.transaction_description_lk,
          tbs.budget_group_lk,
          COALESCE(group_lk.short_description, group_lk.description) AS budget_group_label,
          tbs.signing_method_lk,
          COALESCE(signing_lk.short_description, signing_lk.description) AS signing_method_label,
          tbs.option_lk,
          COALESCE(option_lk.short_description, option_lk.description) AS option_label,
          tbs.option_decision_lk,
          COALESCE(option_decision_lk.short_description, option_decision_lk.description) AS option_decision_label,
          tbs.cap_amount,
          tbs.tax_amount,
          tbs.apron_amount,
          tbs.mts_amount
        FROM pcms.team_budget_snapshots tbs
        LEFT JOIN pcms.teams team
          ON team.team_id = tbs.team_id
        LEFT JOIN pcms.people p
          ON p.person_id = tbs.player_id
        LEFT JOIN pcms.lookups group_lk
          ON group_lk.lookup_type = 'lk_budget_groups'
         AND group_lk.lookup_code = tbs.budget_group_lk
        LEFT JOIN pcms.lookups signing_lk
          ON signing_lk.lookup_type = 'lk_signed_methods'
         AND signing_lk.lookup_code = tbs.signing_method_lk
        LEFT JOIN pcms.lookups option_lk
          ON option_lk.lookup_type = 'lk_options'
         AND option_lk.lookup_code = tbs.option_lk
        LEFT JOIN pcms.lookups option_decision_lk
          ON option_decision_lk.lookup_type = 'lk_option_decisions'
         AND option_decision_lk.lookup_code = tbs.option_decision_lk
        WHERE tbs.transaction_id = #{id_sql}
        ORDER BY
          tbs.salary_year,
          COALESCE(team.team_code, tbs.team_code),
          tbs.player_id NULLS LAST,
          tbs.team_budget_snapshot_id
        LIMIT 300
      SQL

      render :show
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def load_index_state!
      conn = ActiveRecord::Base.connection

      @daterange = params[:daterange].to_s.strip.presence || "season"
      @team = params[:team].to_s.strip.upcase.presence
      @team = nil unless @team&.match?(/\A[A-Z]{3}\z/)
      @signings = params[:signings] != "0"
      @waivers = params[:waivers] != "0"
      @extensions = params[:extensions] != "0"
      @other = params[:other] == "1"
      @selected_transaction_id = normalize_selected_transaction_id_param(params[:selected_id])

      @team_options = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
        ORDER BY team_code
      SQL

      # Calculate date filters
      today = Date.today
      season_start = today.month >= 7 ? Date.new(today.year, 7, 1) : Date.new(today.year - 1, 7, 1)

      where_clauses = ["t.trade_id IS NULL"] # trades have their own workspace

      case @daterange
      when "today"
        where_clauses << "t.transaction_date = #{conn.quote(today)}"
      when "week"
        where_clauses << "t.transaction_date >= #{conn.quote(today - 7)}"
      when "month"
        where_clauses << "t.transaction_date >= #{conn.quote(today - 30)}"
      when "season"
        where_clauses << "t.transaction_date >= #{conn.quote(season_start)}"
      end

      selected_types = []
      selected_types.concat(%w[SIGN RSIGN]) if @signings
      selected_types.concat(%w[WAIVE WAIVR]) if @waivers
      selected_types << "EXTSN" if @extensions
      selected_types.uniq!

      if @other
        excluded = %w[SIGN RSIGN EXTSN WAIVE WAIVR TRADE]
        excluded_sql = excluded.map { |c| conn.quote(c) }.join(", ")

        if selected_types.any?
          selected_sql = selected_types.map { |c| conn.quote(c) }.join(", ")
          where_clauses << "(t.transaction_type_lk IN (#{selected_sql}) OR t.transaction_type_lk NOT IN (#{excluded_sql}))"
        else
          where_clauses << "t.transaction_type_lk NOT IN (#{excluded_sql})"
        end
      elsif selected_types.any?
        selected_sql = selected_types.map { |c| conn.quote(c) }.join(", ")
        where_clauses << "t.transaction_type_lk IN (#{selected_sql})"
      end

      if @team.present?
        where_clauses << "(t.from_team_code = #{conn.quote(@team)} OR t.to_team_code = #{conn.quote(@team)})"
      end

      @transactions = conn.exec_query(<<~SQL).to_a
        WITH filtered_transactions AS (
          SELECT
            t.transaction_id,
            t.transaction_date,
            t.transaction_type_lk,
            t.transaction_description_lk,
            t.trade_id,
            t.player_id,
            t.from_team_id,
            t.from_team_code,
            t.to_team_id,
            t.to_team_code,
            t.signed_method_lk,
            t.contract_type_lk
          FROM pcms.transactions t
          WHERE #{where_clauses.join(" AND ")}
          ORDER BY t.transaction_date DESC, t.transaction_id DESC
          LIMIT 200
        )
        SELECT
          t.transaction_id,
          t.transaction_date,
          t.transaction_type_lk,
          t.transaction_description_lk,
          t.trade_id,
          t.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            t.player_id::text
          ) AS player_name,
          t.from_team_id,
          t.from_team_code,
          from_team.team_name AS from_team_name,
          t.to_team_id,
          t.to_team_code,
          to_team.team_name AS to_team_name,
          t.signed_method_lk,
          t.contract_type_lk
        FROM filtered_transactions t
        LEFT JOIN pcms.people p
          ON p.person_id = t.player_id
        LEFT JOIN pcms.teams from_team
          ON from_team.team_id = t.from_team_id
        LEFT JOIN pcms.teams to_team
          ON to_team.team_id = t.to_team_id
        ORDER BY t.transaction_date DESC, t.transaction_id DESC
      SQL

      build_sidebar_summary!(selected_transaction_id: @selected_transaction_id)
    end

    def build_sidebar_summary!(selected_transaction_id: nil)
      rows = Array(@transactions)
      bucket_counts = {
        signings: rows.count { |row| transaction_bucket(row["transaction_type_lk"]) == :signings },
        waivers: rows.count { |row| transaction_bucket(row["transaction_type_lk"]) == :waivers },
        extensions: rows.count { |row| transaction_bucket(row["transaction_type_lk"]) == :extensions },
        other: rows.count { |row| transaction_bucket(row["transaction_type_lk"]) == :other }
      }

      active_type_filters = []
      active_type_filters << "Signings" if @signings
      active_type_filters << "Waivers" if @waivers
      active_type_filters << "Extensions" if @extensions
      active_type_filters << "Other" if @other

      filters = ["Date: #{daterange_label(@daterange)}"]
      filters << "Team: #{@team}" if @team.present?
      filters << "Types: #{active_type_filters.join(', ')}" if active_type_filters.any?

      top_rows = rows.first(14)
      selected_id = selected_transaction_id.to_i
      if selected_id.positive?
        selected_row = rows.find { |row| row["transaction_id"].to_i == selected_id }
        if selected_row.present? && top_rows.none? { |row| row["transaction_id"].to_i == selected_id }
          top_rows = [selected_row] + top_rows.first(13)
        end
      end

      @sidebar_summary = {
        row_count: rows.size,
        daterange_label: daterange_label(@daterange),
        filters:,
        signings_count: bucket_counts[:signings],
        waivers_count: bucket_counts[:waivers],
        extensions_count: bucket_counts[:extensions],
        other_count: bucket_counts[:other],
        top_rows:
      }
    end

    def load_sidebar_transaction_payload(transaction_id)
      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(transaction_id)

      transaction = conn.exec_query(<<~SQL).first
        SELECT
          t.transaction_id,
          t.transaction_date,
          t.transaction_type_lk,
          t.transaction_description_lk,
          t.salary_year,
          t.trade_id,
          t.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            t.player_id::text
          ) AS player_name,
          t.from_team_id,
          t.from_team_code,
          from_team.team_name AS from_team_name,
          t.to_team_id,
          t.to_team_code,
          to_team.team_name AS to_team_name,
          t.signed_method_lk,
          t.contract_type_lk
        FROM pcms.transactions t
        LEFT JOIN pcms.people p
          ON p.person_id = t.player_id
        LEFT JOIN pcms.teams from_team
          ON from_team.team_id = t.from_team_id
        LEFT JOIN pcms.teams to_team
          ON to_team.team_id = t.to_team_id
        WHERE t.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless transaction

      ledger_summary = conn.exec_query(<<~SQL).first || {}
        SELECT
          COUNT(*)::integer AS ledger_row_count,
          SUM(COALESCE(le.cap_change, 0)) AS cap_change_total,
          SUM(COALESCE(le.tax_change, 0)) AS tax_change_total,
          SUM(COALESCE(le.apron_change, 0)) AS apron_change_total
        FROM pcms.ledger_entries le
        WHERE le.transaction_id = #{id_sql}
      SQL

      artifact_summary = conn.exec_query(<<~SQL).first || {}
        SELECT
          (SELECT COUNT(*)::integer FROM pcms.team_exception_usage teu WHERE teu.transaction_id = #{id_sql}) AS exception_usage_count,
          (SELECT COUNT(*)::integer FROM pcms.transaction_waiver_amounts twa WHERE twa.transaction_id = #{id_sql}) AS dead_money_count,
          (SELECT COUNT(*)::integer FROM pcms.team_budget_snapshots tbs WHERE tbs.transaction_id = #{id_sql}) AS budget_snapshot_count
      SQL

      trade_summary = nil
      if transaction["trade_id"].present?
        trade_sql = conn.quote(transaction["trade_id"])
        trade_summary = conn.exec_query(<<~SQL).first
          SELECT
            tr.trade_id,
            tr.trade_date,
            COUNT(DISTINCT tt.team_id)::integer AS team_count,
            COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.player_id IS NOT NULL)::integer AS player_line_item_count,
            COUNT(ttd.trade_team_detail_id) FILTER (WHERE ttd.draft_pick_year IS NOT NULL)::integer AS pick_line_item_count
          FROM pcms.trades tr
          LEFT JOIN pcms.trade_teams tt
            ON tt.trade_id = tr.trade_id
          LEFT JOIN pcms.trade_team_details ttd
            ON ttd.trade_id = tr.trade_id
          WHERE tr.trade_id = #{trade_sql}
          GROUP BY tr.trade_id, tr.trade_date
          LIMIT 1
        SQL
      end

      {
        transaction:,
        ledger_summary:,
        artifact_summary:,
        trade_summary:
      }
    end

    def normalize_selected_transaction_id_param(raw)
      selected_id = Integer(raw.to_s.strip, 10)
      selected_id.positive? ? selected_id : nil
    rescue ArgumentError, TypeError
      nil
    end

    def selected_overlay_visible?(overlay_type:, overlay_id:)
      return false unless overlay_type.to_s == "transaction"

      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      Array(@transactions).any? { |row| row["transaction_id"].to_i == normalized_id }
    end

    def transaction_bucket(type_code)
      code = type_code.to_s.upcase
      return :signings if %w[SIGN RSIGN].include?(code)
      return :waivers if %w[WAIVE WAIVR].include?(code)
      return :extensions if code == "EXTSN"

      :other
    end

    def daterange_label(value)
      case value.to_s
      when "today" then "Today"
      when "week" then "This week"
      when "month" then "This month"
      when "season" then "This season"
      else "All dates"
      end
    end
  end
end
