## $Id$
curveRep <- function(x, y, id, kn=5, kxdist=5, k=5, p=5, force1=TRUE,
                     metric=c('euclidean','manhattan'),
                     smooth=FALSE, extrap=FALSE, pr=FALSE) {
  require(cluster)
  metric <- match.arg(metric)
  
  id <- as.character(id)
  omit <- is.na(x + y)
  missfreq <- NULL; nomit <- sum(omit)
  if(nomit) {
    m <- tapply(omit, id, sum)
    missfreq <- table(m)
    x <- x[!omit]; y <- y[!omit]; id <- id[!omit]
  }
  n <- length(x)
  ns <- table(id)
  nunique <- length(unique(ns))

  if(nunique==1 || nunique <= kn) {
    cuts <- sort(unique(ns))
    ncuts <- c(cuts, Inf)
  } else {
    grouped.n <- cut2(ns, g=kn)
    cuts <- cut2(ns, g=kn, onlycuts=TRUE)
    if(force1 && cuts[1] > 1 && min(ns)==1)
      cuts <- sort(unique(c(1:2, cuts)))
    ncuts <- c(unique(c(min(ns), cuts)), Inf)
  }
  nlev <- length(ncuts)-1
  res <- vector('list', nlev); names(res) <- as.character(cuts)

  clust <- function(x, k)
    if(diff(range(x))==0) rep(1, NROW(x)) else
    clara(x, k, metric=metric)$clustering

  interp <- if(extrap)
    function(x, y=NULL, xout) approxExtrap(x, y, xout=xout)$y else
    function(x, y=NULL, xout) approx(x, y, xout=xout, rule=2)$y

  ## Cluster by sample size first
  if(pr) cat('Creating',nlev,'sample size groups\n\n')
  for(i in 1:nlev) {
    ## Get list of curve ids in this sample size group
    ids <- names(ns)[ns >= ncuts[i] & ns < ncuts[i+1]]
    if(pr) cat('Processing sample size [',ncuts[i],',',ncuts[i+1],
               ') containing ', length(ids),' curves\n',sep='')
    if(length(ids) < kxdist) res[[i]] <- list(ids) else {
      ## Cluster by distribution of x within sample size group
      ## Summarize these ids by clustering on range of x,
      ## plus the largest gap if minimum sample size > 2
      ## Use only the x position is min sample size is 1
      s <- id %in% ids
      ssize <- min(tapply(x[s], id[s], function(w) length(unique(w))))
      z <- tapply((1:n)[s], id[s],
                  function(j) if(ssize==1) x[j][1] else
                  if(ssize==2) range(x[j]) else
                  c(range(x[j]),max(diff(sort(x[j])))))
      z <- matrix(unlist(z), nrow=length(z), byrow=TRUE)
      if(kxdist > nrow(z) - 1)
        stop('number of curves to cluster must be >= kxdist+1')
      distclusters <- clust(z, kxdist)
      if(pr) {
        cat(' Number of curves in each x-dist cluster:\n')
        print(table(distclusters))
      }
      resi <- list()
      ## Within x distribution and within sample size interval,
      ## cluster on linearly interpolated y at p equally spaced x points
      ## unless <2 unique x-points for some curve
      for(clus in 1:max(distclusters)) {
        idc <- ids[distclusters==clus]
        if(pr) cat(' Processing x-distribution group', clus,
                   'containing', length(idc),'curves\n')
        s <- id %in% idc
        ssize <- min(tapply(x[s], id[s], function(w) length(unique(w))))
        if(ssize > 1) {
          xrange <- range(x[s])
          xseq <- seq(xrange[1], xrange[2], length.out=p)
        }
        g <- if(ssize==1) function(j) c(mean(x[j]), mean(y[j])) else
         if(smooth && ssize > 2)
           function(j) interp(lowess(x[j],y[j]), xout=xseq) else
           function(j) interp(x[j], y[j], xout=xseq)
        
        z <- tapply((1:n)[s], id[s], g)
        z <- matrix(unlist(z), nrow=length(idc), byrow=TRUE)
        yclusters <- clust(z, min(k, max(length(idc)-2,1)))
        names(yclusters) <- idc
        resi[[clus]] <- yclusters
      }
      res[[i]] <- resi
    }
  }
  structure(list(res=res, ns=table(ns), nomit=nomit, missfreq=missfreq,
                 ncuts=ncuts[-length(ncuts)], kn=kn, kxdist=kxdist, k=k, p=p,
                 smooth=smooth, x=x, y=y, id=id),
            class='curveRep')
}

