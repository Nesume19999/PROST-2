/*******************************************************************************
Title: 			Reporting toolkit - report document (Word)
Author: 		PROST v2 reporting toolkit
Description:	Assembles a Word (.docx) report for one simulation: an auto-written
				narrative summary, a compact indicator table, and the charts
				produced by "R3 - Charts.do".

Run R3 before this module so the figures exist to embed.

Inputs (globals):
	${reportdir}   folder with _prep_<sim>_*.dta and figures/<sim>/*.png
	${prep_sim}    simulation name
	${country} ${currency}

Output:
	${reportdir}/<sim>_PROST_report.docx
*******************************************************************************/

	version 15
	quietly do "${codedir}/Rlib - helpers.do"

	local sim    "${prep_sim}"
	local cur    "${currency}"
	local figdir "${reportdir}/figures/`sim'"
	local docx   "${reportdir}/`sim'_PROST_report.docx"

	noisily display _newline as result "Building Word report for simulation: `sim'"


//	---------------------------------------------------------------------------
//	Gather headline numbers for the narrative
//	---------------------------------------------------------------------------
	use "${reportdir}/_prep_`sim'_system.dta", clear
	sort year
	quietly summarize year
	local y0 = r(min)
	local y1 = r(max)

	// helper: pull a variable's value in a given year into a local
	foreach v in dependency_ratio beneficiaries_m contributors_m ///
				 replacement_ratio coverage_active balance_b {
		quietly summarize `v' if year==`y0', meanonly
		local `v'0 = r(mean)
		quietly summarize `v' if year==`y1', meanonly
		local `v'1 = r(mean)
	}

	// first year the illustrative balance turns negative (if any)
	quietly summarize year if balance < 0
	local negyear = r(min)
	local has_neg = (r(N) > 0)

	local dep_change = `dependency_ratio1' - `dependency_ratio0'


//	---------------------------------------------------------------------------
//	Build a compact indicator table (decade snapshots) held in memory
//	---------------------------------------------------------------------------
	preserve
		keep year dependency_ratio coverage_active replacement_ratio ///
			 beneficiaries_m contributors_m balance_b
		keep if mod(year, 10)==0 | year==`y0' | year==`y1'
		format dependency_ratio coverage_active replacement_ratio %6.1f
		format beneficiaries_m contributors_m balance_b %8.2f
		rename dependency_ratio  DependRatio
		rename coverage_active   CoveragePct
		rename replacement_ratio ReplRatioPct
		rename beneficiaries_m   BenefMillions
		rename contributors_m    ContribMillions
		rename balance_b         BalanceBn
		tempfile snap
		save `snap'
	restore


//	---------------------------------------------------------------------------
//	Assemble the document
//	---------------------------------------------------------------------------
	putdocx clear
	putdocx begin

	putdocx paragraph, style(Title)
	putdocx text ("PROST v2 Pension Projection Report")
	putdocx paragraph, style(Subtitle)
	putdocx text ("Simulation: `sim'   |   Country: ${country}   |   Generated: `c(current_date)'")

	putdocx paragraph, style(Heading1)
	putdocx text ("1. Summary")
	putdocx paragraph
	putdocx text ("This report summarises the `sim' projection over `y0'-`y1'. ")
	putdocx text ("The system dependency ratio moves from ")
	putdocx text (string(`dependency_ratio0', "%4.1f")), bold
	putdocx text (" to ")
	putdocx text (string(`dependency_ratio1', "%4.1f")), bold
	putdocx text (" beneficiaries per 100 contributors (a change of ")
	putdocx text (string(`dep_change', "%+4.1f")), bold
	putdocx text ("). The number of beneficiaries goes from ")
	putdocx text (string(`beneficiaries_m0', "%4.2f")), bold
	putdocx text (" million to ")
	putdocx text (string(`beneficiaries_m1', "%4.2f")), bold
	putdocx text (" million, while contributors move from ")
	putdocx text (string(`contributors_m0', "%4.2f")), bold
	putdocx text (" million to ")
	putdocx text (string(`contributors_m1', "%4.2f")), bold
	putdocx text (" million. The average old-age replacement ratio in `y1' is ")
	putdocx text (string(`replacement_ratio1', "%4.1f")), bold
	putdocx text ("%.")
	if `has_neg' {
		putdocx paragraph
		putdocx text ("On the illustrative, parameter-driven financing assumptions, the ")
		putdocx text ("annual balance first turns negative in ")
		putdocx text ("`negyear'"), bold
		putdocx text (".")
	}

	putdocx paragraph, style(Heading1)
	putdocx text ("2. Key indicators (decade snapshots)")
	preserve
		use `snap', clear
		putdocx table tbl = data("year DependRatio CoveragePct ReplRatioPct BenefMillions ContribMillions BalanceBn"), ///
			varnames border(all)
	restore

	putdocx paragraph, style(Heading1)
	putdocx text ("3. Figures")

	local i = 1
	foreach f in 01_contributors_vs_beneficiaries 02_dependency_ratio ///
				 03_beneficiaries_by_type 04_wage_vs_pension ///
				 05_replacement_and_coverage 06_financial_balance ///
				 07_age_pyramid_final_year 08_density_by_decile_final_year {
		capture confirm file "`figdir'/`f'.png"
		if !_rc {
			putdocx paragraph, halign(center)
			putdocx image "`figdir'/`f'.png", width(6in)
		}
		else {
			noisily display as error "  (missing figure `f'.png - run R3 first)"
		}
		local ++i
	}

	putdocx paragraph, style(Heading1)
	putdocx text ("4. Notes")
	putdocx paragraph
	putdocx text ("Beneficiary, contributor, wage and pension figures come directly ")
	putdocx text ("from the PROST v2 in-year reporting outputs. Contributions, ")
	putdocx text ("expenditure and the net balance are illustrative: they are derived ")
	putdocx text ("from an assumed contribution rate of ${contrib_rate}% applied to the ")
	putdocx text ("average wage and the number of contributors, annualised over ")
	putdocx text ("${periods} pay periods. Treat the financing block as indicative ")
	putdocx text ("rather than an actuarial balance.")

	putdocx save "`docx'", replace
	noisily display as text "  report written to `docx'"
