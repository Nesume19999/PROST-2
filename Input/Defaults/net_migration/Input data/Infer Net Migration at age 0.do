

// Note: We infer the net migration at birth by getting the difference between births and the population ta age 0
// Note: So we will infer it based on births and the Jan1 population data

local fertdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\fertility\Input data"
local outdir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\net_migration\Input data"
local popdir "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\population\Input data"




** 1. INFER MET MIGRATION AT AGE 0 **
cd "`popdir'"
use population_data_jan1.dta, replace
keep if age == 0

cd "`fertdir'"
merge 1:1 iso3_code location time using birth_data.dta, nogenerate
replace births = 0 if missing(births) // ONly for the end of the forecast horizon

// Compute the sex ratio
*generate sex_ratio = popmale / poptotal
generate sex_ratio = 1.05	// Usual sex ratio at birth

keep iso3_code location time age births poptotal sex_ratio
generate net_migration = poptotal - births
generate net_migrationfemale = net_migration * (1 / (1 + sex_ratio)) 	// Inferred Female 
generate net_migrationmale = net_migration - net_migrationfemale		// Inferred Male
drop net_migration

rename time year
reshape long net_migration, i(iso3_code location age year) j(sex) string
keep net_migration iso3_code location age sex year
reshape wide net_migration, i(iso3_code age sex) j(year)


rename net_migration* y*
generate variable = "net_migration"


sort iso3_code age
order iso3 location variable age sex
rename iso3_code iso3


* Save the file
compress
cd "`outdir'"
save inferred_net_migration_age_0.dta, replace




