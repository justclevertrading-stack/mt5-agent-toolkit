//+------------------------------------------------------------------+
//| OrbLondon.mq5                                                     |
//|                                                                   |
//| London opening range breakout on XAUUSD M5.                       |
//|                                                                   |
//| Range      the three M5 candles 08:00, 08:05, 08:10 UK time       |
//| Long       first M5 close above the range high, EMA9 > EMA21      |
//| Short      first M5 close below the range low,  EMA9 < EMA21      |
//|            EMAs on InpEmaTimeframe, M5 by default, H1 for the     |
//|            higher timeframe filter variant                        |
//| Stop       the opposite side of the range                         |
//| TP1        one range height, closes half and moves stop to entry  |
//| TP2        two range heights, for the remainder                   |
//| Session    one trade, no entry after 12:30 UK, flat at 20:00 UK   |
//|                                                                   |
//| Session times are UK. Server time is converted to UK with the EU  |
//| and UK daylight saving calendars. See InpServerUtcOffset* below.  |
//|                                                                   |
//| Built from templates/EA_Template.mq5. Everything below the        |
//| STRATEGY section is that template's safety layer: risk sizing,    |
//| broker capability detection, order normalisation, trade result    |
//| checking, and state rebuilt from the account after a restart.     |
//| Specification: strategies/OrbLondon.md                            |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.00"
#property description "London opening range breakout, XAUUSD M5."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Session, all times UK (Europe/London) ===";
input int    InpRangeStartHour   = 8;       // Opening range starts, UK hour
input int    InpRangeStartMinute = 0;       // Opening range starts, UK minute
input int    InpRangeMinutes     = 15;      // Opening range length, minutes
input int    InpLastEntryHour    = 12;      // No new entry from this UK hour
input int    InpLastEntryMinute  = 30;      // No new entry from this UK minute
input int    InpFlattenHour      = 20;      // Close everything at this UK hour
input int    InpFlattenMinute    = 0;       // Close everything at this UK minute

input group "=== Server time zone ===";
// Vantage runs EET/EEST: UTC+2 in winter, UTC+3 in summer. A server fixed at
// UTC+3 all year is set by making both of these 3.
input int    InpServerUtcOffsetWinter = 2;  // Server UTC offset outside EU DST
input int    InpServerUtcOffsetSummer = 3;  // Server UTC offset during EU DST

input group "=== Strategy ===";
input int    InpFastEmaPeriod    = 9;       // Fast EMA period
input int    InpSlowEmaPeriod    = 21;      // Slow EMA period
input double InpMinRangeUsd      = 5.0;     // Skip session below this range height, $
input double InpMaxRangeUsd      = 25.0;    // Skip session above this range height, $
input bool   InpFirstBreakOnly   = true;    // Only the first close beyond a side counts
input double InpTp1RangeMult     = 1.0;     // TP1, range heights from entry
input double InpTp2RangeMult     = 2.0;     // TP2, range heights from entry
input double InpTp1ClosePercent  = 50.0;    // Percent of the position closed at TP1

input group "=== Variants. Baseline is every one of these at its default ===";
input bool   InpUseEmaFilter     = true;    // Require the EMA to agree with the break
// The EMAs are read on the last CLOSED bar of this timeframe at the moment the
// M5 break candle closes. On H1 that is the previous full hour, never the hour
// still forming, so the value cannot change after the signal is taken.
input ENUM_TIMEFRAMES InpEmaTimeframe = PERIOD_M5; // Timeframe the two EMAs are read on
input bool   InpMoveToBreakEven  = true;    // Move the stop to entry at TP1
input bool   InpStopAtMidpoint   = false;   // Stop at the range midpoint, not the far side
input bool   InpRangeFilterPct   = false;   // Filter the range by percent of price, not dollars
input double InpMinRangePct      = 0.15;    // Skip below this, % of the range midpoint
input double InpMaxRangePct      = 0.60;    // Skip above this, % of the range midpoint

