# OrbLondon NY split: cash-open skip, chop filter, retest entry, and EmaPullback

Measured 2026-10-25 on the backtest-only install `C:\MT5-Backtest` (build
6230), branch `ny-split` (from `lid-fade` at `4ef1794`). Settings reused from
`strategies/lid-fade-results.md`: Vantage data, M5, model 1 (1 minute OHLC),
$10,000, USD, 1:100, 1% risk, commission 0, BREAK mode,
`InpFirstBreakOnly = true`, EMA 9/21 M5 cross filter.

Years: 2023 = 2023.01.01-12.31, 2024 = 2024.01.01-12.31, 2025 =
2025.01.01-09.26 (same end date as the earlier batches). History quality
was 100% on every run listed here.

**Sessions.** New York only: `InpTradeLondon=false`, `InpTradeNY=true`, NY box
13:30-13:45 UK, last entry 16:00, flat 18:00 (the live NY times; the EA's
compiled default flat is 16:00, so `InpNYFlatTime=18:00` is passed on every
run).

**DJ30.i inputs** on top, as in the earlier Dow transplant
(`strategies/OrbLondon.md`): `InpMinRangePoints=3000`,
`InpMaxRangePoints=20000` (30 to 200 index points), `InpMaxSpreadPoints=500`.

**Pass bar:** PF > 1.3 in all three years AND max equity drawdown < 10% in
all three years.

**Columns.** Trades, win % (profit > 0), PF and net come from the EA's CSV,
one row per position, as in the earlier batches. Max DD is the report's
maximal equity drawdown. Reports and CSVs are local only (`reports/` is
gitignored): `reports/nysplit-20261025-<variant>-<XAUUSD|DJ30i>-<year>.*`.

## Assumptions

- **Path.** The brief names `MQL5/Experts/`; this repository keeps sources in
  `src/Experts/`, so the EA is `src/Experts/OrbLondon.mq5` and the new EA
  `src/Experts/EmaPullback.mq5`.
- **Starting version.** `lid-fade` was at 1.15 (New York only by default), not
  1.14. 1.15 with the live NY times reproduces the NY-only baseline of the
  lid-fade batch exactly (gold 2025 +901.23, PF 1.24, DD 9.52%), so the new
  work starts from it as 1.16.
- **BASE.** Every job is compared against BASE = NY only with
  `InpSkipCashOpenBar=false`, i.e. 1.15 behaviour. It is not in the brief but
  is needed to see what each change does.
- **Later variants build on S0.** The cash-open skip defaults to true, so C2,
  C3, C4, A30, R1 and R1C3 all run with it on.
- **DJ30.i 2023.** The Dow notes of 2026-10-09 say M5 history started
  2024-01-02. The install now holds 2023 as well (70 410 bars, quality 100%),
  so 2023 is included for both symbols.
- **Stale build caught.** `compile.ps1` writes the `.ex5` next to the source;
  the tester reads `C:\MT5-Backtest\MQL5\Experts`. The first S0 batch ran the
  old 1.15 build and matched BASE to the cent. It was discarded, the build
  was copied into the tester, and every number below comes from the
  deployed build of its job.

## Job 1: cash-open bar skip (S0)

**Rule.** New inputs `InpSkipCashOpenBar` (default **true**) and
`InpCashOpenUK` (default `"14:30"`). An entry is sent at the open of the bar
after the break candle, so the candle that closes at 14:30 UK is the one
whose order would land inside the 14:30-14:35 cash-open bar. That candle is
not entered, and it does not count as the session's first break. The
decision waits for the cash-open bar's own close at 14:35: if that candle
also closes beyond the same edge (and the EMA agrees), it is entered at
14:35. A 14:30 candle that closes beyond is entered normally at 14:35.
Logged "cash-open skip". Applies to both sessions; London never reaches
14:30.

`InpCashOpenUK` is a fixed UK time. In the weeks when US and UK clocks are
out of step (about three weeks in March, one around the end of October)
the US cash open is 13:30 UK, inside the NY box, and the skip lands on the
wrong bar unless the input is moved. These runs leave it at 14:30
throughout.

