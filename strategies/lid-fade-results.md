# OrbLondon 1.14: lid fade, big-candle skip, break-even and EMA-exit variants

Measured 2026-10-18 on the backtest-only install `C:\MT5-Backtest` (build 6230).
XAUUSD M5, Vantage data, model 1, $10,000, 1% risk, commission 0, BREAK mode,
`InpFirstBreakOnly = true`, range 500-2500 points, EMA filter as live (M5 9/21
cross). Baseline A is the live configuration: London and NY boxes, NY last
entry 16:00 UK, NY flat 18:00 UK. 2023 and 2024 are full years; 2025 is
2025.01.01-09.26.

Source: `src/Experts/OrbLondon.mq5` 1.14, commit `b279f9c` on branch
`lid-fade`. Inputs per variant: `sets/OrbLondon-<variant>.set`. Reports and
CSVs (local only, `reports/` is gitignored):
`reports/lidfade-20261018-<variant>-<both|london|ny>-<year>.*`.

## Variants

| Var | Inputs on top of A |
|---|---|
| A | none (live settings) |
| S1a | `InpBigBreakSkipPct=100` |
| S1b | `InpBigBreakSkipPct=150` |
| F1a | `InpLidFade=true`, `InpLidFadeWindow=6` |
| F1b | `InpLidFade=true`, `InpLidFadeWindow=12` |
| F2 | F1a + `InpBigBreakSkipPct=100` |
| B1 | `InpBreakEvenPoints=600` |
| F3 | F2 + `InpBreakEvenPoints=600` |
| X1 | `InpExitOnEmaCross=true` |
| X2 | X1 + `InpBreakEvenPoints=600` |

## Results

Trades and win % come from the EA's CSV, one row per position; a win is profit
> 0. PF and net are from the CSV, and every CSV matches its report's net profit
to the cent (90 runs). Max DD is the report's maximal equity drawdown. The bold
rows are two-session runs. The London-only and NY-only lines are separate
single-session runs, so they do not add up exactly to the bold row. London-only
lines include the lid fades.

