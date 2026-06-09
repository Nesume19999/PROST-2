/*******************************************************************************
Title: 			Reporting toolkit - prepare indicators
Author: 		PROST v2 reporting toolkit
Description:	Reads the four PROST v2 in-year reporting CSVs for one simulation
				and builds tidy indicator datasets used by the charts, tables,
				report and comparison modules.

Inputs (globals set by the master "R1 - Run report toolkit.do"):
	${outdir}         folder containing the PROST output CSVs
	${reportdir}      folder where prepared datasets are written
	${prep_sim}       the simulation name to prepare (e.g. "Baseline")
	${contrib_rate}   assumed contribution rate, in % of covered wage
	${periods}        pay periods per year used to annualise wage/pension amounts

Source CSVs (per simulation <sim>):
	1_PROSTv2-<sim>-Inyear-Pensioner-Reporting-Totals.csv
	1_PROSTv2-<sim>-Inyear-Pensioner-Reporting-Breakdowns.csv
	1_PROSTv2-<sim>-Inyear-Affiliate-Reporting-Totals.csv
	1_PROSTv2-<sim>-Inyear-Affiliate-Reporting-Breakdowns.csv

Outputs (per simulation <sim>):
	_prep_<sim>_system.dta    one row per year: headline system indicators
	_prep_<sim>_bytype.dta    one row per year x pension type: beneficiaries
	_prep_<sim>_byage.dta     one row per year x gender x age group: beneficiaries
	_prep_<sim>_bydecile.dta  one row per year x wage decile: affiliate indicators
*******************************************************************************/

	version 15
	quietly do "${codedir}/Rlib - helpers.do"

	local sim   "${prep_sim}"
	local S      = "/"
	local pfx    "${outdir}`S'1_PROSTv2-`sim'-Inyear"

	noisily display _newline as result "Preparing indicators for simulation: `sim'"


//	===========================================================================
//	1. PENSIONER TOTALS -> system-level beneficiary stocks & average pension
//	===========================================================================
	prost_import using "`pfx'-Pensioner-Reporting-Totals.csv"

	// The totals file holds the grand-total row per year; filter defensively.
	keep if gender=="Total" & age_grp=="Total" & pension_type=="Total" & pension_class=="Total"
	capture destring retired disabled widowed deceased avg_pension pension_index, replace force

	gen double total_beneficiaries = retired + disabled + widowed
	rename avg_pension avg_pension_all
	keep year retired disabled widowed deceased total_beneficiaries avg_pension_all pension_index
	tempfile pens_tot
	save `pens_tot'


//	===========================================================================
//	2. AFFILIATE TOTALS -> contributors, wages, population
//	===========================================================================
	prost_import using "`pfx'-Affiliate-Reporting-Totals.csv"

	// Some build scripts name the working-age column "working_age": accept both.
	capture rename working_age working_age_total

	// Grand-total row: all categories == "Total".
	keep if gender=="Total" & wage_decile=="Total" & dens=="Total"
	capture destring num_contributors num_affiliates num_inactive ///
		population_total working_age_total wage avg_age contribution_density, replace force

	rename wage avg_wage
	keep year num_contributors num_affiliates num_inactive ///
		 population_total working_age_total avg_wage avg_age contribution_density
	tempfile aff_tot
	save `aff_tot'


//	===========================================================================
//	3. PENSIONER BREAKDOWNS -> beneficiaries & average pension by type
//	===========================================================================
	prost_import using "`pfx'-Pensioner-Reporting-Breakdowns.csv"
	capture destring retired disabled widowed deceased avg_pension, replace force

	// Keep genuine type rows (1/2/3), drop the "Total" placeholder rows.
	gen ptype = real(pension_type)
	drop if missing(ptype)
	keep if inlist(ptype, 1, 2, 3)

	// Beneficiaries of a given type sit in the status column matching that type.
	gen double bene = retired + disabled + widowed
	gen double benefit_mass = bene * avg_pension          // for count-weighted mean

	collapse (sum) bene benefit_mass, by(year ptype)
	gen double avg_pension_type = benefit_mass / bene
	drop benefit_mass

	label define ptype_LAB 1 "Old-age" 2 "Disability" 3 "Survivor", replace
	label values ptype ptype_LAB
	label variable bene             "Beneficiaries"
	label variable avg_pension_type "Average pension"
	gen str20 simulation = "`sim'"
	order simulation year ptype bene avg_pension_type
	sort year ptype
	save "${reportdir}/_prep_`sim'_bytype.dta", replace

	// Year-level totals derived from the type split: annual benefit expenditure.
	preserve
		gen double exp_mass = bene * avg_pension_type
		collapse (sum) benefit_expenditure_period = exp_mass, by(year)
		tempfile exp_year
		save `exp_year'
	restore

	// Old-age average pension by year, for the replacement-ratio indicator.
	preserve
		keep if ptype==1
		keep year avg_pension_type
		rename avg_pension_type avg_pension_oldage
		tempfile oldage
		save `oldage'
	restore


