"""
prepare.py
==========
Load the four PROST v2 in-year reporting CSVs for one simulation and build the
tidy indicator tables used by the charts, tables, report and comparison
modules.

This mirrors the Stata module "R2 - Prepare indicators.do" exactly, so it also
serves as an independent cross-check of that module's numbers.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

import numpy as np
import pandas as pd

# Categorical columns that the model writes as value-label text. Depending on
# the file they may arrive as strings ("Total", "Male") or as integers
# (pension_type = 1,2,3). We coerce them all to clean strings so filters such
# as `gender == "Total"` behave identically across files.
CATEGORY_COLS = [
    "gender", "wage_decile", "dens", "age_grp", "age",
    "pension_type", "pension_class",
]

TYPE_LABELS = {1: "Old-age", 2: "Disability", 3: "Survivor"}


@dataclass
class ReportParams:
    """User assumptions that drive the (illustrative) financing block."""
    contrib_rate: float = 10.0   # contribution rate, % of covered wage
    periods: int = 12            # pay periods per year (to annualise amounts)
    currency: str = "LCU"        # currency label for money axes
    country: str = ""            # country label for titles


@dataclass
class SimData:
    """Prepared indicators for a single simulation."""
    sim: str
    params: ReportParams
    system: pd.DataFrame      # one row per year: headline indicators
    bytype: pd.DataFrame      # year x pension type: beneficiaries & avg pension
    byage: pd.DataFrame       # year x gender x age group: beneficiaries
    bydecile: pd.DataFrame    # year x wage decile: affiliate indicators
    years: tuple = field(default=())

    @property
    def first_year(self) -> int:
        return int(self.system["year"].min())

    @property
    def last_year(self) -> int:
        return int(self.system["year"].max())


# --------------------------------------------------------------------------- #
#  CSV loading helpers                                                         #
# --------------------------------------------------------------------------- #
def _csv_path(outdir: str, sim: str, kind: str) -> str:
    names = {
        "pens_tot": "Pensioner-Reporting-Totals",
        "pens_brk": "Pensioner-Reporting-Breakdowns",
        "aff_tot": "Affiliate-Reporting-Totals",
        "aff_brk": "Affiliate-Reporting-Breakdowns",
    }
    fname = f"1_PROSTv2-{sim}-Inyear-{names[kind]}.csv"
    return os.path.join(outdir, fname)


def _read(outdir: str, sim: str, kind: str) -> pd.DataFrame:
    """Read one reporting CSV and standardise its categorical columns."""
    path = _csv_path(outdir, sim, kind)
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Expected PROST output not found:\n  {path}\n"
            f"(simulation '{sim}', file kind '{kind}')"
        )
    df = pd.read_csv(path)
    # Some build scripts name the working-age column "working_age".
    if "working_age" in df.columns and "working_age_total" not in df.columns:
        df = df.rename(columns={"working_age": "working_age_total"})
    for col in CATEGORY_COLS:
        if col in df.columns:
            df[col] = df[col].astype(str).str.strip()
    return df


# --------------------------------------------------------------------------- #
#  Per-file preparation steps                                                  #
# --------------------------------------------------------------------------- #
def _pensioner_totals(outdir: str, sim: str) -> pd.DataFrame:
    df = _read(outdir, sim, "pens_tot")
    grand = df[
        (df["gender"] == "Total")
        & (df["age_grp"] == "Total")
        & (df["pension_type"] == "Total")
        & (df["pension_class"] == "Total")
    ].copy()
    grand["total_beneficiaries"] = grand[["retired", "disabled", "widowed"]].sum(axis=1)
    grand = grand.rename(columns={"avg_pension": "avg_pension_all"})
    keep = ["year", "retired", "disabled", "widowed", "deceased",
            "total_beneficiaries", "avg_pension_all", "pension_index"]
    return grand[keep].reset_index(drop=True)


def _affiliate_totals(outdir: str, sim: str) -> pd.DataFrame:
    df = _read(outdir, sim, "aff_tot")
    grand = df[
        (df["gender"] == "Total")
        & (df["wage_decile"] == "Total")
        & (df["dens"] == "Total")
    ].copy()
    grand = grand.rename(columns={"wage": "avg_wage"})
    keep = ["year", "num_contributors", "num_affiliates", "num_inactive",
            "population_total", "working_age_total", "avg_wage", "avg_age",
            "contribution_density"]
    return grand[keep].reset_index(drop=True)


def _pensioner_by_type(outdir: str, sim: str):
    df = _read(outdir, sim, "pens_brk")
    df["ptype"] = pd.to_numeric(df["pension_type"], errors="coerce")
    df = df[df["ptype"].isin([1, 2, 3])].copy()
    df["bene"] = df[["retired", "disabled", "widowed"]].sum(axis=1)
    df["benefit_mass"] = df["bene"] * df["avg_pension"]

    g = df.groupby(["year", "ptype"], as_index=False).agg(
        bene=("bene", "sum"), benefit_mass=("benefit_mass", "sum")
    )
    g["avg_pension_type"] = g["benefit_mass"] / g["bene"]
    g["type_label"] = g["ptype"].map(TYPE_LABELS)
    g["simulation"] = sim
    bytype = g[["simulation", "year", "ptype", "type_label",
                "bene", "avg_pension_type"]].sort_values(["year", "ptype"])

    # Per-year benefit expenditure (per pay period) = sum of benefit mass.
    exp_year = g.groupby("year", as_index=False)["benefit_mass"].sum()
    exp_year = exp_year.rename(columns={"benefit_mass": "benefit_expenditure_period"})

    # Old-age average pension by year (for the replacement ratio).
    oldage = g[g["ptype"] == 1][["year", "avg_pension_type"]].rename(
        columns={"avg_pension_type": "avg_pension_oldage"}
    )
    return bytype.reset_index(drop=True), exp_year, oldage


def _pensioner_by_age(outdir: str, sim: str) -> pd.DataFrame:
    df = _read(outdir, sim, "pens_brk")
    df = df[df["gender"].isin(["Male", "Female"])].copy()
    df["age_grp_n"] = pd.to_numeric(df["age_grp"], errors="coerce")
    df = df.dropna(subset=["age_grp_n"])
    df["bene"] = df[["retired", "disabled", "widowed"]].sum(axis=1)
    g = df.groupby(["year", "gender", "age_grp_n"], as_index=False)["bene"].sum()
    g = g.rename(columns={"age_grp_n": "age_grp"})
    g["age_grp"] = g["age_grp"].astype(int)
    g["simulation"] = sim
    return g[["simulation", "year", "gender", "age_grp", "bene"]].sort_values(
        ["year", "gender", "age_grp"]
    ).reset_index(drop=True)


def _affiliate_by_decile(outdir: str, sim: str) -> pd.DataFrame:
    df = _read(outdir, sim, "aff_brk")
    df["decile_n"] = pd.to_numeric(df["wage_decile"], errors="coerce")
    df = df.dropna(subset=["decile_n"])
    g = df.groupby(["year", "decile_n"], as_index=False).agg(
        num_contributors=("num_contributors", "sum"),
        num_affiliates=("num_affiliates", "sum"),
        num_inactive=("num_inactive", "sum"),
        contribution_density=("contribution_density", "mean"),
        wage=("wage", "mean"),
    )
    g = g.rename(columns={"decile_n": "wage_decile"})
    g["wage_decile"] = g["wage_decile"].astype(int)
    g["simulation"] = sim
    return g.sort_values(["year", "wage_decile"]).reset_index(drop=True)


# --------------------------------------------------------------------------- #
#  Public entry point                                                         #
# --------------------------------------------------------------------------- #
def load_simulation(outdir: str, sim: str,
                    params: ReportParams | None = None) -> SimData:
    """Read all four CSVs for one simulation and assemble indicator tables."""
    params = params or ReportParams()

    pens_tot = _pensioner_totals(outdir, sim)
    aff_tot = _affiliate_totals(outdir, sim)
    bytype, exp_year, oldage = _pensioner_by_type(outdir, sim)
    byage = _pensioner_by_age(outdir, sim)
    bydecile = _affiliate_by_decile(outdir, sim)

    # ---- Assemble the system-level time series (one row per year) ----------
    sysdf = (
        pens_tot
        .merge(aff_tot, on="year", how="outer")
        .merge(exp_year, on="year", how="left")
        .merge(oldage, on="year", how="left")
        .sort_values("year")
        .reset_index(drop=True)
    )

    cr = params.contrib_rate / 100.0
    pp = params.periods

    sysdf["dependency_ratio"] = 100 * sysdf["total_beneficiaries"] / sysdf["num_contributors"]
    sysdf["coverage_active"] = 100 * sysdf["num_contributors"] / sysdf["working_age_total"]
    sysdf["replacement_ratio"] = 100 * sysdf["avg_pension_oldage"] / sysdf["avg_wage"]

    sysdf["expenditure"] = sysdf["benefit_expenditure_period"] * pp
    sysdf["contributions"] = cr * sysdf["avg_wage"] * sysdf["num_contributors"] * pp
    sysdf["balance"] = sysdf["contributions"] - sysdf["expenditure"]
    sysdf["balance_pct_contrib"] = 100 * sysdf["balance"] / sysdf["contributions"]
    sysdf["spend_per_contributor"] = sysdf["expenditure"] / sysdf["num_contributors"]

    # Scaled copies for readable charts.
    sysdf["contributors_m"] = sysdf["num_contributors"] / 1e6
    sysdf["beneficiaries_m"] = sysdf["total_beneficiaries"] / 1e6
    sysdf["working_age_m"] = sysdf["working_age_total"] / 1e6
    sysdf["expenditure_b"] = sysdf["expenditure"] / 1e9
    sysdf["contributions_b"] = sysdf["contributions"] / 1e9
    sysdf["balance_b"] = sysdf["balance"] / 1e9

    sysdf.insert(0, "simulation", sim)

    return SimData(
        sim=sim, params=params, system=sysdf, bytype=bytype,
        byage=byage, bydecile=bydecile,
        years=(int(sysdf["year"].min()), int(sysdf["year"].max())),
    )
