# Block: GB_est

library(spade)
library(RPostgreSQL)
library(DBI)
library(FIADB.diRect)

handler <- function(EVAL_GRP = 512017,
                    ATTRIBUTE_NBR = 10,
                    GRP_BY_ATTRIB = "STATECD",
                    FIADB_HOST = "localhost",
                    FIADB_PORT = 5432,
                    FIADB_USER = "pradtke",
                    FIADB_PASSWORD = "") {

  grp_by_vec <- trimws(strsplit(GRP_BY_ATTRIB, ",")[[1]])

  result <- GB_est(
    EVAL_GRP      = as.integer(EVAL_GRP),
    ATTRIBUTE_NBR = as.integer(ATTRIBUTE_NBR),
    GRP_BY_ATTRIB = grp_by_vec
  )

  saveRDS(result, "result.rds")
  File(path = "result.rds")
}

spade_types(handler) <- list(.return = "File")

run(handler)
