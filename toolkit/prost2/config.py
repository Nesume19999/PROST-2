"""Configuration: parameters, data environments, paths and filenames.

Mirrors the locals defined at the top of the Stata files (especially
`1 - PROSTv2 - Build projection database.do`, lines ~56-110) so the Python
toolkit uses exactly the same assumptions as Duncan's code.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

# --------------------------------------------------------------------------
# The four data environments. They differ ONLY in preprocessing steps 03/04
# (affiliation + transition rate estimation), via the *.do variants:
#   full           -> "03 - ... affiliation rates.do" / "04 - ... transitions rates.do"
#   very_low       -> "... - VERY LOW DATA.do"
#   low            -> "... - LOW DATA.do"
#   extremely_low  -> "... - EXTREMELY LOW DATA.do"
# --------------------------------------------------------------------------
DATA_ENVIRONMENTS = ("full", "very_low", "low", "extremely_low")

# Maps each environment to the suffix used by the Stata variant filenames.
ENV_SUFFIX = {
    "full": "",
    "very_low": " - VERY LOW DATA",
    "low": " - LOW DATA",
    "extremely_low": " - EXTREMELY LOW DATA",
}


@dataclass(frozen=True)
class Parameters:
    """Simulation parameters (from the build file's locals)."""
    country: str = "MEX"
    simname: str = "Baseline"
    baseyear: int = 2024
    horizon: int = 80                      # number of projection years
    samplesize: int = 10                   # % sample (100=full, 1=1%)
    max_eligibility_age: int = 75
    working_age_min: int = 15
    working_age_max: int = 64
    # Wage adjustment to bring 2020 data to the 2024 baseyear (ILO monthly
    # earnings growth): 9878.469 / 7048.628
    wage_adjustment: float = 9878.469 / 7048.628
    extended_output: bool = False
    histograms: bool = False
    seed: int = 2                          # matches Stata `set seed 2`

    @property
    def startyear(self) -> int:
        return self.baseyear + 1

    @property
    def endyear(self) -> int:
        return self.baseyear + self.horizon


@dataclass(frozen=True)
class Paths:
    """Folder layout, all relative to the repo `root` (matches the .do macros)."""
    root: str

    @property
    def input(self) -> str:
        return os.path.join(self.root, "Input")

    @property
    def output(self) -> str:
        return os.path.join(self.root, "Output")

    @property
    def defaults(self) -> str:
        return os.path.join(self.input, "Defaults")

    def default(self, subfolder: str) -> str:
        return os.path.join(self.defaults, subfolder)


# Default subfolder names under Input/Defaults/ (match the repo structure).
DEFAULT_SUBDIRS = {
    "affiliation": "affiliation",
    "population": "population",
    "population_obs": "population_obs",
    "mortality": "mortality",
    "mortality_obs": "mortality_obs",
    "wage_growth": "wage_growth",
    "transitions": "transitions",
    "lifecycle": "lifecycle wages",
    "retirement": "retirement",
    "disability": "disability",
    "survivor": "survivor",
}

# Raw client microdata (live in Input/, read only during preprocessing).
RAW_LONGITUDINAL = "2 Input from client - longitudinal microdata about affiliates.dta"
RAW_BENEFICIARIES = "3 Input from client - microdata about beneficiaries.dta"

# Filenames produced/consumed by the pipeline (country-substituted at runtime).
FILENAMES = {
    "baseyear_data": "baseyear_data_{country}.dta",          # step 01 out / build in
    "pensioners_data": "pensioners_{country}.dta",           # step 02 out / build in
    "affiliation": "affiliation_{country}_10.csv",           # step 03 out / build in
    "population": "population_{country}.csv",
    "population_hist": "population_historical_{country}.dta",
    "mortality": "mortality_{country}.csv",
    "mortality_obs": "mortality_obs_{country}.csv",
    "wage_growth": "cpi_{country}.csv",
    "lifecycle_model": "lifecycle_wages_{country}",          # step 05 out / build in (.ster)
    "job_exit_model": "job_exit_model_{country}_10_final",   # step 04
    "job_entry_model": "job_entry_model_{country}_10_final",
    "retirement_rates": "retirement_rates_{country}.csv",    # step 06
    "disability_rates": "disability_rates_{country}.csv",
    "survivor_rates": "survivor_rates_{country}.csv",
    "lm_assumptions": "labor_market_assumptions.csv",
    "index_assumptions": "indexation_assumptions_{country}.csv",
}


def fname(key: str, country: str = "MEX") -> str:
    return FILENAMES[key].format(country=country)
