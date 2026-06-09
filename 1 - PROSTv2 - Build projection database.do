/******************************************************************************* 
Title: 			Build projection dataset
Author: 		Duncan MacDonald 
Date created: 	March 27th, 2026
Description:	For building PROST v2 pension model (adjusted for April 2026 model concept)

Status variable
	- 1  = alive and affiliated
	- 2  = retired
	- 3  = disabled
	- 4  = widowed
	- 99 = dead
	
Note: This code uses gtools and ftools to speed up processing
Source: https://gtools.readthedocs.io/en/latest/
Source: https://github.com/sergiocorreia/ftools

Commands:
ssc install gtools
ssc install ftools

		
TODO: Adjust model to account for the quality of data
TODO: Add in DC plan
TODO: Add into an ado file
TODO: Create GUI
		
*******************************************************************************/	

//	INITIALIZATION
	clear all

//	----------------------------------------------------------------------
//	RUTA LOCAL - carpeta del repositorio PROST-2 en tu PC
//	(clear all borra los globals, por eso se define en cada archivo)
//	----------------------------------------------------------------------
	global root   "C:/Users/WB542352/OneDrive - WBG/Documents/GitHub/PROST-2"
	global rawdir "${root}/MEX"	// microdata cruda del cliente (solo preprocesamiento)
	pause off
	set trace off
	timer on 1

// 	SETS THE SEED OF THE RANDOM NUMBER GENERATOR
//	Note: Any seed works the same. 
//	The idea is to set it to one specific value so to have the same resuts when the model is re-run
	set seed 2
	
//	SPEED SETTINGS
	// Uses float variables rather than double - less space than double (increases speed)
	set type float	
	// Ensure that all processores are being used
	local max_processors = c(processors_max)
	set processors `max_processors'

//	SET THE SIMULATION NAME
	local simname 		= "Baseline"
	local country		= "MEX"
	
//	SET PARAMETERS, AND THE NAME OF FOLDER AND FILES OF THE EXERCISE:
	local indir 		= "${root}/Input"							// User inputs
	local outdir 		= "${root}/Output"							// Projection outputs
	local popdir 		= "${root}/Input/Defaults/population"		// Default population data
	local mortdir 		= "${root}/Input/Defaults/mortality"		// Default mortality data
	local affdir 		= "${root}/Input/Defaults/affiliation"		// Affiliation data
	local transdir 		= "${root}/Input/Defaults/transitions"		// Transition matrix
	local wagegrowdir 	= "${root}/Input/Defaults/wage_growth"		// Wage growth projections
	local lifecycledir 	= "${root}/Input/Defaults/lifecycle wages"	// Relative wage growth for different groups (age-gender-decile)


//	Names of input databases
 	local baseyear_data  	 = "baseyear_data_MEX.dta"			// Detailed affiliate data in the base year
	local pensioners_data	 = "pensioners_MEX.dta"				// Detailed pensioner data in the base year
	local affiliation_data 	 = "affiliation_MEX_10.csv"			// Affiliate rates derived from the longitudinal data
	local population_data 	 = "population_MEX.csv"				// Population projections
	local mortality_data	 = "mortality_MEX.csv"				// Mortality rates
	local decile_wage_data 	 = "decile_wages_MEX.csv"			// Decile wage distributions derived from baseyear_data (mean, sd, min, max) 
	*local transitions_data	 = "transitions_MEX_15_groups.dta"	// Wage dynamics transitions matrix
	local lm_assumptions	 = "labor_market_assumptions.csv"	// Labour market assumptions over the projection (turnover_target, emp_rate_growth)
	local index_assummptions = "indexation_assumptions_MEX.csv"	// Wage and Benefit Indexation Assumptions over the projection
	local wage_grow_data 	 = "cpi_MEX.csv"					// Assumed wage growth by year
	
//	Transition model data
	local job_exit_model 		= "job_exit_model_MEX_10_final" // "job_exit_model_MEX_10_last" // "job_exit_model_MEX_10_final"
	local job_entry_model 		= "job_entry_model_MEX_10_final" // "job_entry_model_MEX_10_last_cod_log" //  job_entry_model_MEX_10_final"

//	Wage model data
	local lifecycle_model 		= "lifecycle_wages_`country'" 	// Model estimates for wage growth (matches name saved by "05 - ... life cycle wage growth profiles.do")

	
	

//	Simulation parameters
	local baseyear = 2024
	local horizon = 80 // 80 				// Number of projection years (default is 80)
	local startyear = `baseyear' + 1		// First year of the projection
	local endyear = `baseyear' + `horizon'	// Last year of the projection
	local samplesize = 10					// Sample size of the projection database (100 is a full sample, 1 is a 1% sample)
	local max_eligibility_age = 75			// [User defined] Cut-off year by which people have no reasonable hope of acquiring more pension time
	local extended_output = 0				// Toggle on and off extended output (output of the entire simulation)
	local histograms = 0					// Toggle on and off histograms
	
	local working_age_min	= 15			// Minimum age to be considered working age
	local working_age_max	= 64			// Maximum age to be considered working age
	local wage_adjustment	= 9878.469 / 7048.628	// Wage adjustment to bring 2020 data to 2024 baseyear (monthly earnings growth from the ILO)
	



	
//	Labour market parameters
//	Note: the key anchors of emp_rate_growth and turnover_target are imported from user-maintained csv files

********************************************************************************
********************************************************************************
//	DB Pension policy parameters


//	The start and end years of the program
	local p_start_year   = 1900
	local p_end_year	 = 3000
	
//	Indicator if the pension system is open or closed to new affiliates
//	Note: Not currently used
	local p_open = 1	// 1 =  open, 0 = closed

//	Year of retirement
//	Note: This will be determined within the model
//	Note: Not currently used
	local p_retire_year = 2100
	

//	Minimum pensionable income (monthly)
//	Note: This is likely the minimum wage (MEX source: pensionarsemejor.com.mex)
	local p_min_income = 249 * 20	// Floor on earnings considered for pension calculations.

//	Maximum pensionable income (monthly)
	local p_max_income = 1000	// Ceiling on earnings considered for pension calculations.

	
//	Pension indexation rule
//	MPIIndexationRate(t) = θ_1 * Inflation(t-1) + θ_2 * RealWageGrowth(t-1) + θ_3 * AnchorVariable(t)
	local p_mpi_index_inflation_coeff = 1	// 	Inflation coefficient for indexing maximum pension 
	local p_mpi_index_realwage_coeff  = 1 	//	Real wage coefficient for indexing maximum pension 
	local p_mpi_index_anchor_coeff 	  = 1 	//	Anchor coefficient for indexing maximum pension 


//	Revalorization rate
//	ValorizedWage_i (r-j) = PensionableWage_i (r-j) * ∏_(m=r-j+1)^r [(1+ValorizationRate(m))] 
//	ValorizationRate(t) = β_1 * Inflation(t-1) + β_2 * RealWageGrowth(t-1)
	local p_revalor_inflation_coeff = 1		// 	Inflation coefficient for revalorization calculation
	local p_revalor_realwage_coeff 	= 1 	//	Real wage coefficient for revalorization calculation
	local p_revalor_anchor_coeff 	= 0 	//	Anchor coefficient for revalorization calculation

//	Reference Wage
//	ReferenceWage_i = 1/N ∑_(j∈SelectedYears) ▒〖ValorizedWage_i (j) 〗
	local ref_wage_n = 3	// How many years to considered
	local ref_wage_m = 100	// How many of the last years to consider
	local ref_wage_type = 1 // Type of calculation
	// 1 = Last N years before retirement: 
	// 2 = Best N years in the career: Highest N wages in the career
	// 3 = Best N years within the last M years: Highest N wages within last M years before retirement
		

// 	Retirement age path
// 	Note: Retirement age may evolve over time.
//	[TODO: Add retirement age according to life expectancy]
	local p_retage_male = 65			// Male: Regular retirement age
	local p_retage_early_male = 0		// Male: Earliest allowed retirement age (0 if not applicable)
	
	local p_retage_female = 65			// Female: Regular retirement age
	local p_retage_early_female = 0		// Female: Earliest allowed retirement age (0 if not applicable)

//  Optional rule linked to life expectancy:
//  RetirementAge(t) = RA_0 + γ(LE(t) - LE_0 )

//  Eligibility Conditions
//  Eligibility for retirement benefits typically requires both a minimum age and a minimum number of years of service.
//  Eligible_i = (Age_i (r) ≥ RetirementAge(r)) ∩ (YearsOfService_i (r) ≥ MinimumService)

// 	Minimum Service Requirement is the minimum number of credited service years required to qualify for a pension (in years).
	local p_min_service_req = (750 / 52)

//	Pension accrual rate (for each year of service)
	local p_accrual = 0.04
	
//	Maximum replacement rate	
	local p_accrual_max = 0.75
	local p_too_old_to_retire = 99	// Age at which people retire even if they have not maxed out their pension [Rough rule]

// 	δ (delta) — Early retirement penalty (the reduction applied per year of early retirement)
	local p_delta = 0.04
	
// 	λ (lambda) — Late retirement bonus (the increase applied per year of delayed retirement)
	local p_lambda = 0.04

//	Minimum guarenteed pensions (minimum monthly amounts)
//	Note: Minimum pension can differ by age, wage, and years of service (or the can be flat)
	local p_minpen_base 		= 2622	// Base minimum pension
	
//  Variation by age - minimum guarenteed pension
	local p_minpen_age			= 60	// Age at which the base minimum pension applies 
	local p_minpen_age_max		= 65	// Maximum age at which the base minimum pension applies 
	local p_minpen_age_step		= 1		// For applying stepwise functions (1 = full step, 2 = half step, 10 = 0.1 step, etc.)
	local p_minpen_age_lvl		= 38	// Increase in the monthly benefit accoridng to age (by level)
	local p_minpen_age_pct		= 0		// Increase in the monthly benefit accoridng to age (by percent)

//  Variation by contributions - minimum guarenteed pension
	local p_minpen_yos			= 20	// Service years at which the base minimum pension applies 
	local p_minpen_yos_max		= 25	// Maximum service years at which the base minimum pension applies
	local p_minpen_yos_step		= 2		// For applying stepwise functions (1 = full step, 2 = half step, 10 = 0.1 step, etc.)
	local p_minpen_yos_lvl		= 187	// Increase in the monthly benefit accoridng to service years (by level)
	local p_minpen_yos_pct		= 0		// Increase in the monthly benefit accoridng to service years (by percent)
	
//  Variation by wage - minimum guarenteed pension
	local p_minpen_refwage		= 3300.53	// Reference wage for determining minimum pension (e.g., minimum wage or UMA)
	local p_minpen_adj1			= 1			// Scalar multiplier on Minimum pension min
	local p_minpen_adj2			= 5			// Scalar multiplier on Minimum pension max
	local p_minpen_wage			= `p_minpen_adj1' * `p_minpen_refwage'	// Wage at which the base minimum pension applies 
	local p_minpen_wage_max		= `p_minpen_adj2' * `p_minpen_refwage'	// Maximum wage at which the base minimum pension applies
	local p_minpen_wage_step	= 1		// For applying stepwise functions (1 = full step, 2 = half step, 10 = 0.1 step, etc.)
	local p_minpen_wage_lvl		= 0		// Increase in the monthly benefit according to wage (by level)
	local p_minpen_wage_pct		= 0.30	// Increase in the monthly benefit according to wage (by percent)
	
//	Maximum pension amount
	local p_pension_max = .

//	Maximum pension: scaling factors for added years of service
	local p_maxpen_age_threshold = 65   // Age above which max pension increases
	local p_maxpen_age_scale     = 0    // Extra pension per year over threshold age
	local p_maxpen_yos_threshold = 30   // Service years above which max pension increases
	local p_maxpen_yos_scale     = 0    // Extra pension per year over threshold YOS
	
//	Lumpsum pension amounts
	local p_lumpsum_flag = 0			// Flag: are lumsum payouts given to retires with no pension eligibility
	local p_contribution_rate_ee = 0.00	// Contribution rate for pensions - employees
	local p_contribution_rate_er = 0.00	// Contribution rate for pensions - employers
	local p_lumpsum_interest = 0.00		// Interest rate paid for lumpsum payouts


	

