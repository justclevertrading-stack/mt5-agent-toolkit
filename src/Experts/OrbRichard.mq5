//+------------------------------------------------------------------+
//| OrbRichard.mq5                                                    |
//|                                                                   |
//| Richard's hand method. Opening range retest on XAUUSD M5, London  |
//| and New York. BACKTESTING ONLY: this EA is not for a live chart.  |
//|                                                                   |
//| Box        LON 08:00-08:15 UK, NY 13:30-13:45 UK, high and low    |
//|            of the M5 candles inside. Range filter in points.      |
//| Permission H1 EMA9 vs EMA21 on the last closed H1 bar at the box  |
//|            end. Long only if EMA9 > EMA21, short only if below.  |
//|            Within InpFlatEmaPct of each other: no trade at all.   |
//| Signal     first M5 close beyond the permitted edge. Not an entry.|
//| Retest     within InpRetestBars candles price comes back to the   |
//|            edge zone (edge +/- InpRetestZoneMult x box) and a     |
//|            candle closes back beyond the edge. Enter at market   |
//|            on that close.                                         |
//| NY run     NY only: the break runs >= 1 box within 2 candles with |
//|            no retest. Enter on the next close beyond the break    |
//|            candle's extreme, inside the same retest window.      |
//| Lid        highest high since the signal >= edge + 1 box and the  |
//|            candle after it closed below that high - 0.3 box:     |
//|            the side is finished.                                  |
//| Re-arm     a close back inside the box before an entry re-arms    |
//|            the side once: two signals per side per session. A     |
//|            signal whose retest window expired also re-arms on a  |
//|            later close back inside. InpSecondBreak off (R4): no   |
//|            re-arm, the first signal's end finishes the side.      |
//| Stop       box midpoint (InpStopAtFarSide for the far side).      |
//|            To entry once price is 0.5 box in favour.              |
//| Targets    TP1 1.0 box from the edge, half closed. TP2 2.0 box,   |
//|            or the runner exits on the first M5 candle that closes |
//|            against the trade after 1.5 box has been reached.      |
//|            NY run entries measure all of these from the entry.    |
//| Time       no entries from 11:30 (LON) / 16:00 (NY) UK,           |
//|            flat 16:00 (LON) / 18:00 (NY) UK.                      |
//|                                                                   |
//| Every rule is decided by replaying the session's closed M5 bars   |
//| from the box end, see ReplaySession. Nothing that decides a trade |
//| lives only in memory.                                             |
//|                                                                   |
//| Built from OrbLondon.mq5 (itself from templates/EA_Template.mq5): |
//| risk sizing, broker detection, order normalisation, result        |
//| checking, UK time and CSV logging are that EA's, unchanged.       |
//| Specification: strategies/OrbRichard.md                           |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.00"
#property description "Richard's opening range retest, London and New York, M5. Backtesting only."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Sessions, all times UK (Europe/London) ===";
input bool   InpTradeLondon      = true;    // Trade the London box
input bool   InpTradeNY          = true;    // Trade the New York box
input int    InpBoxMinutes       = 15;      // Box length, minutes, both sessions
input string InpLonStart         = "08:00"; // London box starts, UK HH:MM
input string InpLonLastEntry     = "11:30"; // No London entry on a candle opening from here
input string InpLonFlatTime      = "16:00"; // Close any London position at this UK time
input string InpNYStart          = "13:30"; // NY box starts, UK HH:MM
input string InpNYLastEntry      = "16:00"; // No NY entry on a candle opening from here
input string InpNYFlatTime       = "18:00"; // Close any NY position at this UK time
input long   InpNyMagicOffset    = 1;       // Added to InpMagic for NY trades
// Comma list of UK dates, yyyy.mm.dd, on which neither session trades. For a
// second run without Fed and NFP days.
input string InpSkipDates        = "";      // UK dates to skip, comma separated

input group "=== Server time zone ===";
input int    InpServerUtcOffsetWinter = 2;  // Server UTC offset outside EU DST
input int    InpServerUtcOffsetSummer = 3;  // Server UTC offset during EU DST

input group "=== Box and permission ===";
// In the symbol's points: $5 to $25 on a 2 digit XAUUSD, as in OrbLondon.
input int    InpMinRangePoints   = 500;     // Skip session below this box height, points
input int    InpMaxRangePoints   = 2500;    // Skip session above this box height, points
input ENUM_TIMEFRAMES InpEmaTimeframe = PERIOD_H1; // Timeframe of the permission EMAs
input int    InpFastEmaPeriod    = 9;       // Fast EMA period
input int    InpSlowEmaPeriod    = 21;      // Slow EMA period
input double InpFlatEmaPct       = 0.05;    // EMAs closer than this % of EMA21: no permission

input group "=== Entry ===";
input int    InpRetestBars       = 6;       // Candles after the signal allowed for the entry
input double InpRetestZoneMult   = 0.125;   // Edge zone, box heights (0.5 x box / 4)
input bool   InpNyRunEntry       = true;    // Rule 5: NY no-retest entry on a run
input double InpNyRunMult        = 1.0;     // Rule 5: run needed, box heights beyond the edge
input int    InpNyRunBars        = 2;       // Rule 5: candles after the signal the run must come in

input group "=== Exits ===";
input double InpBeMult           = 0.5;     // Stop to entry at this many box heights in favour
input double InpTp1Mult          = 1.0;     // TP1, box heights from the edge
input double InpTp1ClosePercent  = 50.0;    // Percent of the position closed at TP1
input double InpTp2Mult          = 2.0;     // TP2, box heights from the edge
input double InpRunnerArmMult    = 1.5;     // Runner exit armed at this many box heights

input group "=== Variants. R1 is every one of these at its default ===";
input bool   InpStopAtFarSide    = false;   // R2: stop at the far side, not the midpoint
input bool   InpUseLid           = true;    // R3 sets false: rule 6, the lid
input double InpLidMult          = 1.0;     // Lid: extreme at least this many box heights out
input double InpLidPullbackMult  = 0.3;     // Lid: next candle closes this far back from it
input bool   InpSecondBreak      = true;    // R4 sets false: rule 7, re-arm after a failed break

