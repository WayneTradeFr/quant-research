//+------------------------------------------------------------------+
//| AMRM_Quant_Manhattan_V2_1.mq5 - XAUUSD H1                        |
//| V2 = V1.3 (v1.64) corrigee pour des backtests realistes          |
//|                                                                  |
//| CORRECTIONS (la logique de signal est inchangee) :               |
//|  1. Sortie partielle UNE SEULE FOIS par trade. En V1.3 elle se   |
//|     repetait a chaque tick des que r >= 1 : la position etait    |
//|     quasi soldee a +1R (SL -1R / TP +1R de fait).                |
//|  2. R calcule sur le risque INITIAL du trade (g_init_risk). En   |
//|     V1.3 le risque etait recalcule depuis le SL courant : apres  |
//|     le 1er trailing (SL au-dessus de l'entree), risk <= 0 et la  |
//|     gestion s'arretait pour le reste du trade.                   |
//|  3. Gestion des positions (partiel, trailing) toujours active,   |
//|     meme hors session ou quand une limite de risque est atteinte.|
//|  4. Entree uniquement au 1er tick d'une nouvelle barre H1        |
//|     (signal sur barres cloturees). Plus de re-entree en cours de |
//|     barre apres une sortie (last_bar_time n'etait mis a jour que |
//|     lorsque l'EA etait a plat).                                  |
//|  5. Taille plafonnee (MaxLots, MaxSizingBalance), arrondi vers   |
//|     le bas, trade ignore si le lot calcule < lot minimum.        |
//|  6. Trailing : respect de la distance minimale broker, SL        |
//|     normalise. Slippage max (Deviation) et filling du symbole.   |
//|                                                                  |
//|  7. (V2.1) Second objectif explicite : apres le partiel, le TP du|
//|     solde est place a Target2R x R (1.5 par defaut). Remplace    |
//|     l'astuce Trail_ATR_Mult=0 (SL pose au prix courant), fragile |
//|     en reel (stop invalide) et dependante du chemin de ticks.    |
//|     Trail_ATR_Mult = 0 desactive desormais le trailing.          |
//|                                                                  |
//| NB : ma_f[1] / bb_base[1] = barre H1 n-2 alors que close = barre |
//| n-1 (decalage d'une barre herite de la V1.3, conserve a dessein  |
//| pour ne pas changer le signal).                                  |
//+------------------------------------------------------------------+
#property copyright "Manhattan Quant Belfort V2.1"
#property version   "2.10"
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input double BaseRiskPct = 2.05;
input int    ATR_Period = 20;
input int    ADX_Period = 15;
input double ADX_TrendThreshold = 30.0;
input int    BB_Period = 20;
input double BB_Dev = 2.0;
input int    FastMA = 25;
input int    SlowMA = 75;
input bool   UseSessionFilter = true;
input int    StartHourUTC = 8;
input int    EndHourUTC = 22;
input int    GMTOffsetHours = 0;   // ajuste si l'heure reelle de declenchement derive de StartHourUTC/EndHourUTC
input double MaxDailyRisk = 3.0;
input double MaxWeeklyRisk = 10.0;
input double SL_ATR_Mult = 1.1;
input double TP_ATR_Mult = 6.0;
input double Trail_ATR_Mult = 1.2;
input int    Magic = 888008;
input int    PrintCooldownSec = 1800;

input double AlertDailyWarnPct  = 80.0;
input double AlertWeeklyWarnPct = 80.0;
input double ADX_TransitionZone = 3.0;
input int    ReversalNotifCooldownSec = 300; // cooldown entre 2 notifs de retournement (secondes)

//--- Stochastic (filtre de timing d'entree dans la tendance)
input bool   UseStochFilter = true; // active/desactive le filtre stochastic
input int    Stoch_K = 14;
input int    Stoch_D = 3;
input int    Stoch_Slowing = 3;
input double Stoch_Oversold = 20.0;
input double Stoch_Overbought = 80.0;

