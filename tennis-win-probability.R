# Load libraries
# install.packages("nflfastR", "ggimage", "devtools")
# devtools::install_github("topfunky/gghighcontrast")
library(nflfastR)
library(tidyverse)
library(gghighcontrast)
library(scales)

library(xgboost)
library(caTools)
library(dplyr)
library(caret)

library(future)
library(future.apply)
future.seed=TRUE
is_running_in_r_studio <- Sys.getenv("RSTUDIO") == "1"
if (is_running_in_r_studio) {
  plan(multisession)
} else {
  plan(multicore)
}

DEVELOPMENT_MODE = FALSE

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

directories <- list("data", "out", "out/w", "out/m")
for (directory in directories) {
  if (!dir.exists(directory)) {
    dir.create(directory)
  }
}

# Point by point records for matches: "w" or "m".
#
# Caches remote file if missing from local filesystem. Returns data frames.
charting_points <- function(gender) {
  retrieve_csv_and_cache_data_locally(
    str_interp(
      "https://raw.githubusercontent.com/JeffSackmann/tennis_MatchChartingProject/master/charting-${gender}-points.csv"
    )
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


build_win_prediction_model <- function(data) {
  set.seed(525)
  # Sample 80% of rows
  indexes = sample(1:nrow(data),
                   round(nrow(data) * 0.8),
                   replace = FALSE)
  train <- data[indexes,]

  y = as.numeric(train$Player1Wins)
  x = train %>% select(SetDelta, GmDelta, Pts1Delta, PtCountdown, Player1IsServing)

  xgb_train <- xgb.DMatrix(data = as.matrix(x), label = y)

  xgb_params <-
    list(
      booster = "gbtree",
      objective = "binary:logistic",
      nthread = -1,
      # default: use as many cores as possible
      eta = 0.3,
      gamma = 0,
      max_depth = 6,
      min_child_weight = 1,
      subsample = 1,
      colsample_bytree = 1
    )

  win_prediction_model <- xgb.train(
    params = xgb_params,
    data = xgb_train,
    nrounds = 3000,
    verbose = 1
  )

  return(win_prediction_model)
}


populate_each_row_with_prediction <- function(pbp) {
  win_prediction_model <- build_win_prediction_model(pbp)

  pbp %<-% {
    pbp %>%
    mutate(win_probability_player_1 =
             predict(win_prediction_model, as.matrix(
               pbp[row_number(), ] %>% select(SetDelta, GmDelta, Pts1Delta, PtCountdown, Player1IsServing)
             ), reshape = TRUE))
  }
  return(pbp)
}


plot_for_match_id <- function(data, single_match_id, prefix) {
  single_match_records <- data %>% filter(match_id == single_match_id)

  plot <- plot_for_data(single_match_records,
                        "white",
                        dayglo_orange)
  ggsave(
    str_interp("out/${prefix}/${single_match_id}.png"),
    plot = plot,
    width = 8,
    height = 4
  )
}


# Plot a single match.
#
# Returns the plot which can be saved to disk or displayed otherwise.
plot_for_data <-
  function(data,
           foreground_color,
           background_color) {
    this_match <- data[1, ]

    plot <- ggplot(data,
                   aes(x = Pt, y = win_probability_player_1)) +
      # 50% reference line
      geom_hline(yintercept = 0.5,
                 color = foreground_color,
                 size = 1) +

      geom_vline(
        data = data %>% filter(IsStartOfSet),
        aes(xintercept = Pt),
        color = foreground_color,
        size = 0.25
      ) +

      # Win Probability
      geom_line(size = 0.8) +

      annotate(
        "text",
        x = 5,
        y = 0.95,
        label = this_match$Player1,
        family = "InputMono",
        color = foreground_color,
        size = 2
      ) +

      annotate(
        "text",
        x = 5,
        y = 0.05,
        label = this_match$Player2,
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
          "${this_match$Player1} vs ${this_match$Player2} @ ${this_match$Tournament} ${this_match$MatchDate}"
        ),
        subtitle = "Custom win probability model for tennis",
        caption = "Model: topfunky.com • Data: The Match Charting Project",
        x = "Plays",
        y = "Win Probability"
      )
  }

plot_accuracy <-
  function(data,
           gender,
           foreground_color,
           background_color) {
    data <- data %>%
      filter(!is.na(SetCount)) %>%
      mutate(bin_pred_prob = round(win_probability_player_1 / 0.05) * 0.05) %>%
      group_by(SetCount, bin_pred_prob) %>%
      # Calculate the calibration results:
      summarize(
        n_plays = n(),
        n_wins = sum(Player1Wins),
        bin_actual_prob = n_wins / n_plays
      ) %>%
      ungroup()

    plot <- data %>%
      ggplot() +
      geom_point(aes(x = bin_pred_prob,
                     y = bin_actual_prob,
                     size = n_plays),
                 color = yellowgreen_neon) +
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
        title = str_interp("Model Accuracy by Set: ${gender}"),
        subtitle = "Model prediction vs actual win percentage",
        caption = "Model: topfunky.com • Data: The Match Charting Project",
        x = "Predicted",
        y = "Actual"
      ) +
      facet_wrap( ~ SetCount, nrow = 2)
  }

