/*******************************************************************************
UN Population By Age Projections

Source: https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=Population

Deaths, by single age. Only medium is available.
https://population.un.org/wpp/assets/Excel%20Files/1_Indicator%20(Standard)/CSV_FILES/WPP2024_DeathsBySingleAgeSex_Medium_2024-2100.csv.gz


*******************************************************************************/


*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\mortality\Input Data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\mortality"
local popdir "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"
cd "`homedir'"

// /* ONLY NEED TO RUN ONCE
/*
** 0. IMPORT AND CLEAN POPULATION DATA 
import delimited "WPP2024_DeathsBySingleAgeSex_Medium_2024-2100.csv", clear 
drop if iso3_code == ""
keep location iso3_code time agegrp  deathmale deathfemale deathtotal
rename agegrp age
replace age = "100" if age == "100+"
destring age, replace

* Save as temp file
compress
save deaths_data.dta, replace
*/

** 1. MERGIE IN THE POPULATION DATA **
cd "`homedir'"
use deaths_data.dta, clear
// Merge in population data
cd "`popdir'"
merge 1:1 iso3_code location time age using population_data_jan1.dta, keep(3)
drop if _merge != 3
drop _merge

// Infer mortality rates
generate mortality = deathtotal / poptotal
generate mortality_male = deathmale / popmale
generate mortality_female = deathfemale / popfemale

// Mortality rates are very high but do not seem to be included in the births data
// As a patch, we use the mortality rate at age 1
generate mortality1 		= mortality 		* (age == 1)
generate mortality_male1 	= mortality_male 	* (age == 1)
generate mortality_female1 	= mortality_female 	* (age == 1)

bysort iso3_code time: egen mort_replace 		= max(mortality1) 
bysort iso3_code time: egen mort_replace_male 	= max(mortality_male1) 
bysort iso3_code time: egen mort_replace_female = max(mortality_female1) 

replace mortality 			= mort_replace 			if age == 0
replace mortality_male 		= mort_replace_male 	if age == 0
replace mortality_female 	= mort_replace_female 	if age == 0


//	Save preliminary data
keep iso3_code location time age mortality mortality_male mortality_female
cd "`homedir'"
save mortality_data.dta, replace


** 2. CLEAN UP AND EXPORT **
rename time year
rename mortality mortality0
rename mortality_male mortality1
rename mortality_female mortality2
reshape long mortality, i(iso3_code year age) j(gender)
generate sex = "total"
replace  sex = "male"   if gender ==1
replace  sex = "female" if gender == 2
generate variable = "mortality"
reshape wide mortality, i(iso3_code age gender sex) j(year)
rename mortality* y*
sort iso3_code gender age
drop gender
rename iso3_code iso3


* Save the file
compress
order iso3 location variable age sex
cd "`homedir'"
save cleaned_mortality_data.dta, replace

* Loop over years and export each 
cd "`outdir'"
drop if sex == "total"
levelsof(iso3), local(countries)
foreach cnt of local countries {
	preserve
		keep if iso3 == "`cnt'"
		export delimited "mortality_`cnt'.csv", replace
	restore
	} // end foreach yr
	

