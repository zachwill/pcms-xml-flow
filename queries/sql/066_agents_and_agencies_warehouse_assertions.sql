-- 066_agents_and_agencies_warehouse_assertions.sql
--
-- Validate:
-- 1) Warehouse row counts match identity tables.
-- 2) cap_2025_total rollups match salary_book_warehouse-derived expectations.
-- 3) Percentile columns are in [0, 1].

DO $$
DECLARE
  agents_expected int;
  agents_actual int;
  agencies_expected int;
  agencies_actual int;
BEGIN
  SELECT COUNT(*) INTO agents_expected FROM pcms.agents;
  SELECT COUNT(*) INTO agents_actual FROM pcms.agents_warehouse;

  IF agents_expected <> agents_actual THEN
    RAISE EXCEPTION
      'agents_warehouse row count mismatch: expected %, got %',
      agents_expected, agents_actual;
  END IF;

  SELECT COUNT(*) INTO agencies_expected FROM pcms.agencies;
  SELECT COUNT(*) INTO agencies_actual FROM pcms.agencies_warehouse;

  IF agencies_expected <> agencies_actual THEN
    RAISE EXCEPTION
      'agencies_warehouse row count mismatch: expected %, got %',
      agencies_expected, agencies_actual;
  END IF;
END;
$$;

DO $$
DECLARE
  mismatch_count int;
BEGIN
  WITH expected AS (
    SELECT
      a.agent_id,
      COALESCE(SUM(sb.cap_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2025_total
    FROM pcms.agents a
    LEFT JOIN pcms.salary_book_warehouse sb
      ON sb.agent_id = a.agent_id
    GROUP BY a.agent_id
  )
  SELECT COUNT(*) INTO mismatch_count
  FROM expected e
  JOIN pcms.agents_warehouse w
    ON w.agent_id = e.agent_id
  WHERE w.cap_2025_total IS DISTINCT FROM e.cap_2025_total;

  IF mismatch_count > 0 THEN
    RAISE EXCEPTION
      'agents_warehouse cap_2025_total mismatch rows=%',
      mismatch_count;
  END IF;
END;
$$;

DO $$
DECLARE
  mismatch_count int;
BEGIN
  WITH expected AS (
    SELECT
      ag.agency_id,
      COALESCE(SUM(sb.cap_2025) FILTER (WHERE NOT COALESCE(sb.is_two_way, false)), 0)::bigint AS cap_2025_total
    FROM pcms.agencies ag
    LEFT JOIN pcms.agents a
      ON a.agency_id = ag.agency_id
    LEFT JOIN pcms.salary_book_warehouse sb
      ON sb.agent_id = a.agent_id
    GROUP BY ag.agency_id
  )
  SELECT COUNT(*) INTO mismatch_count
  FROM expected e
  JOIN pcms.agencies_warehouse w
    ON w.agency_id = e.agency_id
  WHERE w.cap_2025_total IS DISTINCT FROM e.cap_2025_total;

  IF mismatch_count > 0 THEN
    RAISE EXCEPTION
      'agencies_warehouse cap_2025_total mismatch rows=%',
      mismatch_count;
  END IF;
END;
$$;

DO $$
DECLARE
  out_of_range_count int;
BEGIN
  SELECT COUNT(*) INTO out_of_range_count
  FROM pcms.agents_warehouse w
  WHERE (w.cap_2025_total_percentile IS NOT NULL AND (w.cap_2025_total_percentile < 0 OR w.cap_2025_total_percentile > 1))
     OR (w.cap_2026_total_percentile IS NOT NULL AND (w.cap_2026_total_percentile < 0 OR w.cap_2026_total_percentile > 1))
     OR (w.cap_2027_total_percentile IS NOT NULL AND (w.cap_2027_total_percentile < 0 OR w.cap_2027_total_percentile > 1))
     OR (w.client_count_percentile IS NOT NULL AND (w.client_count_percentile < 0 OR w.client_count_percentile > 1))
     OR (w.max_contract_count_percentile IS NOT NULL AND (w.max_contract_count_percentile < 0 OR w.max_contract_count_percentile > 1));

  IF out_of_range_count > 0 THEN
    RAISE EXCEPTION
      'agents_warehouse percentile out-of-range rows=%',
      out_of_range_count;
  END IF;
END;
$$;

DO $$
DECLARE
  out_of_range_count int;
BEGIN
  SELECT COUNT(*) INTO out_of_range_count
  FROM pcms.agencies_warehouse w
  WHERE (w.cap_2025_total_percentile IS NOT NULL AND (w.cap_2025_total_percentile < 0 OR w.cap_2025_total_percentile > 1))
     OR (w.cap_2026_total_percentile IS NOT NULL AND (w.cap_2026_total_percentile < 0 OR w.cap_2026_total_percentile > 1))
     OR (w.cap_2027_total_percentile IS NOT NULL AND (w.cap_2027_total_percentile < 0 OR w.cap_2027_total_percentile > 1))
     OR (w.client_count_percentile IS NOT NULL AND (w.client_count_percentile < 0 OR w.client_count_percentile > 1))
     OR (w.max_contract_count_percentile IS NOT NULL AND (w.max_contract_count_percentile < 0 OR w.max_contract_count_percentile > 1))
     OR (w.agent_count_percentile IS NOT NULL AND (w.agent_count_percentile < 0 OR w.agent_count_percentile > 1));

  IF out_of_range_count > 0 THEN
    RAISE EXCEPTION
      'agencies_warehouse percentile out-of-range rows=%',
      out_of_range_count;
  END IF;
END;
$$;
