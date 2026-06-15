---
title: "The PROST v2 Pension Microsimulation Model"
subtitle: "Technical Methodology Document"
author: "World Bank — PROST Team"
date: "June 2026"
lang: en
---

# Executive summary

This document describes, in technical detail, the methodology implemented in the
Stata (`.do`) programs that build the **PROST v2** pension model for Mexico
(country code `MEX`). The model comprises two major blocks:

1. **Preprocessing** (steps 01–06): starting from the longitudinal microdata of
   IMSS affiliates and from the beneficiary microdata, it estimates the model
   inputs: the base-year affiliate dataset, the pensioner database, affiliation
   rates, labor-market transition models, life-cycle wage-growth profiles, and
   retirement/disability/survivor incidence rates.
2. **Projection** (`1 - PROSTv2 - Build projection database.do`): a stochastic,
   individual-level microsimulation, month by month, that projects affiliates
   and pensioners over an 80-year horizon.

The preprocessing of the **affiliation rates** (step 03) and of the **transition
models** (step 04) exists in four variants depending on data availability —
*full*, *very low data*, *low data*, and *extremely low data*; the rest of the
pipeline is common to all four.

> **Note on the scope of the code.** Some components are specified but not yet
> implemented in this version (disability and survivorship, defined-contribution
> account accumulation, NPV-based retirement decision). They are flagged
> explicitly as *pending* in the relevant sections.

---

# 1. Introduction and architecture

## 1.1 Purpose of the model

PROST v2 is an actuarial **microsimulation** model of the pension system. Unlike
an aggregate cell-based model, it maintains the state of each individual
(affiliate or pensioner) and simulates their demographic and labor-market
transitions probabilistically. This allows it to compute, year by year, the
flows of new contributors, exits and re-entries to formal employment, newly
granted pensions, pension amounts, and indexation, disaggregated by age, sex,
wage decile, and pension type.

## 1.2 Pipeline flow

```
  Client microdata (IMSS)                      Default inputs (Defaults/)
  ├─ affiliate longitudinal panel (.dta)       ├─ population (projected + historical)
  └─ beneficiaries (.dta)                       ├─ mortality (projected + observed)
            │                                   ├─ wage growth (CPI)
            ▼                                   └─ assumptions (labor market, indexation)
  PREPROCESSING
  01  baseyear_data_MEX.dta        (base-year affiliate dataset)
  02  pensioners_MEX.dta           (reclassified pensioner database)
  03  affiliation_MEX_10.csv       (affiliation rates by age/sex)        [4 variants]
  04  job_exit / job_entry models  (cloglog exit/entry hazards)          [4 variants]
  05  lifecycle_wages_MEX          (wage-growth profile)
  06  retirement/disability/survivor_rates_MEX.csv  (incidence rates)
            │
            ▼
  PROJECTION  (1 - PROSTv2 - Build projection database.do)
  Initialization → annual loop (2025–2104) × monthly loop (1–12)
  → Outputs: final affiliate and pensioner databases + annual reports
```

## 1.3 The four data environments

The model is designed to function even when longitudinal microdata are limited.
The affiliation rates (step 03) and the transition models (step 04) have four
variants:

| Environment | Available data | Strategy |
|---|---|---|
| **Full** | Complete longitudinal panel (several years × months per person) | Affiliation dates and month-to-month transitions are observed directly. |
| **Very low data** | Cross-section with tenure (`loa`), no monthly filter | Year/age of affiliation is reconstructed from tenure. |
| **Low data** | Cross-section with tenure, December only | As *very low* but using the December snapshot to reduce duplication. |
| **Extremely low data** | Cross-section with tenure + contribution density (`dens`) | Affiliation is reconstructed and a statistical expansion factor (ZOIB regression) corrects the undercount of non-contributors. |

## 1.4 Conventions and coding

