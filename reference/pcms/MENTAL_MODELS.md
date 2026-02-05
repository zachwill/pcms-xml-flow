# PCMS mental models (frontend-derived)

> Source: copied from `/Users/zachwill/blazers/rotation/pcms/MENTAL_MODELS.md`.
>
> This is a **reference implementation memo** derived from the official NBA PCMS frontend bundle.
> It is intentionally kept close to the mechanics/edge-cases/rounding rules PCMS encodes.
>
> Use this alongside:
> - Official write-ups + examples in `~/blazers/cba-docs/{cba,ops}` (external, not in this repo)
> - Our Postgres truth in `pcms.*` warehouses + `pcms.fn_*` primitives

---

# PCMS mental models (frontend-derived)

This is a **language-agnostic** write-up of the most important “how PCMS thinks” rules we found embedded in the PCMS frontend bundle (`script.js` in this folder; in the parent repo it lives at `pcms/script.js`).

It’s meant to be shared with folks working in **Postgres / Python / TypeScript / Ruby / etc** so they can reimplement the same computations against our own data in the Postgres **`pcms` schema**.

> Source of truth: the PCMS AngularJS bundle (`script.js`) acts like a *reference implementation*.
> Where helpful, this doc includes pointers to the relevant helper/service name so you can grep the bundle.

---

## Glossary

- **LK / “lookup code”**: PCMS uses short string codes everywhere (e.g. `contractTypeLk`, `transactionTypeLk`).
- **YSV**: *Yearly System Values* (season boundaries, cap/tax/apron thresholds, key dates like trade deadline).
- **YSS**: *Yearly Salary Scale* (min salary tables by years of service).
- **Duty days**: day-counts inside the playing season used for proration.
- **Cap / Tax / Apron / MTS**: parallel “views” of salary/budget.
  - Apron often includes **first apron** and **second apron**.
- **A1 / A2**: hard cap levels (First Apron / Second Apron).

---

## 1) Lookups are the spine of the system (not “constants”)

**Mental model:** PCMS is not a small set of hardcoded enums. Most “rules inputs” are delivered as a big lookup payload (commonly `lookups/all`) and treated as a global dictionary.

What that means operationally:

- Most computations are parameterized by values in lookups:
  - season boundaries (`firstDayOfSeason`, `lastDayOfSeason`)
  - playing season dates (`playingStartDate`, `playingEndDate`)
  - cap/tax/apron thresholds (`capAmount`, `taxLevel`, `taxApron`, `taxApron2`)
  - `daysInSeason` (used in nearly every proration)
  - minimum salary scales (YSS tables by years-of-service)
  - transaction type metadata (what fields apply, how to interpret the transaction)

- PCMS caches lookups aggressively in the browser:
  - compressed JSON stored in LocalStorage
  - a server-side `lookups/hash` tells the client when it must reload

**Implementation takeaway:** any serious reimplementation needs a reliable “lookup layer”:

- Either normalized dimension tables (recommended), or
- A cached lookup JSON blob with *league + season versioning*

In our DB, lookups-ish concepts live across:

- `pcms.lookups` (code tables)
- `pcms.league_system_values` (YSV-like season/system values)
- `pcms.league_salary_scales` (YSS-like minimum salary scales)

---

## 2) Season/year is derived from date boundaries (not just `YYYY`)

**Mental model:** “What season does this transaction/signing/trade belong to?” is answered by checking where the date falls between season boundary dates.

PCMS has a canonical helper (frontend): `Lookups.getSeasonYearlyValue(league, date)`.

### 2.1 Algorithm (language-agnostic)

Inputs:

- `league_lk` (e.g. `NBA`, `WNBA`, `DLG`)
- `date` (timestamp)
- `YSVs[league_lk][year]` where each YSV has:
  - `first_day_of_season`
  - `last_day_of_season`

Algorithm:

```text
1) Convert `date` to a “date without time”, using the same timezone convention everywhere.
   PCMS normalizes to NY-time day boundaries.

2) Search candidate YSV years around the date’s calendar year
   (PCMS checks previous/current/next to handle seasons that span years).

3) Return the YSV where:
     first_day_of_season <= date_without_time <= last_day_of_season

4) If no match, return null/undefined.
```

### 2.2 Implementation pitfalls