//--- V2 : sortie partielle, trailing, taille, execution
input bool   UsePartialExit = true;   // sortie partielle (une seule fois par trade)
input double PartialR = 1.0;          // declenchement en multiples de R (risque initial)
input double PartialPct = 50.0;       // % du volume ferme
input double Target2R = 1.5;          // objectif du solde apres le partiel, en multiples de R (0 = TP initial conserve)
input double TrailStartR = 1.5;       // le trailing demarre a ce multiple de R
input double MaxLots = 20.0;          // plafond de taille (lots)
input double MaxSizingBalance = 0.0;  // solde max pris en compte pour la taille (0 = pas de plafond)
input int    Deviation = 20;          // deviation max (points)

int atr_h, adx_h, bb_h, ma_fast_h, ma_slow_h, stoch_h;
double atr[], adx[], bb_upper[], bb_lower[], bb_base[], ma_f[], ma_s[], stoch_main[];
double daily_start_balance = 0.0;
datetime current_day = 0;
double weekly_start_balance = 0.0;
datetime current_week = 0;
datetime last_daily_print = 0;
datetime last_weekly_print = 0;
datetime last_bar_time = 0;
datetime last_reversal_notif = 0;

bool daily_warn_sent     = false;
bool weekly_warn_sent    = false;
bool adx_transition_sent = false;
bool session_was_active  = false;

int      current_month_num = 0;
int      current_year_num  = 0;
double   month_start_balance = 0.0;
int      month_trade_count = 0;
int      month_cap_hit_count = 0;
int      month_reversal_alert_count = 0;
int      month_adx_transition_count = 0;

//--- suivi du trade courant (un seul trade a la fois)
ulong    g_tracked_ticket = 0;
bool     g_partial_done   = false;
double   g_init_risk      = 0.0;   // distance entree -> SL initial (1R)

