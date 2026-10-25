//+------------------------------------------------------------------+
//| EmaPullback.mq5                                                   |
//|                                                                   |
//| EMA 50/200 trend with an RSI pullback to the EMA50, chart         |
//| timeframe. Built for XAUUSD H1 and H4.                            |
//|                                                                   |
//| Trend   long  close > EMA200 and EMA50 > EMA200, short the mirror |
//| Long    the bar's low came within InpTouchPct % of EMA50 (or      |
//|         through it), RSI(14) 40 to 55, close above EMA50          |
//| Short   the bar's high came within InpTouchPct % of EMA50, RSI    |
//|         45 to 60, close below EMA50                               |
//| Entry   at market on that close                                   |
//| Stop    lowest low (highest high) of the last InpStopBars bars    |
//| Target  InpRewardRisk x the entry to stop distance                |
//| Limits  one position, InpMinBarsBetween bars between entries,     |
//|         optional UK time window for entries                       |
//|                                                                   |
//| Built from templates/EA_Template.mq5. Everything below the        |
//| STRATEGY section is that template's safety layer, with            |
//| OpenPosition taking a structural stop and target, and a fixed lot |
//| option because the specification asks for 0.1 lot.               |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.00"
#property description "EMA 50/200 trend, RSI pullback to EMA50, structural stop, 1.5R target."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Strategy ===";
input int    InpFastPeriod       = 50;      // Pullback EMA period
input int    InpSlowPeriod       = 200;     // Trend EMA period
input int    InpRsiPeriod        = 14;      // RSI period
input double InpTouchPct         = 0.3;     // Low (high) within this % of EMA50 counts as a touch
input double InpLongRsiMin       = 40.0;    // Long: RSI at least this
input double InpLongRsiMax       = 55.0;    // Long: RSI at most this
input double InpShortRsiMin      = 45.0;    // Short: RSI at least this
input double InpShortRsiMax      = 60.0;    // Short: RSI at most this
input int    InpStopBars         = 5;       // Stop at the extreme of this many closed bars
input double InpRewardRisk       = 1.5;     // Take profit, multiples of the risk
input int    InpMinBarsBetween   = 12;      // Minimum bars from one entry to the next

input group "=== Entry time window, UK. Off by default ===";
input bool   InpUseTimeWindow    = false;   // Only enter inside the window below
input string InpWindowStartUK    = "12:00"; // First entry time, UK HH:MM
input string InpWindowEndUK      = "20:00"; // No entry from this UK time
input int    InpServerUtcOffsetWinter = 2;  // Server UTC offset outside EU DST
input int    InpServerUtcOffsetSummer = 3;  // Server UTC offset during EU DST

input group "=== Risk management ===";
input double InpFixedLot         = 0.1;     // Fixed lot, 0 = size from InpRiskPercent
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance, when InpFixedLot is 0
input int    InpMaxPositions     = 1;       // Max simultaneous positions
input int    InpMaxTradesPerDay  = 0;       // Max entries per day, 0 = no limit

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points

input group "=== Identity ===";
input long   InpMagic            = 20261025; // Magic number
input string InpComment          = "EmaPullback"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CTrade   trade;
int      fastHandle  = INVALID_HANDLE;
int      slowHandle  = INVALID_HANDLE;
int      rsiHandle   = INVALID_HANDLE;
datetime lastBarTime = 0;
bool     isHedging   = false;
int      windowStart = 0;           // minutes into the UK day
int      windowEnd   = 0;

// Indicator values for the last closed bars.
// Index 1 is the most recently closed bar, index 2 the one before it.
// Index 0 is the bar still forming and is deliberately not used.
double   fastMA[];
double   slowMA[];
double   rsiVal[];

// The stop and target the strategy section chose for this bar.
double   setupStop = 0.0;

//+------------------------------------------------------------------+
//| STRATEGY. This is the only section you normally change.           |
//+------------------------------------------------------------------+

//--- Lowest low or highest high of closed bars 1 to InpStopBars.
double StopExtreme(const bool lowest)
{
   double v = lowest ? iLow(_Symbol, PERIOD_CURRENT, 1) : iHigh(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= InpStopBars; i++)
   {
      double x = lowest ? iLow(_Symbol, PERIOD_CURRENT, i) : iHigh(_Symbol, PERIOD_CURRENT, i);
      if(x <= 0.0) return(0.0);
      v = lowest ? MathMin(v, x) : MathMax(v, x);
   }
   return(v);
}

