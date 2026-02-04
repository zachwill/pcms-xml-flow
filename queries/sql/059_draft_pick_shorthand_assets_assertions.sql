-- 059_draft_pick_shorthand_assets_assertions.sql
-- Presence/invariant checks for curated pick shorthand storage.
--
-- NOTE: This table is expected to be empty initially; do not assert row counts.

DO $$
DECLARE c int;
BEGIN
  IF to_regclass('pcms.draft_pick_shorthand_assets') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.draft_pick_shorthand_assets';
  END IF;

  -- Ensure required columns exist (guards against partial/manual schema drift)
  SELECT COUNT(*) INTO c
  FROM information_schema.columns
  WHERE table_schema='pcms'
    AND table_name='draft_pick_shorthand_assets'
    AND column_name IN (
      'team_code',
      'draft_year',
      'draft_round',
      'asset_slot',
      'shorthand_input',
      'shorthand',
      'endnote_ids',
      'referenced_team_codes'
    );

  IF c <> 8 THEN
    RAISE EXCEPTION 'pcms.draft_pick_shorthand_assets missing expected columns (found %/8)', c;
  END IF;
END
$$;
