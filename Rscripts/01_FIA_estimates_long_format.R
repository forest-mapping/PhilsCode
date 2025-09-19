# Convert FIA state*county direct estimates of vol & biomass to SI and assign mountain codes
# save result in long format
# must designate which states are calculated
states <- c("37","47","51")

# need to list the names and path for all R scripts that are run previously
# probably ~/GEDI/masked_NAIP.R and GEDI_FH.R


# This code is designed to organize the data set from FIA with remote-sensing sources

# must include ~/GEDI/getPopEstwVar.R (generate the volume(vol_by_fips_su) and biomass(bio_by_fips_su)from FIA database)
# if RDS files are not current, re-run getPopEstwVar.R. Otherwise read existing RDS files
# source("/home/qianqian/GEDI/getPopEstwVar.R")
path_RDS <- file.path("/home/rstudio/data/FIADB/RDS/")
bio_by_fips_su <- readRDS(file.path(path_RDS,"bio_by_fips_su.RDS"))
vol_by_fips_su <- readRDS(file.path(path_RDS,"vol_by_fips_su.RDS"))

library(dplyr)
library(tidyr)
library(stringr)

# FIA county-level biomass survey (direct estimates)

# bio_by_fips_su has code=county_fips+0.1*survey unit
bio_by_fips_su$code <- as.character(bio_by_fips_su$`PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1`*10)
str(bio_by_fips_su)

# subtract the last digit in code, which is the survey unit code defined in FIA
bio_by_fips_su$surveyunit <-str_sub(bio_by_fips_su$code,-1)

# create county fips code (co_fips)
bio_by_fips_su$co_fips<-as.numeric(substr(bio_by_fips_su$code,1,5))

# FIA county-level volume survey (direct estimates)
vol_by_fips_su$code <- as.character(vol_by_fips_su$`PLOT.STATECD * 1000 + PLOT.COUNTYCD+ PLOT.UNITCD *0.1`*10)
vol_by_fips_su$surveyunit <-str_sub(vol_by_fips_su$code,-1)
vol_by_fips_su$co_fips<-as.numeric(substr(vol_by_fips_su$code,1,5))

# "countylevel_by_state" function that prepare county-level volume/biomass by state code
# must include the national wide FIA survey data (not including DC)
# Voume: choose state code(STATECD), county code(co_fips), FIA survey unit (surveyunit),
# Volume (VOLCFGRS),variance of volume (var_of_estimate), and year (YEAR)
# change unit (1) volume from ft^3 to million meters^3; (2) variance of biomass from cubic feet^2 to (million meter)^2
# Biomass: choose state code(STATECD), county code(co_fips), FIA survey unit (surveyunit),
# biomass(DRYBIO_AG),variance of biomass (var_of_estimate), and year (YEAR)
# change unit (1) biomass from pound to million kg; (2) variance of biomass from pound^2 to (million kg)^2

calc_vol_bio<-function(statecode){
  df1 <- vol_by_fips_su %>%
    dplyr::mutate (response=c("Volume"),value=VOLCFGRS*0.0283168/1e6, var=var_of_estimate*(0.0283168/1e6)^2) %>% 
    dplyr::select(STATECD,co_fips,surveyunit,response,value,var,YEAR) %>% filter (STATECD==statecode)

  df2 <- bio_by_fips_su %>%
    dplyr::mutate (response=c("Biomass"),value=DRYBIO_AG*0.453592/1e6, var=var_of_estimate*(0.453592/1e6)^2) %>% 
    dplyr::select(STATECD,co_fips,surveyunit,response,value,var,YEAR) %>% filter (STATECD==statecode)
  
  rbind(df1,df2) %>% dplyr::arrange(STATECD,co_fips,surveyunit,response)
}

fia_estimates <- do.call(rbind,lapply(states,function(x)calc_vol_bio(x)))

# assign mountain indicator by survey unit
mountain_codes <- read.csv(file.path(path_RDS,"../mountain_ref.csv"),stringsAsFactors = FALSE,
                           colClasses = c("character","character","integer"))

fia_estimates <- left_join(fia_estimates,mountain_codes)

saveRDS(fia_estimates,file=file.path(path_RDS,paste0("fia_estimates_TN_NC_VA.RDS")))
# lapply(states,function(x)saveRDS(fia_estimates,file=file.path(path_RDS,paste0("fia_estimates_TN_NC_VA.RDS"))))
# at this point the fia county level estimates are calculated in long format
# saved in /home/rstudio/data/FIADB/RDS
