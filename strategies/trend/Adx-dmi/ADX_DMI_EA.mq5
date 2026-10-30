//+------------------------------------------------------------------+
//| ADX_DMI_EA.mq5                                                   |
//| ADX/DMI close-only : signal sur la barre 1 (cloturee),           |
//| execution a l'ouverture de la barre suivante (= "market on close")|
//| Compatible CFD et futures (MGC) : sizing via tick value/size     |
//+------------------------------------------------------------------+
#property strict
#property version "1.30"
#include <Trade/Trade.mqh>

input group "=== ADX / DMI ==="
input int    InpADXPeriod   = 14;
input double InpADXEntry    = 25.0;   // ADX > seuil pour entrer
input int    InpRiseBars    = 2;      // ADX en hausse depuis N clotures
input double InpDISpread    = 5.0;    // ecart minimum +DI / -DI
input double InpADXExit     = 20.0;   // sortie si ADX < seuil

input group "=== Stop / Exhaustion ==="
input int    InpATRPeriod   = 14;
input double InpSLATR       = 1.5;    // stop initial = N x ATR
input double InpExhProfitATR= 1.5;    // exhaustion : profit > N x ATR
input int    InpExhBars     = 3;      // ... et ADX en baisse depuis N clotures
input double InpPartialPct  = 50.0;   // % cloture a l'exhaustion
input int    InpChandN      = 10;     // Chandelier : plus haut/bas close sur N barres
input double InpChandATR    = 2.5;    // Chandelier : x ATR

input group "=== Risque ==="
input double InpRiskPct     = 1.0;    // % equity risque par trade
input double InpMaxSpreadPts= 0;      // 0 = off
input double InpMarginMaxPct= 50.0;   // marge max utilisee apres entree (%)

input group "=== Options de reduction du risque (toutes OFF par defaut) ==="
input bool   InpUseADXScale   = false;  // 1) risque reduit si ADX faible
input double InpADXScaleThr   = 25.0;   //    ADX[1] < seuil -> risque x multiplicateur
input double InpADXScaleMult  = 0.5;
input bool   InpUseEquityDD   = false;  // 2) risque reduit si equity sous son plus haut
input double InpEqDDPct       = 8.0;    //    DD equity (%) declencheur
input double InpEqDDMult      = 0.5;
input bool   InpUseDailyLoss  = false;  // 3) plafond de perte journalier (jour serveur)
input double InpDailyLossPct  = 2.0;    //    stop des entrees si equity < debut de jour - X %
input bool   InpUseStagnation = false;  // 4) sortie sur stagnation
input int    InpStagBars      = 12;     //    apres N barres...
input double InpStagR         = 0.5;    //    ...si profit < X R (avant l'exhaustion)
input bool   InpUseVolFilter  = false;  // 5) filtre de volatilite
input int    InpVolSlowATR    = 50;     //    ATR lent
input double InpVolMinRatio   = 0.8;    //    entree si ATR(rapide)/ATR(lent) >= seuil
input bool   InpUseUSProtect  = false;  // 6) break-even avant la session US (gagnants seulement)
input int    InpUSProtectHour = 15;     //    heure serveur de la barre qui declenche
input double InpUSProtectMinR = 0.5;    //    profit minimum (en R) pour passer a BE
input int    InpUSBEOffsetPts = 0;      //    decalage du BE (points, commun a 6 et 6c)
input bool   InpUseBEAll      = false;  // 6c) break-even a TOUTES les heures
input double InpBEAllMinR     = 1.0;    //    profit minimum (en R) pour passer a BE
input bool   InpUseUSFlat     = false;  // 6b) cloture totale a l'heure choisie (test comparatif)
input int    InpUSFlatHour    = 15;     //    heure serveur (pas de nouvelle entree sur cette barre)

input group "=== Session (HEURE SERVEUR) ==="
input bool   InpUseSession  = false;
input int    InpStartHour   = 8;
input int    InpEndHour     = 22;

input group "=== Divers ==="
input long   InpMagic       = 20261028;
input int    InpDeviation   = 30;

