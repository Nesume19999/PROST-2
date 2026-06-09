/*******************************************************************************
ILO Wage Data

Sources:
International Labour Organisation

ILOSTAT Earnings
https://ilostat.ilo.org/data/snapshots/earnings/

Average monthly earnings of employees
Average monthly earnings of employees by sex and age (local currency)


Gini Index of hourly earnings by sex and age 



ILO ISO3 codes:
https://ilostat.ilo.org/methods/concepts-and-definitions/classification-country-groupings/

*******************************************************************************/

clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\wage\Input data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\wage"


local baseyear = 2024
********************************************************************************
	

// ONLY NEED TO RUN ONCE


//	IMPORT AND CLEAN GINI DATA
	cd "`homedir'"
	use "EAR_EHRG_SEX_AGE_NB_A-20260317T1601.dta", clear
	rename ref_area_label country
	merge m:1 country using ILO_iso3_codes.dta, nogenerate keepusing(iso3code)
	rename iso3code iso3
	rename sex_label sex
	rename time year
	destring year, replace
	replace iso3 = "CIV" if country == "Côte d'Ivoire"
	drop if iso3 == ""
	drop if sex == "Total"
	rename classif1_label agegrp
	keep country iso3 year sex obs_value agegrp
	order iso3 country year sex agegrp obs_value 
	replace obs_value = 0 if missing(obs_value) // Replace unreliable values with 0
	
//	Get only the latest year
	bysort iso3: egen latest_year = max(year)
	keep if year == latest_year
	drop latest_year
//	Keep only the 10 year bands
	replace agegrp = subinstr(agegrp,"Age (Aggregate bands): ","",.)
	keep if inlist(agegrp, "15-24", "25-54", "55-64", "65+")
	
//	Generate an expension factor to help the mergeing by age
	generate expansion_factor = 0
	replace  expansion_factor = 24-15  + 1 if agegrp == "15-24"
	replace  expansion_factor = 54-25  + 1 if agegrp == "25-54"
	replace  expansion_factor = 64-55  + 1 if agegrp == "55-64"
	replace  expansion_factor = 100-65 + 1 if agegrp == "65+"
	
	generate min_age = 0
	replace  min_age = 15  - 1 if agegrp == "15-24"
	replace  min_age = 25  - 1 if agegrp == "25-54"
	replace  min_age = 55  - 1 if agegrp == "55-64"
	replace  min_age = 65  - 1 if agegrp == "65+"
	
	expand expansion_factor
	
	bysort iso3 year sex agegrp: generate age = min_age + _n
	
//	Cleanup
	replace year = `baseyear'
	drop min_age expansion_factor
	rename obs_value gini
	
	
//	Save the data in a tempfile
	tempfile gini 
	save `gini'
	


//	IMPORT AND CLEAN DATA
	cd "`homedir'"
	use "EAR_EMTA_SEX_AGE_NB_A-20260317T1745.dta", clear
	*import delimited "EAR_EMTA_SEX_AGE_NB_A-20260313T2031.csv", clear
	rename ref_area_label country
	// Merge in ISO3 codes
	merge m:1 country using ILO_iso3_codes.dta, nogenerate keepusing(iso3code iloregion worldbankincomegroup)
	// Cleanup
	rename iso3code iso3
	rename sex_label sex
	rename time year
	destring year, replace
	drop if year > `baseyear'
	replace iso3 = "CIV" if country == "Côte d'Ivoire"
	replace worldbankincomegroup = "Lower-middle income" if iso3 == "CIV"
	replace iloregion = "Africa" if iso3 == "CIV"
	replace worldbankincomegroup = "Lower-middle income" if iso3 == "IND"
	replace iloregion = "Asia and the Pacific" if iso3 == "IND"
	
//	Get only the latest year
	bysort iso3: egen latest_year = max(year)
	keep if year == latest_year
	drop latest_year

	drop if iso3 == ""
	drop if sex == "Total"
	rename classif1_label agegrp
	keep country iso3 year sex obs_value agegrp iloregion worldbankincomegroup
	order iso3 country year sex agegrp obs_value 
	replace obs_value = 0 if missing(obs_value) // Replace unreliable values with 0

//	Keep only the 10 year bands
	replace agegrp = subinstr(agegrp,"Age (10-year bands): ","",.)
	keep if inlist(agegrp, "15-24", "25-34", "35-44", "45-54", "55-64", "65+")
	
//	Merge in the data
	merge m:1 iso3 using WB_GDP_growth_annual.dta, nogenerate keepusing(y*)
	// Assume that growth in missing years was the same as the year before (if missing -- few are)
	forvalues yr = 2000/`baseyear' {
		local yr1 = `yr' - 1
		replace y`yr' = y`yr1' if missing(y`yr')
		} // end forvalues
		
//	Grow wages to baseyear
	generate base_earn = 0
	generate base_year = `baseyear'
	// Compute wage adjustments
	forvalues yr = 2000/`baseyear' {
		capture drop adj`yr'
		generate adj`yr' = 1
		local nextyear = `yr' + 1
		forvalues year = `nextyear'/`baseyear' {
			replace adj`yr' = adj`yr' * (1 + y`year' / 100)
			} // end foreach year
		replace base_earn = obs_value * adj`yr' if year == `yr'
		} // end foreach yr
	
