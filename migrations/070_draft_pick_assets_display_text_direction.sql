-- 070_draft_pick_assets_display_text_direction.sql
--
-- Make vw_draft_pick_assets.display_text direction-aware.
--
-- Problem:
-- - Curated shorthand expresses net pick logic (MF/LF pools, protections)
-- - But for outgoing rows (PCMS raw_part begins with "To ..."), a plain MF/LF shorthand
--   can be misread as something the team *has*, when it is actually something they *owe*.
--
-- Decision:
-- - Keep pcms.draft_pick_shorthand_assets.shorthand as a pure MF/LF language (no "To ..." prefixes).
-- - Render outgoing directionality in the overlay view display_text:
--     "To XYZ: <shorthand or raw_part>"
--
-- XYZ determination (important):
-- - Prefer the last TEAM token that appears after an "or to" clause (final destination in PCMS branch text).
--   Example: "To CHA(...) or to DET(...) or to UTA(...)" => XYZ = UTA.
-- - Otherwise, fall back to the first "To TEAM" token.
-- - Otherwise, fall back to sa.counterparty_team_code.

begin;

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

  case
    when sa.raw_part ~* '^to\\s' then
      (
        'To '
        || coalesce(
          (regexp_match(sa.raw_part, '(?i).*or\\s+to\\s+([A-Z]{3})\\(\\d+\\)'))[1],
          (regexp_match(sa.raw_part, '(?i)^to\\s+([A-Z]{3})'))[1],
          nullif(sa.counterparty_team_code, '')
        )
        || ': '
        || coalesce(sh.shorthand, sa.raw_part)
      )
    else
      coalesce(sh.shorthand, sa.raw_part)
  end as display_text,

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
  'Overlay view: pcms.draft_pick_summary_assets + pcms.draft_pick_shorthand_assets + endnote helpers (wide warehouse-like query surface). display_text is direction-aware for outgoing ("To ...") rows.';

commit;
