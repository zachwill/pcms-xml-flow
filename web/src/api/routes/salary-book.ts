import { SQL } from "bun";
import { RouteRegistry } from "@/lib/server/router";

/**
 * NBA Salary Book API Routes
 *
 * Endpoints for fetching salary data from PostgreSQL (pcms schema)
 */
export const salaryBookRouter = new RouteRegistry();

// Lazily initialize SQL connection (requires POSTGRES_URL)
let sql: SQL | null = null;
function getSql() {
  const url = process.env.POSTGRES_URL;
  if (!url) {
    throw new Error("POSTGRES_URL is not set");
  }
  if (!sql) {
    sql = new SQL(url);
  }
  return sql;
}

// Cached feature flags for optional tables.
//
// Some deployments may not run the NBA Stats ingest, so `public.nba_players`
// (used only for `position`) can be missing.
let hasPublicNbaPlayersTable: boolean | null = null;
async function getHasPublicNbaPlayersTable(): Promise<boolean> {
  if (hasPublicNbaPlayersTable !== null) return hasPublicNbaPlayersTable;

  const sql = getSql();
  const rows = await sql`
    SELECT to_regclass('public.nba_players') IS NOT NULL AS ok
  `;

  hasPublicNbaPlayersTable = !!rows?.[0]?.ok;
  return hasPublicNbaPlayersTable;
}

// Trade evaluation helpers
const TRADE_MODES = new Set([
  "expanded",
  "standard",
  "aggregated_standard",
  "transition",
]);

function normalizeTradeMode(value: unknown): string {
  if (typeof value !== "string") return "expanded";
  const mode = value.trim().toLowerCase();
  return TRADE_MODES.has(mode) ? mode : "expanded";
}

function normalizeTeamCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  return code.length > 0 ? code : null;
}

function normalizeIdArray(value: unknown): number[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((id) => Number(id))
    .filter((id) => Number.isFinite(id));
}

const PICK_PROTECTION_REGEX = /(Top\s+\d+|Lottery|Unprotected)[\s-]*(Protected)?/i;

function parsePickProtections(fragment: string | null | undefined): string | null {
  if (!fragment) return null;
  const match = fragment.match(PICK_PROTECTION_REGEX);
  return match ? match[0] : null;
}

// GET /api/salary-book/teams
// Fetch all NBA teams from pcms.teams
salaryBookRouter.get("/teams", async () => {
  const sql = getSql();
  const teams = await sql`
    SELECT
      team_id,
      team_code,
      team_name,
      team_nickname,
      city,
      conference_name
    FROM pcms.teams
    WHERE league_lk = 'NBA'
      AND is_active = true
    ORDER BY conference_name, team_code
  `;

  // Map to frontend format
  const result = teams.map((t: any) => ({
    team_id: Number(t.team_id),
    team_code: t.team_code,
    name: t.team_name,
    nickname: t.team_nickname,
    city: t.city,
    conference: t.conference_name === "Eastern" ? "EAST" : "WEST",
  }));

  return Response.json(result);
});

// GET /api/salary-book/system-values?from=2025&to=2030
// Fetch NBA league system values (cap/tax/apron lines, exception constants, key dates)
salaryBookRouter.get("/system-values", async (req) => {
  const url = new URL(req.url);
  const from = Number(url.searchParams.get("from") ?? "2025");
  const to = Number(url.searchParams.get("to") ?? "2030");

  if (!Number.isFinite(from) || !Number.isFinite(to)) {
    return Response.json({ error: "from/to must be numbers" }, { status: 400 });
  }

  const minYear = Math.min(from, to);
  const maxYear = Math.max(from, to);

  const sql = getSql();

  const rows = await sql`
    SELECT
      salary_year as year,

      salary_cap_amount::numeric,
      tax_level_amount::numeric,
      tax_apron_amount::numeric as first_apron_amount,
      tax_apron2_amount::numeric as second_apron_amount,
      minimum_team_salary_amount::numeric,
      tax_bracket_amount::numeric,

      non_taxpayer_mid_level_amount::numeric,
      taxpayer_mid_level_amount::numeric,
      room_mid_level_amount::numeric,
      bi_annual_amount::numeric,
      two_way_salary_amount::numeric,
      tpe_dollar_allowance::numeric,
      max_trade_cash_amount::numeric,
      international_player_payment_limit::numeric,

      maximum_salary_25_pct::numeric,
      maximum_salary_30_pct::numeric,
      maximum_salary_35_pct::numeric,

      scale_raise_rate::numeric,
      days_in_season,

      season_start_at::date,
      season_end_at::date,
      moratorium_start_at::date,
      moratorium_end_at::date,
      trade_deadline_at::date,
      dec_15_trade_lift_at::date,
      jan_15_trade_lift_at::date,
      jan_10_guarantee_at::date
    FROM pcms.league_system_values
    WHERE league_lk = 'NBA'
      AND salary_year BETWEEN ${minYear} AND ${maxYear}
    ORDER BY salary_year
  `;

  return Response.json(rows);
});

