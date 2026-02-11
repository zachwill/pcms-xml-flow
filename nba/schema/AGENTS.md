# NBA Schema Reference

This directory contains PostgreSQL table definitions for NBA data ingestion. The schema consolidates data from two primary sources:

1. **NBA Official APIs** (`nba-stats.txt`, `nba-cdn.txt`, etc.) — primary source
2. **NGSS (Genius Sports)** — legacy/supplemental source with richer metadata in some areas

---

## Schema Overview

### Core Entity Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `nba.players` | `nba_id` | Player directory (all leagues: NBA, WNBA, G League) |
| `nba.teams` | `team_id` | Team directory with arena info |
| `nba.games` | `game_id` | Individual game records with scores, broadcasters, status |
| `nba.schedules` | `(season_year, league_id)` | Season-level metadata (weeks, calendars, broadcasters) |
| `nba.playoff_series` | `series_id` | Playoff series/bracket metadata (unified across NBA/NGSS sources) |
| `nba.standings` | `(league_id, season_year, season_type, team_id, standing_date)` | Historical standings snapshots |

### Boxscore & Stats Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `nba.boxscores_traditional` | `(game_id, nba_id)` | Player traditional stats per game |
| `nba.boxscores_advanced` | `(game_id, nba_id)` | Player advanced stats per game |
| `nba.boxscores_advanced_team` | `(game_id, team_id)` | Team advanced stats per game |
| `nba.boxscores_traditional_team` | `(game_id, team_id)` | Team-level traditional boxscore (bench pts, paint pts, etc.) |
| `nba.player_stats_aggregated` | `(nba_id, team_id, season_year, season_type, per_mode, measure_type)` | Season aggregates |
| `nba.team_stats_aggregated` | `(team_id, season_year, season_type, per_mode, measure_type)` | Team season aggregates |

### Event & Tracking Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `nba.play_by_play` | `game_id` | Full PBP event stream as JSONB (one row per game) |
| `nba.players_on_court` | `game_id` | Players on court (POC) as JSONB (one row per game) |
| `nba.hustle_stats` | `(game_id, nba_id)` | Player hustle metrics (deflections, boxouts, etc.) |
| `nba.hustle_stats_team` | `(game_id, team_id)` | Team hustle totals (official team block) |
| `nba.hustle_events` | `game_id` | Hustle event stream as JSONB |
| `nba.tracking_stats` | `(game_id, nba_id)` | Player tracking metrics (distance, speed, touches) |
| `nba.tracking_streams` | `stream_id` | Hawkeye tracking stream status |
| `nba.lineup_stats_season` | `(league_id, season_year, season_type, team_id, player_ids, per_mode, measure_type)` | Season-level lineup performance |
| `nba.lineup_stats_game` | `(game_id, team_id, player_ids, per_mode, measure_type)` | Game-level lineup performance |

### Supplemental Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `nba.injuries` | `(nba_id, team_id)` | Active injury report (overwritten on fetch) |
| `nba.alerts` | `alert_id` | Game alerts (milestones, runs, career highs) |
| `nba.pregame_storylines` | `(game_id, team_id, storyline_order)` | Pre-tip narratives |

### NGSS (Legacy/Supplemental) Tables

| Table | Primary Key | Purpose |
|-------|-------------|---------|
| `nba.ngss_games` | `game_id` | NGSS game metadata (rulesets, granular timestamps) |
| `nba.ngss_rosters` | `(ngss_game_id, ngss_person_id)` | Person mapping layer for NGSS data |
| `nba.ngss_boxscores` | `game_id` | Full NGSS boxscore as JSONB |
| `nba.ngss_pbp` | `game_id` | Full NGSS PBP as JSONB (richer than NBA PBP for challenges, officials) |
| `nba.ngss_officials` | `(game_id, ngss_official_id)` | Game officials with assignment roles |

---

## Key Design Decisions

### Identity & Cross-Referencing