//	Cleanup
	rename obs_value obs_earnings
	rename year obs_year
	rename base_earn earnings
	label variable earnings "Average monthly earnings of employees (grown from observed year)"
	label variable obs_earnings "Average monthly earnings of employees (in observed year)"
	drop y* adj* 

	
//	Generate an expension factor to help the mergeing by age
	generate expansion_factor = 0
	replace  expansion_factor = 24-15  + 1 if agegrp == "15-24"
	replace  expansion_factor = 34-25  + 1 if agegrp == "25-34"
	replace  expansion_factor = 44-35  + 1 if agegrp == "35-44"
	replace  expansion_factor = 54-45  + 1 if agegrp == "45-54"
	replace  expansion_factor = 64-55  + 1 if agegrp == "55-64"
	replace  expansion_factor = 100-65 + 1 if agegrp == "65+"
	
	generate min_age = 0
	replace  min_age = 15  - 1 if agegrp == "15-24"
	replace  min_age = 25  - 1 if agegrp == "25-34"
	replace  min_age = 35  - 1 if agegrp == "35-44"
	replace  min_age = 45  - 1 if agegrp == "45-54"
	replace  min_age = 55  - 1 if agegrp == "55-64"
	replace  min_age = 65  - 1 if agegrp == "65+"
	
	expand expansion_factor
	
	bysort iso3 base_year sex agegrp: generate age = min_age + _n

//	Cleanup	
	drop min_age expansion_factor
	rename base_year year
	order iso3 country sex agegrp age obs_year obs_earnings year earnings
	drop if missing(obs_earnings)
	
//	Merge in the Gini coefficient (so we can infer the standard deviation)
	merge 1:1 iso3 country sex age year using `gini', keepusing(gini)  keep(1 3) nogenerate
	
//	Some value are missing so we take the averages from similar region-income countries
	bysort iloregion age worldbankincomegroup: egen gini_avg = mean(gini)
	replace gini = gini_avg if missing(gini)
	drop gini_avg
	
//	We infer the standard deviation by assuming a lognormal distribution and working backwards
//	Refer to this for a background: https://stats.stackexchange.com/questions/642991/is-it-possible-to-calculate-a-standard-deviation-from-the-gini-coefficient-and-m
	generate double erfinv = invnormal((1 + gini) / 2) / sqrt(2)
	generate double sd_lognormal = 2 * erfinv
	generate double sd = earnings * sqrt(exp(sd_lognormal^2) - 1)


//	EXPORT THE DATA
//	Save the file
	cd "`homedir'"
	compress
	save wage_data.dta, replace

//	Loop over years and export each file
	cd "`outdir'"
	keep iso3 country sex age year earnings gini sd
	levelsof(iso3), local(countries)
	foreach cnt of local countries {
		preserve
			keep if iso3 == "`cnt'"
			export delimited "wage_`cnt'.csv", replace
		restore
		} // end foreach yr
		


		
