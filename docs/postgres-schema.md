# ZachBase Postgres schema

Generated at: 2026-01-02T04:23:08.910Z
Source table: zachbase.postgres

## blitz

### Tables

```
availability
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

body_comp
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

contracts
 - contract_id integer primary key
 - player_id integer
 - team_id integer
 - first_name text
 - last_name text
 - birth_date date
 - years_of_service integer
 - is_max_contract boolean
 - is_minimum_contract boolean
 - contract_type text
 - free_agent_type text
 - signing_method text
 - signing_date date
 - no_trade_flag boolean
 - poison_pill_amount numeric
 - trade_restriction text
 - trade_restriction_end date
 - cap_hit_2024 numeric
 - tax_hit_2024 numeric
 - apron_hit_2024 numeric
 - option_type_2024 text
 - cap_hit_2025 numeric
 - tax_hit_2025 numeric
 - apron_hit_2025 numeric
 - option_type_2025 text
 - cap_hit_2026 numeric
 - tax_hit_2026 numeric
 - apron_hit_2026 numeric
 - option_type_2026 text
 - cap_hit_2027 numeric
 - tax_hit_2027 numeric
 - apron_hit_2027 numeric
 - option_type_2027 text
 - cap_hit_2028 numeric
 - tax_hit_2028 numeric
 - apron_hit_2028 numeric
 - option_type_2028 text
 - total_remaining_after_2024 numeric
 - total_guaranteed numeric
 - guaranteed_seasons integer
 - agent_id integer
 - agent_name text
 - agency_id integer
 - agency_name text
 - raw_data jsonb
 - created_at timestamp with time zone default now()
 - last_changed_at timestamp with time zone
 - player_status text

development_updates
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

draft_rankings
 - id serial primary key
 - draft_year integer
 - data jsonb
 - scout_id text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - value_delimiters jsonb

draft_review
 - id serial primary key
 - blitz_id text
 - draft_range text
 - shades_of text
 - archetype text
 - highlight_1 text
 - highlight_2 text
 - highlight_3 text
 - strengths text
 - weaknesses text
 - analytics text
 - background text
 - stats_title text
 - stats_subtitle text
 - stats text
 - agent text
 - scout_id text
 - last_edited_by text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - hometown text
 - draft_year integer
 - medical_flag boolean
 - intel_flag boolean
 - combine_draft_range text
 - combine_what_we_know text
 - combine_questions text
 - combine_jersey_number text
 - intel_concern boolean
 - defensive_role text

draft_scout_rankings
 - scout_id text primary key
 - draft_year integer primary key
 - data jsonb
 - created_at timestamp with time zone
 - updated_at timestamp with time zone

draft_tier_info
 - id serial primary key
 - tier text
 - trade_value text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone

free_agent_rankings
 - id integer primary key
 - season integer
 - data jsonb
 - scout_id text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone

geoff
 - id integer primary key
 - nba_id integer
 - report_date date
 - participation text
 - reason text
 - laterality text
 - body_region text
 - body_part text
 - body_site text
 - description text
 - ps_missed_game boolean
 - rs_missed_game boolean
 - po_game_missed text
 - notes text
 - scout_id text
 - created_at timestamp with time zone

intel
 - id integer primary key
 - blitz_id text
 - blitz_name text
 - scout_id text
 - intel text
 - source_team text
 - source_relationship text
 - confidence_level numeric
 - created_at timestamp with time zone default now()

intel_buyouts
 - id integer primary key
 - blitz_id text
 - blitz_team_id text
 - vertical text
 - remaining_years integer
 - buyout_amount numeric
 - notes text
 - scout_id text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone default now()

intel_reports
 - id integer primary key
 - data jsonb
 - blitz_id text
 - scout_id text
 - mother text
 - father text
 - other_family text
 - background text
 - basketball_journey text
 - mental_makeup text
 - off_court_habits text
 - injury_history text
 - key_contact_1 text
 - key_contact_2 text
 - source_name text
 - source_relationship text
 - created_at timestamp with time zone

map_to_nba
 - blitz_id text primary key
 - nba_id integer
 - created_at timestamp with time zone

measurements
 - measurement_id integer primary key
 - blitz_id text
 - event_name text
 - measurement_date date
 - height_wo_shoes numeric
 - height_w_shoes numeric
 - weight numeric
 - wingspan numeric
 - standing_reach numeric
 - body_fat_pct numeric
 - hand_length numeric
 - hand_width numeric
 - shoulder_height numeric
 - standing_vertical_leap numeric
 - max_vertical_leap numeric
 - lane_agility_time numeric
 - modified_lane_agility_time numeric
 - three_quarter_sprint numeric
 - bench_press numeric
 - second_leap numeric
 - absolute_leap numeric
 - triple_hop_left numeric
 - triple_hop_right numeric
 - created_by_id text
 - created timestamp without time zone
 - updated timestamp without time zone
 - event_id text
 - jersey_num text
 - is_home_team text

medical_updates
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

nutrition_updates
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

performance_updates
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

playcalls
 - season integer
 - game_id text
 - chance_id text primary key
 - offense text
 - playcall text
 - offense_type text

playcalls_raw
 - game_id text primary key
 - season integer
 - playcall text primary key
 - offense_type text
 - period integer primary key
 - minute integer primary key
 - second integer primary key
 - offense text

positions
 - blitz_id text primary key
 - "position" integer
 - position_estimate integer
 - first_name text
 - last_name text
 - position_input integer
 - nba_id integer

practice_minutes
 - smartabase_id integer primary key
 - smartabase_user_id integer
 - player text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

prospect_medical
 - id integer primary key
 - red_flag boolean
 - blitz_id text
 - blitz_name text
 - scouting_review text
 - scouting_review_last_user_id text
 - vaccination_status text
 - medical_history text
 - medical_history_last_user_id text
 - orthopedic_exam_risk integer
 - orthopedic_exam text
 - orthopedic_exam_last_user_id text
 - orthopedic_exam_doctor_id text
 - internal_assessment_risk integer
 - internal_assessment text
 - internal_assessment_last_user_id text
 - internal_assessment_doctor_id text
 - finalized_by_user_id text
 - created_at timestamp without time zone
 - updated_at timestamp without time zone
 - covid_contracted boolean
 - covid_contracted_dates jsonb
 - covid_cardiac_clearance boolean
 - imaging_requests jsonb
 - medical_history_finalized_by_id text
 - internal_assessment_finalized_by_id text
 - orthopedic_exam_finalized_by_id text
 - movement_performance text
 - movement_performance_last_user_id text
 - movement_performance_finalized_by_id text

prospects
 - blitz_id text primary key
 - team_id text
 - draft_year bigint
 - first_name text
 - last_name text
 - birth_date date
 - birth_place text
 - jersey_number text
 - height numeric
 - weight numeric
 - "position" text
 - headshot_url text
 - tier integer
 - created_at timestamp without time zone
 - updated_at timestamp without time zone
 - experience text
 - combine_invite text
 - nba_id bigint
 - agent text
 - wingspan numeric
 - agent_id bigint
 - agency_id bigint

scout_report_games
 - id serial primary key
 - blitz_id text
 - blitz_team_id text
 - game_id text
 - scout_id text
 - grades jsonb
 - data jsonb
 - report_type text
 - manual_event_id text
 - notes text
 - submitted_by_id text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone
 - is_draft boolean

scout_reports
 - id serial primary key
 - report_type text
 - scout_id text
 - data jsonb
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - is_draft boolean

snapshot_tier_draft
 - id serial primary key
 - data jsonb
 - created_at timestamp with time zone default now()

teams
 - team_id text primary key
 - name text
 - short_name text
 - abbrev text
 - league_id text primary key

tier_nba
 - nba_id integer primary key
 - tier integer
 - blitz_position text
 - player_type text
 - watch_list text
 - created_at text

transactions
 - id serial primary key
 - player_id integer
 - team_id integer
 - contract_id integer
 - agency_id integer
 - agency_name text
 - agency_active_flg boolean
 - agent_id integer
 - agent_first_name text
 - agent_last_name text
 - player_first_name text
 - player_last_name text
 - player_birth_date date
 - player_birth_country text
 - player_height numeric
 - player_weight numeric
 - player_position text
 - player_status text
 - contract_type text
 - budget_group text
 - free_agent_designation text
 - free_agent_status text
 - signing_date date
 - ledger_date date
 - raw_data jsonb
 - created_at timestamp with time zone default now()

user_group_level
 - scout_id text primary key
 - group_id text primary key

user_groups
 - group_id text primary key
 - description text
 - precedence integer
 - user_pool_id text

users
 - scout_id text
 - sub text
 - email_verified boolean
 - given_name text
 - family_name text
 - email text
 - user_pool_id text

zach_reports
 - draft integer primary key
 - blitz_id text primary key
 - player text
 - full_report text
 - concise_report text
 - intel_report text
```


### Views

```
scouts_2025
 - blitz_id text
 - scout text
 - rank bigint
 - player text
 - draft_age numeric
 - "position" text
 - height text
 - weight numeric
 - wingspan text
 - length numeric
 - birth_place text
 - birth_date date
 - agent text
 - peak_rating numeric
 - rookie_rating numeric
 - combine_invite text

tier_draft
 - blitz_id text
 - tier integer
 - tier_name text
 - draft_slot bigint
 - team_name text
 - player_name text
 - age numeric
 - draft_age numeric
 - birth_date date
 - birth_place text
 - height numeric
 - weight numeric
 - wingspan numeric
 - "position" text
 - created_at timestamp without time zone
 - updated_at timestamp without time zone
 - experience text
 - combine_invite text
 - nba_id bigint
 - agent text
 - agent_id bigint
 - agency_id bigint
 - jersey_number text
 - first_name text
 - last_name text
 - tier_slot bigint
 - tier_trade_value text
```


### Functions

```
function prospect_profile(p_blitz_id text) returns jsonb
```


## ctg

### Tables

```
ctg_anthro
 - ctg_id text primary key
 - first_name text
 - last_name text
 - height numeric
 - height_percentile numeric
 - wingspan numeric
 - wingspan_percentile numeric
 - left_arm_length numeric
 - left_arm_length_percentile numeric
 - right_arm_length numeric
 - right_arm_length_percentile numeric
 - left_leg_length numeric
 - left_leg_length_percentile numeric
 - right_leg_length numeric
 - right_leg_length_percentile numeric
 - wingspan_to_height_ratio numeric
 - wingspan_to_height_ratio_percentile numeric
 - nba_id bigint

ctg_auth
 - token text primary key
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

ctg_nba
 - season integer primary key
 - ctg_id integer primary key
 - ctg_team_id integer primary key
 - player text
 - first_name text
 - last_name text
 - team_code text
 - season_type integer
 - age numeric(5,2)
 - "position" integer
 - position_category text
 - games integer
 - minutes numeric(8,2)
 - seconds integer
 - ortg numeric(8,3)
 - drtg numeric(8,3)
 - point_diff numeric(8,3)
 - pythagorean_wins numeric(6,3)
 - efg numeric(6,5)
 - tov_pct numeric(6,5)
 - oreb_pct numeric(6,5)
 - ft_rate numeric(8,3)
 - opp_efg numeric(6,5)
 - opp_tov_pct numeric(6,5)
 - opp_oreb_pct numeric(6,5)
 - opp_ft_rate numeric(8,3)
 - rim_fg numeric(6,5)
 - rim_freq numeric(6,5)
 - short_mid_fg numeric(6,5)
 - short_mid_freq numeric(6,5)
 - long_mid_fg numeric(6,5)
 - long_mid_freq numeric(6,5)
 - mid_fg numeric(6,5)
 - mid_freq numeric(6,5)
 - fg3_pct numeric(6,5)
 - fg3_freq numeric(6,5)
 - fg3_cnr_pct numeric(6,5)
 - fg3_cnr_freq numeric(6,5)
 - fg3_arc_pct numeric(6,5)
 - fg3_arc_freq numeric(6,5)
 - opp_rim_fg numeric(6,5)
 - opp_rim_freq numeric(6,5)
 - opp_short_mid_fg numeric(6,5)
 - opp_short_mid_freq numeric(6,5)
 - opp_long_mid_fg numeric(6,5)
 - opp_long_mid_freq numeric(6,5)
 - opp_mid_fg numeric(6,5)
 - opp_mid_freq numeric(6,5)
 - opp_fg3_pct numeric(6,5)
 - opp_fg3_freq numeric(6,5)
 - opp_fg3_cnr_pct numeric(6,5)
 - opp_fg3_cnr_freq numeric(6,5)
 - opp_fg3_arc_pct numeric(6,5)
 - opp_fg3_arc_freq numeric(6,5)
 - half_court_eff numeric(8,3)
 - half_court_freq numeric(6,5)
 - half_court_oreb_pct numeric(6,5)
 - opp_half_court_eff numeric(8,3)
 - opp_half_court_freq numeric(6,5)
 - opp_half_court_oreb_pct numeric(6,5)
 - trans_eff numeric(8,3)
 - trans_freq numeric(6,5)
 - trans_pts_added numeric(8,5)
 - trans_dreb_eff numeric(8,3)
 - trans_dreb_freq numeric(6,5)
 - trans_dreb_pts_added numeric(8,5)
 - trans_stl_eff numeric(8,3)
 - trans_stl_freq numeric(6,5)
 - trans_stl_pts_added numeric(8,5)
 - opp_trans_eff numeric(8,3)
 - opp_trans_freq numeric(6,5)
 - opp_trans_pts_added numeric(8,5)
 - opp_trans_dreb_eff numeric(8,3)
 - opp_trans_dreb_freq numeric(6,5)
 - opp_trans_dreb_pts_added numeric(8,5)
 - opp_trans_stl_eff numeric(8,3)
 - opp_trans_stl_freq numeric(6,5)
 - opp_trans_stl_pts_added numeric(8,5)
 - putback_eff numeric(8,3)
 - putback_freq numeric(8,3)
 - putback_pts_per_miss numeric(8,3)
 - opp_putback_eff numeric(8,3)
 - opp_putback_freq numeric(8,3)
 - opp_putback_pts_per_miss numeric(8,3)
 - ortg_ptile numeric(6,5)
 - drtg_ptile numeric(6,5)
 - point_diff_ptile numeric(6,5)
 - pythagorean_wins_ptile numeric(6,5)
 - efg_ptile numeric(6,5)
 - tov_pct_ptile numeric(6,5)
 - oreb_pct_ptile numeric(6,5)
 - ft_rate_ptile numeric(6,5)
 - rim_fg_ptile numeric(6,5)
 - rim_freq_ptile numeric(6,5)
 - short_mid_fg_ptile numeric(6,5)
 - short_mid_freq_ptile numeric(6,5)
 - long_mid_fg_ptile numeric(6,5)
 - long_mid_freq_ptile numeric(6,5)
 - mid_fg_ptile numeric(6,5)
 - mid_freq_ptile numeric(6,5)
 - fg3_pct_ptile numeric(6,5)
 - fg3_freq_ptile numeric(6,5)
 - fg3_cnr_pct_ptile numeric(6,5)
 - fg3_cnr_freq_ptile numeric(6,5)
 - fg3_arc_pct_ptile numeric(6,5)
 - fg3_arc_freq_ptile numeric(6,5)
 - half_court_eff_ptile numeric(6,5)
 - half_court_freq_ptile numeric(6,5)
 - half_court_oreb_ptile numeric(6,5)
 - trans_eff_ptile numeric(6,5)
 - trans_freq_ptile numeric(6,5)
 - trans_dreb_eff_ptile numeric(6,5)
 - trans_dreb_freq_ptile numeric(6,5)
 - trans_stl_eff_ptile numeric(6,5)
 - trans_stl_freq_ptile numeric(6,5)
 - trans_pts_added_ptile numeric(6,5)
 - putback_eff_ptile numeric(6,5)
 - putback_freq_ptile numeric(6,5)
 - putback_pts_per_miss_ptile numeric(6,5)
 - opp_efg_ptile numeric(6,5)
 - opp_tov_pct_ptile numeric(6,5)
 - opp_oreb_pct_ptile numeric(6,5)
 - opp_ft_rate_ptile numeric(6,5)
 - opp_rim_fg_ptile numeric(6,5)
 - opp_rim_freq_ptile numeric(6,5)
 - opp_short_mid_fg_ptile numeric(6,5)
 - opp_short_mid_freq_ptile numeric(6,5)
 - opp_long_mid_fg_ptile numeric(6,5)
 - opp_long_mid_freq_ptile numeric(6,5)
 - opp_mid_fg_ptile numeric(6,5)
 - opp_mid_freq_ptile numeric(6,5)
 - opp_fg3_pct_ptile numeric(6,5)
 - opp_fg3_freq_ptile numeric(6,5)
 - opp_fg3_cnr_pct_ptile numeric(6,5)
 - opp_fg3_cnr_freq_ptile numeric(6,5)
 - opp_fg3_arc_pct_ptile numeric(6,5)
 - opp_fg3_arc_freq_ptile numeric(6,5)
 - opp_half_court_eff_ptile numeric(6,5)
 - opp_half_court_freq_ptile numeric(6,5)
 - opp_half_court_oreb_ptile numeric(6,5)
 - opp_trans_eff_ptile numeric(6,5)
 - opp_trans_freq_ptile numeric(6,5)
 - opp_trans_dreb_eff_ptile numeric(6,5)
 - opp_trans_dreb_freq_ptile numeric(6,5)
 - opp_trans_stl_eff_ptile numeric(6,5)
 - opp_trans_stl_freq_ptile numeric(6,5)
 - opp_putback_eff_ptile numeric(6,5)
 - ortg_diff_ptile numeric(6,5)
 - drtg_diff_ptile numeric(6,5)
 - efg_diff_ptile numeric(6,5)
 - tov_pct_diff_ptile numeric(6,5)
 - oreb_pct_diff_ptile numeric(6,5)
 - ft_rate_diff_ptile numeric(6,5)
 - rim_fg_diff_ptile numeric(6,5)
 - rim_freq_diff_ptile numeric(6,5)
 - short_mid_fg_diff_ptile numeric(6,5)
 - short_mid_freq_diff_ptile numeric(6,5)
 - long_mid_fg_diff_ptile numeric(6,5)
 - long_mid_freq_diff_ptile numeric(6,5)
 - mid_fg_diff_ptile numeric(6,5)
 - mid_freq_diff_ptile numeric(6,5)
 - fg3_pct_diff_ptile numeric(6,5)
 - fg3_freq_diff_ptile numeric(6,5)
 - fg3_cnr_pct_diff_ptile numeric(6,5)
 - fg3_cnr_freq_diff_ptile numeric(6,5)
 - fg3_arc_pct_diff_ptile numeric(6,5)
 - fg3_arc_freq_diff_ptile numeric(6,5)
 - half_court_eff_diff_ptile numeric(6,5)
 - half_court_freq_diff_ptile numeric(6,5)
 - half_court_oreb_diff_ptile numeric(6,5)
 - transition_eff_diff_ptile numeric(6,5)
 - transition_freq_diff_ptile numeric(6,5)
 - putback_eff_diff_ptile numeric(6,5)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - nba_id integer

ctg_schedule
 - game_id text primary key
 - game_date date
 - season integer
 - season_type integer
 - away_score integer
 - home_score integer
 - away_team_id text
 - away_team text
 - home_team_id text
 - home_team text

ctg_teams
 - team_id text primary key
 - team_name text
 - team_code text
 - t_id integer

pro_player_games
 - season integer primary key
 - endpoint text primary key
 - params jsonb primary key
 - data jsonb
 - created_at timestamp with time zone default now()

pro_player_stats
 - season integer primary key
 - endpoint text primary key
 - params jsonb primary key
 - data jsonb
 - created_at timestamp with time zone default now()

pro_team_games
 - season integer primary key
 - endpoint text primary key
 - params jsonb primary key
 - data jsonb
 - created_at timestamp with time zone default now()

pro_team_stats
 - season integer primary key
 - endpoint text primary key
 - params jsonb primary key
 - data jsonb
 - created_at timestamp with time zone default now()
```


