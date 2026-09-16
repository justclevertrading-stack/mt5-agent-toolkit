---
name: mt5-backtest-report
description: Read and judge an MT5 Strategy Tester report. Use after running scripts/backtest.ps1 or build.ps1, when the user asks whether a backtest result is good, or when explaining metrics like profit factor, drawdown, recovery factor or win rate. Also covers the traps that make a backtest look better than reality. Do not use for writing MQL5 or for choosing a strategy.
---

# Reading a backtest report

Your job is to report what the numbers say, and to point out when they cannot
be trusted. Not to decide whether the strategy is worth trading. That is the
account owner's decision.

## Read in this order

Do not start with profit. Start with whether the test was valid at all.

### 1. History Quality

Anything below 100% invalidates everything else on the page. The tester filled
gaps in the price data with its own approximations, so the trades shown may
never have been possible.

Below 100%: say so first, before quoting any other number. Tell the user to
download more history for that symbol and run it again.

`backtest.ps1` already raises a warning for this.

### 2. Total Trades

- **Zero**: the EA never entered. Not a bad strategy, a broken one. Check the
  entry conditions, the spread filter, and that the symbol name is right.
- **Under about 30**: too few to mean anything. Any conclusion is noise.
  Extend the date range.
- **Thousands over a short period**: probably entering every tick rather than
  once per bar. Check the new-bar guard.

### 3. Profit Factor

Gross profit divided by gross loss.

| Value | Meaning |
|---|---|
| Below 1.0 | Loses money |
| 1.0 to 1.2 | Barely above break-even. Commission and slippage will erase it |
| 1.3 to 1.6 | Reasonable |
| Above 2.0 | Good, and worth checking for overfitting or a data problem |
| Above 5.0 | Almost always a mistake somewhere, not a discovery |

### 4. Maximum Equity Drawdown

The worst peak-to-trough fall in account value. Use the **equity** figure, not
the balance figure. Balance drawdown only counts closed trades and hides how
bad an open position got.

Ask the user directly: could you have kept the EA running through a fall this
large? Most people stop a system at half the drawdown their backtest shows.

### 5. Recovery Factor and Sharpe Ratio

Recovery Factor is net profit divided by maximum drawdown. It answers "was the
profit worth the pain". Below 1.0 means the worst drawdown was larger than
everything the strategy earned.

Sharpe Ratio below zero means the returns were worse than doing nothing.

## The win rate trap

Never lead with the win rate. It is the most misleading number on the page.

A real measured example from this project, the stock MetaQuotes MACD Sample on
EURUSDm H1 over three months:

```
Total Trades       12
Profit Trades      9 (75.00%)
Total Net Profit   12.18       on a 10,000 deposit
Profit Factor      1.08
Recovery Factor    0.06
Largest profit trade    49.00
Largest loss trade     -77.00
```

Seventy-five percent of trades won, and the account gained 0.12% in three
months. The losers were bigger than the winners.

Win rate without average win versus average loss says nothing.

## An EA that scales out breaks Total Trades and win rate

Measured 2026-09-15, `OrbLondon` on XAUUSD M5, build 6182.

MT5 counts a **closing deal** as a trade. An EA that closes half at a first
target and the rest later produces two closing deals from one position, and
the report counts both.

| | Report says | Per position |
|---|---|---|
| Trades | 103 | 68 |
| Win rate | 67.96% | 51.47% |
| Average profit trade | 38.66 | 77.32 |
| Profit factor | 0.87 | 0.87 |
| Max equity drawdown | 10.63% | 10.63% |

Every partial take-profit is booked as a win, and the remainder that comes back
to break even is booked as a second, near-zero trade. The win rate is inflated
by sixteen points and the average win halved. Profit factor, net profit and
drawdown are sums over the same deals either way, so they are unaffected.

Spot it from `Total Deals` against `Total Trades`. With no scaling out,
deals = 2 x trades. Here it was 171 deals to 103 trades, which means 68 entries
and 103 exits, so 35 positions closed in two pieces.

Recompute per position before quoting a win rate. Walk the deals table in time
order: a deal with direction `in` opens a position, every `out` until the next
`in` belongs to it, and the position wins if the sum of those profits is
positive. Say which basis the number is on.

The deals table is in the report HTML (UTF-16 LE), after a cell reading
`Deals` and a 13-column header `Time, Deal, Symbol, Type, Direction, Volume,
Price, Order, Commission, Swap, Profit, Balance, Comment`. The first row is
the `balance` deposit, and the `Comment` cell is absent on a scale-out deal
that was not the stop or the target. Verified 2026-09-16: a parser written
this way reproduced the recorded baseline exactly, 68 positions, 51.47%,
PF 0.87, -417.72.

## Splitting one run into sub-periods

Split the **same run's** deals table by position open date. Do not run the
sub-periods as separate backtests: with percent-of-balance sizing the second
half starts from a different balance and its lots, and therefore its dollar
figures, are no longer comparable with the full run.

From the deals table a sub-period gives trades, win rate, profit factor and
net profit exactly. The drawdown it gives is the **balance** drawdown over
closed positions, as a percent of the running peak starting from the balance
at the window's start. The report's equity drawdown is intrabar and only
exists for the whole run, so a table that mixes the two must say which is
which.

## History Quality "n/a" means re-run it, not "bad data"

Measured 2026-09-15, build 6182. The same EA, inputs, symbol and window run
twice on `Model=1`:

| | First run | Second run |
|---|---|---|
| History Quality | **n/a** | **100%** |
| Bars | 49456 | 49456 |
| Ticks | 987 551 | 987 551 |
| Total net profit | -417.72 | -417.72 |

