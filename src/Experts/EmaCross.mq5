//+------------------------------------------------------------------+
//| EmaCross.mq5                                                      |
//|                                                                   |
//| EMA 9/21 crossover on XAUUSD M5, two intraday windows.            |
//|                                                                   |
//| Signal     EMA9 crosses EMA21 on a CLOSED M5 candle. Bullish      |
//|            cross buys, bearish cross sells, at the open of the    |
//|            next candle                                            |
//| Windows    London 08:00-11:30 and New York 13:30-16:00 UK. The    |
//|            entry time, which is the cross candle's close, must    |
//|            fall inside a window                                   |
//| Filters    InpH1Filter: buys only with H1 EMA9 > EMA21, sells     |
//|            only with H1 EMA9 < EMA21                              |
//|            InpMinAtrPct: skip when M5 ATR(14) is below this       |
//|            percentage of price. 0 turns it off                    |
//| Stop       the lowest low (buy) or highest high (sell) of the     |
//|            last 10 closed candles, one point beyond, clamped to   |
//|            between 0.05% and 0.30% of the entry price            |
//| TP1        1.5R, closes half and moves the stop to entry          |
//| TP2        3R, for the remainder                                  |
//| Exits      an opposite cross closes everything, and anything      |
//|            still open at 16:00 UK is closed at market             |
//| Session    one position at a time, at most 3 entries per UK day   |
//|                                                                   |
//| Session times are UK. Server time is converted to UK with the EU  |
//| and UK daylight saving calendars. See InpServerUtcOffset* below.  |
//|                                                                   |
//| Every signal, taken or skipped, is printed to the Experts log and |
//| appended to a CSV. See the LOGGING section near the bottom.       |
//|                                                                   |
//| Built from src/Experts/OrbLondon.mq5, itself built from           |
//| templates/EA_Template.mq5. Everything below the STRATEGY section  |
//| is that template's safety layer: risk sizing, broker capability   |
//| detection, order normalisation, trade result checking, and state  |
//| rebuilt from the account after a restart.                         |
//| Specification: strategies/EmaCross.md                             |
//+------------------------------------------------------------------+
#property copyright "MQL5 Workspace"
#property version   "1.00"
#property description "EMA 9/21 crossover, XAUUSD M5, London and New York windows."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Session, all times UK (Europe/London) ===";
input int    InpLondonStartHour    = 8;     // London window opens, UK hour
input int    InpLondonStartMinute  = 0;     // London window opens, UK minute
input int    InpLondonEndHour      = 11;    // London window closes, UK hour
input int    InpLondonEndMinute    = 30;    // London window closes, UK minute
input int    InpNewYorkStartHour   = 13;    // New York window opens, UK hour
input int    InpNewYorkStartMinute = 30;    // New York window opens, UK minute
input int    InpNewYorkEndHour     = 16;    // New York window closes, UK hour
input int    InpNewYorkEndMinute   = 0;     // New York window closes, UK minute
input int    InpFlattenHour        = 16;    // Close everything at this UK hour
input int    InpFlattenMinute      = 0;     // Close everything at this UK minute

input group "=== Server time zone ===";
// Vantage runs EET/EEST: UTC+2 in winter, UTC+3 in summer. A server fixed at
// UTC+3 all year is set by making both of these 3.
input int    InpServerUtcOffsetWinter = 2;  // Server UTC offset outside EU DST
input int    InpServerUtcOffsetSummer = 3;  // Server UTC offset during EU DST

input group "=== Strategy ===";
input int    InpFastEmaPeriod    = 9;       // Fast EMA period
input int    InpSlowEmaPeriod    = 21;      // Slow EMA period
input int    InpSwingLookback    = 10;      // Candles searched for the swing point
input int    InpStopBufferPoints = 1;       // Extra points beyond the swing
input double InpMinStopPct       = 0.05;    // Stop never tighter than this, % of price
input double InpMaxStopPct       = 0.30;    // Stop never wider than this, % of price
input double InpTp1RMult         = 1.5;     // TP1, R multiples from entry
input double InpTp2RMult         = 3.0;     // TP2, R multiples from entry
input double InpTp1ClosePercent  = 50.0;    // Percent of the position closed at TP1

