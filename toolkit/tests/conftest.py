"""Shared pytest fixtures."""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from prost2 import synthetic  # noqa: E402


@pytest.fixture(scope="session")
def small_panel():
    """A small, fast, deterministic synthetic panel for unit tests.

    Large enough to estimate stable transition rates, small enough to be quick.
    """
    cfg = synthetic.SyntheticConfig(
        n_workers=3_000, start_year=2010, end_year=2024, seed=12345)
    return synthetic.generate(cfg)
