#!/usr/bin/env python3
"""
make_sample_csvs.py
===================
Convenience generator for *synthetic* PROST v2 in-year reporting outputs.

It writes the four CSV files the model's build script produces, for two
simulations ("Baseline" and "Reform"), so the Stata reporting toolkit can be
developed and tested end-to-end without a Stata run.

The schemas (column names, ordering, and the use of value-label text such as
"Male"/"Active"/"Total" for categorical columns) mirror what
`export delimited` writes in "1 - PROSTv2 - Build projection database.do".

A pure-Stata equivalent is provided in
"Reporting/R0 - Generate synthetic outputs.do"; either reproduces equivalent
data. Numbers here are illustrative only and carry no economic meaning.

Usage:
    python3 make_sample_csvs.py [output_dir]

Default output_dir is ../sample_output relative to this file.
"""

import csv
import math
import os
import sys

START_YEAR = 2025
END_YEAR = 2075
PENSION_TYPES = {1: "old-age", 2: "disability", 3: "survivor"}
AGE_GROUPS = list(range(50, 100, 5))  # 50,55,...,95 (beneficiary ages)


# --------------------------------------------------------------------------- #
#  Scenario trajectories (deterministic, illustrative)                        #
# --------------------------------------------------------------------------- #
def scenario_params(sim):
    """Return per-scenario shape parameters."""
    if sim == "Reform":
        # Reform: later retirement -> slower beneficiary growth, lower spend.
        return dict(benef_growth=0.022, contrib_growth=0.011, pension_level=0.95)
    # Baseline
    return dict(benef_growth=0.030, contrib_growth=0.008, pension_level=1.00)


def system_series(sim):
    """Build a per-year dict of the headline system aggregates."""
    p = scenario_params(sim)
    rows = {}
    for i, year in enumerate(range(START_YEAR, END_YEAR + 1)):
        # Demography: working-age population grows then plateaus/declines.
        working_age = 80.0e6 * (1 + 0.004 * i - 0.00010 * i * i)
        population = working_age / 0.62  # working-age share ~62%
        # Coverage of the active labour force declines slowly.
        coverage = 0.46 - 0.0010 * i
        contributors = working_age * coverage * (1 + p["contrib_growth"]) ** 0
        contributors = working_age * coverage
        # Beneficiaries grow with ageing (scenario-dependent).
        benef_total = 3.0e6 * (1 + p["benef_growth"]) ** i
        # Split beneficiaries across types.
        share = {1: 0.78, 2: 0.07, 3: 0.15}  # old-age, disability, survivor
        benef = {t: benef_total * s for t, s in share.items()}
        # Wages and pensions (monthly, local currency), grow ~nominal.
        avg_wage = 12000.0 * (1.035) ** i
        repl = {1: 0.42, 2: 0.35, 3: 0.30}
        avg_pension = {t: avg_wage * repl[t] * p["pension_level"] for t in PENSION_TYPES}
        rows[year] = dict(
            working_age=working_age,
            population=population,
            contributors=contributors,
            benef=benef,
            avg_wage=avg_wage,
            avg_pension=avg_pension,
        )
    return rows


# --------------------------------------------------------------------------- #
#  CSV writers                                                                #
# --------------------------------------------------------------------------- #
AFFIL_COLS = [
    "year", "gender", "wage_decile", "dens",
    "samplesize", "num_affiliates", "num_contributors", "num_inactive",
    "num_new_affiliates", "num_exiters", "num_reentrants",
    "retired", "disabled", "widowed", "deceased",
    "avg_age", "los", "loa", "wage", "contribution_density",
    "population_total", "working_age_total",
    "target_employment_rate", "employment_rate",
    "target_turnover_rate", "turnover_rate",
]

PENS_COLS = [
    "year", "gender", "age_grp", "pension_class", "pension_type",
    "retired", "disabled", "widowed", "deceased",
    "avg_pension", "pension_index",
]


def _affil_row(year, gender, decile, dens, s, frac=1.0, density=None):
    """Assemble one affiliate-reporting row (frac scales the stock columns)."""
    contributors = s["contributors"] * frac
    affiliates = contributors / 0.85
    inactive = affiliates - contributors
    if density is None:
        density = 0.72
    return {
        "year": year, "gender": gender, "wage_decile": decile, "dens": dens,
        "samplesize": round(affiliates / 1000.0, 1),
        "num_affiliates": round(affiliates, 1),
        "num_contributors": round(contributors, 1),
        "num_inactive": round(inactive, 1),
        "num_new_affiliates": round(affiliates * 0.05, 1),
        "num_exiters": round(affiliates * 0.04, 1),
        "num_reentrants": round(affiliates * 0.03, 1),
        "retired": 0, "disabled": 0, "widowed": 0, "deceased": round(affiliates * 0.006, 1),
        "avg_age": round(39.0 + 0.05 * (year - START_YEAR), 2),
        "los": round(11.0, 2), "loa": round(14.0, 2),
        "wage": round(s["avg_wage"], 2),
        "contribution_density": round(density, 4),
        "population_total": round(s["population"], 1),
        "working_age_total": round(s["working_age"], 1),
        "target_employment_rate": 95.0,
        "employment_rate": round(100 * contributors / affiliates, 2),
        "target_turnover_rate": 7.0,
        "turnover_rate": round(100 * (affiliates * 0.07) / (affiliates * 12), 4),
    }


