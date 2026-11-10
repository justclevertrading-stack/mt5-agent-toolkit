//+------------------------------------------------------------------+
//| GoldTrendPullback.mq5                                             |
//|                                                                   |
//| Built from templates\EA_Template.mq5.                             |
//| Specification: strategies\GoldTrendPullback.md                    |
//|                                                                   |
//| H1 trend pullback for XAUUSD, on closed bars only.                |
//|   trend    EMA(50) above / below EMA(200)                         |
//|   pullback the bar's low (long) or high (short) touches EMA(20)   |
//|   trigger  the same bar closes back on the trend side of EMA(20)  |
//|   stop     1.5 x ATR(14), target 2 x the stop (2R)                |
//| Exit on stop loss or take profit only. No early exit, no trailing.|
//|                                                                   |
//| Differences from the template, all marked "CHANGED":              |
//|   the stop distance comes from ATR instead of a fixed number of   |
//|   points, so OpenPosition takes the distance as a parameter, and  |
//|   a minimum-stop rail refuses implausibly tight stops (see        |
//|   mql5-patterns/references/risk-sizing.md). Lot sizing itself is  |
//|   the template's, unchanged.                                      |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.00"
#property description "H1 EMA trend pullback for gold. See strategies/GoldTrendPullback.md"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Strategy ===";
input int    InpTrendFastPeriod  = 50;      // Trend EMA, fast
input int    InpTrendSlowPeriod  = 200;     // Trend EMA, slow
input int    InpPullbackPeriod   = 20;      // Pullback EMA
input int    InpAtrPeriod        = 14;      // ATR period
input double InpAtrStopMult      = 1.5;     // Stop loss, x ATR
input double InpRewardRisk       = 2.0;     // Take profit, x stop distance, 0 = none

input group "=== Risk management ===";
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance
input int    InpMinStopPoints    = 100;     // Refuse trades whose stop is tighter than this, points
input int    InpMaxPositions     = 1;       // Max simultaneous positions
input int    InpMaxTradesPerDay  = 3;       // Max entries per day, 0 = no limit

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points (see spec for 3-digit quotes)

input group "=== Identity ===";
input long   InpMagic            = 20261110; // Magic number
input string InpComment          = "GoldTrendPullback"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CTrade   trade;
int      trendFastHandle = INVALID_HANDLE;
int      trendSlowHandle = INVALID_HANDLE;
int      pullbackHandle  = INVALID_HANDLE;
int      atrHandle       = INVALID_HANDLE;
datetime lastBarTime = 0;
bool     isHedging   = false;

// Indicator values for the last closed bars.
// Index 1 is the most recently closed bar, index 2 the one before it.
// Index 0 is the bar still forming and is deliberately not used.
double   emaTrendFast[];
double   emaTrendSlow[];
double   emaPullback[];
double   atr[];
MqlRates bars[];

//+------------------------------------------------------------------+
//| STRATEGY. This is the only section you normally change.           |
//|                                                                   |
//| bars[1] and the indicator arrays at [1] are the last closed bar.  |
//+------------------------------------------------------------------+

//--- Uptrend, the closed bar dipped to the pullback EMA and closed above it.
bool ShouldOpenLong()
{
   bool upTrend  = emaTrendFast[1] > emaTrendSlow[1];
   bool touched  = bars[1].low   <= emaPullback[1];
   bool rejected = bars[1].close >  emaPullback[1];
   return(upTrend && touched && rejected);
}

//--- Downtrend, the closed bar rallied to the pullback EMA and closed below it.
bool ShouldOpenShort()
{
   bool downTrend = emaTrendFast[1] < emaTrendSlow[1];
   bool touched   = bars[1].high  >= emaPullback[1];
   bool rejected  = bars[1].close <  emaPullback[1];
   return(downTrend && touched && rejected);
}

//--- The specification says exit on stop loss or take profit only.
bool ShouldCloseLong()  { return(false); }
bool ShouldCloseShort() { return(false); }

//--- CHANGED: stop distance in price, from the signal bar's ATR.
double StopDistancePrice()
{
   return(InpAtrStopMult * atr[1]);
}

