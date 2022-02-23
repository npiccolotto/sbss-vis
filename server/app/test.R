library('SpatialBSS')
library('compositions')
library('ggplot2')
library('gstat')
library('statnet.common')
library('sp')
library('sf')
library('jsonlite')
library('raster')
library('SDraw')
library('rgdal')
library('spdep')
library('jsonlite')
library('tictoc')
library('reshape2')
library('parallel')
library('tidygraph')

# Tidyverse
library("purrr")
library("tibble")
library("lubridate")
library("dplyr")

setwd('/Users/npiccolotto/Projects/cvast/bssvis/sbss-app/server/app')


#### DATA INIT
set.seed(1)
dataset.name <- Sys.getenv('SBSS_DATASET')
if (dataset.name == '') {
  print("[WARNING]: SBSS_DATASET unset, using default dataset")
  dataset.name <- 'gemas'
}
guidancefile.name <-
  paste(dataset.name, '_guidance.RData', sep = '')

# Get desired guidance granularity.
BLOCK_MAX_LEVEL <- Sys.getenv('SBSS_BLOCK_MAX_LEVEL')
if (BLOCK_MAX_LEVEL == '') {
  print("[WARNING]: SBSS_BLOCK_MAX_LEVEL unset, using default block level")
  BLOCK_MAX_LEVEL <- 8
} else {
  BLOCK_MAX_LEVEL <- as.integer(BLOCK_MAX_LEVEL)
}
KERNEL_MAX_LEVEL <- Sys.getenv('SBSS_KERNEL_MAX_LEVEL')
if (KERNEL_MAX_LEVEL == '') {
  print("[WARNING]: SBSS_KERNEL_MAX_LEVEL unset, using default kernel level")
  KERNEL_MAX_LEVEL <- 4
} else {
  KERNEL_MAX_LEVEL <- as.integer(KERNEL_MAX_LEVEL)
}
IS_COMPOSITE <- Sys.getenv('SBSS_IS_COMPOSITE')
if (IS_COMPOSITE == '') {
  print("[WARNING]: SBSS_IS_COMPOSITE unset, using default value TRUE")
  IS_COMPOSITE <- T
} else {
  IS_COMPOSITE <- as.logical(IS_COMPOSITE)
  if (is.na(IS_COMPOSITE)) {
    print(
      "[WARNING]: Could not infer logical value from SBSS_IS_COMPOSITE, using default value TRUE"
    )
    IS_COMPOSITE <- T
  }
}
NUM_CORES_USED <- max(parallel::detectCores() - 1, 1)
print(paste('[INFO]: Using',NUM_CORES_USED, 'CPU cores'))

dataset.path <- paste('data/', dataset.name, '.csv', sep = '')
dataset.original <- read.csv(dataset.path)

print('== DATASET == ')
print(paste('path: ', dataset.path))
print(paste('nrow: ', nrow(dataset.original)))
print(paste('ncol: ', ncol(dataset.original)))
print(colnames(dataset.original))

# spherical coordinates
WGS84 <- sp::CRS('+init=epsg:4326')
# web mercator as in leaflet for planar projection
WEB_MERC <-
  sp::CRS(
    '+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext  +no_defs'
  )
MARGIN_FACTOR <-
  1.025 # extend bounding box of dataset by this factor so that points are not on any drawn borders

ed <- function(x, y) {
  return(sqrt(sum((x - y) ^ 2)))
}

cov_as_vector <- function(C) {
  return(C[lower.tri(C, diag = T)])
}

ev_diff <- function(C) {
  return(sum(diff(sort(
    abs(eigen(C)$values)
  ))))
}

build_ring_kernel <- function(D, d.min, d.max) {
  n <- ncol(D)
  K <- matrix(0, n, n)
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      d <- D[j, i]
      if (is.na(d)) {
        print(paste('HEY', i, j))
      }
      if (d.min < d && d <= d.max) {
        K[i, j] = 1
        K[j, i] = 1
      }
    }
  }
  return(K)
}


util_flatten_bisected <- function(things) {
  return(purrr::flatten(things))
}

util_bisect_flat <- function(things) {
  agg <- list()
  l <- 0
  while ((2 ^ (l + 1) - 1) <= length(things)) {
    agg <- append(agg, list(things[(2 ^ l):(2 ^ (l + 1) - 1)]))
    
    l <- l + 1
  }
  return(agg)
}

util_chunk <- function(arr, k = 2) {
  n <- length(arr)
  result <- list()
  if (n %% k != 0) {
    stop('no')
  }
  i <- 1
  while (i + k - 1 <= n) {
    result <- append(result, list(arr[i:(i + k - 1)]))
    i <- i + k
  }
  return(result)
}

# takes top left and bottom right points, makes a bounding box
util_expand_to_bbox <- function(topleft, bottomright) {
  extent <- bottomright - topleft
  center <- topleft + extent / 2
  
  M <- matrix(
    c(
      topleft,
      center + c(1,-1) * extent / 2,
      bottomright,
      center + c(-1, 1) * extent / 2
    ),
    ncol = 2,
    byrow = T
  )
  return(M)
}

# Takes a SpatialPolygon, returns it coordinates
util_get_coords <- function(P) {
  return(P@polygons[[1]]@Polygons[[1]]@coords)
}


util_density_to_df <- function(d) {
  return(list(
    bw = d$bw,
    n = d$n,
    density = data.frame(x = d$x, y = d$y)
  ))
}

util_to_ntiles <- function(population,
                           sample = c(),
                           ntiles = 6) {
  percentiles <-
    quantile(population, probs = 0:ntiles * 1 / ntiles) %>% unname()
  
  # return sample as ntiles of population, if provided
  if (length(sample) > 0) {
    return(sample %>% purrr::map(function(m) {
      return(dplyr::last(which(percentiles[1:ntiles] <= m)))
    }) %>% unlist() %>% unname())
  }
  
  # return percentile cuts otherwise
  return(percentiles)
}

util_arr_idx_to_linear_idx <- function(r, c, n) {
  # Consider
  #       [,1] [,2] [,3] [,4]
  # [1,]    1    2    4    7
  # [2,]    0    3    5    8
  # [3,]    0    0    6    9
  # [4,]    0    0    0   10
  #
  # Obs.: In column x there are x values. Hence column x starts at sum(1..x-1) + 1
  # The sum formula is solved with n(n+1)/2
  column <- 0
  if (c > 1) {
    column <- c * (c - 1) / 2
  }
  return(column + r)
}

