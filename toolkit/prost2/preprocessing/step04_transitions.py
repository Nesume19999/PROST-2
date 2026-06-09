"""Step 04 — Estimate job entry/exit transition rates  (4 data-environment variants).

Port of:
  full          -> `04 - Pre-processing - Estimate transitions rates.do`
  very_low      -> `04 - ... - VERY LOW DATA.do`
  low           -> `04 - ... - LOW DATA.do`
  extremely_low -> `04 - ... - EXTREMELY LOW DATA.do`

INPUT :
  Input/ "2 Input from client - longitudinal microdata about affiliates.dta"
OUTPUT (Input/Defaults/transitions/):
  job_exit_model_MEX_10_final, job_entry_model_MEX_10_final   (cloglog estimates)
  transitions_MEX_10.dta

In Stata these are `cloglog` discrete-time hazard models for leaving / entering
formal employment (as a function of age, gender, decile, duration, time to
retirement). The Python port estimates the equivalent complementary-log-log
GLM (statsmodels) and stores predicted hazards; the environments differ in the
richness of the covariates used.
(to be ported + validated against the Stata estimates once data is uploaded.)
"""
from __future__ import annotations

from ..config import Parameters, Paths

_PENDING = (
    "step04_transitions: implementation pending real-data validation. "
    "Upload the longitudinal microdata via Git LFS so the cloglog entry/exit "
    "hazard models can be estimated and checked against the Stata .ster files."
)


def run(params: Parameters, paths: Paths, data_env: str = "full"):
    raise NotImplementedError(_PENDING)
