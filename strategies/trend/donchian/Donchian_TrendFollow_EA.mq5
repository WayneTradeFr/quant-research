//+------------------------------------------------------------------+
//| Donchian_TrendFollow_EA.mq5  (v3)                                |
//|                                                                  |
//| Strategie : trend-follow Donchian (inspire Turtle), XAUUSD.      |
//|                                                                  |
//| ENTREE  : cloture hors du canal Donchian. Mode ensemble : 3      |
//|           canaux (30/60/120) qui votent, InpMinVotes requis.     |
//| FILTRES : t-stat pente, Efficiency Ratio, regime de vol,         |
//|           session, spread, news, EMA HTF, compression du canal.  |
//| SORTIES : canal Donchian de sortie, SL ATR (filet), sortie       |
//|           partielle, breakeven, time stop, trailing optionnel.   |
//| RISQUE  : lot par risque USD, scale par votes et vol-target,     |
//|           limites jour/compte, re-entree controlee.              |
//| LOG     : CSV des valeurs de filtres par trade (analyse buckets).|
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--------------------- INPUTS ----------------------------------------
input group "=== General ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;   // timeframe de trading
input ulong  InpMagicNumber        = 20260929;

input group "=== Donchian entree / sortie ==="
input int    InpEntryPeriod        = 10;     // canal d'entree (utilise si ensemble OFF)
input bool   InpUseEnsemble        = false;   // 3 canaux qui votent
input int    InpEntryPeriod1       = 30;
input int    InpEntryPeriod2       = 60;
input int    InpEntryPeriod3       = 120;
input int    InpMinVotes           = 2;      // votes requis (1..3)
input bool   InpScaleRiskByVotes   = false;   // risque x (votes / 3)
input int    InpExitPeriod         = 110;     // canal de sortie

input group "=== Filtre t-stat de pente ==="
input bool   InpUseTStatFilter     = false;
input int    InpTStatPeriod        = 50;
input double InpTStatThreshold     = 2.0;    // long : t > +seuil, short : t < -seuil

input group "=== Filtre Efficiency Ratio ==="
input bool   InpUseERFilter        = false;
input int    InpERPeriod           = 20;
input double InpERThreshold        = 0.30;

input group "=== Filtre regime de volatilite ==="
input bool   InpUseVolRegimeFilter = false;
input int    InpATRLongPeriod      = 100;    // ATR court = InpATR_Period
input double InpVolRatioMin        = 1.0;    // ATR court / ATR long > seuil

input group "=== Filtre session (heure serveur broker) ==="
input bool   InpUseSessionFilter   = false;
input int    InpSessionStartHour   = 9;      // inclus
input int    InpSessionEndHour     = 21;     // exclu

input group "=== Filtre spread ==="
input bool   InpUseSpreadFilter    = false;
input int    InpMaxSpreadPoints    = 40;

input group "=== Filtre news (calendrier MT5, inactif en testeur) ==="
input bool   InpUseNewsFilter      = false;
input string InpNewsCurrency       = "USD";
input int    InpNewsMinutesBefore  = 30;
input int    InpNewsMinutesAfter   = 30;

input group "=== Filtre tendance HTF (EMA) ==="
input bool   InpUseHTFFilter       = false;
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H1;
input int    InpHTFEMAPeriod       = 200;
input bool   InpUseHTFSlope        = false;  // exige aussi la pente de l'EMA dans le sens
input int    InpHTFSlopeBars       = 5;

input group "=== Filtre compression du canal ==="
input bool   InpUseCompressionFilter = true;
input int    InpCompressPeriod       = 20;   // largeur du canal mesuree sur N barres
input int    InpCompressLookback     = 200;  // historique pour le percentile
input double InpCompressMaxPct       = 50.0; // largeur actuelle <= ce percentile

input group "=== Risque / SL ==="
input double InpRiskUSD            = 500.0;
input int    InpATR_Period         = 14;
input double InpATR_Multiplier     = 1.0;
input bool   InpUseVolTarget       = true;   // risque x clamp(1 / ratio vol)
input double InpVolScaleMin        = 0.4;
input double InpVolScaleMax        = 1.25;

