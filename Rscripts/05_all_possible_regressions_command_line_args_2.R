# All possible regressions for fitting Fay-Herriot models
library(sae)
library(dplyr)
tol = 1e-06
alpha = 0.01
k_best = 5

# read command line args
args = commandArgs(trailingOnly = TRUE)

source(file.path("/home/rstudio/data/temp/adj_YL_FisherScore_eblupFH.R"))

if (length(args) != 3) {
  stop(length(args), "Specify command line arguments: STATECD SOURCE response.")
}
res = args[3] # c("Biomass","Volume")
src = args[2] # c("GEDI_default","GEDI_NLCD")
statecd = as.integer(args[1]) # c(37,47,51)

# print(statecd,src,res)
# stop(paste(statecd,src,res)," Stop point.")
# if(!args %in% unique(countiesUS$STATENAME)){
#   stop("Input state entered incorrectly. Program terminated!")
# }

# read data for modeling
path_fia <- file.path("/home/rstudio/data/FIADB/RDS/")
long_data <- readRDS(file.path(path_fia, "FIA_GEDI_for_Fay-Herriot.RDS"))

# names(long_data)
# table(long_data$SOURCE,long_data$response)

res = "Volume" # c("Biomass","Volume")
src = "GEDI_NLCD" # c("GEDI_default","GEDI_NLCD","NAIP_noWater","NAIP_GEDI","NAIP_NLCD")
statecd = 51 # c(37,47,51)

regdata <- long_data %>%
  filter(response == res, SOURCE == src, STATECD == statecd) %>%
  rename(
    !!res := value,
    `B5` = `5`,
    `B10` = `10`,
    `B15` = `15`,
    `B20` = `20`,
    `B25` = `25`,
    `B30` = `30`,
    `B35` = `35`
  ) %>%
  mutate(
    `MB5` = M * `B5`,
    `MB10` = M * `B10`,
    `MB15` = M * `B15`,
    `MB20` = M * `B20`,
    `MB25` = M * `B25`,
    `MB30` = M * `B30`,
    `MB35` = M * `B35`
  )

# replace NA with zero in CHM height bins
regdata[, 14:27][is.na(regdata[, 14:27])] <- 0


x = names(regdata)[14:27]
y = names(regdata)[5]

# i = 1
# n = choose(length(x),i)
# rhs_all <- combn(x,i)

