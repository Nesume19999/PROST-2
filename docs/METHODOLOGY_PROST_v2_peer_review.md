---
title: "The PROST v2 Pension Microsimulation Model"
subtitle: "Methodology Note for Peer Reviewers"
author: "World Bank — PROST Team"
date: "June 2026"
lang: en
---

# Purpose of this note

This note is written for **peer reviewers** assessing the methodological
soundness of the PROST v2 pension microsimulation model for Mexico. It is a
companion to the full *Technical Methodology Document*: rather than re-describing
every line of code, it foregrounds the **design choices, statistical
assumptions, identification, calibration, and limitations** that a reviewer would
want to scrutinize, and it lists **specific open questions** at the end of each
section. Equations and parameter values are reproduced where they are material to
the assessment; the full algorithmic detail is in the companion document.

Throughout, items the code itself flags as not-yet-implemented are marked
**[PENDING]**. Reviewers should treat the current model as a working-age and
old-age **defined-benefit** projection engine; disability, survivorship, and
defined-contribution accumulation are scaffolded but inactive.

---

# 1. Model class and intended use

PROST v2 is a **stochastic, dynamic microsimulation** of a national pension
scheme. It maintains an individual-level state vector for each affiliate and
pensioner and advances it on a **monthly** time step for demographic and
labor-market events and an **annual** time step for wages, benefits, and
indexation, over an 80-year horizon (base year 2024; projection 2025–2104).

The intended use is **fiscal and actuarial projection** of system-level
aggregates — number of contributors and pensioners, contribution and benefit
flows, replacement rates — under deterministic macro and policy scenarios, with
behavioral and demographic uncertainty handled by Monte-Carlo draws.

**Why microsimulation rather than a cohort-component / cell model.** The scheme's
benefit formula depends nonlinearly on individual contribution histories
(length of service, reference wage, early/late-retirement adjustments) and on
the joint distribution of tenure, density, and wage. A cell model would require
strong distributional assumptions to track these interactions; microsimulation
represents them directly. The cost is Monte-Carlo (sampling) error, addressed in
§5.

> **For reviewers.** (i) Is microsimulation justified given the data, or would a
> well-specified cell model suffice for the headline aggregates? (ii) Is the
> 80-year horizon credible given that all behavioral models are estimated on a
> ≤10-year window (§3)?

---

# 2. Data sources and the "data environment" design

## 2.1 Sources

- **Client microdata:** an IMSS affiliate longitudinal panel (wages, age, sex,
  tenure, contribution density) and a beneficiary file (pension amounts and
  types). These drive the base-year population, the affiliation rates, the
  transition models, the wage profiles, and the incidence rates.
- **Default inputs:** UN/national **population** (historical + projected),
  **mortality** (observed + projected), aggregate **wage growth** (CPI series),
  and user-supplied **labor-market** and **indexation** assumption files.

## 2.2 The four data environments

A distinctive design feature is that the two data-hungry preprocessing steps —
affiliation rates (step 03) and transition models (step 04) — each ship in
**four variants** keyed to how much longitudinal information is available:
*full*, *very low data*, *low data*, *extremely low data*. The intent is
portability to countries where only a cross-section with a tenure variable, or a
tenure-plus-density cross-section, is available.

The fallbacks are not innocuous, and reviewers should weigh them explicitly:

- **Tenure-based reconstruction (low/very-low/extremely-low).** When the panel is
  absent, the year and age of affiliation are imputed as
  `year − floor(loa/12)` and `max(age − floor(loa/12), 0)`. This assumes a
  **single, uninterrupted affiliation spell** and ignores re-entry, so it will
  misdate anyone with gapped careers and will compress the age-at-entry
  distribution.
- **Monthly duplication (very-low).** Without the December-only filter, every
  monthly observation of the same person contributes to the new-affiliate count,
  mechanically inflating flows. The *low data* variant mitigates this by keeping
  `month==12` only.
- **ZOIB expansion (extremely-low).** A zero-and-one-inflated Beta regression of
  contribution density on sex (with age and sex in the one-inflation part) yields
  an `expansion_factor = 1/(1 − implied_p_zero)` that scales up affiliate counts
  to proxy for unobserved non-contributors. This is a **model-based
  extrapolation**: its validity rests on density being a good proxy for the
  missing mass, and on the parametric Beta/inflation form.

> **For reviewers.** (i) Which environment is used for the Mexico baseline, and
> is that disclosed in the results? (ii) The four variants are not nested
> estimators of the same quantity — they can produce materially different
> affiliation rates. Has a sensitivity comparison across environments been run on
> the same data to bound this? (iii) The tenure reconstruction's single-spell
> assumption interacts with the model's own emphasis on re-entry (§4); is that
> internally consistent?

---

# 3. Statistical estimation

All behavioral models are estimated on at most the **last 10 years** of data
(`years_avg = 10`) for ages ≥ 15. This window choice trades recency against
sample size and is a candidate for sensitivity analysis.

## 3.1 Labor-market transitions (step 04)

Monthly exit (T1) and entry (T2) probabilities are **complementary log-log
hazards**:

