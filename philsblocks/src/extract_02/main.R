library(psaeRuntimeConnector)

require(raster)
# require(rgdal)
require(sf)
require(data.table)
require(snow)
require(crayon)
require(terra)


path_gedi_default <- "./data/GEDI/CHM/default/"
path_gedi_nlcd <- "./data/GEDI/CHM/NLCD/"
path_naip_default <- "./data/NAIP_CHM_noWater/VA" # this needs to be generalized 
naip_default_fn <- dir(path_naip_default, pattern = "*.tif")


handler <- function(args) {
    mask_GEDI_NLCD <- function(i) {
        i <- 1
        COUNTY <- substr(naip_default_fn[i], 5, nchar(naip_default_fn[i]) - 12)
        countyCD <- as.integer(substr(
            counties_1_state$COVER_ID[counties_1_state$COUNTY == COUNTY],
            3,
            5
        ))[1]
        # print(paste(COUNTY %in% counties_1_state$COUNTY,COUNTY,"County"))
        default <- rast(file.path(path_naip_default, files[i]))
        countynameLC <- countiesFIA_1_state$COUNTYNM[
            countiesFIA_1_state$COUNTYCD == countyCD
        ]
        if (grepl(" Of ", countynameLC) | grepl(" And ", countynameLC)) {
            countynameLC <- gsub(" Of ", " of ", countynameLC)
            countynameLC <- gsub(" And ", " and ", countynameLC)
        }
        gedi_fn <- naip_gedi_fn[grep(
            x = naip_gedi_fn,
            pattern = paste0(countynameLC, ".tif")
        )]

        temp_path <- file.path(path_gedi_default, stateAbbrev, gedi_fn)
        print(temp_path)
        gedi <- rast(temp_path)
        nlcd_fn <- naip_nlcd_fn[grep(
            x = naip_nlcd_fn,
            pattern = paste0(countynameLC, "_forest.tif")
        )]
        nlcd <- rast(file.path(path_gedi_nlcd, stateAbbrev, nlcd_fn))
        # crs(default)
        system.time({
            gedi_aea <- reproject_align_raster(gedi, default)
            nlcd_aea <- reproject_align_raster(nlcd, ref_rast = default)
            gedi_10m <- resample(gedi_aea, default)
            nlcd_10m <- resample(nlcd_aea, default)
        })

        # mask gedi NA and zero values in default NAIP CHM
        temp <- c(default, gedi_10m)
        # NA values in raster2 (gedi_10m) cause raster1 (default) cells to be set to NA
        temp[][, 1][is.na(temp[][, 2])] <- NA
        # 0 values in raster2 (gedi_10m) cause raster1 (default) cells to be set to 0
        temp[][, 1][temp[][, 2] == 0] <- 0
        naip_gedi <- terra::subset(temp, 2)

        # mask NLCD NA and zero values in default NAIP CHM
        temp <- c(default, nlcd_10m)
        # NA values in raster2 (nlcd_10m) cause raster1 (default) cells to be set to NA
        temp[][, 1][is.na(temp[][, 2])] <- NA
        # 0 values in raster2 (nlcd_10m) cause raster1 (default) cells to be set to 0
        temp[][, 1][temp[][, 2] == 0] <- 0
        naip_nlcd <- terra::subset(temp, 2)

        # path_chm_GEDI
        # path_chm_NLCD

        if (args %in% c("North Carolina", "Tennessee", "Virginia")) {
            raster::writeRaster(
                naip_gedi,
                overwrite = TRUE,
                filename = file.path(
                    path_chm_GEDI,
                    paste0(countyCD, "_", COUNTY, ".img")
                )
            )
            raster::writeRaster(
                naip_nlcd,
                overwrite = TRUE,
                filename = file.path(
                    path_chm_NLCD,
                    paste0(countyCD, "_", COUNTY, ".img")
                )
            )

            png(
                filename = file.path(
                    path_chm_GEDI,
                    paste0(countyCD, "_", COUNTY, ".png")
                ),
                width = 4,
                height = 4,
                units = "in",
                res = 300
            )
            plot(naip_gedi, main = paste0(countynameLC, " County, GEDI mask"))
            dev.off()
            png(
                filename = file.path(
                    path_chm_NLCD,
                    paste0(countyCD, "_", COUNTY, ".png")
                ),
                width = 4,
                height = 4,
                units = "in",
                res = 300
            )
            plot(naip_nlcd, main = paste0(countynameLC, " County, NLCD mask"))
            dev.off()
        }
    }

    # path_nlcd <- "./data/NLCD/"

    stateAbbrev <- state.abb[state.name == args]

    # path to UScounties shapefile
    path_counties <- "data/FIA_SE_Counties_shapefile/counties4project.shp"
    fn_FIAcounties <- "data/CSV_DATA/COUNTY.csv"
    # fn_FIAunits <- "./data/FIADB/CSV_DATA/REF_UNIT.csv"
    fn_STATES <- "data/CSV_DATA/STATES.csv"

    # Set pathnames (OUTPUTS)
    path_chm_GEDI <- file.path("./data/NAIP/CHM/GEDI", stateAbbrev)
    path_chm_NLCD <- file.path("./data/NAIP/CHM/NLCD", stateAbbrev)
    # path_nlcd_1_state <- file.path(path_nlcd,stateAbbrev) # won't need the state raster since county-level gedi CHMs have the NLCD mask

    # create output paths if needed
    if (!dir.exists(path_chm_NLCD)) {
        dir.create(path_chm_NLCD)
    }
    if (!dir.exists(path_chm_GEDI)) {
        dir.create(path_chm_GEDI)
    }
    # if(!dir.exists(path_nlcd_1_state)) dir.create(path_nlcd_1_state)

    # Read INPUTS
    counties4project <- st_read(path_counties)
    countiesFIA <- read.csv(fn_FIAcounties, stringsAsFactors = FALSE)
    statesUS <- read.csv(fn_STATES, stringsAsFactors = FALSE) %>%
        dplyr::filter(STATE <= 56) %>%
        dplyr::select(-STATENS) %>% # only US states
        dplyr::rename(STATECD = STATE, STATENAME = STATE_NAME)
    statesUS <- statesUS[statesUS$STATECD %in% countiesFIA$STATECD, ] # gets rid of DC

    stateCD <- statesUS$STATECD[statesUS$STATENAME == args]
    counties_1_state <- counties4project[counties4project$STATE == args, ] %>%
        data.frame()
    countiesFIA_1_state <- countiesFIA[
        countiesFIA$STATECD == stateCD,
        c("STATECD", "UNITCD", "COUNTYCD", "COUNTYNM")
    ]

    # Extract target state (args) from raster layers -------------------------
    naip_gedi_fn <- dir(
        file.path(path_gedi_default, stateAbbrev),
        pattern = ".tif$"
    )
    naip_nlcd_fn <- dir(
        file.path(path_gedi_nlcd, stateAbbrev),
        pattern = ".tif$"
    )
    countyLC <- substr(naip_gedi_fn, 5, nchar(naip_gedi_fn) - 4)

    # mask NAIP CHM for county i raster in directory list

    files <- list.files(path_naip_default)

    lapply(seq_along(naip_default_fn), function(x) mask_GEDI_NLCD(x))
    # lapply(69:72,function(x)mask_GEDI_NLCD(x))

    print(cat("Program complete.\n"))
    stop(paste0(
        "Program complete.\n",
        args,
        " NAIP CHMs masked and written to ",
        path_chm_GEDI,
        "\nand ",
        path_chm_NLCD
    ))
}