**XAUUSD**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| BASE | 2023 | 94 | 53.2 | 1.29 | +882.61 | 6.23% | no |
| BASE | 2024 | 110 | 51.8 | 1.01 | +50.03 | 10.50% | no |
| BASE | 2025 | 107 | 59.8 | 1.24 | +901.23 | 9.52% | no |
| S0 | 2023 | 94 | 54.3 | 1.34 | +1030.42 | 4.35% | yes |
| S0 | 2024 | 110 | 52.7 | 1.05 | +197.52 | 9.11% | no |
| S0 | 2025 | 107 | 59.8 | 1.24 | +897.30 | 8.33% | no |

**DJ30.i**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| BASE | 2023 | 155 | 55.5 | 1.11 | +717.48 | 8.88% | no |
| BASE | 2024 | 160 | 54.4 | 1.05 | +367.65 | 13.48% | no |
| BASE | 2025 | 115 | 60.9 | 1.34 | +1585.36 | 6.70% | yes |
| S0 | 2023 | 155 | 56.8 | 1.14 | +942.93 | 6.56% | no |
| S0 | 2024 | 159 | 56.0 | 1.02 | +100.52 | 13.36% | no |
| S0 | 2025 | 115 | 62.6 | 1.38 | +1710.57 | 6.88% | yes |

**Verdict.**
- **XAUUSD S0: fails.** The skip helps every year's drawdown (6.23 to 4.35%,
  10.50 to 9.11%, 9.52 to 8.33%) and lifts 2023 to PF 1.34, but 2024 (1.05)
  and 2025 (1.24) stay well under 1.3. Same trade count every year: the skip
  defers entries by one bar, it does not remove them.
- **DJ30.i S0: fails.** 2025 passes (PF 1.38, DD 6.88%) but 2023 is PF 1.14
  and 2024 PF 1.02 with a 13.36% drawdown.

## Job 2: split scorecard, S0

| | 2023 PF / DD | 2024 PF / DD | 2025 PF / DD | Passes the bar? |
|---|---|---|---|---|
| XAUUSD | 1.34 / 4.35% | **1.05** / 9.11% | **1.24** / 8.33% | **No.** PF under 1.3 in 2024 and 2025 |
| DJ30.i | **1.14** / 6.56% | **1.02** / **13.36%** | 1.38 / 6.88% | **No.** PF under 1.3 in 2023 and 2024, DD over 10% in 2024 |

**Neither symbol passes.** Gold is the steadier of the two on drawdown, under
10% in all three years, so its only problem is PF. The Dow has the best single
year (2025) but fails 2024 on both PF and drawdown.

## Job 3: chop filter (C2, C3, C4) and minimum box against ATR (A30)

**Rules.** All on top of S0.
- `InpChopFilter` (default false), `InpChopMult` (default 3.0),
  `InpChopStartUK` (default `"06:00"`): the high to low of the M5 candles
  from 06:00 UK up to the NY box start (13:30) is measured; when it is more
  than `InpChopMult` box heights, the NY box is skipped that day. Missing
  candles in the window are tolerated. New York only. Logged "chop skip".
- `InpMinBoxAtrPct` (default 0 = off): a box smaller than that percent of
  ATR(14) on H1 is skipped. The ATR is read on the last H1 bar that had
  closed when the box locked (the 12:00-13:00 UK bar for the 13:30-13:45
  box), so it cannot change during the session. Applies to both sessions.
  Logged "ATR skip".

**XAUUSD**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| S0 | 2023 | 94 | 54.3 | 1.34 | +1030.42 | 4.35% | yes |
| S0 | 2024 | 110 | 52.7 | 1.05 | +197.52 | 9.11% | no |
| S0 | 2025 | 107 | 59.8 | 1.24 | +897.30 | 8.33% | no |
| C2 | 2023 | 72 | 58.3 | 1.73 | +1347.86 | 2.36% | yes |
| C2 | 2024 | 60 | 58.3 | 1.43 | +729.53 | 5.39% | yes |
| C2 | 2025 | 25 | 40.0 | 0.74 | -282.93 | 6.65% | no |
| C3 | 2023 | 86 | 55.8 | 1.50 | +1282.87 | 2.92% | yes |
| C3 | 2024 | 85 | 57.6 | 1.42 | +1084.79 | 4.09% | yes |
| C3 | 2025 | 53 | 52.8 | 0.96 | -84.73 | 8.84% | no |
| C4 | 2023 | 91 | 54.9 | 1.38 | +1101.41 | 3.96% | yes |
| C4 | 2024 | 99 | 56.6 | 1.28 | +885.65 | 5.87% | no |
| C4 | 2025 | 72 | 54.2 | 1.06 | +161.14 | 11.39% | no |
| A30 | 2023 | 94 | 54.3 | 1.34 | +1030.42 | 4.35% | yes |
| A30 | 2024 | 110 | 52.7 | 1.05 | +197.52 | 9.11% | no |
| A30 | 2025 | 106 | 59.4 | 1.22 | +849.38 | 8.33% | no |