CTrade   trade;
int      hADX = INVALID_HANDLE, hATR = INVALID_HANDLE, hATRs = INVALID_HANDLE;
datetime lastBar = 0;
double   eqPeak = 0;        // plus haut d'equity (option 2)
double   dayEq = 0;         // equity en debut de jour (option 3)
datetime dayStamp = 0;
string   PeakGV() { return "ADXDMIPK_" + IntegerToString(InpMagic); }   // prefixe distinct de GVPrefix()

//+------------------------------------------------------------------+
int OnInit()
{
   hADX = iADX(_Symbol, _Period, InpADXPeriod);
   hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(hADX == INVALID_HANDLE || hATR == INVALID_HANDLE) return INIT_FAILED;
   if(InpRiseBars < 1 || InpExhBars < 1 || InpChandN < 2) return INIT_PARAMETERS_INCORRECT;
   if(InpADXExit >= InpADXEntry) return INIT_PARAMETERS_INCORRECT;   // evite les passes incoherentes en optimisation
   if(InpUSProtectHour < 0 || InpUSProtectHour > 23 || InpUSFlatHour < 0 || InpUSFlatHour > 23) return INIT_PARAMETERS_INCORRECT;
   if(InpUseVolFilter)
   {
      hATRs = iATR(_Symbol, _Period, InpVolSlowATR);
      if(hATRs == INVALID_HANDLE) return INIT_FAILED;
   }
   eqPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(PeakGV()))
      eqPeak = MathMax(eqPeak, GlobalVariableGet(PeakGV()));
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hATRs != INVALID_HANDLE) IndicatorRelease(hATRs);
}

//+------------------------------------------------------------------+
string GVName(ulong id) { return "ADXDMI_" + IntegerToString(InpMagic) + "_" + (string)id; }
string GVPrefix()       { return "ADXDMI_" + IntegerToString(InpMagic) + "_"; }

bool HasPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
      { ticket = t; return true; }
   }
   return false;
}

bool SessionOK()
{
   if(!InpUseSession) return true;
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   if(InpStartHour <= InpEndHour) return (d.hour >= InpStartHour && d.hour < InpEndHour);
   return (d.hour >= InpStartHour || d.hour < InpEndHour);
}

double CalcLots(double slDist, double riskMult = 1.0)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickSize <= 0 || tickValue <= 0 || step <= 0 || slDist <= 0) return 0;

   double riskMoney  = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 * riskMult;
   double lossPerLot = slDist / tickSize * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;
   if(lots < vmin)
   {
      PrintFormat("Skip: lot %.4f < min %.4f (risque %.2f trop faible pour ce stop)", lots, vmin, riskMoney);
      return 0;
   }
   return MathMin(lots, vmax);
}

