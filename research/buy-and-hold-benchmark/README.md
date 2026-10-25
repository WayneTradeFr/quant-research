# Comparaison avec l'achat-conservation de l'or

> **EN summary** — Benchmark of the two published trend-following strategies against buy-and-hold gold (unlevered, Feb 2016 – Oct 2026, monthly data). Neither strategy beats buy-and-hold on return (CAGR 10.8% and 9.9% vs 11.7%) and Sharpe ratios are similar (0.82 and 0.78 vs 0.78). Their value is **diversification**: correlation with gold is 0.31 and 0.06. A 50/50 mix of gold and SuperTrend keeps the same return (11.3% vs 11.7%) with **half the drawdown** (11.6% vs 24.1%) and a Sharpe of 1.07. Alpha t-statistics (1.9 and 2.3) are marginal and biased upward by in-sample optimization.

## Pourquoi cette comparaison

Une stratégie sur l'or doit être jugée contre la solution la plus simple : acheter l'or et ne rien faire. Sur la période, l'or est passé d'environ 1 090 à 4 000 USD (×3,7). Une stratégie qui rapporte moins avec plus de travail n'apporte rien si elle ne réduit pas le risque ou ne diversifie pas.

## Méthode

- Période commune : **février 2016 - octobre 2026**, rendements **mensuels** (128 mois).
- Achat-conservation : une position longue sans levier, reconstruite à partir des prix des transactions des backtests (environ 23 000 points, au moins 20 par mois).
- Stratégies : solde du compte en fin de mois (Donchian M30 et SuperTrend M30 publiés ; AMRM avec SL = TP, voir le [post-mortem](../amrm-postmortem/README.md)).
- Bêta et alpha : régression des rendements mensuels de chaque stratégie sur ceux de l'or.

## Résultats

| | Capital final (base 100) | Rendement annualisé | Volatilité | Sharpe | Drawdown max (mensuel) | Corrélation avec l'or |
|---|---|---|---|---|---|---|
| Or, achat-conservation | 324 | 11,7 % | 15,7 % | 0,78 | 24,1 % | 1,00 |
| Donchian | 298 | 10,8 % | 13,7 % | 0,82 | 20,7 % | 0,31 |
| SuperTrend | 273 | 9,9 % | 13,1 % | 0,78 | 18,8 % | 0,06 |
| AMRM (SL = TP) | 124 | 2,1 % | 10,9 % | 0,24 | 37,8 % | 0,02 |

| | Bêta | Alpha annualisé | t-stat de l'alpha |
|---|---|---|---|
| Donchian | 0,27 | +7,9 % | 1,9 |
| SuperTrend | 0,05 | +9,7 % | 2,3 |

### Rendement annuel

| Année | Or | Donchian | SuperTrend | AMRM (SL = TP) |
|---|---|---|---|---|
| 2016 | -6,2 % | +19,4 % | -3,0 % | +22,8 % |
| 2017 | +12,8 % | +27,0 % | +5,0 % | +18,6 % |
| 2018 | -1,8 % | +9,6 % | -8,6 % | -4,1 % |
| 2019 | +18,8 % | +15,8 % | +5,6 % | -9,7 % |
| 2020 | +24,6 % | +16,4 % | +28,9 % | +1,5 % |
| 2021 | -3,5 % | +3,9 % | +33,9 % | +9,0 % |
| 2022 | -0,7 % | +2,6 % | -3,4 % | -10,5 % |
| 2023 | +13,4 % | -14,0 % | +17,8 % | -10,8 % |
| 2024 | +26,5 % | +4,5 % | +8,4 % | -5,4 % |
| 2025 | +65,5 % | +20,0 % | +12,5 % | +9,7 % |
| 2026 (jusqu'en oct.) | -7,3 % | +15,0 % | +17,9 % | +10,4 % |

![Capital normalisé](equity_comparison.svg)

### Mélanges avec l'or

| Portefeuille | Rendement annualisé | Sharpe | Drawdown max (mensuel) |
|---|---|---|---|
| 100 % or | 11,7 % | 0,78 | 24,1 % |
| 50 % or + 50 % Donchian | 11,6 % | 0,99 | 11,2 % |
| 50 % or + 50 % SuperTrend | 11,3 % | 1,07 | 11,6 % |
| Donchian + SuperTrend (50/50) | 10,7 % | 1,03 | 16,5 % |
| Un tiers chacun : or, Donchian, SuperTrend | 11,3 % | 1,16 | 10,3 % |

## Lecture

- **Seules, les stratégies ne battent pas l'or** : ni en rendement (10,8 % et 9,9 % contre 11,7 %), ni en Sharpe (0,82 et 0,78 contre 0,78). En 2025, année à +65,5 % pour l'or, elles font +20,0 % et +12,5 %.
- **Leur intérêt est la diversification** : corrélation de 0,31 et 0,06 avec l'or. Mélangées à parts égales avec l'or, elles gardent presque le même rendement avec environ la moitié du drawdown.
- **L'AMRM n'apporte rien** : rendement de 2,1 %, Sharpe de 0,24 et drawdown de 37,8 %, conforme au post-mortem.
- Corrélation entre le Donchian et le SuperTrend : 0,21.

## Limites

1. **Alpha fragile.** Les t-stats de 1,9 et 2,3 sont marginaux sur 128 mois, et les paramètres ont été optimisés sur la période : l'alpha réel est probablement plus faible.
2. **Données approximatives.** L'or est reconstruit à partir de prix de transactions et échantillonné au mois : son drawdown est sous-estimé. Pour les stratégies, le solde ne compte que les trades clôturés, sans les gains ou pertes latents.
3. **Coûts.** Les stratégies ne contiennent que le spread et le swap du testeur (commission à 0). L'achat-conservation est supposé sans frais, ce qui avantage l'or (un ETF coûte environ 0,4 % par an).
4. **Un seul actif, une seule période.** L'or a presque quadruplé sur la période, ce qui est favorable à l'achat-conservation.
5. Ticks synthétiques pour les backtests (voir les README des stratégies).

## Prochaines étapes

- Refaire la comparaison avec des données de prix journalières propres (drawdown de l'or réel).
- Tester le mélange avec des poids optimisés en walk-forward, pas en échantillon complet.
- Ajouter les coûts de commission aux stratégies.
