# Block: extract_county_chm - diagnostic

library(spade)
library(terra)
library(sf)
library(exactextractr)
library(dplyr)

handler <- function(state_abbrev = "VA",
                    path_gfchm = "~/data/GEDI/Forest_height_2019_NAM.tif",
                    path_counties = "~/data/Government/Counties/FIA/County_Boundaries/tl_2016_us_county_CONUS_Only_City-States_Assimilated.shp",
                    path_nlcd_dir = "~/data/NLCD",
                    path_survey = "~/data/FIADB/CSV_DATA/SURVEY.csv",
                    use_nlcd_mask = "true") {

  message("Reading county shapefile...\n")
  counties_all <- st_read(path_counties, quiet = TRUE)
  counties_all$STATECD = counties_all$CID2 %/% 1000
  counties_all$COUNTYCD = counties_all$CID2 %% 1000

  message("Reading state codes...\n")
  state_codes <- read.csv(path_survey,stringsAsFactors = FALSE) %>%
    dplyr::select(STATECD,STATEAB) %>% distinct()
  state_fips_int <- state_codes$STATECD[which(state_codes$STATEAB == state_abbrev)]
  cid2_min <- state_fips_int * 1000 + 1
  cid2_max <- state_fips_int * 1000 + 999
  counties_state <- counties_all[counties_all$CID2 >= cid2_min &
                                   counties_all$CID2 <= cid2_max, ]
  message("State:", state_abbrev, "- Counties:", nrow(counties_state), "\n")

  message("Reading GFCHM raster...\n")
  gfchm <- rast(path_gfchm)
  message("GFCHM CRS:", crs(gfchm, describe=TRUE)$name, "\n")
  message("GFCHM extent:", as.character(ext(gfchm)), "\n")

  message("Reprojecting counties to GFCHM CRS...\n")
  counties_wgs84 <- st_transform(counties_state, crs(gfchm))
  message("Counties WGS84 bbox:\n")
  message(st_bbox(counties_wgs84))

  message("Converting to SpatVector...\n")
  counties_vect <- vect(counties_wgs84)
  message("SpatVector extent:\n")
  print(ext(counties_vect))

  message("Cropping GFCHM...\n")
  gfchm_state <- crop(gfchm, counties_vect)
  message("Crop successful!\n")

  saveRDS(data.frame(status="diagnostic"), "result.rds")
  File(path = "result.rds")
}

spade_types(handler) <- list(.return = "File")

run(handler)
