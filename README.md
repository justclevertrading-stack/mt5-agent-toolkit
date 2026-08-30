# MT5 Agent Toolkit

Give an AI coding agent everything it needs to turn a written trading strategy
into a working MetaTrader 5 Expert Advisor, compile it, backtest it, and report
honest numbers.

You describe the strategy in plain language. The agent writes the MQL5,
compiles it, reads its own errors, fixes them, runs a backtest, and tells you
what happened. You read the numbers and decide.

You do not need to know MQL5. Works with Claude Code, Codex, or any agent that
can read files and run PowerShell.

---

## Why this exists

Two problems, and the second is the one that costs you.

**MQL5 is a niche language and models write MQL4 by mistake.** They reach for
`OrderSend` with eight parameters, `OrderSelect`, `OP_BUY`, bare `Ask` and
`Bid`, `#property strict`. None of it compiles. Without grounding, you spend
hours watching an agent rediscover the same errors.

**MetaTrader's command line lies to you.** Not "fails" — *lies*. Almost every
way to drive it headlessly has a failure mode that returns exit code zero and
produces output that looks fine.

| What happens | What you see |
|---|---|
| MetaEditor compiles cleanly | exit code **1** |
| MetaEditor finds 22 errors | exit code **0** |
| MetaTrader is already open when you start a test | exit 0, no report, **not one line in any log** |
| Another program holds TCP 3000 | agent connects and drops in 1 ms, test abandoned, exit 0 |
| Report path given as absolute | silently ignored, no report |
| `.ini` written by PowerShell's `Set-Content -Encoding utf8` | BOM breaks `[Common]`, "account is not specified" |
| **No `.set` file passed** | **tester ignores your compiled defaults and reuses the previous run's inputs** |

That last one deserves its own paragraph. MetaTrader saves the inputs from each
test into `MQL5\Profiles\Tester\<ExpertName>.set` and silently reuses them when
a run does not name a parameter file. Change a default in your source,
recompile, test again, and you get the **old** numbers, with a freshly built
`.ex5` sitting on disk and no warning anywhere.

Measured here: the same binary produced **8 trades with no set file and 26 with
one**. Without a fix for this, the whole edit, compile, test loop is fiction.
You could ship an EA to a live account having never once tested the code you
believe you tested.

Every trap above is worked around in `scripts/`, and every one was found by
experiment, not by reading documentation. The scripts are ordinary PowerShell.
The list is the actual product.

---

## Quick start

Requires Windows, MetaTrader 5, PowerShell 5.1 or later, and Git.

```powershell
git clone https://github.com/smizxe/mt5-agent-toolkit.git
cd mt5-agent-toolkit
.\scripts\setup.ps1          # finds MetaTrader, writes config\paths.json
```

Full walkthrough in [SETUP.md](SETUP.md). About 30 minutes on a new machine.

Then open your agent in this folder and describe what you want:

> An EA for EURUSD on H1. Buy when RSI crosses up through 30, sell when it
> crosses down through 70. Stop loss 300 points, take profit 600 points, risk
> 1% per trade, one position at a time.

The agent asks about anything you left out, writes the specification into
`strategies/`, copies a template, fills in the strategy section, compiles,
fixes its own errors, and backtests.

Two commands do the work, and the agent runs them itself:

```powershell
.\scripts\compile.ps1  -File "src\Experts\MyEA.mq5" -Json
.\scripts\backtest.ps1 -Expert "MyEA.ex5" -Symbol EURUSD -From 2024.01.01 -To 2024.12.31 -Json
```

Both return JSON. `compile.ps1` includes a `hints` field carrying the correct
signature of any built-in the agent called wrongly, which is usually enough to
fix the error in one pass instead of three.

---

## What is in here

```
.agents/skills/     the knowledge base the agent reads before writing code
scripts/            compile, backtest, build, setup
templates/          two EA starting points, both compile and trade as shipped
src/Experts/        worked examples
strategies/         one specification file per EA, written before the code
```

**Skills.** Four of them, loaded on demand rather than all at once:
verified MQL5 patterns, a growing table of real compile errors with causes and
fixes, a strategy intake checklist that forces vague descriptions to become
precise, and a guide to reading a backtest report without fooling yourself.

**Templates.** `EA_Template.mq5` for market entries with a fixed stop.
`EA_Template_Structural.mq5` for pending limit orders whose entry, stop and
target are computed from structure. Both ship with risk sizing from the real
stop distance, broker capability detection, filling mode negotiation, price
normalisation to tick size, and state rebuilt from the account so the EA
survives a terminal restart.

The structural template also caps position size against free margin. That is
not decoration. Lot size is risk divided by stop distance, so a stop that comes
out far smaller than intended does not produce a small loss, it produces an
enormous position. A real bug found here computed a stop of 0.4 pip and asked
for **6.24 lots on a ten thousand dollar account nominally risking 0.25%** —
and the percentage was obeyed exactly. Percent-of-balance sizing cannot catch
that on its own.

---

## The loop this is built around

```
describe strategy  ->  agent writes MQL5  ->  compile
                                                |
                        error? -> recorded in the compile-errors skill
                                                |
                       compiles -> backtest -> report -> demo -> your decision
```

A compile error met once is written down so the next session does not meet it
again. A snippet that compiles and behaves correctly becomes a pattern. The
repository is meant to get better with use, and pull requests adding a real
error or a verified pattern are the most useful contribution you can make.

---

## Limits, stated plainly

- **Windows only.** MetaEditor and the Strategy Tester agent have no macOS
  build. MetaTrader on a Mac runs under Wine, and the tester agent does not.
- The agent writes code. It does not design strategies and should not be asked
  to. If a description is ambiguous it is supposed to ask you, not guess.
- The MetaTrader economic calendar returns nothing inside the Strategy Tester,
  so a news filter cannot be backtested honestly. There is no fake one here.
- Every trap listed above was reproduced on MetaTrader 5 build **5836**.
  The compile path was re-verified on build **6140**. Other builds are
  untested, and a build that fixes one of these traps will not announce it.
- If something on your machine keeps MetaTrader running in the background,
  headless backtests cannot start at all. See note 0 in `scripts/backtest.ps1`.

---

## Disclaimer

This software builds programs that can place orders with real money.

Nothing here is financial advice or a claim that any strategy is profitable.
Backtest results describe the past and predict nothing. Every EA must be
backtested, run on a demo account, and approved by the account owner before it
goes anywhere near a funded account.

You are responsible for every order your software sends.

## License

[MIT](LICENSE).