util_linear_idx_to_arr_idx <- function(k, n) {
  # Consider
  #       [,1] [,2] [,3] [,4]
  # [1,]    1    2    4    7
  # [2,]    0    3    5    8
  # [3,]    0    0    6    9
  # [4,]    0    0    0   10
  #
  # The diagonal in column x has value sum(1..x)
  if (k == 1) {
    return(c(1, 1))
  }
  column <- 1
  repeat {
    column <- column + 1
    last_index_in_col <- (column * (column + 1) / 2)
    if (last_index_in_col >= k) {
      break
    }
  }
  return(c(k - (column - 1) * column / 2, column))
}

# Variogram, but using a distance matrix to not care about projections
# Not sure why *SO MANY* functions in geo libraries are like yeah sure the earth is flat
# alskdfjal;sdjfkl;sajdf;l this will be fucken slow
#
# @param D distance matrix in geo space
# @param D.data distance matrix in data space (for proper variog: (a-b)^2 where a,b are values, not vectors or anything)
util_calc_variog <-
  function(D,
           D.data,
           num.bins = 20,
           max.dist = max(D) / 2) {
    bins = seq(0, max.dist, length.out = num.bins + 1)
    N <- nrow(D)
    D.upper <- D[upper.tri(D)]
    
    D.data.upper <- D.data[upper.tri(D.data)]
    
    v <- c(1:num.bins) %>% purrr::map(function(i) {
      b.min <- bins[i]
      b.max <- bins[i + 1]
      
      center <- b.min + (b.max - b.min) / 2
      
      idxs <- which(D.upper > b.min & D.upper <= b.max)
      n <- length(idxs)
      v <- sum(D.data.upper[idxs]) / n
      return(c(center, v, n))
    }) %>% do.call(rbind, .)
    
    return(v)
  }

util_make_polygon <-
  function(M, ID = 'foo', proj4string = WEB_MERC) {
    p <-
      sp::SpatialPolygons(list(sp::Polygons(list(
        sp::Polygon(M, hole = F)
      ), ID = ID)), proj4string = proj4string)
    return(p)
  }


util_merge_clusters <- function(labels, a, b, new_label) {
  a_indices <- which(labels == a)
  b_indices <- which(labels == b)
  
  labels[a_indices] <- new_label
  labels[b_indices] <- new_label
  return(labels)
}

# Takes SpatialPolygonsDataFrame (possibly also SpatialPolygons)
util_polygons_touch <- function(n1, n2) {
  coords1 <- round(n1@polygons[[1]]@Polygons[[1]]@coords[-1,], 5)
  coords2 <- round(n2@polygons[[1]]@Polygons[[1]]@coords[-1,], 5)
  # if they have anything in common, their combination is smaller than the sum of individual coords
  #return(nrow(unique(rbind(coords1, coords2))) < (nrow(coords1) + nrow(coords2)))
  
  # TODO check if this works, should require 2 shared vertices at least, seems better for voronois
  return(nrow(unique(rbind(coords1, coords2))) <= (nrow(coords1) + nrow(coords2)) - 2)
}

dist_edge <- function(dataset, i, j) {
  return(Matrix::norm(
    tcrossprod(dataset[i,]) - tcrossprod(dataset[j,]),
    type = 'F'
  ))
}

# A measure of how dissimilar points inside a region are
# Should probably somehow match the edge similarity
dist_region_heterogeneity <- function(dataset, node_indices) {
  hg <- 0
  if (length(node_indices) == 1) {
    return(hg)
  }
  samplecov <- cov(dataset[node_indices,])
  means <- colMeans(dataset[node_indices,])
  for (idx in node_indices) {
    hg <- hg + Matrix::norm(tcrossprod(dataset[idx,] - means) - samplecov, 'F')
  }
  return(hg)
}

to_local_distances <- function(D.global, selection) {
  # -Inf because then points won't be considered in building the kernel matrix
  # (there should be a > 0 requirement) and also don't interfere with max(D)
  D.global[!selection, ] <- -Inf
  D.global[, !selection] <- -Inf
  for (i in which(selection[selection = T])) {
    D.global[i,!selection] <- -Inf
    D.global[!selection, i] <- -Inf
  }
  return(D.global)
}

get_region_guidance <- function(points) {
  num_points <- 0
  diff_ev <- NA
  diff_cov <- NA
  
  # points are supposed to be an n x p matrix
  if (is.null(dim(points))) {
    # n can be 1, in which case it's a vector
    if (is.vector(points) || is.rmult(points)) {
      # and just casting it to a matrix makes it p x 1 (:
      # so we flip it around to have 1 x p again
      points <- t(as.matrix(as.vector(points)))
    }
    else {
      print(points)
      print(class(points))
      print(typeof(points))
      stop('OOPS WHAT IS IT')
    }
  }
  num_points <- nrow(points)
  
  if (num_points > 1) {
    points.C <- cov(points)
    diff_ev <- ev_diff(points.C)
    diff_cov <- Matrix::norm(dataset.C - points.C, type = 'F')
  }
  return(list(
    type = 'region',
    num_points = num_points,
    diff_ev = diff_ev,
    diff_cov = diff_cov
  ))
}

get_kernel_guidance <- function(points, K) {
  num_points <- mean(colSums(K))
  # TODO stuff breaks with whitening = T - ask christoph
  points.C <-
    SpatialBSS::local_covariance_matrix(as.matrix(points), list(K), whitening = F)[[1]]
  diff_ev <- ev_diff(points.C)
  return(list(
    type = 'kernel',
    diff_ev = diff_ev,
    num_points = num_points
  ))
}

build_contiguity_matrix <- function() {
  # Compute spatial contiguity matrix, i.e., which area borders on which
  # for GEMAS takes ~15 minutes with all 8 cores on MacBook Pro (2019) with 1,4 GHz Quad-Core Intel Core i5 and 16G RAM
  print('Building contiguity tree...')
  pairs <- t(combn(1:N, m = 2, simplify = T))
  contiguity_pairs <- parallel::mclapply(1:nrow(pairs), function(r) {
    i <- pairs[r, 1]
    j <- pairs[r, 2]
    
    return(util_polygons_touch(spatial.voronoi[i, ], spatial.voronoi[j, ]))
  }, mc.cores = NUM_CORES_USED)
  return(list(
    pairs=pairs,
    contiguity_pairs=contiguity_pairs
  ))
}