input group "=== Sortie partielle ==="
input bool   InpUsePartialExit     = true;
input double InpPartialR           = 1.0;    // en multiples de R (distance SL initial)
input double InpPartialPct         = 50.0;   // % du volume ferme

input group "=== Breakeven ==="
input bool   InpUseBreakeven       = false;
input double InpBETriggerR         = 1.0;
input double InpBEOffsetPoints     = 20;     // marge au-dela du prix d'entree

input group "=== Time stop ==="
input bool   InpUseTimeStop        = true;
input int    InpTimeStopBars       = 40;
input double InpTimeStopMinR       = 0.5;    // ferme si progression < ce R apres N barres

input group "=== Trailing en points (optionnel) ==="
input bool   InpUseTrailingStop    = false;
input double InpTrailingStart      = 1200;
input double InpTrailingStop       = 1400;
input double InpTrailingStep       = 25;

input group "=== Re-entree ==="
input bool   InpUseReentryRules      = true;
input bool   InpReentryNeedsReset    = true; // apres une perte, exige une barre sans signal avant de re-entrer
input int    InpReentryCooldownBars  = 3;    // barres d'attente apres une perte (meme sens)
input int    InpMaxEntriesPerDay     = 4;

input group "=== Limites de risque ==="
input int    InpMaxLosingTradesDay = 3;
input double InpMaxDailyLossUSD    = 4500.0;
input bool   InpCloseOnRiskLimit   = true;   // ferme la position si limite jour/compte atteinte
input double InpMaxAccountLossUSD  = 18000.0;
input bool   InpUseAccountCap      = false;   // false = exploration uniquement
input bool   InpUseFTMORiskMode    = false;  // plancher EOD-trailing (plus haute balance de cloture)

input group "=== Log CSV ==="
input bool   InpLogTrades          = true;
input string InpLogFileName        = "Donchian_TF_filters_log.csv";

//--------------------- STATE -------------------------------------------
int      hATR     = INVALID_HANDLE;
int      hATRLong = INVALID_HANDLE;
int      hEMA     = INVALID_HANDLE;
datetime lastBarTime = 0;

double   dayStartEquity       = 0;
double   accountStartEquity   = 0;
double   ftmoAccountLossFloor = 0;
int      losingTradesToday    = 0;
int      g_entriesToday       = 0;
datetime currentDay           = 0;
bool     tradingHaltedForever = false;
bool     dailyLimitHitToday   = false;

// Etat du trade courant
double   g_riskDist    = 0.0;   // distance de prix du SL initial (1R)
double   g_posVolume   = 0.0;   // volume restant suivi via les deals
double   g_tradeProfit = 0.0;   // profit cumule du trade (partiels inclus)
bool     g_partialDone = false;
bool     g_beDone      = false;

// Valeurs des filtres a l'entree (log)
bool     g_entryValid   = false;
int      g_entryDir     = 0;
int      g_entryVotes   = 0;
datetime g_entryTime    = 0;
double   g_entryT       = 0.0;
double   g_entryER      = 0.0;
double   g_entryVR      = 0.0;
double   g_entryComp    = -1.0;
double   g_entryRiskUSD = 0.0;

// Re-entree
bool     g_waitResetLong  = false;
bool     g_waitResetShort = false;
int      g_lastLossDir    = 0;
datetime g_lastLossTime   = 0;

//+------------------------------------------------------------------+
// Selection de MA position (symbole + magic)
//+------------------------------------------------------------------+
bool SelectOwnPosition()
  {
   if(!PositionSelect(_Symbol)) return false;
   if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) return false;
   return true;
  }

int OwnPositionDir()
  {
   if(!SelectOwnPosition()) return 0;
   long type = PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY)  return 1;
   if(type == POSITION_TYPE_SELL) return -1;
   return 0;
  }

bool CloseOwnPosition(const string why)
  {
   if(!SelectOwnPosition()) return false;
   bool ok = trade.PositionClose(_Symbol);
   if(ok) Print("Position fermee : ", why);
   else   Print("Echec fermeture (", why, ") : ", trade.ResultRetcodeDescription());
   return ok;
  }

