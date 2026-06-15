---
title: "Modelo de microsimulación de pensiones PROST v2"
subtitle: "Documento de metodología técnica"
author: "Banco Mundial — Equipo PROST"
date: "Junio 2026"
lang: es
---

# Resumen

Este documento describe, con detalle técnico, la metodología implementada en el
conjunto de programas Stata (`.do`) que construyen el modelo de pensiones
**PROST v2** para México (código de país `MEX`). El modelo consta de dos
grandes bloques:

1. **Preprocesamiento** (pasos 01–06): a partir de la microdata longitudinal de
   afiliados del IMSS y de la microdata de beneficiarios, estima los insumos del
   modelo: dataset base del año inicial, base de pensionados, tasas de
   afiliación, modelos de transición laboral, perfiles de crecimiento salarial
   por ciclo de vida, y tasas de incidencia de retiro/invalidez/sobrevivencia.
2. **Proyección** (`1 - PROSTv2 - Build projection database.do`): una
   microsimulación estocástica, individuo por individuo, mes a mes, que proyecta
   afiliados y pensionados durante un horizonte de 80 años.

El preprocesamiento de las **tasas de afiliación** (paso 03) y de los **modelos
de transición** (paso 04) existe en cuatro variantes según la disponibilidad de
datos —*full*, *very low data*, *low data* y *extremely low data*—; el resto del
pipeline es común a las cuatro.

> **Nota sobre el alcance del código.** Algunos componentes están especificados
> pero aún no implementados en esta versión (invalidez y sobrevivencia,
> acumulación de cuentas de contribución definida, decisión de retiro por VPN).
> Se señalan explícitamente como *pendientes* en las secciones correspondientes.

---

# 1. Introducción y arquitectura

## 1.1 Propósito del modelo

PROST v2 es un modelo **actuarial de microsimulación** del sistema de pensiones.
A diferencia de un modelo de celdas agregadas, mantiene el estado de cada
individuo (afiliado o pensionado) y simula sus transiciones demográficas y
laborales de forma probabilística. Esto permite calcular, año a año, los flujos
de nuevos contribuyentes, salidas y reingresos al empleo formal, nuevas
pensiones otorgadas, montos de pensión, e indexación, con desagregación por
edad, género, decil salarial y tipo de pensión.

## 1.2 Flujo del pipeline

```
  Microdata cliente (IMSS)                     Insumos por defecto (Defaults/)
  ├─ longitudinal afiliados (.dta)             ├─ población (proyección + histórica)
  └─ beneficiarios (.dta)                      ├─ mortalidad (proyección + observada)
            │                                  ├─ crecimiento salarial (CPI)
            ▼                                  └─ supuestos (mercado laboral, indexación)
  PREPROCESAMIENTO
  01  baseyear_data_MEX.dta        (dataset base de afiliados, año inicial)
  02  pensioners_MEX.dta           (base de pensionados reclasificada)
  03  affiliation_MEX_10.csv       (tasas de afiliación por edad/género)   [4 variantes]
  04  job_exit / job_entry models  (hazards cloglog de salida/entrada)     [4 variantes]
  05  lifecycle_wages_MEX          (perfil de crecimiento salarial)
  06  retirement/disability/survivor_rates_MEX.csv  (tasas de incidencia)
            │
            ▼
  PROYECCIÓN  (1 - PROSTv2 - Build projection database.do)
  Inicialización → loop anual (2025–2104) × loop mensual (1–12)
  → Outputs: bases finales de afiliados y pensionados + reportes anuales
```

## 1.3 Los cuatro entornos de datos

El modelo está diseñado para funcionar incluso cuando la microdata
longitudinal es limitada. Las tasas de afiliación (paso 03) y los modelos de
transición (paso 04) tienen cuatro variantes:

| Entorno | Datos disponibles | Estrategia |
|---|---|---|
| **Full** | Panel longitudinal completo (varios años × meses por persona) | Se observan directamente las fechas de afiliación y las transiciones mes a mes. |
| **Very low data** | Corte transversal con antigüedad (`loa`), sin filtro mensual | Se reconstruye el año/edad de afiliación a partir de la antigüedad. |
| **Low data** | Corte transversal con antigüedad, solo diciembre | Igual que *very low* pero usando el corte de diciembre para reducir duplicación. |
| **Extremely low data** | Corte transversal con antigüedad + densidad de contribución (`dens`) | Se reconstruye afiliación y se aplica un factor de expansión estadístico (regresión ZOIB) para corregir el subconteo de no contribuyentes. |

## 1.4 Convenciones y codificación

| Variable | Códigos |
|---|---|
| `gender` | 1 = hombre, 2 = mujer |
| `status` (afiliados) | 1 = vivo/afiliado, 2 = retirado, 3 = inválido, 4 = viudo/sobreviviente, 99 = fallecido |
| `pension_class` | 1 = beneficio definido (DB), 2 = contribución definida (DC) |
| `pension_type` | 1 = vejez (old-age), 2 = invalidez, 3 = sobrevivencia |
| `pension_id` | 1 OA-DB, 2 Inv-DB, 3 Sob-DB, 4 OA-DC, 5 Inv-DC, 6 Sob-DC |
| `dens` | 1 = contribuye este mes, 0 = no contribuye (informal/desempleado) |
| `los` | *length of service*: meses acumulados con contribución |
| `loa` (`aux`) | *length of affiliation*: meses desde la primera afiliación |

---

# Parte I — Preprocesamiento

# 2. Pasos del preprocesamiento

## 2.1 Paso 01 — Dataset base del año inicial

**Programa:** `01 - Pre-processing - Generate baseyear dataset.do`
**Insumo:** `2 Input from client - longitudinal microdata about affiliates.dta`
**Producto:** `baseyear_data_MEX.dta`

**Propósito.** Construir, a partir del panel longitudinal, el conjunto de
afiliados del año más reciente con las variables de estado que requiere la
microsimulación.

**Método.**

1. Se determina el año más reciente: `latest_year = max(year)`.
2. Limpieza y edad: se renombra `aux` → `loa`; `age = year − yob`.
3. **Identificación de spells (episodios).** Ordenando por `id` y fecha
   `date = ym(year, month)`, se marca un nuevo episodio cuando cambia la densidad
   o la persona, y se calcula la longitud de cada episodio:
   ```stata
   generate byte new_spell = (dens != dens[_n-1] | id != id[_n-1])
   generate spell_id = sum(new_spell)
   bysort spell_id: generate spell_length = _N
   ```
4. **Índice de salario relativo.** Se construye el salario relativo a la media
   anual y se arrastra hacia adelante (*carryforward*) el último valor conocido:
   ```stata
   bysort year: egen mean_wage_yr = mean(wage)
   generate wage_relative_mean = wage / mean_wage_yr
   carryforward wage_relative_mean, replace
   ```
5. **Deciles salariales.** El decil de referencia se asigna con el salario
   relativo del último diciembre y se propaga como el decil "verdadero" de la
   persona; quien no contribuye (`dens==0`) recibe decil 0. Adicionalmente se
   calcula un decil dentro de cada celda (año, edad, género).
6. Conversión de salario diario a mensual: `wage = wage × 20` (20 días
   laborables).
7. Se conserva el año más reciente, se inicializa `status = 1` (todos vivos) y se
   guarda el dataset base.

## 2.2 Paso 02 — Base de pensionados

**Programa:** `02 - Pre-processing - Generate beneficiary database.do`
**Insumo:** `3 Input from client - microdata about beneficiaries.dta`
**Producto:** `pensioners_MEX.dta`

**Propósito.** Reclasificar la microdata de beneficiarios en clase, tipo e
identificador de pensión.

**Método.** Se descartan los registros con `type` vacío (para alinear los conteos
con los totales agregados). A partir de la letra `type` se construyen:

| `type` | `pension_class` | `pension_type` | `pension_id` |
|---|---|---|---|
| B | 1 (DB) | 1 (vejez) | 1 |
| C | 1 (DB) | 2 (invalidez) | 2 |
| D | 1 (DB) | 3 (sobrevivencia) | 3 |
| E | 2 (DC) | 1 (vejez) | 4 |
| F | 2 (DC) | 2 (invalidez) | 5 |
| G | 2 (DC) | 3 (sobrevivencia) | 6 |

Se renombra `monthlybenefit` → `pension_benefit`, se eliminan `iden` (no único) y
`type`, y se guarda la base.

## 2.3 Paso 03 — Tasas de afiliación

**Programa:** `03 - Pre-processing - Generate affiliation rates.do` (+ 3 variantes)
**Productos:** `affiliation_MEX_10.csv` (y sus equivalentes `_LOW_DATA`,
`_VERY_LOW_DATA`, `_EXTREMELY_LOW_DATA`)

**Propósito.** Estimar la tasa de **nuevos afiliados** por edad y género,
definida como:

```
affiliation_rate(edad, género) = nuevos_afiliados / (población × 1000)
```

(la población viene en miles, de ahí el factor 1000). Estas tasas se usan en la
proyección para generar las cohortes de nuevos entrantes cada año.

**Método (versión full).**

1. Se calcula la edad, se filtra `age >= 15` y se conservan los últimos 10 años
   (`year > latest_year − 10`).
2. **Filtro de nuevos afiliados:** `keep if los == 1 & aux == 1` (primer mes de
   servicio y de afiliación).
3. Conteo de nuevos afiliados por (año, edad, género) con `collapse (count)`.
4. Se descarta el año más antiguo (la afiliación estaría sobreestimada al inicio
   del registro).
5. Se cruza con la población histórica (`population_historical_MEX.dta`), se
   agregan numerador y denominador por (edad, género) y se calcula la tasa.

**Diferencias entre entornos de datos.**

| Aspecto | Full | Very low | Low | Extremely low |
|---|---|---|---|---|
| Insumo | Panel longitudinal | `verylowdata_MEX.dta` | `lowdata_MEX.dta` | `extremelylowdata_MEX.dta` |
| Año/edad de afiliación | Observado | Reconstruido `year − floor(loa/12)` | Reconstruido | Reconstruido |
| Identificación de nuevo afiliado | `los==1 & aux==1` | Imputado por antigüedad | Imputado | Imputado |
| Filtro temporal | Se descarta el año más antiguo | Todos los meses | Solo `month==12` | Todos los meses |
| Ajuste por no contribuyentes | — | — | — | **Factor de expansión ZOIB** |
| Conteo | `count` de `id` | `count` de `id` | `count` de `id` | `sum` del `expansion_factor` |
| Salida | `affiliation_MEX_10.csv` | `..._VERY_LOW_DATA.csv` | `..._LOW_DATA.csv` | `..._EXTREMELY_LOW_DATA.csv` |

**Detalle del factor de expansión (extremely low data).** Como solo se observa
la densidad de contribución del año (`dens`, meses contribuidos), se modela la
proporción contribuida `dens_share = dens/12` con una **regresión Beta inflada en
cero y uno (ZOIB)**:

```stata
zoib dens_share i.gender, oneinflate(age i.gender)
```

De las predicciones se derivan los parámetros Beta (`alpha`, `beta`), la
probabilidad implícita de cero contribuciones y un factor de expansión
`expansion_factor = 1/(1 − implied_p_zero)` que infla el conteo de afiliados para
compensar el subregistro de quienes no contribuyen todos los meses.

**Parámetros.** `years_avg = 10` (ventana de años), `minimum_age = 15`.

## 2.4 Paso 04 — Modelos de transición laboral (T1 / T2)

**Programa:** `04 - Pre-processing - Estimate transitions rates.do` (+ 3 variantes)
**Productos:** estimaciones `job_exit_model_MEX_10_final` y
`job_entry_model_MEX_10_final`