//	===========================================================================
//	4. PENSIONER BREAKDOWNS -> beneficiaries by age group & gender (for pyramid)
//	===========================================================================
	prost_import using "`pfx'-Pensioner-Reporting-Breakdowns.csv"
	capture destring retired disabled widowed deceased, replace force

	// Detailed gender x age rows only (exclude the "Total" placeholders).
	keep if inlist(gender, "Male", "Female")
	gen agev = real(age_grp)
	drop if missing(agev)

	gen double bene = retired + disabled + widowed
	collapse (sum) bene, by(year gender agev)
	rename agev age_grp
	label variable bene "Beneficiaries"
	gen str20 simulation = "`sim'"
	order simulation year gender age_grp bene
	sort year gender age_grp
	save "${reportdir}/_prep_`sim'_byage.dta", replace


//	===========================================================================
//	5. AFFILIATE BREAKDOWNS -> affiliate indicators by wage decile
//	===========================================================================
	prost_import using "`pfx'-Affiliate-Reporting-Breakdowns.csv"
	capture rename working_age working_age_total
	capture destring num_contributors num_affiliates num_inactive wage ///
		contribution_density, replace force

	gen decilev = real(wage_decile)
	drop if missing(decilev)            // drop any "Total" placeholder rows

	collapse (sum) num_contributors num_affiliates num_inactive ///
			 (mean) contribution_density wage, by(year decilev)
	rename decilev wage_decile
	label variable contribution_density "Contribution density"
	label variable num_contributors     "Contributors"
	gen str20 simulation = "`sim'"
	order simulation year wage_decile
	sort year wage_decile
	save "${reportdir}/_prep_`sim'_bydecile.dta", replace


//	===========================================================================
//	6. ASSEMBLE THE SYSTEM-LEVEL TIME SERIES (one row per year)
//	===========================================================================
	use `pens_tot', clear
	merge 1:1 year using `aff_tot',  nogenerate
	merge 1:1 year using `exp_year', nogenerate
	merge 1:1 year using `oldage',   nogenerate
	sort year

	// Parameters from the master (with safe fallbacks if run standalone).
	local crate   = cond("${contrib_rate}"=="", 10, ${contrib_rate})   // % of wage
	local periods = cond("${periods}"=="", 12, ${periods})             // per year

	// --- Coverage & dependency -------------------------------------------------
	gen double dependency_ratio = 100 * total_beneficiaries / num_contributors
	gen double coverage_active  = 100 * num_contributors / working_age_total
	label variable dependency_ratio "Beneficiaries per 100 contributors"
	label variable coverage_active  "Contributors as % of working-age pop."

	// --- Replacement ratio (average old-age pension / average wage) -----------
	gen double replacement_ratio = 100 * avg_pension_oldage / avg_wage
	label variable replacement_ratio "Average old-age pension as % of wage"

	// --- Finances (illustrative; driven by assumed parameters) ----------------
	gen double expenditure = benefit_expenditure_period * `periods'
	gen double contributions = (`crate'/100) * avg_wage * num_contributors * `periods'
	gen double balance = contributions - expenditure
	gen double balance_pct_contrib = 100 * balance / contributions
	gen double spend_per_contributor = expenditure / num_contributors
	label variable expenditure   "Annual benefit expenditure"
	label variable contributions "Annual contributions"
	label variable balance       "Net balance (contributions - expenditure)"

	// --- Scaled copies (millions / billions) for readable charts --------------
	gen double contributors_m       = num_contributors    / 1e6
	gen double beneficiaries_m      = total_beneficiaries / 1e6
	gen double working_age_m        = working_age_total   / 1e6
	gen double expenditure_b        = expenditure   / 1e9
	gen double contributions_b      = contributions / 1e9
	gen double balance_b            = balance        / 1e9
	label variable contributors_m  "Contributors (millions)"
	label variable beneficiaries_m "Beneficiaries (millions)"

	gen str20 simulation = "`sim'"
	order simulation year
	save "${reportdir}/_prep_`sim'_system.dta", replace

	noisily display as text "  prepared datasets saved for `sim' (years " ///
		_continue
	quietly summarize year
	noisily display as text r(min) "-" r(max) ")"