input group "=== Risk management ===";
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance
input int    InpMinStopsLevel    = 20;      // Floor under the broker's stops level, points
input int    InpMaxPositions     = 1;       // Max simultaneous positions
input int    InpMaxTradesPerDay  = 1;       // Max entries per session, 0 = no limit
// Accounting only. MT5 charges commission from the broker's group settings,
// which the tester does not have, so this input does not move a single trade.
// It is applied to the OnTester result and printed at the end of the run.
input double InpCommissionPerLot = 0.0;     // Round-trip commission, $ per lot

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points

input group "=== Identity ===";
input long   InpMagic            = 20260915; // Magic number
input string InpComment          = "OrbLondon"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
#define WORK_TF      PERIOD_M5
#define SCAN_BARS    400            // 08:00 to 20:00 UK is 144 M5 bars

CTrade   trade;
int      fastHandle  = INVALID_HANDLE;
int      slowHandle  = INVALID_HANDLE;
datetime lastBarTime = 0;
bool     isHedging   = false;

// Indicator values for the last closed bars.
// Index 1 is the most recently closed bar, index 2 the one before it.
// Index 0 is the bar still forming and is deliberately not used.
double   fastMA[];
double   slowMA[];

// The signal the strategy section produced for the bar that has just closed.
int      signalDir  = 0;            // +1 long, -1 short, 0 nothing
double   signalStop = 0.0;          // the opposite side of the range
double   signalSpan = 0.0;          // range height, one R for the targets
string   signalWhy  = "";

// The position whose volume was already reported as unsplittable.
ulong    splitWarnedPosition = 0;

// Session diagnostics, printed once per session so a day with no trade can be
// explained from the log alone. Never used as strategy state: every rule is
// recomputed from bars or from the account, so a restart changes nothing.
datetime loggedSession = 0;

//+------------------------------------------------------------------+
//| STRATEGY. This is the only section you normally change.           |
//|                                                                   |
//| Everything here reads closed M5 bars and the two EMAs, which are  |
//| the last closed bar of InpEmaTimeframe. It writes                 |
//| signalDir, signalStop and signalSpan. It never sends an order:    |
//| the safety layer below sizes, normalises and checks the trade.    |
//+------------------------------------------------------------------+

//--- The opening range of the UK day the given bar belongs to.
//--- Returns false when the three range candles are not all present.
bool ComputeRange(const datetime ukDay, double &hi, double &lo)
{
   int startMinute = InpRangeStartHour * 60 + InpRangeStartMinute;
   int endMinute   = startMinute + InpRangeMinutes;
   int barMinutes  = PeriodSeconds(WORK_TF) / 60;
   int wanted      = (barMinutes > 0) ? InpRangeMinutes / barMinutes : 0;
   int found       = 0;

   hi = 0.0;
   lo = 0.0;
   if(wanted <= 0)
      return(false);

   for(int i = 1; i <= SCAN_BARS; i++)
   {
      datetime barTime = iTime(_Symbol, WORK_TF, i);
      if(barTime <= 0)
         break;

      datetime uk = ServerToUk(barTime);
      if(UkDayOf(uk) != ukDay)
         break;                               // walked back into an earlier day

      int minute = UkMinuteOfDay(uk);
      if(minute < startMinute)
         break;                               // before the range, nothing left
      if(minute >= endMinute)
         continue;                            // after the range, keep walking back

      double h = iHigh(_Symbol, WORK_TF, i);
      double l = iLow(_Symbol, WORK_TF, i);
      if(h <= 0.0 || l <= 0.0)
         return(false);

      if(found == 0) { hi = h; lo = l; }
      else           { hi = MathMax(hi, h); lo = MathMin(lo, l); }
      found++;
   }

   return(found == wanted && hi > lo);
}

//--- True when no earlier candle in this session already closed beyond this
//--- side of the range. Read from bars, so a restart cannot forget a break.
bool IsFirstCloseBeyond(const datetime ukDay, const bool above,
                        const double hi, const double lo)
{
   int endMinute = InpRangeStartHour * 60 + InpRangeStartMinute + InpRangeMinutes;

   for(int i = 2; i <= SCAN_BARS; i++)        // from index 2: skip the signal bar
   {
      datetime barTime = iTime(_Symbol, WORK_TF, i);
      if(barTime <= 0)
         break;

      datetime uk = ServerToUk(barTime);
      if(UkDayOf(uk) != ukDay)
         break;
      if(UkMinuteOfDay(uk) < endMinute)
         break;                               // reached the range itself

      double c = iClose(_Symbol, WORK_TF, i);
      if(c <= 0.0)
         continue;
      if(above && c > hi) return(false);
      if(!above && c < lo) return(false);
   }
   return(true);
}

