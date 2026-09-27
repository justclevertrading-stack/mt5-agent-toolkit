# Writing a CSV from an EA, and reading it back after a backtest

Verified 2026-09-23, build 6182, `EmaCross` on XAUUSD M5. Five runs, each one's
CSV net profit equal to the HTML report's net profit to the cent.

---

## Where a tester run's file actually goes

`FileOpen("name.csv", ...)` without `FILE_COMMON` writes into the **agent's own
sandbox**, `<data folder>\Tester\Agent-*\MQL5\Files\`, not into
`<data folder>\MQL5\Files\`. That directory is per agent, is reused by the next
run, and is not where anyone looks.

Add `FILE_COMMON` and the file lands in
`C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\Common\Files\`, which is a
single fixed path the harness can read straight after the run. This works from
inside the Strategy Tester; it is not blocked like `WebRequest`.

Make it an input rather than a constant, so live trading still writes where the
user expects and only the backtest is redirected:

```cpp
input bool   InpCsvCommonFolder = false;   // Write to Common\Files instead
input string InpCsvFile         = "emacross_log.csv";

int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
if(InpCsvCommonFolder)
   flags |= FILE_COMMON;
```

`backtest.ps1 -Inputs @{ InpCsvCommonFolder = $true; InpCsvFile = 'run_A.csv' }`
then gives one file per variant with no source change. Give each run its own
name, or delete the file first: rows from the previous run are otherwise still
there and every count comes out wrong.

## Append without losing the header

```cpp
// once, in OnInit. In the tester, open with FILE_WRITE alone so each run
// starts a clean file rather than appending to the last one.
int h = FileOpen(InpCsvFile, flags);
if(h != INVALID_HANDLE)
{
   if(FileSize(h) == 0)
      FileWrite(h, "date,time_uk,direction,outcome,r_result");
   FileClose(h);
}

// per row
int h = FileOpen(InpCsvFile, flags);
if(h == INVALID_HANDLE)
   return;
FileSeek(h, 0, SEEK_END);
FileWrite(h, StringFormat("%s,%s,%s,%s,%.3f", ...));
FileClose(h);
```

`FILE_TXT` with one preformatted string per `FileWrite` is deliberate. In
`FILE_CSV` mode `FileWrite` inserts the delimiter between arguments and applies
its own number formatting, which is harder to control than `StringFormat`.

Keep commas out of any free-text column, or the column count changes on those
rows. A skip reason reading `"lot rounds to zero, balance too low"` became two
fields; a semicolon fixed it.

## Rows that cannot be written when the signal fires

An outcome column is only known when the position closes, and a "what did price
do next" column only when those candles exist. Hold the rows in an array of
structs, write each one when it settles, and flush the rest in `OnDeinit`,
which the tester does call at the end of a run.

Two rules make this safe:

- **No trading decision may read the held rows.** They are diagnostics. A
  restart loses the unwritten ones, which must cost log lines and nothing else.
  Every trading rule still comes from bars or from the account.
- **Drop written rows from the array.** Over a year of M5 an EA that logs
  skipped signals as well as trades produces hundreds of rows, and a struct
  array that only grows is a leak.

## Why this beats parsing the report's deals table

Skill `mt5-backtest-report` explains that MT5 counts each closing deal as a
trade, so an EA that scales out inflates its own trade count and win rate, and
that the fix is to walk the deals table and group by position.

An EA that writes its own row per position never has the problem. It also
records things the deals table cannot: which filter rejected a signal that was
never traded, which session the entry fell in, and what the higher timeframe
looked like at the time. Measured on the same five runs, the per-position net
from the CSV matched the report's net exactly, which is what makes the CSV
trustworthy for the splits the report cannot produce.

## Classifying how a position ended

`DEAL_REASON` on the last `DEAL_ENTRY_OUT` deal says whether the broker closed
it, and the EA knows about its own closes:

```cpp
if(exitTagSetBeforeThisEaClosedIt != "")  outcome = exitTagSetBeforeThisEaClosedIt;
else if(lastReason == DEAL_REASON_TP)     outcome = "TP2";
else if(lastReason == DEAL_REASON_SL)     outcome = (outDeals > 1) ? "BE" : "SL";
```

`outDeals > 1` is what separates a stop at the entry price after a partial take
profit from a real stop loss, without a flag that a restart would lose. Set the
tag immediately **before** calling `PositionClose`, and clear it if the close
is rejected.

Realised R is the honest measure for a position that scales out:

```cpp
rResult = totalRealisedMoney / moneyRiskedAtEntry;   // 1.5R half + 3R half = 2.25
```

**Recorded:** 2026-09-23

## Splitting a result by session, which the report cannot do

Re-verified 2026-09-27 on `OrbLondon` with a London and a New York box, build
6230. Fourteen runs, every CSV's net equal to its report's net to the cent.

The HTML report gives one net profit for the run. With two sessions in one
binary the question is immediately "which of them earned it", and the report
cannot answer, because both sessions trade the same symbol. A `session` column
answers it from the same file that already proves it agrees with the report:

```
date,time_uk,session,mode,direction,box_low,box_high,box_height,entry,stop,
r_at_stop,retest,outcome,r_result,minutes_in_trade,profit_usd,reason
```

```powershell
$traded = Import-Csv $csv | Where-Object { $_.outcome -notlike 'SKIPPED*' }
$traded | Group-Object session | ForEach-Object {
    "{0}: {1} positions, net {2:N2}" -f $_.Name, $_.Count,
        ($_.Group | Measure-Object profit_usd -Sum).Sum
}
```

Two details that make the file trustworthy rather than merely present:

- **One set of held-row slots per session**, not one per EA. A single
  "record being filled in" index cannot hold two open trades at once, and the
  second session's row silently overwrites the first's. Keep the tracking state
  in an array indexed by session.
- **Adopt a position that has no row.** After a restart the position exists and
  its row does not. Rebuild the row from the position and from the box
  recomputed out of bars, rather than dropping the trade from the log.

The same file is what makes a "wait for the retest" variant measurable at all.
Log the row when the break is detected, not when the order fills, and a
`retest` column of `Y` or `N` then gives the fill rate and the win rate of the
filled subset against the plain-break run: 67% of breaks filled, and those won
10 percentage points less often than taking every break.

**Recorded:** 2026-09-27
