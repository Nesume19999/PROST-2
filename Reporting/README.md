# PROST v2 Reporting Toolkit

A reporting layer that sits **downstream** of the PROST v2 pension model. It
reads the in-year reporting CSVs produced by
`1 - PROSTv2 - Build projection database.do` and turns them into:

- **Charts** (PNG) — contributors vs beneficiaries, dependency ratio,
  beneficiaries by pension type, wage vs pension, replacement ratio & coverage,
  an illustrative financial balance, a beneficiary age pyramid, and contribution
  density by wage decile.
- **Summary tables** (Excel) — a multi-sheet workbook of key indicators.
- **A report document** (Word) — narrative + tables + embedded charts.
- **Scenario comparison** — side-by-side charts, an Excel comparison, and a
  short comparison report for two simulations (e.g. *Baseline* vs *Reform*).

The toolkit **does not modify the model**. It only consumes the CSVs the model
already writes, so it slots in with no changes to your `.do` build scripts.

It ships in **two equivalent implementations** — use whichever fits your
workflow:

| | Language | Run with | Status |
|---|---|---|---|
| **Python** | `prost_report/` package | `python3 run_report.py` | **Verified end-to-end** on the bundled sample data |
| **Stata**  | `R1`–`R6` `.do` files | `do "R1 - Run report toolkit.do"` | Mirrors the Python logic; run in your Stata |

> The Python version was built and executed in an environment without Stata, so
> it could be verified directly. The Stata version is the in-ecosystem sibling
> and produces equivalent outputs from the same inputs. The numbers the Python
> version prints (e.g. in the Excel `Overview`/`Finances` sheets) serve as a
> reference you can diff against your Stata run.

---

## Inputs

For each simulation `<sim>`, the toolkit expects these four files (exactly as
the model exports them) in one folder:

```
1_PROSTv2-<sim>-Inyear-Pensioner-Reporting-Totals.csv
1_PROSTv2-<sim>-Inyear-Pensioner-Reporting-Breakdowns.csv
1_PROSTv2-<sim>-Inyear-Affiliate-Reporting-Totals.csv
1_PROSTv2-<sim>-Inyear-Affiliate-Reporting-Breakdowns.csv
```

Categorical columns (`gender`, `dens`, `wage_decile`, `age_grp`,
`pension_type`, `pension_class`) are handled exactly as Stata's
`export delimited` writes them — i.e. value-label text such as `Male`,
`Active`, and the `Total` placeholders (`99`/`999`). Both toolkits coerce these
to a common form before filtering.

---

## Quick start (Python)

```bash
cd Reporting
pip install -r requirements.txt          # one time

# Demo against the bundled synthetic data (no arguments needed):
python3 run_report.py

# Against your real model outputs:
python3 run_report.py \
    --outdir "/path/to/model/Output" \
    --reportdir "/path/to/Reports" \
    --sim Baseline --sim Reform --compare \
    --contrib-rate 10 --periods 12 --currency MXN --country MEX
```

Outputs land in `--reportdir` (default `./report_output`):

```
report_output/
  figures/<sim>/01..08_*.png
  figures/comparison/C1..C3_*.png
  tables/<sim>_PROST_tables.xlsx
  tables/Comparison_<a>_vs_<b>.xlsx
  <sim>_PROST_report.docx
  Comparison_<a>_vs_<b>_report.docx
```

Run `python3 run_report.py --help` for all options.

---

## Quick start (Stata)

1. Open `R1 - Run report toolkit.do` and edit the **USER SETTINGS** block:
   - `codedir`   — folder containing the `R*.do` files (this folder)
   - `outdir`    — folder with the PROST output CSVs (or `sample_output` for a demo)
   - `reportdir` — where reports are written
   - `sims`      — simulation names, e.g. `"Baseline Reform"`
   - financing assumptions: `contrib_rate`, `periods`, `currency`, `country`
2. Run it:
   ```stata
   do "R1 - Run report toolkit.do"
   ```

Requires **Stata 15+** (uses `putdocx`). No SSC packages needed.

### Stata module map
| File | Role |
|---|---|
| `R1 - Run report toolkit.do` | Master driver; sets parameters, calls the rest |
| `R2 - Prepare indicators.do` | CSVs → tidy `_prep_<sim>_*.dta` indicator datasets |
| `R3 - Charts.do` | PNG charts |
| `R4 - Summary tables.do` | Excel workbook (`export excel`) |
| `R5 - Report document.do` | Word report (`putdocx`) |
| `R6 - Scenario comparison.do` | Two-simulation comparison |
| `Rlib - helpers.do` | Shared helper programs (CSV import, mkdir, PNG export) |

Parameters flow from `R1` to the modules via **global** macros (globals persist
across `do`; locals do not), so the modules can also be run individually once
`R1` has set the globals.

---

## The financing block is illustrative

Beneficiary, contributor, wage and pension figures come straight from the model
outputs. **Contributions, expenditure and the net balance are derived**, not
read from the model:

- `expenditure  = Σ_type (beneficiaries_type × average_pension_type) × periods`
- `contributions = contribution_rate × average_wage × contributors × periods`
- `balance = contributions − expenditure`

Treat this block as indicative (driven by the `contrib_rate` and `periods`
parameters), not as an actuarial balance.

---

## Synthetic test data

`sample_output/` contains ready-to-use **synthetic** CSVs for two simulations
(*Baseline*, *Reform*) so the toolkit can be demoed without a model run. The
numbers are illustrative and carry no economic meaning.

Regenerate them with:

```bash
python3 tools/make_sample_csvs.py            # writes into ../sample_output
```

The generator reproduces the model's export format (column order, value-label
text, `Total` placeholders) and is internally consistent — the per-type and
per-age breakdowns reconcile with the grand totals.

---

## Folder layout

```
Reporting/
  R1..R6 *.do            Stata toolkit (+ Rlib - helpers.do)
  prost_report/          Python package (prepare, charts, tables, report, compare, cli)
  run_report.py          Python convenience driver
  requirements.txt       Python dependencies
  tools/
    make_sample_csvs.py  Synthetic data generator
  sample_output/         Bundled synthetic input CSVs (Baseline, Reform)
  report_output/         Generated reports (created on run)
```
