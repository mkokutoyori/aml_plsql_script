# Repository guidance

Audit scripts for the FLEXCUBE (FCUBS) Oracle database of a CEMAC bank.
Read-only PL/SQL, run by the internal audit department.

## THE RULE THAT OVERRIDES EVERYTHING ELSE

**`ACTB_HISTORY` is the only place where the life cycle of a contract really
lives. It is the table that tells the truth. Every other table is secondary.**

A contract exists, earns interest, is accrued, is collected, is redeemed and
is reversed **in `ACTB_HISTORY` and nowhere else**. The entries are the facts;
everything else is the front office's intention or a management view of it.

Consequences, to apply without exception when writing or reviewing a control:

- **Anchor every life-cycle test on `ACTB_HISTORY`.** Redemption is the
  `PRINCIPAL_LIQD` tag, not a row in `LDTB_CONTRACT_LIQ`. Interest collection
  is the `INT_%_LIQD` tag. Accrual is `EVENT = 'ACCR'`. A position is closed
  when the signed balance of its security account is nil, not when a status
  column says so.
- **Never conclude from a management table alone.** `LDTB_CONTRACT_LIQ`,
  `LDTB_CONTRACT_LIQ_SUMMARY`, `LDTB_CONTRACT_BALANCE`,
  `LDTB_CONTRACT_ICCF_DETAILS`, `LDTB_CONTRACT_ACCRUAL_HISTORY` and
  `CONTRACT_STATUS` are useful, but they are secondary. Where they disagree
  with the entries, **the entries win** and the disagreement is itself a
  finding worth reporting.
- `LDTB_CONTRACT_MASTER` is the terms of the deal (nominal, rate, dates,
  product, counterparty), not its life. Use it to say what the deal *should*
  have produced, then prove what it *did* produce from `ACTB_HISTORY`.
- Join key: `ACTB_HISTORY.TRN_REF_NO = LDTB_CONTRACT_MASTER.CONTRACT_REF_NO`.
  Account key: `ACTB_HISTORY.AC_NO = STTB_ACCOUNT.AC_GL_NO`.

## What the bank actually does with these securities

The bank buys a sovereign security **intending to hold it to maturity** and
cash the whole coupon. That intention is what `LDTB_CONTRACT_MASTER` records.
Under liquidity pressure the bank **sells the security before maturity**. That
is a normal act of treasury management, not an anomaly — and because
`ACTB_HISTORY` is a record of transactions, the sale appears there as a
liquidation, while the contract master keeps saying the deal runs to its
original maturity date.

Two rules follow, and they apply to every control:

- **"Still held" is `NOT EXISTS (PRINCIPAL_LIQD)`, never `MATURITY_DATE >
  SYSDATE`.** A security leaves the book on the day its `PRINCIPAL_LIQD` entry
  is passed. Building a population off the maturity date counts securities
  sold months ago as still on the balance sheet and invents gaps against every
  rebuilt position (this is what CUT-03, CUT-04, CUT-05 and STA-04 got wrong).
  Symmetrically, a control on what must be unwound (deferred income released,
  receivable cleared, interest collected) applies to everything that has *left
  the book*, redeemed or sold, not only to what has matured.
- **Print the holding period in every test.** From `VALUE_DATE` to the first
  `PRINCIPAL_LIQD` entry, or to the reporting date while the security is still
  held. `sec_row` computes it once and every exception table inherits it.
  Interest is earned only over that period: a security sold at half its life
  earned half its coupon, so any comparison against `MAIN_COMP_AMOUNT` must be
  prorated (LC-04) and any expected accrual series must stop at the sale date
  (INT-05, CUT-01, LC-06).

An early sale is therefore **descriptive information** (LIF-05: how long held,
what yield realised), not a finding. What *is* a finding is an accrual that
kept running after the sale, income booked for a period the bank did not hold
the security, or a balance left behind on the balance sheet.

## Contracts with no entry in ACTB_HISTORY

A contract of `LDTB_CONTRACT_MASTER` with **no row at all** in `ACTB_HISTORY`
has no life in the accounts: the balance sheet has never carried it. Because
every control is anchored on the entries, these contracts fall silently
outside all of them — a control cannot conclude on a deal that produced
nothing. They must therefore be counted, explained and **named** in their own
right (`audit_securities.sql` sections 1.13 to 1.17; EXT-03 carries the
verdict, EXT-04 is the mirror case of an entry with no contract).

