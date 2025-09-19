library(sae)
source(file.path("/home/rstudio/data/temp/adj_YL_FisherScore_eblupFH.R"))
source(file.path("/home/rstudio/data/temp/adj_YL_FisherScore_mseFH.R"))

path_naip <- "/home/rstudio/data/NAIP"
path_gedi <- "/home/rstudio/data/GEDI"
path_fia <- file.path("/home/rstudio/data/FIADB/RDS/")
long_data <- readRDS(file.path(path_fia,"FIA_GEDI_for_Fay-Herriot.RDS"))

# names(long_data)
# table(long_data$SOURCE,long_data$response)

# res = "Volume"                 # c("Biomass","Volume")
# src = "GEDI_NLCD"            # c("GEDI_default","GEDI_NLCD","NAIP_noWater","NAIP_GEDI","NAIP_NLCD")
# statecd = 37                    # c(37,47,51)


best_naip_fn <- dir(path_naip,pattern="^best_.*.RDS")
best_gedi_fn <- dir(path_gedi,pattern="^best_.*.RDS")


temp <- lapply(best_naip_fn,function(x){
  best_naip <- readRDS(file.path(path_naip,x))
  list(STATECD=best_naip[[1]],SOURCE=best_naip[[2]],MODEL=best_naip[[3]])
})

best_naip <- do.call(rbind,temp)

temp <- lapply(best_gedi_fn,function(x){
  best_naip <- readRDS(file.path(path_gedi,x))
  list(STATECD=best_naip[[1]],SOURCE=best_naip[[2]],MODEL=best_naip[[3]])
})

best_gedi <- do.call(rbind,temp)

best_models <- rbind(best_naip,best_gedi)
# x = 3
refit_best <- function(x){
  f_string <- paste(best_models[x,3])
  f = as.formula(f_string)
  res = strsplit(f_string," ~")[[1]][1]
  src <- paste(best_models[x,2])
  statecd <- as.integer(best_models[x,1])
  
  regdata <- long_data %>% filter(response == res,SOURCE == src,STATECD == statecd) %>% 
    rename(!!res := value,
           `B5` = `5`,
           `B10` = `10`,
           `B15` = `15`,
           `B20` = `20`,
           `B25` = `25`,
           `B30` = `30`,
           `B35` = `35`) %>%
    mutate(`MB5` = M*`B5`,
           `MB10` = M*`B10`,
           `MB15` = M*`B15`,
           `MB20` = M*`B20`,
           `MB25` = M*`B25`,
           `MB30` = M*`B30`,
           `MB35` = M*`B35`)
  # replace NA with zero in CHM height bins
  regdata[,14:27][is.na(regdata[,14:27])] <- 0
  
  eblup_fit <- eblupFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  # mse_fit <- my_mseFH(formula=f,vardir=var,method = "REML",MAXITER = 1000,data=regdata)
  
  if(!eblup_fit$fit$convergence)stop("Model: ",
                                       paste(best_models[x,3],"did not converge for statecd: "),
                                       statecd,paste(" source: "),src)
  # if(!mse_fit$est$fit$convergence)stop("Model: ",
  #                                      paste(best_models[x,3],"did not converge for statecd: "),
  #                                      statecd,paste(" source: "),src)
  # return AIC stats for graphing
  # aic <- mse_fit$est$fit$goodness[2]
  # refvar <- mse_fit$est$fit$refvar
  # data.frame(STATECD=as.integer(statecd),SOURCE=src,RESPONSE=res,
  #            N_PAR=as.integer(nrow(mse_fit$est$fit$estcoef)),AIC=as.numeric(aic),refvar = refvar)
  aic <- eblup_fit$fit$goodness[2]
  refvar <- eblup_fit$fit$refvar
  data.frame(STATECD=as.integer(statecd),SOURCE=src,RESPONSE=res,
             N_PAR=as.integer(nrow(eblup_fit$fit$estcoef)),AIC=as.numeric(aic),refvar = refvar)

  # return(mse_fit)
  # best_models[1:2,3]
  # str(best_models)            
  
}

# temp <- lapply(c(1,3,5),function(x)refit_best(x))
# temp[[1]]$est$fit$estcoef
# temp[[2]]$est$fit$estcoef
# temp[[3]]$est$fit$estcoef

  temp <- lapply(1:length(best_models[,1]),function(x)refit_best(x))

results <- do.call(rbind,temp)
# which(results$SOURCE == "NAIP_NLCD" & results$STATECD %in% c(37,51) & results$RESPONSE == "Volume")
# which(results$SOURCE == "GEDI_default" & results$STATECD %in% c(47) & results$RESPONSE == "Volume")