// GET /api/salary-book/tax-rates?year=2025
// Fetch NBA luxury tax rate brackets (amount-over-tax → marginal rate)
salaryBookRouter.get("/tax-rates", async (req) => {
  const url = new URL(req.url);
  const year = Number(url.searchParams.get("year") ?? "2025");

  if (!Number.isFinite(year)) {
    return Response.json({ error: "year must be a number" }, { status: 400 });
  }

  const sql = getSql();

  const rows = await sql`
    SELECT
      salary_year as year,
      lower_limit::numeric,
      upper_limit::numeric,
      tax_rate_non_repeater::numeric,
      tax_rate_repeater::numeric,
      base_charge_non_repeater::numeric,
      base_charge_repeater::numeric
    FROM pcms.league_tax_rates
    WHERE league_lk = 'NBA'
      AND salary_year = ${year}
    ORDER BY lower_limit
  `;

  return Response.json(rows);
});

// GET /api/salary-book/players?team=:teamCode
// Fetch player salaries from pcms.salary_book_warehouse
salaryBookRouter.get("/players", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const hasNbaPlayers = await getHasPublicNbaPlayersTable();
  const positionExpr = hasNbaPlayers
    ? sql.unsafe("np.primary_position")
    : sql.unsafe("NULL::text");
  const nbaPlayersJoin = hasNbaPlayers
    ? sql.unsafe("LEFT JOIN public.nba_players np ON np.nba_id = s.player_id")
    : sql.unsafe("");

  const players = await sql`
    SELECT
      s.player_id as id,
      s.player_id,
      COALESCE(
        NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
        s.player_name
      ) as player_name,
      p.display_first_name,
      p.display_last_name,
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code) as team_code,
      ${positionExpr} as position,
      s.age,
      p.years_of_service,
      s.cap_2025::numeric,
      s.cap_2026::numeric,
      s.cap_2027::numeric,
      s.cap_2028::numeric,
      s.cap_2029::numeric,
      s.cap_2030::numeric,
      s.pct_cap_2025::numeric,
      s.pct_cap_2026::numeric,
      s.pct_cap_2027::numeric,
      s.pct_cap_2028::numeric,
      s.pct_cap_2029::numeric,
      s.pct_cap_2030::numeric,
      s.pct_cap_percentile_2025::numeric,
      s.pct_cap_percentile_2026::numeric,
      s.pct_cap_percentile_2027::numeric,
      s.pct_cap_percentile_2028::numeric,
      s.pct_cap_percentile_2029::numeric,
      s.pct_cap_percentile_2030::numeric,
      s.option_2025,
      s.option_2026,
      s.option_2027,
      s.option_2028,
      s.option_2029,
      s.option_2030,

      s.guaranteed_amount_2025::numeric,
      s.guaranteed_amount_2026::numeric,
      s.guaranteed_amount_2027::numeric,
      s.guaranteed_amount_2028::numeric,
      s.guaranteed_amount_2029::numeric,
      s.guaranteed_amount_2030::numeric,

      s.is_fully_guaranteed_2025,
      s.is_fully_guaranteed_2026,
      s.is_fully_guaranteed_2027,
      s.is_fully_guaranteed_2028,
      s.is_fully_guaranteed_2029,
      s.is_fully_guaranteed_2030,

      s.is_partially_guaranteed_2025,
      s.is_partially_guaranteed_2026,
      s.is_partially_guaranteed_2027,
      s.is_partially_guaranteed_2028,
      s.is_partially_guaranteed_2029,
      s.is_partially_guaranteed_2030,

      s.is_non_guaranteed_2025,
      s.is_non_guaranteed_2026,
      s.is_non_guaranteed_2027,
      s.is_non_guaranteed_2028,
      s.is_non_guaranteed_2029,
      s.is_non_guaranteed_2030,

      s.likely_bonus_2025::numeric,
      s.likely_bonus_2026::numeric,
      s.likely_bonus_2027::numeric,
      s.likely_bonus_2028::numeric,
      s.likely_bonus_2029::numeric,
      s.likely_bonus_2030::numeric,

      s.unlikely_bonus_2025::numeric,
      s.unlikely_bonus_2026::numeric,
      s.unlikely_bonus_2027::numeric,
      s.unlikely_bonus_2028::numeric,
      s.unlikely_bonus_2029::numeric,
      s.unlikely_bonus_2030::numeric,

      s.agent_id,
      s.agent_name,
      a.agency_id,
      a.agency_name,
      COALESCE(s.is_two_way, false)::boolean as is_two_way,
      COALESCE(s.is_poison_pill, false)::boolean as is_poison_pill,
      s.poison_pill_amount::numeric as poison_pill_amount,
      COALESCE(s.is_no_trade, false)::boolean as is_no_trade,
      COALESCE(s.is_trade_bonus, false)::boolean as is_trade_bonus,
      s.trade_bonus_percent::numeric as trade_bonus_percent,

      s.contract_type_code,
      s.contract_type_lookup_value,

      s.signed_method_code,
      s.signed_method_lookup_value,
      s.team_exception_id,
      s.exception_type_code,
      s.exception_type_lookup_value,
      s.min_contract_code,
      s.min_contract_lookup_value,
      COALESCE(s.is_min_contract, false)::boolean as is_min_contract,
      s.trade_restriction_code,
      s.trade_restriction_lookup_value,
      s.trade_restriction_end_date,
      COALESCE(s.is_trade_restricted_now, false)::boolean as is_trade_restricted_now,

      COALESCE(s.is_trade_consent_required_now, false)::boolean as is_trade_consent_required_now,
      COALESCE(s.is_trade_preconsented, false)::boolean as is_trade_preconsented,
      s.player_consent_lk,

      CASE
        WHEN s.signed_method_code = 'BRD' THEN 'BIRD'
        WHEN s.signed_method_code = 'EBE' THEN 'EARLY_BIRD'
        WHEN s.signed_method_code = 'NBE' THEN 'NON_BIRD'
        ELSE NULL
      END as bird_rights
    FROM pcms.salary_book_warehouse s
    LEFT JOIN pcms.people p ON s.player_id = p.person_id
    ${nbaPlayersJoin}
    LEFT JOIN pcms.agents a ON s.agent_id = a.agent_id
    WHERE COALESCE(NULLIF(s.person_team_code, ''), s.team_code) = ${teamCode}
    ORDER BY
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code),
      s.cap_2025 DESC NULLS LAST,
      p.years_of_service DESC NULLS LAST,
      p.display_last_name ASC NULLS LAST,
      p.display_first_name ASC NULLS LAST
  `;

  return Response.json(players);
});