int VolDigits(const double step)
  {
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9)
     {
      s *= 10.0;
      d++;
     }
   return d;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpEntryPeriod < 2 || InpEntryPeriod1 < 2 || InpEntryPeriod2 < 2 || InpEntryPeriod3 < 2 ||
      InpExitPeriod < 2 || InpATR_Period < 1 || InpATRLongPeriod < 2 ||
      InpMinVotes < 1 || InpMinVotes > 3 ||
      InpCompressPeriod < 2 || InpCompressLookback < 3 ||
      InpPartialPct <= 0.0 || InpPartialPct >= 100.0 ||
      InpHTFSlopeBars < 1 || InpHTFEMAPeriod < 2)
     {
      Print("Parametres invalides.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   hATR     = iATR(_Symbol, InpTimeframe, InpATR_Period);
   hATRLong = iATR(_Symbol, InpTimeframe, InpATRLongPeriod);
   if(hATR == INVALID_HANDLE || hATRLong == INVALID_HANDLE)
     {
      Print("Erreur creation indicateurs ATR.");
      return(INIT_FAILED);
     }

   if(InpUseHTFFilter)
     {
      hEMA = iMA(_Symbol, InpHTF, InpHTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA == INVALID_HANDLE)
        {
         Print("Erreur creation EMA HTF.");
         return(INIT_FAILED);
        }
     }

   trade.SetExpertMagicNumber(InpMagicNumber);

   accountStartEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartEquity       = accountStartEquity;
   ftmoAccountLossFloor = AccountInfoDouble(ACCOUNT_BALANCE);
   currentDay           = TimeCurrent() - (TimeCurrent() % 86400);

   // Reprise d'etat si une position existe deja (redemarrage)
   if(SelectOwnPosition())
     {
      g_posVolume = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(sl > 0.0) g_riskDist = MathAbs(op - sl);
      g_partialDone = true;
      g_beDone      = true;
      g_entryDir    = OwnPositionDir();
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE)     IndicatorRelease(hATR);
   if(hATRLong != INVALID_HANDLE) IndicatorRelease(hATRLong);
   if(hEMA != INVALID_HANDLE)     IndicatorRelease(hEMA);
  }

//+------------------------------------------------------------------+
void CheckNewDay()
  {
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   if(today != currentDay)
     {
      if(InpUseFTMORiskMode)
        {
         double eodBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(eodBalance > ftmoAccountLossFloor)
            ftmoAccountLossFloor = eodBalance;
        }

      currentDay         = today;
      dayStartEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      losingTradesToday  = 0;
      g_entriesToday     = 0;
      dailyLimitHitToday = false;
     }
  }

// true si une limite de risque (compte ou jour) est atteinte
bool RiskLimitHit()
  {
   if(tradingHaltedForever) return true;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpUseAccountCap)
     {
      double ref = InpUseFTMORiskMode ? ftmoAccountLossFloor : accountStartEquity;
      double accountLoss = ref - equity;
      if(accountLoss >= InpMaxAccountLossUSD)
        {
         tradingHaltedForever = true;
         Print("STOP DEFINITIF : perte compte atteinte (", accountLoss, "$)");
         return true;
        }
     }

   double dayLoss = dayStartEquity - equity;
   if(dayLoss >= InpMaxDailyLossUSD)
      dailyLimitHitToday = true;

   return dailyLimitHitToday;
  }

