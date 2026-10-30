# Validation notes

## Protocol

1. **Baseline** with textbook ADX/DMI rules (entry ADX > 25 rising, DI spread 5, stop 1.5 ATR). Net +397 k$ on 2016-2026, profit factor 1.11, drawdown ~22%.
2. **Grid optimisation** on 2016-2022 (ADX entry, ADX exit, stop multiple, Chandelier multiple), criterion `OnTester`: Sharpe x sqrt(trades) / (1 + equity DD% / 10), with a floor of 100 trades and PF > 1.
3. **Forward test** on 2023 onward with parameters frozen.
4. **Plateau check**: prefer zones where neighbouring parameter values give similar scores, never an isolated best pass.
5. **Ablation** of each risk filter, in-sample and out-of-sample.

## Findings

### Parameter landscape
- Chandelier multiple: flat between 1.5 and 3.0 in both periods, so it was fixed at 2.5.
- Stop multiple: wider stops lower both profit and drawdown (a risk dial rather than an edge change).
- ADX entry: in-sample peak at 30 (neighbours 28 and 32 much weaker) did not survive the forward test, where 38-40 looked best. No stable plateau, so a low threshold (20) was chosen for volume and the drawdown handled through risk per trade.

### Hour-of-day analysis
- Stops cluster at 15:00-17:00 server time (US session): positions opened in the morning are stopped by US volatility, while winners exit overnight. Part of this is mechanical (selection effect), not proof that the US session causes the losses.
- Entries between 13:00 and 17:00 were profitable in both periods, so blocking them would remove profit without reducing the drawdown. Hour filters were not kept.

### Ablation (risk filters disabled cumulatively)

| Test | In-sample profit / DD balance | Out-of-sample profit / DD balance |
|---|---|---|
| Base | +391 k / 15.5% | +68 k / 15.8% |
| No equity-drawdown scaling | +836 k / 26.1% | +135 k / 26.5% |
| + no daily loss cap | +824 k / 26.1% | +130 k / 26.5% |
| + no volatility filter | +821 k / 26.2% | +130 k / 26.5% |
| + no break-even | +780 k / 27.5% | +143 k / 26.5% |
| + no session filter | +326 k / 34.1% | +108 k / 30.2% |

Reading: the volatility filter never triggered out-of-sample (identical result), the break-even is neutral, the daily cap helps slightly, and the session filter is the only one that changes quality (profit factor and Sharpe), not just risk level.

### Out-of-sample decay
Normalised by balance, annualised return is about 25% in 2016-2022 versus about 13.5% in 2023-today (profit factor 1.30 vs 1.19). Expectations should be based on the out-of-sample figures.

## Next steps
- Real-time demo run with the final parameters (spread, slippage, execution).
- Same parameters on another data feed or on MGC futures with real commissions.
- Stress test: shift each key parameter by one step and check stability.

## Note on risk levels
The optimisation and ablation figures above were run at 1% risk per trade. The final full-period runs in the README compare 0.5%, 1% and 1.5%: profit and drawdown scale up with risk, the profit factor stays between 1.18 and 1.20.
