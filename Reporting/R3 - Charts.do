/*******************************************************************************
Title: 			Reporting toolkit - charts
Author: 		PROST v2 reporting toolkit
Description:	Builds the standard set of projection charts for one simulation
				from the datasets prepared by "R2 - Prepare indicators.do" and
				exports them as PNG figures.

Inputs (globals):
	${reportdir}   folder with the _prep_<sim>_*.dta datasets
	${prep_sim}    simulation name to chart
	${currency}    currency label used on money axes (e.g. "MXN")

Output:
	${reportdir}/figures/<sim>/01..08_*.png
*******************************************************************************/

	version 15
	quietly do "${codedir}/Rlib - helpers.do"
	set scheme s1color

	local sim   "${prep_sim}"
	local cur   "${currency}"
	local figdir "${reportdir}/figures/`sim'"
	prost_mkdir "${reportdir}/figures"
	prost_mkdir "`figdir'"

	noisily display _newline as result "Building charts for simulation: `sim'"


//	---------------------------------------------------------------------------
//	1. Contributors vs beneficiaries
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_system.dta", clear
	twoway (line contributors_m  year, lwidth(medthick)) ///
		   (line beneficiaries_m year, lwidth(medthick) lpattern(dash)), ///
		title("Contributors vs beneficiaries") subtitle("`sim'") ///
		ytitle("Persons (millions)") xtitle("Year") ///
		legend(order(1 "Contributors" 2 "Beneficiaries") rows(1) position(6)) ///
		name(g1, replace)
	prost_png "`figdir'/01_contributors_vs_beneficiaries.png"


//	---------------------------------------------------------------------------
//	2. System dependency ratio
//	---------------------------------------------------------------------------
	twoway (line dependency_ratio year, lwidth(medthick) lcolor(navy)), ///
		title("System dependency ratio") subtitle("`sim'") ///
		ytitle("Beneficiaries per 100 contributors") xtitle("Year") ///
		name(g2, replace)
	prost_png "`figdir'/02_dependency_ratio.png"


//	---------------------------------------------------------------------------
//	3. Beneficiaries by pension type
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_bytype.dta", clear
	gen double bene_m = bene / 1e6
	twoway (line bene_m year if ptype==1, lwidth(medthick)) ///
		   (line bene_m year if ptype==2, lwidth(medthick)) ///
		   (line bene_m year if ptype==3, lwidth(medthick)), ///
		title("Beneficiaries by pension type") subtitle("`sim'") ///
		ytitle("Persons (millions)") xtitle("Year") ///
		legend(order(1 "Old-age" 2 "Disability" 3 "Survivor") rows(1) position(6)) ///
		name(g3, replace)
	prost_png "`figdir'/03_beneficiaries_by_type.png"


//	---------------------------------------------------------------------------
//	4. Average old-age pension vs average wage
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_system.dta", clear
	twoway (line avg_wage          year, lwidth(medthick)) ///
		   (line avg_pension_oldage year, lwidth(medthick) lpattern(dash)), ///
		title("Average wage vs average old-age pension") subtitle("`sim'") ///
		ytitle("`cur' per period") xtitle("Year") ///
		legend(order(1 "Average wage" 2 "Average old-age pension") rows(1) position(6)) ///
		name(g4, replace)
	prost_png "`figdir'/04_wage_vs_pension.png"


//	---------------------------------------------------------------------------
//	5. Replacement ratio and active coverage
//	---------------------------------------------------------------------------
	twoway (line replacement_ratio year, lwidth(medthick)) ///
		   (line coverage_active   year, lwidth(medthick) lpattern(dash)), ///
		title("Replacement ratio and coverage") subtitle("`sim'") ///
		ytitle("Percent") xtitle("Year") ///
		legend(order(1 "Old-age pension / wage" 2 "Coverage of working-age") ///
			rows(1) position(6)) ///
		name(g5, replace)
	prost_png "`figdir'/05_replacement_and_coverage.png"


//	---------------------------------------------------------------------------
//	6. Financial balance: contributions, expenditure, net balance
//	---------------------------------------------------------------------------
	twoway (line contributions_b year, lwidth(medthick)) ///
		   (line expenditure_b   year, lwidth(medthick) lpattern(dash)) ///
		   (line balance_b        year, lwidth(medthick) lpattern(shortdash) lcolor(cranberry)), ///
		yline(0, lcolor(gs8)) ///
		title("Illustrative financial balance") subtitle("`sim'") ///
		ytitle("`cur', billions per year") xtitle("Year") ///
		legend(order(1 "Contributions" 2 "Expenditure" 3 "Net balance") ///
			rows(1) position(6)) ///
		note("Contributions = contribution rate x average wage x contributors. Parameter-driven; illustrative only.") ///
		name(g6, replace)
	prost_png "`figdir'/06_financial_balance.png"


//	---------------------------------------------------------------------------
//	7. Beneficiary age pyramid (final projection year)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_byage.dta", clear
	quietly summarize year
	local fy = r(max)
	keep if year==`fy'
	gen double bene_m = bene / 1e6
	replace bene_m = -bene_m if gender=="Male"
	twoway (bar bene_m age_grp if gender=="Male",   horizontal barwidth(4)) ///
		   (bar bene_m age_grp if gender=="Female", horizontal barwidth(4)), ///
		title("Beneficiary age structure, `fy'") subtitle("`sim'") ///
		ytitle("Age group") xtitle("Persons (millions) - Male | Female +") ///
		legend(order(1 "Male" 2 "Female") rows(1) position(6)) ///
		name(g7, replace)
	prost_png "`figdir'/07_age_pyramid_final_year.png"


//	---------------------------------------------------------------------------
//	8. Contribution density by wage decile (final projection year)
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_bydecile.dta", clear
	quietly summarize year
	keep if year==r(max)
	local fy = r(max)
	graph bar (mean) contribution_density, over(wage_decile, label(labsize(small))) ///
		title("Contribution density by wage decile, `fy'") subtitle("`sim'") ///
		ytitle("Average contribution density") ///
		name(g8, replace)
	prost_png "`figdir'/08_density_by_decile_final_year.png"

	noisily display as text "  charts written to `figdir'"