```
T1 (dens==1):  cloglog  transition_out  c.spell_length##i.wage_decile_ref
                                         c.age##c.age  i.gender  c.los_gap
T2 (dens==0):  cloglog  transition_in   c.spell_length##i.wage_decile_ref
                                         c.age##c.age  i.gender  c.log_cod  c.los_gap
```

with `p = 1 − exp(−exp(xb))`, standard errors clustered by `id`.

Points a reviewer should examine:

- **Functional form.** cloglog is a discrete-time proportional-hazard
  approximation; duration dependence enters through `spell_length` interacted
  with the reference decile. There is no unobserved-heterogeneity (frailty) term,
  so any persistent individual propensity to exit/enter is absorbed into the
  covariates and the clustered SEs — point predictions may be biased if frailty
  is important.
- **Endogeneity of covariates.** `los_gap`, `log_cod`, and `wage_decile_ref` are
  functions of the same contribution history the hazard governs; they are
  treated as predetermined. The direction of any resulting bias is worth a
  comment.
- **Use in projection.** The estimated hazards are not used as-is: they are
  rescaled each year by `outflow_adjustment`/`inflow_adjustment` so that
  aggregate employment and turnover hit exogenous targets (§4). The micro model
  therefore supplies the *shape* of transitions across age/decile/tenure, while
  the *level* is calibrated. This should be stated plainly when interpreting the
  coefficients.

## 3.2 Life-cycle wage growth (step 05)

A single OLS regression of **relative** wage growth (cohort growth ÷ aggregate
growth, ×100) on a **full three-way interaction** `i.wage_decile#i.gender#i.age`,
on cohort-collapsed data, after trimming observations beyond ±3 SD and dropping
near-retirement workers with sufficient contributions (to avoid selection).

Reviewer considerations: (i) the three-way saturated interaction is
high-dimensional and may be noisily estimated in sparse decile×age×sex cells;
(ii) the ratio definition is unstable when aggregate growth is near zero in a
given year; (iii) trimming at 3 SD is reasonable but the result should be checked
for sensitivity to the threshold.

## 3.3 Affiliation and incidence rates (steps 03, 06)

Affiliation rates are empirical ratios (new affiliates ÷ population), discussed
under §2.2. The retirement/disability/survivor incidence rates (step 06) apply a
**cohort-survival adjustment**: observed beneficiary counts are divided by the
ratio of cohort survival between the base year and the pension-start year, to
recover the original entering cohort. This requires a long mortality series; the
code backfills 1850–1949 by holding the earliest observed rates constant — an
approximation whose effect on recovered counts for very old cohorts should be
acknowledged.

> **For reviewers.** (i) Are standard errors / fit diagnostics for T1, T2, and
> the wage regression reported anywhere, or only point estimates fed forward?
> (ii) Is there any out-of-sample or holdout validation of the transition and
> wage models? (iii) The incidence rates average the last 20 years; for a system
> mid-reform this may blend heterogeneous regimes.

---

# 4. Simulation mechanics, calibration, and the benefit formula

## 4.1 Calibration to exogenous targets

Two internal calibration loops make the micro dynamics conform to macro
assumptions:

- **Labor market.** Predicted exit/entry hazards are scaled so that the
  simulated employment rate moves by `emp_rate_growth` and gross turnover matches
  `turnover_target` each year.
- **Wages.** After applying decile-specific relative growth, all wages are
  rescaled by `(1 + wage_growth_user)/(1 + wage_growth_obs)` so the simulated
  mean wage growth equals the assumed aggregate exactly.

These are sensible "alignment" devices common in microsimulation, but they mean
the **aggregate paths are imposed, not predicted**; the model's value-added is the
distribution *around* those aggregates. Reviewers should interpret headline
employment and wage trajectories as assumptions, not model outputs.

## 4.2 Benefit formula (defined benefit)

For an eligible individual:

```
replacement_rate     = yos·p_accrual − years_early·p_delta + years_late·p_lambda
replacement_rate     = max( min(replacement_rate, p_accrual_max), 0 )
pension_benefit_base = reference_wage · replacement_rate
pension_benefit      = max( min(pension_benefit_base, pension_maxpen), pension_minpen )
```

with eligibility = (service ≥ `p_min_service_req`) ∧ (age past the
δ-penalty floor) ∧ (age ≥ earliest age). Baseline policy parameters: accrual 4%/yr
(cap 75%), early/late adjustment ±4%/yr, minimum service ≈14.42 years, retirement
age 65, forced retirement 99, base minimum pension 2,622 (adjusted by age,
tenure, and wage). The reference wage supports rolling-average or best-N-years
definitions and is revalorized annually by a weighted index of inflation, real
wage growth, and an anchor.

Reviewer considerations: (i) the **rule-based retirement trigger** — retire when
the replacement-rate cap is hit *or* at age 99 — is mechanical and will tend to
push retirement to the cap; the more behavioral **NPV decision is [PENDING]**, so
the timing distribution of retirements is currently an artifact of the rule, not
of incentives; (ii) the covered-wage cap (`p_max_income`) and floor interact with
the minimum-pension adjustments in ways worth a worked example; (iii) the
parameters should be checked against current Mexican law (e.g., IMSS/Ley 97
week requirements and the *pensión garantizada*), since several are placeholders.

