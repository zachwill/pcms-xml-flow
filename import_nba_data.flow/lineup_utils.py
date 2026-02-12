import time
from typing import Callable

import httpx

QUERY_TOOL_URL = "https://api.nba.com/v0/api/querytool"

LINEUP_MEASURE_TYPES = ["Base", "Advanced"]
LINEUP_PER_MODES = ["Totals", "PerGame", "Per36Minutes", "Per100Possessions"]
LINEUP_GAME_PER_MODE = "Totals"
LINEUP_QUANTITY = 5
LINEUP_MAX_ROWS = 10000
LINEUP_GROUPING = "None"
LINEUP_GAME_BATCH_SIZE = {
    "Base": 150,
    "Advanced": 120,
}
# Keep an aggressive default for throughput; fetch helper can split batches on failures.
LINEUP_SEASON_TEAM_BATCH_SIZE = 10

LINEUP_STAT_COLUMNS = [
    "gp",
    "minutes",
    "off_rating",
    "def_rating",
    "net_rating",
    "ast_pct",
    "ast_tov",
    "ast_ratio",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pace",
    "pie",
]

LINEUP_STAT_PREFIXES = (
    "BASE_",
    "ADV_",
    "MISC_",
    "SCORING_",
    "OPP_",
    "TRACKING_",
    "DEF_",
    "DEFENSIVE_",
)

LINEUP_STAT_MAP = {
    "GP": "gp",
    "G": "gp",
    "GAMES_PLAYED": "gp",
    "MIN": "minutes",
    "MIN_PG": "minutes",
    "MINUTES": "minutes",
    "OFF_RATING": "off_rating",
    "OFFRTG": "off_rating",
    "DEF_RATING": "def_rating",
    "DEFRTG": "def_rating",
    "NET_RATING": "net_rating",
    "NETRTG": "net_rating",
    "AST_PCT": "ast_pct",
    "AST_TO": "ast_tov",
    "AST_TOV": "ast_tov",
    "AST_RATIO": "ast_ratio",
    "OREB_PCT": "oreb_pct",
    "DREB_PCT": "dreb_pct",
    "REB_PCT": "reb_pct",
    "TM_TOV_PCT": "tm_tov_pct",
    "TEAM_TOV_PCT": "tm_tov_pct",
    "EFG_PCT": "efg_pct",
    "TS_PCT": "ts_pct",
    "USG_PCT": "usg_pct",
    "PACE": "pace",
    "PIE": "pie",
}

LINEUP_RATE_COLUMNS = {
    "ast_pct",
    "oreb_pct",
    "dreb_pct",
    "reb_pct",
    "tm_tov_pct",
    "efg_pct",
    "ts_pct",
    "usg_pct",
    "pie",
}


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


def parse_minutes_interval(value: str | None):
    if value is None or value == "":
        return None
    if isinstance(value, str):
        if value.startswith("PT"):
            minutes = 0
            seconds = 0.0
            try:
                body = value.replace("PT", "")
                if "M" in body:
                    minutes_str, rest = body.split("M", 1)
                    minutes = int(minutes_str) if minutes_str else 0
                else:
                    rest = body
                if "S" in rest:
                    seconds = float(rest.replace("S", ""))
            except ValueError:
                return None
            return round((minutes * 60 + seconds) / 60.0, 2)
        if ":" in value:
            try:
                minutes_str, seconds_str = value.split(":", 1)
                return round((int(minutes_str) * 60 + float(seconds_str)) / 60.0, 2)
            except ValueError:
                return None
    try:
        minutes = float(value)
    except (ValueError, TypeError):
        return None
    return round(minutes, 2)


def normalize_lineup_stat_key(key: str) -> str:
    if not key:
        return ""

    normalized = key.upper()
    if normalized in LINEUP_STAT_MAP:
        return normalized

    for prefix in LINEUP_STAT_PREFIXES:
        if normalized.startswith(prefix):
            candidate = normalized[len(prefix):]
            if candidate in LINEUP_STAT_MAP:
                return candidate

    return normalized