# REDCAP http://dx.doi.org/10.1080/13658810701674970
build_contiguity_tree <- function(contiguity) {
  dataset <- as.matrix(dataset.param)
  contiguity_pairs <- contiguity$contiguity_pairs
  pairs <- contiguity$pairs
  # Sort first-order edges (T in a triangle of contiguity) by dissimilarity in ascending order
  first_order_edges <- pairs[which(contiguity_pairs %in% c(T)),]
  edge_dists <- unlist(lapply(1:nrow(first_order_edges), function(index) {
    return(dist_edge(dataset, first_order_edges[index,1], first_order_edges[index, 2]))
  }))

  first_order_edges.sorted <- first_order_edges[order(edge_dists),]
  
  cluster_labels <- 1:N
  contiguity_tree <- matrix(0, ncol=2, nrow=0)
  
  new_label <- N + 1
  e <- 1
  while(!all(cluster_labels == cluster_labels[1])) {
    i <- first_order_edges.sorted[e,1]
    j <- first_order_edges.sorted[e,2]
    
    if (cluster_labels[i] != cluster_labels[j]) {
      cluster_labels <- util_merge_clusters(cluster_labels, cluster_labels[i], cluster_labels[j], new_label)
      contiguity_tree <- rbind(contiguity_tree, c(i,j))
      new_label <- new_label + 1
    }
    
    e <- e + 1
  }
  return(contiguity_tree)
}

# REDCAP http://dx.doi.org/10.1080/13658810701674970
make_cov_diff_regionalization <- function(contiguity_tree, num_regions = BLOCK_MAX_LEVEL) {
  dataset <- as.matrix(dataset.param)
  
  # Now we have a spatially contiguous tree
  # and need to find the best edges to cut to obtain the actual regions
  splitting_edges <- c()
  splittable_edges <- 1:nrow(contiguity_tree)
  
  repeat {
    print(paste('Finding region', length(splitting_edges) + 2, '...'))
    
    edge_hgs <-
      parallel::mclapply(splittable_edges, function(e) {
        nodes_without_e <- tidygraph::as_tbl_graph(contiguity_tree[-c(splitting_edges, e), ]) %>%
          tidygraph::activate(nodes) %>%
          tidygraph::mutate(group = tidygraph::group_components()) %>%
          data.frame()
        
        n1 <- contiguity_tree[e,1]
        n2 <- contiguity_tree[e,2]
        
        D.1 <- which(nodes_without_e$group == nodes_without_e$group[n1])
        D.2 <- which(nodes_without_e$group == nodes_without_e$group[n2])
        
        hg <- dist_region_heterogeneity(dataset, c(D.1, D.2)) -
          dist_region_heterogeneity(dataset, D.1) -
          dist_region_heterogeneity(dataset, D.2)
        return(hg)
      }, mc.cores = NUM_CORES_USED)
    
    hg.index <- edge_hgs %>% unlist() %>% which.max()
    e <- splittable_edges[hg.index]
    print(paste('Best split on edge', e))
    
    splitting_edges <- c(splitting_edges, e)
    splittable_edges <- (1:nrow(contiguity_tree))[-c(splitting_edges)]
    
    if (length(splitting_edges) + 1 >= num_regions) {
      break;
    }
  }
  return(splitting_edges)
}

plot(util_make_polygon(util_split_edges_to_regionalization(contiguity_tree, splitting_edges)[[1]]))

util_split_edges_to_regionalization <- function(contiguity_tree, splitting_edges) {
  dataset <- as.matrix(dataset.param)
  tree <- contiguity_tree
  num_regions <- length(splitting_edges) + 1
  if (length(splitting_edges) > 0) {
    tree <- contiguity_tree[-c(splitting_edges),]
  }
  g.star <- tidygraph::as_tbl_graph(tree, directed=F) %>%
    tidygraph::activate(nodes) %>%
    tidygraph::mutate(group=tidygraph::group_components()) %>%
    data.frame()
  
  regionalization <- lapply(1:num_regions, function(i) {
    region <- raster::aggregate(spatial.voronoi[which(g.star$group == i), ])
    region.patch <- util_get_coords(region)
    region.patch.flat <- util_get_coords(sp::spTransform(region, WEB_MERC))
    selection <- over(dataset.spatial, region) %in% c(1)
    num_points <- length(selection[selection == T])
    
    return(list(
      id = paste('cov_diff', i, num_regions, sep = '.'),
      index = i,
      depth = num_regions,
      patch = region.patch,
      patch_flat = region.patch.flat,
      selection = selection,
      num_points = num_points,
      region_guidance = get_region_guidance(dataset[selection, ])
    ))
  })
  return(regionalization)
}

make_cov_diff_regionalizations <- function(contiguity_tree, num_regions = BLOCK_MAX_LEVEL) {
  splitting_edges <- make_cov_diff_regionalization(contiguity_tree, num_regions=num_regions)
  
  return(1:num_regions %>% purrr::map(function(nr) {
    edges <- c()
    if(nr > 1) {
      edges <- splitting_edges[1:(nr-1)]
    }
    return(util_split_edges_to_regionalization(contiguity_tree, edges))
  }))
}

reg2 <- util_split_edges_to_regionalization(contiguity_tree, splitting_edges[1:4])
plot(util_make_polygon(reg2[[4]]$patch_flat))

