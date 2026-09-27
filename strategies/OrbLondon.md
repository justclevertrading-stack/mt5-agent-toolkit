# Strategy: OrbLondon

Opening-range breakout on gold, with an EMA trend filter, a two-stage target
and a hard session close. Two sessions: London, and since 2026-09-27 New York
as well.

## Market
- Symbol:                    XAUUSD (Vantage Markets, no suffix)
- Timeframe:                 M5
- Trading sessions:          London: box 08:00-08:15 UK, entries 08:15 to
                             12:30 UK, flat at 20:00 UK.
                             New York: box 13:30-13:45 UK, entries 13:45 to
                             the flat time, flat at 16:00 UK.
- Days not to trade:         none specified, Monday to Friday as the broker offers them

### Time zones
The user's session times are Europe/London. The broker's server time was given
as UTC+3.

Vantage runs its servers on EET/EEST, so the offset is UTC+2 in winter and
UTC+3 in summer. The EA therefore takes both as inputs
(`InpServerUtcOffsetWinter` = 2, `InpServerUtcOffsetSummer` = 3) and picks
between them with the EU daylight-saving calendar, then converts UTC to London
with the UK calendar. Both calendars switch on the same instant, so with these
defaults UK time is always server time minus two hours.

If the server is in fact fixed at UTC+3 all year, set
`InpServerUtcOffsetWinter` = 3 and nothing else changes.

**Verified, not assumed.** Gold's daily break is fixed to the CME, 16:00 to
17:00 Chicago, which is 22:00 to 23:00 London all year. On Vantage XAUUSD the
M5 gap sits at 00:00 to 01:00 server in both January and June 2025, so the
offsets above put it at 22:00 to 23:00 London in both seasons. Measured
2026-09-15 with a throwaway probe EA on `Model=2`.

## Indicators
| Name | Parameters | Applied to | Purpose |
|---|---|---|---|
| EMA fast | 9, `InpEmaTimeframe` (M5 default) | Close | Trend filter, read on the breakout candle |
| EMA slow | 21, `InpEmaTimeframe` (M5 default) | Close | Trend filter, read on the breakout candle |

The EMAs are read on the last **closed** bar of `InpEmaTimeframe` at the
moment the M5 break candle closes. With the default M5 that is the break
candle itself. With H1 (variants G and H below) it is the previous full hour,
not the hour still forming, so every break inside the same hour sees the same
EMA values and the filter cannot repaint.

## The two sessions

Both sessions run the same rules on their own box. They are independent in
every respect that can block a trade:

| | London | New York |
|---|---|---|
| Box | `InpRangeStartHour`:`InpRangeStartMinute` for `InpRangeMinutes` | `InpNYStart` to `InpNYEnd` |
| Default box | 08:00-08:15 UK | 13:30-13:45 UK |
| Last entry | `InpLastEntryHour`:`InpLastEntryMinute`, 12:30 UK | `InpNYLastEntry`, 16:00 UK |
| Flat | `InpFlattenHour`:`InpFlattenMinute`, 20:00 UK | `InpNYFlatTime`, 16:00 UK |
| Magic | `InpMagic` | `InpMagic` + `InpNyMagicOffset` |
| Switch | `InpTradeLondon` | `InpTradeNY` |

- One trade per session per day, counted from the deal history **per magic
  number**. A London trade, open or closed, never uses up New York's entry and
  the reverse is also true. `InpMaxPositions` is likewise per session, so both
  can hold a position at the same time. The account is hedging, so the two stay
  separate; on a netting account the server would merge them, and the EA says
  so in the journal at startup.
- Both sessions convert server time to UK time through the one `ServerToUk`,
  so the New York box follows UK daylight saving exactly as London does.
- No last-entry time was specified for New York, so `InpNYLastEntry` defaults
  to the flat time. A separate rule refuses any entry at or after a session's
  own flat time, so with the defaults the last New York signal is the candle
  closing 15:55 UK. Without that rule a 15:55 break would open a position and
  the 16:00 flat would close it in the same second.

## Entry modes