def write_affiliate(path, series):
    tot = path["tot"]
    brk = path["brk"]
    with open(tot, "w", newline="") as ft, open(brk, "w", newline="") as fb:
        wt = csv.DictWriter(ft, fieldnames=AFFIL_COLS)
        wb = csv.DictWriter(fb, fieldnames=AFFIL_COLS)
        wt.writeheader()
        wb.writeheader()
        for year, s in series.items():
            # ---- Totals file: grand total + gender margins + density margins
            wt.writerow(_affil_row(year, "Total", "Total", "Total", s))
            wt.writerow(_affil_row(year, "Male", "Total", "Total", s, frac=0.55))
            wt.writerow(_affil_row(year, "Female", "Total", "Total", s, frac=0.45))
            wt.writerow(_affil_row(year, "Total", "Total", "Active", s, frac=0.80, density=0.90))
            wt.writerow(_affil_row(year, "Total", "Total", "Inactive", s, frac=0.20, density=0.15))
            # ---- Breakdowns file: gender x decile x density (full detail)
            for gi, gender in enumerate(("Male", "Female")):
                gfrac = 0.55 if gender == "Male" else 0.45
                for decile in range(1, 11):
                    # density rises with decile; deciles split the stock evenly-ish
                    dec_frac = gfrac * (0.07 + 0.006 * decile)
                    for dens, dfrac, dval in (("Active", 0.80, 0.55 + 0.04 * decile),
                                              ("Inactive", 0.20, 0.10 + 0.01 * decile)):
                        wb.writerow(_affil_row(
                            year, gender, str(decile), dens, s,
                            frac=dec_frac * dfrac, density=min(dval, 0.99)))


def write_pensioner(path, series):
    tot = path["tot"]
    brk = path["brk"]
    with open(tot, "w", newline="") as ft, open(brk, "w", newline="") as fb:
        wt = csv.DictWriter(ft, fieldnames=PENS_COLS)
        wb = csv.DictWriter(fb, fieldnames=PENS_COLS)
        wt.writeheader()
        wb.writeheader()
        for year, s in series.items():
            benef = s["benef"]
            avg_pension = s["avg_pension"]
            total_benef = sum(benef.values())
            # Weighted average pension across all beneficiaries (grand total row)
            wavg = sum(benef[t] * avg_pension[t] for t in benef) / total_benef
            deceased = total_benef * 0.025
            # ---- Totals file: one grand-total row per year
            wt.writerow({
                "year": year, "gender": "Total", "age_grp": "Total",
                "pension_class": "Total", "pension_type": "Total",
                "retired": round(benef[1], 1),
                "disabled": round(benef[2], 1),
                "widowed": round(benef[3], 1),
                "deceased": round(deceased, 1),
                "avg_pension": round(wavg, 2),
                "pension_index": round(0.03, 4),
            })
            # ---- Breakdowns file: gender x age_grp x type (class = 1)
            # Age weights are normalised so that, summed over age groups and
            # genders, the breakdown reconciles EXACTLY with the totals file.
            raw_w = {ag: math.exp(-((ag - 70) ** 2) / (2 * 12.0 ** 2)) for ag in AGE_GROUPS}
            w_sum = sum(raw_w.values())
            age_w = {ag: raw_w[ag] / w_sum for ag in AGE_GROUPS}  # sums to 1
            for gender, gfrac in (("Male", 0.48), ("Female", 0.52)):  # sums to 1
                for ag in AGE_GROUPS:
                    for t in PENSION_TYPES:
                        cnt = benef[t] * gfrac * age_w[ag]
                        col = {1: "retired", 2: "disabled", 3: "widowed"}[t]
                        row = {
                            "year": year, "gender": gender, "age_grp": str(ag),
                            "pension_class": "1", "pension_type": str(t),
                            "retired": 0, "disabled": 0, "widowed": 0,
                            "deceased": round(cnt * 0.02, 2),
                            "avg_pension": round(avg_pension[t], 2),
                            "pension_index": "",
                        }
                        row[col] = round(cnt, 2)
                        wb.writerow(row)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "sample_output")
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    for sim in ("Baseline", "Reform"):
        series = system_series(sim)
        base = f"1_PROSTv2-{sim}-Inyear"
        write_affiliate({
            "tot": os.path.join(out, f"{base}-Affiliate-Reporting-Totals.csv"),
            "brk": os.path.join(out, f"{base}-Affiliate-Reporting-Breakdowns.csv"),
        }, series)
        write_pensioner({
            "tot": os.path.join(out, f"{base}-Pensioner-Reporting-Totals.csv"),
            "brk": os.path.join(out, f"{base}-Pensioner-Reporting-Breakdowns.csv"),
        }, series)
        print(f"  wrote 4 CSVs for simulation '{sim}'")
    print(f"Synthetic PROST outputs written to: {out}")


if __name__ == "__main__":
    main()
