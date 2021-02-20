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

# Plot a single match.
#
# Returns the plot which can be saved to disk or displayed otherwise.
plot_for_data <-
  function(data,
           foreground_color,
           background_color) {
    this_match <- data[1,]

    plot <- ggplot(data,
                   aes(x = Pt, y = win_probability_player_1)) +
      # 50% reference line
      geom_hline(yintercept = 0.5,
                 color = foreground_color,
                 size = 1) +

      # Win Probability
      geom_line(size = 0.8) +

      annotate(
        "text",
        x = 5,
        y = 0.95,
        label = this_match$player1,
        family = "InputMono",
        color = foreground_color,
        size = 2
      ) +

      annotate(
        "text",
        x = 5,
        y = 0.05,
        label = this_match$player2,
        family = "InputMono",
        color = foreground_color,
        size = 2
      ) +

      # Formatting
      scale_y_continuous(labels = percent, limits = c(0, 1)) +
      theme_high_contrast(
        base_family = "InputMono",
        background_color = background_color,
        foreground_color = foreground_color
      ) +
      theme(axis.text.x = element_blank(),
            axis.ticks.x = element_blank()) +
      labs(
        title = str_interp(
          "${this_match$player1} vs ${this_match$player2} @ ${this_match$tournament} ${this_match$date}"
        ),
        subtitle = "Custom win probability model for women's tennis",
        caption = "Data from https://github.com/JeffSackmann/tennis_MatchChartingProject",
        x = "Plays",
        y = "Win Probability"
      )
  }


build_win_prediction_model <- function(data) {
  set.seed(525)
  # Sample 80% of rows
  indexes = sample(1:nrow(data),
                   round(nrow(data) * 0.8),
                   replace = FALSE)
  train <- data[indexes, ]

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


plot_for_match_id <- function(data, single_match_id) {
  single_match_records <- data %>% filter(match_id == single_match_id)

  plot <- plot_for_data(single_match_records,
                        "white",
                        dayglo_orange)
  ggsave(
    str_interp("out/${single_match_id}.png"),
    plot = plot,
    width = 8,
    height = 4
  )
}

load_and_clean_data <- function() {
  pbp <- charting_w_points() %>%
    # Fix problematic encoding on some rows
    mutate(match_id = iconv(match_id, "ASCII", "UTF-8")) %>%
    # The `separate` function splits a string like "20200823-A-B-C" on dashes.
    # Grab only the first piece as a new `date_string` column.
    separate(
      match_id,
      c(
        "date_string",
        "gender",
        "tournament",
        "round",
        "player1",
        "player2"
      ),
      remove = FALSE,
      sep = "-"
    ) %>%
    mutate(
      date = as.Date(date_string, format = "%Y%m%d"),
      player1 = str_replace(player1, "_", " "),
      player2 = str_replace(player2, "_", " ")
    )

  # Get final play to determine match winner
  final_play_for_each_match <-
    pbp %>%
    group_by(match_id) %>%
    filter(Pt == max(Pt)) %>%
    mutate(match_winner_is_player_1 = ifelse(PtWinner == 1, 1, 0))

  # Select only a few fields
  match_winners <- final_play_for_each_match %>%
    select(match_id, match_winner_is_player_1)

  # Join so all rows include the match winner
  pbp <-
    pbp %>%
    inner_join(match_winners, by = "match_id")

  # Create rows for final outcome.
  # The point by point frames don't include the final score.
  match_result_plays <- final_play_for_each_match %>%
    mutate(
      Pt = Pt + 1,
      Set1 = ifelse(match_winner_is_player_1 == 1, Set1 + 1, Set1),
      Set2 = ifelse(match_winner_is_player_1 == 0, Set2 + 1, Set2),
      Gm1 = 0,
      Gm2 = 0,
      Pts = "0-0"
    ) %>%
    select(
      match_id,
      Pt,
      Set1,
      Set2,
      Gm1,
      Gm2,
      Pts,
      match_winner_is_player_1,
      date,
      gender,
      tournament,
      round,
      player1,
      player2
    )

  pbp <- bind_rows(pbp, match_result_plays)
  return(pbp)
}

plot_accuracy <-
  function(data, foreground_color, background_color) {
    data <- data %>%
      mutate(bin_pred_prob = round(win_probability_player_1 / 0.02) * 0.02) %>%
      group_by(bin_pred_prob) %>%
      # Calculate the calibration results:
      summarize(
        n_plays = n(),
        n_wins = length(which(match_winner_is_player_1 == 1)),
        bin_actual_prob = n_wins / n_plays
      )

    plot <- data %>%
      # ungroup() %>%
      # mutate(qtr = fct_recode(
      #   factor(qtr),
      #   "Q1" = "1",
      #   "Q2" = "2",
      #   "Q3" = "3",
      #   "Q4" = "4"
      # )) %>%
      ggplot() +
      geom_point(aes(
        x = bin_pred_prob,
        y = bin_actual_prob,
        size = n_plays
      ), color = yellowgreen_neon) +
      geom_smooth(aes(x = bin_pred_prob, y = bin_actual_prob),
                  color = foreground_color,
                  method = "loess") +
      geom_abline(
        slope = 1,
        intercept = 0,
        color = foreground_color,
        lty = 2 # dashed
      ) +
      scale_x_continuous(labels = percent, limits = c(0, 1)) +
      scale_y_continuous(labels = percent, limits = c(0, 1)) +
      theme_high_contrast(
        base_family = "InputMono",
        background_color = background_color,
        foreground_color = foreground_color
      ) +
      theme(legend.position = "none") +
      labs(
        title = "Model Accuracy",
        subtitle = "Custom prediction vs actual win percentage",
        caption = "Data from Match Charting Project",
        x = "Predicted",
        y = "Actual"
      )
    # TODO: facet_wrap
  }


run <- function() {
  match_ids <- list(
    "20190928-W-Wuhan-F-Aryna_Sabalenka-Alison_Riske",
    "20190325-W-Miami-R16-Caroline_Wozniacki-Su_Wei_Hsieh",
    "20190325-W-Miami-R16-Ashleigh_Barty-Kiki_Bertens",
    "20080705-W-Wimbledon-F-Venus_Williams-Serena_Williams"
  )

  pbp <- load_and_clean_data() %>%
    filter(date > as.Date("2008-01-01")) %>%
    populate_each_row_with_prediction()

  for (single_match_id in match_ids) {
    plot_for_match_id(pbp, single_match_id)
  }

  plot <- plot_accuracy(pbp, light_grey, "#222222")
  ggsave("out/accuracy.png", plot=plot, width=6, height=4)

  # For debugging...create a frame with just this match
  single_match_pbp <-
    pbp %>%
    filter(match_id == single_match_id) %>%
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
