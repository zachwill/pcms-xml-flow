-- 051_draft_picks_warehouses_assertions.sql
-- Assertion-style checks for draft picks warehouses.

DO $$
DECLARE c int;
DECLARE miny int;
DECLARE maxy int;
BEGIN
  -- Ensure tables exist
  IF to_regclass('pcms.draft_picks_warehouse') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.draft_picks_warehouse';
  END IF;

  IF to_regclass('pcms.draft_pick_slots_warehouse') IS NULL THEN
    RAISE EXCEPTION 'missing relation: pcms.draft_pick_slots_warehouse';
  END IF;

  -- Ensure new outcomes JSON exists (added in 039)
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='pcms'
      AND table_name='draft_pick_slots_warehouse'
      AND column_name='ownership_outcomes_json'
  ) THEN
    RAISE EXCEPTION 'pcms.draft_pick_slots_warehouse missing ownership_outcomes_json (run migration 039)';
  END IF;

  -- Non-empty
  SELECT COUNT(*) INTO c FROM pcms.draft_picks_warehouse;
  IF c = 0 THEN
    RAISE EXCEPTION 'pcms.draft_picks_warehouse is empty';
  END IF;

  SELECT COUNT(*) INTO c FROM pcms.draft_pick_slots_warehouse;
  IF c = 0 THEN
    RAISE EXCEPTION 'pcms.draft_pick_slots_warehouse is empty';
  END IF;

  -- No blank team codes
  SELECT COUNT(*) INTO c FROM pcms.draft_picks_warehouse WHERE coalesce(team_code,'') = '';
  IF c > 0 THEN
    RAISE EXCEPTION 'pcms.draft_picks_warehouse has % blank team_code values', c;
  END IF;

  SELECT COUNT(*) INTO c FROM pcms.draft_pick_slots_warehouse
   WHERE coalesce(current_team_code,'') = '' OR coalesce(original_team_code,'') = '';
  IF c > 0 THEN
    RAISE EXCEPTION 'pcms.draft_pick_slots_warehouse has % blank team code values', c;
  END IF;

  -- Year bounds sanity (matches summaries: 2018-2032)
  SELECT min(draft_year), max(draft_year) INTO miny, maxy FROM pcms.draft_picks_warehouse;
  IF miny < 2018 OR maxy > 2032 THEN
    RAISE EXCEPTION 'pcms.draft_picks_warehouse draft_year out of expected range: [% - %]', miny, maxy;
  END IF;

  -- Regression: ensure we are splitting on literal "|" not every character
  -- Fixture: POR 2025 2nd round should be exactly one fragment (no single-letter explosion)
  SELECT COUNT(*) INTO c
  FROM pcms.draft_picks_warehouse
  WHERE team_code='POR' AND draft_year=2025 AND draft_round=2;

  IF c <> 1 THEN
    RAISE EXCEPTION 'Expected exactly 1 POR 2025 round-2 fragment, got % (splitter regression)', c;
  END IF;

  SELECT COUNT(*) INTO c
  FROM pcms.draft_picks_warehouse
  WHERE team_code='POR' AND draft_year=2025 AND draft_round=2
    AND raw_fragment = 'To TOR(259) (via SAC(15))';

  IF c <> 1 THEN
    RAISE EXCEPTION 'POR 2025 round-2 raw_fragment mismatch (splitter regression)';
  END IF;

  -- Regression: endnote refs should be extracted
  SELECT COUNT(*) INTO c
  FROM pcms.draft_picks_warehouse
  WHERE team_code='CHI' AND draft_year=2023 AND draft_round=1 AND asset_slot=1
    AND endnote_refs = array[96]::int[];

  IF c <> 1 THEN
    RAISE EXCEPTION 'Expected CHI 2023 round-1 endnote_refs={96} (endnote extraction regression)';
  END IF;
END
$$;