test <- (data.frame(STATECD=unlist(best_models[1:30]),
                    SOURCE=unlist(best_models[31:60]),
                    RESPONSE=unlist(lapply(strsplit(as.character(unlist(best_models[61:90]))," ~"),'[',1)),
                    MODEL=as.character(unlist(best_models[61:90]))))

results2 <-  left_join(results,test) %>%
  group_by(STATECD,RESPONSE) %>%
  arrange(STATECD,RESPONSE,AIC)
as.data.frame(results2)

# change replace to TRUE if you want to replace the previous saved results
fwrite(results2,file.path(path_gedi,"Best_models.csv"),replace = FALSE)

# runs to here without error (PJR)

results2 <- fread(file.path(path_gedi,"Best_models.csv"))

Biomass_AIC <- results %>% dplyr::filter(RESPONSE == "Biomass") %>% arrange(STATECD,AIC)
# make a table to chart Biomass model results
Biomass_AIC <- results %>% filter(RESPONSE == "Biomass") %>%
  dplyr::select(-N_PAR,-refvar) %>%
  tidyr::spread(SOURCE,AIC)

row.names(Biomass_AIC) <- Biomass_AIC$STATECD
Biomass_AIC <- Biomass_AIC[,-1:-2]
to_plot <- as.matrix(Biomass_AIC)
row.names(to_plot) <- Biomass_AIC$STATECD
barplot(height=to_plot,beside=TRUE,main="Biomass",ylab="AIC")

Volume_AIC <- results %>% filter(RESPONSE == "Volume") %>%
  dplyr::select(-N_PAR,-refvar) %>%
  spread(SOURCE,AIC)

row.names(Volume_AIC) <- Volume_AIC$STATECD
Volume_AIC <- Volume_AIC[,-1:-2]
to_plot <- as.matrix(Volume_AIC)
barplot(height=to_plot,beside=TRUE,main="Volume")

Biomass_refvar <- results %>% dplyr::filter(RESPONSE == "Biomass") %>% arrange(STATECD,refvar)
# make a table to chart Biomass model results
Biomass_refvar <- results %>% filter(RESPONSE == "Biomass") %>%
  dplyr::select(-N_PAR,-AIC) %>%
  tidyr::spread(SOURCE,refvar)

row.names(Biomass_refvar) <- Biomass_refvar$STATECD
Biomass_refvar <- Biomass_refvar[,-1:-2]
to_plot <- as.matrix(Biomass_refvar)
row.names(to_plot) <- Biomass_refvar$STATECD
barplot(height=to_plot,beside=TRUE,main="Biomass",ylab="refvar")

Volume_refvar <- results %>% dplyr::filter(RESPONSE == "Volume") %>% arrange(STATECD,refvar)
# make a table to chart Volume model results
Volume_refvar <- results %>% filter(RESPONSE == "Volume") %>%
  dplyr::select(-N_PAR,-AIC) %>%
  tidyr::spread(SOURCE,refvar)

row.names(Volume_refvar) <- Volume_refvar$STATECD
Volume_refvar <- Volume_refvar[,-1:-2]
to_plot <- as.matrix(Volume_refvar)
row.names(to_plot) <- Volume_refvar$STATECD
barplot(height=to_plot,beside=TRUE,main="Volume",ylab="refvar")


