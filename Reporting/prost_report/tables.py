"""
tables.py
=========
Write a multi-sheet Excel workbook of key indicators for one simulation.
Mirrors the Stata module "R4 - Summary tables.do".
"""

from __future__ import annotations

import os
from datetime import date

import pandas as pd

from .prepare import SimData


def build_tables(sd: SimData, xlsx_path: str) -> str:
    """Write the summary workbook for simulation `sd`; return the path."""
    os.makedirs(os.path.dirname(os.path.abspath(xlsx_path)), exist_ok=True)
    sys = sd.system
    fy = sd.last_year

    # --- Overview ----------------------------------------------------------
    overview = sys[[
        "year", "num_contributors", "total_beneficiaries", "dependency_ratio",
        "coverage_active", "replacement_ratio", "avg_wage", "avg_pension_oldage",
        "population_total", "working_age_total",
    ]].rename(columns={
        "year": "Year",
        "num_contributors": "Contributors",
        "total_beneficiaries": "Beneficiaries",
        "dependency_ratio": "Dependency ratio (per 100)",
        "coverage_active": "Coverage (% working-age)",
        "replacement_ratio": "Replacement ratio (%)",
        "avg_wage": "Average wage",
        "avg_pension_oldage": "Average old-age pension",
        "population_total": "Total population",
        "working_age_total": "Working-age population",
    })

    # --- Beneficiaries by type (wide) -------------------------------------
    bt = sd.bytype.pivot(index="year", columns="type_label", values="bene")
    bt = bt.reset_index().rename(columns={"year": "Year"})
    for c in ("Old-age", "Disability", "Survivor"):
        if c not in bt.columns:
            bt[c] = 0.0
    bt["Total beneficiaries"] = bt[["Old-age", "Disability", "Survivor"]].sum(axis=1)
    bt = bt[["Year", "Old-age", "Disability", "Survivor", "Total beneficiaries"]]

    # --- Finances ----------------------------------------------------------
    fin = sys[[
        "year", "contributions", "expenditure", "balance",
        "balance_pct_contrib", "spend_per_contributor",
    ]].rename(columns={
        "year": "Year",
        "contributions": "Contributions",
        "expenditure": "Expenditure",
        "balance": "Net balance",
        "balance_pct_contrib": "Balance (% of contributions)",
        "spend_per_contributor": "Expenditure per contributor",
    })

    # --- By age (final year) ----------------------------------------------
    ba = sd.byage[sd.byage["year"] == fy]
    by_age = ba.pivot(index="age_grp", columns="gender", values="bene").reset_index()
    by_age = by_age.rename(columns={"age_grp": "Age group"})
    for c in ("Male", "Female"):
        if c not in by_age.columns:
            by_age[c] = 0.0
    by_age["Total"] = by_age[["Male", "Female"]].sum(axis=1)

    # --- By decile (final year) -------------------------------------------
    bd = sd.bydecile[sd.bydecile["year"] == fy][[
        "wage_decile", "num_contributors", "num_affiliates",
        "contribution_density", "wage",
    ]].rename(columns={
        "wage_decile": "Wage decile",
        "num_contributors": "Contributors",
        "num_affiliates": "Affiliates",
        "contribution_density": "Contribution density",
        "wage": "Average wage",
    })

    # --- Notes -------------------------------------------------------------
    p = sd.params
    notes = pd.DataFrame({
        "Item": [
            "Simulation", "Country", "Currency", "Contribution rate (%)",
            "Pay periods per year", "Source", "Nature of finances", "Generated",
        ],
        "Value": [
            sd.sim, p.country, p.currency, p.contrib_rate, p.periods,
            "PROST v2 in-year reporting CSVs",
            "Illustrative, parameter-driven", date.today().isoformat(),
        ],
    })

    with pd.ExcelWriter(xlsx_path, engine="openpyxl") as xw:
        overview.to_excel(xw, sheet_name="Overview", index=False)
        bt.to_excel(xw, sheet_name="Beneficiaries", index=False)
        fin.to_excel(xw, sheet_name="Finances", index=False)
        by_age.to_excel(xw, sheet_name=f"By age {fy}", index=False)
        bd.to_excel(xw, sheet_name=f"By decile {fy}", index=False)
        notes.to_excel(xw, sheet_name="Notes", index=False)
        _autosize(xw)

    return xlsx_path


def _autosize(writer):
    """Widen columns to fit their content for readability."""
    for ws in writer.book.worksheets:
        for col in ws.columns:
            width = max((len(str(c.value)) for c in col if c.value is not None),
                        default=8)
            ws.column_dimensions[col[0].column_letter].width = min(width + 2, 40)