//--- Return true to open a long position on this bar. Sets setupStop.
bool ShouldOpenLong()
{
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double l = iLow(_Symbol, PERIOD_CURRENT, 1);
   if(c <= 0.0 || l <= 0.0) return(false);

   bool trend   = c > slowMA[1] && fastMA[1] > slowMA[1];
   bool touched = l <= fastMA[1] * (1.0 + InpTouchPct / 100.0);
   bool rsiOk   = rsiVal[1] >= InpLongRsiMin && rsiVal[1] <= InpLongRsiMax;
   if(!(trend && touched && rsiOk && c > fastMA[1]))
      return(false);

   setupStop = StopExtreme(true);
   PrintFormat("%s long setup: close %.*f above EMA%d %.*f, low %.*f, EMA%d %.*f, RSI %.1f, stop %.*f",
               InpComment, _Digits, c, InpFastPeriod, _Digits, fastMA[1], _Digits, l,
               InpSlowPeriod, _Digits, slowMA[1], rsiVal[1], _Digits, setupStop);
   return(setupStop > 0.0);
}

//--- Return true to open a short position on this bar. Sets setupStop.
bool ShouldOpenShort()
{
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh(_Symbol, PERIOD_CURRENT, 1);
   if(c <= 0.0 || h <= 0.0) return(false);

   bool trend   = c < slowMA[1] && fastMA[1] < slowMA[1];
   bool touched = h >= fastMA[1] * (1.0 - InpTouchPct / 100.0);
   bool rsiOk   = rsiVal[1] >= InpShortRsiMin && rsiVal[1] <= InpShortRsiMax;
   if(!(trend && touched && rsiOk && c < fastMA[1]))
      return(false);

   setupStop = StopExtreme(false);
   PrintFormat("%s short setup: close %.*f below EMA%d %.*f, high %.*f, EMA%d %.*f, RSI %.1f, stop %.*f",
               InpComment, _Digits, c, InpFastPeriod, _Digits, fastMA[1], _Digits, h,
               InpSlowPeriod, _Digits, slowMA[1], rsiVal[1], _Digits, setupStop);
   return(setupStop > 0.0);
}

//--- Exits are the stop and the target only.
bool ShouldCloseLong()  { return(false); }
bool ShouldCloseShort() { return(false); }

//--- InpMinBarsBetween: bars since the last entry of this EA, read from
//--- history so a restart cannot forget it. A large number when none.
int BarsSinceLastEntry()
{
   datetime now = TimeCurrent();
   datetime from = (datetime)((long)now - (long)PeriodSeconds(PERIOD_CURRENT) * (InpMinBarsBetween + 2) * 2);
   if(!HistorySelect(from, now))
      return(INT_MAX);

   datetime last = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)  continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t > last) last = t;
   }
   if(last == 0)
      return(INT_MAX);
   return(iBarShift(_Symbol, PERIOD_CURRENT, last, false));
}

//--- InpUseTimeWindow: is the current server time inside the UK window?
bool InsideTimeWindow()
{
   if(!InpUseTimeWindow)
      return(true);
   int m = UkMinuteOfDay(ServerToUk(TimeCurrent()));
   return(m >= windowStart && m < windowEnd);
}