**DJ30.i**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| S0 | 2023 | 155 | 56.8 | 1.14 | +942.93 | 6.56% | no |
| S0 | 2024 | 159 | 56.0 | 1.02 | +100.52 | 13.36% | no |
| S0 | 2025 | 115 | 62.6 | 1.38 | +1710.57 | 6.88% | yes |
| C2 | 2023 | 52 | 55.8 | 1.04 | +78.28 | 8.05% | no |
| C2 | 2024 | 59 | 49.2 | 0.86 | -359.03 | 9.77% | no |
| C2 | 2025 | 20 | 60.0 | 1.54 | +375.49 | 3.69% | yes |
| C3 | 2023 | 87 | 57.5 | 1.21 | +725.62 | 7.66% | no |
| C3 | 2024 | 100 | 54.0 | 1.04 | +184.33 | 11.79% | no |
| C3 | 2025 | 39 | 56.4 | 1.07 | +104.94 | 5.75% | no |
| C4 | 2023 | 119 | 58.8 | 1.26 | +1260.08 | 6.41% | no |
| C4 | 2024 | 126 | 55.6 | 0.99 | -28.27 | 13.55% | no |
| C4 | 2025 | 64 | 60.9 | 1.21 | +527.87 | 6.47% | no |
| A30 | 2023 | 155 | 56.8 | 1.14 | +942.93 | 6.56% | no |
| A30 | 2024 | 159 | 56.0 | 1.02 | +100.52 | 13.36% | no |
| A30 | 2025 | 115 | 62.6 | 1.38 | +1710.57 | 6.88% | yes |

**Verdict.**
- **C2, XAUUSD: fails.** The best 2023 and 2024 of the whole batch (PF 1.73
  and 1.43, DD under 6%), then 2025 collapses to 25 trades at PF 0.74. In
  2025's strongly trending gold, most mornings were wider than two NY boxes,
  so the filter removed most of the year and kept the losers.
- **C3, XAUUSD: fails, nearest miss on gold.** 2023 PF 1.50 and 2024 PF 1.42,
  both with drawdown under 5%, but 2025 is PF 0.96 on 53 trades. Two of three
  years pass; the year that fails is the most recent one.
- **C4, XAUUSD: fails.** Milder: 2023 passes, 2024 PF 1.28 just misses,
  2025 PF 1.06 with an 11.39% drawdown.
- **C2, C3, C4, DJ30.i: all fail.** The chop filter does not help the Dow:
  every multiple makes 2024 worse or barely changes it, and C2 and C3 cut the
  good 2025. Only C2 2025 passes, on 20 trades.
- **A30, both symbols: fails, and is close to a no-op.** It skipped one
  session in three years (gold, 2025-05-07). The points range filter
  (500 points on gold, 3000 on the Dow) already removes nearly every box
  smaller than 30% of H1 ATR.

The chop result on gold is the most interesting of the batch, but it is a
sign change in the most recent year rather than a weak year, and the
multiple that does best (2 to 3) also discards the most trades. Treat it as
a lead to re-test on 2022 and on 2025.10 onwards, not as an edge.

## Job 4: retest-only entry (R1, R1C3)

**Rule.** `InpRetestOnly` (default false), `InpRetestTolerance` (default
1.0). After the session's first M5 close beyond a box edge, with the EMA
agreeing on that break candle, the break is not entered. The first later
close that is still beyond the same edge by no more than the tolerance is
entered at market. If any candle from the break onwards reaches more than
one box height beyond the edge before that, the setup is cancelled (98
cancellations logged over the 12 runs). Stop, TP1/TP2, last entry, flat and
one trade per session are unchanged. The cash-open skip still applies to
the entry candle. R1C3 adds the chop filter at 3x.