- **Timezone matters.** PCMS effectively treats “days” as NY-local days.
- The comparison is **inclusive** (<= / >=).
- Always treat “season year” as derived data, not as `date.year`.

### 2.3 SQL analogue (rough)

```sql
select league_lk, salary_year
from pcms.league_system_values
where league_lk = 'NBA'
  and date '2026-02-01' between season_start_at::date and season_end_at::date;
```

(You may need to adjust columns/timezones depending on your schema.)

---

## 3) Duty days + proration is the core time-based unit

**Mental model:** once you know the season (YSV), you can compute duty days, and duty days drive proration for multiple areas (min deals, two-ways, waiver amounts, trade bonus proration, etc.).

Canonical helpers live in the frontend `ContractHelperService`.

### 3.1 “Available duty days from start”

```text
start = max(signing_date, ysv.playing_start_date)
end   = ysv.playing_end_date

available_duty_days = (end - start) + 1
available_duty_days = clamp(available_duty_days, 0, ysv.days_in_season)
```

Notes:
- The `+ 1` is important: days are counted inclusively.
- The clamp avoids negative duty days and avoids exceeding season length.

### 3.2 “Duty days served as-of a date”

```text
start = max(signing_date, playing_start_date)
end   = min(as_of_date, playing_end_date)

duty_days = (end - start) + 1
if duty_days < 0: duty_days = 0
```

### 3.3 Generic proration helper

PCMS uses **whole-dollar rounding** (no cents):

```text
prorated = round(default_salary * duty_days / ysv.days_in_season)
```

**Implementation takeaway:** if you build a shared library for “PCMS-like computations”, put these duty day functions at the bottom and reuse them.

---

## 4) Trade logic: multiple non-obvious rules are encoded client-side

**Mental model:** “trade math” in PCMS is not just one equation. It composes:

- salary composition rules
- option-year handling
- bonus inclusion rules (and bonus flipping)
- cap hold adjustments for roster spot minimums
- hard cap (apron) validations

The canonical cluster is the frontend `TradeHelperService` + trade-related Angular filters.

### 4.1 Trade bonus calculation (high-level)

PCMS’s trade bonus computation is roughly:

1) Determine the season (YSV) for the **trade date**.
2) Compute remaining-season compensation for the current year (duty-day proration).
3) Add future-season compensation, with option-year rules (ETO has special casing).
4) Compute total trade bonus:

```text
total_trade_bonus = round(total_remaining_comp * trade_bonus_percent / 100)

# apply cap/limit
trade_bonus_limit = explicit_limit ?? contract.trade_bonus_amount
if trade_bonus_limit is not null:
  total_trade_bonus = min(total_trade_bonus, trade_bonus_limit)
```

5) Apportion the total bonus across seasons using **skill protection weighting**.
6) Apply rounding rules (PCMS uses `floor` for some allocations, then distributes remainder pennies).
7) If a revised trade bonus exists for the current season, it overrides the calculated value.

#### 4.1.1 Key required input fields

To replicate PCMS’s trade bonus calculation, you generally need:

- Contract/version:
  - `tradeBonusPercent`
  - `tradeBonusAmount` (cap)
  - `salaries[]` (per-year)
- Salary rows:
  - `salaryYear`
  - `totalBaseComp`
  - `skillProtectionAmount`
  - option fields: `optionLk`, `optionDecisionLk`
  - possible override: `revisedTradeBonus`
- YSV (from trade date):
  - `systemYear`
  - `playingEndDate`
  - `daysInSeason`

#### 4.1.2 Important edge behavior

- **No cents.** PCMS ultimately returns whole-dollar amounts.
- **ETO handling is special.** Exercised ETO years can change whether comp is included and how proration works.
- **Skill protection weighting** is used to allocate bonus across years.

#### 4.1.3 Reference pseudocode (close to PCMS)

This is intentionally “mechanical” so it can be translated to SQL/Python/TS/etc.

