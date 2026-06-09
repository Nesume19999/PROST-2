"""Pipeline orchestration: preprocessing (01-06) + projection, per data environment."""
from __future__ import annotations

import os
from .config import (
    Parameters, Paths, DATA_ENVIRONMENTS, DEFAULT_SUBDIRS,
    RAW_LONGITUDINAL, RAW_BENEFICIARIES, fname,
)
from .preprocessing import (
    step01_baseyear, step02_beneficiaries, step03_affiliation,
    step04_transitions, step05_lifecycle_wages, step06_rates,
)
from . import projection

PREPROCESS_STEPS = [
    ("01 baseyear", lambda p, pa, env: step01_baseyear.run(p, pa)),
    ("02 beneficiaries", lambda p, pa, env: step02_beneficiaries.run(p, pa)),
    ("03 affiliation", lambda p, pa, env: step03_affiliation.run(p, pa, env)),
    ("04 transitions", lambda p, pa, env: step04_transitions.run(p, pa, env)),
    ("05 lifecycle wages", lambda p, pa, env: step05_lifecycle_wages.run(p, pa)),
    ("06 rates", lambda p, pa, env: step06_rates.run(p, pa)),
]


def required_inputs(params: Parameters, paths: Paths) -> dict[str, str]:
    """Map of human label -> absolute path for the raw/assumption inputs."""
    c = params.country
    d = paths.default
    return {
        "raw longitudinal": os.path.join(paths.input, RAW_LONGITUDINAL),
        "raw beneficiaries": os.path.join(paths.input, RAW_BENEFICIARIES),
        "population": os.path.join(d(DEFAULT_SUBDIRS["population"]), fname("population", c)),
        "population (hist)": os.path.join(d(DEFAULT_SUBDIRS["population_obs"]), fname("population_hist", c)),
        "mortality": os.path.join(d(DEFAULT_SUBDIRS["mortality"]), fname("mortality", c)),
        "mortality (obs)": os.path.join(d(DEFAULT_SUBDIRS["mortality_obs"]), fname("mortality_obs", c)),
        "wage growth (cpi)": os.path.join(d(DEFAULT_SUBDIRS["wage_growth"]), fname("wage_growth", c)),
        "lm assumptions": os.path.join(paths.input, fname("lm_assumptions", c)),
        "indexation assumptions": os.path.join(paths.input, fname("index_assumptions", c)),
    }


def check_inputs(params: Parameters, paths: Paths) -> list[tuple[str, str, bool]]:
    rows = []
    for label, path in required_inputs(params, paths).items():
        rows.append((label, path, os.path.exists(path)))
    return rows


def run_pipeline(params: Parameters, paths: Paths, data_env: str, stage: str = "all") -> None:
    if data_env not in DATA_ENVIRONMENTS:
        raise ValueError(f"unknown data env {data_env!r}; choose {DATA_ENVIRONMENTS}")
    print(f"\n=== data environment: {data_env}  |  stage: {stage} ===")

    if stage in ("all", "preprocess"):
        for name, fn in PREPROCESS_STEPS:
            try:
                fn(params, paths, data_env)
                print(f"  [ok]      {name}")
            except NotImplementedError as e:
                print(f"  [pending] {name}: {e}")
            except FileNotFoundError as e:
                print(f"  [missing] {name}: {e}")

    if stage in ("all", "project"):
        try:
            projection.run(params, paths, data_env)
            print("  [ok]      projection -> Output/")
        except NotImplementedError as e:
            print(f"  [pending] projection: {e}")
        except FileNotFoundError as e:
            print(f"  [missing] projection: {e}")