| Variable | Codes |
|---|---|
| `gender` | 1 = male, 2 = female |
| `status` (affiliates) | 1 = alive/affiliated, 2 = retired, 3 = disabled, 4 = widow(er)/survivor, 99 = deceased |
| `pension_class` | 1 = defined benefit (DB), 2 = defined contribution (DC) |
| `pension_type` | 1 = old-age, 2 = disability, 3 = survivor |
| `pension_id` | 1 OA-DB, 2 Dis-DB, 3 Surv-DB, 4 OA-DC, 5 Dis-DC, 6 Surv-DC |
| `dens` | 1 = contributes this month, 0 = does not (informal/unemployed) |
| `los` | *length of service*: cumulative months with contributions |
| `loa` (`aux`) | *length of affiliation*: months since first affiliation |

---

# Part I — Preprocessing

# 2. Preprocessing steps

## 2.1 Step 01 — Base-year dataset

**Program:** `01 - Pre-processing - Generate baseyear dataset.do`
**Input:** `2 Input from client - longitudinal microdata about affiliates.dta`
**Output:** `baseyear_data_MEX.dta`

**Purpose.** Build, from the longitudinal panel, the set of affiliates for the
most recent year with the state variables required by the microsimulation.

**Method.**

1. The most recent year is determined: `latest_year = max(year)`.
2. Cleaning and age: `aux` is renamed to `loa`; `age = year − yob`.
3. **Spell identification.** Sorting by `id` and date `date = ym(year, month)`, a
   new spell is flagged when density or person changes, and the length of each
   spell is computed:
   ```stata
   generate byte new_spell = (dens != dens[_n-1] | id != id[_n-1])
   generate spell_id = sum(new_spell)
   bysort spell_id: generate spell_length = _N
   ```
4. **Relative wage index.** The wage relative to the annual mean is built and the
   last known value is carried forward:
   ```stata
   bysort year: egen mean_wage_yr = mean(wage)
   generate wage_relative_mean = wage / mean_wage_yr
   carryforward wage_relative_mean, replace
   ```
5. **Wage deciles.** The reference decile is assigned using the relative wage of
   the most recent December and propagated as the person's "true" decile; those
   not contributing (`dens==0`) receive decile 0. A within-cell decile (by year,
   age, sex) is also computed.
6. Daily-to-monthly wage conversion: `wage = wage × 20` (20 working days).
7. The most recent year is kept, `status = 1` is initialized (everyone alive),
   and the base dataset is saved.

## 2.2 Step 02 — Pensioner database

**Program:** `02 - Pre-processing - Generate beneficiary database.do`
**Input:** `3 Input from client - microdata about beneficiaries.dta`
**Output:** `pensioners_MEX.dta`

**Purpose.** Reclassify the beneficiary microdata into pension class, type, and
identifier.

**Method.** Records with an empty `type` are dropped (to align counts with the
aggregate totals). From the `type` letter the following are constructed:

| `type` | `pension_class` | `pension_type` | `pension_id` |
|---|---|---|---|
| B | 1 (DB) | 1 (old-age) | 1 |
| C | 1 (DB) | 2 (disability) | 2 |
| D | 1 (DB) | 3 (survivor) | 3 |
| E | 2 (DC) | 1 (old-age) | 4 |
| F | 2 (DC) | 2 (disability) | 5 |
| G | 2 (DC) | 3 (survivor) | 6 |

`monthlybenefit` is renamed to `pension_benefit`, `iden` (not unique) and `type`
are dropped, and the database is saved.

## 2.3 Step 03 — Affiliation rates

**Program:** `03 - Pre-processing - Generate affiliation rates.do` (+ 3 variants)
**Outputs:** `affiliation_MEX_10.csv` (and its `_LOW_DATA`, `_VERY_LOW_DATA`,
`_EXTREMELY_LOW_DATA` counterparts)

**Purpose.** Estimate the rate of **new affiliates** by age and sex, defined as:

```
affiliation_rate(age, sex) = new_affiliates / (population × 1000)
```

(population is in thousands, hence the factor of 1000). These rates are used in
the projection to generate the new-entrant cohorts each year.

**Method (full version).**

1. Age is computed, `age >= 15` is filtered, and the last 10 years are kept
   (`year > latest_year − 10`).
