1| # Comparaison avec l'achat-conservation de l'or
2| 
3| > **EN summary** — Benchmark of the two published trend-following strategies against buy-and-hold gold (unlevered, Feb 2016 – Oct 2026, monthly data). Neither strategy beats buy-and-hold on return, but they improve diversification and lower drawdown.
4| 
5| ## Pourquoi cette comparaison
6| 
7| Une stratégie sur l'or doit être jugée contre la solution la plus simple : acheter l'or et ne rien faire. Sur la période, l'or est passé d'environ 1 090 à 4 000 USD (×3,7). Une stratégie qui ne bat pas le simple achat-conservation doit être évaluée en termes de diversification, pas seulement de performance brute.
8| 
9| ## Méthode
10| 
11| - Période commune : **février 2016 - octobre 2026**, rendements **mensuels** (128 mois).
12| - Achat-conservation : une position longue sans levier, reconstruite à partir des prix des transactions des backtests (environ 23 000 points, au moins 20 par mois).
13| - Stratégies : solde du compte en fin de mois (Donchian M30 et SuperTrend M30 publiés ; AMRM avec SL = TP, voir le [post-mortem](../amrm-postmortem/README.md)).
14| - Bêta et alpha : régression des rendements mensuels de chaque stratégie sur ceux de l'or.
15| 
16| ## Résultats
17| 
18| | | Capital final (base 100) | Rendement annualisé | Volatilité | Sharpe | Drawdown max (mensuel) | Corrélation avec l'or |
19| |---|---|---|---|---|---|---|
20| | Or, achat-conservation | 324 | 11,7 % | 15,7 % | 0,78 | 24,1 % | 1,00 |
21| | Donchian | 298 | 10,8 % | 13,7 % | 0,82 | 20,7 % | 0,31 |
22| | SuperTrend | 273 | 9,9 % | 13,1 % | 0,78 | 18,8 % | 0,06 |
23| | AMRM (SL = TP) | 124 | 2,1 % | 10,9 % | 0,24 | 37,8 % | 0,02 |
24| 
25| | | Bêta | Alpha annualisé | t-stat de l'alpha |
26| |---|---|---|---|
27| | Donchian | 0,27 | +7,9 % | 1,9 |
28| | SuperTrend | 0,05 | +9,7 % | 2,3 |
29| 
30| ### Rendement annuel
31| 
32| | Année | Or | Donchian | SuperTrend | AMRM (SL = TP) |
33| |---|---|---|---|---|
34| | 2016 | -6,2 % | +19,4 % | -3,0 % | +22,8 % |
35| | 2017 | +12,8 % | +27,0 % | +5,0 % | +18,6 % |
36| | 2018 | -1,8 % | +9,6 % | -8,6 % | -4,1 % |
37| | 2019 | +18,8 % | +15,8 % | +5,6 % | -9,7 % |
38| | 2020 | +24,6 % | +16,4 % | +28,9 % | +1,5 % |
39| | 2021 | -3,5 % | +3,9 % | +33,9 % | +9,0 % |
40| | 2022 | -0,7 % | +2,6 % | -3,4 % | -10,5 % |
41| | 2023 | +13,4 % | -14,0 % | +17,8 % | -10,8 % |
42| | 2024 | +26,5 % | +4,5 % | +8,4 % | -5,4 % |
43| | 2025 | +65,5 % | +20,0 % | +12,5 % | +9,7 % |
44| | 2026 (jusqu'en oct.) | -7,3 % | +15,0 % | +17,9 % | +10,4 % |
45| 
46| ![Capital normalisé](equity_comparison.png)
47| 
48| ### Mélanges avec l'or
49| 
50| | Portefeuille | Rendement annualisé | Sharpe | Drawdown max (mensuel) |
51| |---|---|---|---|
52| | 100 % or | 11,7 % | 0,78 | 24,1 % |
53| | 50 % or + 50 % Donchian | 11,6 % | 0,99 | 11,2 % |
54| | 50 % or + 50 % SuperTrend | 11,3 % | 1,07 | 11,6 % |
55| | Donchian + SuperTrend (50/50) | 10,7 % | 1,03 | 16,5 % |
56| | Un tiers chacun : or, Donchian, SuperTrend | 11,3 % | 1,16 | 10,3 % |
57| 
58| ## Lecture
59| 
60| - **Seules, les stratégies ne battent pas l'or** : ni en rendement (10,8 % et 9,9 % contre 11,7 %), ni en Sharpe (0,82 et 0,78 contre 0,78). En 2025, année à +65,5 % pour l'or, elles font +20,0 % et +12,5 %.
61| - **Leur intérêt est la diversification** : corrélation de 0,31 et 0,06 avec l'or. Mélangées à parts égales avec l'or, elles gardent presque le même rendement avec environ la moitié du drawdown.
62| - **L'AMRM n'apporte rien** : rendement de 2,1 %, Sharpe de 0,24 et drawdown de 37,8 %, conforme au post-mortem.
63| - Corrélation entre le Donchian et le SuperTrend : 0,21.
64| 
65| ## Limites
66| 
67| 1. **Alpha fragile.** Les t-stats de 1,9 et 2,3 sont marginaux sur 128 mois, et les paramètres ont été optimisés sur la période : l'alpha réel est probablement plus faible.
68| 2. **Données approximatives.** L'or est reconstruit à partir de prix de transactions et échantillonné au mois : son drawdown est sous-estimé. Pour les stratégies, le solde ne compte que les transactions de backtest et ignore les coûts de friction de marché.
69| 3. **Coûts.** Les stratégies ne contiennent que le spread et le swap du testeur (commission à 0). L'achat-conservation est supposé sans frais, ce qui avantage l'or (un ETF coûte environ 0,4 %/an).
70| 4. **Un seul actif, une seule période.** L'or a presque quadruplé sur la période, ce qui est favorable à l'achat-conservation.
71| 5. Ticks synthétiques pour les backtests (voir les README des stratégies).
72| 
73| ## Prochaines étapes
74| 
75| - Refaire la comparaison avec des données de prix journalières propres (drawdown de l'or réel).
76| - Tester le mélange avec des poids optimisés en walk-forward, pas en échantillon complet.
77| - Ajouter les coûts de commission aux stratégies.
78| 