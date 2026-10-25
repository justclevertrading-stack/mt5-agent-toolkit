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
