# Block: join_chm_stats

# Sys.setenv(PROJ_NETWORK = "OFF")
# Sys.setenv(PROJ_DATA = "/usr/share/proj")
# Sys.setenv(PROJ_LIB  = "/usr/share/proj")

message("Loading package libraries...\n")
library(spade)
library(terra)
library(sf)
library(exactextractr)
library(dplyr)
library(tidyr)
message("Finished loading package libraries...\n")

handler <- function(fia_data,
                    state_abbrev = "VA",
                    path_gfchm = "/home/pradtke/source/PhilsCode/ref/chm_Tazewell_aea.tif",
                    gfchm_option = "default", # "default","NLCD","NLCD52",
                    path_state = "/home/pradtke/source/PhilsCode/ref/STATES.csv",
                    path_county = "/home/pradtke/source/PhilsCode/ref/COUNTY.csv") {

  message("Reading reformatted FIA estimates...\n")
  fia_df <- readRDS(fia_data@path)

  # fia_df = readRDS(dir(pattern = "result.rds","~/.spade",
  #                      recursive = TRUE,full.names = TRUE)[1])

  message("Reading county GFCHM files...\n")
  fn_gfchm = path_gfchm
  message(paste("GFCHM raster filenames for",length(fn_gfchm),"counties in",state_abbrev))
  county_rast = rast(fn_gfchm)
  # plot(county_rast)

  message("Reading state codes...\n")
  state_codes <- read.csv(path_state, stringsAsFactors = FALSE) %>%
    rename(STATECD = STATE,
           STATEAB = STUSAB,
           STATENAME = STATE_NAME) %>% arrange(STATECD) %>% distinct()
  state_fips_int <- state_codes$STATECD[which(state_codes$STATEAB == state_abbrev)]
  message("State codes read from file...\n")

  message("Reading county codes...\n")
  county_codes <- read.csv(path_county, stringsAsFactors = FALSE) %>%
    filter(STATECD == state_fips_int) %>% dplyr::select(STATECD,UNITCD,COUNTYCD,COUNTYNM) %>%
    arrange(COUNTYCD)
  message("County codes read from file...\n")

  message("State:", state_abbrev, " - Counties: ", nrow(county_codes), "\n")

  state_fips_int <- state_codes$STATECD[which(state_codes$STATEAB == state_abbrev)]

  countynames = sort(county_codes$COUNTYNM)
  # can add an error check here if countynames all match fn_gfchm
  # length(countynames) == length(fn_gfchm)

  county_name = strsplit(fn_gfchm,split='_')[[1]][2]
  county_code = county_codes$COUNTYCD[county_codes$COUNTYNM == county_name]
  if(!grepl(toupper(county_name),toupper(fn_gfchm)))
    stop("County name match error: join_chm_stats.R")
  county_rast$Layer_1[county_rast$Layer_1 > 100] <- NA

  bins <- (cut(values(county_rast$Layer_1),breaks=c(-1,0,5,10,15,20,25,30,35),labels=F)-1)*5
  # create new raster with same geometry
  county_bins = county_rast$Layer_1
  # assign new values
  values(county_bins) <- bins
  # plot(county_bins,reverse = TRUE)

  chm_dist <- as.data.frame(table(bins))
  chm_dist$STATECD = state_fips_int
  chm_dist$COUNTYCD = county_code
  chm_dist$COUNTYNM = county_name
  chm_dist$BIN_HT = as.numeric(as.character(chm_dist$bins))
  chm_dist$KM2 <- chm_dist$Freq * prod(res(county_rast))/1e6

  chm_dist <- chm_dist %>% left_join(state_codes) %>%
    dplyr::select(-STATENS)

  message("Pivoting CHM height-bin distribution wide (one column per bin)...\n")
  chm_wide <- chm_dist %>%
    dplyr::mutate(CO_FIPS = STATECD * 1000 + COUNTYCD) %>%
    dplyr::select(STATECD, COUNTYCD, CO_FIPS, BIN_HT, KM2) %>%
    tidyr::pivot_wider(
      names_from = BIN_HT,
      values_from = KM2,
      names_prefix = "KM2_HY",
      values_fill = 0
    )

  message("Joining CHM height-bin columns onto FIA estimates by co_fips...\n")
  result <- fia_df %>%
    dplyr::right_join(chm_wide)

  saveRDS(result, "result.rds")
  File(path = "result.rds")
}
spade_types(handler) <- list(fia_data = "File", .return = "File")

run(handler)