make_equal_area_regionalizations <-
  function(max.level = BLOCK_MAX_LEVEL) {
    regionalizations <- list()
    r <- 1
    for (i in 1:max.level) {
      regions <- list()
      side <- i
      
      cellsize <- dataset.extent / side
      
      for (j in 1:(side * side)) {
        ro <- (j - 1) %/% side
        cl <- (j - 1) %% side
        print(paste("Generating region", j, '/', side * side, 'at level', i))
        pixel.bbox <-  util_expand_to_bbox(
          dataset.bbox@bbox[, 'min'] + c(ro, cl) * cellsize,
          dataset.bbox@bbox[, 'min'] + c(ro + 1, cl + 1) * cellsize
        )
        region <- util_make_polygon(pixel.bbox,
                                    ID = paste(i, j, ro, cl, sep = '.'),
                                    proj4string = WGS84)
        region.patch <- util_get_coords(region)
        region.patch.flat <-
          util_get_coords(sp::spTransform(region, WEB_MERC))
        selection <- over(dataset.spatial, region) %in% c(1)
        num_points <- length(selection[selection == T])
        regions[[j]] <- list(
          id = paste('ee', i, j, sep = '.'),
          index = j,
          depth = i,
          patch = region.patch,
          patch_flat = region.patch.flat,
          selection = selection,
          num_points = num_points,
          region_guidance = get_region_guidance(dataset.param[selection, ])
        )
      }
      regionalizations[[r]] <- regions
      r <- r + 1
    }
    return(regionalizations)
  }

make_kernels <- function(max.dist, max.level = KERNEL_MAX_LEVEL) {
  kernels <- matrix(0, ncol = 4, nrow = 0)
  colnames(kernels) <- c('depth', 'index', 'r1','r2')
  for (i in 0:max.level) {
    num_rings <- 2 ^ i
    ring_size <- (max.dist / num_rings)
    for (j in 1:num_rings) {
      ring <- c(i, j, c(j - 1, j) * ring_size)
      kernels <- rbind(kernels, ring)
      print(paste('Generated kernel', j, '/', num_rings, 'in level', i))
    }
  }
  # returns a list of rows in kernels
  return(as.list(data.frame(t(kernels))))
}

# since region guidance is calculated already during make_regionalization
# this only evaluates a set of kernels in the regionalization
calc_guidance <- function(regionalization, kernels) {
  guidance.rings <- list()
  for (ring in kernels) {
    ring_regionalization_guidance <- matrix(0, ncol=2, nrow=0)
    for (region in regionalization) {
      rdepth <- ring[1]
      rindex <- ring[2]
      r1 <- ring[3]
      r2 <- ring[4]
      print(
        paste(
          'Calculating guidance for kernel',
          r1,
          '-',
          r2,
          'in region',
          region$id,
          '(',
          region$num_points,
          ' points )'
        )
      )
      ring_region_guidance <- list(type = 'kernel',
                                   diff_ev = NA,
                                   num_points = NA)
      if (region$num_points > 1) {
        selection <- region$selection
        D.block <- dataset.spatial.D[selection, selection]
        K <- build_ring_kernel(D.block, r1, r2)
        ring_region_guidance <-
          get_kernel_guidance(dataset.param[selection,], K)
      }
      ring_regionalization_guidance <- rbind(
        ring_regionalization_guidance,
        c(ring_region_guidance$diff_ev, ring_region_guidance$num_points)
      )
    }
    guidance.rings <- append(guidance.rings, list(list(
      type = 'kernel',
      ring = c(r1, r2),
      depth = rdepth,
      index = rindex,
      diff_ev = ring_regionalization_guidance[, 1],
      num_points = ring_regionalization_guidance[, 2]
    )))
  }
  return(guidance.rings)
}

calc_cov_diff_guidance <- function(num.regions=2, max.dist = MAX_DIST) {
  contiguity_tree <- build_contiguity_tree(build_contiguity_matrix())
  regionalizations <- make_cov_diff_regionalizations(contiguity_tree, num.regions)
  kernels <- make_kernels(max.dist)
  guidance <-
    purrr::map(regionalizations, function(regionalization) {
      return(calc_guidance(regionalization, kernels))
    })
  
  return(list(regions = regionalizations,
              kernels = guidance))
}

calc_equal_area_block_guidance <- function(max.dist = MAX_DIST) {
  # TODO tomorrow this is now a vastly simplified version of what was before
  # and therefore probably broken
  # at the very least the API format now changed
  regionalizations <-
    make_equal_area_regionalizations() # list of lists
  kernels <- make_kernels(max.dist)
  guidance <-
    purrr::map(regionalizations, function(regionalization) {
      return(calc_guidance(regionalization, kernels))
    })
  
  return(list(regions = regionalizations,
              kernels = guidance))
}

get_image_pyramid <-
  function(spatial.variable,
           sizes = c(4, 6, 8, 16, 32),
           ntiles = 6) {
    sizes <- sort(sizes)
    xextent <-
      c(spatial.variable@bbox['longitude', 'min'], spatial.variable@bbox['longitude', 'max'])
    yextent <-
      c(spatial.variable@bbox['latitude', 'min'], spatial.variable@bbox['latitude', 'max'])
    xwidth <- xextent[2] - xextent[1]
    ywidth <- yextent[2] - yextent[1]
    celloffset <- c(xextent[1], yextent[1])
    
    pyramid <- list()
    for (j in 1:length(sizes)) {
      side <- sizes[[j]]
      cellsize <- c(xwidth / side, ywidth / side)
      cellcentre <- c(xwidth / 2 * side, ywidth / 2 * side)
      grd <-
        SpatialGrid(GridTopology(celloffset, cellsize, c(side, side)), proj4string = WGS84)
      agg <- aggregate(spatial.variable, grd, FUN = 'median')
      cell_data <-
        util_to_ntiles(spatial.variable@data[, 1],
                       agg@data %>% unlist() %>% unname(),
                       ntiles)
      pyramid[[j]] <-
        t(matrix(
          cell_data,
          byrow = T,
          ncol = side,
          nrow = side
        ))
    }
    return(pyramid)
  }

# TODO maybe philentropy has a faster implementation? Note that this is not euclidean distance!
# returns a giant p*n x n matrix
calc_dist_matrix_variog <- function(D) {
  # parallelization somehow leads to lost data after save
  variog.D <- lapply(as.list(1:ncol(D)), function(k) {
    data <- D[, k]
    return(outer(1:N, 1:N, Vectorize(function(i, j) {
      return((data[i] - data[j]) ^ 2)
    })))
  }) %>% do.call(rbind, .)
  return(variog.D)
}