**Propósito.** Estimar la probabilidad mensual de **salir** del empleo formal
(T1) y de **entrar/reingresar** al empleo formal (T2), como funciones de las
características del individuo. Estos *hazards* se aplican mes a mes en la
proyección.

**Construcción de variables.** Sobre el panel (muestreado al `samplesize`%):
duración del episodio actual (`spell_length`), densidad de contribución
`contribution_density = los/loa` y su logaritmo `log_cod = log(max(cod, 0.001))`,
brechas a la elegibilidad (`age_gap`, `los_gap`, `pension_gap`), salario relativo
y decil de referencia. Se conservan los últimos `years_avg = 10` años y
`age >= 15`. La transición se define con el estado del mes siguiente:

```stata
generate current_state = (wage_decile > 0)        // contribuye ahora
generate next_state    = (f.wage_decile > 0)      // contribuye el mes siguiente
generate transition_in  = (current_state==0 & next_state==1) if current_state==0
generate transition_out = (current_state==1 & next_state==0) if current_state==1
```

**Modelos (complementary log-log / cloglog).**

- **T1 — salida del empleo** (sobre meses con `dens==1`):
  ```stata
  cloglog transition_out  c.spell_length##i.wage_decile_ref  c.age##c.age  ///
                          i.gender  c.los_gap                    , cluster(id)
  ```
- **T2 — entrada al empleo** (sobre meses con `dens==0`, añade `log_cod`):
  ```stata
  cloglog transition_in   c.spell_length##i.wage_decile_ref  c.age##c.age  ///
                          i.gender  c.log_cod  c.los_gap        , cluster(id)
  ```

donde `c.x` indica covariable continua, `i.x` categórica, `##` interacción
completa (incluye efectos principales) y `c.age##c.age` produce el término
cuadrático en edad. Los errores estándar se agrupan por `id` (no altera los
coeficientes puntuales ni los *hazards* predichos). El *hazard* mensual se
recupera como `p = 1 − exp(−exp(xb))`.

**Diferencias entre entornos.** Las variantes *very/low/extremely low data*
estiman los mismos modelos con conjuntos de covariables progresivamente más
reducidos, según la información disponible en cada corte de datos.

## 2.5 Paso 05 — Perfiles de crecimiento salarial por ciclo de vida

**Programa:** `05 - Pre-processing - Generate life cycle wage growth profiles.do`
**Producto:** estimaciones `lifecycle_wages_MEX`

**Propósito.** Estimar el crecimiento salarial **relativo al crecimiento
agregado** por género, edad y decil, para proyectar trayectorias salariales
individuales heterogéneas.

**Método.**

1. Salario relativo a la media anual y deciles de referencia (como en el paso 04).
2. Se descartan trabajadores cerca del retiro con contribución suficiente
   (`drop if los_gap==0 & age >= early_retage`, con `early_retage = 60`) para
   evitar sesgo de selección.
3. Se colapsa a nivel cohorte (`yob`, género, decil, año) y se calculan:
   - crecimiento de la cohorte: `wage_growth_cohort = 100·(wage − L.wage)/L.wage`
   - crecimiento global: `wage_growth_global = 100·(mean_wage_yr − L.mean_wage_yr)/L.mean_wage_yr`
   - **crecimiento relativo:** `wage_growth_relative = 100·wage_growth_cohort/wage_growth_global`
4. Se filtran *outliers* fuera de media ± 3 desviaciones estándar
   (`reg_include_flag`).
5. **Regresión** con interacción completa de tres vías:
   ```stata
   regress wage_growth_relative  i.wage_decile#i.gender#i.age  if reg_include_flag
   ```
   Las estimaciones se guardan y se usan para predecir el crecimiento relativo por
   celda (decil, género, edad).

**Parámetros.** `minimum_age = 15`, `early_retage = 60`,
`retcont_min = (750/52)·12 ≈ 173.08` meses, recorte de *outliers* a 3 SD.

## 2.6 Paso 06 — Tasas de retiro, invalidez y sobrevivencia

