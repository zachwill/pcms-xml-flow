-- 062_draft_pick_assets_views_assertions.sql
--
-- Assertions for draft pick overlay/workbench views.

begin;

-- Views exist
select 1 as ok
where to_regclass('pcms.vw_draft_pick_assets') is not null;

select 1 as ok
where to_regclass('pcms.vw_draft_pick_shorthand_todo') is not null;

select 1 as ok
where to_regclass('pcms.vw_draft_pick_shorthand_orphans') is not null;

-- Rowcount invariant: overlay view should be 1:1 with summary assets (PK join)
do $$
declare c_summary bigint;
declare c_view bigint;
begin
  select count(*) into c_summary from pcms.draft_pick_summary_assets;
  select count(*) into c_view from pcms.vw_draft_pick_assets;

  if c_summary <> c_view then
    raise exception 'vw_draft_pick_assets rowcount mismatch: summary=% view=%', c_summary, c_view;
  end if;
end $$;

-- Fallback invariant: if there is no shorthand row, display_text == raw_part
do $$
declare c bigint;
begin
  select count(*) into c
  from pcms.vw_draft_pick_assets
  where not has_shorthand
    and display_text <> raw_part;

  if c <> 0 then
    raise exception 'Expected display_text to equal raw_part for rows without shorthand (bad rows=%)', c;
  end if;
end $$;

commit;
