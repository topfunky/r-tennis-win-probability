# Load libraries
# install.packages("nflfastR", "ggimage", "devtools")
# devtools::install_github("topfunky/gghighcontrast")
library(nflfastR)
library(tidyverse)
library(gghighcontrast)
library(scales)
library(ggimage)

# Don't display numbers in scientific notation
options(scipen = 9999)

# Colors
dayglo_orange = "#ff6700"
light_blue = "#0098ff"
red = "#ff0000"
grey = "#808080"
kiwi_green = "#8ee53f"
dark_olive_green = "#556b2f"
dark_raspberry = "#872657"
rich_black = "#010203"

yellowgreen_neon = "#8bff00"
light_grey = "#999999"

if (!dir.exists("data")) {
  dir.create("data")
}

# Point by point records for women's matches.
#
# Caches remote file if missing from local filesystem. Returns data frames.
charting_w_points <- function() {
  retrieve_csv_and_cache_data_locally(
    "https://raw.githubusercontent.com/JeffSackmann/tennis_MatchChartingProject/master/charting-w-points.csv"
  )
}

charting_w_matches <- function() {
  retrieve_csv_and_cache_data_locally(
    "https://raw.githubusercontent.com/JeffSackmann/tennis_MatchChartingProject/master/charting-w-matches.csv"
  )
}

retrieve_csv_and_cache_data_locally <- function(url) {
  filename <- basename(url)

  # Check for cache or download if missing
  local_filename_with_path = str_interp("data/${filename}")
  if (!file.exists(local_filename_with_path)) {
    download.file(url, local_filename_with_path)
  }

  data <- read_csv(local_filename_with_path)

  return(data)
}
