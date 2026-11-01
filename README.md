# quant-research

Recherche systématique en trading : stratégies, résultats backtestés, méthodologie de validation et limites explicites.

> Systematic trading research on XAUUSD (MQL5). Each strategy is published with tested parameters, in-sample/out-of-sample splits, cost breakdown and an explicit limitations section.

## Objectif du projet

Ce dépôt vise à documenter des idées de trading de façon rigoureuse :

- hypothèse de marché claire avant l'implémentation ;
- séparation en période d'optimisation et de validation ;
- résultats accompagnés de leurs limites ;
- coût du trading et qualité des données étudiés ;
- publication des réglages testés pour permettre une lecture critique.

## Principes de recherche

- Hypothèse d'abord : chaque stratégie part d'une logique de marché explicite.
- IS / OOS : optimisation puis validation hors échantillon.
- Coûts inclus : spread, swap et conditions de test documentées.
- Limites assumées : concentration des gains, drawdown, dépendance au régime de marché.
- Transparence : résultats présentés tels quels, avec leurs biais et leurs frictions.

## Stratégies publiées

| Famille | Stratégie | Période / instrument | Statut |
|---|---|---|---|
| Trend following | [Donchian TrendFollow (XAUUSD M30)](strategies/trend/donchian/README.md) | XAUUSD, M30 | Publié |
| Trend following | [SuperTrend + pullback (XAUUSD M30)](strategies/trend/supertrend/README.md) | XAUUSD, M30 | Publié |
| Trend following | [ADX/DMI close-only (XAUUSD H1)](strategies/trend/adx-dmi/README.md) | XAUUSD, H1 | Publié |
| Analyse | [AMRM : post-mortem d'un faux avantage](research/amrm-postmortem/README.md) | XAUUSD, H1 | Publié |
| Benchmark | [Comparaison avec l'achat-conservation de l'or](research/buy-and-hold-benchmark/README.md) | XAUUSD / or | Publié |

## Structure du dépôt

```text
quant-research/
├── README.md
├── strategies/
│   └── trend/
│       ├── donchian/
│       │   ├── Donchian_TrendFollow_EA.mq5
│       │   ├── Donchian_TF_M30_tested.set
│       │   ├── README.md
│       │   ├── annual_pnl.svg
│       │   └── equity.svg
│       ├── supertrend/
│       │   ├── SuperTrend_ER_EA_v3.mq5
│       │   ├── SuperTrend_M30_tested.set
│       │   ├── README.md
│       │   ├── annual_returns.svg
│       │   └── equity.svg
│       └── adx-dmi/
│           ├── ADX_DMI_EA.mq5
│           ├── README.md
│           ├── validation.md
│           ├── equity_curve.png
│           ├── yearly_returns.png
│           └── yearly_returns.csv
├── research/
│   ├── amrm-postmortem/
│   │   ├── AMRM_Quant_Manhattan_V2_1.mq5
│   │   ├── README.md
│   │   ├── annual_returns_compare.svg
│   │   ├── set_B_partial_target1R.set
│   │   └── set_C_symmetric_SL1_TP1.set
│   └── buy-and-hold-benchmark/
│       ├── README.md
│       └── equity_comparison.svg
└── LICENSE
```

## Comment lire les résultats

- Les résultats sont des backtests, pas des garanties de performance futures.
- L'objectif n'est pas de "prouver" une stratégie, mais d'identifier des idées intéressantes et leurs failings.
- Les meilleurs résultats peuvent être le produit de données, règles de sortie ou filtres qui ne se maintiennent pas hors échantillon.
- Les analyses incluent des coûts et des limites ; il faut toujours relire le README de la stratégie concernée avant d'en conclure quoi que ce soit.

## Auteur

Wayne — étudiant en trading systématique, avec un intérêt particulier pour la recherche quantitative sur les marchés financiers et les méthodes de validation robustes.

Outils principaux : MQL5, Python, C++ (apprentissage continu).

## À retenir

Ce dépôt ne cherche pas à vendre un signal miracle. Il documente des idées de recherche, leurs conditions de test, et les limites qui les affectent.