input group "=== Risk management ===";
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance
input int    InpMinStopsLevel    = 20;      // Floor under the broker's stops level, points
// Accounting only, as in OrbLondon: the tester charges no commission.
input double InpCommissionPerLot = 0.0;     // Round-trip commission, $ per lot

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points

input group "=== Logging ===";
input bool   InpCsvLog           = true;    // Append one row per signal to a CSV
input string InpCsvFile          = "orbrichard_log.csv"; // File under MQL5\Files
input bool   InpCsvCommonFolder  = false;   // Write to the shared Common\Files instead

input group "=== Identity ===";
input long   InpMagic            = 20261011; // Magic number, London
input string InpComment          = "OrbRichard"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
#define WORK_TF        PERIOD_M5
#define SCAN_BARS      400
#define SESSION_LON    0
#define SESSION_NY     1
#define SESSION_COUNT  2

// Entry types, carried in the order comment so the exit levels can be
// rebuilt from the position alone.
#define ENTRY_NONE     0
#define ENTRY_RETEST   1
#define ENTRY_RUN      2

// What the replay saw happen on the bar that has just closed.
#define EV_NONE        0
#define EV_SIGNAL      1
#define EV_ENTER       2
#define EV_REARM       3
#define EV_BACK_INSIDE 4
#define EV_LID         5
#define EV_NO_RETEST   6
#define EV_TIME        7

CTrade   trade;
int      fastHandle  = INVALID_HANDLE;
int      slowHandle  = INVALID_HANDLE;
datetime lastBarTime = 0;
bool     isHedging   = false;

// Session times, minutes into the UK day, parsed once in OnInit.
int      boxStart[SESSION_COUNT];
int      boxEnd[SESSION_COUNT];
int      lastEntry[SESSION_COUNT];
int      flatTime[SESSION_COUNT];

datetime skipDays[];

// The result of replaying one session up to the bar that has just closed.
struct ReplayResult
{
   int      event;          // EV_*, for the bar that has just closed only
   int      entryType;      // ENTRY_* when event is EV_ENTER
   int      signalNo;       // 1 or 2, the signal the event belongs to
   datetime signalBar;      // server time of that signal candle
   string   text;           // what happened, for the journal and the CSV
};

//+------------------------------------------------------------------+
//| Per session bookkeeping. Diagnostics and caches only.             |
//+------------------------------------------------------------------+
struct SessionState
{
   datetime loggedDay;      // the UK day already described in the journal
   datetime permDay;        // UK day the permission below was read for
   int      permDir;        // +1 long only, -1 short only, 0 none
   int      record;         // index into records for the open trade, -1 none
   int      pendingRecord;  // index into records for an order just sent
   ulong    position;       // POSITION_IDENTIFIER being tracked
   datetime openTime;
   double   risk;           // money at risk when the position opened
   string   exitTag;        // set immediately before a close this EA decides
   ulong    planPosition;   // position the exit levels below belong to
   double   planBox;
   double   planBase;       // level the targets are measured from
};

SessionState sess[SESSION_COUNT];

//+------------------------------------------------------------------+
//| One row of the CSV, held until every column is known.             |
//+------------------------------------------------------------------+
struct SignalRecord
{
   datetime signalBar;      // server time of the signal candle
   datetime ukSignal;       // UK time of the signal candle
   datetime ukEntry;        // UK time of the entry candle, 0 when none
   int      session;
   int      dir;
   int      signalNo;
   string   mode;           // RETEST, RUN, or - for a signal never entered
   double   boxHi;
   double   boxLo;
   double   entry;
   double   stop;
   double   rAtStop;
   string   retest;         // Y entered, N not entered
   string   outcome;
   string   reason;
   double   rResult;
   int      minutes;
   double   profit;
   bool     settled;
   bool     written;
};

SignalRecord records[];
bool     csvHeaderChecked = false;

// The entry the strategy section asked for on the bar that has just closed.
int      signalDir  = 0;
double   signalStop = 0.0;
double   signalBox  = 0.0;
double   signalHi   = 0.0;
double   signalLo   = 0.0;
int      signalType = ENTRY_NONE;
string   signalWhy  = "";
int      replaySignalNo  = 0;       // signal number and candle of that entry
datetime replaySignalBar = 0;

//+------------------------------------------------------------------+
//| STRATEGY                                                    |
//+------------------------------------------------------------------+

//--- The box of the UK day ukDay, for [startMinute, endMinute).
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
      if(UkDayOf(uk) > ukDay)
         continue;                            // a later day, keep walking back
      if(UkDayOf(uk) < ukDay)
         break;                               // walked back into an earlier day

      int minute = UkMinuteOfDay(uk);
      if(minute < startMinute)
         break;
      if(minute >= endMinute)
         continue;

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

bool ComputeSessionBox(const int s, const datetime ukDay, double &hi, double &lo)
{
   return(ComputeBox(ukDay, boxStart[s], boxEnd[s], hi, lo));
}