bool IsNewBar()
  {
   datetime t[];
   if(CopyTime(_Symbol, InpTimeframe, 0, 1, t) < 1) return false;
   if(t[0] != lastBarTime)
     {
      lastBarTime = t[0];
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
// Plus haut / plus bas sur 'period' bougies CLOSES, en EXCLUANT la
// derniere bougie close (shift 2..period+1), car c'est elle qu'on
// compare pour detecter la cassure.
//+------------------------------------------------------------------+
bool GetDonchianLevels(const int period, double &highest, double &lowest)
  {
   double h[], l[];
   if(CopyHigh(_Symbol, InpTimeframe, 2, period, h) < period) return false;
   if(CopyLow(_Symbol, InpTimeframe, 2, period, l) < period) return false;

   highest = h[ArrayMaximum(h)];
   lowest  = l[ArrayMinimum(l)];
   return true;
  }

// Votes des canaux d'entree : nPer = nombre de canaux utilises
bool CountVotes(const double lastClose, int &votesL, int &votesS, int &nPer)
  {
   int periods[3] = {0, 0, 0};
   if(InpUseEnsemble)
     {
      periods[0] = InpEntryPeriod1;
      periods[1] = InpEntryPeriod2;
      periods[2] = InpEntryPeriod3;
      nPer = 3;
     }
   else
     {
      periods[0] = InpEntryPeriod;
      nPer = 1;
     }

   votesL = 0;
   votesS = 0;
   for(int i = 0; i < nPer; i++)
     {
      double hi = 0.0, lo = 0.0;
      if(!GetDonchianLevels(periods[i], hi, lo)) return false;
      if(lastClose > hi)      votesL++;
      else if(lastClose < lo) votesS++;
     }
   return true;
  }

//+------------------------------------------------------------------+
// t-stat de la pente : OLS de Close sur le temps, 'period' barres
// closes. Score de qualite de tendance (prix autocorreles : pas une
// vraie p-value).
//+------------------------------------------------------------------+
bool CalcTStat(const int period, double &tstat)
  {
   if(period < 5) return false;

   double c[];
   if(CopyClose(_Symbol, InpTimeframe, 1, period, c) < period) return false;

   double n  = (double)period;
   double xm = (n - 1.0) / 2.0;

   double ym = 0.0;
   for(int i = 0; i < period; i++)
      ym += c[i];
   ym /= n;

   double sxx = 0.0;
   double sxy = 0.0;
   for(int i = 0; i < period; i++)
     {
      double dx = (double)i - xm;
      sxx += dx * dx;
      sxy += dx * (c[i] - ym);
     }
   if(sxx <= 0.0) return false;

   double b = sxy / sxx;
   double a = ym - b * xm;

   double sse = 0.0;
   for(int i = 0; i < period; i++)
     {
      double e = c[i] - (a + b * (double)i);
      sse += e * e;
     }

   if(sse <= 1e-12)
     {
      if(b > 0.0)      tstat = 999.0;
      else if(b < 0.0) tstat = -999.0;
      else             tstat = 0.0;
      return true;
     }

   double s2 = sse / (n - 2.0);
   double se = MathSqrt(s2 / sxx);
   if(se <= 0.0) return false;

   tstat = b / se;
   return true;
  }

// Efficiency Ratio de Kaufman : |P_t - P_{t-n}| / somme(|dP|)
bool CalcER(const int period, double &er)
  {
   if(period < 2) return false;

   double c[];
   if(CopyClose(_Symbol, InpTimeframe, 1, period + 1, c) < period + 1) return false;

   double net = MathAbs(c[period] - c[0]);
   double sum = 0.0;
   for(int i = 1; i <= period; i++)
      sum += MathAbs(c[i] - c[i - 1]);

   if(sum <= 0.0) er = 0.0;
   else           er = net / sum;
   return true;
  }

// Ratio de vol : ATR court / ATR long (barre close shift 1)
bool CalcVolRatio(double &ratio)
  {
   double s[], l[];
   if(CopyBuffer(hATR, 0, 1, 1, s) < 1) return false;
   if(CopyBuffer(hATRLong, 0, 1, 1, l) < 1) return false;
   if(l[0] <= 0.0) return false;

   ratio = s[0] / l[0];
   return true;
  }

// Percentile de la largeur actuelle du canal (InpCompressPeriod)
// parmi les InpCompressLookback dernieres largeurs. Bas = compression.
bool CalcCompressionPct(double &pct)
  {
   const int p = InpCompressPeriod;
   const int L = InpCompressLookback;
   const int total = L + p - 1;

   double h[], l[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   if(CopyHigh(_Symbol, InpTimeframe, 2, total, h) < total) return false;
   if(CopyLow(_Symbol, InpTimeframe, 2, total, l) < total) return false;

   double w0  = 0.0;
   int    cnt = 0;
   for(int k = 0; k < L; k++)
     {
      double hi = h[k];
      double lo = l[k];
      for(int j = 1; j < p; j++)
        {
         if(h[k + j] > hi) hi = h[k + j];
         if(l[k + j] < lo) lo = l[k + j];
        }
      double w = hi - lo;
      if(k == 0) w0 = w;
      else if(w <= w0) cnt++;
     }

   pct = 100.0 * (double)cnt / (double)(L - 1);
   return true;
  }

//+------------------------------------------------------------------+
// FILTRES
//+------------------------------------------------------------------+
bool InSession()
  {
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(InpSessionStartHour <= InpSessionEndHour)
      return (h >= InpSessionStartHour && h < InpSessionEndHour);
   return (h >= InpSessionStartHour || h < InpSessionEndHour);
  }

bool SpreadOK()
  {
   if(!InpUseSpreadFilter) return true;
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpreadPoints);
  }

// Blocage autour des news USD a fort impact (calendrier MT5).
// Echec silencieux (pas de blocage) si le calendrier est indisponible.
bool IsNewsBlackout()
  {
   if(!InpUseNewsFilter) return false;

   datetime now  = TimeTradeServer();
   datetime from = now - (datetime)(InpNewsMinutesAfter * 60);
   datetime to   = now + (datetime)(InpNewsMinutesBefore * 60);

   MqlCalendarValue vals[];
   if(!CalendarValueHistory(vals, from, to, NULL, InpNewsCurrency)) return false;

   int n = ArraySize(vals);
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH) return true;
     }
   return false;
  }

