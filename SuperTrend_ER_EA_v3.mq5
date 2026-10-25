//+------------------------------------------------------------------+
//|  SuperTrend_ER_EA_v3.mq5                                         |
//|  v3 = v2 + 3 modules optionnels (tous désactivés par défaut)     |
//|                                                                  |
//|  BASE (identique v2)                                             |
//|   - SuperTrend sur InpSignalTF (M30), stop-and-reverse sur flip  |
//|   - SL = ligne SuperTrend, trailing sur la ligne                 |
//|   - filtres optionnels : ER / ADX, DEMA (TF signal)              |
//|   - entrée immédiate ou sur 1re clôture M5 confirmant le flip    |
//|                                                                  |
//|  MODULE 1 - CONTRÔLE DU RISQUE                                   |
//|   - InpMinLots = 0 : plus de plancher de taille, le risque réel  |
//|     par trade vaut InpRiskPct (sinon le plancher le fausse)      |
//|   - InpUseDDScaling : le risque des NOUVEAUX trades est réduit   |
//|     linéairement quand l'equity est sous son sommet :            |
//|     x1 à InpDDStart %  ->  x InpDDMinMult à InpDDFull %          |
//|                                                                  |
//|  MODULE 2 - PYRAMIDAGE                                           |
//|   - après l'entrée, ajout d'une position à chaque palier de      |
//|     +InpPyramidStepR x R (R = distance entrée -> SL initial),    |
//|     max InpPyramidMax ajouts, risque InpPyramidRiskPct par ajout |
//|     (calculé sur la distance prix -> SL actuel = ligne ST)       |
//|   - InpPyramidNeedBE : n'ajouter que si le SL est au moins au    |
//|     point d'entrée (position initiale sans risque)               |
//|   - netting (futures) : les ajouts s'additionnent dans l'unique  |
//|     position ; hedging (CFD) : positions séparées, même SL       |
//|                                                                  |
//|  MODULE 3 - RÉ-ENTRÉE DANS LA TENDANCE                           |
//|   - à plat, SuperTrend inchangée (pas de flip), filtres OK :     |
//|     entrée si la dernière clôture du TF signal dépasse le plus   |
//|     haut (long) / plus bas (short) des InpReentryLookback barres |
//|     précédentes. Max InpMaxReentries par tendance.               |
//|                                                                  |
//|  MODULE 4 - PAUSE EN RANGE (v3.10)                               |
//|   - InpUseRangePause : pas de NOUVELLE entrée (flip ou          |
//|     ré-entrée) quand le range est détecté. Les positions        |
//|     ouvertes ne sont pas touchées (trailing / sortie normaux).  |
//|   - range = toutes les conditions activées sont vraies :        |
//|       flips >= InpRangeMinFlips sur InpRangeLookback barres,    |
//|       ligne plate >= InpRangeFlatBars barres avant la barre,    |
//|       ER < InpRangeERMax  (0 = condition ignorée)               |
//|                                                                  |
//|  FILTRE RÉGRESSION LINÉAIRE (v3.20) - alternative à la DEMA      |
//|   - InpUseLinReg : pente de la régression linéaire des          |
//|     InpLRLength dernières clôtures du TF signal. Longs si pente |
//|     > 0, shorts si pente < 0. InpLRMinR : |R de Pearson| mini.  |
//|   - exclusif avec la DEMA (mettre InpDEMAPeriod = 0)            |
//|                                                                  |
//|  ENTRÉE SUR PULLBACK (v3.30) - alternative à l'entrée M5         |
//|   - InpUsePullbackEntry : après un flip, on n'entre pas tout de  |
//|     suite : on attend un rebond de InpPullbackATR x ATR depuis   |
//|     l'extrême du flip, puis une bougie de reprise (voir          |
//|     HandlePullback). SL inchangé = ligne SuperTrend, donc        |
//|     distance au SL plus courte et taille plus grande à risque    |
//|     égal. Exclusif avec InpUseM5Entry.                           |
//|                                                                  |
//|  PYRAMIDAGE SUR REPLI (v3.40)                                    |
//|   - InpPyramidOnPullback : remplace les paliers en R. On ajoute  |
//|     quand le trade gagnant (déjà InpPyramidMinProfitR x R de     |
//|     profit) fait un repli de InpPyramidPullbackATR x ATR puis    |
//|     repart (bougie du TF d'entrée dans le sens du trade).        |
//|     InpPyramidMax, InpPyramidRiskPct et InpPyramidNeedBE         |
//|     restent valables ; InpPyramidStepR n'est plus utilisé.       |
//|                                                                  |
//|  Pour retrouver la v2 : modules off et InpMinLots = 1.0          |
//+------------------------------------------------------------------+
#property copyright "SuperTrend ER EA v3"
#property version   "3.40"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_REGIME_FILTER
{
   FILTER_NONE   = 0,  // Aucun (SuperTrend nu)
   FILTER_ER     = 1,  // Efficiency Ratio
   FILTER_ADX    = 2,  // ADX
   FILTER_ER_ADX = 3   // ER et ADX
};

enum ENUM_ST_SOURCE
{
   ST_SRC_HL2   = 0,   // (High+Low)/2
   ST_SRC_CLOSE = 1    // Close
};