### Views

_None_


### Functions

_None_


## draftexpress

### Tables

```
dx_cookies
 - id serial primary key
 - cookie text
 - created_at timestamp with time zone default now()
```


### Views

_None_


### Functions

_None_


## dunks

### Tables

```
epm
 - season integer primary key
 - season_type integer primary key
 - nba_id integer primary key
 - player text
 - team_id integer
 - team_code text
 - team_code_all text
 - "position" text
 - age integer
 - rookie_year integer
 - height_inches integer
 - weight numeric(5,1)
 - g integer
 - roster_games integer
 - gs integer
 - mp numeric(10,3)
 - mpg numeric(5,2)
 - oepm numeric(8,5)
 - depm numeric(8,5)
 - epm numeric(8,5)
 - ewins numeric(8,4)
 - usg numeric(6,5)
 - ts numeric(6,5)
 - efg numeric(6,5)
 - rim_fg numeric(6,5)
 - mid_fg numeric(6,5)
 - fg2_pct numeric(6,5)
 - fg3_pct numeric(6,5)
 - ft_pct numeric(6,5)
 - oreb_pct numeric(6,5)
 - dreb_pct numeric(6,5)
 - ast_pct numeric(6,5)
 - tov_pct numeric(6,5)
 - stl_pct numeric(6,5)
 - blk_pct numeric(6,5)
 - pts_75 numeric(6,2)
 - fgm_rim_75 numeric(6,3)
 - fga_rim_75 numeric(6,3)
 - fgm_mid_75 numeric(6,3)
 - fga_mid_75 numeric(6,3)
 - fg2m_75 numeric(6,3)
 - fg2a_75 numeric(6,3)
 - fg3m_75 numeric(6,3)
 - fg3a_75 numeric(6,3)
 - ftm_75 numeric(6,3)
 - fta_75 numeric(6,3)
 - oreb_75 numeric(6,3)
 - dreb_75 numeric(6,3)
 - reb_75 numeric(6,3)
 - ast_75 numeric(6,3)
 - tov_75 numeric(6,3)
 - stl_75 numeric(6,3)
 - blk_75 numeric(6,3)
 - pts_pg numeric(5,2)
 - fgm_rim_pg numeric(5,2)
 - fga_rim_pg numeric(5,2)
 - fgm_mid_pg numeric(5,2)
 - fga_mid_pg numeric(5,2)
 - fg2m_pg numeric(5,2)
 - fg2a_pg numeric(5,2)
 - fg3m_pg numeric(5,2)
 - fg3a_pg numeric(5,2)
 - ftm_pg numeric(5,2)
 - fta_pg numeric(5,2)
 - oreb_pg numeric(5,2)
 - dreb_pg numeric(5,2)
 - reb_pg numeric(5,2)
 - ast_pg numeric(5,2)
 - tov_pg numeric(5,2)
 - stl_pg numeric(5,2)
 - blk_pg numeric(5,2)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - games_pct numeric(5,4)
 - dnp_games integer
 - epm_pctl numeric(5,2)
 - epm_pos_pctl numeric(5,2)
 - oepm_pctl numeric(5,2)
 - oepm_pos_pctl numeric(5,2)
 - depm_pctl numeric(5,2)
 - depm_pos_pctl numeric(5,2)
 - ewins_pctl numeric(5,2)
 - ewins_pos_pctl numeric(5,2)
 - usg_pctl numeric(5,2)
 - usg_pos_pctl numeric(5,2)
 - ts_pctl numeric(5,2)
 - ts_pos_pctl numeric(5,2)
 - efg_pctl numeric(5,2)
 - efg_pos_pctl numeric(5,2)
 - rim_fg_pctl numeric(5,2)
 - rim_fg_pos_pctl numeric(5,2)
 - mid_fg_pctl numeric(5,2)
 - mid_fg_pos_pctl numeric(5,2)
 - fg2_pct_pctl numeric(5,2)
 - fg2_pct_pos_pctl numeric(5,2)
 - fg3_pct_pctl numeric(5,2)
 - fg3_pct_pos_pctl numeric(5,2)
 - ft_pct_pctl numeric(5,2)
 - ft_pct_pos_pctl numeric(5,2)
 - oreb_pct_pctl numeric(5,2)
 - oreb_pct_pos_pctl numeric(5,2)
 - dreb_pct_pctl numeric(5,2)
 - dreb_pct_pos_pctl numeric(5,2)
 - ast_pct_pctl numeric(5,2)
 - ast_pct_pos_pctl numeric(5,2)
 - tov_pct_pctl numeric(5,2)
 - tov_pct_pos_pctl numeric(5,2)
 - stl_pct_pctl numeric(5,2)
 - stl_pct_pos_pctl numeric(5,2)
 - blk_pct_pctl numeric(5,2)
 - blk_pct_pos_pctl numeric(5,2)
 - pts_75_pctl numeric(5,2)
 - pts_75_pos_pctl numeric(5,2)
 - oreb_75_pctl numeric(5,2)
 - oreb_75_pos_pctl numeric(5,2)
 - dreb_75_pctl numeric(5,2)
 - dreb_75_pos_pctl numeric(5,2)
 - reb_75_pctl numeric(5,2)
 - reb_75_pos_pctl numeric(5,2)
 - ast_75_pctl numeric(5,2)
 - ast_75_pos_pctl numeric(5,2)
 - tov_75_pctl numeric(5,2)
 - tov_75_pos_pctl numeric(5,2)
 - stl_75_pctl numeric(5,2)
 - stl_75_pos_pctl numeric(5,2)
 - blk_75_pctl numeric(5,2)
 - blk_75_pos_pctl numeric(5,2)
 - fga_rim_75_pctl numeric(5,2)
 - fga_rim_75_pos_pctl numeric(5,2)
 - fga_mid_75_pctl numeric(5,2)
 - fga_mid_75_pos_pctl numeric(5,2)
 - fg3a_75_pctl numeric(5,2)
 - fg3a_75_pos_pctl numeric(5,2)
 - games_pct_pctl numeric(5,2)
 - dnp_games_pctl numeric(5,2)
 - mpg_pctl numeric(5,2)

epm_skills
 - data_date date primary key
 - nba_id integer primary key
 - game_optimized integer primary key default 0
 - season integer
 - season_type integer
 - team_id integer
 - game_id integer
 - last_game_date date
 - status_id integer
 - player text
 - pace numeric(8,4)
 - mp_48 numeric(6,4)
 - usg numeric(6,5)
 - pts_100 numeric(8,4)
 - ts numeric(6,5)
 - efg numeric(6,5)
 - fga_rim_100 numeric(8,4)
 - fga_mid_100 numeric(8,4)
 - fg2a_100 numeric(8,4)
 - fg3a_100 numeric(8,4)
 - fta_100 numeric(8,4)
 - rim_fg numeric(6,5)
 - mid_fg numeric(6,5)
 - fg2_pct numeric(6,5)
 - fg3_pct numeric(6,5)
 - ft_pct numeric(6,5)
 - ast_100 numeric(8,4)
 - tov_100 numeric(8,4)
 - oreb_100 numeric(8,4)
 - dreb_100 numeric(8,4)
 - stl_100 numeric(8,4)
 - blk_100 numeric(8,4)
 - oepm numeric(8,5)
 - depm numeric(8,5)
 - epm numeric(8,5)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - nba_game_id text default ('00'::text || (game_id)::text)
 - last_game_pred_mp numeric(8,5)
 - last_game_actual_mp numeric(8,5)
 - last_game_is_dnp boolean
 - last_game_dnp_category text

epm_team
 - game_date date primary key
 - team_id integer primary key
 - season integer
 - season_type integer
 - team_name text
 - team_market text
 - team_code text
 - team_record text
 - team_epm numeric(8,5)
 - team_oepm numeric(8,5)
 - team_depm numeric(8,5)
 - team_epm_rank integer
 - team_oepm_rank integer
 - team_depm_rank integer
 - team_epm_z numeric(6,4)
 - team_oepm_z numeric(6,4)
 - team_depm_z numeric(6,4)
 - team_epm_go numeric(8,5)
 - team_oepm_go numeric(8,5)
 - team_depm_go numeric(8,5)
 - team_epm_go_rank integer
 - team_oepm_go_rank integer
 - team_depm_go_rank integer
 - team_epm_go_z numeric(6,4)
 - team_oepm_go_z numeric(6,4)
 - team_depm_go_z numeric(6,4)
 - team_epm_smooth numeric(8,5)
 - team_oepm_smooth numeric(8,5)
 - team_depm_smooth numeric(8,5)
 - team_epm_smooth_rank integer
 - team_oepm_smooth_rank integer
 - team_depm_smooth_rank integer
 - team_epm_smooth_z numeric(6,4)
 - team_oepm_smooth_z numeric(6,4)
 - team_depm_smooth_z numeric(6,4)
 - team_epm_full numeric(8,5)
 - team_oepm_full numeric(8,5)
 - team_depm_full numeric(8,5)
 - team_epm_full_rank integer
 - team_oepm_full_rank integer
 - team_depm_full_rank integer
 - team_epm_full_z numeric(6,4)
 - team_oepm_full_z numeric(6,4)
 - team_depm_full_z numeric(6,4)
 - sos numeric(8,5)
 - sos_off numeric(8,5)
 - sos_def numeric(8,5)
 - sos_rank integer
 - sos_off_rank integer
 - sos_def_rank integer
 - sos_z numeric(6,4)
 - sos_off_z numeric(6,4)
 - sos_def_z numeric(6,4)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

pred_box
 - game_id integer primary key
 - nba_id integer primary key
 - team_id integer
 - player text
 - "position" text
 - height_inches integer
 - weight integer
 - pred_pace numeric(6,3)
 - pred_mp numeric(5,2)
 - pred_pts numeric(5,2)
 - pred_fg2m numeric(5,2)
 - pred_fg2a numeric(5,2)
 - pred_fg3m numeric(5,2)
 - pred_fg3a numeric(5,2)
 - pred_ftm numeric(5,2)
 - pred_fta numeric(5,2)
 - pred_oreb numeric(5,2)
 - pred_dreb numeric(5,2)
 - pred_reb numeric(5,2)
 - pred_ast numeric(5,2)
 - pred_tov numeric(5,2)
 - pred_stl numeric(5,2)
 - pred_blk numeric(5,2)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

pred_game
 - game_id integer primary key
 - season integer
 - season_type integer
 - game_date date
 - status_id integer
 - home_team_id integer
 - home_team_name text
 - home_name text
 - home_team_code text
 - home_score integer
 - home_rested integer
 - away_team_id integer
 - away_team_name text
 - away_name text
 - away_team_code text
 - away_score integer
 - away_rested integer
 - pred_home_score numeric(6,3)
 - pred_away_score numeric(6,3)
 - home_win_prob numeric(6,5)
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
```


### Views

_None_


### Functions

_None_


## kenpom

### Tables

```
archive
 - archive_date date primary key
 - season integer primary key
 - team_name text primary key
 - kp_team_id integer
 - preseason boolean default false
 - seed integer
 - event text
 - conf_short text
 - adj_em numeric
 - rank_adj_em integer
 - adj_oe numeric
 - rank_adj_oe integer
 - adj_de numeric
 - rank_adj_de integer
 - adj_tempo numeric
 - rank_adj_tempo integer
 - adj_em_final numeric
 - rank_adj_em_final integer
 - adj_oe_final numeric
 - rank_adj_oe_final integer
 - adj_de_final numeric
 - rank_adj_de_final integer
 - adj_tempo_final numeric
 - rank_adj_tempo_final integer
 - rank_change integer
 - adj_em_change numeric
 - adj_tempo_change numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

conf_stats
 - season integer primary key
 - team_name text primary key
 - kp_team_id integer
 - kp_conf_id integer
 - conf_short text
 - data_through text
 - adj_oe numeric
 - rank_adj_oe integer
 - adj_de numeric
 - rank_adj_de integer
 - oe numeric
 - rank_oe integer
 - de numeric
 - rank_de integer
 - adj_tempo numeric
 - rank_adj_tempo integer
 - tempo numeric
 - rank_tempo integer
 - efg_pct numeric
 - rank_efg_pct integer
 - tov_pct numeric
 - rank_tov_pct integer
 - oreb_pct numeric
 - rank_oreb_pct integer
 - ft_rate numeric
 - rank_ft_rate integer
 - def_efg_pct numeric
 - rank_def_efg_pct integer
 - def_tov_pct numeric
 - rank_def_tov_pct integer
 - def_oreb_pct numeric
 - rank_def_oreb_pct integer
 - def_ft_rate numeric
 - rank_def_ft_rate integer
 - off_dist_ft numeric
 - rank_off_dist_ft integer
 - off_dist_fg2 numeric
 - rank_off_dist_fg2 integer
 - off_dist_fg3 numeric
 - rank_off_dist_fg3 integer
 - def_dist_ft numeric
 - rank_def_dist_ft integer
 - def_dist_fg2 numeric
 - rank_def_dist_fg2 integer
 - def_dist_fg3 numeric
 - rank_def_dist_fg3 integer
 - fg3_pct numeric
 - rank_fg3_pct integer
 - fg2_pct numeric
 - rank_fg2_pct integer
 - ft_pct numeric
 - rank_ft_pct integer
 - fg3_rate numeric
 - rank_fg3_rate integer
 - block_pct numeric
 - rank_block_pct integer
 - steal_rate numeric
 - rank_steal_rate integer
 - nst_rate numeric
 - rank_nst_rate integer
 - assist_rate numeric
 - rank_assist_rate integer
 - opp_fg3_pct numeric
 - rank_opp_fg3_pct integer
 - opp_fg2_pct numeric
 - rank_opp_fg2_pct integer
 - opp_ft_pct numeric
 - rank_opp_ft_pct integer
 - opp_fg3_rate numeric
 - rank_opp_fg3_rate integer
 - opp_block_pct numeric
 - rank_opp_block_pct integer
 - opp_steal_rate numeric
 - rank_opp_steal_rate integer
 - opp_nst_rate numeric
 - rank_opp_nst_rate integer
 - opp_assist_rate numeric
 - rank_opp_assist_rate integer
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

conferences
 - season integer primary key
 - kp_conf_id integer primary key
 - conf_short text
 - conf_name text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

fanmatch
 - kp_game_id integer primary key
 - season integer
 - game_date date
 - visitor text
 - home text
 - visitor_team_id integer
 - home_team_id integer
 - visitor_rank integer
 - home_rank integer
 - visitor_pred numeric
 - home_pred numeric
 - home_win_prob numeric
 - pred_tempo numeric
 - thrill_score numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

team_stats
 - season integer primary key
 - team_name text primary key
 - kp_team_id integer
 - kp_conf_id integer
 - conf_short text
 - data_through text
 - seed integer
 - coach text
 - wins integer
 - losses integer
 - event text
 - adj_em numeric
 - rank_adj_em integer
 - adj_oe numeric
 - rank_adj_oe integer
 - adj_de numeric
 - rank_adj_de integer
 - oe numeric
 - rank_oe integer
 - de numeric
 - rank_de integer
 - tempo numeric
 - rank_tempo integer
 - adj_tempo numeric
 - rank_adj_tempo integer
 - pythag numeric
 - rank_pythag integer
 - luck numeric
 - rank_luck integer
 - sos numeric
 - rank_sos integer
 - sos_offense numeric
 - rank_sos_offense integer
 - sos_defense numeric
 - rank_sos_defense integer
 - nc_sos numeric
 - rank_nc_sos integer
 - apl_offense numeric
 - rank_apl_offense integer
 - apl_defense numeric
 - rank_apl_defense integer
 - conf_apl_offense numeric
 - rank_conf_apl_offense integer
 - conf_apl_defense numeric
 - rank_conf_apl_defense integer
 - efg_pct numeric
 - rank_efg_pct integer
 - tov_pct numeric
 - rank_tov_pct integer
 - oreb_pct numeric
 - rank_oreb_pct integer
 - ft_rate numeric
 - rank_ft_rate integer
 - def_efg_pct numeric
 - rank_def_efg_pct integer
 - def_tov_pct numeric
 - rank_def_tov_pct integer
 - def_oreb_pct numeric
 - rank_def_oreb_pct integer
 - def_ft_rate numeric
 - rank_def_ft_rate integer
 - off_dist_ft numeric
 - rank_off_dist_ft integer
 - off_dist_fg2 numeric
 - rank_off_dist_fg2 integer
 - off_dist_fg3 numeric
 - rank_off_dist_fg3 integer
 - def_dist_ft numeric
 - rank_def_dist_ft integer
 - def_dist_fg2 numeric
 - rank_def_dist_fg2 integer
 - def_dist_fg3 numeric
 - rank_def_dist_fg3 integer
 - avg_height numeric
 - avg_height_rank integer
 - height_eff numeric
 - height_eff_rank integer
 - height_pg numeric
 - height_pg_rank integer
 - height_sg numeric
 - height_sg_rank integer
 - height_sf numeric
 - height_sf_rank integer
 - height_pf numeric
 - height_pf_rank integer
 - height_c numeric
 - height_c_rank integer
 - experience numeric
 - experience_rank integer
 - bench numeric
 - bench_rank integer
 - continuity numeric
 - continuity_rank integer
 - fg3_pct numeric
 - rank_fg3_pct integer
 - fg2_pct numeric
 - rank_fg2_pct integer
 - ft_pct numeric
 - rank_ft_pct integer
 - fg3_rate numeric
 - rank_fg3_rate integer
 - block_pct numeric
 - rank_block_pct integer
 - steal_rate numeric
 - rank_steal_rate integer
 - nst_rate numeric
 - rank_nst_rate integer
 - assist_rate numeric
 - rank_assist_rate integer
 - opp_fg3_pct numeric
 - rank_opp_fg3_pct integer
 - opp_fg2_pct numeric
 - rank_opp_fg2_pct integer
 - opp_ft_pct numeric
 - rank_opp_ft_pct integer
 - opp_fg3_rate numeric
 - rank_opp_fg3_rate integer
 - opp_block_pct numeric
 - rank_opp_block_pct integer
 - opp_steal_rate numeric
 - rank_opp_steal_rate integer
 - opp_nst_rate numeric
 - rank_opp_nst_rate integer
 - opp_assist_rate numeric
 - rank_opp_assist_rate integer
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

teams
 - season integer primary key
 - kp_team_id integer primary key
 - team_name text
 - conf_short text
 - coach text
 - arena text
 - arena_city text
 - arena_state text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
```