**Programa:** `06 - Pre-processing - Generate retirement disability survivor rates.do`
**Productos:** `retirement_rates_MEX.csv`, `disability_rates_MEX.csv`,
`survivor_rates_MEX.csv`

**Propósito.** Derivar tasas de incidencia (por edad y género) de nuevas
pensiones de vejez, invalidez y sobrevivencia, ajustadas por mortalidad de
cohorte, a partir de la base de beneficiarios.

**Método.**

1. **Mortalidad y supervivencia de cohorte.** Se importa la mortalidad
   observada (`mortality_obs_MEX.csv`), se pasa a formato largo y se
   *retro-completa* hacia atrás (1850–1949) para cubrir cohortes longevas. Para
   cada cohorte (definida por `birth_year = year − age`) se acumula la
   supervivencia:
   ```stata
   generate log_surv_increment = log(1 - mortality_rate)
   bysort gender birth_year (age): generate cum_log_surv = sum(log_surv_increment)
   generate survival_rate = exp(cum_log_surv)        // S(a) = ∏ (1 − q(x))
   ```
2. **Conteo de pensiones nuevas** por (edad, género, año de inicio, tipo) y
   *reshape* a columnas `oa_pension`, `disa_pension`, `survivor_pension`.
3. **Edad al inicio** de la pensión: `age_start = max(age − (baseyear − year), 0)`.
4. **Ajuste por mortalidad de cohorte.** Para recuperar el tamaño original de la
   cohorte que entró a pensión, se divide por la razón de supervivencia entre el
   año base y el año de inicio:
   ```stata
   generate oa_pension_adj = oa_pension / (survival_rate_now / survival_rate_start)
   ```
   (análogo para invalidez y sobrevivencia).
5. **Normalización a tasas** dividiendo por la población de referencia
   (`pop × 1000`), filtrado a los últimos `include_years = 20` años, y promedio por
   (edad, género). Se exportan los tres CSV.

**Parámetros.** `include_years = 20`; edad tope a 100; retro-completado de
mortalidad 1850–1949; codificación de género 1/2 y de tipo 1/2/3.

---

# Parte II — Proyección (microsimulación)

# 3. Construcción de la base de proyección

**Programa:** `1 - PROSTv2 - Build projection database.do` (~2 807 líneas)

## 3.1 Parámetros de la simulación

| Parámetro | Valor | Significado |
|---|---|---|
| `baseyear` | 2024 | Año base de la microdata |
| `startyear` | 2025 | Primer año proyectado (`baseyear + 1`) |
| `endyear` | 2104 | Último año proyectado |
| `horizon` | 80 | Años de proyección |
| `samplesize` | 10 | Tamaño de muestra (% de la población; peso = 100/samplesize) |
| `seed` | 2 | Semilla del generador aleatorio (reproducibilidad) |
| `working_age_min/max` | 15 / 64 | Edades activas |
| `max_eligibility_age` | 75 | Edad tope sin esperanza razonable de elegibilidad |
| `wage_adjustment` | 9878.469/7048.628 ≈ 1.402 | Ajuste salarial 2020→2024 (ILO) |
| `country` / `simname` | MEX / "Baseline" | País / escenario |

**Parámetros de política (sistema de pensiones).** Edad de retiro 65 (ambos
sexos); requisito mínimo de servicio `p_min_service_req = 750/52 ≈ 14.42` años;
tasa de acumulación `p_accrual = 4%` por año de servicio con tope
`p_accrual_max = 75%`; penalización por retiro anticipado `p_delta = 4%`/año y
bono por retiro tardío `p_lambda = 4%`/año; retiro forzoso a los 99 años;
pensión mínima base `p_minpen_base = 2 622` (con ajustes por edad, antigüedad y
salario); descuento `p_discount_rate = 3%` (para la decisión de retiro por VPN,
pendiente). El cálculo del salario de referencia admite tres modos
(`ref_wage_type`): promedio móvil, mejores N años, o mejores N dentro de los
últimos M.

## 3.2 Insumos

