# /// script
# requires-python = ">=3.11"
# dependencies = ["psycopg[binary]", "httpx", "sniffio", "typing-extensions", "tenacity"]
# ///
import os
import time
from datetime import date, datetime, timedelta, timezone

import httpx
import psycopg
from psycopg.types.json import Json
from tenacity import RetryCallState, retry, retry_if_exception, stop_after_attempt, wait_exponential

BASE_URL = "https://api.nba.com/v0"
QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"
QUERY_TOOL_TRUNCATION_THRESHOLD = 9900

QUERYTOOL_EVENT_STREAM_MAX_ROWS_RETURNED = 10000
QUERYTOOL_EVENT_STREAM_BATCH_SIZES = {
    "TrackingPasses": 16,
    "DefensiveEvents": 30,
    "TrackingDrives": 50,
    "TrackingIsolations": 200,
    "TrackingPostUps": 200,
}
QUERYTOOL_EVENT_STREAM_TYPES = list(QUERYTOOL_EVENT_STREAM_BATCH_SIZES.keys())

QUERYTOOL_EVENT_STREAM_PER_MODE = "Totals"
QUERYTOOL_EVENT_STREAM_SUM_SCOPE = "Event"
QUERYTOOL_EVENT_STREAM_GROUPING = "None"
QUERYTOOL_EVENT_STREAM_TEAM_GROUPING = "Y"
QUERYTOOL_EVENT_STREAM_SINGLE_BATCH_MAX_ATTEMPTS = 4
QUERYTOOL_EVENT_STREAMS_SKIP_EXISTING_ON_SEASON_BACKFILL = True

HTTP_RETRYABLE_STATUSES = {403, 429, 500, 502, 503, 504}
HTTP_RETRY_MAX_ATTEMPTS = 4
HTTP_RETRY_MIN_WAIT_SECONDS = 1
HTTP_RETRY_MAX_WAIT_SECONDS = 8


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def elapsed_ms(started_perf: float) -> float:
    return round((time.perf_counter() - started_perf) * 1000, 2)


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


def _is_retryable_response(response: httpx.Response) -> bool:
    retryable_400 = response.status_code == 400 and "Database Error" in response.text
    return response.status_code in HTTP_RETRYABLE_STATUSES or retryable_400


def _is_retryable_http_exception(exc: Exception) -> bool:
    if isinstance(exc, httpx.TimeoutException):
        return True

    if isinstance(exc, httpx.HTTPStatusError):
        response = exc.response
        if response is None:
            return False
        return _is_retryable_response(response)

    if isinstance(exc, httpx.TransportError):
        return True

    return False


def _before_sleep_http_retry(retry_state: RetryCallState) -> None:
    outcome = retry_state.outcome
    if outcome is None or not outcome.failed:
        return

    exc = outcome.exception()
    if isinstance(exc, httpx.HTTPStatusError) and exc.response is not None:
        if exc.response.status_code == 403:
            extra_sleep = min(20, 5 * retry_state.attempt_number)
            time.sleep(extra_sleep)


@retry(
    reraise=True,
    retry=retry_if_exception(_is_retryable_http_exception),
    stop=stop_after_attempt(HTTP_RETRY_MAX_ATTEMPTS),
    wait=wait_exponential(
        multiplier=HTTP_RETRY_MIN_WAIT_SECONDS,
        min=HTTP_RETRY_MIN_WAIT_SECONDS,
        max=HTTP_RETRY_MAX_WAIT_SECONDS,
    ),
    before_sleep=_before_sleep_http_retry,
)
def _http_get_with_retry(
    client: httpx.Client,
    url: str,
    params: dict | None,
    headers: dict,
) -> httpx.Response:
    response = client.get(url, params=params, headers=headers)
    if _is_retryable_response(response):
        response.raise_for_status()
    return response


def request_json(
    client: httpx.Client,
    path: str,
    params: dict | None = None,
    retries: int = 3,
    base_url: str = BASE_URL,
) -> dict:
    headers = {"X-NBA-Api-Key": os.environ["NBA_API_KEY"]}
    url = f"{base_url}{path}"

    if retries <= 1:
        response = client.get(url, params=params, headers=headers)
        if _is_retryable_response(response):
            response.raise_for_status()
    else:
        response = _http_get_with_retry(client, url, params, headers)

    if response.status_code == 404:
        return {}

    response.raise_for_status()
    return response.json()


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