input group "Timeframes"
input ENUM_TIMEFRAMES InpSignalTF     = PERIOD_M30;    // TF du signal SuperTrend
input ENUM_TIMEFRAMES InpEntryTF      = PERIOD_M5;     // TF d'entrée / de suivi (M5)

input group "SuperTrend"
input int             InpATRPeriod    = 25;            // Période ATR (Wilder)
input double          InpMult         = 3.0;           // Multiplicateur ATR
input ENUM_ST_SOURCE  InpSource       = ST_SRC_CLOSE;  // Source

input group "Filtre de régime (ER / ADX)"
input ENUM_REGIME_FILTER InpFilter    = FILTER_NONE;   // Filtre
input int             InpERPeriod     = 20;            // Période ER
input double          InpERThreshold  = 0.30;          // Seuil ER (entrée si ER > seuil)
input int             InpADXPeriod    = 14;            // Période ADX
input double          InpADXThreshold = 22.0;          // Seuil ADX (entrée si ADX > seuil)

input group "Filtre de tendance DEMA (TF signal)"
input int             InpDEMAPeriod   = 250;           // Période DEMA (0 = désactivé)

input group "Filtre de tendance régression linéaire (ALTERNATIVE à la DEMA)"
input bool            InpUseLinReg    = false;         // Activer (mettre InpDEMAPeriod = 0)
input int             InpLRLength     = 100;           // Longueur de la régression (barres)
input double          InpLRMinR       = 0.0;           // |R de Pearson| minimum (0 = ignoré)

input group "Entrée M5"
input bool            InpUseM5Entry   = false;          // Entrer sur clôture M5 confirmant le flip
input int             InpMaxWaitM5    = 7;             // Nb max de bougies M5 à attendre
input bool            InpEnterOnTimeout = false;       // Entrer quand même si pas de confirmation

input group "Entrée sur pullback (ALTERNATIVE à l'entrée M5)"
input bool            InpUsePullbackEntry = true;     // Entrer sur le rebond après le flip (exclusif avec M5)
input double          InpPullbackATR      = 0.5;       // Rebond requis (x ATR du TF signal)
input int             InpPullbackMaxBars  = 12;        // Attente max (en barres du TF signal)

input group "Direction"
input bool            InpAllowLong    = true;          // Autoriser les longs
input bool            InpAllowShort   = true;          // Autoriser les shorts

input group "Risque (module 1)"
input double          InpRiskPct      = 0.5;           // Risque par trade (% du solde)
input double          InpMinLots      = 0.0;           // Plancher de taille (0 = aucun)
input double          InpMaxLots      = 10.0;          // Taille max
input double          InpTP_R         = 0.0;           // TP en multiple de R (0 = pas de TP)
input bool            InpUseDDScaling = false;         // Réduire le risque en drawdown
input double          InpDDStart      = 2.0;          // DD (%) où la réduction commence
input double          InpDDFull       = 5.0;          // DD (%) où la réduction est maximale
input double          InpDDMinMult    = 0.25;          // Multiplicateur de risque minimal

input group "Pyramidage (module 2)"
input bool            InpUsePyramid   = true;         // Activer le pyramidage
input int             InpPyramidMax   = 3;             // Nb max d'ajouts
input double          InpPyramidStepR = 2.0;           // Palier d'ajout (multiple de R)
input double          InpPyramidRiskPct = 0.25;        // Risque par ajout (% du solde)
input bool            InpPyramidNeedBE  = true;       // Ajouter seulement si SL au point d'entrée ou mieux
input bool            InpPyramidOnPullback = true;    // Ajouter sur repli du trade gagnant (remplace les paliers en R)
input double          InpPyramidPullbackATR = 0.5;     // Repli requis (x ATR du TF signal) avant l'ajout
input double          InpPyramidMinProfitR  = 2.0;     // Profit latent mini (en R) pour autoriser un ajout

input group "Ré-entrée (module 3)"
input bool            InpUseReentry   = false;         // Activer la ré-entrée dans la tendance
input int             InpReentryLookback = 21;         // Nb de barres du plus haut / plus bas
input int             InpMaxReentries = 1;             // Max de ré-entrées par tendance

input group "Pause en range (module 4)"
input bool            InpUseRangePause = false;        // Bloquer les nouvelles entrées en range
input int             InpRangeLookback = 40;           // Fenêtre (barres) pour compter les flips
input int             InpRangeMinFlips = 2;            // Flips mini dans la fenêtre (0 = ignoré)
input int             InpRangeFlatBars = 0;            // SuperTrend plate depuis N barres mini (0 = ignoré)
input double          InpRangeERMax    = 0.0;          // ER maximum : range si ER < valeur (0 = ignoré)

input group "Exécution"
input long            InpMagic        = 20261016;      // Magic number
input int             InpDeviation    = 10;            // Déviation max (points)
input int             InpWarmupBars   = 800;           // Barres d'historique pour recalcul SuperTrend

input group "Critère d'optimisation (OnTester) - à ne PAS optimiser"
input int             InpOptMinTrades = 200;           // Nb min de trades (sinon rejeté)
input double          InpOptMinPF     = 1.10;          // PF min (sinon score x0.5)