// GET /api/salary-book/cap-holds?team=:teamCode
// Fetch cap holds from pcms.cap_holds_warehouse for the current season only (2025)
salaryBookRouter.get("/cap-holds", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const holds = await sql`
    SELECT
      non_contract_amount_id as id,
      team_code,
      player_id,
      player_name,
      amount_type_lk,

      MAX(cap_amount) FILTER (WHERE salary_year = 2025)::numeric as cap_2025,
      MAX(cap_amount) FILTER (WHERE salary_year = 2026)::numeric as cap_2026,
      MAX(cap_amount) FILTER (WHERE salary_year = 2027)::numeric as cap_2027,
      MAX(cap_amount) FILTER (WHERE salary_year = 2028)::numeric as cap_2028,
      MAX(cap_amount) FILTER (WHERE salary_year = 2029)::numeric as cap_2029
    FROM pcms.cap_holds_warehouse
    WHERE team_code = ${teamCode}
      AND salary_year BETWEEN 2025 AND 2029
    GROUP BY non_contract_amount_id, team_code, player_id, player_name, amount_type_lk
    ORDER BY cap_2025 DESC NULLS LAST, player_name ASC NULLS LAST
  `;

  return Response.json(holds);
});

// GET /api/salary-book/exceptions?team=:teamCode
// Fetch exceptions from pcms.exceptions_warehouse for years 2025-2029
salaryBookRouter.get("/exceptions", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const exceptions = await sql`
    SELECT
      team_exception_id as id,
      team_code,
      exception_type_lk,
      exception_type_name,
      trade_exception_player_id,
      trade_exception_player_name,
      expiration_date,
      is_expired,

      MAX(remaining_amount) FILTER (WHERE salary_year = 2025)::numeric as remaining_2025,
      MAX(remaining_amount) FILTER (WHERE salary_year = 2026)::numeric as remaining_2026,
      MAX(remaining_amount) FILTER (WHERE salary_year = 2027)::numeric as remaining_2027,
      MAX(remaining_amount) FILTER (WHERE salary_year = 2028)::numeric as remaining_2028,
      MAX(remaining_amount) FILTER (WHERE salary_year = 2029)::numeric as remaining_2029
    FROM pcms.exceptions_warehouse
    WHERE team_code = ${teamCode}
      AND salary_year BETWEEN 2025 AND 2029
      AND COALESCE(is_expired, false) = false
    GROUP BY
      team_exception_id,
      team_code,
      exception_type_lk,
      exception_type_name,
      trade_exception_player_id,
      trade_exception_player_name,
      expiration_date,
      is_expired
    ORDER BY remaining_2025 DESC NULLS LAST, exception_type_name ASC NULLS LAST
  `;

  return Response.json(exceptions);
});

// GET /api/salary-book/dead-money?team=:teamCode
// Fetch dead money from pcms.dead_money_warehouse for years 2025-2029
salaryBookRouter.get("/dead-money", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const deadMoney = await sql`
    SELECT
      transaction_waiver_amount_id as id,
      team_code,
      player_id,
      player_name,
      waive_date,

      MAX(cap_value) FILTER (WHERE salary_year = 2025)::numeric as cap_2025,
      MAX(cap_value) FILTER (WHERE salary_year = 2026)::numeric as cap_2026,
      MAX(cap_value) FILTER (WHERE salary_year = 2027)::numeric as cap_2027,
      MAX(cap_value) FILTER (WHERE salary_year = 2028)::numeric as cap_2028,
      MAX(cap_value) FILTER (WHERE salary_year = 2029)::numeric as cap_2029
    FROM pcms.dead_money_warehouse
    WHERE team_code = ${teamCode}
      AND salary_year BETWEEN 2025 AND 2029
    GROUP BY transaction_waiver_amount_id, team_code, player_id, player_name, waive_date
    ORDER BY cap_2025 DESC NULLS LAST, player_name ASC NULLS LAST
  `;

  return Response.json(deadMoney);
});

