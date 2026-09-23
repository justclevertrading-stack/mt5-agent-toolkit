# Strategy: EmaCross

EMA 9/21 crossover on gold M5, traded only inside the London and New York
windows, with an optional H1 trend filter, a structural stop, a two-stage
target and a hard 16:00 flat.

## Market
- Symbol:                    XAUUSD (Vantage Markets, no suffix)
- Timeframe:                 M5
- Trading windows:           London 08:00-11:30 UK, New York 13:30-16:00 UK.
                             Everything flat at 16:00 UK.
- Days not to trade:         none specified, Monday to Friday as the broker offers them

### Time zones
Identical to `OrbLondon`: the server runs EET/EEST, so the EA takes
`InpServerUtcOffsetWinter` = 2 and `InpServerUtcOffsetSummer` = 3 and picks
between them with the EU daylight-saving calendar, then converts UTC to London
with the UK calendar. With these defaults UK time is server time minus two
hours all year. See `strategies/OrbLondon.md` for how that was verified against
gold's CME daily break.

A window is inclusive of its start and exclusive of its end, and the time
tested is the **entry** time, which is the moment the cross candle closes. So
the last London entry is 11:25 and the last New York entry is 15:55; nothing is
opened at 16:00, which is the same minute the flat fires.

## Indicators
| Name | Parameters | Applied to | Purpose |
|---|---|---|---|
| EMA fast | 9, M5 | Close | The cross itself |
| EMA slow | 21, M5 | Close | The cross itself |
| EMA fast | 9, `InpH1Timeframe` (H1) | Close | Trend filter |
| EMA slow | 21, `InpH1Timeframe` (H1) | Close | Trend filter |
| ATR | 14, M5 | - | `InpMinAtrPct` volatility floor |

Every value is read at index 1, the last **closed** bar of that indicator's own
timeframe. On H1 that is the previous full hour, never the hour still forming,
so the filter cannot repaint.

## Entry, long
1. On the M5 candle that has just closed, EMA9 > EMA21, and on the candle
   before it EMA9 <= EMA21. That is the bullish cross.
2. The entry time, which is that candle's close, falls inside the London or the
   New York window.
3. `InpH1Filter` is off, or H1 EMA9 > EMA21.
4. `InpMinAtrPct` is 0, or M5 ATR(14) is at least that percentage of price.
5. No position is open, and fewer than `InpMaxTradesPerDay` entries have been
   made this UK day.
6. Enter at market on the open of the next candle.

## Entry, short
The mirror image: EMA9 crossing below EMA21, H1 EMA9 < EMA21.

## Exit
- Stop loss:      the lowest low (long) or highest high (short) of the last 10
                  closed M5 candles, one point beyond it, then clamped so the
                  distance is never below 0.05% and never above 0.30% of the
                  entry price. The clamp moves the stop to the nearest allowed
                  distance; it does not cancel the trade.
- Take profit 1:  1.5R. Half the position closes and the stop moves to entry.
- Take profit 2:  3R for the remainder. This is the order's TP, so it fills
                  without the EA being connected.
- Opposite cross: closes everything, at any time of day. This is an exit rule,
                  not a session rule, so it is not gated by the windows.
- Early exit:     any position still open at 16:00 UK is closed at market.
- Trailing stop:  none.

If the lot is too small to split, TP1 still moves the stop to entry and the
whole position runs to TP2.

## Position sizing
Identical to `OrbLondon`.
- Method:                    % risk of balance
- Risk per trade:            1.0%
- Stop distance used:        the real distance from fill price to the clamped
                             structural stop
- Max simultaneous positions: 1
- Max entries per day:       3, counted from the deal history so a restart
                             cannot hand the EA a fourth trade. The day
                             boundary is UK midnight

## Filters
- Max spread:                50 points ($0.50 on a 2-digit XAUUSD)
- Broker stops level:        respected, floor of 20 points
- Do not trade when:         a position is open, three entries are already
                             made today, the H1 EMAs disagree (when the filter
                             is on), ATR is below the floor, spread too wide,
                             or the cross falls outside both windows

## Bar timing
- Entries act on the **closed** M5 bar.
- Position management (TP1, break even, the 16:00 flat) runs on every tick, so
  an intrabar TP1 touch is not missed.

## Logging

Every signal inside a window, taken or skipped, produces one line in the
Experts log and one row in `MQL5\Files\emacross_log.csv`
(`InpCsvFile`; `InpCsvCommonFolder` puts it in the shared `Common\Files`
instead, which is what the backtests below used because a tester agent's own
sandbox is thrown away).

