# Entry, exit, trailing stop, multiple positions

Verified by compile on 2026-08-05, MetaEditor build 5836.

`templates/EA_Template.mq5` already contains the market entry and the simple
exit. This file covers what to add beyond that.

---

## Market entry with CTrade

The short form. `EA_Template.mq5` has the full version with lot sizing and
stops-level handling.

```cpp
trade.SetExpertMagicNumber(InpMagic);
trade.SetTypeFilling(PickFillingMode());   // see broker-adaptation.md
trade.SetDeviationInPoints(10);

bool ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment);
if(!ok || trade.ResultRetcode() != TRADE_RETCODE_DONE)
   PrintFormat("Order rejected: %s", RetcodeText(trade.ResultRetcode()));
```

Price `0.0` means market price. Passing an explicit price to a market order
invites requotes for no benefit.

---

## Market entry with MqlTradeRequest

Use this when `CTrade` does not expose what you need. Zero the struct first:
uninitialised fields are a common source of rejections that look random.

```cpp
MqlTradeRequest request;
MqlTradeResult  result;
ZeroMemory(request);
ZeroMemory(result);

request.action       = TRADE_ACTION_DEAL;
request.symbol       = _Symbol;
request.volume       = lot;
request.type         = ORDER_TYPE_BUY;      // ORDER_TYPE, never POSITION_TYPE
request.price        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
request.sl           = sl;
request.tp           = tp;
request.deviation    = 10;
request.magic        = InpMagic;            // the field is 'magic', not 'magicnumber'
request.type_filling = PickFillingMode();
request.comment      = InpComment;

if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
   PrintFormat("OrderSend failed: %s", RetcodeText(result.retcode));
```

---

## Closing

```cpp
// One position
trade.PositionClose(ticket);

// All of this EA's positions on this symbol
void CloseAllMine()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)   // downwards
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      if(!trade.PositionClose(ticket))
         PrintFormat("Close failed for #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
   }
}
```

Iterate downwards. Closing inside an ascending loop shifts the remaining
indices and silently skips positions.

---

## Trailing stop

Two rules that make the difference between a trailing stop that works and one
that fills the log with errors.

- Only ever move the stop in the profitable direction. Never loosen it.
- Respect `SYMBOL_TRADE_FREEZE_LEVEL`. Inside that distance the broker refuses
  modification, and retrying produces a stream of rejections.

```cpp
void UpdateTrailingStop(int trailPoints, int stepPoints)
{
   double point       = _Point;
   long   stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   if(trailPoints < stopsLevel)
      trailPoints = (int)stopsLevel + 1;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long   type    = PositionGetInteger(POSITION_TYPE);
      double openPr  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
      {
         if(bid - openPr < trailPoints * point) continue;      // not in profit enough
         if((bid - curSL) < (freezeLevel + 1) * point) continue; // too close to modify

         double newSL = NormalizeDouble(bid - trailPoints * point, _Digits);
         if(newSL > curSL + stepPoints * point)                 // only ever upward
            if(!trade.PositionModify(ticket, newSL, curTP))
               PrintFormat("Modify failed #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(openPr - ask < trailPoints * point) continue;
         if((curSL - ask) < (freezeLevel + 1) * point) continue;

         double newSL = NormalizeDouble(ask + trailPoints * point, _Digits);
         if(curSL == 0.0 || newSL < curSL - stepPoints * point) // only ever downward
            if(!trade.PositionModify(ticket, newSL, curTP))
               PrintFormat("Modify failed #%I64u: %s", ticket, RetcodeText(trade.ResultRetcode()));
      }
   }
}
```

`stepPoints` exists so the stop is not rewritten on every single tick. Without
it the EA sends thousands of modifications a day.

---

## Break even

A special case of trailing: move the stop to entry once the trade is far enough
ahead, then leave it.

```cpp
if(type == POSITION_TYPE_BUY && bid - openPr >= triggerPoints * _Point)
{
   double be = NormalizeDouble(openPr + lockPoints * _Point, _Digits);
   if(curSL < be)
      trade.PositionModify(ticket, be, curTP);
}
```

`lockPoints` should cover the spread and commission, otherwise "break even"
still closes at a small loss.

---

## Scaling out: close part at a first target, then break even

Verified in `src/Experts/OrbLondon.mq5`, 2026-09-15, build 6182. 68 positions,
35 partial closes, no rejected close and no rejected modify.

```cpp
double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double closeVol = NormalizeDouble(MathFloor((volume * percent / 100.0) / lotStep) * lotStep, 2);

if(closeVol >= minLot && (volume - closeVol) >= minLot)
   trade.PositionClosePartial(ticket, closeVol);
else
   Print("Volume cannot be split. Whole position runs to the final target.");

trade.PositionModify(ticket, NormalizePrice(openPrice), tp);   // stop to entry
```

Both halves of the test matter. `closeVol >= minLot` stops a zero-volume
request; `(volume - closeVol) >= minLot` stops the broker being left with a
remainder it cannot hold. At the minimum lot there is nothing to split, and the
EA must say so rather than silently skipping the target.

Decide in advance what happens when the split is impossible. Running the whole
position to the far target is one answer, closing all of it at the near target
is another. Both are defensible; picking one silently at 3am is not.

### Carry no state between ticks

The obvious implementation sets a `tp1Done` flag. It is wrong: the flag is
gone after a restart, and the EA scales out of the same position twice.

Ask the deal history instead. This is the reliable test, because the partial
close itself is the thing being remembered:

```cpp
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

// Called with PositionGetInteger(POSITION_IDENTIFIER), not the ticket. On a
// hedging account they are usually equal; on netting they are not.
```

