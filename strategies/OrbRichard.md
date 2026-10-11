# OrbRichard: Richard's hand method, London and New York opening range retest

**Backtesting only. Not approved for a live chart.** The EA prints a warning if
it is attached outside the Strategy Tester.

Source: `src/Experts/OrbRichard.mq5`, built from `OrbLondon.mq5` (same safety
layer, UK time conversion, 1% sizing and CSV format). XAUUSD M5, model 1,
$10,000, 1% risk per trade.

## Rules (all times UK; "close" = M5 close)

1. **Boxes.** London 08:00-08:15, NY 13:30-13:45: high and low of the three M5
   candles. Box height must be 500-2500 points ($5-25 on 2-digit gold).
2. **Permission.** H1 EMA9 vs EMA21 on the last *closed* H1 bar at the box end
   (07:00 bar for London, 12:00 bar for NY). Long only if EMA9 > EMA21, short
   only if below. If they are within 0.05% of EMA21, the session is skipped.
   Closes beyond the non-permitted edge are ignored.
3. **Signal.** First M5 close beyond the permitted edge. Not an entry.
4. **Retest entry.** Within 6 candles after the signal candle, a candle whose
   low (long) reaches edge + 0.125 x box (0.5 x box / 4) or lower, and which
   closes back above the edge. Market entry on that close. The signal candle
   itself does not count as a touch.
5. **NY no-retest entry (NY only).** If the favourable extreme since the signal
   (signal candle included) reaches edge + 1 box by the 2nd candle after the
   signal, with no touch of the edge zone, enter on the first close beyond the
   signal candle's high (long) / low (short), within the same 6-candle window.
   Stop at the box midpoint.
6. **Lid.** If the highest high since the signal is >= edge + 1 box and the
   candle right after the one that made it closes below that high - 0.3 box,
   the side is finished. Checked before the retest on the same candle.
7. **Re-arm / second break.** A close back inside the box before an entry
   re-arms the side. **A signal whose 6-candle window ran out without an
   entry also re-arms on a later close back inside** (user correction,
   2026-10-11). The next close beyond the same edge is signal 2, and rules 4-6
   apply again. At most two signals and one entry per side per session. After
   the second signal ends without an entry, the side is finished.
8. **Stop.** Box midpoint. Moved to the entry once price is 0.5 box in favour
   of the entry.
9. **Targets.** TP1 at edge + 1 box: half closed. TP2 at edge + 2 box (server
   take profit), or the runner exits on the first M5 candle that closes against
   the trade (close < open for a long), counted from the candle that first
   reaches edge + 1.5 box. Rule-5 entries, and any retest whose entry is already
   past TP1, measure TP1, TP2 and the 1.5 trigger from the entry instead.
10. **Time.** No entry on a candle opening at or after 11:30 (London) / 16:00
    (NY). Flat 16:00 London, 18:00 NY.
11. **Skip dates.** `InpSkipDates`, comma list of `yyyy.mm.dd` UK dates; both
    sessions skip them.

## Variants

| Var | Inputs | Meaning |
|---|---|---|
| R1 | defaults | Rules as written |
| R2 | `InpStopAtFarSide=true` | Stop at the far side of the box (rule-5 entries too) |
| R3 | `InpUseLid=false` | Rule 6 off |
| R4 | `InpSecondBreak=false` | Rule 7 off: the first signal's end, whatever the cause, finishes the side |

## Interpretations agreed with the user (2026-10-11)

- Rule 5 targets and break-even are measured from the entry.
- A "close against the trade" means a candle of the opposite colour.
- Retest window expiry: re-arms on a later close inside (correction, above).
- The rule-5 entry must come within the 6-candle window.

Decided without asking, flagged in the report:
- The permission reads the last closed H1 bar, never the forming one.
- A touch and the rejection close may be the same candle (the touch candle
  either closes beyond the edge, which is an entry, or back inside, which is
  rule 7).
- Break-even is measured from the fill price.

## Logging

CSV with OrbLondon's 17 columns plus `signal_no,entry_time_uk`. One row per
**signal**, entered or not. `retest` is `Y` when the signal was entered, and
`mode` is `RETEST` or `RUN` for entries. Outcomes: `SL`, `BE`, `TP1_BE`,
`TP2`, `runner`, `timecut`, or `SKIPPED_REARM`, `SKIPPED_BACK_INSIDE`,
`SKIPPED_LID`, `SKIPPED_NO_RETEST`, `SKIPPED_TIME`, `SKIPPED_SPREAD`.
Trade statistics count `retest = Y` rows only. A win is profit > 0, so `BE` at
$0.00 is not a win.