int OnInit()
{
   atr_h = iATR(_Symbol, PERIOD_H1, ATR_Period);
   adx_h = iADX(_Symbol, PERIOD_H1, ADX_Period);
   bb_h = iBands(_Symbol, PERIOD_H1, BB_Period, BB_Dev, 0, PRICE_CLOSE);
   ma_fast_h = iMA(_Symbol, PERIOD_H1, FastMA, 0, MODE_EMA, PRICE_CLOSE);
   ma_slow_h = iMA(_Symbol, PERIOD_H1, SlowMA, 0, MODE_EMA, PRICE_CLOSE);
   stoch_h = iStochastic(_Symbol, PERIOD_H1, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);

   if(atr_h == INVALID_HANDLE || adx_h == INVALID_HANDLE || bb_h == INVALID_HANDLE ||
      ma_fast_h == INVALID_HANDLE || ma_slow_h == INVALID_HANDLE || stoch_h == INVALID_HANDLE)
   {
      Print("Erreur creation indicateurs.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(atr, true); ArraySetAsSeries(adx, true);
   ArraySetAsSeries(bb_upper, true); ArraySetAsSeries(bb_lower, true); ArraySetAsSeries(bb_base, true);
   ArraySetAsSeries(ma_f, true); ArraySetAsSeries(ma_s, true);
   ArraySetAsSeries(stoch_main, true);

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(Deviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   session_was_active = IsTradingSession();

   // redemarrage avec une position deja ouverte : on evite un 2e partiel
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == Magic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         g_tracked_ticket = tk;
         g_partial_done   = true;
         g_init_risk      = 0.0;
         break;
      }
   }

   Print("=== MANHATTAN QUANT BOT V2.10 CHARGE (XAUUSD) ===");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
   IndicatorRelease(atr_h); IndicatorRelease(adx_h); IndicatorRelease(bb_h);
   IndicatorRelease(ma_fast_h); IndicatorRelease(ma_slow_h); IndicatorRelease(stoch_h);
}

//--- TimeGMT() suit l'horloge du PC/VPS, pas le temps broker :
//    on utilise TimeTradeServer() + offset manuel ajustable.
bool IsTradingSession()
{
   if(!UseSessionFilter) return true;
   MqlDateTime t;
   datetime ref = TimeTradeServer() - GMTOffsetHours*3600;
   TimeToStruct(ref, t);
   return (t.hour >= StartHourUTC && t.hour <= EndHourUTC);
}

void CheckSessionAlert()
{
   bool active_now = IsTradingSession();
   if(active_now != session_was_active)
   {
      if(active_now)
         SendNotification("AMRM XAUUSD : session de trading démarrée, le bot est actif.");
      else
         SendNotification("AMRM XAUUSD : session de trading terminée, le bot est en pause.");
      session_was_active = active_now;
   }
}

bool CheckDailyRisk()
{
   datetime now = TimeCurrent();
   datetime today = now - (now % 86400);
   if(today != current_day)
   {
      daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      current_day = today;
      daily_warn_sent = false;
   }
   if(daily_start_balance <= 0.0) return true;
   double loss = daily_start_balance - AccountInfoDouble(ACCOUNT_BALANCE);
   double loss_pct = loss / daily_start_balance * 100.0;

   if(loss_pct > MaxDailyRisk * AlertDailyWarnPct/100.0 && !daily_warn_sent)
   {
      SendNotification("AMRM XAUUSD : attention, tu approches de ta limite de perte du jour.");
      daily_warn_sent = true;
   }

   if(loss_pct > MaxDailyRisk)
   {
      if(now - last_daily_print >= PrintCooldownSec)
      {
         Print("=== DAILY RISK CAP HIT - PAUSE ===");
         SendNotification("AMRM XAUUSD : limite de perte du jour atteinte, le bot fait une pause.");
         last_daily_print = now;
         month_cap_hit_count++;
      }
      return false;
   }
   return true;
}
datetime GetWeekStart(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   int dow = s.day_of_week;
   int days_since_monday = (dow == 0) ? 6 : dow - 1;
   datetime day_trunc = t - (t % 86400);
   return day_trunc - days_since_monday * 86400;
}
bool CheckWeeklyRisk()
{
   datetime now = TimeCurrent();
   datetime week_start = GetWeekStart(now);
   if(week_start != current_week)
   {
      weekly_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      current_week = week_start;
      weekly_warn_sent = false;
   }
   if(weekly_start_balance <= 0.0) return true;
   double loss = weekly_start_balance - AccountInfoDouble(ACCOUNT_BALANCE);
   double loss_pct = loss / weekly_start_balance * 100.0;

   if(loss_pct > MaxWeeklyRisk * AlertWeeklyWarnPct/100.0 && !weekly_warn_sent)
   {
      SendNotification("AMRM XAUUSD : attention, tu approches de ta limite de perte de la semaine.");
      weekly_warn_sent = true;
   }

   if(loss_pct > MaxWeeklyRisk)
   {
      if(now - last_weekly_print >= PrintCooldownSec)
      {
         Print("=== WEEKLY RISK CAP HIT - PAUSE JUSQU'À LUNDI ===");
         SendNotification("AMRM XAUUSD : limite de perte de la semaine atteinte, pause jusqu'à lundi.");
         last_weekly_print = now;
         month_cap_hit_count++;
      }
      return false;
   }
   return true;
}
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == Magic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
}

//--- Taille de position : risque en % du solde (plafonne), arrondi vers le bas,
//    plafond MaxLots, 0 si le lot calcule est inferieur au minimum.
double CalculateLot(const double riskPct, const double sl_distance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(MaxSizingBalance > 0.0) balance = MathMin(balance, MaxSizingBalance);
   double risk_amount = balance * riskPct / 100.0;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tick_size <= 0.0 || tick_value <= 0.0 || lot_step <= 0.0 || sl_distance <= 0.0) return 0.0;

   double loss_per_lot = sl_distance / tick_size * tick_value;
   if(loss_per_lot <= 0.0) return 0.0;

   double lot = risk_amount / loss_per_lot;
   lot = MathMin(lot, MathMin(MaxLots, max_lot));
   lot = MathFloor(lot / lot_step + 1e-9) * lot_step;
   if(lot < min_lot) return 0.0;

   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(lot_step)));
   return NormalizeDouble(lot, digits);
}

