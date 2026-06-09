"""Step 04 -- Estimate job entry/exit transition rates  (pipeline wiring).

The actual modelling lives in the independent, testable module
``prost2.transitions`` (T1 = job exit, T2 = job entry). This file only wires
that module into the preprocessing pipeline: it loads the longitudinal panel
(real .dta or a synthetic .parquet), samples, fits both cloglog models and
writes the fitted hazards.

The four data environments (full / very_low / low / extremely_low) differ in
the richness of the covariate set; only `full` is wired so far.
"""
from __future__ import annotations

import os
import numpy as np
import pandas as pd

from .. import io_utils, transitions
from ..config import Parameters, Paths, DEFAULT_SUBDIRS, RAW_LONGITUDINAL


def _load_panel(paths: Paths) -> pd.DataFrame:
    """Prefer the real .dta; fall back to the committed synthetic parquet."""
    real = os.path.join(paths.input, RAW_LONGITUDINAL)
    if os.path.exists(real):
        return io_utils.read_stata(real)
    syn = os.path.join(paths.input, "synthetic", "synthetic_affiliates.parquet")
    if os.path.exists(syn):
        return pd.read_parquet(syn)
    raise FileNotFoundError(
        f"No longitudinal panel found (looked for {real} and {syn})")


def run(params: Parameters, paths: Paths, data_env: str = "full",
        samplesize: int | None = None):
    if data_env != "full":
        raise NotImplementedError(
            f"step04 data_env={data_env!r} not wired yet (only 'full').")

    df = _load_panel(paths)
    samplesize = samplesize if samplesize is not None else params.samplesize
    if samplesize < 100:
        rng = np.random.default_rng(params.seed)
        ids = df["id"].drop_duplicates()
        keep = ids.sample(frac=samplesize / 100.0, random_state=params.seed)
        df = df[df["id"].isin(set(keep))]

    frame = transitions.prepare(df)
    exit_model = transitions.fit_exit(frame)
    entry_model = transitions.fit_entry(frame)

    frame["exit_hazard"] = transitions.predict_hazard(exit_model, frame)
    frame["entry_hazard"] = transitions.predict_hazard(entry_model, frame)

    out_dir = paths.default(DEFAULT_SUBDIRS["transitions"])
    io_utils.save_csv(
        frame[["id", "year", "month", "age", "gender", "wage_decile_ref",
               "spell_length", "exit_hazard", "entry_hazard"]],
        os.path.join(out_dir, f"transitions_{params.country}_{samplesize}.csv"),
    )
    return {"exit_model": exit_model, "entry_model": entry_model, "frame": frame}
