# Strategy: OrbLondon

London opening-range breakout on gold, with an EMA trend filter, a two-stage
target and a hard session close.

## Market
- Symbol:                    XAUUSD (Vantage Markets, no suffix)
- Timeframe:                 M5
- Trading sessions:          Range 08:00-08:15 UK. Entries 08:15 to 12:30 UK.
                             Everything flat at 20:00 UK.
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
| EMA fast | 9, M5 | Close | Trend filter, read on the breakout candle |
| EMA slow | 21, M5 | Close | Trend filter, read on the breakout candle |

## The range
- The three M5 candles opening 08:00, 08:05 and 08:10 UK.
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
| `InpMoveToBreakEven` | true | false: TP1 still closes half, stop stays at the range edge |
| `InpStopAtMidpoint` | false | true: stop at the range midpoint. Targets stay at 1 and 2 range heights, so the lot doubles at the same 1% risk |
| `InpRangeFilterPct` | false | true: filter the range by `InpMinRangePct` to `InpMaxRangePct` of the range midpoint instead of by dollars |
| `InpCommissionPerLot` | 0.0 | Accounting only, never moves a trade. 0.00 is correct for a Vantage Standard STP account, where the cost is in the spread |

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
