"""Step 03 — Generate affiliation rates  (4 data-environment variants).

Port of:
  full          -> `03 - Pre-processing - Generate affiliation rates.do`
  very_low      -> `03 - ... - VERY LOW DATA.do`
  low           -> `03 - ... - LOW DATA.do`
  extremely_low -> `03 - ... - EXTREMELY LOW DATA.do`

INPUT :
  Input/ "2 Input from client - longitudinal microdata about affiliates.dta"
  Input/Defaults/population_obs/population_historical_MEX.dta  (merge on year/gender/age)
OUTPUT:
  Input/Defaults/affiliation/affiliation_MEX_10.csv   (cols: year gender age affiliation_rate ...)

The environments differ in how the affiliation rate is estimated:
  full           -> directly from the longitudinal microdata
  very/low/xlow  -> progressively coarser fallbacks when microdata is scarce
(to be ported + validated against the Stata CSVs once data is uploaded).
"""
from __future__ import annotations

from ..config import Parameters, Paths

_PENDING = (
    "step03_affiliation: implementation pending real-data validation. "
    "Upload Input/ + Input/Defaults/ via Git LFS so this step can be ported "
    "and checked against affiliation_{country}_10.csv."
)


def run(params: Parameters, paths: Paths, data_env: str = "full"):
    raise NotImplementedError(_PENDING)
