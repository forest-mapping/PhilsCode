# Block: glmnet_var_select

message("Loading package libraries...\n")
library(spade)
library(arrow)
library(dplyr)
library(glmnet)

message("Finished loading package libraries...\n")

handler <- function(joined_data,
                     response = "ESTIMATE",
                     alphas = "0,0.25,0.5,0.75,1",
                     seed = 42){

  message("Reading joined FIA/GFCHM parquet file...\n")
  df <- arrow::read_parquet(joined_data@path)

  if (!(response %in% names(df)))
    stop(paste0("response column '", response, "' not found in joined_data"))

  ht_cols <- grep("^FRAC_HT", names(df), value = TRUE)
  if (length(ht_cols) == 0)
    stop("No FRAC_HT* (GFCHM height-bin) columns found in joined_data.")

  message("Predictors: ", paste(ht_cols, collapse = ", "), "\n")
  message("Response: ", response, "\n")

  X <- as.matrix(df[, ht_cols, drop = FALSE])
  y <- df[[response]]

  keep <- stats::complete.cases(X, y)
  if (any(!keep)) {
    message("Dropping ", sum(!keep), " row(s) with missing values.\n")
    X <- X[keep, , drop = FALSE]
    y <- y[keep]
  }

  alpha_vec <- as.numeric(trimws(strsplit(alphas, ",")[[1]]))
  set.seed(seed)

  message("Fitting cv.glmnet across alpha = ", paste(alpha_vec, collapse = ", "), "...\n")
  # Shared fold assignment across all alphas so CV-MSE comparisons are
  # apples-to-apples (otherwise each alpha gets its own random folds).
  n <- length(y)
  nfolds <- min(10, n)
  foldid <- sample(rep(seq_len(nfolds), length.out = n))

  cv_fits <- setNames(vector("list", length(alpha_vec)), paste0("alpha_", alpha_vec))
  for (i in seq_along(alpha_vec)) {
    cv_fits[[i]] <- cv.glmnet(X, y, alpha = alpha_vec[i], foldid = foldid, intercept = FALSE)
  }

  message("Building coefficient comparison table (lambda.min and lambda.1se per alpha)...\n")
  coef_cols <- list()
  for (i in seq_along(alpha_vec)) {
    a <- alpha_vec[i]
    fit <- cv_fits[[i]]
    coef_cols[[paste0("a", a, "_min")]] <- as.numeric(coef(fit, s = "lambda.min"))[-1]
    coef_cols[[paste0("a", a, "_1se")]] <- as.numeric(coef(fit, s = "lambda.1se"))[-1]
  }
  coef_table <- do.call(cbind, coef_cols)
  rownames(coef_table) <- ht_cols

  message("Rendering diagnostic PDF (selection table + CV curves + coefficient paths)...\n")
  pdf("glmnet_diagnostics.pdf", width = 10, height = 8)

  # --- Page 1: selected-coefficient table across alphas ---
  plot.new()
  title(paste0("glmnet Variable Selection (lambda.min / lambda.1se) \u2014 response: ", response))
  tbl_text <- capture.output(print(round(coef_table, 4)))
  text(0.02, 0.95, paste(tbl_text, collapse = "\n"),
       adj = c(0, 1), family = "mono", cex = 0.7)

  # --- Page(s): CV curve + coefficient path per alpha ---
  for (i in seq_along(alpha_vec)) {
    a <- alpha_vec[i]
    fit_cv <- cv_fits[[i]]
    fit_full <- glmnet(X, y, alpha = a, intercept = FALSE)

    op <- par(mfrow = c(1, 2))
    plot(fit_cv)
    title(sprintf("CV-MSE, alpha = %.2f", a), line = 2.5)

    plot(fit_full, xvar = "lambda", label = TRUE)
    title(sprintf("Coefficient paths, alpha = %.2f", a), line = 2.5)
    par(op)
  }

  dev.off()

  message("Diagnostics written: glmnet_diagnostics.pdf\n")
  File(path = "glmnet_diagnostics.pdf")
}

spade_types(handler) <- list(
  joined_data = "File",
  .return     = "File"
)

run(handler)
