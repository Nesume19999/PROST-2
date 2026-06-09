/******************************************************************************* 
Title: 			Generate affiliation rates from cross-sectional data in a LOW DATA environment
Author: 		Duncan MacDonald 
Date created: 	June 2nd, 2026
Description:	For building PROST v2 pension model

	
	
Note: This code uses gtools and ftools to speed up processing
Source: https://gtools.readthedocs.io/en/latest/
Source: https://github.com/sergiocorreia/ftools

Commands:
ssc install gtools
ssc install ftools
ssc install zoib


Note:	We assume that the low data environment is either cross sectional monthly 
		data for the latest year, or aggregated contribution data for each active 
		individual
			
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
	local indir		 = "${root}/Input"
	local homedir 	 = "${rawdir}"
	local histpopdir = "${root}/Input/Defaults/population_obs"
	local affdir 	 = "${root}/Input/Defaults/affiliation"

//	Simulation parameters
	local years_avg 	= 10  	// Number of years of back data that are averaged to generate 
	local minimum_age 	= 15	// Minimum age to consider (some young ages don't have a lot of data)
	
//	Name of input data
	local low_data 		= "lowdata_`country'"
	local very_low_data = "verylowdata_`country'"
	local extremely_low_data = "extremelylowdata_`country'"
	local long_data  	= "2 Input from client - longitudinal microdata about affiliates.dta"
	local histpop_data = "population_historical_MEX.dta"
	
//	Name of output data
	local affiliation_outdata = "affiliation_`country'_`years_avg'_EXTREMELY_LOW_DATA"
	

	
********************************************************************************
// 	Open the cross-sectional microdata about affiliates - LOW DATA
	cd "`indir'"
	use "`extremely_low_data'",clear
	
//	Get the latest year of the dataset
	summarize year
	local latest_year = r(max)
	
//	Rename some variables
	rename aux loa 	// Length of affiliation (months)
	
// 	Sort the annual data into 5-year bands (to reduce noise)
	generate age = year - yob				
	
	
//	Generate affiliation year/
//	Note: We assume that our year data is end-of-year data [and so use floor]	
	generate year_affiliated = year - floor(loa / 12)
	*generate year_affiliated = year - round(loa / 12, -1)

	
//	Compute age affilated
	generate age_affiliated = max(age - floor(loa / 12), 0) 
	*generate age_affiliated = max(age - round(loa / 12, -1), 0) 

	
//	Keep only one observation per person
	*keep if month == 12
	
	
********************************************************************************
	
//	ADJUSTMENT FOR NON_ACTIVE CONTRIBUTORS


//	Model the in-year contribution density
	generate dens_share = dens / 12

// 	Zero-or-One Inflated Beta (ZOIB) Regression
//	See: https://www.sciencedirect.com/science/article/abs/pii/S0167947311003628
	zoib dens_share i.gender, oneinflate(age i.gender)


//	Extract the linear prediction for the mean and scale parameters
//	Note: Because zoib uses a logit link for the mean, we must use invlogit()
//	Note: Because zoib uses a log link for precision, we use exp()
	predict double xb, xb
	generate b_mu = invlogit(xb)
	generate b_phi = exp(xb_lnphi)

//	Transform into your Alpha and Beta shape parameters
	generate b_alpha = b_mu * b_phi
	generate b_beta  = (1 - b_mu) * b_phi

//	Get the explicit probability of being a pure 1 from the inflation equation
	predict p_pure_one, pr1
	generate p_continuous_interval = 1 - p_pure_one

//	Calculate the conditional probability mass shifting into the 0-state
	generate implied_p_zero = (1 / (1 + b_alpha)) * p_continuous_interval
	replace implied_p_zero = 0 if b_alpha >= 1 // If Alpha > 0 then no smile curve at 0

//	Calculate your final population expansion headcount multiplier
	generate expansion_factor = 1 / (1 - implied_p_zero)









	
********************************************************************************	
	
//	Affiliation rates
//	Note that the longitudinal data include just affiliates 
//	It does not include those who have already retired (but who contributed in the past)
//	This is good as it shows a snapshot of individuals and when they started contributing

//	Keep only those people who newly join the system
	*keep if los == 1 & aux == 1
	
//	Collapse the data 
	*collapse (count) affiliates=id, by(year_affiliated age_affiliated gender)
	collapse (sum) affiliates=expansion_factor, by(year_affiliated age_affiliated gender)
	rename year_affiliated year
	rename age_affiliated age
	
//  Keep only the most recent years
	keep if year > `latest_year'  - `years_avg'
	keep if age >= `minimum_age'


	
//	Merge in historical population data (data is in '000s)
	cd "`histpopdir'"
	merge 1:1 year gender age using "`histpop_data'", keep(1 3) keepusing(pop) nogenerate
	
//	Compute average affiliation rates
	collapse (sum) affiliates pop, by(age gender)
	generate affiliation_rate = affiliates / (pop * 1000)		// Rate of new affiliated joining the pension system
	drop affiliates pop
	
	
********************************************************************************	
//	Save the dataset
//	Note: we save as a CSV so that users can adjust it
	cd "`affdir'"
	export delimited "`affiliation_outdata'.csv", replace

********************************************************************************