bool MarginOK(ENUM_ORDER_TYPE type, double lots, double price)
{
   double margin;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin)) return false;
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN) + margin) / AccountInfoDouble(ACCOUNT_EQUITY) * 100.0 <= InpMarginMaxPct;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == lastBar) return;          // close-only : une evaluation par nouvelle barre
   lastBar = bt;

   int need = MathMax(InpRiseBars, InpExhBars) + 3;
   double adx[], pdi[], mdi[], atr[];
   ArraySetAsSeries(adx, true); ArraySetAsSeries(pdi, true);
   ArraySetAsSeries(mdi, true); ArraySetAsSeries(atr, true);
   if(CopyBuffer(hADX, 0, 0, need, adx) < need) return;   // ADX
   if(CopyBuffer(hADX, 1, 0, need, pdi) < need) return;   // +DI
   if(CopyBuffer(hADX, 2, 0, need, mdi) < need) return;   // -DI
   if(CopyBuffer(hATR, 0, 0, need, atr) < need) return;

   // Suivi equity (options 2 et 3), une fois par barre
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > eqPeak)
   {
      eqPeak = eq;
      if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(PeakGV(), eqPeak);
   }
   datetime today = TimeCurrent() - TimeCurrent() % 86400;
   if(today != dayStamp) { dayStamp = today; dayEq = eq; }

   ulong ticket;
   if(HasPosition(ticket)) ManagePosition(ticket, adx, pdi, mdi, atr);
   else GlobalVariablesDeleteAll(GVPrefix());   // nettoie les etats de positions fermees

   if(HasPosition(ticket)) return;              // une seule position a la fois
   if(!SessionOK()) return;
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return;

   // Garde : ouverture interdite par le broker (close-only, desactive...) -> 1 seul message par jour
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
   {
      static datetime warned = 0;
      if(TimeCurrent() - warned > 86400)
      {
         PrintFormat("Ouverture de position interdite sur %s (trade mode = %d)", _Symbol, (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE));
         warned = TimeCurrent();
      }
      return;
   }

   // Option 6b : pas de nouvelle entree sur la barre de cloture totale
   if(InpUseUSFlat)
   {
      MqlDateTime tn; TimeToStruct(TimeCurrent(), tn);
      if(tn.hour == InpUSFlatHour) return;
   }

   // Option 3 : plafond de perte journalier
   if(InpUseDailyLoss && dayEq > 0 && eq < dayEq * (1.0 - InpDailyLossPct / 100.0)) return;

   // Option 5 : filtre de volatilite (ATR rapide / ATR lent)
   if(InpUseVolFilter)
   {
      double aslow[];
      ArraySetAsSeries(aslow, true);
      if(CopyBuffer(hATRs, 0, 1, 1, aslow) < 1 || aslow[0] <= 0) return;
      if(atr[1] / aslow[0] < InpVolMinRatio) return;
   }

   // Condition A : momentum (ADX > seuil et en hausse depuis N clotures)
   if(!(adx[1] > InpADXEntry)) return;
   for(int k = 1; k <= InpRiseBars; k++)
      if(!(adx[k] > adx[k + 1])) return;

   // Condition B : direction
   int dir = 0;
   if(pdi[1] > mdi[1] + InpDISpread)      dir = 1;
   else if(mdi[1] > pdi[1] + InpDISpread) dir = -1;
   if(dir == 0) return;

   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist  = InpSLATR * atr[1];
   double sl    = (dir == 1) ? price - dist : price + dist;
   double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(dist <= 0 || dist < minStop) return;

   // Options 1 et 2 : multiplicateur de risque (se cumulent)
   double riskMult = 1.0;
   if(InpUseADXScale && adx[1] < InpADXScaleThr) riskMult *= InpADXScaleMult;
   if(InpUseEquityDD && eqPeak > 0 && eq < eqPeak * (1.0 - InpEqDDPct / 100.0)) riskMult *= InpEqDDMult;

   double lots = CalcLots(dist, riskMult);
   if(lots <= 0) return;
   ENUM_ORDER_TYPE ot = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!MarginOK(ot, lots, price)) { Print("Skip: marge insuffisante"); return; }

   sl = NormalizeDouble(sl, _Digits);
   if(dir == 1) trade.Buy(lots, _Symbol, 0, sl, 0, "ADX_DMI");
   else         trade.Sell(lots, _Symbol, 0, sl, 0, "ADX_DMI");
}

