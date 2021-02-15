# [WIP] Tennis In-Game Win Probability with R

An experiment in building an in-game win probability model for tennis matches.

## Development notes

Data cleanup tasks to do:

- Split `match_id` on `-` to get year, player 1, player 2, etc.
- Need to mutate initials of each player and store in fields for player 1 and player 2 so `Serving` is meaningful (`IS` for `Iga_Swiatek`)
- Match doesn't have a final frame but ends with `PtWinner` after last record for each match
- Winner of the final point is the winner of the match (player `1` or `2` in `PtWinner`)
- Records are numbered by point (approximately 100 per match)
- `Set1` and `Set2` are sets won by player 1 or two
- Same for `Gm1` and `Gm2`
- `Pts` needs to be split on `-` to find points for each player