input group "=== Variants. Baseline is every one of these at its default ===";
input bool   InpH1Filter         = true;    // Require the H1 EMAs to agree with the cross
// The H1 EMAs are read on the last CLOSED bar of this timeframe at the moment
// the M5 cross candle closes, never the hour still forming, so the value
// cannot change after the signal is taken.
input ENUM_TIMEFRAMES InpH1Timeframe = PERIOD_H1; // Timeframe of the trend filter EMAs
input double InpMinAtrPct        = 0.0;     // Skip below this M5 ATR(14), % of price. 0 = off
input int    InpAtrPeriod        = 14;      // ATR period for InpMinAtrPct
input bool   InpMoveToBreakEven  = true;    // Move the stop to entry at TP1
input bool   InpCloseOnOpposite  = true;    // An opposite cross closes everything
input bool   InpReverseOnOpposite= true;    // That same cross may then open the other way

input group "=== Risk management ===";
input double InpRiskPercent      = 1.0;     // Risk per trade, % of balance
input int    InpMinStopsLevel    = 20;      // Floor under the broker's stops level, points
input int    InpMaxPositions     = 1;       // Max simultaneous positions
input int    InpMaxTradesPerDay  = 3;       // Max entries per UK day, 0 = no limit
// Accounting only. MT5 charges commission from the broker's group settings,
// which the tester does not have, so this input does not move a single trade.
// It is applied to the OnTester result and printed at the end of the run.
input double InpCommissionPerLot = 0.0;     // Round-trip commission, $ per lot

input group "=== Filters ===";
input int    InpMaxSpreadPoints  = 50;      // Max spread allowed, points

input group "=== Logging ===";
input bool   InpCsvLog           = true;    // Append every signal to a CSV
input string InpCsvFile          = "emacross_log.csv"; // File under MQL5\Files
input bool   InpCsvCommonFolder  = false;   // Write to the shared Common\Files instead
input int    InpRetestBars       = 6;       // Candles watched for a return to the cross level

input group "=== Identity ===";
input long   InpMagic            = 20260923; // Magic number
input string InpComment          = "EmaCross"; // Order comment

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
#define WORK_TF      PERIOD_M5

CTrade   trade;
int      fastHandle   = INVALID_HANDLE;
int      slowHandle   = INVALID_HANDLE;
int      h1FastHandle = INVALID_HANDLE;
int      h1SlowHandle = INVALID_HANDLE;
int      atrHandle    = INVALID_HANDLE;
datetime lastBarTime  = 0;
bool     isHedging    = false;

// Indicator values for the last closed bars.
// Index 1 is the most recently closed bar, index 2 the one before it.
// Index 0 is the bar still forming and is deliberately not used.
double   fastMA[];
double   slowMA[];
double   h1FastMA[];
double   h1SlowMA[];
double   atrBuf[];

// The signal the strategy section produced for the bar that has just closed.
int      signalDir  = 0;            // +1 long, -1 short, 0 nothing
double   signalStop = 0.0;          // the clamped swing stop
double   signalR    = 0.0;          // stop distance in price, one R for the targets
string   signalWhy  = "";

// The position whose volume was already reported as unsplittable.
ulong    splitWarnedPosition = 0;

