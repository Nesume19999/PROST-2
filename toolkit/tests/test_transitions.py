"""Tests for Step 04 (T1/T2 transition models) against the known baseline.

Because the synthetic generator uses *known* monthly transition hazards
(exit = 0.03, entry = 0.10), the realised and model-predicted hazards must
recover those values -- this is the "compare to expected baseline" check.
"""
import numpy as np
import pytest

from prost2 import synthetic, transitions


@pytest.fixture(scope="module")
def frame(small_panel):
    return transitions.prepare(small_panel)


def test_prepare_builds_expected_columns(frame):
    for col in ["spell_length", "wage_decile_ref", "los_gap", "log_cod",
                "transition_out", "transition_in", "age"]:
        assert col in frame.columns


def test_transition_indicators_are_binary(frame):
    out = frame["transition_out"].dropna().unique()
    inn = frame["transition_in"].dropna().unique()
    assert set(np.unique(out)) <= {0.0, 1.0}
    assert set(np.unique(inn)) <= {0.0, 1.0}
    # exit defined only for employed, entry only for unemployed months
    assert (frame.loc[frame["transition_out"].notna(), "dens"] == 1).all()
    assert (frame.loc[frame["transition_in"].notna(), "dens"] == 0).all()


def test_empirical_rates_match_known_baseline(frame):
    rates = transitions.empirical_rates(frame)
    assert rates.exit_rate == pytest.approx(synthetic.TRUE_EXIT_HAZARD, abs=0.01)
    assert rates.entry_rate == pytest.approx(synthetic.TRUE_ENTRY_HAZARD, abs=0.02)


def test_exit_model_fits_and_recovers_baseline(frame):
    model = transitions.fit_exit(frame)
    assert model.converged
    employed = frame[(frame["dens"] == 1) & frame["wage_decile_ref"].notna()]
    pred = transitions.predict_hazard(model, employed)
    assert np.all((pred >= 0) & (pred <= 1))
    # mean predicted hazard tracks the true exit hazard
    assert pred.mean() == pytest.approx(synthetic.TRUE_EXIT_HAZARD, abs=0.01)


def test_entry_model_fits_and_recovers_baseline(frame):
    model = transitions.fit_entry(frame)
    assert model.converged
    unemployed = frame[(frame["dens"] == 0) & frame["wage_decile_ref"].notna()]
    pred = transitions.predict_hazard(model, unemployed)
    assert np.all((pred >= 0) & (pred <= 1))
    assert pred.mean() == pytest.approx(synthetic.TRUE_ENTRY_HAZARD, abs=0.02)
