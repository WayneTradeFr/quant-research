# Comparaison avec l'achat-conservation de l'or

> En résumé — Benchmark des deux stratégies de suivi de tendance publiées contre l'achat-conservation de l'or (non léveré, février 2016 à octobre 2026, données mensuelles). Aucune stratégie ne bat l'achat-conservation sur le rendement total, mais leur véritable intérêt réside surtout dans la diversification.

## Pourquoi cette comparaison

Une stratégie sur l'or doit être jugée contre la solution la plus simple : acheter l'or et ne rien faire.

Sur la période, le métal est passé d'environ 1 090 à 4 000 USD, soit un gain d'environ 3,7 fois. L'achat-conservation est donc un benchmark très solide pour évaluer si une stratégie de timing ajoute réellement de la valeur.

## Méthode

- Période commune : février 2016 à octobre 2026
- Fréquence : rendements mensuels (128 mois)
- Benchmark : achat-conservation de l'or, sans levier
- Reconstruction de la position : à partir des prix de transactions des backtests (environ 23 000 points, au moins 20 points par mois)
- Stratégies comparées :
  - Donchian M30
  - SuperTrend M30
  - AMRM avec SL = TP (voir le [post-mortem](../amrm-postmortem/README.md))
- Analyse :
  - bêta et alpha par régression des rendements mensuels de chaque stratégie sur ceux de l'or

## Résultats

| Stratégie | Capital final (base 100) | Rendement annualisé | Volatilité | Sharpe | Drawdown max (mensuel) | Corrélation avec l'or |
|---|---:|---:|---:|---:|---:|---:|
| Or, achat-conservation | 324 | 11,7 % | 15,7 % | 0,78 | 24,1 % | 1,00 |
| Donchian | 298 | 10,8 % | 13,7 % | 0,82 | 20,7 % | 0,31 |
| SuperTrend | 273 | 9,9 % | 13,1 % | 0,78 | 18,8 % | 0,06 |
| AMRM (SL = TP) | 124 | 2,1 % | 10,9 % | 0,24 | 37,8 % | 0,02 |

| Stratégie | Bêta | Alpha annualisé | t-stat de l'alpha |
|---|---:|---:|---:|
| Donchian | 0,27 | +7,9 % | 1,9 |
| SuperTrend | 0,05 | +9,7 % | 2,3 |

### Rendement annuel

| Année | Or | Donchian | SuperTrend | AMRM (SL = TP) |
|---|---:|---:|---:|---:|
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

![Capital normalisé](equity_comparison.png)

## Mélanges avec l'or

| Portefeuille | Rendement annualisé | Sharpe | Drawdown max (mensuel) |
|---|---:|---:|---:|
| 100 % or | 11,7 % | 0,78 | 24,1 % |
| 50 % or + 50 % Donchian | 11,6 % | 0,99 | 11,2 % |
| 50 % or + 50 % SuperTrend | 11,3 % | 1,07 | 11,6 % |
| Donchian + SuperTrend (50/50) | 10,7 % | 1,03 | 16,5 % |
| Un tiers chacun : or, Donchian, SuperTrend | 11,3 % | 1,16 | 10,3 % |

## Lecture

- Les stratégies seules ne battent pas l'or :
  - Donchian : 10,8 % contre 11,7 %
  - SuperTrend : 9,9 % contre 11,7 %
  - Sharpe comparable ou légèrement inférieur
- Leur vrai intérêt est la diversification :
  - corrélation faible avec l'or
  - les mélanges 50/50 gardent presque le même rendement tout en réduisant le drawdown
- L'AMRM n'apporte rien dans ce cadre :
  - rendement de 2,1 %
  - Sharpe de 0,24
  - drawdown de 37,8 %
  - cohérent avec le post-mortem
- La corrélation entre Donchian et SuperTrend est faible : 0,21

## Limites

1. Alpha fragile  
   Les t-stats de 1,9 et 2,3 sont marginaux sur 128 mois, et les paramètres ont été optimisés sur la période. L'alpha réel est probablement plus faible.

2. Données approximatives  
   L'or est reconstruit à partir de prix de transactions et échantillonné au mois : son drawdown est sous-estimé. Pour les stratégies, le solde ne compte que le solde du compte en fin de mois et ne reflète pas tout le détail des entrées/sorties.

3. Coûts  
   Les stratégies ne comprennent que le spread et le swap du testeur (commission à 0). L'achat-conservation est supposé sans frais, ce qui avantage l'or. Un ETF sur l'or coûte typiquement environ 0,4 % par an.

4. Une seule période, un seul actif  
   L'or a presque quadruplé sur la période, ce qui est favorable à l'achat-conservation.

5. Ticks synthétiques pour les backtests  
   Voir les README des stratégies respectives.

## Prochaines étapes

- Refaire la comparaison avec des données de prix journalières propres pour mesurer le vrai drawdown de l'or
- Tester les mélanges avec des pondérations optimisées en walk-forward, pas sur l'ensemble de la période
- Ajouter les coûts de commission aux stratégies