# Either process the data, write a cached version, and return it,
# or just return the cached version from disk for quicker processing.
load_and_clean_data <- function(data, gender) {
  local_data_cache_filename <- str_interp("data/${gender}.rds")
  if (DEVELOPMENT_MODE) {
    # Always recalculate if in development mode
    return(clean_data(data))
  } else if (!file.exists(local_data_cache_filename)) {
    # Recalculate and save to disk
    cleaned_data <- clean_data(data)
    write_rds(cleaned_data, local_data_cache_filename)
    return(cleaned_data)
  } else {
    # Use cache
    cleaned_data <- readRDS(local_data_cache_filename)
    return(cleaned_data)
  }
}

# Turn "0", "15", "30", "40", "AD" to 1, 2, 3, 4, 5
# so traditional math can be done against the points scored.
convert_pts_to_integer <- function(v) {
  case_when(
    v == "0" ~ 0,
    v == "15" ~ 1,
    v == "30" ~ 2,
    v == "40" ~ 3,
    v == "AD" ~ 4,
    # Tiebreak
    v == "1" ~ 1,
    v == "2" ~ 2,
    v == "3" ~ 3,
    v == "4" ~ 4,
    v == "5" ~ 5,
    v == "6" ~ 6,
  )
}

clean_data <- function(data) {
  pbp <- data %>%
    # Fix problematic encoding on some rows
    mutate(match_id = iconv(match_id, "ASCII", "UTF-8")) %>%
    # The `separate` function splits a string like "20200823-A-B-C" on dashes.
    # Grab only the first piece as a new `date_string` column.
    separate(
      match_id,
      c(
        "date_string",
        "Gender",
        "Tournament",
        "MatchRound",
        "Player1",
        "Player2"
      ),
      remove = FALSE,
      sep = "-"
    ) %>%
    separate(Pts, c("PtsA", "PtsB"), remove = FALSE, sep = "-") %>%
    mutate(
      PtsA = convert_pts_to_integer(PtsA),
      PtsB = convert_pts_to_integer(PtsB),
      # If server is Player1, then PtsA will be the server's score
      Pts1Delta = ifelse(Svr == 1, (PtsA - PtsB), (PtsB - PtsA)),
      Pts2Delta = ifelse(Svr == 2, (PtsA - PtsB), (PtsB - PtsA)),
      MatchDate = as.Date(date_string, format = "%Y%m%d"),
      Player1 = str_replace_all(Player1, "_", " "),
      Player2 = str_replace_all(Player2, "_", " "),
      Tournament = str_replace_all(Tournament, "_", " "),
      Player1IsServing = as.numeric(Svr == 1)
    )

  # Get final play to determine match winner
  final_play_for_each_match <-
    pbp %>%
    group_by(match_id) %>%
    filter(Pt == max(Pt)) %>%
    mutate(
      Player1Wins = as.numeric(PtWinner == 1),
      Pt = Pt + 1,
      PtTotal = Pt
    ) %>%
    ungroup()

  # Select only a few fields
  match_winners <- final_play_for_each_match %>%
    select(match_id, Player1Wins, PtTotal)

  # Join so all rows include the match winner
  pbp <-
    pbp %>%
    inner_join(match_winners, by = "match_id")

  # Create rows for final outcome.
  # The point by point frames don't include the final score.
  match_result_plays <- final_play_for_each_match %>%
    mutate(
      Set1 = ifelse(Player1Wins == 1, Set1 + 1, Set1),
      Set2 = ifelse(Player1Wins == 0, Set2 + 1, Set2),
      Gm1 = 0,
      Gm2 = 0,
      Pts = "0-0",
      Pts1Delta = 0,
      Pts2Delta = 0
    ) %>%
    select(
      match_id,
      Pt,
      Set1,
      Set2,
      Gm1,
      Gm2,
      Pts,
      Player1Wins,
      MatchDate,
      Gender,
      Tournament,
      MatchRound,
      Player1,
      Player2,
      PtTotal,
      Pts1Delta,
      Pts2Delta,
      Player1IsServing
    )

  pbp <- bind_rows(pbp, match_result_plays)

  # Calculate delta for Sets, Games, Pt (number of plays)
  pbp <- pbp %>%
    mutate(
      SetDelta = Set1 - Set2,
      GmDelta = Gm1 - Gm2,
      PtCountdown = PtTotal - Pt,
      IsStartOfSet = (Pt < PtTotal & (Set1 > lag(Set1) |
                                        Set2 > lag(Set2))),
      # Calculate set but index from 1 (first set played is Set 1)
      SetCount = ifelse(Pt < PtTotal, Set1 + Set2 + 1, NA)
    ) %>%
    arrange(match_id, Pt)

  return(pbp)
}