//+------------------------------------------------------------------+
//| END OF STRATEGY SECTION                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)
   {
      Print("InpRiskPercent must be between 0 and 100.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpAtrStopMult <= 0.0)
   {
      Print("InpAtrStopMult must be greater than zero. Lot sizing depends on it.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpRewardRisk < 0.0)
   {
      Print("InpRewardRisk must be zero (no take profit) or positive.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTrendFastPeriod >= InpTrendSlowPeriod)
   {
      Print("InpTrendFastPeriod must be smaller than InpTrendSlowPeriod.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpPullbackPeriod <= 0 || InpAtrPeriod <= 0)
   {
      Print("InpPullbackPeriod and InpAtrPeriod must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   trendFastHandle = iMA(_Symbol, PERIOD_CURRENT, InpTrendFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   trendSlowHandle = iMA(_Symbol, PERIOD_CURRENT, InpTrendSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   pullbackHandle  = iMA(_Symbol, PERIOD_CURRENT, InpPullbackPeriod,  0, MODE_EMA, PRICE_CLOSE);
   atrHandle       = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
   if(trendFastHandle == INVALID_HANDLE || trendSlowHandle == INVALID_HANDLE ||
      pullbackHandle  == INVALID_HANDLE || atrHandle       == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
   }

   if(Period() != PERIOD_H1)
      Print("Warning: the specification is for H1. This chart is ", EnumToString(Period()), ".");

   ArraySetAsSeries(emaTrendFast, true);
   ArraySetAsSeries(emaTrendSlow, true);
   ArraySetAsSeries(emaPullback,  true);
   ArraySetAsSeries(atr,          true);
   ArraySetAsSeries(bars,         true);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(PickFillingMode());
   trade.SetDeviationInPoints(10);

   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   LogBrokerCapabilities();

   // State is rebuilt from the account, never carried in memory.
   // See skill mql5-patterns, references/state-and-restart.md.
   PrintFormat("%s starting. %d open position(s), %d entry(ies) already today.",
               InpComment, CountMyPositions(), CountMyEntriesToday());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(trendFastHandle != INVALID_HANDLE) IndicatorRelease(trendFastHandle);
   if(trendSlowHandle != INVALID_HANDLE) IndicatorRelease(trendSlowHandle);
   if(pullbackHandle  != INVALID_HANDLE) IndicatorRelease(pullbackHandle);
   if(atrHandle       != INVALID_HANDLE) IndicatorRelease(atrHandle);
   // Never close positions here. OnDeinit also runs on recompile and on a
   // chart template change, and closing then would be a disaster.
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Act once per closed bar, not on every tick.
   datetime current = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current == lastBarTime)
      return;

   if(!RefreshIndicators())
      return;                       // not enough bars yet, try again next bar

   lastBarTime = current;

   ManageOpenPositions();

   if(!IsSpreadAcceptable())
      return;
   if(CountMyPositions() >= InpMaxPositions)
      return;
   if(InpMaxTradesPerDay > 0 && CountMyEntriesToday() >= InpMaxTradesPerDay)
      return;

   if(ShouldOpenLong())
   {
      PrintFormat("%s long signal: EMA%d %.2f > EMA%d %.2f, low %.2f <= EMA%d %.2f < close %.2f",
                  InpComment, InpTrendFastPeriod, emaTrendFast[1], InpTrendSlowPeriod, emaTrendSlow[1],
                  bars[1].low, InpPullbackPeriod, emaPullback[1], bars[1].close);
      OpenPosition(ORDER_TYPE_BUY, StopDistancePrice());
   }
   else if(ShouldOpenShort())
   {
      PrintFormat("%s short signal: EMA%d %.2f < EMA%d %.2f, high %.2f >= EMA%d %.2f > close %.2f",
                  InpComment, InpTrendFastPeriod, emaTrendFast[1], InpTrendSlowPeriod, emaTrendSlow[1],
                  bars[1].high, InpPullbackPeriod, emaPullback[1], bars[1].close);
      OpenPosition(ORDER_TYPE_SELL, StopDistancePrice());
   }
}

//+------------------------------------------------------------------+
//| Load the last three indicator values. False means not ready.     |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(trendFastHandle, 0, 0, 3, emaTrendFast) < 3) return(false);
   if(CopyBuffer(trendSlowHandle, 0, 0, 3, emaTrendSlow) < 3) return(false);
   if(CopyBuffer(pullbackHandle,  0, 0, 3, emaPullback)  < 3) return(false);
   if(CopyBuffer(atrHandle,       0, 0, 3, atr)          < 3) return(false);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, bars)     < 3) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Close positions the strategy no longer wants.                    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)   // downwards, indices shift
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      bool wantClose = (type == POSITION_TYPE_BUY)  ? ShouldCloseLong()
                     : (type == POSITION_TYPE_SELL) ? ShouldCloseShort()
                     : false;

      if(wantClose)
      {
         if(!trade.PositionClose(ticket))
            PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
   }
}

//+------------------------------------------------------------------+
//| Send a market order with normalised volume and stops.            |
//+------------------------------------------------------------------+
//| CHANGED: the stop distance is passed in (ATR based) instead of    |
//| read from a fixed points input. Everything after it is template.  |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, double stopDistancePrice)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   // Rail 1 from risk-sizing.md: a stop that is implausibly tight would make
   // the position implausibly large. Refuse the trade, never size up.
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop    = MathMax((double)InpMinStopPoints, (double)stopsLevel + 2.0) * _Point;
   if(stopDistancePrice < minStop)
   {
      PrintFormat("%s skipped: stop %.2f is tighter than the minimum %.2f.",
                  InpComment, stopDistancePrice, minStop);
      return;
   }

   int    slPoints   = (int)MathCeil(stopDistancePrice / _Point);
   int    tpPoints   = (int)MathRound(slPoints * InpRewardRisk);
   if(tpPoints > 0)
      tpPoints = (int)MathMax((double)tpPoints, (double)stopsLevel + 1);

   double slDistance = slPoints * _Point;
   double lot = CalculateLot(slDistance);
   if(lot <= 0.0)
   {
      Print("Calculated lot is zero. Risk too small, or balance too low for the minimum lot.");
      return;
   }

   double price, sl, tp = 0.0;
   if(type == ORDER_TYPE_BUY)
   {
      price = ask;
      sl = NormalizeDouble(price - slDistance, _Digits);
      if(tpPoints > 0) tp = NormalizeDouble(price + tpPoints * _Point, _Digits);
   }
   else
   {
      price = bid;
      sl = NormalizeDouble(price + slDistance, _Digits);
      if(tpPoints > 0) tp = NormalizeDouble(price - tpPoints * _Point, _Digits);
   }

   bool ok = (type == ORDER_TYPE_BUY)
           ? trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment)
           : trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("%s %s %.2f lot at %.*f, SL %.*f, TP %.*f",
                  InpComment, (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  lot, _Digits, price, _Digits, sl, _Digits, tp);
   }
   else
   {
      PrintFormat("Order rejected: %s (retcode %u)", RetcodeText(code), code);
   }
}

//+------------------------------------------------------------------+
//| Lot size from a percentage of balance and the stop distance.     |
//+------------------------------------------------------------------+
double CalculateLot(double stopDistancePrice)
{
   if(stopDistancePrice <= 0.0) return(0.0);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   // Tick value is already in the account currency, which is what makes this
   // correct for cross pairs and metals. Deriving risk from pips is not.
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return(0.0);

   double lossPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return(0.0);

   return(NormalizeLot(riskMoney / lossPerLot));
}

//+------------------------------------------------------------------+
//| Round down to the lot step and clamp to the broker's limits.     |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0) return(0.0);

   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) return(0.0);          // refuse rather than risk more than asked
   if(lot > maxLot) lot = maxLot;

   return(NormalizeDouble(lot, 2));
}