# dataset preprocessing
# assumption: first two columns are longitude and latitude, the rest is multivariate data
N <- nrow(dataset.original)
dataset.input <- as.matrix(dataset.original[,-c(1, 2)])
dataset.input.ntiles <-
  apply(dataset.input, 2, function(cl) {
    return(util_to_ntiles(cl, cl))
  })
dataset.param <- scale(dataset.input)
if (IS_COMPOSITE) {
  dataset.clr <- compositions::clr(dataset.input)
  dataset.ilr <- compositions::clr2ilr(dataset.clr)
  dataset.param <- as.data.frame(dataset.ilr) # avoid rmult class that jsonlite doesn't know
  colnames(dataset.param) <- 1:(ncol(dataset.input)-1) %>% purrr::map(function(i) {
    return(paste('ILR',i,sep=''))
  }) %>% unlist()
}
dataset.param.ntiles <- apply(dataset.param, 2,function(cl) {
  return(util_to_ntiles(cl,cl))
})
dataset.input.z <- scale(dataset.input)

dataset.C <- cov(dataset.param)
dataset.spatial <-
  sp::SpatialPointsDataFrame(dataset.original[, c('longitude', 'latitude')],
                             as.data.frame(dataset.input),
                             proj4string = WGS84)
spatial.voronoi <- SDraw::voronoi.polygons(dataset.spatial, range.expand = 0.05)
dataset.spatial.D <- sp::spDists(dataset.spatial, longlat = T)
dataset.spatial.D.density <-
  density(dataset.spatial.D[lower.tri(dataset.spatial.D)])
MAX_DIST <- max(dataset.spatial.D) / 2

spatial_summaries <- list()
spatial_summaries[['input']] <- list()

dataset.extent <-
  (dataset.spatial@bbox[, 'max'] - dataset.spatial@bbox[, 'min'])
dataset.center <- dataset.extent / 2 + dataset.spatial@bbox[, 'min']
dataset.extent <- dataset.extent * MARGIN_FACTOR
dataset.bbox <- matrix(
  c(
    dataset.center - dataset.extent / 2,
    dataset.center + c(1,-1) * dataset.extent / 2,
    dataset.center + dataset.extent / 2,
    dataset.center + c(-1, 1) * dataset.extent / 2
  ),
  ncol = 2,
  byrow = T
)
colnames(dataset.bbox) <- c('longitude', 'latitude')
dataset.bbox <-
  sp::SpatialPolygons(list(sp::Polygons(list(
    sp::Polygon(dataset.bbox, hole = F)
  ), ID = 'bbox')), proj4string = WGS84)

dataset.flat <- sp::spTransform(dataset.spatial, WEB_MERC)
dataset.flat.extent <-
  (dataset.flat@bbox[, 'max'] - dataset.flat@bbox[, 'min'])
dataset.flat.center <-
  dataset.flat.extent / 2 + dataset.flat@bbox[, 'min']
sidelength <- dataset.flat.extent * MARGIN_FACTOR
dataset.flat.bbox <- matrix(
  c(
    dataset.flat.center + c(-1,-1) * sidelength / 2,
    dataset.flat.center + c(1,-1) * sidelength / 2,
    dataset.flat.center + c(1, 1) * sidelength / 2,
    dataset.flat.center + c(-1, 1) * sidelength / 2
  ),
  ncol = 2,
  byrow = T
)
dataset.flat.bbox <-
  sp::SpatialPolygons(list(sp::Polygons(list(
    sp::Polygon(dataset.flat.bbox, hole = F)
  ), ID = 'bbox')), proj4string = WEB_MERC)
dataset.flat.extent <-
  (dataset.flat.bbox@bbox[, 'max'] - dataset.flat.bbox@bbox[, 'min'])

plot(dataset.bbox,add=T)
plot(dataset.spatial)


plot(util_make_polygon(util_expand_to_bbox(dataset.bbox@bbox[,1],dataset.bbox@bbox[,2]), proj4string = WGS84),add=T)

## GUIDANCE AND GENERAL PREPROCESSING CACHE

guidancefile.path <- paste('./', guidancefile.name, sep = '')
if (file.exists(guidancefile.path)) {
  load(file = guidancefile.path)
  print(paste("Loaded guidance from", guidancefile.path))
} else {
  print(paste(
    "Guidance file not found at",
    guidancefile.path,
    '- now computing guidance...'
  ))
  
  tic("Guidance (COV)")
  guidance.cov <- calc_cov_diff_guidance(num.regions=BLOCK_MAX_LEVEL, max.dist=MAX_DIST)
  toc()
  
  tic("Guidance (EE)")
  guidance.blocks <- calc_equal_area_block_guidance(max.dist=MAX_DIST)
  toc()
  
  tic("Distance matrices for variograms")
  D.data.param <- calc_dist_matrix_variog(dataset.param)
  toc()
  
  
  tic("Spatial summaries")
  for (col in colnames(dataset.spatial@data)) {
    spatial_summaries[['input']][[col]] <-
      get_image_pyramid(dataset.spatial[, col])
  }
  toc()
  
  save(guidance.blocks,
       guidance.cov,
       D.data.param,
       spatial_summaries,
       file = guidancefile.path)
  print(paste("Saved guidance to", guidancefile.path))
}

#### UTILS

