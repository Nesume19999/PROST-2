/*******************************************************************************
Historic mortality rates

------------------------------
UN Population By Age Projections
Source: https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=Population

Population by Single Age - medium scenario
Population on 01 January, by single age. Only medium is available.
https://population.un.org/wpp/assets/Excel%20Files/1_Indicator%20(Standard)/CSV_FILES/WPP2024_Population1JanuaryBySingleAgeSex_Medium_1950-2023.csv.gz




------------------------------

Deaths, by single age. Only medium is available.
1950-2023 (gz)
https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=CSV%20format


*******************************************************************************/


*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir 	= "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\mortality_obs\Input data"
local outdir 	= "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\mortality_obs"
local popdir 	= "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population_obs\Input data"
cd "`homedir'"

// /* ONLY NEED TO RUN ONCE
/*
** 0. IMPORT AND CLEAN POPULATION DATA 
import delimited "WPP2024_DeathsBySingleAgeSex_Medium_1950-2023.csv", clear 
drop if iso3_code == ""
keep location iso3_code time agegrp  deathmale deathfemale deathtotal
rename agegrp age
replace age = "100" if age == "100+"
destring age, replace

* Save as temp file
compress
save deaths_data_obs.dta, replace
*/

** 1. MERGE IN THE POPULATION DATA **
cd "`homedir'"
use deaths_data_obs.dta, clear
// Merge in population data
cd "`popdir'"
merge 1:1 iso3_code location time age using population_historical_data_jan1.dta, keep(3)
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
save mortality_obs_data.dta, replace


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
save cleaned_mortality_obs_data.dta, replace

* Loop over years and export each 
cd "`outdir'"
drop if sex == "total"
levelsof(iso3), local(countries)
foreach cnt of local countries {
	preserve
		keep if iso3 == "`cnt'"
		export delimited "mortality_obs_`cnt'.csv", replace
	restore
	} // end foreach yr
	

