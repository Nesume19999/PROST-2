"""Step 04 -- Job entry / exit transition models (T1 / T2).

Independent, testable port of `04 - Pre-processing - Estimate transitions
rates.do`. Two complementary-log-log (cloglog) discrete-time hazard models:

    T1  job EXIT  (transition_out), estimated on currently-employed months:
        cloglog transition_out  c.spell_length##i.wage_decile_ref
                                 c.age##c.age  i.gender  c.los_gap    if dens==1

    T2  job ENTRY (transition_in),  estimated on currently-unemployed months:
        cloglog transition_in   c.spell_length##i.wage_decile_ref
                                 c.age##c.age  i.gender  c.log_cod  c.los_gap if dens==0

(In Stata the SEs are clustered on `id`; clustering does not change the point
estimates or the fitted hazards, so it is omitted here and noted in docs.)

Public API:
    prepare(df, ...)          -> feature frame with transition indicators
    fit_exit(frame)           -> fitted T1 model (GLMResults)
    fit_entry(frame)          -> fitted T2 model (GLMResults)
    predict_hazard(model, X)  -> predicted monthly hazard in [0, 1]
    empirical_rates(frame)    -> realised mean exit/entry hazards (for validation)
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf

from . import features

# Pension-system parameters used to build the time-to-retirement covariates.
RETAGE_MALE = 65
RETAGE_FEMALE = 65
RETCONT_MIN = (750 / 52) * 12      # minimum contribution months ~ 173.08
MIN_AGE = 15
YEARS_AVG = 10                     # window of recent years used for estimation

EXIT_FORMULA = (
    "transition_out ~ spell_length * C(wage_decile_ref) "
    "+ age + I(age**2) + C(gender) + los_gap"
)
ENTRY_FORMULA = (
    "transition_in ~ spell_length * C(wage_decile_ref) "
    "+ age + I(age**2) + C(gender) + log_cod + los_gap"
)


def _cloglog_family() -> sm.families.Binomial:
    links = sm.families.links
    link = getattr(links, "CLogLog", getattr(links, "cloglog", None))()
    return sm.families.Binomial(link=link)


def prepare(df: pd.DataFrame, latest_year: int | None = None,
            years_avg: int = YEARS_AVG, min_age: int = MIN_AGE) -> pd.DataFrame:
    """Build the estimation frame from a raw longitudinal panel.

    Applies the full Step-04 feature pipeline, then keeps the most recent
    `years_avg` years and ages >= `min_age` (reference deciles are computed
    *before* trimming, exactly as in the Stata code).
    """
    if latest_year is None:
        latest_year = int(df["year"].max())

    out = features.add_age_and_date(df)
    out = features.add_spells(out)
    out = features.add_contribution_density(out)
    out = features.add_pension_gaps(out, RETAGE_MALE, RETAGE_FEMALE, RETCONT_MIN)
    out = features.add_wage_deciles(out, latest_year=latest_year)

    # Reference deciles are set; now restrict the estimation window.
    out = out[(out["year"] > latest_year - years_avg) & (out["age"] >= min_age)]
    out = features.add_transitions(out, latest_year=latest_year)
    return out.reset_index(drop=True)


def fit_exit(frame: pd.DataFrame):
    """T1: probability of leaving formal employment (employed months only)."""
    data = frame[(frame["dens"] == 1) & frame["transition_out"].notna()
                 & frame["wage_decile_ref"].notna()].copy()
    model = smf.glm(EXIT_FORMULA, data=data, family=_cloglog_family())
    return model.fit()


def fit_entry(frame: pd.DataFrame):
    """T2: probability of entering formal employment (unemployed months only)."""
    data = frame[(frame["dens"] == 0) & frame["transition_in"].notna()
                 & frame["wage_decile_ref"].notna()].copy()
    model = smf.glm(ENTRY_FORMULA, data=data, family=_cloglog_family())
    return model.fit()


def predict_hazard(model, frame: pd.DataFrame) -> np.ndarray:
    """Predicted monthly hazard for the rows of `frame` (NaN where infeasible)."""
    return np.asarray(model.predict(frame))


@dataclass(frozen=True)
class EmpiricalRates:
    exit_rate: float       # mean realised job-exit hazard (employed months)
    entry_rate: float      # mean realised job-entry hazard (unemployed months)
    n_employed: int
    n_unemployed: int


def empirical_rates(frame: pd.DataFrame) -> EmpiricalRates:
    """Realised monthly transition rates -- the baseline tests check against."""
    exit_obs = frame.loc[frame["transition_out"].notna(), "transition_out"]
    entry_obs = frame.loc[frame["transition_in"].notna(), "transition_in"]
    return EmpiricalRates(
        exit_rate=float(exit_obs.mean()),
        entry_rate=float(entry_obs.mean()),
        n_employed=int(exit_obs.size),
        n_unemployed=int(entry_obs.size),
    )