//--- Look at the bar that has just closed and decide what to do.
void DetectSignal()
{
   signalDir  = 0;
   signalStop = 0.0;
   signalSpan = 0.0;
   signalWhy  = "";

   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   if(barTime <= 0)
      return;

   datetime uk     = ServerToUk(barTime);
   datetime ukDay  = UkDayOf(uk);
   int      minute = UkMinuteOfDay(uk);

   int rangeEnd = InpRangeStartHour * 60 + InpRangeStartMinute + InpRangeMinutes;
   int lastEnry = InpLastEntryHour * 60 + InpLastEntryMinute;

   if(minute < rangeEnd)
      return;                                  // range not locked yet
   if(minute >= lastEnry)
      return;                                  // too late in the session

   double hi = 0.0, lo = 0.0;
   if(!ComputeRange(ukDay, hi, lo))
   {
      LogSessionOnce(ukDay, "range incomplete, session skipped");
      return;
   }

   double span = hi - lo;
   double midpoint = (hi + lo) / 2.0;

   if(InpRangeFilterPct)
   {
      double pct = (midpoint > 0.0) ? span / midpoint * 100.0 : 0.0;
      if(pct < InpMinRangePct || pct > InpMaxRangePct)
      {
         LogSessionOnce(ukDay, StringFormat("range %.2f is %.3f%% of %.2f, outside %.2f%% to %.2f%%, session skipped",
                                            span, pct, midpoint, InpMinRangePct, InpMaxRangePct));
         return;
      }
      LogSessionOnce(ukDay, StringFormat("range %.*f to %.*f, height %.2f (%.3f%%)",
                                         _Digits, lo, _Digits, hi, span, pct));
   }
   else
   {
      if(span < InpMinRangeUsd || span > InpMaxRangeUsd)
      {
         LogSessionOnce(ukDay, StringFormat("range %.2f outside %.2f to %.2f, session skipped",
                                            span, InpMinRangeUsd, InpMaxRangeUsd));
         return;
      }
      LogSessionOnce(ukDay, StringFormat("range %.*f to %.*f, height %.2f",
                                         _Digits, lo, _Digits, hi, span));
   }

   double close = iClose(_Symbol, WORK_TF, 1);
   if(close <= 0.0)
      return;

   if(close > hi)
   {
      if(InpUseEmaFilter && fastMA[1] <= slowMA[1])
      {
         PrintFormat("%s: close %.*f above range high %.*f but %s EMA%d %.*f is not above EMA%d %.*f. No trade.",
                     InpComment, _Digits, close, _Digits, hi,
                     EnumToString(InpEmaTimeframe),
                     InpFastEmaPeriod, _Digits, fastMA[1],
                     InpSlowEmaPeriod, _Digits, slowMA[1]);
         return;
      }
      if(InpFirstBreakOnly && !IsFirstCloseBeyond(ukDay, true, hi, lo))
         return;

      signalDir  = 1;
      signalStop = InpStopAtMidpoint ? midpoint : lo;
      signalSpan = span;
      signalWhy  = StringFormat("close %.*f above range high %.*f%s, stop at the %s",
                                _Digits, close, _Digits, hi,
                                (InpUseEmaFilter ? ", EMA agrees" : ""),
                                (InpStopAtMidpoint ? "midpoint" : "far side"));
   }
   else if(close < lo)
   {
      if(InpUseEmaFilter && fastMA[1] >= slowMA[1])
      {
         PrintFormat("%s: close %.*f below range low %.*f but %s EMA%d %.*f is not below EMA%d %.*f. No trade.",
                     InpComment, _Digits, close, _Digits, lo,
                     EnumToString(InpEmaTimeframe),
                     InpFastEmaPeriod, _Digits, fastMA[1],
                     InpSlowEmaPeriod, _Digits, slowMA[1]);
         return;
      }
      if(InpFirstBreakOnly && !IsFirstCloseBeyond(ukDay, false, hi, lo))
         return;

      signalDir  = -1;
      signalStop = InpStopAtMidpoint ? midpoint : hi;
      signalSpan = span;
      signalWhy  = StringFormat("close %.*f below range low %.*f%s, stop at the %s",
                                _Digits, close, _Digits, lo,
                                (InpUseEmaFilter ? ", EMA agrees" : ""),
                                (InpStopAtMidpoint ? "midpoint" : "far side"));
   }
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
   if(InpFastEmaPeriod >= InpSlowEmaPeriod)
   {
      Print("InpFastEmaPeriod must be smaller than InpSlowEmaPeriod.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinRangeUsd <= 0.0 || InpMaxRangeUsd < InpMinRangeUsd)
   {
      Print("Range height bounds are inconsistent.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp2RangeMult <= InpTp1RangeMult || InpTp1RangeMult <= 0.0)
   {
      Print("InpTp2RangeMult must be greater than InpTp1RangeMult, and both above zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp1ClosePercent <= 0.0 || InpTp1ClosePercent >= 100.0)
   {
      Print("InpTp1ClosePercent must be between 0 and 100 exclusive.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   int barMinutes = PeriodSeconds(WORK_TF) / 60;
   if(barMinutes <= 0 || InpRangeMinutes % barMinutes != 0)
   {
      PrintFormat("InpRangeMinutes %d is not a whole number of %d minute candles.",
                  InpRangeMinutes, barMinutes);
      return(INIT_PARAMETERS_INCORRECT);
   }

   fastHandle = iMA(_Symbol, InpEmaTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, InpEmaTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

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
   // Never close positions here. OnDeinit also runs on recompile and on a
   // chart template change, and closing then would be a disaster.
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Position management runs on every tick. TP1 is a price level inside the
   // bar, and the 20:00 flat is a clock event; neither can wait for a close.
   ManageOpenPositions();

   // Entries act once per closed bar.
   datetime current = iTime(_Symbol, WORK_TF, 0);
   if(current == lastBarTime)
      return;

   if(!RefreshIndicators())
      return;                       // not enough bars yet, try again next bar

   lastBarTime = current;

   if(CountMyPositions() >= InpMaxPositions)
      return;
   if(InpMaxTradesPerDay > 0 && CountMyEntriesToday() >= InpMaxTradesPerDay)
      return;

   DetectSignal();
   if(signalDir == 0)
      return;

   if(!IsSpreadAcceptable())
   {
      PrintFormat("%s: signal skipped, spread %d above %d points. %s",
                  InpComment, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
                  InpMaxSpreadPoints, signalWhy);
      return;
   }

   OpenPosition(signalDir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Load the last three indicator values. False means not ready.     |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(fastHandle, 0, 0, 3, fastMA) < 3) return(false);
   if(CopyBuffer(slowHandle, 0, 0, 3, slowMA) < 3) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Take profit 1, break even, and the end of session flat.          |
//| Runs on every tick. Everything it needs is read from the position |
//| itself, so a restart in the middle of a trade changes nothing.    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   bool flatten = IsPastFlattenTime();

   for(int i = PositionsTotal() - 1; i >= 0; i--)   // downwards, indices shift
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      bool stale = (UkDayOf(ServerToUk(opened)) < UkDayOf(ServerToUk(TimeCurrent())));

      if(flatten || stale)
      {
         if(trade.PositionClose(ticket))
            PrintFormat("%s: #%I64u closed at the %02d:%02d UK session end.",
                        InpComment, ticket, InpFlattenHour, InpFlattenMinute);
         else
            PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
         continue;
      }

      HandleFirstTarget(ticket);
   }
}

//+------------------------------------------------------------------+
//| At one range height, close part of the position and move the stop |
//| to the entry price. The range height is recovered from the order's|
//| own take profit, so no state has to survive between ticks.        |
//+------------------------------------------------------------------+
void HandleFirstTarget(const ulong ticket)
{
   long   type   = PositionGetInteger(POSITION_TYPE);
   double open   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);
   if(open <= 0.0 || volume <= 0.0)
      return;

   bool  isBuy      = (type == POSITION_TYPE_BUY);
   ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

   // TP1 is done once part of the position has been closed. Read from the
   // deal history rather than a flag, so a restart cannot scale out twice.
   if(HasClosedPart(positionId))
      return;

   // When the break even move is on, a stop already at entry says the same
   // thing, and covers the position that was too small to split.
   double halfPoint = _Point * 0.5;
   if(InpMoveToBreakEven && sl > 0.0 &&
      ((isBuy && sl >= open - halfPoint) || (!isBuy && sl <= open + halfPoint)))
      return;

   double span = (tp > 0.0) ? MathAbs(tp - open) / InpTp2RangeMult
                            : ((sl > 0.0) ? MathAbs(open - sl) : 0.0);
   if(span <= 0.0)
      return;

   double target1 = isBuy ? open + span * InpTp1RangeMult
                          : open - span * InpTp1RangeMult;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   bool reached = isBuy ? (bid >= target1) : (ask <= target1);
   if(!reached)
      return;

   // Close the requested share, if the broker's volume steps allow a split.
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double closeVol = 0.0;
   if(lotStep > 0.0)
      closeVol = NormalizeDouble(MathFloor((volume * InpTp1ClosePercent / 100.0) / lotStep) * lotStep, 2);

   if(closeVol >= minLot && (volume - closeVol) >= minLot)
   {
      if(trade.PositionClosePartial(ticket, closeVol))
         PrintFormat("%s: TP1 at %.*f, closed %.2f of %.2f lot on #%I64u.",
                     InpComment, _Digits, target1, closeVol, volume, ticket);
      else
         PrintFormat("Partial close failed for #%I64u: %s",
                     ticket, RetcodeText(trade.ResultRetcode()));
   }
   else
   {
      // Warn once per position, not once per tick: with the break even move
      // off there is nothing else to record that this has already happened.
      if(splitWarnedPosition != positionId)
      {
         splitWarnedPosition = positionId;
         PrintFormat("%s: TP1 at %.*f but %.2f lot cannot be split (min %.2f, step %.2f). "
                     "Whole position runs to TP2.",
                     InpComment, _Digits, target1, volume, minLot, lotStep);
      }
   }

   if(!InpMoveToBreakEven)
      return;

   double breakEven = NormalizePrice(open);
   if(trade.PositionModify(ticket, breakEven, tp))
      PrintFormat("%s: stop moved to entry %.*f on #%I64u.", InpComment, _Digits, breakEven, ticket);
   else
      PrintFormat("Break even modify failed for #%I64u: %s",
                  ticket, RetcodeText(trade.ResultRetcode()));
}

//+------------------------------------------------------------------+
//| Has any part of this position already been closed?                |
//+------------------------------------------------------------------+
bool HasClosedPart(const ulong positionId)
{
   if(!HistorySelectByPosition(positionId))
      return(false);

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Send a market order. The stop comes from the range, the target is |
//| a multiple of the range height, and the lot from the real stop    |
//| distance rather than from a fixed point count.                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   // Respect the broker's minimum stop distance, never below the floor the
   // user asked for.
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel < InpMinStopsLevel)
      stopsLevel = InpMinStopsLevel;
   double minGap = (stopsLevel + 1) * _Point;

   bool   isBuy = (type == ORDER_TYPE_BUY);
   double price = isBuy ? ask : bid;
   double sl    = NormalizePrice(signalStop);
   double tp    = NormalizePrice(isBuy ? price + signalSpan * InpTp2RangeMult
                                       : price - signalSpan * InpTp2RangeMult);

   if(isBuy && sl > price - minGap)
   {
      PrintFormat("%s: entry skipped, stop %.*f is not %d points below ask %.*f.",
                  InpComment, _Digits, sl, (int)stopsLevel, _Digits, price);
      return;
   }
   if(!isBuy && sl < price + minGap)
   {
      PrintFormat("%s: entry skipped, stop %.*f is not %d points above bid %.*f.",
                  InpComment, _Digits, sl, (int)stopsLevel, _Digits, price);
      return;
   }
   if(MathAbs(tp - price) < minGap)
   {
      PrintFormat("%s: entry skipped, target %.*f is inside the stops level.",
                  InpComment, _Digits, tp);
      return;
   }

   double slDistance = MathAbs(price - sl);
   double lot = CalculateLot(slDistance);
   if(lot <= 0.0)
   {
      Print("Calculated lot is zero. Risk too small, or balance too low for the minimum lot.");
      return;
   }

   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment)
                   : trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("%s %s %.2f lot at %.*f, SL %.*f, TP1 %.*f, TP2 %.*f | %s",
                  InpComment, (isBuy ? "BUY" : "SELL"), lot, _Digits, price,
                  _Digits, sl,
                  _Digits, (isBuy ? price + signalSpan * InpTp1RangeMult
                                  : price - signalSpan * InpTp1RangeMult),
                  _Digits, tp, signalWhy);
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
//| Entries made this session, read from history. Never from a        |
//| counter. This is what makes the one trade per session cap survive |
//| a terminal restart. The day boundary is UK midnight, not the      |
//| server's, so a session is never split across two counts.          |
//+------------------------------------------------------------------+
int CountMyEntriesToday()
{
   datetime now      = TimeCurrent();
   datetime dayStart = now - (ServerToUk(now) - UkDayOf(ServerToUk(now)));

   if(!HistorySelect(dayStart, now))
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
//| Commission the tester cannot charge.                              |
//|                                                                   |
//| MT5 takes commission from the broker's group settings, which a    |
//| Strategy Tester run does not have, so every backtest here shows   |
//| zero. This reports what the run would really have cost and        |
//| returns the commission-adjusted profit as the OnTester result.    |
//| It deliberately changes no trade: sizing, stops and targets are   |
//| identical whatever this input is set to.                          |
//+------------------------------------------------------------------+
double OnTester()
{
   double volume = 0.0;

   if(HistorySelect(0, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)  continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         volume += HistoryDealGetDouble(ticket, DEAL_VOLUME);
      }
   }

   double testerNet  = TesterStatistics(STAT_PROFIT);
   double commission = volume * InpCommissionPerLot;

   PrintFormat("%s: %.2f lots entered. Commission at %.2f per lot round trip = %.2f. "
               "Tester net %.2f, net after commission %.2f.",
               InpComment, volume, InpCommissionPerLot, commission,
               testerNet, testerNet - commission);

   return(testerNet - commission);
}

//+------------------------------------------------------------------+
//| Server time to UK time.                                           |
//|                                                                   |
//| Two calendars are involved. The server follows the EU rules with  |
//| the offsets given as inputs; London follows the UK rules, which   |
//| switch on the same instant as the EU ones. The EU test uses the   |
//| server clock as an approximation of UTC, which can only be wrong  |
//| for one hour early on a switching Sunday, hours before any        |
//| session this EA trades.                                           |
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

//--- UK midnight that a UK timestamp belongs to, and minutes since it.
datetime UkDayOf(const datetime ukTime)
{
   long seconds = (long)ukTime;
   return((datetime)(seconds - (seconds % 86400)));
}

int UkMinuteOfDay(const datetime ukTime)
{
   long seconds = (long)ukTime;
   return((int)((seconds % 86400) / 60));
}

//+------------------------------------------------------------------+
//| True from the session close time onwards.                         |
//+------------------------------------------------------------------+
bool IsPastFlattenTime()
{
   int minute = UkMinuteOfDay(ServerToUk(TimeCurrent()));
   return(minute >= InpFlattenHour * 60 + InpFlattenMinute);
}

//+------------------------------------------------------------------+
//| One line per session in the journal, so a day with no trade can   |
//| be explained without rerunning anything.                          |
//+------------------------------------------------------------------+
void LogSessionOnce(const datetime ukDay, const string message)
{
   if(loggedSession == ukDay)
      return;
   loggedSession = ukDay;
   PrintFormat("%s %s: %s", InpComment, TimeToString(ukDay, TIME_DATE), message);
}

//+------------------------------------------------------------------+
//| Round to the broker's tick size, not just to digits. On symbols   |
//| whose tick size is not one point, a price rounded only to digits  |
//| is rejected as an invalid price.                                  |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return(NormalizeDouble(price, _Digits));
   return(NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits));
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
