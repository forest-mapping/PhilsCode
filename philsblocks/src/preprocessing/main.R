library(psaeRuntimeConnector)


# @param state (character): the full name of the state to process
handler <- function(path1, path2, state) {
    first_path <- psaeRuntimeConnector::to_path(path1)
    # fill in script 2

    data <- psaeRuntimeConnector::load_rda(path2)

    return(
        psaeRuntimeConnector::new_file()
    )
}