Things worth establishing about that population, in order: whether entries
exist under **another module** (the accounting exists, the audit scope is too
narrow); the `CONTRACT_STATUS` / `USER_DEFINED_STATUS` and version count (a
cancelled or unauthorised deal legitimately produces nothing); whether the
maturity is still ahead (an invisible live position, the worst case); and what
`LDTB_CONTRACT_LIQ`, `LDTB_CONTRACT_BALANCE`,
`LDTB_CONTRACT_ACCRUAL_HISTORY`, `LDTB_CONTRACT_ICCF_DETAILS` and
`LDTB_CONTRACT_SCHEDULES` still carry for them — a management figure with no
accounting behind it is a disagreement, and the entries win.

`sec_row` prints `NO ENTRY` in the EXIT column for these contracts and leaves
the holding period blank. Never let it show `HELD`: that would credit the bank
with a position the general ledger has never carried.

## Rebuilding the coupon: never assume the day-count basis

A coupon follows from three figures and nothing else: `LCY_AMOUNT`,
`MAIN_COMP_RATE`, and the number of days held —
`coupon = nominal x rate / 100 x days / basis`.

`MAIN_COMP_AMOUNT` is the front office's statement of that figure, not proof
of it. A control that compares the accounting to `MAIN_COMP_AMOUNT` finds the
books in perfect agreement with a wrong figure whenever the deal itself was
captured wrong. The CPN family (part 6 BIS of `audit_securities.sql`) closes
that blind spot: it rebuilds the coupon from principal and rate and tests
`MAIN_COMP_AMOUNT` itself (CPN-01, which carries INT-02), the accrued coupon
carried for securities still held (CPN-02), the coupon recognised over the
holding period for securities out of the book (CPN-03), and the rate the
accounting implies (CPN-04).

**Never hard-code a single day-count basis.** A control fixed on /360 fires on
nearly every contract of a portfolio priced on another basis: it describes the
convention, not an anomaly, and drowns the real findings — the previous French
script proved this (687/687 lines reconciled once every convention was tested,
15.9% on /360 alone). Recompute each contract under ACT/360, ACT/365, ACT/366
and 30/360, retain the convention that reproduces the stated amount, and raise
an exception only when **none** does. The retained convention then serves every
downstream test, so the accrued coupon is measured on the deal's own basis
rather than one the auditor picked. 30/360 uses a different day count from the
actual-day conventions, so contracts fitted on it whose month count differs
from the actual count are set aside and reported separately rather than
compared on the wrong metric.

When a reperformance fails, print what *would* explain the booked figure — the
implied rate at the stated nominal, and the implied nominal at the stated rate.
One of the two is usually what was really meant, and it tells the auditor at
once whether the rate or the principal was captured wrong.

## CALYPSO: a system that sends entries and nothing else

Since 16/06/2025 the securities and treasury business runs in **CALYPSO**, the
front office system, not in the money market module (whose last entry is dated
16/06/2025 — the two dates are the migration). Calypso creates **no row in
`LDTB_CONTRACT_MASTER`**: no nominal, no rate, no value date, no maturity. It
posts accounting entries and nothing else, so none of the 56 matrix controls
can run on it — they all need a deal file that does not exist. Part 12 of
`audit_securities.sql` covers it with its own family, CAL-01 to CAL-13, cut off
at 31/08/2026.

Identify its entries by the triple, never by the module alone (`DE` is the
retail module and holds millions of rows):

    MODULE 'DE' · PRODUCT 'MNIP' · USER_ID = AUTH_ID = 'CALYPSOUSR'
    one single AMOUNT_TAG 'TXN_AMT' and TRN_CODE 'NIP' on every line

**The bridge accounts are the heart of the review.** Calypso never posts a deal
as one balanced entry facing the counterparty: it splits it into legs, each
using a *bridge* account as its counter-leg, cleared on the settlement event —
`467000186` securities, `467000188` money market and transfers, `467000243`
client mirror trades. A transit account must return to nil; what it still
carries is the accounting measure of what the interface has not closed. Age it
by Calypso deal key, never by `TRN_REF_NO` (one reference per *event*, so every
reference is unbalanced on the bridge by design). A residual that is an exact
multiple of a billion is one whole missing leg, not a drift, and is resolvable
in a single query.