all_p <- function(p, preds, resp) {
  n = choose(length(preds), p)
  rhs_all <- combn(preds, p)
  # dim(rhs_all)
  system.time({
    test <- lapply(1:n, function(j) {
      f = as.formula(paste(
        resp,
        "~ ",
        paste(rhs_all[, j], collapse = " + "),
        " + 0"
      ))
      print(paste("reg:", j))
      eblup_fit <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 500)

      # Scenario 51 NAIP_NLCD Biomass (j=80) Biomass ~ B5 + B15 + B25 + MB10 + 0 will crash eblupFH
      if (
        (j == 80 & statecd == 51 & res == "Biomass" & src == "NAIP_NLCD") |
          (j == 889 & statecd == 51 & res == "Volume" & src == "NAIP_NLCD") |
          (j == 578 & statecd == 51 & res == "Biomass" & src == "NAIP_NLCD")
      ) {
        print(paste0(
          "No convergence in model #",
          j,
          " of ",
          p,
          " predictors: ",
          paste0(rhs_all[, j], collapse = ' ')
        ))
        data.frame(reg = j, preds = rhs_all[, j], aic = NA, pvalue = NA)
      } else {
        if (eblup_fit$fit$convergence == FALSE) {
          eblup_fit <- eblupFH_3(
            f,
            vardir = var,
            data = regdata,
            MAXITER = 1000
          )
        }
        if (eblup_fit$fit$convergence == TRUE) {
          data.frame(
            reg = j,
            preds = rhs_all[, j],
            aic = eblup_fit$fit$goodness[2],
            pvalue = eblup_fit$fit$estcoef$pvalue
          )
        } else {
          print(paste0(
            "No convergence in model #",
            j,
            " of ",
            p,
            " predictors: ",
            paste0(rhs_all[, j], collapse = ' ')
          ))
          data.frame(reg = j, preds = rhs_all[, j], aic = NA, pvalue = NA)
        }
      }
    })
    all_reg_p <- do.call(rbind, test)
    all_reg_temp <- all_reg_p
    best_reg <- vector(mode = "integer", k_best)
    for (k in 1:k_best) {
      reg_no = all_reg_temp$reg[which(
        all_reg_temp$aic == min(all_reg_temp$aic, na.rm = TRUE)
      )]
      if (p == 1) {
        best_reg[k] = reg_no
      } else {
        best_reg[k] = ifelse(
          sd(reg_no) < tol,
          reg_no[1],
          stop("Problem with best_reg & reg_no in all_p function ")
        )
      }
      # if(k == 1){
      #   best_p <- all_reg_temp %>% dplyr::filter(reg == best_reg[k]) %>%
      #     mutate(is.signif=(pvalue < alpha),rank = k)
      # }else{
      #   next_best <- all_reg_temp %>% dplyr::filter(reg == best_reg[k]) %>%
      #     mutate(is.signif=(pvalue < alpha),rank = k)
      #   best_p <- rbind(best_p,next_best)
      # }
      all_reg_temp <- all_reg_temp %>% filter(reg != best_reg[k])
    }
    results <- data.frame(reg = best_reg, rank = 1:k_best, p = p) %>%
      left_join(all_reg_p) %>%
      mutate(is.signif = (pvalue < alpha))
    # best_p <- all_reg_p %>% dplyr::filter(reg == best_reg)
  })
  results
}


best_regs <- do.call(
  rbind,
  lapply(1:k_best, function(i) all_p(p = i, preds = x, resp = y))
)

temp <- best_regs %>%
  group_by(rank, p) %>%
  summarize(all_signif = all(is.signif), aic = min(aic)) %>%
  filter(all_signif == TRUE) %>%
  arrange(aic, p, rank)

best_preds <- temp[1, ] %>%
  left_join(best_regs) %>%
  ungroup() %>%
  dplyr::select(preds) %>%
  unlist()

best_model = c(
  statecd,
  src,
  as.formula(
    paste(res, "~ ", paste(best_preds, collapse = " + "), " + 0")
  )
)
if (grepl(src, pattern = "GEDI_")) {
  saveRDS(
    best_model,
    file = file.path(
      "/home/rstudio/data/GEDI",
      paste0("best_", statecd, "_", src, "_", res, ".RDS")
    )
  )
} else {
  saveRDS(
    best_model,
    file = file.path(
      "/home/rstudio/data/NAIP",
      paste0("best_", statecd, "_", src, "_", res, ".RDS")
    )
  )
}

stop(paste(statecd, src, res), " Stop point.")

all_p(1, x, y)

stop("End of all possible subsets regression. Script below is in development.")

# potential best model for Volume, GEDI masked by NLCD
f = as.formula(paste(res, "~ ", "B20 + B25 + B30 + 0"))
eblup_vol <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 100)
eblup_vol

# potential best model for Volume, GEDI default mask
f = as.formula(paste(res, "~ ", "B20 + B25 + B30 + MB5 + MB10 + 0"))
eblup_vol <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 100)
eblup_vol


f = as.formula(paste(res, "~ ", "B20 + B25 + B30 + 0"))
mseREML_vol <- mseFH(f, vardir = var, data = regdata, MAXITER = 100)
mseREML_vol
f = as.formula(paste(res, "~ ", "B20 + B25 + B30 + 0"))
eblup_vol <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 100)
eblup_vol

