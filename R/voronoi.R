#' Generate a Bounded Voronoi Plot
#'
#' Creates a Voronoi plot where cells are clipped to a maximum radius around each point,
#' with extensive options for customization including shape, highlighting, and color.
#'
#' @param data A data frame containing the plotting data.
#' @param radius_limit The maximum radius (or half side-length for squares) for the clipping shape. Defaults to 15.
#' @param shape The clipping shape. One of "circle" (default), "square", or "cell".
#' @param point_size The size of the central points. Defaults to 2.
#' @param col_palette A named vector for custom cell colors, e.g., `c("Type1" = "red", "Type2" = "#00FF00")`. If `NULL`, uses ggplot's default palette.
#' @param x_col The name of the column in `data` containing X coordinates. Defaults to "x".
#' @param y_col The name of the column in `data` containing Y coordinates. Defaults to "y".
#' @param color_col The name of the column in `data` used for coloring the cells. Defaults to "cell_type".
#' @param highlight_col The name of the logical (`TRUE`/`FALSE`) column in `data` used for highlighting cells. Defaults to "highlighted".
#' @param opacity The opacity (0 to 1) of non-highlighted cells. Highlighted cells are always fully opaque (1.0). Defaults to 0.3.
#'
#' @return A `ggplot` object representing the Voronoi plot.
#'
#' @importFrom sf st_as_sf st_geometry st_polygon st_sfc st_sf coord_sf
#' @importFrom sp SpatialPointsDataFrame
#' @importFrom dismo voronoi
#' @importFrom ggplot2 ggplot geom_sf geom_point scale_alpha_identity scale_color_identity labs theme_bw aes scale_fill_manual
#' @importFrom grDevices runif
#'
#' @export
generate_voronoi_plot <- function(data, radius_limit = 15, shape = "circle", point_size = 2, col_palette = NULL, x_col="x", y_col="y", color_col="cell_type", highlight_col="highlighted", opacity=0.3) {

  # Helper function to create a circle polygon
  create_circle_polygon <- function(center_x, center_y, radius, n_points = 100) {
    angles <- seq(0, 2 * pi, length.out = n_points + 1)
    points_matrix <- cbind(
      center_x + radius * cos(angles),
      center_y + radius * sin(angles)
    )
    points_matrix[nrow(points_matrix), ] <- points_matrix[1, ]
    st_polygon(list(points_matrix))
  }

  # Helper function to create a square polygon
  create_square_polygon <- function(center_x, center_y, radius) {
    half_side <- radius
    points_matrix <- rbind(
      c(center_x - half_side, center_y - half_side),
      c(center_x + half_side, center_y - half_side),
      c(center_x + half_side, center_y + half_side),
      c(center_x - half_side, center_y + half_side),
      c(center_x - half_side, center_y - half_side)
    )
    st_polygon(list(points_matrix))
  }

  # Helper function to create an organic "cell" shape
  create_cell_shape_polygon <- function(center_x, center_y, radius, n_points = 100, noise_factor = 0.2) {
    angles <- seq(0, 2 * pi, length.out = n_points + 1)
    noise <- runif(n_points + 1, min = -noise_factor * radius, max = noise_factor * radius)
    noisy_radius <- radius + noise
    noisy_radius[length(noisy_radius)] <- noisy_radius[1]
    
    points_matrix <- cbind(
      center_x + noisy_radius * cos(angles),
      center_y + noisy_radius * sin(angles)
    )
    points_matrix[nrow(points_matrix), ] <- points_matrix[1, ]
    st_polygon(list(points_matrix))
  }


  # Input validation
  required_cols <- c(x_col, y_col, color_col, highlight_col)
  if (!all(required_cols %in% names(data))) {
    missing_cols <- required_cols[!required_cols %in% names(data)]
    stop(paste("Input data frame must contain the specified columns. Missing:", paste(missing_cols, collapse=", ")))
  }
  
  if (!is.logical(data[[highlight_col]])) {
    stop(paste("Highlight column '", highlight_col, "' must be logical (TRUE/FALSE)."))
  }

  sp_points <- sp::SpatialPointsDataFrame(coords = data[, c(x_col, y_col)], data = data)
  voronoi_sp <- dismo::voronoi(sp_points)
  plot_data <- st_as_sf(voronoi_sp)
  
  clipped_geoms_list <- lapply(1:nrow(plot_data), function(i) {
    if (shape == "square") {
      clipping_poly <- create_square_polygon(
        center_x = plot_data[[x_col]][i],
        center_y = plot_data[[y_col]][i],
        radius = radius_limit
      )
    } else if (shape == "cell") {
      clipping_poly <- create_cell_shape_polygon(
        center_x = plot_data[[x_col]][i],
        center_y = plot_data[[y_col]][i],
        radius = radius_limit
      )
    } else {
      clipping_poly <- create_circle_polygon(
        center_x = plot_data[[x_col]][i],
        center_y = plot_data[[y_col]][i],
        radius = radius_limit
      )
    }
    
    clipped_sf_object <- suppressWarnings({
      st_intersection(plot_data[i, "geometry"], clipping_poly)
    })
    
    if (nrow(clipped_sf_object) == 0) {
        return(st_polygon())
    } else {
        return(st_geometry(clipped_sf_object)[[1]])
    }
  })
  
  geoms <- st_sfc(clipped_geoms_list)
  plot_sf <- st_sf(plot_data, geometry = geoms) 

  if (nrow(plot_sf) == 0) {
      warning("No valid polygons were generated after clipping. Plot will be empty.")
      return(ggplot(data, aes(x=.data[[x_col]], y=.data[[y_col]])) + geom_point() + labs(title="Voronoi Plot (No Polygons)"))
  }

  p <- ggplot(plot_sf) +
    geom_sf(aes(fill = .data[[color_col]], 
                alpha = ifelse(.data[[highlight_col]], 1.0, opacity)),
            color = NA, lwd = 0) +
            
    geom_sf(data = plot_sf[!plot_sf[[highlight_col]], ],
            fill = NA, aes(color = "grey"), lwd = 0.8) +
            
    geom_sf(data = plot_sf[plot_sf[[highlight_col]], ],
            fill = NA, aes(color = "black"), lwd = 0.8) +

    geom_point(data = data[!data[[highlight_col]], ], 
               aes(x = .data[[x_col]], y = .data[[y_col]]),
               shape = 16, size = point_size, color = "grey", alpha = opacity + 0.2) +
               
    geom_point(data = data[data[[highlight_col]], ], 
               aes(x = .data[[x_col]], y = .data[[y_col]]),
               shape = 16, size = point_size, color = "black") +

    scale_alpha_identity(guide = "none") +
    scale_color_identity(guide = "none") +
    labs(title = "Bounded Voronoi Plot", 
         x = "X Coordinate", y = "Y Coordinate", 
         fill = color_col) +
    theme_bw() +
    coord_sf(datum = NA)
  
  if (!is.null(col_palette)) {
    p <- p + scale_fill_manual(values = col_palette)
  }

  return(p)
}