| Variant | Year | Trades | Win % | PF | Net $ | Max DD |
|---|---|---|---|---|---|---|
| **A** | 2023 | 105 | 52.4 | 1.21 | +754.09 | 5.54% |
|   London only | 2023 | 11 | 45.5 | 0.92 | -46.78 | 4.58% |
|   NY only | 2023 | 94 | 53.2 | 1.29 | +882.61 | 6.23% |
| **A** | 2024 | 127 | 52.0 | 1.00 | +5.82 | 10.85% |
|   London only | 2024 | 17 | 52.9 | 1.00 | +0.34 | 3.53% |
|   NY only | 2024 | 110 | 51.8 | 1.01 | +50.03 | 10.50% |
| **A** | 2025 | 179 | 57.0 | 1.11 | +766.78 | 10.40% |
|   London only | 2025 | 72 | 52.8 | 0.97 | -97.43 | 8.95% |
|   NY only | 2025 | 107 | 59.8 | 1.24 | +901.23 | 9.52% |
| **S1a** | 2023 | 105 | 53.3 | 1.28 | +956.27 | 5.56% |
|   London only | 2023 | 11 | 45.5 | 0.92 | -46.78 | 4.58% |
|   NY only | 2023 | 94 | 54.3 | 1.36 | +1058.53 | 6.24% |
| **S1a** | 2024 | 127 | 52.0 | 1.01 | +26.61 | 10.99% |
|   London only | 2024 | 17 | 52.9 | 0.99 | -7.76 | 3.61% |
|   NY only | 2024 | 110 | 51.8 | 1.02 | +74.83 | 10.42% |
| **S1a** | 2025 | 175 | 56.6 | 1.05 | +351.56 | 11.85% |
|   London only | 2025 | 70 | 54.3 | 1.00 | -2.28 | 8.76% |
|   NY only | 2025 | 105 | 58.1 | 1.10 | +365.79 | 10.26% |
| **S1b** | 2023 | 105 | 52.4 | 1.21 | +754.09 | 5.54% |
|   London only | 2023 | 11 | 45.5 | 0.92 | -46.78 | 4.58% |
|   NY only | 2023 | 94 | 53.2 | 1.29 | +882.61 | 6.23% |
| **S1b** | 2024 | 127 | 52.0 | 1.00 | +5.82 | 10.85% |
|   London only | 2024 | 17 | 52.9 | 1.00 | +0.34 | 3.53% |
|   NY only | 2024 | 110 | 51.8 | 1.01 | +50.03 | 10.50% |
| **S1b** | 2025 | 179 | 57.0 | 1.10 | +737.13 | 10.29% |
|   London only | 2025 | 72 | 52.8 | 0.97 | -95.29 | 8.93% |
|   NY only | 2025 | 107 | 59.8 | 1.24 | +887.39 | 9.43% |
| **F1a** | 2023 | 109 | 51.4 | 1.24 | +876.87 | 7.42% |
|   London only | 2023 | 15 | 40.0 | 1.03 | +18.65 | 6.80% |
|   NY only | 2023 | 94 | 53.2 | 1.29 | +882.61 | 6.23% |
| **F1a** | 2024 | 133 | 50.4 | 0.98 | -85.08 | 12.48% |
|   London only | 2024 | 23 | 43.5 | 0.87 | -110.84 | 5.18% |
|   NY only | 2024 | 110 | 51.8 | 1.01 | +50.03 | 10.50% |
| **F1a** | 2025 | 214 | 50.0 | 1.07 | +595.84 | 14.24% |
|   London only | 2025 | 107 | 40.2 | 0.94 | -268.70 | 14.98% |
|   NY only | 2025 | 107 | 59.8 | 1.24 | +901.23 | 9.52% |
| **F1b** | 2023 | 109 | 51.4 | 1.24 | +876.87 | 7.42% |
|   London only | 2023 | 15 | 40.0 | 1.03 | +18.65 | 6.80% |
|   NY only | 2023 | 94 | 53.2 | 1.29 | +882.61 | 6.23% |
| **F1b** | 2024 | 133 | 50.4 | 0.98 | -85.08 | 12.48% |
|   London only | 2024 | 23 | 43.5 | 0.87 | -110.84 | 5.18% |
|   NY only | 2024 | 110 | 51.8 | 1.01 | +50.03 | 10.50% |
| **F1b** | 2025 | 221 | 49.8 | 1.12 | +1055.53 | 10.53% |
|   London only | 2025 | 114 | 40.4 | 1.02 | +95.63 | 13.65% |
|   NY only | 2025 | 107 | 59.8 | 1.24 | +901.23 | 9.52% |
| **F2** | 2023 | 109 | 52.3 | 1.30 | +1054.66 | 7.42% |
|   London only | 2023 | 15 | 40.0 | 1.03 | +18.65 | 6.80% |
|   NY only | 2023 | 94 | 54.3 | 1.36 | +1058.53 | 6.24% |
| **F2** | 2024 | 133 | 50.4 | 0.99 | -48.60 | 12.41% |
|   London only | 2024 | 23 | 43.5 | 0.86 | -118.94 | 5.26% |
|   NY only | 2024 | 110 | 51.8 | 1.02 | +74.83 | 10.42% |
| **F2** | 2025 | 210 | 49.0 | 1.02 | +135.68 | 16.92% |
|   London only | 2025 | 105 | 40.0 | 0.95 | -242.89 | 15.83% |
|   NY only | 2025 | 105 | 58.1 | 1.10 | +365.79 | 10.26% |
| **B1** | 2023 | 105 | 56.2 | 1.19 | +620.05 | 5.57% |
|   London only | 2023 | 11 | 54.5 | 0.96 | -19.29 | 4.58% |
|   NY only | 2023 | 94 | 56.4 | 1.22 | +625.34 | 7.92% |
| **B1** | 2024 | 127 | 58.3 | 0.92 | -327.99 | 11.83% |
|   London only | 2024 | 17 | 58.8 | 1.15 | +102.37 | 3.60% |
|   NY only | 2024 | 110 | 58.2 | 0.88 | -400.45 | 11.24% |
| **B1** | 2025 | 179 | 60.9 | 0.95 | -325.47 | 15.51% |
|   London only | 2025 | 72 | 56.9 | 0.67 | -945.62 | 13.83% |
|   NY only | 2025 | 107 | 63.6 | 1.19 | +682.12 | 9.20% |
| **F3** | 2023 | 109 | 56.0 | 1.28 | +929.31 | 7.39% |
|   London only | 2023 | 15 | 46.7 | 1.21 | +113.11 | 5.95% |
|   NY only | 2023 | 94 | 57.4 | 1.29 | +804.41 | 7.91% |
| **F3** | 2024 | 133 | 56.4 | 0.90 | -413.44 | 12.17% |
|   London only | 2024 | 23 | 47.8 | 0.99 | -5.84 | 4.20% |
|   NY only | 2024 | 110 | 58.2 | 0.89 | -394.35 | 11.30% |
| **F3** | 2025 | 210 | 51.9 | 0.92 | -594.69 | 20.19% |
|   London only | 2025 | 105 | 41.9 | 0.80 | -831.93 | 16.99% |
|   NY only | 2025 | 105 | 61.9 | 1.06 | +221.43 | 9.88% |
| **X1** | 2023 | 105 | 52.4 | 1.20 | +718.47 | 5.48% |
|   London only | 2023 | 11 | 45.5 | 0.83 | -95.15 | 4.58% |
|   NY only | 2023 | 94 | 53.2 | 1.29 | +885.77 | 6.22% |
| **X1** | 2024 | 127 | 52.0 | 1.00 | +16.31 | 11.08% |
|   London only | 2024 | 17 | 52.9 | 1.04 | +32.23 | 3.65% |
|   NY only | 2024 | 110 | 51.8 | 1.00 | +9.45 | 11.06% |
| **X1** | 2025 | 179 | 57.0 | 1.10 | +735.09 | 10.55% |
|   London only | 2025 | 72 | 52.8 | 0.96 | -128.01 | 8.95% |
|   NY only | 2025 | 107 | 59.8 | 1.24 | +906.55 | 9.52% |
| **X2** | 2023 | 105 | 56.2 | 1.18 | +596.98 | 5.55% |
|   London only | 2023 | 11 | 54.5 | 0.85 | -73.61 | 4.58% |
|   NY only | 2023 | 94 | 56.4 | 1.22 | +647.89 | 7.90% |
| **X2** | 2024 | 127 | 58.3 | 0.92 | -318.65 | 12.21% |
|   London only | 2024 | 17 | 58.8 | 1.20 | +135.62 | 3.59% |
|   NY only | 2024 | 110 | 58.2 | 0.88 | -409.05 | 11.51% |
| **X2** | 2025 | 179 | 60.9 | 0.93 | -407.88 | 16.00% |
|   London only | 2025 | 72 | 56.9 | 0.64 | -1013.27 | 14.02% |
|   NY only | 2025 | 107 | 63.6 | 1.19 | +686.72 | 9.20% |