2. **New-affiliate filter:** `keep if los == 1 & aux == 1` (first month of
   service and of affiliation).
3. New affiliates are counted by (year, age, sex) with `collapse (count)`.
4. The earliest year is dropped (affiliation would be overstated at the start of
   the record).
5. The data are merged with historical population
   (`population_historical_MEX.dta`), numerator and denominator are aggregated by
   (age, sex), and the rate is computed.

**Differences across data environments.**

| Aspect | Full | Very low | Low | Extremely low |
|---|---|---|---|---|
| Input | Longitudinal panel | `verylowdata_MEX.dta` | `lowdata_MEX.dta` | `extremelylowdata_MEX.dta` |
| Year/age of affiliation | Observed | Reconstructed `year − floor(loa/12)` | Reconstructed | Reconstructed |
| New-affiliate identification | `los==1 & aux==1` | Imputed from tenure | Imputed | Imputed |
| Temporal filter | Earliest year dropped | All months | `month==12` only | All months |
| Non-contributor adjustment | — | — | — | **ZOIB expansion factor** |
| Counting | `count` of `id` | `count` of `id` | `count` of `id` | `sum` of `expansion_factor` |
| Output | `affiliation_MEX_10.csv` | `..._VERY_LOW_DATA.csv` | `..._LOW_DATA.csv` | `..._EXTREMELY_LOW_DATA.csv` |

**Detail of the expansion factor (extremely low data).** Since only the year's
contribution density (`dens`, months contributed) is observed, the contributed
proportion `dens_share = dens/12` is modeled with a **zero-and-one inflated Beta
(ZOIB) regression**:

```stata
zoib dens_share i.gender, oneinflate(age i.gender)
```

From the predictions the Beta parameters (`alpha`, `beta`), the implied
probability of zero contributions, and an expansion factor
`expansion_factor = 1/(1 − implied_p_zero)` are derived; the latter inflates the
affiliate count to compensate for the under-registration of those who do not
contribute every month.

**Parameters.** `years_avg = 10` (year window), `minimum_age = 15`.

## 2.4 Step 04 — Labor-market transition models (T1 / T2)

**Program:** `04 - Pre-processing - Estimate transitions rates.do` (+ 3 variants)
**Outputs:** estimates `job_exit_model_MEX_10_final` and
`job_entry_model_MEX_10_final`

**Purpose.** Estimate the monthly probability of **exiting** formal employment
(T1) and of **entering/re-entering** formal employment (T2) as functions of
individual characteristics. These hazards are applied month by month in the
projection.

**Variable construction.** Over the panel (sampled at `samplesize`%): current
spell length (`spell_length`), contribution density
`contribution_density = los/loa` and its log `log_cod = log(max(cod, 0.001))`,
eligibility gaps (`age_gap`, `los_gap`, `pension_gap`), relative wage, and
reference decile. The last `years_avg = 10` years and `age >= 15` are kept. The
transition is defined using the following month's state:

```stata
generate current_state = (wage_decile > 0)        // contributes now
generate next_state    = (f.wage_decile > 0)      // contributes next month
generate transition_in  = (current_state==0 & next_state==1) if current_state==0
generate transition_out = (current_state==1 & next_state==0) if current_state==1
```

**Models (complementary log-log / cloglog).**

- **T1 — job exit** (over months with `dens==1`):
  ```stata
  cloglog transition_out  c.spell_length##i.wage_decile_ref  c.age##c.age  ///
                          i.gender  c.los_gap                    , cluster(id)
  ```
- **T2 — job entry** (over months with `dens==0`, adds `log_cod`):
  ```stata
  cloglog transition_in   c.spell_length##i.wage_decile_ref  c.age##c.age  ///
                          i.gender  c.log_cod  c.los_gap        , cluster(id)
  ```

where `c.x` denotes a continuous covariate, `i.x` categorical, `##` a full
interaction (including main effects), and `c.age##c.age` produces the quadratic
term in age. Standard errors are clustered by `id` (this does not alter the
point coefficients or the predicted hazards). The monthly hazard is recovered as
`p = 1 − exp(−exp(xb))`.

