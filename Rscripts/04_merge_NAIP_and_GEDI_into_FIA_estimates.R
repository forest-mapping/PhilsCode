# Merge NAIP CHMs into FIA estimates with default and NLCD masks

library (dplyr)
library(tidyr)
library(data.table)

path_GEDI_default <- file.path ("/home/rstudio/data/GEDI/CHM/default")
path_GEDI_NLCD <- file.path ("/home/rstudio/data/GEDI/CHM/NLCD")
path_NAIP_noWater <- file.path ("/home/rstudio/data/NAIP/CHM/noWater/")
path_NAIP_GEDI <- file.path ("/home/rstudio/data/NAIP/CHM/GEDI/")
path_NAIP_NLCD <- file.path ("/home/rstudio/data/NAIP/CHM/NLCD/")
fn_STATES <- "/home/rstudio/data/Government/STATES.csv"
fn_FIAcounties <- "/home/rstudio/data/FIADB/CSV_DATA/COUNTY.csv"
path_RDS <- file.path("/home/rstudio/data/FIADB/RDS/")

# must designate which states are calculated
# states <- c("37","47","51")
states <- c("NC","VA","TN")

countiesFIA <- read.csv(fn_FIAcounties,stringsAsFactors = FALSE)
# import table with state abbreviations and two-digit code
statesUS <- read.csv(fn_STATES,stringsAsFactors = FALSE) %>% dplyr::filter(STATE <= 56) %>% 
  dplyr::select(-STATENS) %>% # only US states
  dplyr::rename(STATECD = STATE, STATENAME = STATE_NAME)
statesUS <- statesUS[statesUS$STATECD %in% countiesFIA$STATECD,]  # gets rid of DC

# import fia estimates
FIA_est_fn <- dir(path_RDS,pattern="^fia_estimates.*.RDS$")

FIA_estimates <- do.call(rbind,lapply(FIA_est_fn,function(x)readRDS(file.path(path_RDS,x)))) %>%
  mutate(STATECD=as.integer(STATECD)) %>% rename(COUNTY_FIPS=co_fips)

# import CHM from GEDI default and GEDI*NLCD
calc_chm <- function (stateAbbrev){
  path_chm_GEDI <- file.path(path_GEDI_default, paste0(stateAbbrev)) 
  df1 <- read.csv(file.path(path_chm_GEDI,"CHM_dist_by_county.csv")) %>% 
    dplyr:: mutate (SOURCE=c("GEDI_default")) %>%
    pivot_wider(names_from=BIN_HT,values_from = km2,id_cols=STATECD:SOURCE)
  
  path_chm_GEDI_NLCD <- file.path(path_GEDI_NLCD, paste0(stateAbbrev)) 
  df2 <- read.csv(file.path(path_chm_GEDI_NLCD,"CHM_dist_by_county.csv")) %>% 
    dplyr:: mutate (SOURCE=c("GEDI_NLCD")) %>%
    pivot_wider(names_from=BIN_HT,values_from = km2,id_cols=STATECD:SOURCE)
  
 df <- rbind(df1,df2) %>% dplyr::arrange(COUNTYNAME,SOURCE) %>% 
   mutate(COUNTY_FIPS = STATECD*1000 + COUNTYCD)
}

chm <- do.call(rbind,lapply(states,function(x)calc_chm(x)))
FIA_GEDI <- left_join(FIA_estimates,chm)

# import CHM from NAIP noWater, GEDI, and GEDI*NLCD
calc_chm <- function (stateAbbrev){
  path_chm_NAIP <- file.path(path_NAIP_noWater, paste0(stateAbbrev)) 
  df1 <- read.csv(file.path(path_chm_NAIP,"CHM_dist_by_county.csv")) %>% 
    dplyr:: mutate (SOURCE=c("NAIP_noWater")) %>%
    pivot_wider(names_from=BIN_HT,values_from = km2,id_cols=STATECD:SOURCE)
  
  path_chm_NAIP_GEDI <- file.path(path_NAIP_GEDI, paste0(stateAbbrev)) 
  df2 <- read.csv(file.path(path_chm_NAIP_GEDI,"CHM_dist_by_county.csv")) %>% 
    dplyr:: mutate (SOURCE=c("NAIP_GEDI")) %>%
    pivot_wider(names_from=BIN_HT,values_from = km2,id_cols=STATECD:SOURCE)
  
  df <- rbind(df1,df2) %>% dplyr::arrange(COUNTYNAME,SOURCE)

  path_chm_NAIP_NLCD <- file.path(path_NAIP_NLCD, paste0(stateAbbrev)) 
  df3 <- read.csv(file.path(path_chm_NAIP_NLCD,"CHM_dist_by_county.csv")) %>% 
    dplyr:: mutate (SOURCE=c("NAIP_NLCD")) %>%
    pivot_wider(names_from=BIN_HT,values_from = km2,id_cols=STATECD:SOURCE)
  
  df <- rbind(df,df3) %>% dplyr::arrange(COUNTYNAME,SOURCE) %>% 
    mutate(COUNTY_FIPS = STATECD*1000 + COUNTYCD)
}

chm <- do.call(rbind,lapply(states,function(x)calc_chm(x)))

FIA_NAIP <- left_join(FIA_estimates,chm) 

saveRDS(FIA_GEDI,file = file.path("/home/rstudio/data/GEDI/FIA_GEDI_for_Fay-Herriot.RDS"))
saveRDS(FIA_NAIP,file = file.path("/home/rstudio/data/NAIP/FIA_GEDI_for_Fay-Herriot.RDS"))

saveRDS(rbind(FIA_GEDI,FIA_NAIP),
        file = file.path("/home/rstudio/data/FIADB/RDS/FIA_GEDI_for_Fay-Herriot.RDS"))