if (res == "Volume" & src == "GEDI_NLCD" & statecd == 51) {
  # compare county eblup estimates to direct
  yy = mseREML_vol$est$eblup
  xx = regdata$Volume

  max_y = max(yy)
  max_x = max(xx)
  min_y = min(yy)
  min_x = min(xx)

  png(
    file.path("EBLUPS_SE.png"),
    res = 300,
    width = 3.25,
    height = 3.25,
    units = "in"
  )
  par(mfrow = c(1, 1), mar = c(2.0, 2.1, 0.5, 0.5) + .1)
  par(mfrow = c(1, 1), mar = c(2.5, 2.5, 0.5, 0.5) + .1)
  plot(xx, yy, ann = FALSE, yaxt = "n", xaxt = "n", cex = .5)
  axis(
    1,
    cex.axis = .7,
    padj = -2,
    tck = -.02,
    at = seq(from = 0, to = max_x, by = 5)
  )
  axis(
    2,
    cex.axis = .7,
    padj = 2,
    tck = -.02,
    at = seq(from = 0, to = max_y, by = 5)
  )
  mtext(
    text = expression(paste("SAE EBLUP Net Volume (million m"^"3", ")")),
    side = 2,
    padj = -2,
    cex = .6
  )
  mtext(
    text = expression(paste("FIA County Net Volume (million m"^"3", ")")),
    side = 1,
    padj = 2,
    cex = .6
  )
  mtext(text = "VA 2019, NLCD 41-43, 90", side = 3, padj = 2, cex = .8)
  abline(0, 1, col = "blue")
  dev.off()

  # plot estimate percent std errors to png file
  cv_direct_FIA = 100 * sqrt(regdata$var[-96:-97]) / regdata$Volume[-96:-97]
  cv_eblup_FIA = 100 * sqrt(mseREML_vol$mse[-96:-97]) / regdata$Volume[-96:-97]

  max_y = max(cv_eblup_FIA, na.rm = T)
  max_x = max(cv_direct_FIA, na.rm = T)
  min_y = min(cv_eblup_FIA, na.rm = T)
  min_x = min(cv_direct_FIA, na.rm = T)

  png(
    file.path("EBLUPS_SE.png"),
    res = 300,
    width = 3.25,
    height = 3.25,
    units = "in"
  )
  par(mfrow = c(1, 1), mar = c(2.0, 2.1, 0.5, 0.5) + .1)
  par(mfrow = c(1, 1), mar = c(2.5, 2.5, 0.5, 0.5) + .1)
  plot(
    cv_eblup_FIA ~ cv_direct_FIA,
    ann = FALSE,
    yaxt = "n",
    xaxt = "n",
    cex = .5
  )
  axis(
    1,
    cex.axis = .7,
    padj = -2,
    tck = -.02,
    at = seq(from = 0, to = max_x, by = 10)
  )
  axis(
    2,
    cex.axis = .7,
    padj = 2,
    tck = -.02,
    at = seq(from = 0, to = max_y, by = 2)
  )
  mtext(
    text = expression(paste("SAE EBLUP Net Volume (million m"^"3", ")")),
    side = 2,
    padj = -2,
    cex = .6
  )
  mtext(
    text = expression(paste("FIA County Net Volume (million m"^"3", ")")),
    side = 1,
    padj = 2,
    cex = .6
  )
  mtext(text = "VA 2019, NLCD 41-43, 90", side = 3, padj = 2, cex = .8)
  abline(0, 1, col = "blue")
  dev.off()
}


f = as.formula(paste(res, "~ ", "B20 + B25 + B30 + 0"))
eblup_fit__NLCD_AGB <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 100)
eblup_fit__NLCD_AGB

f = as.formula(paste(res, "~ ", "B15 + B25 + B30 + 0"))
eblup_fit_NLCD_vol <- eblupFH_3(f, vardir = var, data = regdata, MAXITER = 100)
eblup_fit_NLCD_vol
