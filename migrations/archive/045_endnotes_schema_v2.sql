-- 045_endnotes_schema_v2.sql
--
-- Expand pcms.endnotes to better model real endnote semantics:
-- - multi-year protections/rollovers
-- - frozen pick notices
-- - promote commonly-used parsed fields out of json
--
-- NOTE: This migration only adds columns + indexes.
-- Backfills should be done via scripts (data-dependent and iterative).

begin;

alter table pcms.endnotes
  add column if not exists note_type text,
  add column if not exists status_lk text,
  add column if not exists resolution_lk text,
  add column if not exists resolved_at date,

  add column if not exists draft_years int[] not null default '{}'::int[],
  add column if not exists draft_rounds int[] not null default '{}'::int[],
  add column if not exists draft_year_start int,
  add column if not exists draft_year_end int,
  add column if not exists has_rollover boolean not null default false,

  add column if not exists is_frozen_pick boolean not null default false,

  add column if not exists teams_mentioned text[] not null default '{}'::text[],
  add column if not exists from_team_codes text[] not null default '{}'::text[],
  add column if not exists to_team_codes text[] not null default '{}'::text[],

  add column if not exists trade_ids int[] not null default '{}'::int[],
  add column if not exists depends_on_endnotes int[] not null default '{}'::int[],

  add column if not exists trade_summary text,
  add column if not exists conveyance_text text,
  add column if not exists protections_text text,
  add column if not exists contingency_text text,
  add column if not exists exercise_text text;

-- Helpful indexes for joins / filtering
create index if not exists endnotes_trade_id_idx on pcms.endnotes (trade_id);
create index if not exists endnotes_trade_ids_gin_idx on pcms.endnotes using gin (trade_ids);
create index if not exists endnotes_draft_years_gin_idx on pcms.endnotes using gin (draft_years);
create index if not exists endnotes_depends_on_gin_idx on pcms.endnotes using gin (depends_on_endnotes);
create index if not exists endnotes_teams_mentioned_gin_idx on pcms.endnotes using gin (teams_mentioned);

commit;
