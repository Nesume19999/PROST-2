# PROST v2 — Python toolkit

A Python (CLI) reimplementation of Duncan MacDonald's **PROST v2** pension
microsimulation, able to run the four **data environments**
(`full`, `very_low`, `low`, `extremely_low`) and write outputs in the **same
CSV format** as the original Stata code.

> **Status: staged build.** The architecture, the I/O layer, and preprocessing
> steps **01–02** are implemented. Steps **03–06** and the **projection**
> carry an exact input/output contract and are ported + validated against the
> real Stata outputs once the input data is uploaded to the repo (Git LFS).
>
> **Fidelity caveat:** the projection is a *stochastic* microsimulation
> (`set seed 2`, `runiform()` in Stata). A Python port reproduces the model
> *logic* and yields results that are **statistically close**, not bit-identical
> to Stata, because the random number generators differ.

---

## Install

```bash
cd toolkit
python -m pip install -r requirements.txt
```

## Run

```bash
# Validate which input files are present (no data needed to see the plan):
python run.py --root .. --data-env full --check

# Run the whole pipeline for one data environment:
python run.py --root .. --data-env full --stage all

# Run all four environments and write side-by-side outputs:
python run.py --root .. --data-env all --stage all
```

CLI options:

| flag | meaning |
|---|---|
| `--root PATH` | repo root (the folder that contains `Input/` and `Output/`) |
| `--data-env`  | `full` \| `very_low` \| `low` \| `extremely_low` \| `all` |
| `--stage`     | `all` \| `preprocess` \| `project` |
| `--simname`   | scenario name written into output filenames (default `Baseline`) |
| `--check`     | only report input-file presence and the planned steps |

## What maps to what (Stata → Python)

| Stata `.do` | Python module |
|---|---|
| `01 - ... baseyear dataset` | `prost2/preprocessing/step01_baseyear.py` ✅ |
| `02 - ... beneficiary database` | `prost2/preprocessing/step02_beneficiaries.py` ✅ |
| `03 - ... affiliation rates` (+3 env variants) | `prost2/preprocessing/step03_affiliation.py` ⏳ |
| `04 - ... transitions rates` (+3 env variants) | `prost2/preprocessing/step04_transitions.py` ⏳ |
| `05 - ... life cycle wage growth` | `prost2/preprocessing/step05_lifecycle_wages.py` ⏳ |
| `06 - ... retirement/disability/survivor rates` | `prost2/preprocessing/step06_rates.py` ⏳ |
| `1 - PROSTv2 - Build projection database` | `prost2/projection.py` ⏳ |

The four **data environments** differ only in steps **03** and **04** (how
affiliation and transition rates are estimated when less longitudinal data is
available). Everything else is shared.

## Outputs (written to `Output/`)

Same names/format as the Stata build, e.g. (Baseline, 2025–2104):
`1_PROSTv2-Baseline-Affiliates-2025-2104.csv`,
`1_PROSTv2-Baseline-Pensioners-2025-2104.csv`,
`1_PROSTv2-Baseline-Inyear-*-Reporting-*.csv`.
