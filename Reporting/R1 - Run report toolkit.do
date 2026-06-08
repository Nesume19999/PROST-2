/*******************************************************************************
Title: 			Run report toolkit (master)
Author: 		PROST v2 reporting toolkit
Description:	Master driver for the PROST v2 reporting toolkit. Reads the
				in-year reporting CSVs produced by the model's build script
				("1 - PROSTv2 - Build projection database.do") and produces, for
				each simulation: charts (PNG), a summary workbook (Excel), and a
				report document (Word) - plus an optional comparison of two
				simulations.

				This is the pure-Stata sibling of the Python package in
				./prost_report. Either produces equivalent outputs from the same
				CSV inputs; use whichever fits your workflow.

Requires:		Stata 15+ (uses putdocx). No external SSC commands needed.

How to run:		1. Edit the USER SETTINGS block below (paths, simulations,
				   parameters).
				2. Run this file:   do "R1 - Run report toolkit.do"

Note:			Parameters are passed to the component R*.do files via GLOBAL
				macros (globals persist across `do`; locals do not).
*******************************************************************************/

	clear all
	set more off


//	==========================================================================
//	USER SETTINGS  (edit these)
//	==========================================================================

	// Folder that contains THIS file and the other R*.do / Rlib files.
	global codedir   "C:/path/to/PROST-2/Reporting"

	// Folder that contains the PROST output CSVs to report on.
	// For a quick demo against the bundled synthetic data, point at sample_output:
	global outdir    "${codedir}/sample_output"

	// Folder where charts, tables and reports will be written (created if needed).
	global reportdir "${codedir}/report_output"

	// Simulations to report on. List one or more names exactly as they appear
	// in the CSV file names (1_PROSTv2-<NAME>-Inyear-...).
	global sims      "Baseline Reform"

	// Produce a side-by-side comparison of the FIRST TWO simulations? (1=yes)
	global do_compare = 1

	// Labels and financing assumptions (the financing block is illustrative).
	global country      "MEX"     // shown in titles
	global currency     "MXN"     // shown on money axes
	global contrib_rate "10"      // contribution rate, % of covered wage
	global periods      "12"      // pay periods per year (annualises amounts)

	// Which deliverables to build (1=yes, 0=skip).
	global do_charts = 1
	global do_tables = 1
	global do_report = 1


//	==========================================================================
//	DRIVER  (no need to edit below)
//	==========================================================================

	// Load shared helper programs.
	quietly do "${codedir}/Rlib - helpers.do"

	// Make sure the output folder exists.
	prost_mkdir "${reportdir}"

	// --- Per-simulation pipeline -------------------------------------------
	foreach sim of global sims {
		global prep_sim "`sim'"
		display _newline(1) as result "================ `sim' ================"

		// Always prepare indicators first (charts/tables/report depend on it).
		do "${codedir}/R2 - Prepare indicators.do"

		if ${do_charts} do "${codedir}/R3 - Charts.do"
		if ${do_tables} do "${codedir}/R4 - Summary tables.do"
		if ${do_report} do "${codedir}/R5 - Report document.do"
	}

	// --- Optional scenario comparison (first two simulations) --------------
	if ${do_compare} {
		// Pull the first two names out of the simulation list.
		local simlist "${sims}"
		local a : word 1 of `simlist'
		local b : word 2 of `simlist'
		if "`b'" == "" {
			display as error "do_compare=1 but fewer than two simulations listed; skipping."
		}
		else {
			global sim_a "`a'"
			global sim_b "`b'"
			display _newline(1) as result "============ Comparison: `a' vs `b' ============"
			do "${codedir}/R6 - Scenario comparison.do"
		}
	}

	display _newline(1) as result "Reporting toolkit complete. Outputs in: ${reportdir}"
