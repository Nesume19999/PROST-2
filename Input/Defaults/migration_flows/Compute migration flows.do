/*******************************************************************************
UN Migration Flows

To generate longitudinal data from cohorts, we need migration flows (and not just net migration)


UN Population Division - International Migrant Stock

Link: 
https://www.un.org/development/desa/pd/content/international-migrant-stock


International Migrant Stock 2024 - Total, destination
Data Link: 
https://www.un.org/development/desa/pd/sites/www.un.org.development.desa.pd/files/undesa_pd_2024_ims_stock_by_sex_and_destination.xlsx

*******************************************************************************/


*! Net Migration Calculation Script - UN WPP Data
clear all
set more off

local homedir = "C:\Users\Duncan\OneDrive\World Bank\Generic\Input\Defaults\migration_flows"


********************************************************************************
	


// ONLY NEED TO RUN ONCE
/*
//	Import the Migration Flow Files and harmonize then
	cd "`homedir'"
	// Table 1
	import delimited "UN-Migration-Flows-Table1.csv", clear 
	// Merge in ISO3 codes and keep matches only (i.e., drop regional totals)
	merge 1:1 locationcode using "UN-iso3-codes.dta", keep(3) nogenerate 
	drop countryregion coverage datatype locationcode
	generate value = "Migrant stock"
	save "UN-Migration-Flows-Table1.dta", replace
	
	// Table 2
	import delimited "UN-Migration-Flows-Table2.csv", clear 
	// Merge in ISO3 codes and keep matches only (i.e., drop regional totals)
	merge 1:1 locationcode using "UN-iso3-codes.dta", keep(3) nogenerate 
	generate value = "Total Population"
	save "UN-Migration-Flows-Table2.dta", replace
	
	// Table 3
	import delimited "UN-Migration-Flows-Table3.csv", clear 
	// Merge in ISO3 codes and keep matches only (i.e., drop regional totals)
	merge 1:1 locationcode using "UN-iso3-codes.dta", keep(3) nogenerate 
	drop countryregion coverage datatype locationcode
	generate value = "International migrant stock as a percentage of the total population by sex"
	save "UN-Migration-Flows-Table3.dta", replace
	
	// Table 4
	import delimited "UN-Migration-Flows-Table4.csv", clear 
	// Merge in ISO3 codes and keep matches only (i.e., drop regional totals)
	merge 1:1 locationcode using "UN-iso3-codes.dta", keep(3) nogenerate 
	drop countryregion coverage datatype locationcode
	generate value = "Female migrants as a percentage of the international migrant stock by region"
	save "UN-Migration-Flows-Table4.dta", replace
	
	// Table 5
	import delimited "UN-Migration-Flows-Table5.csv", clear 
	// Merge in ISO3 codes and keep matches only (i.e., drop regional totals)
	merge 1:1 locationcode using "UN-iso3-codes.dta", keep(3) nogenerate 
	drop countryregion coverage datatype locationcode
	generate value = "Annual rate of change of the migrant stock by sex"
	save "UN-Migration-Flows-Table5.dta", replace
*/

********************************************************************************
//	Import the tabkes
	cd "`homedir'"
	use "UN-Migration-Flows-Table3.dta", clear
	keep country iso3 m2024 f2024 // b2024
	*rename b2024 mig_stock_both
	rename m2024 migrant_stock1 // Male
	rename f2024 migrant_stock2 // Female

// 	merge 1:1 iso3 using "UN-Migration-Flows-Table4.dta", nogenerate keepusing(y2024)
// 	rename y2024 mig_share_female
//	
	merge 1:1 iso3 using "UN-Migration-Flows-Table5.dta", nogenerate keepusing(m20202024 f20202024)
	*rename b20202024 mig_growth_both
	rename m20202024 migrant_growth1 // Male
	rename f20202024 migrant_growth2 // Female
	
//	Rehape the data for merging with gender-segregated data
	reshape long migrant_stock migrant_growth, i(iso3 country) j(gender)
	
	label define gender_lab 1 "Male" 2 "Female"
	label variable gender gender_lab
	

	
//	Clean and save the data
	order country iso3
	cd "`homedir'"
	save "UN-Migration-Flows.dta", replace
	
//	Export to CSV
	cd "`homedir'"
	export delimited using "UN-Migration-Flows.csv", replace