bool PassHTF(const int dir, const double lastClose)
  {
   if(!InpUseHTFFilter) return true;
   if(hEMA == INVALID_HANDLE) return false;

   int need = InpUseHTFSlope ? (InpHTFSlopeBars + 1) : 1;
   double e[];
   if(CopyBuffer(hEMA, 0, 1, need, e) < need) return false;

   double emaNow = e[need - 1];
   if(dir > 0 && lastClose <= emaNow) return false;
   if(dir < 0 && lastClose >= emaNow) return false;

   if(InpUseHTFSlope)
     {
      double emaOld = e[0];
      if(dir > 0 && emaNow <= emaOld) return false;
      if(dir < 0 && emaNow >= emaOld) return false;
     }
   return true;
  }

bool PassCompression()
  {
   g_entryComp = -1.0;
   if(!InpUseCompressionFilter) return true;

   double pct = 0.0;
   if(!CalcCompressionPct(pct)) return false;
   g_entryComp = pct;
   return (pct <= InpCompressMaxPct);
  }

// t-stat, ER, regime de vol. Stocke les valeurs pour le log et le sizing.
bool PassStatFilters(const int dir)
  {
   double t = 0.0, er = 0.0, vr = 0.0;

   if(!CalcTStat(InpTStatPeriod, t)) return false;
   if(!CalcER(InpERPeriod, er)) return false;
   if(!CalcVolRatio(vr)) return false;

   g_entryT  = t;
   g_entryER = er;
   g_entryVR = vr;

   if(InpUseTStatFilter)
     {
      if(dir > 0 && t <= InpTStatThreshold)  return false;
      if(dir < 0 && t >= -InpTStatThreshold) return false;
     }

   if(InpUseERFilter && er <= InpERThreshold) return false;

   if(InpUseVolRegimeFilter && vr <= InpVolRatioMin) return false;

   return true;
  }

bool ReentryAllowed(const int dir)
  {
   if(!InpUseReentryRules) return true;

   if(InpReentryNeedsReset)
     {
      if(dir > 0 && g_waitResetLong)  return false;
      if(dir < 0 && g_waitResetShort) return false;
     }

   if(InpReentryCooldownBars > 0 && g_lastLossDir == dir && g_lastLossTime > 0)
     {
      int sh = iBarShift(_Symbol, InpTimeframe, g_lastLossTime, false);
      if(sh >= 0 && sh < InpReentryCooldownBars) return false;
     }
   return true;
  }