print.curveRep <- function(x, ...) {
  sm <- if(x$smooth) 'smooth' else 'not smoothed'
  cat('kn:',x$kn, ' kxdist:',x$kxdist, ' k:',x$k,
      ' p:',x$p, ' ', sm, '\n\n', sep='')
  cat('Frequencies of number of non-missing values per curve:\n')
  print(x$ns)
  if(length(x$missfreq)) {
    cat(x$nomit, 'missing values excluded.\n\n')
    cat('\nFrequency of number of missing values per curve:\n')
    print(x$missfreq)
  }
  cat('\nSample size cuts:', paste(x$ncuts, collapse=' '),'\n')
  cat('Number of x distribution groups per sample size group:',
      paste(sapply(x$res, length), collapse=' '),'\n\n')
  res <- x$res
  nn <- c(names(res),'')
  for(i in 1:length(res)) {
    ngroup <- res[[i]]
    maxclus <- max(unlist(ngroup))
    w <- matrix(NA, nrow=maxclus, ncol=length(ngroup),
                dimnames=list(paste('Cluster',1:maxclus),
                  paste('x-Dist', 1:length(ngroup))))
    j <- 0
    for(xdistgroup in ngroup) {
      j <- j+1
      w[,j] <- tabulate(xdistgroup, nbins=maxclus)
    }
    cat('\nNumber of Curves for Sample Size ', nn[i],'-',nn[i+1],'\n',sep='')
    print(w)
  }
  invisible()
}

plot.curveRep <- function(x, which=1:length(res),
                          method=c('all','lattice'),
                          m=NULL, probs=c(.5,.25,.75),
                          nx=NULL, fill=TRUE, idcol=NULL,
                          xlim=range(x), ylim=range(y),
                          xlab='x', ylab='y') {
  method <- match.arg(method)
  res <- x$res; id <- x$id; y <- x$y; k <- x$k; x <- x$x
  nm <- names(res)

  samp <- function(ids)
    if(!length(m) || is.character(m) ||
       length(ids) <= m) ids else sample(ids, m)
  if(is.character(m) &&
     (m != 'quantiles' || method != 'lattice'))
    stop('improper value of m')
  
  if(method=='lattice') {
    if(length(which) != 1)
      stop('must specify one n range to plot for method="lattice"')
    require(lattice)
    nres <- names(res)
    if(length(nres)==1) nname <- NULL else
    nname <- if(which==length(nres))
      paste('n>=',nres[which],sep='') else
      if(nres[which]=='1' & nres[which+1]=='2') 'n=1' else
      paste(nres[which],'<=n<',nres[which+1],sep='')
    
    res <- res[[which]]
    n <- length(x)
    X <- Y <- xdist <- cluster <- numeric(n); curve <- character(n)
    st <- 1
    for(jx in 1:length(res)) {
      xgroup  <- res[[jx]]
      ids <- names(xgroup)
      for(jclus in 1:max(xgroup)) {
        ids.in.cluster <- samp(ids[xgroup==jclus])
        for(cur in ids.in.cluster) {
          s <- id %in% cur
          np <- sum(s)
          i <- order(x[s])
          en <- st+np-1
          if(en > n) stop('program logic error 1')
          X[st:en]       <- x[s][i]
          Y[st:en]       <- y[s][i]
          xdist[st:en]   <- jx
          cluster[st:en] <- jclus
          curve[st:en]   <- cur
          st <- st+np
        }
      }
    }
    Y <- Y[1:en]; X <- X[1:en]
    distribution <- xdist[1:en]; cluster <- cluster[1:en]
    curve <- curve[1:en]
    pan <- if(length(idcol))
      function(x, y, subscripts, groups, type, ...) {
        groups <- as.factor(groups)[subscripts]
        for(g in levels(groups)) {
          idx <- groups == g
          xx <- x[idx]; yy <- y[idx]; ccols <- idcol[g]
          if (any(idx)) { 
            switch(type, 
                   p = lpoints(xx, yy, col = ccols), 
                   l = llines(xx, yy, col = ccols), 
                   b = { lpoints(xx, yy, col = ccols) 
                         llines(xx, yy, col = ccols) }) 
          } 
        } 
      } else panel.superpose 
 
    if(is.character(m))
      print(xYplot(Y ~ X | distribution*cluster,
                   method='quantiles', probs=probs, nx=nx,
                   xlab=xlab, ylab=ylab,
                   xlim=xlim, ylim=ylim,
                   main=nname, as.table=TRUE)) else
    print(xyplot(Y ~ X | distribution*cluster, groups=curve,
                 xlab=xlab, ylab=ylab,
                 xlim=xlim, ylim=ylim,
                 type=if(nres[which]=='1')'b' else 'l',
                 main=nname, panel=pan, as.table=TRUE))
    return(invisible())
  }

  for(jn in which) {
    ngroup <- res[[jn]]
    for(jx in 1:length(ngroup)) {
      xgroup <- ngroup[[jx]]
      ids <- names(xgroup)
      for(jclus in 1:max(xgroup)) {
        rids <- ids[xgroup==jclus]
        nc <- length(rids)
        ids.in.cluster <- samp(rids)
        for(curve in 1:length(ids.in.cluster)) {
          s <- id %in% ids.in.cluster[curve]
          i <- order(x[s])
          type <- if(length(unique(x[s]))==1)'b' else 'l'
          if(curve==1) {
            plot(x[s][i], y[s][i], xlab=xlab, ylab=ylab,
                 type='n', xlim=xlim, ylim=ylim)
            title(paste('n=',nm[jn],' x=',jx,
                        ' c=',jclus,' ',nc,' curves', sep=''), cex=.5)
          }
          lines(x[s][i], y[s][i], type=type,
                col=if(length(idcol))
                 idcol[ids.in.cluster[curve]] else curve)
        }
      }
      if(fill && max(xgroup) < k)
        for(i in 1:(k - max(xgroup)))
          plot(0, 0, type='n', axes=FALSE, xlab='', ylab='')
    }
  }
}

