-- Migration: 009_nba_team_metadata.sql
-- Description: Populate city, state, country, division, conference for NBA teams.
--              PCMS source data has these as null for all NBA teams.
-- Date: 2026-01-18

BEGIN;

-- NBA Team Metadata
-- Source: Manually curated (PCMS doesn't provide this data for NBA teams)

UPDATE pcms.teams SET
  city = v.city,
  state_lk = v.state_lk,
  country_lk = v.country_lk,
  division_name = v.division_name,
  conference_name = v.conference_name
FROM (VALUES
  -- Eastern Conference - Atlantic Division
  (1610612738, 'Boston',       'MA', 'USA', 'Atlantic',  'Eastern'),
  (1610612751, 'Brooklyn',     'NY', 'USA', 'Atlantic',  'Eastern'),
  (1610612752, 'New York',     'NY', 'USA', 'Atlantic',  'Eastern'),
  (1610612755, 'Philadelphia', 'PA', 'USA', 'Atlantic',  'Eastern'),
  (1610612761, 'Toronto',      'ON', 'CAN', 'Atlantic',  'Eastern'),

  -- Eastern Conference - Central Division
  (1610612741, 'Chicago',      'IL', 'USA', 'Central',   'Eastern'),
  (1610612739, 'Cleveland',    'OH', 'USA', 'Central',   'Eastern'),
  (1610612765, 'Detroit',      'MI', 'USA', 'Central',   'Eastern'),
  (1610612754, 'Indianapolis', 'IN', 'USA', 'Central',   'Eastern'),
  (1610612749, 'Milwaukee',    'WI', 'USA', 'Central',   'Eastern'),

  -- Eastern Conference - Southeast Division
  (1610612737, 'Atlanta',      'GA', 'USA', 'Southeast', 'Eastern'),
  (1610612766, 'Charlotte',    'NC', 'USA', 'Southeast', 'Eastern'),
  (1610612748, 'Miami',        'FL', 'USA', 'Southeast', 'Eastern'),
  (1610612753, 'Orlando',      'FL', 'USA', 'Southeast', 'Eastern'),
  (1610612764, 'Washington',   'DC', 'USA', 'Southeast', 'Eastern'),

  -- Western Conference - Northwest Division
  (1610612743, 'Denver',          'CO', 'USA', 'Northwest',  'Western'),
  (1610612750, 'Minneapolis',     'MN', 'USA', 'Northwest',  'Western'),
  (1610612760, 'Oklahoma City',   'OK', 'USA', 'Northwest',  'Western'),
  (1610612757, 'Portland',        'OR', 'USA', 'Northwest',  'Western'),
  (1610612762, 'Salt Lake City',  'UT', 'USA', 'Northwest',  'Western'),

  -- Western Conference - Pacific Division
  (1610612744, 'San Francisco', 'CA', 'USA', 'Pacific',   'Western'),
  (1610612746, 'Los Angeles',   'CA', 'USA', 'Pacific',   'Western'),
  (1610612747, 'Los Angeles',   'CA', 'USA', 'Pacific',   'Western'),
  (1610612756, 'Phoenix',       'AZ', 'USA', 'Pacific',   'Western'),
  (1610612758, 'Sacramento',    'CA', 'USA', 'Pacific',   'Western'),

  -- Western Conference - Southwest Division
  (1610612742, 'Dallas',       'TX', 'USA', 'Southwest', 'Western'),
  (1610612745, 'Houston',      'TX', 'USA', 'Southwest', 'Western'),
  (1610612763, 'Memphis',      'TN', 'USA', 'Southwest', 'Western'),
  (1610612740, 'New Orleans',  'LA', 'USA', 'Southwest', 'Western'),
  (1610612759, 'San Antonio',  'TX', 'USA', 'Southwest', 'Western')
) AS v(team_id, city, state_lk, country_lk, division_name, conference_name)
WHERE pcms.teams.team_id = v.team_id;

COMMIT;

-- Verification query:
-- SELECT team_id, team_name, team_code, city, state_lk, division_name, conference_name 
-- FROM pcms.teams 
-- WHERE league_lk = 'NBA' AND team_name NOT LIKE 'Non-NBA%'
-- ORDER BY conference_name, division_name, city;