return_estimates <- function(x){
  f_string <- paste(best_models[x,3])
  f = as.formula(f_string)
  res = strsplit(f_string," ~")[[1]][1]
  src <- paste(best_models[x,2])
  statecd <- as.integer(best_models[x,1])
  
  regdata <- long_data %>% filter(response == res,SOURCE == src,STATECD == statecd) %>% 
    rename(!!res := value,
           `B5` = `5`,
           `B10` = `10`,
           `B15` = `15`,
           `B20` = `20`,
           `B25` = `25`,
           `B30` = `30`,
           `B35` = `35`) %>%
    mutate(`MB5` = M*`B5`,
           `MB10` = M*`B10`,
           `MB15` = M*`B15`,
           `MB20` = M*`B20`,
           `MB25` = M*`B25`,
           `MB30` = M*`B30`,
           `MB35` = M*`B35`)
  # replace NA with zero in CHM height bins
  regdata[,14:27][is.na(regdata[,14:27])] <- 0
  
  # eblup_fit <- eblupFH(f,vardir=var,data=regdata,MAXITER = 1000)
  mse_fit <- mseFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  eblup_fit <- eblupFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  
  
  if(!eblup_fit$fit$convergence)stop("Model: ",
                                       paste(best_models[x,3],"did not converge for statecd: "),
                                       statecd,paste(" source: "),src)
  # return AIC stats for graphing
  # aic <- mse_fit$est$fit$goodness[2]
  # data.frame(STATECD=as.integer(statecd),SOURCE=src,RESPONSE=res,
  #            N_PAR=as.integer(nrow(mse_fit$est$fit$estcoef)),AIC=as.numeric(aic))
  # return efficiency stats for counties
  syn_pred <- unlist(lapply(1:nrow(regdata),function(x){sum(regdata[x,all.vars(f)][,-1] * eblup_fit$fit$estcoef$beta)}))
  syn_pred2 <- unlist(lapply(1:nrow(regdata),function(x){sum(regdata[x,all.vars(f)][,-1] * mse_fit$est$fit$estcoef$beta)}))
  
  if(res == "Biomass"){
    data.frame(res = res,src = src,STATECD=statecd,surveyunit=regdata$surveyunit,
               COUNTYCD=regdata$COUNTYCD,COUNTYNAME = regdata$COUNTYNAME,
               direct_var = regdata$var,
               FH_mse = mse_fit$mse, 
               RE = mse_fit$mse/regdata$var,
               SER = sqrt(mse_fit$mse/regdata$var),
               direct_est = regdata$Biomass,
               FH_est = mse_fit$est$eblup,
               resid = mse_fit$est$eblup - regdata$Biomass,
               syn_pred = syn_pred)
  }else{
    data.frame(res = res,src = src,STATECD=statecd,surveyunit=regdata$surveyunit,
               COUNTYCD=regdata$COUNTYCD,COUNTYNAME = regdata$COUNTYNAME,
               direct_var = regdata$var,
               FH_mse = mse_fit$mse, 
               RE = mse_fit$mse/regdata$var,
               SER = sqrt(mse_fit$mse/regdata$var),
               direct_est = regdata$Volume,
               FH_est = mse_fit$est$eblup,
               resid = mse_fit$est$eblup - regdata$Volume,
               syn_pred = syn_pred)
  }
  
  
  # refvar <- mse_fit$est$fit$refvar
  # return(mse_fit)
  # best_models[1:2,3]
  # str(best_models)            
  
}

estimates <- do.call(rbind,lapply(1:nrow(best_models),function(x)return_estimates(x)))
fwrite(estimates,file.path(path_gedi,"Best_model_EBLUPs.csv"),replace = FALSE)
best_summary <- estimates %>% group_by(STATECD,res,src) %>% 
  summarize(mean_ser = mean(SER)) %>% 
  as.data.frame()
fwrite(best_summary,file.path(path_gedi,"Best_model_SERs.csv"),replace = FALSE)

return_coefs <- function(x){
  f_string <- paste(best_models[x,3])
  f = as.formula(f_string)
  res = strsplit(f_string," ~")[[1]][1]
  src <- paste(best_models[x,2])
  statecd <- as.integer(best_models[x,1])
  
  regdata <- long_data %>% filter(response == res,SOURCE == src,STATECD == statecd) %>% 
    rename(!!res := value,
           `B5` = `5`,
           `B10` = `10`,
           `B15` = `15`,
           `B20` = `20`,
           `B25` = `25`,
           `B30` = `30`,
           `B35` = `35`) %>%
    mutate(`MB5` = M*`B5`,
           `MB10` = M*`B10`,
           `MB15` = M*`B15`,
           `MB20` = M*`B20`,
           `MB25` = M*`B25`,
           `MB30` = M*`B30`,
           `MB35` = M*`B35`)
  # replace NA with zero in CHM height bins
  regdata[,14:27][is.na(regdata[,14:27])] <- 0
  
  # eblup_fit <- eblupFH(f,vardir=var,data=regdata,MAXITER = 1000)
  # mse_fit <- mseFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  eblup_fit <- eblupFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  
  if(!eblup_fit$fit$convergence)stop("Model: ",
                                     paste(best_models[x,3],"did not converge for statecd: "),
                                     statecd,paste(" source: "),src)
  data.frame(res = res,src = src,STATECD=statecd,
             predictor=rownames(eblup_fit$fit$estcoef),
             value=eblup_fit$fit$estcoef$beta,
             pvalue=eblup_fit$fit$estcoef$pvalue)
  
  # refvar <- mse_fit$est$fit$refvar
  # return(mse_fit)
  # best_models[x,3]
  # str(best_models)            
  
}

