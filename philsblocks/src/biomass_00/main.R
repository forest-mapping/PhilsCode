library(psaeRuntimeConnector)
# this reads a text file in as a character string that you can then
# pass to the db
library(readr)
library(DBI)
library(duckdb)


readQuery <- function(x) {
    readChar(x, file.info(x)$size)
}


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

    print(summary(value))

    #state_cd_column <- purrr::map(
    #    value$EVAL_GRP,
    #    function(x) {
    #        return(
    #            ifelse(
    #                nchar(x) == 5,
    #                substr(x, 1, 1),
    #                substr(x, 1, 2)
    #            )
    #        )
    #    }
    #)

    #print(state_cd_column)
    # clean up the names
    value$STATECD <- ifelse(
        nchar(value$EVAL_GRP) == 5,
        substr(value$EVAL_GRP, 1, 1),
        substr(value$EVAL_GRP, 1, 2)
    )

    value$YEAR <- ifelse(
        nchar(value$EVAL_GRP) == 5,
        substr(value$EVAL_GRP, 2, 5),
        substr(value$EVAL_GRP, 3, 6)
    )

    names(value)[2] <- by

    names(value)[3] <- tree_table_var

    return(value)
}


handler <- function() {
    path_data <- "./data/FIADB/RDS"

    if (!exists("con")) {
        con <- dbConnect(duckdb())

        # Load the SQLite extension
        install_cmd <- "INSTALL sqlite;"
        load_cmd <- "LOAD sqlite;"
        attach_cmd <- "ATTACH './data/FS_FIADB.db' (type sqlite); USE FS_FIADB;"

        dbExecute(con, install_cmd)
        dbExecute(con, load_cmd)
        dbExecute(con, attach_cmd)
    }

    # this is a general query for any tree variable
    base_tree_query <- readQuery("./sql/tree_county_biomass.sql")

    # total biomass estimate and variances for latest evaluation by county
    system.time(
        bio_by_fips_su <- getEstimate(
            "DRYBIO_AG",
            base_tree_query,
            "PLOT.STATECD * 1000 + PLOT.COUNTYCD + PLOT.UNITCD *0.1"
        )
    )

    output_path <- file.path(path_data, "bio_by_fips_su2017.RDS")

    saveRDS(bio_by_fips_su, file = output_path)

    return(psaeRuntimeConnector::new_file(output_path))
}
