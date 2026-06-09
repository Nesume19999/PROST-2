"""Shared longitudinal feature engineering.

These helpers reproduce, in pandas, the variable construction that the Stata
pre-processing files build on the affiliate panel (spells, contribution
density, pension gaps, wage deciles). They are kept separate so every modelling
stage (transitions, wages, benefits) can reuse the exact same definitions and
each piece is independently testable.

Expected input columns: id, year, month, yob, gender, wage, dens, los, loa
(`aux` is accepted and renamed to `loa`).
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def add_age_and_date(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    if "aux" in df.columns and "loa" not in df.columns:
        df = df.rename(columns={"aux": "loa"})
    df["age"] = df["year"] - df["yob"]
    df["date"] = df["year"] * 12 + (df["month"] - 1)   # Stata ym(year, month)
    return df.sort_values(["id", "date"]).reset_index(drop=True)


def add_spells(df: pd.DataFrame) -> pd.DataFrame:
    """Spell ids and within-spell duration (matches Step 04 lines 116-127)."""
    df = df.copy()
    new_spell = (df["dens"] != df["dens"].shift()) | (df["id"] != df["id"].shift())
    spell_id = new_spell.cumsum()
    grp = df.groupby(spell_id)
    df["total_spell_length"] = grp["dens"].transform("size")
    df["spell_length"] = grp.cumcount() + 1          # time-in-spell to date (_n)
    df["log_spell_length"] = np.log(df["spell_length"])
    return df


def add_contribution_density(df: pd.DataFrame) -> pd.DataFrame:
    """contribution_density = los / loa ; log_cod = log(max(cod, 0.001))."""
    df = df.copy()
    df["contribution_density"] = df["los"] / df["loa"]
    df["log_cod"] = np.log(np.maximum(df["contribution_density"], 0.001))
    return df


def add_pension_gaps(df: pd.DataFrame, retage_male: int = 65,
                     retage_female: int = 65,
                     retcont_min: float = (750 / 52) * 12) -> pd.DataFrame:
    """Months to retirement eligibility (Step 04 lines 140-149)."""
    df = df.copy()
    age_gap = np.where(
        df["gender"] == 1,
        np.maximum(retage_male - df["age"], 0) * 12,
        np.maximum(retage_female - df["age"], 0) * 12,
    )
    df["age_gap"] = age_gap
    df["los_gap"] = np.maximum(retcont_min - df["los"], 0)
    df["pension_gap"] = np.maximum(df["age_gap"], df["los_gap"])
    return df


def _xtile(s: pd.Series, n: int = 10) -> pd.Series:
    valid = s.dropna()
    if valid.empty:
        return pd.Series(np.nan, index=s.index)
    try:
        binned = pd.qcut(s, n, labels=range(1, n + 1), duplicates="drop")
        return pd.Series(binned, index=s.index).astype("float")
    except ValueError:
        ranks = s.rank(method="first", pct=True)
        return np.ceil(ranks * n).clip(1, n)


def add_wage_deciles(df: pd.DataFrame, latest_year: int | None = None) -> pd.DataFrame:
    """Relative wage, carried-forward, and the reference decile.

    Mirrors Step 04 lines 156-174: deciles are assigned from the relative wage
    at (latest_year, December); a person's reference decile is then their last
    known decile, applied to their whole career.
    """
    df = df.copy()
    if latest_year is None:
        latest_year = int(df["year"].max())

    df["mean_wage_yr"] = df.groupby("year")["wage"].transform("mean")
    df["wage_relative_mean"] = df["wage"] / df["mean_wage_yr"]
    # carryforward by id (Stata: by id: carryforward)
    df["wage_relative_mean"] = df.groupby("id")["wage_relative_mean"].ffill()

    mask = (df["year"] == latest_year) & (df["month"] == 12)
    ref_last = pd.Series(np.nan, index=df.index)
    ref_last.loc[mask] = _xtile(df.loc[mask, "wage_relative_mean"], 10)
    df["wage_decile_ref"] = ref_last.groupby(df["id"]).transform("max")

    df["wage_decile"] = df["wage_decile_ref"]
    df.loc[df["dens"] == 0, "wage_decile"] = 0
    return df


def add_transitions(df: pd.DataFrame, latest_year: int | None = None) -> pd.DataFrame:
    """Next-period state and the in/out transition indicators.

    Mirrors Step 04 lines 188-204. `transition_out` is defined only for
    currently-contributing months, `transition_in` only for non-contributing
    months; both are set missing at the end of the observation window and at a
    person's final observation (where the lead is undefined).
    """
    df = df.copy()
    if latest_year is None:
        latest_year = int(df["year"].max())

    df["next_decile"] = df.groupby("id")["wage_decile"].shift(-1)
    next_dens = df.groupby("id")["dens"].shift(-1)
    valid_next = next_dens.notna() & ~(
        (df["year"] == latest_year) & (df["month"] == 12))

    # Contribution state. Stata uses `wage_decile > 0`, which equals dens == 1
    # except where the reference decile is missing (there Stata's `missing > 0`
    # is TRUE, pandas' NaN > 0 is FALSE). We key off `dens` directly to encode
    # the intended "contributed this month" state without that ambiguity.
    current_state = (df["dens"] == 1)
    next_state = (next_dens == 1)

    df["transition_out"] = np.where(
        current_state & valid_next, (~next_state).astype(float), np.nan)
    df["transition_in"] = np.where(
        (~current_state) & valid_next, next_state.astype(float), np.nan)
    return df
