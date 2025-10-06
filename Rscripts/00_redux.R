library(DBI)
library(duckdb)




con <- dbConnect(duckdb())

run_query_from_file <- function(query_path, con) {
    query <- readChar(query_path, file.info(query_path)$size)
    data <- dbGetQuery(con, query)

    return (as.data.frame(data))
}



biomass_query_file <- system.file("./sql/tree_1.sql")
volume_query_file <- system.file("./sql/tree_2.sql")

biomass_output_file <- system.file("./data/bio_by_fips_su2017.RDS")
volume_output_file <- system.file("./data/vol_by_fips_su2017.RDS")


biomass_data <- run_query_from_file(biomass_query_file, con)
#volume_data <- run_query_from_file(volume_query_file, con)

saveRDS(biomass_data, biomass_output_file)
#saveRDS(volume_data, volume_output_file)