CTrade   g_trade;
int      g_hADX  = INVALID_HANDLE;
int      g_hDEMA = INVALID_HANDLE;

datetime g_lastSigBar   = 0;
datetime g_lastEntryBar = 0;

// signal en attente de confirmation M5
int      g_pendDir  = 0;
double   g_pendLine = 0.0;
int      g_pendBars = 0;

// état du mode pullback
double   g_pendExtreme   = 0.0;   // plus bas (short) / plus haut (long) depuis le flip
double   g_pendATR       = 0.0;   // ATR du TF signal au moment du flip
int      g_pendPhase     = 0;     // 0 = attente du rebond, 1 = rebond atteint, attente de la reprise
double   g_pendPrevClose = 0.0;   // clôture de la bougie d'entrée précédente
int      g_pendMaxBars   = 0;     // nb max de bougies du TF d'entrée

// groupe de trades courant (pyramidage)
int      g_grpDir      = 0;
double   g_grpEntry    = 0.0;
double   g_grpRiskDist = 0.0;
int      g_grpAdds     = 0;

// pyramidage sur repli
double   g_grpExtreme   = 0.0;   // plus haut (long) / plus bas (short) depuis l'entrée ou le dernier ajout
int      g_pyrPhase     = 0;     // 0 = suivi de l'extrême, 1 = repli atteint, attente de la reprise
double   g_pyrPrevClose = 0.0;   // clôture de la bougie d'entrée précédente
double   g_atrSig       = 0.0;   // dernier ATR du TF signal

// ré-entrées dans la tendance courante
int      g_reentries   = 0;

// sommet d'equity (réduction du risque en drawdown)
double   g_peakEq      = 0.0;