bool EntryAllowed(const int dir, const double lastClose)
  {
   if(!InSession()) return false;
   if(!SpreadOK()) return false;
   if(!ReentryAllowed(dir)) return false;
   if(!PassHTF(dir, lastClose)) return false;
   if(!PassCompression()) return false;
   if(!PassStatFilters(dir)) return false;
   if(IsNewsBlackout()) return false;
   return true;
  }

//+------------------------------------------------------------------+
// SIZING
//+------------------------------------------------------------------+
double CalcLotForRisk(const double riskUSD, const double slPoints)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickValue <= 0 || tickSize <= 0 || point <= 0) return 0.0;

   double slPriceDistance = slPoints * point;
   double valuePerLot = (slPriceDistance / tickSize) * tickValue;
   if(valuePerLot <= 0) return 0.0;

   double lot = riskUSD / valuePerLot;
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lotStep <= 0) return 0.0;

   lot = MathFloor(lot / lotStep + 1e-9) * lotStep;
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   return NormalizeDouble(lot, VolDigits(lotStep));
  }

void OpenTrade(const int direction, const int votes, const int nPer)
  {
   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;

   double atrBuf[];
   if(CopyBuffer(hATR, 0, 1, 1, atrBuf) < 1) return;
   double slPoints = (atrBuf[0] / point) * InpATR_Multiplier;

   // Risque : base x votes x vol-target
   double voteScale = 1.0;
   if(InpUseEnsemble && InpScaleRiskByVotes && nPer > 0)
      voteScale = (double)votes / (double)nPer;

   double volScale = 1.0;
   if(InpUseVolTarget && g_entryVR > 0.0)
      volScale = MathMax(InpVolScaleMin, MathMin(InpVolScaleMax, 1.0 / g_entryVR));

   double riskUSD = InpRiskUSD * voteScale * volScale;

   double lot = CalcLotForRisk(riskUSD, slPoints);
   if(lot <= 0) { Print("Lot invalide, trade annule."); return; }

   double sl = (direction > 0) ? price - slPoints * point : price + slPoints * point;

   bool ok;
   if(direction > 0)
      ok = trade.Buy(lot, _Symbol, price, sl, 0, "Donchian_TF");
   else
      ok = trade.Sell(lot, _Symbol, price, sl, 0, "Donchian_TF");

   if(ok)
     {
      double filled = trade.ResultVolume();
      g_posVolume   = (filled > 0.0) ? filled : lot;
      g_tradeProfit = 0.0;
      g_riskDist    = slPoints * point;
      g_partialDone = false;
      g_beDone      = false;

      g_entryValid   = true;
      g_entryDir     = direction;
      g_entryVotes   = votes;
      g_entryTime    = TimeCurrent();
      g_entryRiskUSD = riskUSD;
      g_entriesToday++;

      Print("Trade ouvert : dir=", direction, " lot=", lot, " votes=", votes, "/", nPer,
            " risk=", DoubleToString(riskUSD, 0), " SL(pts)=", DoubleToString(slPoints, 0),
            " t=", DoubleToString(g_entryT, 2), " ER=", DoubleToString(g_entryER, 2),
            " VR=", DoubleToString(g_entryVR, 2));
     }
   else
      Print("Echec ouverture : ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
// SORTIES
//+------------------------------------------------------------------+
void CheckDonchianExit()
  {
   int dir = OwnPositionDir();
   if(dir == 0) return;

   double exitHigh = 0.0, exitLow = 0.0;
   if(!GetDonchianLevels(InpExitPeriod, exitHigh, exitLow)) return;

   double lastClose = iClose(_Symbol, InpTimeframe, 1);

   bool exitSignal = false;
   if(dir > 0 && lastClose < exitLow)  exitSignal = true;
   if(dir < 0 && lastClose > exitHigh) exitSignal = true;

   if(exitSignal)
      CloseOwnPosition("sortie canal Donchian");
  }

// Ferme si apres N barres la progression est inferieure a MinR
void CheckTimeStop()
  {
   if(!InpUseTimeStop) return;
   if(!SelectOwnPosition()) return;
   if(g_riskDist <= 0.0) return;

   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   int barsHeld = iBarShift(_Symbol, InpTimeframe, opened, false);
   if(barsHeld < InpTimeStopBars) return;

   long   type  = PositionGetInteger(POSITION_TYPE);
   double openP = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double prog  = (type == POSITION_TYPE_BUY) ? (bid - openP) : (openP - ask);

   if(prog < InpTimeStopMinR * g_riskDist)
      CloseOwnPosition("time stop");
  }

// Distance minimale broker respectee pour un nouveau SL ?
bool StopDistanceOK(const long type, const double newSL)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)  return ((bid - newSL) >= level);
   if(type == POSITION_TYPE_SELL) return ((newSL - ask) >= level);
   return false;
  }