**Differences across environments.** The *very/low/extremely low data* variants
estimate the same models with progressively reduced covariate sets, according to
the information available in each data cut.

## 2.5 Step 05 — Life-cycle wage-growth profiles

**Program:** `05 - Pre-processing - Generate life cycle wage growth profiles.do`
**Output:** estimates `lifecycle_wages_MEX`

**Purpose.** Estimate wage growth **relative to aggregate growth** by sex, age,
and decile, in order to project heterogeneous individual wage trajectories.

**Method.**

1. Wage relative to the annual mean and reference deciles (as in step 04).
2. Workers near retirement with sufficient contributions are dropped
   (`drop if los_gap==0 & age >= early_retage`, with `early_retage = 60`) to
   avoid selection bias.
3. Data are collapsed to the cohort level (`yob`, sex, decile, year) and the
   following are computed:
   - cohort growth: `wage_growth_cohort = 100·(wage − L.wage)/L.wage`
   - global growth: `wage_growth_global = 100·(mean_wage_yr − L.mean_wage_yr)/L.mean_wage_yr`
   - **relative growth:** `wage_growth_relative = 100·wage_growth_cohort/wage_growth_global`
4. Outliers outside mean ± 3 standard deviations are filtered (`reg_include_flag`).
5. **Regression** with a full three-way interaction:
   ```stata
   regress wage_growth_relative  i.wage_decile#i.gender#i.age  if reg_include_flag
   ```
   The estimates are stored and used to predict relative growth by cell (decile,
   sex, age).

**Parameters.** `minimum_age = 15`, `early_retage = 60`,
`retcont_min = (750/52)·12 ≈ 173.08` months, outlier trimming at 3 SD.

## 2.6 Step 06 — Retirement, disability, and survivor rates

**Program:** `06 - Pre-processing - Generate retirement disability survivor rates.do`
**Outputs:** `retirement_rates_MEX.csv`, `disability_rates_MEX.csv`,
`survivor_rates_MEX.csv`

**Purpose.** Derive incidence rates (by age and sex) of new old-age, disability,
and survivor pensions, adjusted for cohort mortality, from the beneficiary
database.

**Method.**

1. **Mortality and cohort survival.** Observed mortality
   (`mortality_obs_MEX.csv`) is imported, reshaped to long format, and
   *backfilled* (1850–1949) to cover long-lived cohorts. For each cohort
   (defined by `birth_year = year − age`), survival is accumulated:
   ```stata
   generate log_surv_increment = log(1 - mortality_rate)
   bysort gender birth_year (age): generate cum_log_surv = sum(log_surv_increment)
   generate survival_rate = exp(cum_log_surv)        // S(a) = ∏ (1 − q(x))
   ```
2. **Count of new pensions** by (age, sex, start year, type) and reshape to
   columns `oa_pension`, `disa_pension`, `survivor_pension`.
3. **Age at pension start:** `age_start = max(age − (baseyear − year), 0)`.
4. **Cohort mortality adjustment.** To recover the original size of the cohort
   that entered the pension, the count is divided by the survival ratio between
   the base year and the start year:
   ```stata
   generate oa_pension_adj = oa_pension / (survival_rate_now / survival_rate_start)
   ```
   (analogous for disability and survivor).
5. **Normalization to rates** by dividing by the reference population
   (`pop × 1000`), filtering to the last `include_years = 20` years, and
   averaging by (age, sex). The three CSVs are exported.

**Parameters.** `include_years = 20`; age top-coded at 100; mortality backfill
1850–1949; sex coded 1/2 and type 1/2/3.

---

# Part II — Projection (microsimulation)

# 3. Building the projection database

**Program:** `1 - PROSTv2 - Build projection database.do` (~2,807 lines)

## 3.1 Simulation parameters

