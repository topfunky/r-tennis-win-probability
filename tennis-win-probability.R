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
if (!dir.exists("out")) {
  dir.create("out")
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

# Fields
# PtWinner : Index of player who won the point (last of match is match winner)
# Svr : Index of player who is serving



# TODO: Write for tennis
plot_for_data <-
  function(data,
           foreground_color,
           background_color) {
    single_match_id <- data[1,]$match_id

    plot <- ggplot(data,
                   aes(x = Pt, y = win_probability_player_1)) +
      # 50% reference line
      geom_hline(yintercept = 0.5,
                 color = grey,
                 size = 1) +


      # Win Probability
      geom_line(size = 0.8) +

      # Formatting
      # scale_x_reverse() +
      scale_y_continuous(labels = percent, limits = c(0, 1)) +
      theme_high_contrast(
        base_family = "InputMono",
        background_color = background_color,
        foreground_color = foreground_color
      ) +
      theme(axis.text.x = element_blank(),
            axis.ticks.x = element_blank()) +
      labs(
        title = str_interp("${single_match_id}"),
        subtitle = "Custom win probability model for tennis",
        caption = "Data from https://github.com/JeffSackmann/tennis_MatchChartingProject",
        x = "Plays",
        y = "Player 1 Win Probability"
      )
  }


build_win_prediction_model <- function(data) {
  set.seed(525)
  # Sample 80% of rows
  indexes = sample(1:nrow(data),
                   round(nrow(data) * 0.8),
                   replace = FALSE)
  train <- data[indexes, ]

  # Fields:
  win_prediction_model = glm(match_winner_is_player_1 ~
                               Set1 + Set2 + Gm1 + Gm2,
                             train,
                             family = "binomial")
  return(win_prediction_model)
}


populate_each_row_with_prediction <- function(pbp) {
  win_prediction_model <- build_win_prediction_model(pbp)

  pbp <- pbp %>%
    mutate(win_probability_player_1 =
             predict(win_prediction_model, pbp[row_number(),], type = "response"))
  return(pbp)
}


plot_for_match_id <- function(single_match_id) {
  plot <- plot_for_data(pbp %>% filter(match_id == single_match_id),
                        "black",
                        "white")
  ggsave(
    str_interp("out/${single_match_id}.png"),
    plot = plot,
    width = 6,
    height = 4
  )

}

run <- function() {
  pbp <- charting_w_points()

  final_play_for_each_match <-
    pbp %>%
    group_by(match_id) %>%
    filter(Pt == max(Pt)) %>%
    mutate(match_winner_is_player_1 = ifelse(PtWinner == 1, 1, 0)) %>%
    select(match_id, match_winner_is_player_1)

  pbp <-
    pbp %>%
    inner_join(final_play_for_each_match, by = "match_id")

  pbp <- populate_each_row_with_prediction(pbp)

  plot_for_match_id("20190928-W-Wuhan-F-Aryna_Sabalenka-Alison_Riske")

  # For debugging...create a frame with just this match
  single_match_pbp <-
    pbp %>%
    filter(match_id == "20190928-W-Wuhan-F-Aryna_Sabalenka-Alison_Riske") %>%
    select(
      match_id,
      Pt,
      Set1,
      Set2,
      Gm1,
      Gm2,
      Pts,
      Svr,
      match_winner_is_player_1,
      win_probability_player_1
    )
}

run()
