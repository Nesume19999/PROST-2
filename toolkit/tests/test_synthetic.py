"""Tests for the synthetic microdata generator."""
import numpy as np

from prost2 import synthetic


EXPECTED_COLUMNS = ["id", "year", "month", "yob", "gender",
                    "wage", "dens", "los", "aux"]


def test_schema_matches_real_microdata(small_panel):
    assert list(small_panel.columns) == EXPECTED_COLUMNS


def test_value_ranges_are_plausible(small_panel):
    df = small_panel
    assert set(df["gender"].unique()) <= {1, 2}
    assert set(df["dens"].unique()) <= {0, 1}
    assert df["month"].between(1, 12).all()
    age = df["year"] - df["yob"]
    assert age.between(synthetic.MIN_WORK_AGE, synthetic.MAX_WORK_AGE).all()


def test_wages_zero_iff_not_employed(small_panel):
    df = small_panel
    assert (df.loc[df["dens"] == 0, "wage"] == 0).all()
    assert (df.loc[df["dens"] == 1, "wage"] > 0).all()


def test_density_near_stationary_target(small_panel):
    # ~0.77 by construction; allow a modest band for sampling noise.
    assert abs(small_panel["dens"].mean() - synthetic.STATIONARY_DENSITY) < 0.05


def test_los_and_aux_are_monotone_cumulatives(small_panel):
    df = small_panel.sort_values(["id", "year", "month"])
    g = df.groupby("id")
    # aux = running month count, los = cumulative employed months
    assert (g["aux"].diff().dropna() == 1).all()
    assert (g["los"].diff().dropna() >= 0).all()
    # los never exceeds aux
    assert (df["los"] <= df["aux"]).all()


def test_deterministic_given_seed():
    cfg = synthetic.SyntheticConfig(n_workers=200, start_year=2018,
                                    end_year=2024, seed=7)
    a = synthetic.generate(cfg)
    b = synthetic.generate(cfg)
    assert a.equals(b)