// GET /api/salary-book/team-salary?team=:teamCode
// Fetch team salary totals from pcms.team_salary_warehouse for years 2025-2030
salaryBookRouter.get("/team-salary", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const salaries = await sql`
    SELECT
      team_code,
      salary_year as year,

      -- Totals
      cap_total::float8,
      tax_total::float8,
      apron_total::float8,
      mts_total::float8,

      -- Breakdown (optional but useful for sidebar/detail views)
      cap_rost::float8,
      cap_fa::float8,
      cap_term::float8,
      cap_2way::float8,
      tax_rost::float8,
      tax_fa::float8,
      tax_term::float8,
      tax_2way::float8,
      apron_rost::float8,
      apron_fa::float8,
      apron_term::float8,
      apron_2way::float8,

      -- Counts
      roster_row_count,
      fa_row_count,
      term_row_count,
      two_way_row_count,

      -- Thresholds
      salary_cap_amount::float8,
      tax_level_amount::float8,
      tax_apron_amount::float8 as first_apron_amount,
      tax_apron2_amount::float8 as second_apron_amount,
      minimum_team_salary_amount::float8,

      -- Space / overage
      (COALESCE(salary_cap_amount, 0) - COALESCE(cap_total, 0))::float8 as cap_space,
      over_cap::float8,
      room_under_tax::float8,
      room_under_apron1::float8 as room_under_first_apron,
      room_under_apron2::float8 as room_under_second_apron,

      -- Flags (compute from "room_under_*" because warehouse booleans can be unset)
      (COALESCE(over_cap, 0) > 0) as is_over_cap,
      (COALESCE(room_under_tax, 0) < 0) as is_over_tax,
      (COALESCE(room_under_apron1, 0) < 0) as is_over_first_apron,
      (COALESCE(room_under_apron2, 0) < 0) as is_over_second_apron,

      -- Raw warehouse flags
      is_taxpayer,
      is_repeater_taxpayer,
      is_subject_to_apron,
      apron_level_lk,

      CASE
        WHEN COALESCE(tax_total, 0) > COALESCE(tax_level_amount, 0)
          THEN pcms.fn_luxury_tax_amount(
            salary_year,
            COALESCE(tax_total, 0) - COALESCE(tax_level_amount, 0),
            COALESCE(is_repeater_taxpayer, false)
          )
        ELSE NULL
      END::float8 as luxury_tax_bill,

      refreshed_at
    FROM pcms.team_salary_warehouse
    WHERE team_code = ${teamCode}
      AND salary_year BETWEEN 2025 AND 2030
    ORDER BY salary_year
  `;

  return Response.json(salaries);
});

// GET /api/salary-book/picks?team=:teamCode
// Fetch draft picks from pcms.draft_picks_warehouse
salaryBookRouter.get("/picks", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const picks = await sql`
    SELECT
      team_code,
      draft_year as year,
      draft_round as round,
      asset_slot,
      sub_asset_slot,
      asset_type,
      is_conditional,
      is_swap,
      raw_fragment as description
    FROM pcms.draft_assets_warehouse
    WHERE team_code = ${teamCode}
      AND draft_year BETWEEN 2025 AND 2030
    ORDER BY draft_year, draft_round, asset_slot, sub_asset_slot
  `;

  return Response.json(picks);
});

// GET /api/salary-book/player-rights?team=:teamCode
// Fetch draft rights / returning rights from pcms.player_rights_warehouse
salaryBookRouter.get("/player-rights", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const rights = await sql`
    SELECT
      player_id,
      player_name,
      league_lk,
      rights_team_id,
      rights_team_code,
      rights_kind,
      rights_source,
      source_trade_id,
      source_trade_date,
      draft_year,
      draft_round,
      draft_pick,
      draft_team_id,
      draft_team_code,
      has_active_nba_contract,
      needs_review
    FROM pcms.player_rights_warehouse
    WHERE rights_team_code = ${teamCode}
    ORDER BY
      CASE rights_kind
        WHEN 'NBA_DRAFT_RIGHTS' THEN 1
        WHEN 'DLG_RETURNING_RIGHTS' THEN 2
        ELSE 3
      END,
      draft_year DESC NULLS LAST,
      draft_round NULLS LAST,
      draft_pick NULLS LAST,
      player_name ASC NULLS LAST
  `;

  return Response.json(rights);
});

// GET /api/salary-book/agent/:agentId
// Fetch agent info + their clients from salary_book_warehouse
salaryBookRouter.get("/agent/:agentId", async (req) => {
  const agentId = req.params.agentId;
  const sql = getSql();

  // Fetch agent info
  const agents = await sql`
    SELECT
      agent_id,
      full_name as name,
      agency_id,
      agency_name
    FROM pcms.agents
    WHERE agent_id = ${agentId}
    LIMIT 1
  `;

  if (agents.length === 0) {
    return Response.json({ error: "Agent not found" }, { status: 404 });
  }

  const agent = agents[0];

  // Fetch clients
  const clients = await sql`
    SELECT
      s.player_id,
      COALESCE(
        NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
        s.player_name
      ) as player_name,
      p.display_first_name,
      p.display_last_name,
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code) as team_code,
      s.age,
      p.years_of_service,
      s.cap_2025::numeric,
      s.cap_2026::numeric,
      s.cap_2027::numeric,
      s.cap_2028::numeric,
      s.cap_2029::numeric,
      s.cap_2030::numeric,
      COALESCE(s.is_two_way, false)::boolean as is_two_way
    FROM pcms.salary_book_warehouse s
    LEFT JOIN pcms.people p ON s.player_id = p.person_id
    WHERE s.agent_id = ${agentId}
    ORDER BY s.cap_2025 DESC NULLS LAST, player_name
  `;

  return Response.json({
    ...agent,
    clients,
  });
});