```text
ysv = season_for_date('NBA', trade_date)
playing_end = ysv.playing_end_date
full_season_duty_days = ysv.days_in_season

# remaining duty days in the current season
# duty_days_remaining = playing_end - trade_date + 1
# clamp to [0, full_season_duty_days]
duty_days_remaining = (playing_end - trade_date) + 1
duty_days_remaining = clamp(duty_days_remaining, 0, full_season_duty_days)

season_comp_remaining =
  round(duty_days_remaining/full_season_duty_days * current_season_salary.total_base_comp)

total_remaining_comp = season_comp_remaining

# protection weights
curr_prot_amt = current_season_salary.skill_protection_amount || 0
curr_prot_pct = curr_prot_amt / current_season_salary.total_base_comp

total_prot_pct = curr_prot_pct

salaries = concat(current_contract.salaries, future_contract.salaries)

is_eto_or_after = false
is_eto_exercised = false
is_eto_deleted = false

for salary in salaries:
  if salary.salary_year <= ysv.system_year: continue

  option_year = (salary.option_lk && salary.option_lk != 'NONE')
  eto_option  = (salary.option_lk == 'ETO')
  exercised   = (salary.option_decision_lk in ['EXER','POE','TOE'])

  if (not option_year) or eto_option or exercised:
    if eto_option:
      is_eto_or_after = true
      if salary.option_decision_lk == 'ETOEX': is_eto_exercised = true
      if salary.option_decision_lk == 'ETODE': is_eto_deleted = true

    # remaining comp excludes exercised ETO year
    if not is_eto_exercised:
      total_remaining_comp += salary.total_base_comp

    # protection weights stop being prorated once you hit ETO,
    # unless the ETO was deleted
    if (not is_eto_or_after) or is_eto_deleted:
      salary.skill_protection_percent =
        (salary.skill_protection_amount || 0) / salary.total_base_comp
      total_prot_pct += salary.skill_protection_percent

protection_ratio =
  (total_prot_pct > 0) ? (curr_prot_pct / total_prot_pct) : 1

total_trade_bonus = round(total_remaining_comp * contract.trade_bonus_percent / 100)

# apply cap/limit
limit = (explicit_trade_bonus_limit is defined) ? explicit_trade_bonus_limit
                                               : contract.trade_bonus_amount
if limit is defined:
  total_trade_bonus = min(total_trade_bonus, limit)

current_year_bonus = floor(total_trade_bonus * protection_ratio)

# allocate remaining years using protection percent shares
allocated = 0
for salary in salaries:
  if salary.skill_protection_percent is not null:
    salary.calculated_trade_bonus =
      floor(total_trade_bonus * salary.skill_protection_percent / total_prot_pct)
    allocated += salary.calculated_trade_bonus

# distribute rounding remainder
for salary in salaries (in a stable order) while allocated < total_trade_bonus:
  salary.calculated_trade_bonus += 1
  allocated += 1

# revised override
if current_year_salary.revised_trade_bonus is not null:
  current_year_bonus = current_year_salary.revised_trade_bonus

return current_year_bonus
```

### 4.2 Trade cap holds adjustment (NBA)

PCMS encodes a non-obvious roster minimum rule when computing trade cap holds.

Inputs:
- `roster_count_pre` (from team salary snapshot)
- `num_sending`, `num_receiving`
- `min_salary_year1` (YSS minimum salary year 1)

Rule:

- Pre-trade minimum roster for “no holds”: **12**
- Post-trade (trade-specific) minimum roster for “no holds”: **13**

Formula:

```text
pre_holds  = max(0, 12 - roster_count_pre)
post_roster = roster_count_pre - num_sending + num_receiving
post_holds = max(0, 13 - post_roster)

cap_holds_adjustment = (post_holds - pre_holds) * min_salary_year1
```

### 4.3 Likely/unlikely bonus flipping (team-performance driven)

PCMS contains logic where certain team-based bonuses can **flip** between:

- likely (`LKLY`)
- unlikely (`ULKLY`)

based on team performance criteria (wins/playoff rounds).

Implementation implications:

- Your “trade salary” math can diverge from PCMS if you don’t replicate flipping.
- PCMS has a separate “should this bonus count?” rule that differs depending on whether you’re computing:
  - cap salary trade matching, vs
  - tax/apron ending salary (PCMS may include both likely and unlikely for tax/apron)

#### 4.3.1 Flip rule (simplified)

Inputs:

- `bonus` with fields like:
  - `teamBasedFlg`
  - `contractBonusTypeLk` (usually `LKLY` or `ULKLY`)
  - `bonusCriteria[]` (wins / playoffs criteria)
- `sent_flg` (boolean): whether the player/bonus is being sent away by this team
- `team_record` (season performance), e.g.:
  - `wins`
  - `playoffsLk`