| Parameter | Value | Meaning |
|---|---|---|
| `baseyear` | 2024 | Base year of the microdata |
| `startyear` | 2025 | First projected year (`baseyear + 1`) |
| `endyear` | 2104 | Last projected year |
| `horizon` | 80 | Projection years |
| `samplesize` | 10 | Sample size (% of population; weight = 100/samplesize) |
| `seed` | 2 | Random-number-generator seed (reproducibility) |
| `working_age_min/max` | 15 / 64 | Working ages |
| `max_eligibility_age` | 75 | Cut-off age with no reasonable hope of eligibility |
| `wage_adjustment` | 9878.469/7048.628 ≈ 1.402 | Wage adjustment 2020→2024 (ILO) |
| `country` / `simname` | MEX / "Baseline" | Country / scenario |

**Policy parameters (pension system).** Retirement age 65 (both sexes); minimum
service requirement `p_min_service_req = 750/52 ≈ 14.42` years; accrual rate
`p_accrual = 4%` per year of service capped at `p_accrual_max = 75%`;
early-retirement penalty `p_delta = 4%`/year and late-retirement bonus
`p_lambda = 4%`/year; forced retirement at age 99; base minimum pension
`p_minpen_base = 2,622` (with adjustments for age, tenure, and wage); discount
rate `p_discount_rate = 3%` (for the NPV retirement decision, pending). The
reference-wage calculation supports three modes (`ref_wage_type`): rolling
average, best N years, or best N within the last M.

## 3.2 Inputs

The following are loaded: population by age/sex/year (`population_MEX.csv`),
mortality (`mortality_MEX.csv`), affiliation rates (`affiliation_MEX_10.csv`),
the transition models from step 04, the wage model from step 05, aggregate wage
growth (`cpi_MEX.csv`), the labor-market (`labor_market_assumptions.csv`) and
indexation (`indexation_assumptions_MEX.csv`) assumptions, and the base
affiliate (`baseyear_data_MEX.dta`) and pensioner (`pensioners_MEX.dta`)
databases. Series with a horizon shorter than the projection are held constant at
their last available year.

## 3.3 Initialization

**Affiliates.** Deduplicated by `id`, sampled at `samplesize`%, and assigned
weight `wgt = 100/samplesize`. Each individual carries: `status`, `age`,
`gender`, `yob`, `wage_decile` (and `wage_decile_ref`), random
`birthmonth`/`deathmonth`, `los`, `loa`, `dens`, `contribution_density`, `wage`,
`wage_ref` (wage at exit, for re-entry), `spell_length`, and the eligibility gaps
(`age_gap`, `los_gap`, `pension_gap`) with an eligibility group: 1 = age-
constrained, 2 = service-constrained, 3 = no reasonable hope. The base wage is
brought to the base year via `wage_adjustment`.

**New-affiliate cohorts (annual).** For each year,
`new_affiliates = round(affiliation_rate × pop, 1)` is computed from population
and affiliation rates; expanded, assigned a random decile
`runiformint(1,10)`, sampled, and saved as tempfiles `affiliates2025 …
affiliates2104`.

**Pensioners.** The pensioner base is sampled, `status = 2` and
`pensioner_source = "observed"` are assigned, along with tracking variables
(`died_flag`, `age_died`, `pension_index`).

## 3.4 The affiliate simulation loop

The simulation runs an **annual loop** (`yr = 2025…2104`) with a nested
**monthly loop** (`month = 1…12`).

### 3.4.1 Annual setup

1. **New cohorts** for the year are appended and initialized (`status=1`,
   `los=0`, `loa=0`, `dens=1`, start month).
2. **Expansion to months** of the year.
3. **Eligibility indicators** (year-invariant): age gap
   `age_gap = max(retage − age,0)·12`, service gap
   `los_gap = max(12·p_min_service_req − los, 0)`, `pension_gap = max(age_gap,
   los_gap)`, implied retirement age, and eligibility group (1/2/3).
4. **Mortality:** rates are merged and the draw
   `randnum_mortality = runiform()` is generated.
5. **Labor-market transition rates:** the cloglog hazards are predicted
   (`p = 1 − exp(−exp(xb))`) for exit and entry.