### Views

_None_


### Functions

_None_


## noah

### Tables

```
kpis
 - kpi text primary key
 - display_name text
 - description text
 - category text default 'core'::text
 - value numeric
 - value_format text default 'number'::text
 - unit text
 - data jsonb default '{}'::jsonb
 - metadata jsonb default '{}'::jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

players
 - noah_id integer primary key
 - player_name text
 - first_name text
 - last_name text
 - number integer
 - height integer
 - email text
 - is_taggable integer
 - is_quick_add integer
 - is_private integer
 - pin integer
 - roster_group text
 - nba_id integer

shots
 - shot_id integer primary key
 - noah_id integer
 - guid text
 - has_gif integer
 - shot_date timestamp without time zone
 - created_at timestamp without time zone
 - made integer
 - angle numeric
 - depth numeric
 - left_right numeric
 - velocity numeric
 - peak_ball_height numeric
 - clean_make integer
 - classified integer
 - shot_type text
 - shot_type_id integer
 - shot_type_text text
 - ball_position_x numeric
 - ball_position_y numeric
 - noah_x numeric
 - noah_y numeric
 - shot_origin_x numeric
 - shot_origin_y numeric
 - shot_length numeric
 - is_swish integer
 - is_three integer
 - is_corner_three integer
 - is_free_throw integer
 - is_layup integer
 - is_bank_shot integer
 - hoop_id integer
 - constant_a numeric
 - constant_b numeric
 - constant_c numeric
 - session_info text
 - session_id text
```


### Views

```
dashboard
 - json_build_object json

total_shots
 - id text
 - shots bigint
```


### Functions

```
function api_dashboard() returns json
function distinct_players() returns integer
```


## pcms

### Tables

```
agencies
 - agency_id integer primary key
 - agency_name text
 - data jsonb
 - created_at timestamp with time zone default now()

agents
 - agent_id integer primary key
 - agent_name text
 - data jsonb
 - created_at timestamp with time zone default now()

apron
 - team_id integer primary key
 - team_code text
 - data jsonb
 - created_at timestamp with time zone default now()

apron_levels
 - apron_level text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

apron_reasons
 - apron_reason text primary key
 - description text
 - apron_level text
 - is_active integer
 - data jsonb
 - created_at timestamp with time zone default now()

award_types
 - award_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

bonus_types
 - bonus_type text primary key
 - description text
 - short_name text
 - is_active integer
 - data jsonb
 - created_at timestamp without time zone default now()

consent_types
 - consent_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp with time zone default now()

contract_caps
 - salary_cap text primary key
 - sign_method text
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

contract_exhibits
 - exhibit text primary key
 - description text
 - short_name text
 - exhibit_order integer
 - record_change timestamp without time zone
 - data jsonb
 - created_at timestamp without time zone default now()

contract_types
 - contract_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp with time zone default now()

contracts
 - contract_id integer primary key
 - data jsonb
 - created_at timestamp with time zone default now()

criteria
 - criteria text primary key
 - description text
 - short_name text
 - bonus_category text
 - criteria_type text
 - is_active integer
 - is_team_criteria integer
 - is_player_criteria integer
 - is_modifier integer
 - is_regular_season integer
 - is_post_season integer
 - data jsonb
 - created_at timestamp without time zone default now()

draft_pick_types
 - draft_pick_entry text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

option_decisions
 - option_decision text primary key
 - description text
 - short_name text
 - is_transaction integer
 - is_waive integer
 - is_active integer
 - data jsonb
 - created_at timestamp without time zone default now()

option_types
 - option_type text primary key
 - description text
 - short_name text
 - is_active integer
 - data jsonb
 - created_at timestamp without time zone default now()

payment_schedules
 - payment_schedule text primary key
 - description text
 - short_name text
 - is_active integer
 - data jsonb
 - created_at timestamp without time zone default now()

person_types
 - person_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

personnel
 - nba_id integer primary key
 - full_name text
 - first_name text
 - last_name text
 - league text
 - person_type text
 - team_id integer
 - team text
 - birthday text
 - hometown text
 - bio text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

player_consent
 - nba_id integer primary key
 - team_id integer primary key
 - season integer primary key
 - consent_type text
 - sign_date date
 - expiration_date date

player_status
 - player_status text primary key
 - description text
 - short_name text
 - is_active integer
 - is_active_list_type integer
 - is_on_roster integer
 - data jsonb
 - created_at timestamp without time zone default now()

players
 - nba_id integer primary key
 - player_name text
 - data jsonb
 - created_at timestamp with time zone default now()

playoff_types
 - playoff_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

protection_types
 - protection_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

record_status
 - record_status text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

report_parameters
 - report_parameter text primary key
 - description text
 - report_parameter_type text
 - data jsonb
 - created_at timestamp without time zone default now()

reports
 - report text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

roles
 - pcms_role text primary key
 - description text
 - data jsonb
 - created_at timestamp without time zone default now()

salary_cap
 - team_id integer primary key
 - team_code text
 - data jsonb
 - created_at timestamp with time zone default now()

salary_overrides
 - override text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

salary_scales
 - season integer primary key
 - years_of_service integer primary key
 - min_year_1 integer
 - min_year_2 integer
 - min_year_3 integer
 - min_year_4 integer
 - min_year_5 integer
 - data jsonb

sign_and_trade_types
 - sign_and_trade_type text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

sign_methods
 - sign_method text primary key
 - description text
 - short_name text
 - is_active smallint
 - is_sign smallint
 - is_trade smallint
 - is_team_exception smallint
 - data jsonb
 - created_at timestamp without time zone default now()

system
 - season integer primary key
 - cap_amount bigint
 - tax_level bigint
 - tax_apron_1 bigint
 - tax_apron_2 bigint
 - minimum_team_salary bigint
 - bi_annual integer
 - mid_level integer
 - taxpayer_mid_level integer
 - room_mid_level integer
 - max_salary_25 integer
 - max_salary_30 integer
 - max_salary_35 integer
 - average_salary integer
 - estimated_average_salary integer
 - two_way_salary integer
 - max_two_way_players integer
 - tax_bracket_amount integer
 - tpe_dollar_allowance integer
 - intl_payment integer
 - max_trade_cash_amount integer
 - poison_pill_growth_pct numeric
 - days_in_season integer
 - draft_date date
 - trade_deadline_date date
 - first_day_of_season date
 - last_day_of_season date
 - playing_start_date date
 - playing_end_date date
 - last_day_of_finals date
 - training_camp_end_date date
 - rookie_camp_end_date date
 - moratorium_end_date date
 - cut_down_date date
 - two_way_cut_down_date date
 - rnd_2_pick_exc_zero_cap_end_date date
 - exception_start_date date
 - exception_prorate_start_date date
 - no_aggregate_cutoff_date date
 - is_exceptions_added smallint
 - is_bonuses_finalized smallint
 - is_free_agent_amounts_finalized smallint
 - is_cap_projection smallint
 - data jsonb
 - created_at timestamp with time zone default now()

trade_attachment_types
 - attachment_type text primary key
 - description text
 - short_name text
 - view_function text
 - data jsonb
 - created_at timestamp without time zone default now()

trade_entries
 - trade_entry text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

trade_restrictions
 - trade_restriction text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp with time zone

trades
 - trade_id integer primary key
 - data jsonb
 - created_at timestamp with time zone default now()

transaction_descriptions
 - transaction_type text primary key
 - transaction_description text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()

transaction_types
 - transaction_type text primary key
 - description text
 - data jsonb
 - created_at timestamp without time zone default now()

transactions
 - transaction_id integer primary key
 - data jsonb
 - created_at timestamp with time zone default now()

two_way_status
 - two_way_status text primary key
 - description text
 - short_name text
 - data jsonb
 - created_at timestamp without time zone default now()
```


### Views

```
salary_cap_increases
 - season integer
 - cap_amount bigint
 - prior_year_cap_amount bigint
 - percentage_of_prior_year numeric
 - percentage_change numeric
```


### Functions

_None_


## pro_insight

### Tables

```
accounts
 - id text primary key
 - first_name text
 - last_name text
 - email text
 - contact_number text
 - last_login timestamp with time zone
 - org text
 - org_title text
 - league text
 - type text
 - member_type text
 - admin_type text
 - is_approved boolean default false
 - is_blocked boolean default false
 - online boolean
 - sub_start timestamp with time zone
 - sub_end timestamp with time zone
 - created_at timestamp with time zone
 - updated_at timestamp with time zone

background
 - player_id text primary key
 - player text default (data ->> 'title'::text)
 - personal jsonb default (data -> 'personal'::text)
 - recruitment jsonb default (data -> 'recruitment'::text)
 - team_history jsonb default (data -> 'team_history'::text)
 - buy_out jsonb default 
CASE
    WHEN (jsonb_typeof(((data -> 'buy_out_info'::text) -> 'terms'::text)) = 'array'::text) THEN
    CASE
        WHEN (jsonb_array_length(((data -> 'buy_out_info'::text) -> 'terms'::text)) > 0) THEN (data -> 'buy_out_info'::text)
        ELSE NULL::jsonb
    END
    ELSE NULL::jsonb
END
 - created_at timestamp without time zone
 - updated_at timestamp without time zone
 - data jsonb

players
 - player_id text primary key
 - player text default (data ->> 'full_name'::text)
 - "position" text default (data ->> 'position'::text)
 - height text default (data ->> 'height'::text)
 - weight integer default 
CASE
    WHEN ((data ->> 'weight_lbs'::text) IS NULL) THEN NULL::integer
    ELSE (regexp_replace((data ->> 'weight_lbs'::text), '[^0-9]'::text, ''::text, 'g'::text))::integer
END
 - birth_date text default (data ->> 'birth_date'::text)
 - age numeric(5,2)
 - hometown text default COALESCE((data ->> 'full_hometown'::text), (data ->> 'hometown'::text))
 - current_team text default (data ->> 'current_team'::text)
 - country text default (data ->> 'country_code'::text)
 - aau_team text default (data ->> 'aau_team_name'::text)
 - aau_brand text default (data ->> 'aau_affil'::text)
 - created_at timestamp without time zone
 - updated_at timestamp without time zone
 - data jsonb
 - background jsonb
 - personal jsonb default (background -> 'personal'::text)
 - recruitment jsonb default (background -> 'recruitment'::text)
 - team_history jsonb default (background -> 'team_history'::text)
 - buy_out jsonb default 
CASE
    WHEN ((jsonb_typeof(((background -> 'buy_out_info'::text) -> 'terms'::text)) = 'array'::text) AND (jsonb_array_length(((background -> 'buy_out_info'::text) -> 'terms'::text)) > 0)) THEN (background -> 'buy_out_info'::text)
    ELSE NULL::jsonb
END
 - mcdonalds integer

reports
 - id text primary key
 - player_id text default (data ->> 'player_id'::text)
 - title text default (data ->> 'title'::text)
 - report text default (data ->> 'report'::text)
 - report_type text default (data ->> 'type'::text)
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - data jsonb
```


### Views

_None_


### Functions

_None_


## public

### Tables