`InpEntryMode` applies to both sessions.

| Mode | Behaviour |
|---|---|
| `BREAK` (default) | Market order on the close outside the box. The original rule |
| `RETEST` | A limit order at the box edge that was broken, box high for longs and box low for shorts. Stop and targets are unchanged, and the lot is sized on the limit-to-stop distance at the same risk percent |

In `RETEST` mode the order is cancelled, and the session finished, when any of
these happens first:

- `InpRetestBars` candles pass without a fill. Logged `SKIPPED_NO_RETEST`.
- A candle closes back inside the box while the order is unfilled. Logged
  `SKIPPED_BACK_INSIDE`.
- The session reaches its flat time. Logged `SKIPPED_SESSION_END`.

The cancel is decided from the order's own setup time and from the box
recomputed out of bars, so an order placed before a restart is still managed
correctly afterwards.

A fill beats a cancel, because a fill happens inside the candle and the cancel
test only runs when that candle has closed. `SKIPPED_BACK_INSIDE` is therefore
rare: to close back inside the box, price has to pass through the limit level,
which fills it. It can still happen, because MT5 bars are bid prices while a
buy limit fills on the ask, so a candle can close a spread's width below the
box high without the ask ever reaching it.

## The range
- The three M5 candles opening 08:00, 08:05 and 08:10 UK, and for New York
  the three opening 13:30, 13:35 and 13:40 UK.
- Range high = highest high of the three, range low = lowest low.
- Locked at 08:15 UK. All three candles must exist or the session is skipped.
- Range height = high - low, in dollars because XAUUSD is quoted in dollars.

## Entry, long
1. The range is locked and its height is between $5 and $25 inclusive.
2. An M5 candle closes above the range high.
3. On that same candle, EMA 9 > EMA 21.
4. Enter at market on the open of the next candle.

## Entry, short
1. The range is locked and its height is between $5 and $25 inclusive.
2. An M5 candle closes below the range low.
3. On that same candle, EMA 9 < EMA 21.
4. Enter at market on the open of the next candle.

Only the **first** close beyond a boundary is examined. If the EMA filter does
not confirm it, that side is finished for the session; the opposite side stays
live. `InpFirstBreakOnly = false` relaxes this to "any candle that closes
beyond with the EMA confirming".

No new entry on a candle that opens at or after 12:30 UK.

## Exit
- Stop loss:      the opposite side of the range. Long stops at the range low,
                  short stops at the range high.
- Take profit 1:  one range height from entry. Half the position closes and the
                  stop moves to the entry price.
- Take profit 2:  two range heights from entry, for the remainder. This is the
                  order's TP, so it fills without the EA being connected.
- Early exit:     any position still open at 20:00 UK is closed at market.
- Trailing stop:  none.

If the lot is too small to split (half would fall under the broker's minimum
volume), TP1 still moves the stop to entry and the whole position runs to TP2.

## Position sizing
- Method:                    % risk of balance
- Risk per trade:            1.0%
- Stop distance used:        the real distance from fill price to the opposite
                             side of the range
- Max simultaneous positions: 1
- Max entries per session:   1, counted from the deal history so a restart
                             cannot hand the EA a second trade

## Filters
- Max spread:                50 points ($0.50 on a 2-digit XAUUSD)
- Broker stops level:        respected, floor of 20 points as the user specified
- Do not trade when:         range height < $5 or > $25, range incomplete,
                             already traded this session, after 12:30 UK

## Bar timing
- Entries act on the **closed** M5 bar.
- Position management (TP1, break even, the 20:00 flat) runs on every tick, so
  an intrabar TP1 touch is not missed.

## Variants

Each is an input override on the one baseline binary, so no source changes
between runs. Baseline is every one of them at its default.

