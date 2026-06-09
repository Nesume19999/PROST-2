/*******************************************************************************
Title:        RUN ALL - PROSTv2 full pipeline
Author:       (runner added on top of Duncan MacDonald's PROST v2 code)
Description:  One-click runner for the whole model:
                 Stage 1  Pre-processing (steps 01 -> 06)
                 Stage 2  Projection / microsimulation -> writes Output/

Requirements: Stata (MP recommended) + gtools + ftools
                 ssc install gtools
                 ssc install ftools

How to run:   Open this file in Stata and click "Do", or:  do "RUN ALL - PROSTv2 pipeline.do"
              (Run from a machine that has Stata AND the input data on disk.)
*******************************************************************************/

	clear all
	set more off

//	==========================================================================
//	EDIT THIS LINE IF YOU MOVE THE REPO TO A DIFFERENT MACHINE/PATH.
//	It must match the `global root` line inside every numbered .do file
//	(they reset globals with `clear all`, so each file defines its own root).
//	==========================================================================
	global root "C:/Users/WB542352/OneDrive - WBG/Documents/GitHub/PROST-2"

//	Work from the repo root so the do-files resolve by name
	cd "${root}"


//	--------------------------------------------------------------------------
//	STAGE 1 - PRE-PROCESSING  (steps 01 -> 06)
//	Reads raw client microdata from ${root}/Input :
//	   - "2 Input from client - longitudinal microdata about affiliates.dta"
//	   - "3 Input from client - microdata about beneficiaries.dta"
//	Writes intermediates into ${root}/Input and ${root}/Input/Defaults/<subfolder>/
//	(baseyear_data_MEX.dta, pensioners_MEX.dta, affiliation_MEX_10.csv,
//	 job_*_model_MEX_10_final, lifecycle_wages_MEX, retirement/disability/survivor rates)
//
//	NOTE: heavy step (the longitudinal file is ~2 GB). If your Defaults/ already
//	      hold up-to-date intermediates, you may comment this line out and run
//	      Stage 2 only. (But the build expects names produced by these steps,
//	      e.g. lifecycle_wages_MEX, so re-run preprocessing if unsure.)
//	--------------------------------------------------------------------------
	do "0 - Run preprocessing steps.do"


//	--------------------------------------------------------------------------
//	STAGE 2 - PROJECTION (microsimulation)
//	Reads ${root}/Input (+ Defaults) and writes results to ${root}/Output :
//	   1_PROSTv2-Baseline-Affiliates-<startyear>-<endyear>.csv
//	   1_PROSTv2-Baseline-Pensioners-<startyear>-<endyear>.csv
//	   1_PROSTv2-Baseline-Inyear-*-Reporting-*.csv
//	To produce the Reform scenario, set `local simname = "Reform"` (line ~56)
//	inside the build file and swap the relevant assumption inputs, then re-run.
//	--------------------------------------------------------------------------
	do "1 - PROSTv2 - Build projection database.do"


	display as result "================================================================"
	display as result " PIPELINE COMPLETE -> outputs written to ${root}/Output"
	display as result "================================================================"

//	--------------------------------------------------------------------------
//	STAGE 3 - REPORTING (optional, run separately)
//	See ./Reporting/ : run_report.py (Python) or "R1 - Run report toolkit.do".
//	It consumes the Inyear-*-Reporting-*.csv files from ${root}/Output.
//	--------------------------------------------------------------------------
