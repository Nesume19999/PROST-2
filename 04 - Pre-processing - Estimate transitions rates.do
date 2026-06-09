
/******************************************************************************* 
Title: 			Estimate transitions rates from longitudinal data
Author: 		Duncan MacDonald 
Date created: 	March 18th, 2026
Description:	For building PROST v2 pension model (Revised)


Transition out model: 
	cloglog transition_out c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.los_gap if den == 1, cluster(id) 
	
Transition in model: 
	cloglog transition_in c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.log_cod c.los_gap if dens == 0, cluster(id)
	
	
Note: This code uses gtools and ftools to speed up processing
Source: https://gtools.readthedocs.io/en/latest/
Source: https://github.com/sergiocorreia/ftools

Commands:
ssc install gtools
ssc install ftools


Note: Here we define deciles as the last known decile of the person as the decile 
	  they had for their entire career. 
	  That is, their most recent decile is their "true" decile.
			
*******************************************************************************/	

//	INITIALIZATION
	clear all

//	----------------------------------------------------------------------
//	RUTA LOCAL - carpeta del repositorio PROST-2 en tu PC
//	(clear all borra los globals, por eso se define en cada archivo)
//	----------------------------------------------------------------------
	global root   "C:/Users/WB542352/OneDrive - WBG/Documents/GitHub/PROST-2"
	global rawdir "${root}/Input"	// microdata cruda del cliente (solo preprocesamiento)
	pause on
	set trace off

//	Country iso3 code
	local country  = "MEX"

//	SET PARAMETERS, AND THE NAME OF FOLDER AND FILES OF THE EXERCISE:
	local homedir 		= "${rawdir}"
	local transdir		= "${root}/Input/Defaults/transitions"

//	Name of input data	
	local long_data  = "2 Input from client - longitudinal microdata about affiliates.dta"


//	Simulation parameters
	local years_avg   = 10  	// Number of years of back data that are averaged to generate (we use 1 right now to )
	local minimum_age = 15		// Minimum age to consider (some young ages don't have a lot of data)
	local samplesize  = 10		// Sample size of the projection database (100 is a full sample, 1 is a 1% sample) - [Only when testing]

	
//	Output model names	
	local job_exit_model 		= "job_exit_model_`country'_`years_avg'_final"
	local job_entry_model 		= "job_entry_model_`country'_`years_avg'_final"
	
	
//	Parameters of the current pension system
//	We need these as we compute transition rates as a function of time to retirement
	local retage_male = 65 					// Male retirement age
	local retage_female = 65				// Female retirement age
	local retcont_min = (750 / 52) * 12		// Minimum contribution threshold (in months)

	
********************************************************************************
// 	Open the longitudinal microdata about affiliates
	cd "`homedir'"
	use "`long_data'", clear
	
	
//	Get the latest year of the dataset
	summarize year
	local latest_year = r(max)
	local earliest_year = r(min)

// 	Sort the annual data into 5-year bands (to reduce noise)
	generate age = year - yob
	
//	Minor cleanup
	rename aux loa
	label variable loa "Length of affiliation (months)"
	
	