| Input | Default | Variant it produces |
|---|---|---|
| `InpUseEmaFilter` | true | false: take every break, no EMA agreement needed |
| `InpEmaTimeframe` | PERIOD_M5 | PERIOD_H1 (16385 in a set file): the 9/21 EMAs are read on the last closed H1 bar instead of the M5 break candle |
| `InpMoveToBreakEven` | true | false: TP1 still closes half, stop stays at the range edge |
| `InpStopAtMidpoint` | false | true: stop at the range midpoint. Targets stay at 1 and 2 range heights, so the lot doubles at the same 1% risk |
| `InpRangeFilterPct` | false | true: filter the range by `InpMinRangePct` to `InpMaxRangePct` of the range midpoint instead of by dollars |
| `InpCommissionPerLot` | 0.0 | Accounting only, never moves a trade. 0.00 is correct for a Vantage Standard STP account, where the cost is in the spread |
| `InpTradeLondon` | true | false: New York only |
| `InpTradeNY` | true | false: London only, which is what the EA did before 2026-09-27 |
| `InpEntryMode` | `BREAK` | `RETEST`: limit at the broken box edge instead of a market order |
| `InpRetestBars` | 6 | Candles a RETEST limit is given to fill |
| `InpCloseBackInsideExit` | false | true: close an open position when a candle closes back inside its box. **New behaviour.** The build before 2026-09-27 had no such exit, which is why the default is off: turning it on invalidates every earlier result |

Measured XAUUSD M5, 2025.01.01 to 2025.09.12, model 1, 100% history quality,
1% risk, $10,000, commission 0. Statistics are per position: MT5 counts each
closing deal as a trade, which the scale-out inflates.

| Variant | Trades | Win rate | PF | Net | Max equity DD |
|---|---|---|---|---|---|
| Baseline | 68 | 51.47% | 0.87 | -417.72 | 10.63% |
| No break even | 68 | 41.18% | 0.91 | -297.98 | 11.39% |
| Midpoint stop | 68 | 35.29% | 0.70 | -1 281.06 | 21.02% |
| Percent range filter | 74 | 52.70% | 0.94 | -188.18 | 10.66% |
| No EMA filter | 80 | 53.75% | 1.07 | +267.40 | 10.24% |
| Last three combined | 74 | 31.08% | 0.85 | -725.10 | 19.78% |

The only variant above break-even is the one with the EMA filter removed, and
splitting it in two shows the edge is not stable: Jan to Jun 59 trades at PF
1.28, Jul to Sep 21 trades at PF 0.62. Not run on real ticks.

### Variants G and H: H1 EMA filter

Measured 2026-09-16, same settings as the table above. G is the baseline with
`InpEmaTimeframe = PERIOD_H1`. H is G plus `InpRangeFilterPct = true`
(0.15% to 0.60% of the range midpoint instead of $5 to $25). 2024 is an
out-of-sample check; nothing was tuned on it. Trades and win rate are per
position. "Max DD" is the report's maximal equity drawdown for a full run and
the balance drawdown over closed positions for a sub-period, since the deals
table cannot give an intrabar figure. Reports `bt-20260916-154943` (G 2025),
`154949` (H 2025), `155026` (G 2024), `155004` (H 2024).

| Variant | Period | Trades | Win rate | PF | Net | Max DD |
|---|---|---|---|---|---|---|
| G | 2025.01.01 to 2025.09.12 | 56 | 48.21% | 0.83 | -466.96 | 7.80% equity |
| G | 2025 Jan to Jun | 40 | 50.00% | 0.98 | -41.52 | 7.19% balance |
| G | 2025 Jul to Sep | 16 | 43.75% | 0.50 | -425.44 | 7.51% balance |
| G | 2024.01.01 to 2024.12.31 | 12 | 33.33% | 0.44 | -424.79 | 4.25% equity |
| H | 2025.01.01 to 2025.09.12 | 61 | 49.18% | 0.90 | -289.27 | 7.72% equity |
| H | 2025 Jan to Jun | 45 | 51.11% | 1.06 | +133.24 | 6.68% balance |
| H | 2025 Jul to Sep | 16 | 43.75% | 0.51 | -422.51 | 7.50% balance |
| H | 2024.01.01 to 2024.12.31 | 35 | 37.14% | 0.69 | -630.84 | 7.13% equity |

