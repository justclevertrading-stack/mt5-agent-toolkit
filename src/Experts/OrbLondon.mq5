//+------------------------------------------------------------------+
//| OrbLondon.mq5                                                     |
//|                                                                   |
//| Opening range breakout on XAUUSD M5, London and New York.         |
//|                                                                   |
//| Box        LON  the M5 candles from 08:00 UK for InpRangeMinutes  |
//|            NY   the M5 candles from InpNYStart to InpNYEnd UK     |
//| Long       first M5 close above the box high, EMA9 > EMA21        |
//| Short      first M5 close below the box low,  EMA9 < EMA21        |
//|            EMAs on InpEmaTimeframe, M5 by default, H1 for the     |
//|            higher timeframe filter variant                        |
//| Entry      BREAK   at market on that close (the original rule)    |
//|            RETEST  a limit at the broken box edge, given          |
//|                    InpRetestBars candles to fill                  |
//| Stop       the opposite side of the box                           |
//| TP1        one box height, closes half and moves stop to entry    |
//| TP2        two box heights, for the remainder                     |
//| Session    one trade per session, no entry after the session's    |
//|            last entry time, flat at its own flatten time          |
//|                                                                   |
//| The two sessions are independent. Each has its own magic number    |
//| (NY is InpMagic + InpNyMagicOffset), its own one-trade-per-session |
//| cap and its own flatten time, so a London trade, open or closed,  |
//| never blocks the New York one and the reverse is also true.       |
//|                                                                   |
//| Session times are UK. Server time is converted to UK with the EU  |
//| and UK daylight saving calendars, for both sessions alike. See    |
//| InpServerUtcOffset* below.                                        |
//|                                                                   |
//| Built from templates/EA_Template.mq5. Everything below the        |
//| STRATEGY section is that template's safety layer: risk sizing,    |
//| broker capability detection, order normalisation, trade result    |
//| checking, and state rebuilt from the account after a restart.     |
//| Specification: strategies/OrbLondon.md                            |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.10"
#property description "London and New York opening range breakout, XAUUSD M5."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Entry mode                                                        |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
{
   ENTRY_BREAK  = 0,    // BREAK: market order on the close outside the box
   ENTRY_RETEST = 1     // RETEST: limit order at the broken box edge
};

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

input group "=== Sessions traded ===";
input bool   InpTradeLondon      = true;    // Trade the London box
input bool   InpTradeNY          = true;    // Trade the New York box
input string InpNYStart          = "13:30"; // NY box starts, UK time HH:MM
input string InpNYEnd            = "13:45"; // NY box ends, UK time HH:MM
// The London session stops taking entries at 12:30 UK, four hours before its
// flatten time. No equivalent cutoff was specified for New York, so the
// default here is the flatten time itself: any break up to 16:00 UK is taken
// and the position is closed at 16:00. Set it earlier to refuse late entries.
input string InpNYLastEntry      = "16:00"; // No new NY entry from this UK time
input string InpNYFlatTime       = "16:00"; // Close any NY position at this UK time
input long   InpNyMagicOffset    = 1;       // Added to InpMagic for NY trades

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

input group "=== Entry mode, applies to both sessions ===";
input ENUM_ENTRY_MODE InpEntryMode = ENTRY_BREAK; // How a break is entered
input int    InpRetestBars       = 6;       // RETEST: candles the limit waits for a fill

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
// Off by default because the build this one replaces had no such exit, and
// turning it on changes every result that came before it. When on it applies
// to both sessions alike.
input bool   InpCloseBackInsideExit = false; // Exit when a candle closes back inside the box

input group "=== Risk management ===";
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance
input int    InpMinStopsLevel    = 20;      // Floor under the broker's stops level, points
input int    InpMaxPositions     = 1;       // Max simultaneous positions per session
input int    InpMaxTradesPerDay  = 1;       // Max entries per session, 0 = no limit
// Accounting only. MT5 charges commission from the broker's group settings,
// which the tester does not have, so this input does not move a single trade.
// It is applied to the OnTester result and printed at the end of the run.
input double InpCommissionPerLot = 0.0;     // Round-trip commission, $ per lot

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points

input group "=== Logging ===";
input bool   InpCsvLog           = true;    // Append one row per break to a CSV
input string InpCsvFile          = "orblondon_log.csv"; // File under MQL5\Files
input bool   InpCsvCommonFolder  = false;   // Write to the shared Common\Files instead

input group "=== Identity ===";
input long   InpMagic            = 20260915; // Magic number, London
input string InpComment          = "OrbLondon"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
#define WORK_TF        PERIOD_M5
#define SCAN_BARS      400          // 08:00 to 20:00 UK is 144 M5 bars
#define SESSION_LON    0
#define SESSION_NY     1
#define SESSION_COUNT  2

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
double   signalStop = 0.0;          // the opposite side of the box
double   signalSpan = 0.0;          // box height, one R for the targets
double   signalHi   = 0.0;          // box high, the long side retest level
double   signalLo   = 0.0;          // box low, the short side retest level
string   signalWhy  = "";

// The position whose volume was already reported as unsplittable.
ulong    splitWarnedPosition = 0;

// New York session times, parsed from their string inputs once in OnInit.
int      nyBoxStart  = 0;           // minutes into the UK day
int      nyBoxEnd    = 0;
int      nyLastEntry = 0;
int      nyFlatten   = 0;

//+------------------------------------------------------------------+
//| Per session bookkeeping.                                          |
//|                                                                   |
//| Diagnostics and CSV plumbing only. Every trading rule is          |
//| recomputed from bars or read back from the account, so a restart   |
//| that empties all of this costs log rows and nothing else.         |
//+------------------------------------------------------------------+
struct SessionState
{
   datetime loggedDay;      // the UK day already described in the journal
   int      record;         // index into records for the open trade, -1 none
   int      pendingRecord;  // index into records for a signal not yet settled
   ulong    position;       // POSITION_IDENTIFIER being tracked
   datetime openTime;
   double   risk;           // money at risk when the position opened
   string   exitTag;        // set immediately before a close this EA decides
};

