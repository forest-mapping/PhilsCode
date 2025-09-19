# Extract_County_CHM_GEDI_serial.R
# Purpose: Extract rasters from GEDI CHM clipped to county polygons
#          Apply two "masks" 1) GEDI default (no mask) and 2) NLCD mask for forests in classes 41-43 and 90
# Instructions: This script runs best from a (linux) command line, for example:
#               nohup Rscript Extract_County_CHM_GEDI_serial.R "North Carolina" > log_NC.txt &
#               notes: a) nohup allows the script to run after logging off
#                      b) Rscript Extract_County_CHM_GEDI_serial.R "North Carolina" runs the script with a state name specified at the command line
#                      c) > log_NC.txt saves the program output (any error messages) in log_NC.txt (NC for North Carolina)
#                      d) & runs the program in the background so that other states can be run at the same time
#                      e) recommend running < 10 states at one time due to memory limits on charcoal2
# This is a serial version (not parallelized).
# can be run for a single state in Rstudio (uncomment line 40: args = "Virginia")

# source reproject_align_raster.R, e.g., "/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_align_raster.R"
source("/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_spat_raster.R")

require(raster)
require(terra)
require(sf)
require(data.table)
require(snow)
require(crayon)
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

args <- commandArgs(trailingOnly = TRUE)
# test only
# args = "Virginia"

# Read data ---------------------------------------------------------------
#    Read data: gediNAM30m (CHM); UScounties (shapefile); nlcd_2019_land_cover_l48_20210604.img; FIAcounties (ref table)
# Set pathnames (INPUTS)
# shared path to GEDI CHM
path_gedi <- "/home/rstudio/data/GEDI"
path_nlcd <- "/home/rstudio/data/NLCD"


# path to UScounties shapefile
path_UScounties <- "/home/rstudio/data/Government/Counties/USCounties.shp"
fn_FIAcounties <- "/home/rstudio/data/FIADB/CSV_DATA/COUNTY.csv"
fn_FIAunits <- "/home/rstudio/data/FIADB/CSV_DATA/REF_UNIT.csv"
fn_STATES <- "/home/rstudio/data/Government/STATES.csv"

# Set pathnames (OUTPUTS)
stateAbbrev <- state.abb[state.name == args]
path_chm_default <- file.path(
  "/home/rstudio/data/GEDI/CHM/default",
  stateAbbrev
)

# path_chm_NLCD <- file.path("/home/rstudio/data/GEDI/CHM/NLCD",stateAbbrev)
path_chm_NLCD <- file.path("/home/rstudio/data/GEDI/CHM/NLCD52", stateAbbrev)
path_nlcd_1_state <- file.path(path_nlcd, stateAbbrev)

# create output paths if needed
if (!dir.exists(path_chm_default)) {
  dir.create(path_chm_default)
}
if (!dir.exists(path_chm_NLCD)) {
  dir.create(path_chm_NLCD)
}
if (!dir.exists(path_nlcd_1_state)) {
  dir.create(path_nlcd_1_state)
}

# Read INPUTS
countiesUS <- st_read(path_UScounties)
countiesFIA <- read.csv(fn_FIAcounties, stringsAsFactors = FALSE)
unitsFIA <- read.csv(fn_FIAunits, stringsAsFactors = FALSE)
statesUS <- read.csv(fn_STATES, stringsAsFactors = FALSE) %>%
  dplyr::filter(STATE <= 56) %>%
  dplyr::select(-STATENS) %>% # only US states
  dplyr::rename(STATECD = STATE, STATENAME = STATE_NAME)
statesUS <- statesUS[statesUS$STATECD %in% countiesFIA$STATECD, ] # gets rid of DC
# read GEDI CHM North America

# done once to correct CHM area calculations (PJR)
# system.time(gediNAM30m_aea <- reproject_align_raster(gediNAM30m,NLCD))

gediNAM30m <- rast(file.path(path_gedi, "Forest_height_2019_NAM.tif"))
NLCD <- rast(file.path(path_nlcd, "nlcd_2019_land_cover_l48_20210604.img"))

if (!args %in% unique(countiesUS$STATENAME)) {
  stop("Input state entered incorrectly. Program terminated!")
}
# stop()  # comment out this line to allow program to extract counties