**Assumption: tolerance in price units.** The brief says "1.0 points". In this
EA a point is the symbol's `_Point`, $0.01 on gold and 0.01 index points on
the Dow; a close within one cent of the edge would almost never happen. So
1.0 is read as price: $1.00 on XAUUSD, 1 index point on DJ30.i. That is
about a tenth of a typical gold box, but only about 2% of a typical Dow box
(median 44 to 52 points). That is why the Dow takes so few trades.

Checked in the journal: XAUUSD 2023-01-18, break close 1916.10 below the box
low 1916.19 at 15:10 UK; the 17:15 UK candle closed at 1915.27, 0.92 under
the edge, and the short was entered.

**XAUUSD**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| R1 | 2023 | 58 | 46.6 | 0.88 | -246.48 | 7.13% | no |
| R1 | 2024 | 71 | 56.3 | 1.15 | +351.26 | 5.05% | no |
| R1 | 2025 | 46 | 45.7 | 0.80 | -459.09 | 8.15% | no |
| R1C3 | 2023 | 55 | 49.1 | 1.04 | +66.48 | 4.73% | no |
| R1C3 | 2024 | 53 | 62.3 | 1.61 | +883.28 | 3.89% | yes |
| R1C3 | 2025 | 23 | 39.1 | 0.54 | -548.35 | 7.17% | no |

**DJ30.i**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| R1 | 2023 | 14 | 64.3 | 2.06 | +463.81 | 3.00% | yes |
| R1 | 2024 | 17 | 58.8 | 1.69 | +435.96 | 3.06% | yes |
| R1 | 2025 | 2 | 50.0 | 1.46 | +45.91 | 1.80% | yes |
| R1C3 | 2023 | 9 | 66.7 | 3.06 | +485.46 | 1.96% | yes |
| R1C3 | 2024 | 7 | 57.1 | 1.95 | +219.47 | 2.06% | yes |
| R1C3 | 2025 | 0 | - | - | 0.00 | 0.00% | no |

**Verdict.**
- **R1, XAUUSD: fails.** Worse than S0 in 2023 and 2025 (PF 0.88 and 0.80).
  Waiting for the retest misses the breaks that run, and those are the winners.
- **R1C3, XAUUSD: fails.** 2024 is good (PF 1.61) but 2025 is PF 0.54 on 23
  trades.
- **R1, DJ30.i: passes the bar on paper, but the sample is far too small to
  mean anything.** PF 2.06 / 1.69 / 1.46 with drawdown at or under about 3%,
  but on 14, 17 and **2** trades. Two trades cannot show a profit factor, and
  33 trades over 2.75 years cannot tell an edge from luck. It passes only
  because the 1-point tolerance lets almost nothing through.
- **R1C3, DJ30.i: fails.** No trades at all in 2025.

## Job 5: EmaPullback, a separate EA (E1H, E4H, E1H-NY)

`src/Experts/EmaPullback.mq5`, built from `templates/EA_Template.mq5`.
Compiled with 0 errors and 0 warnings on the first attempt.

**Rules as built.**
- Trend on the chart timeframe: long needs close > EMA200 and EMA50 > EMA200,
  short the mirror.
- **Long:** the bar's low is at or below EMA50 x (1 + 0.3%), so it came
  within 0.3% of EMA50 or went through it; RSI(14) is 40 to 55 inclusive; the
  bar closes above EMA50.
- **Short:** the bar's high is at or above EMA50 x (1 - 0.3%); RSI 45 to 60;
  the bar closes below EMA50.
- Entry at market on the next bar's first tick, i.e. at the close.
- Stop: lowest low (highest high) of the last 5 closed bars, the signal bar
  included. TP = 1.5 x the actual entry-to-stop distance. No other exit.
- One position at a time. At least 12 bars between entries, counted from the
  last entry deal in history (restart-safe). Fixed 0.1 lot. Spread cap 50
  points. No session filter.
- **E1H-NY:** `InpUseTimeWindow=true`, entries only from 12:00 to 19:59 UK
  (server time converted with the EU DST calendar, as in OrbLondon). Exits
  are not time-limited.
- A stop inside the broker's stops level is refused rather than widened.