def fetch_existing_event_stream_game_ids(
    conn: psycopg.Connection,
    game_ids: list[str],
    event_type: str,
) -> set[str]:
    if not game_ids:
        return set()

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT DISTINCT game_id
            FROM nba.querytool_event_streams
            WHERE game_id = ANY(%s::text[])
              AND event_type = %s
            """,
            (game_ids, event_type),
        )
        return {row[0] for row in cur.fetchall() if row and row[0]}


def chunked(values: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        size = 1
    return [values[i:i + size] for i in range(0, len(values), size)]


def split_batch(values: list[str]) -> tuple[list[str], list[str]]:
    midpoint = max(1, len(values) // 2)
    return values[:midpoint], values[midpoint:]


def reduce_querytool_event_row(payload_row: dict) -> dict:
    stats = payload_row.get("stats") or {}
    team_id = parse_int(payload_row.get("teamId"))
    if team_id == 0:
        team_id = None

    return {
        "event_number": parse_int(payload_row.get("eventNumber")),
        "nba_id": parse_int(payload_row.get("playerId")),
        "team_id": team_id,
        "period": parse_int(payload_row.get("period")),
        "game_clock": parse_float(payload_row.get("gameClock")),
        "x": parse_int(payload_row.get("x")),
        "y": parse_int(payload_row.get("y")),
        "stats": stats,
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

    telemetry = {
        "config": {
            "event_types": QUERYTOOL_EVENT_STREAM_TYPES,
            "batch_sizes": QUERYTOOL_EVENT_STREAM_BATCH_SIZES,
            "max_rows_returned": QUERYTOOL_EVENT_STREAM_MAX_ROWS_RETURNED,
            "truncation_threshold": QUERY_TOOL_TRUNCATION_THRESHOLD,
            "skip_existing_on_season_backfill": QUERYTOOL_EVENT_STREAMS_SKIP_EXISTING_ON_SEASON_BACKFILL,
        },
        "game_selection": {
            "source": "",
            "candidate_games": 0,
            "season_type_filtered_games": 0,
            "selected_games": 0,
            "final_games": 0,
            "duration_ms": 0.0,
        },
        "event_types": {},
        "fetch": {
            "coverage": {},
            "total_batch_attempt_count": 0,
            "total_split_batch_count": 0,
            "total_truncation_warning_count": 0,
            "duration_ms": 0.0,
        },
        "upsert": {
            "executed": False,
            "duration_ms": 0.0,
        },
        "duration_ms": 0.0,
    }

    conn: psycopg.Connection | None = None
    try:
        conn = psycopg.connect(os.environ["POSTGRES_URL"])

        errors: list[str] = []
        stream_rows: list[dict] = []

        season_label_value = season_label
        normalized_mode = (mode or "refresh").strip().lower()
        desired_season_type = normalize_season_type(season_type)

        game_list: list[tuple[str, int | None]] = []
        game_id_list: list[str] = []

        selection_started = time.perf_counter()
        if game_ids:
            game_id_list = [gid.strip() for gid in game_ids.split(",") if gid.strip()]
            if game_id_list:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT game_id, game_status FROM nba.games WHERE game_id = ANY(%s)",
                        (game_id_list,),
                    )
                    status_map = {row[0]: row[1] for row in cur.fetchall()}
                game_list = [(gid, status_map.get(gid)) for gid in game_id_list]

            telemetry["game_selection"].update(
                {
                    "source": "game_ids",
                    "candidate_games": len(game_id_list),
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
                game_rows = cur.fetchall()

            candidate_games = len(game_rows)
            if desired_season_type:
                game_rows = [
                    (gid, status, game_season_type)
                    for gid, status, game_season_type in game_rows
                    if normalize_season_type(game_season_type) == desired_season_type
                ]

            game_list = [(gid, status) for gid, status, _ in game_rows]
            telemetry["game_selection"].update(
                {
                    "source": "nba.games",
                    "candidate_games": candidate_games,
                    "season_type_filtered_games": len(game_rows),
                    "selected_games": len(game_list),
                    "date_range": {
                        "start": start_dt.isoformat(),
                        "end": end_dt.isoformat(),
                    },
                    "only_final_games": bool(only_final_games),
                }
            )

        allow_unknown_final = bool(game_id_list)
        if only_final_games:
            if allow_unknown_final:
                game_list = [(gid, status) for gid, status in game_list if status in (None, 3)]
            else:
                game_list = [(gid, status) for gid, status in game_list if status == 3]

        final_game_ids = [
            gid
            for gid, status in game_list
            if status == 3 or (allow_unknown_final and status is None)
        ]
        telemetry["game_selection"]["selected_games"] = len(game_list)
        telemetry["game_selection"]["final_games"] = len(final_game_ids)
        telemetry["game_selection"]["duration_ms"] = elapsed_ms(selection_started)

        if final_game_ids and not season_label_value:
            errors.append("querytool_event_streams: season_label is required when game_ids are provided")

        enable_skip_existing = (
            QUERYTOOL_EVENT_STREAMS_SKIP_EXISTING_ON_SEASON_BACKFILL
            and normalized_mode == "season_backfill"
            and not bool(game_id_list)
        )

        event_type_game_ids: dict[str, list[str]] = {
            event_type: list(final_game_ids)
            for event_type in QUERYTOOL_EVENT_STREAM_TYPES
        }

        if enable_skip_existing and final_game_ids:
            for event_type in QUERYTOOL_EVENT_STREAM_TYPES:
                existing_game_ids = fetch_existing_event_stream_game_ids(conn, final_game_ids, event_type)
                event_type_game_ids[event_type] = [
                    gid for gid in final_game_ids if gid not in existing_game_ids
                ]

        telemetry["fetch"]["coverage"] = {
            "skip_existing_enabled": enable_skip_existing,
            "selected_final_games": len(final_game_ids),
            "to_fetch_games_by_event_type": {
                event_type: len(event_type_game_ids.get(event_type) or [])
                for event_type in QUERYTOOL_EVENT_STREAM_TYPES
            },
        }

        fetch_started = time.perf_counter()
        if final_game_ids and season_label_value:
            with httpx.Client(timeout=60) as client:
                for event_type in QUERYTOOL_EVENT_STREAM_TYPES:
                    event_started = time.perf_counter()
                    batch_size = QUERYTOOL_EVENT_STREAM_BATCH_SIZES.get(event_type, 25)
                    target_game_ids = event_type_game_ids.get(event_type) or []

                    metrics = {
                        "batch_size": batch_size,
                        "initial_batch_count": 0,
                        "batch_attempt_count": 0,
                        "completed_batch_count": 0,
                        "split_batch_count": 0,
                        "single_batch_retry_count": 0,
                        "rows_seen": 0,
                        "rows_emitted": 0,
                        "truncation_warning_count": 0,
                        "duration_ms": 0.0,
                    }

                    if not target_game_ids:
                        metrics["skipped"] = True
                        metrics["reason"] = "coverage_complete"
                        metrics["game_id_count"] = 0
                        metrics["duration_ms"] = elapsed_ms(event_started)
                        telemetry["event_types"][event_type] = metrics
                        continue

                    pending_batches = chunked(target_game_ids, batch_size)
                    single_batch_attempts: dict[str, int] = {}
                    metrics["initial_batch_count"] = len(pending_batches)

                    while pending_batches:
                        batch = pending_batches.pop(0)
                        if not batch:
                            continue

                        metrics["batch_attempt_count"] += 1
                        params = {
                            "LeagueId": league_id,
                            "SeasonYear": season_label_value,
                            "SeasonType": season_type,
                            "PerMode": QUERYTOOL_EVENT_STREAM_PER_MODE,
                            "SumScope": QUERYTOOL_EVENT_STREAM_SUM_SCOPE,
                            "Grouping": QUERYTOOL_EVENT_STREAM_GROUPING,
                            "TeamGrouping": QUERYTOOL_EVENT_STREAM_TEAM_GROUPING,
                            "EventType": event_type,
                            "GameId": ",".join(batch),
                            "MaxRowsReturned": QUERYTOOL_EVENT_STREAM_MAX_ROWS_RETURNED,
                        }

                        batch_key = ",".join(batch)
                        try:
                            payload = request_json(
                                client,
                                "/event/player",
                                params,
                                retries=1,
                                base_url=QUERY_TOOL_URL,
                            )
                        except httpx.HTTPStatusError as exc:
                            status = exc.response.status_code if exc.response is not None else None
                            if status in {414, 429, 500, 502, 503, 504} and len(batch) > 1:
                                left, right = split_batch(batch)
                                pending_batches = [left, right, *pending_batches]
                                metrics["split_batch_count"] += 1
                                continue

                            if status in {414, 429, 500, 502, 503, 504}:
                                attempts = single_batch_attempts.get(batch_key, 0) + 1
                                single_batch_attempts[batch_key] = attempts
                                if attempts < QUERYTOOL_EVENT_STREAM_SINGLE_BATCH_MAX_ATTEMPTS:
                                    time.sleep(min(5, attempts))
                                    pending_batches.append(batch)
                                    metrics["single_batch_retry_count"] += 1
                                    continue

                                errors.append(
                                    f"querytool_event_streams {event_type}: batch ({batch[0]}...{batch[-1]}) "
                                    f"failed with HTTP {status} after {attempts} attempts; skipping"
                                )
                                continue

                            raise
                        except httpx.HTTPError as exc:
                            if len(batch) > 1:
                                left, right = split_batch(batch)
                                pending_batches = [left, right, *pending_batches]
                                metrics["split_batch_count"] += 1
                                continue

                            attempts = single_batch_attempts.get(batch_key, 0) + 1
                            single_batch_attempts[batch_key] = attempts
                            if attempts < QUERYTOOL_EVENT_STREAM_SINGLE_BATCH_MAX_ATTEMPTS:
                                time.sleep(min(5, attempts))
                                pending_batches.append(batch)
                                metrics["single_batch_retry_count"] += 1
                                continue

                            errors.append(
                                f"querytool_event_streams {event_type}: batch ({batch[0]}...{batch[-1]}) "
                                f"transport error after {attempts} attempts; skipping: {exc}"
                            )
                            continue

                        rows = payload.get("players") or []
                        rows_returned = parse_int((payload.get("meta") or {}).get("rowsReturned"))
                        metrics["rows_seen"] += len(rows)

                        suspicious = (
                            (rows_returned is not None and rows_returned >= QUERY_TOOL_TRUNCATION_THRESHOLD)
                            or len(rows) >= QUERY_TOOL_TRUNCATION_THRESHOLD
                        )

                        if suspicious and len(batch) > 1:
                            left, right = split_batch(batch)
                            pending_batches = [left, right, *pending_batches]
                            metrics["split_batch_count"] += 1
                            continue

                        if suspicious:
                            errors.append(
                                f"querytool_event_streams {event_type}: batch for game {batch[0]} may be truncated "
                                f"(rows={len(rows)}, rowsReturned={rows_returned})"
                            )
                            metrics["truncation_warning_count"] += 1

                        grouped: dict[str, list[dict]] = {gid: [] for gid in batch}
                        for payload_row in rows:
                            game_id_row = payload_row.get("gameId")
                            if not game_id_row or game_id_row not in grouped:
                                continue
                            grouped[game_id_row].append(reduce_querytool_event_row(payload_row))

                        fetched_at = now_utc()
                        for gid in batch:
                            stream_rows.append(
                                {
                                    "game_id": gid,
                                    "event_type": event_type,
                                    "events_json": Json(grouped.get(gid) or []),
                                    "created_at": fetched_at,
                                    "updated_at": fetched_at,
                                    "fetched_at": fetched_at,
                                }
                            )

                        metrics["rows_emitted"] += len(batch)
                        metrics["completed_batch_count"] += 1

                    metrics["duration_ms"] = elapsed_ms(event_started)
                    telemetry["event_types"][event_type] = metrics
                    telemetry["fetch"]["total_batch_attempt_count"] += metrics["batch_attempt_count"]
                    telemetry["fetch"]["total_split_batch_count"] += metrics["split_batch_count"]
                    telemetry["fetch"]["total_truncation_warning_count"] += metrics["truncation_warning_count"]

        telemetry["fetch"]["duration_ms"] = elapsed_ms(fetch_started)

        inserted_stream_rows = 0
        upsert_started = time.perf_counter()
        if not dry_run and stream_rows:
            telemetry["upsert"]["executed"] = True
            inserted_stream_rows = upsert(
                conn,
                "nba.querytool_event_streams",
                stream_rows,
                ["game_id", "event_type"],
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
                    "table": "nba.querytool_event_streams",
                    "rows": len(stream_rows),
                    "upserted": inserted_stream_rows,
                },
            ],
            "telemetry": telemetry,
            "errors": errors,
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