// compteurs (journal)
int      g_cFlips = 0, g_cBlockedFilter = 0, g_cBlockedDEMA = 0;
int      g_cArmed = 0, g_cConfirmed = 0, g_cTimeoutSkip = 0, g_cTimeoutEnter = 0, g_cCancelledFlip = 0;
int      g_cPBArmed = 0, g_cPBEntered = 0, g_cPBTimeout = 0, g_cPBInvalid = 0;
int      g_cAdds = 0, g_cReentry = 0, g_cBlockedRange = 0, g_cBlockedLR = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpATRPeriod < 2 || InpERPeriod < 2 || InpMult <= 0.0 || InpWarmupBars < 200
      || InpMinLots < 0.0 || InpMinLots > InpMaxLots || InpMaxWaitM5 < 1 || InpDEMAPeriod < 0
      || InpRiskPct <= 0.0 || InpReentryLookback < 2 || InpMaxReentries < 0
      || InpPyramidMax < 0 || InpPyramidStepR <= 0.0 || InpPyramidRiskPct <= 0.0
      || InpDDFull <= InpDDStart || InpDDMinMult <= 0.0 || InpDDMinMult > 1.0)
   {
      Print("Paramètres invalides.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpUseLinReg && (InpDEMAPeriod > 0 || InpLRLength < 10 || InpLRMinR < 0.0 || InpLRMinR > 1.0))
   {
      Print("Régression linéaire : mets InpDEMAPeriod = 0 (DEMA OU régression, pas les deux), InpLRLength >= 10 et 0 <= InpLRMinR <= 1.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpPyramidOnPullback && (InpPyramidPullbackATR <= 0.0 || InpPyramidMinProfitR < 0.0))
   {
      Print("Pyramidage sur repli : InpPyramidPullbackATR doit être > 0 et InpPyramidMinProfitR >= 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpUsePullbackEntry && (InpUseM5Entry || InpPullbackATR <= 0.0 || InpPullbackMaxBars < 1))
   {
      Print("Pullback : désactive InpUseM5Entry (modes exclusifs), InpPullbackATR > 0 et InpPullbackMaxBars >= 1.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if((InpUseM5Entry || InpUsePyramid || InpUsePullbackEntry) && PeriodSeconds(InpEntryTF) > PeriodSeconds(InpSignalTF))
   {
      Print("Le TF d'entrée doit être inférieur ou égal au TF du signal.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(InpFilter == FILTER_ADX || InpFilter == FILTER_ER_ADX)
   {
      g_hADX = iADX(_Symbol, InpSignalTF, InpADXPeriod);
      if(g_hADX == INVALID_HANDLE) { Print("Échec création handle ADX."); return INIT_FAILED; }
   }
   if(InpDEMAPeriod > 0)
   {
      g_hDEMA = iDEMA(_Symbol, InpSignalTF, InpDEMAPeriod, 0, PRICE_CLOSE);
      if(g_hDEMA == INVALID_HANDLE) { Print("Échec création handle DEMA."); return INIT_FAILED; }
   }

   g_peakEq = AccountInfoDouble(ACCOUNT_EQUITY);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_hADX  != INVALID_HANDLE) IndicatorRelease(g_hADX);
   if(g_hDEMA != INVALID_HANDLE) IndicatorRelease(g_hDEMA);
   PrintFormat("STATS flips=%d | bloqués filtre=%d | bloqués DEMA=%d | armés M5=%d | confirmés=%d | timeout annulés=%d | timeout entrés=%d | annulés (flip inverse)=%d | ajouts pyramide=%d | ré-entrées=%d | bloqués range=%d | bloqués régression=%d | pullback armés=%d entrés=%d timeout=%d invalidés=%d",
               g_cFlips, g_cBlockedFilter, g_cBlockedDEMA, g_cArmed, g_cConfirmed,
               g_cTimeoutSkip, g_cTimeoutEnter, g_cCancelledFlip, g_cAdds, g_cReentry, g_cBlockedRange, g_cBlockedLR, g_cPBArmed, g_cPBEntered, g_cPBTimeout, g_cPBInvalid);
}

//+------------------------------------------------------------------+
double RoundTick(double p)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return NormalizeDouble(p, _Digits);
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
}

//+------------------------------------------------------------------+
//| Recalcule la SuperTrend depuis l'historique du TF signal         |
//| Barre 0 = en formation (ignorée), barre 1 = dernière fermée.     |
//| Sorties supplémentaires pour la ré-entrée : close1, hiPrev,      |
//| loPrev (plus haut / plus bas des InpReentryLookback barres       |
//| précédant la barre 1).                                           |
//+------------------------------------------------------------------+
bool ComputeSignals(int &trend1, int &trend2, double &line1, double &er,
                    double &close1, double &hiPrev, double &loPrev,
                    int &flipsRecent, int &flatPrev, double &atrOut)
{
   atrOut      = 0.0; // ATR (Wilder) du TF signal à la barre fermée
   flipsRecent = 0;   // flips dans les InpRangeLookback barres AVANT la barre fermée
   flatPrev    = 0;   // nb de barres consécutives où la ligne était plate, avant la barre fermée
   int flatCnt = 0;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, InpSignalTF, 0, InpWarmupBars, r);
   if(n < InpATRPeriod + InpERPeriod + InpReentryLookback + 50) return false;

   int last = n - 2;                            // dernière barre fermée

   double atr = 0.0, sumTR = 0.0;
   double up = 0.0, dn = 0.0;
   int    trCur = 1, trPrev = 1;

   for(int i = 1; i <= last; i++)
   {
      if(i == last) flatPrev = flatCnt;          // état de la ligne avant la barre fermée

      double trv = MathMax(r[i].high - r[i].low,
                   MathMax(MathAbs(r[i].high - r[i-1].close),
                           MathAbs(r[i].low  - r[i-1].close)));

      if(i <= InpATRPeriod)
      {
         sumTR += trv;
         if(i < InpATRPeriod) continue;
         atr = sumTR / InpATRPeriod;
      }
      else
         atr = (atr * (InpATRPeriod - 1) + trv) / InpATRPeriod;

      double src = (InpSource == ST_SRC_HL2) ? (r[i].high + r[i].low) / 2.0 : r[i].close;
      double nUp = src - InpMult * atr;
      double nDn = src + InpMult * atr;

      if(i == InpATRPeriod)
      {
         up = nUp; dn = nDn; trCur = 1; trPrev = 1;
      }
      else
      {
         double pc  = r[i-1].close;
         double oUp = up, oDn = dn;
         if(pc > oUp) nUp = MathMax(nUp, oUp);
         if(pc < oDn) nDn = MathMin(nDn, oDn);

         int tNew = trCur;
         if(trCur == -1 && r[i].close > oDn)      tNew = 1;
         else if(trCur == 1 && r[i].close < oUp)  tNew = -1;

         bool flipped = (tNew != trCur);
         bool flat    = (tNew == 1) ? (nUp == oUp) : (nDn == oDn);   // ligne inchangée

         trPrev = trCur;
         trCur  = tNew;
         up = nUp; dn = nDn;

         if(flipped)
         {
            flatCnt = 0;
            if(i >= last - InpRangeLookback && i < last) flipsRecent++;
         }
         else if(flat) flatCnt++;
         else          flatCnt = 0;
      }
   }

   trend1 = trCur;
   trend2 = trPrev;
   line1  = (trCur == 1) ? up : dn;

   er = 0.0;
   if(last - InpERPeriod >= 1)
   {
      double change = MathAbs(r[last].close - r[last - InpERPeriod].close);
      double path   = 0.0;
      for(int k = last - InpERPeriod + 1; k <= last; k++)
         path += MathAbs(r[k].close - r[k-1].close);
      er = (path > 0.0) ? change / path : 0.0;
   }

   // extrêmes des barres précédant la barre fermée (pour la ré-entrée)
   close1 = r[last].close;
   int from = MathMax(1, last - InpReentryLookback);
   hiPrev = r[from].high;
   loPrev = r[from].low;
   for(int k = from + 1; k < last; k++)
   {
      if(r[k].high > hiPrev) hiPrev = r[k].high;
      if(r[k].low  < loPrev) loPrev = r[k].low;
   }
   atrOut = atr;
   return true;
}

//+------------------------------------------------------------------+
//| Détection de range : toutes les conditions activées doivent être |
//| vraies (flips récents, ligne plate, ER bas). Aucune condition    |
//| activée = jamais de range.                                       |
//+------------------------------------------------------------------+
bool RangeDetected(const double er, const int flips, const int flat)
{
   if(!InpUseRangePause) return false;
   bool any = false, ok = true;
   if(InpRangeMinFlips > 0)  { any = true; ok = ok && (flips >= InpRangeMinFlips); }
   if(InpRangeFlatBars > 0)  { any = true; ok = ok && (flat  >= InpRangeFlatBars); }
   if(InpRangeERMax > 0.0)   { any = true; ok = ok && (er < InpRangeERMax); }
   return (any && ok);
}

//+------------------------------------------------------------------+
bool FilterOK(const double er)
{
   bool okER  = true;
   bool okADX = true;

   if(InpFilter == FILTER_ER || InpFilter == FILTER_ER_ADX)
      okER = (er > InpERThreshold);

   if(InpFilter == FILTER_ADX || InpFilter == FILTER_ER_ADX)
   {
      double a[1];
      if(CopyBuffer(g_hADX, 0, 1, 1, a) != 1) return false;
      okADX = (a[0] > InpADXThreshold);
   }
   return (okER && okADX);
}

//+------------------------------------------------------------------+
//| Filtre de tendance par régression linéaire (TF signal)           |
//| Régression des InpLRLength dernières clôtures fermées :          |
//|   long autorisé si pente > 0, short autorisé si pente < 0.       |
//|   InpLRMinR > 0 : exige aussi |R de Pearson| >= InpLRMinR        |
//| Calcul sur barres fermées uniquement (pas de repaint).           |
//+------------------------------------------------------------------+
bool LROK(const int dir)
{
   if(!InpUseLinReg) return true;

   double y[];
   ArraySetAsSeries(y, false);                 // y[0] = la plus ancienne
   int n = InpLRLength;
   if(CopyClose(_Symbol, InpSignalTF, 1, n, y) != n) return false;

   double sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0, syy = 0.0;
   for(int i = 0; i < n; i++)
   {
      double x = (double)i;
      sx  += x;
      sy  += y[i];
      sxy += x * y[i];
      sxx += x * x;
      syy += y[i] * y[i];
   }
   double dx = n * sxx - sx * sx;
   double dy = n * syy - sy * sy;
   if(dx <= 0.0) return false;

   double cov   = n * sxy - sx * sy;
   double slope = cov / dx;

   if(InpLRMinR > 0.0)
   {
      if(dy <= 0.0) return false;
      double r = cov / MathSqrt(dx * dy);
      if(MathAbs(r) < InpLRMinR) return false;
   }
   return (dir == 1) ? (slope > 0.0) : (slope < 0.0);
}

//+------------------------------------------------------------------+
bool DEMAOK(const int dir)
{
   if(InpDEMAPeriod <= 0) return true;
   double d[1];
   if(CopyBuffer(g_hDEMA, 0, 1, 1, d) != 1) return false;
   double c = iClose(_Symbol, InpSignalTF, 1);
   if(c <= 0.0) return false;
   return (dir == 1) ? (c > d[0]) : (c < d[0]);
}

//+------------------------------------------------------------------+
//| Positions de l'EA sur ce symbole (netting : 1, hedging : n)      |
//| Renvoie le nombre ; ticket/dir/sl/tp = première position         |
//+------------------------------------------------------------------+
int CountPositions(ulong &ticket, int &dir, double &sl, double &tp)
{
   int c = 0;
   ticket = 0; dir = 0; sl = 0.0; tp = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(c == 0)
      {
         ticket = tk;
         dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         sl     = PositionGetDouble(POSITION_SL);
         tp     = PositionGetDouble(POSITION_TP);
      }
      c++;
   }
   return c;
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      g_trade.PositionClose(tk);
   }
   g_grpDir = 0;
}

//+------------------------------------------------------------------+
//| Multiplicateur de risque selon le drawdown d'equity              |
//+------------------------------------------------------------------+
double RiskMult()
{
   if(!InpUseDDScaling || g_peakEq <= 0.0) return 1.0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_peakEq - eq) / g_peakEq * 100.0;
   if(dd <= InpDDStart) return 1.0;
   double t = MathMin(1.0, (dd - InpDDStart) / (InpDDFull - InpDDStart));
   return 1.0 - t * (1.0 - InpDDMinMult);
}

//+------------------------------------------------------------------+
double CalcLots(const double stopDist, const double riskPct, const bool applyFloor)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickVal <= 0.0) tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickVal <= 0.0 || stopDist <= 0.0) return 0.0;

   double risk       = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0 * RiskMult();
   double lossPerLot = stopDist / tickSize * tickVal;
   double lots       = risk / lossPerLot;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 1.0;

   if(applyFloor && InpMinLots > 0.0) lots = MathMax(lots, InpMinLots);
   lots = MathMin(lots, MathMin(InpMaxLots, vmax));
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0.0;

   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(lots, digits);
}

