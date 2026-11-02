# Notes de validation

## Protocole

1. **Référence** avec les règles ADX/DMI classiques (entrée ADX > 25 en hausse, écart DI de 5, stop 1,5 ATR). Net +397 000 USD sur 2016-2026, profit factor 1,11, drawdown d'environ 22 %.
2. **Optimisation par grille** sur 2016-2022 (entrée ADX, sortie ADX, multiple du stop, multiple du Chandelier), critère `OnTester` : Sharpe × √(nombre de trades) / (1 + drawdown equity % / 10), avec un minimum de 100 trades et un profit factor > 1.
3. **Test en avant** sur 2023 et après, paramètres figés.
4. **Contrôle du plateau** : privilégier les zones où les valeurs voisines donnent des scores proches, jamais un pic isolé.
5. **Ablation** de chaque filtre de risque, en IS et en OOS.

## Constats

### Paysage des paramètres
- Multiple du Chandelier : plat entre 1,5 et 3,0 sur les deux périodes, donc fixé à 2,5.
- Multiple du stop : des stops plus larges baissent à la fois le profit et le drawdown (un réglage du risque plutôt qu'un changement d'avantage).
- Entrée ADX : pic IS à 30 (voisins 28 et 32 bien plus faibles) qui n'a pas survécu au test en avant, où 38-40 semblaient meilleurs. Pas de plateau stable : un seuil bas (20) a été choisi pour le volume, et le drawdown est géré par le risque par trade.

### Analyse par heure
- Les stops se concentrent entre 15h et 17h (heure serveur, session américaine) : les positions ouvertes le matin sont stoppées par la volatilité américaine, tandis que les gagnantes sortent la nuit. Une partie de l'effet est mécanique (effet de sélection) et ne prouve pas que la session américaine cause les pertes.
- Les entrées entre 13h et 17h étaient rentables sur les deux périodes : les bloquer aurait retiré du profit sans réduire le drawdown. Les filtres horaires n'ont pas été retenus.

### Ablation (filtres de risque désactivés de façon cumulative)

| Test | Profit IS / drawdown solde | Profit OOS / drawdown solde |
|---|---|---|
| Base | +391 k / 15,5 % | +68 k / 15,8 % |
| Sans réduction du risque en drawdown | +836 k / 26,1 % | +135 k / 26,5 % |
| + sans plafond journalier | +824 k / 26,1 % | +130 k / 26,5 % |
| + sans filtre de volatilité | +821 k / 26,2 % | +130 k / 26,5 % |
| + sans break-even | +780 k / 27,5 % | +143 k / 26,5 % |
| + sans filtre de session | +326 k / 34,1 % | +108 k / 30,2 % |

Lecture : le filtre de volatilité ne s'est jamais déclenché en OOS (résultat identique), le break-even est neutre, le plafond journalier aide légèrement, et le filtre de session est le seul qui change la qualité (profit factor et Sharpe) et pas seulement le niveau de risque.

### Dégradation en OOS
Normalisé par le solde, le rendement annualisé est d'environ 25 % sur 2016-2022 contre environ 13,5 % depuis 2023 (profit factor 1,30 contre 1,19). Les attentes doivent s'appuyer sur les chiffres OOS.

## Prochaines étapes
- Essai en temps réel sur démo avec les paramètres finaux (spread, glissement, exécution).
- Mêmes paramètres sur un autre flux de données ou sur le contrat MGC avec commissions réelles.
- Test de stabilité : décaler chaque paramètre clé d'un pas et vérifier la stabilité.

## Note sur les niveaux de risque
Les chiffres d'optimisation et d'ablation ci-dessus ont été obtenus à 1 % de risque par trade. Les runs finaux du README comparent 0,5 %, 1 % et 1,5 % : profit et drawdown augmentent avec le risque, le profit factor reste entre 1,18 et 1,20.
