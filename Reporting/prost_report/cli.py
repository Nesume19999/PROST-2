"""
cli.py
======
Command-line entry point that ties the toolkit together:

    prepare -> charts -> tables -> report   (per simulation)
    compare                                  (when two simulations are given)

Example:
    python3 -m prost_report.cli \\
        --outdir ../sample_output --reportdir ../report_output \\
        --sim Baseline --sim Reform --compare \\
        --contrib-rate 10 --periods 12 --currency MXN --country MEX
"""

from __future__ import annotations

import argparse
import os
import sys

from .prepare import ReportParams, load_simulation
from .charts import build_charts
from .tables import build_tables
from .report import build_report
from .compare import compare_simulations


def build_arg_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="prost_report",
        description="Build pension projection reports from PROST v2 output CSVs.",
    )
    ap.add_argument("--outdir", required=True,
                    help="Folder containing the PROST v2 in-year reporting CSVs.")
    ap.add_argument("--reportdir", required=True,
                    help="Folder where charts, tables and reports are written.")
    ap.add_argument("--sim", action="append", default=[], dest="sims",
                    help="Simulation name (repeatable). e.g. --sim Baseline --sim Reform")
    ap.add_argument("--compare", action="store_true",
                    help="Also produce a comparison of the first two simulations.")
    ap.add_argument("--contrib-rate", type=float, default=10.0,
                    help="Assumed contribution rate, %% of covered wage (default 10).")
    ap.add_argument("--periods", type=int, default=12,
                    help="Pay periods per year used to annualise amounts (default 12).")
    ap.add_argument("--currency", default="LCU", help="Currency label for charts/tables.")
    ap.add_argument("--country", default="", help="Country label for report titles.")
    return ap


def run(args) -> int:
    if not args.sims:
        print("error: provide at least one --sim", file=sys.stderr)
        return 2

    params = ReportParams(
        contrib_rate=args.contrib_rate, periods=args.periods,
        currency=args.currency, country=args.country,
    )
    os.makedirs(args.reportdir, exist_ok=True)

    loaded = {}
    for sim in args.sims:
        print(f"\n=== Simulation: {sim} ===")
        sd = load_simulation(args.outdir, sim, params)
        loaded[sim] = sd
        print(f"  prepared {sd.first_year}-{sd.last_year} "
              f"({len(sd.system)} years)")

        figdir = os.path.join(args.reportdir, "figures", sim)
        figs = build_charts(sd, figdir)
        print(f"  charts:  {len(figs)} PNG -> {figdir}")

        xlsx = os.path.join(args.reportdir, "tables", f"{sim}_PROST_tables.xlsx")
        build_tables(sd, xlsx)
        print(f"  tables:  {xlsx}")

        docx = os.path.join(args.reportdir, f"{sim}_PROST_report.docx")
        build_report(sd, figdir, docx)
        print(f"  report:  {docx}")

    if args.compare:
        if len(args.sims) < 2:
            print("warning: --compare needs two simulations; skipping.",
                  file=sys.stderr)
        else:
            a, b = loaded[args.sims[0]], loaded[args.sims[1]]
            print(f"\n=== Comparison: {a.sim} vs {b.sim} ===")
            res = compare_simulations(
                a, b,
                figdir=os.path.join(args.reportdir, "figures", "comparison"),
                xlsx_path=os.path.join(args.reportdir, "tables",
                                       f"Comparison_{a.sim}_vs_{b.sim}.xlsx"),
                docx_path=os.path.join(args.reportdir,
                                       f"Comparison_{a.sim}_vs_{b.sim}_report.docx"),
            )
            print(f"  figures: {len(res['figures'])}")
            print(f"  workbook: {res['workbook']}")
            print(f"  report:   {res['report']}")

    print("\nDone.")
    return 0


def main(argv=None) -> int:
    args = build_arg_parser().parse_args(argv)
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