// GET /api/salary-book/player/:playerId
// Fetch a single player's full details
salaryBookRouter.get("/player/:playerId", async (req) => {
  const playerId = req.params.playerId;
  const sql = getSql();

  const hasNbaPlayers = await getHasPublicNbaPlayersTable();
  const positionExpr = hasNbaPlayers
    ? sql.unsafe("np.primary_position")
    : sql.unsafe("NULL::text");
  const nbaPlayersJoin = hasNbaPlayers
    ? sql.unsafe("LEFT JOIN public.nba_players np ON np.nba_id = s.player_id")
    : sql.unsafe("");

  const players = await sql`
    SELECT
      s.player_id,
      s.contract_id,
      s.version_number,
      COALESCE(
        NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
        s.player_name
      ) as player_name,
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code) as team_code,
      ${positionExpr} as position,
      s.age,
      p.years_of_service,
      s.cap_2025::numeric,
      s.cap_2026::numeric,
      s.cap_2027::numeric,
      s.cap_2028::numeric,
      s.cap_2029::numeric,
      s.cap_2030::numeric,
      s.option_2025,
      s.option_2026,
      s.option_2027,
      s.option_2028,
      s.option_2029,
      s.option_2030,

      s.guaranteed_amount_2025::numeric,
      s.guaranteed_amount_2026::numeric,
      s.guaranteed_amount_2027::numeric,
      s.guaranteed_amount_2028::numeric,
      s.guaranteed_amount_2029::numeric,
      s.guaranteed_amount_2030::numeric,

      s.is_fully_guaranteed_2025,
      s.is_fully_guaranteed_2026,
      s.is_fully_guaranteed_2027,
      s.is_fully_guaranteed_2028,
      s.is_fully_guaranteed_2029,
      s.is_fully_guaranteed_2030,

      s.is_partially_guaranteed_2025,
      s.is_partially_guaranteed_2026,
      s.is_partially_guaranteed_2027,
      s.is_partially_guaranteed_2028,
      s.is_partially_guaranteed_2029,
      s.is_partially_guaranteed_2030,

      s.is_non_guaranteed_2025,
      s.is_non_guaranteed_2026,
      s.is_non_guaranteed_2027,
      s.is_non_guaranteed_2028,
      s.is_non_guaranteed_2029,
      s.is_non_guaranteed_2030,

      s.likely_bonus_2025::numeric,
      s.likely_bonus_2026::numeric,
      s.likely_bonus_2027::numeric,
      s.likely_bonus_2028::numeric,
      s.likely_bonus_2029::numeric,
      s.likely_bonus_2030::numeric,

      s.unlikely_bonus_2025::numeric,
      s.unlikely_bonus_2026::numeric,
      s.unlikely_bonus_2027::numeric,
      s.unlikely_bonus_2028::numeric,
      s.unlikely_bonus_2029::numeric,
      s.unlikely_bonus_2030::numeric,

      s.agent_id,
      s.agent_name,
      a.agency_id,
      a.agency_name,
      COALESCE(s.is_two_way, false)::boolean as is_two_way,
      COALESCE(s.is_poison_pill, false)::boolean as is_poison_pill,
      s.poison_pill_amount::numeric as poison_pill_amount,
      COALESCE(s.is_no_trade, false)::boolean as is_no_trade,
      COALESCE(s.is_trade_bonus, false)::boolean as is_trade_bonus,
      s.trade_bonus_percent::numeric as trade_bonus_percent,

      s.contract_type_code,
      s.contract_type_lookup_value,

      s.signed_method_code,
      s.signed_method_lookup_value,
      s.team_exception_id,
      s.exception_type_code,
      s.exception_type_lookup_value,
      s.min_contract_code,
      s.min_contract_lookup_value,
      COALESCE(s.is_min_contract, false)::boolean as is_min_contract,
      s.trade_restriction_code,
      s.trade_restriction_lookup_value,
      s.trade_restriction_end_date,
      COALESCE(s.is_trade_restricted_now, false)::boolean as is_trade_restricted_now,

      COALESCE(s.is_trade_consent_required_now, false)::boolean as is_trade_consent_required_now,
      COALESCE(s.is_trade_preconsented, false)::boolean as is_trade_preconsented,
      s.player_consent_lk,

      CASE
        WHEN s.signed_method_code = 'BRD' THEN 'BIRD'
        WHEN s.signed_method_code = 'EBE' THEN 'EARLY_BIRD'
        WHEN s.signed_method_code = 'NBE' THEN 'NON_BIRD'
        ELSE NULL
      END as bird_rights
    FROM pcms.salary_book_warehouse s
    LEFT JOIN pcms.people p ON s.player_id = p.person_id
    ${nbaPlayersJoin}
    LEFT JOIN pcms.agents a ON s.agent_id = a.agent_id
    WHERE s.player_id = ${playerId}
    LIMIT 1
  `;

  if (players.length === 0) {
    return Response.json({ error: "Player not found" }, { status: 404 });
  }

  const player = players[0] as any;
  const contractId = Number(player.contract_id);
  const versionNumber = Number(player.version_number);
  const hasContract =
    Number.isFinite(contractId) &&
    contractId > 0 &&
    Number.isFinite(versionNumber);

  let protections: any[] = [];
  let bonuses: any[] = [];

  if (hasContract) {
    protections = await sql`
      SELECT
        cp.protection_id,
        cp.salary_year,
        cp.protection_coverage_lk,
        cp.protection_amount::numeric,
        cp.effective_protection_amount::numeric,
        cp.is_conditional_protection,
        cp.protection_types_json,
        cp.conditional_protection_comments,
        COALESCE(
          jsonb_agg(
            jsonb_build_object(
              'condition_id', cpc.condition_id,
              'amount', cpc.amount,
              'clause_name', cpc.clause_name,
              'earned_date', cpc.earned_date,
              'earned_type_lk', cpc.earned_type_lk,
              'is_full_condition', cpc.is_full_condition,
              'criteria_description', cpc.criteria_description,
              'criteria_json', cpc.criteria_json
            ) ORDER BY cpc.condition_id
          ) FILTER (WHERE cpc.condition_id IS NOT NULL),
          '[]'::jsonb
        ) AS conditions
      FROM pcms.contract_protections cp
      LEFT JOIN pcms.contract_protection_conditions cpc
        ON cp.contract_id = cpc.contract_id
       AND cp.version_number = cpc.version_number
       AND cp.protection_id = cpc.protection_id
      WHERE cp.contract_id = ${contractId}
        AND cp.version_number = ${versionNumber}
      GROUP BY
        cp.protection_id,
        cp.salary_year,
        cp.protection_coverage_lk,
        cp.protection_amount,
        cp.effective_protection_amount,
        cp.is_conditional_protection,
        cp.protection_types_json,
        cp.conditional_protection_comments
      ORDER BY cp.salary_year, cp.protection_id
    `;

    bonuses = await sql`
      SELECT
        bonus_id,
        salary_year,
        bonus_amount::numeric,
        bonus_type_lk,
        is_likely,
        earned_lk,
        paid_by_date,
        clause_name,
        criteria_description,
        criteria_json
      FROM pcms.contract_bonuses
      WHERE contract_id = ${contractId}
        AND version_number = ${versionNumber}
      ORDER BY salary_year, bonus_id
    `;
  }

  const { contract_id: _contractId, version_number: _versionNumber, ...playerData } = player;

  return Response.json({
    ...playerData,
    contract_protections: protections,
    contract_bonuses: bonuses,
  });
});