//	[TODO: Ensure that years early is included in the pension calculation]
// 	YearsEarly_i = max(0, RetirementAge(r)-ActualRetirementAge_i )
// 	YearsLate_i = max(0, ActualRetirementAge_i-RetirementAge(r))
// 	Pension_(adj,i) = Pension_(base,i) * (1-δYearsEarly_i) * (1+λYearsLate_i )



// 	Minimum Pension in base year
// 	Minimum pensions are usually defined as a matrix depending on retirement age and years of service.
//	[TODO: Consider how to include this]


// After retirement, the pension evolves according to the indexation rule.
// Pension_i (t) = Pension_i (t-1) * (1 + PensionIndexationRate(t))


// Pension indexation rule
// PensionIndexationRate(t) = α_1 * Inflation(t-1) + α_2 * RealWageGrowth(t-1) + α_3 * AnchorVariable(t)
//	[TODO: Put in ability to define indexation across time - import a csv file]
	local pindex_inflation 	= 3.5	// Assumed annual inflation rate
	local pindex_realwage 	= 0	// Assumed annual real wage growth rate
	local pindex_anchor 	= 0	// Assumed annual anchor variable rate

	local alpha1 = 1	// Pension index coefficient on inflation
	local alpha2 = 1	// Pension index coefficient on real wages
	local alpha3 = 1	// Pension index coefficient on anchor variable

//	Lump sum calculations (for when pension eligibility is not met)
//  [TODO: Add in variables for lump-sum calculations, toggle, etc]


//	Retirement decision
	local p_discount_rate = 0.03   // Annual discount rate for NPV calculation



	