```
artificial_analysis
 - id text primary key
 - model text
 - slug text
 - creator_id text
 - creator_name text
 - creator_slug text
 - evaluations jsonb
 - pricing jsonb
 - median_output_tps numeric
 - median_first_token_seconds numeric
 - fetched_at timestamp with time zone default now()
 - release_date date

bref_team_codes
 - team_code text primary key
 - nba_team_code text
 - nba_team_id integer

bref_team_html
 - season integer primary key
 - season_code text
 - html text
 - bref_season integer

bref_team_stats
 - season integer primary key
 - team_code text primary key
 - nba_team_id integer
 - data jsonb
 - nba_team_code text

bri
 - season integer primary key
 - season_formatted text
 - revenue numeric
 - bri numeric
 - bri_pct_revenue numeric
 - total_salaries numeric
 - total_benefits numeric
 - total_salaries_and_benefits numeric
 - player_share numeric
 - player_share_pct numeric
 - total_salary_and_benefits_as_pct numeric
 - escrow_adjustment boolean
 - overage_shortfall numeric
 - notes text
 - revenue_local_media numeric
 - revenue_national_tv numeric
 - revenue_team_sponsorships numeric
 - revenue_seating_and_suites numeric
 - revenue_concessions_and_parking numeric
 - revenue_local_media_pct numeric
 - revenue_national_revenue_pct numeric
 - revenue_team_sponsorships_pct numeric
 - revenue_seating_and_suites_pct numeric
 - revenue_concessions_and_parking_pct numeric
 - tv_deal text
 - tv_deal_avg numeric
 - tv_deal_rolling_total numeric
 - tv_deal_year integer
 - tv_deal_partners jsonb
 - tv_deal_notes text
 - salary_cap bigint
 - salary_cap_pct_change numeric

cba
 - article_id integer primary key
 - article text
 - section_id integer primary key
 - section text
 - markdown text
 - simplified text
 - cap_machine text

crafted_historical
 - craft_id text primary key
 - nba_id integer
 - player text
 - season integer
 - team text
 - "position" text
 - age integer
 - is_rookie boolean default false
 - g integer
 - mp integer
 - mpg numeric
 - pts numeric
 - ast numeric
 - reb numeric
 - oreb numeric
 - dreb numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - pts_75 numeric
 - orb_75 numeric
 - drb_75 numeric
 - reb_75 numeric
 - ast_75 numeric
 - stl_75 numeric
 - blk_75 numeric
 - tov_75 numeric
 - fga_75 numeric
 - fg3a_75 numeric
 - fta_75 numeric
 - ts numeric
 - ts_rel numeric
 - fg3_rate numeric
 - fg3_rate_rel numeric
 - ft_rate numeric
 - tov_pct numeric
 - tov_pct_creation numeric
 - oreb_pct numeric
 - oreb_pct_rel numeric
 - dreb_pct numeric
 - dreb_pct_rel numeric
 - stl_pct numeric
 - blk_pct numeric
 - pf_rel numeric
 - crafted_pm numeric
 - crafted_opm numeric
 - crafted_dpm numeric
 - box_creation numeric
 - offensive_load numeric
 - passer_rating numeric
 - portability numeric
 - shot_quality numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

crafted_nba
 - season integer primary key
 - nba_id text primary key
 - player text
 - is_rookie boolean
 - slug text
 - age numeric
 - dob date
 - hometown text
 - region text
 - latitude numeric
 - longitude numeric
 - is_out_for_season boolean
 - team text
 - "position" text
 - position_combo text
 - position_group text
 - pg_pct numeric
 - sg_pct numeric
 - sf_pct numeric
 - pf_pct numeric
 - c_pct numeric
 - g integer
 - gs integer
 - mpg numeric
 - mp numeric
 - minutes_2yr numeric
 - minutes_2025 numeric
 - height numeric
 - wingspan numeric
 - weight numeric
 - length_diff numeric
 - size_grade text
 - pts numeric
 - ast numeric
 - reb numeric
 - oreb numeric
 - dreb numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - pf numeric
 - plus_minus numeric
 - pts_75 numeric
 - orb_75 numeric
 - drb_75 numeric
 - reb_75 numeric
 - ast_75 numeric
 - stl_75 numeric
 - blk_75 numeric
 - tov_75 numeric
 - fga_75 numeric
 - fg3a_75 numeric
 - fta_75 numeric
 - ts numeric
 - ts_rel numeric
 - fg3_rate numeric
 - fg3_rate_rel numeric
 - ft_rate numeric
 - usg numeric
 - tov_pct numeric
 - tov_pct_creation numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - oreb_pct_rel numeric
 - dreb_pct_rel numeric
 - stl_pct numeric
 - blk_pct numeric
 - pf_rel numeric
 - ws numeric
 - bpm numeric
 - obpm numeric
 - dbpm numeric
 - vorp numeric
 - lebron numeric
 - lebron_o numeric
 - lebron_d numeric
 - darko numeric
 - darko_o numeric
 - darko_d numeric
 - drip numeric
 - drip_o numeric
 - drip_d numeric
 - crafted_pm numeric
 - crafted_opm numeric
 - crafted_dpm numeric
 - crafted_pm_pctl numeric
 - crafted_opm_pctl numeric
 - crafted_dpm_pctl numeric
 - my_crafted_pm numeric
 - my_crafted_pm_pctl numeric
 - crafted_warp numeric
 - crafted_peak_pm numeric
 - proj_crafted_opm numeric
 - proj_crafted_dpm numeric
 - proj_crafted_pm numeric
 - proj_warp numeric
 - peak_war numeric
 - talent_level numeric
 - points_added numeric
 - box_creation numeric
 - offensive_load numeric
 - passer_rating numeric
 - passer_rating_added numeric
 - portability numeric
 - shot_quality numeric
 - touches numeric
 - passes_made numeric
 - passes_received numeric
 - play_handoff_freq numeric
 - play_cut_freq numeric
 - play_iso_freq numeric
 - play_pnr_ball_freq numeric
 - play_pnr_roll_freq numeric
 - play_post_freq numeric
 - play_offscreen_freq numeric
 - play_spotup_freq numeric
 - play_transition_freq numeric
 - play_putback_freq numeric
 - play_handoff_ppp numeric
 - play_cut_ppp numeric
 - play_iso_ppp numeric
 - play_pnr_ball_ppp numeric
 - play_pnr_roll_ppp numeric
 - play_post_ppp numeric
 - play_offscreen_ppp numeric
 - play_spotup_ppp numeric
 - play_transition_ppp numeric
 - play_putback_ppp numeric
 - def_vs_pg_pct numeric
 - def_vs_sg_pct numeric
 - def_vs_sf_pct numeric
 - def_vs_pf_pct numeric
 - def_vs_c_pct numeric
 - versatility_rating numeric
 - matchup_difficulty numeric
 - deflections numeric
 - ra_drb numeric
 - ra_orb numeric
 - ra_dtov numeric
 - role_offense_archetype text
 - role_offense_primary text
 - role_offense_secondary text
 - role_defense text
 - game_score_avg numeric
 - pct_great_game numeric
 - pct_good_game numeric
 - pct_fair_game numeric
 - pct_poor_game numeric
 - bball_iq numeric
 - value_a numeric
 - value_freq numeric
 - value_gr numeric
 - lineup_value numeric
 - team_dreb numeric
 - rim_freq numeric

delancey_place
 - id integer primary key
 - title text
 - body text
 - blog_date date
 - book_author text
 - book_title text
 - book_pages text
 - book_publisher text
 - book_date text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - tags text[] default '{}'::text[]
 - ai_last_score integer
 - ai_last_judged_at timestamp with time zone
 - ai_score_count integer default 0
 - ai_score_sum numeric default 0
 - ai_score_mean numeric default 
CASE
    WHEN (ai_score_count > 0) THEN round((ai_score_sum / (ai_score_count)::numeric), 2)
    ELSE NULL::numeric
END

documents
 - title text primary key
 - pages jsonb
 - notes text
 - tags jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

dx_mock_drafts
 - draft_year integer generated by default as identity primary key
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

dx_mock_snapshots
 - id serial primary key
 - draft_year integer
 - data jsonb
 - snapshot_date date default CURRENT_DATE
 - created_at timestamp with time zone default now()

dx_top_100
 - draft_year integer primary key
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

fanduel_draft
 - id serial
 - data jsonb
 - created_at timestamp with time zone default now()
 - draft integer

github
 - id serial primary key
 - repo text
 - file_path text
 - file_name text
 - code text
 - interesting integer[] default '{}'::integer[]
 - interesting_score numeric(10,2)
 - rough_draft text
 - revised_draft text
 - final_draft text
 - notes text
 - insights text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

github_data_grid
 - id serial primary key
 - repo text
 - insights text
 - rough_code text
 - revised_code text
 - notes text
 - rank_code jsonb
 - rank_code_avg numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

github_interesting
 - repo text primary key
 - interesting text
 - file_names text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone
 - glob_path text
 - repomix text
 - data_grid text
 - blurb text
 - tags jsonb

github_railway
 - repo text primary key
 - user_name text
 - repo_name text
 - url text
 - git_url text
 - file_name text primary key
 - content text
 - language text
 - branch text
 - watchers integer
 - stargazers integer
 - forks integer
 - open_issues integer
 - description text
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - pushed_at timestamp with time zone
 - archived boolean

gleague_schedule
 - season_id text primary key
 - year bigint
 - data jsonb
 - created_at timestamp with time zone

gm_to_nba
 - nba_id integer primary key
 - gm_id integer
 - notes text
 - created_at timestamp with time zone default now()

gm_trade_deadline_model
 - gm_id integer primary key
 - gm_player text
 - gm_team text
 - gm_age numeric
 - model numeric

gsoc
 - id serial primary key
 - source text
 - source_id text
 - title text
 - description text
 - category text
 - severity text
 - occurred_at timestamp with time zone
 - lat numeric
 - lon numeric
 - location text
 - url text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

kagi
 - search_term text primary key
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

nba_all_games
 - game_id text primary key
 - game_code text
 - game_date date
 - game_start_time timestamp with time zone
 - game_status_code integer
 - game_status_text text
 - season_id integer
 - season_year text
 - season_type text
 - year integer
 - away_id integer
 - away_team text
 - away_wins integer
 - away_losses integer
 - away_win_pct numeric
 - home_id integer
 - home_team text
 - home_wins integer
 - home_losses integer
 - home_win_pct numeric
 - score_away integer
 - score_home integer
 - score_diff integer
 - arena_name text
 - arena_city text
 - arena_state text
 - data jsonb

nba_arenas
 - arena_id bigint primary key
 - arena_name text
 - city text
 - state text
 - country text
 - timezone text
 - league_code text

nba_box
 - game_id text primary key
 - game_date date
 - season_id text
 - season integer
 - periods integer
 - attendance integer
 - away_id integer
 - away_team text
 - away_pts integer
 - away_plus_minus integer
 - away_minutes integer
 - away_fga integer
 - away_fgm integer
 - away_fg_pct numeric
 - away_fg3a integer
 - away_fg3m integer
 - away_fg3_pct numeric
 - away_fta integer
 - away_ftm integer
 - away_ft_pct numeric
 - away_dreb integer
 - away_oreb integer
 - away_reb integer
 - away_ast integer
 - away_ast_tov numeric
 - away_tov integer
 - away_stl integer
 - away_blk integer
 - away_blkd integer
 - away_fouls integer
 - away_fouls_drawn integer
 - away_fast_break_pts integer
 - away_in_paint_pts integer
 - away_second_chance_pts integer
 - away_bench_pts integer
 - away_biggest_lead integer
 - away_biggest_run integer
 - away_lead_changes integer
 - away_tied integer
 - away_pts_off_tov integer
 - away_reb_personal integer
 - away_reb_team integer
 - away_tov_team integer
 - away_tov_total integer
 - away_fg2a integer default 
CASE
    WHEN ((away_fga IS NULL) OR (away_fg3a IS NULL)) THEN NULL::integer
    ELSE (away_fga - away_fg3a)
END
 - away_fg2m integer default 
CASE
    WHEN ((away_fgm IS NULL) OR (away_fg3m IS NULL)) THEN NULL::integer
    ELSE (away_fgm - away_fg3m)
END
 - away_fg2_pct numeric default 
CASE
    WHEN ((away_fga - away_fg3a) = 0) THEN NULL::numeric
    ELSE round((((away_fgm - away_fg3m))::numeric / (NULLIF((away_fga - away_fg3a), 0))::numeric), 4)
END
 - away_efg numeric default 
CASE
    WHEN (away_fga = 0) THEN NULL::numeric
    ELSE round((((away_fgm)::numeric + (0.5 * (away_fg3m)::numeric)) / (away_fga)::numeric), 4)
END
 - away_ts numeric default 
CASE
    WHEN (((away_fga)::numeric + (0.44 * (away_fta)::numeric)) = (0)::numeric) THEN NULL::numeric
    ELSE round(((away_pts)::numeric / ((2)::numeric * ((away_fga)::numeric + (0.44 * (away_fta)::numeric)))), 4)
END
 - home_id integer
 - home_team text
 - home_pts integer
 - home_plus_minus integer
 - home_minutes integer
 - home_fga integer
 - home_fgm integer
 - home_fg_pct numeric
 - home_fg3a integer
 - home_fg3m integer
 - home_fg3_pct numeric
 - home_fta integer
 - home_ftm integer
 - home_ft_pct numeric
 - home_dreb integer
 - home_oreb integer
 - home_reb integer
 - home_ast integer
 - home_ast_tov numeric
 - home_tov integer
 - home_stl integer
 - home_blk integer
 - home_blkd integer
 - home_fouls integer
 - home_fouls_drawn integer
 - home_fast_break_pts integer
 - home_in_paint_pts integer
 - home_second_chance_pts integer
 - home_bench_pts integer
 - home_biggest_lead integer
 - home_biggest_run integer
 - home_lead_changes integer
 - home_tied integer
 - home_pts_off_tov integer
 - home_reb_personal integer
 - home_reb_team integer
 - home_tov_team integer
 - home_tov_total integer
 - home_fg2a integer default 
CASE
    WHEN ((home_fga IS NULL) OR (home_fg3a IS NULL)) THEN NULL::integer
    ELSE (home_fga - home_fg3a)
END
 - home_fg2m integer default 
CASE
    WHEN ((home_fgm IS NULL) OR (home_fg3m IS NULL)) THEN NULL::integer
    ELSE (home_fgm - home_fg3m)
END
 - home_fg2_pct numeric default 
CASE
    WHEN ((home_fga - home_fg3a) = 0) THEN NULL::numeric
    ELSE round((((home_fgm - home_fg3m))::numeric / (NULLIF((home_fga - home_fg3a), 0))::numeric), 4)
END
 - home_efg numeric default 
CASE
    WHEN (home_fga = 0) THEN NULL::numeric
    ELSE round((((home_fgm)::numeric + (0.5 * (home_fg3m)::numeric)) / (home_fga)::numeric), 4)
END
 - home_ts numeric default 
CASE
    WHEN (((home_fga)::numeric + (0.44 * (home_fta)::numeric)) = (0)::numeric) THEN NULL::numeric
    ELSE round(((home_pts)::numeric / ((2)::numeric * ((home_fga)::numeric + (0.44 * (home_fta)::numeric)))), 4)
END
 - officials jsonb
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - arena_id integer
 - arena_name text
 - is_sellout boolean
 - away_fg3_rate numeric
 - away_gfg numeric
 - home_fg3_rate numeric
 - home_gfg numeric
 - end_of_quarter jsonb
 - away_dnp jsonb
 - home_dnp jsonb

nba_box_advanced
 - game_id text primary key
 - game_date date
 - periods integer
 - attendance integer
 - away_id integer
 - away_team text
 - away_poss integer
 - away_ortg numeric
 - away_drtg numeric
 - away_net numeric
 - away_ast_tov numeric
 - away_ast_ratio numeric
 - away_ast_pct numeric
 - away_oreb_pct numeric
 - away_dreb_pct numeric
 - away_reb_pct numeric
 - away_tov_pct numeric
 - away_efg numeric
 - away_ts numeric
 - away_fast_break_pts integer
 - away_paint_pts integer
 - away_second_chance_pts integer
 - away_bench_pts integer
 - away_biggest_lead integer
 - away_biggest_run integer
 - away_lead_changes integer
 - away_tied integer
 - away_reb_total integer
 - away_pts_off_tov integer
 - home_id integer
 - home_team text
 - home_poss integer
 - home_ortg numeric
 - home_drtg numeric
 - home_net numeric
 - home_ast_tov numeric
 - home_ast_ratio numeric
 - home_ast_pct numeric
 - home_oreb_pct numeric
 - home_dreb_pct numeric
 - home_reb_pct numeric
 - home_tov_pct numeric
 - home_efg numeric
 - home_ts numeric
 - home_fast_break_pts integer
 - home_paint_pts integer
 - home_second_chance_pts integer
 - home_bench_pts integer
 - home_biggest_lead integer
 - home_biggest_run integer
 - home_lead_changes integer
 - home_tied integer
 - home_reb_total integer
 - home_pts_off_tov integer
 - data jsonb
 - season_id text
 - season integer
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_coach_assoc
 - id text primary key
 - nba_id integer
 - full_name text
 - biography text
 - experience text
 - data jsonb
 - created_at timestamp with time zone default CURRENT_TIMESTAMP
 - web_search text
 - claude_v3 text
 - bad_intel text
 - team text
 - "position" text
 - birthday date
 - hometown text
 - is_front_bench boolean
 - education jsonb
 - teams jsonb
 - updated_at timestamp with time zone default CURRENT_TIMESTAMP

nba_day_in_history
 - id integer primary key
 - date date
 - history date
 - content text
 - link text
 - is_timeless boolean
 - is_portland boolean
 - month_day text

nba_dev_team_stats
 - season text primary key default (data ->> 'season'::text)
 - season_id integer
 - team_id integer primary key default ((data ->> 'teamId'::text))::integer
 - team_code text default (data ->> 'teamAbbreviation'::text)
 - league_id text default (data ->> 'leagueId'::text)
 - season_type text default (data ->> 'seasonType'::text)
 - per_mode text primary key default (data ->> 'perMode'::text)
 - data jsonb
 - created_at timestamp with time zone default CURRENT_TIMESTAMP
 - updated_at timestamp with time zone

nba_dnp
 - game_id text primary key
 - game_date date
 - season_id text
 - season integer
 - team_id integer
 - team_code text
 - nba_id integer primary key
 - player text
 - first_name text
 - last_name text
 - jersey_num text
 - active_status text
 - dnp_reason text
 - dnp_description text
 - dnp_category text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - is_home boolean
 - is_away boolean

nba_games
 - game_id text primary key
 - season_id text
 - season integer
 - game_date date
 - game_date_est timestamp with time zone
 - game_duration_seconds integer
 - is_regular_season boolean
 - is_postseason boolean
 - game_type text
 - game_code text
 - game_sequence integer
 - game_label text
 - game_sublabel text
 - game_subtype text
 - game_status integer
 - game_status_text text
 - postponed_status text
 - away_id integer
 - away_city text
 - away_name text
 - away_team text
 - away_wins integer
 - away_losses integer
 - away_seed integer
 - home_id integer
 - home_city text
 - home_name text
 - home_team text
 - home_wins integer
 - home_losses integer
 - home_seed integer
 - score_away integer
 - score_home integer
 - winner_id integer
 - winner text
 - is_home_winner boolean
 - arena_name text
 - arena_city text
 - arena_state text
 - is_neutral_site boolean
 - series_text text
 - series_conference text
 - series_game_number text
 - if_necessary boolean
 - broadcasters jsonb
 - points_leaders jsonb
 - game_date_utc timestamp with time zone
 - game_start_actual timestamp with time zone
 - game_end_actual timestamp with time zone
 - day_of_week text
 - month_num integer
 - week_number integer
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_injury_snapshots
 - snapshot_id bigint generated by default as identity primary key
 - created_at timestamp with time zone default now()
 - data jsonb
 - success boolean
 - error_details text

nba_live_stats
 - game_id text primary key
 - segment text primary key default 'FULL'::text
 - game_date date
 - game_start_time timestamp with time zone
 - game_code text
 - status text
 - periods integer
 - clock text
 - home_id integer
 - home_code text
 - home_score integer
 - away_id integer
 - away_code text
 - away_score integer
 - home_poss integer
 - home_pts integer
 - home_ortg numeric
 - home_drtg numeric
 - home_net numeric
 - away_poss integer
 - away_pts integer
 - away_ortg numeric
 - away_drtg numeric
 - away_net numeric
 - home_fg2a integer
 - home_fg2m integer
 - home_fg2_pct numeric
 - home_fg3a integer
 - home_fg3m integer
 - home_fg3_pct numeric
 - home_fg3a_rate numeric
 - home_fta integer
 - home_ftm integer
 - home_ft_pct numeric
 - home_ftr numeric
 - home_rim_att integer
 - home_rim_made integer
 - home_rim_pct numeric
 - home_floater_att integer
 - home_floater_made integer
 - home_floater_pct numeric
 - home_mid_att integer
 - home_mid_made integer
 - home_mid_pct numeric
 - home_corner_att integer
 - home_corner_made integer
 - home_corner_pct numeric
 - home_arc_att integer
 - home_arc_made integer
 - home_arc_pct numeric
 - home_rim_rate numeric
 - home_floater_rate numeric
 - home_mid_rate numeric
 - home_corner_rate numeric
 - home_arc_rate numeric
 - away_fg2a integer
 - away_fg2m integer
 - away_fg2_pct numeric
 - away_fg3a integer
 - away_fg3m integer
 - away_fg3_pct numeric
 - away_fg3a_rate numeric
 - away_fta integer
 - away_ftm integer
 - away_ft_pct numeric
 - away_ftr numeric
 - away_rim_att integer
 - away_rim_made integer
 - away_rim_pct numeric
 - away_floater_att integer
 - away_floater_made integer
 - away_floater_pct numeric
 - away_mid_att integer
 - away_mid_made integer
 - away_mid_pct numeric
 - away_corner_att integer
 - away_corner_made integer
 - away_corner_pct numeric
 - away_arc_att integer
 - away_arc_made integer
 - away_arc_pct numeric
 - away_rim_rate numeric
 - away_floater_rate numeric
 - away_mid_rate numeric
 - away_corner_rate numeric
 - away_arc_rate numeric
 - home_transition_poss integer
 - home_transition_pts integer
 - home_transition_tov integer
 - home_second_chance_pts integer
 - home_oreb integer
 - home_dreb integer
 - home_fg3_oreb_opps integer
 - home_fg3_oreb integer
 - home_tov integer
 - home_tov_pct numeric
 - away_transition_poss integer
 - away_transition_pts integer
 - away_transition_tov integer
 - away_second_chance_pts integer
 - away_oreb integer
 - away_dreb integer
 - away_fg3_oreb_opps integer
 - away_fg3_oreb integer
 - away_tov integer
 - away_tov_pct numeric
 - home_kills_3 integer
 - home_kills_4 integer
 - home_kills_5 integer
 - home_kills_6 integer
 - home_kills_7 integer
 - home_kills_8_plus integer
 - home_kills_delta integer
 - home_kills_pi integer
 - away_kills_3 integer
 - away_kills_4 integer
 - away_kills_5 integer
 - away_kills_6 integer
 - away_kills_7 integer
 - away_kills_8_plus integer
 - away_kills_delta integer
 - away_kills_pi integer
 - pace_poss_per_minute numeric
 - pace_poss_per_48 numeric
 - pace_fastbreak_rate numeric
 - pace_avg_poss_seconds numeric
 - home_runs_count integer
 - away_runs_count integer
 - home_biggest_run_net integer
 - away_biggest_run_net integer
 - runs jsonb
 - runs_with_timeout jsonb
 - is_clutch boolean
 - clutch_start_clock text
 - home_clutch_poss integer
 - home_clutch_pts integer
 - home_clutch_fgm integer
 - home_clutch_fga integer
 - home_clutch_tov integer
 - home_clutch_ortg numeric
 - home_clutch_shots integer
 - home_clutch_stops integer
 - away_clutch_poss integer
 - away_clutch_pts integer
 - away_clutch_fgm integer
 - away_clutch_fga integer
 - away_clutch_tov integer
 - away_clutch_ortg numeric
 - away_clutch_shots integer
 - away_clutch_stops integer
 - clutch_player_onoff jsonb
 - lead_changes integer
 - times_tied integer
 - times_tied_minutes numeric
 - home_largest_lead_pts integer
 - home_largest_lead_clock text
 - home_largest_lead_period integer
 - home_time_leading numeric
 - away_largest_lead_pts integer
 - away_largest_lead_clock text
 - away_largest_lead_period integer
 - away_time_leading numeric
 - lead_history jsonb
 - home_starter_pts integer
 - home_bench_pts integer
 - home_starter_minutes numeric
 - home_bench_minutes numeric
 - home_starter_net numeric
 - home_bench_net numeric
 - away_starter_pts integer
 - away_bench_pts integer
 - away_starter_minutes numeric
 - away_bench_minutes numeric
 - away_starter_net numeric
 - away_bench_net numeric
 - lineup_stints jsonb
 - player_minutes jsonb
 - player_onoff jsonb
 - rotation_patterns jsonb
 - officials jsonb
 - timeouts jsonb
 - validation jsonb
 - league_id text
 - season_id text
 - season integer
 - season_formatted text
 - season_type text
 - arena_name text
 - arena_city text
 - arena_state text
 - home_wins integer
 - home_losses integer
 - home_win_pct numeric
 - away_wins integer
 - away_losses integer
 - away_win_pct numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_media_guide_staff
 - season integer primary key
 - team_code text primary key
 - raw_text text
 - staff jsonb
 - coaches jsonb
 - created_at timestamp with time zone default now()
 - is_alphabetical smallint

nba_media_guides
 - season integer primary key
 - team text primary key
 - url text
 - markdown text
 - biographies jsonb
 - coaches jsonb
 - created_at timestamp with time zone default now()

nba_on_court
 - game_id text primary key
 - data jsonb

nba_pbp
 - game_id text primary key
 - data jsonb

nba_personnel
 - nba_id integer primary key
 - full_name text
 - first_name text
 - last_name text
 - league text
 - person_type text
 - team_id integer
 - team text
 - birthday text
 - hometown text
 - bio text
 - data jsonb
 - created_at timestamp with time zone
 - updated_at timestamp with time zone
 - wikipedia jsonb
 - on_roster jsonb
 - recent_season integer

nba_personnel_games
 - game_id text primary key
 - game_date date
 - away_team text
 - home_team text
 - away_coaches jsonb
 - home_coaches jsonb
 - away_players jsonb
 - home_players jsonb
 - away_possessions integer
 - away_ortg numeric
 - away_drtg numeric
 - away_net numeric
 - away_ast_to numeric
 - away_ast_ratio numeric
 - away_ast_pct numeric
 - away_oreb_pct numeric
 - away_dreb_pct numeric
 - away_reb_pct numeric
 - away_tov_pct numeric
 - away_efg numeric
 - away_ts numeric
 - away_fast_break_pts integer
 - away_paint_pts integer
 - away_second_chance_pts integer
 - away_bench_pts integer
 - away_pts_off_tov integer
 - away_max_lead integer
 - home_possessions integer
 - home_ortg numeric
 - home_drtg numeric
 - home_net numeric
 - home_ast_to numeric
 - home_ast_ratio numeric
 - home_ast_pct numeric
 - home_oreb_pct numeric
 - home_dreb_pct numeric
 - home_reb_pct numeric
 - home_tov_pct numeric
 - home_efg numeric
 - home_ts numeric
 - home_fast_break_pts integer
 - home_paint_pts integer
 - home_second_chance_pts integer
 - home_bench_pts integer
 - home_pts_off_tov integer
 - home_max_lead integer
 - periods integer
 - attendance integer
 - away_team_score integer
 - home_team_score integer
 - actual_total_score numeric
 - game_over_under numeric
 - favorite text
 - away_team_line numeric
 - home_team_line numeric
 - vegas_line numeric
 - absolute_spread numeric
 - over_hit smallint
 - under_hit smallint
 - favorite_covered smallint
 - underdog_covered smallint
 - away_team_won smallint
 - home_team_won smallint
 - away_implied_total numeric
 - home_implied_total numeric
 - actual_margin integer
 - away_cover_margin numeric
 - home_cover_margin numeric
 - total_over_under_margin numeric
 - away_over_under_margin numeric
 - home_over_under_margin numeric

nba_personnel_metrics
 - metric text primary key default (data ->> 'metric'::text)
 - model_r2 numeric default ((data ->> 'model_r2'::text))::numeric
 - half_life numeric primary key default (((data -> 'parameters'::text) ->> 'half_life'::text))::numeric
 - data jsonb
 - created_at timestamp with time zone default CURRENT_TIMESTAMP
 - updated_at timestamp with time zone

nba_personnel_metrics_v2
 - metric text primary key default (data ->> 'metric'::text)
 - model_r2 numeric default ((data ->> 'model_r2'::text))::numeric
 - half_life numeric primary key default (((data -> 'parameters'::text) ->> 'half_life'::text))::numeric
 - data jsonb
 - created_at timestamp with time zone default CURRENT_TIMESTAMP
 - updated_at timestamp with time zone

nba_player_minutes
 - nba_id integer
 - season integer
 - player_name text
 - minutes integer

nba_players
 - nba_id integer primary key
 - full_name text
 - first_name text
 - last_name text
 - initials text
 - dob date
 - age numeric
 - height numeric
 - height_formatted text
 - weight integer
 - primary_position text
 - yos integer
 - draft_year integer
 - draft_pick integer
 - draft_round integer
 - draft_team_id integer
 - is_early_entry boolean
 - is_two_way boolean
 - school_id integer
 - school_name text
 - roster_name text
 - stats_name text
 - player_status text
 - record_status text
 - gm_id integer
 - blitz_id text
 - hp_id integer
 - roto_id integer
 - sr_id text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - ctg_id integer
 - ctg_pro_id text

nba_preseason_odds
 - season integer primary key
 - season_code text
 - team_code text primary key
 - team_name text
 - odds integer
 - over_under numeric
 - wins integer
 - losses integer
 - wins_82 numeric
 - losses_82 numeric
 - is_over boolean
 - is_under boolean
 - bucket text
 - source_url text
 - implied_prob numeric
 - market_share numeric

nba_rapm_current
 - nba_id integer primary key
 - "position" text
 - player text
 - team text
 - rapm_darko numeric
 - rapm_rank_darko numeric
 - rapm_rank_timedecay numeric
 - rapm_timedecay numeric
 - orapm_darko numeric
 - orapm_rank_darko numeric
 - orapm_rank_timedecay numeric
 - orapm_timedecay numeric
 - drapm_darko numeric
 - drapm_rank_darko numeric
 - drapm_rank_timedecay numeric
 - drapm_timedecay numeric
 - two_year_rapm numeric
 - two_year_rapm_rank numeric
 - two_year_orapm numeric
 - two_year_orapm_rank numeric
 - two_year_drapm numeric
 - two_year_drapm_rank numeric
 - three_year_rapm numeric
 - three_year_rapm_rank numeric
 - three_year_orapm numeric
 - three_year_orapm_rank numeric
 - three_year_drapm numeric
 - three_year_drapm_rank numeric
 - four_year_rapm numeric
 - four_year_rapm_rank numeric
 - four_year_orapm numeric
 - four_year_orapm_rank numeric
 - four_year_drapm numeric
 - four_year_drapm_rank numeric
 - five_year_rapm numeric
 - five_year_rapm_rank numeric
 - five_year_orapm numeric
 - five_year_orapm_rank numeric
 - five_year_drapm numeric
 - five_year_drapm_rank numeric

nba_raptor
 - raptor_id text primary key
 - nba_id integer
 - season integer primary key
 - player text
 - "position" text
 - mp integer
 - poss integer
 - raptor numeric
 - raptor_pctl numeric
 - raptor_rank numeric
 - raptor_offense numeric
 - raptor_offense_pctl numeric
 - raptor_offense_rank numeric
 - raptor_defense numeric
 - raptor_defense_pctl numeric
 - raptor_defense_rank numeric
 - war numeric
 - war_pctl numeric
 - war_rank numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_referees
 - referee text primary key
 - write_up text
 - favorite text
 - games integer
 - experience integer
 - photo text
 - pronunciation text
 - nba_id integer
 - nbra_data jsonb
 - is_active smallint default 0
 - actual_game_count integer

nba_roster_lineups
 - game_id text primary key
 - data jsonb
 - created_at timestamp with time zone default now()

nba_rosters
 - season integer primary key
 - season_id integer
 - team_id integer primary key
 - team_code text
 - players jsonb
 - coaches jsonb
 - created_at timestamp with time zone

nba_schedule
 - season_id text primary key
 - year bigint
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_season_types
 - season_id text primary key
 - season_name text
 - season_type text
 - year bigint
 - league_code text

nba_staff
 - season integer primary key
 - season_formatted text
 - team_code text
 - team text primary key
 - full_name text primary key
 - first_name text
 - last_name text
 - title text primary key
 - email text
 - mobile_phone text
 - office_phone text

nba_standings
 - season_id text primary key
 - team_id integer primary key
 - year integer
 - team text
 - team_city text
 - team_name text
 - team_slug text
 - conference text
 - division text
 - league_rank integer
 - division_rank integer
 - conference_games_back numeric
 - division_games_back numeric
 - league_games_back numeric
 - playoff_rank integer
 - playoff_seeding integer
 - sort_order integer
 - clinched_conference integer
 - clinched_division integer
 - clinched_playoffs integer
 - clinched_play_in integer
 - eliminated_conference integer
 - eliminated_division integer
 - eliminated_playoffs integer
 - wins integer
 - losses integer
 - win_pct numeric
 - record text
 - conference_record text
 - division_record text
 - home text
 - road text
 - neutral text
 - current_streak integer
 - current_streak_text text
 - long_loss_streak integer
 - long_win_streak integer
 - current_home_streak integer
 - current_home_streak_text text
 - long_home_streak integer
 - long_home_streak_text text
 - current_road_streak integer
 - current_road_streak_text text
 - long_road_streak integer
 - long_road_streak_text text
 - points_pg numeric
 - opp_points_pg numeric
 - diff_pts_pg numeric
 - oct text
 - nov text
 - "dec" text
 - jan text
 - feb text
 - mar text
 - apr text
 - may text
 - jun text
 - jul text
 - aug text
 - sep text
 - vs_east text
 - vs_west text
 - vs_atlantic text
 - vs_central text
 - vs_northwest text
 - vs_pacific text
 - vs_southeast text
 - vs_southwest text
 - ahead_at_half text
 - behind_at_half text
 - tied_at_half text
 - ahead_at_third text
 - behind_at_third text
 - tied_at_third text
 - fewer_turnovers text
 - lead_in_fg_pct text
 - lead_in_reb text
 - last_10 text
 - last_10_home text
 - last_10_road text
 - opp_over_500 text
 - opp_score_100_pts text
 - score_100_pts text
 - ten_pts_or_more text
 - three_pts_or_less text
 - eliminated_postseason integer
 - clinch_indicator text
 - created_at timestamp without time zone

nba_team_colors
 - team_id integer primary key
 - team_code text
 - established integer
 - primary_color text
 - secondary_color text

nba_team_staff
 - season integer primary key
 - season_formatted text
 - team_code text
 - team text primary key
 - full_name text primary key
 - first_name text
 - last_name text
 - title text primary key
 - email text
 - mobile_phone text
 - office_phone text
 - nba_id integer
 - dob date
 - background text
 - hometown text
 - notes text
 - tags jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_teams
 - team_id integer primary key
 - team_code text
 - team_city text
 - team_mascot text
 - is_nba smallint

nba_tidbits
 - id integer primary key
 - date date
 - content text
 - link text
 - description text

nba_trade_deadline_dates
 - season_id text primary key
 - season integer
 - trade_deadline date

ncaa_247sports
 - id integer primary key
 - post_date timestamp with time zone
 - title text
 - summary text
 - content text
 - slug text
 - slack_channel text
 - slack_message text
 - slack_at timestamp with time zone
 - vip boolean
 - author text
 - author_url text
 - logo_url text
 - alternate_logo_url text
 - image_url text
 - asset_key integer
 - sport text
 - sport_key integer
 - label text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

ncaa_rivals_news
 - id integer primary key
 - post_date timestamp with time zone
 - title text
 - summary text
 - content text
 - slack_channel text
 - slack_message text
 - slack_at timestamp with time zone
 - slug text
 - full_url text
 - author text
 - featured_image text
 - primary_category text
 - modified_date timestamp with time zone
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

ncaa_watchlist
 - player_id text primary key
 - full_name text
 - "position" text
 - dob date
 - active boolean default true
 - gm_id integer
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

ngss_boxscores
 - game_id text primary key
 - game_date date
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - data jsonb

ngss_challenges
 - season_id text
 - game_id text primary key
 - team_id integer
 - team_code text
 - period integer
 - score_away integer
 - score_home integer
 - sub_type text
 - action_type text
 - success integer
 - descriptor text
 - description text
 - challenge_note text
 - order_number integer
 - action_number integer primary key
 - previous_action integer
 - period_number integer
 - period_type text
 - clock text
 - shot_clock text
 - time_actual timestamp without time zone
 - edited timestamp without time zone
 - is_target_score_last_period boolean
 - x double precision
 - y double precision
 - possession integer
 - value text
 - qualifiers jsonb

ngss_pbp
 - game_id text primary key
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - data jsonb

ngss_persons
 - season_id text primary key
 - year bigint
 - data jsonb
 - created_at timestamp with time zone default now()

ngss_standings
 - league_code text primary key
 - season_id text primary key
 - team_id integer primary key
 - team_name text
 - team_city text
 - team_tricode text
 - division text
 - conference text
 - team_status text
 - timezone text
 - games integer
 - wins integer
 - losses integer
 - games_behind numeric
 - conference_wins integer
 - conference_losses integer
 - conference_rank integer
 - conference_games_behind numeric
 - division_wins integer
 - division_losses integer
 - home_wins integer
 - home_losses integer
 - road_wins integer
 - road_losses integer
 - last10_wins integer
 - last10_losses integer
 - streak integer
 - league_rank integer
 - division_rank integer
 - created_at timestamp with time zone default now()

ngss_teams
 - team_id integer primary key
 - team_code text
 - team_city text
 - team_mascot text
 - is_nba smallint default 0
 - is_gleague smallint default 0

nightly_emails
 - email text primary key
 - name text
 - tags jsonb default '[]'::jsonb
 - notes text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

pcms_contracts
 - contract_id bigint generated by default as identity primary key
 - nba_id bigint
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

pcms_player_data
 - nba_id bigint generated by default as identity primary key
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

postgame_players
 - game_id text primary key
 - game_date date
 - nba_id text primary key
 - player text
 - team_id integer
 - team text
 - opp_team_id integer
 - opp text
 - is_away boolean
 - is_home boolean
 - season integer
 - season_type text
 - periods integer
 - starter boolean
 - played boolean
 - dnp text
 - seconds integer
 - minutes integer
 - minutes_formatted text
 - "position" text
 - rotation text
 - fgm integer
 - fga integer
 - fg2m integer
 - fg2a integer
 - fg3m integer
 - fg3a integer
 - ftm integer
 - fta integer
 - reb integer
 - oreb integer
 - dreb integer
 - ast integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - pts integer
 - plus_minus integer
 - efg numeric
 - ts numeric
 - ft_fga numeric
 - ppp numeric
 - usage numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - reb_pct numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - poss numeric
 - fic numeric
 - fgm_ptile numeric
 - fga_ptile numeric
 - fg2m_ptile numeric
 - fg2a_ptile numeric
 - fg3m_ptile numeric
 - fg3a_ptile numeric
 - ftm_ptile numeric
 - fta_ptile numeric
 - reb_ptile numeric
 - oreb_ptile numeric
 - dreb_ptile numeric
 - ast_ptile numeric
 - stl_ptile numeric
 - blk_ptile numeric
 - tov_ptile numeric
 - pf_ptile numeric
 - pts_ptile numeric
 - plus_minus_ptile numeric
 - efg_ptile numeric
 - ts_ptile numeric
 - ft_fga_ptile numeric
 - ppp_ptile numeric
 - usage_ptile numeric
 - ast_pct_ptile numeric
 - tov_pct_ptile numeric
 - stl_pct_ptile numeric
 - blk_pct_ptile numeric
 - reb_pct_ptile numeric
 - oreb_pct_ptile numeric
 - dreb_pct_ptile numeric
 - poss_ptile numeric
 - fic_ptile numeric
 - seconds_ptile numeric
 - minutes_ptile numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

postgame_teams
 - game_id text primary key
 - game_date date
 - team_id integer primary key
 - team text
 - opp_team_id integer
 - opp text
 - season integer
 - season_type text
 - periods integer
 - is_away boolean
 - is_home boolean
 - fgm integer
 - fga integer
 - fg2m integer
 - fg2a integer
 - fg3m integer
 - fg3a integer
 - ftm integer
 - fta integer
 - reb integer
 - oreb integer
 - dreb integer
 - ast integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - pts integer
 - plus_minus integer
 - fast_break_pts integer
 - paint_pts integer
 - second_chance_pts integer
 - pts_off_tov integer
 - bench_pts integer
 - efg numeric
 - tov_pct numeric
 - oreb_pct numeric
 - ft_fga numeric
 - poss numeric
 - ppp numeric
 - ts numeric
 - q1_pts integer
 - q2_pts integer
 - q3_pts integer
 - q4_pts integer
 - ot_pts integer
 - ot2_pts integer
 - fgm_ptile numeric
 - fga_ptile numeric
 - fg2m_ptile numeric
 - fg2a_ptile numeric
 - fg3m_ptile numeric
 - fg3a_ptile numeric
 - ftm_ptile numeric
 - fta_ptile numeric
 - reb_ptile numeric
 - oreb_ptile numeric
 - dreb_ptile numeric
 - ast_ptile numeric
 - stl_ptile numeric
 - blk_ptile numeric
 - tov_ptile numeric
 - pf_ptile numeric
 - pts_ptile numeric
 - plus_minus_ptile numeric
 - fast_break_pts_ptile numeric
 - paint_pts_ptile numeric
 - second_chance_pts_ptile numeric
 - pts_off_tov_ptile numeric
 - bench_pts_ptile numeric
 - efg_ptile numeric
 - tov_pct_ptile numeric
 - oreb_pct_ptile numeric
 - ft_fga_ptile numeric
 - poss_ptile numeric
 - ppp_ptile numeric
 - ts_ptile numeric
 - q1_pts_ptile numeric
 - q2_pts_ptile numeric
 - q3_pts_ptile numeric
 - q4_pts_ptile numeric
 - ot_pts_ptile numeric
 - ot2_pts_ptile numeric
 - opp_fgm integer
 - opp_fga integer
 - opp_fg2m integer
 - opp_fg2a integer
 - opp_fg3m integer
 - opp_fg3a integer
 - opp_ftm integer
 - opp_fta integer
 - opp_oreb integer
 - opp_dreb integer
 - opp_reb integer
 - opp_ast integer
 - opp_stl integer
 - opp_blk integer
 - opp_tov integer
 - opp_pf integer
 - opp_pts integer
 - opp_fast_break_pts integer
 - opp_paint_pts integer
 - opp_second_chance_pts integer
 - opp_pts_off_tov integer
 - opp_bench_pts integer
 - opp_efg numeric
 - opp_tov_pct numeric
 - opp_oreb_pct numeric
 - opp_ft_fga numeric
 - opp_poss numeric
 - opp_ppp numeric
 - opp_ts numeric
 - opp_q1_pts integer
 - opp_q2_pts integer
 - opp_q3_pts integer
 - opp_q4_pts integer
 - opp_ot_pts integer
 - opp_ot2_pts integer
 - opp_fgm_ptile numeric
 - opp_fga_ptile numeric
 - opp_fg2m_ptile numeric
 - opp_fg2a_ptile numeric
 - opp_fg3m_ptile numeric
 - opp_fg3a_ptile numeric
 - opp_ftm_ptile numeric
 - opp_fta_ptile numeric
 - opp_oreb_ptile numeric
 - opp_dreb_ptile numeric
 - opp_reb_ptile numeric
 - opp_ast_ptile numeric
 - opp_stl_ptile numeric
 - opp_blk_ptile numeric
 - opp_tov_ptile numeric
 - opp_pf_ptile numeric
 - opp_pts_ptile numeric
 - opp_fast_break_pts_ptile numeric
 - opp_paint_pts_ptile numeric
 - opp_second_chance_pts_ptile numeric
 - opp_pts_off_tov_ptile numeric
 - opp_bench_pts_ptile numeric
 - opp_efg_ptile numeric
 - opp_tov_pct_ptile numeric
 - opp_oreb_pct_ptile numeric
 - opp_ft_fga_ptile numeric
 - opp_poss_ptile numeric
 - opp_ppp_ptile numeric
 - opp_ts_ptile numeric
 - opp_q1_pts_ptile numeric
 - opp_q2_pts_ptile numeric
 - opp_q3_pts_ptile numeric
 - opp_q4_pts_ptile numeric
 - opp_ot_pts_ptile numeric
 - opp_ot2_pts_ptile numeric
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

s2
 - gm_id integer
 - s2_id integer primary key
 - report_date date primary key
 - report_time time without time zone
 - full_name text
 - score integer
 - perception_speed integer
 - search_efficiency integer
 - tracking_capacity integer
 - spatial_awareness integer
 - decision_complexity integer
 - instinctive_learning integer
 - impulse_control integer
 - distraction_control integer
 - improvisation integer
 - reaction_speed integer
 - reaction_accuracy integer
 - draft integer

sportradar_nba_injuries
 - game_date date primary key
 - season integer
 - season_id integer
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

sports_jobs
 - id serial primary key
 - role text
 - sport text
 - company text
 - discipline text
 - apply_url text
 - date_listed date
 - created_at timestamp with time zone default now()

spotrac_transactions
 - id text primary key
 - spotrac_id integer
 - full_name text
 - "position" text
 - team text
 - date date
 - description text
 - created_at timestamp with time zone default now()
 - slack_message text
 - slack_at timestamp with time zone
 - action text
 - slack_channel text

youtube
 - youtube_id text primary key
 - upload_date date
 - channel text
 - title text
 - duration bigint
 - view_count bigint
 - description text
 - transcript text
 - slack_message text
 - transcript_tldr text
 - data jsonb
 - created_at timestamp with time zone default now()
 - slack_channel text
 - slack_at timestamp without time zone
 - do_not_scrape boolean
 - is_revised boolean

youtube_channels
 - channel text primary key
 - url text
 - notes text
 - tags jsonb
 - created_at timestamp with time zone default now()
```


