#' Sina plot
#'
#' The sina plot is a data visualization chart suitable for plotting any single
#' variable in a multiclass dataset. It is an enhanced jitter strip chart,
#' where the width of the jitter is controlled by the density distribution of
#' the data within each class.
#'
#' @details There are two available ways to define the x-axis borders for the
#' samples to spread within:
#' \itemize{
#'  \item{`method == "density"`
#'
#'    A density kernel is estimated along the y-axis for every sample group, and
#'    the samples are spread within that curve. In effect this means that points
#'    will be positioned randomly within a violin plot with the same parameters.
#'  }
#'  \item{`method == "counts"`:
#'
#'    The borders are defined by the number of samples that occupy the same bin.
#'
#'   }
#' }
#'
#' @section Aesthetics:
#' geom_sina understand the following aesthetics (required aesthetics are in
#' bold):
#'
#' - **x**
#' - **y**
#' - color
#' - group
#' - size
#' - alpha
#'
#' @inheritParams ggplot2::geom_path
#' @inheritParams ggplot2::stat_identity
#' @inheritParams ggplot2::stat_density
#'
#' @param scale How should each sina be scaled. Corresponds to the `scale`
#' parameter in [ggplot2::geom_violin()]? Available are:
#'
#' - `'area'` for scaling by the largest density/bin among the different sinas
#' - `'count'` as above, but in addition scales by the maximum number of points
#'   in the different sinas.
#' - `'width'` Only scale according to the `maxwidth` parameter
#'
#' For backwards compatibility it can also be a logical with `TRUE` meaning
#' `area` and `FALSE` meaning `width`
#'
#' @param method Choose the method to spread the samples within the same
#' bin along the x-axis. Available methods: "density", "counts" (can be
#' abbreviated, e.g. "d"). See `Details`.
#'
#' @param maxwidth Control the maximum width the points can spread into. Values
#' between 0 and 1.
#'
#' @param bin_limit If the samples within the same y-axis bin are more
#' than `bin_limit`, the samples's X coordinates will be adjusted.
#'
#' @param binwidth The width of the bins. The default is to use `bins`
#'   bins that cover the range of the data. You should always override
#'   this value, exploring multiple widths to find the best to illustrate the
#'   stories in your data.
#'
#' @param bins Number of bins. Overridden by binwidth. Defaults to 50.
#'
#' @param seed A seed to set for the jitter to ensure a reproducible plot
#'
#' @author Nikos Sidiropoulos, Claus Wilke, and Thomas Lin Pedersen
#'
#' @name geom_sina
#' @rdname geom_sina
#'
#' @section Computed variables:
#'
#' \describe{
#'   \item{density}{The density or sample counts per bin for each point}
#'   \item{scaled}{`density` scaled by the maximum density in each group}
#'   \item{n}{The number of points in the group the point belong to}
#' }
#'
#'
#' @examples
#' ggplot(midwest, aes(state, area)) + geom_point()
#'
#' # Boxplot and Violin plots convey information on the distribution but not the
#' # number of samples, while Jitter does the opposite.
#' ggplot(midwest, aes(state, area)) +
#'   geom_violin()
#'
#' ggplot(midwest, aes(state, area)) +
#'   geom_jitter()
#'
#' # Sina does both!
#' ggplot(midwest, aes(state, area)) +
#'   geom_violin() +
#'   geom_sina()
#'
#' p <- ggplot(midwest, aes(state, popdensity)) +
#'   scale_y_log10()
#'
#' p + geom_sina()
#'
#' # Colour the points based on the data set's columns
#' p + geom_sina(aes(colour = inmetro))
#'
#' # Or any other way
#' cols <- midwest$popdensity > 10000
#' p + geom_sina(colour = cols + 1L)
#'
#' # Sina plots with continuous x:
#' ggplot(midwest, aes(cut_width(area, 0.02), popdensity)) +
#'   geom_sina() +
#'   scale_y_log10()
#'
#'
#' ### Sample gaussian distributions
#' # Unimodal
#' a <- rnorm(500, 6, 1)
#' b <- rnorm(400, 5, 1.5)
#'
#' # Bimodal
#' c <- c(rnorm(200, 3, .7), rnorm(50, 7, 0.4))
#'
#' # Trimodal
#' d <- c(rnorm(200, 2, 0.7), rnorm(300, 5.5, 0.4), rnorm(100, 8, 0.4))
#'
#' df <- data.frame(
#'   'Distribution' = c(
#'     rep('Unimodal 1', length(a)),
#'     rep('Unimodal 2', length(b)),
#'     rep('Bimodal', length(c)),
#'     rep('Trimodal', length(d))
#'   ),
#'   'Value' = c(a, b, c, d)
#' )
#'
#' # Reorder levels
#' df$Distribution <- factor(
#'   df$Distribution,
#'   levels(df$Distribution)[c(3, 4, 1, 2)]
#' )
#'
#' p <- ggplot(df, aes(Distribution, Value))
#' p + geom_boxplot()
#' p + geom_violin() +
#'   geom_sina()
#'
#' # By default, Sina plot scales the width of the class according to the width
#' # of the class with the highest density. Turn group-wise scaling off with:
#' p +
#'   geom_violin() +
#'   geom_sina(scale = FALSE)
NULL

