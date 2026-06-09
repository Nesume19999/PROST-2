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
