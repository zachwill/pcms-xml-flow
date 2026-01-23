-- 053_draft_assets_warehouse_assertions.sql
--
-- Assertions for endnotes-enriched draft assets warehouse.

begin;

-- table exists + non-empty
select 1 as ok
where to_regclass('pcms.draft_assets_warehouse') is not null;

select 1 as ok
from pcms.draft_assets_warehouse
limit 1;

-- primary key uniqueness sanity
do $$
declare
  n_total bigint;
  n_distinct bigint;
begin
  select count(*) into n_total from pcms.draft_assets_warehouse;
  select count(*) into n_distinct
  from (
    select distinct team_code, draft_year, draft_round, asset_slot, sub_asset_slot
    from pcms.draft_assets_warehouse
  ) d;

  if n_total <> n_distinct then
    raise exception 'draft_assets_warehouse PK not unique: total=% distinct=% (check includes sub_asset_slot)', n_total, n_distinct;
  end if;
end $$;

-- If a row has endnote_refs, it should usually match an endnote.
-- Allow a small number of unmatched refs (very recent trades).
do $$
declare
  with_refs bigint;
  matched bigint;
  ratio numeric;
begin
  select
    count(*) filter (where cardinality(endnote_refs) > 0),
    count(*) filter (where cardinality(endnote_refs) > 0 and has_endnote_match)
  into with_refs, matched
  from pcms.draft_assets_warehouse;

  if with_refs = 0 then
    return;
  end if;

  ratio := matched::numeric / with_refs;
  if ratio < 0.95 then
    raise exception 'draft_assets_warehouse endnote match rate too low: matched=% with_refs=% ratio=%', matched, with_refs, ratio;
  end if;
end $$;

-- distribution sanity: should not be all OTHER
do $$
declare
  total bigint;
  non_other bigint;
  ratio numeric;
begin
  select count(*), count(*) filter (where asset_type <> 'OTHER')
  into total, non_other
  from pcms.draft_assets_warehouse;

  if total = 0 then
    raise exception 'draft_assets_warehouse empty';
  end if;

  ratio := non_other::numeric / total;
  if ratio < 0.40 then
    raise exception 'draft_assets_warehouse asset_type seems wrong: non_other=% total=% ratio=%', non_other, total, ratio;
  end if;
end $$;

commit;
