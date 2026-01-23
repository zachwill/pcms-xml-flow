-- 038_draft_picks_warehouses.sql
--
-- Draft picks warehouses:
-- 1) pcms.draft_pick_slots_warehouse: trade-derived, slot-based, provenance-first.
-- 2) pcms.draft_picks_warehouse: summary-derived, team-facing, fidelity-first.
--
-- Notes:
-- - Warehouses intentionally do NOT resolve protections/swaps into deterministic outcomes.
-- - Slot ownership is computed from latest movement row in pcms.draft_pick_trades.
-- - Team-facing picks are computed by exploding pcms.draft_pick_summaries on literal '|'.
-- - endnote_refs are numeric ids found in parentheses, constrained to 1..999.

begin;

-- -----------------------------------------------------------------------------
-- 1) Slot-based warehouse (trade-derived)
-- -----------------------------------------------------------------------------

do $$
begin
  if to_regclass('pcms.draft_pick_slots_warehouse') is null then
    create table pcms.draft_pick_slots_warehouse (
      draft_year int not null,
      draft_round int not null,

      original_team_id bigint not null,
      original_team_code text not null,

      current_team_id bigint not null,
      current_team_code text not null,

      last_trade_id bigint,
      last_trade_date date,
      last_from_team_id bigint,
      last_from_team_code text,
      last_to_team_id bigint,
      last_to_team_code text,

      is_swap boolean,
      is_conditional boolean,
      conditional_type_lk text,

      needs_review boolean not null default false,
      refreshed_at timestamptz not null default now(),

      primary key (draft_year, draft_round, original_team_id)
    );

    create index draft_pick_slots_warehouse_current_team_idx
      on pcms.draft_pick_slots_warehouse (current_team_code, draft_year);

    create index draft_pick_slots_warehouse_original_team_idx
      on pcms.draft_pick_slots_warehouse (original_team_code, draft_year);
  end if;
end $$;

create or replace function pcms.refresh_draft_pick_slots_warehouse()
returns void
language plpgsql
as $$
begin
  truncate table pcms.draft_pick_slots_warehouse;

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
    refreshed_at
  )
  with ranked as (
    select
      dpt.*,
      row_number() over (
        partition by dpt.draft_year, dpt.draft_round, dpt.original_team_id
        order by dpt.trade_date desc nulls last, dpt.trade_id desc, dpt.id desc
      ) as rnk
    from pcms.draft_pick_trades dpt
  )
  select
    draft_year,
    draft_round,
    original_team_id,
    original_team_code,
    to_team_id as current_team_id,
    to_team_code as current_team_code,
    trade_id as last_trade_id,
    trade_date as last_trade_date,
    from_team_id as last_from_team_id,
    from_team_code as last_from_team_code,
    to_team_id as last_to_team_id,
    to_team_code as last_to_team_code,
    is_swap,
    is_conditional,
    conditional_type_lk,
    (coalesce(is_swap, false) or coalesce(is_conditional, false)) as needs_review,
    now() as refreshed_at
  from ranked
  where rnk = 1;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2) Team-facing warehouse (summary-derived)
-- -----------------------------------------------------------------------------

do $$
begin
  if to_regclass('pcms.draft_picks_warehouse') is null then
    create table pcms.draft_picks_warehouse (
      team_id bigint not null,
      team_code text not null,
      draft_year int not null,
      draft_round int not null,
      asset_slot int not null,

      asset_type text not null,

      raw_round_text text,
      raw_fragment text not null,

      -- numeric ids in parentheses (often endnote ids in external corpus)
      numeric_paren_refs int[] not null default '{}'::int[],
      -- filtered to plausible endnote range
      endnote_refs int[] not null default '{}'::int[],

      is_forfeited boolean not null default false,
      is_conditional_text boolean not null default false,
      is_swap_text boolean not null default false,

      needs_review boolean not null default false,
      refreshed_at timestamptz not null default now(),

      primary key (team_code, draft_year, draft_round, asset_slot)
    );

    create index draft_picks_warehouse_team_year_idx
      on pcms.draft_picks_warehouse (team_code, draft_year);

    create index draft_picks_warehouse_year_round_idx
      on pcms.draft_picks_warehouse (draft_year, draft_round);

    create index draft_picks_warehouse_endnote_refs_gin_idx
      on pcms.draft_picks_warehouse using gin (endnote_refs);
  else
    -- backfill columns if table exists from earlier iterations
    alter table pcms.draft_picks_warehouse
      add column if not exists numeric_paren_refs int[] not null default '{}'::int[];

    alter table pcms.draft_picks_warehouse
      add column if not exists endnote_refs int[] not null default '{}'::int[];
  end if;
end $$;

-- IMPORTANT: SQL-language function (not plpgsql)
-- We observed correlated subqueries inside plpgsql CTEs could yield empty arrays;
-- SQL function version behaves correctly.
create or replace function pcms.refresh_draft_picks_warehouse()
returns void
language sql
as $$
  truncate pcms.draft_picks_warehouse;

  insert into pcms.draft_picks_warehouse (
    team_id,
    team_code,
    draft_year,
    draft_round,
    asset_slot,
    asset_type,
    raw_round_text,
    raw_fragment,
    numeric_paren_refs,
    endnote_refs,
    is_forfeited,
    is_conditional_text,
    is_swap_text,
    needs_review,
    refreshed_at
  )
  with base as (
    select team_id, team_code, draft_year, 1 as draft_round, first_round as raw_round_text
    from pcms.draft_pick_summaries

    union all

    select team_id, team_code, draft_year, 2 as draft_round, second_round as raw_round_text
    from pcms.draft_pick_summaries
  ), exploded as (
    select
      b.*, 
      trim(frag) as raw_fragment,
      ordinality::int as asset_slot
    from base b
    , lateral regexp_split_to_table(coalesce(b.raw_round_text, ''), chr(92) || '|') with ordinality as t(frag, ordinality)
    where trim(coalesce(frag, '')) <> ''
  ), parsed as (
    select
      e.*,
      case
        when e.raw_fragment ~* '^own\b' then 'OWN'
        when e.raw_fragment ~* '^to\s+' then 'TO'
        when e.raw_fragment ~* '^has\s+' then 'HAS'
        when e.raw_fragment ~* '^may\s+have\b' then 'MAY_HAVE'
        else 'OTHER'
      end as asset_type,

      coalesce(r.refs, '{}'::int[]) as numeric_paren_refs,
      coalesce(
        (select array_agg(x) filter (where x between 1 and 999)
         from unnest(coalesce(r.refs, '{}'::int[])) as x),
        '{}'::int[]
      ) as endnote_refs,

      (e.raw_fragment ~* 'forfeit') as is_forfeited,
      (e.raw_fragment ~* '\b(if|unless|provided|more favorable|less favorable|converts to|or to|may have)\b') as is_conditional_text,
      (e.raw_fragment ~* '\bswap\b') as is_swap_text
    from exploded e
    cross join lateral (
      select array_agg((m[1])::int) as refs
      from regexp_matches(e.raw_fragment, '\((\d+)\)', 'g') as m
    ) r
  )
  select
    team_id,
    team_code,
    draft_year,
    draft_round,
    asset_slot,
    asset_type,
    raw_round_text,
    raw_fragment,
    numeric_paren_refs,
    endnote_refs,
    is_forfeited,
    is_conditional_text,
    is_swap_text,
    (is_forfeited or is_conditional_text or is_swap_text) as needs_review,
    now() as refreshed_at
  from parsed;
$$;

commit;