//--- Rule 2. The direction this session may trade, read once per day from
//--- the last closed bar of InpEmaTimeframe at the box end. boxEndServer is
//--- the open time of the first M5 candle after the box.
int ReadPermission(const int s, const datetime ukDay, const datetime boxEndServer)
{
   if(sess[s].permDay == ukDay)
      return(sess[s].permDir);

   int dir = 0;
   int shift = iBarShift(_Symbol, InpEmaTimeframe, boxEndServer, false);
   double f[1], w[1];
   if(shift < 0 ||
      CopyBuffer(fastHandle, 0, shift + 1, 1, f) < 1 ||
      CopyBuffer(slowHandle, 0, shift + 1, 1, w) < 1 || w[0] <= 0.0)
   {
      // Not cached, so a missing bar is retried on the next candle.
      PrintFormat("%s %s: %s EMAs not readable at the box end, no permission yet.",
                  InpComment, SessionTag(s), EnumToString(InpEmaTimeframe));
      return(0);
   }

   double gapPct = MathAbs(f[0] - w[0]) / w[0] * 100.0;
   string text;
   if(gapPct < InpFlatEmaPct)
      text = StringFormat("EMA%d %.*f and EMA%d %.*f are %.3f%% apart, under %.2f%%: flat, session skipped",
                          InpFastEmaPeriod, _Digits, f[0], InpSlowEmaPeriod, _Digits, w[0],
                          gapPct, InpFlatEmaPct);
   else
   {
      dir = (f[0] > w[0]) ? 1 : -1;
      text = StringFormat("EMA%d %.*f %s EMA%d %.*f (%.3f%%): %s only",
                          InpFastEmaPeriod, _Digits, f[0], (dir > 0 ? ">" : "<"),
                          InpSlowEmaPeriod, _Digits, w[0], gapPct, (dir > 0 ? "long" : "short"));
   }

   sess[s].permDay = ukDay;
   sess[s].permDir = dir;
   PrintFormat("%s %s %s: %s %s", InpComment, SessionTag(s), TimeToString(ukDay, TIME_DATE),
               EnumToString(InpEmaTimeframe), text);
   return(dir);
}

//--- Replay the session from the box end to the bar that has just closed
//--- (index 1), applying rules 3 to 7 candle by candle, and report what
//--- happened on that last bar. Distances are signed with dir so one code
//--- path serves both sides: "beyond" is positive on the breakout side.
void ReplaySession(const int s, const datetime ukDay, const int dir,
                   const double hi, const double lo, const int firstBar,
                   ReplayResult &res)
{
   res.event     = EV_NONE;
   res.entryType = ENTRY_NONE;
   res.signalNo  = 0;
   res.signalBar = 0;
   res.text      = "";

   double box  = hi - lo;
   double edge = (dir > 0) ? hi : lo;
   double zone = InpRetestZoneMult * box;

   int      state      = 0;        // 0 armed, 1 signalled, 2 done, 3 expired awaiting a close inside
   int      signals    = 0;
   int      k          = 0;        // candles since the signal candle
   datetime sigBar     = 0;
   double   sigExtreme = 0.0;      // signal candle's high (long) or low (short)
   double   runMax     = 0.0;      // furthest favourable extreme since the signal, beyond the edge
   int      runMaxBar  = -1;
   bool     touched    = false;
   bool     runReady   = false;

   for(int i = firstBar; i >= 1; i--)
   {
      if(state == 2)
         break;

      datetime barTime = iTime(_Symbol, WORK_TF, i);
      int      minute  = UkMinuteOfDay(ServerToUk(barTime));
      double   o = iOpen (_Symbol, WORK_TF, i);
      double   h = iHigh (_Symbol, WORK_TF, i);
      double   l = iLow  (_Symbol, WORK_TF, i);
      double   c = iClose(_Symbol, WORK_TF, i);
      bool     last = (i == 1);

      // Rule 10. A candle opening at the last entry time cannot be entered on.
      if(minute >= lastEntry[s])
      {
         if(state == 1 && last)
         {
            res.event     = EV_TIME;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = "SKIPPED_TIME: last entry time reached while waiting for the retest";
         }
         break;
      }

      double fav     = (dir > 0) ? h : l;
      double adv     = (dir > 0) ? l : h;
      double closeIn = dir * (c - edge);           // > 0 closed beyond the edge
      double favOut  = dir * (fav - edge);
      double advOut  = dir * (adv - edge);

      // state 3: the signal expired unentered; only a close back inside the
      // box matters now, and it re-arms the side. Not logged as its own row.
      if(state == 3)
      {
         if(closeIn < 0.0)
            state = 0;
         continue;
      }

      if(state == 0)
      {
         if(closeIn <= 0.0)
            continue;

         // Rule 3. A close beyond the permitted edge is a signal.
         state      = 1;
         signals++;
         k          = 0;
         sigBar     = barTime;
         sigExtreme = fav;
         runMax     = favOut;
         runMaxBar  = i;
         touched    = false;
         runReady   = (s == SESSION_NY && InpNyRunEntry && runMax >= InpNyRunMult * box);
         if(last)
         {
            res.event     = EV_SIGNAL;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("signal %d: close %.*f %s the box %s %.*f",
                                         signals, _Digits, c, (dir > 0 ? "above" : "below"),
                                         (dir > 0 ? "high" : "low"), _Digits, edge);
         }
         continue;
      }

      // state == 1, a signal is waiting.
      k++;

      // Rule 6, the lid. Judged before anything else on this candle: a candle
      // that both closes well back from the extreme and lands in the edge zone
      // is the rejection beyond, not a retest.
      if(favOut > runMax)
      {
         runMax    = favOut;
         runMaxBar = i;
      }
      else if(InpUseLid && runMaxBar == i + 1 && runMax >= InpLidMult * box &&
              closeIn < runMax - InpLidPullbackMult * box)
      {
         state = 2;
         if(last)
         {
            res.event     = EV_LID;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("SKIPPED_LID: extreme %.*f is %.2f boxes out and the next candle closed %.*f; side finished",
                                         _Digits, edge + dir * runMax, runMax / box, _Digits, c);
         }
         continue;
      }

      // Rule 7. Back inside the box before an entry.
      if(closeIn < 0.0)
      {
         bool rearm = (InpSecondBreak && signals < 2);
         state = rearm ? 0 : 2;
         if(last)
         {
            res.event     = rearm ? EV_REARM : EV_BACK_INSIDE;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("%s: close %.*f back inside the box; %s",
                                         (rearm ? "SKIPPED_REARM" : "SKIPPED_BACK_INSIDE"), _Digits, c,
                                         (rearm ? "side re-armed for a second signal" : "side finished"));
         }
         continue;
      }

      // Rule 4. The retest: price back in the edge zone, close beyond the edge.
      if(advOut <= zone)
         touched = true;
      if(k <= InpRetestBars && touched && closeIn > 0.0)
      {
         state = 2;
         if(last)
         {
            res.event     = EV_ENTER;
            res.entryType = ENTRY_RETEST;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("retest %d candle(s) after signal %d: low/high %.*f within %.*f of the edge %.*f, close %.*f",
                                         k, signals, _Digits, adv, _Digits, zone, _Digits, edge, _Digits, c);
         }
         continue;
      }

      // Rule 5. NY only: a run of a box within InpNyRunBars candles, untouched,
      // then a close beyond the signal candle's extreme.
      if(s == SESSION_NY && InpNyRunEntry && !touched && k <= InpNyRunBars &&
         runMax >= InpNyRunMult * box)
         runReady = true;
      if(runReady && !touched && k <= InpRetestBars && dir * (c - sigExtreme) > 0.0)
      {
         state = 2;
         if(last)
         {
            res.event     = EV_ENTER;
            res.entryType = ENTRY_RUN;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("no-retest run: %.2f boxes out with no retest, close %.*f beyond the break candle's %.*f",
                                         runMax / box, _Digits, c, _Digits, sigExtreme);
         }
         continue;
      }

      // The window ran out. With re-arm on (R1) the side waits for a close
      // back inside, which re-arms it for its second signal; with it off (R4),
      // or with both signals used, the side is finished.
      if(k >= InpRetestBars)
      {
         bool wait = (InpSecondBreak && signals < 2);
         state = wait ? 3 : 2;
         if(last)
         {
            res.event     = EV_NO_RETEST;
            res.signalNo  = signals;
            res.signalBar = sigBar;
            res.text      = StringFormat("SKIPPED_NO_RETEST: no retest within %d candles; %s", InpRetestBars,
                                         (wait ? "side waits for a close back inside to re-arm" : "side finished"));
         }
      }
      continue;
   }
}

