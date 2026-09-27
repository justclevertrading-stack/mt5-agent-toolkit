# Position lookup, trade results, surviving a restart

Verified by compile on 2026-08-05, MetaEditor build 5836.

The live terminal for this project runs on a home PC, not a VPS. It will be
restarted by power cuts, Windows updates and the user, sometimes while a
position is open. Everything here assumes that.

---

## Never trust a variable, ask the account

After a restart every global resets to its default. The positions on the
account do not. Any decision that depends on history must read the account.

The failure this prevents: an EA that limits itself with
`int tradesToday = 0;` restarts at midday, resets the counter to zero, and
opens a second full day of trades.

```cpp
// WRONG
int tradesToday = 0;
if(tradesToday < InpMaxPerDay) { ... tradesToday++; }

// RIGHT
if(CountMyDealsToday() < InpMaxPerDay) { ... }
```

---

## Open positions belonging to this EA

```cpp
int CountMyPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}
```

Iterate **downwards**. Closing a position inside an ascending loop shifts the
indices and silently skips entries.

`PositionGetTicket(i)` selects the position as a side effect, which is why the
`PositionGetInteger` calls that follow need no ticket argument.

Filter on both magic number and symbol. Another EA, or the user trading by
hand, may hold positions on the same account.

---

## Deals closed today

```cpp
int CountMyDealsToday()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
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
      if(ticket == 0)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}
```

`TimeCurrent()` is **broker server time**, not the machine's local time. The
server's day boundary is what matters for a daily limit, and its GMT offset
differs by broker and shifts with daylight saving. Never use `TimeLocal()` for
this.

**Weekend pitfall.** `TimeCurrent()` is the time of the *last tick*, not the
current time. While the market is closed it stays frozen on Friday night, so a
"today" count run on a Saturday or Sunday (for example in `OnInit` when the EA
is attached) counts Friday's deals. This happened to OrbLondon. On a Sunday
attach it reported "1 entry(ies) already today" because of Friday's trade. For
"now" outside the tester, use `TimeTradeServer()`, which the terminal computes
from the local clock and keeps running. Also check each deal's own `DEAL_TIME`
against the target day:

```cpp
datetime ServerNow()
{
   if(MQLInfoInteger(MQL_TESTER))
      return(TimeCurrent());            // simulated clock in the tester
   datetime live = TimeTradeServer();
   return(live > TimeCurrent() ? live : TimeCurrent());
}
```

---

## Trade result codes

Every trade operation must be checked. `CTrade` exposes the code through
`trade.ResultRetcode()`.

```cpp
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
```

What each one usually means in practice:

| Code | Meaning | Sensible response |
|---|---|---|
| 10004 requote | Price moved during the request | Retry a small number of times, then give up |
| 10006 rejected | Broker refused | Log and stop. Do not loop |
| 10014 invalid volume | Lot not normalised to the step | Fix the sizing code, not the retry logic |
| 10016 invalid stops | Stop closer than `SYMBOL_TRADE_STOPS_LEVEL` | Widen the stop |
| 10019 no money | Insufficient free margin | Stop trading, alert the user |
| 10018 market closed | Outside session hours | Wait |
| 10030 invalid fill | Wrong filling mode | See `broker-adaptation.md` |

Never retry in an unbounded loop. On a live account a tight retry loop against
a rejecting broker is how an EA generates hundreds of requests in a minute.

---

## Persisting something that genuinely must survive

Prefer rebuilding from the account. If a value truly cannot be derived, write
it to a file in `MQL5\Files\` or use `GlobalVariableSet`, and still treat the
account as the source of truth in `OnInit`.

## One magic number per session, when sessions must not block each other

Verified 2026-09-27, build 6230, `OrbLondon` trading a London and a New York
box on XAUUSD M5.

"One trade per session" and "one position at a time" are almost always written
as a single cap over the whole EA. As soon as there are two sessions, that cap
silently couples them: the London trade consumes the day's entry, or is still
open when the New York box breaks, and the second session never trades. The
symptom is a two-session EA that produces exactly the one-session results.

Give each session its own magic number and make every count take one:

```cpp
long SessionMagic(const int s) { return(s == SESSION_NY ? InpMagic + InpNyMagicOffset : InpMagic); }

int SessionOfMagic(const long magic)          // which session a position belongs to
{
   if(magic == InpMagic)                    return(SESSION_LON);
   if(magic == InpMagic + InpNyMagicOffset) return(SESSION_NY);
   return(-1);                               // not ours
}

int CountMyPositions(const long magic)    { ... PositionGetInteger(POSITION_MAGIC) == magic ... }
int CountMyEntriesToday(const long magic) { ... HistoryDealGetInteger(t, DEAL_MAGIC) == magic ... }
```

The cap is then per session and still read from the account, so it survives a
restart exactly as the single-session version did. It also separates the two in
the History tab and in any per-trade log, which is the only way to answer "which
session made the money".

Two things to check before shipping it:

- **Netting versus hedging.** Two positions on one symbol only coexist on a
  hedging account. On netting the server merges them into one net position
  whatever the magic numbers say, and the second entry partly closes the first.
  Read `ACCOUNT_MARGIN_MODE` in `OnInit` and say so in the journal.
- **Refuse an entry at or after that session's own flatten time.** A session
  whose last-entry time equals its flatten time will otherwise open a position
  on the candle that closes at the flat and close it in the same second. Three
  such trades appeared in a first run and disappeared with a one-line guard.

To prove the sessions really are independent, run each alone and then together
and compare the per-session trade counts: 72 London and 105 New York alone, 72
and 105 together, with 43 days holding one of each.

**Recorded:** 2026-09-27