SessionState sess[SESSION_COUNT];

//+------------------------------------------------------------------+
//| One row of the CSV, held until every column is known.             |
//|                                                                   |
//| A row needs the outcome, which only exists once the position has   |
//| closed, and in RETEST mode whether the limit ever filled. Rows    |
//| are therefore held here and written when they settle, with the     |
//| remainder flushed in OnDeinit, which the tester does call.        |
//+------------------------------------------------------------------+
struct SignalRecord
{
   datetime signalBar;      // server time of the break candle
   datetime ukSignal;       // UK time of the break candle
   int      session;        // SESSION_LON or SESSION_NY
   int      dir;            // +1 long, -1 short
   string   mode;           // BREAK or RETEST
   double   boxHi;
   double   boxLo;
   double   entry;          // fill price, or the intended price when skipped
   double   stop;
   double   rAtStop;        // entry to stop distance, in price
   string   retest;         // Y filled, N cancelled, - not in RETEST mode
   string   outcome;        // OPEN TP1 TP2 BE SL timecut backinside SKIPPED_*
   string   reason;         // why it was skipped, empty otherwise
   double   rResult;        // realised profit / money risked
   int      minutes;        // minutes in trade
   double   profit;         // realised money, account currency
   bool     settled;        // outcome is final
   bool     written;
};

SignalRecord records[];
bool     csvHeaderChecked = false;

//+------------------------------------------------------------------+
//| STRATEGY. This is the only section you normally change.           |
//|                                                                   |
//| Everything here reads closed M5 bars and the two EMAs, which are  |
//| the last closed bar of InpEmaTimeframe. It writes                 |
//| signalDir, signalStop, signalSpan, signalHi and signalLo. It      |
//| never sends an order: the safety layer below sizes, normalises     |
//| and checks the trade.                                             |
//+------------------------------------------------------------------+