Se cargan: población por edad/género/año (`population_MEX.csv`), mortalidad
(`mortality_MEX.csv`), tasas de afiliación (`affiliation_MEX_10.csv`), los
modelos de transición del paso 04, el modelo de salarios del paso 05, el
crecimiento salarial agregado (`cpi_MEX.csv`), los supuestos de mercado laboral
(`labor_market_assumptions.csv`) e indexación
(`indexation_assumptions_MEX.csv`), y las bases base de afiliados
(`baseyear_data_MEX.dta`) y pensionados (`pensioners_MEX.dta`). Las series con
horizonte menor al de proyección se mantienen constantes en su último año
disponible.

## 3.3 Inicialización

**Afiliados.** Se deduplica por `id`, se muestrea al `samplesize`% y se asigna
peso `wgt = 100/samplesize`. Cada individuo lleva: `status`, `age`, `gender`,
`yob`, `wage_decile` (y `wage_decile_ref`), `birthmonth`/`deathmonth` aleatorios,
`los`, `loa`, `dens`, `contribution_density`, `wage`, `wage_ref` (salario al
salir, para reingresar), `spell_length`, y las brechas de elegibilidad
(`age_gap`, `los_gap`, `pension_gap`) con un grupo de elegibilidad: 1 =
restringido por edad, 2 = restringido por servicio, 3 = sin esperanza razonable.
El salario base se lleva al año base con `wage_adjustment`.

**Cohortes de nuevos afiliados (anuales).** Para cada año se calculan
`new_affiliates = round(affiliation_rate × pop, 1)` a partir de población y tasas
de afiliación; se expanden, se les asigna decil aleatorio `runiformint(1,10)`, se
muestrean y se guardan como tempfiles `affiliates2025 … affiliates2104`.

**Pensionados.** Se muestrea la base de pensionados, se asigna `status = 2`,
`pensioner_source = "observed"`, y variables de seguimiento (`died_flag`,
`age_died`, `pension_index`).

## 3.4 El loop de simulación de afiliados

La simulación recorre un **loop anual** (`yr = 2025…2104`) con un **loop mensual
anidado** (`month = 1…12`).

### 3.4.1 Preparación anual

1. **Se agregan las nuevas cohortes** del año y se inicializan (`status=1`,
   `los=0`, `loa=0`, `dens=1`, mes de inicio).
2. **Expansión a meses** del año.
3. **Indicadores de elegibilidad** (invariantes en el año): brecha de edad
   `age_gap = max(retage − age,0)·12`, brecha de servicio
   `los_gap = max(12·p_min_service_req − los, 0)`, `pension_gap = max(age_gap,
   los_gap)`, edad implícita de retiro y grupo de elegibilidad (1/2/3).
4. **Mortalidad:** se cruzan las tasas y se genera el sorteo
   `randnum_mortality = runiform()`.
5. **Tasas de transición laboral:** se predicen los *hazards* cloglog
   (`p = 1 − exp(−exp(xb))`) para salida y entrada.
6. **Ajuste a metas de mercado laboral:** los *hazards* se reescalan por factores
   `outflow_adjustment` e `inflow_adjustment` para que la tasa de empleo y la
   rotación agregadas igualen los supuestos del año
   (`emp_rate_growth`, `turnover_target`).

### 3.4.2 Operaciones mensuales

Para cada mes:

1. **Envejecimiento:** `age = age + 1` en el mes de cumpleaños.
2. **Mortalidad:** `status = 99` si `mortality > randnum_mortality` en el mes de
   defunción; se anula el salario y `dens`.
3. **Transiciones laborales (estocásticas):**
   ```stata
   replace exiter    = (runiform() < transition_out & wage_decile > 0)
   replace reentrant = (runiform() < transition_in  & wage_decile == 0)
   ```
   Los que salen guardan `wage_ref`, pasan a `dens=0` y `wage_decile=0`; los que
   reingresan recuperan su decil de referencia. El `spell_length` se reinicia a 1
   en cualquier transición.
