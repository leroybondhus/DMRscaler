#' get_loc_fdr_pval
#'
#' @param mat matrix with samples on columns and locs on rows
#' @param cases case column names
#' @param controls control column names
#' @param stat_test statistical test used for signifance estimation
#' @param fdr false discover rate desired
#' @param resolution number of bins to use for table
#' @param return_table if set to TRUE returns table of FDR values instead of single value
#'
#' @importFrom foreach foreach
#' @importFrom foreach getDoParWorkers
#' @importFrom foreach %dopar%
#'
#' @return get_loc_fdr_pval returns a dataframe of pvalue cutoffs and corresponding fdr rate at those cutoffs based on permutation. Uses 2x 1/fdr permutations for estimation
#'
#' @export

get_loc_fdr_pval <- function(mat, cases, controls, stat_test, fdr=0.1, resolution=100, return_table=TRUE){
  temp <- split(1:nrow(mat),cut(1:nrow(mat),max(getDoParWorkers(),2),labels=F))
  mat_subs_list <- list()
  mat <- as.matrix(mat)
  for(i in 1:length(temp)){
    mat_subs_list[[i]] <- mat[temp[[i]],]
  }
  tp_pval <- foreach(mat_sub=mat_subs_list, .combine="c") %dopar% {
    tp_p <- numeric(length = nrow(mat_sub))
    for(i in 1:nrow(mat_sub)){
      tp_p[i] <- stat_test(mat_sub[i,cases],mat_sub[i,controls])$p.value
    }
    tp_p
  }



  num_permutations <- max(10, ceiling((1/fdr) * 2))
  if( num_permutations / getDoParWorkers() > 4 ){
    warning( paste(num_permutations," permutations across ", getDoParWorkers(), "worker node.. this may take a while",sep=""))
  }

  if(num_permutations > choose(length(cases)+length(controls),length(cases) )){
    warning(paste("Warning: permutations required for accurate fdr estimation:",num_permutations,
                ",number of possible permutations:", choose(length(cases)+length(controls),length(cases) ),
                ",using ",choose(length(cases)+length(controls),length(cases) ), "permutations", sep=""))
    perms <- combn(length(cases)+length(controls), length(cases))
    perms <- t(perms[,1:floor(ncol(perms)/2)])
  } else {
    perms <- matrix(nrow=num_permutations, ncol=min(length(cases),length(controls)) )
    for(i in 1:nrow(perms)){
      if(length(cases) <= length(controls)){
        perms[i,] <- sample(c(cases,controls), length(cases))

      } else {
        perms[i,] <- sample(c(controls,cases), length(controls))
      }

    }
  }

  print(paste("Running ",num_permutations, " permutations across ", getDoParWorkers()," worker nodes",sep=""))

  pvals <- foreach(i = 1:nrow(perms), .combine="cbind") %dopar% {
    g1 <- perms[i,]
    g2 <- c(cases,controls)[which(!is.element(c(cases,controls),perms[i,]))]
    temp_p <- numeric(length = nrow(mat))
    for(j in 1:nrow(mat)){
      temp_p[j] <- stat_test(mat[j,g1],mat[j,g2])$p.value
    }
    temp_p
  }


  temp_seq <- seq(floor(min(log10(c(tp_pval, as.vector(pvals))))),0,length.out= resolution)
  tp_temp <- hist(log10(tp_pval), temp_seq, plot=F)
  tp_seq <- cumsum(tp_temp$counts / sum(tp_temp$counts))

  temp <- hist(log10(pvals), temp_seq, plot=F)
  p_seq <- cumsum(temp$counts / sum(temp$counts))

  df <- data.frame(log10pval_cutoff=temp_seq[-length(temp_seq)], fdr=p_seq/tp_seq)
  if(return_table){
    return(df)
  } else {
    if(length(which(df$fdr <= fdr))==0){
      warning("desired fdr rate not achieved, use less stringent threshold. Returning 0")
      return(0)
    }
    pval_cutoff <- min(-log10(fdr), 10^df$log10pval_cutoff[max(which( df$fdr <= fdr ))])
    return(pval_cutoff)
  }

}
#
