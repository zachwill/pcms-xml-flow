# Windmill Schedules

This document inventories all `*.schedule.yaml` files in the repository and summarizes what each schedule runs.
Use the file paths below as the reference data for the cron backbone.

## Inventory by path

> Fields: schedule file ➜ script path, cron schedule, timezone, enabled, flow, args.

### `u/zach/`

- `u/zach/delancey_place_interesting.schedule.yaml` ➜ `u/zach/delancey_place_interesting`
  - Schedule: `0 * * * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `false`, Flow: `false`
  - Args: `batch_size=15`, `concurrency=3`, `dry_run=false`, `total_items=45`
- `u/zach/backfill_nba_advanced_box_scores.schedule.yaml` ➜ `f/nba/nba_box_advanced`
  - Schedule: `0 */6 17-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season_id=22025`
- `u/zach/backfill_nba_box.schedule.yaml` ➜ `f/nba/nba_boxscores`
  - Schedule: `0 */6 17-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season=22025`
- `u/zach/sports_jobs.schedule.yaml` ➜ `u/zach/sports_jobs`
  - Schedule: `0 0 7,19 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `dry_run=false`

### `f/blitz/`

- `f/blitz/update_data.schedule.yaml` ➜ `f/blitz/update_data`
  - Schedule: `5 26 5 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `true`
  - Args: none
- `f/blitz/pcms_xml.schedule.yaml` ➜ `f/blitz/pcms_xml`
  - Schedule: `0 35 2,14 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none

### `f/noah/`

- `f/noah/update_noah_kpis.schedule.yaml` ➜ `f/noah/update_noah_kpis`
  - Schedule: `0 0 * * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/noah/check_on_streamlit.schedule.yaml` ➜ `f/noah/check_on_streamlit`
  - Schedule: `0 0 */2 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `timeout_ms=30000`
- `f/noah/recent_shots.schedule.yaml` ➜ `f/noah/recent_shots`
  - Schedule: `0 15 5,13,20 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `true`
  - Args: none
- `f/noah/refresh_dashboard_view.schedule.yaml` ➜ `f/noah/refresh_dashboard_view`
  - Schedule: `0 5 */8 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none

### `f/slack/`

- `f/slack/reddit_rumors.schedule.yaml` ➜ `f/slack/reddit_rumors`
  - Schedule: `0 13 8,20 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `channel=#rumors`
- `f/slack/referees.schedule.yaml` ➜ `f/slack/referees`
  - Schedule: `0 5 7 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `true`
  - Args: none
- `f/slack/rivals_news.schedule.yaml` ➜ `f/slack/rivals_rewrite`
  - Schedule: `0 5 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `days_back=3`, `dry_run=false`
- `f/slack/hoopshype_schedule.schedule.yaml` ➜ `f/slack/hoopshype`
  - Schedule: `9 0 4-23,0 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `days_back=2`

### `f/rotowire/`

- `f/rotowire/nba_to_slack.schedule.yaml` ➜ `f/rotowire/nba_news_to_slack`
  - Schedule: `1 12,36,54 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `dry_run=false`, `earliest_date=`
- `f/rotowire/college_sheri.schedule.yaml` ➜ `f/rotowire/college_sheri`
  - Schedule: `1 12,36,54 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `dry_run=false`, `earliest_date=2025-09-10`
- `f/rotowire/all_news.schedule.yaml` ➜ `f/rotowire/all_sports`
  - Schedule: `0 0 4,21 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/rotowire/nba_lines.schedule.yaml` ➜ `f/rotowire/action_network`
  - Schedule: `5 5 8,10,12,14,16 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/rotowire/recent_news.schedule.yaml` ➜ `f/rotowire/recent_news`
  - Schedule: `5 */12 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `batch_limit=1`, `input_date=`

### `f/draft/`