Neither is above break-even over any full period, and both share the
baseline's shape: Jan to Jun roughly flat, Jul to Sep clearly losing.

### New York session and the two entry modes, measured 2026-09-27

XAUUSD M5, model 1, 100% history quality, 1% risk, $10,000, commission 0, every
other input at its default. MT5 build 6230. "Trades" is **positions**, counted
from the EA's own CSV, not the report's deal count, which the TP1 scale-out
inflates by about half again. "Max DD" is the report's maximal equity drawdown.
Reports are `reports\orbny-20260927-<variant>-<mode>-<period>.htm`.

| Variant | Mode | Period | Trades | Win % | PF | Net | Max DD |
|---|---|---|---|---|---|---|---|
| London | BREAK | 2025.01.01-09.26 | 72 | 52.78 | 0.97 | -97.43 | 933.44 (8.95%) |
| London | BREAK | 2024 | 17 | 52.94 | 1.00 | +0.34 | 358.27 (3.53%) |
| London | RETEST | 2025.01.01-09.26 | 50 | 42.00 | 0.75 | -678.11 | 1 002.26 (9.83%) |
| London | RETEST | 2024 | 12 | 41.67 | 0.78 | -148.13 | 316.07 (3.13%) |
| NY | BREAK | 2025.01.01-09.26 | 105 | 56.19 | 1.08 | +296.81 | 1 000.58 (9.59%) |
| NY | BREAK | 2024 | 109 | 49.54 | 1.01 | +38.07 | 1 067.85 (10.27%) |
| NY | RETEST | 2025.01.01-09.26 | 73 | 45.21 | 0.87 | -427.14 | 1 288.57 (12.23%) |
| NY | RETEST | 2024 | 83 | 46.99 | 1.05 | +161.72 | 1 094.50 (10.61%) |
| Both | BREAK | 2025.01.01-09.26 | 177 | 54.80 | 1.03 | +201.46 | 1 170.96 (11.08%) |
| Both | BREAK | 2024 | 126 | 50.00 | 1.00 | +12.47 | 1 116.65 (10.78%) |
| Both | RETEST | 2025.01.01-09.26 | 123 | 43.90 | 0.82 | -1 056.08 | 1 812.24 (17.50%) |
| Both | RETEST | 2024 | 95 | 46.32 | 1.00 | +10.90 | 1 046.73 (10.28%) |

Net split by session in the two-session runs, from the CSV:

| Run | London net | New York net |
|---|---|---|
| Both BREAK 2025 | -94.30 over 72 | +295.76 over 105 |
| Both BREAK 2024 | -3.95 over 17 | +16.42 over 109 |
| Both RETEST 2025 | -663.96 over 50 | -392.12 over 73 |
| Both RETEST 2024 | -137.15 over 12 | +148.05 over 83 |

RETEST mode against BREAK mode on the same breaks:

| Variant | Period | Breaks | Filled | Fill rate | Win % filled | Win % in BREAK |
|---|---|---|---|---|---|---|
| London | 2025 | 75 | 50 | 66.7% | 42.00 | 52.78 |
| London | 2024 | 17 | 12 | 70.6% | 41.67 | 52.94 |
| NY | 2025 | 107 | 73 | 68.2% | 45.21 | 56.19 |
| NY | 2024 | 112 | 83 | 74.1% | 46.99 | 49.54 |
| Both | 2025 | 182 | 123 | 67.6% | 43.90 | 54.80 |
| Both | 2024 | 129 | 95 | 73.6% | 46.32 | 50.00 |

What the numbers say, and what they do not:

- Waiting for the retest loses money in every period and on both sessions. It
  gives up a third of the breaks and the ones it does take win about 10
  percentage points less often. The pullback that fills the order is itself the
  signal failing: the trade starts closer to its stop with the same target.
- New York is the better of the two boxes on this data, and the only
  configuration above break-even over a full period in either year. Its edge is
  not large: PF 1.08 and 1.01 are inside the range commission and slippage
  erase, and the earlier work on this EA already showed that a 2025 profit
  factor near 1 splits into a positive first half and a negative second.
