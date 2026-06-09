/*******************************************************************************
UN Net Migration

Imputed as a residual from UN Medium projection

https://population.un.org/wpp/downloads?folder=Standard%20Projections&group=CSV%20format



Sources:
Population by Single Age - Population on 01 January, by single age. Medium scenario
https://population.un.org/wpp/assets/Excel%20Files/1_Indicator%20(Standard)/CSV_FILES/WPP2024_Population1JanuaryBySingleAgeSex_Medium_2024-2100.csv.gz

Deaths, by single age. Medium scenario
https://population.un.org/wpp/assets/Excel%20Files/1_Indicator%20(Standard)/CSV_FILES/WPP2024_DeathsBySingleAgeSex_Medium_2024-2100.csv.gz

Births (thousands), Medium scenario
https://population.un.org/wpp

*******************************************************************************/


*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\net_migration\Input data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\net_migration"

local fertdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\fertility\Input data"
local mortdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\mortality\Input data"
local popdir "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"



********************************************************************************
	


// ONLY NEED TO RUN ONCE
/*
//	IMPORT AND CLEAN BIRTHS DATA
	cd "`homedir'"
	import delimited "WPP2024_Fertility_by_Age1.csv", clear 
	drop if iso3_code == ""
	keep if variant == "Medium"
	keep if time >= 2024
	keep location iso3_code time agegrp  births
	rename agegrp age

//	Collapse births to aggregate
	collapse (sum) births, by(iso3_code location time)

	generate age = 0 // All births happen at age 0

//	Save dta file
	compress
	save birth_data.dta, replace
*/


/*
//	IMPORT AND CLEAN POPULATION DATA
	import delimited "WPP2024_Population1JanuaryBySingleAgeSex_Medium_2024-2100.csv", clear 

//	Keep only necessary variables (Location, Time, Age, Sex, Total Population)
	drop if iso3_code == ""
	keep location iso3_code time agegrp  poptotal popmale popfemale
	rename agegrp age
	replace age = "100" if age == "100+"
	destring age, replace

//	Save dta file
	compress
	cd "`homedir'"
	save pop_data.dta, replace
*/


// 	Open the mortality data
	cd "`mortdir'"
	use mortality_data.dta, clear

//	MERGE POPULATION AND DEATHS AND BIRTHS 
	cd "`homedir'"
	merge 1:1 location iso3_code time age using pop_data.dta
	drop _merge

	merge 1:1 location iso3_code time age using birth_data.dta
	drop _merge


//	Define cohorts
	generate birth_year = time - age	// Constant cohorts
	egen country_id = group(iso3_code)  // Unique country ID
	egen cohort_id = group(country_id birth_year) // Unique cohort ID
	label var cohort_id "Unique ID for Age Cohort within Country"

//	Set the time series 
	tsset cohort time

//	CALCULATE NET MIGRATION USING THE BALANCING EQUATION
//	The Balancing Equation: Net Migration = Next Year's Pop - (Current Pop - Deaths)
	generate net_migration 			= poptotal  - (l.poptotal  * (1 - l.mortality))
	generate net_migration_male 	= popmale   - (l.popmale   * (1 - l.mortality_male))
	generate net_migration_female	= popfemale - (l.popfemale * (1 - l.mortality_female))



//	SPECIAL CASE: INFANTS (AGE 0)
// 	Compute sex-at-birth ratio (we need this as an approximation as we don't have births by sex)
//	Note: We use the SRB in the baseyear as we don't know if there will be more data imported by the user
	bysort iso3_code: egen baseyear = min(time)
	
	generate share_male_base = popmale / (popfemale + popmale)  if time == baseyear & age == 0
	bysort iso3_code: egen share_male = max(share_male_base)
	generate share_female = 1 - share_male


//	Note: For Age 0, the 'Current Pop' is actually the number of Births that year.
//	Note: We don't apply the mortality rate here
	replace net_migration        = poptotal  - (births			    	) 	if age == 0
	replace net_migration_male   = popmale   - (births * share_male   	) 	if age == 0
	replace net_migration_female = popfemale - (births * share_female 	)   if age == 0

	
//	CLEAN UP THE DATA	
	rename time year
	rename iso3_code iso3
	keep iso3 year age net_migration_male net_migration_female
	rename net_migration_male net_migration1
	rename net_migration_female net_migration2
	drop if year == 2023
	drop if age < 0
	reshape long net_migration, i(iso3 year age) j(gender)
	generate sex = "male"
	replace  sex = "female" if gender == 2
	generate variable = "net_migration"
	reshape wide net_migration, i(iso3 age gender sex) j(year)
	rename net_migration* y*
	sort iso3 gender age
	drop y2101 gender



//	EXPORT THE DATA
//	Save the file
	cd "`homedir'"
	compress
	save net_migration_data.dta, replace

//	Loop over years and export each file
	cd "`outdir'"
	levelsof(iso3), local(countries)
	foreach cnt of local countries {
		preserve
			keep if iso3 == "`cnt'"
			export delimited "net_migration_`cnt'.csv", replace
		restore
		} // end foreach yr
		

