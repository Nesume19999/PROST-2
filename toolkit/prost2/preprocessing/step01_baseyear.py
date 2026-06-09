"""Step 01 — Generate the base-year affiliate dataset.

Port of `01 - Pre-processing - Generate baseyear dataset.do`.

INPUT  (Input/):  "2 Input from client - longitudinal microdata about affiliates.dta"
OUTPUT (Input/):  baseyear_data_MEX.dta

The longitudinal file is expected to contain at least:
    id, year, month, yob, gender, wage (daily), dens (formality/density), aux
"""
from __future__ import annotations

import os
import numpy as np
import pandas as pd

from .. import io_utils
from ..config import Parameters, Paths, RAW_LONGITUDINAL, fname


def _xtile(s: pd.Series, n: int = 10) -> pd.Series:
    """Approx of Stata `xtile`: assign 1..n quantile bins.

    NOTE (validation point): Stata's xtile and pandas qcut break ties slightly
    differently; bins are validated against the Stata output once data is up.
    """
    valid = s.dropna()
    if valid.empty:
        return pd.Series(np.nan, index=s.index)
    try:
        binned = pd.qcut(s, n, labels=range(1, n + 1), duplicates="drop")
    except ValueError:
        # too many duplicate edges -> rank-based fallback
        ranks = s.rank(method="first", pct=True)
        binned = np.ceil(ranks * n).clip(1, n)
    return pd.Series(binned, index=s.index).astype("float")


def run(params: Parameters, paths: Paths) -> pd.DataFrame:
    long_path = os.path.join(paths.input, RAW_LONGITUDINAL)
    df = io_utils.read_stata(long_path)

    latest_year = int(df["year"].max())

    # Minor cleanup + age
    if "aux" in df.columns:
        df = df.rename(columns={"aux": "loa"})  # length of affiliation (months)
    df["age"] = df["year"] - df["yob"]

    # Time index (Stata ym(year, month)) and sort by person/time
    df["date"] = df["year"] * 12 + (df["month"] - 1)
    df = df.sort_values(["id", "date"]).reset_index(drop=True)

    # Spells: a new spell starts when density status changes or the person changes
    new_spell = (df["dens"] != df["dens"].shift()) | (df["id"] != df["id"].shift())
    spell_id = new_spell.cumsum()
    df["spell_length"] = spell_id.groupby(spell_id).transform("size")

    # Wage growth index: wage relative to the yearly mean, carried forward
    df["mean_wage_yr"] = df.groupby("year")["wage"].transform("mean")
    df["wage_relative_mean"] = df["wage"] / df["mean_wage_yr"]
    # carryforward within person (validation point: Stata `carryforward` w/o by)
    df["wage_relative_mean"] = df.groupby("id")["wage_relative_mean"].ffill()

    # Reference decile from the last observation (latest year, month 12)
    mask = (df["year"] == latest_year) & (df["month"] == 12)
    ref = pd.Series(np.nan, index=df.index)
    ref.loc[mask] = _xtile(df.loc[mask, "wage_relative_mean"], 10)
    df["wage_decile_ref"] = ref.groupby(df["id"]).transform("max")

    df["wage_decile"] = df["wage_decile_ref"]
    df.loc[df["dens"] == 0, "wage_decile"] = 0  # unemployed / informal

    # Wage decile within (year, age, gender)
    df["wage_decile_age_sex"] = (
        df.groupby(["year", "age", "gender"])["wage_relative_mean"]
        .transform(lambda x: _xtile(x, 10))
    )

    # Daily -> monthly wage (assumed 20 workdays)
    df["wage"] = df["wage"] * 20

    # Keep latest year, mark status alive
    out = df[df["year"] == latest_year].copy()
    out["status"] = 1  # 1=alive, 2=dead, 3=disabled, 4=widowed

    out_path = os.path.join(paths.input, fname("baseyear_data", params.country))
    io_utils.save_stata(out, out_path)
    return out
