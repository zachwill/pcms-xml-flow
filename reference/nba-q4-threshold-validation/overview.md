# Q4 _Closeout_ Thresholds

> Does the NBA _Closeout_ table hold in post-COVID regular season games?

**Data:** 2,988 close games (final margin ≤ 10), season ≥ 2021.

---

## 1. How the Table Holds Up (exact closeout-time snapshots)

Win rates at each threshold, measured at the table’s closeout time:

| Lead | _Closeout_ | Games | Wins | Losses | Win% |
|---:|:---:|---:|---:|---:|---:|
| 4 | 00:01 | 1,959 | 1,959 | 0 | **100.00%** |
| 5 | 00:04 | 1,680 | 1,679 | 1 | **99.94%** |
| 6 | 00:09 | 1,382 | 1,382 | 0 | **100.00%** |
| 7 | 00:16 | 1,069 | 1,069 | 0 | **100.00%** |
| 8 | 00:25 | 759 | 759 | 0 | **100.00%** |
| 9 | 00:36 | 543 | 543 | 0 | **100.00%** |
| 10 | 00:49 | 368 | 368 | 0 | **100.00%** |

**Bottom line:** At exact closeout-time snapshots, 6/7 rows are perfect (100%). Only lead ≥5 at 00:04 has a miss (1 loss in 1,680).

---

## 2. First-Loss Analysis (full time sweep)

“First loss” = earliest second remaining where at least one team with lead ≥ L eventually lost.

| Lead | _Table Says_ | First Loss | Empirical 100% | Verdict |
|---:|:---:|:---:|:---:|:---|
| 4 | 00:01 | 00:03 | 00:02 | ✓ Table is safe |
| 5 | 00:04 | 00:04 | 00:03 | ⚠️ Borderline (1s late) |
| 6 | 00:09 | 00:10 | 00:09 | ✓ Exact match |
| 7 | 00:16 | 00:19 | 00:18 | ✓ Table is safe |
| 8 | 00:25 | 00:27 | 00:26 | ✓ Table is safe |
| 9 | 00:36 | 00:27 | 00:26 | ⚠️ Sensitive to interpretation |
| 10 | 00:49 | 02:03 | 02:02 | ✓ Very conservative |

---

## 3. Key Findings

1. **The table is very strong at exact snapshot times.**
   - 6 thresholds are 100%.
   - The only non-100% threshold is lead ≥5 at 00:04.

2. **Lead ≥6 at 00:09 is directly supported.**
   - 1,382 games, 0 losses.

3. **Lead ≥10 at 00:49 is conservative.**
   - 368 games, 0 losses at that snapshot.
   - First observed loss in the sweep appears much earlier (02:03 remaining).

4. **Lead ≥9 needs careful wording.**
   - At the exact 00:36 snapshot: 543/543.
   - In full sweep logic (any time ≤ closeout), losses appear by 00:27.

---

## Queries used

- Exact closeout-time counts:  
  `reference/nba-q4-threshold-validation/sql/q4_closeout_table_counts.sql`
- Full sweep / first-loss table:  
  `reference/nba-q4-threshold-validation/sql/q4_threshold_sweep_4_10.sql`
- Starter pull timing sweep (coach behavior):  
  `reference/nba-q4-threshold-validation/sql/q4_starter_pull_sweeps.sql`
