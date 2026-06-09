#!/usr/bin/env python3
"""Generate and persist the synthetic affiliate panel.

Writes a parquet file (efficient, ~Git-LFS friendly) plus a small metadata
sidecar documenting the seed and assumptions, so the synthetic data is fully
reproducible.

Usage:
    python scripts/generate_synthetic_data.py                  # 50k workers
    python scripts/generate_synthetic_data.py --n-workers 10000
    python scripts/generate_synthetic_data.py --out ../Input/synthetic
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from prost2 import synthetic  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Generate synthetic affiliate panel")
    ap.add_argument("--n-workers", type=int, default=50_000)
    ap.add_argument("--start-year", type=int, default=2005)
    ap.add_argument("--end-year", type=int, default=2024)
    ap.add_argument("--seed", type=int, default=synthetic.DEFAULT_SEED)
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "..", "Input", "synthetic"))
    args = ap.parse_args(argv)

    cfg = synthetic.SyntheticConfig(
        n_workers=args.n_workers, start_year=args.start_year,
        end_year=args.end_year, seed=args.seed)
    print(f"Generating {cfg.n_workers:,} workers, {cfg.start_year}-{cfg.end_year} "
          f"(seed {cfg.seed})...")
    df = synthetic.generate(cfg)

    os.makedirs(args.out, exist_ok=True)
    data_path = os.path.join(args.out, "synthetic_affiliates.parquet")
    df.to_parquet(data_path, index=False)

    meta = {
        "config": asdict(cfg),
        "rows": int(len(df)),
        "workers": int(df["id"].nunique()),
        "mean_density": float(df["dens"].mean()),
        "known_baseline": {
            "true_exit_hazard": synthetic.TRUE_EXIT_HAZARD,
            "true_entry_hazard": synthetic.TRUE_ENTRY_HAZARD,
            "stationary_density": synthetic.STATIONARY_DENSITY,
        },
    }
    with open(os.path.join(args.out, "synthetic_metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)

    print(f"  rows={meta['rows']:,}  workers={meta['workers']:,}  "
          f"mean density={meta['mean_density']:.3f}")
    print(f"  wrote {data_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