**Assumption: fixed lot.** The repository rule is percent-of-balance sizing.
The brief asks for a fixed 0.1 lot, so `InpFixedLot=0.1` is the default, and
`InpFixedLot=0` switches to `InpRiskPercent` sizing. With a fixed lot, the
money at risk per trade varies with the stop width, so drawdowns here are
not comparable with the 1%-risk OrbLondon runs.

Trades, win %, PF and net come from the report; the EA closes each position
in one deal, so report trades are positions.

**XAUUSD**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| E1H | 2023 | 220 | 42.3 | 1.17 | +855.02 | 9.93% | no |
| E1H | 2024 | 203 | 38.4 | 0.91 | -620.57 | 17.72% | no |
| E1H | 2025 | 147 | 36.1 | 1.02 | +144.92 | 19.63% | no |
| E4H | 2023 | 45 | 48.9 | 1.68 | +1193.46 | 5.82% | yes |
| E4H | 2024 | 46 | 34.8 | 0.82 | -758.65 | 20.29% | no |
| E4H | 2025 | 33 | 45.5 | 1.52 | +1895.45 | 10.64% | no |
| E1H-NY | 2023 | 149 | 40.9 | 1.10 | +365.14 | 9.25% | no |
| E1H-NY | 2024 | 134 | 44.8 | 1.23 | +1079.79 | 12.91% | no |
| E1H-NY | 2025 | 92 | 35.9 | 0.78 | -1582.93 | 31.04% | no |

**Verdict.**
- **E1H: fails.** PF 1.17 / 0.91 / 1.02, with drawdowns near 18-20% in 2024
  and 2025. The win rate (36-42%) is too low for a 1.5R target.
- **E4H: fails.** It has the best years of the job (2023 PF 1.68, 2025 PF
  1.52), but 2024 is PF 0.82 with a 20.29% drawdown, and 2025's drawdown is
  10.64%. 33 to 46 trades a year.
- **E1H-NY: fails.** The time window helps 2024 (PF 1.23) and costs 2025 badly
  (PF 0.78, 31.04% drawdown). The fixed 0.1 lot with wide H1 stops at 2025
  gold prices is part of that drawdown.

## Job 6: 9 EMA + VWAP V1/V2/V3: skipped

No specification found. A case-insensitive search for "VWAP" across the
whole repository, `strategies/` included, returns nothing. Nothing was built
or run.

## What passes

**On the letter of the bar, one combination: R1 (retest-only entry) on
DJ30.i**, at PF 2.06 / 1.69 / 1.46 and max DD 3.00% / 3.06% / 1.80%.

It should not be treated as a pass. It made 14, 17 and 2 trades. The 2025
"PF 1.46" is one winner and one loser. The count is small because the
retest tolerance (1 index point, see Job 4) is about 2% of a typical Dow box.
A fair test of the idea needs a tolerance scaled to the box (for example a
fraction of its height) and enough trades to judge, at least 30 a year.

Nothing else clears the bar on either symbol. The nearest real candidate is
**C3 on XAUUSD** (chop filter at 3x): PF 1.50 and 1.42 with drawdown under 5%
in 2023 and 2024, but PF 0.96 in 2025.

Nothing here justifies changing the live settings. The only new default,
`InpSkipCashOpenBar=true`, changes the live build when it is recompiled. On
gold it cut drawdown in every year and cost at most $4 (2025); on the Dow it
helped 2023 and 2025 but cost $267 in 2024 (+367.65 to +100.52). Set it false
to keep 1.15 behaviour exactly.

## Caveats

- One broker's data, commission 0, model 1 (not real ticks).
- The variants were chosen in advance by the brief, but several were
  compared on the same three years. The best of nine variants on one sample
  will look better than it is.
- `InpCashOpenUK` stays at 14:30 all year, so in the weeks UK and US clocks
  are out of step the skip lands an hour after the real cash open.
- None of this is a recommendation to trade.

## Job 7: S0-fixed (1.17), cash-open entry deferred instead of skipped

