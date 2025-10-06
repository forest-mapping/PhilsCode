library(psaeRuntimeConnector)
library(dplyr)
library(tidyr)
library(stringr)


states <- c("37", "47", "51")

# need to list the names and path for all R scripts that are run previously
# probably ~/GEDI/masked_NAIP.R and GEDI_FH.R

# This code is designed to organize the data set from FIA with remote-sensing sources

# must include ~/GEDI/getPopEstwVar.R (generate the volume(vol_by_fips_su) and biomass(bio_by_fips_su)from FIA database)
# if RDS files are not current, re-run getPopEstwVar.R. Otherwise read existing RDS files
# source("/home/qianqian/GEDI/getPopEstwVar.R")
path_RDS <- file.path("./data/FIADB/RDS/")
bio_by_fips_su <- readRDS(file.path(path_RDS, "bio_by_fips_su2017.RDS"))
#vol_by_fips_su <- readRDS(file.path(path_RDS, "vol_by_fips_su.RDS"))


calc_vol_bio <- function(statecode) {
    #df1 <- vol_by_fips_su %>%
    #    dplyr::mutate(
    #        response = c("Volume"),
    #        value = VOLCFGRS * 0.0283168 / 1e6,
    #        var = var_of_estimate * (0.0283168 / 1e6)^2
    #    ) %>%
    #    dplyr::select(
    #        STATECD,
    #        co_fips,
    #        surveyunit,
    #        response,
    #        value,
    #        var,
    #        YEAR
    #    ) %>%
    #    filter(STATECD == statecode)

    df2 <- bio_by_fips_su %>%
        dplyr::mutate(
            response = c("Biomass"),
            value = DRYBIO_AG * 0.453592 / 1e6,
            var = var_of_estimate * (0.453592 / 1e6)^2
        ) %>%
        dplyr::select(
            STATECD,
            co_fips,
            surveyunit,
            response,
            value,
            var,
            YEAR
        ) %>%
        filter(STATECD == statecode)

    #rbind(df1, df2) %>% 
    return(df2 %>% dplyr::arrange(STATECD, co_fips, surveyunit, response))
}


handler <- function() {

    # this is something that we can remove?
    #input_file_path <- psaeRuntimeConnector::to_path(input_data)
    #bio_by_fips_su <- readRDS(input_file_path)

    # bio_by_fips_su has code=county_fips+0.1*survey unit
    bio_by_fips_su$code <- as.character(
    bio_by_fips_su$`PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1` * 10
    )
    str(bio_by_fips_su)

    # subtract the last digit in code, which is the survey unit code defined in FIA
    bio_by_fips_su$surveyunit <- str_sub(bio_by_fips_su$code, -1)

    # create county fips code (co_fips)
    bio_by_fips_su$co_fips <- as.numeric(substr(bio_by_fips_su$code, 1, 5))

    # FIA county-level volume survey (direct estimates)
    #vol_by_fips_su$code <- as.character(
    #vol_by_fips_su$`PLOT.STATECD * 1000 + PLOT.COUNTYCD+ PLOT.UNITCD *0.1` * 10
    #)
    #vol_by_fips_su$surveyunit <- str_sub(vol_by_fips_su$code, -1)
    #vol_by_fips_su$co_fips <- as.numeric(substr(vol_by_fips_su$code, 1, 5))


    fia_estimates <- do.call(rbind, lapply(states, function(x) calc_vol_bio(x)))

    # assign mountain indicator by survey unit
    mountain_codes <- read.csv(
        file.path("./data/mountain_ref.csv"),
        stringsAsFactors = FALSE,
        colClasses = c("character", "character", "integer")
    )

    fia_estimates <- left_join(fia_estimates, mountain_codes)


    output_file <- file.path(path_RDS, paste0("fia_estimates_TN_NC_VA.RDS"))
    saveRDS(
        fia_estimates,
        file = output_file)
        
    return(psaeRuntimeConnector::new_file(output_file))
}