bool IsStopValid(double entry_price, double sl, double tp, ENUM_ORDER_TYPE order_type)
{
   double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freeze_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double min_stop = MathMax(stop_level, freeze_level);
   if(min_stop <= 0) min_stop = 50 * _Point;

   if(MathAbs(entry_price - sl) < min_stop) return false;
   if(MathAbs(tp - entry_price) < min_stop) return false;

   if(order_type == ORDER_TYPE_BUY && (sl >= entry_price || tp <= entry_price)) return false;
   if(order_type == ORDER_TYPE_SELL && (sl <= entry_price || tp >= entry_price)) return false;

   return true;
}

double GetMonthlyWinRate(datetime month_start, int &total_closed)
{
   if(!HistorySelect(month_start, TimeCurrent())) { total_closed = 0; return 0.0; }
   int wins = 0, total = 0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != Magic) continue;
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      total++;
      if(profit > 0) wins++;
   }
   total_closed = total;
   if(total == 0) return 0.0;
   return (double)wins / total * 100.0;
}

//--- Place le second objectif du solde de la position (apres le partiel).
//    Si le prix l'a deja atteint ou est trop proche du niveau, on ferme au marche.
void ApplyTarget2(const ulong ticket, const int type, const double entry, const double min_stop)
{
   if(Target2R <= 0.0 || g_init_risk <= 0.0) return;
   if(!PositionSelectByTicket(ticket)) return;

   double tp2 = (type == POSITION_TYPE_BUY) ? entry + Target2R * g_init_risk
                                            : entry - Target2R * g_init_risk;
   tp2 = NormalizeDouble(tp2, _Digits);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   bool done_or_too_close = (type == POSITION_TYPE_BUY) ? (tp2 - price < MathMax(min_stop, _Point))
                                                       : (price - tp2 < MathMax(min_stop, _Point));
   if(done_or_too_close)
      trade.PositionClose(ticket);
   else
      trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), tp2);
}

//--- Gestion de la position ouverte (appelee a chaque tick, sans condition de session/risque)
void ManageTrades()
{
   double adx_hist[];
   ArraySetAsSeries(adx_hist, true);
   bool adx_declining = false;
   if(CopyBuffer(adx_h, 0, 1, 3, adx_hist) == 3)
   {
      adx_declining = (adx_hist[1] > adx_hist[2]) && (adx_hist[0] < adx_hist[1]);
   }

   double atr_l[];
   ArraySetAsSeries(atr_l, true);
   bool atr_ok = (CopyBuffer(atr_h, 0, 1, 1, atr_l) == 1 && atr_l[0] > 0.0);

   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stop_level   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freeze_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double min_stop = MathMax(stop_level, freeze_level);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != Magic ||
         PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double price = PositionGetDouble(POSITION_PRICE_CURRENT);
      int type = (int)PositionGetInteger(POSITION_TYPE);

      // nouveau trade : on memorise le risque initial (SL d'origine) et on remet le partiel a zero
      if(ticket != g_tracked_ticket)
      {
         g_tracked_ticket = ticket;
         g_partial_done   = false;
         g_init_risk      = 0.0;
      }
      if(g_init_risk <= 0.0)
      {
         double r0 = (type == POSITION_TYPE_BUY) ? entry - sl : sl - entry;
         if(r0 > 0.0)      g_init_risk = r0;
         else if(atr_ok)   g_init_risk = atr_l[0] * SL_ATR_Mult;
         else              continue;
      }

      // alerte retournement (cooldown global)
      double ma_fast_now[];
      ArraySetAsSeries(ma_fast_now, true);
      if(CopyBuffer(ma_fast_h, 0, 0, 1, ma_fast_now) == 1)
      {
         bool price_crossed_back =
            (type == POSITION_TYPE_BUY  && price < ma_fast_now[0]) ||
            (type == POSITION_TYPE_SELL && price > ma_fast_now[0]);

         if(adx_declining && price_crossed_back &&
            (TimeCurrent() - last_reversal_notif >= ReversalNotifCooldownSec))
         {
            SendNotification("AMRM XAUUSD : signe possible de retournement sur ton trade en cours, surveille.");
            month_reversal_alert_count++;
            last_reversal_notif = TimeCurrent();
         }
      }

      double dist = (type == POSITION_TYPE_BUY) ? (price - entry) : (entry - price);
      double r = dist / g_init_risk;

      // sortie partielle : une seule fois par trade
      if(UsePartialExit && !g_partial_done && r >= PartialR)
      {
         double vol = PositionGetDouble(POSITION_VOLUME);
         double close_vol = MathFloor((vol * PartialPct / 100.0) / lot_step + 1e-9) * lot_step;
         if(close_vol >= min_lot && (vol - close_vol) >= min_lot)
         {
            if(trade.PositionClosePartial(ticket, close_vol))
            {
               g_partial_done = true;
               ApplyTarget2(ticket, type, entry, min_stop);
            }
         }
         else
         {
            g_partial_done = true;   // volume trop petit pour scinder
            ApplyTarget2(ticket, type, entry, min_stop);
         }
         if(!PositionSelectByTicket(ticket)) continue;
         sl = PositionGetDouble(POSITION_SL);
      }

      // trailing sur ATR, uniquement dans le sens favorable
      if(atr_ok && Trail_ATR_Mult > 0.0 && r >= TrailStartR)
      {
         double trail = atr_l[0] * Trail_ATR_Mult;
         double new_sl = (type == POSITION_TYPE_BUY) ? price - trail : price + trail;
         new_sl = NormalizeDouble(new_sl, _Digits);
         bool better = (type == POSITION_TYPE_BUY) ? (new_sl > sl + _Point)
                                                   : (sl <= 0.0 || new_sl < sl - _Point);
         bool far_enough = (MathAbs(price - new_sl) >= min_stop);
         if(better && far_enough)
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
      }
   }
}

