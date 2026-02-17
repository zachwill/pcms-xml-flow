# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions"]
# ///
import os
import time
from datetime import date, datetime, timedelta, timezone

import httpx
import psycopg

BASE_URL = "https://api.nba.com/v0"
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"
QUERY_TOOL_TRUNCATION_THRESHOLD = 9900

SHOT_CHART_PER_MODE = "Totals"
SHOT_CHART_SUM_SCOPE = "Event"
SHOT_CHART_GROUPING = "None"
SHOT_CHART_TEAM_GROUPING = "Y"
SHOT_CHART_MAX_ROWS = 10000
SHOT_CHART_BATCH_SIZE = 50  # ~180 shots/game × 50 = ~9000, safely under 10k API limit
SHOT_CHART_SINGLE_BATCH_MAX_ATTEMPTS = 4
SHOT_CHART_UPSERT_CHUNK_SIZE = 0  # 0 disables chunking (single executemany)
SHOT_CHART_INCLUDE_BATCH_METRICS = True
SHOT_CHART_SPLITTABLE_HTTP_STATUSES = {414, 429, 500, 502, 503, 504}


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def elapsed_ms(started_perf: float) -> float:
    return round((time.perf_counter() - started_perf) * 1000, 2)


def chunked(values: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        size = 1
    return [values[i:i + size] for i in range(0, len(values), size)]


def split_batch(values: list[str]) -> tuple[list[str], list[str]]:
    midpoint = max(1, len(values) // 2)
    return values[:midpoint], values[midpoint:]


def chunk_rows(values: list[dict], size: int) -> list[list[dict]]:
    if size <= 0:
        return [values]
    return [values[i:i + size] for i in range(0, len(values), size)]


def parse_season_year(label: str | None) -> int | None:
    if not label:
        return None
    try:
        return int(label[:4])
    except (ValueError, TypeError):
        return None


def parse_date(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return datetime.strptime(value, "%Y-%m-%d").date()
        except ValueError:
            return None


def parse_int(value):
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        try:
            return int(float(value))
        except (ValueError, TypeError):
            return None


def parse_float(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def normalize_season_type(value: str | None) -> str:
    if not value:
        return ""

    normalized = " ".join(str(value).strip().lower().replace("-", " ").split())
    aliases = {
        "regular": "regular season",
        "regular season": "regular season",
        "pre season": "pre season",
        "preseason": "pre season",
        "playoff": "playoffs",
        "playoffs": "playoffs",
        "play in": "playin",
        "playin": "playin",
        "all star": "all star",
    }
    return aliases.get(normalized, normalized)


def resolve_season_date_range(season_label: str | None) -> tuple[date, date]:
    if not season_label:
        raise ValueError("season_backfill mode requires season_label")

    text = str(season_label).strip()
    try:
        start_year = int(text[:4])
    except (TypeError, ValueError):
        raise ValueError("season_label must look like YYYY-YY (e.g. 2024-25)")

    end_year = start_year + 1
    if "-" in text:
        suffix = text.split("-", 1)[1].strip()
        if suffix:
            if len(suffix) == 2 and suffix.isdigit():
                century = start_year // 100
                end_year = century * 100 + int(suffix)
                if end_year < start_year:
                    end_year += 100
            else:
                try:
                    end_year = int(suffix)
                except ValueError:
                    end_year = start_year + 1

    start = date(start_year, 9, 1)
    end = date(end_year, 7, 31)
    today = now_utc().date()
    if end > today:
        end = today
    return start, end


def resolve_date_range(
    mode: str,
    days_back: int | None,
    start_date: str | None,
    end_date: str | None,
    season_label: str | None,
) -> tuple[date, date]:
    if start_date or end_date:
        if not (start_date and end_date):
            raise ValueError("start_date and end_date must both be provided")
        start = parse_date(start_date)
        end = parse_date(end_date)
        if not start or not end:
            raise ValueError("start_date/end_date must be YYYY-MM-DD")
        return start, end

    normalized_mode = (mode or "refresh").strip().lower()

    if normalized_mode == "refresh":
        today = now_utc().date()
        start = today - timedelta(days=days_back or 2)
        return start, today

    if normalized_mode in {"backfill", "date_backfill"}:
        raise ValueError("date_backfill mode requires start_date and end_date (or game_ids)")

    if normalized_mode == "season_backfill":
        return resolve_season_date_range(season_label)

    raise ValueError("mode must be one of: refresh, date_backfill, season_backfill")


def request_json(
    client: httpx.Client,
    path: str,
    params: dict | None = None,
    retries: int = 3,
    base_url: str = BASE_URL,
) -> dict:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{base_url}{path}"

    for attempt in range(retries):
        try:
            resp = client.get(url, params=params, headers=headers)
        except httpx.TimeoutException:
            if attempt == retries - 1:
                raise
            time.sleep(1 + attempt)
            continue

        retryable_400 = resp.status_code == 400 and "Database Error" in resp.text
        if resp.status_code in {429, 500, 502, 503, 504} or retryable_400:
            if attempt == retries - 1:
                resp.raise_for_status()
            time.sleep(1 + attempt)
            continue
        if resp.status_code == 404:
            return {}
        resp.raise_for_status()
        return resp.json()

    raise RuntimeError(f"Failed to fetch {url}")


def upsert(
    conn: psycopg.Connection,
    table: str,
    rows: list[dict],
    conflict_keys: list[str],
    update_exclude: list[str] | None = None,
) -> int:
    if not rows:
        return 0
    update_exclude = update_exclude or []

    cols: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for col in row.keys():
            if col not in seen:
                seen.add(col)
                cols.append(col)

    update_cols = [c for c in cols if c not in conflict_keys and c not in update_exclude]

    placeholders = ", ".join(["%s"] * len(cols))
    col_list = ", ".join(cols)
    conflict = ", ".join(conflict_keys)

    if update_cols:
        updates = ", ".join([f"{c} = EXCLUDED.{c}" for c in update_cols])
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO UPDATE SET {updates}"
    else:
        sql = f"INSERT INTO {table} ({col_list}) VALUES ({placeholders}) ON CONFLICT ({conflict}) DO NOTHING"

    with conn.cursor() as cur:
        cur.executemany(sql, [tuple(r.get(c) for c in cols) for r in rows])
    conn.commit()
    return len(rows)


def derive_shot_type(stats: dict) -> str | None:
    """Derive a human-readable shot type from the FieldGoals stats flags."""
    if parse_float(stats.get("FG_ALLEY_OOP")) == 1.0:
        return "alley_oop"
    if parse_float(stats.get("FG_FINGER_ROLL")) == 1.0:
        return "finger_roll"
    if parse_float(stats.get("FG_DUNK")) == 1.0:
        return "dunk"
    if parse_float(stats.get("FG_TIP")) == 1.0:
        return "tip"
    if parse_float(stats.get("FG_HOOK")) == 1.0:
        return "hook"
    if parse_float(stats.get("FG_LAYUP")) == 1.0:
        return "layup"
    if parse_float(stats.get("FG_JUMPER")) == 1.0:
        return "jumper"
    return None


TRACKING_SHOT_FLAG_MAP = {
    "SHOT_AFTER_SCREENS": "tracking_shot_after_screens",
    "SHOT_CATCH_AND_SHOOT": "tracking_shot_catch_and_shoot",
    "SHOT_LOB": "tracking_shot_lob",
    "SHOT_LONG_HEAVE": "tracking_shot_long_heave",
    "SHOT_PULL_UP": "tracking_shot_pull_up",
    "SHOT_TIP_IN": "tracking_shot_tip_in",
    "SHOT_TRAILING_THREE": "tracking_shot_trailing_three",
    "SHOT_TRANSITION": "tracking_shot_transition",
}


def map_tracking_shot_flags(stats: dict) -> dict:
    """Map TrackingShots (0/1) flags to nba.shot_chart boolean columns."""
    out: dict = {}
    for key, column in TRACKING_SHOT_FLAG_MAP.items():
        value = parse_float(stats.get(key))
        if value is None:
            out[column] = None
        else:
            out[column] = value == 1.0
    return out


def fetch_event_player_payload(
    client: httpx.Client,
    base_params: dict,
    event_type: str,
) -> dict:
    params = dict(base_params)
    params["EventType"] = event_type

    started_perf = time.perf_counter()
    payload = request_json(
        client,
        "/event/player",
        params,
        retries=1,
        base_url=QUERY_TOOL_URL,
    )
    players = payload.get("players") or []
    rows_returned = parse_int((payload.get("meta") or {}).get("rowsReturned"))

    return {
        "payload": payload,
        "players": players,
        "rows_returned": rows_returned,
        "duration_ms": elapsed_ms(started_perf),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def main(
    dry_run: bool = False,
    league_id: str = "00",
    season_label: str | None = None,
    season_type: str = "Regular Season",
    mode: str = "refresh",
    days_back: int | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    game_ids: str | None = None,
    only_final_games: bool = True,
) -> dict:
    started_at = now_utc()
    started_perf = time.perf_counter()

    shot_chart_batch_size = SHOT_CHART_BATCH_SIZE
    single_batch_max_attempts = SHOT_CHART_SINGLE_BATCH_MAX_ATTEMPTS
    upsert_chunk_size = SHOT_CHART_UPSERT_CHUNK_SIZE
    include_batch_metrics = SHOT_CHART_INCLUDE_BATCH_METRICS

    telemetry = {
        "config": {
            "batch_size": shot_chart_batch_size,
            "max_rows_returned": SHOT_CHART_MAX_ROWS,
            "truncation_threshold": QUERY_TOOL_TRUNCATION_THRESHOLD,
            "single_batch_max_attempts": single_batch_max_attempts,
            "upsert_chunk_size": upsert_chunk_size,
            "include_batch_metrics": include_batch_metrics,
        },
        "game_selection": {
            "source": "",
            "candidate_games": 0,
            "season_type_filtered_games": 0,
            "selected_games": 0,
            "duration_ms": 0.0,
        },
        "fetch": {
            "initial_batch_count": 0,
            "batch_attempt_count": 0,
            "completed_batch_count": 0,
            "split_batch_count": 0,
            "single_batch_retry_count": 0,
            "field_goals_calls": 0,
            "tracking_calls": 0,
            "field_goals_rows_seen": 0,
            "tracking_rows_seen": 0,
            "rows_emitted": 0,
            "truncation_warning_count": 0,
            "duration_ms": 0.0,
            "batch_metrics": [],
        },
        "upsert": {
            "attempted_rows": 0,
            "chunks": 0,
            "duration_ms": 0.0,
            "executed": False,
        },
        "duration_ms": 0.0,
    }

    conn: psycopg.Connection | None = None
    try:
        season_label_value = season_label
        desired_season_type = normalize_season_type(season_type)

        conn = psycopg.connect(os.environ["POSTGRES_URL"])
        game_list: list[str] = []
        shot_chart_rows: list[dict] = []
        section_errors: list[str] = []

        # --- Resolve game list ---
        game_resolution_started = time.perf_counter()
        if game_ids:
            game_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
            telemetry["game_selection"].update(
                {
                    "source": "game_ids",
                    "candidate_games": len(game_list),
                    "season_type_filtered_games": len(game_list),
                    "selected_games": len(game_list),
                }
            )
        else:
            start_dt, end_dt = resolve_date_range(mode, days_back, start_date, end_date, season_label)
            season_label_filter = season_label_value or None
            query = """
                SELECT game_id, game_status, season_type
                FROM nba.games
                WHERE game_date BETWEEN %s AND %s
                  AND league_id = %s
                  AND (%s::text IS NULL OR season_label = %s)
                ORDER BY game_date, game_id
            """
            with conn.cursor() as cur:
                cur.execute(query, (start_dt, end_dt, league_id, season_label_filter, season_label_filter))
                game_status_rows = cur.fetchall()

            game_candidates = len(game_status_rows)

            if desired_season_type:
                game_status_rows = [
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_status_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_after_season_type = len(game_status_rows)

            if only_final_games:
                game_list = [gid for gid, status, _ in game_status_rows if status == 3]
            else:
                game_list = [gid for gid, _, _ in game_status_rows]

            telemetry["game_selection"].update(
                {
                    "source": "nba.games",
                    "candidate_games": game_candidates,
                    "season_type_filtered_games": game_after_season_type,
                    "selected_games": len(game_list),
                    "date_range": {
                        "start": start_dt.isoformat(),
                        "end": end_dt.isoformat(),
                    },
                    "only_final_games": bool(only_final_games),
                }
            )

        telemetry["game_selection"]["duration_ms"] = elapsed_ms(game_resolution_started)

        # --- Fetch + parse batched shot chart ---
        fetch_started = time.perf_counter()
        if season_label_value and game_list:
            pending_batches = chunked(game_list, shot_chart_batch_size)
            telemetry["fetch"]["initial_batch_count"] = len(pending_batches)
            single_batch_attempts: dict[str, int] = {}

            with httpx.Client(timeout=60) as client:
                while pending_batches:
                    batch = pending_batches.pop(0)
                    if not batch:
                        continue

                    telemetry["fetch"]["batch_attempt_count"] += 1
                    batch_metric = {
                        "batch_attempt": telemetry["fetch"]["batch_attempt_count"],
                        "batch_game_count": len(batch),
                        "first_game_id": batch[0],
                        "last_game_id": batch[-1],
                        "action": "",
                        "warnings": [],
                    }

                    batch_params = {
                        "LeagueId": league_id,
                        "SeasonYear": season_label_value,
                        "SeasonType": season_type,
                        "PerMode": SHOT_CHART_PER_MODE,
                        "SumScope": SHOT_CHART_SUM_SCOPE,
                        "Grouping": SHOT_CHART_GROUPING,
                        "TeamGrouping": SHOT_CHART_TEAM_GROUPING,
                        "GameId": ",".join(batch),
                        "MaxRowsReturned": SHOT_CHART_MAX_ROWS,
                    }

                    batch_key = ",".join(batch)
                    try:
                        batch_fetch_started = time.perf_counter()
                        field_goals_result = fetch_event_player_payload(client, batch_params, "FieldGoals")
                        tracking_result = fetch_event_player_payload(client, batch_params, "TrackingShots")
                        batch_metric["fetch_total_ms"] = elapsed_ms(batch_fetch_started)
                    except httpx.HTTPStatusError as exc:
                        status_code = exc.response.status_code if exc.response is not None else None
                        if status_code in SHOT_CHART_SPLITTABLE_HTTP_STATUSES and len(batch) > 1:
                            left, right = split_batch(batch)
                            pending_batches = [left, right, *pending_batches]
                            telemetry["fetch"]["split_batch_count"] += 1
                            batch_metric["action"] = f"split_http_{status_code}"
                        elif status_code in SHOT_CHART_SPLITTABLE_HTTP_STATUSES:
                            attempts = single_batch_attempts.get(batch_key, 0) + 1
                            single_batch_attempts[batch_key] = attempts
                            if attempts < single_batch_max_attempts:
                                time.sleep(min(5, attempts))
                                pending_batches.append(batch)
                                telemetry["fetch"]["single_batch_retry_count"] += 1
                                batch_metric["action"] = f"retry_http_{status_code}"
                                batch_metric["retry_attempt"] = attempts
                            else:
                                section_errors.append(
                                    f"shot_chart batch ({batch[0]}...{batch[-1]}) failed with HTTP {status_code} "
                                    f"after {attempts} attempts; skipping"
                                )
                                batch_metric["action"] = f"skip_http_{status_code}"
                                batch_metric["retry_attempt"] = attempts
                        else:
                            section_errors.append(
                                f"shot_chart batch ({batch[0]}...{batch[-1]}) failed: {exc}"
                            )
                            batch_metric["action"] = "skip_http_error"
                            batch_metric["error"] = str(exc)

                        if include_batch_metrics:
                            telemetry["fetch"]["batch_metrics"].append(batch_metric)
                        continue
                    except httpx.HTTPError as exc:
                        if len(batch) > 1:
                            left, right = split_batch(batch)
                            pending_batches = [left, right, *pending_batches]
                            telemetry["fetch"]["split_batch_count"] += 1
                            batch_metric["action"] = "split_transport_error"
                            batch_metric["error"] = str(exc)
                        else:
                            attempts = single_batch_attempts.get(batch_key, 0) + 1
                            single_batch_attempts[batch_key] = attempts
                            if attempts < single_batch_max_attempts:
                                time.sleep(min(5, attempts))
                                pending_batches.append(batch)
                                telemetry["fetch"]["single_batch_retry_count"] += 1
                                batch_metric["action"] = "retry_transport_error"
                                batch_metric["retry_attempt"] = attempts
                                batch_metric["error"] = str(exc)
                            else:
                                section_errors.append(
                                    f"shot_chart batch ({batch[0]}...{batch[-1]}) transport error "
                                    f"after {attempts} attempts; skipping: {exc}"
                                )
                                batch_metric["action"] = "skip_transport_error"
                                batch_metric["retry_attempt"] = attempts
                                batch_metric["error"] = str(exc)

                        if include_batch_metrics:
                            telemetry["fetch"]["batch_metrics"].append(batch_metric)
                        continue
                    except Exception as exc:
                        section_errors.append(f"shot_chart batch ({batch[0]}...{batch[-1]}): {exc}")
                        batch_metric["action"] = "skip_error"
                        batch_metric["error"] = str(exc)
                        if include_batch_metrics:
                            telemetry["fetch"]["batch_metrics"].append(batch_metric)
                        continue

                    telemetry["fetch"]["field_goals_calls"] += 1
                    telemetry["fetch"]["tracking_calls"] += 1

                    field_goals_rows = field_goals_result["players"]
                    tracking_rows = tracking_result["players"]
                    field_goals_rows_returned = field_goals_result["rows_returned"]
                    tracking_rows_returned = tracking_result["rows_returned"]

                    telemetry["fetch"]["field_goals_rows_seen"] += len(field_goals_rows)
                    telemetry["fetch"]["tracking_rows_seen"] += len(tracking_rows)

                    batch_metric["field_goals"] = {
                        "rows": len(field_goals_rows),
                        "rows_returned": field_goals_rows_returned,
                        "duration_ms": field_goals_result["duration_ms"],
                    }
                    batch_metric["tracking_shots"] = {
                        "rows": len(tracking_rows),
                        "rows_returned": tracking_rows_returned,
                        "duration_ms": tracking_result["duration_ms"],
                    }

                    suspicious_field_goals = (
                        (field_goals_rows_returned is not None and field_goals_rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                        or len(field_goals_rows) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                    )
                    suspicious_tracking = (
                        (tracking_rows_returned is not None and tracking_rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                        or len(tracking_rows) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                    )

                    if (suspicious_field_goals or suspicious_tracking) and len(batch) > 1:
                        left, right = split_batch(batch)
                        pending_batches = [left, right, *pending_batches]
                        telemetry["fetch"]["split_batch_count"] += 1
                        batch_metric["action"] = "split_truncation_suspected"
                        if suspicious_field_goals:
                            warning = (
                                f"FieldGoals rows near cap for batch {batch[0]}...{batch[-1]} "
                                f"(rows={len(field_goals_rows)}, rowsReturned={field_goals_rows_returned})"
                            )
                            batch_metric["warnings"].append(warning)
                        if suspicious_tracking:
                            warning = (
                                f"TrackingShots rows near cap for batch {batch[0]}...{batch[-1]} "
                                f"(rows={len(tracking_rows)}, rowsReturned={tracking_rows_returned})"
                            )
                            batch_metric["warnings"].append(warning)
                        telemetry["fetch"]["truncation_warning_count"] += len(batch_metric["warnings"])

                        if include_batch_metrics:
                            telemetry["fetch"]["batch_metrics"].append(batch_metric)
                        continue

                    if suspicious_field_goals:
                        warning = (
                            f"shot_chart batch {batch[0]}...{batch[-1]} may be truncated "
                            f"(FieldGoals rows={len(field_goals_rows)}, rowsReturned={field_goals_rows_returned})"
                        )
                        section_errors.append(warning)
                        batch_metric["warnings"].append(warning)
                        telemetry["fetch"]["truncation_warning_count"] += 1

                    if suspicious_tracking:
                        warning = (
                            f"shot_chart batch {batch[0]}...{batch[-1]} may be truncated "
                            f"(TrackingShots rows={len(tracking_rows)}, rowsReturned={tracking_rows_returned})"
                        )
                        section_errors.append(warning)
                        batch_metric["warnings"].append(warning)
                        telemetry["fetch"]["truncation_warning_count"] += 1

                    parse_started = time.perf_counter()
                    shot_fetched_at = now_utc()
                    tracking_flags_by_key: dict[tuple[str, int], dict] = {}
                    for tracking_row in tracking_rows:
                        tracking_event_num = parse_int(tracking_row.get("eventNumber"))
                        if tracking_event_num is None:
                            continue
                        game_id_tracking = tracking_row.get("gameId")
                        if not game_id_tracking:
                            continue
                        tracking_flags_by_key[(game_id_tracking, tracking_event_num)] = map_tracking_shot_flags(
                            tracking_row.get("stats") or {}
                        )

                    batch_rows: list[dict] = []
                    for player in field_goals_rows:
                        stats = player.get("stats") or {}
                        event_num = parse_int(player.get("eventNumber"))
                        if event_num is None:
                            continue

                        season_label_shot = player.get("seasonYear") or season_label_value
                        team_id_shot = parse_int(player.get("teamId"))
                        if team_id_shot == 0:
                            team_id_shot = None

                        assisted_id = parse_int(stats.get("AST_BY_PLAYER_ID"))
                        if assisted_id == 0:
                            assisted_id = None

                        assisted_name = stats.get("AST_BY_PLAYER_NAME")
                        if assisted_name in (None, "", "0"):
                            assisted_name = None

                        batch_rows.append(
                            {
                                "game_id": player.get("gameId"),
                                "event_number": event_num,
                                "nba_id": parse_int(player.get("playerId")),
                                "team_id": team_id_shot,
                                "period": parse_int(player.get("period")),
                                "game_clock": parse_float(player.get("gameClock")),
                                "x": parse_int(player.get("x")),
                                "y": parse_int(player.get("y")),
                                "shot_made": parse_float(stats.get("FGM")) == 1.0,
                                "is_three": parse_float(stats.get("FG3")) == 1.0,
                                "shot_type": derive_shot_type(stats),
                                "shot_zone_area": stats.get("SHOT_ZONE_AREA"),
                                "shot_zone_range": stats.get("SHOT_ZONE_RANGE"),
                                "assisted_by_id": assisted_id,
                                "assisted_by_name": assisted_name,
                                "player_name": player.get("name"),
                                "position": player.get("position"),
                                "opponent_name": player.get("opponentName"),
                                "game_date": parse_date(player.get("gameDate")),
                                "season_year": parse_season_year(season_label_shot),
                                "season_label": season_label_shot,
                                "season_type": player.get("seasonType") or season_type,
                                "created_at": shot_fetched_at,
                                "updated_at": shot_fetched_at,
                                "fetched_at": shot_fetched_at,
                                **(tracking_flags_by_key.get((player.get("gameId"), event_num)) or {}),
                            }
                        )

                    shot_chart_rows.extend(batch_rows)
                    telemetry["fetch"]["rows_emitted"] += len(batch_rows)
                    telemetry["fetch"]["completed_batch_count"] += 1

                    batch_metric["parse_merge_ms"] = elapsed_ms(parse_started)
                    batch_metric["rows_emitted"] = len(batch_rows)
                    batch_metric["action"] = "processed"

                    if include_batch_metrics:
                        telemetry["fetch"]["batch_metrics"].append(batch_metric)
        elif game_list and not season_label_value:
            section_errors.append("shot_chart: season_label is required when game_ids are provided")

        telemetry["fetch"]["duration_ms"] = elapsed_ms(fetch_started)

        inserted_shot_chart = 0
        telemetry["upsert"]["attempted_rows"] = len(shot_chart_rows)

        upsert_started = time.perf_counter()
        if not dry_run and shot_chart_rows:
            chunks = chunk_rows(shot_chart_rows, upsert_chunk_size)
            telemetry["upsert"]["chunks"] = len(chunks)
            telemetry["upsert"]["executed"] = True
            for chunk in chunks:
                inserted_shot_chart += upsert(
                    conn,
                    "nba.shot_chart",
                    chunk,
                    ["game_id", "event_number"],
                    update_exclude=["created_at"],
                )
        telemetry["upsert"]["duration_ms"] = elapsed_ms(upsert_started)

        if conn:
            conn.close()

        telemetry["duration_ms"] = elapsed_ms(started_perf)

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [
                {
                    "table": "nba.shot_chart",
                    "rows": len(shot_chart_rows),
                    "upserted": inserted_shot_chart,
                },
            ],
            "telemetry": telemetry,
            "errors": section_errors,
        }
    except Exception as exc:
        if conn:
            conn.close()

        telemetry["duration_ms"] = elapsed_ms(started_perf)

        return {
            "dry_run": dry_run,
            "started_at": started_at.isoformat(),
            "finished_at": now_utc().isoformat(),
            "tables": [],
            "telemetry": telemetry,
            "errors": [str(exc)],
        }


if __name__ == "__main__":
    main()
