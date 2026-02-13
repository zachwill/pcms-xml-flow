module Entities
  class DraftSelectionsController < ApplicationController
    INDEX_ROUNDS = %w[all 1 2].freeze

    # GET /draft-selections
    def index
      load_index_workspace_state!
      render :index
    end

    # GET /draft-selections/pane
    def pane
      load_index_workspace_state!
      render partial: "entities/draft_selections/workspace_main"
    end

    # GET /draft-selections/sidebar/base
    def sidebar_base
      load_index_workspace_state!
      render partial: "entities/draft_selections/rightpanel_base"
    end

    # GET /draft-selections/sidebar/:id
    def sidebar
      transaction_id = Integer(params[:id])
      raise ActiveRecord::RecordNotFound if transaction_id <= 0

      render partial: "entities/draft_selections/rightpanel_overlay_selection", locals: load_sidebar_selection_payload(transaction_id)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    # GET /draft-selections/sidebar/clear
    def sidebar_clear
      render partial: "entities/draft_selections/rightpanel_clear"
    end

    # GET /draft-selections/:slug
    def show
      slug = params[:slug].to_s.strip.downcase
      raise ActiveRecord::RecordNotFound if slug.blank?

      record = Slug.find_by!(entity_type: "draft_selection", slug: slug)

      canonical = Slug.find_by(entity_type: "draft_selection", entity_id: record.entity_id, canonical: true)
      if canonical && canonical.slug != record.slug
        redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
        return
      end

      @draft_selection_id = record.entity_id
      @draft_selection_slug = record.slug

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(@draft_selection_id)

      @draft_selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          ds.drafting_team_id,
          ds.drafting_team_code,
          ds.draft_amount,
          ds.transaction_date,
          tx.trade_id,
          tx.transaction_type_lk,
          tx.transaction_description_lk,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ''
          ) AS player_name,
          t.team_name
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.transactions tx ON tx.transaction_id = ds.transaction_id
        LEFT JOIN pcms.people p ON p.person_id = ds.player_id
        LEFT JOIN pcms.teams t ON t.team_id = ds.drafting_team_id
        WHERE ds.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless @draft_selection

      player_sql = conn.quote(@draft_selection["player_id"])
      @current_team = conn.exec_query(<<~SQL).first
        SELECT
          sbw.team_code,
          t.team_id,
          t.team_name
        FROM pcms.salary_book_warehouse sbw
        LEFT JOIN pcms.teams t
          ON t.team_code = sbw.team_code
         AND t.league_lk = 'NBA'
        WHERE sbw.player_id = #{player_sql}
        LIMIT 1
      SQL

      year_sql = conn.quote(@draft_selection["draft_year"])
      round_sql = conn.quote(@draft_selection["draft_round"])
      drafting_code_sql = conn.quote(@draft_selection["drafting_team_code"])

      @pick_provenance_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          dpt.id,
          dpt.trade_id,
          tr.trade_date,
          dpt.draft_year,
          dpt.draft_round,
          dpt.from_team_id,
          dpt.from_team_code,
          dpt.to_team_id,
          dpt.to_team_code,
          dpt.original_team_id,
          dpt.original_team_code,
          dpt.is_swap,
          dpt.is_future,
          dpt.is_conditional,
          dpt.conditional_type_lk,
          dpt.is_draft_year_plus_two
        FROM pcms.draft_pick_trades dpt
        LEFT JOIN pcms.trades tr
          ON tr.trade_id = dpt.trade_id
        WHERE dpt.draft_year = #{year_sql}
          AND dpt.draft_round = #{round_sql}
          AND (
            dpt.original_team_code = #{drafting_code_sql}
            OR dpt.from_team_code = #{drafting_code_sql}
            OR dpt.to_team_code = #{drafting_code_sql}
          )
        ORDER BY tr.trade_date NULLS LAST, dpt.id
        LIMIT 120
      SQL

      render :show
    end

    # GET /draft-selections/:id (numeric fallback)
    def redirect
      id = Integer(params[:id])

      canonical = Slug.find_by(entity_type: "draft_selection", entity_id: id, canonical: true)
      if canonical
        redirect_to draft_selection_path(canonical.slug), status: :moved_permanently
        return
      end

      conn = ActiveRecord::Base.connection
      id_sql = conn.quote(id)

      row = conn.exec_query(<<~SQL).first
        SELECT
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ''
          ) AS player_name
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.people p ON p.person_id = ds.player_id
        WHERE ds.transaction_id = #{id_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless row

      parts = [
        "draft",
        row["draft_year"],
        "r#{row['draft_round']}",
        "p#{row['pick_number']}",
        row["player_name"].to_s.parameterize.presence,
      ].compact

      base = parts.join("-")
      base = "draft-selection-#{id}" if base.blank?

      slug = base
      i = 2
      while Slug.reserved_slug?(slug) || Slug.exists?(entity_type: "draft_selection", slug: slug)
        slug = "#{base}-#{i}"
        i += 1
      end

      Slug.create!(entity_type: "draft_selection", entity_id: id, slug: slug, canonical: true)

      redirect_to draft_selection_path(slug), status: :moved_permanently
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    private

    def load_index_workspace_state!
      setup_index_filters!
      load_index_dimensions!
      load_index_rows!
      build_sidebar_summary!
    end

    def setup_index_filters!
      @query = params[:q].to_s.strip
      @round_lens = normalize_round_param(params[:round]) || "all"
      @team_lens = normalize_team_code_param(params[:team]) || ""
    end

    def load_index_dimensions!
      conn = ActiveRecord::Base.connection

      @year_options = conn.exec_query(<<~SQL).rows.flatten.map(&:to_i)
        SELECT DISTINCT draft_year
        FROM pcms.draft_selections
        ORDER BY draft_year DESC
      SQL

      requested_year = normalize_year_param(params[:year])
      @year_lens = if requested_year.present? && @year_options.include?(requested_year)
        requested_year.to_s
      elsif @year_options.any?
        @year_options.first.to_s
      else
        Date.today.year.to_s
      end

      @team_options = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_name
        FROM pcms.teams
        WHERE league_lk = 'NBA'
          AND team_name NOT LIKE 'Non-NBA%'
        ORDER BY team_code
      SQL
    end

    def load_index_rows!
      conn = ActiveRecord::Base.connection

      where_clauses = ["ds.draft_year = #{conn.quote(@year_lens.to_i)}"]
      where_clauses << "ds.draft_round = #{conn.quote(@round_lens.to_i)}" if @round_lens != "all"
      where_clauses << "ds.drafting_team_code = #{conn.quote(@team_lens)}" if @team_lens.present?

      if @query.present?
        if @query.match?(/\A\d+\z/)
          query_value = @query.to_i
          where_clauses << <<~SQL.squish
            (
              ds.player_id = #{conn.quote(query_value)}
              OR ds.transaction_id = #{conn.quote(query_value)}
              OR ds.pick_number = #{conn.quote(query_value)}
            )
          SQL
        else
          query_sql = conn.quote("%#{@query}%")
          where_clauses << <<~SQL.squish
            (
              COALESCE(NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''), NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), '')) ILIKE #{query_sql}
              OR ds.drafting_team_code ILIKE #{query_sql}
              OR COALESCE(t.team_name, '') ILIKE #{query_sql}
            )
          SQL
        end
      end

      @results = conn.exec_query(<<~SQL).to_a
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ds.player_id::text
          ) AS player_name,
          ds.drafting_team_id,
          ds.drafting_team_code,
          t.team_name AS drafting_team_name,
          ds.transaction_date,
          tx.trade_id,
          tx.transaction_type_lk,
          (
            SELECT COUNT(*)::integer
            FROM pcms.draft_pick_trades dpt
            WHERE dpt.draft_year = ds.draft_year
              AND dpt.draft_round = ds.draft_round
              AND (
                dpt.original_team_code = ds.drafting_team_code
                OR dpt.from_team_code = ds.drafting_team_code
                OR dpt.to_team_code = ds.drafting_team_code
              )
          ) AS provenance_trade_count
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.people p
          ON p.person_id = ds.player_id
        LEFT JOIN pcms.transactions tx
          ON tx.transaction_id = ds.transaction_id
        LEFT JOIN pcms.teams t
          ON t.team_code = ds.drafting_team_code
         AND t.league_lk = 'NBA'
        WHERE #{where_clauses.join(" AND ")}
        ORDER BY ds.draft_year DESC, ds.draft_round ASC, ds.pick_number ASC
        LIMIT 260
      SQL
    end

    def build_sidebar_summary!
      rows = Array(@results)

      filters = ["Year: #{@year_lens}"]
      filters << "Round: R#{@round_lens}" if @round_lens != "all"
      filters << "Team: #{@team_lens}" if @team_lens.present?
      filters << %(Search: "#{@query}") if @query.present?

      @sidebar_summary = {
        year: @year_lens,
        round: @round_lens,
        team: @team_lens,
        query: @query,
        row_count: rows.size,
        first_round_count: rows.count { |row| row["draft_round"].to_i == 1 },
        with_trade_count: rows.count { |row| row["trade_id"].present? },
        known_player_count: rows.count { |row| row["player_id"].present? },
        unique_team_count: rows.map { |row| row["drafting_team_code"].presence }.compact.uniq.size,
        provenance_trade_total: rows.sum { |row| row["provenance_trade_count"].to_i },
        filters: filters,
        top_rows: rows.first(14)
      }
    end

    def load_sidebar_selection_payload(transaction_id)
      conn = ActiveRecord::Base.connection
      tx_sql = conn.quote(transaction_id)

      selection = conn.exec_query(<<~SQL).first
        SELECT
          ds.transaction_id,
          ds.draft_year,
          ds.draft_round,
          ds.pick_number,
          ds.player_id,
          COALESCE(
            NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
            NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)), ''),
            ds.player_id::text
          ) AS player_name,
          ds.drafting_team_id,
          ds.drafting_team_code,
          t.team_name AS drafting_team_name,
          ds.transaction_date,
          tx.trade_id,
          tx.transaction_type_lk,
          tx.transaction_description_lk
        FROM pcms.draft_selections ds
        LEFT JOIN pcms.transactions tx
          ON tx.transaction_id = ds.transaction_id
        LEFT JOIN pcms.people p
          ON p.person_id = ds.player_id
        LEFT JOIN pcms.teams t
          ON t.team_code = ds.drafting_team_code
         AND t.league_lk = 'NBA'
        WHERE ds.transaction_id = #{tx_sql}
        LIMIT 1
      SQL
      raise ActiveRecord::RecordNotFound unless selection

      current_team = nil
      if selection["player_id"].present?
        player_sql = conn.quote(selection["player_id"])
        current_team = conn.exec_query(<<~SQL).first
          SELECT
            sbw.team_code,
            t.team_id,
            t.team_name
          FROM pcms.salary_book_warehouse sbw
          LEFT JOIN pcms.teams t
            ON t.team_code = sbw.team_code
           AND t.league_lk = 'NBA'
          WHERE sbw.player_id = #{player_sql}
          LIMIT 1
        SQL
      end

      year_sql = conn.quote(selection["draft_year"])
      round_sql = conn.quote(selection["draft_round"])
      team_sql = conn.quote(selection["drafting_team_code"])

      provenance_rows = conn.exec_query(<<~SQL).to_a
        SELECT
          dpt.id,
          dpt.trade_id,
          tr.trade_date,
          dpt.from_team_code,
          dpt.to_team_code,
          dpt.original_team_code,
          dpt.is_swap,
          dpt.is_future,
          dpt.is_conditional,
          dpt.conditional_type_lk
        FROM pcms.draft_pick_trades dpt
        LEFT JOIN pcms.trades tr
          ON tr.trade_id = dpt.trade_id
        WHERE dpt.draft_year = #{year_sql}
          AND dpt.draft_round = #{round_sql}
          AND (
            dpt.original_team_code = #{team_sql}
            OR dpt.from_team_code = #{team_sql}
            OR dpt.to_team_code = #{team_sql}
          )
        ORDER BY tr.trade_date NULLS LAST, dpt.id
        LIMIT 120
      SQL

      {
        selection: selection,
        current_team: current_team,
        provenance_rows: provenance_rows
      }
    end

    def selected_overlay_visible?(overlay_id:)
      normalized_id = overlay_id.to_i
      return false if normalized_id <= 0

      @results.any? { |row| row["transaction_id"].to_i == normalized_id }
    end

    def normalize_team_code_param(raw)
      code = raw.to_s.strip.upcase
      return nil if code.blank?
      return nil unless code.match?(/\A[A-Z]{3}\z/)

      code
    end

    def normalize_year_param(raw)
      year = Integer(raw.to_s.strip)
      return nil if year <= 0

      year
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_round_param(raw)
      round = raw.to_s.strip
      round = "all" if round.blank?
      return round if INDEX_ROUNDS.include?(round)

      nil
    end
  end
end
