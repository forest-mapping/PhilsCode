# must source reproject_align_raster.R, e.g., "/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_align_raster.R"  #maybe not, because the county map has reprojected in ArcPro#
#
require(raster)
require(terra)
require(sf)
require(crayon)
# library(gdalUtils)
# source("/home/qianqian/GEDI/Rscript/reproject_align_raster.R")
source("/home/pradtke/Rscripts/NAIP-FH/Rscripts/reproject_spat_raster.R")

# read stateAbbrev from command line using commandArgs() as below
# needs an error trap
args = commandArgs(trailingOnly = T)
# for testing set to virginia
# args <- "TN"

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

# read input data -----
path <- "/home/rstudio/data/Government/Counties/USCounties.shp"
path_counties <- "/home/rstudio/data/Government/Counties/counties4project.shp"
fn_FIAcounties <- "/home/rstudio/data/FIADB/CSV_DATA/COUNTY.csv"
fn_FIAunits <- "/home/rstudio/data/FIADB/CSV_DATA/REF_UNIT.csv"
fn_STATES <- "/home/rstudio/data/Government/STATES.csv"

countiesUS <- st_read(path)
counties4project <- st_read(path_counties)
countiesFIA <- read.csv(fn_FIAcounties, stringsAsFactors = FALSE)
unitsFIA <- read.csv(fn_FIAunits, stringsAsFactors = FALSE)
statesUS <- read.csv(fn_STATES, stringsAsFactors = FALSE) %>%
  dplyr::filter(STATE <= 56) %>%
  dplyr::select(-STATENS) %>% # only US states
  dplyr::rename(STATECD = STATE, STATENAME = STATE_NAME)
statesUS <- statesUS[statesUS$STATECD %in% countiesFIA$STATECD, ] # gets rid of DC

stateAbbrev = args
statename <- statesUS$STATENAME[statesUS$STUSAB == args]
stateCD <- statesUS$STATECD[statesUS$STUSAB == args]
counties_1_state <- counties4project[counties4project$STATE == statename, ] %>%
  data.frame()
countiesFIA_1_state <- countiesFIA[
  countiesFIA$STATECD == stateCD,
  c("STATECD", "UNITCD", "COUNTYCD", "COUNTYNM")
]


# NAIP CHMs (noWater, GEDI, and NLCD)
path_chm <- "/home/rstudio/data/NAIP/CHM/"
path_chm_noWater <- "/home/rstudio/data/NAIP/CHM/noWater"
path_chm_GEDI <- "/home/rstudio/data/NAIP/CHM/GEDI"
path_chm_NLCD <- "/home/rstudio/data/NAIP/CHM/NLCD"

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

# calculate height distributions for default (noWater) mask ------------------------------------
# noWater mask
path <- file.path(path_chm, "noWater", stateAbbrev)
mapnames_noWater <- dir(file.path(path))[grepl("^chm_.*.tif$", dir(path))]

# nchar(mapnames_noWater[1])
countynames <- unlist(lapply(1:length(mapnames_noWater), function(x) {
  substr(
    mapnames_noWater[x],
    start = 5,
    stop = (nchar(mapnames_noWater[x]) - 12)
  )
}))

# Loop through counties and tabulate the default CHM distribution by 5 m ht classes  #
system.time({
  # runs in about 2 minutes for Virginia counties  #
  temp <- lapply(countynames, function(x) {
    COUNTY <- x
    # print(x)
    countyCD <- counties_1_state$co_fips[counties_1_state$COUNTY == COUNTY]
    countynameLC = countiesFIA_1_state$COUNTYNM[
      countiesFIA_1_state$COUNTYCD == countyCD
    ] # should be the same as x
    if (grepl(" Of ", countynameLC) | grepl(" And ", countynameLC)) {
      countynameLC <- gsub(" Of ", " of ", countynameLC)
      countynameLC <- gsub(" And ", " and ", countynameLC)
    }
    test_poly <- countiesPolygon[countiesPolygon$NAME == countynameLC, ]
    statecd <- statesUS$STATECD[statesUS$STUSAB == args]
    chm.exists = file.exists(file.path(
      path_chm_noWater,
      args,
      paste0("chm_", COUNTY, "_noWater.tif")
    ))
    cat(
      "NAIP noWater CHM for county:",
      COUNTY,
      ifelse(chm.exists, "exists", "does not exist"),
      '\n'
    )
    if (chm.exists) {
      test_tif <- raster(file.path(
        path_chm_noWater,
        args,
        paste0("chm_", COUNTY, "_noWater.tif")
      ))
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
      chm_dist$countyname = COUNTY
      chm_dist$bin_ht = as.numeric(as.character(chm_dist$bins))
      chm_dist$km2 <- chm_dist$Freq * 100 / 1e6
      return(chm_dist)
    }
  })
})

chm_dist <- do.call(rbind, temp) %>%
  dplyr::left_join(statesUS) %>%
  dplyr::rename(COUNTYNAME = countyname, FREQ = Freq, BIN_HT = bin_ht)

write.csv(
  chm_dist,
  file.path(path_chm_noWater, args, "CHM_dist_by_county.csv"),
  row.names = F
)

print(paste0(
  "Default (noWater) CHM bin distributions calculated for: ",
  statesUS$STATENAME[statesUS$STUSAB == args]
))