# Extract/mask target state (args) from raster layers -------------------------
counties_1_state <- countiesUS[countiesUS$STATENAME == args, ]
# reproject counties to match GEDI CHM data
counties_1_state <- st_transform(counties_1_state, raster::crs(gediNAM30m))
# crop and mask the GEDI raster layer to one state based on the command line value of args
system.time({
  # takes about 3.5 minutes on charcoal2. Using beginCluster() doesn't speed it up.
  gediNAM30m_1_state <- raster::mask(
    raster::crop(gediNAM30m, counties_1_state),
    counties_1_state
  ) # much faster to crop to the extent of the state polygon before masking
  # values > 100 in Potapov CHM are bad values
  gediNAM30m_1_state[gediNAM30m_1_state[] > 100] <- NA
})
counties_1_state_aea <- st_transform(counties_1_state, raster::crs(NLCD))

if (
  !file.exists(file.path(
    path_nlcd_1_state,
    paste0("NLCD_", stateAbbrev, "_aea.img")
  ))
) {
  # reproject counties to match NLCD data
  # counties_1_state <- spTransform(counties_1_state,raster::crs(NLCD))
  counties_1_state_aea <- st_transform(counties_1_state, raster::crs(NLCD))
  # crop and mask the NLCD raster layer to one state based on the command line value of args
  system.time({
    # takes about 3-5 minutes on charcoal2
    NLCD_1_state <- raster::mask(
      raster::crop(NLCD, counties_1_state_aea),
      counties_1_state_aea
    ) # much faster to crop to the extent of the state polygon before masking
  })

  # commented (PJR) out to use NAIP aea coordinate system for proper raster sizing
  # reproject counties to match GEDI CHM data
  # counties_1_state <- spTransform(counties_1_state,raster::crs(gediNAM30m_1_state))
  # # reproject NLCD_1_state to match GEDI CHM data
  # system.time({    # Virginia takes about 2.5 minutes running in parallel on charcoal2 15 min in serial
  #   NLCD_1_state <- reproject_align_raster(NLCD_1_state,ref_rast = gediNAM30m_1_state)
  # })

  # if args %in% c("North Carolina","Tennessee","Virginia") save NLCD_1_state so it can be used in the NAIP mask
  # is there any reason to save the NLCD_1_state raster for every state?
  if (args %in% c("North Carolina", "Tennessee", "Virginia")) {
    if (!dir.exists(file.path(path_nlcd, stateAbbrev))) {
      dir.create(file.path(path_nlcd, stateAbbrev))
    }
    raster::writeRaster(
      NLCD_1_state,
      filename = file.path(
        path_nlcd,
        stateAbbrev,
        paste0(
          "NLCD_",
          stateAbbrev,
          "_aea.img"
        )
      ),
      overwrite = TRUE
    )
  }
} else {
  NLCD_1_state <- rast(file.path(
    path_nlcd_1_state,
    paste0("NLCD_", stateAbbrev, "_aea.img")
  ))
}

#    SECTION Extract county CHMs ----------------------------------------
countiesFIA_1_state <- dplyr::left_join(statesUS, countiesFIA) %>%
  dplyr::select(STATENAME, STATECD, UNITCD, COUNTYCD, COUNTYNM, CN, STUSAB) %>%
  dplyr::filter(STATENAME == args)

# loop through counties and crop+mask then save county-level rasters
test <- lapply(countiesFIA_1_state$COUNTYCD, function(countycode) {
  county <- counties_1_state_aea[
    as.integer(counties_1_state_aea$CENSUSCODE) == countycode,
  ]
  county_aea <- st_transform(county, raster::crs(NLCD_1_state))
  county <- st_transform(county, raster::crs(gediNAM30m_1_state))
  gedi_1_county <- raster::mask(
    raster::crop(gediNAM30m_1_state, county),
    county
  ) # much faster to crop to the extent of the county polygon before masking
  system.time(
    gedi_1_county_aea <- reproject_align_raster(gedi_1_county, NLCD_1_state)
  )
  # writeRaster(gedi_1_county,filename=file.path(path_chm_default,paste0("chm_",county$NAME,".tif")),
  #             overwrite=T,format="GTiff")
  writeRaster(
    gedi_1_county_aea,
    filename = file.path(
      path_chm_default,
      paste0("chm_", county$NAME, "_aea.tif")
    ),
    overwrite = T,
    filetype = "GTiff"
  )
  # saves a plot of the county chm
  # png(filename=file.path(path_chm_default,paste0("chm_",county$NAME,".png")),
  #     width = 12,height = 12,units = "in",res = 300)
  # plot(county,main = county$NAME)
  # plot(gedi_1_county,add=TRUE)
  # dev.off()
  png(
    filename = file.path(
      path_chm_default,
      paste0("chm_", county$NAME, "_aea.png")
    ),
    width = 12,
    height = 12,
    units = "in",
    res = 300
  )
  plot(county_aea$geometry, main = county$NAME, border = 1, lwd = 1, col = NULL)
  plot(gedi_1_county_aea$Layer_1, add = TRUE)
  dev.off()
})
cat(paste(
  black$underline$bold(args),
  "Counties written to folder: ",
  path_chm_default
))