coefficients <- do.call(rbind,lapply(1:nrow(best_models),function(x)return_coefs(x)))
coef_wide <- coefficients %>% dplyr::select(-pvalue) %>% spread(predictor,value)
fwrite(coefficients,file.path(path_gedi,"Best_model_coeficients.csv"),replace = FALSE)
fwrite(coef_wide,file.path(path_gedi,"Best_model_coeficients_wide.csv"),replace = FALSE)

# graph frequencies of coefficients in best models
# tables give values manually entered into barplot data df
table(coefficients$predictor[coefficients$res == "Volume"])[c(7,1:6,8:12)]
table(coefficients$predictor[coefficients$res == "Biomass"])[c(7,1:6,14,8:13)]
barplot_data <- data.frame(values = c(2,5,3,3,7,8,8,6,11,12,9,9,7,7),  # Create example data
                   group = rep(c("B5","B10","B15","B20","B25","B30","B35"),
                               each = 2),
                   subgroup = c("Volume","Biomass"))
bp_data <- reshape(barplot_data,                        # Modify data for Base R barplot
                   idvar = "subgroup",
                   timevar = "group",
                   direction = "wide")
row.names(bp_data) <- bp_data$subgroup
bp_data <- bp_data[ , 2:ncol(bp_data)]
colnames(bp_data) <- c("M/B5","M/B10","M/B15","M/B20","M/B25","M/B30","M/B35")
bp_data <- as.matrix(bp_data)
bp_data 

png(file.path(path_gedi,"/results/Coeff_Freqs.png"),
    width=5,height=5,units="in",res=400)
barplot(height = bp_data,                       # Grouped barplot using Base R
        beside = TRUE,horiz=TRUE,las=1,
        axisnames = FALSE,xaxt = "n",
        space = c(0,.5),
        axis.lty = 1,
        
        ylab = "CHM height bin coefficient",
        xlab = "Frequency in best models",
        legend.text=TRUE,
        args.legend = list(bty="n",x = "bottomright",
                           inset=.02,cex=1.1,y.intersp=0.7))
axis(side=1,at=0:11)
par(las=1)
axis(side=2,labels=colnames(bp_data),at=c(1.5,4,6.5,9,11.5,14,16.5),
     hadj=0.625,lwd.ticks=0)
dev.off()

estimates %>% filter(STATECD==37,src=="GEDI_default",surveyunit==2) %>% 
  dplyr::select(direct_est,FH_est) %>% plot()
abline(0,1,col="blue")

estimates %>% filter(STATECD==37,src=="GEDI_default",surveyunit==2,direct_est>22)

test <- long_data %>% filter(STATECD==37,response=="Biomass")
head(test)

hist(test$`5`)
hist(test$`10`)
hist(test$`15`)
hist(test$`20`)
hist(test$`25`)
hist(test$`30`)
hist(test$`35`)

library(ggplot2)

