-- 041_draft_assets_warehouse.sql
--
-- Fix regex patterns in pcms.refresh_draft_assets_warehouse():
-- inside $$-quoted SQL bodies, backslashes are literal.
-- Use single backslashes for regex escapes (\s, \b, \d, etc.) where intended.
--
-- Rebuild from scratch (drop/recreate) to avoid any lingering confusion.

begin;

drop function if exists pcms.refresh_draft_assets_warehouse();
drop table if exists pcms.draft_assets_warehouse;

create table pcms.draft_assets_warehouse (
  team_id bigint not null,
  team_code text not null,
  draft_year int not null,
  draft_round int not null,

  asset_slot int not null,
  sub_asset_slot int not null,

  asset_type text not null,
  is_conditional boolean not null default false,
  is_swap boolean not null default false,

  counterparty_team_code text,
  counterparty_team_codes text[] not null default '{}'::text[],
  via_team_codes text[] not null default '{}'::text[],

  raw_round_text text,
  raw_fragment text not null,
  raw_part text not null,
  endnote_refs int[] not null default '{}'::int[],

  primary_endnote_id int,
  has_endnote_match boolean not null default false,

  endnote_trade_date date,
  endnote_is_swap boolean,
  endnote_is_conditional boolean,
  endnote_depends_on int[] not null default '{}'::int[],
  endnote_explanation text,

  needs_review boolean not null default false,
  refreshed_at timestamptz not null default now(),

  primary key (team_code, draft_year, draft_round, asset_slot, sub_asset_slot)
);

create index draft_assets_warehouse_team_year_idx
  on pcms.draft_assets_warehouse (team_code, draft_year);

create index draft_assets_warehouse_year_round_idx
  on pcms.draft_assets_warehouse (draft_year, draft_round);

create index draft_assets_warehouse_primary_endnote_idx
  on pcms.draft_assets_warehouse (primary_endnote_id);

create index draft_assets_warehouse_endnote_refs_gin_idx
  on pcms.draft_assets_warehouse using gin (endnote_refs);

create index draft_assets_warehouse_via_team_codes_gin_idx
  on pcms.draft_assets_warehouse using gin (via_team_codes);

create index draft_assets_warehouse_counterparty_team_codes_gin_idx
  on pcms.draft_assets_warehouse using gin (counterparty_team_codes);


create or replace function pcms.refresh_draft_assets_warehouse()
returns void
language sql
as $$
  truncate pcms.draft_assets_warehouse;

  with base as (
    select
      dp.team_id,
      dp.team_code,
      dp.draft_year,
      dp.draft_round,
      dp.asset_slot,
      dp.raw_round_text,
      dp.raw_fragment,
      dp.endnote_refs,
      dp.endnote_refs[1] as primary_endnote_id,
      dp.needs_review as needs_review_from_summary
    from pcms.draft_picks_warehouse dp
  ), exploded as (
    select
      b.*,
      t.ordinality::int as sub_asset_slot,
      btrim(t.part) as raw_part
    from base b
    cross join lateral regexp_split_to_table(b.raw_fragment, '\s*;\s*') with ordinality as t(part, ordinality)
    where btrim(coalesce(t.part,'')) <> ''
  ), parsed as (
    select
      e.*,
      case
        when e.raw_part ~* '^own\b' then 'OWN'
        when e.raw_part ~* '^to\s+' then 'TO'
        when e.raw_part ~* '^has\s+' then 'HAS'
        when e.raw_part ~* '^may\s+have\s+' then 'MAY_HAVE'
        else 'OTHER'
      end as asset_type,

      (regexp_match(e.raw_part, '^(?:To|Has)\s+([A-Z]{2,3})\(\d+\)', 'i'))[1] as cp_1,
      (regexp_match(e.raw_part, '^May\s+have\s+([A-Z]{2,3})\(\d+\)', 'i'))[1] as cp_2,

      -- Counterparties (multi): collect all recipient team codes mentioned.
      -- Use simpler patterns; embedded alternation + \b proved brittle.
      coalesce(
        (
          select array_agg(distinct x order by x)
          from (
            select m[1] as x from regexp_matches(e.raw_part, 'to\s+([A-Z]{2,3})\(\d+\)', 'gi') as m
            union
            select m[1] as x from regexp_matches(e.raw_part, 'has\s+([A-Z]{2,3})\(\d+\)', 'gi') as m
            union
            select m[1] as x from regexp_matches(e.raw_part, 'may\s+have\s+([A-Z]{2,3})\(\d+\)', 'gi') as m
          ) u
        ),
        '{}'::text[]
      ) as counterparty_team_codes,

      -- Via chain codes
      coalesce(
        (
          select array_agg(distinct m[1] order by m[1])
          from regexp_matches(e.raw_part, 'via\s+([A-Z]{2,3})\(\d+\)', 'gi') as m
        ),
        '{}'::text[]
      ) as via_team_codes,

      (e.raw_part ~* '\b(if|unless|provided|more favorable|less favorable|converts to|or to|may have)\b') as is_conditional_text,
      (e.raw_part ~* '\bswap\b') as is_swap_text

    from exploded e
  ), joined as (
    select
      p.*,
      nullif(coalesce(p.cp_1, p.cp_2), '') as counterparty_team_code,

      (en.endnote_id is not null) as has_endnote_match,
      en.trade_date as endnote_trade_date,
      en.is_swap as endnote_is_swap,
      en.is_conditional as endnote_is_conditional,
      coalesce(
        (
          select array_agg((x)::int)
          from jsonb_array_elements_text(coalesce(en.conditions_json->'depends_on_endnotes','[]'::jsonb)) as x
        ),
        '{}'::int[]
      ) as endnote_depends_on,
      en.explanation as endnote_explanation
    from parsed p
    left join pcms.endnotes en
      on en.endnote_id = p.primary_endnote_id
  )
  insert into pcms.draft_assets_warehouse (
    team_id,
    team_code,
    draft_year,
    draft_round,
    asset_slot,
    sub_asset_slot,
    asset_type,
    is_conditional,
    is_swap,
    counterparty_team_code,
    counterparty_team_codes,
    via_team_codes,
    raw_round_text,
    raw_fragment,
    raw_part,
    endnote_refs,
    primary_endnote_id,
    has_endnote_match,
    endnote_trade_date,
    endnote_is_swap,
    endnote_is_conditional,
    endnote_depends_on,
    endnote_explanation,
    needs_review,
    refreshed_at
  )
  select
    team_id,
    team_code,
    draft_year,
    draft_round,
    asset_slot,
    sub_asset_slot,
    asset_type,
    (coalesce(is_conditional_text,false) or coalesce(endnote_is_conditional,false)) as is_conditional,
    (coalesce(is_swap_text,false) or coalesce(endnote_is_swap,false)) as is_swap,
    counterparty_team_code,
    counterparty_team_codes,
    via_team_codes,
    raw_round_text,
    raw_fragment,
    raw_part,
    endnote_refs,
    primary_endnote_id,
    has_endnote_match,
    endnote_trade_date,
    endnote_is_swap,
    endnote_is_conditional,
    endnote_depends_on,
    endnote_explanation,
    (
      needs_review_from_summary
      or (cardinality(endnote_refs) > 0 and not has_endnote_match)
      or (asset_type in ('TO','HAS','MAY_HAVE') and counterparty_team_code is null and cardinality(counterparty_team_codes)=0)
    ) as needs_review,
    now() as refreshed_at
  from joined;
$$;

commit;
