"""
Database connection and query helpers.

Provides:
- Connection management via POSTGRES_URL
- Query helpers that return dicts/rows
- SQL assertion runner (fail-fast validation)
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

import psycopg


def get_connection_string() -> str:
    """Return POSTGRES_URL from environment (raises if missing)."""
    url = os.environ.get("POSTGRES_URL")
    if not url:
        raise RuntimeError("POSTGRES_URL environment variable is required")
    return url


def get_connection() -> psycopg.Connection:
    """Open a new psycopg connection."""
    return psycopg.connect(get_connection_string())


def fetch_all(sql: str, params: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    """Execute query and return all rows as list of dicts."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            columns = [desc.name for desc in cur.description or []]
            return [dict(zip(columns, row)) for row in cur.fetchall()]


def fetch_one(sql: str, params: dict[str, Any] | None = None) -> dict[str, Any] | None:
    """Execute query and return first row as dict (or None)."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            row = cur.fetchone()
            if row is None:
                return None
            columns = [desc.name for desc in cur.description or []]
            return dict(zip(columns, row))


def run_sql_assertions(assertions_file: Path | None = None) -> tuple[bool, str]:
    """
    Run SQL assertion suite via psql.

    Returns (passed, output). If assertions_file is None, uses the default
    queries/sql/run_all.sql path.
    """
    if assertions_file is None:
        # Default: project root / queries/sql/run_all.sql
        project_root = Path(__file__).parent.parent.parent
        assertions_file = project_root / "queries" / "sql" / "run_all.sql"

    if not assertions_file.exists():
        return False, f"Assertions file not found: {assertions_file}"

    try:
        result = subprocess.run(
            [
                "psql",
                get_connection_string(),
                "-v",
                "ON_ERROR_STOP=1",
                "-f",
                str(assertions_file),
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        passed = result.returncode == 0
        output = result.stdout + result.stderr
        return passed, output
    except subprocess.TimeoutExpired:
        return False, "SQL assertions timed out"
    except FileNotFoundError:
        return False, "psql not found in PATH"