//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spread <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Open positions belonging to this EA on this symbol.              |
//+------------------------------------------------------------------+
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Entries made today, read from history. Never from a counter.     |
//| This is what makes the EA survive a terminal restart.            |
//+------------------------------------------------------------------+
int CountMyEntriesToday()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);   // broker server time, not local time
   now.hour = 0;
   now.min  = 0;
   now.sec  = 0;
   datetime dayStart = StructToTime(now);

   if(!HistorySelect(dayStart, TimeCurrent()))
      return(0);

   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)  != _Symbol)  continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  == DEAL_ENTRY_IN)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Pick a filling mode the broker actually supports.                |
//| Getting this wrong rejects every order with retcode 10030.       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING PickFillingMode()
{
   int mask = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mask & SYMBOL_FILLING_FOK) != 0) return(ORDER_FILLING_FOK);
   if((mask & SYMBOL_FILLING_IOC) != 0) return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
void LogBrokerCapabilities()
{
   PrintFormat("Symbol %s  digits %d  point %.*f", _Symbol, _Digits, _Digits, _Point);
   PrintFormat("Account mode: %s", isHedging ? "HEDGING" : "NETTING or EXCHANGE");
   PrintFormat("Volume min %.2f  max %.2f  step %.2f",
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   PrintFormat("Stops level %d  freeze level %d",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
}

//+------------------------------------------------------------------+
string RetcodeText(uint code)
{
   switch(code)
   {
      case TRADE_RETCODE_DONE:              return("DONE");
      case TRADE_RETCODE_DONE_PARTIAL:      return("PARTIAL FILL");
      case TRADE_RETCODE_REQUOTE:           return("REQUOTE");
      case TRADE_RETCODE_REJECT:            return("REJECTED");
      case TRADE_RETCODE_INVALID_STOPS:     return("INVALID STOPS");
      case TRADE_RETCODE_INVALID_VOLUME:    return("INVALID VOLUME");
      case TRADE_RETCODE_NO_MONEY:          return("NOT ENOUGH MONEY");
      case TRADE_RETCODE_MARKET_CLOSED:     return("MARKET CLOSED");
      case TRADE_RETCODE_TRADE_DISABLED:    return("TRADE DISABLED");
      case TRADE_RETCODE_INVALID_FILL:      return("UNSUPPORTED FILLING MODE");
      case TRADE_RETCODE_CONNECTION:        return("NO CONNECTION");
      case TRADE_RETCODE_PRICE_CHANGED:     return("PRICE CHANGED");
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return("TOO MANY REQUESTS");
      default:                              return("UNKNOWN " + IntegerToString(code));
   }
}
//+------------------------------------------------------------------+
