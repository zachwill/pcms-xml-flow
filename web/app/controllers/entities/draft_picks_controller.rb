require "set"

module Entities
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
          endnote_explanation,
          endnote_trade_date,
          refreshed_at
        FROM pcms.draft_pick_summary_assets
        WHERE team_code = #{team_sql}
          AND draft_year = #{year_sql}
          AND draft_round = #{round_sql}
        ORDER BY asset_slot, sub_asset_slot
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
          WHERE league_lk = 'NBA'
            AND team_code IN (#{in_list})
        SQL

        @teams_by_code = team_rows.each_with_object({}) do |t, h|
          h[t["team_code"]] = t
        end
      else
        @teams_by_code = {}
      end

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
  end
end
