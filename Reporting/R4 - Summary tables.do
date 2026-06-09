/*******************************************************************************
Title: 			Reporting toolkit - summary tables (Excel)
Author: 		PROST v2 reporting toolkit
Description:	Writes a multi-sheet Excel workbook of key indicators for one
				simulation from the datasets prepared by R2.

Inputs (globals):
	${reportdir}   folder with the _prep_<sim>_*.dta datasets
	${prep_sim}    simulation name
	${country} ${currency} ${contrib_rate} ${periods}   (for the Notes sheet)

Output:
	${reportdir}/tables/<sim>_PROST_tables.xlsx
		sheets: Overview | Beneficiaries | Finances | By age | By decile | Notes
*******************************************************************************/

	version 15
	quietly do "${codedir}/Rlib - helpers.do"

	local sim   "${prep_sim}"
	prost_mkdir "${reportdir}/tables"
	local xls   "${reportdir}/tables/`sim'_PROST_tables.xlsx"

	noisily display _newline as result "Building Excel tables for simulation: `sim'"


//	---------------------------------------------------------------------------
//	Sheet 1: Overview - headline indicators by year
//	(First sheet uses replace to (re)create the whole workbook file.)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_system.dta", clear
	keep year num_contributors total_beneficiaries dependency_ratio ///
		 coverage_active replacement_ratio avg_wage avg_pension_oldage ///
		 population_total working_age_total
	format num_contributors total_beneficiaries population_total ///
		   working_age_total %15.0fc
	format dependency_ratio coverage_active replacement_ratio %9.1f
	format avg_wage avg_pension_oldage %12.2f
	label variable year                "Year"
	label variable num_contributors    "Contributors"
	label variable total_beneficiaries "Beneficiaries"
	label variable dependency_ratio    "Dependency ratio (per 100)"
	label variable coverage_active     "Coverage (% working-age)"
	label variable replacement_ratio   "Replacement ratio (%)"
	label variable avg_wage            "Average wage"
	label variable avg_pension_oldage  "Average old-age pension"
	label variable population_total    "Total population"
	label variable working_age_total   "Working-age population"
	export excel using "`xls'", firstrow(varlabels) sheet("Overview") replace


//	---------------------------------------------------------------------------
//	Sheet 2: Beneficiaries by type (wide: year x type)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_bytype.dta", clear
	keep year ptype bene
	reshape wide bene, i(year) j(ptype)
	rename bene1 oldage
	rename bene2 disability
	rename bene3 survivor
	gen double total = oldage + disability + survivor
	format oldage disability survivor total %15.0fc
	label variable year       "Year"
	label variable oldage     "Old-age"
	label variable disability "Disability"
	label variable survivor   "Survivor"
	label variable total      "Total beneficiaries"
	export excel using "`xls'", firstrow(varlabels) sheet("Beneficiaries") sheetreplace


//	---------------------------------------------------------------------------
//	Sheet 3: Finances by year (illustrative, parameter-driven)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_system.dta", clear
	keep year contributions expenditure balance balance_pct_contrib spend_per_contributor
	format contributions expenditure balance %18.0fc
	format balance_pct_contrib %9.1f
	format spend_per_contributor %12.2f
	label variable year                  "Year"
	label variable contributions         "Contributions"
	label variable expenditure           "Expenditure"
	label variable balance               "Net balance"
	label variable balance_pct_contrib   "Balance (% of contributions)"
	label variable spend_per_contributor "Expenditure per contributor"
	export excel using "`xls'", firstrow(varlabels) sheet("Finances") sheetreplace


//	---------------------------------------------------------------------------
//	Sheet 4: Beneficiaries by age group & gender (final projection year)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_byage.dta", clear
	quietly summarize year
	local fy = r(max)
	keep if year==`fy'
	keep gender age_grp bene
	reshape wide bene, i(age_grp) j(gender) string
	capture rename beneMale male
	capture rename beneFemale female
	capture gen double male   = 0 if missing(male)
	capture gen double female = 0 if missing(female)
	gen double total = male + female
	format male female total %15.0fc
	label variable age_grp "Age group"
	label variable male    "Male"
	label variable female  "Female"
	label variable total   "Total"
	export excel using "`xls'", firstrow(varlabels) sheet("By age `fy'") sheetreplace


//	---------------------------------------------------------------------------
//	Sheet 5: Affiliate indicators by wage decile (final projection year)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_bydecile.dta", clear
	quietly summarize year
	local fy = r(max)
	keep if year==`fy'
	keep wage_decile num_contributors num_affiliates contribution_density wage
	format num_contributors num_affiliates %15.0fc
	format contribution_density %9.3f
	format wage %12.2f
	label variable wage_decile          "Wage decile"
	label variable num_contributors     "Contributors"
	label variable num_affiliates       "Affiliates"
	label variable contribution_density "Contribution density"
	label variable wage                 "Average wage"
	export excel using "`xls'", firstrow(varlabels) sheet("By decile `fy'") sheetreplace


//	---------------------------------------------------------------------------
//	Sheet 6: Notes & parameters
//	---------------------------------------------------------------------------
	clear
	set obs 8
	gen str40 item  = ""
	gen str60 value = ""
	replace item = "Simulation"            in 1
	replace item = "Country"               in 2
	replace item = "Currency"              in 3
	replace item = "Contribution rate (%)" in 4
	replace item = "Pay periods per year"  in 5
	replace item = "Source"                in 6
	replace item = "Nature of finances"    in 7
	replace item = "Generated"             in 8
	replace value = "${prep_sim}"          in 1
	replace value = "${country}"           in 2
	replace value = "${currency}"          in 3
	replace value = "${contrib_rate}"      in 4
	replace value = "${periods}"           in 5
	replace value = "PROST v2 in-year reporting CSVs" in 6
	replace value = "Illustrative, parameter-driven"  in 7
	replace value = "`c(current_date)'"    in 8
	label variable item  "Item"
	label variable value "Value"
	export excel using "`xls'", firstrow(varlabels) sheet("Notes") sheetreplace

	noisily display as text "  workbook written to `xls'"