void ManageTrailingStop()
  {
   if(!InpUseTrailingStop) return;
   if(!SelectOwnPosition()) return;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   long   posType   = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double startDist = InpTrailingStart * point;
   double trailDist = InpTrailingStop  * point;
   double stepDist  = InpTrailingStep  * point;

   if(posType == POSITION_TYPE_BUY)
     {
      double profit = bid - openPrice;
      if(profit < startDist) return;
      double newSL = bid - trailDist;
      if(newSL >= bid) return;
      if(currentSL == 0.0 || newSL > currentSL + stepDist)
         trade.PositionModify(_Symbol, NormalizeDouble(newSL, digits), currentTP);
     }
   else if(posType == POSITION_TYPE_SELL)
     {
      double profit = openPrice - ask;
      if(profit < startDist) return;
      double newSL = ask + trailDist;
      if(newSL <= ask) return;
      if(currentSL == 0.0 || newSL < currentSL - stepDist)
         trade.PositionModify(_Symbol, NormalizeDouble(newSL, digits), currentTP);
     }
  }

// Gestion a chaque tick : sortie partielle, breakeven, trailing
void ManagePosition()
  {
   if(!SelectOwnPosition()) return;

   if(g_riskDist > 0.0)
     {
      double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      long   type  = PositionGetInteger(POSITION_TYPE);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double prog  = (type == POSITION_TYPE_BUY) ? (bid - openP) : (openP - ask);

      // --- Sortie partielle ---
      if(InpUsePartialExit && !g_partialDone && prog >= InpPartialR * g_riskDist)
        {
         double vol  = PositionGetDouble(POSITION_VOLUME);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(step > 0.0)
           {
            double cv = MathFloor((vol * InpPartialPct / 100.0) / step + 1e-9) * step;
            cv = NormalizeDouble(cv, VolDigits(step));
            if(cv < minV || (vol - cv) < (minV - 1e-9))
               g_partialDone = true; // volume trop petit pour scinder
            else if(trade.PositionClosePartial(_Symbol, cv))
              {
               g_partialDone = true;
               Print("Sortie partielle : ", cv, " lots a ", DoubleToString(InpPartialR, 2), "R");
              }
            else
               Print("Echec sortie partielle : ", trade.ResultRetcodeDescription());
           }
         if(!SelectOwnPosition()) return;
        }

      // --- Breakeven ---
      if(InpUseBreakeven && !g_beDone && prog >= InpBETriggerR * g_riskDist)
        {
         double off   = InpBEOffsetPoints * point;
         double newSL = (type == POSITION_TYPE_BUY) ? (openP + off) : (openP - off);
         double curSL = PositionGetDouble(POSITION_SL);
         bool better  = (type == POSITION_TYPE_BUY) ? (curSL == 0.0 || newSL > curSL)
                                                    : (curSL == 0.0 || newSL < curSL);
         if(!better)
            g_beDone = true; // SL deja meilleur
         else if(StopDistanceOK(type, newSL))
           {
            if(trade.PositionModify(_Symbol, NormalizeDouble(newSL, digits),
                                    PositionGetDouble(POSITION_TP)))
              {
               g_beDone = true;
               Print("Breakeven active.");
              }
           }
        }
     }

   ManageTrailingStop();
  }