//--- The opening range of the UK day the given bar belongs to, for the
//--- window [startMinute, endMinute) of that day.
//--- Returns false when the range candles are not all present.
bool ComputeBox(const datetime ukDay, const int startMinute, const int endMinute,
                double &hi, double &lo)
{
   int barMinutes  = PeriodSeconds(WORK_TF) / 60;
   int wanted      = (barMinutes > 0) ? (endMinute - startMinute) / barMinutes : 0;
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

//--- The box of the session the given bar belongs to.
bool ComputeSessionBox(const int s, const datetime ukDay, double &hi, double &lo)
{
   return(ComputeBox(ukDay, SessionBoxStart(s), SessionBoxEnd(s), hi, lo));
}

//--- True when no earlier candle in this session already closed beyond this
//--- side of the box. Read from bars, so a restart cannot forget a break.
bool IsFirstCloseBeyond(const datetime ukDay, const int boxEndMinute, const bool above,
                        const double hi, const double lo)
{
   for(int i = 2; i <= SCAN_BARS; i++)        // from index 2: skip the signal bar
   {
      datetime barTime = iTime(_Symbol, WORK_TF, i);
      if(barTime <= 0)
         break;

      datetime uk = ServerToUk(barTime);
      if(UkDayOf(uk) != ukDay)
         break;
      if(UkMinuteOfDay(uk) < boxEndMinute)
         break;                               // reached the box itself

      double c = iClose(_Symbol, WORK_TF, i);
      if(c <= 0.0)
         continue;
      if(above && c > hi) return(false);
      if(!above && c < lo) return(false);
   }
   return(true);
}

//--- Look at the bar that has just closed and decide what to do for this
//--- session. Returns true when signalDir is set.
bool DetectSignal(const int s)
{
   signalDir  = 0;
   signalStop = 0.0;
   signalSpan = 0.0;
   signalHi   = 0.0;
   signalLo   = 0.0;
   signalWhy  = "";

   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   if(barTime <= 0)
      return(false);

   datetime uk     = ServerToUk(barTime);
   datetime ukDay  = UkDayOf(uk);
   int      minute = UkMinuteOfDay(uk);

   int boxEnd   = SessionBoxEnd(s);
   int lastEnry = SessionLastEntry(s);

   if(minute < boxEnd)
      return(false);                           // box not locked yet
   if(minute >= lastEnry)
      return(false);                           // too late in the session

   double hi = 0.0, lo = 0.0;
   if(!ComputeBox(ukDay, SessionBoxStart(s), boxEnd, hi, lo))
   {
      LogSessionOnce(s, ukDay, "range incomplete, session skipped");
      return(false);
   }

   double span = hi - lo;
   double midpoint = (hi + lo) / 2.0;

   if(InpRangeFilterPct)
   {
      double pct = (midpoint > 0.0) ? span / midpoint * 100.0 : 0.0;
      if(pct < InpMinRangePct || pct > InpMaxRangePct)
      {
         LogSessionOnce(s, ukDay, StringFormat("range %.2f is %.3f%% of %.2f, outside %.2f%% to %.2f%%, session skipped",
                                               span, pct, midpoint, InpMinRangePct, InpMaxRangePct));
         return(false);
      }
      LogSessionOnce(s, ukDay, StringFormat("range %.*f to %.*f, height %.2f (%.3f%%)",
                                            _Digits, lo, _Digits, hi, span, pct));
   }
   else
   {
      if(span < InpMinRangeUsd || span > InpMaxRangeUsd)
      {
         LogSessionOnce(s, ukDay, StringFormat("range %.2f outside %.2f to %.2f, session skipped",
                                               span, InpMinRangeUsd, InpMaxRangeUsd));
         return(false);
      }
      LogSessionOnce(s, ukDay, StringFormat("range %.*f to %.*f, height %.2f",
                                            _Digits, lo, _Digits, hi, span));
   }

   double close = iClose(_Symbol, WORK_TF, 1);
   if(close <= 0.0)
      return(false);

   if(close > hi)
   {
      if(InpUseEmaFilter && fastMA[1] <= slowMA[1])
      {
         PrintFormat("%s %s: close %.*f above range high %.*f but %s EMA%d %.*f is not above EMA%d %.*f. No trade.",
                     InpComment, SessionTag(s), _Digits, close, _Digits, hi,
                     EnumToString(InpEmaTimeframe),
                     InpFastEmaPeriod, _Digits, fastMA[1],
                     InpSlowEmaPeriod, _Digits, slowMA[1]);
         return(false);
      }
      if(InpFirstBreakOnly && !IsFirstCloseBeyond(ukDay, boxEnd, true, hi, lo))
         return(false);

      signalDir  = 1;
      signalStop = InpStopAtMidpoint ? midpoint : lo;
      signalSpan = span;
      signalHi   = hi;
      signalLo   = lo;
      signalWhy  = StringFormat("close %.*f above range high %.*f%s, stop at the %s",
                                _Digits, close, _Digits, hi,
                                (InpUseEmaFilter ? ", EMA agrees" : ""),
                                (InpStopAtMidpoint ? "midpoint" : "far side"));
   }
   else if(close < lo)
   {
      if(InpUseEmaFilter && fastMA[1] >= slowMA[1])
      {
         PrintFormat("%s %s: close %.*f below range low %.*f but %s EMA%d %.*f is not below EMA%d %.*f. No trade.",
                     InpComment, SessionTag(s), _Digits, close, _Digits, lo,
                     EnumToString(InpEmaTimeframe),
                     InpFastEmaPeriod, _Digits, fastMA[1],
                     InpSlowEmaPeriod, _Digits, slowMA[1]);
         return(false);
      }
      if(InpFirstBreakOnly && !IsFirstCloseBeyond(ukDay, boxEnd, false, hi, lo))
         return(false);

      signalDir  = -1;
      signalStop = InpStopAtMidpoint ? midpoint : hi;
      signalSpan = span;
      signalHi   = hi;
      signalLo   = lo;
      signalWhy  = StringFormat("close %.*f below range low %.*f%s, stop at the %s",
                                _Digits, close, _Digits, lo,
                                (InpUseEmaFilter ? ", EMA agrees" : ""),
                                (InpStopAtMidpoint ? "midpoint" : "far side"));
   }

   return(signalDir != 0);
}

//+------------------------------------------------------------------+
//| END OF STRATEGY SECTION                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Session definition. All four values are minutes into the UK day.  |
//+------------------------------------------------------------------+
string SessionTag(const int s)
{
   return(s == SESSION_NY ? "NY" : "LON");
}

long SessionMagic(const int s)
{
   return(s == SESSION_NY ? InpMagic + InpNyMagicOffset : InpMagic);
}

//--- Which session a magic number belongs to, or -1 for a stranger's.
int SessionOfMagic(const long magic)
{
   if(magic == InpMagic)                     return(SESSION_LON);
   if(magic == InpMagic + InpNyMagicOffset)  return(SESSION_NY);
   return(-1);
}

bool SessionEnabled(const int s)
{
   return(s == SESSION_NY ? InpTradeNY : InpTradeLondon);
}

int SessionBoxStart(const int s)
{
   return(s == SESSION_NY ? nyBoxStart
                          : InpRangeStartHour * 60 + InpRangeStartMinute);
}

int SessionBoxEnd(const int s)
{
   return(s == SESSION_NY ? nyBoxEnd
                          : InpRangeStartHour * 60 + InpRangeStartMinute + InpRangeMinutes);
}

int SessionLastEntry(const int s)
{
   return(s == SESSION_NY ? nyLastEntry
                          : InpLastEntryHour * 60 + InpLastEntryMinute);
}

int SessionFlatten(const int s)
{
   return(s == SESSION_NY ? nyFlatten
                          : InpFlattenHour * 60 + InpFlattenMinute);
}

//--- "13:30" to 810. False on anything that is not HH:MM in range.
bool ParseUkTime(const string text, int &minutes)
{
   minutes = 0;

   string parts[];
   if(StringSplit(text, StringGetCharacter(":", 0), parts) != 2)
      return(false);

   string hourText   = parts[0];
   string minuteText = parts[1];
   StringTrimLeft(hourText);
   StringTrimRight(hourText);
   StringTrimLeft(minuteText);
   StringTrimRight(minuteText);
   if(StringLen(hourText) == 0 || StringLen(minuteText) == 0)
      return(false);

   int hour   = (int)StringToInteger(hourText);
   int minute = (int)StringToInteger(minuteText);
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return(false);

   minutes = hour * 60 + minute;
   return(true);
}

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
   if(!InpTradeLondon && !InpTradeNY)
   {
      Print("Neither session is enabled. Set InpTradeLondon or InpTradeNY.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpEntryMode == ENTRY_RETEST && InpRetestBars <= 0)
   {
      Print("InpRetestBars must be above zero in RETEST mode.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // The New York times are only parsed and enforced when that session is on,
   // so a malformed string cannot stop a London only run from starting.
   if(InpTradeNY)
   {
      if(InpNyMagicOffset == 0)
      {
         Print("InpNyMagicOffset must not be zero: the two sessions would share one magic number.");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(!ParseUkTime(InpNYStart, nyBoxStart) || !ParseUkTime(InpNYEnd, nyBoxEnd) ||
         !ParseUkTime(InpNYLastEntry, nyLastEntry) || !ParseUkTime(InpNYFlatTime, nyFlatten))
      {
         Print("InpNYStart, InpNYEnd, InpNYLastEntry and InpNYFlatTime must all read HH:MM.");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(nyBoxEnd <= nyBoxStart)
      {
         Print("InpNYEnd must be later than InpNYStart.");
         return(INIT_PARAMETERS_INCORRECT);
      }
      if((nyBoxEnd - nyBoxStart) % barMinutes != 0)
      {
         PrintFormat("The NY box %s to %s is not a whole number of %d minute candles.",
                     InpNYStart, InpNYEnd, barMinutes);
         return(INIT_PARAMETERS_INCORRECT);
      }
      if(nyLastEntry < nyBoxEnd || nyFlatten < nyBoxEnd)
      {
         Print("InpNYLastEntry and InpNYFlatTime must both be later than InpNYEnd.");
         return(INIT_PARAMETERS_INCORRECT);
      }
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

   for(int s = 0; s < SESSION_COUNT; s++)
   {
      sess[s].loggedDay     = 0;
      sess[s].record        = -1;
      sess[s].pendingRecord = -1;
      sess[s].position      = 0;
      sess[s].openTime      = 0;
      sess[s].risk          = 0.0;
      sess[s].exitTag       = "";
   }

   LogBrokerCapabilities();
   PrepareCsv();

   // State is rebuilt from the account, never carried in memory.
   // See skill mql5-patterns, references/state-and-restart.md.
   for(int s = 0; s < SESSION_COUNT; s++)
   {
      if(!SessionEnabled(s))
         continue;
      PrintFormat("%s %s: box %02d:%02d to %02d:%02d UK, last entry %02d:%02d, flat %02d:%02d, "
                  "magic %I64d, mode %s. %d open position(s), %d entry(ies) already today.",
                  InpComment, SessionTag(s),
                  SessionBoxStart(s) / 60, SessionBoxStart(s) % 60,
                  SessionBoxEnd(s) / 60, SessionBoxEnd(s) % 60,
                  SessionLastEntry(s) / 60, SessionLastEntry(s) % 60,
                  SessionFlatten(s) / 60, SessionFlatten(s) % 60,
                  SessionMagic(s), ModeTag(),
                  CountMyPositions(SessionMagic(s)), CountMyEntriesToday(SessionMagic(s)));
   }
   if(!isHedging && InpTradeLondon && InpTradeNY)
      Print("Note: this account is NETTING. A New York entry while a London position is "
            "still open is merged into one net position by the server, whatever the magic "
            "numbers say. On a hedging account the two stay separate.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   FlushAllRecords();

   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   // Never close positions here. OnDeinit also runs on recompile and on a
   // chart template change, and closing then would be a disaster.
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Position management runs on every tick. TP1 is a price level inside the
   // bar, and the session flat is a clock event; neither can wait for a close.
   for(int s = 0; s < SESSION_COUNT; s++)
      SyncTracking(s);
   ManageOpenPositions();
   if(InpEntryMode == ENTRY_RETEST)
      ManagePendingOrders();

   // Entries act once per closed bar.
   datetime current = iTime(_Symbol, WORK_TF, 0);
   if(current == lastBarTime)
      return;

   if(!RefreshIndicators())
      return;                       // not enough bars yet, try again next bar

   lastBarTime = current;

   CheckCloseBackInside();

   for(int s = 0; s < SESSION_COUNT; s++)
   {
      if(!SessionEnabled(s))
         continue;

      // Never enter at or after this session's own flatten time. Without this
      // a session whose last entry time equals its flatten time, which is the
      // New York default, would open a position and close it in the same
      // second. For London, last entry 12:30 against a 20:00 flat, it can
      // never fire.
      if(IsPastFlatten(s))
         continue;

      long magic = SessionMagic(s);
      if(CountMyPositions(magic) >= InpMaxPositions)
         continue;
      if(InpMaxTradesPerDay > 0 && CountMyEntriesToday(magic) >= InpMaxTradesPerDay)
         continue;
      if(CountMyPendingOrders(magic) > 0)
         continue;                  // a retest limit of this session is still live

      if(!DetectSignal(s))
         continue;

      if(!IsSpreadAcceptable())
      {
         PrintFormat("%s %s: signal skipped, spread %d above %d points. %s",
                     InpComment, SessionTag(s), (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
                     InpMaxSpreadPoints, signalWhy);
         continue;
      }

      if(InpEntryMode == ENTRY_RETEST)
         PlaceRetestLimit(s);
      else
         OpenPosition(s, signalDir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   }

   FlushSettledRecords();
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)   // downwards, indices shift
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int s = SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(s < 0) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      bool stale   = (UkDayOf(ServerToUk(opened)) < UkDayOf(ServerToUk(TimeCurrent())));
      bool flatten = IsPastFlatten(s);

      if(flatten || stale)
      {
         sess[s].exitTag = "timecut";
         if(trade.PositionClose(ticket))
            PrintFormat("%s %s: #%I64u closed at the %02d:%02d UK session end.",
                        InpComment, SessionTag(s), ticket,
                        SessionFlatten(s) / 60, SessionFlatten(s) % 60);
         else
         {
            sess[s].exitTag = "";
            PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
         }
         continue;
      }

      HandleFirstTarget(ticket);
   }
}

//+------------------------------------------------------------------+
//| Optional exit: a candle closes back inside the box.               |
//|                                                                   |
//| Off by default. The build this replaced had no such exit, so       |
//| turning it on is a change of strategy, not a bug fix.             |
//+------------------------------------------------------------------+
void CheckCloseBackInside()
{
   if(!InpCloseBackInsideExit)
      return;

   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   double   close   = iClose(_Symbol, WORK_TF, 1);
   if(barTime <= 0 || close <= 0.0)
      return;

   datetime ukDay = UkDayOf(ServerToUk(barTime));

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int s = SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(s < 0) continue;

      double hi = 0.0, lo = 0.0;
      if(!ComputeSessionBox(s, ukDay, hi, lo))
         continue;

      bool isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool inside = isBuy ? (close < hi) : (close > lo);
      if(!inside)
         continue;

      sess[s].exitTag = "backinside";
      if(trade.PositionClose(ticket))
         PrintFormat("%s %s: #%I64u closed, candle closed back inside the box at %.*f.",
                     InpComment, SessionTag(s), ticket, _Digits, close);
      else
      {
         sess[s].exitTag = "";
         PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
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
//| Send a market order. The stop comes from the box, the target is   |
//| a multiple of the box height, and the lot from the real stop       |
//| distance rather than from a fixed point count.                    |
//+------------------------------------------------------------------+
void OpenPosition(const int s, ENUM_ORDER_TYPE type)
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

   int idx = NewRecord(s, signalDir, price, sl, signalHi, signalLo);

   if(isBuy && sl > price - minGap)
   {
      SkipRecord(idx, StringFormat("stop %.*f is not %d points below ask %.*f",
                                   _Digits, sl, (int)stopsLevel, _Digits, price));
      return;
   }
   if(!isBuy && sl < price + minGap)
   {
      SkipRecord(idx, StringFormat("stop %.*f is not %d points above bid %.*f",
                                   _Digits, sl, (int)stopsLevel, _Digits, price));
      return;
   }
   if(MathAbs(tp - price) < minGap)
   {
      SkipRecord(idx, StringFormat("target %.*f is inside the stops level", _Digits, tp));
      return;
   }

   double slDistance = MathAbs(price - sl);
   double lot = CalculateLot(slDistance);
   if(lot <= 0.0)
   {
      SkipRecord(idx, "calculated lot is zero; risk too small or balance too low");
      return;
   }

   trade.SetExpertMagicNumber(SessionMagic(s));

   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment)
                   : trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("%s %s %s %.2f lot at %.*f, SL %.*f, TP1 %.*f, TP2 %.*f | %s",
                  InpComment, SessionTag(s), (isBuy ? "BUY" : "SELL"), lot, _Digits, price,
                  _Digits, sl,
                  _Digits, (isBuy ? price + signalSpan * InpTp1RangeMult
                                  : price - signalSpan * InpTp1RangeMult),
                  _Digits, tp, signalWhy);
      sess[s].pendingRecord = idx;
      SyncTracking(s);
   }
   else
   {
      SkipRecord(idx, StringFormat("order rejected: %s", RetcodeText(code)));
      PrintFormat("Order rejected: %s (retcode %u)", RetcodeText(code), code);
   }
}

//+------------------------------------------------------------------+
//| RETEST mode. Place a limit at the box edge that was broken, with  |
//| the stop on the far side and the same targets as a market entry.   |
//| The order is cancelled by ManagePendingOrders after               |
//| InpRetestBars candles, or if a candle closes back inside the box.  |
//+------------------------------------------------------------------+
void PlaceRetestLimit(const int s)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel < InpMinStopsLevel)
      stopsLevel = InpMinStopsLevel;
   double minGap = (stopsLevel + 1) * _Point;

   bool   isBuy = (signalDir == 1);
   double entry = NormalizePrice(isBuy ? signalHi : signalLo);
   double sl    = NormalizePrice(signalStop);
   double tp    = NormalizePrice(isBuy ? entry + signalSpan * InpTp2RangeMult
                                       : entry - signalSpan * InpTp2RangeMult);

   int idx = NewRecord(s, signalDir, entry, sl, signalHi, signalLo);

   // A buy limit must sit below the ask, a sell limit above the bid, both by
   // the stops level. When price is already back at the box edge the retest
   // has effectively happened inside the break candle, and there is no order
   // to place.
   if(isBuy && entry > ask - minGap)
   {
      SkipRecord(idx, StringFormat("SKIPPED_NO_ROOM: limit %.*f is not %d points below ask %.*f",
                                   _Digits, entry, (int)stopsLevel, _Digits, ask));
      return;
   }
   if(!isBuy && entry < bid + minGap)
   {
      SkipRecord(idx, StringFormat("SKIPPED_NO_ROOM: limit %.*f is not %d points above bid %.*f",
                                   _Digits, entry, (int)stopsLevel, _Digits, bid));
      return;
   }
   if(MathAbs(entry - sl) < minGap || MathAbs(tp - entry) < minGap)
   {
      SkipRecord(idx, "stop or target closer than the broker's minimum distance");
      return;
   }

   double lot = CalculateLot(MathAbs(entry - sl));
   if(lot <= 0.0)
   {
      SkipRecord(idx, "calculated lot is zero; risk too small or balance too low");
      return;
   }

   trade.SetExpertMagicNumber(SessionMagic(s));

   bool ok = isBuy ? trade.BuyLimit (lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment)
                   : trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED))
   {
      PrintFormat("%s %s %s LIMIT %.2f lot at %.*f, SL %.*f, TP1 %.*f, TP2 %.*f, %d candles to fill | %s",
                  InpComment, SessionTag(s), (isBuy ? "BUY" : "SELL"), lot, _Digits, entry,
                  _Digits, sl,
                  _Digits, (isBuy ? entry + signalSpan * InpTp1RangeMult
                                  : entry - signalSpan * InpTp1RangeMult),
                  _Digits, tp, InpRetestBars, signalWhy);
      sess[s].pendingRecord = idx;
   }
   else
   {
      SkipRecord(idx, StringFormat("limit rejected: %s", RetcodeText(code)));
      PrintFormat("Limit order rejected: %s (retcode %u)", RetcodeText(code), code);
   }
}

//+------------------------------------------------------------------+
//| RETEST mode. Cancel a limit that has run out of candles, whose    |
//| box price has closed back inside, or whose session has ended.     |
//|                                                                   |
//| Every test is recomputed from the order and from bars, so this     |
//| works on an order placed before a restart just as well.           |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   int barSeconds = PeriodSeconds(WORK_TF);
   if(barSeconds <= 0)
      return;

   datetime formingBar = iTime(_Symbol, WORK_TF, 0);
   datetime lastBar    = iTime(_Symbol, WORK_TF, 1);
   double   lastClose  = iClose(_Symbol, WORK_TF, 1);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      int s = SessionOfMagic(OrderGetInteger(ORDER_MAGIC));
      if(s < 0) continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT) continue;

      string why = "";

      if(IsPastFlatten(s))
         why = "SKIPPED_SESSION_END";

      if(why == "" && InpRetestBars > 0 && formingBar > 0)
      {
         datetime setup    = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         datetime setupBar = (datetime)((long)setup - ((long)setup % barSeconds));
         if((long)formingBar >= (long)setupBar + (long)InpRetestBars * barSeconds)
            why = "SKIPPED_NO_RETEST";
      }

      if(why == "" && lastBar > 0 && lastClose > 0.0)
      {
         double hi = 0.0, lo = 0.0;
         if(ComputeSessionBox(s, UkDayOf(ServerToUk(lastBar)), hi, lo))
         {
            if(type == ORDER_TYPE_BUY_LIMIT  && lastClose < hi) why = "SKIPPED_BACK_INSIDE";
            if(type == ORDER_TYPE_SELL_LIMIT && lastClose > lo) why = "SKIPPED_BACK_INSIDE";
         }
      }

      if(why == "")
         continue;

      if(trade.OrderDelete(ticket))
      {
         PrintFormat("%s %s: limit #%I64u cancelled, %s.", InpComment, SessionTag(s), ticket, why);
         SettlePending(s, why);
      }
      else
         PrintFormat("Delete failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
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
//| The money a position puts at risk, read from the position itself. |
//+------------------------------------------------------------------+
double RiskMoneyOf(const double volume, const double open, const double sl)
{
   if(volume <= 0.0 || open <= 0.0 || sl <= 0.0)
      return(0.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   return(volume * MathAbs(open - sl) / tickSize * tickValue);
}

//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spread <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Open positions of one magic number on this symbol.               |
//+------------------------------------------------------------------+
int CountMyPositions(const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Pending orders of one magic number on this symbol.                |
//+------------------------------------------------------------------+
int CountMyPendingOrders(const long magic)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == magic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Entries made this session, read from history. Never from a        |
//| counter. This is what makes the one trade per session cap survive |
//| a terminal restart. The day boundary is UK midnight, not the      |
//| server's, so a session is never split across two counts.          |
//|                                                                   |
//| Counted per magic number, which is what keeps the two sessions    |
//| independent: a London trade never uses up New York's one entry.   |
//|                                                                   |
//| "Now" is ServerNow(), not TimeCurrent(). TimeCurrent() is the     |
//| time of the last tick, so over a weekend it stays on Friday night |
//| and Friday's entry was counted as today's on a Sunday attach.     |
//+------------------------------------------------------------------+
int CountMyEntriesToday(const long magic)
{
   datetime now      = ServerNow();
   datetime ukToday  = UkDayOf(ServerToUk(now));
   datetime dayStart = now - (ServerToUk(now) - ukToday);

   if(!HistorySelect(dayStart, now + 60))
      return(0);

   int count = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != magic)   continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL)  != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_IN) continue;
      // Belt and braces: the deal itself must fall on the current UK day.
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(UkDayOf(ServerToUk(dealTime)) != ukToday) continue;
      count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| The current server time, also when the market is closed.          |
//|                                                                   |
//| TimeTradeServer() is computed from the local clock and the        |
//| server's offset, so it keeps running over a weekend. In the       |
//| Strategy Tester TimeCurrent() is the simulated clock and is used. |
//+------------------------------------------------------------------+
datetime ServerNow()
{
   if(MQLInfoInteger(MQL_TESTER))
      return(TimeCurrent());
   datetime live = TimeTradeServer();
   return(live > TimeCurrent() ? live : TimeCurrent());
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
         if(SessionOfMagic(HistoryDealGetInteger(ticket, DEAL_MAGIC)) < 0)  continue;
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
//| session this EA trades.                                          |
//|                                                                   |
//| Both sessions go through this one function, so the New York box    |
//| follows UK daylight saving exactly as the London one does.       |
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
//| True from this session's close time onwards.                      |
//+------------------------------------------------------------------+
bool IsPastFlatten(const int s)
{
   int minute = UkMinuteOfDay(ServerToUk(TimeCurrent()));
   return(minute >= SessionFlatten(s));
}

//+------------------------------------------------------------------+
//| One line per session per day in the journal, so a day with no     |
//| trade can be explained without rerunning anything.                |
//+------------------------------------------------------------------+
void LogSessionOnce(const int s, const datetime ukDay, const string message)
{
   if(sess[s].loggedDay == ukDay)
      return;
   sess[s].loggedDay = ukDay;
   PrintFormat("%s %s %s: %s", InpComment, SessionTag(s),
               TimeToString(ukDay, TIME_DATE), message);
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
      case TRADE_RETCODE_PLACED:            return("PLACED");
      case TRADE_RETCODE_REQUOTE:           return("REQUOTE");
      case TRADE_RETCODE_REJECT:            return("REJECTED");
      case TRADE_RETCODE_INVALID_STOPS:     return("INVALID STOPS");
      case TRADE_RETCODE_INVALID_VOLUME:    return("INVALID VOLUME");
      case TRADE_RETCODE_INVALID_PRICE:     return("INVALID PRICE");
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
//| LOGGING                                                           |
//|                                                                   |
//| One row per break that produced an order attempt, taken or not,   |
//| with the session it belongs to, so a London only run and a two    |
//| session run can be compared from a single file. See skill          |
//| mql5-patterns, references/logging-and-files.md.                   |
//+------------------------------------------------------------------+
string ModeTag()
{
   return(InpEntryMode == ENTRY_RETEST ? "RETEST" : "BREAK");
}

//--- Start a row for the break on the bar that has just closed. The box is
//--- passed in rather than read from the signal globals, so a position adopted
//--- after a restart can be logged without touching them.
int NewRecord(const int s, const int dir, const double entry, const double stop,
              const double boxHi, const double boxLo)
{
   int n = ArraySize(records);
   ArrayResize(records, n + 1);

   datetime barTime = iTime(_Symbol, WORK_TF, 1);

   records[n].signalBar = barTime;
   records[n].ukSignal  = ServerToUk(barTime);
   records[n].session   = s;
   records[n].dir       = dir;
   records[n].mode      = ModeTag();
   records[n].boxHi     = boxHi;
   records[n].boxLo     = boxLo;
   records[n].entry     = entry;
   records[n].stop      = stop;
   records[n].rAtStop   = MathAbs(entry - stop);
   records[n].retest    = (InpEntryMode == ENTRY_RETEST) ? "?" : "-";
   records[n].outcome   = "";
   records[n].reason    = "";
   records[n].rResult   = 0.0;
   records[n].minutes   = 0;
   records[n].profit    = 0.0;
   records[n].settled   = false;
   records[n].written   = false;

   return(n);
}

bool ValidRecord(const int idx)
{
   return(idx >= 0 && idx < ArraySize(records));
}

//--- Mark a signal as not taken and say why, in the log and in the CSV.
void SkipRecord(const int idx, const string reason)
{
   if(!ValidRecord(idx))
      return;

   int s = records[idx].session;

   // A reason that already names its own outcome, SKIPPED_NO_ROOM and the
   // like, becomes the outcome. Anything else is a plain SKIPPED with the
   // detail in the reason column.
   string outcome = "SKIPPED";
   if(StringFind(reason, "SKIPPED_") == 0)
   {
      int colon = StringFind(reason, ":");
      outcome = (colon > 0) ? StringSubstr(reason, 0, colon) : reason;
   }

   records[idx].outcome = outcome;
   records[idx].reason  = CsvSafe(reason);
   records[idx].retest  = (InpEntryMode == ENTRY_RETEST) ? "N" : "-";
   records[idx].settled = true;

   PrintFormat("%s %s: entry skipped, %s. %s", InpComment, SessionTag(s), reason, signalWhy);

   if(sess[s].pendingRecord == idx)
      sess[s].pendingRecord = -1;
}

//--- A retest limit was cancelled. The session is finished either way.
void SettlePending(const int s, const string why)
{
   int idx = sess[s].pendingRecord;
   sess[s].pendingRecord = -1;
   if(!ValidRecord(idx))
      return;

   records[idx].outcome = why;
   records[idx].retest  = "N";
   records[idx].settled = true;
}

//+------------------------------------------------------------------+
//| Adopt a position this EA has opened, or one that was already open |
//| when the terminal restarted, and close its row when it goes.      |
//+------------------------------------------------------------------+
void SyncTracking(const int s)
{
   if(sess[s].position != 0)
   {
      if(!HasPositionWithId(sess[s].position))
         FinaliseClosedTrade(s);
      return;
   }

   ulong id = FindMyPositionId(SessionMagic(s));
   if(id == 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != id) continue;

      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);

      int idx = sess[s].pendingRecord;
      if(!ValidRecord(idx) || records[idx].settled)
      {
         // No row waiting, which happens after a restart. Rebuild one from the
         // position and from the box, both of which are still readable, so the
         // trade is logged even though the signal that opened it is gone.
         double hi = 0.0, lo = 0.0;
         ComputeSessionBox(s, UkDayOf(ServerToUk(TimeCurrent())), hi, lo);
         idx = NewRecord(s, (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1),
                         open, sl, hi, lo);
      }

      records[idx].entry   = open;
      records[idx].stop    = sl;
      records[idx].rAtStop = MathAbs(open - sl);
      records[idx].outcome = "OPEN";
      if(records[idx].retest == "?")
         records[idx].retest = "Y";

      sess[s].record        = idx;
      sess[s].pendingRecord = -1;
      sess[s].position      = id;
      sess[s].openTime      = (datetime)PositionGetInteger(POSITION_TIME);
      sess[s].risk          = RiskMoneyOf(volume, open, sl);
      sess[s].exitTag       = "";
      return;
   }
}

//--- The identifier of an open position of one magic number.
ulong FindMyPositionId(const long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)    continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;
      return((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   }
   return(0);
}

bool HasPositionWithId(const ulong positionId)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return(true);
   }
   return(false);
}

//--- The tracked position has gone. Work out how it ended and close the row.
void FinaliseClosedTrade(const int s)
{
   ulong positionId = sess[s].position;
   if(positionId == 0)
      return;

   double   profit   = 0.0;
   datetime lastTime = 0;
   long     lastWhy  = -1;
   int      outs     = 0;

   if(HistorySelectByPosition(positionId))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         outs++;
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(dealTime >= lastTime)
         {
            lastTime = dealTime;
            lastWhy  = HistoryDealGetInteger(ticket, DEAL_REASON);
         }
      }
   }

   string outcome;
   if(sess[s].exitTag != "")
      outcome = sess[s].exitTag;                    // timecut or backinside
   else if(lastWhy == DEAL_REASON_TP)
      outcome = "TP2";
   else if(lastWhy == DEAL_REASON_SL)
      outcome = (outs > 1) ? (InpMoveToBreakEven ? "BE" : "TP1") : "SL";
   else
      outcome = "closed";

   int idx = sess[s].record;
   if(ValidRecord(idx))
   {
      records[idx].outcome = outcome;
      records[idx].profit  = profit;
      records[idx].rResult = (sess[s].risk > 0.0) ? profit / sess[s].risk : 0.0;
      records[idx].minutes = (lastTime > sess[s].openTime)
                             ? (int)((lastTime - sess[s].openTime) / 60) : 0;
      records[idx].settled = true;

      PrintFormat("%s %s: %s %s closed %s, %.2f R (%.2f), %d minutes in trade.",
                  InpComment, SessionTag(s),
                  TimeToString(records[idx].ukSignal, TIME_DATE | TIME_MINUTES),
                  (records[idx].dir > 0 ? "BUY" : "SELL"),
                  outcome, records[idx].rResult, profit, records[idx].minutes);
   }

   sess[s].record   = -1;
   sess[s].position = 0;
   sess[s].openTime = 0;
   sess[s].risk     = 0.0;
   sess[s].exitTag  = "";
}