#' @rdname ggforce-extensions
#' @format NULL
#' @usage NULL
#' @export
StatSina <- ggproto('StatSina', Stat,
  required_aes = c('x', 'y'),

  setup_data = function(data, params) {
    if (is.double(data$x) && !.has_groups(data) && any(data$x != data$x[1L])) {
      stop('Continuous x aesthetic -- did you forget aes(group=...)?',
        call. = FALSE
      )
    }

    data
  },

  setup_params = function(data, params) {
    params$maxwidth <- params$maxwidth %||% (resolution(data$x %||% 0) * 0.9)

    if (is.null(params$binwidth) && is.null(params$bins)) {
      params$bins <- 50
    }

    params
  },

  compute_panel = function(self, data, scales, scale = TRUE, method = 'density',
                           bw = 'nrd0', kernel = 'gaussian', binwidth = NULL,
                           bins = NULL, maxwidth = 1, adjust = 1, bin_limit = 1,
                           seed = NA) {

    if (!is.null(binwidth)) {
      bins <- bin_breaks_width(scales$y$dimension() + 1e-8, binwidth)
    } else {
      bins <- bin_breaks_bins(scales$y$dimension() + 1e-8, bins)
    }

    data <- ggproto_parent(Stat, self)$compute_panel(data, scales,
      scale = scale, method = method, bw = bw, kernel = kernel,
      bins = bins$breaks, maxwidth = maxwidth, adjust = adjust,
      bin_limit = bin_limit)

    if (is.logical(scale)) {
      scale <- if (scale) 'area' else 'width'
    }
    # choose how sinas are scaled relative to each other
    data$sinawidth <- switch(
      scale,
      # area : keep the original densities but scale them to a max width of 1
      #        for plotting purposes only
      area = data$density / max(data$density),
      # count: use the original densities scaled to a maximum of 1 (as above)
      #        and then scale them according to the number of observations
      count = data$density / max(data$density) * data$n / max(data$n),
      # width: constant width (each density scaled to a maximum of 1)
      width = data$scaled
    )

    if (!is.na(seed)) {
      new_seed <- sample(.Machine$integer.max, 1L)
      set.seed(seed)
      on.exit(set.seed(new_seed))
    }
    data$xmin <- data$x - maxwidth / 2
    data$xmax <- data$x + maxwidth / 2
    data$x_diff <- runif(nrow(data), min = -1, max = 1) *
      maxwidth * data$sinawidth/2
    data$width <- maxwidth

    # jitter y values if the input is input is integer
    if (all(data$y == floor(data$y))) {
      #data$y <- jitter(data$y)
    }

    data
  },

  compute_group = function(data, scales, scale = TRUE, method = 'density',
                           bw = 'nrd0', kernel = 'gaussian',
                           maxwidth = 1, adjust = 1, bin_limit = 1,
                           bins = NULL) {
    if (nrow(data) == 0) return(NULL)

    if (nrow(data) < 3) {
      data$density <- 0
      data$scaled <- 1
    } else if (method == 'density') { # density kernel estimation
      range <- range(data$y, na.rm = TRUE)
      bw <- calc_bw(data$y, bw)
      dens <- compute_density(data$y, data$w, from = range[1], to = range[2],
                              bw = bw, adjust = adjust, kernel = kernel)
      densf <- stats::approxfun(dens$x, dens$density, rule = 2)

      data$density <- densf(data$y)
      data$scaled <- data$density / max(dens$density)

      data
    } else { # bin based estimation
      bin_index <- cut(data$y, bins, include.lowest = TRUE, labels = FALSE)
      data$density <- tapply(bin_index, bin_index, length)[as.character(bin_index)]
      data$density[data$density <= bin_limit] <- 0
      data$scaled <- data$density / max(data$density)
    }

    # Compute width if x has multiple values
    if (length(unique(data$x)) > 1) {
      width <- diff(range(data$x)) * maxwidth
    } else {
      width <- maxwidth
    }
    data$width <- width
    data$n <- nrow(data)
    data$x <- mean(range(data$x))
    data
  },
  finish_layer = function(data, params) {
    # rescale x in case positions have been adjusted
    x_mod <- (data$xmax - data$xmin) / data$width
    data$x <- data$x + data$x_diff * x_mod
    data
  },
  extra_params = 'na.rm'
)