//--- Look at the bar that has just closed for this session. Returns true when
//--- an entry is due, with the signal globals set. Signals that end without an
//--- entry are written to the CSV here.
bool DetectSignal(const int s)
{
   signalDir  = 0;
   signalType = ENTRY_NONE;
   signalWhy  = "";

   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   if(barTime <= 0)
      return(false);

   datetime uk     = ServerToUk(barTime);
   datetime ukDay  = UkDayOf(uk);
   int      minute = UkMinuteOfDay(uk);

   if(minute < boxEnd[s] || minute > lastEntry[s])
      return(false);                           // box not locked, or long past entries

   if(IsSkipDay(ukDay))
   {
      LogSessionOnce(s, ukDay, "date listed in InpSkipDates, session skipped");
      return(false);
   }

   double hi = 0.0, lo = 0.0;
   if(!ComputeSessionBox(s, ukDay, hi, lo))
   {
      LogSessionOnce(s, ukDay, "box incomplete, session skipped");
      return(false);
   }

   double span = hi - lo;
   int spanPoints = (int)MathRound(span / _Point);
   if(span < InpMinRangePoints * _Point || span > InpMaxRangePoints * _Point)
   {
      LogSessionOnce(s, ukDay, StringFormat("box %.*f (%d points) outside %d to %d points, session skipped",
                                            _Digits, span, spanPoints, InpMinRangePoints, InpMaxRangePoints));
      return(false);
   }
   LogSessionOnce(s, ukDay, StringFormat("box %.*f to %.*f, height %.*f (%d points)",
                                         _Digits, lo, _Digits, hi, _Digits, span, spanPoints));

   // The oldest candle after the box, where the replay starts.
   int firstBar = 0;
   for(int i = 1; i <= SCAN_BARS; i++)
   {
      datetime t = iTime(_Symbol, WORK_TF, i);
      if(t <= 0) break;
      datetime u = ServerToUk(t);
      if(UkDayOf(u) != ukDay || UkMinuteOfDay(u) < boxEnd[s])
         break;
      firstBar = i;
   }
   if(firstBar == 0)
      return(false);

   int dir = ReadPermission(s, ukDay, iTime(_Symbol, WORK_TF, firstBar));
   if(dir == 0)
      return(false);

   ReplayResult res;
   ReplaySession(s, ukDay, dir, hi, lo, firstBar, res);
   if(res.event == EV_NONE)
      return(false);

   if(res.event == EV_SIGNAL)
   {
      PrintFormat("%s %s: %s", InpComment, SessionTag(s), res.text);
      return(false);
   }

   if(res.event != EV_ENTER)
   {
      int idx = NewRecord(s, dir, res.signalNo, res.signalBar, 0, "-", 0.0, 0.0, hi, lo);
      SkipRecord(idx, res.text);
      return(false);
   }

   double midpoint = (hi + lo) / 2.0;
   signalDir  = dir;
   signalType = res.entryType;
   signalStop = InpStopAtFarSide ? (dir > 0 ? lo : hi) : midpoint;
   signalBox  = span;
   signalHi   = hi;
   signalLo   = lo;
   signalWhy  = StringFormat("%s, stop at the %s", res.text, (InpStopAtFarSide ? "far side" : "midpoint"));

   // Remembered for the row this entry writes.
   replaySignalNo  = res.signalNo;
   replaySignalBar = res.signalBar;
   return(true);
}

//+------------------------------------------------------------------+
//| END OF STRATEGY SECTION                                           |
//+------------------------------------------------------------------+

string SessionTag(const int s)
{
   return(s == SESSION_NY ? "NY" : "LON");
}

long SessionMagic(const int s)
{
   return(s == SESSION_NY ? InpMagic + InpNyMagicOffset : InpMagic);
}

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

string EntryTypeTag(const int type)
{
   if(type == ENTRY_RUN)    return("RUN");
   if(type == ENTRY_RETEST) return("RETEST");
   return("-");
}