# Adapted PAM from doi:10.1016/j.eswa.2008.01.039
cop_pam <-
  function(data,
           cantLink,
           k,
           diss = F,
           compute_stats = F) {
    fast_dist <- function(x, y) {
      return(1 - abs(cor(x, y)))
    }
    
    compute_cluster_representative_and_diameter_and_cardinality <-
      function(pred) {
        R <- matrix(0, nrow = k, ncol = 3)
        for (i in 1:k) {
          elements <- which(pred %in% c(i))
          n <- length(elements)
          if (n == 0) {
            next
            
          }
          if (n == 1) {
            R[i,] <- c(elements[1], 0, n)
            next
            
          }
          dists <-
            outer(elements, elements, Vectorize(function(x, y) {
              return(fast_dist(data[x, ], data[y, ]))
            }))
          R[i,] <-
            c(elements[which.min(colSums(dists))], max(dists), n)
        }
        return(R)
      }
    
    compute_cluster_representative_dist <-
      function(pred, clusinfo) {
        return(unlist(map(1:length(pred), function(i) {
          element <- data[i, ]
          cluster <- pred[i]
          j <- clusinfo[cluster, 1]
          representative <- data[j, ]
          return(fast_dist(element, representative))
        })))
      }
    
    compute_cluster_separation <- function(pred) {
      MD <- matrix(NA, nrow = k, ncol = k)
      cluster_comparison_pairs <- t(combn(1:k, 2))
      for (pair_idx in 1:nrow(cluster_comparison_pairs)) {
        c1 <- cluster_comparison_pairs[pair_idx, 1]
        c2 <- cluster_comparison_pairs[pair_idx, 2]
        
        elements_c1 <- which(pred %in% c(c1))
        elements_c2 <- which(pred %in% c(c2))
        if (length(elements_c1) > 0 && length(elements_c2) > 0) {
          dists <- outer(elements_c1, elements_c2, Vectorize(function(x, y) {
            return(fast_dist(data[x, ], data[y, ]))
          }))
          MD[c1, c2] <- min(dists)
          MD[c2, c1] <- min(dists)
        } else {
          MD[c1, c2] <- NA
          MD[c1, c2] <- NA
        }
      }
      return(apply(MD, 2, function(x) {
        if (all(is.na(x))) {
          return(NA) # otherwise min returns Inf and that screws mean()
        }
        return(min(x, na.rm = T))
      }))
    }
    
    collect_and_return <- function(cluster_labels) {
      if (compute_stats) {
        representatives_and_more <-
          compute_cluster_representative_and_diameter_and_cardinality(cluster_labels)
        representatives_and_more <-
          cbind(representatives_and_more,
                compute_cluster_separation(cluster_labels))
        distances_to_representative <-
          compute_cluster_representative_dist(cluster_labels, representatives_and_more)
        clusinfo <- representatives_and_more
        return(
          list(
            labels = cluster_labels,
            distances_to_representative = distances_to_representative,
            clusinfo = clusinfo
          )
        )
      } else {
        return(cluster_labels)
      }
    }
    
    is_compatible_with_all <- function(clw, i, candidates) {
      if (all(is.na(clw[[i]]))) {
        return(T)
      }
      return(length(intersect(candidates, clw[[i]])) == 0)
    }
    
    can_put_element_in_cluster <- function(label, clw, i, j) {
      if (all(is.na(clw[[i]]))) {
        return(T)
      }
      for (u in clw[[i]]) {
        if (label[u] == j) {
          return(F)
        }
      }
      return(T)
    }
    
    if (!diss && k > nrow(data)) {
      return(0)
    }
    
    # building cannot link lists
    # this is more efficient than reducing from a nxn binary constraint matrix
    nc <- nrow(cantLink)
    n <- nrow(data)
    cannot_link_list <- list()
    for (i in 1:n) {
      cannot_link_list[[i]] <- NA
    }
    
    for (i in 1:nc) {
      if (i > nc)
        break
      
      u <- cantLink[i, 1]
      v <- cantLink[i, 2]
      if (any(is.na(cannot_link_list[[u]]))) {
        cannot_link_list[[u]] <- c(v)
      } else {
        cannot_link_list[[u]] <- c(cannot_link_list[[u]], v)
      }
      if (any(is.na(cannot_link_list[[v]]))) {
        cannot_link_list[[v]] <- c(u)
      } else {
        cannot_link_list[[v]] <- c(cannot_link_list[[v]], u)
      }
    }
    
    # build distance matrix
    D <- as.matrix(data)
    if (!diss) {
      data <- as.matrix(data)
      d <- ncol(data)
      
      D <- matrix(0, ncol = n, nrow = n)
      triangle <- combn(1:n, 2)
      for (v in 1:ncol(triangle)) {
        i <- triangle[1, v]
        j <- triangle[2, v]
        d <- 0
        if (i != j) {
          d <- fast_dist(data[i, ], data[j, ])
        }
        D[i, j] <- d
        D[j, i] <- d
      }
    }
    
    does_clustering_violate_constraints <-
      function(assignments, cll) {
        violations <- rep(T, length(assignments))
        for (i in 1:length(assignments)) {
          assigned_medoid <- assignments[i]
          violations[i] <-
            !can_put_element_in_cluster(assignments, cll, i, assigned_medoid)
        }
        return(violations)
      }
    
    find_new_medoid <- function(assignments, medoid_idx) {
      n <- length(assignments)
      elements_in_cluster <- (1:n)[assignments %in% c(medoid_idx)]
      new_medoid_idx <-
        which.min(unlist(lapply(elements_in_cluster, function(e) {
          return(sum(D[e, elements_in_cluster]))
        })))
      return(elements_in_cluster[new_medoid_idx])
    }
    
    assign_to_nearest_medoid <-
      function(object_idxs, medoid_idxs, cll) {
        n <- length(object_idxs)
        assignments <- rep(0, n)
        medoids <- (1:n)[medoid_idxs]
        for (i in 1:n) {
          o <- object_idxs[i]
          available_medoids <- c()
          for (m in medoid_idxs) {
            if (can_put_element_in_cluster(assignments, cll, i, m)) {
              available_medoids <- c(available_medoids, m)
            }
          }
          if (length(available_medoids) == 0) {
            stop('no available medoid')
          }
          
          nearest_idx <- which.min(D[o, available_medoids])
          assignments[i] <- available_medoids[nearest_idx]
        }
        return(assignments)
      }
    
    calc_cost <- function(assignments, M) {
      object_idxs <- 1:length(assignments)
      C <- cbind(object_idxs, assignments)
      return(sum(apply(C, 1, function(r) {
        o <- r[1]
        m <- M[r[2]]
        return(D[o, m])
      })))
    }
    
    # initial medoids are from unconstrained PAM - in our case distances suggest the correct partitioning anyhow
    initial <- cluster::pam(D, k, diss = T, pamonce = 5)
    A <- as.integer(initial$clustering)
    M <- unlist(lapply(initial$medoids, function(a) {
      return(match(a, initial$medoids))
    }))
    
    # while the constraints are violated we reassign to next best medoid
    constraint_violations <-
      does_clustering_violate_constraints(A, cannot_link_list)
    C <- calc_cost(A, M)
    C.star <- 0
    while (any(constraint_violations) || abs(C.star - C) > 1e-4) {
      C <- C.star
      M.star <- M
      for (j in 1:k) {
        M.star[j] <- find_new_medoid(A, j)
      }
      
      A.star <-
        assign_to_nearest_medoid(1:n, M.star, cannot_link_list)
      A.star <- unlist(lapply(A.star, function(a) {
        return(match(a, M.star))
      }))
      
      A <- A.star
      M <- M.star
      C.star <- calc_cost(A.star, M.star)
      constraint_violations <-
        does_clustering_violate_constraints(A, cannot_link_list)
    }
    
    return(collect_and_return(A))
  }