// GET /api/salary-book/pick?team=:teamCode&year=:year&round=:round
// Fetch a single pick's details by team, year, and round
salaryBookRouter.get("/pick", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");
  const yearStr = url.searchParams.get("year");
  const roundStr = url.searchParams.get("round");

  if (!teamCode || !yearStr || !roundStr) {
    return Response.json(
      { error: "team, year, and round parameters required" },
      { status: 400 }
    );
  }

  const year = parseInt(yearStr, 10);
  const round = parseInt(roundStr, 10);

  if (isNaN(year) || isNaN(round)) {
    return Response.json(
      { error: "year and round must be valid integers" },
      { status: 400 }
    );
  }

  const sql = getSql();

  const assets = await sql`
    SELECT
      team_code,
      draft_year as year,
      draft_round as round,
      asset_slot,
      sub_asset_slot,
      asset_type,
      is_conditional,
      is_swap,
      counterparty_team_code,
      counterparty_team_codes,
      via_team_codes,
      raw_fragment,
      raw_part,
      endnote_refs,
      primary_endnote_id,
      endnote_trade_date,
      endnote_explanation,
      endnote_is_swap,
      endnote_is_conditional,
      endnote_depends_on,
      needs_review
    FROM pcms.draft_assets_warehouse
    WHERE team_code = ${teamCode}
      AND draft_year = ${year}
      AND draft_round = ${round}
    ORDER BY asset_slot, sub_asset_slot
  `;

  if (assets.length === 0) {
    return Response.json({ error: "Pick not found" }, { status: 404 });
  }

  const primary = assets[0] as any;
  const rawFragment = primary.raw_fragment || "";
  const primaryCounterpartyCodes = Array.isArray(primary.counterparty_team_codes)
    ? primary.counterparty_team_codes
    : [];
  const primaryCounterparty =
    primary.counterparty_team_code ?? primaryCounterpartyCodes[0] ?? null;

  let originTeamCode = teamCode;
  if (["HAS", "MAY_HAVE", "OTHER"].includes(primary.asset_type) && primaryCounterparty) {
    originTeamCode = primaryCounterparty;
  }

  const endnoteRefs = Array.from(
    new Set(
      assets
        .flatMap((row: any) => (Array.isArray(row.endnote_refs) ? row.endnote_refs : []))
        .map((id: any) => Number(id))
        .filter((id: number) => Number.isFinite(id))
    )
  ).sort((a, b) => Number(a) - Number(b));

  const endnotes = endnoteRefs.length > 0
    ? await sql`
        SELECT
          endnote_id,
          trade_id,
          trade_date,
          is_swap,
          is_conditional,
          explanation,
          conditions_json,
          note_type,
          status_lk,
          resolution_lk,
          resolved_at,
          draft_years,
          draft_rounds,
          draft_year_start,
          draft_year_end,
          has_rollover,
          is_frozen_pick,
          teams_mentioned,
          from_team_codes,
          to_team_codes,
          trade_ids,
          depends_on_endnotes,
          trade_summary,
          conveyance_text,
          protections_text,
          contingency_text,
          exercise_text
        FROM pcms.endnotes
        WHERE endnote_id = ANY(${sql.array(endnoteRefs, "INT")})
        ORDER BY trade_date DESC NULLS LAST, endnote_id DESC
      `
    : [];

  const endnoteIdSet = new Set(
    endnotes.map((note: any) => Number(note.endnote_id)).filter(Number.isFinite)
  );
  const missingEndnoteRefs = endnoteRefs.filter((id) => !endnoteIdSet.has(id));

  const tradeClaimsRows = originTeamCode
    ? await sql`
        SELECT
          draft_year,
          draft_round,
          original_team_code,
          trade_claims_json,
          claims_count,
          distinct_to_teams_count,
          has_conditional_claims,
          has_swap_claims,
          latest_trade_id,
          latest_trade_date,
          needs_review
        FROM pcms.draft_pick_trade_claims_warehouse
        WHERE original_team_code = ${originTeamCode}
          AND draft_year = ${year}
          AND draft_round = ${round}
        LIMIT 1
      `
    : [];

  const tradeClaimsRow = tradeClaimsRows[0] as any | undefined;
  const tradeClaimsPayload = tradeClaimsRow?.trade_claims_json;
  let tradeClaimsArray: any[] = [];

  if (Array.isArray(tradeClaimsPayload)) {
    tradeClaimsArray = tradeClaimsPayload;
  } else if (typeof tradeClaimsPayload === "string") {
    try {
      const parsed = JSON.parse(tradeClaimsPayload);
      if (Array.isArray(parsed)) {
        tradeClaimsArray = parsed;
      }
    } catch {
      tradeClaimsArray = [];
    }
  }

  const tradeClaims = tradeClaimsRow
    ? {
        draft_year: tradeClaimsRow.draft_year,
        draft_round: tradeClaimsRow.draft_round,
        original_team_code: tradeClaimsRow.original_team_code,
        claims_count: tradeClaimsRow.claims_count,
        distinct_to_teams_count: tradeClaimsRow.distinct_to_teams_count,
        has_conditional_claims: tradeClaimsRow.has_conditional_claims,
        has_swap_claims: tradeClaimsRow.has_swap_claims,
        latest_trade_id: tradeClaimsRow.latest_trade_id,
        latest_trade_date: tradeClaimsRow.latest_trade_date,
        needs_review: tradeClaimsRow.needs_review,
        trade_claims: tradeClaimsArray,
      }
    : null;

  const teams = await sql`
    SELECT team_code, team_name, team_nickname
    FROM pcms.teams
    WHERE team_code IN (${teamCode}, ${originTeamCode})
      AND league_lk = 'NBA'
  `;

  const destinationTeam = teams.find((t: any) => t.team_code === teamCode) ?? null;
  const originTeam = teams.find((t: any) => t.team_code === originTeamCode) ?? null;

  const protections =
    endnotes.find((note: any) => note.protections_text)?.protections_text ??
    parsePickProtections(rawFragment);

  const isSwap = assets.some((row: any) => row.is_swap);
  const isConditional = assets.some((row: any) => row.is_conditional);

  return Response.json({
    team_code: teamCode,
    year,
    round,
    asset_type: primary.asset_type ?? null,
    description: rawFragment,
    origin_team_code: originTeamCode,
    origin_team: originTeam,
    destination_team: destinationTeam,
    protections,
    is_swap: isSwap,
    is_conditional: isConditional,
    endnotes,
    trade_claims: tradeClaims,
    missing_endnote_refs: missingEndnoteRefs,
    assets: assets.map((row: any) => ({
      asset_slot: row.asset_slot,
      sub_asset_slot: row.sub_asset_slot,
      asset_type: row.asset_type,
      is_conditional: row.is_conditional,
      is_swap: row.is_swap,
      counterparty_team_code: row.counterparty_team_code ?? null,
      counterparty_team_codes: Array.isArray(row.counterparty_team_codes)
        ? row.counterparty_team_codes
        : [],
      via_team_codes: Array.isArray(row.via_team_codes) ? row.via_team_codes : [],
      raw_fragment: row.raw_fragment,
      raw_part: row.raw_part,
      endnote_refs: normalizeIdArray(row.endnote_refs),
      primary_endnote_id: row.primary_endnote_id ?? null,
      endnote_trade_date: row.endnote_trade_date ?? null,
      endnote_explanation: row.endnote_explanation ?? null,
      endnote_is_swap: row.endnote_is_swap ?? null,
      endnote_is_conditional: row.endnote_is_conditional ?? null,
      endnote_depends_on: normalizeIdArray(row.endnote_depends_on),
      needs_review: row.needs_review ?? false,
    })),
  });
});

