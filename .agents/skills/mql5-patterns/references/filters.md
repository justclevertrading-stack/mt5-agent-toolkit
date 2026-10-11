# Time, session and market condition filters

Verified by compile on 2026-08-05, MetaEditor build 5836.

---

## Broker time is not your time

`TimeCurrent()` returns the **trade server's** time. `TimeLocal()` returns the
machine's. They are almost never the same, and the difference moves twice a
year when daylight saving changes on one side and not the other.

Every session filter must use server time. A filter written against local time
silently shifts by an hour twice a year, and the EA starts trading a session it
was told to avoid.

```cpp
MqlDateTime t;
TimeToStruct(TimeCurrent(), t);   // server time. Never TimeLocal for filters.
// t.hour, t.min, t.day_of_week (0 = Sunday), t.mon, t.day
```

Tell the user which server time zone the filter assumes, and put it in the
strategy file. `TimeGMTOffset()` gives the machine's offset from GMT, which is
not the same as the server's.

---

## Session times given in a city's time, not the server's

Verified in `src/Experts/OrbLondon.mq5`, 2026-09-15, build 6182.

Traders describe sessions in London or New York time. The server is somewhere
else and both clocks change on their own calendar, so a single hard-coded
offset is wrong for part of the year.

Take the server's offset as two inputs, one per season, and convert through UTC:

```cpp
input int InpServerUtcOffsetWinter = 2;   // EET
input int InpServerUtcOffsetSummer = 3;   // EEST

//--- Last Sunday of the month at 01:00 UTC, when the EU clocks change.
//--- March and October both have 31 days, which is what makes this short.
datetime EuSwitchTime(const int year, const int month)
{
   MqlDateTime d; ZeroMemory(d);
   d.year = year; d.mon = month; d.day = 31; d.hour = 1;
   datetime candidate = StructToTime(d);
   MqlDateTime probe;  TimeToStruct(candidate, probe);
   return((datetime)((long)candidate - (long)probe.day_of_week * 86400));
}

bool IsEuropeanSummerTime(const datetime utc)
{
   MqlDateTime t; TimeToStruct(utc, t);
   return(utc >= EuSwitchTime(t.year, 3) && utc < EuSwitchTime(t.year, 10));
}

datetime ServerToUk(const datetime serverTime)
{
   int offset = IsEuropeanSummerTime(serverTime) ? InpServerUtcOffsetSummer
                                                 : InpServerUtcOffsetWinter;
   datetime utc = (datetime)((long)serverTime - (long)offset * 3600);
   return(IsEuropeanSummerTime(utc) ? (datetime)((long)utc + 3600) : utc);
}

datetime UkDayOf(const datetime ukTime)        // UK midnight it belongs to
{
   long s = (long)ukTime;
   return((datetime)(s - (s % 86400)));
}

int UkMinuteOfDay(const datetime ukTime)
{
   long s = (long)ukTime;
   return((int)((s % 86400) / 60));
}
```

`datetime` needs the cast to `long` before `%` and before arithmetic on the
offset. Without it the expressions still compile but the intent is unclear and
mixed-type arithmetic has bitten this repository before.

The EU test on the server clock rather than on true UTC can only be wrong for
one hour early on a switching Sunday, hours before any London or New York
session.

### Verify the offset, do not trust what you were told

A user quoting "the server is UTC+3" is usually quoting the season they are in.
Most European brokers are EET/EEST and move to UTC+2 in winter. One hour of
error moves the whole session.

Gold is the cheapest yardstick. Its daily break is fixed to the CME, 16:00 to
17:00 Chicago, which is **22:00 to 23:00 London all year round**. Print the gap
between consecutive M5 bars over a few days, convert it with the code above,
and check where it lands:

```cpp
int gap = (int)(iTime(_Symbol, PERIOD_M5, 1) - iTime(_Symbol, PERIOD_M5, 2));
if(gap > 300)
   PrintFormat("GAP %d min | server %s | UK %s", gap / 60, ...);
```