## 4.3 Unimplemented components **[PENDING]**

- **Disability and survivorship.** Incidence rates are produced (step 06) but the
  transitions are not applied in the loop; pensioner counts therefore exclude
  these risks.
- **Defined contribution.** DC accounts, balances, and annuitization are not
  accumulated (`p_lumpsum_flag = 0`); the system is projected as pure DB.
- **NPV retirement.** See §4.2.

These omissions are material for any total-cost or replacement-rate conclusion
and should bound the claims made from current outputs.

> **For reviewers.** (i) Given calibration, what exactly is being validated when
> the model "matches" historical aggregates? (ii) Should results be presented as
> DB-only and old-age-only until the [PENDING] modules are active? (iii) Are the
> policy parameters sourced and dated?

---

# 5. Stochastic error, reproducibility, and validation

- **Monte-Carlo error.** The run uses a **10% sample** and a **single random seed
  (`seed = 2`)**. Mortality, transitions, wage draws, and decile/birth-month
  assignment are all stochastic. With one seed and a 10% sample there is no
  characterization of sampling variability around the projected aggregates.
  Reviewers should expect **multi-seed (and ideally larger-sample) replication**
  with reported Monte-Carlo confidence bands before point projections are used
  for fiscal decisions.
- **Reproducibility.** Within a platform the fixed seed makes runs reproducible.
  Across platforms (e.g., the Stata original vs. the Python re-implementation),
  RNG differences mean only **statistical**, not bit-for-bit, agreement is
  expected; a documented cross-implementation reconciliation (same inputs,
  distribution of outputs) would strengthen confidence.
- **Validation.** The companion materials describe in-year reporting tables but
  no formal back-test. A minimal validation suite would include: (i) base-year
  reproduction of observed contributor and pensioner stocks; (ii) short-horizon
  back-cast against recent observed years; (iii) sensitivity to the data
  environment (§2.2), the 10-year estimation window, and the trimming/threshold
  choices.

> **For reviewers.** (i) What is the Monte-Carlo standard error on the headline
> 2050/2104 aggregates? (ii) Is base-year calibration exact (do weighted sample
> stocks equal administrative totals)? (iii) Has the Python/Stata pair been
> reconciled on identical inputs?

---

# 6. Summary assessment checklist for reviewers

| Area | Status | Key question |
|---|---|---|
| Model class fit for purpose | Plausible | Microsimulation vs. cell model trade-off justified? |
| Data environment / fallbacks | Needs disclosure | Which variant is used; sensitivity across variants? |
| Transition models (cloglog) | Estimated, calibrated | Frailty omitted; level is calibrated not predicted |
| Wage profile (saturated OLS) | Estimated | Sparse-cell noise; ratio instability near zero growth |
| Incidence rates + survival adj. | Estimated | Long backfill approximation; 20-yr blend |
| Benefit formula (DB) | Implemented | Parameters vs. current law; rule-based retirement |
| Disability / survivor / DC / NPV | **[PENDING]** | Results should be scoped to DB old-age |
| Stochastic error | Single seed, 10% | No Monte-Carlo bands reported |
| Reproducibility | Within-platform | Cross-implementation reconciliation pending |
| Validation / back-test | Not documented | Base-year + back-cast + sensitivity needed |

---

# Appendix A — Baseline policy and simulation parameters

| Parameter | Value | Role |
|---|---|---|
| `baseyear` / `startyear` / `endyear` | 2024 / 2025 / 2104 | Horizon |
| `samplesize` / `seed` | 10% / 2 | Monte-Carlo design |
| `years_avg` | 10 | Estimation window (steps 03–05) |
| `include_years` | 20 | Incidence-rate window (step 06) |
| `working_age_min/max` | 15 / 64 | Labor-force ages |
| `p_min_service_req` | 750/52 ≈ 14.42 yr | Eligibility |
| `p_accrual` / `p_accrual_max` | 4%/yr / 75% | Replacement rate |
| `p_delta` / `p_lambda` | 4% / 4% per yr | Early penalty / late bonus |
| retirement age / forced | 65 / 99 | Eligibility / retirement trigger |
| `p_minpen_base` | 2,622 | Minimum pension (adj. age/tenure/wage) |
| `p_discount_rate` | 3% | NPV decision **[PENDING]** |
| indexation weights `alpha1..3` | 1 / 1 / 1 | Inflation / real wage / anchor |
| default `pindex_inflation` | 3.5% | Benefit indexation |

---

# Appendix B — Companion documents

- *The PROST v2 Pension Microsimulation Model — Technical Methodology Document*
  (full algorithmic description of steps 01–06 and the projection engine).
- Python re-implementation under `toolkit/` (modular, testable; statistically
  equivalent to the Stata original).

*This note was compiled from a direct reading of the PROST-2 repository `.do`
programs and is intended to support, not replace, reviewers' independent
inspection of the source.*
