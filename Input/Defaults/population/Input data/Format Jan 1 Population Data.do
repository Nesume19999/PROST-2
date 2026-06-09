/*******************************************************************************
UN Population By Age Projections

Source: https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=Population

Population on 01 January, by single age. Only medium is available.
https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=CSV%20format

Note: We need the January 1st data to make sure that data aligns with transition rates
https://population.un.org/wpp/assets/Excel%20Files/1_Indicator%20(Standard)/CSV_FILES/WPP2024_Population1JanuaryBySingleAgeSex_Medium_2024-2100.csv.gz



*******************************************************************************/


*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population"
cd "`homedir'"

// /* ONLY NEED TO RUN ONCE

** 0. IMPORT AND CLEAN POPULATION DATA 
import delimited "WPP2024_Population1JanuaryBySingleAgeSex_Medium_2024-2100.csv", clear 
drop if iso3_code == ""
keep location iso3_code time agegrp  poptotal popmale popfemale
rename agegrp age
replace age = "100" if age == "100+"
destring age, replace

* Save as temp file
compress
save population_data_jan1.dta, replace



** 1. CLEAN UP AND EXPORT **
rename time year
rename poptotal pop0
rename popmale pop1
rename popfemale pop2
reshape long pop, i(iso3_code year age) j(gender)
generate sex = "total"
replace  sex = "male"   if gender ==1
replace  sex = "female" if gender == 2
generate variable = "population"
reshape wide pop, i(iso3_code age gender sex) j(year)
rename pop* y*
sort iso3_code gender age
drop gender
rename iso3_code iso3


* Save the file
compress
save cleaned_pop_data_jan1.dta, replace

* Loop over years and export each 
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population"

cd "`outdir'"
drop if sex == "total"
levelsof(iso3), local(countries)
foreach cnt of local countries {
	preserve
		keep if iso3 == "`cnt'"
		export delimited "population_`cnt'.csv", replace
	restore
	} // end foreach yr
	

