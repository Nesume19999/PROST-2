/*******************************************************************************
IMF WEO CPI Projections


Source: https://data.imf.org/en/datasets/IMF.RES:WEO

Variable of interest:
PCPIPCH	All Items, Consumer price index (CPI), Period average, percent change


*******************************************************************************/


// Setup
clear all
set more off

// locals
	local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\wage_growth\Input data"
	local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\wage_growth"

	local projection_year = 2100 // Last year to project to



** 0. IMPORT AND CLEAN IMF WEO DATA 
	cd "`homedir'"
	import excel "WEOOct2025all.xlsx", sheet("Countries") firstrow

// Cleanup
	rename COUNTRYID iso3
	keep if INDICATORID == "PCPIPCH"
	keep iso3 y*

//	Reshape the data long
	reshape long y, i(iso3) j(year)
	rename y wage_growth
	label variable wage_growth "All Items, Consumer price index (CPI), Period average, percent change, PCPIPCH (IMF WEO)"

//	Expand the data into the future
	summarize year
	local latest_year = r(max)
	local horizon = `projection_year' - `latest_year' + 1
	
	expand `horizon' if year == `latest_year'
	
	// Update years for the expanded dataset
	bysort iso3 year: replace year = (year - 1) + _n 


//	Save the file
	cd "`homedir'"
	compress
	save cleaned_weo_imf_cpi.dta, replace

//	Loop over countries and export each 

	cd "`outdir'"
	levelsof(iso3), local(countries)
	foreach cnt of local countries {
		preserve
			keep if iso3 == "`cnt'"
			export delimited "cpi_`cnt'.csv", replace
		restore
		} // end foreach cnt
		