## Results

### First grid, measured 2026-10-11

Version 1.00 on `C:\MT5-Backtest` (build 6230). XAUUSD M5, model 1, $10,000,
1%, commission 0. 2025 = 2025.01.01-09.26; 2024 and 2023 full years, with 2023
untouched out-of-sample. London and NY are single-session runs; Combined is the
two-session run. n / win% / PF / net / max DD. n and win% come from the CSV
(one row per position). Max DD is the report's maximal equity drawdown. Every
CSV reconciles to its report's net profit to the cent. Reports and CSVs:
`reports\orbrichard-20261011-<var>-<london|ny|both>-<year>.*`. The 20 largest
losses per run are in `strategies/OrbRichard-losses.md`.

| Var | Year | London | NY | Combined |
|---|---|---|---|---|
| R1 | 2025 | 32 / 28.1 / 0.47 / -848.45 / 10.69% | 56 / 50.0 / 1.11 / +242.38 / 6.85% | 88 / 42.0 / 0.83 / -637.91 / 13.12% |
| R1 | 2024 | 6 / 16.7 / 0.10 / -349.81 / 4.35% | 44 / 38.6 / 1.38 / +554.05 / 4.85% | 50 / 36.0 / 1.11 / +199.30 / 6.31% |
| R1 | 2023 | 5 / 40.0 / 2.10 / +105.75 / 1.81% | 24 / 29.2 / 0.67 / -305.34 / 6.10% | 29 / 31.0 / 0.80 / -202.74 / 6.10% |
| R2 | 2025 | 32 / 34.4 / 0.43 / -696.27 / 7.97% | 56 / 58.9 / 1.19 / +295.28 / 4.89% | 88 / 50.0 / 0.83 / -476.43 / 8.64% |
| R2 | 2024 | 6 / 33.3 / 0.67 / -61.12 / 1.95% | 44 / 43.2 / 1.47 / +428.03 / 3.26% | 50 / 42.0 / 1.33 / +363.01 / 3.11% |
| R2 | 2023 | 5 / 40.0 / 1.24 / +22.67 / 1.45% | 24 / 37.5 / 0.91 / -48.54 / 3.90% | 29 / 37.9 / 0.96 / -23.09 / 3.59% |
| R3 | 2025 | 33 / 27.3 / 0.47 / -848.45 / 10.69% | 61 / 50.8 / 1.11 / +260.46 / 7.07% | 94 / 42.6 / 0.84 / -619.48 / 12.94% |
| R3 | 2024 | 6 / 16.7 / 0.10 / -349.81 / 4.35% | 45 / 37.8 / 1.28 / +436.05 / 5.83% | 51 / 35.3 / 1.04 / +83.04 / 7.35% |
| R3 | 2023 | = R1 | = R1 | = R1 |
| R4 | 2025 | 26 / 23.1 / 0.42 / -821.24 / 10.01% | 43 / 58.1 / 1.54 / +799.60 / 4.96% | 69 / 44.9 / 0.98 / -71.36 / 9.56% |
| R4 | 2024 | 5 / 20.0 / 0.10 / -349.81 / 3.64% | 34 / 41.2 / 1.74 / +722.75 / 4.17% | 39 / 38.5 / 1.26 / +347.63 / 5.02% |
| R4 | 2023 | 5 / 40.0 / 2.10 / +105.75 / 1.81% | 19 / 26.3 / 0.49 / -366.93 / 5.25% | 24 / 29.2 / 0.68 / -264.00 / 5.12% |

R1 minus variant, combined net: R2 -161.48 / -163.71 / -179.65 (2025/2024/2023,
sum -504.84); R3 -18.43 / +116.26 / 0.00 (sum +97.83); R4 -566.55 / -148.33 /
+61.26 (sum -653.62). Negative means the R1 rule cost money.

R1's second-signal entries alone: 2025 19 trades, 6 wins, -529.46; 2024 11, 3,
-153.27; 2023 5, 2, +62.92.

London trades are few in 2023-2024 (5-6 a year) because the $5-25 box filter
is in points and gold's London box was mostly under $5 at those prices, as
noted for OrbLondon. Every loss in every run is at most one full stop (-1.00 R);
the remainder are time cuts.
