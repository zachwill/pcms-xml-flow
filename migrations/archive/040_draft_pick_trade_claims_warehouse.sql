-- 040_draft_pick_trade_claims_warehouse.sql
--
-- Replace misleading slot "ownership" warehouse with a claims/evidence warehouse.
--
-- Rationale:
-- - pcms.draft_pick_trades is derived from trade_team_details (trade_entry_lk='DRPCK'),
--   which encodes pick-related line-items/branches/claims. It is NOT a deterministic
--   ownership ledger in the presence of protections, swaps, and conditional branches.
-- - The team-year summaries (draft_pick_summaries) are stateful prose and can diverge
--   from any naive slot-owner derivation.
--
-- This migration:
-- - Drops pcms.draft_pick_slots_warehouse (table) and its refresh function.
-- - Adds pcms.draft_pick_trade_claims_warehouse, which stores ALL trade-derived claims
--   per (draft_year, draft_round, original_team).
-- - Provides JSONB payload + a few scalar helper fields, but does NOT claim "current owner".

begin;

-- Drop old, misleading warehouse
DROP FUNCTION IF EXISTS pcms.refresh_draft_pick_slots_warehouse();
DROP TABLE IF EXISTS pcms.draft_pick_slots_warehouse;

-- New claims/evidence warehouse
CREATE TABLE IF NOT EXISTS pcms.draft_pick_trade_claims_warehouse (
  draft_year int not null,
  draft_round int not null,

  original_team_id bigint not null,
  original_team_code text not null,

  -- JSON array of all candidate trade-derived claims (newest first)
  trade_claims_json jsonb not null default '[]'::jsonb,

  claims_count int not null default 0,
  distinct_to_teams_count int not null default 0,

  has_conditional_claims boolean not null default false,
  has_swap_claims boolean not null default false,

  -- A convenience only: most recent trade touching this slot (by trade_date/trade_id/id)
  latest_trade_id bigint,
  latest_trade_date date,

  needs_review boolean not null default false,
  refreshed_at timestamptz not null default now(),

  primary key (draft_year, draft_round, original_team_id)
);

CREATE INDEX IF NOT EXISTS draft_pick_trade_claims_original_team_idx
  ON pcms.draft_pick_trade_claims_warehouse (original_team_code, draft_year);

CREATE INDEX IF NOT EXISTS draft_pick_trade_claims_json_gin_idx
  ON pcms.draft_pick_trade_claims_warehouse USING gin (trade_claims_json);

CREATE OR REPLACE FUNCTION pcms.refresh_draft_pick_trade_claims_warehouse()
RETURNS void
LANGUAGE sql
AS $$
  truncate pcms.draft_pick_trade_claims_warehouse;

  with ordered as (
    select
      dpt.*, 
      row_number() over (
        partition by dpt.draft_year, dpt.draft_round, dpt.original_team_id
        order by dpt.trade_date desc nulls last, dpt.trade_id desc, dpt.id desc
      ) as latest_rank
    from pcms.draft_pick_trades dpt
  ), agg as (
    select
      dpt.draft_year,
      dpt.draft_round,
      dpt.original_team_id,
      dpt.original_team_code,

      jsonb_agg(
        jsonb_build_object(
          'trade_id', dpt.trade_id,
          'trade_date', dpt.trade_date,
          'from_team_id', dpt.from_team_id,
          'from_team_code', dpt.from_team_code,
          'to_team_id', dpt.to_team_id,
          'to_team_code', dpt.to_team_code,
          'is_swap', dpt.is_swap,
          'is_conditional', dpt.is_conditional,
          'conditional_type_lk', dpt.conditional_type_lk
        )
        order by dpt.trade_date desc nulls last, dpt.trade_id desc, dpt.id desc
      ) as trade_claims_json,

      count(*) as claims_count,
      count(distinct dpt.to_team_code) as distinct_to_teams_count,
      bool_or(coalesce(dpt.is_conditional,false)) as has_conditional_claims,
      bool_or(coalesce(dpt.is_swap,false)) as has_swap_claims
    from pcms.draft_pick_trades dpt
    group by 1,2,3,4
  ), latest as (
    select
      draft_year,
      draft_round,
      original_team_id,
      max(trade_id) filter (where latest_rank=1) as latest_trade_id,
      max(trade_date) filter (where latest_rank=1) as latest_trade_date
    from ordered
    group by 1,2,3
  )
  insert into pcms.draft_pick_trade_claims_warehouse (
    draft_year,
    draft_round,
    original_team_id,
    original_team_code,
    trade_claims_json,
    claims_count,
    distinct_to_teams_count,
    has_conditional_claims,
    has_swap_claims,
    latest_trade_id,
    latest_trade_date,
    needs_review,
    refreshed_at
  )
  select
    a.draft_year,
    a.draft_round,
    a.original_team_id,
    a.original_team_code,
    a.trade_claims_json,
    a.claims_count,
    a.distinct_to_teams_count,
    a.has_conditional_claims,
    a.has_swap_claims,
    l.latest_trade_id,
    l.latest_trade_date,
    (
      a.has_conditional_claims
      or a.has_swap_claims
      or a.claims_count > 1
      or a.distinct_to_teams_count > 1
    ) as needs_review,
    now() as refreshed_at
  from agg a
  join latest l
    on l.draft_year=a.draft_year
   and l.draft_round=a.draft_round
   and l.original_team_id=a.original_team_id;
$$;

commit;