// POST /api/salary-book/trade-evaluate
// Evaluate a 2-team player-only trade via pcms.fn_tpe_trade_math
salaryBookRouter.post("/trade-evaluate", async (req) => {
  const body = await req.json().catch(() => null);

  if (!body || typeof body !== "object") {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const salaryYear = Number((body as any).salaryYear ?? 2025);
  if (!Number.isFinite(salaryYear)) {
    return Response.json({ error: "salaryYear must be a number" }, { status: 400 });
  }

  const league = typeof (body as any).league === "string" ? (body as any).league : "NBA";
  const mode = normalizeTradeMode((body as any).mode);

  const teamInputs = Array.isArray((body as any).teams) ? (body as any).teams : [];
  if (teamInputs.length === 0) {
    return Response.json({ error: "teams are required" }, { status: 400 });
  }

  const teams = teamInputs
    .map((team: any) => {
      const teamCode = normalizeTeamCode(team?.teamCode);
      if (!teamCode) return null;

      return {
        teamCode,
        outgoingPlayerIds: normalizeIdArray(team?.outgoingPlayerIds),
        incomingPlayerIds: normalizeIdArray(team?.incomingPlayerIds),
      };
    })
    .filter(Boolean) as Array<{
      teamCode: string;
      outgoingPlayerIds: number[];
      incomingPlayerIds: number[];
    }>;

  if (teams.length === 0) {
    return Response.json({ error: "No valid teams provided" }, { status: 400 });
  }

  const sql = getSql();

  const results = await Promise.all(
    teams.map(async (team) => {
      const outgoingArray = sql.array(team.outgoingPlayerIds, "INT");
      const incomingArray = sql.array(team.incomingPlayerIds, "INT");

      const rows = await sql`
        SELECT
          team_code,
          salary_year,
          tpe_type,
          traded_pre_trade_salary_total::float8 as outgoing_salary,
          replacement_post_salary_total::float8 as incoming_salary,
          baseline_apron_total::float8 as baseline_apron_total,
          post_trade_apron_total::float8 as post_trade_apron_total,
          first_apron_amount::float8 as first_apron_amount,
          is_padding_removed,
          tpe_padding_amount::float8 as tpe_padding_amount,
          tpe_dollar_allowance::float8 as tpe_dollar_allowance,
          max_replacement_salary::float8 as max_incoming,
          has_league_system_values,
          has_team_salary,
          traded_rows_found,
          replacement_rows_found
        FROM pcms.fn_tpe_trade_math(
          ${team.teamCode},
          ${salaryYear},
          ${outgoingArray},
          ${incomingArray},
          ${mode},
          ${league}
        )
      `;

      const row = rows[0] ?? {};
      const outgoingSalary = Number((row as any).outgoing_salary ?? 0);
      const outgoingForRange = Number.isFinite(outgoingSalary)
        ? Math.round(outgoingSalary)
        : 0;

      const ranges = await sql`
        SELECT
          min_incoming::float8 as min_incoming,
          max_incoming::float8 as max_incoming
        FROM pcms.fn_trade_salary_range(
          ${outgoingForRange},
          ${salaryYear},
          ${mode},
          ${league}
        )
      `;

      const range = ranges[0] ?? null;

      const reasonCodes: string[] = [];
      if (!(row as any).has_league_system_values) {
        reasonCodes.push("MISSING_SYSTEM_VALUES");
      }
      if (!(row as any).has_team_salary) {
        reasonCodes.push("MISSING_TEAM_SALARY");
      }
      if ((row as any).is_padding_removed) {
        reasonCodes.push("ALLOWANCE_ZERO_FIRST_APRON");
      }
      if ((row as any).max_incoming === null || (row as any).max_incoming === undefined) {
        reasonCodes.push("MISSING_MATCHING_FORMULA");
      }
      if (
        (row as any).max_incoming !== null &&
        (row as any).max_incoming !== undefined &&
        (row as any).incoming_salary !== null &&
        (row as any).incoming_salary !== undefined &&
        (row as any).incoming_salary > (row as any).max_incoming
      ) {
        reasonCodes.push("INCOMING_EXCEEDS_MAX");
      }
      if (
        typeof (row as any).traded_rows_found === "number" &&
        (row as any).traded_rows_found < team.outgoingPlayerIds.length
      ) {
        reasonCodes.push("OUTGOING_PLAYERS_NOT_FOUND");
      }
      if (
        typeof (row as any).replacement_rows_found === "number" &&
        (row as any).replacement_rows_found < team.incomingPlayerIds.length
      ) {
        reasonCodes.push("INCOMING_PLAYERS_NOT_FOUND");
      }

      const blockingReasons = reasonCodes.filter(
        (reason) => reason !== "ALLOWANCE_ZERO_FIRST_APRON"
      );

      return {
        team_code: team.teamCode,
        outgoing_salary: (row as any).outgoing_salary ?? null,
        incoming_salary: (row as any).incoming_salary ?? null,
        min_incoming: range?.min_incoming ?? null,
        max_incoming: (row as any).max_incoming ?? range?.max_incoming ?? null,
        tpe_type: (row as any).tpe_type ?? mode,
        is_trade_valid: blockingReasons.length === 0,
        reason_codes: reasonCodes,
        baseline_apron_total: (row as any).baseline_apron_total ?? null,
        post_trade_apron_total: (row as any).post_trade_apron_total ?? null,
        first_apron_amount: (row as any).first_apron_amount ?? null,
        is_padding_removed: (row as any).is_padding_removed ?? null,
        tpe_padding_amount: (row as any).tpe_padding_amount ?? null,
        tpe_dollar_allowance: (row as any).tpe_dollar_allowance ?? null,
        traded_rows_found: (row as any).traded_rows_found ?? null,
        replacement_rows_found: (row as any).replacement_rows_found ?? null,
      };
    })
  );

  return Response.json({
    salary_year: salaryYear,
    mode,
    league,
    teams: results,
  });
});

// GET /api/salary-book/two-way-capacity?team=:teamCode
// Fetch two-way player capacity data from pcms.team_two_way_capacity
salaryBookRouter.get("/two-way-capacity", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

  const capacity = await sql`
    SELECT
      team_id,
      team_code,
      current_contract_count,
      games_remaining,
      under_15_games_count,
      under_15_games_remaining
    FROM pcms.team_two_way_capacity
    WHERE team_code = ${teamCode}
    LIMIT 1
  `;

  if (capacity.length === 0) {
    return Response.json({ error: "Team not found" }, { status: 404 });
  }

  return Response.json(capacity[0]);
});