### Views

```
bball_index_stats
 - player_name text
 - season_formatted text
 - rotation text
 - offense_role text
 - defense_role text
 - lebron numeric
 - o_lebron numeric
 - d_lebron numeric
 - rapm numeric
 - o_rapm numeric
 - d_rapm numeric

bert_challenges
 - team_code text
 - games_played integer
 - total_challenges bigint
 - total_challenges_rank bigint
 - challenges_per_game numeric
 - challenges_per_game_rank bigint
 - successful_challenges bigint
 - successful_per_game numeric
 - successful_per_game_rank bigint
 - success_percentage numeric
 - success_rate_rank bigint

bert_challenges_log
 - game_id text
 - team_id integer
 - team_code text
 - period integer
 - score_away integer
 - score_home integer
 - sub_type text
 - action_type text
 - success integer
 - descriptor text
 - description text
 - challenge_note text
 - order_number integer
 - action_number integer
 - previous_action integer
 - period_number integer
 - period_type text
 - clock text
 - shot_clock text
 - time_actual timestamp without time zone
 - edited timestamp without time zone
 - is_target_score_last_period boolean
 - x double precision
 - y double precision
 - possession integer
 - value text
 - qualifiers jsonb

dx_2025
 - pick_number integer
 - dx_player_id integer
 - player_name text
 - age numeric
 - height text
 - weight integer
 - "position" text
 - predraft_team text
 - dx_predraft_team_id integer
 - league text
 - games_played integer
 - minutes numeric
 - points numeric
 - rebounds numeric
 - assists numeric
 - two_point_pct numeric
 - three_point_pct numeric
 - free_throw_pct numeric
 - pts_per_36 numeric
 - reb_per_36 numeric
 - ast_per_36 numeric
 - per numeric
 - rsci_rank integer

magnets
 - nba_id integer
 - contract_id integer
 - team_id integer
 - team text
 - player_name text
 - magnet_name text
 - age numeric
 - "position" text
 - sign_team_id integer
 - sign_team text
 - sign_date date
 - sign_method text
 - sign_method_description text
 - on_same_team integer
 - contract_start_year integer
 - contract_end_year integer
 - contract_remaining integer
 - contract_length integer
 - contract_type text
 - vet_min_1yr integer
 - two_way_2yr integer
 - contract_version_number numeric
 - last_change_date date
 - sign_and_trade integer
 - sign_and_trade_team_id integer
 - sign_and_trade_team text
 - team_exception_id integer
 - two_way_service_limit integer
 - future_salary numeric
 - total_salary numeric
 - cap_hit_2024 numeric
 - cap_pct_2024 numeric
 - tax_salary_2024 numeric
 - apron_salary_2024 numeric
 - cap_tax_variance_2024 numeric
 - cap_apron_variance_2024 numeric
 - option_type_2024 text
 - cap_hit_2025 numeric
 - cap_pct_2025 numeric
 - tax_salary_2025 numeric
 - apron_salary_2025 numeric
 - cap_tax_variance_2025 numeric
 - cap_apron_variance_2025 numeric
 - option_type_2025 text
 - cap_hit_2026 numeric
 - cap_pct_2026 numeric
 - tax_salary_2026 numeric
 - apron_salary_2026 numeric
 - cap_tax_variance_2026 numeric
 - cap_apron_variance_2026 numeric
 - option_type_2026 text
 - cap_hit_2027 numeric
 - cap_pct_2027 numeric
 - tax_salary_2027 numeric
 - apron_salary_2027 numeric
 - cap_tax_variance_2027 numeric
 - cap_apron_variance_2027 numeric
 - option_type_2027 text
 - cap_hit_2028 numeric
 - cap_pct_2028 numeric
 - tax_salary_2028 numeric
 - apron_salary_2028 numeric
 - cap_tax_variance_2028 numeric
 - cap_apron_variance_2028 numeric
 - option_type_2028 text
 - cap_hit_2029 numeric
 - cap_pct_2029 numeric
 - tax_salary_2029 numeric
 - apron_salary_2029 numeric
 - cap_tax_variance_2029 numeric
 - cap_apron_variance_2029 numeric
 - option_type_2029 text
 - cap_hit_2030 numeric
 - cap_pct_2030 numeric
 - tax_salary_2030 numeric
 - apron_salary_2030 numeric
 - cap_tax_variance_2030 numeric
 - cap_apron_variance_2030 numeric
 - option_type_2030 text
 - agency_id integer
 - agency text
 - agent_id integer
 - agent_name text
 - record_status text
 - birth_date date
 - draft_year integer
 - draft_round integer
 - draft_pick integer
 - early_entry integer
 - years_of_service integer
 - pcms_player_status text
 - no_trade integer
 - consent_to_trade integer
 - consent_type text
 - poison_pill integer
 - poison_pill_amount integer
 - trade_kicker integer
 - trade_kicker_amount integer
 - trade_kicker_pct numeric
 - trade_bonus_earned integer
 - reduced_tpe integer
 - no_aggregate integer
 - incentive_bonus integer
 - buyout_player integer
 - exhibit_10 integer
 - trade_deadline_model numeric

nba_west_vs_east
 - season_id text
 - year integer
 - wins bigint
 - losses bigint
 - total bigint
 - win_pct numeric

ngss_rosters
 - team_id integer
 - team text
 - nba_id integer
 - player text
 - "position" text
 - name_initial text
 - first_name text
 - family_name text
 - jersey_number text
 - team_city text
 - team_mascot text

pcms_players
 - nba_id integer
 - player_name text
 - player_initials text
 - birth_date date
 - age numeric
 - height integer
 - height_formatted text
 - weight integer
 - "position" text
 - years_of_service text
 - draft_year integer
 - draft_pick integer
 - draft_round text
 - draft_team_id integer
 - early_entry boolean
 - school_id integer
 - two_way integer
 - uniform_number text
 - roster_name text
 - stats_name text
 - created_at date
 - updated_at date
 - league text
 - player_status text
 - record_status text
 - gleague_status text

portland_game_flow
 - game_id text
 - quarter integer
 - type text
 - time_start text
 - time_end text
 - score jsonb
 - time_start_seconds integer
 - time_end_seconds integer

portland_games
 - game_id text
 - game_date date
 - is_home boolean
 - opponent text
 - opponent_team jsonb
 - portland_team jsonb
 - full_game jsonb

portland_player_stats
 - game_id text
 - game_date date
 - players jsonb

postgame
 - game_id text
 - game_date date
 - data json

salary_cap
 - team_id integer
 - team text
 - apron_level text
 - is_apron_1 integer
 - is_apron_2 integer
 - team_buffer_2024 numeric
 - apron_reason text
 - apron_reason_description text
 - apron_1_trade_id integer
 - apron_1_transaction_id integer
 - apron_2_trade_id integer
 - apron_2_transaction_id integer
 - apron_change_date date
 - taxpayer_repeater integer
 - contracts_2024 integer
 - team_cap_2024 numeric
 - team_tax_2024 numeric
 - cap_tax_variance_2024 numeric
 - team_apron_2024 numeric
 - cap_apron_variance_2024 numeric
 - dead_cap_2024 numeric
 - cap_room_2024 numeric
 - below_mts_2024 numeric
 - below_tax_2024 numeric
 - below_apron_1_2024 numeric
 - below_apron_2_2024 numeric
 - nba_mts_2024 numeric
 - nba_cap_2024 numeric
 - nba_tax_2024 numeric
 - nba_apron_1_2024 numeric
 - nba_apron_2_2024 numeric
 - cap_holds_2024 numeric
 - contracts_2025 integer
 - team_cap_2025 numeric
 - team_tax_2025 numeric
 - cap_tax_variance_2025 numeric
 - team_apron_2025 numeric
 - cap_apron_variance_2025 numeric
 - dead_cap_2025 numeric
 - cap_room_2025 numeric
 - below_mts_2025 numeric
 - below_tax_2025 numeric
 - below_apron_1_2025 numeric
 - below_apron_2_2025 numeric
 - nba_mts_2025 numeric
 - nba_cap_2025 numeric
 - nba_tax_2025 numeric
 - nba_apron_1_2025 numeric
 - nba_apron_2_2025 numeric
 - cap_holds_2025 numeric
 - contracts_2026 integer
 - team_cap_2026 numeric
 - team_tax_2026 numeric
 - cap_tax_variance_2026 numeric
 - team_apron_2026 numeric
 - cap_apron_variance_2026 numeric
 - cap_room_2026 numeric
 - dead_cap_2026 numeric
 - below_mts_2026 numeric
 - below_tax_2026 numeric
 - below_apron_1_2026 numeric
 - below_apron_2_2026 numeric
 - nba_mts_2026 numeric
 - nba_cap_2026 numeric
 - nba_tax_2026 numeric
 - nba_apron_1_2026 numeric
 - nba_apron_2_2026 numeric
 - cap_holds_2026 numeric
 - contracts_2027 integer
 - team_cap_2027 numeric
 - team_tax_2027 numeric
 - cap_tax_variance_2027 numeric
 - team_apron_2027 numeric
 - cap_apron_variance_2027 numeric
 - dead_cap_2027 numeric
 - cap_room_2027 numeric
 - below_mts_2027 numeric
 - below_tax_2027 numeric
 - below_apron_1_2027 numeric
 - below_apron_2_2027 numeric
 - nba_mts_2027 numeric
 - nba_cap_2027 numeric
 - nba_tax_2027 numeric
 - nba_apron_1_2027 numeric
 - nba_apron_2_2027 numeric
 - cap_holds_2027 numeric
 - contracts_2028 integer
 - team_cap_2028 numeric
 - team_tax_2028 numeric
 - cap_tax_variance_2028 numeric
 - team_apron_2028 numeric
 - cap_apron_variance_2028 numeric
 - dead_cap_2028 numeric
 - cap_room_2028 numeric
 - below_mts_2028 numeric
 - below_tax_2028 numeric
 - below_apron_1_2028 numeric
 - below_apron_2_2028 numeric
 - nba_mts_2028 numeric
 - nba_cap_2028 numeric
 - nba_tax_2028 numeric
 - nba_apron_1_2028 numeric
 - nba_apron_2_2028 numeric
 - cap_holds_2028 numeric
 - contracts_2029 integer
 - team_cap_2029 numeric
 - team_tax_2029 numeric
 - cap_tax_variance_2029 numeric
 - team_apron_2029 numeric
 - cap_apron_variance_2029 numeric
 - dead_cap_2029 numeric
 - cap_room_2029 numeric
 - below_mts_2029 numeric
 - below_tax_2029 numeric
 - below_apron_1_2029 numeric
 - below_apron_2_2029 numeric
 - nba_mts_2029 numeric
 - nba_cap_2029 numeric
 - nba_tax_2029 numeric
 - nba_apron_1_2029 numeric
 - nba_apron_2_2029 numeric
 - cap_holds_2029 numeric
 - contracts_2030 integer
 - team_cap_2030 numeric
 - team_tax_2030 numeric
 - cap_tax_variance_2030 numeric
 - team_apron_2030 numeric
 - cap_apron_variance_2030 numeric
 - dead_cap_2030 numeric
 - cap_room_2030 numeric
 - below_mts_2030 numeric
 - below_tax_2030 numeric
 - below_apron_1_2030 numeric
 - below_apron_2_2030 numeric
 - nba_mts_2030 numeric
 - nba_cap_2030 numeric
 - nba_tax_2030 numeric
 - nba_apron_1_2030 numeric
 - nba_apron_2_2030 numeric
 - cap_holds_2030 numeric

sean_team_standings
 - league text
 - season integer
 - season_code text
 - team_name text
 - team_code text
 - conference text
 - division text
 - wins integer
 - losses integer
 - win_percentage numeric(5,1)
 - games_behind numeric
 - conference_rank integer
 - division_rank integer
 - home_record text
 - road_record text
 - last_10 text

sean_team_stats
 - season text
 - season_id integer
 - league text
 - team_id integer
 - team_code text
 - team_name text
 - games numeric
 - off_rtg numeric
 - off_rtg_rank bigint
 - ts_pct numeric
 - ts_pct_rank bigint
 - efg_pct numeric
 - efg_pct_rank bigint
 - fg3a_rate numeric
 - fg3a_rate_rank bigint
 - fta_rate numeric
 - fta_rate_rank bigint
 - ast_pct numeric
 - ast_pct_rank bigint
 - tov_pct numeric
 - tov_pct_rank bigint
 - oreb_pct numeric
 - oreb_pct_rank bigint
 - pace numeric
 - pace_rank bigint
 - net_rtg numeric
 - net_rtg_rank bigint
 - paint_pts_pct numeric
 - paint_pts_pct_rank bigint
 - fastbreak_pts_pct numeric
 - fastbreak_pts_pct_rank bigint
 - def_rtg numeric
 - def_rtg_rank bigint
 - dreb_pct numeric
 - dreb_pct_rank bigint
 - opp_efg_pct numeric
 - opp_efg_pct_rank bigint
 - opp_tov_pct numeric
 - opp_tov_pct_rank bigint
 - opp_fg3_pct numeric
 - opp_fg3_pct_rank bigint

youtube_geomean
 - channel text
 - youtube_id text
 - title text
 - transcript text
 - upload_date date
 - duration bigint
 - view_count bigint
 - days_old integer
 - has_transcript boolean
 - has_claude_transcript boolean
 - duration_percentile numeric
 - views_percentile numeric
 - recency_percentile numeric
 - geomean_score numeric

zach_reports
 - draft integer
 - blitz_id text
 - player text
 - full_report text
 - concise_report text
 - intel_report text
```