Identical data, identical trades, different quality label. The first run was
the one that pulled the history down from the broker, and the tester reports
`n/a` rather than a percentage when it has been filling the cache as it goes.

So `n/a` is not evidence of a data problem, and it is not evidence of good data
either. It carries no information at all. Run the same test again: the second
run reports a real percentage, and *that* is the number to judge.

Do not report `n/a` to the user as "history quality below 100%", which is what
`backtest.ps1` currently warns. Re-run first, then quote the percentage.

## Four reasons a backtest lies

State whichever of these apply. Do not let a good-looking result pass without
checking them.

**1. Commission and swap were not set.**
Every deal in the report showing `0.00` commission does **not** mean the
account is commission-free. MT5 charges commission from the broker's group
settings on the server, which a terminal never receives and a tester run
therefore cannot apply. Confirmed against a Vantage live account, 2026-09-15:
zero commission on all 171 deals.

So the report cannot answer the question. The account owner has to. Ask which
account type it is, because the answer changes the arithmetic completely:
a commission-free Standard account pays entirely through the spread, which the
tester *does* model, while a raw-spread account pays a per-lot fee the tester
has silently omitted.

Take it as an input so the number is recorded in the report header, apply it to
the `OnTester` result, and never let it change a trade:

```cpp
input double InpCommissionPerLot = 0.0;   // Round trip, $ per lot

double OnTester()
{
   // Sum DEAL_ENTRY_IN volumes: one round trip is charged per lot entered,
   // so partial exits do not add to it.
   double commission = enteredVolume * InpCommissionPerLot;
   return(TesterStatistics(STAT_PROFIT) - commission);
}
```

Keeping it out of lot sizing and out of the break-even level is deliberate. The
moment commission moves a stop, two runs at different commission settings stop
being comparable, and the variant table stops meaning anything.

Because the charge is linear in volume, one run answers every rate: report the
lots traded alongside the result and any commission can be applied afterwards
without testing again.

**2. The modelling mode was too coarse.**
`Model=1` (one minute OHLC) is fast and fine for strategies acting on closed
bars. It is meaningless for anything that reacts intrabar, uses tight stops, or
scalps. Those need `Model=4`, real ticks, and real tick history downloaded.

**3. Spread was not realistic.**
The tester can use the current spread rather than the historical one. Spread
widens sharply at session opens and around news, which is exactly when many
strategies trade.

**4. The parameters were fitted to this exact period.**
If the numbers were tuned until the chart looked good, the result describes the
past and predicts nothing. Test an untouched date range before believing it.

## Before trusting any comparison between two runs

MetaTrader saves the inputs used by the last test into
`MQL5\Profiles\Tester\<ExpertName>.set` and silently reuses that file whenever
the run does not name one. A changed default in the source, recompiled, then
tested, reproduces the **old** numbers with a freshly built `.ex5` on disk and
no warning anywhere.

Measured: the same binary gave 8 trades with no set file and 26 with a set file
that named one unrelated input.

`backtest.ps1` writes a set file on every run, which is what makes a result a
function of the source. If a backtest is ever run by another route, check that
the inputs shown at the top of the report are the ones intended. Two runs whose
input lists differ are not a comparison.

## When there is no report at all

A missing report is not a strategy problem and must not be diagnosed as one.
Work down this list before touching any EA code.

| Symptom | Cause | Fix |
|---|---|---|
| Script exits in about a second, tester log gains **no new lines** | MetaTrader is already open. Windows hands `/config:` to the running instance, which ignores it, and the launcher returns 0 | Close MetaTrader. `backtest.ps1` now refuses to start in this case rather than letting it look like a data fault |
| Tester log says `symbol ... not exist` | Wrong suffix | Exness is `EURUSDm`, not `EURUSD`. Read Market Watch |
| `tester not started because the account is not specified` | No saved login, or a BOM in the `.ini` | Log in once by hand, and never write the `.ini` with `Set-Content -Encoding utf8` |
| Agent connects then disconnects within a millisecond | Another program holds port 3000 | `backtest.ps1` scans for a free port already |
| Report path was absolute | Silently ignored | The report name must be relative to the data folder |
| A backtest that *just* succeeded is followed by one that refuses to start | The previous run's terminal is still shutting down | Wait, then run again. See below |

The first row is by far the most common in daily use, because a trader keeps
MetaTrader open all day. It also produces the least evidence: exit code zero,
empty logs, no report. Check it first.

## The terminal outlives the script that started it

`backtest.ps1` returns as soon as the process it launched exits, and that is
**not** the same moment the terminal is gone. `ShutdownTerminal=1` fires once
testing completes, but before the process actually ends the terminal finishes
loading the normal profile: it reconnects to the broker, opens the saved charts,
initialises whatever EAs are attached to them, and only then shuts down.

Measured 2026-08-08, build 5836. A run that produced its report at 15:42:10 left
a terminal alive until `exit with code 0` at 15:43:25, about 75 seconds after the
script had already returned a fully parsed result. A second backtest started in
that window hit the "MetaTrader 5 is already running" guard and failed.

This matters because the failure lands on the *next* run, not the one that caused
it, so it reads as an unrelated problem. Two things follow:

- Back-to-back backtests are not reliably back-to-back. Check for a running
  `terminal64` and wait for it to disappear before starting the next one.
- The lingering process is genuinely a leftover of the automation, not the user's
  own MetaTrader. Confirm with its start time and the terminal log before killing
  anything: closing a terminal a human is using is far worse than waiting.

## What to say back to the user

Give them, in this order: whether the test was valid, how many trades, profit
factor, worst equity drawdown, and any of the four traps above that apply.

Then stop. Do not recommend trading it, do not suggest parameter changes to
improve the numbers, and do not compare it to a target return. Implementing and
measuring the strategy is the job; judging it is not.
