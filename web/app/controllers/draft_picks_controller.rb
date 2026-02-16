require "set"

class DraftPicksController < ApplicationController
  # GET /draft-picks/:team_code/:year/:round
  def show
    team_code = params[:team_code].to_s.strip.upcase
    raise ActiveRecord::RecordNotFound unless team_code.match?(/\A[A-Z]{3}\z/)

    year = Integer(params[:year])
    round = Integer(params[:round])
    raise ActiveRecord::RecordNotFound unless round == 1 || round == 2

    conn = ActiveRecord::Base.connection
    team_sql = conn.quote(team_code)
    year_sql = conn.quote(year)
    round_sql = conn.quote(round)

    @team = conn.exec_query(<<~SQL).first || {}
      SELECT team_id, team_code, team_name, conference_name
      FROM pcms.teams
      WHERE team_code = #{team_sql}
        AND league_lk = 'NBA'
      LIMIT 1
    SQL

    @draft_pick_group = {
      "team_code" => team_code,
      "draft_year" => year,
      "draft_round" => round,
    }

    @assets = conn.exec_query(<<~SQL).to_a
      SELECT
        team_code,
        draft_year,
        draft_round,
        asset_slot,
        sub_asset_slot,
        asset_type,
        is_forfeited,
        is_swap,
        is_conditional,
        counterparty_team_code,
        counterparty_team_codes,
        via_team_codes,
        raw_round_text,
        raw_fragment,
        raw_part,
        display_text,
        primary_endnote_id,
        effective_endnote_ids,
        endnote_explanation,
        endnote_trade_date,
        needs_review,
        refreshed_at
      FROM pcms.vw_draft_pick_assets
      WHERE team_code = #{team_sql}
        AND draft_year = #{year_sql}
        AND draft_round = #{round_sql}
      ORDER BY asset_slot, sub_asset_slot
    SQL

    @trade_chain_rows = conn.exec_query(<<~SQL).to_a
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
          dpt.from_team_code = #{team_sql}
          OR dpt.to_team_code = #{team_sql}
          OR dpt.original_team_code = #{team_sql}
        )
      ORDER BY tr.trade_date NULLS LAST, dpt.id
      LIMIT 200
    SQL

    # Build a mapping of related team codes → team_id/team_name (for link-rich UI).
    codes = Set.new([team_code])
    @assets.each do |row|
      codes.add(row["counterparty_team_code"].to_s.strip.upcase) if row["counterparty_team_code"].present?

      parse_codes(row["counterparty_team_codes"]).each { |c| codes.add(c) }
      parse_codes(row["via_team_codes"]).each { |c| codes.add(c) }
    end

    if codes.any?
      in_list = codes.to_a.map { |c| conn.quote(c) }.join(",")

      team_rows = conn.exec_query(<<~SQL).to_a
        SELECT team_code, team_id, team_name
        FROM pcms.teams
        WHERE team_code IN (#{in_list})
      SQL

      @teams_by_code = team_rows.each_with_object({}) do |t, h|
        h[t["team_code"]] = t
      end
    else
      @teams_by_code = {}
    end

    # Resolve referenced endnotes for this pick group.
    endnote_ids = @assets.flat_map do |row|
      ids = parse_ints(row["effective_endnote_ids"])
      if ids.empty? && row["primary_endnote_id"].present?
        row["primary_endnote_id"].to_i
      else
        ids
      end
    end.uniq.sort

    @referenced_endnote_ids = endnote_ids

    if endnote_ids.any?
      in_list = endnote_ids.map { |idv| conn.quote(idv) }.join(",")
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
          is_conditional,
          from_team_code,
          to_team_code,
          draft_year_start,
          draft_year_end,
          draft_rounds
        FROM pcms.endnotes
        WHERE endnote_id IN (#{in_list})
        ORDER BY endnote_id
      SQL
    else
      @endnotes = []
    end

    @endnotes_by_id = @endnotes.each_with_object({}) { |row, h| h[row["endnote_id"].to_i] = row }

    render :show
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  private

  # Rails type casting for array columns can vary depending on adapter settings.
  # This helper accepts:
  # - Ruby arrays (already decoded)
  # - Postgres array strings like "{BOS,LAL}"
  # - nil
  def parse_codes(val)
    return [] if val.nil?
    return val.map { |v| v.to_s.strip.upcase }.reject(&:blank?) if val.is_a?(Array)

    s = val.to_s
    return [] if s.blank? || s == "{}"

    s.gsub(/[{}\"]/ , "")
      .split(",")
      .map { |v| v.to_s.strip.upcase }
      .reject(&:blank?)
  end

  def parse_ints(val)
    return [] if val.nil?

    if val.is_a?(Array)
      return val.filter_map do |v|
        begin
          Integer(v)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end

    s = val.to_s
    return [] if s.blank? || s == "{}"

    s.gsub(/[{}\"]/ , "")
      .split(",")
      .filter_map do |v|
        begin
          Integer(v.to_s.strip)
        rescue ArgumentError, TypeError
          nil
        end
      end
  end
end
