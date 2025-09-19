library(RPostgreSQL)
library(readr)

# loads the PostgreSQL driver
drv <- dbDriver("PostgreSQL")

con <- DBI::dbConnect(drv, dbname = "fiadb")

# sql script "tree_estn_errors.sql" must be in the working directory
setwd("/home/pradtke/Rscripts/FIADB/sql/")
path_data <- "/home/rstudio/data/FIADB/RDS"


if (!exists("con")) {
  # loads the PostgreSQL driver
  drv <- dbDriver("PostgreSQL")

  # creates a connection to the postgres database
  # note that "con" will be used later in each connection to the database
  con <- dbConnect(
    drv,
    dbname = "testdb",
    host = "localhost",
    port = 5433,
    user = "postgres",
    password = rstudioapi::askForPassword()
  )
}

# this reads a text file in as a character string that you can then
# pass to the db
readQuery <- function(x) {
  readChar(x, file.info(x)$size)
}

# this is a general query for any tree variable
base_tree_query <- readQuery("tree_estn_errors_SE2017.sql")

# by <- "PLOT.STATECD"
# tree_table_var <- "DRYBIO_AG"
# base_query <- base_tree_query

getEstimate <- function(
  tree_table_var = "DRYBIO_AG",
  base_query,
  by = "PLOT.STATECD"
) {
  # construct the query
  query <- gsub("%by%", by, base_query)
  query <- gsub("%tree_var%", tree_table_var, query)

  # convert pounds to tons
  if (grepl("DRYBIO", tree_table_var)) {
    query <- gsub(tree_table_var, paste0(tree_table_var, " / 2000"), query)
  }

  value <- dbGetQuery(con, query)

  # clean up the names
  value$STATECD <- ifelse(
    nchar(value$eval_grp) == 5,
    substr(value$eval_grp, 1, 1),
    substr(value$eval_grp, 1, 2)
  )

  value$YEAR <- ifelse(
    nchar(value$eval_grp) == 5,
    substr(value$eval_grp, 2, 5),
    substr(value$eval_grp, 3, 6)
  )

  names(value)[2] <- by

  names(value)[3] <- tree_table_var

  return(value)
}

# total biomass estimate and variances for latest evaluation by state
# system.time(
#   bio_by_state <- getEstimate("DRYBIO_AG", base_tree_query, "PLOT.STATECD")
# )
#
# # gross merch vol estimate and variances for latest evaluation by state
# system.time(
#   vol_by_state <- getEstimate("VOLCFGRS", base_tree_query, "PLOT.STATECD")
# )
# gross merch vol estimate and variances for latest evaluation by county
system.time(
  vol_by_fips_su <- getEstimate(
    "VOLCFGRS",
    base_tree_query,
    "PLOT.STATECD * 1000 + PLOT.COUNTYCD+ PLOT.UNITCD *0.1"
  )
)

# total biomass estimate and variances for latest evaluation by county
system.time(
  bio_by_fips_su <- getEstimate(
    "DRYBIO_AG",
    base_tree_query,
    "PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1"
  )
)

# path_data <- "/home/rstudio/data/FIADB/RDS"
saveRDS(bio_by_fips_su, file = file.path(path_data, "bio_by_fips_su2017.RDS"))
saveRDS(vol_by_fips_su, file = file.path(path_data, "vol_by_fips_su2017.RDS"))
