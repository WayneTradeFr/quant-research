# ADX/DMI Trend Follower — XAUUSD (H1)

Close-only trend-following Expert Advisor (MQL5) built on the ADX/DMI system, with a documented
validation process: in-sample optimisation, out-of-sample test, ablation of every risk filter,
and a comparison of three risk-per-trade levels.

> Research project. Backtest results only, no live track record yet. Not investment advice.

![Equity curves](docs/equity_curve.png)

## Strategy

All signals are computed on the **last closed bar**; orders are sent at the next bar's open (no intra-bar repainting).

| Block | Rule |
|---|---|
| Long entry | ADX > 20, ADX rising for 2 consecutive closes, +DI > -DI + 5 |
| Short entry | Symmetric (-DI > +DI + 5) |
| Initial stop | 1.5 x ATR(14), no fixed take-profit |
| Exit 1 | ADX < 15 (trend lost) |
| Exit 2 | DI cross against the position |
| Exit 3 (exhaustion) | Profit > 2.5 ATR and ADX falling 3 closes: close 30%, trail the rest with a Chandelier (highest close of 10 bars - 2.5 ATR) |
| Break-even | Stop moved to entry (+10 pts) once profit >= 2R |
| Risk | 0.5% / 1% / 1.5% of equity per trade (see results); lot size from tick value / tick size, works on CFD and futures |
| Risk filters | Risk x0.5 when equity is 5% below its peak; no new entries after a 2% daily loss |
| Session | Entries only 09:00-18:00 broker server time |

## Results — full period (XAUUSD H1, 2016-01-01 to 2026-10-29)

Same parameters for the three runs except the risk per trade.
100 000 USD start, 1:100 leverage, 13.5 M ticks, history quality 87%.

| Metric | Risk 0.5% | Risk 1% | Risk 1.5% |
|---|---|---|---|
| Net profit | +191 k$ | +695 k$ | +1 083 k$ |
| Annualised return (compound) | 10.4% | 21.1% | 25.6% |
| Profit factor | 1.18 | 1.20 | 1.18 |
| Recovery factor | 5.33 | 5.32 | 4.54 |
| Sharpe ratio | 1.59 | 1.82 | 1.60 |
| Max drawdown (balance / equity) | 11.4% / 13.9% | 20.7% / 22.8% | 29.6% / 32.8% |
| Annualised return / max balance drawdown | 0.91 | 1.02 | 0.87 |
| Average win / average loss | 1 037 $ / -624 $ | 3 564 $ / -2 122 $ | 6 032 $ / -3 645 $ |
| Swap cost | -14 k$ | -46 k$ | -71 k$ |

About 2 860 closing deals (about 2 500 positions), max 22 consecutive losses, average holding time 9 h 16 min in all three runs.

**Reading**
- Profit and drawdown scale with the risk per trade, but not exactly proportionally (equity-drawdown scaling, daily cap and lot rounding interact with the risk level).
- On this data, **1% gives the best risk-adjusted profile** (highest Sharpe, best return per point of drawdown). This is an observation on one backtest, not a general rule.
- Even at 0.5%, the equity drawdown (13.9%) would exceed a typical 10% prop-firm limit; roughly 0.3% would be needed.

### In-sample vs out-of-sample (returns normalised by balance at entry)

| | 2016-2022 (PF / annualised) | 2023-2026 (PF / annualised) |
|---|---|---|
| Risk 0.5% | 1.26 / 13.0% | 1.15 / 5.9% |
| Risk 1% | 1.30 / 25.7% | 1.19 / 13.5% |
| Risk 1.5% | 1.24 / 28.5% | 1.21 / 21.1% |

Out-of-sample performance degrades (annualised return roughly halves at 1%) but stays profitable at every risk level.

### Annual return (% of start-of-year balance)

![Annual returns](docs/yearly_returns.png)

| Year | Risk 0.5% | Risk 1% | Risk 1.5% |
|---|---|---|---|
| 2016 | +19.5% | +23.1% | +19.4% |
| 2017 | +11.3% | +29.3% | +34.0% |
| 2018 | +35.5% | +75.6% | +78.7% |
| 2019 | -0.1% | +4.0% | +8.8% |
| 2020 | +21.0% | +48.0% | +55.4% |
| 2021 | +10.6% | +21.1% | +32.0% |
| 2022 | -3.2% | -6.0% | -10.8% |
| 2023 | +2.8% | +6.0% | +8.8% |
| 2024 | +5.8% | +18.1% | +24.3% |
| 2025 | +8.1% | +23.6% | +37.2% |
| 2026 (to Oct 29) | +6.1% | +5.0% | +12.1% |

## What the validation showed

- **Risk filters do not add alpha.** Disabling them roughly doubles profit but also the drawdown: equivalent to raising risk per trade, not to a better strategy.
- **The session filter matters most.** Without it, profit factor and Sharpe fall sharply.
- **The ADX entry threshold is not stable.** The in-sample optimum (30) was an isolated peak that did not hold out-of-sample, so a low threshold (20) was kept for trade count.
- **Hour-of-day filters were rejected**: results flip sign between adjacent hours and between periods (noise).

Details in [`docs/validation.md`](docs/validation.md).

## Limitations

- Backtest only. Tester commission was 0 (the reports show no commission); with a commission-based account the profit factor would be lower. Swap cost is significant (see table).
- **Long flat phase**: the balance stagnated from mid-2021 to end-2023, with the maximum drawdown reached in early 2023. Expect multi-year plateaus.
- Roughly one position in three wins; losing streaks reach 22 trades.
- The 2023-2025 forward window was inspected during exploration, so the out-of-sample result is not fully blind.
- Returns are concentrated in some years (2018, 2020, 2025); 2022 is negative and 2019 and 2023 are weak.

## Repository layout

```
src/ADX_DMI_EA.mq5        Expert Advisor (MetaTrader 5)
docs/validation.md        Methodology, ablation study, lessons learned
docs/equity_curve.png     Balance and drawdown, three risk levels
docs/yearly_returns.png   Annual returns, three risk levels
docs/yearly_returns.csv   Annual returns (data)
```

## Usage

1. Copy `src/ADX_DMI_EA.mq5` to `MQL5/Experts/` and compile in MetaEditor.
2. Strategy Tester: XAUUSD, H1, real ticks or "1 minute OHLC", deposit 100 000.
3. Set the inputs from the table above (the file defaults are the starting values of the research, not the final ones).
4. Session hours are **server time**: check your broker's offset.
