# Block: sort_csv

library(spade)

handler <- function(table, sort_column = "x") {
  data <- read.csv(table@path)

  if (!sort_column %in% names(data)) {
    stop(sprintf("Column '%s' not found in input CSV", sort_column))
  }

  sorted_data <- data[order(data[[sort_column]]), ]

  write.csv(sorted_data, "sorted.csv", row.names = FALSE)
  File(path = "sorted.csv")
}

spade_types(handler) <- list(table = "File", .return = "File")

run(handler)