4. **Actualización de métricas:** `dens = (wage_decile>0)`; `los` se incrementa
   solo si contribuye; `loa` siempre; se recalcula `contribution_density`,
   `log_cod`, `los_gap` y `pension_gap`.
5. **Asignación de salario** a nuevos entrantes y reingresantes: se extrae de la
   distribución del decil, truncada a sus límites
   `wage = max(min(rnormal(μ, σ), max), min)`; los reingresantes con `wage_ref`
   recuperan su salario previo.

### 3.4.3 Dinámica salarial anual

Tras el loop mensual: se predice el crecimiento **relativo** por celda
(decil/género/edad) con el modelo del paso 05, se aplica junto con el crecimiento
agregado del año, y luego se hace un **ajuste macro** para que el crecimiento
salarial promedio simulado iguale exactamente el supuesto del usuario:

```stata
local wage_adjustment_factor = (1 + wage_growth_user) / (1 + wage_growth_obs)
replace wage = wage × wage_adjustment_factor
```

### 3.4.4 Elegibilidad y cálculo de la pensión

1. **Revalorización del salario de referencia** según `ref_wage_type`, con tasa:
   ```
   p_revalorization_rate = (c_infl·pindex_inflation + c_rw·pindex_realwage
                            + c_anchor·pindex_anchor) / 100
   ```
2. **Salario de referencia:** salario cubierto acotado a `[p_min_income,
   p_max_income]`, agregado por persona; el salario de referencia se actualiza
   como promedio móvil o como promedio de los mejores N años, según el modo.
3. **Elegibilidad** (conjunción de condiciones):
   ```stata
   pension_elig_mincont = ((los/12) >= p_min_service_req)
   pension_elig_delta   = (age >= retage − 1/p_delta)
   pension_elig_early   = (age >= p_retage_early)
   pension_elig = pension_elig_mincont & pension_elig_delta & pension_elig_early
   ```
4. **Tasa de reemplazo** y **beneficio base:**
   ```
   replacement_rate = yos·p_accrual − years_early·p_delta + years_late·p_lambda
   replacement_rate = max(min(replacement_rate, p_accrual_max), 0)
   pension_benefit_base = reference_wage · replacement_rate · pension_elig
   ```
5. **Pensión mínima y máxima.** La mínima parte de `p_minpen_base` y se ajusta por
   edad, años de servicio y salario (con coeficientes por nivel/porcentaje y
   escalones). El beneficio final se acota:
   ```
   pension_benefit = max(min(pension_benefit_base, pension_maxpen), pension_minpen) · pension_elig
   ```
6. **Indexación de parámetros** (mínima/máxima) con `mpi_index_rate`, de forma
   análoga a la revalorización.

### 3.4.5 Decisión de retiro y traspaso a pensionados

En la versión actual el retiro es **basado en reglas**: el individuo se retira
(`status = 2`) si es elegible y alcanzó la tasa de reemplazo máxima **o** la edad
de retiro forzoso (99). *(Existe, comentada, una decisión alternativa por VPN que
compara el valor presente de retirarse ahora vs. esperar un año, usando esperanza
de vida y `p_discount_rate`; está pendiente.)* Los afiliados que se retiran se
extraen como nuevos pensionados (`pensioners{yr}`), y al cierre del año se
descartan los retirados y fallecidos.

> **Pendientes (señalados en el código).** Invalidez y sobrevivencia (la
> estructura existe, esperando datos); acumulación de cuentas DC y pago de suma
> alzada (`p_lumpsum_flag = 0`); decisión de retiro por VPN; ajuste de `iacc` en
> el escalamiento del salario base.

## 3.5 El loop de pensionados

Inicializando con los pensionados base (`status = 2`), cada año se: (1) agregan
los nuevos retirados del año; (2) aplica mortalidad estocástica
(`died_flag = 1` si `mortality > runiform()`); (3) **indexan** los beneficios:
```
pension_index = (alpha1·pindex_inflation + alpha2·pindex_realwage
                 + alpha3·pindex_anchor) / 100
pension_benefit = pension_benefit · (1 + pension_index)
```
(con `alpha1=alpha2=alpha3=1` y, por defecto, `pindex_inflation = 3.5%`); (4)
generan los conteos ponderados por estado; y (5) envejece la población un año.

