eblupFH_3 <-function (formula, vardir, method = "REML", MAXITER = 5000, PRECISION = 1e-04, 
                      B = 0, data) 
{
  result <- list(eblup = NA, fit = list(method = method, convergence = TRUE, 
                                        iterations = 0, estcoef = NA, refvar = NA, goodness = NA))
  if (method != "REML" & method != "ML" & method != "FH") 
    stop(" method=\"", method, "\" must be \"REML\", \"ML\" or \"FH\".")
  namevar <- deparse(substitute(vardir))
  if (!missing(data)) {
    formuladata <- model.frame(formula, na.action = na.omit, 
                               data)
    X <- model.matrix(formula, data)
    vardir <- data[, namevar]
  }
  else {
    formuladata <- model.frame(formula, na.action = na.omit)
    X <- model.matrix(formula)
  }
  y <- formuladata[, 1]
  if (attr(attributes(formuladata)$terms, "response") == 1) 
    textformula <- paste(formula[2], formula[1], formula[3])
  else textformula <- paste(formula[1], formula[2])
  if (length(na.action(formuladata)) > 0) 
    stop("Argument formula=", textformula, " contains NA values.")
  if (any(is.na(vardir))) 
    stop("Argument vardir=", namevar, " contains NA values.")
  m <- length(y)
  p <- dim(X)[2]
  Xt <- t(X)
  if (method == "ML") {
    Aest.ML <- 0
    Aest.ML[1] <- median(vardir)
    k <- 0
    diff <- PRECISION + 1
    while ((diff > PRECISION) & (k < MAXITER)) {
      k <- k + 1
      Vi <- 1/(Aest.ML[k] + vardir)
      XtVi <- t(Vi * X)
      Q <- solve(XtVi %*% X, tol=1e-30)
      P <- diag(Vi) - t(XtVi) %*% Q %*% XtVi
      Py <- P %*% y
      shrinkage <- vardir/(vardir + Aest.ML[k])
      s <- (-0.5) * sum(Vi) + 0.5 * (t(Py) %*% Py) + (1/m) * sum((vardir/(vardir + Aest.ML[k])**2)) / (atan(sum(diag(m)-diag(shrinkage)))) * (1+sum((diag(m)-diag((vardir/(vardir+Aest.ML[k])))**2)))
      F <- 0.5 * sum(Vi^2)
      Aest.ML[k + 1] <- Aest.ML[k] + s/F
      diff <- abs((Aest.ML[k + 1] - Aest.ML[k])/Aest.ML[k])
    }
    A.ML <- max(Aest.ML[k + 1], 0)
    result$fit$iterations <- k
    if (k >= MAXITER && diff >= PRECISION) {
      result$fit$convergence <- FALSE
      return(result)
    }
    Vi <- 1/(A.ML + vardir)
    XtVi <- t(Vi * X)
    Q <- solve(XtVi %*% X, tol=1e-50)
    beta.ML <- Q %*% XtVi %*% y
    varA <- 1/F
    std.errorbeta <- sqrt(diag(Q))
    tvalue <- beta.ML/std.errorbeta
    pvalue <- 2 * pnorm(abs(tvalue), lower.tail = FALSE)
    Xbeta.ML <- X %*% beta.ML
    resid <- y - Xbeta.ML
    shrinkage <- vardir/(vardir + A.ML)
    loglike <- (-0.5) * (sum(log(2 * pi * (A.ML + vardir)) + 
                               (resid^2)/(A.ML + vardir))) + (1/m)*log(atan(sum(diag(m)-diag(shrinkage))))
    AIC <- (-2) * loglike + 2 * (p + 1)
    BIC <- (-2) * loglike + (p + 1) * log(m)
    goodness <- c(loglike = loglike, AIC = AIC, BIC = BIC)
    coef <- data.frame(beta = beta.ML, std.error = std.errorbeta, 
                       tvalue, pvalue)
    variance <- A.ML
    EBLUP <- Xbeta.ML + A.ML * Vi * resid
  }
  else if (method == "REML") {
    Aest.REML <- 0
    Aest.REML[1] <- median(vardir)
    k <- 0
    diff <- PRECISION + 1
    while ((diff > PRECISION) & (k < MAXITER)) {
      k <- k + 1
      Vi <- 1/(Aest.REML[k] + vardir)
      XtVi <- t(Vi * X)
      Q <- solve(XtVi %*% X, tol=1e-50)
      P <- diag(Vi) - t(XtVi) %*% Q %*% XtVi
      Py <- P %*% y
      shrinkage <- vardir/(vardir + Aest.REML[k])
      s <- (-0.5) * sum(diag(P)) + 0.5 * (t(Py) %*% Py) + (1/m) * sum((vardir/(vardir + Aest.REML[k])**2)) / (atan(sum(diag(m)-diag(shrinkage)))) * (1+sum((diag(m)-diag((vardir/(vardir+Aest.REML[k])))**2)))
      F <- 0.5 * sum(diag(P %*% P))
      Aest.REML[k + 1] <- Aest.REML[k] + s/F
      diff <- abs((Aest.REML[k + 1] - Aest.REML[k])/Aest.REML[k])
    }
    A.REML <- max(Aest.REML[k + 1], 0)
    result$fit$iterations <- k
    if (k >= MAXITER && diff >= PRECISION) {
      result$fit$convergence <- FALSE
      return(result)
    }
    Vi <- 1/(A.REML + vardir)
    XtVi <- t(Vi * X)
    Q <- solve(XtVi %*% X, tol=1e-50)
    beta.REML <- Q %*% XtVi %*% y
    varA <- 1/F
    std.errorbeta <- sqrt(diag(Q))
    tvalue <- beta.REML/std.errorbeta
    pvalue <- 2 * pnorm(abs(tvalue), lower.tail = FALSE)
    Xbeta.REML <- X %*% beta.REML
    resid <- y - Xbeta.REML
    shrinkage <- vardir/(vardir + A.REML)
    loglike <- (-0.5) * (sum(log(2 * pi * (A.REML + vardir)) + 
                               (resid^2)/(A.REML + vardir))) + (1/m)*log(atan(sum(diag(m)-diag(shrinkage))))
    AIC <- (-2) * loglike + 2 * (p + 1)
    BIC <- (-2) * loglike + (p + 1) * log(m)
    goodness <- c(loglike = loglike, AIC = AIC, BIC = BIC)
    coef <- data.frame(beta = beta.REML, std.error = std.errorbeta, 
                       tvalue, pvalue)
    variance <- A.REML
    EBLUP <- Xbeta.REML + A.REML * Vi * resid
  }
  else {
    Aest.FH <- NULL
    Aest.FH[1] <- median(vardir)
    k <- 0
    diff <- PRECISION + 1
    while ((diff > PRECISION) & (k < MAXITER)) {
      k <- k + 1
      Vi <- 1/(Aest.FH[k] + vardir)
      XtVi <- t(Vi * X)
      Q <- solve(XtVi %*% X)
      betaaux <- Q %*% XtVi %*% y
      resaux <- y - X %*% betaaux
      s <- sum((resaux^2) * Vi) - (m - p)
      F <- sum(Vi)
      Aest.FH[k + 1] <- Aest.FH[k] + s/F
      diff <- abs((Aest.FH[k + 1] - Aest.FH[k])/Aest.FH[k])
    }
    A.FH <- max(Aest.FH[k + 1], 0)
    result$fit$iterations <- k
    if (k >= MAXITER && diff >= PRECISION) {
      result$fit$convergence <- FALSE
      return(result)
    }
    Vi <- 1/(A.FH + vardir)
    XtVi <- t(Vi * X)
    Q <- solve(XtVi %*% X)
    beta.FH <- Q %*% XtVi %*% y
    varA <- 1/F
    varbeta <- diag(Q)
    std.errorbeta <- sqrt(varbeta)
    zvalue <- beta.FH/std.errorbeta
    pvalue <- 2 * pnorm(abs(zvalue), lower.tail = FALSE)
    Xbeta.FH <- X %*% beta.FH
    resid <- y - Xbeta.FH
    loglike <- (-0.5) * (sum(log(2 * pi * (A.FH + vardir)) + 
                               (resid^2)/(A.FH + vardir)))
    AIC <- (-2) * loglike + 2 * (p + 1)
    BIC <- (-2) * loglike + (p + 1) * log(m)
    goodness <- c(loglike = loglike, AIC = AIC, BIC = BIC)
    coef <- data.frame(beta = beta.FH, std.error = std.errorbeta, 
                       tvalue = zvalue, pvalue)
    variance <- A.FH
    EBLUP <- Xbeta.FH + A.FH * Vi * resid
  }
  result$fit$estcoef <- coef
  result$fit$refvar <- variance
  result$fit$goodness <- goodness
  result$eblup <- EBLUP
  min2loglike <- (-2) * loglike
  KIC <- min2loglike + 3 * (p + 1)
  if (B >= 1) {
    sigma2d <- vardir
    lambdahat <- result$fit$refvar
    betahat <- matrix(result$fit$estcoef[, "beta"], ncol = 1)
    D <- nrow(X)
    B1hatast <- 0
    B3ast <- 0
    B5ast <- 0
    sumlogf_ythetahatastb <- 0
    sumlogf_yastbthetahatastb <- 0
    Xbetahat <- X %*% betahat
    b <- 1
    while (b <= B) {
      uastb <- sqrt(lambdahat) * matrix(data = rnorm(D, 
                                                     mean = 0, sd = 1), nrow = D, ncol = 1)
      eastb <- sqrt(sigma2d) * matrix(data = rnorm(D, mean = 0, 
                                                   sd = 1), nrow = D, ncol = 1)
      yastb <- Xbetahat + uastb + eastb
      resultb <- eblupFH(yastb ~ X - 1, sigma2d, method = method, 
                         MAXITER = MAXITER, PRECISION = PRECISION)
      if (resultb$fit$convergence == FALSE) {
        message <- paste("Bootstrap b=", b, ": ", method, 
                         " iteration does not converge.\n")
        cat(message)
        next
      }
      else {
        betahatastb <- matrix(resultb$fit$estcoef[, "beta"], 
                              ncol = 1)
        lambdahatastb <- resultb$fit$refvar
        Xbetahathatastb2 <- (X %*% (betahat - betahatastb))^2
        yastbXbetahatastb2 <- (yastb - X %*% betahatastb)^2
        lambdahatastbsigma2d <- lambdahatastb + sigma2d
        lambdahatsigma2d <- lambdahat + sigma2d
        B1ast <- sum((lambdahatsigma2d + Xbetahathatastb2 - 
                        yastbXbetahatastb2)/lambdahatastbsigma2d)
        B1hatast <- B1hatast + B1ast
        logf <- (-0.5) * sum(log(2 * pi * lambdahatastbsigma2d) + 
                               ((y - X %*% betahatastb)^2)/lambdahatastbsigma2d)
        sumlogf_ythetahatastb <- sumlogf_ythetahatastb + 
          logf
        sumlogf_yastbthetahatastb <- sumlogf_yastbthetahatastb + 
          resultb$fit$goodness["loglike"]
        B3ast <- B3ast + sum((lambdahatastbsigma2d + 
                                Xbetahathatastb2)/lambdahatsigma2d)
        B5ast <- B5ast + sum(log(lambdahatastbsigma2d) + 
                               yastbXbetahatastb2/lambdahatastbsigma2d)
        b <- b + 1
      }
    }
    B2ast <- sum(log(lambdahatsigma2d)) + B3ast/B - B5ast/B
    AICc <- min2loglike + B1hatast/B
    AICb1 <- as.vector(min2loglike - 2/B * (sumlogf_ythetahatastb - 
                                              sumlogf_yastbthetahatastb))
    AICb2 <- as.vector(min2loglike - 4/B * (sumlogf_ythetahatastb - 
                                              result$fit$goodness["loglike"] * B))
    KICc <- AICc + B2ast
    KICb1 <- AICb1 + B2ast
    KICb2 <- AICb2 + B2ast
    result$fit$goodness <- c(result$fit$goodness, KIC = KIC, 
                             AICc = AICc, AICb1 = AICb1, AICb2 = AICb2, KICc = KICc, 
                             KICb1 = KICb1, KICb2 = KICb2, nBootstrap = B)
  }
  else result$fit$goodness <- c(result$fit$goodness, KIC = KIC)
  return(result)
}
