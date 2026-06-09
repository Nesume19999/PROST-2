"""Projection — the PROST v2 microsimulation.

Port of `1 - PROSTv2 - Build projection database.do` (the 2806-line build).

INPUTS (Input/ and Input/Defaults/):
  baseyear_data_MEX.dta, pensioners_MEX.dta,
  Defaults/population/population_MEX.csv, Defaults/mortality/mortality_MEX.csv,
  Defaults/affiliation/affiliation_MEX_10.csv, Defaults/wage_growth/cpi_MEX.csv,
  Defaults/transitions/job_{entry,exit}_model_MEX_10_final,
  Defaults/lifecycle wages/lifecycle_wages_MEX,
  Input/labor_market_assumptions.csv, Input/indexation_assumptions_MEX.csv

OUTPUTS (Output/):
  1_PROSTv2-{simname}-Affiliates-{startyear}-{endyear}.csv
  1_PROSTv2-{simname}-Pensioners-{startyear}-{endyear}.csv
  1_PROSTv2-{simname}-Inyear-Affiliate-Reporting-{Totals,Breakdowns}.csv
  1_PROSTv2-{simname}-Inyear-Pensioner-Reporting-{Totals,Breakdowns}.csv

The simulation samples `samplesize`% of affiliates (weight = 100/samplesize),
then for each year (startyear..endyear) and month:
  1. mortality (status -> 99 dead),
  2. job exit / entry (predicted hazards from step 04),
  3. wage dynamics (life-cycle profile from step 05 + macro wage growth),
  4. retirement / disability / survivor transitions (rates from step 06),
  5. pension award + indexation (assumptions),
and accumulates affiliate and pensioner reporting tables.

FIDELITY NOTE: the Stata version is stochastic (`set seed 2`, `runiform()`).
The Python port reproduces the model logic with numpy's RNG; results will be
statistically close but not bit-identical. Validated against the Stata Output/
CSVs once data is uploaded.
"""
from __future__ import annotations

from .config import Parameters, Paths

_PENDING = (
    "projection: implementation pending real-data validation. "
    "Upload Input/ + Input/Defaults/ (and the step 03-06 outputs) via Git LFS "
    "so the microsimulation can be ported and validated against the Stata "
    "Output/1_PROSTv2-*.csv files."
)


def run(params: Parameters, paths: Paths, data_env: str = "full"):
    raise NotImplementedError(_PENDING)