### Lid fades on their own

Fade entries (CSV session `FADE`) from the two-session runs.

| Variant | Year | Fades | Win % | PF | Net $ |
|---|---|---|---|---|---|
| F1a | 2023 | 4 | 50.0 | 1.01 | +2.27 |
| F1a | 2024 | 6 | 50.0 | 0.50 | -149.66 |
| F1a | 2025 | 35 | 40.0 | 0.94 | -135.10 |
| F1a | all | 45 | 42.2 | 0.89 | -282.49 |
| F1b | 2023 | 4 | 50.0 | 1.01 | +2.27 |
| F1b | 2024 | 6 | 50.0 | 0.50 | -149.66 |
| F1b | 2025 | 42 | 45.2 | 1.11 | +278.39 |
| F1b | all | 52 | 46.2 | 1.04 | +131.00 |
| F2 | 2023 | 4 | 50.0 | 1.01 | +2.27 |
| F2 | 2024 | 6 | 50.0 | 0.50 | -149.66 |
| F2 | 2025 | 35 | 40.0 | 0.94 | -123.61 |
| F2 | all | 45 | 42.2 | 0.90 | -271.00 |
| F3 | 2023 | 4 | 50.0 | 1.01 | +1.19 |
| F3 | 2024 | 6 | 66.7 | 0.71 | -58.20 |
| F3 | 2025 | 35 | 45.7 | 1.08 | +141.15 |
| F3 | all | 45 | 48.9 | 1.04 | +84.14 |