## 3.6 Outputs y reporting

Las salidas se escriben en `Output/` con la convención de nombres
`1_PROSTv2-{simname}-…-{startyear}-{endyear}.csv`:

| Archivo | Contenido |
|---|---|
| `…-Affiliates-2025-2104.csv` | Base final de afiliados (un registro por individuo, última observación) |
| `…-Pensioners-2025-2104.csv` | Base final de pensionados |
| `…-Inyear-Affiliate-Reporting-Totals.csv` | Agregados anuales de afiliados (afiliados, contribuyentes, nuevos, salidas, reingresos, retirados/inválidos/viudos/fallecidos, edad/salario/densidad medios, tasas de empleo y rotación) |
| `…-Inyear-Affiliate-Reporting-Breakdowns.csv` | Lo anterior desagregado por género, decil y `dens` |
| `…-Inyear-Pensioner-Reporting-Totals.csv` | Agregados anuales de pensionados (conteos por estado, pensión media, índice) |
| `…-Inyear-Pensioner-Reporting-Breakdowns.csv` | Lo anterior por grupo de edad (quinquenal), género, clase y tipo |

**Escalamiento.** Los conteos muestrales se multiplican por el peso
`wgt = 100/samplesize` para estimar la población total.

---

# 4. Supuestos clave

## 4.1 Elementos estocásticos vs. determinísticos

| Proceso | Tipo | Método |
|---|---|---|
| Mortalidad | Estocástico | `status=99` si `tasa > runiform()` (mensual, en mes de defunción) |
| Transiciones de empleo (T1/T2) | Estocástico | Hazard cloglog `1−exp(−exp(xb))`, sorteo Bernoulli mensual |
| Salario de nuevos entrantes | Estocástico | `rnormal(μ,σ)` truncado a límites del decil |
| Decil y mes de nacimiento/defunción | Estocástico | `runiformint` |
| Crecimiento salarial (agregado y relativo) | Determinístico | Supuesto por año × perfil del modelo (paso 05) |
| Parámetros de pensión e indexación | Determinístico | Reglas de política / supuestos anuales |
| Invalidez y sobrevivencia | Estocástico | *(pendiente)* sorteo Bernoulli desde tasas del paso 06 |

## 4.2 Limitaciones conocidas

- Invalidez y sobrevivencia aún no implementadas (estructura lista).
- Acumulación de cuentas de contribución definida (DC) no modelada.
- La decisión de retiro es por reglas, no por VPN con esperanza de vida.
- Más allá de las transiciones estocásticas de empleo, no hay heterogeneidad
  adicional en el comportamiento contributivo.

---

# Anexo A — Correspondencia con la reimplementación en Python

El repositorio incluye un *toolkit* en Python (`toolkit/`) que reimplementa el
pipeline de forma modular y testeable, manteniendo la misma metodología:

| Componente Stata | Módulo Python |
|---|---|
| Paso 01 | `prost2/preprocessing/step01_baseyear.py` |
| Paso 02 | `prost2/preprocessing/step02_beneficiaries.py` |
| Paso 03 (+ variantes) | `prost2/preprocessing/step03_affiliation.py` |
| Paso 04 (T1/T2) | `prost2/transitions.py` (+ `features.py`) |
| Paso 05 | `prost2/preprocessing/step05_lifecycle_wages.py` |
| Paso 06 | `prost2/preprocessing/step06_rates.py` |
| Proyección | `prost2/projection.py` |

Dado que la microsimulación es **estocástica** (semilla y `runiform()` en Stata),
la versión en Python reproduce la *lógica* del modelo y entrega resultados
estadísticamente cercanos, no idénticos bit a bit, porque los generadores de
números aleatorios difieren entre plataformas.

*Documento generado a partir de la lectura directa de los programas `.do` del
repositorio PROST-2.*