- `f/draft/dx_mock_draft.schedule.yaml` ➜ `f/draft/dx_mock_draft`
  - Schedule: `25 55 6,13 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `false`, Flow: `false`
  - Args: `draft_year=2026`
- `f/draft/fanduel.schedule.yaml` ➜ `f/draft/fanduel_odds`
  - Schedule: `42 */15 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `false`, Flow: `false`
  - Args: none
- `f/draft/kenpom_stats.schedule.yaml` ➜ `f/draft/kenpom_stats`
  - Schedule: `0 0 2,4 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `date=`, `dry_run=false`, `endpoint=nightly`

### `f/realgm/`

- `f/realgm/ncaa.schedule.yaml` ➜ `f/realgm/ncaa`
  - Schedule: `0 7 2,4 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season=2026`, `season_part=Season`, `stat_type=all`
- `f/realgm/gleague.schedule.yaml` ➜ `f/realgm/gleague`
  - Schedule: `0 32 2,4 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season=2026`, `season_part=FullSeason`, `stat_type=all`
- `f/realgm/nba.schedule.yaml` ➜ `f/realgm/nba`
  - Schedule: `0 4 2,4 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season=2026`, `season_part=Regular_Season`, `stat_type=all`

### `f/nba/`

- `f/nba/fetch_ngss_persons.schedule.yaml` ➜ `f/nba/fetch_ngss_persons`
  - Schedule: `0 0 */8 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season_id=22025`
- `f/nba/fetch_injury_snapshots.schedule.yaml` ➜ `f/nba/fetch_nba_injuries`
  - Schedule: `0 0 */3 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/nba/dunks_epm.schedule.yaml` ➜ `f/nba/dunks_threes`
  - Schedule: `0 0 3,7,14,16 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `date=`, `season=2026`, `season_type=2`
- `f/nba/process_nba_json_data.schedule.yaml` ➜ `f/nba/process_nba_data`
  - Schedule: `0 8 16,18,20,22,0 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `season_id=22025`
- `f/nba/nba_dev_portal.schedule.yaml` ➜ `f/nba/nba_dev_portal`
  - Schedule: `1 2 20,21,23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `false`, Flow: `true`
  - Args: `season_id=22024`
- `f/nba/schedule_nightly_email.schedule.yaml` ➜ `f/nba/send_nightly_email`
  - Schedule: `0 0 1 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `date=`, `is_test=false`
- `f/nba/spotrac_flow.schedule.yaml` ➜ `f/nba/spotrac_flow`
  - Schedule: `16 30 4-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `true`
  - Args: `start_date=2025-09-01`

### `f/youtube/`

- `f/youtube/postgresfm.schedule.yaml` ➜ `f/youtube/postgresfm`
  - Schedule: `0 0 14,18 ? * 5` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/youtube/transcript_schedule.schedule.yaml` ➜ `f/youtube/transcript_loop`
  - Schedule: `22 6,48 5-23 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `false`, Flow: `false`
  - Args: `number_of_rows=50`, `upload_date=2025-07-22`
- `f/youtube/new_videos.schedule.yaml` ➜ `f/youtube/new_videos`
  - Schedule: `12 13 4,6,8,10,12,14,16,18,20 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `true`
  - Args: `transcripts_since=2025-09-01`
- `f/youtube/schedule_podcasts.schedule.yaml` ➜ `f/youtube/schedule_podcasts`
  - Schedule: `12 15 4,6,8,10,12,14,16,18,20 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none

### `f/ctg/`

- `f/ctg/ctg_schedule.schedule.yaml` ➜ `f/ctg/ctg_schedule`
  - Schedule: `0 15 5 * * *` (cron v1), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: none
- `f/ctg/player_stats.schedule.yaml` ➜ `f/ctg/player_stats`
  - Schedule: `0 0 5 * * *` (cron v2), Timezone: `America/Los_Angeles`
  - Enabled: `true`, Flow: `false`
  - Args: `dry_run=false`, `start_season=2025`, `end_season=2025`
