"""
prost_report
============
A reporting toolkit for PROST v2 pension projections.

It reads the in-year reporting CSVs produced by the model's build script
("1 - PROSTv2 - Build projection database.do") and turns them into charts,
Excel summary tables, a Word report document, and scenario comparisons.

It does NOT change or depend on the Stata model: it consumes the same
`export delimited` CSVs the model already writes. A parallel pure-Stata
version of this toolkit lives in the R*.do files alongside this package.

Public API:
    load_simulation(outdir, sim, params)   -> SimData
    build_charts(simdata, figdir)
    build_tables(simdata, xlsx_path)
    build_report(simdata, figdir, docx_path)
    compare_simulations(sim_a, sim_b, ...)
"""

from .prepare import SimData, ReportParams, load_simulation
from .charts import build_charts
from .tables import build_tables
from .report import build_report
from .compare import compare_simulations

__all__ = [
    "SimData", "ReportParams", "load_simulation",
    "build_charts", "build_tables", "build_report", "compare_simulations",
]