# https://theclevermachine.wordpress.com/2013/03/30/the-statistical-whitening-transform/
white_data <- function(x) {
  n <- nrow(x)
  # means of random vectors
  mu <- colMeans(x)
  
  # centered data: remove mean
  x_0 <- sweep(x,
               MARGIN = 2,
               STATS = mu,
               FUN = '-')
  # compute sample covariance matrix
  S <- (t(x_0) %*% x_0) / (n - 1)
  # compute eigenvalues
  S.evd <- eigen(S, symmetric = TRUE)
  
  # actual whitening: rotate around cov. eigenvectors like PCA, scale to unit variance
  # rotation matrix
  E <- S.evd$vectors
  R <- t(E)
  # scaling matrix
  D <- diag(S.evd$values)
  D.sqrt <- diag(sqrt(S.evd$values))
  D.inv.sqrt <- diag(1 / sqrt(S.evd$values))
  
  # whitening matrices
  s_inv_sqrt <- D.inv.sqrt %*% R
  s_sqrt <- D.sqrt %*% R
  
  x_w <- x_0 %*% t(s_inv_sqrt)
  colnames(x_w) <- colnames(x_0)
  
  return(list(
    mu = mu,
    x_0 = x_0,
    x_w = x_w,
    s_inv_sqrt = s_inv_sqrt,
    s_sqrt = s_sqrt
  ))
}

#### API FUNCTIONS

#* @filter cors
cors <- function(req, res) {
  res$setHeader("Access-Control-Allow-Methods", "*")
  res$setHeader("Access-Control-Allow-Headers", "*")
  res$setHeader("Access-Control-Allow-Origin", "*")
  if (req$REQUEST_METHOD == 'OPTIONS') {
    res$status <- 200
    return()
  } else {
    plumber::forward()
  }
}

#* @get /data/metadata/colnames
#* @param group:string
function(group = 'input') {
  if (group == 'input') {
    return(colnames(dataset.input))
  }
  if (group == 'param') {
    return(colnames(dataset.param))
  }
  # TODO look for a sbss result with id == group
  stop('no')
}

#* @get /data/metadata/descriptive-stats
#* @param group:string
function(group = 'input') {
  ds <- dataset.input
  
  if (group == 'param') {
    ds <- dataset.param
  }
  
  ntiles <- apply(ds, 2, function(column) {
    return(util_to_ntiles(column))
  })
  
  return(list(ntileBorders = t(ntiles)))
}

#* @get /data/metadata/correlation-matrix
#* @param group:string
function(group = 'input') {
  ds <- dataset.input
  if (group == 'param') {
    ds <- dataset.param
  }
  p <- ncol(ds)
  C <- outer(1:p, 1:p, Vectorize(function(x, y) {
    return(cor(ds[, x], ds[, y]))
  }))
  return(C)
}

#* @get /data/original
#* @param group:string
function(group = 'input') {
  ds <- dataset.input
  if (group == 'param') {
    ds <- dataset.param
  }
  
  return(t(as.matrix(ds)))
}

#* @get /data/ntiles
#* @param group:string
function(group = 'input') {
  if (group == 'input') {
    return(t(dataset.input.ntiles))
  }
  if (group == 'param') {
    return(t(dataset.param.ntiles))
  }
}

#* @get /data/scaled
function() {
  return(t(as.matrix(dataset.input.z)))
}

#* @get /data/locations
#* @serializer json list(digits = 8)
#* @param crs
function(crs = 'wgs84') {
  if (crs == 'wgs84') {
    return(as.matrix(dataset.original[, 1:2]))
  }
  return(as.matrix(dataset.flat@coords))
}

#* @get /data/locations/bbox
#* @serializer json list(digits = 8)
#* @param crs
function(crs = 'wgs84') {
  if (crs == 'wgs84') {
    return(as.matrix(t(dataset.bbox@bbox)[, c('y', 'x')]))
  }
  return(as.matrix(t(dataset.flat.bbox@bbox)[, c('y', 'x')]))
}


#* @get /data/metadata/density
#* @serializer json list(digits = 10)
#* @param group
#* @param col
#* @param crs
function(group, col, crs = 'wgs84') {
  if (group == 'dataset' && col == 'distances') {
    if (crs == 'wgs84') {
      return(util_density_to_df(dataset.spatial.D.density))
    }
    stop(paste('no distances for crs', crs))
  }
  if (group == 'input') {
    return(util_density_to_df(density(dataset.input[, col])))
  }
  if (group == 'param') {
    ds <- dataset.param
    return(util_density_to_df(density(ds[, col])))
  }
  stop(paste('no density for', group, col))
}

#* @get /spatial-summary
#* @serializer json list(na="null")
#* @param group:string
function(group = 'input') {
  return(spatial_summaries[[group]])
}

#* @post /locations/viewport
#* @param neLat:number
#* @param neLon:number
#* @param swLat:number
#* @param swLon:number
function(neLat, neLon, swLat, swLon) {
  bbox <- util_make_polygon(util_expand_to_bbox(c(neLon, neLat),
                                                c(swLon, swLat)),
                            'bbox',
                            WGS84)
  selection <- over(dataset.spatial, bbox) %in% c(1)
  # -1 because R is 1-indexed and JS is 0-indexed
  return(which(selection %in% c(T)) - 1)
}