- The 2024 trade counts are not comparable between sessions. The dollar range
  filter admitted 17 London sessions and 109 New York ones, because the New
  York box averaged $9.82 against London's $6.24: 13:30 UK is 08:30 New York,
  when US data prints. As with variants G and H, a range filter in dollars is a
  filter on the price level as much as on the range.
- Roughly a third of New York trades, 30 of 105 in 2025, are closed by the
  16:00 flat rather than by a stop or a target. A 2h15 session against a target
  two box heights away truncates trades that London's 11h45 lets run.
- London's net differs slightly between its own run and the two-session run,
  -97.43 against -94.30 on the same 72 trades. Nothing about the London rules
  changed: the lot is 1% of balance, and in the two-session run the balance at
  each London entry has New York's results in it.
- Nothing here is walk-forward or real-tick tested, and none of it is a
  recommendation to trade.

### The environment moved under the older tables

The two tables above this one cannot be compared with this one. Re-running the
**unmodified** pre-2026-09-27 binary today over 2025.01.01 to 2025.09.12 gives
69 positions and net -146.81, where the 2026-09-15 baseline row records
-417.72. The source code is identical; the tester is now build 6230 instead of
6182, and the stored XAUUSD M5 history has changed, 49 433 bars today against
49 456 on 16 September.

That is why the London no-change check was run as a pair on the same day rather
than against the recorded numbers. Old binary and new binary, both over
2025.01.01 to 2025.09.12, `InpTradeNY = false`, `InpEntryMode = BREAK`:
identical on every field of the report, net -146.81, PF 0.95, 104 deals,
equity drawdown 933.44 (8.95%). Reports `orbny-20260927-parity-base-2025.htm`
and `orbny-20260927-parity-new-2025.htm`.

The 2024 trade count for G is not a property of the H1 filter. The dollar
range filter skipped 237 of 258 sessions in 2024 because the 08:00 to 08:15
range on gold was mostly $2 to $4 at 2024 prices; only 21 sessions reached
$5. The percent filter (H) admitted 35 positions from the same year. A range
filter in dollars is therefore a filter on the price level as much as on the
range, and the two years are not comparable under it.

## Logging

The EA writes one CSV row per break that produced an order attempt, taken or
not, so a London-only run and a two-session run can be compared from a single
file and the net can be split by session, which the HTML report cannot do.

```
date,time_uk,session,mode,direction,box_low,box_high,box_height,entry,stop,
r_at_stop,retest,outcome,r_result,minutes_in_trade,profit_usd,reason
```

- `session` is `LON` or `NY`, `mode` is `BREAK` or `RETEST`.
- `retest` is `Y` when a RETEST limit filled, `N` when it was cancelled, `-` in
  BREAK mode.
- `outcome` is one of `TP2`, `BE`, `TP1`, `SL`, `timecut`, `backinside`,
  `SKIPPED_*`, `OPEN` or `UNSETTLED`.
- One row per **position**, so the count is the real trade count rather than
  the report's deal count, which the TP1 scale-out inflates.
- `InpCsvCommonFolder = true` puts the file in `Common\Files`, which is where a
  backtest's file can be read from afterwards. See skill `mql5-patterns`,
  `references/logging-and-files.md`.

Verified on the 2025 London run of 2026-09-27: 69 rows summing to -146.81,
equal to the report's net profit to the cent, against the report's own count of
104 "trades".

The rows are diagnostics. No trading rule reads them, so a restart that loses
the unwritten ones costs log lines and nothing else.

## Explicitly forbidden
No averaging down, no martingale, no second position, no re-entry after the
session's one trade.

## Open questions
None blocking. Assumptions made and flagged to the user:
- "After 12:30" means a candle opening 12:30 or later is too late; the candle
  that closes at 12:30 is still a valid signal.
- The EMA filter is a condition on the first candle to close beyond a side,
  not a reason to wait for a later one. `InpFirstBreakOnly` switches this.
- Break even means the exact entry price, with no extra buffer for commission.