**The portfolio has to be rebuilt from the entries**, because it exists nowhere
else. Securities are carried at **face value** (`512410100` bonds, `511210100`
bills — note bonds land on a *transaction* account and bills on a *placement*
account, which the chart of accounts and the Calypso books do not agree on);
the whole premium or discount is parked in a deferred-income account
(`472200108`, `472200106`) and released daily; the accrued coupon bought with
the paper sits on `512800100` as an asset. So **carrying value = face value −
unearned income**, and a report that does not net the two overstates the book.

Two traps:

- **The narrative is the only business information.** `EXTERNAL_REF_NO` is
  pipe-separated (deal id | entry id | event | product type | counterparty |
  book | instrument code | instrument label). Its format has already changed
  once without notice. Measure it — field-count distribution, raw samples,
  parsed samples — *before* any figure depends on it, and keep the token
  positions in parameters so a shift is a one-line fix.
- **Never read a gross total.** The daily engine posts the full cumulative
  accrual and reverses it the next business day, inflating gross flows by a
  factor of eighty or more. Only net movements mean anything.

## Reading ACTB_HISTORY correctly

- **Key on `AC_NO`, not on `AC_NATURAL_GL`.** The natural GL is often empty,
  especially on general-ledger accounts. Group on the four-digit accounting
  class, `SUBSTR(AC_NO, 1, 4)`, so a sub-account opened later inside an
  authorised class is caught without amending the script. Use
  `AC_NATURAL_GL` only as a second-rank fallback.
- **A reversal does not flip the direction: it repeats the same `DRCR_IND`
  with a NEGATIVE `LCY_AMOUNT`.** Every total must therefore be a SIGNED sum
  (`CASE drcr_ind WHEN 'D' THEN amount ELSE -amount END`). Summing gross
  debits against gross credits reads reversals backwards and inflates both
  columns.
- Never de-duplicate with `SELECT DISTINCT` on the whole row: legitimately
  identical lines exist and only the technical key separates them.
- `STTB_ACCOUNT` holds several rows per `AC_GL_NO`. Always join through a
  pre-aggregated view, otherwise every entry is multiplied.
- The table holds ~5.8 M rows: filter on `MODULE` first, always.

## Script conventions

- One anonymous PL/SQL block, one terminating `/`, read-only (no DDL, no
  COMMIT), run in a single pass under SQL Developer (F5).
- **No accented characters, no `&`, and never a `:` followed by a letter** —
  SQL Developer would read it as a bind variable and open an input window.
- Every section wrapped in its own `BEGIN ... EXCEPTION WHEN OTHERS` so a
  failing section does not kill the report.
- All thresholds grouped in a parameter block at the top of `DECLARE`.
- PL/SQL requires every variable to be declared **before** the first
  subprogram of the block.
- A locally declared function **cannot** be called from inside a SQL
  statement (PLS-00231). Use `TO_CHAR` and friends in SQL, the helpers only
  in PL/SQL expressions.
- Validate every table and column against `fcubs.csv` (the data dictionary)
  before using it.

## Reporting conventions

- **A control that raises an exception must name the securities concerned**:
  contract reference, product, issuer, nominal, rate, booking date, value
  date, maturity date. A finding nobody can trace to named contracts is not
  actionable.
- `audit_securities.sql` reports in **English** and prints, under each
  business label, the **database column name between parentheses**, so a
  reader can rebuild any figure with a query of their own.
- Do not keep a control that fires on the whole population: it describes the
  portfolio, not an anomaly, and it drowns the real findings. Either
  recalibrate it with a threshold, or move it to descriptive material and say
  so explicitly.

## Files

- `audit_securities.sql` — the current securities audit script (English).
- `audit_marche_monetaire.sql` — the previous money-market script (French),
  kept for reference; do not delete.
- `explore_mm_operations.sql`, `explore_fx_operations.sql` — exploration
  scripts. `money_marker_exploration_report.txt` is the MM exploration output.
- `fcubs.csv` — data dictionary: table, column, type, row count.