//+------------------------------------------------------------------+
//| One row of the CSV, held until every column is known.             |
//|                                                                   |
//| A row needs two things that are not available when the signal     |
//| fires: how the trade ended, and whether price came back to the    |
//| cross level within InpRetestBars candles. Rows are therefore held |
//| here and written once both are settled, or at OnDeinit.           |
//|                                                                   |
//| This is diagnostics only. No trading decision reads it, so losing |
//| it in a restart costs log lines and nothing else. Every rule the  |
//| EA trades on is recomputed from bars or from the account.         |
//+------------------------------------------------------------------+
struct SignalRecord
{
   datetime crossBar;        // server time of the cross candle
   datetime ukEntry;         // UK time of the entry, the cross candle's close
   int      dir;             // +1 long, -1 short
   bool     h1Aligned;       // did the H1 EMAs agree, whatever the filter did
   double   entry;           // fill price, or the price at signal time when skipped
   double   stop;
   double   rAtStop;         // entry to stop distance, in price
   string   session;         // LONDON or NY
   string   outcome;         // TP1 TP2 SL BE opposite timecut SKIPPED
   string   reason;          // why it was skipped, empty otherwise
   double   rResult;         // realised profit / money risked
   int      minutes;         // minutes in trade
   double   profit;          // realised money, account currency
   double   crossLevel;      // where the two EMAs crossed
   double   closeLevel;      // close of the cross candle, about the entry
   int      barsSeen;        // candles examined for the retest
   bool     retest;          // price came back to crossLevel
   bool     retestClose;     // price came back to closeLevel
   bool     retestDone;      // InpRetestBars candles have been examined
   bool     settled;         // outcome is final
   bool     written;
};

SignalRecord records[];

// The open trade, for the log row only. Trading state is read from the
// account, never from these.
int      activeRecord   = -1;
ulong    activePosition = 0;        // POSITION_IDENTIFIER
datetime activeOpenTime = 0;
double   activeRisk     = 0.0;      // money risked at entry
string   activeExitTag  = "";       // set before a close the EA itself decides

bool     csvHeaderChecked = false;

//+------------------------------------------------------------------+
//| STRATEGY. This is the only section you normally change.           |
//|                                                                   |
//| Everything here reads closed M5 bars, the two M5 EMAs, the two    |
//| H1 EMAs and the M5 ATR. It writes signalDir, signalStop and       |
//| signalR. It never sends an order: the safety layer below sizes,   |
//| normalises and checks the trade.                                  |
//+------------------------------------------------------------------+

//--- The cross on the bar that has just closed. +1 bullish, -1 bearish.
//--- Index 1 is that closed bar, index 2 the one before it, so a cross is
//--- fully formed before it is acted on and cannot repaint.
int DetectCross()
{
   if(fastMA[1] > slowMA[1] && fastMA[2] <= slowMA[2]) return(1);
   if(fastMA[1] < slowMA[1] && fastMA[2] >= slowMA[2]) return(-1);
   return(0);
}

//--- Do the H1 EMAs agree with this direction?
bool IsH1Aligned(const int dir)
{
   if(dir > 0) return(h1FastMA[1] >  h1SlowMA[1]);
   if(dir < 0) return(h1FastMA[1] <  h1SlowMA[1]);
   return(false);
}

//--- Stop from structure, then clamped.
//--- The swing point is the extreme of the last InpSwingLookback closed
//--- candles, one point beyond it. The clamp is applied to the DISTANCE, so a
//--- stop that would be too tight or too wide is moved to the nearest allowed
//--- distance from the entry rather than dropped.
void ComputeStop(const int dir, const double entry, double &stop, double &rDist)
{
   double extreme = 0.0;
   for(int i = 1; i <= InpSwingLookback; i++)
   {
      double h = iHigh(_Symbol, WORK_TF, i);
      double l = iLow(_Symbol, WORK_TF, i);
      if(h <= 0.0 || l <= 0.0)
         break;
      if(i == 1)              extreme = (dir > 0) ? l : h;
      else if(dir > 0)        extreme = MathMin(extreme, l);
      else                    extreme = MathMax(extreme, h);
   }

   double buffer = InpStopBufferPoints * _Point;
   double raw    = (dir > 0) ? extreme - buffer : extreme + buffer;

   rDist = MathAbs(entry - raw);
   if(extreme <= 0.0)
      rDist = 0.0;

   double minDist = entry * InpMinStopPct / 100.0;
   double maxDist = entry * InpMaxStopPct / 100.0;
   if(rDist < minDist) rDist = minDist;
   if(rDist > maxDist) rDist = maxDist;

   stop = NormalizePrice((dir > 0) ? entry - rDist : entry + rDist);
   rDist = MathAbs(entry - stop);
}

