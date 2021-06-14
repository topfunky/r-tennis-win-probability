# Tennis In-Game Win Probability with R

An experiment in building an in-game win probability model for tennis matches. Uses [XGBoost](https://xgboost.ai).

## Sample match

- [Point by point](http://www.tennisabstract.com/charting/20080705-W-Wimbledon-F-Venus_Williams-Serena_Williams.html)

![Venus v Sabrina](out/w/20080705-W-Wimbledon-F-Venus_Williams-Serena_Williams.png)

- [Point by point](http://www.tennisabstract.com/charting/20050403-M-Miami_Masters-F-Roger_Federer-Rafael_Nadal.html)
- [Video highlights](https://www.youtube.com/watch?v=QKlXGgbwwJI)

![Federer v Nadal](out/m/20050403-M-Miami_Masters-F-Roger_Federer-Rafael_Nadal.png)

## Accuracy

Women's model

![Accuracy Women](out/w/accuracy.png)

Men's model

![Accuracy Men](out/m/accuracy.png)

## Feature Importance

Women's model

![Feature Importance Women](out/w/importance.png)

Men's model

![Feature Importance Men](out/m/importance.png)

## Reference

Data is from the [Match Charting Project](https://github.com/JeffSackmann/tennis_MatchChartingProject).

## Development notes

Run on the command line:

```shell
$ R --no-save < tennis-win-probability.R
```

Data cleanup tasks to do:

- Records are numbered by point `Pts` (approximately 100 per match)
- `Set1` and `Set2` are sets won by player 1 or two
- Same for `Gm1` and `Gm2`
- The model uses points, games, and sets
- The identity of the player serving the ball is not currently included in the model
- Add estimated points (EPA) for potentially even greater accuracy