### Functions

```
function api_bert_challenges() returns jsonb
function api_fanduel() returns jsonb
function api_search_cba(q text) returns cba
function clean_name(txt text) returns text
function daitch_mokotoff(text) returns text[]
function difference(text, text) returns integer
function dmetaphone(text) returns text
function dmetaphone_alt(text) returns text
function find_missing_boxscores() returns record
function find_missing_pbp() returns text
function find_nba_dev_games(table_name text, season_id text) returns text
function fn_dx_mock_draft_snapshot() returns trigger
function get_injury_report() returns jsonb
function gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) returns internal
function gin_extract_value_trgm(text, internal) returns internal
function gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) returns boolean
function gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) returns "char"
function gtrgm_compress(internal) returns internal
function gtrgm_consistent(internal, text, smallint, oid, internal) returns boolean
function gtrgm_decompress(internal) returns internal
function gtrgm_distance(internal, text, smallint, oid, internal) returns double precision
function gtrgm_in(cstring) returns gtrgm
function gtrgm_options(internal) returns void
function gtrgm_out(gtrgm) returns cstring
function gtrgm_penalty(internal, internal, internal) returns internal
function gtrgm_picksplit(internal, internal) returns internal
function gtrgm_same(gtrgm, gtrgm, internal) returns internal
function gtrgm_union(internal, internal) returns gtrgm
function jsonb_truncate(p_jsonb jsonb) returns jsonb
function jsonify(val jsonb) returns jsonb
function levenshtein(text, text, integer, integer, integer) returns integer
function levenshtein(text, text) returns integer
function levenshtein_less_equal(text, text, integer) returns integer
function levenshtein_less_equal(text, text, integer, integer, integer, integer) returns integer
function metaphone(text, integer) returns text
function missing_pbp() returns text
function nba_refs_for_slack(game text, refs text[]) returns jsonb
function normalize_name(text) returns text
function parse_minutes(time_str text) returns numeric
function refresh_nba_games() returns integer
function set_limit(real) returns real
function show_limit() returns real
function show_trgm(text) returns text[]
function similarity(text, text) returns real
function similarity_dist(text, text) returns real
function similarity_op(text, text) returns boolean
function soundex(text) returns text
function strict_word_similarity(text, text) returns real
function strict_word_similarity_commutator_op(text, text) returns boolean
function strict_word_similarity_dist_commutator_op(text, text) returns real
function strict_word_similarity_dist_op(text, text) returns real
function strict_word_similarity_op(text, text) returns boolean
function text_soundex(text) returns text
function update_ngss_challenges() returns trigger
function word_similarity(text, text) returns real
function word_similarity_commutator_op(text, text) returns boolean
function word_similarity_dist_commutator_op(text, text) returns real
function word_similarity_dist_op(text, text) returns real
function word_similarity_op(text, text) returns boolean
function zachbase_user(p_user text, p_pass text) returns integer
```


## realgm

### Tables