#' @rdname geom_sina
#' @export
stat_sina <- function(mapping = NULL, data = NULL, geom = 'sina',
                      position = 'dodge', scale = 'area', method = 'density',
                      bw = 'nrd0', kernel = 'gaussian', maxwidth = NULL,
                      adjust = 1, bin_limit = 1, binwidth = NULL, bins = NULL,
                      seed = NA, ..., na.rm = FALSE, show.legend = NA,
                      inherit.aes = TRUE) {
  method <- match.arg(method, c('density', 'counts'))

  layer(
    data = data,
    mapping = mapping,
    stat = StatSina,
    geom = geom,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list(scale = scale, method = method, bw = bw, kernel = kernel,
      maxwidth = maxwidth, adjust = adjust, bin_limit = bin_limit,
      binwidth = binwidth, bins = bins, seed = seed, na.rm = na.rm, ...)
  )
}

#' @rdname geom_sina
#' @export
geom_sina <- function(mapping = NULL, data = NULL,
                      stat = 'sina', position = 'dodge',
                      ...,
                      na.rm = FALSE,
                      show.legend = NA,
                      inherit.aes = TRUE) {
  layer(
    data = data,
    mapping = mapping,
    stat = stat,
    geom = GeomPoint,
    position = position,
    show.legend = show.legend,
    inherit.aes = inherit.aes,
    params = list(
      na.rm = na.rm,
      ...
    )
  )
}



# Binning functions -------------------------------------------------------

bins <- function(breaks, closed = c('right', 'left'),
                 fuzz = 1e-08 * stats::median(diff(breaks))) {
  stopifnot(is.numeric(breaks))
  closed <- match.arg(closed)

  breaks <- sort(breaks)
  # Adapted base::hist - this protects from floating point rounding errors
  if (closed == 'right') {
    fuzzes <- c(-fuzz, rep.int(fuzz, length(breaks) - 1))
  } else {
    fuzzes <- c(rep.int(-fuzz, length(breaks) - 1), fuzz)
  }

  structure(
    list(
      breaks = breaks,
      fuzzy = breaks + fuzzes,
      right_closed = closed == 'right'
    ),
    class = 'ggplot2_bins'
  )
}

# Compute parameters -----------------------------------------------------------