Measured on Vantage XAUUSD, 2026-09-15: the gap is 00:00 to 01:00 server in
both January and June, which is 22:00 to 23:00 London under 2 in winter and 3
in summer. Both inputs confirmed in two probe runs of under a minute each,
using `-Model 2`.

A throwaway probe EA run on `Model=2` costs about a minute and settles a
question that otherwise silently shifts every trade in the backtest.

---

## Trading hours

```cpp
input int InpStartHour = 8;    // server time
input int InpEndHour   = 20;   // server time

bool IsWithinTradingHours()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   if(InpStartHour == InpEndHour)
      return(true);                       // no restriction

   if(InpStartHour < InpEndHour)
      return(t.hour >= InpStartHour && t.hour < InpEndHour);

   // Window crosses midnight, for example 22:00 to 04:00
   return(t.hour >= InpStartHour || t.hour < InpEndHour);
}
```

The midnight-crossing case is the one that gets forgotten, and it is exactly
the case an Asian-session strategy needs.

---

## Day of week

```cpp
bool IsTradingDay()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   if(t.day_of_week == 0 || t.day_of_week == 6)   // Sunday, Saturday
      return(false);

   // Many strategies avoid Friday's last hours, when liquidity thins out
   // and weekend gap risk begins.
   if(t.day_of_week == 5 && t.hour >= 20)
      return(false);

   return(true);
}
```

`day_of_week` is 0 for Sunday through 6 for Saturday. Some brokers open Sunday
evening in server time, so Sunday is not always empty.

---

## Spread

The cheapest and most important filter. Spread widens sharply at session opens
and around news, which is exactly when many strategies want to trade.

```cpp
bool IsSpreadAcceptable()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spread <= InpMaxSpreadPoints);
}
```

Note this is in **points**, not pips. On a 5-digit symbol, 30 points is 3 pips.

---

## Enough history to compute anything

Early in a backtest, and after a reconnect, the indicators do not have enough
bars yet. Reading them anyway produces signals from empty data.

```cpp
if(Bars(_Symbol, PERIOD_CURRENT) < InpSlowPeriod + 10)
   return;
```

`CopyBuffer` returning fewer elements than requested means the same thing, and
is the more reliable check. The template already returns early on it.

---

## Connection loss

On a home PC the internet will drop. The terminal reconnects by itself, but
while it is down, prices are stale and orders will fail.

```cpp
if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   return;                        // no connection, do nothing this tick

if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   return;                        // AutoTrading is off

if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   return;                        // the broker has disabled EA trading
```

These three checks belong at the top of `OnTick` in any EA that will run
unattended. They cost nothing and prevent a stream of failed orders.

Do not try to close positions when the connection is down. It will not work,
and the retries make the log unreadable.

---

## News

There is no reliable built-in way to know a news release is coming. MQL5 has an
economic calendar API, but it is not available during Strategy Tester runs, so
a filter built on it behaves differently in backtest and live. That difference
is worse than having no filter, because it makes the backtest meaningless.

The honest options, in order of preference:

1. **A manual time window.** The user names the dates and hours to avoid, and
   the EA skips them. Behaves identically in backtest and live.
2. **A wider spread filter.** Spread blows out during news, so the spread
   filter already blocks most of the danger without any calendar at all.

If the user asks for automatic news avoidance, explain the backtest problem
before building it. Do not silently produce a filter that only works live.

## Higher-timeframe value "as of" a past moment

To read an H1 indicator as it stood at some earlier M5 time (e.g. "H1 EMA at
the box end", evaluated later on), find the H1 bar containing that time and
step one bar older, so the value comes from a closed H1 bar and cannot repaint:

```mql5
int shift = iBarShift(_Symbol, PERIOD_H1, momentServer, false); // H1 bar containing the moment
double f[1];
if(shift < 0 || CopyBuffer(fastHandle, 0, shift + 1, 1, f) < 1) { /* not ready, retry later */ }
```

Cache the result per day once read, but do not cache a failure, so a missing
bar is retried on the next candle. Verified in `OrbRichard.mq5` (2026-10-11):
2025-02-25 NY read the 12:00 UK H1 bar at 13:45 UK.

**Recorded:** 2026-10-11