High-level behavior:

```text
bonus.has_been_flipped = false

if not bonus.team_based: return
if bonus.type not in {LKLY, ULKLY}: return

# PCMS only flips in the context of the acquiring team (sent_flg == false)
if sent_flg != false: return
if team_record is null: return
if bonus.criteria is empty: return

meets_all_criteria = evaluate(bonus.criteria, team_record)

if bonus.type == 'ULKLY' and meets_all_criteria:
  bonus.has_been_flipped = true   # treated as likely
if bonus.type == 'LKLY' and not meets_all_criteria:
  bonus.has_been_flipped = true   # treated as unlikely
```

Criteria types PCMS evaluates include:

- `TWINS` (team wins) paired with an operator criterion (`BTWN`, `EQL`, `GT`, `GTE`, `LT`, `LTE`)
- playoff rounds (e.g. `PRND1`, `PRND2`, `PRND3`, `PRND4`, `CHAMP`), using a “round reached” ordering map

#### 4.3.2 Effective bonus type and “does it count?”

PCMS also defines an “effective” type:

```text
effective_type =
  bonus.has_been_flipped ? flip(LKLY <-> ULKLY) : bonus.contract_bonus_type_lk
```

And then uses a counting rule equivalent to:

```text
if computing_for_tax_or_apron:
  # for apron checks, PCMS includes both likely and unlikely
  return bonus.type in {LKLY, ULKLY}

# otherwise, only include bonuses that are effectively "likely" after flip
return (bonus.type == 'LKLY' and not bonus.has_been_flipped) or
       (bonus.type == 'ULKLY' and bonus.has_been_flipped)
```

### 4.4 Bonus maximums (“effective bonus amount”)

PCMS applies maximum constraints that transform raw bonus amounts into **effective bonus amounts**.

Mental model:

- Bonuses are not simply additive.
- Compute `effective_bonus_amount` only after applying max rules.

If you store bonuses in a DB, it’s often worth modeling:

- raw `bonus_amount`
- computed `effective_bonus_amount`

and being explicit about which one downstream calculations use.

### 4.5 Apron / hard-cap checks (A1 / A2)

PCMS treats apron constraints as a validation step over a computed **post-trade ending salary**.

High-level rule:

- If not hardcapped → “passes” (with a message)
- If hardcapped at first apron (A1):
  - fail if post-trade apron salary > `ysv.taxApron`
- If hardcapped at second apron (A2):
  - fail if post-trade apron salary > `ysv.taxApron2`

PCMS also checks a “next year / apron assumption” variant.

**Implementation note:** the hardest part is reproducing “ending salary” composition exactly (PCMS uses Angular filters that incorporate incoming/outgoing trade pieces and bonus inclusion rules). The mental model is: **compute post-trade salary under the apron lens, then compare to the apron threshold for the correct season.**

---

## 5) Waiver amounts: proration + protection floors + caps (NBA)

PCMS has a single helper that reads like a spec: `buildWaiverAmountForNba` (frontend `WaiverHelperService`).

### 5.1 Inputs you need

- Contract:
  - `contractTypeLk` (converted two-way vs normal)
  - `signingDate`
  - `convertDate` (if converted)
- Salary row for the waived player (per year):
  - `salaryYear`
  - `totalBaseComp`
  - `skillProtectionAmount`
  - `signingBonus`
  - `tradeBonusAmount`
  - `internationalPlayerPayment`
  - variance fields: `capTaxVarianceFlg`, `contractTaxSalaryAdjustment`, `contractTaxApronSalaryAdjustment`
  - caps: `contractCapSalary`, `contractTaxSalary`, `contractTaxApronSalary`, `contractMtsSalary`
  - option fields: `optionLk`
- YSV for `salaryYear`:
  - `playingStartDate`, `playingEndDate`, `daysInSeason`, `cutDownDate`
- External inputs:
  - `waivedYear` (season year waived)
  - `waiverClearDate`

### 5.2 Algorithm (simplified, but matches PCMS structure)

1) Choose signing date:

```text
signing_date = (contractTypeLk == 'REG2W') ? convertDate : signingDate
```

2) Compute duty days from start of season/signing to waiver clear:

```text
duty_days = (waiver_clear_date - max(playing_start, signing_date)) + 1
if duty_days > ysv.days_in_season: duty_days = ysv.days_in_season

# if clear date is after playing end, recompute using playing end
if waiver_clear_date > playing_end:
  duty_days = (playing_end - max(playing_start, signing_date)) + 1
```

3) Compute “full season duty days”:

```text
full_season_duty_days = (playing_end - max(playing_start, signing_date)) + 1
full_season_duty_days = min(full_season_duty_days, ysv.days_in_season)
```

4) Determine protection:

```text
protection = salary.skill_protection_amount

# after cut-down date, protection becomes full base comp
if waiver_clear_date >= ysv.cut_down_date:
  protection = salary.total_base_comp
```

5) Add “bonus amounts” into the waiver amount:

```text
bonus_amounts = signing_bonus + trade_bonus + international_player_payment
```

6) Compute cap + MTS value:

```text
is_future_year = (salary.salary_year > waived_year)

base = is_future_year ? protection
                    : max(total_base_comp * duty_days/full_season_duty_days, protection)

cap_value = round(base) + bonus_amounts
mts_value = cap_value
```

7) Compute tax + apron value (as implemented in PCMS):

```text
if salary.cap_tax_variance_flg:
  if salary.total_base_comp == protection:
    # fully protected: no duty-day proration
    tax_value = salary.total_base_comp + salary.contract_tax_salary_adjustment
    apron_value = tax_value
  else:
    base = is_future_year ? protection
                        : max((salary.total_base_comp + salary.contract_tax_apron_salary_adjustment)
                              * duty_days/full_season_duty_days,
                              protection)
    tax_value = round(base) + bonus_amounts
    apron_value = tax_value
else:
  base = is_future_year ? protection
                      : max(salary.total_base_comp * duty_days/full_season_duty_days, protection)
  tax_value = round(base) + bonus_amounts
  apron_value = tax_value
```

Note: in the “fully protected + cap-tax variance” branch above, the PCMS frontend does **not** add `bonus_amounts` before capping. If you need strict parity, copy that behavior.

8) Cap the computed values at the contract’s applicable salary caps:

```text
cap_value   = min(cap_value,   contract_cap_salary)

tax_value   = min(tax_value,   contract_tax_salary)

apron_value = min(apron_value, contract_tax_apron_salary)

mts_value   = min(mts_value,   contract_mts_salary)
```

9) Default option decision suggestions:

```text
if option_lk == 'ETO':  option_decision_lk = 'ETODE'
if option_lk == 'TEAM': option_decision_lk = 'WTOPT'
if option_lk == 'PLYR': option_decision_lk = 'WVPF'
if option_lk == 'PLYTF': option_decision_lk = 'WVTF'
else: option_decision_lk = null
```

### 5.3 Notes / gotchas

- The function treats **future years** differently (`max = protection`) — it does not prorate base comp in future years.
- PCMS is very explicit about not overpaying if waiver clear occurs after playing end.
- The code also attempts to provide fallback playing start/end dates if YSV lacks them (Oct 28 / Apr 15 or Apr 14 in leap years). In practice, you should implement this fallback using the relevant season year.

---

## 6) General implementation notes (for any language)

1) **Be explicit about rounding.** PCMS mixes `round()` and `floor()` in places (especially trade bonus allocation). Document your rounding in code.

2) **Treat monetary amounts as integers.** PCMS generally operates in whole dollars with “no cents”.

3) **Normalize dates to a consistent timezone/day boundary** before doing season matching or duty day math.

4) **Model raw vs effective values.** Bonuses are the obvious example.

5) **Test against fixtures.** If you want to be PCMS-compatible, build a small set of test vectors from your snapshots and assert that your outputs match.

6) **Be consistent about field naming.** PCMS payloads are mostly **camelCase** (e.g. `tradeBonusPercent`). Our Postgres tables are **snake_case** (e.g. `trade_bonus_percent`). Map explicitly and keep a small glossary in your code.

---

## Appendix: Where to look in this repo

- `specs/scriptjs-domain.md` – a curated write-up with more pointers back into `script.js`
- `specs/_generated/` – generated indexes for navigating `script.js` quickly
  - services / filters / endpoints / field usage

Regenerate indexes:

```bash
python3 scripts/extract_scriptjs_index.py --script script.js --out-dir specs/_generated
```