```
date,time_uk,direction,h1_aligned,entry,stop,r_at_stop,outcome,r_result,
minutes_in_trade,session,retest6,retest6_close,profit_usd,reason
```

- `h1_aligned` is recorded whatever `InpH1Filter` is set to, so one file
  answers "how did the trades the filter would have blocked actually do".
- `outcome` is `TP2`, `SL`, `BE`, `opposite`, `timecut`, `TP1` (only reachable
  with `InpMoveToBreakEven` off), `SKIPPED`, or `OPEN` at the end of a run.
- `reason` is filled only on a `SKIPPED` row.
- `r_result` is realised money divided by the money risked at entry, so a
  position that takes half off at 1.5R and the rest at 3R reads 2.25.
- `minutes_in_trade` is entry to the last closing deal.
- The two `retest6` columns are explained below.
- Columns after `minutes_in_trade` are additions to the requested set, not
  replacements.

A row is written once both its outcome and its retest window are settled, so
the file is not in strict signal order; sort by date and time. Rows are held in
memory until then, which means a terminal restart loses the unwritten ones.
Nothing the EA trades on reads this file: every rule is recomputed from bars or
from the account.

### The "is the first cross a fake" measure

`retest6` asks: within the next 6 closed candles, did price come back to the
level where the two EMAs crossed, `(EMA9 + EMA21) / 2` on the cross candle?

`retest6_close` asks the same about the cross candle's **close**, which is
roughly the entry price. It is logged only to show why it is useless: on M5
gold price comes back through its own close within 6 candles 99% of the time,
and a measure that is always true answers nothing.

Both are measured on the candles **after** the cross, which overlap the trade.
This is a diagnosis of where the losses come from, not a filter that could be
applied at entry.

## Variants

Each is an input override on the one baseline binary, so no source changes
between runs.

| Input | Default | Variant it produces |
|---|---|---|
| `InpH1Filter` | true | false: take every cross, no H1 agreement needed |
| `InpMinAtrPct` | 0.0 | a percentage floor under M5 ATR(14) |
| `InpMoveToBreakEven` | true | false: TP1 still closes half, stop stays at the swing |
| `InpCloseOnOpposite` | true | false: only TP, SL and the 16:00 flat close a trade |
| `InpReverseOnOpposite` | true | false: the opposite cross is an exit only, it does not open the other way |
| `InpH1Timeframe` | PERIOD_H1 | any timeframe. 16385 in a set file |
| `InpCommissionPerLot` | 0.0 | Accounting only, never moves a trade |

## Measured results

XAUUSD M5, model 1, 100% history quality on every run, $10,000, 1% risk,
commission 0, `InpMaxTradesPerDay` 3. Statistics are **per position**, computed
from the EA's own signal CSV; its net profit reproduces the report's net
profit to the cent in all five runs. "Max DD" is the report's maximal equity
drawdown. Reports are in `reports/emacross-20260923-<variant>/`.

| Run | Inputs | Period | Signals | Trades | Win rate | PF | Net | Max DD | Avg R |
|---|---|---|---|---|---|---|---|---|---|
| A | H1 filter on | 2025.01.01-09.12 | 622 | 275 | 30.55% | 0.77 | -2 488.64 | 30.53% | -0.100 |
| B | H1 filter off | 2025.01.01-09.12 | 622 | 447 | 30.43% | 0.85 | -2 608.98 | 29.94% | -0.063 |
| C-A | H1 filter on | 2024 full year | 863 | 392 | 32.65% | 1.01 | +202.15 | 27.10% | +0.010 |
| C-B | H1 filter off | 2024 full year | 863 | 628 | 31.05% | 0.95 | -1 099.43 | 35.45% | -0.014 |
| D | A + `InpMinAtrPct` 0.03 | 2025.01.01-09.12 | 622 | 275 | 30.55% | 0.77 | -2 488.64 | 30.53% | -0.100 |

### Split by window

| Run | London trades / win / PF / net | New York trades / win / PF / net |
|---|---|---|
| A | 168 / 25.00% / 0.64 / -2 339.28 | 107 / 39.25% / 0.96 / -149.36 |
| B | 325 / 26.15% / 0.76 / -2 989.89 | 122 / 41.80% / 1.08 / +380.91 |
| C-A | 218 / 27.52% / 0.89 / -981.89 | 174 / 39.08% / 1.18 / +1 184.04 |
| C-B | 417 / 28.30% / 0.91 / -1 236.58 | 211 / 36.49% / 1.02 / +137.15 |