//--- A comma in a free text column would change the column count.
string CsvSafe(const string text)
{
   string clean = text;
   StringReplace(clean, ",", ";");
   return(clean);
}

//--- Open the CSV, write the header if the file is new. In the tester the
//--- file is truncated instead, so one run is one file.
void PrepareCsv()
{
   if(!InpCsvLog || csvHeaderChecked)
      return;
   csvHeaderChecked = true;

   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(MQLInfoInteger(MQL_TESTER))
      flags = FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpCsvCommonFolder)
      flags |= FILE_COMMON;

   int h = FileOpen(InpCsvFile, flags);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("%s: cannot open %s for logging, error %d. Logging to the journal only.",
                  InpComment, InpCsvFile, GetLastError());
      return;
   }

   if(FileSize(h) == 0)
      FileWrite(h, "date,time_uk,session,mode,direction,box_low,box_high,box_height,"
                   "entry,stop,r_at_stop,retest,outcome,r_result,minutes_in_trade,"
                   "profit_usd,reason");
   FileClose(h);

   PrintFormat("%s: signal log at %s%s",
               InpComment, (InpCsvCommonFolder ? "Common\\Files\\" : "MQL5\\Files\\"), InpCsvFile);
}

//--- Append one finished row.
void WriteRecord(const int i)
{
   if(records[i].written)
      return;
   records[i].written = true;

   if(!InpCsvLog)
      return;

   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpCsvCommonFolder)
      flags |= FILE_COMMON;

   int h = FileOpen(InpCsvFile, flags);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);

   string line = StringFormat("%s,%s,%s,%s,%s,%.*f,%.*f,%.2f,%.*f,%.*f,%.*f,%s,%s,%.3f,%d,%.2f,%s",
                              TimeToString(records[i].ukSignal, TIME_DATE),
                              TimeToString(records[i].ukSignal, TIME_MINUTES),
                              SessionTag(records[i].session),
                              records[i].mode,
                              (records[i].dir > 0 ? "BUY" : "SELL"),
                              _Digits, records[i].boxLo,
                              _Digits, records[i].boxHi,
                              records[i].boxHi - records[i].boxLo,
                              _Digits, records[i].entry,
                              _Digits, records[i].stop,
                              _Digits, records[i].rAtStop,
                              records[i].retest,
                              records[i].outcome,
                              records[i].rResult,
                              records[i].minutes,
                              records[i].profit,
                              records[i].reason);
   FileWrite(h, line);
   FileClose(h);
}