6. **Adjustment to labor-market targets:** the hazards are rescaled by factors
   `outflow_adjustment` and `inflow_adjustment` so that the aggregate employment
   rate and turnover match the year's assumptions (`emp_rate_growth`,
   `turnover_target`).

### 3.4.2 Monthly operations

For each month:

1. **Aging:** `age = age + 1` in the birth month.
2. **Mortality:** `status = 99` if `mortality > randnum_mortality` in the death
   month; wage and `dens` are zeroed.
3. **Labor-market transitions (stochastic):**
   ```stata
   replace exiter    = (runiform() < transition_out & wage_decile > 0)
   replace reentrant = (runiform() < transition_in  & wage_decile == 0)
   ```
   Exiters save `wage_ref`, move to `dens=0` and `wage_decile=0`; re-entrants
   recover their reference decile. `spell_length` resets to 1 on any transition.
4. **Metric updates:** `dens = (wage_decile>0)`; `los` increments only if
   contributing; `loa` always; `contribution_density`, `log_cod`, `los_gap`, and
   `pension_gap` are recomputed.
5. **Wage assignment** to new entrants and re-entrants: drawn from the decile
   distribution, truncated to its bounds
   `wage = max(min(rnormal(μ, σ), max), min)`; re-entrants with `wage_ref`
   recover their previous wage.

### 3.4.3 Annual wage dynamics

After the monthly loop: the **relative** growth per cell (decile/sex/age) is
predicted with the step-05 model, applied together with the year's aggregate
growth, and then a **macro adjustment** ensures the simulated average wage growth
exactly matches the user's assumption:

```stata
local wage_adjustment_factor = (1 + wage_growth_user) / (1 + wage_growth_obs)
replace wage = wage × wage_adjustment_factor
```

### 3.4.4 Eligibility and pension calculation

1. **Revalorization of the reference wage** according to `ref_wage_type`, with
   rate:
   ```
   p_revalorization_rate = (c_infl·pindex_inflation + c_rw·pindex_realwage
                            + c_anchor·pindex_anchor) / 100
   ```
2. **Reference wage:** covered wage bounded to `[p_min_income, p_max_income]`,
   aggregated per person; the reference wage is updated as a rolling average or as
   the average of the best N years, depending on the mode.
3. **Eligibility** (conjunction of conditions):
   ```stata
   pension_elig_mincont = ((los/12) >= p_min_service_req)
   pension_elig_delta   = (age >= retage − 1/p_delta)
   pension_elig_early   = (age >= p_retage_early)
   pension_elig = pension_elig_mincont & pension_elig_delta & pension_elig_early
   ```
4. **Replacement rate** and **base benefit:**
   ```
   replacement_rate = yos·p_accrual − years_early·p_delta + years_late·p_lambda
   replacement_rate = max(min(replacement_rate, p_accrual_max), 0)
   pension_benefit_base = reference_wage · replacement_rate · pension_elig
   ```
5. **Minimum and maximum pension.** The minimum starts from `p_minpen_base` and
   is adjusted by age, years of service, and wage (with level/percentage
   coefficients and steps). The final benefit is bounded:
   ```
   pension_benefit = max(min(pension_benefit_base, pension_maxpen), pension_minpen) · pension_elig
   ```
6. **Parameter indexation** (minimum/maximum) with `mpi_index_rate`, analogous to
   revalorization.

### 3.4.5 Retirement decision and transfer to pensioners

In the current version, retirement is **rule-based**: the individual retires
(`status = 2`) if eligible and has reached the maximum replacement rate **or** the
forced-retirement age (99). *(A commented-out NPV-based alternative exists that
compares the present value of retiring now vs. waiting one year, using life
expectancy and `p_discount_rate`; it is pending.)* Retiring affiliates are
extracted as new pensioners (`pensioners{yr}`), and at year-end retirees and the
deceased are dropped.

> **Pending items (flagged in the code).** Disability and survivorship (the
> structure exists, awaiting data); DC account accumulation and lump-sum payment
> (`p_lumpsum_flag = 0`); NPV retirement decision; adjustment of `iacc` in the
> base-wage scaling.

