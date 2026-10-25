# quant-research

Recherche en trading systématique : stratégies, méthodologie de validation et résultats présentés **tels quels, limites comprises**.

> **EN summary** — Systematic trading research on XAUUSD (MQL5). Each strategy comes with its tested parameters, in-sample / out-of-sample split, cost breakdown and an explicit limitations section. The goal is to show methodology (hypothesis, validation, honest failure analysis), not to sell a backtest.

## Principes

- **Hypothèse d'abord** : chaque stratégie part d'une idée de marché explicite (momentum, retour à la moyenne, etc.).
- **Séparation IS / OOS** : optimisation sur une période, validation sur une autre, puis test sur l'historique complet.
- **Coûts inclus** : spread, swap, commission documentés séparément.
- **Limites assumées** : concentration des gains, drawdown, dépendance au régime de marché.

## Contenu

| Famille | Stratégie | Statut |
|---|---|---|
| Trend following | [Donchian TrendFollow (XAUUSD M30)](strategies/trend/donchian/README.md) | Publié |
| Trend following | [SuperTrend + pullback (XAUUSD M30)](strategies/trend/supertrend/README.md) | Publié |
| Analyse | [AMRM : post-mortem d'un faux avantage](research/amrm-postmortem/README.md) | Publié |

## Structure

```
strategies/
└── trend/
    ├── donchian/     # code .mq5, inputs testés (.set), graphiques, README
    └── supertrend/   # idem
research/
└── amrm-postmortem/  # analyse d'un backtest dont l'avantage était un artefact
```

## Auteur

Wayne — étudiant, trading systématique, objectif : marchés de capitaux quantitatifs (market making / HFT). Outils : MQL5, Python, C++ (en apprentissage).