//+------------------------------------------------------------------+
//| END OF STRATEGY SECTION                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpFixedLot < 0.0 || (InpFixedLot == 0.0 && (InpRiskPercent <= 0.0 || InpRiskPercent > 100.0)))
   {
      Print("InpFixedLot must not be negative, and with it 0, InpRiskPercent must be between 0 and 100.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpFastPeriod >= InpSlowPeriod)
   {
      Print("InpFastPeriod must be smaller than InpSlowPeriod.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpStopBars <= 0 || InpRewardRisk <= 0.0 || InpMinBarsBetween < 0)
   {
      Print("InpStopBars and InpRewardRisk must be above zero, InpMinBarsBetween not negative.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpUseTimeWindow &&
      (!ParseUkTime(InpWindowStartUK, windowStart) || !ParseUkTime(InpWindowEndUK, windowEnd) ||
       windowEnd <= windowStart))
   {
      Print("InpWindowStartUK and InpWindowEndUK must read HH:MM, the end after the start.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   fastHandle = iMA(_Symbol, PERIOD_CURRENT, InpFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, PERIOD_CURRENT, InpSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle  = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   ArraySetAsSeries(rsiVal, true);

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
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(rsiHandle  != INVALID_HANDLE) IndicatorRelease(rsiHandle);
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
   if(!InsideTimeWindow())
      return;
   if(BarsSinceLastEntry() < InpMinBarsBetween)
      return;

   if(ShouldOpenLong())
      OpenPosition(ORDER_TYPE_BUY, setupStop);
   else if(ShouldOpenShort())
      OpenPosition(ORDER_TYPE_SELL, setupStop);
}

//+------------------------------------------------------------------+
//| Load the last three indicator values. False means not ready.     |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(fastHandle, 0, 0, 3, fastMA) < 3) return(false);
   if(CopyBuffer(slowHandle, 0, 0, 3, slowMA) < 3) return(false);
   if(CopyBuffer(rsiHandle,  0, 0, 3, rsiVal) < 3) return(false);
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
void OpenPosition(ENUM_ORDER_TYPE type, const double stopPrice)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   double price = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slDistance = (type == ORDER_TYPE_BUY) ? price - stopPrice : stopPrice - price;

   // The stop comes from structure, so a stop inside the broker's minimum
   // distance is refused rather than widened: widening changes the trade.
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(slDistance <= (stopsLevel + 1) * _Point)
   {
      PrintFormat("%s setup skipped: stop %.*f is %.*f from %.*f, inside the %d point stops level.",
                  InpComment, _Digits, stopPrice, _Digits, slDistance, _Digits, price, (int)stopsLevel);
      return;
   }

   double lot = (InpFixedLot > 0.0) ? NormalizeLot(InpFixedLot) : CalculateLot(slDistance);
   if(lot <= 0.0)
   {
      Print("Calculated lot is zero. Risk too small, or balance too low for the minimum lot.");
      return;
   }

   double sl, tp;
   if(type == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(stopPrice, _Digits);
      tp = NormalizeDouble(price + InpRewardRisk * slDistance, _Digits);
   }
   else
   {
      sl = NormalizeDouble(stopPrice, _Digits);
      tp = NormalizeDouble(price - InpRewardRisk * slDistance, _Digits);
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
//| UK time, from server time. Copied from OrbLondon.mq5.             |
//+------------------------------------------------------------------+
datetime ServerToUk(const datetime serverTime)
{
   int offset = IsEuropeanSummerTime(serverTime) ? InpServerUtcOffsetSummer
                                                 : InpServerUtcOffsetWinter;
   datetime utc = (datetime)((long)serverTime - (long)offset * 3600);
   return(IsEuropeanSummerTime(utc) ? (datetime)((long)utc + 3600) : utc);
}

//--- Last Sunday of the given month, at 01:00 UTC, when the EU clocks change.
datetime EuSwitchTime(const int year, const int month)
{
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year;
   d.mon  = month;
   d.day  = 31;                       // March and October both have 31 days
   d.hour = 1;

   datetime candidate = StructToTime(d);
   MqlDateTime probe;
   TimeToStruct(candidate, probe);
   return((datetime)((long)candidate - (long)probe.day_of_week * 86400));
}

bool IsEuropeanSummerTime(const datetime utc)
{
   MqlDateTime t;
   TimeToStruct(utc, t);
   return(utc >= EuSwitchTime(t.year, 3) && utc < EuSwitchTime(t.year, 10));
}

int UkMinuteOfDay(const datetime ukTime)
{
   long seconds = (long)ukTime;
   return((int)((seconds % 86400) / 60));
}

//--- "13:30" to 810. False on anything that is not HH:MM in range.
bool ParseUkTime(const string text, int &minutes)
{
   minutes = 0;
   string parts[];
   if(StringSplit(text, StringGetCharacter(":", 0), parts) != 2)
      return(false);
   int hour   = (int)StringToInteger(parts[0]);
   int minute = (int)StringToInteger(parts[1]);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return(false);
   minutes = hour * 60 + minute;
   return(true);
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
