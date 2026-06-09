#!/usr/bin/env python3
"""
run_report.py
=============
Convenience driver for the PROST v2 Python reporting toolkit.

With no arguments it runs a full demo against the bundled synthetic outputs in
./sample_output and writes everything to ./report_output:

    python3 run_report.py

To point it at real model outputs, pass the same flags accepted by the CLI, e.g.

    python3 run_report.py --outdir "C:/.../Output" --reportdir "C:/.../Reports" \
        --sim Baseline --sim Reform --compare \
        --contrib-rate 10 --periods 12 --currency MXN --country MEX

See: python3 run_report.py --help
"""

import os
import sys

# Make the local package importable when run from this folder.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from prost_report.cli import main

HERE = os.path.dirname(os.path.abspath(__file__))

DEMO_ARGS = [
    "--outdir", os.path.join(HERE, "sample_output"),
    "--reportdir", os.path.join(HERE, "report_output"),
    "--sim", "Baseline",
    "--sim", "Reform",
    "--compare",
    "--contrib-rate", "10",
    "--periods", "12",
    "--currency", "MXN",
    "--country", "MEX",
]

if __name__ == "__main__":
    argv = sys.argv[1:] if len(sys.argv) > 1 else DEMO_ARGS
    raise SystemExit(main(argv))
