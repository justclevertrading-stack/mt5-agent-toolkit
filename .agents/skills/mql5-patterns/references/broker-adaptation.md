# Broker adaptation

Read every one of these at runtime. None of them can be assumed.

All snippets verified by compile on 2026-08-05, MetaEditor build 5836.

---

## Symbol suffix

Brokers rename instruments. The Exness demo used for verification exposes
`EURUSDm`, `XAUUSDm`, `BTCUSDm`. Every symbol carries the `m` suffix, with no
exceptions. Other brokers use `.m`, `.raw`, `x`, or nothing.

A wrong symbol name is not a warning. The Strategy Tester aborts:

```
Tester   symbol EURUSD not exist
Terminal shutdown with -1000012358 (tester symbol does not exist)
```

**Never hardcode a symbol.** Take it from `_Symbol` for the attached chart, or
from an input for anything else.

---

## Netting or hedging

Netting accounts hold at most one position per symbol; an opposite order
reduces or reverses it rather than opening a second position. Hedging accounts
allow many. Code written for one is wrong on the other.

```cpp
long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);

if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   ; // multiple positions per symbol are allowed
else if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
   ; // one net position per symbol only
else
   ; // ACCOUNT_MARGIN_MODE_EXCHANGE, an exchange account
```

If the strategy needs simultaneous opposite positions, refuse to run on a
netting account rather than silently misbehaving.

---

## Filling mode

The wrong filling mode gets every order rejected with
`TRADE_RETCODE_INVALID_FILL` (10030). The compiler cannot catch it.

`SYMBOL_FILLING_MODE` is a bit mask, so test bits, do not compare.

```cpp
int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
bool canFOK = (filling & SYMBOL_FILLING_FOK) != 0;
bool canIOC = (filling & SYMBOL_FILLING_IOC) != 0;

ENUM_ORDER_TYPE_FILLING PickFilling()
{
   int mask = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((mask & SYMBOL_FILLING_FOK) != 0)
      return(ORDER_FILLING_FOK);
   if((mask & SYMBOL_FILLING_IOC) != 0)
      return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
}
```

With `CTrade`:

```cpp
trade.SetTypeFilling(PickFilling());
```

---

## Volume constraints

```cpp
double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
```

Rounding to the step is mandatory. See `risk-sizing.md` for `NormalizeLot`.

---

## Stops level and freeze level

Two different limits. Both apply.

```cpp
long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
```

- **Stops level**: minimum distance in points between the current price and a
  stop loss or take profit. Closer than this and the order is rejected with
  `TRADE_RETCODE_INVALID_STOPS` (10016).
- **Freeze level**: how close to the price an existing order may be before the
  broker forbids modifying or closing it. Ignoring this produces modification
  failures that look random.

Both are frequently zero on retail accounts, which is exactly why code that
ignores them appears to work until it meets a broker where they are not.

---

## Tick value and tick size

The basis of correct position sizing. Never derive lot size from points alone.

```cpp
double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
```

`tickValue` is already expressed in the account currency, which is what makes
it safe for cross pairs and metals. Deriving money risk from pip counts is not.

---

## Spread filter

```cpp
long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
if(spreadPoints > InpMaxSpreadPoints)
   return; // do not trade in this tick
```

Spread widens sharply around session opens and news. Every EA needs this.

A points threshold is per instrument. OrbLondon's default 50 points is $0.50
on Vantage XAUUSD but 0.50 index points on DJ30.i, whose spread is 1.2 to 1.5
index points (118 to 148 points) at the London and New York opens: left at
the default, the filter would refuse every Dow trade. 500 never rejected one
in 2024 or 2025. Measured 2026-10-09.

---

## Price thresholds in points, not in the quote currency

A filter written in dollars ("skip a range under $5") is only right on the
instrument it was written for. Take the bound as an `int` in the symbol's
points and convert it once, comparing in price:

```cpp
input int InpMinRangePoints = 500;   // $5.00 on a 2 digit XAUUSD
input int InpMaxRangePoints = 2500;  // $25.00

double span = hi - lo;
if(span < InpMinRangePoints * _Point || span > InpMaxRangePoints * _Point)
   return(false);
int spanPoints = (int)MathRound(span / _Point);   // for the journal only
```

Comparing `span` against `points * _Point` keeps the old dollar thresholds
bit for bit: `500 * 0.01` and `2500 * 0.01` round to exactly 5.0 and 25.0 in
a double. OrbLondon 1.13 replaced its dollar inputs this way and reproduced
the 1.12 XAUUSD CSV line for line (2025, both sessions, 178 rows). Comparing
`MathRound(span / _Point)` against the bound instead would move ties.

A "point" here is `_Point`, not an index point. On Vantage DJ30.i the point
is 0.01, so 30 to 200 Dow points is 3000 to 20000.

### Vantage DJ30.i, read 2026-10-09 (build 6230)

| Field | Value |
|---|---|
| Name | `DJ30.i`, "Dow Jones Index Cash CFD (USD)". `DJ30ft.i` is the future, `DOW` is Dow Inc stock |
| Digits / point / tick size | 2 / 0.01 / 0.01 |
| Tick value | 0.01 USD per 0.01 per lot, so $1 per index point per lot |
| Contract size | 1 |
| Volume min / step | 0.1 / 0.1 |
| Stops level | 500 points (5 index points) |
| Spread | floating, 118 to 148 points when read; mean of the M5 bar spread at 13:30 and 14:30 UK over 2024-2025 was 129 |
| Trade sessions | Mon to Fri 01:00 to 24:00 server, so 23:00 to 22:00 UK with a one hour break at 22:00 UK |