- **`nba_id`** is the authoritative player identifier (NBA's `personId`)
- **`team_id`** is the official NBA team identifier (e.g., `1610612737` for Hawks)
- **`game_id`** is the 10-digit NBA game identifier (e.g., `0022300001`)
- **`ngss_*_id`** columns store Genius Sports identifiers for joining legacy feeds

### JSONB for Complex/Unstable Structures

Following the "PBP Guidance" principle, these are stored as JSONB to prevent premature schema explosion:
- `nba.play_by_play.pbp_json`
- `nba.players_on_court.poc_json`
- `nba.hustle_events.hustle_events_json`
- `nba.ngss_boxscores.boxscore_json`
- `nba.ngss_pbp.ngss_pbp_json`
- `nba.games.game_json`
- `nba.schedules.*_json` columns

### Numeric Precision

| Type | Usage |
|------|-------|
| `numeric(5,4)` | Percentages as decimals (e.g., 0.5432) |
| `numeric(6,2)` | Ratings per 100 possessions (e.g., 115.42) |
| `numeric(8,2)` | Aggregate stats and minutes (totals or per-game averages) |

### League Identifiers

```
'00' = NBA
'10' = WNBA
'20' = G League
```

### Season Conventions

- `season_year` = starting year (e.g., `2023` for 2023-24 season)
- `season_label` = display string (e.g., `"2023-24"`)
- `season_type` = `"Regular Season"`, `"Playoffs"`, `"Pre Season"`, `"PlayIn"`, `"All-Star"`, `"IST Championship"`

---

## Common Query Patterns

### Get player's current team
```sql
SELECT * FROM nba.players WHERE nba_id = 203081;
-- current_team_id, current_team_tricode are denormalized
```

### Get game with teams
```sql
SELECT g.*, 
       h.team_full_name AS home_team,
       a.team_full_name AS away_team
FROM nba.games g
JOIN nba.teams h ON g.home_team_id = h.team_id
JOIN nba.teams a ON g.away_team_id = a.team_id
WHERE g.game_id = '0022300354';
```

### Get player stats for a game
```sql
SELECT p.full_name, b.*
FROM nba.boxscores_traditional b
JOIN nba.players p ON b.nba_id = p.nba_id
WHERE b.game_id = '0022300354'
ORDER BY b.pts DESC;
```

### Get season aggregates
```sql
SELECT * FROM nba.player_stats_aggregated
WHERE nba_id = 203081
  AND season_year = 2023
  AND season_type = 'Regular Season'
  AND per_mode = 'PerGame'
  AND measure_type = 'Base';
```

---

## File Reference

Each `.txt` file in this directory defines one table:

| File | Table |
|------|-------|
| `players.txt` | `nba.players` |
| `teams.txt` | `nba.teams` |
| `games.txt` | `nba.games` |
| `schedules.txt` | `nba.schedules` |
| `playoff_series.txt` | `nba.playoff_series` |
| `standings.txt` | `nba.standings` |
| `boxscores_traditional.txt` | `nba.boxscores_traditional` |
| `boxscores_advanced.txt` | `nba.boxscores_advanced` |
| `boxscores_advanced_team.txt` | `nba.boxscores_advanced_team` |
| `boxscores_traditional_team.txt` | `nba.boxscores_traditional_team` |
| `play_by_play.txt` | `nba.play_by_play` |
| `players_on_court.txt` | `nba.players_on_court` |
| `lineup_stats_season.txt` | `nba.lineup_stats_season` |
| `lineup_stats_game.txt` | `nba.lineup_stats_game` |
| `lineups.txt` | `nba.lineups` (deprecated) |
| `player_stats_aggregated.txt` | `nba.player_stats_aggregated` |
| `team_stats_aggregated.txt` | `nba.team_stats_aggregated` |
| `injuries.txt` | `nba.injuries` |
| `alerts.txt` | `nba.alerts` |
| `hustle_stats.txt` | `nba.hustle_stats` |
| `hustle_stats_team.txt` | `nba.hustle_stats_team` |
| `hustle_events.txt` | `nba.hustle_events` |
| `tracking_stats.txt` | `nba.tracking_stats` |
| `tracking_streams.txt` | `nba.tracking_streams` |
| `pregame_storylines.txt` | `nba.pregame_storylines` |
| `ngss_games.txt` | `nba.ngss_games` |
| `ngss_rosters.txt` | `nba.ngss_rosters` |
| `ngss_boxscores.txt` | `nba.ngss_boxscores` |
| `ngss_pbp.txt` | `nba.ngss_pbp` |
| `ngss_officials.txt` | `nba.ngss_officials` |

---

## When to Use NBA vs NGSS Tables

| Use Case | Table |
|----------|-------|
| Standard player/team/game lookups | `nba.*` tables |
| Boxscores with standard metrics | `nba.boxscores_*` |
| Play-by-play with challenge/officials context | `nba.ngss_pbp` |
| Game rulesets (shot clock, period length) | `nba.ngss_games.ruleset_json` |
| Official assignments (Crew Chief, Umpire) | `nba.ngss_officials` |
| Metrics not in NBA API (EfficiencyGameScore) | `nba.ngss_boxscores.boxscore_json` |