*quietly{	
********************************************************************************

********************************************************************************
//	STEP 1.0
//	Load the population projections into memory	
	// Open the population projections
	cd "`popdir'"
	import delimited "`population_data'", clear
	
	// Reshape to long
 	greshape long y, i(iso3 location variable age sex) j(year) // gtools version of reshape [faster]
	rename y pop
	replace pop = 1000 * pop
	
	// Generate a gender variables
	capture drop gender
	generate gender = .
	replace  gender = 1 if sex == "male"
	replace  gender = 2 if sex == "female"
	
	// Generate working age population
	generate working_age = 0
	replace  working_age = pop if age >= `working_age_min' & age <= `working_age_max'

	
	// Save the population data
	tempfile population_database
	save `population_database', replace
	quietly summarize year, meanonly
	local population_max_year = r(max)	// Last year with population data (for capping)


	// Collapse the data to get population totals
	collapse (sum) pop working_age, by(iso3 location variable year gender sex)
	
	// Save the population data -  by gender
	tempfile population_db_gender
	save `population_db_gender', replace
	
	// Collapse the data to get population totals
	collapse (sum) pop working_age, by(iso3 location variable year)
	
	// Save the population data -  by total
	tempfile population_db_total
	save `population_db_total', replace

********************************************************************************
//	STEP 1.1
//	Build the new affiliate database
// 	Note: Affiliates are generated RANDOMLY (stochastic process)

	// Import and save the affilation data
	cd "`affdir'"
	import delimited "`affiliation_data'", clear
	tempfile affiliation_rate
	save `affiliation_rate', replace


	// Open the population projections
	use `population_database', clear
	
	// Merge in the affiliation rates
	join affiliation_rate, from(`affiliation_rate') by(age gender) keep(1 3) nogenerate	// ftools version of merge [faster]
	replace affiliation_rate = 0 if missing(affiliation_rate) // Rates for the young and old are likely not provided
	
	// Compute the affiliation rate (note: population is reported in units)
	generate new_affiliates = round(affiliation_rate * pop, 1)
	keep if new_affiliates > 0
		
	// Expand the dataset
	expand new_affiliates
	
	// Determine the person's starting deciles
	// Assign wage decile randomly
	generate wage_decile = runiformint(1, 10)
	// Assign wage decile (within age and sex) to align with wage_decile
	generate wage_decile_age_sex = wage_decile
		
	// Cleanup
	keep age sex gender year wage_decile wage_decile_age_sex
	
	//	Save the database of generate affiliates
	tempfile affiliates
	save `affiliates', replace
	
	// Generate a new database of affiliates for each year (to be appended later on)
	// Note: When projection year exceeds population data, reuse the last available year's rates
	forvalues yr = `baseyear'/`endyear' {
		local yr_cap = min(`yr', `population_max_year')
		preserve
			// Keep only one year (capped to last available population year)
			keep if year == `yr_cap'
			replace year = `yr'		// Restore the actual projection year label

			// Only take a sample the of affiliates [TODO: Consider a stratified sample]
			sample `samplesize'

			// Generate a sampling weight [TODO: Change if we take a stratified sample]
			generate wgt = 100 / `samplesize'

			// Save the dataset
			tempfile affiliates`yr'
			save `affiliates`yr'', replace
			display "Generated `affiliates`yr''"
		restore
		} // end forvalues i
		
	
********************************************************************************
//	STEP 1.2
//	Load the wage growth projections into memory
	cd "`wagegrowdir'"
	import delimited "`wage_grow_data'", clear
	rename year year_merge
	tempfile wage_growth_database
	save `wage_growth_database', replace
	quietly summarize year_merge, meanonly
	local wage_growth_max_year = r(max)		// Last year with wage growth data (for capping)
	
	

********************************************************************************
//	STEP 1.3
//	Load the pensioners database into memory
	cd "`indir'"
	use "`pensioners_data'", clear
	tempfile pensioners_database
	save `pensioners_database', replace	

// 	Pension type 
//	Note: This is very Mexico specific
// 	B = Old-age DB 
// 	C = Disability DB
// 	D = Survivor DB
// 	E = Old-age DC
// 	F = Disability DC
// 	G = Survivor DC


********************************************************************************
//	STEP 1.4
	//	Load the mortality rates database into memory
	cd "`mortdir'"
	import delimited "`mortality_data'", clear
	
	// Reshape to long
	greshape long y, i(iso3 location variable age sex) j(year_merge) // gtools version of reshape [faster]
	rename y mortality
	
	// Generate a gender variables
	capture drop gender
	generate gender = .
	replace  gender = 1 if sex == "male"
	replace  gender = 2 if sex == "female"
	drop sex
	
	//	Save the mortalty data
	tempfile mortality_database
	save `mortality_database', replace
	quietly summarize year, meanonly
	local mortality_max_year = r(max)		// Last year with mortality data (for capping)
	
	



********************************************************************************
//	STEP 1.5
//	Load the labour market assumptions into memory
	cd "`indir'"
	import delimited "`lm_assumptions'", clear
	tempfile labor_market_assumptions_data
	save `labor_market_assumptions_data', replace
	
//	Save the annual data as locals
//	When data is unavailable beyond its last year, carry forward the last known value
	local turnover_last = .
	local emp_rate_last = .
	forvalues yr = `startyear'/`endyear' {
		quietly summarize turnover_target if year == `yr'
		if r(N) > 0 {
			local turnover_`yr' = r(mean)
			local turnover_last  = r(mean)
		}
		else {
			local turnover_`yr' = `turnover_last'
		}
		quietly summarize emp_rate_growth if year == `yr'
		if r(N) > 0 {
			local emp_rate_`yr' = r(mean)
			local emp_rate_last  = r(mean)
		}
		else {
			local emp_rate_`yr' = `emp_rate_last'
		}
		}

	
********************************************************************************
//	STEP 1.6
//	Load the labour market assumptions into memory
	cd "`transdir'"
	
	// Load the job entry probabilities into memory
	estimates use "`job_exit_model'"
	estimates store job_exit_stored
	
	// Load the job exit probabilities into memory
	estimates use "`job_entry_model'"
	estimates store job_entry_stored
	
	
********************************************************************************
//	STEP 1.7
//	Load the lifecycle wage growth rates into memory
	cd "`lifecycledir'"
	estimates use "`lifecycle_model'"
	estimates store lifecycle_stored
	
	
********************************************************************************
//	STEP 1.8
//	Load the indexation assumptions into memory
	cd "`indir'"
	import delimited "`index_assummptions'", clear
	rename year year_merge
	tempfile indexation_database
	save `indexation_database', replace
	quietly summarize year_merge, meanonly
	local indexation_max_year = r(max)		// Last year with indexation data (for capping)
	
	
********************************************************************************
//	STEP 1.9
//	Create empty reporting files (for filling with data)
	
	
	**********
	// Reporting: make tempfile for inyear affiliate  - TOTALS
	tempfile inyear_affiliate_reporting_tot
	preserve
		clear
		save `inyear_affiliate_reporting_tot', emptyok replace
	restore
	
	**********
	// Reporting: make tempfile for inyear affiliate reporting - BREAKDOWNS
	tempfile inyear_affiliate_reporting
	preserve
		clear
		save `inyear_affiliate_reporting', emptyok replace
	restore

	
	
	**********
	// Reporting: make tempfile for inyear pension reporting - TOTALS
	tempfile inyear_pension_reporting_tot
	preserve
		clear
		save `inyear_pension_reporting_tot', emptyok replace
	restore
	
	**********
	// Reporting: make tempfile for inyear pension reporting - BREAKDOWNS
	tempfile inyear_pension_reporting
	preserve
		clear
		save `inyear_pension_reporting', emptyok replace
	restore
	




********************************************************************************
// 	STEP 2
// 	Set-up the baseyear database

//	Project the database
//	Open the baseyear microdata
	cd "`indir'"
	use "`baseyear_data'",clear

	
	**********
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

	
	// Generate a sampling weight [TODO: Change if we take a stratified sample]
	generate wgt = 100 / `samplesize'	

	
	
	**********
	//	Grow the last year of the affiliate database to the base year
	replace year = `baseyear'
	replace wage = wage * `wage_adjustment'
	// TODO: Adjust the iacc variable [talk to Marola and Asta on how to best do this]
	

	
	
	
	
	**********
	//	Define some reporting variables
	generate new_affiliate_flag   = .			// Flag for new affiliates
	generate deathyear  		  = .			// Year person died
	generate wage_at_death 		  = .			// Person's wage at death
	generate contribution_density = los / loa	// Contribution density
	generate birthmonth = runiformint(1, 12)	// Month someone was born (randomly assigned)
	generate deathmonth = runiformint(1, 12) 	// Month person died (randomly assigned)



	
 
	**********
	// [Sanity check: Output histograms of contribution density by decile]
	// Save histogram to compare with simulated density in the last year
	if `histograms' == 1 {
		histogram contribution_density if month == 12, name(cod_baseyear, replace) yscale(range(0 5))
		histogram contribution_density if month == 12, by(wage_decile) name(cod_by_decile_baseyear, replace) yscale(range(0 15))
		} // end if histograms
	
	**********
	// Placeholder: Affiliate's pension reference wage (starts as their wage)
	capture drop reference_wage
	generate reference_wage = wage
	
	//	Placeholder: The N best years of earnings
	// 	2 = Best N years in the career: Highest N wages in the career
	if `ref_wage_type' == 2   {
		forvalues i = 1/`ref_wage_n' {
			generate bestwage`i' = 0
			} // end forvalues i
		} // end if `ref_wage_type' == 2 
		
	//	Placeholder: The N best years of earnings and the year of the best wage
	// 	3 = Best N years within the last M years: Highest N wages within last M years before retirement
	if  `ref_wage_type' == 3  {
		forvalues i = 1/`ref_wage_n' {
			generate bestwage`i' = 0
			generate bestyear`i' = 0
			} // end forvalues i
		} // end if `ref_wage_type' == 3
		
			
	
	**********
	// Placeholder: Variables for determining transition rates
	generate age_gap = .					// Years until eligible for pension (on basis of age)
	generate los_gap = .					// Years until eligible for pension (on basis of service)
	generate pension_gap = .				// Years until eligible for pension (on basis of service or age, whichever is binding)
	generate implied_retage = .				// Implied age that person would be eligible for retirement (if fully contributing)
	generate group = .						// Merging group (1 = age constrainted, 2 = service constrained, 3 = no hope)
	generate age_merge = .					// For merging to transitions database (that has 3 groups in it) 
	generate service_gap = .				// For merging to transitions database (that has 3 groups in it) 
	generate exiter = .						// Flag: 1 = exiting formal work
	generate reentrant = .					// Flag: 1 = reentering formal work
	generate new_affiliate = .				// Flag: 1 = entering formal work for the first time


	

	**********
	// Placeholder: Wage distribution variables
	generate wage_mean_decile = .			// Mean by decile
	generate wage_sd_decile   = .			// Standard deviation by decile
	generate wage_max_decile  = . 			// Minimum by decile
	generate wage_min_decile  = .			// Maximum by decile
	generate wage_change	  = .			// Flag: 1 = wage changed that period (for workers)
	generate wage_ref		  = .			// Reference wage for those that lost their job (model assumed they come back to the same wage) 
	generate sim_wage_growth  = .			// Simulated wage_growth after adjusting for relative growth (age-sex-decile) 
	
	
	**********
	//	Placeholders: Pension eligibilty
	generate pension_elig_mincont = 0		// Minimum contribution
	generate pension_elig_delta   = 0		// Early retirment penalty
	generate pension_elig_early   = 0 		// Early retirement restirctions
	generate pension_elig		  = 0 		// Overall eligibility

	
	**********
	// Placeholder: Pension benefits
	generate yos 					= .		// Length of service (in years)
	generate years_early 			= .		// Number of years before regular retirement age
	generate years_late 			= .		// Number of years after regular retirement age
	generate replacement_rate		= .		// Calculated pension replacement rate
	generate pension_benefit_base 	= .		// Monthly pension benefit (before applying minmax)
	generate pension_benefit		= .		// Monthly pension benefit
	generate pension_minpen			= . 	// Minimum pension amount
	generate pension_maxpen			= .		// Maximum pension amount
	generate pension_lumpsum		= .		// Lumpsum amount for those who retire with no pension eligibility
	generate retire_year			= .		// Year retired
	generate retire_month			= .		// Month retired
	generate covered_wage			= .		// Covered wage used for pension benefit calculations.
	
	
	**********
	// Update variables for determining labour market conditions
	
	// Merge in the labour market assumptions
	capture drop turnover_target
	capture drop emp_rate_growth
	join emp_rate_growth turnover_target, from(`labor_market_assumptions_data') by(year) keep(1 3) nogenerate	// ftools version of merge [faster]
	local turnover_target = turnover_target		// Easier to have these as locals than as variables [only works if we only have one year in the DB]
	local emp_rate_growth = emp_rate_growth		// Easier to have these as locals than as variables [only works if we only have one year in the DB]


	
	// Store the population and employment totals as well as the total flows
	tempvar samp
	tempvar emp
	tempvar reentrants
	tempvar affiliates
	tempvar new_affiliates
	tempvar exiters

	
	// Note: We use this method do that we can disaggregate results by gender-age-decile (if we want to)
	gegen `samp' 	  		= count(dens)  		  	// Sample population count
	gegen `emp'  	  		= sum(dens)    		   	// Employment count
	gegen `reentrants'  	= sum(reentrant)      	// Number of re-entrants
	gegen `affiliates'		= sum(status!=99)		// Number of total affilates
	gegen `new_affiliates'  = sum(new_affiliate)  	// Number of new affiliates
	gegen `exiters'  		= sum(exiter)  		  	// Number of exiters

	
	// This is mostly for reporting (and for adjusting transition rates)
	generate sample_pop 	 	= `samp' / 12						// Annual sample population count
	generate affiliates			= `affiliates' / 12					// Number of affilates
	generate employment      	= `emp'	/ 12						// Number of affiliates who are contributing ("working")
	generate employment_rate 	= 100 * employment / affiliates		// "Employment rate": Share of affiliates who are working
	generate unemployment    	= affiliates - employment			// Number of affiliates who are not contributing ("not working")
	generate reentrants      	= `reentrants'						// Number of re-entrants
	generate new_affiliates  	= `new_affiliates'					// Number of new affiliates
	generate exiters 		 	= `exiters'							// Number of exiters
	generate exits_target 	 	= (`turnover_target'/ 100) * affiliates / 2 // Target number of exists (assuming inflows match outflows)	
	generate reentrants_target 	= exits_target 						// Target number of re-entrants (assuming inflows match outflows)
	generate inflow_adjustment = 1									// Adjustment to ensure inflows match labour market assumptions (none in baseyear)
	generate outflow_adjustment = 1									// Adjustment to ensure outflows match labour market assumptions (none in baseyear)
	generate expected_reentrants = .
	generate expected_exits = .
	generate transition_in = .
	generate transition_out = .
	generate log_cod = log(max(contribution_density, 0.001))

	//	Store the baseline employment rate (for targeting)
	local target_emp_rate_last     = employment_rate / 100				// Baseline employment rate


	// Compute inflow and outflow rates
	// Note: We do not include new_affiliates in the inflow rate as they do not come from the stock of non-contributing affilates
	generate inflow_rate   = 100 * reentrants / unemployment 					// Share of "unemployed" flowing into "employment"
	generate outflow_rate  = 100 * exiters / employment							// Share of "employed" flowing into "unemployment"
	generate turnover_rate = 100 * (exiters + reentrants) / (affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
 
	

	
	**********
	// Reporting: make tempfile for EXTENDED OUTPUT inyear affiliate reporting
	if `extended_output' == 1 {
		tempfile extended_output_data
		// Start by saving the baseyear
		save `extended_output_data', emptyok replace
		} // end if extedned _output





********************************************************************************
********************************************************************************
//	Project the database



	****************************************************************************
	****************************************************************************
	****************************************************************************
	****************************************************************************
	****************************************************************************
//	Affiliates: Loop over the projection period
	forvalues yr = `startyear'/`endyear' {
		
		// Save the last row of the dataset for later (when adding new ID numbers)
		local last_row = _N
		
		// Record the previous year
		local lastyear = `yr' - 1

	
		*******************
		//	Stage 1 - Bring in the new affiliates
		//	Note: We start with the baseline observations and append the projected new affiliates
		display " "
		display "Adding new affiliates from `affiliates`yr''"
		append using `affiliates`yr''

		// Give new affiliates a new id number
// 		summarize id, meanonly
// 		local max_id = r(max)
		local max_id = id[`last_row']
		replace new_affiliate_flag = `yr' if missing(id)
		replace new_affiliate = 0
		replace new_affiliate = 1		if new_affiliate_flag == `yr'	// Flag for when someone becomes a new affiliate
		replace id = `max_id' + (_n - `last_row') if missing(id)			


		// Clean up the value for new affiliates
		// New affiliates start in first month of the year 
		replace yob = year - age 				if new_affiliate_flag == `yr'
		replace birthmonth = runiformint(1, 12) if new_affiliate_flag == `yr'   	// Randomly assign a birth month
		replace deathmonth = runiformint(1, 12) if new_affiliate_flag == `yr'		// Randomly assign a birth month (destiny)
		replace status = 1  	 				if new_affiliate_flag == `yr'		// Everyone starts out alive
		replace wage_decile_ref = wage_decile  	if new_affiliate_flag == `yr'		// Everyone is given a wage decile ot start
		replace month = 1  		 				if new_affiliate_flag == `yr'		// New affiliates start in first month of the year  
		// Note: As new affiliated are created before we move the data forward, that start with zero values (which are then incremented later on)
		replace los = 0 		 				if new_affiliate_flag == `yr'	 	// Length of service (months)  
		replace loa = 0 						if new_affiliate_flag == `yr'		// Length of affiliation (months) 
		replace spell_length = 0				if new_affiliate_flag == `yr'		// Duration in job or unemployment (months)
		replace dens = 1						if new_affiliate_flag == `yr'		// Flag: Contirbuting this month? 
		replace contribution_density = 1		if new_affiliate_flag == `yr'		// Initial density is 1 until it is updated
		replace log_cod = 0 					if new_affiliate_flag == `yr'		// Initial LN(density) is 0 until it is updated


		
		*******************
		//	Stage 2 - Project existing dataset forward
		// 	Project the last observation for each individual forward
		// 	Note: At this point we have new affiliates for the new year, but not yet the existing population

		//	Pull forward the last month of observations into the new year
		capture drop expanded
		expand 2 if year == `lastyear' & month == 12 , generate(expanded)	
		replace month = 1    if expanded
		replace year  = `yr' if expanded
		
		//	Project for the rest of the months in the year
		capture drop to_expand
		generate to_expand = 0
		replace  to_expand = 13 - month if year == `yr'
		expand to_expand
		drop to_expand
		
		//	Rename the months in the expanded dataset to cover the year
		bysort id year: replace month = (month - 1) + _n if year == `yr'
		
		//	Copy the last month of the last year (and save it as month 0, so we can use it in our time series data)
		capture drop last_obs_copy
		expand 2 if (year == `lastyear' & month == 12) | (new_affiliate_flag == `yr' & month == 12) , generate(last_obs_copy)	
		replace month = 0    if last_obs_copy 
		replace year  = `yr' if last_obs_copy
		
	
		// Update the labour market assumptions
// 		capture drop turnover_target
// 		capture drop emp_rate_growth
// 		join emp_rate_growth turnover_target, from(`labor_market_assumptions_data') by(year) keep(1 3) nogenerate	// ftools version of merge [faster]
// 		local turnover_target = turnover_target		// Easier to have these as locals than as variables [only works if we only have one year in the DB]
// 		local emp_rate_growth = emp_rate_growth		// Easier to have these as locals than as variables [only works if we only have one year in the DB]
		local turnover_target = `turnover_`yr''
		local emp_rate_growth = `emp_rate_`yr''



		*******************
		//	Stage 3 - Compute the variables that we need and then drop the previous year
		//	Note: We do this for computational reasons (otherwise this takes way too long to run)
		
		// Get the average wage of the previous year's data
		// Note: This is used later on for a macro adjustment of wages to fit user-defined wage growth
		quietly summarize wage if year == `yr' - 1
		local old_wage = r(mean)

		// Keep only the current year
		keep if year == `yr'
		
		
		// Update person's age
		// [TODO: For computational reasons, everybody ages in January, do we want to change this?]
		// [TODO: Check that we need the if statment status != 99 depending on how we deal with dead people]
		*replace age = age + 1 if status != 99	// Update age if person is not dead
		// Note: Moved to the month loop
		
		
		// Compute some pension-rule-specific indicators (for determining which transition matrix to use)	
		// Months until reaching eligible retirement age
		replace  age_gap = max(`p_retage_male'   - age, 0) * 12 if gender == 1 // Male
		replace  age_gap = max(`p_retage_female' - age, 0) * 12 if gender == 2 // Female
		
		// Months of contributions requred to be eligible for an old-age pension
		replace los_gap = max(12 * `p_min_service_req' - los, 0)
		replace pension_gap = max(age_gap, los_gap)
		
		// Implied age that person would be eligible for retirement
		replace implied_retage = age + (los_gap / 12)
		
		// Update the merging group
		// Group 1 : Worker will accumulate enough service time before retirement
		// Group 2 : Worker will not accumulate enough service time before normal retirement, but can work longer and be eligible
		// Group 3 : Worker will not accumulate enough service time before normal retirement, and cannot reasonably work longer and be eligible
		replace group = 1 if age_gap >= los_gap												
		replace group = 2 if age_gap <  los_gap & implied_retage <= `max_eligibility_age'	
		replace group = 3 if age_gap <  los_gap & implied_retage >  `max_eligibility_age'	
		
		// Update the merge in variables (depending on which group a person is in)
		replace age_merge = .
		replace age_merge = age   if group == 1
		replace service_gap = .
		replace service_gap = ceil(los_gap / 12) if group == 2
		
		
		*******************
		//	Stage 4 - Determine mortality
		
		// 	Merge in mortality data
		noisily display " "
		noisily display "Merging in mortality rates..."
		capture drop mortality
		// Cap merge year so projection years beyond data use the last available rates
		capture drop year_merge
		generate year_merge = min(year, `mortality_max_year')
		join mortality, from(`mortality_database') by(gender age year_merge) keep(1 3) nogenerate	// ftools version of merge [faster]
		drop year_merge

		// Dead people don't have a mortality rate
		replace mortality = . if status == 99
		
		// Sample probability of dying
		tempvar randnum_mortality
		generate `randnum_mortality' = runiform()

		
		
		*******************
		//	Stage 5 - Merge in transitions and wage dynamics
		// 	Note: At this point, we have a new year of observations, but with the same wage as the previous year
		
		*******************
		// Store the mean and sd of wages by decile and sample to give the wages to new entrants
		tempvar wage_mean
		tempvar wage_sd
		tempvar wage_min
		tempvar wage_max
		
		// Note: We use reference deciles here so that out of work reentrants also have wage distribtuions
		// Note: This works because wages are missing for the out-of-work
		gegen `wage_mean' = mean(wage)  , by(wage_decile_ref)	// Mean by decile
		gegen `wage_sd'   = sd(wage)    , by(wage_decile_ref) 	// Standard deviation by decile
		gegen `wage_min'  = min(wage)   , by(wage_decile_ref)	// Minimum by decile
		gegen `wage_max'  = max(wage)   , by(wage_decile_ref)	// Maximum by decile
		
		// This is mostly for reporting
		replace  wage_mean_decile = `wage_mean'				// Mean by decile
		replace  wage_sd_decile   = `wage_sd'				// Standard deviation by decile
		replace  wage_min_decile  = `wage_min' 				// Minimum by decile
		replace  wage_max_decile  = `wage_max'				// Maximum by decile
		*******************
		
		
		//	Compute probability of transitioning out of work
		// Note: Function of age, gender, job tenure, los_gap and wage decile
		estimates restore job_exit_stored	
		predict job_exit_predict, xb
		replace transition_out = 1 - exp(-exp(job_exit_predict))
		drop job_exit_predict
		
		//	Compute probability of transitioning into of work
		// Note: Function of age, gender, unemploment duration, log_cod, los_gap and wage decile
		estimates restore job_entry_stored	
		predict job_entry_predict, xb
		replace transition_in = 1 - exp(-exp(job_entry_predict)) 
		drop job_entry_predict 
		
		
// 		**********
// 		// Compute probability of transitioning out of work
// 		// Note: Function of age, gender, job tenure, and wage decile
// 		// Note: We set up our prediction and then update it in the monthly loop
//		
// 		// Restore the estimates
// 		estimates restore job_exit_stored
// 		matrix b_exit   = e(b)          // Row vector of exit model coefficients
// 		local exit_vars = e(depvar)     // Get variable list from the model
// 		// Extract the coefficient on spell_length:
// 		local b_exit_spell  = b_exit[1, colnumb(b_exit,  "spell_length")]
// 		// Predict exit probabilities using current spell_length:
// 		capture drop xb_exit_base
// 		predict xb_exit_base,  xb     	// Compute once per year for the full dataset
// 		replace transition_out = 1 - exp(-exp(xb_exit_base))
//
//		
//		
// 		**********
// 		// Compute probability of transitioning into of work
// 		// Note: Function of age, gender, unemploment duration, and wage decile
// 		// Note: We set up our prediction and then update it in the monthly loop
//		
// 		// Restore the estimates
// 		estimates restore job_entry_stored
// 		matrix b_entry   = e(b)         // Row vector of entry model coefficients
// 		local entry_vars = e(depvar)    // Get variable list from the model
// 		// Extract the coefficient on spell_length:
// 		local b_entry_spell = b_entry[1, colnumb(b_entry, "spell_length")]
// 		// Predict entry probabilities using current spell_length:		
// 		capture drop xb_entry_base
// 		predict xb_entry_base, xb     	// Compute once per year for the full dataset
// 		replace transition_in = 1 - exp(-exp(xb_entry_base)) 
				
		
		**********
		// Adjust transition rates to ensure that the employment rate follows the growth trajectory
		noisily display " "
		noisily display "Adjusting transition rates to match labour market path..."
		
		**********
		// Update population to account for new affiliates
		tempvar affiliates
		gegen `affiliates' 	  	= count(status!=99)  		 if month > 0   //, by(wage_decile_ref)	// Sample population count
		replace affiliates 	 	= `affiliates' / 12						// Total number of affiliates
		
		**********
		// Compute inflow and outflow targets:
		quietly summarize new_affiliate if month == 1
		local delta_affiliates = r(sum)							// Number of new affiliates (who count towards inflows)	
		
		// Get the current employment rate
		quietly summarize dens if month == 1
		local current_emp_rate = r(mean)
		
		// Compute target flows in and out of employment
		local target_emp_rate 	  	= `target_emp_rate_last' + (`emp_rate_growth' / 100)	// The global target employment rate 
		local target_emp_rate_last 	= `target_emp_rate' 									// Store the previous target employment rate 
		local delta_employment      = (`target_emp_rate' - `current_emp_rate') * affiliates	// Number of jobs added 
		local gross_flows      		= (`turnover_target' / 100) * affiliates * 12   		// Number of people changing states (annual)
		local balancing_exits 		= min((`gross_flows' + `delta_employment') / 2, 0)		// Balancing exits   (when entries are constrained)
		local balancing_entry 		= min((`gross_flows' - `delta_employment') / 2, 0)		// Balancing entries (when exits are constrained)

		
		**********
		// Adjust outflow rates:
		
		// Update exits_target to hit employment and turnover targets 
		replace exits_target = max((`gross_flows' - `delta_employment') / 2	 - `balancing_exits', 0)

		// Get the unadjusted expected number of exits (sum of transition_out for those working)
		tempvar expected_exits 
		gegen `expected_exits' = sum(transition_out if dens == 1 & month > 0) 
		replace expected_exits = `expected_exits'
		
		// Update transition_out rate adjustment based on exits target
		replace outflow_adjustment = exits_target / `expected_exits'
		replace transition_out = transition_out * outflow_adjustment
	
		
		**********
		// Adjust inflow rates:
		
		// Update reentrants_target to hit employment and turnover targets  
		replace reentrants_target = max((`gross_flows' + `delta_employment') / 2 - `balancing_entry', 0)	

		// Get the unadjusted expected number of re-entrants (sum of transition_in for those not working)
		tempvar expected_reentrants 
		gegen `expected_reentrants' = sum(transition_in if dens == 0 & month > 0 ) 
		replace expected_reentrants = `expected_reentrants'

		// Update transition_out rate adjustment based on exits target
		replace inflow_adjustment = reentrants_target / `expected_reentrants'
		replace transition_in = transition_in * inflow_adjustment
		
		
		**********
		// Apply the transition probabilities
		noisily display " "
		noisily display "Determining transitions in and out of work and implementing wage growth..."
		noisily display " "
		noisily display "Implementing wage growth dynamics..."
		noisily display " "
		noisily display "Assigning wages to labour market entrants..."
		
		// Replace the month and year of the last month of the last year now that we have trimmed the data down
		// Note: we do this for the tsset, and then revert
		replace year  = `lastyear' 	if month == 0 
		replace month = 12    		if month == 0 
		
		// Set up the data as time series data
		// Note: We have to do this each year because we are adding new afifliates 
		// 		 each year that need to be included in the time series panel
		capture drop date
		generate date = ym(year, month)
		tsset id date
		*sort id date 
		
		
		// Switch month and year back
		// Note: we do this for the tsset, and then revert
		replace month = 0    	if year  == `lastyear'
		replace year  = `yr' 	if month == 0 
		
		
//		Note: This code is faster but it involves more hardcoding of the model into the PROST model (which we maybe don't want) 
// 		**********
// 		// Compute probability of transitioning out of work
// 		// Note: Function of age, gender, job tenure, and wage decile
// 		// cloglog transition_out c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.los_gap if den == 1, cluster(id) 
// 		// Note: We set up our prediction and then update it in the monthly loop
//		
// 		// Restore the estimates
// 		estimates restore job_exit_stored
// 		matrix b_exit   = e(b)          // Row vector of exit model coefficients
// 		local exit_vars = e(depvar)     // Get variable list from the model
// 		// Extract the coefficient on spell_length:
// 		local b_exit_spell  = b_exit[1, colnumb(b_exit,  "spell_length")]
// 		// Predict exit probabilities using current spell_length:
// 		capture drop xb_exit_base
// 		predict xb_exit_base,  xb     	// Compute ONCE for the full dataset
//		
//		
// 		**********
// 		// Compute probability of transitioning into of work
// 		// Note: Function of age, gender, unemploment duration, and wage decile
// 		// cloglog transition_in c.spell_length##i.wage_decile_ref c.age##c.age i.gender c.log_cod c.los_gap if dens == 0, cluster(id)
// 		// Note: We set up our prediction and then update it in the monthly loop
//		
// 		// Restore the estimates
// 		estimates restore job_entry_stored
// 		matrix b_entry   = e(b)         // Row vector of entry model coefficients
// 		local entry_vars = e(depvar)    // Get variable list from the model
// 		// Extract the coefficient on spell_length:
// 		local b_entry_spell = b_entry[1, colnumb(b_entry, "spell_length")]
// 		// Predict entry probabilities using current spell_length:		
// 		capture drop xb_entry_base
// 		predict xb_entry_base, xb     	// Compute onceoer year for the full dataset


		

		
		************************************************************************
		************************************************************************
		************************************************************************
		// Loop across the months to update transitions and wages
		forvalues month = 1/12 {	
			// Update age (based on month)
			replace age = age + 1 if birthmonth == `month' & status != 99
			
			// Update mortality (based on month)
			replace status = 99 if mortality > `randnum_mortality' & deathmonth == `month'
			
			//	Update transition probabilities using a model approach 
			//	Include job tenure and unemployment spells when determining transition rates
			
			// Use the spell length from last month to determine transition probabilities for this month
			replace spell_length = l.spell_length if month == `month'
			
			// Compute probability of transitioning out of work
			// Note: Function of age, gender, job tenure, and wage decile
			estimates restore job_exit_stored	
			predict job_exit_predict, xb
			replace transition_out = 1 - exp(-exp(job_exit_predict))     if month == `month'
			replace transition_out = transition_out * outflow_adjustment if month == `month' // Anchor outflows to annual targets
			drop job_exit_predict
			
			// Compute probability of transitioning into of work
			// Note: Function of age, gender, unemploment duration, and wage decile
			estimates restore job_entry_stored	
			predict job_entry_predict, xb
			replace transition_in = 1 - exp(-exp(job_entry_predict))    if month == `month' 
			replace transition_in = transition_in * inflow_adjustment   if month == `month' // Anchor inflows to annual targets
			drop job_entry_predict 


// 			// Update transition probabilities - only the spell_length component:
// 			generate xb_exit  = xb_exit_base  + `b_exit_spell'  * (spell_length - l.spell_length)
// 			generate xb_entry = xb_entry_base + `b_entry_spell' * (spell_length - l.spell_length)
// 			replace transition_out = 1 - exp(-exp(xb_exit))  if month == `month'
// 			replace transition_in  = 1 - exp(-exp(xb_entry)) if month == `month'
// 			drop xb_exit xb_entry
			
		
			*******************		
			// Ensure new affiliate consistency
			// Right now: Everybody becomes a new affiliate in Janaury
			*replace new_affiliate = 0		if month != 1
			
			// Record the data from the previous period
			replace wage_decile	= l.wage_decile		if month == `month' 
			replace wage 		= l.wage			if month == `month'

			
			*******************		
			// Compute transitions
			// Sample transitions in and out of active contributions (choose a random number)
			
			// Transitioning out of active contributions (i.e. formal work)
			replace exiter = (runiform() < transition_out & wage_decile > 0) if month == `month'
			
			// Transitioning into active contributions (i.e. formal work)
			replace reentrant = (runiform() < transition_in & wage_decile == 0) if month == `month'

			
			
			
			// Update reference wages and wage deciles for exiters and enterers
			// Exiters:
			replace wage_ref    = wage 	if month == `month' & exiter == 1
			replace wage    	= .  	if month == `month' & exiter == 1
			replace dens    	= 0 	if month == `month' & exiter == 1
			replace wage_decile = 0     if month == `month' & exiter == 1
			// Reentrants:
			replace wage_decile = wage_decile_ref if month == `month' & reentrant == 1
			// Both:
			replace spell_length = 1 if month == `month' & (reentrant == 1 | exiter == 1)

		
			// Update the density and length of service variables (los)
			replace dens = (wage_decile >  0) 	if month == `month'			// If working: Note the density flag
			replace los = l.los + 1 if month == `month' & wage_decile >  0	// If working: Increment length of service 
			replace los = l.los     if month == `month' & wage_decile == 0	// If not working: Do not increment length of service
			replace loa = l.loa + 1 if month == `month' 					// Increment length of affiliation 

			replace contribution_density = los / loa if month == `month' 	// Update contribution density 
			replace log_cod = log(max(contribution_density, 0.001))
			
			// Update los-gap and pension-gap calculations
			replace los_gap = max(12 * `p_min_service_req' - los, 0)
			replace pension_gap = max(age_gap, los_gap)
			
			// Increment duration of spell (job or unemployment)
			replace spell_length = l.spell_length + 1  if month == `month' & !(reentrant == 1 | exiter == 1)

			

			*******************		
			// Assign wages to reentrants
			// Special case: those that move from out-of-work to work need to have a given wage

			
			// Sample a wages to new entrants and new affiliates
			// Note: bounded by the min and max of the decile
			// New affiliates are given the same wage for the entire first year
			replace wage = max(min(rnormal(`wage_mean', `wage_sd'), `wage_max'), `wage_min') if missing(l.wage) & new_affiliate == 1

			
			// We give reentrants the same wage they left with (adjusted for wage growth)
			// Note: We give reentrants the same wage they left with so that we can assign wage penalties (in a later revision)
			// Note: If we don't have a previous wage then we sample a wage
			replace wage = wage_ref if month == `month' & reentrant == 1 & !missing(wage_ref)
			replace wage = max(min(rnormal(`wage_mean', `wage_sd'), `wage_max'), `wage_min') if month == `month' & reentrant == 1 & missing(wage_ref)
			

	
			} // end forvalues month
		************************************************************************
		************************************************************************
		************************************************************************
		
		*******************
		// Update the reference wage for re-entrants who didn't have a wage in the past
		tempvar wage_ref_update
		gegen `wage_ref_update' = max(wage_ref), by(id)
		replace wage_ref = `wage_ref_update' if missing(wage_ref)
			
			

		*******************		
		// Compute wage dynamics
		// Note: This is done annually and not monthly
			
		//	Merge in the wage growth database
		noisily display " "
		noisily display "Merging in the wage growth database..."
		capture drop wage_growth
		// Cap merge year so projection years beyond data use the last available growth rate
		capture drop year_merge
		generate year_merge = min(year, `wage_growth_max_year')
		join wage_growth, from(`wage_growth_database') by(year_merge) keep(1 3) nogenerate	// ftools version of merge [faster]
		drop year_merge
		
		// Get the user determined wage growth 
		// Note: this works as we only simulate one year at a time
		quietly summarize wage_growth
		local wage_growth_user = r(mean) / 100
			
		//	Load in model parameters to compute relative wages
		//	Note: the model uses the following inputs:
		//			- wage_decile_age_sex (wage deciles by age and sex)
		//			- gender (1 = male, 2 = female)
		//			- age (in years)
		estimates restore lifecycle_stored
		
		// Predict relative wage 
		capture drop relative_wage_growth
		predict relative_wage_growth, xb

		// Adjust global wage growth to reflect age-sec-decile profiles
		replace sim_wage_growth = wage_growth * relative_wage_growth / 100
		
		// Adjust wages
		replace wage = wage * (1 + (sim_wage_growth / 100)) 

		// Re-adjust wages to ensure that user-defined wage growth is obtained
		
		// Get the average wage of the sample (this year)
		quietly summarize wage
		local new_wage = r(mean)
		
		// Compare to average wage of last year (defined earlier in the code)
		local wage_growth_obs = (`new_wage' / `old_wage') - 1
		
		// Compute aggregate adjustments
		local wage_adjustment = (1 + `wage_growth_user') / (1 + `wage_growth_obs')

		// Adjust wages to reflect user-defined aggregate wage growth
		replace wage     = wage     * `wage_adjustment'	
		replace wage_ref = wage_ref * `wage_adjustment'
		


	

		
		*******************
		//	Stage 5 - Determine mortality
		
// 		// 	Merge in mortality data  
// 		noisily display " "
// 		noisily display "Merging in mortality rates..."
// 		capture drop mortality
// 		join mortality, from(`mortality_database') by(gender age year) keep(1 3) nogenerate	// ftools version of merge [faster]
//		
// 		// Dead people don't have a mortality rate
// 		replace mortality = . if status == 99
//		
// 		// Sample probability of dying
// 		tempvar randnum_mortality
// 		generate `randnum_mortality' = runiform()
//		
// 		// Assign mortality randomly
// 		replace status = 99 if mortality > runiform() // Status 99 means dead
		
		// Housekeeping for when people die
		replace deathyear = `yr'	 	if status == 99 & !missing(mortality)	// Record year died
		replace wage_at_death = wage 	if status == 99 & !missing(mortality)
		replace wage = . 			 	if status == 99
		replace pension_benefit = 0     if status == 99                         // Stop paying pension
		replace dens            = 0     if status == 99                         // Not contributing
		

		
		



		*******************
		//	Stage 6 - Apply disability and survivor
		// 	[TODO: Sort out disability and survivor data - Talk to Marola and Asta about this]
		
		// Once rate files are available, implement as follows:
		// Disability:
		//   import delimited "`indir'\disability_rates_`country'.csv", clear   // columns: age gender year disability_rate
		//   tempfile disability_database; save `disability_database', replace   // (load before main loop)
		//   Inside loop: join disability_rate, from(`disability_database') by(age gender year) keep(1 3) nogenerate
		//   replace status = 3 if status == 1 & disability_rate > runiform()   // Status 3 = disabled
		// Survivor (widowhood):
		//   Requires a separate survivor_rate file and a record of deceased affiliates (see the TODO at Stage 11
		//   about keeping dead people in the dataset). Basic approach:
		//   generate widow_flag = 0
		//   replace  widow_flag = 1  if status[_n-1] == 99 & widow_rate > runiform()
		//   replace  status     = 4  if widow_flag   // Status 4 = widowed

		
		
		

		*******************
		//	Stage 7 - Index values and Compute annual reference values
		//	Note: we do this so that we can carry forward some summary statistics
		//  Note: At this point, all mortality, disabiity, and job transitions have been calculated
			
		// Update contribution density
		replace contribution_density = los / loa 
		replace log_cod = log(max(contribution_density, 0.001))

	
		**********
		//	Index previous reference values
		
		// Load in the annual assumed inflation
		// Cap merge year so projection years beyond data use the last available indexation values
		capture drop pindex_inflation pindex_realwage pindex_anchor
		capture drop year_merge
		generate year_merge = min(year, `indexation_max_year')
		join pindex_inflation pindex_realwage pindex_anchor, from(`indexation_database') by(year_merge) keep(1 3) nogenerate
		drop year_merge
		quietly summarize pindex_inflation
		local pindex_inflation = r(mean)
		quietly summarize pindex_realwage
		local pindex_realwage  = r(mean)
		quietly summarize pindex_anchor
		local pindex_anchor    = r(mean)


		// Compute revalorization rate
		local p_revalorization_rate = ( `p_revalor_inflation_coeff' * `pindex_inflation' ///
									  + `p_revalor_realwage_coeff'  * `pindex_realwage'  ///
							          + `p_revalor_anchor_coeff'    * `pindex_anchor') / 100
		
		// Update reference wages if type 1 (best of last x years)
		if `ref_wage_type' == 1 {
			replace reference_wage = replace * (1 + `p_revalorization_rate') 
			} // end if statement
								
		// Update reference wages if type 2 or 3 (best x oy y years)
		if `ref_wage_type' == 2 | `ref_wage_type' == 3 {
			forvalues i = 1/`ref_wage_n' {
				replace bestwage`i' = bestwage`i' * (1 + `p_revalorization_rate') 
				} // end forvalues
			} // end if statement
		
		
		**********
		// Reference wage placeholders
		
		// Compute average wage for the year
		capture drop avg_wage
		gegen avg_wage = mean(wage)  , by(id)	

		// 	Here we update placeholder values that record the current best years of contributions
		//	Get the N highest wages
		if `ref_wage_type' == 2 {
			// The Lowest wage of best N wages
			tempvar refwage_min 
			gegen `refwage_min' = rowmin(bestwage*) 
			// Compare the lowest best wage to the current wage (replace if current wage is bigger)
			forvalues i = 1/`ref_wage_n' {
				replace bestwage`i' = avg_wage if avg_wage > bestwage`i' & bestwage`i' == `refwage_min' 
				} // end forvalues i
			} //end if `ref_wage_type' == 2
			
		//	Get the N highest wages of the M last years
		if `ref_wage_type' == 3 {
			// The Lowest wage of best N wages
			tempvar refwage_min 
			gegen `refwage_min' = rowmin(bestwage*) 
			// Compare the lowest best wage to the current wage (replace if current wage is bigger)
			forvalues i = 1/`ref_wage_n' {
				// Erase any years that are older than M
				replace bestwage`i' = . if bestyear`i' < (`yr' - `ref_wage_m') 
				replace bestyear`i' = . if bestyear`i' < (`yr' - `ref_wage_m')
				// Save the wage if is it better than the lowest best wage
				replace bestwage`i' = avg_wage if avg_wage > bestwage`i' & bestwage`i' == `refwage_min'
				// Save the year of the wage if is it better than the lowest best wage
				replace bestyear`i' = `yr'		if avg_wage > bestwage`i' & bestwage`i' == `refwage_min' 
				} // end forvalues i
			}  // end if `ref_wage_type' == 3
		**********	
		
		
		**********
		// Update variables for determining labour market conditions
		
		// Store the population and employment totals as well as the total flows
		tempvar samp
		tempvar emp
		tempvar reentrants
		tempvar affiliates
		tempvar new_affiliates
		tempvar exiters

		
		// Note: We use this method so that we can disaggregate results by gender-age-decile (if we want to)
		gegen `samp' 	  		= count(dens)  		 if month > 0  //, by(wage_decile_ref)	// Population count
		gegen `emp'  	  		= sum(dens)    		 if month > 0  //, by(wage_decile_ref) 	// Employment count
		gegen `reentrants'  	= sum(reentrant)     if month > 0  //, by(wage_decile_ref)	// Number of re-entrants
		gegen `affiliates'      = sum(status!=99)    if month > 0  //, by(wage_decile_ref)	// Number of total affiliates
		gegen `new_affiliates'  = sum(new_affiliate) if month > 0  //, by(wage_decile_ref)	// Number of new affiliates
		gegen `exiters'  		= sum(exiter)  		 if month > 0  //, by(wage_decile_ref)	// Number of exiters

		
		// This is mostly for reporting (and for adjusting transition rates)
		replace sample_pop 	 	= `samp' / 12						// Annual Population count
		replace affiliates 	 	= `affiliates' / 12					// Number of total affiliates
		replace employment      = `emp'	/ 12						// Number of affiliates who are contributing ("working")
		replace employment_rate = 100 * employment / affiliates 	// "Employment rate": Share of affiliates who are working
		replace unemployment    = affiliates - employment			// Number of affiliates who are not contributing ("not working")
		replace reentrants      = `reentrants'						// Number of re-entrants
		replace new_affiliates  = `new_affiliates'					// Number of new affiliates
		replace exiters 		= `exiters'							// Number of exiters

		// Compute inflow and outflow rates
		// Note: We do not include new_affiliates in the inflow rate as they do not come from the stock of non-contributing affilates
		replace inflow_rate   = 100 * reentrants / unemployment 					// Share of "unemployed" flowing into "employment"
		replace outflow_rate  = 100 * exiters / employment							// Share of "employed" flowing into "unemployment"
		replace turnover_rate = 100 * (exiters + reentrants) / (affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			
	

		
		
		*******************
		//	Stage 8 - Apply pension layers
		
		**********
		// Compute Reference Wages:
		// [TODO: Check if we apply the maximum or minimum earnings before or after computing reference wages]
		// [TODO: Apply revalorization on reference wages]
		// Each person's average wage 
		
		// Determine covered wages
		replace covered_wage = max(min(wage, `p_max_income'), `p_min_income') if !missing(wage)
		
		// Compute average wage across the year
		capture drop avg_covered_wage
		gegen avg_covered_wage = mean(covered_wage)  , by(id)	

		
		// Compute the reference wage
		// Note: This depends on the type of calculation
		// 1 = Last N years before retirement: 
		if `ref_wage_type' == 1 {
			// Increment the reference wage
			replace reference_wage = reference_wage * ((`ref_wage_n' - 1)/ `ref_wage_n') + (1 / `ref_wage_n') * avg_covered_wage
			} //end if `ref_wage_type' == 1
		// 2 = Best N years in the career: Highest N wages in the career
		else if `ref_wage_type' == 2 {
			// Compare the lowest number 
			capture drop reference_wage
			egen reference_wage = rowmean(bestwage*)
			} //end if `ref_wage_type' == 2
		// 3 = Best N years within the last M years: Highest N wages within last M years before retirement
		// Note: This is the same as ref_wage_type = 2 above, but processed differently higher up
		else if `ref_wage_type' == 3 {
			capture drop reference_wage
			egen reference_wage = rowmean(bestwage*)
			} //end if `ref_wage_type' == 3
			
		
		
		
		**********
		// Determine pension eligibility:
		// Eligible for pension based on length of service
		replace pension_elig_mincont = ((los / 12) >= `p_min_service_req')

		// Eligible for pension based on early retirement penalty
		replace pension_elig_delta = (age >= (`p_retage_male'   - (1 / `p_delta'))) if gender == 1
		replace pension_elig_delta = (age >= (`p_retage_female' - (1 / `p_delta'))) if gender == 2
		
		// Eligible for pension based on early retirement restriction
		replace pension_elig_early = (age >= `p_retage_early_male')   if gender == 1
		replace pension_elig_early = (age >= `p_retage_early_female') if gender == 2
		
		// Eligile for a pension if you meet all of the eligibility criteria
		replace pension_elig = (pension_elig_mincont & pension_elig_delta & pension_elig_early)

		
		**********
		// Determine pension benefit:
		// Years of service
		replace yos = los / 12	
		
		// Years early (prior to retirement)
		replace years_early = max(`p_retage_male'   - age, 0) if gender == 1
		replace years_early = max(`p_retage_female' - age, 0) if gender == 2
		
		// Years late (after to retirement)
		replace years_late = max(age - `p_retage_male'  , 0) if gender == 1
		replace years_late = max(age - `p_retage_female', 0) if gender == 2
		
		// Pension replacement rate
		replace replacement_rate = yos * `p_accrual' - (years_early * `p_delta') + (years_late * `p_lambda')
		replace replacement_rate = max(min(replacement_rate, `p_accrual_max'), 0)	// Apply minimums and maximums


		
		
		**********
		//	Compute the minimum guarenteed pensions (minimum monthly amounts):
		//	Note: Minimum pension can differ by age, wage, and years of service (or the can be flat)
		//	Note: Some of the values are indexed in Stage 7
		replace pension_minpen = `p_minpen_base'

		// Variation by age
		tempvar  minpen_age 
		generate `minpen_age'	= min(max(`p_minpen_age' - age, 0), `p_minpen_age_max' - `p_minpen_age')
		replace  `minpen_age'   = floor(`minpen_age' / `p_minpen_age_step') * `p_minpen_age_step'		// Apply the step increment
		replace  pension_minpen = pension_minpen * (1 + (`p_minpen_age_pct' * `minpen_age')) + (`minpen_age' * `p_minpen_age_lvl') 	// Apply both the percent and level change (usually only one applies)


		// Variation by service time	
		tempvar  minpen_yos 
		generate `minpen_yos'	= min(max(`p_minpen_yos' - yos, 0), `p_minpen_yos_max' - `p_minpen_yos')
		replace  `minpen_yos'   = floor(`minpen_yos' / `p_minpen_yos_step') * `p_minpen_yos_step'		// Apply the step increment
		replace  pension_minpen = pension_minpen * (1 + (`p_minpen_yos_pct' * `minpen_yos')) + (`minpen_yos' * `p_minpen_yos_lvl') 	// Apply both the percent and level change (usually only one applies)


		// Variation by wage
		tempvar  minpen_wage 
		generate `minpen_wage'	= min(max((wage - `p_minpen_wage')/`p_minpen_wage', 0), (`p_minpen_wage_max' - `p_minpen_wage')/`p_minpen_wage')
		replace  `minpen_wage'  = floor(`minpen_wage' / `p_minpen_wage_step') * `p_minpen_wage_step'		// Apply the step increment
		replace  pension_minpen = pension_minpen * (1 + (`p_minpen_wage_pct' * `minpen_wage')) + (`minpen_wage' * `p_minpen_wage_lvl') 	// Apply both the percent and level change (usually only one applies)




		
		// Maximum pension amount
		// Note: This allows for maximum pension amounts to scale with age and years of contributions
		replace pension_maxpen = `p_pension_max'
		replace pension_maxpen = pension_maxpen * (1 + `p_maxpen_age_scale') * max(age - `p_maxpen_age_threshold', 0) 
		replace pension_maxpen = pension_maxpen * (1 + `p_maxpen_yos_scale') * max(yos - `p_maxpen_yos_threshold', 0) 
		
		
		**********
		// Compute the pension benefit:
		// Pension_(base,i) = ReferenceWage_i ∑_(t=1)^(YearsofService(r))▒〖AccrualRate〗_i (t)
		replace pension_benefit_base = reference_wage *  replacement_rate * pension_elig
		
		//	Apply pension minimums and maximums
		replace pension_benefit = max(min(pension_benefit_base, pension_maxpen), pension_minpen) * pension_elig
		

		**********
		// Index pension benefit amounts 
		// This includes: base pension, reference wage, minimum and maximum pensions
		
		// Minimum pension index rate 
		local mpi_index_rate = ( `p_mpi_index_inflation_coeff' * `pindex_inflation' ///
							   + `p_mpi_index_realwage_coeff'  * `pindex_realwage'  ///
							   + `p_mpi_index_anchor_coeff'    * `pindex_anchor') / 100
		

		// Update related pension amounts
		local p_minpen_base    	= `p_minpen_base'    * (1 + `mpi_index_rate')
		local p_minpen_refwage 	= `p_minpen_refwage' * (1 + `mpi_index_rate')
		local p_minpen_wage		= `p_minpen_adj1' * `p_minpen_refwage'	
		local p_minpen_wage_max	= `p_minpen_adj2' * `p_minpen_refwage'	 
		local p_pension_max     = `p_pension_max' * (1 + `mpi_index_rate')
		



		*******************
		//	Stage 9 - Retirement decision
		//	Note: People retire if they have enough contributions to retire and are eligible
		//	If there is a benefit to working longer, they will work longer
		// [TODO: Replace this with a decision that reflects net present value of a pension and life expectancy]
		// [TODO: Talk to Marola about how to model retirement decision]
		
		// Rough rule: people retire if eligible and if hit the maximum replacement rate (or are too old)
		replace status = 2 if pension_elig &  (replacement_rate >= `p_accrual_max' | age >= `p_too_old_to_retire')  
		
		// NPV-based retirement decision:
		// [TODO: Add in life expectancy-based retirement decision]
// 		Replace the rough rule below with:
// 		  // Years of remaining life expectancy (approximate; requires LE data merged by age/gender/year)
// 		  generate le_remaining = <life_expectancy_at_age> - age   // from merged LE table
// 		  // NPV of retiring now: annuity valued at current pension benefit
// 		  generate npv_retire_now  = pension_benefit * (1 - (1/(1+`p_discount_rate'))^le_remaining) ///
// 		                             / `p_discount_rate' if pension_elig
// 		  // NPV of retiring next year: one more year of contributions, then collect adjusted pension
// 		  generate pension_if_wait = reference_wage * min(yos+1, `ref_wage_n') * `p_accrual'
// 		  generate npv_retire_next = pension_if_wait * (1 - (1/(1+`p_discount_rate'))^(le_remaining-1)) ///
// 		                             / `p_discount_rate' / (1 + `p_discount_rate') if pension_elig
// 		  replace status = 2 if pension_elig & (npv_retire_now >= npv_retire_next | age >= `p_too_old_to_retire')

		// [TODO: Discuss with Marola and Asta:]
		//	(1) UN tables as life-expectancy table source for NPV calculation? 
		//	(2) appropriate default discount rate? 
		//	(3) how does retirement decision interact with disability/survivor transitions?
		
		
		
		// Record the month and year of retirement
		// [TODO: Currently people retire at end of the year, we may change this]
		replace retire_year  = `yr' if status == 2
		replace retire_month = 12   if status == 2  
		
		// Compute lump-sum amounts for those who retire but are not eligible
		*replace pension_lumpsum = 0 if `p_lumpsum_flag' == 1
		
		
		*******************
		// Approximate calculation of lump-sum amounts
		// [TODO: Fix this calculation to make it generic]
		replace pension_lumpsum = (los / 12) * avg_covered_wage * `p_contribution_rate_ee' * (1 + `p_lumpsum_interest')^yos if `p_lumpsum_flag' & !pension_elig & status == 2
		


		
		
		*******************
		//	Stage 10 - In-year reporting
		// 	Note: Because we drop all of the years as we process them, we need to collect all of our reporting as we go

		// Generate tempfiles
		tempfile rpt_gender_decile_dens_inyear
		tempfile rpt_gender_decile_inyear
		tempfile rpt_gender_dens_inyear
		tempfile rpt_decile_dens_inyear
		tempfile rpt_decile_inyear
		tempfile rpt_gender_inyear
		tempfile rpt_dens_inyear
		tempfile rpt_total_inyear
		
		// Generate status totals
		*capture drop  affiliated
		capture drop  retired
		capture drop  disabled
		capture drop  widowed
		capture drop  deceased
		capture drop  num_new_affiliates
		capture drop  num_exiters
		capture drop  num_reentrants
		capture drop  num_affiliates
		capture drop  num_contributors
		capture drop  num_inactive
		capture drop  target_employment_rate
		capture drop  target_turnover_rate
		capture drop  population_total

		*generate affiliated  		= wgt * (status == 1)
		generate retired     		= wgt * (status == 2)
		generate disabled    		= wgt * (status == 3)
		generate widowed     		= wgt * (status == 4)
		generate deceased    		= wgt * (status == 99)
		generate num_new_affiliates = wgt * new_affiliate
		
		// More detailed aggregates for these states as they are not persistent
		gegen num_exiters   = sum(exiter)   if month > 0, by(id)	// Number of exiters
		replace num_exiters = wgt * num_exiters
		
		gegen num_reentrants   = sum(reentrant)   if month > 0, by(id)	// Number of reentrants
		replace num_reentrants = wgt * num_reentrants
		
		gegen num_affiliates   = sum(status!=99)   if month > 0, by(id)	// Number of reentrants
		replace num_affiliates = wgt * num_affiliates / 12
		
		gegen num_contributors   = sum(dens==1 & status!=99)   if month > 0, by(id)	// Number of active contributors
		replace num_contributors = wgt * num_contributors / 12
		
		gegen num_inactive   = sum(dens==0 & status!=99)   if month > 0, by(id)	// Number of reentrants
		replace num_inactive = wgt * num_inactive / 12

		// Report on targets
		generate target_employment_rate = 100 * `target_emp_rate'
		generate target_turnover_rate	= `turnover_target'
		
		// Join in the total population data
		capture drop pop
		capture drop working_age
		capture drop population_total
		capture drop working_age_total
		join pop working_age, from(`population_db_total') by(year) keep(1 3) nogenerate	// ftools version of merge [faster]
		rename pop population_total
		rename working_age working_age_total
		

		
		// Reporting locals
		local sumvars  = "num_new_affiliates num_exiters num_reentrants num_affiliates num_contributors num_inactive retired disabled widowed deceased samplesize=wgt"
		local meanvars = "population_total working_age_total avg_age=age los loa wage contribution_density target_employment_rate target_turnover_rate"
 
		***************
		// In-year reporting by decile, gender, and contribution status:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by decile, gender, and contribution status
			collapse (sum) `sumvars' (mean) `meanvars', by(gender wage_decile dens)
			// Generate placeholders (for appending)
			generate year = `yr'
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By decile
			save `rpt_gender_decile_dens_inyear', emptyok replace
		restore
			
			
		***************
		// In-year reporting by decile and gender:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by decile and gender
			collapse (sum) `sumvars' (mean) `meanvars', by(gender wage_decile)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate dens = 99 			// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By decile
			save `rpt_gender_decile_inyear', emptyok replace
		restore
		
		
		***************
		// In-year reporting by decile and contribution status:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by decile and contribution status
			collapse (sum) `sumvars' (mean) `meanvars', by(wage_decile dens)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate gender = 99 	// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By decile and density
			save `rpt_decile_dens_inyear', emptyok replace
		restore
		
		
		***************
		// In-year reporting by gender and contribution status:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by gender and contribution status
			collapse (sum) `sumvars' (mean) `meanvars', by(gender dens)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate wage_decile = 99 	// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By gender and density
			save `rpt_gender_dens_inyear', emptyok replace
		restore
		
		
		***************
		// In-year reporting by decile:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by decile and gender
			collapse (sum) `sumvars' (mean) `meanvars', by(wage_decile)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate gender = 99	// Totals placeholder
			generate dens = 99 		// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By decile
			save `rpt_decile_inyear', emptyok replace
		restore
		
		
		***************
		// In-year reporting totals by gender:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by gender
			collapse (sum) `sumvars' (mean) `meanvars', by(gender)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate wage_decile = 99 	// Totals placeholder
			generate dens = 99 			// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save by gender
			save `rpt_gender_inyear', emptyok replace
		restore
				
			
		***************
		// In-year reporting by contribution status:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by contribution status
			collapse  (sum) `sumvars' (mean) `meanvars', by(dens)
			// Generate placeholders (for appending)
			generate year = `yr'
			generate gender = 99 		// Totals placeholder
			generate wage_decile = 99 	// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate 		= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save By decile
			save `rpt_dens_inyear', emptyok replace
		restore
		
		
		***************
		// In-year reporting totals:
		preserve
			// Keep just the last month of the year
			keep if month == 12
			// Collapse by gender
			collapse (sum) `sumvars' (mean) `meanvars'
			// Generate placeholders (for appending)
			generate year = `yr'
			generate gender = 99 		// Totals placeholder
			generate wage_decile = 99 	// Totals placeholder
			generate dens = 99 			// Totals placeholder
			// Compute employment rate and turnover rate
			generate employment_rate 	= 100 * num_contributors / num_affiliates						// "Employment rate": Share of affiliates who are working
			generate turnover_rate	 	= 100 * (num_exiters + num_reentrants) / (num_affiliates * 12)	// Share of people changing roles each year: (exiters + reentrants) / affiliates
			// Order the variables
			order year gender wage_decile dens  								///
			samplesize num_affiliates num_contributors num_inactive 			/// 
			num_new_affiliates num_exiters num_reentrants  						///
			retired disabled widowed deceased  									///
			avg_age los loa wage contribution_density 							///
			population_total working_age 							 			/// 
			target_employment_rate employment_rate								///
			target_turnover_rate turnover_rate
			// Save totals
			save `rpt_total_inyear', emptyok replace
		restore
		
		
		***************
		// Accumulate in-year reporting into reporting database - total
		preserve
			use `inyear_affiliate_reporting_tot', clear
			append using `rpt_total_inyear'
			save `inyear_affiliate_reporting_tot', replace
		restore
		
		
		***************
		// Accumulate in-year reporting into reporting database - breakdowns
		preserve
			use `inyear_affiliate_reporting', clear
			append using `rpt_gender_decile_dens_inyear'
			append using `rpt_gender_decile_inyear'
			append using `rpt_gender_dens_inyear'
			append using `rpt_decile_dens_inyear'
			append using `rpt_decile_inyear'
			append using `rpt_gender_inyear'
			append using `rpt_dens_inyear'
			save `inyear_affiliate_reporting', replace
		restore
		

			


		
		*******************
		//	Stage 11 - Save database of affiiates transitioning to be pension beneficiaries (i.e those retiring)
		// Carve off the pensioners into a storage location (for appending later on to the pensioners basecase)
		preserve
			// [TODO: Format this dataset so that it blends in with the pensioners basecase]
			//	Note: Needs to contain the following variables:
			//		- pension_benefit	[Monthly pension benefit]
			//		- age 				[Age of recipient]
			//		- gender 			[Gender of recipient, 1 = male, 2 = female]
			//		- startyear 		[Year pension started being paid]
			//		- pension_class 	[Class of pension (e.g., 1=DB, 2=DC, etc.)]
			//		- pension_type 		[Type of pension (old-age, disability, surivior)]
			//		- pension_id		[Pension unique ID number]
			tempfile pensioners`yr'
			keep if status == 2		// Status 2 = retired
			keep if month == retire_month		

			// Generate the pension-specific variables 
			generate startyear = `yr'
			generate pension_class = 1 	// Pension class = Defined Benefit (DB)
			generate pension_type = 1 	// Pension type = old-age (1)
			generate pension_id = 1   	// Pension system unique ID
			rename id affiliate_id
			// Distinguish from base-year observed pensioners
			generate pensioner_source = "projected"    
			// Keep only the key reporting variables
			keep pension_benefit age gender startyear pension_class pension_type ///
				 pension_id wgt year affiliate_id yob los iacc wage_decile status ///
				 reference_wage years_early years_late replacement_rate ///
				 retire_year deathyear deathmonth pension_minpen pension_maxpen ///
				 pension_lumpsum pensioner_source
			save `pensioners`yr''
			noisily display " "
			noisily display "Pensioners in `yr' saved to a separate file"
		restore
		
		// Save in-year dataset for appending later (if extended_output flag is toggled)
		// Note: We compile these datasets on
		if `extended_output' == 1 {
			// Save a copy of the existing database
			tempfile affiliate_sim`yr'
			save `affiliate_sim`yr'', replace
			} // end if extended_output
		
		
		//	Cleanup variables that we will redefine 
		capture drop __00*	// Drop tempvars

		
		// Drop pensioners (they are no longer affiliates)
		drop if status == 2
		
		// Drop people who have died
		// Once the disability/survivor stage is active, deceased affiliates must be accessible
		// to determine which survivors become widows/widowers. Replace the drop with:
		// preserve
		//     keep if status == 99
		//     tempfile deceased_affiliates`yr'
		//     save `deceased_affiliates`yr'', replace   // Available for Stage 6 survivor processing
		// restore
		// drop if status == 99   // Still drop from main simulation dataset
		// Alternatively, carry the deceased for one additional year with a flag, then drop them the
		// following year after survivor transitions have been applied.
		drop if status == 99
	

	
	} // end forvalues yr	 
	****************************************************************************
	****************************************************************************
	****************************************************************************
	****************************************************************************
	****************************************************************************

//	Compress the dataset (for size constraints)
	compress, nocoalesce
	
********************************************************************************
//	Final reporting on the affiliate database
	// Keep only the latest observation in a year
	keep if month == 12
	
	// Clean up tempvars before saving
	capture drop __00*
	
	// Move all the annual wage variables to the back
	*order wage_????, last
	
	
	// Export the data
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Affiliates-`startyear'-`endyear'.csv", replace
	

	// [Sanity check: Output histograms of contribution density by decile]
	// Save histogram to compare with simulated density in the last year
	if `histograms' == 1 {
		histogram contribution_density if month == 12, name(cod_lastyear, replace) yscale(range(0 5))
		histogram contribution_density if month == 12, by(wage_decile) name(cod_by_decile_lastyear, replace) yscale(range(0 15))
		graph combine cod_by_decile_baseyear cod_by_decile_lastyear, name(by_decile)
		graph combine cod_baseyear cod_lastyear, name(aggregate)
		} // end if histograms

	
	
	
********************************************************************************
//	Export EXTENDED OUTPUT in-year affiliate reporting
	if `extended_output' == 1 {
		// Open the database
		use `extended_output_data', clear

		// Append it to the extended output database 
		forvalues yr = `startyear'/`endyear' {
			append using `affiliate_sim`yr''
			}
		
		// Clean up tempvars before saving
		capture drop __00*
		
		// Export dataset
		*cd "`outdir'"
		save "`outdir'\1_PROSTv2-`simname'-EXTENDED-OUTPUT.dta", replace
		} // end if extended_output
	

	

	
	

********************************************************************************
//	Pensioners projection
//	After working through the affiliate database we save the pensioners by year
//	and merge it into the pension database to get the database of pensioners
//	We then project that forward

//	Load the baseyear pensioners database
//	Note: Contains the following variables:
//		- pension_benefit	[Monthly pension benefit]
//		- age 				[Age of recipient]
//		- gender 			[Gender of recipient, 1 = male, 2 = female]
//		- startyear 		[Year pension started being paid]
//		- pension_class 	[Class of pension (e.g., DB, DC, etc.)]
//		- pension_type 		[Type of pension (old-age, disability, surivior)]
//		- pension_id		[Pension unique ID number]
	use `pensioners_database', clear	
	
//	Sample a share of the baseyear individuals to be our projection database
//	[TODO: Consider a stratified sample]
	sample `samplesize'

// 	Generate a sampling weight [TODO: Change if we take a stratified sample]
	capture drop wgt
	generate wgt = 100 / `samplesize'
	
//	Add in the year	
	capture drop year
	generate year = `baseyear'
	
//	Add in a pensioner unique ID number
	capture drop pensioner_id
	generate pensioner_id = _n
	
//	Inlcude a pensioner source (observed / projected)
	generate pensioner_source = "observed"
	
//	Add in a status (in the base year it is all 2 = retired)
//	[TODO: Revisit this when adding in disabilty and survivor]
	capture drop status
	generate status = 2 // 2 = retired
	
//	Add a variable of age at death (for calculating life expectancy)
	capture drop age_died
	generate age_died = .
	
//	Add variable capturing if a person died this year
	capture drop died_flag
	generate died_flag = 0
	
//	Reporting placeholders
	generate pension_index = 0		// Annual indexation parameter (user defined)
	
pause "pension"
	

//	Pensioners: Loop over the projection period
	forvalues yr = `startyear'/`endyear' {
		// Save the last row of the dataset for later (when adding new ID numbers)
		local last_pensioner_row = _N
	
		
		**********
		// Stage 1: Append years pensioners
		append using `pensioners`yr''
		
		// Give new pensioners a new id number
		summarize pensioner_id, meanonly
		local max_pensioner_id = r(max)
		replace pensioner_id = `max_pensioner_id' + (_n - `last_pensioner_row') if missing(pensioner_id)
		
		// Reset died_flag to zero
		replace died_flag = 0

		
		**********
		// Stage 2: Apply mortality rates	
		
		// 	Merge in mortality data
		noisily display " "
		noisily display "Merging in mortality rates..."
		capture drop mortality
		// Cap merge year so projection years beyond data use the last available rates
		capture drop year_merge
		generate year_merge = min(year, `mortality_max_year')
		join mortality, from(`mortality_database') by(gender age year_merge) keep(1 3) nogenerate	// ftools version of merge [faster]
		drop year_merge

		// Sample probability of dying
		tempvar randnum_mortality
		generate `randnum_mortality' = runiform()
		
		// Assign mortality
		replace died_flag = 1 		if mortality > `randnum_mortality' & status != 99
		replace deathyear = `yr'	if died_flag == 1 // Record year died
		replace status = 99 		if died_flag == 1 // Status 99 means dead
		
		// Housekeeping for dead people
		replace pension_benefit = . if died_flag == 1
		replace age_died = age 		if died_flag == 1
	
	
	
		**********
		// Stage 3: Index pension benefits
		// After retirement, the pension evolves according to the indexation rule.
		// Pension_i (t) = Pension_i (t-1) * (1+PensionIndexationRate(t))
		// PensionIndexationRate(t) = α_1 * Inflation(t-1) + α_2 * RealWageGrowth(t-1) + α_3 * AnchorVariable(t)
		
		capture drop pindex_inflation pindex_realwage pindex_anchor
		// Cap merge year so projection years beyond data use the last available indexation values
		capture drop year_merge
		generate year_merge = min(year, `indexation_max_year')
		join pindex_inflation pindex_realwage pindex_anchor, from(`indexation_database') by(year_merge) keep(1 3) nogenerate
		drop year_merge
		quietly summarize pindex_inflation
		local pindex_inflation = r(mean)
		quietly summarize pindex_realwage
		local pindex_realwage  = r(mean)
		quietly summarize pindex_anchor
		local pindex_anchor    = r(mean)

		replace pension_index = ( `alpha1' * `pindex_inflation' 	///
								   + `alpha2' * `pindex_realwage' 	///
								   + `alpha3' * `pindex_anchor') / 100 		
		replace pension_benefit = pension_benefit * (1 + pension_index)

		
		**********
		// Stage 4: In-year reporting
		
	
		/*
		Outputs to report on:

		Average Age of Disabled Beneficiaries (by year, by sex) 
		Total Number of Old Age Retirees (by year, by sex) 
		Total Number of Survivors (by year, by sex) 
		Total Number of Disabled Beneficiaries (by year, by sex) 
		Retirees (by age and sex, by year) 
		Survivors (by age and sex, by year) 
		Disabled Beneficiaries (by age and sex, by year) 
		*/
		
		
		// Generate tempfiles
		tempfile pension_age_gender_class_type
		tempfile pension_age_gender_class
		tempfile pension_age_gender_type
		tempfile pension_age_class_type
		tempfile pension_gender_class_type
		tempfile pension_age_gender
		tempfile pension_gender_class
		tempfile pension_gender_type
		tempfile pension_age_class
		tempfile pension_age_type
		tempfile pension_class_type
		tempfile pension_gender
		tempfile pension_age
		tempfile pension_class
		tempfile pension_type
		tempfile pension_total
		

		
		// Generate status totals
		capture drop  retired
		capture drop  disabled
		capture drop  widowed
		capture drop  deceased
		generate retired  	 = wgt * (status == 2)
		generate disabled    = wgt * (status == 3)
		generate widowed     = wgt * (status == 4)
		generate deceased    = wgt * (died_flag)	

		// In-year reporting by decile and gender:
		local sumvars = "retired disabled widowed deceased"
		local meanvars = "avg_pension=pension_benefit"
		local meanvars_totals = "avg_pension=pension_benefit pension_index"

		
		
		**********
		// In-year reporting totals by gender, age, class and pension type:
		preserve
			// Collapse by gender, age, class, and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(gender age_grp pension_class pension_type)
			generate year = `yr'
			// Save totals
			save `pension_age_gender_class_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender, age, and class:
		preserve
			// Collapse by gender, age, class, and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(gender age_grp pension_class)
			generate year = `yr'
			generate pension_type = 999 	// Totals placeholder
			// Save totals
			save `pension_age_gender_class', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender, age, and pension type:
		preserve
			// Collapse by gender, age, class, and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(gender age_grp pension_type)
			generate year = `yr'
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_age_gender_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender, class and pension type:
		preserve
			// Collapse by age, class, and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(age_grp pension_class pension_type)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			// Save totals
			save `pension_age_class_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender, class and pension type:
		preserve
			// Collapse by gender, age, class, and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(gender pension_class pension_type)
			generate year = `yr'
			generate age_grp = 999 			// Totals placeholder
			// Save totals
			save `pension_gender_class_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender, age:
		preserve
			// Collapse by gender, age
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(gender age_grp)
			generate year = `yr'
			generate pension_type = 999 	// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_age_gender', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by gender and class:
		preserve
			// Collapse by gender and class
			collapse (sum) `sumvars' (mean) `meanvars', by(gender pension_class)
			generate year = `yr'
			generate age_grp = 999 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			// Save totals
			save `pension_gender_class', emptyok replace
		restore
		

			**********
		// In-year reporting totals by gender and pension type:
		preserve
			// Collapse by gender and type
			collapse (sum) `sumvars' (mean) `meanvars', by(gender pension_type)
			generate year = `yr'
			generate age_grp = 999 			// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_gender_type', emptyok replace
		restore
		
		
		
		**********
		// In-year reporting totals by age and class:
		preserve
			// Collapse by age and class
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(age_grp pension_class)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			// Save totals
			save `pension_age_class', emptyok replace
		restore
		
		
		
		**********
		// In-year reporting totals by age and pension type:
		preserve
			// Collapse by age and type
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(age_grp pension_type)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_age_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by class and pension type:
		preserve
			// Collapse by class and type
			collapse (sum) `sumvars' (mean) `meanvars', by(pension_class pension_type)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate age_grp = 999 			// Totals placeholder
			// Save totals
			save `pension_class_type', emptyok replace
		restore
		
		
		
		**********
		// In-year reporting totals by gender:
		preserve
			// Collapse by gender
			collapse (sum) `sumvars' (mean) `meanvars', by(gender)
			generate year = `yr'
			generate age_grp = 999 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_gender', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by age:
		preserve
			// Collapse by age
			generate age_grp = floor(age / 5) * 5  // 5-year grouping
			collapse (sum) `sumvars' (mean) `meanvars', by(age_grp)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_age', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by class:
		preserve
			// Collapse by class
			collapse (sum) `sumvars' (mean) `meanvars', by(pension_class)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate age_grp = 999 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			// Save totals
			save `pension_class', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals by pension type:
		preserve
			// Collapse by type
			collapse (sum) `sumvars' (mean) `meanvars', by(pension_type)
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate age_grp = 999 			// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_type', emptyok replace
		restore
		
		
		**********
		// In-year reporting totals:
		preserve
			// Collapse
			collapse (sum) `sumvars' (mean) `meanvars_totals'
			generate year = `yr'
			generate gender = 99 			// Totals placeholder
			generate age_grp = 999 			// Totals placeholder
			generate pension_type = 999 	// Totals placeholder
			generate pension_class = 999	// Totals placeholder
			// Save totals
			save `pension_total', emptyok replace
		restore
		
		
		// Accumulate in-year reporting into reporting database - TOTALS
		preserve
			use `inyear_pension_reporting_tot', clear
			append using `pension_total'
			save `inyear_pension_reporting_tot', replace
		restore
		
		
		// Accumulate in-year reporting into reporting database - BREAKDOWNS
		preserve
			use `inyear_pension_reporting', clear
			append using `pension_age_gender_class_type'
			append using `pension_age_gender_class'
			append using `pension_age_gender_type'
			append using `pension_age_class_type'
			append using `pension_gender_class_type'
			append using `pension_age_gender'
			append using `pension_gender_class'
			append using `pension_gender_type'
			append using `pension_age_class'
			append using `pension_age_type'
			append using `pension_class_type'
			append using `pension_gender'
			append using `pension_age'
			append using `pension_class'
			append using `pension_type'
			save `inyear_pension_reporting', replace
		restore
		
		


		// Drop reporting variables
		capture drop retired
		capture drop disabled
		capture drop widowed
		capture drop deceased	

		
		
		**********
		// Stage 5: Update values
		replace age  = age  + 1 if status != 99
		replace year = year + 1
		
		
		} // end forvalues yr


********************************************************************************
//	Final reporting on the pensioner database
	// Clean up tempvars before saving
	capture drop __00*
	
	// Export the data
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Pensioners-`startyear'-`endyear'.csv", replace	
	
	





********************************************************************************



		
********************************************************************************
//	Export in-year affiliate reporting	- TOTALS
	use `inyear_affiliate_reporting_tot', clear
	
	// Define labels to identify placeholders
	label define decile_LAB 99 	"Total", add
	label define gender_LAB ///
		 1 "Male"	/// 
		 2 "Female"	///
		99 "Total"	, add
	label define dens_LAB ///
		 1 "Active"	/// 
		 0 "Inactive"	///
		99 "Total"	, add
	
	// Add labels
	label values wage_decile 	decile_LAB
	label values gender 		gender_LAB
	label values dens 			dens_LAB

	
	// Order the data
	order year gender wage_decile dens
	
	// Export dataset
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Inyear-Affiliate-Reporting-Totals.csv", replace
	
	
********************************************************************************
//	Export in-year affiliate reporting	- BREAKDOWNS
	use `inyear_affiliate_reporting', clear
	
	// Define labels to identify placeholders
	label define decile_LAB 99 	"Total"
	label define gender_LAB ///
		 1 "Male"	/// 
		 2 "Female"	///
		99 "Total"	, add
	capture label define dens_LAB ///
		 1 "Active"	/// 
		 0 "Inactive"	///
		99 "Total"	, add
	
	// Add labels
	label values wage_decile 	decile_LAB
	label values gender 		gender_LAB
	label values dens 			dens_LAB

	
	// Order the data
	order year gender wage_decile dens
	
	// Export dataset
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Inyear-Affiliate-Reporting-Breakdowns.csv", replace
	

********************************************************************************
//	Export in-year pensioner reporting	

	// Open the dataset
	use `inyear_pension_reporting_tot', clear
	
	// Checks for common issues:
	assert !missing(year)          // Ensure every row has a year (missing year = broken accumulation)
	assert !missing(gender)        // Placeholder 99 should be present, but never truly missing
	assert pension_type != .       // All rows should have a pension type or the 999 placeholder
		
	// Define labels to identify placeholders	
	label define age_LAB			999	"Total", add
	label define pension_type_LAB	999	"Total", add
	label define pension_class_LAB	999	"Total", add
	label define gender_LAB ///
		 1 "Male"	/// 
		 2 "Female"	///
		99 "Total"	, add
		
	// Add labels
	label values gender 		gender_LAB
	label values pension_type 	pension_type_LAB
	label values pension_class	pension_class_LAB
	label values age_grp 		age_LAB
	
	// Order the data
	order year gender age_grp
	
	// Export dataset
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Inyear-Pensioner-Reporting-Totals.csv", replace
	
	
	
********************************************************************************
//	Export in-year pensioner reporting	
//	[TODO: Check that this works as intended]

	// Open the dataset
	use `inyear_pension_reporting', clear
		
	
	// Checks for common issues:
	assert !missing(year)          // Ensure every row has a year (missing year = broken accumulation)
	assert !missing(gender)        // Placeholder 99 should be present, but never truly missing
	assert pension_type != .       // All rows should have a pension type or the 999 placeholder
		
	// Define labels to identify placeholders
	label define age_LAB			999	"Total", add
	label define pension_type_LAB	999	"Total", add
	label define pension_class_LAB	999	"Total", add
	label define gender_LAB ///
		 1 "Male"	/// 
		 2 "Female"	///
		99 "Total"	, add
		
	// Add labels
	label values gender 		gender_LAB
	label values pension_type 	pension_type_LAB
	label values pension_class	pension_class_LAB
	label values age 			age_LAB
	
	// Order the data
	order year gender age
	
	// Export dataset
	*cd "`outdir'"
	export delimited using "`outdir'\1_PROSTv2-`simname'-Inyear-Pensioner-Reporting-Breakdowns.csv", replace
	
	
********************************************************************************

*} // end quietly


// 	Timer
	timer off 1
	timer list 1
	




********************************************************************************
********************************************************************************
//	PROGRAMS
********************************************************************************
********************************************************************************

// [TODO: Add programs for repetetive code]



/********************** UPDATE LABOUR MARKET **********************************/
capture program drop update_labour_market
program define update_labour_market
	version 15

	

 
	
end // end update_labour_market function


/********************** PENSION RULES *****************************************/
capture program drop pension_rules
program define pension_rules
	version 15

	


	
end // end pension_rules function


/************************** REPORTING *****************************************/
capture program drop reporting
program define reporting
	version 15

	

 
	
end // end reporting function