run_w <- function() {
  match_ids <- list(
    "20190928-W-Wuhan-F-Aryna_Sabalenka-Alison_Riske",
    "20190325-W-Miami-R16-Caroline_Wozniacki-Su_Wei_Hsieh",
    "20190325-W-Miami-R16-Ashleigh_Barty-Kiki_Bertens",
    "20080705-W-Wimbledon-F-Venus_Williams-Serena_Williams"
  )

  pbp <- load_and_clean_data(charting_points("w"), "w") %>%
    filter(MatchDate > as.Date("2005-01-01")) %>%
    populate_each_row_with_prediction()

  for (single_match_id in match_ids) {
    plot_for_match_id(pbp, single_match_id, "w")
  }

  plot <- plot_accuracy(pbp, "Women", light_grey, "#222222")
  ggsave(
    "out/accuracy-w.png",
    plot = plot,
    width = 6,
    height = 4
  )
}


run_m <- function() {
  match_ids <- list(
    "20210212-M-Australian_Open-R32-Andrey_Rublev-Feliciano_Lopez",
    "20080811-M-Los_Angeles-F-Andy_Roddick-Juan_Martin_Del_Potro",
    "20200130-M-Australian_Open-SF-Roger_Federer-Novak_Djokovic",
    "20050403-M-Miami_Masters-F-Roger_Federer-Rafael_Nadal",
    "20180905-M-US_Open-QF-Rafael_Nadal-Dominic_Thiem",
    "20190704-M-Wimbledon-R64-Rafael_Nadal-Nick_Kyrgios"
  )

  pbp <- load_and_clean_data(charting_points("m"), "m") %>%
    filter(MatchDate > as.Date("2005-01-01")) %>%
    populate_each_row_with_prediction()

  for (single_match_id in match_ids) {
    plot_for_match_id(pbp, single_match_id, "m")
  }

  plot <- plot_accuracy(pbp, "Men", light_grey, "#222222")
  ggsave(
    "out/accuracy-m.png",
    plot = plot,
    width = 6,
    height = 4
  )
}

# run_w()
# run_m()

# Run in parallel
functions <- list(run_w, run_m)
future_lapply(functions, function(x) {
  x()
})
