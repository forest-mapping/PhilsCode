# Block: hello-there

library(spade)

handler <- function(name = "World") {
  writeLines(paste0("Hello, ", name, "."), "greeting.txt")
  File(path = "greeting.txt")
}

spade_types(handler) <- list(.return = "File")

run(handler)
# TODO: implement block logic

# Write outputs to outputs/ directory