# calculate height distributions for GEDI mask -------------------------------------
# GEDI mask
path <- file.path(path_chm, "GEDI", stateAbbrev)
mapnames_GEDI <- dir(file.path(path))[grepl(".img$", dir(path))]

countynames <- unlist(lapply(1:length(mapnames_GEDI), function(x) {
  strsplit(strsplit(mapnames_GEDI[x], c("_"))[[1]][2], ".", fixed = TRUE)[[1]][
    1
  ]
}))
countynames <- sort(countynames)

# Loop through counties and tabulate the GEDI CHM distribution by 5 m ht classes  #
system.time({
  # runs in about 2 minutes for Virginia counties  #
  temp <- lapply(countynames, function(x) {
    COUNTY <- x
    # print(x)
    countyCD <- counties_1_state$co_fips[counties_1_state$COUNTY == COUNTY]
    if (length(countyCD) > 1) {
      countyCD = countyCD[1]
    } # fix counties like Dickson Tennessee)
    countynameLC = countiesFIA_1_state$COUNTYNM[
      countiesFIA_1_state$COUNTYCD == countyCD
    ] # should be the same as x
    if (grepl(" Of ", countynameLC) | grepl(" And ", countynameLC)) {
      countynameLC <- gsub(" Of ", " of ", countynameLC)
      countynameLC <- gsub(" And ", " and ", countynameLC)
    }
    test_poly <- countiesPolygon[countiesPolygon$NAME == countynameLC, ]
    statecd <- statesUS$STATECD[statesUS$STUSAB == args]
    countyname = test_poly$NAME # should be the same as x
    chm.exists = file.exists(file.path(
      path_chm_GEDI,
      args,
      paste0(countyCD, "_", COUNTY, ".img")
    ))
    cat(
      "GEDI mask CHM for county:",
      countyname,
      ifelse(chm.exists, "exists", "does not exist"),
      '\n'
    )
    if (chm.exists) {
      test_tif <- raster(file.path(
        path_chm_GEDI,
        args,
        paste0(countyCD, "_", COUNTY, ".img")
      ))
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
      chm_dist$countyname = COUNTY
      chm_dist$bin_ht = as.numeric(as.character(chm_dist$bins))
      chm_dist$km2 <- chm_dist$Freq * 100 / 1e6
      return(chm_dist)
    }
  })
})

chm_dist <- do.call(rbind, temp) %>%
  dplyr::left_join(statesUS) %>%
  dplyr::rename(COUNTYNAME = countyname, FREQ = Freq, BIN_HT = bin_ht)

write.csv(
  chm_dist,
  file.path(path_chm_GEDI, args, "CHM_dist_by_county.csv"),
  row.names = F
)

print(paste0(
  "GEDI CHM bin distributions calculated for: ",
  statesUS$STATENAME[statesUS$STUSAB == args]
))


# calculate height distributions for NLCD mask -------------------------------------
# NLCD mask
path <- file.path(path_chm, "NLCD", stateAbbrev)
mapnames_NLCD <- dir(file.path(path))[grepl(".img$", dir(path))]

countynames <- unlist(lapply(1:length(mapnames_NLCD), function(x) {
  strsplit(strsplit(mapnames_NLCD[x], c("_"))[[1]][2], ".", fixed = TRUE)[[1]][
    1
  ]
}))
countynames <- sort(countynames)

# Loop through counties and tabulate the NLCD CHM distribution by 5 m ht classes  #
system.time({
  # runs in about 2 minutes for Virginia counties  #
  temp <- lapply(countynames, function(x) {
    COUNTY <- x
    # print(x)
    countyCD <- counties_1_state$co_fips[counties_1_state$COUNTY == COUNTY]
    if (length(countyCD) > 1) {
      countyCD = countyCD[1]
    } # fix counties like Dickson Tennessee)
    countynameLC = countiesFIA_1_state$COUNTYNM[
      countiesFIA_1_state$COUNTYCD == countyCD
    ] # should be the same as x
    if (grepl(" Of ", countynameLC) | grepl(" And ", countynameLC)) {
      countynameLC <- gsub(" Of ", " of ", countynameLC)
      countynameLC <- gsub(" And ", " and ", countynameLC)
    }
    test_poly <- countiesPolygon[countiesPolygon$NAME == countynameLC, ]
    statecd <- statesUS$STATECD[statesUS$STUSAB == args]
    countyname = test_poly$NAME # should be the same as x
    chm.exists = file.exists(file.path(
      path_chm_NLCD,
      args,
      paste0(countyCD, "_", COUNTY, ".img")
    ))
    cat(
      "NLCD mask CHM for county:",
      countyname,
      ifelse(chm.exists, "exists", "does not exist"),
      '\n'
    )
    if (chm.exists) {
      test_tif <- raster(file.path(
        path_chm_NLCD,
        args,
        paste0(countyCD, "_", COUNTY, ".img")
      ))
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
      chm_dist$countyname = COUNTY
      chm_dist$bin_ht = as.numeric(as.character(chm_dist$bins))
      chm_dist$km2 <- chm_dist$Freq * 100 / 1e6
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
  "NLCD CHM bin distributions calculated for: ",
  statesUS$STATENAME[statesUS$STUSAB == args]
))