//--- ATR of the last closed M5 bar as a percentage of price.
double AtrPercent()
{
   double price = iClose(_Symbol, WORK_TF, 1);
   if(price <= 0.0 || atrBuf[1] <= 0.0)
      return(0.0);
   return(atrBuf[1] / price * 100.0);
}

//--- LONDON, NY, or an empty string outside both windows. The minute given is
//--- the UK minute of the ENTRY, which is the moment the cross candle closes.
//--- A window is inclusive of its start and exclusive of its end, so the last
//--- New York entry is 15:55 and nothing is opened at the 16:00 flat.
string SessionOfEntry(const int minute)
{
   int londonOpen  = InpLondonStartHour  * 60 + InpLondonStartMinute;
   int londonClose = InpLondonEndHour    * 60 + InpLondonEndMinute;
   int nyOpen      = InpNewYorkStartHour * 60 + InpNewYorkStartMinute;
   int nyClose     = InpNewYorkEndHour   * 60 + InpNewYorkEndMinute;

   if(minute >= londonOpen && minute < londonClose) return("LONDON");
   if(minute >= nyOpen     && minute < nyClose)     return("NY");
   return("");
}

//--- A cross has just closed. Exit first, then consider an entry.
void OnCross(const int dir)
{
   // An opposite cross closes everything, at any time of day. This is an exit
   // rule, not a session rule, so it is not gated by the entry windows.
   bool closedOpposite = false;
   if(InpCloseOnOpposite)
      closedOpposite = CloseOpposite(dir);

   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   if(barTime <= 0)
      return;

   datetime ukEntry = ServerToUk(barTime + PeriodSeconds(WORK_TF));
   string   session = SessionOfEntry(UkMinuteOfDay(ukEntry));
   if(session == "")
      return;                                  // outside both windows

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   double entry = (dir > 0) ? ask : bid;
   double stop  = 0.0, rDist = 0.0;
   ComputeStop(dir, entry, stop, rDist);

   bool aligned = IsH1Aligned(dir);
   int  idx     = NewRecord(barTime, ukEntry, dir, aligned, entry, stop, rDist, session);

   signalDir  = 0;
   signalStop = stop;
   signalR    = rDist;
   signalWhy  = StringFormat("%s EMA%d/%d cross at %.*f, %s window, H1 %s, stop %.*f (%.2f R)",
                             (dir > 0 ? "bullish" : "bearish"),
                             InpFastEmaPeriod, InpSlowEmaPeriod,
                             _Digits, iClose(_Symbol, WORK_TF, 1), session,
                             (aligned ? "aligned" : "against"),
                             _Digits, stop, rDist);

   // Filters, in the order that makes the log read like the decision.
   if(closedOpposite && !InpReverseOnOpposite)
                                              { SkipSignal(idx, "opposite cross used as an exit only"); return; }
   if(rDist <= 0.0)                          { SkipSignal(idx, "stop distance is zero"); return; }
   if(InpH1Filter && !aligned)               { SkipSignal(idx, "H1 EMA not aligned"); return; }

   if(InpMinAtrPct > 0.0)
   {
      double atrPct = AtrPercent();
      if(atrPct < InpMinAtrPct)
      {
         SkipSignal(idx, StringFormat("ATR %.3f%% below %.3f%%", atrPct, InpMinAtrPct));
         return;
      }
   }

   if(CountMyPositions() >= InpMaxPositions)  { SkipSignal(idx, "a position is already open"); return; }
   if(InpMaxTradesPerDay > 0 && CountMyEntriesToday() >= InpMaxTradesPerDay)
                                              { SkipSignal(idx, "daily entry cap reached"); return; }
   if(!IsSpreadAcceptable())
   {
      SkipSignal(idx, StringFormat("spread %d above %d points",
                                   (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
                                   InpMaxSpreadPoints));
      return;
   }

   signalDir = dir;
   OpenPosition(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, idx);
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
   if(InpSwingLookback < 2)
   {
      Print("InpSwingLookback must be at least 2 candles.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpMinStopPct <= 0.0 || InpMaxStopPct < InpMinStopPct)
   {
      Print("Stop distance bounds are inconsistent.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp2RMult <= InpTp1RMult || InpTp1RMult <= 0.0)
   {
      Print("InpTp2RMult must be greater than InpTp1RMult, and both above zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpTp1ClosePercent <= 0.0 || InpTp1ClosePercent >= 100.0)
   {
      Print("InpTp1ClosePercent must be between 0 and 100 exclusive.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   fastHandle   = iMA(_Symbol, WORK_TF, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle   = iMA(_Symbol, WORK_TF, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h1FastHandle = iMA(_Symbol, InpH1Timeframe, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   h1SlowHandle = iMA(_Symbol, InpH1Timeframe, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle    = iATR(_Symbol, WORK_TF, InpAtrPeriod);
   if(fastHandle   == INVALID_HANDLE || slowHandle   == INVALID_HANDLE ||
      h1FastHandle == INVALID_HANDLE || h1SlowHandle == INVALID_HANDLE ||
      atrHandle    == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles, error ", GetLastError());
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastMA,   true);
   ArraySetAsSeries(slowMA,   true);
   ArraySetAsSeries(h1FastMA, true);
   ArraySetAsSeries(h1SlowMA, true);
   ArraySetAsSeries(atrBuf,   true);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(PickFillingMode());
   trade.SetDeviationInPoints(10);

   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   LogBrokerCapabilities();
   PrepareCsv();

   // State is rebuilt from the account, never carried in memory.
   // See skill mql5-patterns, references/state-and-restart.md.
   PrintFormat("%s starting. %d open position(s), %d entry(ies) already today.",
               InpComment, CountMyPositions(), CountMyEntriesToday());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   FlushAllRecords();

   if(fastHandle   != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle   != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(h1FastHandle != INVALID_HANDLE) IndicatorRelease(h1FastHandle);
   if(h1SlowHandle != INVALID_HANDLE) IndicatorRelease(h1SlowHandle);
   if(atrHandle    != INVALID_HANDLE) IndicatorRelease(atrHandle);
   // Never close positions here. OnDeinit also runs on recompile and on a
   // chart template change, and closing then would be a disaster.
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Position management runs on every tick. TP1 is a price level inside the
   // bar, and the 16:00 flat is a clock event; neither can wait for a close.
   ManageOpenPositions();
   FinaliseClosedTrade();

   // Entries act once per closed bar.
   datetime current = iTime(_Symbol, WORK_TF, 0);
   if(current == lastBarTime)
      return;

   if(!RefreshIndicators())
      return;                       // not enough bars yet, try again next bar

   lastBarTime = current;

   // The retest window is measured on the bars AFTER the cross, so this runs
   // before a cross on this same bar is recorded.
   UpdateRetests();

   int cross = DetectCross();
   if(cross != 0)
      OnCross(cross);

   FlushSettledRecords();
}

//+------------------------------------------------------------------+
//| Load the last three indicator values. False means not ready.     |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(fastHandle,   0, 0, 3, fastMA)   < 3) return(false);
   if(CopyBuffer(slowHandle,   0, 0, 3, slowMA)   < 3) return(false);
   if(CopyBuffer(h1FastHandle, 0, 0, 3, h1FastMA) < 3) return(false);
   if(CopyBuffer(h1SlowHandle, 0, 0, 3, h1SlowMA) < 3) return(false);
   if(CopyBuffer(atrHandle,    0, 0, 3, atrBuf)   < 3) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Close every position of this EA that faces the other way.         |
//| True when at least one was closed, which is what decides whether  |
//| this same cross may then be taken as an entry.                    |
//+------------------------------------------------------------------+
bool CloseOpposite(const int dir)
{
   bool closedAny = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;

      long type = PositionGetInteger(POSITION_TYPE);
      bool faces = (dir > 0) ? (type == POSITION_TYPE_SELL) : (type == POSITION_TYPE_BUY);
      if(!faces) continue;

      activeExitTag = "opposite";
      if(trade.PositionClose(ticket))
      {
         closedAny = true;
         PrintFormat("%s: #%I64u closed on the opposite %s cross.",
                     InpComment, ticket, (dir > 0 ? "bullish" : "bearish"));
      }
      else
      {
         activeExitTag = "";
         PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
   }

   // The row for the position just closed is completed straight away, so the
   // reversal that may follow starts from a clean tracker.
   if(closedAny)
      FinaliseClosedTrade();

   return(closedAny);
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
         activeExitTag = "timecut";
         if(trade.PositionClose(ticket))
            PrintFormat("%s: #%I64u closed at the %02d:%02d UK session end.",
                        InpComment, ticket, InpFlattenHour, InpFlattenMinute);
         else
         {
            activeExitTag = "";
            PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
         }
         continue;
      }

      HandleFirstTarget(ticket);
   }
}

//+------------------------------------------------------------------+
//| At 1.5R, close part of the position and move the stop to the      |
//| entry price. R is recovered from the order's own take profit, so  |
//| no state has to survive between ticks.                            |
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

   double r = (tp > 0.0) ? MathAbs(tp - open) / InpTp2RMult
                         : ((sl > 0.0) ? MathAbs(open - sl) : 0.0);
   if(r <= 0.0)
      return;

   double target1 = isBuy ? open + r * InpTp1RMult
                          : open - r * InpTp1RMult;
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
//| Send a market order. The stop comes from the swing, the target is |
//| a multiple of the stop distance, and the lot from the real stop   |
//| distance rather than from a fixed point count.                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, const int recordIndex)
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
   double tp    = NormalizePrice(isBuy ? price + signalR * InpTp2RMult
                                       : price - signalR * InpTp2RMult);

   if(isBuy && sl > price - minGap)
   {
      SkipSignal(recordIndex, StringFormat("stop %.*f is not %d points below ask",
                                           _Digits, sl, (int)stopsLevel));
      return;
   }
   if(!isBuy && sl < price + minGap)
   {
      SkipSignal(recordIndex, StringFormat("stop %.*f is not %d points above bid",
                                           _Digits, sl, (int)stopsLevel));
      return;
   }
   if(MathAbs(tp - price) < minGap)
   {
      SkipSignal(recordIndex, "target is inside the stops level");
      return;
   }

   double slDistance = MathAbs(price - sl);
   double lot = CalculateLot(slDistance);
   if(lot <= 0.0)
   {
      SkipSignal(recordIndex, "lot rounds to zero; balance too low for the minimum lot");
      return;
   }

   bool ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment)
                   : trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);

   uint code = trade.ResultRetcode();
   if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL))
   {
      double fill = (trade.ResultPrice() > 0.0) ? trade.ResultPrice() : price;
      PrintFormat("%s %s %.2f lot at %.*f, SL %.*f, TP1 %.*f, TP2 %.*f | %s",
                  InpComment, (isBuy ? "BUY" : "SELL"), lot, _Digits, fill,
                  _Digits, sl,
                  _Digits, (isBuy ? fill + signalR * InpTp1RMult
                                  : fill - signalR * InpTp1RMult),
                  _Digits, tp, signalWhy);

      StartTracking(recordIndex, fill, sl);
   }
   else
   {
      PrintFormat("Order rejected: %s (retcode %u)", RetcodeText(code), code);
      SkipSignal(recordIndex, StringFormat("order rejected: %s", RetcodeText(code)));
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
//| Entries made today, read from history. Never from a counter.      |
//| This is what makes the three per day cap survive a terminal       |
//| restart. The day boundary is UK midnight, not the server's.       |
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
//| LOGGING                                                           |
//|                                                                   |
//| One line per signal to the Experts log, and one CSV row per       |
//| signal including the ones a filter skipped, so a filtered run and |
//| an unfiltered one can be compared from a single file.             |
//+------------------------------------------------------------------+

//--- Start a row. Returns its index in records.
int NewRecord(const datetime crossBar, const datetime ukEntry, const int dir,
              const bool h1Aligned, const double entry, const double stop,
              const double rAtStop, const string session)
{
   int n = ArraySize(records);
   ArrayResize(records, n + 1);

   records[n].crossBar   = crossBar;
   records[n].ukEntry    = ukEntry;
   records[n].dir        = dir;
   records[n].h1Aligned  = h1Aligned;
   records[n].entry      = entry;
   records[n].stop       = stop;
   records[n].rAtStop    = rAtStop;
   records[n].session    = session;
   records[n].outcome    = "";
   records[n].reason     = "";
   records[n].rResult    = 0.0;
   records[n].minutes    = 0;
   records[n].profit     = 0.0;
   // The cross level is where the two EMAs met, which is the level the
   // signal is built on. The candle's close is logged beside it because on M5
   // gold price comes back through its own close almost every time, and a
   // measure that is always true answers nothing.
   records[n].crossLevel  = (fastMA[1] + slowMA[1]) / 2.0;
   records[n].closeLevel  = iClose(_Symbol, WORK_TF, 1);
   records[n].barsSeen    = 0;
   records[n].retest      = false;
   records[n].retestClose = false;
   records[n].retestDone  = (InpRetestBars <= 0);
   records[n].settled    = false;
   records[n].written    = false;

   return(n);
}

//--- Mark a signal as not taken and say why, in the log and in the CSV.
void SkipSignal(const int idx, const string reason)
{
   if(idx < 0 || idx >= ArraySize(records))
      return;

   records[idx].outcome = "SKIPPED";
   records[idx].reason  = reason;
   records[idx].settled = true;

   PrintFormat("%s: %s SIGNAL SKIPPED, %s. %s",
               InpComment, TimeToString(records[idx].ukEntry, TIME_DATE | TIME_MINUTES),
               reason, signalWhy);
}

//--- The trade is on. Remember what the log row still needs.
void StartTracking(const int idx, const double fill, const double stop)
{
   ulong posId = 0;
   ulong deal  = trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal))
      posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(posId == 0)
      posId = FindMyPositionId();

   activeRecord   = idx;
   activePosition = posId;
   activeOpenTime = TimeCurrent();
   activeRisk     = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   activeExitTag  = "";

   if(idx >= 0 && idx < ArraySize(records))
   {
      records[idx].entry   = fill;
      records[idx].stop    = stop;
      records[idx].rAtStop = MathAbs(fill - stop);
      records[idx].outcome = "OPEN";
   }
}

//--- The identifier of an open position of this EA, when the deal lookup
//--- cannot supply it.
ulong FindMyPositionId()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
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
void FinaliseClosedTrade()
{
   if(activePosition == 0)
      return;
   if(HasPositionWithId(activePosition))
      return;

   double   profit   = 0.0;
   datetime lastTime = 0;
   long     lastWhy  = -1;
   int      outs     = 0;

   if(HistorySelectByPosition(activePosition))
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
   if(activeExitTag != "")
      outcome = activeExitTag;                      // opposite or timecut
   else if(lastWhy == DEAL_REASON_TP)
      outcome = "TP2";
   else if(lastWhy == DEAL_REASON_SL)
      outcome = (outs > 1) ? (InpMoveToBreakEven ? "BE" : "TP1") : "SL";
   else
      outcome = "closed";

   int idx = activeRecord;
   if(idx >= 0 && idx < ArraySize(records))
   {
      records[idx].outcome = outcome;
      records[idx].profit  = profit;
      records[idx].rResult = (activeRisk > 0.0) ? profit / activeRisk : 0.0;
      records[idx].minutes = (lastTime > activeOpenTime)
                             ? (int)((lastTime - activeOpenTime) / 60) : 0;
      records[idx].settled = true;

      PrintFormat("%s: %s %s closed %s, %.2f R (%.2f), %d minutes in trade.",
                  InpComment, TimeToString(records[idx].ukEntry, TIME_DATE | TIME_MINUTES),
                  (records[idx].dir > 0 ? "BUY" : "SELL"),
                  outcome, records[idx].rResult, profit, records[idx].minutes);
   }

   activeRecord   = -1;
   activePosition = 0;
   activeOpenTime = 0;
   activeRisk     = 0.0;
   activeExitTag  = "";
}

//--- Did price come back to the cross level? Called once per closed bar,
//--- before any cross on that same bar is recorded, so a record never counts
//--- its own candle.
void UpdateRetests()
{
   datetime barTime = iTime(_Symbol, WORK_TF, 1);
   double   hi      = iHigh(_Symbol, WORK_TF, 1);
   double   lo      = iLow(_Symbol, WORK_TF, 1);
   if(barTime <= 0 || hi <= 0.0 || lo <= 0.0)
      return;

   int n = ArraySize(records);
   for(int i = 0; i < n; i++)
   {
      if(records[i].retestDone || records[i].written) continue;
      if(barTime <= records[i].crossBar)              continue;

      records[i].barsSeen++;
      if(records[i].dir > 0)
      {
         if(lo <= records[i].crossLevel) records[i].retest      = true;
         if(lo <= records[i].closeLevel) records[i].retestClose = true;
      }
      else
      {
         if(hi >= records[i].crossLevel) records[i].retest      = true;
         if(hi >= records[i].closeLevel) records[i].retestClose = true;
      }
      if(records[i].barsSeen >= InpRetestBars) records[i].retestDone = true;
   }
}

//--- Open the CSV, write the header if the file is new. In the tester the
//--- file is truncated instead, so one run is one file.
void PrepareCsv()
{
   if(!InpCsvLog || csvHeaderChecked)
      return;
   csvHeaderChecked = true;

   int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpCsvCommonFolder)
      flags |= FILE_COMMON;
   if(MQLInfoInteger(MQL_TESTER))
   {
      flags = FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
      if(InpCsvCommonFolder)
         flags |= FILE_COMMON;
   }

   int h = FileOpen(InpCsvFile, flags);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("%s: cannot open %s for logging, error %d. Logging to the journal only.",
                  InpComment, InpCsvFile, GetLastError());
      return;
   }

   if(FileSize(h) == 0)
      FileWrite(h, "date,time_uk,direction,h1_aligned,entry,stop,r_at_stop,outcome,"
                   "r_result,minutes_in_trade,session,retest6,retest6_close,profit_usd,reason");
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

   string line = StringFormat("%s,%s,%s,%s,%.*f,%.*f,%.*f,%s,%.3f,%d,%s,%s,%s,%.2f,%s",
                              TimeToString(records[i].ukEntry, TIME_DATE),
                              TimeToString(records[i].ukEntry, TIME_MINUTES),
                              (records[i].dir > 0 ? "BUY" : "SELL"),
                              (records[i].h1Aligned ? "Y" : "N"),
                              _Digits, records[i].entry,
                              _Digits, records[i].stop,
                              _Digits, records[i].rAtStop,
                              records[i].outcome,
                              records[i].rResult,
                              records[i].minutes,
                              records[i].session,
                              (records[i].retestDone ? (records[i].retest      ? "Y" : "N") : "?"),
                              (records[i].retestDone ? (records[i].retestClose ? "Y" : "N") : "?"),
                              records[i].profit,
                              records[i].reason);
   FileWrite(h, line);
   FileClose(h);
}

//--- Write every row whose outcome and retest are both settled, then drop the
//--- written rows so the array does not grow without limit.
void FlushSettledRecords()
{
   int n = ArraySize(records);
   for(int i = 0; i < n; i++)
      if(records[i].settled && records[i].retestDone && !records[i].written)
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
         records[i].outcome = "OPEN";
      WriteRecord(i);
   }
   ArrayResize(records, 0);
}

void CompactRecords()
{
   int n = ArraySize(records);
   int keep = 0;
   for(int i = 0; i < n; i++)
   {
      if(records[i].written)
         continue;
      if(keep != i)
      {
         records[keep] = records[i];
         if(activeRecord == i)
            activeRecord = keep;
      }
      keep++;
   }
   if(keep != n)
      ArrayResize(records, keep);
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
