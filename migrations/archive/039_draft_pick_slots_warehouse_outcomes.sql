-- 039_draft_pick_slots_warehouse_outcomes.sql
--
-- Improve draft_pick_slots_warehouse to support "best-effort" scalar current owner
-- while preserving ambiguity via JSONB outcomes.
--
-- Key idea:
-- - For each (draft_year, draft_round, original_team), keep *all* trade-derived candidate outcomes
--   in ownership_outcomes_json.
-- - Choose a scalar current_owner_* using a heuristic preference:
--     1) prefer non-conditional rows (is_conditional=false)
--     2) then newest by trade_date/trade_id/id
-- - Still mark needs_review if ANY outcome is conditional/swap OR if outcomes disagree.

begin;

alter table pcms.draft_pick_slots_warehouse
  add column if not exists ownership_outcomes_json jsonb not null default '[]'::jsonb;

alter table pcms.draft_pick_slots_warehouse
  add column if not exists outcomes_count int not null default 0;

alter table pcms.draft_pick_slots_warehouse
  add column if not exists distinct_to_teams_count int not null default 0;

create or replace function pcms.refresh_draft_pick_slots_warehouse()
returns void
language plpgsql
as $$
begin
  truncate table pcms.draft_pick_slots_warehouse;

  -- Build per-slot outcomes array containing all trade rows.
  with outcomes as (
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
      ) as ownership_outcomes_json,
      count(*) as outcomes_count,
      count(distinct dpt.to_team_code) as distinct_to_teams_count,
      bool_or(coalesce(dpt.is_swap,false) or coalesce(dpt.is_conditional,false)) as any_risky
    from pcms.draft_pick_trades dpt
    group by 1,2,3,4
  ),
  best as (
    -- Choose best-effort scalar current owner:
    -- prefer non-conditional rows, then newest.
    select
      dpt.*,
      row_number() over (
        partition by dpt.draft_year, dpt.draft_round, dpt.original_team_id
        order by (case when coalesce(dpt.is_conditional,false) then 1 else 0 end) asc,
                 dpt.trade_date desc nulls last,
                 dpt.trade_id desc,
                 dpt.id desc
      ) as pick_rank
    from pcms.draft_pick_trades dpt
  ),
  best1 as (
    select * from best where pick_rank=1
  )
  insert into pcms.draft_pick_slots_warehouse (
    draft_year,
    draft_round,
    original_team_id,
    original_team_code,
    current_team_id,
    current_team_code,
    last_trade_id,
    last_trade_date,
    last_from_team_id,
    last_from_team_code,
    last_to_team_id,
    last_to_team_code,
    is_swap,
    is_conditional,
    conditional_type_lk,
    needs_review,
    refreshed_at,
    ownership_outcomes_json,
    outcomes_count,
    distinct_to_teams_count
  )
  select
    b1.draft_year,
    b1.draft_round,
    b1.original_team_id,
    b1.original_team_code,
    b1.to_team_id as current_team_id,
    b1.to_team_code as current_team_code,
    b1.trade_id as last_trade_id,
    b1.trade_date as last_trade_date,
    b1.from_team_id as last_from_team_id,
    b1.from_team_code as last_from_team_code,
    b1.to_team_id as last_to_team_id,
    b1.to_team_code as last_to_team_code,
    b1.is_swap,
    b1.is_conditional,
    b1.conditional_type_lk,
    (
      o.any_risky
      or o.distinct_to_teams_count > 1
      or o.outcomes_count > 1
    ) as needs_review,
    now() as refreshed_at,
    o.ownership_outcomes_json,
    o.outcomes_count,
    o.distinct_to_teams_count
  from best1 b1
  join outcomes o
    on o.draft_year=b1.draft_year
   and o.draft_round=b1.draft_round
   and o.original_team_id=b1.original_team_id;
end;
$$;

commit;
