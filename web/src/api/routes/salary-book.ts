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

// GET /api/salary-book/players?team=:teamCode
// Fetch player salaries from pcms.salary_book_warehouse
salaryBookRouter.get("/players", async (req) => {
  const url = new URL(req.url);
  const teamCode = url.searchParams.get("team");

  if (!teamCode) {
    return Response.json({ error: "team parameter required" }, { status: 400 });
  }

  const sql = getSql();

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

      COALESCE(s.is_trade_consent_required_now, false)::boolean as is_trade_consent_required_now,
      COALESCE(s.is_trade_preconsented, false)::boolean as is_trade_preconsented,
      s.player_consent_lk
    FROM pcms.salary_book_warehouse s
    LEFT JOIN pcms.people p ON s.player_id = p.person_id
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
      NULL::numeric as cap_2026,
      NULL::numeric as cap_2027,
      NULL::numeric as cap_2028,
      NULL::numeric as cap_2029
    FROM pcms.cap_holds_warehouse
    WHERE team_code = ${teamCode}
      AND salary_year = 2025
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
      asset_type,
      raw_fragment as description
    FROM pcms.draft_picks_warehouse
    WHERE team_code = ${teamCode}
      AND draft_year BETWEEN 2025 AND 2030
    ORDER BY draft_year, draft_round, asset_slot
  `;

  return Response.json(picks);
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
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code) as team_code,
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

  const players = await sql`
    SELECT
      s.player_id,
      COALESCE(
        NULLIF(TRIM(CONCAT_WS(' ', p.display_first_name, p.display_last_name)), ''),
        s.player_name
      ) as player_name,
      COALESCE(NULLIF(s.person_team_code, ''), s.team_code) as team_code,
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

      COALESCE(s.is_trade_consent_required_now, false)::boolean as is_trade_consent_required_now,
      COALESCE(s.is_trade_preconsented, false)::boolean as is_trade_preconsented,
      s.player_consent_lk
    FROM pcms.salary_book_warehouse s
    LEFT JOIN pcms.people p ON s.player_id = p.person_id
    LEFT JOIN pcms.agents a ON s.agent_id = a.agent_id
    WHERE s.player_id = ${playerId}
    LIMIT 1
  `;

  if (players.length === 0) {
    return Response.json({ error: "Player not found" }, { status: 404 });
  }

  return Response.json(players[0]);
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

  // Fetch the pick details
  const picks = await sql`
    SELECT
      team_code,
      draft_year as year,
      draft_round as round,
      asset_slot,
      asset_type,
      raw_fragment as description
    FROM pcms.draft_picks_warehouse
    WHERE team_code = ${teamCode}
      AND draft_year = ${year}
      AND draft_round = ${round}
    ORDER BY asset_slot
  `;

  if (picks.length === 0) {
    return Response.json({ error: "Pick not found" }, { status: 404 });
  }

  // Get team info for destination team
  const teams = await sql`
    SELECT team_code, team_name, team_nickname
    FROM pcms.teams
    WHERE team_code = ${teamCode}
      AND league_lk = 'NBA'
    LIMIT 1
  `;

  const destinationTeam = teams.length > 0 ? teams[0] : null;

  // Parse the raw_fragment for origin team info
  // The raw_fragment often contains the origin team code
  const pick = picks[0];
  const rawFragment = pick.description || "";

  // Try to extract origin team from description
  // Common patterns: "LAL 1st", "Own 1st", "From LAL"
  let originTeamCode = teamCode; // Default to same team
  const fromMatch = rawFragment.match(/(?:From|from)\s+([A-Z]{3})/);
  const prefixMatch = rawFragment.match(/^([A-Z]{3})\s+/);

  if (fromMatch) {
    originTeamCode = fromMatch[1];
  } else if (prefixMatch && prefixMatch[1] !== "Own") {
    originTeamCode = prefixMatch[1];
  }

  // Get origin team info if different
  let originTeam = null;
  if (originTeamCode !== teamCode) {
    const originTeams = await sql`
      SELECT team_code, team_name, team_nickname
      FROM pcms.teams
      WHERE team_code = ${originTeamCode}
        AND league_lk = 'NBA'
      LIMIT 1
    `;
    if (originTeams.length > 0) {
      originTeam = originTeams[0];
    }
  }

  // Parse protections from description
  // Common patterns: "Top 5 Protected", "Lottery Protected"
  let protections = null;
  const protectedMatch = rawFragment.match(/(Top\s+\d+|Lottery|Unprotected)[\s-]*(Protected)?/i);
  if (protectedMatch) {
    protections = protectedMatch[0];
  }

  // Determine if it's a swap
  const isSwap = rawFragment.toLowerCase().includes("swap");

  return Response.json({
    team_code: teamCode,
    year,
    round,
    asset_type: pick.asset_type,
    description: rawFragment,
    origin_team_code: originTeamCode,
    origin_team: originTeam,
    destination_team: destinationTeam,
    protections,
    is_swap: isSwap,
    // Collect all picks for this team/year/round (in case multiple)
    all_slots: picks.map((p: any) => ({
      asset_slot: p.asset_slot,
      asset_type: p.asset_type,
      description: p.description,
    })),
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