New York beat London on every measure in every run. London supplies most of the
trades and all of the loss.

### Split by H1 alignment

With the filter on, every trade is with-trend by construction, so the
comparison only exists inside the unfiltered runs.

| Run | With trend trades / win / PF / net | Counter trend trades / win / PF / net |
|---|---|---|
| B | 204 / 29.41% / 0.74 / -2 082.19 | 243 / 31.28% / 0.94 / -526.79 |
| C-B | 287 / 32.06% / 1.04 / +397.48 | 341 / 30.21% / 0.87 / -1 496.91 |

The two years disagree: in 2025 the counter-trend half was the better one, in
2024 the with-trend half was. The H1 filter is not separating winners from
losers in any stable way.

### Exit mix

| Run | opposite | timecut | SL | TP2 | BE |
|---|---|---|---|---|---|
| A | 162 | 45 | 38 | 17 | 13 |
| B | 286 | 50 | 54 | 31 | 26 |
| C-A | 210 | 69 | 53 | 36 | 24 |
| C-B | 396 | 77 | 75 | 56 | 24 |

Between 54% and 64% of trades end on the opposite cross, and 6% to 9% reach TP2.
On M5 gold the 9/21 pair crosses back long before 3R is reached, so the
opposite-cross rule, not the stop or the target, is what actually closes the
strategy's trades.

### The first cross is a fake about 56% of the time

Measured over every cross inside a window, taken or not, so the filter setting
does not change it.

| Period | Crosses | Returned to the EMA cross level within 6 candles | Returned to the cross candle's close |
|---|---|---|---|
| 2025.01.01-09.12 | 622 | 349 (56.1%) | 621 (99.8%) |
| 2024 full year | 863 | 492 (57.0%) | 856 (99.2%) |

Splitting the taken trades by that flag separates them almost completely:

| Run | Retested: trades / win / avg R | Not retested: trades / win / avg R |
|---|---|---|
| A | 160 / 15.6% / -0.345 | 115 / 51.3% / +0.240 |
| B | 249 / 18.1% / -0.277 | 198 / 46.0% / +0.205 |
| C-A | 231 / 16.9% / -0.298 | 161 / 55.3% / +0.452 |
| C-B | 354 / 15.3% / -0.275 | 274 / 51.5% / +0.324 |

Four runs across two years agree: a cross that gets pulled back to its own
crossing level loses, a cross that does not gets paid. The separation is far
larger than anything the H1 filter or the session split produces.

It is **not** a tradeable filter as measured. The six candles are after the
entry, so the flag is not knowable when the order is sent. What it says is
where the loss lives, not how to avoid it.

### `InpMinAtrPct` = 0.03 changes nothing, and why

Run D reproduces run A in every number: the filter skipped zero signals. On M5 gold
ATR(14) as a percentage of price sits roughly between 0.03% and 0.15%, so a
0.03% floor is under almost every candle.

A diagnostic run at 0.10% (`reports/emacross-20260923-D-probe010/`, not one of
the four requested) shows where the input starts to bite: of the 283 signals
the H1 filter let through, 189 were below 0.10% ATR and 94 were taken. Those 94
made 39.36% wins, PF 1.04, +152.47, maximal equity drawdown 13.46%, average
+0.021 R. Better than A on every line, on a quarter of the trades, and on one
untested threshold in one period, which is the definition of a number that
needs an out-of-sample run before it means anything.

## Explicitly forbidden
No averaging down, no martingale, no second position, no re-entry beyond the
three entries a day.

## Open questions
None blocking. Assumptions made and flagged to the user:
- **Window edges.** The window test is applied to the entry, not to the cross
  candle's open, so a cross candle that closes at 11:30 is too late.
- **"Plus 1 point".** Read as one point *beyond* the swing, so a long's stop is
  the lowest low minus a point. Configurable as `InpStopBufferPoints`.
- **The clamp acts on the distance.** A stop outside the 0.05% to 0.30% band is
  moved to the nearest edge of the band, not dropped.
- **"Swing low over the last 10 candles"** is the lowest low of the last ten
  closed candles, not a fractal or pivot definition.
- **The opposite cross reverses.** It closes the open trade, and the same cross
  is then eligible as an entry if the window, the filters and the daily cap
  allow. `InpReverseOnOpposite = false` makes it an exit only. This matters: it
  is why the daily cap of three is reached on 175 signals in run B.
- **R result** is realised money over money risked at entry, not a price
  distance, so partial exits are accounted for exactly.
- Break even means the exact entry price, with no buffer for commission.