p <- ggplot(test, aes(x=SOURCE, y=`5`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`10`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`15`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`20`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`25`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`30`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p <- ggplot(test, aes(x=SOURCE, y=`35`, fill=SOURCE)) + # fill=name allow to automatically dedicate a color for each group
  geom_violin()

p
# Best model residuals (AIC) plotted by Survey unit -----
lapply(1:length(best_models[,1]),function(x){
  test <- return_estimates(x)
  statecd = test[1,3]
  src = test[1,2]
  res = test[1,1]
  # test %>% dplyr::select(direct_est,RE) %>% plot()
  # test2 <- long_data %>% filter(response == res,SOURCE == src,STATECD == statecd) %>%
  #   left_join(test)
  
  fn_png <- file.path(path_naip,"Results/Plots",paste0(res,"_",statecd,src,".png"))
  png(fn_png,res=300,width=4,height=3,units="in")
  par(mfrow=c(1,1),mar=c(3,3,2,1)+.1,cex.main=1,mgp=c(2,1,0))
  test %>% dplyr::select(direct_est,resid) %>% plot(.,main=paste0("State ",statecd," ",res,", source: ",src),
                                                    xlab="Direct estimate",ylab="F-H Residual",col=test$surveyunit)
  n_units <- length(unique(test$surveyunit))
  colors <- unique(test$surveyunit)
  for(i in 1:n_units){
    su_i <- which(test$surveyunit == colors[i])
    lw1 <- loess(resid ~ direct_est,data=test[su_i,])
    j <- order(test$direct_est[su_i])
    lines(test$direct_est[su_i][j],lw1$fitted[j],col=colors[i],lwd=2)
  }
  # legend(x=max(test$direct_est)-2,y=max(test$resid),legend=unique(test$surveyunit),pch=1,col=unique(test$surveyunit))
  legend(x=0.3,y=min(test$resid)/3,legend=unique(test$surveyunit),pch=1,col=colors,xjust=0,cex=.5)
  abline(0,0,col="blue")
  dev.off()
})



return_best <- function(x){
  f_string <- paste(best_models[x,3])
  f = as.formula(f_string)
  res = strsplit(f_string," ~")[[1]][1]
  src <- paste(best_models[x,2])
  statecd <- as.integer(best_models[x,1])
  
  regdata <- long_data %>% filter(response == res,SOURCE == src,STATECD == statecd) %>% 
    rename(!!res := value,
           `B5` = `5`,
           `B10` = `10`,
           `B15` = `15`,
           `B20` = `20`,
           `B25` = `25`,
           `B30` = `30`,
           `B35` = `35`) %>%
    mutate(`MB5` = M*`B5`,
           `MB10` = M*`B10`,
           `MB15` = M*`B15`,
           `MB20` = M*`B20`,
           `MB25` = M*`B25`,
           `MB30` = M*`B30`,
           `MB35` = M*`B35`)
  # replace NA with zero in CHM height bins
  regdata[,14:27][is.na(regdata[,14:27])] <- 0
  
  # eblup_fit <- eblupFH(f,vardir=var,data=regdata,MAXITER = 1000)
  mse_fit <- mseFH_3(f,vardir=var,data=regdata,MAXITER = 1000)
  
  if(!mse_fit$est$fit$convergence)stop("Model: ",
                                       paste(best_models[x,3],"did not converge for statecd: "),
                                       statecd,paste(" source: "),src)
  # return AIC stats for graphing
  # aic <- mse_fit$est$fit$goodness[2]
  # data.frame(STATECD=as.integer(statecd),SOURCE=src,RESPONSE=res,
  #            N_PAR=as.integer(nrow(mse_fit$est$fit$estcoef)),AIC=as.numeric(aic))
  # return efficiency stats for counties
  syn_pred <- unlist(lapply(1:nrow(regdata),function(x){sum(regdata[x,all.vars(f)][,-1] * mse_fit$est$fit$estcoef$beta)}))
  
  # if(res == "Biomass"){
  #   data.frame(res = res,src = src,STATECD=statecd,surveyunit=regdata$surveyunit,
  #              COUNTYCD=regdata$COUNTYCD,COUNTYNAME = regdata$COUNTYNAME,
  #              direct_var = regdata$var,
  #              FH_mse = mse_fit$mse, 
  #              RE = mse_fit$mse/regdata$var,
  #              SER = sqrt(mse_fit$mse/regdata$var),
  #              direct_est = regdata$Biomass,
  #              FH_est = mse_fit$est$eblup,
  #              resid = mse_fit$est$eblup - regdata$Biomass,
  #              syn_pred = syn_pred)
  # }else{
  #   data.frame(res = res,src = src,STATECD=statecd,surveyunit=regdata$surveyunit,
  #              COUNTYCD=regdata$COUNTYCD,COUNTYNAME = regdata$COUNTYNAME,
  #              direct_var = regdata$var,
  #              FH_mse = mse_fit$mse, 
  #              RE = mse_fit$mse/regdata$var,
  #              SER = sqrt(mse_fit$mse/regdata$var),
  #              direct_est = regdata$Volume,
  #              FH_est = mse_fit$est$eblup,
  #              resid = mse_fit$est$eblup - regdata$Volume,
  #              syn_pred = syn_pred)
  # }
  
  
  # refvar <- mse_fit$est$fit$refvar
  # return(mse_fit)
  # best_models[1:2,3]
  # str(best_models)            
  return(mse_fit)
}

# UNDER CONSTRUCTION: calculate reletive efficiencies ETC. -----
test <- lapply(1:length(temp),function(x)return_estimates(x))
refvar <- lapply(1:length(temp),function(x)return_best(x)$est$fit$refvar)

aic <- lapply(1:length(temp),function(x)return_best(x)$est$fit$goodness[2])
refvar <- lapply(1:length(temp),function(x)return_best(x)$est$fit$refvar)

# unlist(aic)
# 
# aic <- mse_fit$est$fit$goodness[2]
# refvar <- mse_fit$est$fit$refvar

