# Cómo correr el modelo PROST v2 (Stata)

Guía para regenerar los archivos de `Output/` con el modelo de Duncan MacDonald.

> **Importante:** el modelo solo corre en una máquina con **Stata** y con los
> datos en disco. La microdata cruda del cliente (~2 GB) **no está en el repo**
> (excluida por tamaño); debe existir localmente en `Input/`.

---

## 1. Requisitos

- **Stata** (MP recomendado por velocidad).
- Paquetes: `gtools` y `ftools`
  ```stata
  ssc install gtools
  ssc install ftools
  ```

## 2. Estructura de carpetas esperada

Todo cuelga de un único `global root` (ya configurado a tu carpeta
`C:/Users/WB542352/OneDrive - WBG/Documents/GitHub/PROST-2`):

```
${root}/
├── Input/
│   ├── 2 Input from client - longitudinal microdata about affiliates.dta   (~2 GB, crudo)
│   ├── 3 Input from client - microdata about beneficiaries.dta             (crudo)
│   ├── baseyear_data_MEX.dta          (lo regenera el paso 01)
│   ├── pensioners_MEX.dta             (lo regenera el paso 02)
│   ├── labor_market_assumptions.csv   (supuesto)
│   ├── indexation_assumptions_MEX.csv (supuesto)
│   └── Defaults/
│       ├── affiliation/      affiliation_MEX_10.csv        (lo regenera el paso 03)
│       ├── population/        population_MEX.csv
│       ├── population_obs/    population_historical_MEX.dta
│       ├── mortality/         mortality_MEX.csv
│       ├── mortality_obs/     mortality_obs_MEX.csv
│       ├── wage_growth/       cpi_MEX.csv
│       ├── transitions/       job_entry_model_MEX_10_final, job_exit_model_MEX_10_final  (paso 04)
│       ├── lifecycle wages/   lifecycle_wages_MEX                                          (paso 05)
│       ├── retirement/        retirement_rates_MEX.csv      (paso 06)
│       ├── disability/        disability_rates_MEX.csv      (paso 06)
│       └── survivor/          survivor_rates_MEX.csv        (paso 06)
└── Output/                    <- resultados de la proyección
```

Todos los `.do` ya apuntan a estas subcarpetas mediante macros
(`popdir`, `mortdir`, `affdir`, `transdir`, `lifecycledir`, ...).

## 3. Correr todo de una vez (recomendado)

```stata
do "RUN ALL - PROSTv2 pipeline.do"
```

Esto ejecuta en orden:

1. **Pre-procesamiento** — `0 - Run preprocessing steps.do` (pasos 01→06).
   Lee la microdata cruda de `Input/`, escribe intermedios en
   `Input/` y `Input/Defaults/<subcarpeta>/`.
2. **Proyección** — `1 - PROSTv2 - Build projection database.do`.
   Lee `Input/` (+ `Defaults/`) y escribe los resultados en **`Output/`**.

## 4. Correr por etapas (manual)

```stata
do "0 - Run preprocessing steps.do"               // Etapa 1: intermedios -> Input/(+Defaults)
do "1 - PROSTv2 - Build projection database.do"   // Etapa 2: resultados -> Output/
```

> Si tus archivos de `Defaults/` ya están al día, puedes saltarte la Etapa 1 y
> correr solo la Etapa 2. Pero el build espera los **nombres** que producen los
> pasos de preprocesamiento (p. ej. `lifecycle_wages_MEX`), así que ante la duda
> corre el preprocesamiento completo.

## 5. Salidas (carpeta `Output/`)

Las genera **únicamente** `1 - PROSTv2 - Build projection database.do`
(`local outdir = "${root}/Output"`), con `simname="Baseline"`, `baseyear=2024`,
`horizon=80` → años 2025–2104:

- `1_PROSTv2-Baseline-Affiliates-2025-2104.csv`
- `1_PROSTv2-Baseline-Pensioners-2025-2104.csv`
- `1_PROSTv2-Baseline-Inyear-Affiliate-Reporting-Totals.csv`
- `1_PROSTv2-Baseline-Inyear-Affiliate-Reporting-Breakdowns.csv`
- `1_PROSTv2-Baseline-Inyear-Pensioner-Reporting-Totals.csv`
- `1_PROSTv2-Baseline-Inyear-Pensioner-Reporting-Breakdowns.csv`

### Escenario **Reform**
Cambia `local simname = "Reform"` (línea ~56 del build) y los supuestos
correspondientes; vuelve a correr el build.

## 6. Reporte (gráficas y tablas) — opcional

Ver carpeta `Reporting/`: `run_report.py` (Python) o `R1 - Run report toolkit.do`.
Consume los CSV `Inyear-*-Reporting-*` de `Output/`.

## 7. "Data environments" (calidad de datos)

Los pasos **03** y **04** tienen variantes según cuántos datos longitudinales
tengas:

| Variante | Cuándo usarla |
|---|---|
| `03/04 ... .do` (normal) | datos completos (lo que corre el runner) |
| `... VERY LOW DATA.do`   | datos limitados |
| `... LOW DATA.do`        | datos muy limitados |
| `... EXTREMELY LOW DATA.do` | datos mínimos |

`0 - Run preprocessing steps.do` corre las variantes **normales**. Para un
entorno de pocos datos, sustituye la llamada al paso 03/04 por la variante
correspondiente.

## 8. Mover el repo a otra máquina

Cada `.do` define su propio `global root` (porque `clear all` borra los globals).
Si cambias de ruta/PC, actualiza la línea `global root "..."` en **todos** los
`.do` (busca y reemplaza). Hoy ya apunta a tu carpeta WB542352.

---

### Notas / cambios aplicados
- `global rawdir` corregido de `${root}/MEX` → **`${root}/Input`** (ahí está la
  microdata cruda del cliente).
- Añadido `RUN ALL - PROSTv2 pipeline.do` (runner de las etapas 1–2).
- Las subcarpetas `Input/Defaults/<tipo>/` ya estaban cableadas en el código.