Measured 2026-11-08, branch `ny-split` at `41265b6`, same install and tester
settings as Job 1: NY only, box 13:30-13:45 UK, last entry 16:00,
`InpNYFlatTime=18:00`, BREAK mode, `InpSkipCashOpenBar=true`, model 1,
$10,000, 1% risk, commission 0; DJ30.i with `InpMinRangePoints=3000`,
`InpMaxRangePoints=20000` and `InpMaxSpreadPoints=500` (passed explicitly,
so `InpAutoHeightBySymbol` leaves them alone). Same years, 2025 ending
09.26. The tester's 1.17 build was copied into `C:\MT5-Backtest\MQL5\Experts`
before the runs. The reports show History Quality "n/a" this time (it was
100% in Job 1); the bar counts match. Reports, CSVs and journals:
`reports/nysplit-20261108-S0fixed-<XAUUSD|DJ30i>-<year>.*`.

**What changed from 1.16.** In 1.16 the candle closing at 14:30 UK was not
entered and did **not** count as the first break, so any later close beyond
the same edge could still be the first break and be entered. In 1.17 that
candle counts as the first break. Its entry is deferred to the 14:35 close
and taken only if the cash-open bar also closes beyond the same edge. When
the 14:35 candle holds, 1.16 and 1.17 take the same trade. They differ only
when it closes back inside: 1.17 finishes that side, while 1.16 waited for
another break.

Deferrals counted in the journals (signal on the 14:25-14:30 candle; entered
at 14:35, or failed back inside; the rest are days the 14:30 candle closed
beyond the opposite edge):

| | 2023 | 2024 | 2025 |
|---|---|---|---|
| XAUUSD deferred / entered / failed | 9 / 6 / 3 | 1 / 0 / 1 | 3 / 1 / 2 |
| DJ30.i deferred / entered / failed | 11 / 5 / 4 | 19 / 13 / 3 | 5 / 2 / 2 |

**XAUUSD**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| S0 | 2023 | 94 | 54.3 | 1.34 | +1030.42 | 4.35% | yes |
| S0-fixed (1.17) | 2023 | 93 | 53.8 | 1.32 | +935.90 | 5.41% | yes |
| S0 | 2024 | 110 | 52.7 | 1.05 | +197.52 | 9.11% | no |
| S0-fixed (1.17) | 2024 | 110 | 52.7 | 1.05 | +197.52 | 9.11% | no |
| S0 | 2025 | 107 | 59.8 | 1.24 | +897.30 | 8.33% | no |
| S0-fixed (1.17) | 2025 | 106 | 60.4 | 1.27 | +1009.95 | 8.74% | no |

**DJ30.i**

| Variant | Year | Trades | Win % | PF | Net $ | Max DD | Year passes |
|---|---|---|---|---|---|---|---|
| S0 | 2023 | 155 | 56.8 | 1.14 | +942.93 | 6.56% | no |
| S0-fixed (1.17) | 2023 | 152 | 57.2 | 1.15 | +998.37 | 6.23% | no |
| S0 | 2024 | 159 | 56.0 | 1.02 | +100.52 | 13.36% | no |
| S0-fixed (1.17) | 2024 | 157 | 56.1 | 1.04 | +231.75 | 12.30% | no |
| S0 | 2025 | 115 | 62.6 | 1.38 | +1710.57 | 6.88% | yes |
| S0-fixed (1.17) | 2025 | 113 | 61.9 | 1.36 | +1605.16 | 6.85% | yes |

**Verdict.** The change is small, as it should be: it touches only the days
a deferred break failed. That cost one to three trades a year (the later
same-side breaks that 1.16 took). On the Dow it helped 2023 and 2024
(+55 and +131) and cost 2025 (-105). On gold it cost 2023 (-94, drawdown
4.35% to 5.41%), left 2024 unchanged and helped 2025 (+113). No year changes
its pass or fail result, and neither symbol passes the bar.

**4 Nov 2026, the live miss, replayed.** The live charts run
`InpRetestOnly=true`, which these runs do not. Replaying 2026-11-02 to 11-06
on XAUUSD with the live inputs gives the same box as the live journal
(4030.42-4047.52). The first close beyond was the **14:35** candle at
4048.71, $1.19 above the high, which is outside the $1.00 retest tolerance.
That armed the setup without a retest close, and none came before 16:00. The
cash-open bar was not involved. 1.16 had no log line for this path; 1.17
prints `break LONG at 4048.71 not taken — retest-only pending`.