void CheckMonthlyBriefing()
{
   MqlDateTime now_struct;
   TimeToStruct(TimeCurrent(), now_struct);

   if(current_month_num == 0)
   {
      current_month_num = now_struct.mon;
      current_year_num  = now_struct.year;
      month_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      return;
   }

   if(now_struct.mon != current_month_num || now_struct.year != current_year_num)
   {
      double balance_now = AccountInfoDouble(ACCOUNT_BALANCE);
      double perf_pct = (month_start_balance > 0.0) ? (balance_now - month_start_balance) / month_start_balance * 100.0 : 0.0;
      int total_closed;
      double win_rate = GetMonthlyWinRate(TimeCurrent() - 31*86400, total_closed);

      string mois_noms[] = {"Jan","Fév","Mar","Avr","Mai","Jun","Jul","Aoû","Sep","Oct","Nov","Déc"};
      string msg = StringFormat(
         "AMRM XAUUSD Bilan %s: %d trades, %.0f%% gagnants, solde %+.1f%%, cap touché %dx, retournement %dx, transition ADX %dx",
         mois_noms[current_month_num-1], month_trade_count, win_rate, perf_pct,
         month_cap_hit_count, month_reversal_alert_count, month_adx_transition_count
      );
      SendNotification(msg);

      current_month_num = now_struct.mon;
      current_year_num  = now_struct.year;
      month_start_balance = balance_now;
      month_trade_count = 0;
      month_cap_hit_count = 0;
      month_reversal_alert_count = 0;
      month_adx_transition_count = 0;
   }
}

//--- true uniquement au 1er tick d'une nouvelle barre H1 (mis a jour a chaque tick,
//    que l'EA soit a plat ou en position)
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_H1, 0);
   if(t == 0 || t == last_bar_time) return false;
   last_bar_time = t;
   return true;
}