#* @post /locations/viewport-for-variable
#* @param neLat:number
#* @param neLon:number
#* @param swLat:number
#* @param swLon:number
#* @param group
#* @param variable
#* @param density:number
function(neLat,
         neLon,
         swLat,
         swLon,
         group,
         variable,
         density = 1) {
  bbox <- util_make_polygon(util_expand_to_bbox(c(neLon, neLat),
                                                c(swLon, swLat)),
                            'bbox',
                            WGS84)
  bbox_filter <- over(dataset.spatial, bbox) %in% c(1)
  ds <- dataset.input.ntiles
  if (group == 'param') {
    ds <- dataset.param.ntiles
  }
  data <- ds[, variable]
  
  get_score <- function(pct) {
    if (pct <= 1 || pct >= 6) {
      return(3)
    }
    if (pct == 2 || pct == 5) {
      return(2)
    }
    if (pct == 3 || pct == 4) {
      return(1)
    }
    return(0)
  }
  
  scores <- unlist(1:N %>% purrr::map(function(i) {
    if (bbox_filter[i] == F) {
      return(0)
    }
    return(get_score(data[i]))
  }))
  
  dist_from_mean <-
    abs(dataset.input[, variable] - mean(dataset.input[, variable]))
  
  by_score <-
    statnet.common::order(cbind(scores, dist_from_mean), decreasing = T)
  
  points_to_render <- c(1:(floor(N * density)))
  
  # -1 because 0-index arrays in js
  return(by_score[points_to_render] - 1)
}

#* @get /guidance
#* @serializer json list(na="null", digits=8)
#* @param partitionType
function(partitionType = 'equal-area') {
  if (partitionType == 'equal-area') {
    return(guidance.blocks)
  }
  if (partitionType == 'cov-diff') {
    return(guidance.cov)
  }
  stop('not implemented')
}

make_kernels_from_usr <- function(usr_kernels) {
  if (length(usr_kernels) == 0){
    return(list())
  }
  # TODO should check somewhere that they don't overlap. not here tho
  kernels <- cbind(0,1:nrow(usr_kernels),usr_kernels) # fake depth and index
  return(as.list(data.frame(t(kernels))))
}

make_regions_from_usr <- function(usr_regions) {
  if (length(usr_regions) == 0) {
    # default to regionalization with one region
    return(guidance.blocks$regions[[1]][[1]])
  }
  return(purrr::imap(usr_regions, function(uregion, i) {
    uregion <- uregion[,c('lng','lat')] # lat/lon switcheroo
    region <- util_make_polygon(uregion, ID='foo', proj4string = WGS84)
    region.patch <- util_get_coords(region)
    region.patch.flat <-
      util_get_coords(sp::spTransform(region, WEB_MERC))
    selection <- over(dataset.spatial, region) %in% c(1)
    num_points <- length(selection[selection == T])
    return(list(
      id = paste('usr', i, sep = '.'),
      index = i,
      depth = 0,
      patch = region.patch,
      patch_flat = region.patch.flat,
      selection = selection,
      num_points = num_points,
      region_guidance = get_region_guidance(dataset.param[selection, ])
    ))
  }))
}

#* @post /user-guidance
#* @serializer json list(na="null", digits=8)
function(req) {
  usr_regionalization <-
    make_regions_from_usr(req$argsBody$regions)
  usr_kernels <- make_kernels_from_usr(req$argsBody$kernels)
  if (length(usr_kernels) == 0){
    return(list(
      regions = list(usr_regionalization)
    ))
  }
  
  kernel_guidance <- calc_guidance(usr_regionalization, usr_kernels)
  return(list(
    regions = list(usr_regionalization),
    kernels = list(kernel_guidance)
  ))
}

#* @get /data/features
function() {
  available_features <- Sys.glob('./features/*.geojson') %>% purrr::map(function(rel_path) {
    ex <- strsplit(basename(rel_path), split="\\.")[[1]]
    return(ex[-2])
  })
  return(available_features)
}

#* @get /data/features/<feature>
#* @serializer json list(na="null", digits=8)
#* @param feature:string
function(feature) {
  # parsing json -> R and then serializing is kinda shitty as it's ambiguous
  # how R data types map to JSON data types. therefore we read it as string
  # and blurp it out
  file <- paste('./features/', feature, '.geojson', sep='')
  featureData <- readChar(file, file.info(file)$size)
  return(featureData)
}

#* @get /data/metadata/variograms
#* @param group
#* @param bins:number
function(group = 'param', bins = 20) {
  if (group != 'param') {
    return(c())
  }
  bins <- as.integer(bins)
  p <- ncol(dataset.param)
  N <- ncol(D.data.param)
  vgs <- 1:p %>% purrr::map(function(i) {
    start_row <- (i-1)*N + 1
    end_row <- start_row + N - 1
    D <- D.data.param[start_row:end_row, ]
    vg <- util_calc_variog(dataset.spatial.D, D, bins, MAX_DIST)
    vg <- data.frame(vg)
    colnames(vg) <- c('center', 'v', 'n')
    return(vg)
  })
  
  vgs.ui <- cbind(vgs[[1]]$center, vgs %>% purrr::map(function(vg) {return(vg$v)}) %>% do.call(cbind, .))
  colnames(vgs.ui) <- c('center', colnames(dataset.param))
  vgs.ui <- data.frame(vgs.ui)
  vgs.ui <- reshape2::melt(vgs.ui, id.vars=c('center'))
  
  return(vgs.ui)
}


plot(util_make_polygon(guidance.cov$regions[[3]][[2]]$patch_flat))

guidance.cov$regions[[2]] %>% purrr::map(function(r) {
  
})


setwd('/Users/npiccolotto/Projects/cvast/bssvis/sbss-app/server/src')
library('SpatialBSS.snss')
set.seed(1)
random_earth_points <- matrix(cbind(
  runif(100, min=-16, max=35),
  runif(100, min=27, max=71)
), ncol=2)

plot(random_earth_points)
random_earth_points.spatial <- sp::SpatialPoints(coords=random_earth_points,proj4string = WGS84)
plot(random_earth_points)

random_earth_points.D <- as.matrix(dist(random_earth_points))
random_earth_points.spatial.D <- as.matrix(sp::spDists(random_earth_points.spatial))

plot_scatterspace(random_earth_points.D, random_earth_points.spatial.D, scale=T, classic = T)
plot_scatterspace(random_earth_points.D,random_earth_points.D,spaces=1)
plot_scatterspace(random_earth_points.spatial.D,random_earth_points.spatial.D,spaces=1)

jsonlite::toJSON(D.w, digits = 8)

max(D.w)



D.w
