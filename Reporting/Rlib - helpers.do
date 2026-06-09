/*******************************************************************************
Title: 			Reporting toolkit - shared helpers
Author: 		PROST v2 reporting toolkit
Description:	Defines small utility programs used across the reporting modules.
				Re-running this file is safe (idempotent): programs are dropped
				and re-defined. Every module loads it first, so the modules can
				also be run standalone (after the master has set the globals).

Programs defined:
	prost_import   - import a PROST in-year reporting CSV and standardise the
	                 categorical columns to string (so "Total"/"Male"/numeric
	                 placeholders can be filtered uniformly across files).
	prost_mkdir    - create a directory if it does not already exist.
	prost_png      - export the current graph to PNG at a consistent size.
*******************************************************************************/

	version 15


//	---------------------------------------------------------------------------
//	prost_import: import one reporting CSV, standardise categorical columns.
//
//	Stata's `export delimited` writes value-label TEXT, so category columns
//	arrive as strings in the "Totals" files ("Male", "Active", "Total") but may
//	arrive as NUMERIC in the "Breakdowns" files (e.g. pension_type = 1,2,3 with
//	no "Total"). We coerce every known category column to string so downstream
//	filters such as `keep if gender=="Total"` always behave the same way.
//	---------------------------------------------------------------------------
	capture program drop prost_import
	program define prost_import
		version 15
		syntax using/

		import delimited using "`using'", varnames(1) case(preserve) clear

		// Coerce known categorical columns to string (only if present & numeric)
		foreach v in gender wage_decile dens age_grp age pension_type pension_class {
			capture confirm variable `v'
			if !_rc {
				capture confirm string variable `v'
				if _rc {
					tostring `v', replace force
				}
			}
		}
	end


//	---------------------------------------------------------------------------
//	prost_mkdir: create a directory, ignoring "already exists" errors.
//	---------------------------------------------------------------------------
	capture program drop prost_mkdir
	program define prost_mkdir
		version 15
		args path
		capture mkdir "`path'"
	end


//	---------------------------------------------------------------------------
//	prost_png: export the most recent graph to PNG at a consistent width.
//	Usage: prost_png "full/path/name.png"
//	---------------------------------------------------------------------------
	capture program drop prost_png
	program define prost_png
		version 15
		args file
		quietly graph export "`file'", width(1800) replace
		noisily display as text "  figure: `file'"
	end
