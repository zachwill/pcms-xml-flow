-- 063_draft_pick_assets_display_text_direction_assertions.sql
--
-- Assertions for direction-aware display_text in pcms.vw_draft_pick_assets.

begin;

-- Ensure view exists
select 1 as ok
from information_schema.views
where table_schema = 'pcms'
  and table_name = 'vw_draft_pick_assets';

-- If a row is outgoing (raw_part begins with "To "), display_text should also begin with "To ".
-- (We only check rows where display_text is non-null; it always should be.)
do $$
declare
  bad_count int;
begin
  select count(*) into bad_count
  from pcms.vw_draft_pick_assets v
  where v.raw_part ~* E'^to\\s'
    and v.display_text !~* E'^to\\s';

  if bad_count > 0 then
    raise exception 'vw_draft_pick_assets display_text is missing "To" prefix for % outgoing rows', bad_count;
  end if;
end $$;

commit;
