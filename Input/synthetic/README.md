# Synthetic affiliate microdata

**This is fully synthetic, non-sensitive data.** It is **not** IMSS client data.
It exists so the PROST v2 Python toolkit can be run and unit-tested without ever
touching the real (confidential) microdata.

## Files
- `synthetic_affiliates.parquet` — the panel (one row per person-month). Same
  schema as the real `2 Input from client - longitudinal microdata about
  affiliates.dta`: `id, year, month, yob, gender, wage, dens, los, aux`.
- `synthetic_metadata.json` — generation config (seed, assumptions) and summary.

## How it was generated
Reproducibly, from a fixed seed:
```bash
cd toolkit
python scripts/generate_synthetic_data.py --n-workers 5000    # committed sample
python scripts/generate_synthetic_data.py --n-workers 50000   # full realistic run
```
**Committed sample:** 5,000 workers, 2005–2024 monthly, seed 20260609
→ ~953k rows, mean density **0.771** (kept small so it lives in plain git, no
LFS needed). The full **50,000-worker** dataset (~9.5M rows, density 0.769) is
reproducible with the command above.

## Generating assumptions (see `prost2/synthetic.py`)
- **Demographics:** gender ~ Bernoulli(0.5); birth years spread so ages span
  18–65 across the window (realistic entries at 18, exits at 65).
- **Employment:** 2-state Markov chain with known monthly hazards
  **exit = 0.03** (employed→unemployed), **entry = 0.10** (unemployed→employed),
  giving a stationary density of ~0.77 and realistic spell lengths.
- **Wages:** daily wage = person log-normal fixed effect × mild age hump ×
  4%/yr nominal growth × log-normal noise; 0 while not employed.

These known hazards are the **baseline** the Step-04 tests validate against
(`toolkit/tests/test_transitions.py`): the realised and model-predicted exit/
entry hazards must recover 0.03 / 0.10.

> ⚠️ Distributions are *plausible*, not calibrated to Mexico. Use only for
> exercising/validating the pipeline mechanics — never for real analysis.
