# Block: reformat_fia
# Reformats GB_est output: selects columns, constructs co_fips,
# joins UNITCD from reference CSV.

library(spade)
library(dplyr)

handler <- function(gb_est_result,
                    unit_ref = "/home/pradtke/source/PhilsCode/ref/STATE_UNIT_COUNTY.csv") {

  # Read GB_est result
  result <- readRDS(gb_est_result@path)

  # Read survey unit reference
  unit_ref_df <- read.csv(unit_ref) %>%
    dplyr::select(STATECD, COUNTYCD, UNITCD, UNITNM)

  # Construct co_fips and select/reorder columns
  result <- result %>%
    dplyr::mutate(co_fips = STATECD * 1000 + COUNTYCD) %>%
    dplyr::left_join(unit_ref_df, by = c("STATECD", "COUNTYCD")) %>%
    dplyr::select(
      EVAL_GRP,
      STATECD,
      UNITCD,
      UNITNM,
      COUNTYCD,
      co_fips,
      COUNTY_NAME,
      ATTRIBUTE_NBR,
      ESTIMATE,
      VAR_OF_ESTIMATE,
      SE_OF_ESTIMATE,
      SE_OF_ESTIMATE_PCT,
      TOTAL_PLOTS,
      NON_ZERO_PLOTS,
      TOT_POP_AC
    )

  saveRDS(result, "result.rds")
  File(path = "result.rds")
}

spade_types(handler) <- list(gb_est_result = "File", .return = "File")

run(handler)