//+------------------------------------------------------------------+
// LOG / FIN DE TRADE
//+------------------------------------------------------------------+
void LogTradeResult(const double profit)
  {
   if(!InpLogTrades) return;
   if(!g_entryValid) return;

   int fh = FileOpen(InpLogFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(fh == INVALID_HANDLE)
     {
      Print("Erreur ouverture log CSV : ", GetLastError());
      return;
     }

   if(FileSize(fh) == 0)
      FileWrite(fh, "entry_time", "dir", "votes", "tstat", "er", "vol_ratio",
                "compress_pct", "risk_usd", "profit_usd", "r_mult");

   FileSeek(fh, 0, SEEK_END);
   double rMult = (g_entryRiskUSD > 0.0) ? (profit / g_entryRiskUSD) : 0.0;
   FileWrite(fh,
             TimeToString(g_entryTime, TIME_DATE | TIME_MINUTES),
             g_entryDir,
             g_entryVotes,
             DoubleToString(g_entryT, 3),
             DoubleToString(g_entryER, 3),
             DoubleToString(g_entryVR, 3),
             DoubleToString(g_entryComp, 1),
             DoubleToString(g_entryRiskUSD, 2),
             DoubleToString(profit, 2),
             DoubleToString(rMult, 3));
   FileClose(fh);
  }

// Appele quand le volume restant tombe a zero (trade totalement clos)
void FinalizeTrade()
  {
   bool loss = (g_tradeProfit < 0.0);

   if(loss)
     {
      losingTradesToday++;
      g_lastLossDir  = g_entryDir;
      g_lastLossTime = TimeCurrent();
      if(InpReentryNeedsReset)
        {
         if(g_entryDir > 0)      g_waitResetLong  = true;
         else if(g_entryDir < 0) g_waitResetShort = true;
        }
     }

   LogTradeResult(g_tradeProfit);

   g_entryValid  = false;
   g_entryDir    = 0;
   g_tradeProfit = 0.0;
   g_posVolume   = 0.0;
   g_riskDist    = 0.0;
   g_partialDone = false;
   g_beDone      = false;
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   double dealPL = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(entry == DEAL_ENTRY_IN)
     {
      g_tradeProfit += dealPL; // commission d'entree eventuelle
      return;
     }
   if(entry != DEAL_ENTRY_OUT) return;

   g_tradeProfit += dealPL;
   g_posVolume   -= HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(g_posVolume > minV * 0.5) return; // sortie partielle : trade encore ouvert

   FinalizeTrade();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CheckNewDay();

   bool limitHit = RiskLimitHit();
   if(limitHit && InpCloseOnRiskLimit)
      CloseOwnPosition("limite de risque atteinte");

   ManagePosition(); // partiel / breakeven / trailing a chaque tick

   if(!IsNewBar()) return;

   if(SelectOwnPosition())
     {
      CheckTimeStop();
      CheckDonchianExit();
      return;
     }

   if(limitHit) return;
   if(losingTradesToday >= InpMaxLosingTradesDay) return;
   if(g_entriesToday >= InpMaxEntriesPerDay) return;

   double lastClose = iClose(_Symbol, InpTimeframe, 1);
   if(lastClose <= 0.0) return;

   int votesL = 0, votesS = 0, nPer = 0;
   if(!CountVotes(lastClose, votesL, votesS, nPer)) return;

   int  minVotes = InpUseEnsemble ? InpMinVotes : 1;
   bool sigL = (votesL >= minVotes);
   bool sigS = (votesS >= minVotes);

   // Reset de re-entree : une barre sans signal dans ce sens libere le blocage
   if(!sigL) g_waitResetLong  = false;
   if(!sigS) g_waitResetShort = false;

   if(!sigL && !sigS) return;

   int dir   = sigL ? 1 : -1;
   int votes = sigL ? votesL : votesS;

   if(!EntryAllowed(dir, lastClose)) return;

   OpenTrade(dir, votes, nPer);
  }
//+------------------------------------------------------------------+