//--- The order comment carries the entry type, which decides what the
//--- targets are measured from.
int EntryTypeOfComment(const string comment)
{
   return(StringFind(comment, " RUN") >= 0 ? ENTRY_RUN : ENTRY_RETEST);
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

//--- InpSkipDates to a list of UK midnights. False on a malformed date.
bool ParseSkipDates()
{
   ArrayResize(skipDays, 0);
   string list = InpSkipDates;
   StringTrimLeft(list);
   StringTrimRight(list);
   if(StringLen(list) == 0)
      return(true);

   string parts[];
   int n = StringSplit(list, StringGetCharacter(",", 0), parts);
   for(int i = 0; i < n; i++)
   {
      string d = parts[i];
      StringTrimLeft(d);
      StringTrimRight(d);
      if(StringLen(d) == 0)
         continue;
      datetime t = StringToTime(d);
      if(t <= 0 || StringLen(d) != 10)
      {
         PrintFormat("InpSkipDates: '%s' is not a yyyy.mm.dd date.", d);
         return(false);
      }
      int m = ArraySize(skipDays);
      ArrayResize(skipDays, m + 1);
      skipDays[m] = UkDayOf(t);
   }
   PrintFormat("%s: %d date(s) skipped from InpSkipDates.", InpComment, ArraySize(skipDays));
   return(true);
}

bool IsSkipDay(const datetime ukDay)
{
   for(int i = ArraySize(skipDays) - 1; i >= 0; i--)
      if(skipDays[i] == ukDay)
         return(true);
   return(false);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(MQLInfoInteger(MQL_TESTER) == 0)
      Print("WARNING: OrbRichard is built for the Strategy Tester only. It is not approved for a live chart.");

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
   if(InpMinRangePoints <= 0 || InpMaxRangePoints < InpMinRangePoints)
   {
      Print("Range height bounds are inconsistent.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp1Mult <= 0.0 || InpTp2Mult <= InpTp1Mult || InpRunnerArmMult <= 0.0)
   {
      Print("Targets must satisfy 0 < InpTp1Mult < InpTp2Mult, and InpRunnerArmMult above zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp1ClosePercent <= 0.0 || InpTp1ClosePercent >= 100.0)
   {
      Print("InpTp1ClosePercent must be between 0 and 100 exclusive.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpRetestBars <= 0 || InpNyRunBars < 0)
   {
      Print("InpRetestBars must be above zero and InpNyRunBars not negative.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   int barMinutes = PeriodSeconds(WORK_TF) / 60;
   if(barMinutes <= 0 || InpBoxMinutes <= 0 || InpBoxMinutes % barMinutes != 0)
   {
      PrintFormat("InpBoxMinutes %d is not a whole number of %d minute candles.", InpBoxMinutes, barMinutes);
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(!InpTradeLondon && !InpTradeNY)
   {
      Print("Neither session is enabled. Set InpTradeLondon or InpTradeNY.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpNyMagicOffset == 0)
   {
      Print("InpNyMagicOffset must not be zero: the two sessions would share one magic number.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(!ParseUkTime(InpLonStart, boxStart[SESSION_LON]) ||
      !ParseUkTime(InpLonLastEntry, lastEntry[SESSION_LON]) ||
      !ParseUkTime(InpLonFlatTime, flatTime[SESSION_LON]) ||
      !ParseUkTime(InpNYStart, boxStart[SESSION_NY]) ||
      !ParseUkTime(InpNYLastEntry, lastEntry[SESSION_NY]) ||
      !ParseUkTime(InpNYFlatTime, flatTime[SESSION_NY]))
   {
      Print("Every session time input must read HH:MM.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   for(int s = 0; s < SESSION_COUNT; s++)
   {
      boxEnd[s] = boxStart[s] + InpBoxMinutes;
      if(lastEntry[s] < boxEnd[s] || flatTime[s] < lastEntry[s])
      {
         PrintFormat("%s: the box must end before the last entry time, and that must not be after the flat time.",
                     SessionTag(s));
         return(INIT_PARAMETERS_INCORRECT);
      }
   }
   if(!ParseSkipDates())
      return(INIT_PARAMETERS_INCORRECT);

   fastHandle = iMA(_Symbol, InpEmaTimeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, InpEmaTimeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(PickFillingMode());
   trade.SetDeviationInPoints(10);

   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   for(int s = 0; s < SESSION_COUNT; s++)
   {
      sess[s].loggedDay     = 0;
      sess[s].permDay       = 0;
      sess[s].permDir       = 0;
      sess[s].record        = -1;
      sess[s].pendingRecord = -1;
      sess[s].position      = 0;
      sess[s].openTime      = 0;
      sess[s].risk          = 0.0;
      sess[s].exitTag       = "";
      sess[s].planPosition  = 0;
      sess[s].planBox       = 0.0;
      sess[s].planBase      = 0.0;
   }

   LogBrokerCapabilities();
   PrepareCsv();

   for(int s = 0; s < SESSION_COUNT; s++)
   {
      if(!SessionEnabled(s))
         continue;
      PrintFormat("%s %s: box %02d:%02d to %02d:%02d UK, last entry %02d:%02d, flat %02d:%02d, magic %I64d. "
                  "Stop %s, lid %s, second break %s%s.",
                  InpComment, SessionTag(s),
                  boxStart[s] / 60, boxStart[s] % 60, boxEnd[s] / 60, boxEnd[s] % 60,
                  lastEntry[s] / 60, lastEntry[s] % 60, flatTime[s] / 60, flatTime[s] % 60,
                  SessionMagic(s), (InpStopAtFarSide ? "far side" : "midpoint"),
                  (InpUseLid ? "on" : "off"), (InpSecondBreak ? "on" : "off"),
                  (s == SESSION_NY ? (InpNyRunEntry ? ", run entry on" : ", run entry off") : ""));
   }
   if(!isHedging && InpTradeLondon && InpTradeNY)
      Print("Note: this account is NETTING. London (flat 16:00) and New York (entries from 13:45) "
            "positions can overlap and would be merged into one net position.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   FlushAllRecords();

   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Break even, TP1 and the session flat are price and clock events inside
   // the bar, so they run on every tick.
   for(int s = 0; s < SESSION_COUNT; s++)
      SyncTracking(s);
   ManageOpenPositions();

   datetime current = iTime(_Symbol, WORK_TF, 0);
   if(current == lastBarTime)
      return;
   lastBarTime = current;

   // The runner exit reads the candle that has just closed.
   CheckRunnerExit();

   for(int s = 0; s < SESSION_COUNT; s++)
   {
      if(!SessionEnabled(s))
         continue;
      if(IsPastFlatten(s))
         continue;

      // The replay runs even with a position open, so signals that end
      // without an entry are logged; it can only ask for one entry per side.
      if(!DetectSignal(s))
         continue;

      long magic = SessionMagic(s);
      if(CountMyPositions(magic) > 0 || CountMyEntriesToday(magic) > 0)
      {
         int idx = NewRecord(s, signalDir, replaySignalNo, replaySignalBar, iTime(_Symbol, WORK_TF, 1),
                             EntryTypeTag(signalType), 0.0, signalStop, signalHi, signalLo);
         SkipRecord(idx, "SKIPPED_ALREADY_ENTERED: this session already has its entry today");
         continue;
      }

      OpenPosition(s, signalDir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   }

   FlushSettledRecords();
}

//+------------------------------------------------------------------+
//| Exit levels of a position: box height and the level the targets   |
//| are measured from. Retest entries measure from the broken edge,   |
//| run entries from their own entry (the edge is already a box or    |
//| more behind them). A retest whose entry is already past TP1 is    |
//| measured from the entry too.                                      |
//+------------------------------------------------------------------+
bool ExitPlan(const int s, const ulong positionId, const bool isBuy, const double open,
              const datetime opened, const string comment, double &box, double &base)
{
   if(sess[s].planPosition == positionId && sess[s].planBox > 0.0)
   {
      box  = sess[s].planBox;
      base = sess[s].planBase;
      return(true);
   }

   double hi = 0.0, lo = 0.0;
   if(!ComputeSessionBox(s, UkDayOf(ServerToUk(opened)), hi, lo))
      return(false);

   box = hi - lo;
   double edge = isBuy ? hi : lo;
   int    dir  = isBuy ? 1 : -1;
   base = edge;
   if(EntryTypeOfComment(comment) == ENTRY_RUN || dir * (open - (edge + dir * InpTp1Mult * box)) >= 0.0)
      base = open;

   sess[s].planPosition = positionId;
   sess[s].planBox      = box;
   sess[s].planBase     = base;
   return(true);
}

//+------------------------------------------------------------------+
//| Break even, TP1 and the session flat, on every tick.              |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int s = SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(s < 0) continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      bool stale   = (UkDayOf(ServerToUk(opened)) < UkDayOf(ServerToUk(TimeCurrent())));
      if(IsPastFlatten(s) || stale)
      {
         sess[s].exitTag = "timecut";
         if(trade.PositionClose(ticket))
            PrintFormat("%s %s: #%I64u closed at the %02d:%02d UK session end.",
                        InpComment, SessionTag(s), ticket, flatTime[s] / 60, flatTime[s] % 60);
         else
         {
            sess[s].exitTag = "";
            PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
         }
         continue;
      }

      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ulong  posId  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      string cmt    = PositionGetString(POSITION_COMMENT);

      double box = 0.0, base = 0.0;
      if(!ExitPlan(s, posId, isBuy, open, opened, cmt, box, base))
         continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
         continue;
      double px  = isBuy ? bid : ask;
      int    dir = isBuy ? 1 : -1;

      // Rule 8. Stop to entry once price is InpBeMult boxes in favour.
      double halfPoint = _Point * 0.5;
      bool atEntry = (sl > 0.0) && ((isBuy && sl >= open - halfPoint) || (!isBuy && sl <= open + halfPoint));
      if(!atEntry && dir * (px - open) >= InpBeMult * box)
      {
         double breakEven = NormalizePrice(open);
         if(trade.PositionModify(ticket, breakEven, tp))
            PrintFormat("%s %s: price %.2f boxes in favour, stop moved to entry %.*f on #%I64u.",
                        InpComment, SessionTag(s), InpBeMult, _Digits, breakEven, ticket);
         else
            PrintFormat("Break even modify failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }

      // Rule 9. TP1: close the requested share once.
      double target1 = base + dir * InpTp1Mult * box;
      if(dir * (px - target1) >= 0.0 && !HasClosedPart(posId))
      {
         double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         double closeVol = 0.0;
         if(lotStep > 0.0)
            closeVol = NormalizeDouble(MathFloor((volume * InpTp1ClosePercent / 100.0) / lotStep) * lotStep, 2);

         if(closeVol >= minLot && (volume - closeVol) >= minLot)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
               PrintFormat("%s %s: TP1 at %.*f, closed %.2f of %.2f lot on #%I64u.",
                           InpComment, SessionTag(s), _Digits, target1, closeVol, volume, ticket);
            else
               PrintFormat("Partial close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Rule 9, the runner. Once price has reached InpRunnerArmMult boxes |
//| from the base, exit on the first M5 candle that closes against    |
//| the trade (a bearish candle for a long). The candle that reached   |
//| the level counts. Read from bars, once per closed candle.         |
//+------------------------------------------------------------------+
void CheckRunnerExit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int s = SessionOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(s < 0) continue;

      bool     isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double   open   = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      ulong    posId  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      string   cmt    = PositionGetString(POSITION_COMMENT);

      double box = 0.0, base = 0.0;
      if(!ExitPlan(s, posId, isBuy, open, opened, cmt, box, base))
         continue;

      int    dir   = isBuy ? 1 : -1;
      double armAt = base + dir * InpRunnerArmMult * box;

      // The candle the position opened in, and every closed one since.
      int  openBar = iBarShift(_Symbol, WORK_TF, opened, false);
      bool armed   = false;
      for(int b = openBar; b >= 1; b--)
      {
         double fav = isBuy ? iHigh(_Symbol, WORK_TF, b) : iLow(_Symbol, WORK_TF, b);
         if(dir * (fav - armAt) >= 0.0)
         {
            armed = true;
            break;
         }
      }
      if(!armed)
         continue;

      double o = iOpen(_Symbol, WORK_TF, 1);
      double c = iClose(_Symbol, WORK_TF, 1);
      if(dir * (c - o) >= 0.0)
         continue;

      sess[s].exitTag = "runner";
      if(trade.PositionClose(ticket))
         PrintFormat("%s %s: #%I64u runner closed, %.1f boxes reached and the %s candle closed against at %.*f.",
                     InpComment, SessionTag(s), ticket, InpRunnerArmMult,
                     TimeToString(ServerToUk(iTime(_Symbol, WORK_TF, 1)), TIME_MINUTES), _Digits, c);
      else
      {
         sess[s].exitTag = "";
         PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
   }
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
//| Market order on the close of the entry candle. TP2 is the server  |
//| take profit; TP1, break even and the runner are managed above.    |
//+------------------------------------------------------------------+
void OpenPosition(const int s, ENUM_ORDER_TYPE type)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel < InpMinStopsLevel)
      stopsLevel = InpMinStopsLevel;
   double minGap = (stopsLevel + 1) * _Point;

   bool   isBuy = (type == ORDER_TYPE_BUY);
   int    dir   = isBuy ? 1 : -1;
   double price = isBuy ? ask : bid;
   double edge  = isBuy ? signalHi : signalLo;
   double base  = (signalType == ENTRY_RUN || dir * (price - (edge + dir * InpTp1Mult * signalBox)) >= 0.0)
                  ? price : edge;
   double sl    = NormalizePrice(signalStop);
   double tp    = NormalizePrice(base + dir * InpTp2Mult * signalBox);

   int idx = NewRecord(s, signalDir, replaySignalNo, replaySignalBar, iTime(_Symbol, WORK_TF, 1),
                       EntryTypeTag(signalType), price, sl, signalHi, signalLo);

   if(!IsSpreadAcceptable())
   {
      SkipRecord(idx, StringFormat("SKIPPED_SPREAD: spread %d above %d points",
                                   (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), InpMaxSpreadPoints));
      return;
   }
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
   if(dir * (tp - price) < minGap)
   {
      SkipRecord(idx, StringFormat("TP2 %.*f is not beyond the entry by the stops level", _Digits, tp));
      return;
   }

   double lot = CalculateLot(MathAbs(price - sl));
   if(lot <= 0.0)
   {
      SkipRecord(idx, "calculated lot is zero; risk too small or balance too low");
      return;
   }

   trade.SetExpertMagicNumber(SessionMagic(s));
   string comment = InpComment + " " + EntryTypeTag(signalType);

   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, comment)
                   : trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("%s %s %s %s %.2f lot at %.*f, SL %.*f, BE at %.*f, TP1 %.*f, TP2 %.*f | %s",
                  InpComment, SessionTag(s), EntryTypeTag(signalType), (isBuy ? "BUY" : "SELL"), lot,
                  _Digits, price, _Digits, sl,
                  _Digits, price + dir * InpBeMult * signalBox,
                  _Digits, base + dir * InpTp1Mult * signalBox,
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
//| Lot size from a percentage of balance and the stop distance.     |
//+------------------------------------------------------------------+
double CalculateLot(double stopDistancePrice)
{
   if(stopDistancePrice <= 0.0) return(0.0);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

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
   if(lot < minLot) return(0.0);
   if(lot > maxLot) lot = maxLot;

   return(NormalizeDouble(lot, 2));
}

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
//| Entries made this session, read from history, UK day boundary.    |
//| Permission allows one side per session, and each side one entry, |
//| so a session has at most one entry a day.                         |
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
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(UkDayOf(ServerToUk(dealTime)) != ukToday) continue;
      count++;
   }
   return(count);
}

datetime ServerNow()
{
   if(MQLInfoInteger(MQL_TESTER))
      return(TimeCurrent());
   datetime live = TimeTradeServer();
   return(live > TimeCurrent() ? live : TimeCurrent());
}

//+------------------------------------------------------------------+
//| Commission the tester cannot charge. Changes no trade.            |
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
//| Server time to UK time. Unchanged from OrbLondon.                 |
//+------------------------------------------------------------------+
datetime ServerToUk(const datetime serverTime)
{
   int offset = IsEuropeanSummerTime(serverTime) ? InpServerUtcOffsetSummer
                                                 : InpServerUtcOffsetWinter;
   datetime utc = (datetime)((long)serverTime - (long)offset * 3600);
   return(IsEuropeanSummerTime(utc) ? (datetime)((long)utc + 3600) : utc);
}

datetime EuSwitchTime(const int year, const int month)
{
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year;
   d.mon  = month;
   d.day  = 31;
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

bool IsPastFlatten(const int s)
{
   int minute = UkMinuteOfDay(ServerToUk(TimeCurrent()));
   return(minute >= flatTime[s]);
}

void LogSessionOnce(const int s, const datetime ukDay, const string message)
{
   if(sess[s].loggedDay == ukDay)
      return;
   sess[s].loggedDay = ukDay;
   PrintFormat("%s %s %s: %s", InpComment, SessionTag(s),
               TimeToString(ukDay, TIME_DATE), message);
}

double NormalizePrice(const double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return(NormalizeDouble(price, _Digits));
   return(NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits));
}

ENUM_ORDER_TYPE_FILLING PickFillingMode()
{
   int mask = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mask & SYMBOL_FILLING_FOK) != 0) return(ORDER_FILLING_FOK);
   if((mask & SYMBOL_FILLING_IOC) != 0) return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
}

void LogBrokerCapabilities()
{
   PrintFormat("Symbol %s  digits %d  point %.*f", _Symbol, _Digits, _Digits, _Point);
   PrintFormat("Tick size %.*f  tick value %.5f %s  contract size %.2f  spread now %d points",
               _Digits, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
               AccountInfoString(ACCOUNT_CURRENCY),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   PrintFormat("Account mode: %s", isHedging ? "HEDGING" : "NETTING or EXCHANGE");
   PrintFormat("Volume min %.2f  max %.2f  step %.2f",
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   PrintFormat("Stops level %d  freeze level %d",
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
}

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
//| LOGGING. One row per signal, entered or not. The first 17 columns |
//| are OrbLondon's, so the same analysis reads both files; `mode` is |
//| the entry type and `retest` is Y when the signal was entered.     |
//+------------------------------------------------------------------+
int NewRecord(const int s, const int dir, const int signalNo, const datetime signalBar,
              const datetime entryBar, const string mode, const double entry, const double stop,
              const double boxHi, const double boxLo)
{
   int n = ArraySize(records);
   ArrayResize(records, n + 1);

   records[n].signalBar = signalBar;
   records[n].ukSignal  = ServerToUk(signalBar);
   records[n].ukEntry   = (entryBar > 0) ? ServerToUk(entryBar) : 0;
   records[n].session   = s;
   records[n].dir       = dir;
   records[n].signalNo  = signalNo;
   records[n].mode      = mode;
   records[n].boxHi     = boxHi;
   records[n].boxLo     = boxLo;
   records[n].entry     = entry;
   records[n].stop      = stop;
   records[n].rAtStop   = (entry > 0.0 && stop > 0.0) ? MathAbs(entry - stop) : 0.0;
   records[n].retest    = "N";
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

void SkipRecord(const int idx, const string reason)
{
   if(!ValidRecord(idx))
      return;

   int s = records[idx].session;

   string outcome = "SKIPPED";
   if(StringFind(reason, "SKIPPED_") == 0)
   {
      int colon = StringFind(reason, ":");
      outcome = (colon > 0) ? StringSubstr(reason, 0, colon) : reason;
   }

   records[idx].outcome = outcome;
   records[idx].reason  = CsvSafe(reason);
   records[idx].retest  = "N";
   records[idx].settled = true;

   PrintFormat("%s %s: signal %d of %s UK not entered, %s.", InpComment, SessionTag(s),
               records[idx].signalNo, TimeToString(records[idx].ukSignal, TIME_MINUTES), reason);

   if(sess[s].pendingRecord == idx)
      sess[s].pendingRecord = -1;
}

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
         double hi = 0.0, lo = 0.0;
         ComputeSessionBox(s, UkDayOf(ServerToUk(TimeCurrent())), hi, lo);
         datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
         idx = NewRecord(s, (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1),
                         0, opened, opened, EntryTypeTag(EntryTypeOfComment(PositionGetString(POSITION_COMMENT))),
                         open, sl, hi, lo);
      }

      records[idx].entry   = open;
      records[idx].stop    = sl;
      records[idx].rAtStop = MathAbs(open - sl);
      records[idx].outcome = "OPEN";
      records[idx].retest  = "Y";

      sess[s].record        = idx;
      sess[s].pendingRecord = -1;
      sess[s].position      = id;
      sess[s].openTime      = (datetime)PositionGetInteger(POSITION_TIME);
      sess[s].risk          = RiskMoneyOf(volume, open, sl);
      sess[s].exitTag       = "";
      return;
   }
}

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
//--- Outcomes: SL (full stop), BE (stopped at entry before TP1), TP1_BE (half
//--- at TP1, rest at entry), TP2, runner, timecut.
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
      outcome = sess[s].exitTag;
   else if(lastWhy == DEAL_REASON_TP)
      outcome = "TP2";
   else if(lastWhy == DEAL_REASON_SL)
   {
      if(outs > 1)
         outcome = "TP1_BE";
      else
         outcome = (sess[s].risk > 0.0 && MathAbs(profit) < 0.25 * sess[s].risk) ? "BE" : "SL";
   }
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

      PrintFormat("%s %s: %s %s %s closed %s, %.2f R (%.2f), %d minutes in trade.",
                  InpComment, SessionTag(s),
                  TimeToString(records[idx].ukEntry, TIME_DATE | TIME_MINUTES),
                  records[idx].mode, (records[idx].dir > 0 ? "BUY" : "SELL"),
                  outcome, records[idx].rResult, profit, records[idx].minutes);
   }

   sess[s].record   = -1;
   sess[s].position = 0;
   sess[s].openTime = 0;
   sess[s].risk     = 0.0;
   sess[s].exitTag  = "";
}

string CsvSafe(const string text)
{
   string clean = text;
   StringReplace(clean, ",", ";");
   return(clean);
}

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
                   "profit_usd,reason,signal_no,entry_time_uk");
   FileClose(h);

   PrintFormat("%s: signal log at %s%s",
               InpComment, (InpCsvCommonFolder ? "Common\\Files\\" : "MQL5\\Files\\"), InpCsvFile);
}

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

   string line = StringFormat("%s,%s,%s,%s,%s,%.*f,%.*f,%.*f,%.*f,%.*f,%.*f,%s,%s,%.3f,%d,%.2f,%s,%d,%s",
                              TimeToString(records[i].ukSignal, TIME_DATE),
                              TimeToString(records[i].ukSignal, TIME_MINUTES),
                              SessionTag(records[i].session),
                              records[i].mode,
                              (records[i].dir > 0 ? "BUY" : "SELL"),
                              _Digits, records[i].boxLo,
                              _Digits, records[i].boxHi,
                              _Digits, records[i].boxHi - records[i].boxLo,
                              _Digits, records[i].entry,
                              _Digits, records[i].stop,
                              _Digits, records[i].rAtStop,
                              records[i].retest,
                              records[i].outcome,
                              records[i].rResult,
                              records[i].minutes,
                              records[i].profit,
                              records[i].reason,
                              records[i].signalNo,
                              (records[i].ukEntry > 0 ? TimeToString(records[i].ukEntry, TIME_MINUTES) : "-"));
   FileWrite(h, line);
   FileClose(h);
}

void FlushSettledRecords()
{
   int n = ArraySize(records);
   for(int i = 0; i < n; i++)
      if(records[i].settled && !records[i].written)
         WriteRecord(i);

   CompactRecords();
}

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