//--- Write every settled row, then drop the written ones so the array does
//--- not grow without limit.
void FlushSettledRecords()
{
   int n = ArraySize(records);
   for(int i = 0; i < n; i++)
      if(records[i].settled && !records[i].written)
         WriteRecord(i);

   CompactRecords();
}

//--- End of the run. Write whatever is left, unsettled rows included.
void FlushAllRecords()
{
   int n = ArraySize(records);
   for(int i = 0; i < n; i++)
   {
      if(records[i].written)
         continue;
      if(records[i].outcome == "")
         records[i].outcome = "UNSETTLED";
      WriteRecord(i);
   }
}

//--- Drop written rows, keeping the indices the session state points at.
void CompactRecords()
{
   int n = ArraySize(records);
   if(n == 0)
      return;

   int keep[];
   ArrayResize(keep, n);
   int kept = 0;
   for(int i = 0; i < n; i++)
   {
      bool referenced = false;
      for(int s = 0; s < SESSION_COUNT; s++)
         if(sess[s].record == i || sess[s].pendingRecord == i)
            referenced = true;
      if(!records[i].written || referenced)
      {
         keep[kept] = i;
         kept++;
      }
   }
   if(kept == n)
      return;

   SignalRecord fresh[];
   ArrayResize(fresh, kept);
   for(int j = 0; j < kept; j++)
   {
      fresh[j] = records[keep[j]];
      for(int s = 0; s < SESSION_COUNT; s++)
      {
         if(sess[s].record        == keep[j]) sess[s].record        = j;
         if(sess[s].pendingRecord == keep[j]) sess[s].pendingRecord = j;
      }
   }

   ArrayResize(records, kept);
   for(int j = 0; j < kept; j++)
      records[j] = fresh[j];
}
//+------------------------------------------------------------------+