********************************************************************************
// 	There is too much data for the model to run in a reasonable time during testing
// 	We need to sample people, but they have multiple observations in the base dataset
//	[TODO: Consider a stratified sample]
	preserve
		tempfile sample_merge
		keep id
		duplicates drop
		sample `samplesize'
		generate sampled = 1
		save `sample_merge'
	restore

	//	Merge the sample back into the dataset to determine who to keep
	join sampled, from(`sample_merge') by(id) keep(1 3) nogenerate // ftools version of merge [faster]
	keep if sampled == 1
	drop sampled

********************************************************************************
//	Compute spells of unemployment and job tenure

//	Set up time series data
	generate date = ym(year, month)
	sort id date

//	Identify the start of a new spell (status change or new person)
	generate byte new_spell = (dens != dens[_n-1] | id != id[_n-1])

//	Create a unique ID for every single spell in the dataset
	generate spell_id = sum(new_spell)

//	Calculate the length of every spell (time-in-spell to date)
	bysort spell_id: generate total_spell_length = _N		// Total time in the spell
	bysort spell_id: generate spell_length = _n  			// time-in-spell to date
	
//  Log of spell duration
	generate log_spell_length = log(spell_length)


//	Compute contribution density
	generate contribution_density = los / loa
	
//	Compute log of contribution density
	generate log_cod = log(max(contribution_density, 0.001))
	
	
********************************************************************************
// Compute some pension-rule-specific indicators (forincusion into the model)	
	
// 	Months until reaching eligible retirement age
	generate age_gap = 0
	replace  age_gap = max(`retage_male'   - age, 0) * 12 if gender == 1 // Male
	replace  age_gap = max(`retage_female' - age, 0) * 12 if gender == 2 // Female
	
// 	Months of contributions requred to be eligible for an old-age pension
	generate los_gap = max(`retcont_min' - los, 0)
	
// 	As both age_gap and los_gap must be filled, we take the max for the model
	generate pension_gap = max(age_gap, los_gap)
	
	
	


********************************************************************************
//	Build a wage growth index from your own data (mean wage each year)
	bysort year: egen mean_wage_yr = mean(wage)			// Average wage in each year
	generate wage_relative_mean = wage / mean_wage_yr   // Compute the wage relative to the mean 
	sort id date										// Sort the data
	by id: carryforward wage_relative_mean, replace			// Carry the latest non-missing data forward
	*carryforward wage_relative_mean, replace			// Carry the latest non-missing data forward
	
	
//  Deciles (using faster gtools) [Compute using relative wages, so we don't need to index]
	gquantiles wage_decile_ref_last = wage_relative_mean if year == `latest_year' & month==12 , xtile nquantiles(10) by(year) 
	bysort id: egen wage_decile_ref = max(wage_decile_ref_last)
	drop wage_decile_ref_last
	
	
//	Compute a reference wage decile (for those people who are not working currently)
	generate wage_decile = wage_decile_ref
	
//	Fill in observed wage_decile with 0 when not working formally
	replace  wage_decile = 0 if dens ==0 // Unemployed or working informally
	
	
	
// 	Pre-processing (drop data and compute wage deciles)
	// Keep only the most recent years
	// Note: We do this only ater getting a person's wage_decile_ref
	keep if year > `latest_year'  - `years_avg'
	keep if age >= `minimum_age'


********************************************************************************
// 	Compute transition rates
	
// 	Set up the time series
	xtset id date
	
// 	Get the last period of deciles and wages
	generate next_decile  = f.wage_decile
	
// 	Compute the current and previous states	
	generate current_state	= (wage_decile > 0)	// Indicator of if person contributed
	generate next_state	  	= (next_decile > 0)	// Indicator of if person contributed
	
// 	Compute the transitions in and out of active contributions
	generate transition_in  = (current_state == 0 & next_state == 1) if current_state == 0	// Indicator: transitioned in 
	generate transition_out = (current_state == 1 & next_state == 0) if current_state == 1	// Indicator: transitioned out
	
//	Clean up transition rates at the end of the observation window
	replace transition_in  = . if year == `latest_year' & month == 12	
	replace transition_out = . if year == `latest_year' & month == 12
	
	
	


********************************************************************************
//	Estimating spell-dependent transition rates
//	Assume your data is in long format: id, month, employed (0/1), tenure_months
//	spell_length = consecutive months in the current state


//	Probability of losing a job (for those currently employed)
	cloglog transition_out c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.los_gap if den == 1, cluster(id) 
	cd "`transdir'"
	estimates save "`job_exit_model'", replace


********************************************************************************
// 	Probability of finding a job (for those currently unemployed)	
	cloglog transition_in c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.log_cod c.los_gap if dens == 0, cluster(id)
	cd "`transdir'"
	estimates save "`job_entry_model'", replace
	
	
	
********************************************************************************	




	
	
	
//	Country iso3 code
	local country  = "MEX"

//	SET PARAMETERS, AND THE NAME OF FOLDER AND FILES OF THE EXERCISE:
	local homedir 		= "${rawdir}"
	local transdir		= "${root}/Input/Defaults/transitions"

//	Name of input data	
	local long_data  = "2 Input from client - longitudinal microdata about affiliates.dta"


//	Simulation parameters
	local years_avg   = 10  	// Number of years of back data that are averaged to generate (we use 1 right now to )
	local minimum_age = 15		// Minimum age to consider (some young ages don't have a lot of data)
	local samplesize  = 10		// Sample size of the projection database (100 is a full sample, 1 is a 1% sample) - [Only when testing]

	
//	Output model names	
	local job_exit_model 		= "job_exit_model_`country'_`years_avg'_final"
	local job_entry_model 		= "job_entry_model_`country'_`years_avg'_final"	
	
	
//	Probability of losing a job (for those currently employed)
	cloglog transition_out c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.los_gap if den == 1 & year == 2020, cluster(id) 
	cd "`transdir'"
	estimates save "`job_exit_model'_2020", replace


********************************************************************************
// 	Probability of finding a job (for those currently unemployed)	
	cloglog transition_in c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.log_cod c.los_gap if dens == 0 & year == 2020, cluster(id)
	cd "`transdir'"
	estimates save "`job_entry_model'_2020", replace
	
	
	
// TODO: The job estimates are OK but not great. We could maybe improve these estimates

cd "${root}/Input/Defaults/transitions"
estimates use "job_entry_model_MEX_10_final"
estimates replay "job_entry_model_MEX_10_final"
capture drop entry_final
predict entry_final

estimates use "job_entry_model_MEX_10_final_2020"
estimates replay "job_entry_model_MEX_10_final_2020"
capture drop entry_final_2020
predict entry_final_2020
*hist entry_low_data


estimates use "job_entry_model_MEX_10_final_LOW_DATA"
estimates replay "job_entry_model_MEX_10_final_LOW_DATA"
capture drop entry_low_data
predict entry_low_data
*hist entry_low_data



*twoway (hist entry_final) (hist entry_low_data) if  dens == 0
twoway (hist entry_final, color(red)) (hist entry_final_2020, color(green)) (hist entry_low_data, color(blue)) if  dens == 0 & year == 2020, legend(label(1 "Full model") label(2 "2020 Data") label(3 "Low Data"))	

	






	