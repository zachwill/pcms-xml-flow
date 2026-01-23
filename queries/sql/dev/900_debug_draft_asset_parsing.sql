-- queries/sql/dev/900_debug_draft_asset_parsing.sql
--
-- Dev scratchpad: draft asset fragment parsing (semicolon split + regex extraction).
--
-- Goal: iterate on these regexes in plain SQL until results look right,
-- then bake into a migration/refresh function.
--
-- Usage:
--   psql "$POSTGRES_URL" -f queries/sql/dev/900_debug_draft_asset_parsing.sql

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 1) Inspect the hardest rows (longest raw_part)
-- -----------------------------------------------------------------------------
with sample as (
  select
    team_code,
    draft_year,
    draft_round,
    asset_slot,
    raw_fragment,
    endnote_refs
  from pcms.draft_picks_warehouse
  order by length(raw_fragment) desc
  limit 250
), exploded as (
  select
    s.*,
    t.ordinality::int as sub_asset_slot,
    trim(t.part) as raw_part
  from sample s
  cross join lateral regexp_split_to_table(s.raw_fragment, '\\s*;\\s*') with ordinality as t(part, ordinality)
  where trim(coalesce(t.part,'')) <> ''
), parsed as (
  select
    e.*,

    case
      when e.raw_part ~* '^own\\b' then 'OWN'
      when e.raw_part ~* '^to\\s+' then 'TO'
      when e.raw_part ~* '^has\\s+' then 'HAS'
      when e.raw_part ~* '^may\\s+have\\s+' then 'MAY_HAVE'
      else 'OTHER'
    end as asset_type,

    -- single counterparty (first recipient)
    (regexp_match(e.raw_part, '^(?:To|Has)\\s+([A-Z]{2,3})\\(\\d+\\)', 'i'))[1] as cp_1,
    (regexp_match(e.raw_part, '^May\\s+have\\s+([A-Z]{2,3})\\(\\d+\\)', 'i'))[1] as cp_2,

    -- all recipients (To/Has/May have/or to)
    coalesce(
      (
        select array_agg(distinct m[1] order by m[1])
        from regexp_matches(e.raw_part, '(?:\\bto\\s+|\\bhas\\s+|\\bmay\\s+have\\s+)([A-Z]{2,3})\\(\\d+\\)', 'gi') as m
      ),
      '{}'::text[]
    ) as cp_all,

    -- via chain
    coalesce(
      (
        select array_agg(distinct m[1] order by m[1])
        from regexp_matches(e.raw_part, '\\bvia\\s+([A-Z]{2,3})\\(\\d+\\)', 'gi') as m
      ),
      '{}'::text[]
    ) as via_all

  from exploded e
)
select
  team_code,
  draft_year,
  draft_round,
  asset_slot,
  sub_asset_slot,
  asset_type,
  raw_part,
  coalesce(cp_1, cp_2) as counterparty_single,
  cp_all as counterparty_all,
  via_all as via_team_codes,
  endnote_refs
from parsed
order by length(raw_part) desc
limit 60;

-- -----------------------------------------------------------------------------
-- 2) Coverage stats: how often do we extract something?
-- -----------------------------------------------------------------------------
with sample as (
  select
    raw_fragment
  from pcms.draft_picks_warehouse
  order by length(raw_fragment) desc
  limit 250
), exploded as (
  select
    trim(t.part) as raw_part
  from sample s
  cross join lateral regexp_split_to_table(s.raw_fragment, '\\s*;\\s*') with ordinality as t(part, ordinality)
  where trim(coalesce(t.part,'')) <> ''
), parsed as (
  select
    raw_part,
    case
      when raw_part ~* '^own\\b' then 'OWN'
      when raw_part ~* '^to\\s+' then 'TO'
      when raw_part ~* '^has\\s+' then 'HAS'
      when raw_part ~* '^may\\s+have\\s+' then 'MAY_HAVE'
      else 'OTHER'
    end as asset_type,
    (regexp_match(raw_part, '^(?:To|Has)\\s+([A-Z]{2,3})\\(\\d+\\)', 'i'))[1] as cp_1,
    (regexp_match(raw_part, '^May\\s+have\\s+([A-Z]{2,3})\\(\\d+\\)', 'i'))[1] as cp_2,
    coalesce(
      (
        select array_agg(distinct m[1] order by m[1])
        from regexp_matches(raw_part, '(?:\\bto\\s+|\\bhas\\s+|\\bmay\\s+have\\s+)([A-Z]{2,3})\\(\\d+\\)', 'gi') as m
      ),
      '{}'::text[]
    ) as cp_all,
    coalesce(
      (
        select array_agg(distinct m[1] order by m[1])
        from regexp_matches(raw_part, '\\bvia\\s+([A-Z]{2,3})\\(\\d+\\)', 'gi') as m
      ),
      '{}'::text[]
    ) as via_all
  from exploded
)
select
  count(*) as n_parts,
  count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE')) as n_relevant,
  count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE') and coalesce(cp_1, cp_2) is not null) as n_single_ok,
  count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE') and cardinality(cp_all) > 0) as n_any_ok,
  count(*) filter (where cardinality(via_all) > 0) as n_has_via,
  round(100.0 * count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE') and coalesce(cp_1, cp_2) is not null) / nullif(count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE')),0), 2) as pct_single_ok,
  round(100.0 * count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE') and cardinality(cp_all) > 0) / nullif(count(*) filter (where asset_type in ('TO','HAS','MAY_HAVE')),0), 2) as pct_any_ok
from parsed;

-- -----------------------------------------------------------------------------
-- 3) Most common normalized patterns (quick clustering)
-- -----------------------------------------------------------------------------
with sample as (
  select raw_fragment
  from pcms.draft_picks_warehouse
  order by length(raw_fragment) desc
  limit 250
), exploded as (
  select trim(t.part) as raw_part
  from sample s
  cross join lateral regexp_split_to_table(s.raw_fragment, '\\s*;\\s*') with ordinality as t(part, ordinality)
  where trim(coalesce(t.part,'')) <> ''
), parsed as (
  select
    raw_part,
    case
      when raw_part ~* '^own\\b' then 'OWN'
      when raw_part ~* '^to\\s+' then 'TO'
      when raw_part ~* '^has\\s+' then 'HAS'
      when raw_part ~* '^may\\s+have\\s+' then 'MAY_HAVE'
      else 'OTHER'
    end as asset_type
  from exploded
)
select
  asset_type,
  regexp_replace(raw_part, '\\(\\d+\\)', '()', 'g') as normalized_part,
  count(*) as n
from parsed
group by 1,2
order by n desc
limit 60;