# Next reclassify forest cover classes in NLCD and use to mask CEDI CHMs
# create classification matrix: reclassify everything as nonforest (0) except 41, 42, 43, and 90 as forest (1)
reclass_df <- c(
  0,
  40,
  0,
  40,
  49,
  1, # classifies 41, 42, and 43 as 1
  49,
  51,
  0,
  51,
  53,
  1, # classifies 52 as 1 (if this doesn't work change the second 52 to 53)
  53,
  89,
  0,
  89,
  90,
  1, # classifies 90 as 1
  90,
  95,
  0
)
reclass_m <- matrix(reclass_df, ncol = 3, byrow = TRUE)
# Only have to run this one time (about 1 minute for Virginia)
system.time({
  NLCD_1_state <- classify(NLCD_1_state, reclass_m, include.lowest = F)
  # set anything but 1 to NA
  NLCD_1_state[NLCD_1_state[] != 1] <- NA
})

# function remove_nonforest
#  loop through countiesFIA_1_state$COUNTYCD (x)
remove_nonforest <- function(countycode, forest = NLCD_1_state) {
  county <- counties_1_state_aea[
    as.integer(counties_1_state_aea$CENSUSCODE) == countycode,
  ]
  fn_county <- file.path(
    path_chm_default,
    paste0("chm_", county$NAME[1], "_aea.tif")
  )
  if (!file.exists(fn_county)) {
    stop(
      "Error in function remove_nonforest: county file: ",
      blue$underline(fn_county),
      " does not exist"
    )
  }
  gedi_1_county_aea <- rast(fn_county)
  if (ext(gedi_1_county_aea) == ext(forest)) {
    print("Extents are the same, no need to crop")
  } else {
    print("Extents are different, cropping data")
    # crop and projectRaster
    forest_cropped <- mask(crop(forest, gedi_1_county_aea), county)
    forest_projected <- project(
      forest_cropped,
      gedi_1_county_aea,
      method = "near"
    )
  }
  ext(forest_projected) == ext(gedi_1_county_aea)
  print(paste("Masking forested areas in:", county$NAME[1]))

  # make sure h2o_projected values are integer
  forest_projected[] <- as.integer(forest_projected[])
  test3 <- gedi_1_county_aea
  # anything NA in the NLCD layer (forest_projected) will be made NA in the GEDI layer (test3)
  test3[is.na(forest_projected[])] <- NA
  #
  writeRaster(
    test3,
    filename = file.path(
      path_chm_NLCD,
      paste0("chm_", county$NAME[1], "_forest.tif")
    ),
    filetype = "GTiff",
    overwrite = T
  )
  # saves a plot of the county chm
  png(
    filename = file.path(
      path_chm_NLCD,
      paste0("chm_", county$NAME[1], "_forest.png")
    ),
    width = 12,
    height = 8,
    units = "in",
    res = 300
  )
  options(terra.pal = terrain.colors(100)[100:1])
  plot(county$geometry, main = county$NAME[1], border = 1, lwd = 1)
  plot(test3, type = "continuous", add = TRUE)
  dev.off()
}

lapply(countiesFIA_1_state$COUNTYCD, function(x) remove_nonforest(x))

print(cat("Program complete.\n"))
print(paste(county$NAME[1], " county CHMs written to ", path_chm_NLCD))
