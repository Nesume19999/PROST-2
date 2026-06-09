

// Note: The Age-specific Fertilities rates do not seem to match up perfectly with the Jan1 population data
// Note: So we will infer it based on births and the Jan1 population data

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\fertility\Input data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\fertility"
local popdir "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"

local tokeep = "asfr_inferred" // "asfr" for the original, "asfr_inferred" for the inferred


cd "`homedir'"

 // ONLY NEED TO RUN ONCE
** 0. IMPORT AND CLEAN BIRTHS DATA 
import delimited "WPP2024_Fertility_by_Age1.csv", clear 
drop if iso3_code == ""
keep if variant == "Medium"
keep if time >= 2024
keep location iso3_code time agegrp asfr births
rename agegrp age


** 1. MERGE IN POPULATION DATA
cd "`popdir'"
merge 1:1 iso3_code location time age using population_data_jan1.dta
keep if _merge ==3 
drop _merge

* Compute inferred fertlity rate
generate asfr_inferred = births / popfemale
replace asfr = asfr / 1000

* Cleanup
*keep iso3_code location time age asfr asfr_inferred births
keep iso3_code location time age asfr asfr_inferred poptotal popfemale births




* Save the file
cd "`homedir'"
compress
save inferred_fertility_rates.dta, replace
*/

** 2. CLEAN UP AND EXPORT **
cd "`homedir'"
use inferred_fertility_rates.dta, replace
rename `tokeep' fertility
keep iso3_code location time age fertility
generate sex = "female"
generate variable = "fertility"
rename time year
reshape wide fertility, i(iso3_code age sex) j(year)
rename fertility* y*
sort iso3_code age
order iso3 location variable age sex
rename iso3_code iso3


* Save the file
compress
cd "`homedir'"
save cleaned_fertility_data.dta, replace

* Loop over years and export each 

cd "`outdir'"
drop if sex == "total"
levelsof(iso3), local(countries)
foreach cnt of local countries {
	preserve
		keep if iso3 == "`cnt'"
		export delimited "fertility_`cnt'.csv", replace
	restore
	} // end foreach yr
	




