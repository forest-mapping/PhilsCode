# Extract_County_CHM_NAIP_serial.R
# Purpose: Mask existing NAIP county CHMs to GEDI and NLCD masks
#          Apply two "masks" 1) GEDI  and 2) NLCD mask for forests in classes 41-43 and 90
# Instructions: This script runs best from a (linux) command line, for example:
#               nohup Rscript Extract_County_CHM_NAIP_serial.R "North Carolina" &> log_NC.txt &
#               notes: a) nohup allows the script to run after logging off
#                      b) Rscript Extract_County_CHM_GEDI_serial.R "North Carolina" runs the script with a state name specified at the command line
#                      c) &> log_NC.txt saves the program output (any error messages) in log_NC.txt (NC for North Carolina)
#                      d) & runs the program in the background so that other states can be run at the same time
#                      e) recommend running < 10 states at one time due to memory limits on charcoal2
# This is a serial version (not parallelized). A parallel function in reproject_align_raster.R works sporadically
# can be run for a single state in Rstudio (uncomment line 42: args = "Virginia")
# REQUIRES THAT DEFAULT NAIP CHMs WERE PREVIOUSLY MADE AND STORED IN path_naip_default

# source reproject_align_raster.R, e.g., "/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_align_raster.R"
# source("/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_align_raster.R")
source("/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_spat_raster.R")

require(raster)
# require(rgdal)
require(sf)
require(data.table)
require(snow)
require(crayon)
# rgdal::setCPLConfigOption("GDAL_PAM_ENABLED", "FALSE")
# Goal: Extract rasters from GEDI CHM clipped to county polygons
# Steps:
#    SECTION Read data: gediNAM30m (CHM); UScounties (shapefile); nlcd_2019_land_cover_l48_20210604.img; FIAcounties (ref table)
#
#    SECTION Extract target state (args) from raster layers
#    Transform (reproject) counties_1_state to match gediNAM30m
#    Transform (reproject) counties_1_state to match NLCD
#    Extract gediNAM30m_1_state from gediNAM30m
#    Extract nlcd_2019_land_cover_1_state from nlcd_2019_land_cover
#    Transform (reproject) nlcd_2019_land_cover_1_state and counties_1_state to match gediNAM30m_1_state

#    SECTION Extract county CHMs from raster layers gediNAM30m_1_state and save to CHM/default
#    Extract counties_1_state from UScounties
#    Mask/reclassify gediNAM30m_1_state_NLCD_mask from gediNAM30m_1_state based on nlcd_2019_land_cover_1_state forest cover classes
#    Extract county CHMs from gediNAM30m_1_state_NLCD_mask and save to CHM/NLCD

args = commandArgs(trailingOnly = TRUE)
# test only
# args = "Tennessee" # c("North Carolina","Tenneessee","Virginia)

# Read data ---------------------------------------------------------------
#    Read data: gediNAM30m (CHM); UScounties (shapefile); nlcd_2019_land_cover_l48_20210604.img; FIAcounties (ref table)
# Set pathnames (INPUTS) for mask layers (CHMs) from GEDI and NLCD
# and for the shared path to NAIP default (noWater) CHM
path_naip <- "/home/rstudio/data/NAIP/CHM"
path_gedi_default <- "/home/rstudio/data/GEDI/CHM/default/"
path_gedi_nlcd <- "/home/rstudio/data/GEDI/CHM/NLCD/"
# path_nlcd <- "/home/rstudio/data/NLCD/"
if (!dir.exists(path_naip)) {
  stop("No input path ", path_naip)
}
if (!dir.exists(path_gedi_default)) {
  stop("No input path ", path_gedi_default)
}
if (!dir.exists(path_gedi_nlcd)) {
  stop("No input path ", path_gedi_nlcd)
}
stateAbbrev <- state.abb[state.name == args]
path_naip_default <- file.path(path_naip, "noWater", stateAbbrev)
if (!dir.exists(path_naip_default)) {
  stop("No input path ", path_naip_default)
}

# path to UScounties shapefile
path_counties <- "/home/rstudio/data/Government/Counties/counties4project.shp"
fn_FIAcounties <- "/home/rstudio/data/FIADB/CSV_DATA/COUNTY.csv"
# fn_FIAunits <- "/home/rstudio/data/FIADB/CSV_DATA/REF_UNIT.csv"
fn_STATES <- "/home/rstudio/data/Government/STATES.csv"

# Set pathnames (OUTPUTS)
path_chm_GEDI <- file.path("/home/rstudio/data/NAIP/CHM/GEDI", stateAbbrev)
path_chm_NLCD <- file.path("/home/rstudio/data/NAIP/CHM/NLCD", stateAbbrev)
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
naip_default_fn <- dir(path_naip_default, pattern = "*.tif$")
naip_gedi_fn <- dir(
  file.path(path_gedi_default, stateAbbrev),
  pattern = ".tif$"
)
naip_nlcd_fn <- dir(file.path(path_gedi_nlcd, stateAbbrev), pattern = ".tif$")
countyLC <- substr(naip_gedi_fn, 5, nchar(naip_gedi_fn) - 4)

# mask NAIP CHM for county i raster in directory list
mask_GEDI_NLCD <- function(i) {
  COUNTY <- substr(naip_default_fn[i], 5, nchar(naip_default_fn[i]) - 12)
  countyCD <- as.integer(substr(
    counties_1_state$COVER_ID[counties_1_state$COUNTY == COUNTY],
    3,
    5
  ))[1]
  # print(paste(COUNTY %in% counties_1_state$COUNTY,COUNTY,"County"))
  default <- rast(file.path(path_naip_default, naip_default_fn[i]))
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
  gedi <- rast(file.path(path_gedi_default, stateAbbrev, gedi_fn))
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
      filename = file.path(path_chm_GEDI, paste0(countyCD, "_", COUNTY, ".img"))
    )
    raster::writeRaster(
      naip_nlcd,
      overwrite = TRUE,
      filename = file.path(path_chm_NLCD, paste0(countyCD, "_", COUNTY, ".img"))
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

lapply(1:length(naip_default_fn), function(x) mask_GEDI_NLCD(x))
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
