# must source reproject_align_raster.R, e.g., "/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_align_raster.R"  #maybe not, because the county map has reprojected in ArcPro#
#

# source("/home/qianqian/GEDI/Rscript/reproject_align_raster.R")
source("/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_spat_raster.R")
require(raster)
require(terra)
require(sf)
require(crayon)
# library(gdalUtils)

# read input data -----
path <- "/home/rstudio/data/Government/Counties/USCounties.shp"
fn_FIAcounties <- "/home/rstudio/data/FIADB/CSV_DATA/COUNTY.csv"
fn_FIAunits <- "/home/rstudio/data/FIADB/CSV_DATA/REF_UNIT.csv"
fn_STATES <- "/home/rstudio/data/Government/STATES.csv"

countiesUS <- st_read(path)
countiesFIA <- read.csv(fn_FIAcounties, stringsAsFactors = FALSE)
unitsFIA <- read.csv(fn_FIAunits, stringsAsFactors = FALSE)
statesUS <- read.csv(fn_STATES, stringsAsFactors = FALSE) %>%
  dplyr::filter(STATE <= 56) %>%
  dplyr::select(-STATENS) %>% # only US states
  dplyr::rename(STATECD = STATE, STATENAME = STATE_NAME)
statesUS <- statesUS[statesUS$STATECD %in% countiesFIA$STATECD, ] # gets rid of DC

# GEDI CHMs (default and NLCD)
path_chm <- "/home/rstudio/data/GEDI/CHM/"
path_chm_default <- "/home/rstudio/data/GEDI/CHM/default"
path_chm_NLCD <- "/home/rstudio/data/GEDI/CHM/NLCD"

# read stateAbbrev from command line using commandArgs() as below
# needs an error trap
args = commandArgs(trailingOnly = T)
# for testing set to virginia
# args <- "VA"

if (length(args) == 0) {
  stop("no command line argument entered.\n")
} else {
  cat(paste0("command line argument entered: ", args, "\n"))
  stateAbbrev = ifelse(
    length(args) == 1,
    args,
    stop("Program halted. Only one command line argument allowed.")
  )
}

# make sure shapefile statenames are consistent with state.name (YES)
if (state.name[state.abb == stateAbbrev] %in% unique(countiesUS$STATENAME)) {
  cat(green("command line argument entered: ", args, "\n"))
} else {
  stop(red(
    "command line argument entered: ",
    args,
    "has no valid state name in state.name dataset\n"
  ))
}

# states <- data.frame(name=state.name,abbrev=state.abb)

countiesPolygon <- countiesUS[
  countiesUS$STATENAME == state.name[state.abb == stateAbbrev],
]

# calculate height distributions for default mask ------------------------------------
# default mask
path <- file.path(path_chm, "default", stateAbbrev)
mapnames_default <- dir(file.path(path))[grepl("^chm_.*.tif$", dir(path))]

nchar(mapnames_default[1])
countynames <- unlist(lapply(1:length(mapnames_default), function(x) {
  substr(
    mapnames_default[x],
    start = 5,
    stop = (nchar(mapnames_default[x]) - 4)
  )
}))
countynames <- countynames[-grep(pattern = "_aea", countynames)]
# Loop through counties and tabulate the default CHM distribution by 5 m ht classes  #
system.time({
  # runs in about 2 minutes for Virginia counties  #
  temp <- lapply(countynames, function(x) {
    test_poly <- countiesPolygon[countiesPolygon$NAME == x, ]
    statecd <- statesUS$STATECD[statesUS$STUSAB == args]
    countyname = test_poly$NAME # should be the same as x
    chm.exists = file.exists(file.path(
      path_chm_default,
      args,
      paste0("chm_", countyname, ".tif")
    ))
    cat(
      "GEDI default CHM for county:",
      countyname,
      ifelse(chm.exists, "exists", "does not exist"),
      '\n'
    )
    if (chm.exists) {
      test_tif <- raster(file.path(
        path_chm_default,
        args,
        paste0("chm_", countyname, ".tif")
      ))
      # test_tif <- reproject_align_raster(rast = test_tif,ref_rast = lc30m)
      test_tif[test_tif > 100] <- NA #remove water
      bins <- cut(
        test_tif[],
        breaks = c(0, 5, 10, 15, 20, 25, 30, 35),
        labels = F
      ) *
        5
      test_tif[] <- bins
      # don;t need to plot the default CHM. Already plotted in CHM/default folders
      # png(file.path(path_chm,paste0(countyname,".png")),width = 6, height = 6,units="in",res=600)
      # plot(test_tif,main=countyname)
      # dev.off()
      chm_dist <- as.data.frame(table(bins))
      chm_dist$STATECD = statecd
      chm_dist$COUNTYCD = test_poly$CENSUSCODE
      chm_dist$countyname = countyname
      chm_dist$bin_ht = as.numeric(as.character(chm_dist$bins))
      chm_dist$km2 <- chm_dist$Freq * 900 / 1e6
      return(chm_dist)
    }
  })
})

