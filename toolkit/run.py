#!/usr/bin/env python3
"""CLI entry point for the PROST v2 Python toolkit.

Examples:
    python run.py --root .. --data-env full --check
    python run.py --root .. --data-env full --stage all
    python run.py --root .. --data-env all  --stage all
"""
from __future__ import annotations

import argparse
import sys

from prost2.config import Parameters, Paths, DATA_ENVIRONMENTS
from prost2 import pipeline


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="PROST v2 — Python pipeline")
    ap.add_argument("--root", default="..", help="repo root (contains Input/ and Output/)")
    ap.add_argument("--data-env", default="full",
                    choices=(*DATA_ENVIRONMENTS, "all"),
                    help="data environment to run")
    ap.add_argument("--stage", default="all",
                    choices=("all", "preprocess", "project"))
    ap.add_argument("--simname", default="Baseline", help="scenario name in output files")
    ap.add_argument("--check", action="store_true",
                    help="only report input-file presence and exit")
    args = ap.parse_args(argv)

    params = Parameters(simname=args.simname)
    paths = Paths(root=args.root)

    if args.check:
        print(f"Input check under: {paths.input}")
        ok = True
        for label, path, present in pipeline.check_inputs(params, paths):
            mark = "OK " if present else "-- "
            ok = ok and present
            print(f"  [{mark}] {label:24s} {path}")
        print("\nAll required inputs present." if ok
              else "\nSome inputs are missing (upload them to Input/ via Git LFS).")
        return 0

    envs = DATA_ENVIRONMENTS if args.data_env == "all" else (args.data_env,)
    for env in envs:
        pipeline.run_pipeline(params, paths, env, stage=args.stage)
    return 0


if __name__ == "__main__":
    sys.exit(main())