## 3.5 The pensioner loop

Initialized with the base pensioners (`status = 2`), each year: (1) the year's
new retirees are appended; (2) stochastic mortality is applied (`died_flag = 1`
if `mortality > runiform()`); (3) benefits are **indexed**:
```
pension_index = (alpha1·pindex_inflation + alpha2·pindex_realwage
                 + alpha3·pindex_anchor) / 100
pension_benefit = pension_benefit · (1 + pension_index)
```
(with `alpha1=alpha2=alpha3=1` and, by default, `pindex_inflation = 3.5%`); (4)
weighted counts by status are generated; and (5) the population ages one year.

## 3.6 Outputs and reporting

Outputs are written to `Output/` with the naming convention
`1_PROSTv2-{simname}-…-{startyear}-{endyear}.csv`:

| File | Content |
|---|---|
| `…-Affiliates-2025-2104.csv` | Final affiliate database (one record per individual, last observation) |
| `…-Pensioners-2025-2104.csv` | Final pensioner database |
| `…-Inyear-Affiliate-Reporting-Totals.csv` | Annual affiliate aggregates (affiliates, contributors, new, exits, re-entries, retired/disabled/widowed/deceased, mean age/wage/density, employment and turnover rates) |
| `…-Inyear-Affiliate-Reporting-Breakdowns.csv` | The above disaggregated by sex, decile, and `dens` |
| `…-Inyear-Pensioner-Reporting-Totals.csv` | Annual pensioner aggregates (counts by status, mean pension, index) |
| `…-Inyear-Pensioner-Reporting-Breakdowns.csv` | The above by age group (5-year), sex, class, and type |

**Scaling.** Sample counts are multiplied by the weight `wgt = 100/samplesize` to
estimate the total population.

---

# 4. Key assumptions

## 4.1 Stochastic vs. deterministic elements

| Process | Type | Method |
|---|---|---|
| Mortality | Stochastic | `status=99` if `rate > runiform()` (monthly, in death month) |
| Employment transitions (T1/T2) | Stochastic | cloglog hazard `1−exp(−exp(xb))`, monthly Bernoulli draw |
| New-entrant wage | Stochastic | `rnormal(μ,σ)` truncated to decile bounds |
| Decile and birth/death month | Stochastic | `runiformint` |
| Wage growth (aggregate and relative) | Deterministic | Yearly assumption × model profile (step 05) |
| Pension parameters and indexation | Deterministic | Policy rules / annual assumptions |
| Disability and survivorship | Stochastic | *(pending)* Bernoulli draw from step-06 rates |

## 4.2 Known limitations

- Disability and survivorship not yet implemented (structure ready).
- Defined-contribution (DC) account accumulation not modeled.
- The retirement decision is rule-based, not NPV with life expectancy.
- Beyond the stochastic employment transitions, there is no additional
  heterogeneity in contributory behavior.

---

# Appendix A — Correspondence with the Python re-implementation

The repository includes a Python toolkit (`toolkit/`) that re-implements the
pipeline in a modular, testable form, preserving the same methodology:

| Stata component | Python module |
|---|---|
| Step 01 | `prost2/preprocessing/step01_baseyear.py` |
| Step 02 | `prost2/preprocessing/step02_beneficiaries.py` |
| Step 03 (+ variants) | `prost2/preprocessing/step03_affiliation.py` |
| Step 04 (T1/T2) | `prost2/transitions.py` (+ `features.py`) |
| Step 05 | `prost2/preprocessing/step05_lifecycle_wages.py` |
| Step 06 | `prost2/preprocessing/step06_rates.py` |
| Projection | `prost2/projection.py` |

Because the microsimulation is **stochastic** (seed and `runiform()` in Stata),
the Python version reproduces the model *logic* and delivers statistically close
— not bit-for-bit identical — results, because random-number generators differ
across platforms.

*Document compiled from a direct reading of the PROST-2 repository `.do`
programs.*
