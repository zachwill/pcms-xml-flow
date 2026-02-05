-- 069_draft_pick_assets_views.sql
--
-- Convenience views that make draft pick assets feel like a single wide “warehouse” table:
-- - pcms.vw_draft_pick_assets: overlay pcms.draft_pick_summary_assets with curated shorthand
--   and endnote helpers.
-- - pcms.vw_draft_pick_shorthand_todo: work queue (missing shorthand, needs_review, missing endnotes)
-- - pcms.vw_draft_pick_shorthand_orphans: shorthand rows that no longer match any summary asset
--
-- Rationale:
-- - draft_pick_summary_assets is refreshable (derived from PCMS summaries)
-- - draft_pick_shorthand_assets is durable (curated; must survive refresh)
-- - these views give consumers a single query surface.

begin;

-- Canonical overlay
create or replace view pcms.vw_draft_pick_assets as
select
  sa.team_id,
  sa.team_code,
  sa.draft_year,
  sa.draft_round,
  sa.asset_slot,
  sa.sub_asset_slot,

  sa.asset_type,
  sa.is_forfeited,
  sa.is_conditional_text,
  sa.is_swap_text,
  sa.is_conditional,
  sa.is_swap,

  sa.counterparty_team_code,
  sa.counterparty_team_codes,
  sa.via_team_codes,

  sa.raw_round_text,
  sa.raw_fragment,
  sa.raw_part,

  sa.numeric_paren_refs,
  sa.endnote_refs,
  sa.missing_endnote_refs,

  sa.primary_endnote_id,
  sa.has_primary_endnote_match,
  sa.endnote_trade_date,
  sa.endnote_is_swap,
  sa.endnote_is_conditional,
  sa.endnote_depends_on,
  sa.endnote_explanation,

  sa.needs_review as summary_needs_review,
  sa.refreshed_at,

  sh.shorthand_input,
  sh.shorthand,
  sh.endnote_ids,
  sh.referenced_team_codes,
  sh.shorthand_ast,
  sh.notes,
  sh.source_lk,
  sh.needs_review as shorthand_needs_review,
  sh.created_at as shorthand_created_at,
  sh.updated_at as shorthand_updated_at,

  (sh.team_code is not null) as has_shorthand,
  coalesce(sh.shorthand, sa.raw_part) as display_text,

  -- Prefer curated endnote_ids when present; otherwise use PCMS-derived refs.
  case
    when coalesce(cardinality(sh.endnote_ids), 0) > 0 then sh.endnote_ids
    else sa.endnote_refs
  end as effective_endnote_ids,

  coalesce(enagg.endnotes, '[]'::jsonb) as effective_endnotes,

  (
    sa.needs_review
    or coalesce(sh.needs_review, false)
    or cardinality(sa.missing_endnote_refs) > 0
  ) as needs_review

from pcms.draft_pick_summary_assets sa
left join pcms.draft_pick_shorthand_assets sh
  on sh.team_code = sa.team_code
 and sh.draft_year = sa.draft_year
 and sh.draft_round = sa.draft_round
 and sh.asset_slot = sa.asset_slot
 and sh.sub_asset_slot = sa.sub_asset_slot
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'endnote_id', en.endnote_id,
        'trade_date', en.trade_date,
        'is_swap', en.is_swap,
        'is_conditional', en.is_conditional,
        'depends_on_endnotes', en.depends_on_endnotes,
        'explanation', en.explanation,
        'source_file', en.metadata_json->>'source_file'
      )
      order by en.endnote_id
    ) as endnotes
  from pcms.endnotes en
  where en.endnote_id = any(
    case
      when coalesce(cardinality(sh.endnote_ids), 0) > 0 then sh.endnote_ids
      else sa.endnote_refs
    end
  )
) enagg on true;

comment on view pcms.vw_draft_pick_assets is
  'Overlay view: pcms.draft_pick_summary_assets + pcms.draft_pick_shorthand_assets + endnote helpers (wide warehouse-like query surface).';

-- Work queue: what needs shorthand and/or review.
create or replace view pcms.vw_draft_pick_shorthand_todo as
select
  v.*,
  (not v.has_shorthand) as is_missing_shorthand,
  (cardinality(v.missing_endnote_refs) > 0) as has_missing_endnotes,
  case
    when cardinality(v.missing_endnote_refs) > 0 then 'missing_endnotes'
    when not v.has_shorthand then 'missing_shorthand'
    when v.summary_needs_review then 'summary_needs_review'
    when coalesce(v.shorthand_needs_review, false) then 'shorthand_needs_review'
    else null
  end as primary_todo_reason
from pcms.vw_draft_pick_assets v
where v.draft_year >= extract(year from current_date)::int - 1
  and (
    not v.has_shorthand
    or v.summary_needs_review
    or coalesce(v.shorthand_needs_review, false)
    or cardinality(v.missing_endnote_refs) > 0
  );

comment on view pcms.vw_draft_pick_shorthand_todo is
  'Workbench queue: draft pick summary assets that are missing shorthand and/or are flagged needs_review (including missing endnotes).';

-- Orphans: shorthand rows that do not match any current summary asset key.
create or replace view pcms.vw_draft_pick_shorthand_orphans as
select
  sh.*, 
  now() as observed_at
from pcms.draft_pick_shorthand_assets sh
left join pcms.draft_pick_summary_assets sa
  on sa.team_code = sh.team_code
 and sa.draft_year = sh.draft_year
 and sa.draft_round = sh.draft_round
 and sa.asset_slot = sh.asset_slot
 and sa.sub_asset_slot = sh.sub_asset_slot
where sa.team_code is null;

comment on view pcms.vw_draft_pick_shorthand_orphans is
  'Curated shorthand rows whose (team_code,year,round,slot,sub_slot) key no longer exists in pcms.draft_pick_summary_assets (likely due to PCMS text changes / splitting drift).';

commit;
