-- 065_draft_pick_shorthand_assets.sql
--
-- Curated Sean-style pick shorthand expressions (MF/LF pools, protections, etc.).
--
-- Why a new table?
-- - pcms.draft_pick_summaries / *_warehouse tables are PCMS-derived and refreshed.
-- - Shorthand is curated/hand-authored (or imported from other sources) and must persist.
-- - Endnote ids should NOT be embedded in shorthand text (so parentheses can be used for
--   protections like "WAS (p. 1-8)").
--
-- Conventions:
-- - team_code uses NBA abbreviations (BKN, SAS, PHX, ...)
-- - shorthand_input = raw user/import input
-- - shorthand = canonical pretty-printed display form

begin;

do $$
begin
  if to_regclass('pcms.draft_pick_shorthand_assets') is null then
    create table pcms.draft_pick_shorthand_assets (
      team_code text not null,
      draft_year int not null,
      draft_round int not null,
      asset_slot int not null,

      -- raw user/import input (may not be normalized)
      shorthand_input text not null,
      -- canonical normalized shorthand (preferred display form)
      shorthand text not null,

      -- related endnote ids in pcms.endnotes (kept out of shorthand text)
      endnote_ids int[] not null default '{}'::int[],

      -- team codes referenced inside shorthand expression (for search/filter)
      referenced_team_codes text[] not null default '{}'::text[],

      -- optional JSON AST for future evaluation (MF/LF resolution)
      shorthand_ast jsonb,

      notes text,
      source_lk text not null default 'manual',
      needs_review boolean not null default false,

      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),

      primary key (team_code, draft_year, draft_round, asset_slot),

      constraint draft_pick_shorthand_assets_round_chk
        check (draft_round in (1, 2)),
      constraint draft_pick_shorthand_assets_team_code_chk
        check (team_code ~ '^[A-Z]{3}$'),
      constraint draft_pick_shorthand_assets_asset_slot_chk
        check (asset_slot > 0)
    );

    comment on table pcms.draft_pick_shorthand_assets is
      'Curated pick shorthand per team/year/round/slot (MF/LF pools, protections), stored separately from PCMS summary-derived warehouses.';

    comment on column pcms.draft_pick_shorthand_assets.team_code is
      'NBA team code (e.g., POR, BKN, SAS).';

    comment on column pcms.draft_pick_shorthand_assets.shorthand_input is
      'Raw shorthand input (may not be normalized).';

    comment on column pcms.draft_pick_shorthand_assets.shorthand is
      'Canonical normalized shorthand (preferred display form).';

    comment on column pcms.draft_pick_shorthand_assets.endnote_ids is
      'Related endnote ids in pcms.endnotes (kept out of shorthand text).';

    comment on column pcms.draft_pick_shorthand_assets.referenced_team_codes is
      'Team codes referenced inside shorthand (for search/filter).';

    comment on column pcms.draft_pick_shorthand_assets.shorthand_ast is
      'Optional JSON AST representing parsed shorthand expression (future-proofing).';
  end if;
end $$;

create index if not exists draft_pick_shorthand_assets_team_year_idx
  on pcms.draft_pick_shorthand_assets (team_code, draft_year);

create index if not exists draft_pick_shorthand_assets_year_round_idx
  on pcms.draft_pick_shorthand_assets (draft_year, draft_round);

create index if not exists draft_pick_shorthand_assets_endnote_ids_gin_idx
  on pcms.draft_pick_shorthand_assets using gin (endnote_ids);

create index if not exists draft_pick_shorthand_assets_referenced_team_codes_gin_idx
  on pcms.draft_pick_shorthand_assets using gin (referenced_team_codes);

commit;
