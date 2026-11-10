# Strategy: GoldTrendPullback

Formerly drafted as "Scalper". The user asked for a scalping bot, then chose
the H1 trend pullback approach for gold on 2026-11-10. The EA is
`src/Experts/GoldTrendPullback.mq5`.

## Account
- Type:                      Demo (confirmed by user)
- Size:                      £10,000 (GBP-denominated)

## Market
- Symbol:                    XAUUSD (confirmed by user, no suffix)
- Timeframe:                 H1
- Trading sessions, if restricted: none (not asked for)
- Days not to trade:         none (not asked for)

## Indicators
| Name | Parameters | Applied to | Purpose |
|---|---|---|---|
| EMA | 50 | Close | Trend, fast leg |
| EMA | 200 | Close | Trend, slow leg |
| EMA | 20 | Close | Pullback level |
| ATR | 14 | H1 | Stop distance |

## Entry, long
1. Use only the last closed H1 bar.
2. Uptrend: EMA(50) > EMA(200) on that bar.
3. Pullback: that bar's low touched or crossed the EMA(20) (low <= EMA20).
4. Rejection: that bar closed back above the EMA(20) (close > EMA20).

## Entry, short
1. Use only the last closed H1 bar.
2. Downtrend: EMA(50) < EMA(200) on that bar.
3. Pullback: that bar's high touched or crossed the EMA(20) (high >= EMA20).
4. Rejection: that bar closed back below the EMA(20) (close < EMA20).

## Exit
- Stop loss:                 1.5 x ATR(14) of the signal bar, from the entry price
- Take profit:               2 x the stop distance (2R)
- Early exit rule:           none, stop loss or take profit only
- Trailing stop:             no

## Position sizing
- Method:                    % risk of balance (template)
- Risk per trade:            1% (confirmed by user, about £100 on £10,000)
- Max simultaneous positions: 1 (template default)
- Max entries per day:       3 (default chosen by Claude, an input, confirm)
- Daily loss limit:          none (confirmed by user)

## Filters
- Max spread:                50 points (default chosen by Claude, an input).
                             On a 2-digit XAUUSD quote that is $0.50; on a
                             3-digit quote it is $0.05 and must be raised to
                             about 500. Check the "digits" line the EA logs
                             at start-up.
- Do not trade when:         no news filter (not asked for)

## Bar timing
- Act on the closed bar, or on every tick: closed bar

## Explicitly forbidden
- No martingale, no averaging down, no grid (one position at a time)

## Open questions
- The 3 entries/day cap and the 50-point spread cap were not asked about; they
  are inputs and can be changed without touching code.