## Verdict

The bar was PF > 1.3 in all three years AND max DD < 10%. **No variant meets
it.** Every one fails in 2024, where two-session PF is 0.90 to 1.01 and every
drawdown is above 10% (10.85% to 12.48%). The nearest miss is F2 in 2023 at
exactly PF 1.30, which is not above 1.3.

- **Big-candle skip.** At 100% (S1a) it helps 2023 (+$202 against A) but costs
  $415 in 2025. At 150% (S1b) it never fires in 2023 or 2024 and changes 2025
  by only -$30.
- **Lid fade.** It adds London trades but no edge. F1b (12-candle window) has
  the best 2025 of any variant, +$1,055.53 at 10.53% DD, and is identical to
  F1a in 2023 and 2024. Fades alone: 45 to 52 trades over three years at PF
  0.89 to 1.04. Only 10 of them fall in 2023-24, because the points-based box
  filter shuts London out at those prices, so the fade cannot be judged on
  those years.
- **Break-even at 600 points (B1, F3, X2).** Win rate rises about 4-6 points,
  but PF falls in every year: winners are stopped at entry before TP1.
- **EMA-cross runner exit (X1).** Almost no effect, within ±$36 of A in every
  year.

Nothing here justifies changing the live settings.

## How the new rules were implemented

All four inputs are off by default. With them off, 1.14 reproduces the 1.13
live-settings runs to the cent (2025 two-session +766.78 at 10.40%, 2024
+5.82).

- **`InpBigBreakSkipPct`**: a break candle whose high-low range is above that
  percentage of the box height is not entered and does not count as the first
  break. The next close beyond the same edge is tested the same way. Logged
  "big-candle skip". Applies to both sessions.
- **`InpLidFade`**: London only, own magic number (`InpMagic +
  InpFadeMagicOffset`), one fade per session.
  - Arms from the London break that was traded, never from an EMA-rejected one.
  - Arm (a): the first-break position's first exit is its stop, at a loss. A
    break-even stop-out (F3) does not arm it.
  - Arm (b): within `InpLidFadeWindow` candles after the break candle, a
    candle closes back inside the box.
  - Entry: the first candle after the arming one whose wick reaches the broken
    edge and whose close is inside the box. Only that first candle counts; if
    it is skipped (spread, after 12:30 UK), there is no fade that session.
  - A first-break position still open at that point is closed first, logged
    `fadeexit`.
  - Stop: the highest high (short) or lowest low (long) since the break, plus
    one spread. TP1 at the opposite box edge, half off, stop to entry. TP2 one
    box beyond.
- **`InpBreakEvenPoints`**: once the position is that many points in profit,
  the stop moves to entry plus the current spread, independently of TP1. A
  stop is never moved backwards.
- **`InpExitOnEmaCross`**: after TP1, the remainder is closed on a fresh M5
  EMA9/21 cross against the trade (EMA9 on the right side on the previous bar,
  wrong side on this one). The stop at entry stays as the backstop.

Checked in the tester journal on 2025-02-13: long break at 10:40 UK, entry
10:45; the 11:00 candle closed back inside and armed the fade; the 11:10
candle wicked to the box high and closed inside, so the long was closed and
the fade sold with its stop above the high since the break plus the spread.

## Caveats

- One broker's data, one symbol, commission 0, model 1 (not real ticks).
- The three baseline A two-session runs report history quality "n/a". A
  re-run of A 2025 gave identical numbers at 100%, so it is a reporting quirk
  on the first run of a date range.
- None of this is a recommendation to trade.