```
all_nba
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - all_nba_team integer
 - age numeric
 - yos integer

all_star
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - selection text
 - age numeric
 - yos integer

current_rosters
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - yos numeric

gleague_comps
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - height numeric
 - weight numeric
 - g integer
 - mp numeric
 - mpg numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg2m_36 numeric
 - fg2a_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - fg_pct numeric
 - ft_pct numeric
 - fg2_pct numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ft_fga numeric
 - stl_pct numeric
 - blk_pct numeric
 - ts numeric
 - efg numeric
 - hob numeric
 - gfg numeric
 - yos integer
 - pts_high integer
 - double_double integer
 - ws numeric
 - dbl_dbl_pct numeric
 - ws_50 numeric
 - ts_efg numeric
 - deflections_36 numeric
 - age_plus_tov_36 numeric
 - age_minus_fgm_36 numeric
 - age_minus_deflections_36 numeric
 - height_bin integer
 - g_pctl integer
 - mpg_pctl integer
 - yos_pctl integer
 - pts_pctl integer
 - reb_pctl integer
 - ast_pctl integer
 - stl_pctl integer
 - blk_pctl integer
 - gfg_pctl integer
 - age_pctl integer
 - r_age numeric
 - r_height numeric
 - r_weight numeric
 - r_fg2m_36 numeric
 - r_fg2a_36 numeric
 - r_pf_36 numeric
 - r_dbl_dbl_pct numeric
 - r_ws_50 numeric
 - r_g numeric
 - r_yos numeric
 - r_fg_pct numeric
 - r_ft_pct numeric
 - r_fg3_pct numeric
 - r_fgm_36 numeric
 - r_fga_36 numeric
 - r_fg3m_36 numeric
 - r_fg3a_36 numeric
 - r_ftm_36 numeric
 - r_fta_36 numeric
 - r_oreb_36 numeric
 - r_dreb_36 numeric
 - r_reb_36 numeric
 - r_ast_36 numeric
 - r_stl_36 numeric
 - r_blk_36 numeric
 - r_tov_36 numeric
 - r_pts_36 numeric
 - r_hob numeric
 - r_ts numeric
 - r_efg numeric
 - r_pts_high numeric
 - r_fg2_pct numeric
 - r_fg3_rate numeric
 - r_ft_fga numeric
 - r_ts_efg numeric
 - r_deflections_36 numeric
 - r_age_plus_tov_36 numeric
 - r_age_minus_fgm_36 numeric
 - r_age_minus_deflections_36 numeric
 - r_gfg numeric
 - r_ht_age_minus_fgm_36 numeric
 - r_ht_age_minus_deflections_36 numeric
 - r_ht_hob numeric
 - r_ht_fg2_pct numeric
 - r_ht_ts_efg numeric

gleague_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts numeric
 - efg numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric
 - mpg numeric
 - fg2m numeric
 - fg2a numeric
 - fg2_pct numeric
 - fg2m_36 numeric
 - fg2a_36 numeric

hoop_summit
 - season integer
 - gm_id integer primary key
 - player text
 - age numeric
 - mp integer
 - pts numeric
 - fgm numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - fic numeric

jordan
 - season integer
 - gm_id integer primary key
 - player text
 - age numeric
 - mp integer
 - pts numeric
 - fgm numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - fic numeric

mcdonalds
 - season integer
 - gm_id integer primary key
 - player text
 - age numeric
 - mp integer
 - pts numeric
 - fgm numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - fic numeric

most_improved
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - yos integer

nba_combine
 - gm_id integer primary key
 - year integer primary key
 - player text
 - team text
 - age numeric
 - pts numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - mp numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - fic numeric

nba_comps
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - height numeric
 - weight numeric
 - g integer
 - mp integer
 - mpg numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg2m_36 numeric
 - fg2a_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - fg_pct numeric
 - ft_pct numeric
 - fg2_pct numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ft_fga numeric
 - stl_pct numeric
 - blk_pct numeric
 - ts numeric
 - efg numeric
 - hob numeric
 - gfg numeric
 - yos integer
 - pts_high integer
 - double_double integer
 - ws numeric
 - dbl_dbl_pct numeric
 - ws_82 numeric
 - ts_efg numeric
 - deflections_36 numeric
 - age_plus_tov_36 numeric
 - age_minus_fgm_36 numeric
 - age_minus_deflections_36 numeric
 - height_bin integer
 - g_pctl integer
 - mpg_pctl integer
 - yos_pctl integer
 - pts_pctl integer
 - reb_pctl integer
 - ast_pctl integer
 - stl_pctl integer
 - blk_pctl integer
 - gfg_pctl integer
 - age_pctl integer
 - r_age numeric
 - r_height numeric
 - r_weight numeric
 - r_fg2m_36 numeric
 - r_fg2a_36 numeric
 - r_pf_36 numeric
 - r_dbl_dbl_pct numeric
 - r_ws_82 numeric
 - r_g numeric
 - r_yos numeric
 - r_fg_pct numeric
 - r_ft_pct numeric
 - r_fg3_pct numeric
 - r_fgm_36 numeric
 - r_fga_36 numeric
 - r_fg3m_36 numeric
 - r_fg3a_36 numeric
 - r_ftm_36 numeric
 - r_fta_36 numeric
 - r_oreb_36 numeric
 - r_dreb_36 numeric
 - r_reb_36 numeric
 - r_ast_36 numeric
 - r_stl_36 numeric
 - r_blk_36 numeric
 - r_tov_36 numeric
 - r_pts_36 numeric
 - r_hob numeric
 - r_ts numeric
 - r_efg numeric
 - r_pts_high numeric
 - r_fg2_pct numeric
 - r_fg3_rate numeric
 - r_ft_fga numeric
 - r_ts_efg numeric
 - r_deflections_36 numeric
 - r_age_plus_tov_36 numeric
 - r_age_minus_fgm_36 numeric
 - r_age_minus_deflections_36 numeric
 - r_gfg numeric
 - r_ht_age_minus_fgm_36 numeric
 - r_ht_age_minus_deflections_36 numeric
 - r_ht_hob numeric
 - r_ht_fg2_pct numeric
 - r_ht_ts_efg numeric

nba_draft
 - season integer primary key
 - pick integer primary key
 - team text
 - trade text
 - gm_id integer
 - nba_id text
 - player text
 - dob date
 - age numeric
 - "position" text
 - height integer
 - weight integer
 - predraft text
 - nationality text
 - hometown text
 - draft_date date

nba_draft_max_ws
 - gm_id integer
 - draft_year integer
 - draft_pick integer
 - draft_team text
 - player text
 - age numeric
 - status text
 - p_already_peaked numeric
 - expected_ws_prior numeric
 - eventual_max_ws_pred numeric
 - ws_peak numeric
 - added_headroom numeric
 - over_under numeric
 - is_above_average integer
 - nba_id integer

nba_max_ws
 - season integer
 - gm_id integer primary key
 - player text
 - age numeric
 - team text
 - g integer
 - ws numeric

nba_playoff_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts_pct numeric
 - efg_pct numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric

nba_pre_all_star_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts_pct numeric
 - efg_pct numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric

nba_preseason_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts_pct numeric
 - efg_pct numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric

nba_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts numeric
 - efg numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric
 - mpg numeric
 - fg2m numeric
 - fg2a numeric
 - fg2_pct numeric
 - fg2m_36 numeric
 - fg2a_36 numeric

ncaa_comps
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - height numeric
 - weight numeric
 - g integer
 - mp integer
 - mpg numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg2m_36 numeric
 - fg2a_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - fg_pct numeric
 - ft_pct numeric
 - fg2_pct numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - ft_fga numeric
 - stl_pct numeric
 - blk_pct numeric
 - ts numeric
 - efg numeric
 - hob numeric
 - gfg numeric
 - yos integer
 - pts_high integer
 - is_power_conf boolean
 - is_west_coast boolean
 - played_nba boolean
 - played_gleague boolean
 - double_double integer
 - ws numeric
 - dbl_dbl_pct numeric
 - ws_82 numeric
 - ts_efg numeric
 - deflections_36 numeric
 - age_plus_tov_36 numeric
 - age_minus_fgm_36 numeric
 - age_minus_deflections_36 numeric
 - height_bin integer
 - g_pctl integer
 - mpg_pctl integer
 - yos_pctl integer
 - pts_pctl integer
 - reb_pctl integer
 - ast_pctl integer
 - stl_pctl integer
 - blk_pctl integer
 - gfg_pctl integer
 - age_pctl integer
 - r_age numeric
 - r_height numeric
 - r_weight numeric
 - r_power_conf numeric
 - r_west_coast numeric
 - r_fg2m_36 numeric
 - r_fg2a_36 numeric
 - r_pf_36 numeric
 - r_dbl_dbl_pct numeric
 - r_ws_82 numeric
 - r_g numeric
 - r_yos numeric
 - r_fg_pct numeric
 - r_ft_pct numeric
 - r_fg3_pct numeric
 - r_fgm_36 numeric
 - r_fga_36 numeric
 - r_fg3m_36 numeric
 - r_fg3a_36 numeric
 - r_ftm_36 numeric
 - r_fta_36 numeric
 - r_oreb_36 numeric
 - r_dreb_36 numeric
 - r_reb_36 numeric
 - r_ast_36 numeric
 - r_stl_36 numeric
 - r_blk_36 numeric
 - r_tov_36 numeric
 - r_pts_36 numeric
 - r_hob numeric
 - r_ts numeric
 - r_efg numeric
 - r_pts_high numeric
 - r_fg2_pct numeric
 - r_fg3_rate numeric
 - r_ft_fga numeric
 - r_ts_efg numeric
 - r_deflections_36 numeric
 - r_age_plus_tov_36 numeric
 - r_age_minus_fgm_36 numeric
 - r_age_minus_deflections_36 numeric
 - r_gfg numeric
 - r_ht_age_minus_fgm_36 numeric
 - r_ht_age_minus_deflections_36 numeric
 - r_ht_hob numeric
 - r_ht_fg2_pct numeric
 - r_ht_ts_efg numeric

ncaa_stats
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - g integer
 - mp integer
 - pts numeric
 - fgm numeric
 - fga numeric
 - fg_pct numeric
 - fg3m numeric
 - fg3a numeric
 - fg3_pct numeric
 - fg3_rate numeric
 - gfg numeric
 - ftm numeric
 - fta numeric
 - ft_pct numeric
 - oreb numeric
 - dreb numeric
 - reb numeric
 - ast numeric
 - stl numeric
 - blk numeric
 - tov numeric
 - pf numeric
 - pts_36 numeric
 - fgm_36 numeric
 - fga_36 numeric
 - fg3m_36 numeric
 - fg3a_36 numeric
 - ftm_36 numeric
 - fta_36 numeric
 - oreb_36 numeric
 - dreb_36 numeric
 - reb_36 numeric
 - ast_36 numeric
 - stl_36 numeric
 - blk_36 numeric
 - tov_36 numeric
 - pf_36 numeric
 - double_double integer
 - triple_double integer
 - pts_40 integer
 - pts_20 integer
 - ast_20 integer
 - stl_5 integer
 - blk_5 integer
 - pts_high integer
 - techs integer
 - hob numeric
 - ast_tov numeric
 - stl_tov numeric
 - ft_fga numeric
 - win integer
 - loss integer
 - win_pct numeric
 - ows numeric
 - dws numeric
 - ws numeric
 - ts numeric
 - efg numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - ast_pct numeric
 - tov_pct numeric
 - stl_pct numeric
 - blk_pct numeric
 - usg numeric
 - ppr numeric
 - pps numeric
 - ortg numeric
 - drtg numeric
 - ediff numeric
 - fic numeric
 - per numeric
 - yos numeric
 - mpg numeric
 - fg2m numeric
 - fg2a numeric
 - fg2_pct numeric
 - conf_id integer
 - conference text
 - is_power_conf boolean
 - is_west_coast boolean
 - fg2m_36 numeric
 - fg2a_36 numeric

opening_day
 - season integer primary key
 - gm_id integer primary key
 - player text
 - team text
 - age numeric
 - yos integer

players
 - gm_id integer primary key
 - player text
 - first_name text
 - last_name text
 - dob date
 - height integer
 - weight integer
 - "position" text
 - hometown text
 - hometown_id integer
 - highschool text
 - highschool_id integer
 - handed text
 - twitter text
 - instagram text
 - website text
 - height_formatted text
 - notable smallint

sitemaps
 - sitemap text primary key
 - content text
 - interesting text
 - notes text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

team_executives
 - team text primary key
 - exec text
 - date_start text primary key
 - date_end text
 - notes text

trades
 - season integer
 - trade_date text primary key
 - gm_id integer primary key
 - player text
 - trade text
```


### Views

_None_


### Functions

_None_


## rotowire

### Tables

```
cfb_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

euroleague_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

golf_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

mlb_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nba_adp
 - season integer primary key
 - data jsonb
 - created_at timestamp with time zone
 - updated_at timestamp with time zone

nba_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - slack_channel text
 - slack_message text
 - slack_at timestamp with time zone
 - is_ignored boolean

nba_players
 - roto_id integer primary key
 - nba_id integer
 - full_name text
 - slug text
 - updated_at timestamp with time zone
 - "position" text
 - team text
 - team_code text
 - birthday date
 - age numeric
 - height text
 - weight integer
 - college text
 - draft text
 - contract text
 - biography text
 - fantasy text
 - image_url text

nba_teams
 - team_id bigint primary key
 - team_code text
 - team_city text
 - team_mascot text
 - is_nba smallint
 - is_gleague smallint
 - roto_team text

ncaa_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - slack_channel text
 - slack_message text
 - slack_at text
 - is_ignored boolean

nfl_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

nhl_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

rotoworld
 - news_id text primary key
 - published timestamp with time zone
 - rotoworld_id text
 - player text
 - first_name text
 - last_name text
 - team text
 - headline text
 - analysis text
 - player_url text
 - player_image text
 - "position" text
 - jersey_number text
 - source text
 - source_url text
 - news_type text
 - team_logo text
 - related_players jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

vegas_nba
 - season integer
 - game_id text
 - game_date date primary key
 - game_time timestamp with time zone
 - month text
 - start_type text
 - away_team_id integer primary key
 - away_team text
 - home_team_id integer primary key
 - home_team text
 - winner text
 - away_team_score integer
 - home_team_score integer
 - score text
 - total numeric
 - game_over_under numeric
 - line numeric
 - spread numeric
 - favorite text
 - over_hit smallint
 - under_hit smallint
 - favorite_covered smallint
 - underdog_covered smallint
 - away_team_won smallint
 - home_team_won smallint
 - rotowire_name text

vegas_nfl
 - season integer primary key
 - week text primary key
 - game_date date
 - game_time timestamp with time zone
 - month text
 - start_type text
 - away_team_id text primary key
 - away_team text
 - home_team_id text primary key
 - home_team text
 - winner text
 - away_team_score integer
 - home_team_score integer
 - score text
 - total numeric
 - game_over_under text
 - line numeric
 - spread numeric
 - favorite text
 - over_hit smallint
 - under_hit smallint
 - favorite_covered smallint
 - underdog_covered smallint
 - away_team_won smallint
 - home_team_won smallint
 - surface text
 - weather_icon text
 - temperature numeric
 - precip_probability text
 - precip_type text
 - wind_speed numeric
 - wind_bearing integer
 - rotowire_name text

wnba_news
 - news_id serial primary key
 - roto_id integer
 - roto_date date
 - full_name text
 - team text
 - "position" text
 - injury text
 - headline text
 - content text
 - is_injured boolean
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
```


### Views

_None_


### Functions

_None_


## scrapy

### Tables

```
action_network
 - game_date date primary key default CURRENT_DATE
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone

bball_index
 - stat_type text primary key
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

fabwags
 - url text primary key
 - title text
 - published_at timestamp with time zone
 - content text
 - created_at timestamp with time zone default now()

hoopshype_feed
 - hoopshype_id bigint generated by default as identity primary key
 - published timestamp with time zone
 - title text
 - content text
 - link text
 - tags jsonb
 - source text
 - source_link text
 - related json
 - claude jsonb
 - on_slack smallint
 - on_injuries smallint
 - ignore_content smallint default 0

hoopshype_tags
 - hoopshype_tag_id bigint generated by default as identity primary key
 - tag text
 - posts integer

hoopshype_wordpress
 - hoopshype_id bigint generated by default as identity primary key
 - published timestamp with time zone
 - title text
 - slug text
 - link text
 - tags jsonb

hoopshype_wrong_tags
 - hoopshype_tag_id bigint
 - tag text
 - slug text
 - posts integer

odds
 - game_id text primary key
 - game_date date
 - away_team text
 - away_score integer
 - home_team text
 - home_score integer
 - winner text
 - away_spread_open numeric
 - away_spread_open_odds numeric
 - away_spread_close numeric
 - away_spread_close_odds numeric
 - over_open numeric
 - over_open_odds numeric
 - over_close numeric
 - over_close_odds numeric
 - home_spread_open numeric
 - home_spread_open_odds numeric
 - home_spread_close numeric
 - home_spread_close_odds numeric
 - under_open numeric
 - under_open_odds numeric
 - under_close numeric
 - under_close_odds numeric
 - odds_id integer
 - nba_id text

postgresfm
 - id text primary key
 - title text
 - summary text
 - transcript text
 - runtime integer
 - published_at date
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone
```


### Views

_None_


### Functions

_None_


## sportradar

### Tables