//+------------------------------------------------------------------+
//| Ouvre une position. isAdd = ajout de pyramide (line = SL actuel) |
//+------------------------------------------------------------------+
bool OpenTrade(const int dir, const double line, const bool isAdd)
{
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = RoundTick(line);

   if(dir == 1  && sl >= price) return false;   // SL invalide (prix sous la ligne)
   if(dir == -1 && sl <= price) return false;

   double dist = MathAbs(price - sl);
   double lots = CalcLots(dist, isAdd ? InpPyramidRiskPct : InpRiskPct, !isAdd);
   if(lots <= 0.0)
   {
      PrintFormat("Trade ignoré : taille < minimum (dist SL = %.2f)", dist);
      return false;
   }

   double tp = 0.0;
   if(isAdd)
   {
      ulong tk; int d; double s, t;
      if(CountPositions(tk, d, s, t) > 0) tp = t;      // conserve le TP existant
   }
   else if(InpTP_R > 0.0)
      tp = RoundTick(price + dir * InpTP_R * dist);

   string cmt = isAdd ? "ST_V3_ADD" : "ST_V3";
   bool ok = (dir == 1) ? g_trade.Buy (lots, _Symbol, price, sl, tp, cmt)
                        : g_trade.Sell(lots, _Symbol, price, sl, tp, cmt);
   if(!ok)
   {
      PrintFormat("Ordre refusé : %d / %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return false;
   }

   if(isAdd)
   {
      g_grpAdds++;
      g_cAdds++;
      g_pyrPhase     = 0;        // après un ajout, on repart à zéro pour le prochain repli
      g_grpExtreme   = price;
      g_pyrPrevClose = price;
   }
   else
   {
      g_grpDir      = dir;
      g_grpEntry    = price;
      g_grpRiskDist = dist;
      g_grpAdds     = 0;
      g_grpExtreme  = price;     // suivi de l'extrême pour le pyramidage sur repli
      g_pyrPhase    = 0;
      g_pyrPrevClose = price;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trailing du SL sur la ligne SuperTrend (toutes les positions)    |
//+------------------------------------------------------------------+
void TrailAll(const int dir, const double line)
{
   double newSL = RoundTick(line);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(dir == 1  && newSL >= bid) { CloseAll(); return; }   // prix déjà sous la ligne
   if(dir == -1 && newSL <= ask) { CloseAll(); return; }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      if(dir == 1  && curSL != 0.0 && newSL <= curSL) continue;   // cliquet : jamais en arrière
      if(dir == -1 && curSL != 0.0 && newSL >= curSL) continue;
      g_trade.PositionModify(tk, newSL, curTP);
   }
}

//+------------------------------------------------------------------+
//| Déclenche un signal : entrée immédiate ou armement M5            |
//+------------------------------------------------------------------+
void FireSignal(const int dir, const double line, const double atrVal = 0.0)
{
   if(InpUsePullbackEntry && atrVal > 0.0)
   {
      // mode pullback : on attend un rebond (short) / repli (long) avant d'entrer
      g_pendDir       = dir;
      g_pendLine      = line;
      g_pendBars      = 0;
      g_pendATR       = atrVal;
      g_pendPhase     = 0;
      g_pendExtreme   = (dir == -1) ? iLow(_Symbol, InpSignalTF, 1) : iHigh(_Symbol, InpSignalTF, 1);
      g_pendPrevClose = 0.0;
      g_pendMaxBars   = InpPullbackMaxBars * (int)(PeriodSeconds(InpSignalTF) / PeriodSeconds(InpEntryTF));
      g_lastEntryBar  = iTime(_Symbol, InpEntryTF, 0);
      g_cPBArmed++;
      return;
   }

   if(!InpUseM5Entry)
   {
      OpenTrade(dir, line, false);
   }
   else
   {
      g_pendDir      = dir;
      g_pendLine     = line;
      g_pendBars     = 0;
      g_lastEntryBar = iTime(_Symbol, InpEntryTF, 0);
      g_cArmed++;
   }
}

//+------------------------------------------------------------------+
//| Nouvelle barre du TF signal                                      |
//+------------------------------------------------------------------+
void OnNewSignalBar()
{
   int    trend1 = 0, trend2 = 0;
   double line1 = 0.0, er = 0.0, close1 = 0.0, hiPrev = 0.0, loPrev = 0.0;
   int    flipsRecent = 0, flatPrev = 0;
   double atrNow = 0.0;
   if(!ComputeSignals(trend1, trend2, line1, er, close1, hiPrev, loPrev, flipsRecent, flatPrev, atrNow)) return;
   g_atrSig = atrNow;                                  // utilisé par le pyramidage sur repli
   bool inRange = RangeDetected(er, flipsRecent, flatPrev);

   // signal en attente caduc (la SuperTrend a rebasculé) ou ligne à mettre à jour
   if(g_pendDir != 0)
   {
      if(trend1 != g_pendDir) { g_pendDir = 0; g_cCancelledFlip++; }
      else                     g_pendLine = line1;
   }

   ulong  ticket = 0;
   int    pdir   = 0;
   double psl = 0.0, ptp = 0.0;
   bool   hasPos = (CountPositions(ticket, pdir, psl, ptp) > 0);
   if(!hasPos) g_grpDir = 0;

   // 1) Gestion de la position ouverte
   if(hasPos)
   {
      if(trend1 != pdir)
      {
         CloseAll();                                 // flip opposé = sortie
         hasPos = false;
      }
      else
         TrailAll(pdir, line1);                      // trailing sur la SuperTrend
   }

   // 2) Flip : nouveau signal
   bool flip = (trend1 != trend2);
   if(flip) g_reentries = 0;

   if(!hasPos && flip)
   {
      g_cFlips++;
      if(trend1 == 1  && !InpAllowLong)  return;
      if(trend1 == -1 && !InpAllowShort) return;
      if(inRange)              { g_cBlockedRange++;  return; }
      if(!FilterOK(er))        { g_cBlockedFilter++; return; }
      if(!DEMAOK(trend1))      { g_cBlockedDEMA++;   return; }
      if(!LROK(trend1))        { g_cBlockedLR++;     return; }
      FireSignal(trend1, line1, atrNow);
      return;
   }

   // 3) Ré-entrée dans la tendance (à plat, pas de flip, rien en attente)
   if(InpUseReentry && !hasPos && !flip && g_pendDir == 0 && g_reentries < InpMaxReentries)
   {
      if(trend1 == 1  && !InpAllowLong)  return;
      if(trend1 == -1 && !InpAllowShort) return;

      bool breakout = (trend1 == 1) ? (close1 > hiPrev) : (close1 < loPrev);
      if(!breakout) return;
      if(inRange) { g_cBlockedRange++; return; }
      if(!FilterOK(er)) return;
      if(!DEMAOK(trend1)) return;
      if(!LROK(trend1)) return;

      g_reentries++;
      g_cReentry++;
      FireSignal(trend1, line1, atrNow);
   }
}

//+------------------------------------------------------------------+
//| Mode pullback (appelé à chaque clôture du TF d'entrée)           |
//|  phase 0 : on suit le plus bas (short) / plus haut (long) depuis |
//|            le flip, jusqu'à un rebond de InpPullbackATR x ATR    |
//|  phase 1 : on entre sur la 1re bougie qui repart dans le sens du |
//|            flip et clôture sous la précédente (short) / au-dessus|
//|            (long)                                                |
//|  annulé si le prix clôture au-delà de la ligne SuperTrend, ou    |
//|  après InpPullbackMaxBars barres du TF signal sans entrée        |
//+------------------------------------------------------------------+
void HandlePullback(const MqlRates &b)
{
   bool isShort = (g_pendDir == -1);

   // invalidation : clôture au-delà de la ligne SuperTrend (SL)
   if((isShort && b.close >= g_pendLine) || (!isShort && b.close <= g_pendLine))
   {
      g_cPBInvalid++;
      g_pendDir = 0;
      return;
   }

   double need = InpPullbackATR * g_pendATR;

   if(g_pendPhase == 0)
   {
      bool rebound = isShort ? (b.high >= g_pendExtreme + need)
                             : (b.low  <= g_pendExtreme - need);
      if(rebound)
         g_pendPhase = 1;
      else
      {
         // pas encore de rebond : l'extrême continue de se prolonger
         if(isShort) { if(b.low  < g_pendExtreme) g_pendExtreme = b.low;  }
         else        { if(b.high > g_pendExtreme) g_pendExtreme = b.high; }
      }
   }
   else
   {
      bool resume = isShort ? (b.close < b.open && b.close < g_pendPrevClose)
                            : (b.close > b.open && b.close > g_pendPrevClose);
      if(resume)
      {
         g_cPBEntered++;
         OpenTrade(g_pendDir, g_pendLine, false);
         g_pendDir = 0;
         return;
      }
   }

   g_pendPrevClose = b.close;

   if(g_pendBars >= g_pendMaxBars)
   {
      g_cPBTimeout++;
      g_pendDir = 0;
   }
}

//+------------------------------------------------------------------+
//| Confirmation M5 d'un signal armé                                 |
//+------------------------------------------------------------------+
void HandlePending()
{
   if(g_pendDir == 0) return;

   ulong  tk = 0; int d = 0; double s = 0.0, t = 0.0;
   if(CountPositions(tk, d, s, t) > 0) { g_pendDir = 0; return; }   // déjà en position

   MqlRates r[];
   if(CopyRates(_Symbol, InpEntryTF, 1, 1, r) != 1) return;         // dernière bougie fermée
   g_pendBars++;

   if(InpUsePullbackEntry) { HandlePullback(r[0]); return; }

   bool confirm = (g_pendDir == 1) ? (r[0].close > r[0].open)
                                   : (r[0].close < r[0].open);

   if(confirm)
   {
      g_cConfirmed++;
      OpenTrade(g_pendDir, g_pendLine, false);
      g_pendDir = 0;
      return;
   }

   if(g_pendBars >= InpMaxWaitM5)
   {
      if(InpEnterOnTimeout) { g_cTimeoutEnter++; OpenTrade(g_pendDir, g_pendLine, false); }
      else                    g_cTimeoutSkip++;
      g_pendDir = 0;
   }
}

//+------------------------------------------------------------------+
//| Pyramidage sur repli (InpPyramidOnPullback)                      |
//|  Appelé à chaque clôture du TF d'entrée, position ouverte.       |
//|  phase 0 : on suit le plus haut (long) / plus bas (short) depuis |
//|            l'entrée (ou le dernier ajout) ; un repli de          |
//|            InpPyramidPullbackATR x ATR n'est retenu que si le    |
//|            trade a déjà gagné InpPyramidMinProfitR x R           |
//|  phase 1 : on ajoute sur la 1re bougie qui repart dans le sens   |
//|            du trade (clôture au-dessus de la précédente pour un  |
//|            long, en dessous pour un short), si le trade est      |
//|            toujours en profit (et SL au point d'entrée si        |
//|            InpPyramidNeedBE)                                     |
//+------------------------------------------------------------------+
void PyramidOnPullback(const double sl)
{
   MqlRates r[];
   if(CopyRates(_Symbol, InpEntryTF, 1, 1, r) != 1) return;
   double h = r[0].high, l = r[0].low, c = r[0].close, o = r[0].open;

   bool   isLong = (g_grpDir == 1);
   double need   = InpPyramidPullbackATR * g_atrSig;
   if(need <= 0.0) { g_pyrPrevClose = c; return; }

   double progress = isLong ? (g_grpExtreme - g_grpEntry) : (g_grpEntry - g_grpExtreme);
   bool   gateOK   = (progress >= InpPyramidMinProfitR * g_grpRiskDist);

   if(g_pyrPhase == 0)
   {
      bool retr = isLong ? (l <= g_grpExtreme - need) : (h >= g_grpExtreme + need);
      if(retr && gateOK)
         g_pyrPhase = 1;                                   // repli suffisant : attente de la reprise
      else
      {
         if(isLong) { if(h > g_grpExtreme) g_grpExtreme = h; }
         else       { if(l < g_grpExtreme) g_grpExtreme = l; }
      }
   }
   else
   {
      bool resume = isLong ? (c > o && c > g_pyrPrevClose)
                           : (c < o && c < g_pyrPrevClose);
      if(resume)
      {
         bool inProfit = isLong ? (c > g_grpEntry) : (c < g_grpEntry);
         bool beOK     = true;
         if(InpPyramidNeedBE) beOK = isLong ? (sl >= g_grpEntry) : (sl <= g_grpEntry);

         if(inProfit && beOK)
         {
            if(!OpenTrade(g_grpDir, sl, true)) g_pyrPhase = 0;   // si l'ordre passe, OpenTrade remet l'état à zéro
         }
         else
            g_pyrPhase = 0;                                      // conditions non remplies : on reprend le suivi
      }
   }
   g_pyrPrevClose = c;
}

//+------------------------------------------------------------------+
//| Pyramidage : ajout à chaque palier de +k x R                     |
//+------------------------------------------------------------------+
void CheckPyramid()
{
   if(!InpUsePyramid || g_grpDir == 0 || g_grpAdds >= InpPyramidMax) return;
   if(g_grpRiskDist <= 0.0) return;

   ulong  tk = 0; int d = 0; double sl = 0.0, tp = 0.0;
   if(CountPositions(tk, d, sl, tp) == 0) { g_grpDir = 0; return; }
   if(d != g_grpDir || sl == 0.0) return;

   if(InpPyramidOnPullback) { PyramidOnPullback(sl); return; }   // ajout sur repli, pas sur paliers en R

   if(InpPyramidNeedBE)
   {
      if(g_grpDir == 1  && sl < g_grpEntry) return;     // pas encore au point d'entrée
      if(g_grpDir == -1 && sl > g_grpEntry) return;
   }

   MqlRates r[];
   if(CopyRates(_Symbol, InpEntryTF, 1, 1, r) != 1) return;

   double trigger = g_grpEntry + g_grpDir * (g_grpAdds + 1) * InpPyramidStepR * g_grpRiskDist;
   bool   hit     = (g_grpDir == 1) ? (r[0].close >= trigger) : (r[0].close <= trigger);
   if(!hit) return;

   OpenTrade(g_grpDir, sl, true);                       // SL de l'ajout = SL actuel (ligne ST)
}

//+------------------------------------------------------------------+
void OnNewEntryBar()
{
   HandlePending();
   CheckPyramid();
}

//+------------------------------------------------------------------+
void OnTick()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEq) g_peakEq = eq;

   datetime tS = iTime(_Symbol, InpSignalTF, 0);
   if(tS != 0 && tS != g_lastSigBar)
   {
      g_lastSigBar = tS;
      OnNewSignalBar();
   }

   if(g_pendDir != 0 || InpUsePyramid)
   {
      datetime tE = iTime(_Symbol, InpEntryTF, 0);
      if(tE != 0 && tE != g_lastEntryBar)
      {
         g_lastEntryBar = tE;
         OnNewEntryBar();
      }
   }
}

//+------------------------------------------------------------------+
//| Critère d'optimisation : profit net / drawdown equity max        |
//|  - moins de InpOptMinTrades trades : rejeté (score négatif)      |
//|  - PF < InpOptMinPF : score divisé par 2                         |
//|  Dans le testeur : Critère d'optimisation = "Max personnalisé"   |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);

   if(InpOptMinTrades > 0 && trades < InpOptMinTrades)
      return -1.0 + trades / InpOptMinTrades;

   if(dd <= 0.0) dd = 1.0;
   double score = profit / dd;

   if(profit > 0.0 && pf < InpOptMinPF)
      score *= 0.5;

   return score;
}
//+------------------------------------------------------------------+
