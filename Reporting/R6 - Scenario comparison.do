/*******************************************************************************
Title: 			Reporting toolkit - scenario comparison
Author: 		PROST v2 reporting toolkit
Description:	Compares two prepared simulations side by side: overlay charts,
				an Excel comparison workbook, and a short Word comparison report.

Both simulations must already be prepared by R2 (the master does this).

Inputs (globals):
	${reportdir}   folder with _prep_<sim>_system.dta for both simulations
	${sim_a}       first  simulation name (e.g. "Baseline")
	${sim_b}       second simulation name (e.g. "Reform")
	${currency}

Outputs:
	${reportdir}/figures/comparison/C1..C3_*.png
	${reportdir}/tables/Comparison_<a>_vs_<b>.xlsx
	${reportdir}/Comparison_<a>_vs_<b>_report.docx
*******************************************************************************/

	version 15
	quietly do "${codedir}/Rlib - helpers.do"
	set scheme s1color

	local a   "${sim_a}"
	local b   "${sim_b}"
	local cur "${currency}"
	local figdir "${reportdir}/figures/comparison"
	prost_mkdir "${reportdir}/figures"
	prost_mkdir "`figdir'"
	prost_mkdir "${reportdir}/tables"

	noisily display _newline as result "Comparing simulations: `a' vs `b'"

	// Confirm both prepared files exist.
	foreach s in "`a'" "`b'" {
		capture confirm file "${reportdir}/_prep_`s'_system.dta"
		if _rc {
			noisily display as error "  missing _prep_`s'_system.dta - prepare `s' with R2 first"
			exit 601
		}
	}


//	---------------------------------------------------------------------------
//	Stack the two simulations for overlay charts
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`a'_system.dta", clear
	append using "${reportdir}/_prep_`b'_system.dta"

	// Dependency ratio
	twoway (line dependency_ratio year if simulation=="`a'", lwidth(medthick)) ///
		   (line dependency_ratio year if simulation=="`b'", lwidth(medthick) lpattern(dash)), ///
		title("Dependency ratio: `a' vs `b'") ///
		ytitle("Beneficiaries per 100 contributors") xtitle("Year") ///
		legend(order(1 "`a'" 2 "`b'") rows(1) position(6)) name(c1, replace)
	prost_png "`figdir'/C1_dependency_ratio.png"

	// Beneficiaries
	twoway (line beneficiaries_m year if simulation=="`a'", lwidth(medthick)) ///
		   (line beneficiaries_m year if simulation=="`b'", lwidth(medthick) lpattern(dash)), ///
		title("Beneficiaries: `a' vs `b'") ///
		ytitle("Persons (millions)") xtitle("Year") ///
		legend(order(1 "`a'" 2 "`b'") rows(1) position(6)) name(c2, replace)
	prost_png "`figdir'/C2_beneficiaries.png"

	// Net balance
	twoway (line balance_b year if simulation=="`a'", lwidth(medthick)) ///
		   (line balance_b year if simulation=="`b'", lwidth(medthick) lpattern(dash)), ///
		yline(0, lcolor(gs8)) ///
		title("Illustrative net balance: `a' vs `b'") ///
		ytitle("`cur', billions per year") xtitle("Year") ///
		legend(order(1 "`a'" 2 "`b'") rows(1) position(6)) name(c3, replace)
	prost_png "`figdir'/C3_net_balance.png"


//	---------------------------------------------------------------------------
//	Side-by-side comparison table (merged on year) -> Excel
//	---------------------------------------------------------------------------
	local keepvars year dependency_ratio beneficiaries_m contributors_m ///
					replacement_ratio balance_b

	use "${reportdir}/_prep_`a'_system.dta", clear
	keep `keepvars'
	foreach v in dependency_ratio beneficiaries_m contributors_m replacement_ratio balance_b {
		rename `v' `v'_a
	}
	tempfile ta
	save `ta'

	use "${reportdir}/_prep_`b'_system.dta", clear
	keep `keepvars'
	foreach v in dependency_ratio beneficiaries_m contributors_m replacement_ratio balance_b {
		rename `v' `v'_b
	}
	merge 1:1 year using `ta', nogenerate
	sort year

	// Differences (b - a) on the headline indicators
	gen double dependency_ratio_diff = dependency_ratio_b - dependency_ratio_a
	gen double beneficiaries_m_diff  = beneficiaries_m_b  - beneficiaries_m_a
	gen double balance_b_diff        = balance_b_b        - balance_b_a

	order year dependency_ratio_a dependency_ratio_b dependency_ratio_diff ///
		  beneficiaries_m_a beneficiaries_m_b beneficiaries_m_diff ///
		  balance_b_a balance_b_b balance_b_diff
	format dependency_ratio_* %8.1f
	format beneficiaries_m_* balance_b_* %10.2f

	local xls "${reportdir}/tables/Comparison_`a'_vs_`b'.xlsx"
	export excel using "`xls'", firstrow(variables) sheet("Comparison") replace
	noisily display as text "  comparison workbook: `xls'"


//	---------------------------------------------------------------------------
//	Short comparison report (Word)
//	---------------------------------------------------------------------------
	quietly summarize year
	local y1 = r(max)
	quietly summarize dependency_ratio_diff if year==`y1', meanonly
	local dep_diff_final = r(mean)
	quietly summarize balance_b_diff if year==`y1', meanonly
	local bal_diff_final = r(mean)

	putdocx clear
	putdocx begin
	putdocx paragraph, style(Title)
	putdocx text ("PROST v2 Scenario Comparison")
	putdocx paragraph, style(Subtitle)
	putdocx text ("`a' vs `b'   |   Generated: `c(current_date)'")

	putdocx paragraph, style(Heading1)
	putdocx text ("Summary")
	putdocx paragraph
	putdocx text ("By `y1', the `b' scenario changes the dependency ratio by ")
	putdocx text (string(`dep_diff_final', "%+4.1f")), bold
	putdocx text (" beneficiaries per 100 contributors relative to `a', and the ")
	putdocx text ("illustrative annual balance by ")
	putdocx text (string(`bal_diff_final', "%+4.2f")), bold
	putdocx text (" billion `cur'.")

	putdocx paragraph, style(Heading1)
	putdocx text ("Figures")
	foreach f in C1_dependency_ratio C2_beneficiaries C3_net_balance {
		capture confirm file "`figdir'/`f'.png"
		if !_rc {
			putdocx paragraph, halign(center)
			putdocx image "`figdir'/`f'.png", width(6in)
		}
	}

	local docx "${reportdir}/Comparison_`a'_vs_`b'_report.docx"
	putdocx save "`docx'", replace
	noisily display as text "  comparison report: `docx'"