curveSmooth <- function(x, y, id, p=NULL, pr=TRUE) {
  omit <- is.na(x + y)
  if(any(omit)) {
    x <- x[!omit]; y <- y[!omit]; id <- id[!omit]
  }
  uid <- unique(id)
  m <- length(uid)
  pp <- length(p)
  if(pp) {
    X <- Y <- numeric(p*m)
    Id <- rep(id, length.out=p*m)
  }
  st <- 1
  ncurve <- 0
  clowess <- function(x, y) {
    ## to get around bug in lowess with occasional wild values
    r <- range(y)
    f <- lowess(x, y)
    f$y <- pmax(pmin(f$y, r[2]), r[1])
    f
  }
  for(j in uid) {
    if(pr) {
      ncurve <- ncurve + 1
      if((ncurve %% 50) == 0) cat(ncurve,'')
    }
    s <- id==j
    xs <- x[s]
    ys <- y[s]
    if(length(unique(xs)) < 3) {
      if(pp) {
        en <- st + length(xs) - 1
        X[st:en] <- xs
        Y[st:en] <- ys
        Id[st:en] <- j
      }
    } else {
      if(pp) {
        uxs <- sort(unique(xs))
        xseq <- if(length(uxs) < p) uxs else
        seq(min(uxs), max(uxs), length.out=p)
        ye <- approx(clowess(xs, ys), xout=xseq)$y
        n <- length(xseq)
        en <- st + n - 1
        X[st:en] <- xseq
        Y[st:en] <- ye
        Id[st:en] <- j
      } else y[s] <- approx(clowess(xs, ys), xout=xs)$y
    }
    st <- en + 1
  }
  if(pr) cat('\n')
  if(pp) {
    X <- X[1:en]
    Y <- Y[1:en]
    Id <- Id[1:en]
    list(x=X, y=Y, id=Id)
  } else list(x=x, y=y, id=id)
}