"""
charts.py
=========
Produce the standard set of projection charts (PNG) for one simulation.
Mirrors the Stata module "R3 - Charts.do".
"""

from __future__ import annotations

import os

import matplotlib
matplotlib.use("Agg")  # headless: write files, never open a window
import matplotlib.pyplot as plt

from .prepare import SimData, TYPE_LABELS

plt.rcParams.update({
    "figure.figsize": (8, 4.5),
    "figure.dpi": 130,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "font.size": 10,
})

# Distinct, colour-blind-friendly palette.
C = ["#1f77b4", "#d62728", "#2ca02c", "#9467bd", "#ff7f0e"]


def _save(fig, path):
    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def build_charts(sd: SimData, figdir: str) -> list[str]:
    """Write all charts for simulation `sd` into `figdir`. Returns file paths."""
    os.makedirs(figdir, exist_ok=True)
    sys = sd.system
    sim = sd.sim
    cur = sd.params.currency
    fy = sd.last_year
    written = []

    def out(name):
        p = os.path.join(figdir, name)
        written.append(p)
        return p

    # 1. Contributors vs beneficiaries -------------------------------------
    fig, ax = plt.subplots()
    ax.plot(sys["year"], sys["contributors_m"], color=C[0], lw=2, label="Contributors")
    ax.plot(sys["year"], sys["beneficiaries_m"], color=C[1], lw=2, ls="--", label="Beneficiaries")
    ax.set(title=f"Contributors vs beneficiaries — {sim}",
           xlabel="Year", ylabel="Persons (millions)")
    ax.legend(loc="best")
    _save(fig, out("01_contributors_vs_beneficiaries.png"))

    # 2. Dependency ratio ---------------------------------------------------
    fig, ax = plt.subplots()
    ax.plot(sys["year"], sys["dependency_ratio"], color=C[3], lw=2)
    ax.set(title=f"System dependency ratio — {sim}",
           xlabel="Year", ylabel="Beneficiaries per 100 contributors")
    _save(fig, out("02_dependency_ratio.png"))

    # 3. Beneficiaries by pension type -------------------------------------
    fig, ax = plt.subplots()
    bt = sd.bytype.copy()
    bt["bene_m"] = bt["bene"] / 1e6
    for i, (pt, lab) in enumerate(TYPE_LABELS.items()):
        sub = bt[bt["ptype"] == pt]
        ax.plot(sub["year"], sub["bene_m"], color=C[i], lw=2, label=lab)
    ax.set(title=f"Beneficiaries by pension type — {sim}",
           xlabel="Year", ylabel="Persons (millions)")
    ax.legend(loc="best")
    _save(fig, out("03_beneficiaries_by_type.png"))

    # 4. Average wage vs average old-age pension ---------------------------
    fig, ax = plt.subplots()
    ax.plot(sys["year"], sys["avg_wage"], color=C[0], lw=2, label="Average wage")
    ax.plot(sys["year"], sys["avg_pension_oldage"], color=C[2], lw=2, ls="--",
            label="Average old-age pension")
    ax.set(title=f"Average wage vs old-age pension — {sim}",
           xlabel="Year", ylabel=f"{cur} per period")
    ax.legend(loc="best")
    _save(fig, out("04_wage_vs_pension.png"))

    # 5. Replacement ratio and coverage ------------------------------------
    fig, ax = plt.subplots()
    ax.plot(sys["year"], sys["replacement_ratio"], color=C[0], lw=2,
            label="Old-age pension / wage")
    ax.plot(sys["year"], sys["coverage_active"], color=C[4], lw=2, ls="--",
            label="Coverage of working-age")
    ax.set(title=f"Replacement ratio and coverage — {sim}",
           xlabel="Year", ylabel="Percent")
    ax.legend(loc="best")
    _save(fig, out("05_replacement_and_coverage.png"))

    # 6. Financial balance --------------------------------------------------
    fig, ax = plt.subplots()
    ax.plot(sys["year"], sys["contributions_b"], color=C[0], lw=2, label="Contributions")
    ax.plot(sys["year"], sys["expenditure_b"], color=C[1], lw=2, ls="--", label="Expenditure")
    ax.plot(sys["year"], sys["balance_b"], color=C[3], lw=2, ls=":", label="Net balance")
    ax.axhline(0, color="grey", lw=0.8)
    ax.set(title=f"Illustrative financial balance — {sim}",
           xlabel="Year", ylabel=f"{cur}, billions per year")
    ax.legend(loc="best")
    ax.text(0.0, -0.28,
            "Contributions = rate × average wage × contributors. Parameter-driven; illustrative only.",
            transform=ax.transAxes, fontsize=7, color="grey")
    _save(fig, out("06_financial_balance.png"))

    # 7. Beneficiary age pyramid (final year) ------------------------------
    fig, ax = plt.subplots()
    ba = sd.byage[sd.byage["year"] == fy].copy()
    ba["bene_m"] = ba["bene"] / 1e6
    male = ba[ba["gender"] == "Male"].sort_values("age_grp")
    female = ba[ba["gender"] == "Female"].sort_values("age_grp")
    ax.barh(male["age_grp"], -male["bene_m"], height=4, color=C[0], label="Male")
    ax.barh(female["age_grp"], female["bene_m"], height=4, color=C[1], label="Female")
    ax.set(title=f"Beneficiary age structure, {fy} — {sim}",
           xlabel="Persons (millions) — Male | Female +", ylabel="Age group")
    # show absolute values on the x axis
    ticks = ax.get_xticks()
    ax.set_xticks(ticks)
    ax.set_xticklabels([f"{abs(t):.1f}" for t in ticks])
    ax.legend(loc="best")
    _save(fig, out("07_age_pyramid_final_year.png"))

    # 8. Contribution density by wage decile (final year) ------------------
    fig, ax = plt.subplots()
    bd = sd.bydecile[sd.bydecile["year"] == fy].sort_values("wage_decile")
    ax.bar(bd["wage_decile"], bd["contribution_density"], color=C[0])
    ax.set(title=f"Contribution density by wage decile, {fy} — {sim}",
           xlabel="Wage decile", ylabel="Average contribution density")
    ax.set_xticks(bd["wage_decile"])
    _save(fig, out("08_density_by_decile_final_year.png"))

    return written
