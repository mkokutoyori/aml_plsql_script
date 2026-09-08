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