# from ggplot2
compute_density <- function(x, w, from, to, bw = "nrd0", adjust = 1,
                            kernel = "gaussian", n = 512) {
  nx <- length(x)
  if (is.null(w)) {
    w <- rep(1 / nx, nx)
  }

  # if less than 2 points return data frame of NAs and a warning
  if (nx < 2) {
    warning("Groups with fewer than two data points have been dropped.", call. = FALSE)
    return(new_data_frame(list(
      x = NA_real_,
      density = NA_real_,
      scaled = NA_real_,
      ndensity = NA_real_,
      count = NA_real_,
      n = NA_integer_
    ), n = 1))
  }

  dens <- stats::density(x, weights = w, bw = bw, adjust = adjust,
                         kernel = kernel, n = n, from = from, to = to)

  new_data_frame(list(
    x = dens$x,
    density = dens$y,
    scaled =  dens$y / max(dens$y, na.rm = TRUE),
    ndensity = dens$y / max(dens$y, na.rm = TRUE),
    count =   dens$y * nx,
    n = nx
  ), n = length(dens$x))
}
calc_bw <- function(x, bw) {
  if (is.character(bw)) {
    if (length(x) < 2)
      stop("need at least 2 points to select a bandwidth automatically", call. = FALSE)
    bw <- switch(
      base::tolower(bw),
      nrd0 = stats::bw.nrd0(x),
      nrd = stats::bw.nrd(x),
      ucv = stats::bw.ucv(x),
      bcv = stats::bw.bcv(x),
      sj = ,
      `sj-ste` = stats::bw.SJ(x, method = "ste"),
      `sj-dpi` = stats::bw.SJ(x, method = "dpi"),
      stop("unknown bandwidth rule")
    )
  }
  bw
}

bin_breaks <- function(breaks, closed = c('right', 'left')) {
  bins(breaks, closed)
}

bin_breaks_width <- function(x_range, width = NULL, center = NULL,
                             boundary = NULL, closed = c('right', 'left')) {
  stopifnot(length(x_range) == 2)

  # if (length(x_range) == 0) {
  #   return(bin_params(numeric()))
  # }
  stopifnot(is.numeric(width), length(width) == 1)
  if (width <= 0) {
    stop('`binwidth` must be positive', call. = FALSE)
  }

  if (!is.null(boundary) && !is.null(center)) {
    stop('Only one of \'boundary\' and \'center\' may be specified.')
  } else if (is.null(boundary)) {
    if (is.null(center)) {
      # If neither edge nor center given, compute both using tile layer's
      # algorithm. This puts min and max of data in outer half of their bins.
      boundary <- width / 2
    } else {
      # If center given but not boundary, compute boundary.
      boundary <- center - width / 2
    }
  }

  # Find the left side of left-most bin: inputs could be Dates or POSIXct, so
  # coerce to numeric first.
  x_range <- as.numeric(x_range)
  width <- as.numeric(width)
  boundary <- as.numeric(boundary)
  shift <- floor((x_range[1] - boundary) / width)
  origin <- boundary + shift * width

  # Small correction factor so that we don't get an extra bin when, for
  # example, origin = 0, max(x) = 20, width = 10.
  max_x <- x_range[2] + (1 - 1e-08) * width
  breaks <- seq(origin, max_x, width)

  bin_breaks(breaks, closed = closed)
}

bin_breaks_bins <- function(x_range, bins = 30, center = NULL,
                            boundary = NULL, closed = c('right', 'left')) {
  stopifnot(length(x_range) == 2)

  bins <- as.integer(bins)
  if (bins < 1) {
    stop('Need at least one bin.', call. = FALSE)
  } else if (bins == 1) {
    width <- diff(x_range)
    boundary <- x_range[1]
  } else {
    width <- (x_range[2] - x_range[1]) / (bins - 1)
  }

  bin_breaks_width(x_range, width,
    boundary = boundary, center = center,
    closed = closed
  )
}

.has_groups <- function(data) {
  # If no group aesthetic is specified, all values of the group column equal to
  # -1L. On the other hand, if a group aesthetic is specified, all values
  # are different from -1L (since they are a result of plyr::id()). NA is
  # returned for 0-row data frames.
  data$group[1L] != -1L
}