def map_lineup_stats(stats: dict) -> dict:
    row: dict = {}
    for key, value in stats.items():
        normalized = normalize_lineup_stat_key(key)
        column = LINEUP_STAT_MAP.get(normalized)
        if not column:
            continue
        if column == "gp":
            parsed = parse_int(value)
        elif column == "minutes":
            parsed = parse_minutes_interval(value)
        else:
            parsed = parse_float(value)
        if parsed is None:
            continue
        if column == "pie":
            if abs(parsed) > 100:
                parsed = parsed / 10000
            elif abs(parsed) > 1:
                parsed = parsed / 100
        elif column in LINEUP_RATE_COLUMNS and abs(parsed) > 1:
            parsed = parsed / 100

        # Pace can blow up for 0-minute (or near-0) lineups; keep within
        # numeric(6,2) bounds to avoid INSERT failures.
        if column == "pace":
            parsed = round(parsed, 2)
            if abs(parsed) >= 10000:
                continue

        row[column] = parsed
    return row


def extract_lineup_player_ids(lineup: dict) -> list[int]:
    ids: list[int] = []
    for idx in range(1, 6):
        player_id = parse_int(lineup.get(f"player{idx}Id"))
        if player_id:
            ids.append(player_id)
    ids.sort()
    return ids


def chunked(values: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        size = 1
    return [values[i:i + size] for i in range(0, len(values), size)]


def split_batch(values: list[str]) -> tuple[list[str], list[str]]:
    midpoint = max(1, len(values) // 2)
    return values[:midpoint], values[midpoint:]


def fetch_querytool_batched_rows(
    client: httpx.Client,
    request_json: Callable,
    path: str,
    base_params: dict,
    ids: list[str],
    row_key: str,
    batch_size: int,
    max_rows_returned: int,
    truncation_threshold: int,
    batch_param: str = "GameId",
    single_batch_max_attempts: int = 4,
) -> tuple[list[dict], list[str]]:
    pending_batches = chunked(ids, batch_size)
    single_batch_attempts: dict[str, int] = {}
    all_rows: list[dict] = []
    warnings: list[str] = []

    while pending_batches:
        batch = pending_batches.pop(0)
        if not batch:
            continue

        params = dict(base_params)
        params[batch_param] = ",".join(batch)
        params["MaxRowsReturned"] = max_rows_returned

        batch_key = ",".join(batch)

        try:
            # Use a single attempt here; if it fails, we decide whether to split/retry.
            payload = request_json(
                client,
                path,
                params,
                retries=1,
                base_url=QUERY_TOOL_URL,
            )
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code if exc.response is not None else None
            splittable_statuses = {414, 429, 500, 502, 503, 504}

            if status in splittable_statuses and len(batch) > 1:
                left, right = split_batch(batch)
                pending_batches = [left, right, *pending_batches]
                continue

            if status in splittable_statuses:
                attempts = single_batch_attempts.get(batch_key, 0) + 1
                single_batch_attempts[batch_key] = attempts
                if attempts < single_batch_max_attempts:
                    time.sleep(min(5, attempts))
                    pending_batches.append(batch)
                    continue

                warnings.append(
                    f"{path} batch ({batch_param}={batch[0]}...{batch[-1]}) failed with HTTP {status} "
                    f"after {attempts} attempts; skipping"
                )
                continue

            raise
        except httpx.HTTPError as exc:
            if len(batch) > 1:
                left, right = split_batch(batch)
                pending_batches = [left, right, *pending_batches]
                continue

            attempts = single_batch_attempts.get(batch_key, 0) + 1
            single_batch_attempts[batch_key] = attempts
            if attempts < single_batch_max_attempts:
                time.sleep(min(5, attempts))
                pending_batches.append(batch)
                continue

            warnings.append(
                f"{path} batch ({batch_param}={batch[0]}...{batch[-1]}) transport error ({exc}) "
                f"after {attempts} attempts; skipping"
            )
            continue

        rows = payload.get(row_key) or []
        meta = payload.get("meta") or {}
        rows_returned = parse_int(meta.get("rowsReturned"))
        suspicious = (
            (rows_returned is not None and rows_returned >= truncation_threshold)
            or len(rows) >= truncation_threshold
        )

        if suspicious and len(batch) > 1:
            left, right = split_batch(batch)
            pending_batches = [left, right, *pending_batches]
            continue

        if suspicious:
            warnings.append(
                f"{path} batch ({batch_param}={batch[0]}...{batch[-1]}) may be truncated "
                f"(rows={len(rows)}, rowsReturned={rows_returned})"
            )

        all_rows.extend(rows)

    return all_rows, warnings