void OnTick()
{
   CheckMonthlyBriefing();
   CheckSessionAlert();

   // 1) gestion des positions : toujours active (hors session, hors limite de risque)
   if(CountOpenTrades() >= 1) ManageTrades();

   // 2) limites de risque : alertes + blocage des NOUVELLES entrees uniquement
   bool risk_ok = CheckDailyRisk();
   if(!CheckWeeklyRisk()) risk_ok = false;

   // 3) signaux evalues une seule fois par barre, a son ouverture
   if(!IsNewBar()) return;

   if(CopyBuffer(atr_h,0,1,3,atr)<3 || CopyBuffer(adx_h,0,1,3,adx)<3 ||
      CopyBuffer(bb_h,1,1,3,bb_upper)<3 || CopyBuffer(bb_h,2,1,3,bb_lower)<3 || CopyBuffer(bb_h,0,1,3,bb_base)<3 ||
      CopyBuffer(ma_fast_h,0,1,3,ma_f)<3 || CopyBuffer(ma_slow_h,0,1,3,ma_s)<3) return;
   if(UseStochFilter && CopyBuffer(stoch_h,0,1,4,stoch_main)<4) return;
   if(atr[0] <= 0) return;

   bool in_session = IsTradingSession();

   bool adx_near_threshold = MathAbs(adx[0] - ADX_TrendThreshold) <= ADX_TransitionZone;
   if(adx_near_threshold && !adx_transition_sent && in_session)
   {
      SendNotification("AMRM XAUUSD : le marché change peut-être de régime (proche du seuil de tendance).");
      adx_transition_sent = true;
      month_adx_transition_count++;
   }
   if(!adx_near_threshold) adx_transition_sent = false;

   if(CountOpenTrades() >= 1) return;     // un seul trade a la fois
   if(!in_session || !risk_ok) return;

   double close = iClose(_Symbol, PERIOD_H1, 1);
   bool trending = adx[0] > ADX_TrendThreshold;
   bool bull_trend = ma_f[1] > ma_s[1] && close > ma_f[1];
   bool bear_trend = ma_f[1] < ma_s[1] && close < ma_f[1];

   //--- Stochastic : timing d'entree dans le pullback (cross de sortie de survente/surachat
   //    dans une fenetre de barres). Si UseStochFilter=false, filtre neutralise.
   bool stoch_buy_trigger  = !UseStochFilter;
   bool stoch_sell_trigger = !UseStochFilter;
   if(UseStochFilter)
   {
      for(int i=1; i<3; i++)
      {
         if(stoch_main[i+1] < Stoch_Oversold && stoch_main[i] >= Stoch_Oversold) stoch_buy_trigger = true;
         if(stoch_main[i+1] > Stoch_Overbought && stoch_main[i] <= Stoch_Overbought) stoch_sell_trigger = true;
      }
   }

   bool buy_signal  = trending && bull_trend && close > bb_base[1] && iClose(_Symbol, PERIOD_M15, 1) > ma_f[1] && stoch_buy_trigger;
   bool sell_signal = trending && bear_trend && close < bb_base[1] && iClose(_Symbol, PERIOD_M15, 1) < ma_f[1] && stoch_sell_trigger;
   if(!buy_signal && !sell_signal) return;

   double lot = CalculateLot(BaseRiskPct, atr[0] * SL_ATR_Mult);
   if(lot <= 0.0) return;

   if(buy_signal)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - atr[0]*SL_ATR_Mult, _Digits);
      double tp = NormalizeDouble(ask + atr[0]*TP_ATR_Mult, _Digits);
      if(IsStopValid(ask, sl, tp, ORDER_TYPE_BUY))
      {
         if(trade.Buy(lot, _Symbol, ask, sl, tp, "ManhattanLong"))
            month_trade_count++;
      }
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(bid + atr[0]*SL_ATR_Mult, _Digits);
      double tp = NormalizeDouble(bid - atr[0]*TP_ATR_Mult, _Digits);
      if(IsStopValid(bid, sl, tp, ORDER_TYPE_SELL))
      {
         if(trade.Sell(lot, _Symbol, bid, sl, tp, "ManhattanShort"))
            month_trade_count++;
      }
   }
}
//+------------------------------------------------------------------+
