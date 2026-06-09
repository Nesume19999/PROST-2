"""I/O helpers: read Stata/CSV inputs, write outputs in Duncan's naming scheme."""
from __future__ import annotations

import os
import pandas as pd


def read_stata(path: str) -> pd.DataFrame:
    """Read a .dta file. Uses pandas (pyreadstat backend if available)."""
    if not os.path.exists(path):
        raise FileNotFoundError(f"Stata file not found: {path}")
    return pd.read_stata(path, convert_categoricals=False)


def read_csv(path: str, **kw) -> pd.DataFrame:
    if not os.path.exists(path):
        raise FileNotFoundError(f"CSV file not found: {path}")
    return pd.read_csv(path, **kw)


def save_stata(df: pd.DataFrame, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_stata(path, write_index=False)


def save_csv(df: pd.DataFrame, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    df.to_csv(path, index=False)


def output_name(kind: str, simname: str, startyear: int, endyear: int) -> str:
    """Reproduce the Stata output filenames, e.g.
    `1_PROSTv2-Baseline-Affiliates-2025-2104.csv`.

    kind is one of: 'Affiliates', 'Pensioners',
    'Inyear-Affiliate-Reporting-Totals', 'Inyear-Affiliate-Reporting-Breakdowns',
    'Inyear-Pensioner-Reporting-Totals', 'Inyear-Pensioner-Reporting-Breakdowns'.
    """
    if kind in ("Affiliates", "Pensioners"):
        return f"1_PROSTv2-{simname}-{kind}-{startyear}-{endyear}.csv"
    return f"1_PROSTv2-{simname}-{kind}.csv"
