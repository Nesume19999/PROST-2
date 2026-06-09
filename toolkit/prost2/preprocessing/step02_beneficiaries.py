"""Step 02 — Generate the beneficiary (pensioner) database.

Port of `02 - Pre-processing - Generate beneficiary database.do`.

INPUT  (Input/):  "3 Input from client - microdata about beneficiaries.dta"
OUTPUT (Input/):  pensioners_MEX.dta

Recodes the raw beneficiary microdata into pension class / type / id and
renames the benefit column.
"""
from __future__ import annotations

import os
import numpy as np
import pandas as pd

from .. import io_utils
from ..config import Parameters, Paths, RAW_BENEFICIARIES, fname

# type letter -> (pension_class, pension_type, pension_id)
#   class: 1=DB (B,C,D), 2=DC (E,F,G)
#   type : 1=Old-age (B,E), 2=Disability (C,F), 3=Survivor (D,G)
_TYPE_MAP = {
    "B": (1, 1, 1),
    "C": (1, 2, 2),
    "D": (1, 3, 3),
    "E": (2, 1, 4),
    "F": (2, 2, 5),
    "G": (2, 3, 6),
}


def run(params: Parameters, paths: Paths) -> pd.DataFrame:
    ben_path = os.path.join(paths.input, RAW_BENEFICIARIES)
    df = io_utils.read_stata(ben_path)

    # Drop pensions with missing type (aligns counts with aggregate totals)
    df = df[df["type"].astype(str).str.strip() != ""].copy()

    df["pension_class"] = df["type"].map(lambda t: _TYPE_MAP.get(t, (np.nan,) * 3)[0])
    df["pension_type"] = df["type"].map(lambda t: _TYPE_MAP.get(t, (np.nan,) * 3)[1])
    df["pension_id"] = df["type"].map(lambda t: _TYPE_MAP.get(t, (np.nan,) * 3)[2])

    if "monthlybenefit" in df.columns:
        df = df.rename(columns={"monthlybenefit": "pension_benefit"})

    df = df.drop(columns=[c for c in ("iden", "type") if c in df.columns])

    out_path = os.path.join(paths.input, fname("pensioners_data", params.country))
    io_utils.save_stata(df, out_path)
    return df