```
docs
 - api text primary key
 - content text
 - notes text
 - data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - is_active boolean default true
 - faq text

gleague_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

gleague_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

gleague_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

gleague_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated_at timestamp with time zone
 - data jsonb

gleague_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

gleague_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

gleague_games
 - game_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

gleague_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

gleague_leaders
 - season_id text primary key
 - season_year integer
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

gleague_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

gleague_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

gleague_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

gleague_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

gleague_seasons
 - season_id text primary key
 - league_id text
 - year integer
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

gleague_series
 - series_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

gleague_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

gleague_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

gleague_standings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

gleague_team_season_player_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

gleague_team_season_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

gleague_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

gleague_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb

intl_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

intl_competitions
 - id text primary key
 - name text
 - gender text
 - category_id text
 - category_name text
 - category_country_code text
 - data jsonb

intl_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

intl_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

intl_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated timestamp with time zone
 - data jsonb

intl_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

intl_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

intl_games
 - game_id text primary key
 - season_id text
 - season_year text
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

intl_groups
 - id text primary key
 - name text
 - group_name text
 - season_id text
 - stage_type text
 - year text
 - phase text
 - "order" integer
 - start_date date
 - end_date date
 - data jsonb

intl_id_mappings
 - entity_type text primary key
 - id text primary key
 - external_id text primary key
 - generated_at timestamp with time zone
 - data jsonb

intl_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

intl_leaders
 - season_id text primary key
 - season_year text
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

intl_merge_mappings
 - entity_type text primary key
 - merged_id text primary key
 - retained_id text primary key
 - name text
 - generated_at timestamp with time zone

intl_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

intl_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

intl_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

intl_rankings
 - season_id text primary key
 - season_year text
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

intl_seasons
 - season_id text primary key
 - league_id text
 - year text
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

intl_series
 - series_id text primary key
 - season_id text
 - season_year text
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

intl_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

intl_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year text
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

intl_sport_events
 - id text primary key
 - season_id text
 - competition_id text
 - category_id text
 - start_time timestamp with time zone
 - start_time_confirmed boolean
 - neutral_site boolean
 - venue_id text
 - status text
 - match_status text
 - home_competitor_id text
 - away_competitor_id text
 - home_score integer
 - away_score integer
 - winner_id text
 - coverage jsonb
 - period_scores jsonb
 - context jsonb
 - data jsonb

intl_standings
 - season_id text primary key
 - season_year text
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

intl_standings_groups
 - season_id text primary key
 - group_id text primary key
 - type text primary key
 - round integer primary key
 - tie_break_rule text
 - live boolean
 - group_name text
 - stage jsonb
 - data jsonb

intl_standings_rows
 - season_id text primary key
 - group_id text primary key
 - competitor_id text primary key
 - rank integer
 - win integer
 - loss integer
 - draw integer
 - played integer
 - win_ratio text
 - win_percentage numeric
 - points integer
 - opp_points integer
 - pts_diff numeric
 - games_behind numeric
 - streak text
 - current_outcome text
 - last_ten_win_record integer
 - last_ten_loss_record integer
 - data jsonb

intl_team_season_player_stats
 - season_id text primary key
 - season_year text
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

intl_team_season_stats
 - season_id text primary key
 - season_year text
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

intl_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

intl_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb

nba_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

nba_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

nba_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

nba_draft
 - draft_id text primary key
 - year integer
 - status text
 - start_date date
 - end_date date
 - venue jsonb
 - broadcast jsonb
 - data jsonb

nba_draft_picks
 - pick_id text primary key
 - draft_id text
 - round_id text
 - team_id text
 - team_code text
 - number integer
 - overall integer
 - traded boolean
 - trades jsonb
 - prospect jsonb
 - data jsonb

nba_draft_prospects
 - prospect_id text primary key
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - dob date
 - height integer
 - weight integer
 - team_name text
 - birth_place text
 - division jsonb
 - conference jsonb
 - top_prospect boolean
 - data jsonb

nba_draft_rounds
 - draft_round_id text primary key
 - draft_id text
 - number integer
 - status text
 - start_date date
 - end_date date
 - data jsonb

nba_draft_trade_transactions
 - transaction_id text primary key
 - trade_id text
 - to_team_id text
 - to_team_code text
 - from_team_id text
 - from_team_code text
 - items jsonb
 - data jsonb

nba_draft_trades
 - trade_id text primary key
 - draft_id text
 - complete boolean
 - sequence bigint
 - data jsonb

nba_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated timestamp with time zone
 - data jsonb

nba_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

nba_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

nba_games
 - game_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

nba_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

nba_leaders
 - season_id text primary key
 - season_year integer
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

nba_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

nba_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

nba_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

nba_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

nba_seasons
 - season_id text primary key
 - league_id text
 - year integer
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

nba_series
 - series_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

nba_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

nba_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

nba_standings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

nba_team_season_player_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

nba_team_season_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

nba_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

nba_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb

ncaa_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

ncaa_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

ncaa_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

ncaa_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated timestamp with time zone
 - data jsonb

ncaa_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

ncaa_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

ncaa_games
 - game_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

ncaa_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

ncaa_leaders
 - season_id text primary key
 - season_year integer
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

ncaa_net_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - net_rank integer
 - prev_net_rank integer
 - wins integer
 - losses integer
 - conf_wins integer
 - conf_losses integer
 - road_wins integer
 - road_losses integer
 - non_conf_wins integer
 - non_conf_losses integer
 - net_sos integer
 - net_non_conf_sos integer
 - avg_opp_net integer
 - avg_opp_net_rank integer
 - quad_1_wins integer
 - quad_1_losses integer
 - quad_2_wins integer
 - quad_2_losses integer
 - quad_3_wins integer
 - quad_3_losses integer
 - quad_4_wins integer
 - quad_4_losses integer
 - data jsonb

ncaa_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

ncaa_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

ncaa_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

ncaa_poll_rankings
 - poll_alias text primary key
 - season_year integer primary key
 - week text primary key
 - effective_time timestamp with time zone
 - team_id text primary key
 - rank integer
 - points integer
 - fp_votes integer
 - prev_rank integer
 - data jsonb

ncaa_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

ncaa_rpi_rankings
 - season_id text primary key
 - season_year integer
 - team_id text primary key
 - team_code text
 - rank integer
 - rpi numeric
 - awp numeric
 - owp numeric
 - oowp numeric
 - sos numeric
 - wins integer
 - losses integer
 - prev_rank integer
 - opponents jsonb
 - data jsonb

ncaa_seasons
 - season_id text primary key
 - league_id text
 - year integer
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

ncaa_series
 - series_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

ncaa_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

ncaa_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

ncaa_standings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

ncaa_team_season_player_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

ncaa_team_season_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

ncaa_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

ncaa_tournament_games
 - tournament_id text primary key
 - game_id text primary key
 - round_id text
 - round_name text
 - bracket_id text
 - bracket_name text
 - title text
 - source jsonb
 - data jsonb

ncaa_tournament_team_stats
 - tournament_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - players jsonb
 - data jsonb

ncaa_tournaments
 - tournament_id text primary key
 - name text
 - parent_id text
 - location text
 - status text
 - season_id text
 - season_year integer
 - season_type text
 - start_date date
 - end_date date
 - data jsonb

ncaa_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb

ncaaw_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

ncaaw_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

ncaaw_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

ncaaw_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated timestamp with time zone
 - data jsonb

ncaaw_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

ncaaw_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

ncaaw_games
 - game_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

ncaaw_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

ncaaw_leaders
 - season_id text primary key
 - season_year integer
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

ncaaw_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

ncaaw_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

ncaaw_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

ncaaw_poll_rankings
 - poll_alias text primary key
 - season_year integer primary key
 - week text primary key
 - effective_time timestamp with time zone
 - team_id text primary key
 - rank integer
 - points integer
 - fp_votes integer
 - prev_rank integer
 - data jsonb

ncaaw_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

ncaaw_rpi_rankings
 - season_id text primary key
 - season_year integer
 - team_id text primary key
 - team_code text
 - rank integer
 - rpi numeric
 - awp numeric
 - owp numeric
 - oowp numeric
 - sos numeric
 - wins integer
 - losses integer
 - prev_rank integer
 - opponents jsonb
 - data jsonb

ncaaw_seasons
 - season_id text primary key
 - league_id text
 - year integer
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

ncaaw_series
 - series_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

ncaaw_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

ncaaw_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

ncaaw_standings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

ncaaw_team_season_player_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

ncaaw_team_season_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

ncaaw_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

ncaaw_tournament_games
 - tournament_id text primary key
 - game_id text primary key
 - round_id text
 - round_name text
 - bracket_id text
 - bracket_name text
 - title text
 - source jsonb
 - data jsonb

ncaaw_tournament_team_stats
 - tournament_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - players jsonb
 - data jsonb

ncaaw_tournaments
 - tournament_id text primary key
 - name text
 - parent_id text
 - location text
 - status text
 - season_id text
 - season_year integer
 - season_type text
 - start_date date
 - end_date date
 - data jsonb

ncaaw_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb

postman
 - api text primary key
 - endpoint text primary key
 - data jsonb
 - summary text
 - code text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

venues
 - venue_id text primary key
 - name text
 - city text
 - state text
 - country text
 - zip text
 - address text
 - capacity integer
 - lat numeric
 - lng numeric
 - location jsonb
 - data jsonb

wnba_change_log
 - date_key date primary key
 - section text primary key
 - entity_id text primary key
 - season_id text
 - last_modified timestamp with time zone
 - data jsonb

wnba_conferences
 - conference_id text primary key
 - league_id text
 - name text
 - alias text
 - data jsonb

wnba_divisions
 - division_id text primary key
 - conference_id text
 - name text
 - alias text
 - data jsonb

wnba_free_agents
 - player_id text primary key
 - status text
 - full_name text
 - first_name text
 - last_name text
 - "position" text
 - primary_position text
 - dob date
 - height integer
 - weight integer
 - birth_place text
 - college text
 - high_school text
 - experience text
 - updated timestamp with time zone
 - data jsonb

wnba_game_player_stats
 - game_id text primary key
 - team_id text
 - team_code text
 - player_id text primary key
 - full_name text
 - age numeric
 - starter boolean
 - played boolean
 - on_court boolean
 - "position" text
 - minutes_formatted text
 - minutes numeric
 - seconds integer
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_double boolean
 - triple_double boolean
 - statistics jsonb
 - data jsonb

wnba_game_team_stats
 - game_id text primary key
 - team_id text primary key
 - team_code text
 - is_away boolean
 - is_home boolean
 - points integer
 - opp_points integer
 - pts_diff integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - poss numeric
 - ortg numeric
 - drtg numeric
 - ast_pct numeric
 - ast_tov numeric
 - oreb_pct numeric
 - dreb_pct numeric
 - reb_pct numeric
 - fast_break_pts integer
 - pts_in_paint integer
 - pts_off_tov integer
 - second_chance_pts integer
 - remaining_timeouts integer
 - scoring jsonb
 - statistics jsonb
 - data jsonb

wnba_games
 - game_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - sr_id text
 - reference text
 - scheduled timestamp with time zone
 - status text
 - coverage text
 - title text
 - venue_id text
 - home_team_id text
 - away_team_id text
 - home_points integer
 - away_points integer
 - neutral_site boolean
 - conference_game boolean
 - track_on_court boolean
 - time_zones jsonb
 - broadcasts jsonb
 - attendance integer
 - duration text
 - quarter integer
 - clock text
 - clock_decimal text
 - officials jsonb
 - entry_mode text
 - times_tied integer
 - lead_changes integer
 - data jsonb

wnba_injuries
 - injury_id text primary key
 - team_id text
 - team_code text
 - player_id text
 - full_name text
 - age numeric
 - description text
 - status text
 - comment text
 - start_date date
 - update_date date
 - data jsonb

wnba_leaders
 - season_id text primary key
 - season_year integer
 - season_type text
 - category_name text primary key
 - category_type text primary key
 - rank integer primary key
 - tied boolean
 - player_id text primary key
 - full_name text
 - age numeric
 - team_ids jsonb
 - score numeric
 - total jsonb
 - average jsonb
 - data jsonb

wnba_pbp_events
 - game_id text primary key
 - event_id text primary key
 - period_id text
 - event_type text
 - description text
 - clock text
 - clock_decimal text
 - wall_clock timestamp with time zone
 - sequence bigint
 - attribution jsonb
 - possession jsonb
 - location jsonb
 - on_court jsonb
 - qualifiers jsonb
 - statistics jsonb
 - away_points integer
 - home_points integer
 - deleted boolean default false
 - data jsonb

wnba_pbp_periods
 - game_id text primary key
 - period_id text primary key
 - number integer
 - period_type text
 - sequence integer
 - scoring jsonb
 - data jsonb

wnba_players
 - player_id text primary key
 - team_id text
 - sr_id text
 - first_name text
 - last_name text
 - full_name text
 - abbr_name text
 - jersey_number text
 - primary_position text
 - "position" text
 - height integer
 - weight integer
 - dob date
 - birth_place text
 - college text
 - high_school text
 - status text
 - experience text
 - rookie_year integer
 - salary numeric
 - draft jsonb
 - reference jsonb
 - data jsonb

wnba_rankings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - clinched text
 - division_rank integer
 - conference_rank integer
 - data jsonb

wnba_seasons
 - season_id text primary key
 - league_id text
 - year integer
 - season_type text
 - start_date date
 - end_date date
 - status text
 - data jsonb

wnba_series
 - series_id text primary key
 - season_id text
 - season_year integer
 - season_type text
 - series_round integer
 - title text
 - status text
 - start_date date
 - participants jsonb
 - data jsonb

wnba_series_games
 - game_id text primary key
 - series_id text
 - title text
 - scheduled timestamp with time zone
 - status text
 - venue_id text
 - neutral_site boolean
 - home_team_id text
 - home_team_code text
 - away_team_id text
 - away_team_code text
 - home_points integer
 - away_points integer
 - pts_diff integer
 - time_zones jsonb
 - broadcasts jsonb
 - data jsonb

wnba_series_team_statistics
 - series_id text primary key
 - team_id text primary key
 - team_code text
 - season_id text
 - season_year integer
 - season_type text
 - status text
 - players jsonb
 - totals jsonb
 - own_record jsonb
 - opponents jsonb
 - data jsonb

wnba_standings
 - season_id text primary key
 - season_year integer
 - season_type text
 - conference_id text primary key
 - division_id text
 - team_id text primary key
 - wins integer
 - losses integer
 - win_pct numeric
 - points numeric
 - opp_points numeric
 - pts_diff numeric
 - calc_rank jsonb
 - streak jsonb
 - records jsonb
 - games_behind jsonb
 - clinched text
 - data jsonb

wnba_team_season_player_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - player_id text primary key
 - full_name text
 - "position" text
 - age numeric
 - jersey_number text
 - games_played integer
 - games_started integer
 - minutes numeric
 - points integer
 - ast integer
 - reb integer
 - oreb integer
 - dreb integer
 - stl integer
 - blk integer
 - tov integer
 - pf integer
 - plus_minus integer
 - fgm integer
 - fga integer
 - fg_pct numeric
 - fg2m integer
 - fg2a integer
 - fg2_pct numeric
 - fg3m integer
 - fg3a integer
 - fg3_pct numeric
 - fg3_rate numeric
 - ftm integer
 - fta integer
 - ft_pct numeric
 - ft_rate numeric
 - gfg numeric
 - hob numeric
 - efg numeric
 - ts numeric
 - usage numeric
 - fic numeric
 - double_doubles integer
 - triple_doubles integer
 - total jsonb
 - average jsonb
 - data jsonb

wnba_team_season_stats
 - season_id text primary key
 - season_year integer
 - season_type text
 - team_id text primary key
 - team_code text
 - own_record jsonb
 - opponents jsonb
 - points integer
 - opp_points integer
 - pts_diff numeric
 - ortg numeric
 - drtg numeric
 - net_rtg numeric
 - poss numeric
 - ast_pct numeric
 - ast_tov numeric
 - gfg numeric
 - efg numeric
 - ts numeric
 - data jsonb

wnba_teams
 - team_id text primary key
 - sr_id text
 - market text
 - name text
 - team_code text
 - reference text
 - conference_id text
 - division_id text
 - venue_id text
 - founded integer
 - owner text
 - mascot text
 - sponsor text
 - president text
 - franchise_id text
 - general_manager text
 - retired_numbers text
 - championships_won integer
 - conference_titles integer
 - playoff_appearances integer
 - championship_seasons text
 - team_colors jsonb
 - data jsonb

wnba_transfers
 - transfer_id text primary key
 - player_id text
 - full_name text
 - age numeric
 - transaction_type text
 - transaction_code text
 - effective_date date
 - last_modified timestamp with time zone
 - from_team_id text
 - from_team_code text
 - to_team_id text
 - to_team_code text
 - description text
 - data jsonb
```


### Views

_None_


### Functions

_None_


## zachbase

### Tables

```
catalog
 - id text primary key
 - description text
 - provider text
 - endpoint text
 - status text
 - tags jsonb default '[]'::jsonb
 - target_table text
 - pk text
 - input_data text
 - input_table text
 - input_pk text
 - windmill text
 - code_v1 text
 - code_v2 text
 - notes text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

daisyui
 - id text primary key
 - code text
 - filetype text
 - rough_draft text
 - revised_draft text
 - component text
 - interesting_rank jsonb
 - avg_rank numeric

datastar
 - id text primary key
 - markdown text
 - url text

dense_ui
 - id text primary key
 - kind text
 - notes text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

dense_ui_examples
 - id text primary key
 - notes text
 - kind text
 - tier integer
 - tier_name text
 - tier_notes text
 - is_revised boolean default false

echarts_examples
 - id text primary key
 - code text
 - notes text

fontawesome
 - icon text primary key
 - family text

glossary
 - id text primary key
 - content text
 - notes text

guides
 - id serial primary key
 - topic text
 - content text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

hp_fact_availability
 - availability_id integer primary key
 - hp_id integer
 - full_name text
 - smartabase_user_id integer
 - event_date date
 - start_timestamp timestamp with time zone
 - end_timestamp timestamp with time zone
 - select_type text
 - final_status text
 - injury_status text
 - illness_status text
 - injury_diagnosis text
 - final_diagnosis text
 - executive_summary text
 - current_soap text
 - current_plan text
 - action text
 - objective text
 - treatment text
 - subjective_notes text
 - consult_date date
 - reporting_date date
 - injury_date date
 - onset_date date
 - close_injury text
 - entered_by_user_id integer
 - raw_data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

hp_fact_body_comp
 - body_comp_id integer primary key
 - hp_id integer
 - full_name text
 - smartabase_user_id integer
 - measurement_date date
 - start_timestamp timestamp with time zone
 - end_timestamp timestamp with time zone
 - body_weight numeric(5,1)
 - body_fat_pct numeric(4,1)
 - last_body_weight numeric(5,1)
 - last_body_fat_pct numeric(4,1)
 - body_weight_loss numeric(5,1)
 - fat_pct_loss numeric(5,2)
 - season_baseline_weight numeric(5,1)
 - season_baseline_body_fat numeric(4,1)
 - details_included boolean
 - raw_data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

hp_fact_reports
 - report_id integer primary key
 - hp_id integer
 - full_name text
 - smartabase_user_id integer
 - report_date date
 - start_timestamp timestamp with time zone
 - end_timestamp timestamp with time zone
 - season integer
 - season_label text
 - report_type text
 - report_text text
 - kpis text
 - summary text
 - notes text
 - games_missed smallint
 - games_missed_season integer
 - games_played_season integer
 - sessions_completed smallint
 - sessions_season integer
 - raw_data jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

hp_players
 - hp_id serial primary key
 - nba_id integer
 - smartabase_user_id integer
 - full_name text
 - first_name text
 - last_name text
 - known_as text
 - age numeric(4,1)
 - dob date
 - height numeric(5,1)
 - height_formatted text
 - weight numeric(5,1)
 - primary_position text
 - secondary_position text
 - shoots text
 - yos integer
 - is_active boolean default true
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

joe_player_slides
 - id serial primary key
 - idx integer
 - full_name text
 - first_name text
 - last_name text
 - dob date
 - hometown text
 - "position" text
 - height text
 - weight text
 - agent text
 - predraft text
 - nba_draft text
 - yos text
 - background text
 - notes text
 - image_url text
 - on_roster boolean default true
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - rough_background text
 - rough_notes text

joe_war
 - id serial primary key
 - link text
 - title text
 - content text
 - revised text
 - tldr text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

mantine
 - id text primary key
 - code jsonb
 - rough_draft text
 - revised_draft text
 - interesting_rank jsonb
 - avg_rank numeric
 - component text

patterns
 - id serial primary key
 - name text
 - principles text
 - code text
 - created_at timestamp with time zone default now()

persons
 - id integer primary key
 - full_name text
 - first_name text
 - last_name text
 - initials text
 - dob date
 - age numeric
 - kind text
 - "position" text
 - status text
 - background text
 - notes text
 - hometown text
 - height_in numeric
 - height text
 - weight numeric
 - wingspan_in numeric
 - wingspan text
 - years_of_service integer
 - draft_year integer
 - draft_pick integer
 - draft_round integer
 - nba_id integer
 - gm_id integer
 - blitz_id text
 - ctg_id text
 - roto_id text
 - sr_id text
 - other_ids jsonb
 - tags jsonb default '[]'::jsonb
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

postgres
 - id text primary key
 - tables text
 - views text
 - functions text
 - notes text
 - revised_notes text
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()

postman
 - id text primary key
 - spec text
 - summary text
 - notes text
 - backfill text
 - create_tables text

webawesome
 - id text primary key
 - code text

webawesome_docs
 - id text primary key
 - markdown text
 - url text
 - notes text

webawesome_examples
 - id text primary key
 - code text
 - pattern text
 - url text
 - notes text
 - interesting_rank jsonb default '[]'::jsonb
 - avg_rank numeric
 - library_id integer
 - library_section text
 - library_lesson text

webawesome_layouts
 - id text primary key
 - code text
 - url text
 - notes text

windmill_examples
 - id serial primary key
 - description text
 - content text
 - interesting jsonb
 - interesting_score numeric

windmill_supabase
 - id serial primary key
 - file_name text
 - content text
 - notes text
 - code_v1 text
 - code_v2 text
 - is_ignored boolean default false
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
 - confidence_score integer
 - confidence_notes text
 - code_replaced boolean

zachbase_invites
 - email text primary key
 - code text
 - is_active boolean default true
 - created_at timestamp with time zone default now()
 - updated_at timestamp with time zone default now()
```


### Views

_None_


### Functions

```
function api_daisyui_components(_limit integer DEFAULT 10) returns record
function api_mantine_components(_limit integer DEFAULT 10) returns record
function api_webawesome_components(_limit integer DEFAULT 10) returns record
function search_patterns(query text, limit_count integer) returns record
```