chm_dist <- do.call(rbind, temp) %>%
  dplyr::left_join(statesUS) %>%
  dplyr::rename(COUNTYNAME = countyname, FREQ = Freq, BIN_HT = bin_ht)

write.csv(
  chm_dist,
  file.path(path_chm_default, args, "CHM_dist_by_county.csv"),
  row.names = F
)

print(paste0(
  "Default GEDI CHM bin distributions calculated for: ",
  statesUS$STATENAME[statesUS$STUSAB == args]
))

# calculate height distributions for NLCD mask -------------------------------------
# NLCD mask
path <- file.path(path_chm, "NLCD", stateAbbrev)
mapnames_NLCD <- dir(file.path(path))[grepl("^chm_.*_forest.tif$", dir(path))]

countynames <- unlist(lapply(1:length(mapnames_NLCD), function(x) {
  substr(mapnames_NLCD[x], start = 5, stop = (nchar(mapnames_NLCD[x]) - 11))
}))

# Loop through counties and tabulate the NLLCD CHM distribution by 5 m ht classes  #
system.time({
  # runs in about 2 minutes for Virginia counties  #
  temp <- lapply(countynames, function(x) {
    test_poly <- countiesPolygon[countiesPolygon$NAME == x, ]
    statecd <- statesUS$STATECD[statesUS$STUSAB == args]
    countyname = test_poly$NAME # should be the same as x
    chm.exists = file.exists(file.path(
      path_chm_NLCD,
      args,
      paste0("chm_", countyname, "_forest.tif")
    ))
    cat(
      "GEDI NLCD CHM for county:",
      countyname,
      ifelse(chm.exists, "exists", "does not exist"),
      '\n'
    )
    if (chm.exists) {
      test_tif <- raster(file.path(
        path_chm_NLCD,
        args,
        paste0("chm_", countyname, "_forest.tif")
      ))
      # test_tif <- reproject_align_raster(rast = test_tif,ref_rast = lc30m)
      test_tif[test_tif > 100] <- NA #remove water
      bins <- cut(
        test_tif[],
        breaks = c(0, 5, 10, 15, 20, 25, 30, 35),
        labels = F
      ) *
        5
      test_tif[] <- bins
      chm_dist <- as.data.frame(table(bins))
      chm_dist$STATECD = statecd
      chm_dist$COUNTYCD = test_poly$CENSUSCODE
      chm_dist$countyname = countyname
      chm_dist$bin_ht = as.numeric(as.character(chm_dist$bins))
      chm_dist$km2 <- chm_dist$Freq * 900 / 1e6
      return(chm_dist)
    }
  })
})

chm_dist <- do.call(rbind, temp) %>%
  dplyr::left_join(statesUS) %>%
  dplyr::rename(COUNTYNAME = countyname, FREQ = Freq, BIN_HT = bin_ht)

write.csv(
  chm_dist,
  file.path(path_chm_NLCD, args, "CHM_dist_by_county.csv"),
  row.names = F
)

print(paste0(
  "NLCD GEDI CHM bin distributions calculated for: ",
  statesUS$STATENAME[statesUS$STUSAB == args]
))
