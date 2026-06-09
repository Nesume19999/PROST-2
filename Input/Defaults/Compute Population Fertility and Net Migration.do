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
cd "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"
import delimited "WPP2024_Fertility_by_Age1.csv", clear 

*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults"
cd "`homedir'"

// /* ONLY NEED TO RUN ONCE

** 0. IMPORT AND CLEAN BIRTHS DATA 
cd "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\fertility"
import delimited "WPP2024_Fertility_by_Age1.csv", clear 
drop if iso3_code == ""
keep if variant == "Medium"
keep if time >= 2024
keep location iso3_code time agegrp births
rename agegrp age

* Collapse births to aggregate
collapse (sum) births, by(iso3_code location time)

generate age = 0 // All births happen at age 0

* Save as temp file
compress
save birth_data.dta, replace


*/

** 1. IMPORT AND CLEAN MEDIUM-VARIANT POPULATION DATA **
import delimited "WPP2024_PopulationBySingleAgeSex_Medium_2024-2100.csv", clear 

drop if iso3_code == ""
* Keep only necessary variables (Location, Time, Age, Sex, Total Population)
keep location iso3_code time agegrp  poptotal popmale popfemale
rename agegrp age
replace age = "100" if age == "100+"
destring age, replace

* Save as temp file
compress
save pop_data_medium.dta, replace

* Compute the next population values **
replace age = age - 1
replace time = time - 1
rename poptotal next_pop_total
rename popfemale next_pop_female
rename popmale next_pop_male

* Save as temp file
compress
save next_pop_data_medium.dta, replace


** 2. IMPORT AND CLEAN ZERO-MIGRATION-VARIANT POPULATION DATA **
import delimited "WPP2024_PopulationBySingleAgeSex_Zero migration_2024-2100.csv", clear 

drop if iso3_code == ""
* Keep only necessary variables (Location, Time, Age, Sex, Total Population)
keep location iso3_code time agegrp  poptotal popmale popfemale
rename agegrp age
rename poptotal poptotal_zero
rename popmale popmale_zero
rename popfemale popfemale_zero

replace age = "100" if age == "100+"
destring age, replace

* Save as temp file
compress
save pop_data_zero_migration.dta, replace

* Compute the next population values **
replace age = age - 1
replace time = time - 1
rename poptotal_zero next_pop_total_zero
rename popfemale_zero next_pop_female_zero
rename popmale_zero next_pop_male_zero

* Save as temp file
compress
save next_pop_data_zero_migration.dta, replace



*/


** 3. COMPUTE NET MIGRATION **
use pop_data_medium, clear
merge 1:1 location iso3_code time age using pop_data_zero_migration
drop _merge

* Determine the net migration amounts
generate net_migration 			= poptotal 	- poptotal_zero
generate net_migration_male 	= popmale 	- popmale_zero
generate net_migration_female 	= popfemale - popfemale_zero


** 3. IMPORT AND CLEAN DEATHS DATA **
* Update the filename to match your downloaded UN WPP Deaths file
import delimited "WPP2024_DeathsBySingleAgeSex_Medium_2024-2100.csv", clear
drop if iso3_code == ""


keep location iso3_code time agegrp deathmale deathfemale deathtotal
rename deathtotal deaths
rename agegrp age
replace age = "100" if age == "100+"
destring age, replace



** 4. MERGE POPULATION AND DEATHS AND BIRTHS **
// merge 1:1 location iso3_code time age using "`pop_data'"
merge 1:1 location iso3_code time age using pop_data.dta
drop _merge

// merge 1:1 location iso3_code time age using "`next_pop_data'"
merge 1:1 location iso3_code time age using next_pop_data.dta
drop _merge

// merge 1:1 location iso3_code time age using "`birth_data'"
merge 1:1 location iso3_code time age using birth_data.dta
drop _merge



** 5. CALCULATE NET MIGRATION USING THE BALANCING EQUATION **
* The Balancing Equation: Net Migration = Next Year's Pop - (Current Pop - Deaths)
generate net_migration 			= next_pop_total  - (poptotal  - deaths)
generate net_migration_male 	= next_pop_male   - (popmale   - deathmale)
generate net_migration_female	= next_pop_female - (popfemale - deathfemale)



** 6. SPECIAL CASE: INFANTS (AGE 0) **
// * Compute sex-at-birth ratio (we need this as an approximation as we don't have births by sex)
// generate sbr = popmale / popfemale
// generate share_male = popmale / (popfemale + popmale)
// generate share_female = popfemale / (popfemale + popmale)
//
// * Note: For Age 0, the 'Current Pop' is actually the number of Births that year.
// replace net_migration        = next_pop_total  - (births			    - deaths) 		if age == 0
// replace net_migration_male   = next_pop_male   - (births * share_male   - deathmale) 	if age == 0
// replace net_migration_female = next_pop_female - (births * share_female - deathfemale)  if age == 0

//	NOTE: Using Births seems to overstate values, so we will use the same net migration values as for 1 year olds
	bysort iso3_code time: egen net_migration1 			= max(cond(age ==1, net_migration, .))
	bysort iso3_code time: egen net_migration_male1 	= max(cond(age ==1, net_migration_male, .))
	bysort iso3_code time: egen net_migration_female1 	= max(cond(age ==1, net_migration_female, .))

	replace net_migration 			= net_migration1 		if age == 0
	replace net_migration_male 		= net_migration_male1 	if age == 0
	replace net_migration_female 	= net_migration_female1 if age == 0
	
	drop net_migration1 net_migration_male1 net_migration_female1



** 7. CLEAN UP AND EXPORT **
rename time year
keep iso3_code year age net_migration_male net_migration_female
rename net_migration_male net_migration1
rename net_migration_female net_migration2
drop if year == 2023
drop if age < 0
reshape long net_migration, i(iso3_code year age) j(gender)
generate sex = "male"
replace  sex = "female" if gender == 2
generate variable = "net_migration"
reshape wide net_migration, i(iso3_code age gender sex) j(year)
rename net_migration* y*
sort iso3_code gender age
drop y2101 gender
rename iso3_code iso3


* Save the file
compress
save net_migration_data.dta, replace

* Loop over years and export each file
levelsof(iso3), local(countries)
foreach cnt of local countries {
	preserve
		keep if iso3 == "`cnt'"
		export delimited "net_migration_`cnt'.csv", replace
	restore
	} // end foreach yr
	

