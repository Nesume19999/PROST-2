"""Step 06 — Generate retirement, disability and survivor rates.

Port of `06 - Pre-processing - Generate retirement disability survivor rates.do`.

INPUT :
  Input/Defaults/affiliation/affiliation_MEX.csv
  Input/Defaults/mortality_obs/mortality_obs_MEX.csv
  Input/pensioners_MEX.dta                          (from step 02)
  Input/Defaults/population_obs/population_historical_MEX.dta
OUTPUT (Input/Defaults/):
  retirement/retirement_rates_MEX.csv
  disability/disability_rates_MEX.csv
  survivor/survivor_rates_MEX.csv

Builds age/gender/year incidence rates for new old-age, disability and survivor
pensions by combining beneficiary stocks with population and survival rates.
(to be ported + validated against the Stata CSVs once data is uploaded.)
"""
from __future__ import annotations

from ..config import Parameters, Paths

_PENDING = (
    "step06_rates: implementation pending real-data validation. "
    "Upload Input/ + Input/Defaults/ via Git LFS so retirement/disability/"
    "survivor rates can be derived and checked against the Stata CSVs."
)


def run(params: Parameters, paths: Paths):
    raise NotImplementedError(_PENDING)