A tempting shortcut is to read the stop instead: if it already sits at the
entry price, TP1 must have happened. That works only while the break-even move
is switched on. The moment it is made optional, the marker disappears and the
EA scales out on every tick for the rest of the trade. Measured 2026-09-15
while building a no-break-even variant of `OrbLondon`.

Keep the stop test as a second condition, not the only one: it covers the
position that was too small to split, where no `out` deal ever appears.

```cpp
if(HasClosedPart(positionId)) return;
if(InpMoveToBreakEven && sl > 0.0 &&
   (isBuy ? (sl >= open - halfPoint) : (sl <= open + halfPoint))) return;

// The R multiple the targets were built from, recovered from the order's own TP.
double span = MathAbs(tp - open) / InpTp2RangeMult;
```

The final target is the record of the trade's original size, so a restart in
the middle of a trade changes nothing at all.

---

## Multiple positions on a netting account

On a netting account the platform keeps one net position per symbol. Sending a
second buy adds to it rather than creating a second position, and
`PositionsTotal()` still returns one.

Any strategy that needs several independent positions must check first:

```cpp
if(!isHedging && InpMaxPositions > 1)
{
   Print("This EA needs a hedging account. This account is netting.");
   return(INIT_FAILED);
}
```

Refusing to start is correct. Running anyway produces position sizes nobody
asked for.

---

## Level versus cross, and why it is not a detail

"Buy when RSI is below 30" and "buy when RSI crosses up through 30" are two
different strategies. Descriptions almost never say which one is meant, and the
generated EA silently picks one. Ask.

```cpp
// LEVEL. True on every bar the condition holds.
bool ShouldOpenLong() { return(rsi[1] < InpBuyLevel); }

// CROSS. True only on the bar the boundary is broken.
bool ShouldOpenLong() { return(rsi[2] <= InpBuyLevel && rsi[1] > InpBuyLevel); }
```

A level rule keeps firing for as long as the level holds, so it re-enters the
moment the previous position closes. What actually limits it is
`InpMaxPositions` and `InpMaxTradesPerDay`, not the signal. Under a level rule
those two inputs stop being safety rails and become part of the strategy: raise
the daily cap and you have a materially different system.

Both were built from the same template with identical risk settings and measured
on the same window, EURUSDm H1, 2024.01.01 to 2024.12.31, model 1, 100% history
quality, 1% risk, SL 300, TP 600, max 1 position, max 5 entries per day.
Measured 2026-08-08.

| | `RsiLevel` (level) | `RsiReversal` (cross) |
|---|---|---|
| Total trades | 145 | 116 |
| Win rate | 36.55% | 36.21% |
| Payoff ratio | 1.90 | 1.89 |
| Profit factor | 1.09 | 1.07 |
| Net profit | 997.21 | 621.88 |
| Max equity drawdown | 2 440.54 (19.13%) | 1 409.07 (11.71%) |
| Recovery factor | 0.41 | 0.44 |

Same edge per trade, and the win rate and payoff are almost identical, which is
what you would expect from the same signal source. The level rule simply takes
25% more of the same trades. It earned 60% more and drew down 73% more for it,
and its recovery factor is slightly worse.

Neither of those profit factors is far enough above 1.0 to survive commission
and slippage. The point of the table is the mechanical difference between the
two rules, not either result.

---

## A pending limit that must die after N candles

Verified 2026-09-27, build 6230, `OrbLondon` RETEST mode on XAUUSD M5. Six runs,
311 limit orders placed, 218 filled, 93 cancelled, every cancel for a reason the
journal names.

Place it GTC and expire it yourself. `ORDER_TIME_SPECIFIED` needs the broker to
allow an expiry on that symbol, and it can only count seconds, while the rule is
almost always written in candles:

```cpp
bool ok = isBuy ? trade.BuyLimit (lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment)
                : trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, InpComment);
uint code = trade.ResultRetcode();
if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED))  // PLACED, not just DONE
```

`TRADE_RETCODE_PLACED` is the success code for a pending order. Checking only
for `DONE` reports every correctly placed limit as a rejection.

Count the candles from the order's own setup time, floored to the bar grid, and
compare against the bar that is forming. No counter, no global, so an order
placed before a restart is still expired on time:

```cpp
int      barSeconds = PeriodSeconds(WORK_TF);
datetime setup      = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
datetime setupBar   = (datetime)((long)setup - ((long)setup % barSeconds));
if((long)iTime(_Symbol, WORK_TF, 0) >= (long)setupBar + (long)InpRetestBars * barSeconds)
   trade.OrderDelete(ticket);       // lived through exactly InpRetestBars candles
```

Every other cancel test should also be recomputed rather than remembered. The
level the order is waiting at came from somewhere, a box, a swing, a gap, and
that somewhere can be rebuilt from bars, so "cancel if price closed back inside
the box" needs no stored state either.

Two results worth knowing before writing a retest rule:

- **A fill beats a cancel.** The fill happens on a tick inside the candle; a
  close-based cancel test only runs once that candle has closed. In 311 orders
  the close-back-inside test never fired once, because price cannot close back
  through the level without trading at it.
- **Bars are bid, a buy limit fills on the ask.** A buy limit at a level formed
  by bar highs needs the bid to fall a spread's width below that level before it
  fills. This is also why a limit placed at the level price has just broken is
  sometimes refused outright: by the time the order goes out, the ask is already
  within the stops level of it. That was 2 to 13 orders per run, logged rather
  than silently dropped:

```cpp
if(isBuy && entry > ask - minGap)   // no room left, the retest already happened
```

**Recorded:** 2026-09-27
