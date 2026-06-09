"""Step 05 — Estimate life-cycle wage growth profiles.

Port of `05 - Pre-processing - Generate life cycle wage growth profiles.do`.

INPUT  (Input/): "2 Input from client - longitudinal microdata about affiliates.dta"
OUTPUT (Input/Defaults/lifecycle wages/): lifecycle_wages_MEX  (regression estimates)

Stata model (full interactions):
    regress wage_growth_relative i.wage_decile#i.gender#i.age   if reg_include_flag
where reg_include_flag keeps obs within +/- 3 SD of mean relative wage growth.
The Python port fits the equivalent OLS with the wage_decile x gender x age cell
means and stores predicted relative wage growth per (decile, gender, age) cell.
(to be ported + validated against the Stata estimates once data is uploaded.)
"""
from __future__ import annotations

from ..config import Parameters, Paths

_PENDING = (
    "step05_lifecycle_wages: implementation pending real-data validation. "
    "Upload the longitudinal microdata via Git LFS so the wage-growth model "
    "can be fit and checked against lifecycle_wages_{country}."
)


def run(params: Parameters, paths: Paths):
    raise NotImplementedError(_PENDING)
