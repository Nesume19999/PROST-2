"""Synthetic affiliate microdata generator.

Produces a longitudinal panel with the SAME SCHEMA as the real IMSS client
file `2 Input from client - longitudinal microdata about affiliates.dta`, but
with fully synthetic (non-sensitive) data, so the pipeline can be exercised and
unit-tested without ever touching the real microdata.

Schema (one row per person-month):
    id      int   person identifier
    year    int   calendar year
    month   int   calendar month (1-12)
    yob     int   year of birth
    gender  int   1 = male, 2 = female
    wage    float daily wage when formally employed, 0 otherwise
    dens    int   1 = contributing/formally employed this month, 0 otherwise
    los     int   length of service: cumulative months contributed (dens==1)
    aux     int   length of affiliation (months since first appearance) -> loa

GENERATING MODEL (documented assumptions)
-----------------------------------------
* Demographics: gender ~ Bernoulli(0.5); birth years spread so ages span ~18-65
  across the window. People only appear in months where 18 <= age <= 65, which
  produces realistic entries (turning 18) and exits (reaching 65).
* Employment: a 2-state Markov chain on formal-employment status with monthly
  transition hazards
      exit  (employed   -> unemployed) = 1 - P_STAY_EMP   = 0.03
      entry (unemployed -> employed)   = 1 - P_STAY_UNEMP  = 0.10
  whose stationary employed share is ~0.77 (a plausible ~70-80% density), and
  which yields realistic employment/unemployment spell lengths. These known
  hazards are the *baseline* the Step-04 tests validate against.
* Wages: daily wage = person fixed effect (log-normal) x mild age hump x annual
  nominal growth x log-normal noise; 0 while not employed.

The generator is deterministic given `seed`.
"""
from __future__ import annotations

from dataclasses import dataclass
import numpy as np
import pandas as pd

# --- Known generating parameters (imported by tests as the "truth") ----------
P_STAY_EMP = 0.97          # P(employed next month | employed now)
P_STAY_UNEMP = 0.90        # P(unemployed next month | unemployed now)
TRUE_EXIT_HAZARD = 1 - P_STAY_EMP        # 0.03
TRUE_ENTRY_HAZARD = 1 - P_STAY_UNEMP     # 0.10
# Stationary share of employed months for the chain above (~0.769):
STATIONARY_DENSITY = TRUE_ENTRY_HAZARD / (TRUE_EXIT_HAZARD + TRUE_ENTRY_HAZARD)

MIN_WORK_AGE = 18
MAX_WORK_AGE = 65

DEFAULT_SEED = 20260609


@dataclass(frozen=True)
class SyntheticConfig:
    n_workers: int = 50_000
    start_year: int = 2005
    end_year: int = 2024
    seed: int = DEFAULT_SEED
    annual_wage_growth: float = 0.04      # nominal
    wage_log_mean: float = 5.5            # median daily wage ~ exp(5.5) ~ 245
    wage_log_sd: float = 0.5


def generate(config: SyntheticConfig | None = None, **overrides) -> pd.DataFrame:
    """Generate the synthetic longitudinal panel as a tidy DataFrame."""
    cfg = config or SyntheticConfig(**overrides)
    rng = np.random.default_rng(cfg.seed)

    n = cfg.n_workers
    years = np.arange(cfg.start_year, cfg.end_year + 1)
    months = np.arange(1, 13)
    # Month grid (year, month) in chronological order -> length T
    grid_year = np.repeat(years, 12)
    grid_month = np.tile(months, len(years))
    T = grid_year.size

    # --- Demographics --------------------------------------------------------
    gender = rng.integers(1, 3, size=n).astype(np.int8)  # 1 or 2
    # Birth years chosen so workers enter (turn 18) or exit (turn 65) within the
    # window, giving ragged but realistic panels.
    yob = rng.integers(cfg.start_year - 55, cfg.end_year - MIN_WORK_AGE + 1,
                       size=n).astype(np.int32)

    # Age matrix (n x T) and in-range mask
    age = grid_year[None, :] - yob[:, None]            # int
    in_range = (age >= MIN_WORK_AGE) & (age <= MAX_WORK_AGE)

    # --- Employment Markov chain (n x T) ------------------------------------
    emp = np.empty((n, T), dtype=bool)
    emp[:, 0] = rng.random(n) < STATIONARY_DENSITY
    for t in range(1, T):
        draw = rng.random(n)
        stay_emp = draw < P_STAY_EMP
        become_emp = draw < (1 - P_STAY_UNEMP)
        emp[:, t] = np.where(emp[:, t - 1], stay_emp, become_emp)

    # --- Flatten to long format, keeping only in-range person-months ---------
    worker_idx = np.repeat(np.arange(n), T)
    yr_flat = np.tile(grid_year, n)
    mo_flat = np.tile(grid_month, n)
    age_flat = age.reshape(-1)
    emp_flat = emp.reshape(-1)
    keep = in_range.reshape(-1)

    worker_idx = worker_idx[keep]
    df = pd.DataFrame({
        "id": worker_idx.astype(np.int32),
        "year": yr_flat[keep].astype(np.int16),
        "month": mo_flat[keep].astype(np.int8),
        "yob": yob[worker_idx],
        "gender": gender[worker_idx],
        "age": age_flat[keep].astype(np.int16),
        "dens": emp_flat[keep].astype(np.int8),
    })
    df = df.sort_values(["id", "year", "month"]).reset_index(drop=True)

    # --- Wages (only when employed) -----------------------------------------
    person_base = np.exp(rng.normal(cfg.wage_log_mean, cfg.wage_log_sd, size=n))
    a = (df["age"].to_numpy() - MIN_WORK_AGE).astype(float)
    age_profile = 1.0 + 0.02 * a - 0.0003 * a * a
    growth = (1 + cfg.annual_wage_growth) ** (df["year"].to_numpy() - cfg.start_year)
    noise = np.exp(rng.normal(0.0, 0.1, size=len(df)))
    wage = person_base[df["id"].to_numpy()] * age_profile * growth * noise
    df["wage"] = np.where(df["dens"].to_numpy() == 1, wage, 0.0).astype(np.float32)

    # --- los (cumulative contributions) and aux/loa (months affiliated) ------
    g = df.groupby("id", sort=False)
    df["los"] = g["dens"].cumsum().astype(np.int32)
    df["aux"] = (g.cumcount() + 1).astype(np.int32)

    df = df.drop(columns=["age"])  # age is derived downstream from yob
    return df[["id", "year", "month", "yob", "gender", "wage", "dens", "los", "aux"]]