//+------------------------------------------------------------------+
void ManagePosition(ulong ticket, const double &adx[], const double &pdi[], const double &mdi[], const double &atr[])
{
   if(!PositionSelectByTicket(ticket)) return;
   bool   isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   double vol    = PositionGetDouble(POSITION_VOLUME);
   ulong  id     = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string gv     = GVName(id);

   // 1) Perte de tendance
   if(adx[1] < InpADXExit) { trade.PositionClose(ticket); return; }
   // 2) Flip de direction
   if((isLong && pdi[1] < mdi[1]) || (!isLong && mdi[1] < pdi[1])) { trade.PositionClose(ticket); return; }

   // 3) Exhaustion : sortie partielle puis Chandelier sur le reste
   bool exhausted = GlobalVariableCheck(gv);
   double c1 = iClose(_Symbol, _Period, 1);
   // Option 6b : cloture totale a l'heure choisie (OFF par defaut)
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   if(InpUseUSFlat && tm.hour == InpUSFlatHour) { trade.PositionClose(ticket); return; }

   // Options 6 / 6c : break-even (avant la session US et/ou a toute heure), uniquement si le stop est
   // encore du mauvais cote de l'entree. Si les deux sont actives, a l'heure US on prend le seuil le plus bas.
   double beR = DBL_MAX;
   if(InpUseBEAll) beR = InpBEAllMinR;
   if(InpUseUSProtect && tm.hour == InpUSProtectHour) beR = MathMin(beR, InpUSProtectMinR);
   if(beR < DBL_MAX)
   {
      double Rinit = isLong ? (open - sl) : (sl - open);        // > 0 tant que le SL n'a pas atteint BE
      double gain  = isLong ? (c1 - open) : (open - c1);
      if(Rinit > 0 && gain >= beR * Rinit)
      {
         double msl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         double be  = NormalizeDouble(open + (isLong ? 1 : -1) * InpUSBEOffsetPts * _Point, _Digits);
         if(isLong  && be > sl && be < SymbolInfoDouble(_Symbol, SYMBOL_BID) - msl) trade.PositionModify(ticket, be, 0);
         if(!isLong && be < sl && be > SymbolInfoDouble(_Symbol, SYMBOL_ASK) + msl) trade.PositionModify(ticket, be, 0);
         if(!PositionSelectByTicket(ticket)) return;
         sl = PositionGetDouble(POSITION_SL);
      }
   }

   // Option 4 : sortie sur stagnation (avant l'exhaustion, le SL est encore le stop initial)
   if(InpUseStagnation && !exhausted)
   {
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      double R = MathAbs(open - sl);
      double pr = isLong ? (c1 - open) : (open - c1);
      if(iBarShift(_Symbol, _Period, opened) >= InpStagBars && R > 0 && pr < InpStagR * R)
      { trade.PositionClose(ticket); return; }
   }

   if(!exhausted)
   {
      double profit = isLong ? (c1 - open) : (open - c1);
      bool adxFalling = true;
      for(int k = 1; k <= InpExhBars; k++)
         if(!(adx[k] < adx[k + 1])) { adxFalling = false; break; }

      if(profit > InpExhProfitATR * atr[1] && adxFalling)
      {
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double pv = MathFloor(vol * InpPartialPct / 100.0 / step) * step;
         if(pv >= vmin && (vol - pv) >= vmin) trade.PositionClosePartial(ticket, pv);
         // si 1 seul contrat (non divisible) : pas de partiel, le Chandelier gere la totalite
         GlobalVariableSet(gv, 1);
         exhausted = true;
      }
   }

   // 4) Chandelier : plus haut/bas CLOSE sur N barres -/+ x ATR (le SL ne recule jamais)
   if(exhausted)
   {
      double cl[];
      ArraySetAsSeries(cl, true);
      if(CopyClose(_Symbol, _Period, 1, InpChandN, cl) < InpChandN) return;
      double minStop = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(!PositionSelectByTicket(ticket)) return;
      sl = PositionGetDouble(POSITION_SL);
      if(isLong)
      {
         double ns = NormalizeDouble(cl[ArrayMaximum(cl, 0, InpChandN)] - InpChandATR * atr[1], _Digits);
         if(ns > sl && ns < SymbolInfoDouble(_Symbol, SYMBOL_BID) - minStop) trade.PositionModify(ticket, ns, 0);
      }
      else
      {
         double ns = NormalizeDouble(cl[ArrayMinimum(cl, 0, InpChandN)] + InpChandATR * atr[1], _Digits);
         if(ns < sl && ns > SymbolInfoDouble(_Symbol, SYMBOL_ASK) + minStop) trade.PositionModify(ticket, ns, 0);
      }
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Critere d'optimisation (choisir "Custom max" dans le testeur)    |
//| score = Sharpe x racine(nb trades) / (1 + DD equity % / 10)      |
//| Rejette : < 100 trades, profit <= 0, facteur de profit <= 1      |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   double pf     = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
   double ddPct  = TesterStatistics(STAT_EQUITYDD_PERCENT);

   if(trades < 100 || profit <= 0 || pf <= 1.0 || sharpe <= 0) return 0.0;
   return sharpe * MathSqrt(trades) / (1.0 + ddPct / 10.0);
}
//+------------------------------------------------------------------+
