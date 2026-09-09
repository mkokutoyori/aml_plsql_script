-- ============================================================================
-- CALYPSO INTERFACE AUDIT SCRIPT - ACCOUNTING ENTRIES ONLY
-- ============================================================================
--
-- WHY THIS IS A SEPARATE SCRIPT
--   audit_securities.sql audits the money market module, where a security is
--   a CONTRACT: LDTB_CONTRACT_MASTER states the nominal, the rate, the value
--   date and the maturity, and every control confronts the entries with those
--   terms.
--
--   Calypso is a different world. It creates NO contract in FLEXCUBE. It
--   posts accounting entries and nothing else. There is no nominal to
--   recompute, no rate to reperform, no maturity to test a redemption
--   against. Not one of the 56 controls of the money market framework can be
--   run here, because they all need a deal file that does not exist.
--
--   The paradigm is therefore not the same, and mixing the two in one report
--   would make both harder to read. This script stands alone: its own
--   parameters, its own controls, its own summary. Run it on its own.
--
-- PURPOSE
--   Audit of what the CALYPSO front office system has posted into the general
--   ledger since its go live. Everything below is deduced from the accounting
--   entries and from nothing else, which is the rule of the house applied to
--   a system that sends only entries: ACTB_HISTORY tells the truth, and here
--   it is the only one talking.
--
--   Two sections carry the review:
--     PART 2  THE TRANSIT ACCOUNTS. A bridge is plumbing, not a position.
--             What it still carries is the accounting measure of what has
--             not been closed. It is the one figure in this report that
--             cannot be explained away.
--             It is read on the WHOLE ACCOUNT, not on the Calypso slice of
--             it: an account has to come back to nil whoever posted on it,
--             and a manual correction on the plumbing between two systems is
--             exactly what an audit looks for. The balance is then split
--             into what the interface posted, what anything else posted, and
--             what predated the go live. The three add up.
--     PART 3  THE PORTFOLIO. It exists nowhere else, so this is not a control
--             against a deal file: it IS the portfolio, security by security,
--             at face value, at carrying value, with its accrued interest.
--
-- COLUMN NAMING CONVENTION
--   Every table prints its heading on two lines: the business label first,
--   then the DATABASE COLUMN NAME between parentheses. A reader can
--   therefore rebuild any figure of this report with a query of their own.
--
-- HOW TO RUN
--   Single anonymous PL/SQL block, read only, no DDL, no COMMIT. One pass,
--   one terminating slash.
--   SQL Developer : open, F5. SQL*Plus : @audit_calypso.sql
--   No substitution variable and no bind variable, so no input window
--   opens at launch.
--
--   THE PERIOD RUNS UP TO THE CUT OFF, NOT FROM IT. Every population is
--   trn_dt >= the go live AND trn_dt < the day after the cut off, so a
--   balance printed here is the balance AT that date. A query written
--   trn_dt >= the cut off measures the movement AFTER it instead, and will
--   never reproduce this report. Section 2.1 a prints the exact query that
--   reproduces its own headline figures.
--
--   ONE GRANT IS REQUIRED BEYOND READ ACCESS: EXECUTE on the function
--   webserve.FN_GET_DESC. FLEXCUBE stores no narrative on an accounting
--   entry; the description everyone reads is computed by that function from
--   the columns of the entry, and it is the only place the Calypso business
--   information survives. Without the grant the block does not compile.
--
--   That call is a PL/SQL function invoked once per row, so it is the cost
--   of this report. Five aggregations need it over the whole population
--   (1.1, the two tables of 1.3, 1.3 a and 1.3 b); everywhere else it is
--   restricted to a handful of accounts, and the sections that need no
--   business meaning at all never call it.
--
-- REPORT LAYOUT
--   PART 0  - scope, parameters, the bridge mechanism, chart of accounts
--   PART 1  - the interface, its footprint and its narrative
--             1.1 footprint   1.2 calendar   1.3 THE NARRATIVE   1.4 accounts
--   PART 2  - THE TRANSIT ACCOUNTS AND THEIR RESIDUAL BALANCE  CAL-01, 02,
--                                                              03 and 14
--             2.1 a how much and who put it there   b in proportion
--                 c who else posts   d growing   e age   f named
--                 g the other pairs
--   PART 3  - THE PORTFOLIO DEDUCED FROM THE ENTRIES           CAL-04 to 06
--             3.1 a position   b month by month   c SECURITY BY SECURITY
--                 d accrued interest   e off balance sheet   f income
--   PART 4  - engine, revaluation, calendar, blind spots       CAL-07 to 13
--             (CAL-14 sits with the transit accounts, in part 2)
--   PART 5  - summary of all tests
--
-- THE ONE THING TO KNOW BEFORE READING
--   Calypso never posts a deal as one balanced entry facing the counterparty.
--   It splits it into legs, and each leg uses a BRIDGE account as its counter
--   leg, cleared on the settlement event. FLEXCUBE receives legs, not deals.
--   One FLEXCUBE reference is created PER EVENT, so a deal can only be put
--   back together through the deal key carried in the narrative. Every
--   section below groups on that key and never on TRN_REF_NO.
--
-- ERROR HANDLING
--   Each section carries its own handler: a section that fails prints its
--   error and the report carries on with the next one.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 500
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET DEFINE OFF
SET TRIMSPOOL ON
-- SPOOL calypso_audit_report.txt

DECLARE

    -- ========================================================================
    -- IDENTIFICATION OF THE INTERFACE
    -- Calypso does not create contracts in FLEXCUBE: it posts accounting
    -- entries and nothing else. They are identified by the triple below.
    -- MODULE alone is not enough: DE is the retail module and holds
    -- millions of rows.
    -- ========================================================================
    k_cy_user     VARCHAR2(20) := 'CALYPSOUSR';  -- USER_ID and AUTH_ID of the interface
    k_cy_upat     VARCHAR2(30) := '%calypso%';   -- pattern tested on LOWER(USER_ID), so a
                                          -- second interface account is not missed
    k_cy_mod      VARCHAR2(4)  := 'DE';          -- MODULE the entries are posted under
    k_cy_prod     VARCHAR2(10) := 'MNIP';        -- the single PRODUCT of the interface
    k_cy_tag      VARCHAR2(20) := 'TXN_AMT';     -- the single AMOUNT_TAG
    k_cy_code     VARCHAR2(10) := 'NIP';         -- the single TRN_CODE
    k_cy_from     DATE := TO_DATE('16/06/2025', 'DD/MM/YYYY');  -- go live
    k_cy_to       DATE := TO_DATE('31/08/2026', 'DD/MM/YYYY');  -- cut off of this review

    -- ========================================================================
    -- THE NARRATIVE
    -- The business meaning of an entry is NOT stored in a column. It is
    -- produced by the FLEXCUBE function
    --     webserve.FN_GET_DESC(module, trn_ref_no, ac_entry_sr_no,
    --                          event_sr_no, trn_code, related_account, ac_no,
    --                          ac_branch, ac_ccy, amount_tag, event,
    --                          instrument_code, related_customer,
    --                          value_dt, trn_dt, related_reference)
    -- called on the columns of ACTB_HISTORY. This script therefore needs
    -- EXECUTE on that function; without the grant the block does not compile.
    -- The call is a PL/SQL function invoked per row, so it is expensive: the
    -- five sections that need it over the whole population are marked, and
    -- every other section reads the entries without it.
    --
    -- Position of the fields inside that description, which is pipe
    -- separated. Tokens are read positionally, empty ones included.
    -- If section 1.3 shows the fields shifted by one, because the string
    -- starts with a pipe, set the offset below to 1 and rerun. Nothing else
    -- has to change.
    k_cy_p0       NUMBER := 0;            -- offset applied to every token position
    k_cy_t_id     NUMBER := 1;            -- Calypso internal deal id
    k_cy_t_evt    NUMBER := 3;            -- event name
    k_cy_t_typ    NUMBER := 4;            -- product type
    k_cy_t_ctp    NUMBER := 5;            -- counterparty
    k_cy_t_book   NUMBER := 6;            -- Calypso book, the business line
    k_cy_t_ins    NUMBER := 7;            -- instrument code
    k_cy_t_lbl    NUMBER := 8;            -- instrument label

    -- The bridge accounts. A bridge is a transit account: Calypso posts one
    -- leg of a deal against it and clears it on the settlement event. It must
    -- return to nil. Its residual balance is the accounting measure of what
    -- the interface has not closed, and is the subject of part 2.
    k_cy_brg_sec  VARCHAR2(20) := '467000186';  -- bridge, securities
    k_cy_brg_mm   VARCHAR2(20) := '467000188';  -- bridge, money market and transfers
    k_cy_brg_mir  VARCHAR2(20) := '467000243';  -- bridge, client mirror trades

    -- The balance sheet accounts Calypso moves, used to rebuild the portfolio
    k_cy_bond     VARCHAR2(20) := '512410100';  -- bonds at face value, trading book
    k_cy_bill     VARCHAR2(20) := '511210100';  -- treasury bills at face value, placement
    k_cy_accr     VARCHAR2(20) := '512800100';  -- accrued interest receivable
    k_cy_def_b    VARCHAR2(20) := '472200108';  -- deferred income, bonds
    k_cy_def_t    VARCHAR2(20) := '472200106';  -- deferred income, treasury bills
    k_cy_prov     VARCHAR2(20) := '591400100';  -- impairment provision, mark to market
    k_cy_borrow   VARCHAR2(20) := '552400100';  -- overnight borrowing, repo liability
    k_cy_debt     VARCHAR2(20) := '559000101';  -- accrued interest payable on the repo
    k_cy_fx_pos   VARCHAR2(20) := '475000160';  -- Calypso FX position account
    k_cy_fx_cv    VARCHAR2(20) := '476000160';  -- its counter value account

    -- Off balance sheet accounts
    k_cy_col_gl   VARCHAR2(20) := '995000100';  -- collateral given, general ledger side
    k_cy_col_ti   VARCHAR2(20) := '952100100';  -- securities pledged as collateral
    k_cy_ob_fxb   VARCHAR2(20) := '971200100';  -- spot bought not yet received
    k_cy_ob_fxs   VARCHAR2(20) := '971400100';  -- spot sold not yet delivered
    k_cy_ob_fwd   VARCHAR2(20) := '972400100';  -- forward sold not yet delivered
    k_cy_ob_adj   VARCHAR2(20) := '979000100';  -- FX off balance sheet adjustment
    k_cy_cus_t    VARCHAR2(20) := '998000100';  -- securities held for third parties
    k_cy_cus_c    VARCHAR2(20) := '938000100';  -- securities held for clients

    -- Income and expense accounts of the interface
    k_cy_inc_b    VARCHAR2(20) := '733400100';  -- bond income, accrued
    k_cy_inc_br   VARCHAR2(20) := '734400100';  -- bond income, realised
    k_cy_inc_t    VARCHAR2(20) := '733200100';  -- bill income, accrued
    k_cy_inc_tr   VARCHAR2(20) := '734200100';  -- bill income, realised
    k_cy_exp_mm   VARCHAR2(20) := '601100100';  -- interest expense, money market
    k_cy_com_pf   VARCHAR2(20) := '725000100';  -- portfolio management commission
    k_cy_com_fx   VARCHAR2(20) := '625000105';  -- commission paid on FX purchases

    -- Calypso thresholds
    k_cy_age      NUMBER := 30;           -- tolerated age of a bridge item, in days
    k_cy_age_c    NUMBER := 12;           -- tolerated age of accrued interest, in months
    k_cy_val_m    NUMBER := 3;            -- tolerated months with no revaluation
    k_cy_infl     NUMBER := 5;            -- tolerated gross over net ratio on an account
    k_cy_round    NUMBER := 1000000000;   -- a residual that is an exact multiple of this
                                          -- is one unmatched leg, not an accumulation
    k_cy_excl     VARCHAR2(8) := '4526';  -- account family excluded from the first extract
    k_cy_back_d   NUMBER := 5;            -- tolerated back valuation, in days

    -- Number of detail lines printed per test
    k_top         NUMBER := 30;
    k_top_all     NUMBER := 200;        -- cap on the exhaustive lists
    k_tol_abs     NUMBER := 1;           -- absolute tolerance, in XAF

    -- ========================================================================
    -- Test registry, fed by p_verdict and printed in part 5
    -- ========================================================================
    TYPE t_res IS RECORD (
        code VARCHAR2(16),
        lib  VARCHAR2(100),
        nb   NUMBER,
        base NUMBER,
        mt   NUMBER,
        crit VARCHAR2(12)
    );
    TYPE t_tab IS TABLE OF t_res INDEX BY PLS_INTEGER;
    g_res     t_tab;
    g_n       PLS_INTEGER := 0;
    g_find    PLS_INTEGER := 0;
    g_sev     PLS_INTEGER := 0;

    -- ========================================================================
    -- Working variables
    -- ========================================================================
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_sub     VARCHAR2(200) := RPAD('-', 116, '-');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_tot2    NUMBER;
    v_mt      NUMBER;
    v_mt2     NUMBER;
    v_row     NUMBER;
    v_d_max   DATE;           -- date buffer, used by the cross checks
    v_lib     VARCHAR2(200);  -- account description buffer
    v_cy_nb   NUMBER := 0;    -- entry lines in scope, reference denominator
    v_cy_mt   NUMBER := 0;    -- gross flow in scope
    v_cy_dl   NUMBER := 0;    -- distinct deal keys in scope
    v_cy_dn   NUMBER := 0;    -- lines with an empty description
    v_cy_dp   NUMBER := 0;    -- lines whose description is pipe separated
    v_cy_dd   NUMBER := 0;    -- distinct descriptions
    v_cy_d1   DATE;           -- first entry
    v_cy_d2   DATE;           -- last entry
    v_d_last2 DATE;           -- second date buffer for the cross checks

    -- ========================================================================
    -- Display helpers
    -- ========================================================================
    PROCEDURE po(t VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(t);
    END;

    PROCEDURE print_part(t VARCHAR2) IS
    BEGIN
        po('');
        po(v_sep);
        po('   ' || t);
        po(v_sep);
    END;

    PROCEDURE print_section(t VARCHAR2) IS
    BEGIN
        po('');
        po(v_sep);
        po('>>> ' || t);
        po(v_sep);
    END;

    PROCEDURE print_sub(t VARCHAR2) IS
    BEGIN
        po('');
        po('  [' || t || ']');
    END;

    PROCEDURE print_kv(l VARCHAR2, v VARCHAR2) IS
    BEGIN
        po('  ' || RPAD(SUBSTR(l, 1, 66), 68, '.') || ' ' || NVL(v, 'NOT POPULATED'));
    END;

    -- Left aligned and right aligned cells
    FUNCTION fpad(x VARCHAR2, n NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN RPAD(' ' || NVL(SUBSTR(x, 1, n - 2), '-'), n);
    END;

    FUNCTION fpadl(x VARCHAR2, n NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN LPAD(NVL(SUBSTR(x, 1, n - 1), '-') || ' ', n);
    END;

    FUNCTION fnum(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G999G990D00');
    END;

    -- Amount expressed in millions of XAF
    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G999G990D00') || ' M';
    END;

    FUNCTION ftx(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF x IS NULL THEN RETURN '-'; END IF;
        RETURN TO_CHAR(x, 'FM990D0000') || ' %';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
    END;

    -- Timestamp WITHOUT a colon: under SQL Developer a colon followed by a
    -- letter would be read as a bind variable and open an input window.
    FUNCTION fdth(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY HH24"h"MI');
    END;

    FUNCTION fpct(p_part NUMBER, p_tot NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF NVL(p_tot, 0) = 0 THEN
            RETURN '-';
        END IF;
        RETURN TO_CHAR(ROUND(100 * p_part / p_tot, 1), 'FM990D0') || ' %';
    END;

    -- Extract the n-th token of a separated list
    FUNCTION f_tok(p_s VARCHAR2, p_n NUMBER, p_sep VARCHAR2 DEFAULT '|')
        RETURN VARCHAR2 IS
        v_s VARCHAR2(4000) := p_s || p_sep;
        v_p NUMBER := 1;
        v_q NUMBER;
    BEGIN
        FOR i IN 1 .. p_n - 1 LOOP
            v_p := INSTR(v_s, p_sep, v_p);
            IF v_p = 0 THEN RETURN NULL; END IF;
            v_p := v_p + 1;
        END LOOP;
        v_q := INSTR(v_s, p_sep, v_p);
        IF v_q = 0 THEN RETURN NULL; END IF;
        RETURN SUBSTR(v_s, v_p, v_q - v_p);
    END;

    -- Horizontal rule of a table, driven by the widths list
    PROCEDURE tbl_line(p_widths VARCHAR2) IS
        v_line VARCHAR2(4000) := '  +';
        v_w    VARCHAR2(4000) := p_widths || ',';
        v_pos  NUMBER := 1;
        v_next NUMBER;
        v_n    NUMBER;
    BEGIN
        LOOP
            v_next := INSTR(v_w, ',', v_pos);
            EXIT WHEN v_next = 0;
            v_n := TO_NUMBER(SUBSTR(v_w, v_pos, v_next - v_pos));
            v_line := v_line || RPAD('-', v_n, '-') || '+';
            v_pos := v_next + 1;
        END LOOP;
        po(v_line);
    END;

    -- Two line table heading: business label, then DATABASE COLUMN NAME.
    --   p_w     widths, comma separated
    --   p_lab   business labels, pipe separated
    --   p_col   database column names, pipe separated, empty where none
    --   p_align one letter per column, R for right aligned, L otherwise
    PROCEDURE tbl_head(p_w VARCHAR2, p_lab VARCHAR2, p_col VARCHAR2,
                       p_align VARCHAR2 DEFAULT NULL) IS
        v_l1 VARCHAR2(4000) := '  |';
        v_l2 VARCHAR2(4000) := '  |';
        v_n  NUMBER := 0;
        v_wi NUMBER;
        v_a  VARCHAR2(1);
        v_c  VARCHAR2(200);
    BEGIN
        tbl_line(p_w);
        LOOP
            v_n  := v_n + 1;
            v_wi := TO_NUMBER(f_tok(p_w, v_n, ','));
            EXIT WHEN v_wi IS NULL;
            v_a  := NVL(SUBSTR(p_align, v_n, 1), 'L');
            v_c  := f_tok(p_col, v_n);
            IF v_c IS NULL OR TRIM(v_c) IS NULL THEN
                v_c := ' ';
            ELSE
                v_c := '(' || TRIM(v_c) || ')';
            END IF;
            IF v_a = 'R' THEN
                v_l1 := v_l1 || fpadl(f_tok(p_lab, v_n), v_wi) || '|';
                v_l2 := v_l2 || fpadl(v_c, v_wi) || '|';
            ELSE
                v_l1 := v_l1 || fpad(f_tok(p_lab, v_n), v_wi) || '|';
                v_l2 := v_l2 || fpad(v_c, v_wi) || '|';
            END IF;
        END LOOP;
        po(v_l1);
        po(v_l2);
        tbl_line(p_w);
    END;

    -- ========================================================================
    -- Test helpers
    -- ========================================================================
    PROCEDURE p_test(p_code VARCHAR2, p_desc VARCHAR2) IS
    BEGIN
        po('');
        po('  ' || v_sub);
        po('  TEST ' || RPAD(p_code, 14) || ' ' || p_desc);
        po('  ' || v_sub);
    END;

    PROCEDURE p_obj(t VARCHAR2) IS
    BEGIN
        po('  Why it matters . ' || t);
    END;

    PROCEDURE p_how(t VARCHAR2) IS
    BEGIN
        po('  How it is run  . ' || t);
    END;

    -- Result of a test: prints the verdict and records it for part 5.
    -- p_crit : CRITICAL / HIGH / MEDIUM / LOW / INFO
    PROCEDURE p_verdict(p_code VARCHAR2,
                        p_lib  VARCHAR2,
                        p_nb   NUMBER,
                        p_base NUMBER   DEFAULT NULL,
                        p_mt   NUMBER   DEFAULT NULL,
                        p_crit VARCHAR2 DEFAULT 'MEDIUM') IS
        v_r t_res;
        v_l VARCHAR2(400);
    BEGIN
        v_r.code := p_code;
        v_r.lib  := SUBSTR(p_lib, 1, 100);
        v_r.nb   := NVL(p_nb, 0);
        v_r.base := p_base;
        v_r.mt   := p_mt;
        v_r.crit := p_crit;
        g_n := g_n + 1;
        g_res(g_n) := v_r;

        v_l := '  >> RESULT . ' || fnum(p_nb) || ' case(s)';
        IF NVL(p_base, 0) > 0 THEN
            v_l := v_l || ' out of ' || fnum(p_base) || ' (' || fpct(p_nb, p_base) || ')';
        END IF;
        IF p_mt IS NOT NULL THEN
            v_l := v_l || ' - amount concerned ' || fmio(p_mt);
        END IF;

        IF NVL(p_nb, 0) = 0 THEN
            v_l := v_l || '   [ PASS ]';
        ELSIF p_crit = 'INFO' THEN
            v_l := v_l || '   [ FOR INFORMATION ]';
        ELSE
            v_l := v_l || '   [ FINDING - ' || p_crit || ' ]';
            g_find := g_find + 1;
            IF p_crit IN ('CRITICAL', 'HIGH') THEN
                g_sev := g_sev + 1;
            END IF;
        END IF;
        po(v_l);
    END;

    -- ========================================================================
    -- THE CALYPSO ITEM TABLE
    -- Calypso posts entries, not contracts, so a finding there cannot name a
    -- CONTRACT_REF_NO. What it names instead is the Calypso deal key, the
    -- book, the counterparty and the instrument, all read from the narrative
    -- returned by FN_GET_DESC. The rule that governs the whole file: a finding
    -- nobody can trace to a named item is not actionable.
    -- ========================================================================
    PROCEDURE cy_head(p_find VARCHAR2 DEFAULT 'FINDING') IS
    BEGIN
        po('     Calypso items concerned . the deal key, the book, the counterparty');
        po('     and the instrument are read from the narrative, so they are only as');
        po('     reliable as section 1.3 shows that narrative to be.');
        tbl_head('4,26,20,20,20,30,14,14,26',
                 'N#|CALYPSO DEAL|BOOK|COUNTERPARTY|EVENT|INSTRUMENT|FIRST|LAST|' || p_find,
                 '|FN_GET_DESC|FN_GET_DESC|FN_GET_DESC|FN_GET_DESC'
                 || '|FN_GET_DESC|TRN_DT|TRN_DT|',
                 'RLLLLLLLR');
    END;

    PROCEDURE cy_row(p_n    NUMBER,
                     p_key  VARCHAR2,
                     p_book VARCHAR2,
                     p_ctp  VARCHAR2,
                     p_evt  VARCHAR2,
                     p_ins  VARCHAR2,
                     p_d1   DATE,
                     p_d2   DATE,
                     p_find VARCHAR2) IS
    BEGIN
        po('  |' || fpadl(TO_CHAR(p_n), 4) || '|' || fpad(p_key, 26) || '|'
            || fpad(p_book, 20) || '|' || fpad(p_ctp, 20) || '|'
            || fpad(p_evt, 20) || '|' || fpad(p_ins, 30) || '|'
            || fpad(fdt(p_d1), 14) || '|' || fpad(fdt(p_d2), 14) || '|'
            || fpadl(p_find, 26) || '|');
    END;

    PROCEDURE cy_foot IS
    BEGIN
        tbl_line('4,26,20,20,20,30,14,14,26');
    END;

BEGIN
    -- ########################################################################
    -- PART 0 : SCOPE, PARAMETERS AND HOW THE INTERFACE WORKS
    -- ########################################################################
    po(v_sep);
    po('   CALYPSO INTERFACE AUDIT - ACCOUNTING ENTRIES POSTED INTO FLEXCUBE');
    po('   Report produced on ' || fdth(SYSDATE));
    po(v_sep);

    print_section('0. SCOPE, PARAMETERS AND HOW THE INTERFACE WORKS');
    BEGIN
        print_sub('0.1 Execution context');
        print_kv('Database',        SYS_CONTEXT('USERENV', 'DB_NAME'));
        print_kv('Instance',        SYS_CONTEXT('USERENV', 'INSTANCE_NAME'));
        print_kv('Schema',          SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        print_kv('Session user',    SYS_CONTEXT('USERENV', 'SESSION_USER'));

        print_sub('0.2 Engagement parameters');
        print_kv('Interface user (USER_ID and AUTH_ID)', k_cy_user);
        print_kv('Pattern actually tested on LOWER(USER_ID)', k_cy_upat);
        print_kv('Module (MODULE)',                      k_cy_mod);
        print_kv('Product (PRODUCT)',                    k_cy_prod);
        print_kv('Amount tag (AMOUNT_TAG)',              k_cy_tag);
        print_kv('Transaction code (TRN_CODE)',          k_cy_code);
        print_kv('Period reviewed (TRN_DT)',             fdt(k_cy_from) || ' to '
                 || fdt(k_cy_to) || ' inclusive, that is TRN_DT below '
                 || fdt(k_cy_to + 1));
        print_kv('Absolute tolerance',                   famt(k_tol_abs) || ' XAF');
        print_kv('Tolerated age of a bridge item',       TO_CHAR(k_cy_age) || ' days');
        print_kv('Tolerated age of accrued interest',    TO_CHAR(k_cy_age_c) || ' months');
        print_kv('Tolerated months with no revaluation', TO_CHAR(k_cy_val_m));
        print_kv('Tolerated gross over net ratio',       TO_CHAR(k_cy_infl));
        print_kv('Tolerated back valuation',             TO_CHAR(k_cy_back_d) || ' days');
        print_kv('A residual multiple of this is one leg', fmio(k_cy_round));
        print_kv('Narrative token offset (k_cy_p0)',     TO_CHAR(k_cy_p0));
        print_kv('Detail lines printed per test',        TO_CHAR(k_top));
        print_kv('Cap on the exhaustive lists',          TO_CHAR(k_top_all));

        print_sub('0.3 How the interface works, and what follows from it');
        po('  Calypso never posts a deal as one balanced entry facing the real');
        po('  counterparty. It splits the deal into several small entries, and each');
        po('  one uses a BRIDGE account as its counter leg. The bridge is the');
        po('  plumbing between the two systems: one event debits it, another event');
        po('  clears it. FLEXCUBE is a slave ledger, it receives legs, not deals.');
        po('');
        po('    ' || k_cy_brg_sec || '   bridge for securities, bonds and bills');
        po('    ' || k_cy_brg_mm || '   bridge for the money market and the nostro transfers');
        po('    ' || k_cy_brg_mir || '   bridge for the client mirror trades');
        po('');
        po('  Three consequences run through the whole report.');
        po('');
        po('  1. A TRANSIT ACCOUNT MUST RETURN TO NIL. Whatever a bridge still');
        po('     carries at the cut off is a deal the interface started and never');
        po('     finished. Part 2 is built entirely on that idea.');
        po('  2. ONE FLEXCUBE REFERENCE PER EVENT. A deal is scattered over several');
        po('     TRN_REF_NO and can only be reassembled through the deal key of the');
        po('     narrative. Grouping on TRN_REF_NO would show every reference');
        po('     unbalanced on the bridge, by construction, and prove nothing.');
        po('  3. THE NARRATIVE IS THE ONLY BUSINESS INFORMATION, AND IT IS NOT A');
        po('     COLUMN. FLEXCUBE carries one product, one tag and one transaction');
        po('     code for every line. The book, the event, the counterparty and the');
        po('     instrument survive only in the description, which is not stored but');
        po('     COMPUTED by webserve.FN_GET_DESC from the columns of the entry. The');
        po('     business meaning of a Calypso entry therefore depends on code this');
        po('     audit does not control and cannot version. Section 1.3 measures how');
        po('     far that free text can be trusted before anything else uses it.');
        po('');
        po('  A fourth point, on reading the figures. Every business day the');
        po('  valuation engine posts the FULL CUMULATIVE accrual of each position');
        po('  and reverses it the next business day. The net result is correct; the');
        po('  gross flows are inflated by a factor of eighty or more. NEVER READ A');
        po('  GROSS TOTAL on the accounts listed in section 4.1.');

        print_sub('0.4 The accounts the interface moves');
        po('  Real account numbers, as they appear in ACTB_HISTORY.AC_NO. The class');
        po('  is the first digit: 5 balance sheet securities and treasury,');
        po('  4 transit and deferred income, 6 expense, 7 income, 9 off balance');
        po('  sheet.');
        tbl_head('4,20,58,40',
                 'N#|ACCOUNT|WHAT IT IS|WHERE IT IS USED',
                 '|AC_NO| | ',
                 'RLLL');
        v_row := 0;
        FOR r IN (SELECT n, ac, q, w FROM (
                    SELECT 1 n, k_cy_brg_sec ac, 'Bridge, securities' q, 'part 2' w FROM DUAL
                    UNION ALL SELECT 2, k_cy_brg_mm, 'Bridge, money market and transfers', 'part 2' FROM DUAL
                    UNION ALL SELECT 3, k_cy_brg_mir, 'Bridge, client mirror trades', 'part 2' FROM DUAL
                    UNION ALL SELECT 4, k_cy_bond, 'Bonds at face value, transaction book', 'part 3' FROM DUAL
                    UNION ALL SELECT 5, k_cy_bill, 'Treasury bills at face value, placement book', 'part 3' FROM DUAL
                    UNION ALL SELECT 6, k_cy_accr, 'Accrued interest receivable', 'part 3' FROM DUAL
                    UNION ALL SELECT 7, k_cy_def_b, 'Unearned income parked on the bonds', 'part 3' FROM DUAL
                    UNION ALL SELECT 8, k_cy_def_t, 'Unearned income parked on the bills', 'part 3' FROM DUAL
                    UNION ALL SELECT 9, k_cy_prov, 'Impairment provision, mark to market', 'part 4' FROM DUAL
                    UNION ALL SELECT 10, k_cy_borrow, 'Overnight borrowing, repo liability', 'part 3' FROM DUAL
                    UNION ALL SELECT 11, k_cy_debt, 'Accrued interest payable on the borrowing', 'part 3' FROM DUAL
                    UNION ALL SELECT 12, k_cy_fx_pos, 'FX position account of the interface', 'part 2' FROM DUAL
                    UNION ALL SELECT 13, k_cy_fx_cv, 'Its counter value account', 'part 2' FROM DUAL
                    UNION ALL SELECT 14, k_cy_col_ti, 'Securities pledged as collateral', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 15, k_cy_col_gl, 'Collateral given, general ledger side', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 16, k_cy_ob_fxb, 'Spot bought and not yet received', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 17, k_cy_ob_fxs, 'Spot sold and not yet delivered', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 18, k_cy_ob_fwd, 'Forward sold and not yet delivered', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 19, k_cy_ob_adj, 'FX off balance sheet adjustment', 'part 2' FROM DUAL
                    UNION ALL SELECT 20, k_cy_cus_t, 'Securities held for third parties', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 21, k_cy_cus_c, 'Securities held for clients', 'parts 2 and 3' FROM DUAL
                    UNION ALL SELECT 22, k_cy_inc_b, 'Bond income, accrued', 'part 3' FROM DUAL
                    UNION ALL SELECT 23, k_cy_inc_br, 'Bond income, realised on disposal', 'part 3' FROM DUAL
                    UNION ALL SELECT 24, k_cy_inc_t, 'Treasury bill income, accrued', 'part 3' FROM DUAL
                    UNION ALL SELECT 25, k_cy_inc_tr, 'Treasury bill income, realised', 'part 3' FROM DUAL
                    UNION ALL SELECT 26, k_cy_exp_mm, 'Interest expense on the money market', 'part 3' FROM DUAL
                    UNION ALL SELECT 27, k_cy_com_pf, 'Portfolio management commission earned', 'part 3' FROM DUAL
                    UNION ALL SELECT 28, k_cy_com_fx, 'Commission paid on FX purchases', 'part 3' FROM DUAL
                  ) ORDER BY n) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac, 20) || '|'
                || fpad(r.q, 58) || '|' || fpad(r.w, 40) || '|');
        END LOOP;
        tbl_line('4,20,58,40');
        po('  Note one inconsistency, visible in the accounts themselves: bonds go');
        po('  to a TRANSACTION account (' || k_cy_bond || ') while bills go to a PLACEMENT');
        po('  account (' || k_cy_bill || '), although both sit in the same Calypso book family.');
        po('  The front office classification and the chart of accounts do not agree,');
        po('  and no entry can say which of the two is right.');

        print_sub('0.5 Reading the report');
        po('  TWO WORDS, AND THEY ARE NOT THE SAME THING.');
        po('');
        po('    BALANCE   the balance as this bank computes it, CREDIT MINUS DEBIT.');
        po('              That is the figure the general ledger shows, so it is the');
        po('              figure this report prints wherever a column is called a');
        po('              balance, a residual or a net. On an asset the balance is');
        po('              therefore NEGATIVE when the bank holds something: a');
        po('              security account carrying paper shows a debit balance,');
        po('              which in credit minus debit is a negative number.');
        po('    POSITION  what the bank actually holds, in its natural sense and');
        po('              always positive when normal. On a debit nature account it');
        po('              is MINUS the balance; on a credit nature account, an');
        po('              income or a deferred income, it is the balance itself.');
        po('');
        po('  Every column says which of the two it is. The portfolio of part 3 is');
        po('  given in positions, because a portfolio read in negative numbers helps');
        po('  nobody; the bridge residuals of part 2 are given as balances, because');
        po('  that is what has to be matched against the ledger. Gross debit and');
        po('  gross credit are printed separately where they help, and section 4.1');
        po('  says exactly on which accounts they must not be used.');
        po('');
        po('  Each test prints why it matters, how it is run, and a verdict:');
        po('');
        po('    [ PASS ]              no case found');
        po('    [ FINDING - level ]   cases found, level CRITICAL to LOW');
        po('    [ FOR INFORMATION ]   descriptive material, not an anomaly');
        po('');
        po('  Every finding names the items concerned: the deal key, the book, the');
        po('  counterparty, the instrument and the dates, all read from the');
        po('  narrative. A finding nobody can trace to a named item is not');
        po('  actionable.');

        print_sub('0.6 Source of truth');
        po('  ACTB_HISTORY IS THE ONLY PLACE WHERE THE LIFE OF THESE OPERATIONS');
        po('  LIVES. In the money market module that rule had to be defended');
        po('  against management tables that said something else. Here there is');
        po('  nothing to defend it against: no contract, no schedule, no balance');
        po('  table. The entries are all there is.');
        po('');
        po('  That has one consequence worth stating plainly. This report cannot');
        po('  tell whether a deal was correctly priced, correctly authorised or');
        po('  correctly valued, because none of that reaches FLEXCUBE. It can tell,');
        po('  with certainty, what the general ledger now carries because of');
        po('  Calypso, what has not been cleared, and what cannot be attached to any');
        po('  identifiable security. Section 4.4 lists what remains unknowable and');
        po('  what has to be asked of the front office.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 1 : THE INTERFACE, ITS FOOTPRINT AND ITS NARRATIVE');
    -- ########################################################################
    po('');
    po('  How many entries, over what period, on how many accounts, through how');
    po('  many books, and above all HOW MUCH OF THE NARRATIVE CAN BE TRUSTED.');
    po('  Section 1.3 is not a formality: every figure of parts 2, 3 and 4 that');
    po('  names a deal, a book or an instrument rests on that one free text');
    po('  field, and this is where the reader gets to judge it.');

    print_section('1. FOOTPRINT, CALENDAR, NARRATIVE AND ACCOUNTS MOVED');
    BEGIN

        -- =====================================================
        print_sub('1.1 Footprint of the interface');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0),
               MIN(h.trn_dt), MAX(h.trn_dt)
          INTO v_cy_nb, v_cy_mt, v_cy_d1, v_cy_d2
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1;
        print_kv('Entry lines posted by ' || k_cy_user, fnum(v_cy_nb));
        print_kv('Gross flow (sum of LCY_AMOUNT)',      fmio(v_cy_mt));
        print_kv('First entry (TRN_DT)',                fdt(v_cy_d1));
        print_kv('Last entry (TRN_DT)',                 fdt(v_cy_d2));
        print_kv('Cut off of this review',              fdt(k_cy_to));
        IF v_cy_nb = 0 THEN
            po('');
            po('  NO CALYPSO ENTRY FOUND with that signature. Either the interface');
            po('  posts under another module, product or user in this database, or');
            po('  the period is wrong. Check section 1.1 a before reading further:');
            po('  every figure of this part would otherwise be nil by construction.');
        END IF;

        SELECT COUNT(DISTINCT h.trn_ref_no),
               COUNT(DISTINCT TRUNC(h.trn_dt)),
               COUNT(DISTINCT h.ac_no)
          INTO v_cnt, v_cnt2, v_cnt3
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1;
        print_kv('Distinct FLEXCUBE references (TRN_REF_NO)', fnum(v_cnt));
        print_kv('Distinct posting dates (TRN_DT)',           fnum(v_cnt2));
        print_kv('Distinct accounts moved (AC_NO)',           fnum(v_cnt3));
        SELECT COUNT(DISTINCT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                  d.ref)),
               NVL(SUM(CASE WHEN d.dsc IS NULL THEN 1 ELSE 0 END), 0),
               NVL(SUM(CASE WHEN INSTR(NVL(d.dsc, ' '), '|') > 0
                            THEN 1 ELSE 0 END), 0),
               COUNT(DISTINCT d.dsc)
          INTO v_cy_dl, v_cy_dn, v_cy_dp, v_cy_dd
          FROM (SELECT h.trn_ref_no ref,
                       webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                            h.event_sr_no, h.trn_code, h.related_account,
                                            h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                            h.event, h.instrument_code, h.related_customer,
                                            h.value_dt, h.trn_dt, h.related_reference) dsc
                  FROM actb_history h
                 WHERE h.module = k_cy_mod
                 AND h.product = k_cy_prod
                 AND LOWER(h.user_id) LIKE k_cy_upat
                 AND h.trn_dt >= k_cy_from
                 AND h.trn_dt <  k_cy_to + 1) d;
        print_kv('Distinct Calypso deal keys (narrative)',    fnum(v_cy_dl));
        po('     One FLEXCUBE reference is created PER EVENT, not per deal. The deal');
        po('     key of the narrative is the only thing that puts a deal back');
        po('     together, which is why every section below groups on it.');

        SELECT NVL(SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0)
          INTO v_tot, v_tot2
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1;
        print_kv('Gross debits',  fmio(v_tot));
        print_kv('Gross credits', fmio(v_tot2));
        print_kv('Balance (credits minus debits)', famt(v_tot2 - v_tot)
                 || CASE WHEN ABS(v_tot - v_tot2) <= k_tol_abs
                         THEN '   the whole population balances'
                         ELSE '   THE POPULATION DOES NOT BALANCE' END);

        print_sub('1.1 a. Is the signature of the interface exclusive');
        po('  Two questions that decide whether the population above is the right');
        po('  one. If ' || k_cy_prod || ' is posted by somebody else, this part misses entries. If');
        po('  ' || k_cy_user || ' posts under another product, this part misses them too.');
        tbl_head('4,54,20,28,18,18',
                 'N#|QUESTION|LINES|AMOUNT|FIRST|LAST',
                 '| |TRN_REF_NO|LCY_AMOUNT|TRN_DT|TRN_DT',
                 'RLRRLL');
        v_row := 0;
        FOR r IN (SELECT 1 ord, 'Product ' || k_cy_prod || ' posted by another user' q FROM DUAL
                  UNION ALL
                  SELECT 2, 'User ' || k_cy_user || ' posting another product' FROM DUAL
                  UNION ALL
                  SELECT 3, 'User ' || k_cy_user || ' posting outside module ' || k_cy_mod FROM DUAL
                  UNION ALL
                  SELECT 4, 'Calypso lines dated after the cut off of this review' FROM DUAL
                  ORDER BY 1) LOOP
            BEGIN
                SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0),
                       MIN(h.trn_dt), MAX(h.trn_dt)
                  INTO v_cnt, v_mt, v_d_max, v_d_last2
                  FROM actb_history h
                 WHERE h.module = k_cy_mod
                   AND ((r.ord = 1 AND h.product = k_cy_prod
                                     AND LOWER(h.user_id) NOT LIKE k_cy_upat)
                     OR (r.ord = 2 AND LOWER(h.user_id) LIKE k_cy_upat AND h.product <> k_cy_prod)
                     OR (r.ord = 4 AND h.product = k_cy_prod
                                     AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_to + 1));
                IF r.ord = 3 THEN
                    SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0),
                           MIN(h.trn_dt), MAX(h.trn_dt)
                      INTO v_cnt, v_mt, v_d_max, v_d_last2
                      FROM actb_history h
                     WHERE LOWER(h.user_id) LIKE k_cy_upat
                       AND h.module <> k_cy_mod;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN v_cnt := -1; v_mt := 0;
                                 v_d_max := NULL; v_d_last2 := NULL;
            END;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.q, 54) || '|'
                || fpadl(CASE WHEN v_cnt < 0 THEN '-' ELSE fnum(v_cnt) END, 20) || '|'
                || fpadl(fmio(v_mt), 28) || '|' || fpad(fdt(v_d_max), 18) || '|'
                || fpad(fdt(v_d_last2), 18) || '|');
        END LOOP;
        tbl_line('4,54,20,28,18,18');
        po('  Line 4 is the material this review deliberately leaves out. It is not');
        po('  an anomaly, it is the cut off at ' || fdt(k_cy_to) || ': the figure is printed so the');
        po('  reader knows how much activity lies beyond it.');

        print_sub('1.1 b. The interface by branch, currency, event and direction');
        tbl_head('4,16,22,22,28,20',
                 'N#|AXIS|VALUE|LINES|GROSS AMOUNT|SHARE OF LINES',
                 '| | |TRN_REF_NO|LCY_AMOUNT| ',
                 'RLLRRR');
        v_row := 0;
        FOR r IN (SELECT axis, val, nb, mt FROM (
                    SELECT 'BRANCH' axis, h.ac_branch val, COUNT(*) nb,
                           SUM(ABS(NVL(h.lcy_amount, 0))) mt, 1 ord
                      FROM actb_history h WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                     GROUP BY h.ac_branch
                    UNION ALL
                    SELECT 'CURRENCY', h.ac_ccy, COUNT(*),
                           SUM(ABS(NVL(h.lcy_amount, 0))), 2
                      FROM actb_history h WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                     GROUP BY h.ac_ccy
                    UNION ALL
                    SELECT 'EVENT', h.event, COUNT(*),
                           SUM(ABS(NVL(h.lcy_amount, 0))), 3
                      FROM actb_history h WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                     GROUP BY h.event
                    UNION ALL
                    SELECT 'DIRECTION', h.drcr_ind, COUNT(*),
                           SUM(ABS(NVL(h.lcy_amount, 0))), 4
                      FROM actb_history h WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                     GROUP BY h.drcr_ind
                  ) ORDER BY ord, nb DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.axis, 16) || '|'
                || fpad(r.val, 22) || '|' || fpadl(fnum(r.nb), 22) || '|'
                || fpadl(fmio(r.mt), 28) || '|' || fpadl(fpct(r.nb, v_cy_nb), 20) || '|');
        END LOOP;
        tbl_line('4,16,22,22,28,20');

        -- =====================================================
        print_sub('1.2 The posting calendar, month by month');
        po('  LINES is the volume, DATES the number of business days used, WEEKEND');
        po('  the lines dated on a Saturday or a Sunday. BALANCE is credit minus');
        po('  debit, and it must be nil every month: an interface that posts an');
        po('  unbalanced month has lost an entry on the way.');
        tbl_head('4,14,18,12,14,28,24,16',
                 'N#|MONTH|LINES|DATES|WEEKEND|GROSS AMOUNT|BALANCE (C minus D)|VERDICT',
                 '|TRN_DT|TRN_REF_NO|TRN_DT|TRN_DT|LCY_AMOUNT|LCY_AMOUNT| ',
                 'RLRRRRRR');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mth, COUNT(*) nb,
                         COUNT(DISTINCT TRUNC(h.trn_dt)) nbd,
                         SUM(CASE WHEN TRUNC(h.trn_dt) - TRUNC(h.trn_dt, 'IW') >= 5
                                  THEN 1 ELSE 0 END) nbw,
                         SUM(ABS(NVL(h.lcy_amount, 0))) mt,
                         SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) sgn
                    FROM actb_history h
                   WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
                   GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM')
                   ORDER BY 1) LOOP
            v_row := v_row + 1;
            IF ABS(r.sgn) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mth, 14) || '|'
                || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nbd), 12) || '|'
                || fpadl(fnum(r.nbw), 14) || '|' || fpadl(fmio(r.mt), 28) || '|'
                || fpadl(famt(r.sgn), 24) || '|'
                || fpadl(CASE WHEN ABS(r.sgn) > k_tol_abs THEN 'UNBALANCED'
                              WHEN r.nbw > 0 THEN 'WEEKEND' ELSE 'OK' END, 16) || '|');
        END LOOP;
        tbl_line('4,14,18,12,14,28,24,16');
        print_kv('Months whose entries do not balance', fnum(v_cnt));

        -- =====================================================
        print_sub('1.3 The narrative, and how far it can be trusted');
        po('  THE DESCRIPTION IS NOT A COLUMN. FLEXCUBE stores no narrative on an');
        po('  accounting entry. What everyone calls the description is produced by a');
        po('  function, called on the columns of the entry:');
        po('');
        po('    webserve.FN_GET_DESC(module, trn_ref_no, ac_entry_sr_no,');
        po('                         event_sr_no, trn_code, related_account, ac_no,');
        po('                         ac_branch, ac_ccy, amount_tag, event,');
        po('                         instrument_code, related_customer,');
        po('                         value_dt, trn_dt, related_reference)');
        po('');
        po('  That matters for two reasons. The business meaning of a Calypso entry');
        po('  depends on code the audit does not control and cannot version: change');
        po('  the function and every figure below changes with it, silently. And the');
        po('  call is made once per row, so the sections that read it over the whole');
        po('  population are the slow ones, this one included.');
        po('');
        po('  On the Calypso entries the string is expected to be pipe separated:');
        po('');
        po('    deal id | entry id | EVENT | product type | counterparty | book |'
           || ' instrument code | instrument label');
        po('');
        po('  Everything below, and every Calypso control, reads it positionally.');
        po('  The tables of this section exist so the reader can verify that reading');
        po('  before trusting a single figure that depends on it. IF THE SAMPLE SHOWS');
        po('  THE FIELDS SHIFTED BY ONE, set k_cy_p0 to 1 in the parameter block and');
        po('  run the script again.');
        print_kv('Lines with an empty description',        fnum(v_cy_dn)
                 || '   ' || fpct(v_cy_dn, v_cy_nb));
        print_kv('Lines whose description is pipe separated', fnum(v_cy_dp)
                 || '   ' || fpct(v_cy_dp, v_cy_nb));
        print_kv('Distinct descriptions',                  fnum(v_cy_dd));
        po('     A line with no pipe is not an error. The interface also carries');
        po('     ordinary commercial traffic whose description is free banking text,');
        po('     a repatriation or a card settlement for instance. Those lines are');
        po('     not treasury deals and cannot be filtered out by product code, since');
        po('     everything is ' || k_cy_prod || '. The count above is how much of the flow they');
        po('     represent.');

        po('');
        po('     Distribution of the number of fields. A stable interface produces');
        po('     one field count. Several counts mean several narrative formats, and');
        po('     any positional reading is right for one of them only.');
        tbl_head('4,20,22,28,18,18',
                 'N#|FIELDS IN THE STRING|LINES|GROSS AMOUNT|FIRST|LAST',
                 '|FN_GET_DESC|TRN_REF_NO|LCY_AMOUNT|TRN_DT|TRN_DT',
                 'RRRRLL');
        v_row := 0;
        FOR r IN (SELECT nbf, COUNT(*) nb, SUM(mt) mt, MIN(dt) d1, MAX(dt) d2
                    FROM (SELECT LENGTH(NVL(d.dsc, ' '))
                                 - LENGTH(REPLACE(NVL(d.dsc, ' '), '|', '')) + 1 nbf,
                                 d.mt, d.dt
                            FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                        h.event_sr_no, h.trn_code, h.related_account,
                                                        h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                        h.event, h.instrument_code, h.related_customer,
                                                        h.value_dt, h.trn_dt, h.related_reference) dsc,
                                         ABS(NVL(h.lcy_amount, 0)) mt, h.trn_dt dt
                                    FROM actb_history h
                                   WHERE h.module = k_cy_mod
                             AND h.product = k_cy_prod
                             AND LOWER(h.user_id) LIKE k_cy_upat
                             AND h.trn_dt >= k_cy_from
                             AND h.trn_dt <  k_cy_to + 1) d)
                   GROUP BY nbf
                   ORDER BY 2 DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpadl(fnum(r.nbf), 20) || '|'
                || fpadl(fnum(r.nb), 22) || '|' || fpadl(fmio(r.mt), 28) || '|'
                || fpad(fdt(r.d1), 18) || '|' || fpad(fdt(r.d2), 18) || '|');
        END LOOP;
        tbl_line('4,20,22,28,18,18');

        po('');
        po('     The same distribution month by month. THIS IS THE TABLE THAT DATES A');
        po('     CHANGE OF FORMAT. A field count that appears in one month and stops');
        po('     in the next is an interface contract that was rewritten, and every');
        po('     parsing rule written before that month stopped matching on that day,');
        po('     silently. It has already happened once.');
        tbl_head('4,16,22,22,30,18',
                 'N#|MONTH|FIELDS IN THE STRING|LINES|GROSS AMOUNT|SHARE OF THE MONTH',
                 '|TRN_DT|FN_GET_DESC|TRN_REF_NO|LCY_AMOUNT| ',
                 'RLRRRR');
        v_row := 0;
        FOR r IN (SELECT mth, nbf, COUNT(*) nb, SUM(mt) mt,
                         RATIO_TO_REPORT(COUNT(*)) OVER (PARTITION BY mth) shr
                    FROM (SELECT TO_CHAR(d.dt, 'YYYY-MM') mth,
                                 LENGTH(NVL(d.dsc, ' '))
                                 - LENGTH(REPLACE(NVL(d.dsc, ' '), '|', '')) + 1 nbf,
                                 d.mt
                            FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                        h.event_sr_no, h.trn_code, h.related_account,
                                                        h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                        h.event, h.instrument_code, h.related_customer,
                                                        h.value_dt, h.trn_dt, h.related_reference) dsc,
                                         ABS(NVL(h.lcy_amount, 0)) mt, h.trn_dt dt
                                    FROM actb_history h
                                   WHERE h.module = k_cy_mod
                             AND h.product = k_cy_prod
                             AND LOWER(h.user_id) LIKE k_cy_upat
                             AND h.trn_dt >= k_cy_from
                             AND h.trn_dt <  k_cy_to + 1) d)
                   GROUP BY mth, nbf
                   ORDER BY mth, nbf) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mth, 16) || '|'
                || fpadl(fnum(r.nbf), 22) || '|' || fpadl(fnum(r.nb), 22) || '|'
                || fpadl(fmio(r.mt), 30) || '|'
                || fpadl(TO_CHAR(ROUND(r.shr * 100, 1), 'FM990D0') || ' %', 18) || '|');
        END LOOP;
        tbl_line('4,16,22,22,30,18');

        po('');
        po('     Raw sample. Read it against the field order above.');
        tbl_head('4,16,110',
                 'N#|DATE|DESCRIPTION AS THE FUNCTION RETURNS IT',
                 '|TRN_DT|FN_GET_DESC',
                 'RLL');
        v_row := 0;
        FOR r IN (SELECT h.trn_dt dt,
                         webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                              h.event_sr_no, h.trn_code, h.related_account,
                                              h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                              h.event, h.instrument_code, h.related_customer,
                                              h.value_dt, h.trn_dt, h.related_reference) ext
                    FROM (SELECT * FROM (
                            SELECT h.* FROM actb_history h
                             WHERE h.module = k_cy_mod
                             AND h.product = k_cy_prod
                             AND LOWER(h.user_id) LIKE k_cy_upat
                             AND h.trn_dt >= k_cy_from
                             AND h.trn_dt <  k_cy_to + 1
                             ORDER BY h.trn_dt DESC, h.trn_ref_no)
                           WHERE ROWNUM <= 12) h) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.dt), 16) || '|'
                || fpad(r.ext, 110) || '|');
        END LOOP;
        tbl_line('4,16,110');

        po('');
        po('     The same lines split into the fields this script will use.');
        tbl_head('4,26,18,20,20,16,34',
                 'N#|DEAL KEY|EVENT|BOOK|COUNTERPARTY|PRODUCT TYPE|INSTRUMENT',
                 '|FN_GET_DESC|FN_GET_DESC|FN_GET_DESC|FN_GET_DESC'
                 || '|FN_GET_DESC|FN_GET_DESC',
                 'RLLLLLL');
        v_row := 0;
        FOR r IN (SELECT RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_id + k_cy_p0), '|') k1,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_evt + k_cy_p0), '|') k2,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_book + k_cy_p0), '|') k3,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_ctp + k_cy_p0), '|') k4,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_typ + k_cy_p0), '|') k5,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_lbl + k_cy_p0), '|') k6
                    FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                      h.event_sr_no, h.trn_code, h.related_account,
                                                      h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                      h.event, h.instrument_code, h.related_customer,
                                                      h.value_dt, h.trn_dt, h.related_reference) dsc
                            FROM (SELECT * FROM (
                                    SELECT h.* FROM actb_history h
                                     WHERE h.module = k_cy_mod
                                     AND h.product = k_cy_prod
                                     AND LOWER(h.user_id) LIKE k_cy_upat
                                     AND h.trn_dt >= k_cy_from
                                     AND h.trn_dt <  k_cy_to + 1
                                     ORDER BY h.trn_dt DESC, h.trn_ref_no)
                                   WHERE ROWNUM <= 12) h) d) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.k1, 26) || '|'
                || fpad(r.k2, 18) || '|' || fpad(r.k3, 20) || '|'
                || fpad(r.k4, 20) || '|' || fpad(r.k5, 16) || '|'
                || fpad(r.k6, 34) || '|');
        END LOOP;
        tbl_line('4,26,18,20,20,16,34');

        print_sub('1.3 a. The business lines Calypso runs, read from the narrative');
        po('  The book is the best proxy available for a business line. FIRST and');
        po('  LAST show the progressive roll out of the interface, product by');
        po('  product. A book that stops without explanation is worth a question.');
        tbl_head('4,26,18,22,26,18,18,18',
                 'N#|BOOK|PRODUCT TYPE|LINES|GROSS AMOUNT|DEALS|FIRST|LAST',
                 '|FN_GET_DESC|FN_GET_DESC|TRN_REF_NO|LCY_AMOUNT'
                 || '|FN_GET_DESC|TRN_DT|TRN_DT',
                 'RLLRRRLL');
        v_row := 0;
        FOR r IN (SELECT RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_book + k_cy_p0), '|') book,
                         RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_typ + k_cy_p0), '|') typ,
                         COUNT(*) nb, SUM(d.mt) mt,
                         COUNT(DISTINCT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                            1, k_cy_t_id + k_cy_p0), '|'),
                                            d.ref)) nbd,
                         MIN(d.dt) d1, MAX(d.dt) d2
                    FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                      h.event_sr_no, h.trn_code, h.related_account,
                                                      h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                      h.event, h.instrument_code, h.related_customer,
                                                      h.value_dt, h.trn_dt, h.related_reference) dsc,
                                 h.trn_ref_no ref, ABS(NVL(h.lcy_amount, 0)) mt,
                                 h.trn_dt dt
                            FROM actb_history h
                           WHERE h.module = k_cy_mod
                           AND h.product = k_cy_prod
                           AND LOWER(h.user_id) LIKE k_cy_upat
                           AND h.trn_dt >= k_cy_from
                           AND h.trn_dt <  k_cy_to + 1) d
                   GROUP BY RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_book + k_cy_p0), '|'),
                            RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_typ + k_cy_p0), '|')
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.book, 26) || '|'
                || fpad(r.typ, 18) || '|' || fpadl(fnum(r.nb), 22) || '|'
                || fpadl(fmio(r.mt), 26) || '|' || fpadl(fnum(r.nbd), 18) || '|'
                || fpad(fdt(r.d1), 18) || '|' || fpad(fdt(r.d2), 18) || '|');
        END LOOP;
        tbl_line('4,26,18,22,26,18,18,18');

        print_sub('1.3 b. The events Calypso posts');
        po('  Each event is a leg of a deal, never a whole deal. BALANCE is credit');
        po('  minus debit over the period: an event that posts and reverses itself,');
        po('  like the daily valuation engine, comes back to nearly nothing while');
        po('  moving billions gross. That contrast is the subject of 4.1.');
        tbl_head('4,28,22,28,26,18,18',
                 'N#|EVENT|LINES|GROSS AMOUNT|BALANCE (C minus D)|FIRST|LAST',
                 '|FN_GET_DESC|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT|TRN_DT|TRN_DT',
                 'RLRRRLL');
        v_row := 0;
        FOR r IN (SELECT RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_evt + k_cy_p0), '|') evt,
                         COUNT(*) nb, SUM(d.mt) mt, SUM(d.sgn) sgn,
                         MIN(d.dt) d1, MAX(d.dt) d2
                    FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                      h.event_sr_no, h.trn_code, h.related_account,
                                                      h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                      h.event, h.instrument_code, h.related_customer,
                                                      h.value_dt, h.trn_dt, h.related_reference) dsc,
                                 ABS(NVL(h.lcy_amount, 0)) mt,
                                 CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                 ELSE -NVL(h.lcy_amount, 0) END sgn,
                                 h.trn_dt dt
                            FROM actb_history h
                           WHERE h.module = k_cy_mod
                           AND h.product = k_cy_prod
                           AND LOWER(h.user_id) LIKE k_cy_upat
                           AND h.trn_dt >= k_cy_from
                           AND h.trn_dt <  k_cy_to + 1) d
                   GROUP BY RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_evt + k_cy_p0), '|')
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.evt, 28) || '|'
                || fpadl(fnum(r.nb), 22) || '|' || fpadl(fmio(r.mt), 28) || '|'
                || fpadl(fmio(r.sgn), 26) || '|' || fpad(fdt(r.d1), 18) || '|'
                || fpad(fdt(r.d2), 18) || '|');
        END LOOP;
        tbl_line('4,28,22,28,26,18,18');

        -- =====================================================
        print_sub('1.4 Every account Calypso moves');
        po('  The complete map of the interface on the chart of accounts. BALANCE is');
        po('  what the account carries at ' || fdt(k_cy_to) || ' from Calypso entries ALONE, in the');
        po('  convention of this bank, CREDIT MINUS DEBIT. A security account holding');
        po('  paper therefore shows a NEGATIVE balance, and an income account a');
        po('  positive one. Read it with the class, first two digits: 5 balance sheet');
        po('  securities and treasury, 4 transit and deferred income, 6 expense,');
        po('  7 income, 9 off balance sheet.');
        tbl_head('4,20,8,40,20,26,26,26,16,16',
                 'N#|ACCOUNT|CLASS|ACCOUNT NAME|LINES|GROSS DEBIT|GROSS CREDIT'
                 || '|BALANCE (C minus D)|FIRST|LAST',
                 '|AC_NO| |AC_GL_DESC|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT|LCY_AMOUNT'
                 || '|TRN_DT|TRN_DT',
                 'RLLLRRRRLL');
        v_row := 0;
        FOR r IN (SELECT h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                         SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0)
                                  ELSE 0 END) dr,
                         SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0)
                                  ELSE 0 END) cr,
                         SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) sgn,
                         MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                    FROM actb_history h
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                 FROM sttb_account GROUP BY ac_gl_no) s
                           ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
                   GROUP BY h.ac_no
                   ORDER BY SUM(ABS(NVL(h.lcy_amount, 0))) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                || fpad(SUBSTR(r.ac_no, 1, 2), 8) || '|' || fpad(r.lib, 40) || '|'
                || fpadl(fnum(r.nb), 20) || '|' || fpadl(fmio(r.dr), 26) || '|'
                || fpadl(fmio(r.cr), 26) || '|' || fpadl(famt(r.sgn), 26) || '|'
                || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|');
        END LOOP;
        tbl_line('4,20,8,40,20,26,26,26,16,16');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 2 : THE BRIDGE ACCOUNTS AND WHAT THEY STILL CARRY');
    -- ########################################################################

    print_section('2. THE RESIDUAL BALANCE OF THE TRANSIT ACCOUNTS');
    BEGIN
        po('  A bridge account is plumbing, not a position. Calypso posts one leg of');
        po('  a deal against it and clears it on the settlement event, so at any');
        po('  date its balance should be nil, or close to nil and made only of');
        po('  deals traded but not yet settled.');
        po('');
        po('  What it actually carries is therefore the accounting measure of what');
        po('  has NOT been closed. It is the one figure in this whole part that');
        po('  cannot be explained away: no deal terms are needed to read it, no');
        po('  narrative, no valuation policy. The account either returns to nil or');
        po('  it does not.');
        po('');
        po('  THIS PART READS THE WHOLE ACCOUNT, NOT THE CALYPSO SLICE OF IT. A');
        po('  transit account has to come back to nil as an ACCOUNT. Testing only');
        po('  the entries the interface posted would hide anything else that landed');
        po('  there, and a manual correction on a bridge is precisely the kind of');
        po('  thing an audit is looking for. So the balance below is the true');
        po('  balance of the account, and it is then split three ways so that the');
        po('  reader sees at once who has to answer for it:');
        po('');
        po('    POSTED BY CALYPSO   module ' || k_cy_mod || ', product ' || k_cy_prod
           || ', user like ' || k_cy_upat || ',');
        po('                        dated on or after the go live ' || fdt(k_cy_from));
        po('    ANYTHING ELSE       everything that is not that, whatever it is');
        po('    BEFORE THE GO LIVE  the part of ANYTHING ELSE that predates Calypso,');
        po('                        printed separately because it is not the');
        po('                        interface failing to clear, it is what the');
        po('                        account already carried when Calypso arrived');
        po('');
        po('  The three add up to the balance, by construction, so the split can be');
        po('  ticked on the page.');
        po('');
        po('  This section then answers four questions, in order. How much is left.');
        po('  Who put it there. Is it growing. And how old it is, deal by deal.');

        -- -----------------------------------------------------
        print_sub('2.1 a. What each transit account carries at ' || fdt(k_cy_to)
                  || ', and who put it there');
        po('  BALANCE is credit minus debit, as this bank computes it and as the');
        po('  general ledger shows it. A positive figure is a credit balance left on');
        po('  the bridge, a negative one a debit balance. Either way it is something');
        po('  that was started and not finished.');
        tbl_head('4,20,32,26,26,26,26,16',
                 'N#|ACCOUNT|ACCOUNT NAME|BALANCE, WHOLE ACCOUNT|POSTED BY CALYPSO'
                 || '|POSTED BY ANYTHING ELSE|OF WHICH BEFORE THE GO LIVE|VERDICT',
                 '|AC_NO|AC_GL_DESC|LCY_AMOUNT|LCY_AMOUNT|LCY_AMOUNT|LCY_AMOUNT| ',
                 'RLLRRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        v_mt2 := 0;
        FOR r IN (SELECT 1 ord, k_cy_brg_sec ac FROM DUAL UNION ALL
                  SELECT 2, k_cy_brg_mm FROM DUAL UNION ALL
                  SELECT 3, k_cy_brg_mir FROM DUAL
                  ORDER BY 1) LOOP
            SELECT NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                   ELSE -NVL(h.lcy_amount, 0) END), 0),
                   NVL(SUM(CASE WHEN h.module = k_cy_mod AND h.product = k_cy_prod
                                AND LOWER(h.user_id) LIKE k_cy_upat
                                AND h.trn_dt >= k_cy_from
                                THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END), 0),
                   NVL(SUM(CASE WHEN h.trn_dt < k_cy_from
                                THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END), 0)
              INTO v_tot, v_tot2, v_mt2
              FROM actb_history h
             WHERE h.ac_no = r.ac
               AND h.trn_dt <  k_cy_to + 1;
            SELECT MAX(a.ac_gl_desc) INTO v_lib
              FROM sttb_account a WHERE a.ac_gl_no = r.ac;
            v_row := v_row + 1;
            IF ABS(v_tot) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(v_tot);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac, 20) || '|'
                || fpad(v_lib, 32) || '|' || fpadl(famt(v_tot), 26) || '|'
                || fpadl(famt(v_tot2), 26) || '|'
                || fpadl(famt(v_tot - v_tot2), 26) || '|'
                || fpadl(famt(v_mt2), 26) || '|'
                || fpadl(CASE WHEN ABS(v_tot) <= k_tol_abs THEN 'CLEARED'
                              WHEN MOD(ABS(v_tot), k_cy_round) = 0 THEN 'ROUND, ONE LEG'
                              ELSE 'NOT CLEARED' END, 16) || '|');
        END LOOP;
        tbl_line('4,20,32,26,26,26,26,16');
        print_kv('Transit accounts that do not clear', fnum(v_cnt) || ' of 3');
        print_kv('Total left in transit',              famt(v_mt) || ' XAF   ' || fmio(v_mt));
        po('  A balance that is an EXACT MULTIPLE of ' || fmio(k_cy_round) || ' is flagged ROUND: it is');
        po('  one whole unmatched leg, not an accumulation of small breaks, and it');
        po('  should be identifiable in a single query rather than reconciled.');

        p_test('CAL-01', 'The transit accounts return to nil');
        p_obj('a transit account carries no position. Whatever it still holds');
        po('                   at the cut off is something that was started and never finished,');
        po('                   and it sits in the balance sheet as an asset or a liability that');
        po('                   belongs to nobody. The test is run on the WHOLE account, not on');
        po('                   the Calypso part of it: the account is what has to come back to');
        po('                   nil, whoever posted on it.');
        p_how('balance, credit minus debit, of each of the three transit');
        po('                   accounts, all entries up to ' || fdt(k_cy_to) || ' whatever their origin.');
        po('                   Tolerance ' || famt(k_tol_abs) || ' XAF.');
        p_verdict('CAL-01', 'Transit account that does not return to nil',
                  v_cnt, 3, v_mt, 'CRITICAL');

        po('');
        po('  HOW TO TICK THE THREE FIGURES ABOVE. Run this, and nothing else. Three');
        po('  things in it are load bearing, and a query missing any one of them will');
        po('  not reproduce the table.');
        po('');
        po('    1. the period runs UP TO the cut off, not from it. A condition');
        po('       trn_dt >= the cut off date measures the movement AFTER it, which');
        po('       is a different question with a different answer.');
        po('    2. NEVER join STTB_ACCOUNT directly on AC_NO. It holds several rows');
        po('       per AC_GL_NO, so a plain join multiplies every entry and inflates');
        po('       the balance by that factor. Take the label with a scalar');
        po('       subquery, as below, or pre aggregate it.');
        po('    3. the upper bound is written as strictly less than the day after,');
        po('       so an entry stamped later in the day on the cut off is not lost.');
        po('');
        po('    SELECT h.ac_no,');
        po('           (SELECT MAX(s.ac_gl_desc) FROM sttb_account s');
        po('             WHERE s.ac_gl_no = h.ac_no) ac_gl_desc,');
        po('           COUNT(*) lines,');
        po('           SUM(CASE h.drcr_ind WHEN ''C'' THEN NVL(h.lcy_amount, 0)');
        po('                               ELSE -NVL(h.lcy_amount, 0) END) balance,');
        po('           SUM(CASE WHEN h.module = ''' || k_cy_mod || ''' AND h.product = '''
           || k_cy_prod || '''');
        po('                     AND LOWER(h.user_id) LIKE ''' || k_cy_upat || '''');
        po('                     AND h.trn_dt >= TO_DATE(''' || fdt(k_cy_from) || ''', ''DD/MM/YYYY'')');
        po('                    THEN CASE h.drcr_ind WHEN ''C'' THEN NVL(h.lcy_amount, 0)');
        po('                                         ELSE -NVL(h.lcy_amount, 0) END');
        po('                    ELSE 0 END) posted_by_calypso');
        po('      FROM actb_history h');
        po('     WHERE h.ac_no IN (''' || k_cy_brg_sec || ''', ''' || k_cy_brg_mm
           || ''', ''' || k_cy_brg_mir || ''')');
        po('       AND h.trn_dt <  TO_DATE(''' || fdt(k_cy_to) || ''', ''DD/MM/YYYY'') + 1');
        po('     GROUP BY h.ac_no');
        po('     ORDER BY h.ac_no;');

        -- -----------------------------------------------------
        print_sub('2.1 b. The same in proportion, and the volume behind it');
        po('  BALANCE OVER GROSS puts the residual in proportion: a balance of a few');
        po('  parts per million of the flow is a handful of unsettled deals, a');
        po('  balance of several percent is a mechanism that does not clear.');
        tbl_head('4,20,16,20,18,26,26,20,16,16',
                 'N#|ACCOUNT|LINES, ALL|OF WHICH CALYPSO|OF WHICH OTHER|GROSS FLOW'
                 || '|BALANCE|BALANCE OVER GROSS|FIRST ENTRY|LAST ENTRY',
                 '|AC_NO|TRN_REF_NO|TRN_REF_NO|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT| '
                 || '|TRN_DT|TRN_DT',
                 'RLRRRRRRLL');
        v_row := 0;
        FOR r IN (SELECT h.ac_no, COUNT(*) nb,
                         SUM(CASE WHEN h.module = k_cy_mod AND h.product = k_cy_prod
                              AND LOWER(h.user_id) LIKE k_cy_upat
                              AND h.trn_dt >= k_cy_from
                                  THEN 1 ELSE 0 END) nb_cy,
                         SUM(ABS(NVL(h.lcy_amount, 0))) gr,
                         SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                             ELSE -NVL(h.lcy_amount, 0) END) sgn,
                         MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                    FROM actb_history h
                   WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                     AND h.trn_dt <  k_cy_to + 1
                   GROUP BY h.ac_no
                   ORDER BY h.ac_no) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fnum(r.nb_cy), 20) || '|'
                || fpadl(fnum(r.nb - r.nb_cy), 18) || '|' || fpadl(fmio(r.gr), 26) || '|'
                || fpadl(famt(r.sgn), 26) || '|'
                || fpadl(fpct(ABS(r.sgn), r.gr), 20) || '|'
                || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|');
        END LOOP;
        tbl_line('4,20,16,20,18,26,26,20,16,16');

        -- -----------------------------------------------------
        print_sub('2.1 c. Who else posts on a transit account');
        po('  Everything on the three bridges that is NOT the interface, broken down');
        po('  by module, product and user. A transit account of an automated');
        po('  interface should be touched by that interface and by nothing else.');
        po('  Anything here is either a manual correction, which has to be');
        po('  documented and approved, or a second producer nobody accounted for.');
        po('  Both are worth a question, and neither is visible if the review looks');
        po('  only at what Calypso posted.');
        tbl_head('4,20,10,12,18,16,26,26,16,16',
                 'N#|ACCOUNT|MODULE|PRODUCT|USER|LINES|GROSS FLOW|BALANCE'
                 || '|FIRST|LAST',
                 '|AC_NO|MODULE|PRODUCT|USER_ID|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT'
                 || '|TRN_DT|TRN_DT',
                 'RLLLLRRRLL');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT h.ac_no, NVL(h.module, '-') mdl, NVL(h.product, '-') prd,
                         NVL(h.user_id, '-') usr, COUNT(*) nb,
                         SUM(ABS(NVL(h.lcy_amount, 0))) gr,
                         SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                             ELSE -NVL(h.lcy_amount, 0) END) sgn,
                         MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                    FROM actb_history h
                   WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                     AND h.trn_dt <  k_cy_to + 1
                     AND NOT (h.module = k_cy_mod AND h.product = k_cy_prod
                              AND LOWER(h.user_id) LIKE k_cy_upat
                              AND h.trn_dt >= k_cy_from)
                   GROUP BY h.ac_no, NVL(h.module, '-'), NVL(h.product, '-'),
                            NVL(h.user_id, '-')
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            v_cnt := v_cnt + r.nb;
            v_mt  := v_mt + ABS(r.sgn);
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                || fpad(r.mdl, 10) || '|' || fpad(r.prd, 12) || '|'
                || fpad(r.usr, 18) || '|' || fpadl(fnum(r.nb), 16) || '|'
                || fpadl(fmio(r.gr), 26) || '|' || fpadl(famt(r.sgn), 26) || '|'
                || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|');
        END LOOP;
        tbl_line('4,20,10,12,18,16,26,26,16,16');
        IF v_row = 0 THEN
            po('  Nothing. The three transit accounts are touched by the interface and');
            po('  by nobody else, which is how it should be.');
        END IF;
        p_test('CAL-14', 'A transit account of the interface is used by the interface only');
        p_obj('these three accounts exist for one automated interface. An');
        po('                   entry on them from another module, another product or a human');
        po('                   user is either a manual correction on the plumbing between two');
        po('                   systems, which must be documented and approved, or a second');
        po('                   producer nobody knew about. Both change what the residual of');
        po('                   the account means, and neither is visible to a review that');
        po('                   looks only at what Calypso posted.');
        p_how('entries on the three transit accounts, up to ' || fdt(k_cy_to) || ', that are');
        po('                   not module ' || k_cy_mod || ' product ' || k_cy_prod
                             || ' by a user matching ' || k_cy_upat || ' on or after');
        po('                   ' || fdt(k_cy_from) || '. Entries predating the go live are counted here');
        po('                   too and shown separately in 2.1 a: they are not the interface');
        po('                   failing, they are what the account already carried.');
        p_verdict('CAL-14', 'Entry on a transit account that the interface did not post',
                  v_cnt, NULL, v_mt, 'HIGH');

        -- -----------------------------------------------------
        print_sub('2.1 d. Is the balance growing, month by month');
        po('  MOVEMENT is what the month added to the account, ALL sources, and');
        po('  RUNNING BALANCE what is left at the end of it. A transit account that');
        po('  works oscillates around nil. One that drifts in the same direction');
        po('  month after month is not a timing difference, it is a leg that is');
        po('  never sent. OF WHICH CALYPSO isolates the interface inside the');
        po('  movement of the month.');
        tbl_head('4,20,14,26,26,30,16',
                 'N#|ACCOUNT|MONTH|MOVEMENT OF THE MONTH|OF WHICH CALYPSO'
                 || '|RUNNING BALANCE|LINES',
                 '|AC_NO|TRN_DT|LCY_AMOUNT|LCY_AMOUNT|LCY_AMOUNT|TRN_REF_NO',
                 'RLLRRRR');
        v_row := 0;
        FOR r IN (SELECT ac_no, mth, mvt, mvt_cy, nb,
                         SUM(mvt) OVER (PARTITION BY ac_no ORDER BY mth) run
                    FROM (SELECT h.ac_no, TO_CHAR(h.trn_dt, 'YYYY-MM') mth,
                                 SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                 ELSE -NVL(h.lcy_amount, 0) END) mvt,
                                 SUM(CASE WHEN h.module = k_cy_mod AND h.product = k_cy_prod
                                  AND LOWER(h.user_id) LIKE k_cy_upat
                                  AND h.trn_dt >= k_cy_from
                                          THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END
                                          ELSE 0 END) mvt_cy,
                                 COUNT(*) nb
                            FROM actb_history h
                           WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                             AND h.trn_dt <  k_cy_to + 1
                           GROUP BY h.ac_no, TO_CHAR(h.trn_dt, 'YYYY-MM'))
                   ORDER BY ac_no, mth) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                || fpad(r.mth, 14) || '|' || fpadl(famt(r.mvt), 26) || '|'
                || fpadl(famt(r.mvt_cy), 26) || '|' || fpadl(famt(r.run), 30) || '|'
                || fpadl(fnum(r.nb), 16) || '|');
        END LOOP;
        tbl_line('4,20,14,26,26,30,16');

        -- -----------------------------------------------------
        print_sub('2.1 e. How old the unmatched items are');
        po('  The balance is broken down by DEAL KEY, the identifier the description');
        po('  carries, because a Calypso deal is scattered over several FLEXCUBE');
        po('  references and only that key puts it back together. On an entry that');
        po('  did not come from the interface the description is ordinary free text');
        po('  and the key is that text, which still groups the item sensibly. An');
        po('  item whose own contribution to a transit account is not nil is');
        po('  unmatched, and its age is counted from its LAST entry to ' || fdt(k_cy_to) || '.');
        po('');
        po('  Read the buckets as a provisioning question. An item a few days old is');
        po('  a settlement in flight. An item six months old is not going to settle');
        po('  by itself, and the balance sheet is carrying it as if it would.');
        tbl_head('4,26,22,20,30,22',
                 'N#|AGE OF THE ITEM|ITEMS|LINES|BALANCE CARRIED|SHARE OF THE BALANCE',
                 '|TRN_DT|FN_GET_DESC|TRN_REF_NO|LCY_AMOUNT| ',
                 'RLRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT bucket, COUNT(*) nb, SUM(nbl) nbl, SUM(resid) mt
                    FROM (SELECT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                     d.ref) dk,
                                 COUNT(*) nbl, SUM(d.sgn) resid,
                                 CASE WHEN TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) <= 30
                                           THEN '1. 0 to 30 days'
                                      WHEN TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) <= 60
                                           THEN '2. 31 to 60 days'
                                      WHEN TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) <= 90
                                           THEN '3. 61 to 90 days'
                                      WHEN TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) <= 180
                                           THEN '4. 91 to 180 days'
                                      WHEN TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) <= 365
                                           THEN '5. 181 to 365 days'
                                      ELSE '6. more than one year' END bucket
                            FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                      h.event_sr_no, h.trn_code, h.related_account,
                                                      h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                      h.event, h.instrument_code, h.related_customer,
                                                      h.value_dt, h.trn_dt, h.related_reference) dsc,
                                         h.trn_ref_no ref, h.trn_dt dt,
                                         CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                         ELSE -NVL(h.lcy_amount, 0) END sgn
                                    FROM actb_history h
                                   WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                                     AND h.trn_dt <  k_cy_to + 1) d
                           GROUP BY NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                         1, k_cy_t_id + k_cy_p0), '|'),
                                        d.ref)
                          HAVING ABS(SUM(d.sgn)) > k_tol_abs)
                   GROUP BY bucket
                   ORDER BY bucket) LOOP
            v_row := v_row + 1;
            v_cnt := v_cnt + r.nb;
            v_mt  := v_mt + ABS(r.mt);
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.bucket, 26) || '|'
                || fpadl(fnum(r.nb), 22) || '|' || fpadl(fnum(r.nbl), 20) || '|'
                || fpadl(famt(r.mt), 30) || '|' || fpadl(fpct(ABS(r.mt), v_mt), 22) || '|');
        END LOOP;
        tbl_line('4,26,22,20,30,22');
        print_kv('Unmatched items in total',            fnum(v_cnt));
        print_kv('Their gross balance, signs ignored',  famt(v_mt));
        po('  The last column is a share of the running total and is therefore only');
        po('  exact on the final line. It is printed so the reader sees at a glance');
        po('  whether the balance sits in the recent buckets or in the old ones.');

        SELECT COUNT(*), NVL(SUM(ABS(resid)), 0) INTO v_cnt, v_mt
          FROM (SELECT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                   1, k_cy_t_id + k_cy_p0), '|'),
                           d.ref) dk,
                       SUM(d.sgn) resid, MAX(d.dt) dlast
                  FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                              h.event_sr_no, h.trn_code, h.related_account,
                                              h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                              h.event, h.instrument_code, h.related_customer,
                                              h.value_dt, h.trn_dt, h.related_reference) dsc,
                               h.trn_ref_no ref, h.trn_dt dt,
                               CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                 ELSE -NVL(h.lcy_amount, 0) END sgn
                          FROM actb_history h
                         WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                           AND h.trn_dt <  k_cy_to + 1) d
                 GROUP BY NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                 1, k_cy_t_id + k_cy_p0), '|'),
                              d.ref)
                HAVING ABS(SUM(d.sgn)) > k_tol_abs
                   AND TRUNC(k_cy_to) - TRUNC(MAX(d.dt)) > k_cy_age);
        p_test('CAL-02', 'No item stays on a transit account beyond the tolerated age');
        p_obj('an unsettled deal is normal for a few days. Beyond that it is a');
        po('                   break: the counter leg was never sent, or was sent under a key');
        po('                   that does not match. Left alone it becomes a permanent line of');
        po('                   the balance sheet that no one can attach to a transaction.');
        p_how('per deal key, signed contribution to the three transit accounts,');
        po('                   all sources. An item whose contribution is not nil and whose last');
        po('                   entry is more than ' || TO_CHAR(k_cy_age) || ' days before ' || fdt(k_cy_to) || ' is a finding.');
        p_verdict('CAL-02', 'Unmatched item on a transit account beyond the tolerated age',
                  v_cnt, NULL, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            cy_head('BALANCE / AGE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT dk, book, ctp, evt, ins, d1, d2, resid,
                               TRUNC(k_cy_to) - TRUNC(d2) age
                          FROM (SELECT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                           d.ref) dk,
                                       MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_book + k_cy_p0), '|')) book,
                                       MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_ctp + k_cy_p0), '|')) ctp,
                                       MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_evt + k_cy_p0), '|')) evt,
                                       MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                           1, k_cy_t_lbl + k_cy_p0), '|')) ins,
                                       MIN(d.dt) d1, MAX(d.dt) d2, SUM(d.sgn) resid
                                  FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                              h.event_sr_no, h.trn_code, h.related_account,
                                                              h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                              h.event, h.instrument_code, h.related_customer,
                                                              h.value_dt, h.trn_dt, h.related_reference) dsc,
                                               h.trn_ref_no ref, h.trn_dt dt,
                                               CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                 ELSE -NVL(h.lcy_amount, 0) END sgn
                                          FROM actb_history h
                                         WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                                           AND h.trn_dt <  k_cy_to + 1) d
                                 GROUP BY NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                                 1, k_cy_t_id + k_cy_p0), '|'),
                                              d.ref))
                         WHERE ABS(resid) > k_tol_abs
                           AND TRUNC(k_cy_to) - TRUNC(d2) > k_cy_age
                         ORDER BY ABS(resid) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                cy_row(v_row, r.dk, r.book, r.ctp, r.evt, r.ins, r.d1, r.d2,
                       famt(r.resid) || ' / ' || fnum(r.age) || ' d');
            END LOOP;
            cy_foot;
        END IF;

        -- -----------------------------------------------------
        print_sub('2.1 f. The unmatched items that carry the most, named');
        po('  The same population without the age filter, ranked by what it carries.');
        po('  SOURCE says whether the item was posted by the interface or by');
        po('  something else, so the reader knows who to ask. ROUND marks a balance');
        po('  that is an exact multiple of ' || fmio(k_cy_round) || ': a single whole leg missing,');
        po('  not a drift, and the fastest of all to resolve.');
        tbl_head('4,26,20,20,28,14,14,12,12',
                 'N#|DEAL KEY|BOOK|COUNTERPARTY|BALANCE CARRIED|FIRST|LAST|SOURCE|ROUND',
                 '|FN_GET_DESC|FN_GET_DESC|FN_GET_DESC|LCY_AMOUNT'
                 || '|TRN_DT|TRN_DT| | ',
                 'RLLLRLLLL');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                               1, k_cy_t_id + k_cy_p0), '|'),
                               d.ref) dk,
                           MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                               1, k_cy_t_book + k_cy_p0), '|')) book,
                           MAX(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                               1, k_cy_t_ctp + k_cy_p0), '|')) ctp,
                           SUM(d.sgn) resid, MIN(d.dt) d1, MAX(d.dt) d2,
                           CASE WHEN MIN(d.cy) = 1 THEN 'CALYPSO'
                                WHEN MAX(d.cy) = 0 THEN 'OTHER'
                                ELSE 'MIXED' END src
                      FROM (SELECT webserve.fn_get_desc(h.module, h.trn_ref_no, h.ac_entry_sr_no,
                                                  h.event_sr_no, h.trn_code, h.related_account,
                                                  h.ac_no, h.ac_branch, h.ac_ccy, h.amount_tag,
                                                  h.event, h.instrument_code, h.related_customer,
                                                  h.value_dt, h.trn_dt, h.related_reference) dsc,
                                   h.trn_ref_no ref, h.trn_dt dt,
                                   CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                     ELSE -NVL(h.lcy_amount, 0) END sgn,
                                   CASE WHEN h.module = k_cy_mod AND h.product = k_cy_prod
                                      AND LOWER(h.user_id) LIKE k_cy_upat
                                      AND h.trn_dt >= k_cy_from
                                        THEN 1 ELSE 0 END cy
                              FROM actb_history h
                             WHERE h.ac_no IN (k_cy_brg_sec, k_cy_brg_mm, k_cy_brg_mir)
                               AND h.trn_dt <  k_cy_to + 1) d
                     GROUP BY NVL(RTRIM(REGEXP_SUBSTR(d.dsc || '|', '[^|]*\|',
                                  1, k_cy_t_id + k_cy_p0), '|'),
                                  d.ref)
                    HAVING ABS(SUM(d.sgn)) > k_tol_abs
                     ORDER BY ABS(SUM(d.sgn)) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.dk, 26) || '|'
                || fpad(r.book, 20) || '|' || fpad(r.ctp, 20) || '|'
                || fpadl(famt(r.resid), 28) || '|' || fpad(fdt(r.d1), 14) || '|'
                || fpad(fdt(r.d2), 14) || '|' || fpad(r.src, 12) || '|'
                || fpad(CASE WHEN MOD(ABS(r.resid), k_cy_round) = 0 THEN 'ROUND'
                             ELSE '-' END, 12) || '|');
        END LOOP;
        tbl_line('4,26,20,20,28,14,14,12,12');

        -- -----------------------------------------------------
        print_sub('2.1 g. The other accounts that have to come back to nil');
        po('  A transit account is not the only one that has to offset. The FX');
        po('  position account and its counter value account must offset each other');
        po('  to the franc; the off balance sheet commitments must be reversed when');
        po('  the deal settles; the collateral pledged must be released when the');
        po('  borrowing is repaid. Each line below is a pair that should net out,');
        po('  and what is left is what is still open at ' || fdt(k_cy_to) || '. These are read on');
        po('  the WHOLE account as well, for the same reason as the bridges.');
        tbl_head('4,46,22,22,28,28,20',
                 'N#|WHAT SHOULD OFFSET|ACCOUNT|OTHER ACCOUNT|BALANCE|OTHER BALANCE'
                 || '|NET LEFT OPEN',
                 '| |AC_NO|AC_NO|LCY_AMOUNT|LCY_AMOUNT| ',
                 'RLLLRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT 1 ord, 'FX position against its counter value' q,
                         k_cy_fx_pos a1, k_cy_fx_cv a2 FROM DUAL UNION ALL
                  SELECT 2, 'Spot bought not received against sold not delivered',
                         k_cy_ob_fxb, k_cy_ob_fxs FROM DUAL UNION ALL
                  SELECT 3, 'Forward sold not delivered against its adjustment',
                         k_cy_ob_fwd, k_cy_ob_adj FROM DUAL UNION ALL
                  SELECT 4, 'Collateral pledged against the general ledger side',
                         k_cy_col_ti, k_cy_col_gl FROM DUAL UNION ALL
                  SELECT 5, 'Client custody, third party pool against client position',
                         k_cy_cus_t, k_cy_cus_c FROM DUAL
                  ORDER BY 1) LOOP
            SELECT NVL(SUM(CASE WHEN h.ac_no = r.a1 THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END), 0),
                   NVL(SUM(CASE WHEN h.ac_no = r.a2 THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END), 0)
              INTO v_tot, v_tot2
              FROM actb_history h
             WHERE h.ac_no IN (r.a1, r.a2)
               AND h.trn_dt <  k_cy_to + 1;
            v_row := v_row + 1;
            IF ABS(v_tot + v_tot2) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(v_tot + v_tot2);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.q, 46) || '|'
                || fpad(r.a1, 22) || '|' || fpad(r.a2, 22) || '|'
                || fpadl(famt(v_tot), 28) || '|' || fpadl(famt(v_tot2), 28) || '|'
                || fpadl(famt(v_tot + v_tot2), 20) || '|');
        END LOOP;
        tbl_line('4,46,22,22,28,28,20');
        p_test('CAL-03', 'The paired accounts of the interface offset each other');
        p_obj('each pair above is a mechanism with two legs: a position and its');
        po('                   counter value, a commitment and its reversal, a pledge and its');
        po('                   release. What does not offset is either a deal still open, which');
        po('                   must be identifiable, or a leg that was never sent.');
        p_how('balance, credit minus debit, of the two accounts of each pair,');
        po('                   added, all entries up to ' || fdt(k_cy_to) || ' whatever their origin. Five');
        po('                   pairs tested, tolerance ' || famt(k_tol_abs) || ' XAF. A net that is not nil is');
        po('                   not automatically wrong on the commitment pairs, where deals');
        po('                   straddling the cut off are normal, but it must be explained deal');
        po('                   by deal, which is what 2.1 f makes possible.');
        p_verdict('CAL-03', 'Paired accounts of the interface that do not offset',
                  v_cnt, 5, v_mt, 'HIGH');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 3 : THE SECURITIES PORTFOLIO DEDUCED FROM THE ENTRIES');
    -- ########################################################################

    print_section('3. WHAT THE BANK HOLDS, READ FROM THE ENTRIES ALONE');
    BEGIN
        po('  There is no contract table behind Calypso. No nominal, no rate, no');
        po('  maturity date is sent to FLEXCUBE. So the portfolio below is not a');
        po('  reconciliation of the accounts against a deal file: it IS the');
        po('  portfolio, rebuilt from the only trace the bank has of it.');
        po('');
        po('  How Calypso carries a security, which decides how it must be read:');
        po('');
        po('    the security is recorded at its FACE VALUE, not at what was paid');
        po('    the difference between price and face, premium or discount, is');
        po('      parked whole in a deferred income account and released day by day');
        po('    the accrued coupon bought with the paper is an asset, not income');
        po('');
        po('  So the balance sheet shows the FACE VALUE of the book. The carrying');
        po('  value is the face value less the unearned income still parked, and the');
        po('  table below computes it.');
        po('');
        po('  Note one inconsistency, visible in the accounts themselves: bonds go');
        po('  to a TRANSACTION account (' || k_cy_bond || ') while bills go to a PLACEMENT');
        po('  account (' || k_cy_bill || '), although both sit in the same Calypso book family.');
        po('  The Calypso classification and the FLEXCUBE chart of accounts do not');
        po('  agree, and no entry can say which of the two is right.');

        -- -----------------------------------------------------
        print_sub('3.1 a. The portfolio at ' || fdt(k_cy_to) || ', line by line');
        po('  BALANCE is credit minus debit, as the general ledger shows it, so the');
        po('  security accounts come out NEGATIVE: they carry a debit balance.');
        po('  POSITION is the same figure in its natural sense, positive when the');
        po('  bank holds something, and it is what the totals below are built on.');
        tbl_head('4,48,20,18,28,28,20',
                 'N#|WHAT IT IS|ACCOUNT|LINES|BALANCE (C minus D)|POSITION|LAST MOVEMENT',
                 '| |AC_NO|TRN_REF_NO|LCY_AMOUNT| |TRN_DT',
                 'RLLRRRL');
        v_row := 0;
        v_tot := 0;
        v_tot2 := 0;
        FOR r IN (SELECT 1 ord, 'Bonds at face value' q, k_cy_bond ac, -1 sg FROM DUAL
                  UNION ALL
                  SELECT 2, 'Treasury bills at face value', k_cy_bill, -1 FROM DUAL
                  UNION ALL
                  SELECT 3, 'Accrued interest receivable', k_cy_accr, -1 FROM DUAL
                  UNION ALL
                  SELECT 4, 'Unearned income parked on the bonds', k_cy_def_b, 1 FROM DUAL
                  UNION ALL
                  SELECT 5, 'Unearned income parked on the bills', k_cy_def_t, 1 FROM DUAL
                  UNION ALL
                  SELECT 6, 'Impairment provision, mark to market', k_cy_prov, 1 FROM DUAL
                  UNION ALL
                  SELECT 7, 'Overnight borrowing, repo liability', k_cy_borrow, 1 FROM DUAL
                  UNION ALL
                  SELECT 8, 'Accrued interest payable on the borrowing', k_cy_debt, 1 FROM DUAL
                  ORDER BY 1) LOOP
            SELECT COUNT(*), NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0), MAX(h.trn_dt)
              INTO v_cnt, v_mt, v_d_max
              FROM actb_history h
             WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
               AND h.ac_no = r.ac;
            v_row := v_row + 1;
            IF r.ord <= 2 THEN
                v_tot := v_tot - v_mt;
            ELSIF r.ord IN (4, 5) THEN
                v_tot2 := v_tot2 + v_mt;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.q, 48) || '|'
                || fpad(r.ac, 20) || '|' || fpadl(fnum(v_cnt), 18) || '|'
                || fpadl(famt(v_mt), 28) || '|' || fpadl(famt(v_mt * r.sg), 28) || '|'
                || fpad(fdt(v_d_max), 20) || '|');
        END LOOP;
        tbl_line('4,48,20,18,28,28,20');
        po('');
        print_kv('Securities at FACE VALUE, position (' || k_cy_bond || ' plus '
                 || k_cy_bill || ')', famt(v_tot) || ' XAF   ' || fmio(v_tot));
        print_kv('Unearned income still parked, position',
                 famt(v_tot2) || ' XAF   ' || fmio(v_tot2));
        print_kv('CARRYING VALUE of the portfolio, face less unearned',
                 famt(v_tot - v_tot2) || ' XAF   ' || fmio(v_tot - v_tot2));
        po('  The published statements must net the two accounts, otherwise the');
        po('  portfolio is presented ' || famt(v_tot2) || ' XAF larger than it is. Confirm with the');
        po('  reporting package that they are netted.');

        -- -----------------------------------------------------
        print_sub('3.1 b. The portfolio month by month');
        po('  BOUGHT is what was debited to the security accounts in the month,');
        po('  SOLD what was credited, and POSITION the running face value at the end');
        po('  of it, in its natural sense. In the balance convention of the bank that');
        po('  same position is the negative of the column, the security accounts');
        po('  carrying a debit balance. That series is the history of the book since');
        po('  the go live.');
        tbl_head('4,14,28,28,30,20,20',
                 'N#|MONTH|BOUGHT IN THE MONTH|SOLD IN THE MONTH|POSITION AT FACE VALUE'
                 || '|DEALS|LINES',
                 '|TRN_DT|LCY_AMOUNT|LCY_AMOUNT|LCY_AMOUNT|FN_GET_DESC|TRN_REF_NO',
                 'RLRRRRR');
        v_row := 0;
        FOR r IN (SELECT mth, dr, cr, nbd, nb,
                         SUM(dr - cr) OVER (ORDER BY mth) pos
                    FROM (SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mth,
                                 SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0)
                                          ELSE 0 END) dr,
                                 SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0)
                                          ELSE 0 END) cr,
                                 COUNT(DISTINCT NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no)) nbd,
                                 COUNT(*) nb
                            FROM actb_history h
                           WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                             AND h.ac_no IN (k_cy_bond, k_cy_bill)
                           GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM'))
                   ORDER BY mth) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mth, 14) || '|'
                || fpadl(fmio(r.dr), 28) || '|' || fpadl(fmio(r.cr), 28) || '|'
                || fpadl(famt(r.pos), 30) || '|' || fpadl(fnum(r.nbd), 20) || '|'
                || fpadl(fnum(r.nb), 20) || '|');
        END LOOP;
        tbl_line('4,14,28,28,30,20,20');

        -- -----------------------------------------------------
        print_sub('3.1 c. The portfolio line by line, security by security');
        po('  THIS IS THE PORTFOLIO. Each line is an instrument as the narrative');
        po('  names it, with what the accounts say the bank still holds of it. FACE');
        po('  is what the security accounts carry, UNEARNED the income still parked');
        po('  against it, CARRYING the difference, ACCRUED the coupon receivable');
        po('  attached to it.');
        po('');
        po('  ALL FOUR ARE POSITIONS, not balances: they are printed in their natural');
        po('  sense, positive when the bank holds something. In the balance');
        po('  convention of the bank, credit minus debit, FACE and ACCRUED are the');
        po('  negatives of what is shown, UNEARNED is as shown.');
        po('');
        po('  An instrument whose FACE is nil has been fully sold or redeemed and is');
        po('  not printed. One whose FACE is nil but which still carries UNEARNED or');
        po('  ACCRUED is printed all the same, in the lower part of the table: that');
        po('  is a position closed on the principal and left open on the income, and');
        po('  it is exactly the kind of residue this report exists to find.');
        tbl_head('4,44,16,28,26,28,24,16,16',
                 'N#|INSTRUMENT|BOOK|FACE VALUE HELD|UNEARNED INCOME|CARRYING VALUE'
                 || '|ACCRUED INTEREST|DEALS|LAST',
                 '|FN_GET_DESC|FN_GET_DESC|LCY_AMOUNT|LCY_AMOUNT| |LCY_AMOUNT'
                 || '|FN_GET_DESC|TRN_DT',
                 'RLLRRRRRL');
        v_row := 0;
        v_tot := 0;
        v_tot2 := 0;
        v_mt  := 0;
        FOR r IN (SELECT ins, book, face, unearned, accrued, nbd, d2 FROM (
                    SELECT RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                           h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                           h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                           h.amount_tag, h.event, h.instrument_code,
                                           h.related_customer, h.value_dt, h.trn_dt,
                                           h.related_reference) || '|', '[^|]*\|',
                                       1, k_cy_t_lbl + k_cy_p0), '|') ins,
                           MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_book + k_cy_p0), '|')) book,
                           SUM(CASE WHEN h.ac_no IN (k_cy_bond, k_cy_bill)
                                    THEN -(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) ELSE 0 END) face,
                           SUM(CASE WHEN h.ac_no IN (k_cy_def_b, k_cy_def_t)
                                    THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END ELSE 0 END) unearned,
                           SUM(CASE WHEN h.ac_no = k_cy_accr
                                    THEN -(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) ELSE 0 END) accrued,
                           COUNT(DISTINCT NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no)) nbd,
                           MAX(h.trn_dt) d2
                      FROM actb_history h
                     WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                       AND h.ac_no IN (k_cy_bond, k_cy_bill, k_cy_def_b,
                                       k_cy_def_t, k_cy_accr)
                     GROUP BY RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                           h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                           h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                           h.amount_tag, h.event, h.instrument_code,
                                           h.related_customer, h.value_dt, h.trn_dt,
                                           h.related_reference) || '|', '[^|]*\|',
                                       1, k_cy_t_lbl + k_cy_p0), '|')
                  ) WHERE ABS(face) > k_tol_abs
                       OR ABS(unearned) > k_tol_abs
                       OR ABS(accrued) > k_tol_abs
                   ORDER BY face DESC, ABS(accrued) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top_all;
            v_tot  := v_tot + r.face;
            v_tot2 := v_tot2 + r.unearned;
            v_mt   := v_mt + r.accrued;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ins, 44) || '|'
                || fpad(r.book, 16) || '|' || fpadl(famt(r.face), 28) || '|'
                || fpadl(famt(r.unearned), 26) || '|'
                || fpadl(famt(r.face - r.unearned), 28) || '|'
                || fpadl(famt(r.accrued), 24) || '|' || fpadl(fnum(r.nbd), 16) || '|'
                || fpad(fdt(r.d2), 16) || '|');
        END LOOP;
        tbl_line('4,44,16,28,26,28,24,16,16');
        print_kv('Lines printed',                          fnum(v_row));
        print_kv('Face value of the lines printed',        famt(v_tot));
        print_kv('Unearned income of the lines printed',   famt(v_tot2));
        print_kv('Accrued interest of the lines printed',  famt(v_mt));
        po('  These totals must agree with 3.1 a. Where they do not, the narrative');
        po('  does not carry the instrument on every line, and the difference is the');
        po('  part of the portfolio that cannot be attributed to a security. That');
        po('  difference is itself the finding, and CAL-04 measures it.');

        SELECT NVL(SUM(CASE WHEN h.ac_no IN (k_cy_bond, k_cy_bill)
                            THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.ac_no IN (k_cy_bond, k_cy_bill)
                             AND TRIM(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                                 h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                                 h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                                 h.amount_tag, h.event, h.instrument_code,
                                                 h.related_customer, h.value_dt, h.trn_dt,
                                                 h.related_reference) || '|', '[^|]*\|',
                                             1, k_cy_t_lbl + k_cy_p0), '|')) IS NULL
                            THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END ELSE 0 END), 0)
          INTO v_tot, v_tot2
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND h.ac_no IN (k_cy_bond, k_cy_bill);
        print_kv('Face value carried with no instrument in the narrative',
                 famt(v_tot2) || '   ' || fpct(ABS(v_tot2), ABS(v_tot)));
        p_test('CAL-04', 'Every security carried can be attached to an instrument');
        p_obj('the portfolio only exists through the narrative. A balance on a');
        po('                   security account that carries no instrument label cannot be');
        po('                   attributed to any paper, cannot be valued, cannot be confirmed');
        po('                   with the custodian and cannot be sold knowingly. It is a');
        po('                   position the bank owns without being able to say what it is.');
        p_how('balance of the security accounts (' || k_cy_bond || ' and ' || k_cy_bill || ')');
        po('                   whose instrument field is empty in the description, against the');
        po('                   total balance of the same accounts.');
        IF ABS(v_tot2) > k_tol_abs THEN v_cnt := 1; ELSE v_cnt := 0; END IF;
        p_verdict('CAL-04', 'Securities carried without an identified instrument',
                  v_cnt, 1, ABS(v_tot2), 'HIGH');

        -- -----------------------------------------------------
        print_sub('3.1 d. Accrued interest, and whether it is ever collected');
        po('  Interest accrues day after day on account ' || k_cy_accr || ' and is cleared when');
        po('  the coupon is cashed. An accrual that grows and is never cleared is');
        po('  income recognised on cash the bank has not received, and it is the');
        po('  single most likely place for an overstatement in this book.');
        po('');
        po('  ACCRUED CARRIED is a position, printed in its natural sense; the');
        po('  balance of the account in credit minus debit is its negative. AGE is');
        po('  counted from the last entry touching that instrument to');
        po('  ' || fdt(k_cy_to) || '. An accrued position whose last movement is old is either a');
        po('  coupon collected outside Calypso and never cleared here, or a coupon');
        po('  that was never collected at all.');
        tbl_head('4,44,16,28,20,16,16,20',
                 'N#|INSTRUMENT|BOOK|ACCRUED CARRIED|LINES|FIRST|LAST|AGE IN DAYS',
                 '|FN_GET_DESC|FN_GET_DESC|LCY_AMOUNT|TRN_REF_NO|TRN_DT|TRN_DT| ',
                 'RLLRRLLR');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT ins, book, accrued, nb, d1, d2,
                           TRUNC(k_cy_to) - TRUNC(d2) age
                      FROM (SELECT RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_lbl + k_cy_p0), '|') ins,
                                   MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                                   h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                                   h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                                   h.amount_tag, h.event, h.instrument_code,
                                                   h.related_customer, h.value_dt, h.trn_dt,
                                                   h.related_reference) || '|', '[^|]*\|',
                                               1, k_cy_t_book + k_cy_p0), '|')) book,
                                   -SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) accrued,
                                   COUNT(*) nb, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                              FROM actb_history h
                             WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                               AND h.ac_no = k_cy_accr
                             GROUP BY RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_lbl + k_cy_p0), '|'))
                     WHERE ABS(accrued) > k_tol_abs
                     ORDER BY ABS(accrued) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ins, 44) || '|'
                || fpad(r.book, 16) || '|' || fpadl(famt(r.accrued), 28) || '|'
                || fpadl(fnum(r.nb), 20) || '|' || fpad(fdt(r.d1), 16) || '|'
                || fpad(fdt(r.d2), 16) || '|' || fpadl(fnum(r.age), 20) || '|');
        END LOOP;
        tbl_line('4,44,16,28,20,16,16,20');

        SELECT COUNT(*), NVL(SUM(ABS(accrued)), 0) INTO v_cnt, v_mt
          FROM (SELECT NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no) dk,
                       SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) accrued,
                       MAX(h.trn_dt) d2
                  FROM actb_history h
                 WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                   AND h.ac_no = k_cy_accr
                 GROUP BY NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no)
                HAVING ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                   AND MONTHS_BETWEEN(k_cy_to, MAX(h.trn_dt)) > k_cy_age_c);
        p_test('CAL-05', 'Accrued interest does not sit uncollected indefinitely');
        p_obj('an accrual is a receivable. It is cleared when the coupon is');
        po('                   cashed. One that has not moved for more than ' || TO_CHAR(k_cy_age_c) || ' months is');
        po('                   income taken to the profit and loss against cash that never');
        po('                   arrived, and it is carried in the balance sheet as an asset.');
        p_how('per Calypso deal key, balance of account ' || k_cy_accr || ' and');
        po('                   date of its last entry. A balance not nil whose last entry is');
        po('                   more than ' || TO_CHAR(k_cy_age_c) || ' months before ' || fdt(k_cy_to) || ' is a finding.');
        p_verdict('CAL-05', 'Accrued interest untouched beyond the tolerated age',
                  v_cnt, v_cy_dl, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            cy_head('ACCRUED / MONTHS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT dk, book, ctp, evt, ins, d1, d2, accrued,
                               ROUND(MONTHS_BETWEEN(k_cy_to, d2), 1) mois
                          FROM (SELECT NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no) dk,
                                       MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_book + k_cy_p0), '|')) book,
                                       MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_ctp + k_cy_p0), '|')) ctp,
                                       MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_evt + k_cy_p0), '|')) evt,
                                       MAX(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_lbl + k_cy_p0), '|')) ins,
                                       MIN(h.trn_dt) d1, MAX(h.trn_dt) d2,
                                       SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) accrued
                                  FROM actb_history h
                                 WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                                   AND h.ac_no = k_cy_accr
                                 GROUP BY NVL(RTRIM(REGEXP_SUBSTR(webserve.fn_get_desc(h.module, h.trn_ref_no,
                                               h.ac_entry_sr_no, h.event_sr_no, h.trn_code,
                                               h.related_account, h.ac_no, h.ac_branch, h.ac_ccy,
                                               h.amount_tag, h.event, h.instrument_code,
                                               h.related_customer, h.value_dt, h.trn_dt,
                                               h.related_reference) || '|', '[^|]*\|',
                                           1, k_cy_t_id + k_cy_p0), '|'),
                                   h.trn_ref_no))
                         WHERE ABS(accrued) > k_tol_abs
                           AND MONTHS_BETWEEN(k_cy_to, d2) > k_cy_age_c
                         ORDER BY ABS(accrued) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                cy_row(v_row, r.dk, r.book, r.ctp, r.evt, r.ins, r.d1, r.d2,
                       famt(r.accrued) || ' / ' || ftx(r.mois) || ' m');
            END LOOP;
            cy_foot;
        END IF;

        -- -----------------------------------------------------
        print_sub('3.1 e. What is still committed off the balance sheet');
        po('  Off balance sheet discipline is the part of this interface that works');
        po('  best: FX commitments, repo collateral and client custody are all');
        po('  recorded and reversed. What is left below is what is still open at');
        po('  ' || fdt(k_cy_to) || ', and each line is a commitment the bank has actually given.');
        tbl_head('4,50,20,20,30,26',
                 'N#|COMMITMENT|ACCOUNT|LINES|STILL COMMITTED|LAST MOVEMENT',
                 '| |AC_NO|TRN_REF_NO|LCY_AMOUNT|TRN_DT',
                 'RLLRRL');
        v_row := 0;
        FOR r IN (SELECT 1 ord, 'Securities pledged as collateral on the repo' q,
                         k_cy_col_ti ac FROM DUAL UNION ALL
                  SELECT 2, 'Collateral given, general ledger side', k_cy_col_gl FROM DUAL
                  UNION ALL
                  SELECT 3, 'Spot currency bought and not yet received', k_cy_ob_fxb FROM DUAL
                  UNION ALL
                  SELECT 4, 'Spot currency sold and not yet delivered', k_cy_ob_fxs FROM DUAL
                  UNION ALL
                  SELECT 5, 'Forward currency sold and not yet delivered', k_cy_ob_fwd FROM DUAL
                  UNION ALL
                  SELECT 6, 'Securities held for third parties', k_cy_cus_t FROM DUAL
                  UNION ALL
                  SELECT 7, 'Securities held for clients', k_cy_cus_c FROM DUAL
                  ORDER BY 1) LOOP
            SELECT COUNT(*), NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0), MAX(h.trn_dt)
              INTO v_cnt, v_mt, v_d_max
              FROM actb_history h
             WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
               AND h.ac_no = r.ac;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.q, 50) || '|'
                || fpad(r.ac, 20) || '|' || fpadl(fnum(v_cnt), 20) || '|'
                || fpadl(famt(v_mt), 30) || '|' || fpad(fdt(v_d_max), 26) || '|');
        END LOOP;
        tbl_line('4,50,20,20,30,26');
        SELECT NVL(SUM(CASE WHEN h.ac_no = k_cy_col_ti THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END
                            ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.ac_no = k_cy_borrow THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END
                            ELSE 0 END), 0)
          INTO v_tot, v_tot2
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND h.ac_no IN (k_cy_col_ti, k_cy_borrow);
        print_kv('Collateral still pledged (' || k_cy_col_ti || ')',       famt(v_tot));
        print_kv('Borrowing still outstanding (' || k_cy_borrow || ')',    famt(v_tot2));
        print_kv('Collateral in excess of the borrowing',              famt(v_tot - v_tot2));
        p_test('CAL-06', 'The collateral pledged is released when the borrowing is repaid');
        p_obj('securities pledged against a repo must come back to the bank');
        po('                   the day the cash is repaid. Collateral still committed with no');
        po('                   borrowing behind it is paper the bank cannot use, sell or');
        po('                   pledge again, and that nothing in the balance sheet explains.');
        p_how('balance of ' || k_cy_col_ti || ' against the outstanding');
        po('                   liability on ' || k_cy_borrow || '. Some excess is normal, a repo being');
        po('                   over collateralised; a large one, or collateral with no');
        po('                   borrowing at all, is not.');
        IF v_tot2 <= k_tol_abs AND ABS(v_tot) > k_tol_abs THEN
            v_cnt := 1;
        ELSE
            v_cnt := 0;
        END IF;
        p_verdict('CAL-06', 'Collateral still pledged with no borrowing behind it',
                  v_cnt, 1, ABS(v_tot), 'HIGH');

        -- -----------------------------------------------------
        print_sub('3.1 f. What the book earned and what it cost');
        po('  Signed movement of the income and expense accounts over the period.');
        po('  These are BALANCES, credit minus debit, and they are the only');
        po('  ones that mean anything: section 4.1 shows why the gross totals of');
        po('  the same accounts are inflated by a factor of eighty or more.');
        tbl_head('4,50,20,20,30,26',
                 'N#|INCOME OR EXPENSE|ACCOUNT|LINES|BALANCE (C minus D)|LAST MOVEMENT',
                 '| |AC_NO|TRN_REF_NO|LCY_AMOUNT|TRN_DT',
                 'RLLRRL');
        v_row := 0;
        v_tot := 0;
        FOR r IN (SELECT 1 ord, 'Bond income, accrued' q, k_cy_inc_b ac, 1 sg FROM DUAL
                  UNION ALL
                  SELECT 2, 'Bond income, realised on disposal', k_cy_inc_br, 1 FROM DUAL
                  UNION ALL
                  SELECT 3, 'Treasury bill income, accrued', k_cy_inc_t, 1 FROM DUAL
                  UNION ALL
                  SELECT 4, 'Treasury bill income, realised on disposal', k_cy_inc_tr, 1 FROM DUAL
                  UNION ALL
                  SELECT 5, 'Portfolio management commission earned', k_cy_com_pf, 1 FROM DUAL
                  UNION ALL
                  SELECT 6, 'Interest expense on the money market', k_cy_exp_mm, -1 FROM DUAL
                  UNION ALL
                  SELECT 7, 'Commission paid on FX purchases', k_cy_com_fx, -1 FROM DUAL
                  ORDER BY 1) LOOP
            SELECT COUNT(*), NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0), MAX(h.trn_dt)
              INTO v_cnt, v_mt, v_d_max
              FROM actb_history h
             WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
               AND h.ac_no = r.ac;
            v_row := v_row + 1;
            v_tot := v_tot + v_mt;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.q, 50) || '|'
                || fpad(r.ac, 20) || '|' || fpadl(fnum(v_cnt), 20) || '|'
                || fpadl(famt(v_mt), 30) || '|' || fpad(fdt(v_d_max), 26) || '|');
        END LOOP;
        tbl_line('4,50,20,20,30,26');
        print_kv('Net result of the Calypso book over the period',
                 famt(v_tot) || ' XAF   ' || fmio(v_tot));
        po('  In credit minus debit an income account comes out POSITIVE and an');
        po('  expense account NEGATIVE, so the net result above is simply their sum,');
        po('  with no sign to turn round: a positive figure is a profit.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 4 : THE ENGINE, THE CALENDAR AND THE REMAINING CONTROLS');
    -- ########################################################################

    print_section('4. THE MECHANICS OF THE INTERFACE');
    BEGIN

        -- -----------------------------------------------------
        print_sub('4.1 The post and reverse engine, and why gross totals lie');
        po('  Every business day Calypso posts the FULL CUMULATIVE accrual of each');
        po('  position, and the next business day it reverses that whole entry');
        po('  before posting the new cumulative figure. The net accounting result is');
        po('  correct. The gross flows are enormous and mean nothing.');
        po('');
        po('  RATIO below is gross movement over the absolute net. A ratio of two is');
        po('  an account that is debited and credited normally. A ratio of eighty is');
        po('  an account driven by the engine, where any statistic, ratio, key');
        po('  indicator or tax return built on gross debit and credit totals is');
        po('  wrong by two orders of magnitude.');
        tbl_head('4,20,38,20,28,26,16,16',
                 'N#|ACCOUNT|ACCOUNT NAME|LINES|GROSS MOVEMENT|NET MOVEMENT|RATIO|VERDICT',
                 '|AC_NO|AC_GL_DESC|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT| | ',
                 'RLLRRRRR');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT * FROM (
                    SELECT h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                           SUM(ABS(NVL(h.lcy_amount, 0))) gr,
                           SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) net
                      FROM actb_history h
                      LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                   FROM sttb_account GROUP BY ac_gl_no) s
                             ON s.ac_gl_no = h.ac_no
                     WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                     GROUP BY h.ac_no
                    HAVING SUM(ABS(NVL(h.lcy_amount, 0)))
                           > k_cy_infl * ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END))
                       AND SUM(ABS(NVL(h.lcy_amount, 0))) > 0
                     ORDER BY SUM(ABS(NVL(h.lcy_amount, 0))) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            v_cnt := v_cnt + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                || fpad(r.lib, 38) || '|' || fpadl(fnum(r.nb), 20) || '|'
                || fpadl(fmio(r.gr), 28) || '|' || fpadl(fmio(r.net), 26) || '|'
                || fpadl(CASE WHEN ABS(r.net) <= k_tol_abs THEN 'nets to nil'
                              ELSE fnum(ROUND(r.gr / ABS(r.net))) END, 16) || '|'
                || fpadl('READ NET ONLY', 16) || '|');
        END LOOP;
        tbl_line('4,20,38,20,28,26,16,16');
        SELECT COUNT(*) INTO v_cnt
          FROM (SELECT h.ac_no
                  FROM actb_history h
                 WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                 GROUP BY h.ac_no
                HAVING SUM(ABS(NVL(h.lcy_amount, 0)))
                       > k_cy_infl * ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END))
                   AND SUM(ABS(NVL(h.lcy_amount, 0))) > 0);
        p_test('CAL-07', 'Gross totals are not usable as statistics on these accounts');
        p_obj('the post and reverse engine inflates every gross total it');
        po('                   touches. This control does not say the accounting is wrong, it');
        po('                   says which accounts must never be read gross. Anyone building a');
        po('                   report, a ratio or a declaration on the gross debit and credit');
        po('                   of the accounts listed above is producing a false figure.');
        p_how('per account, gross movement over the absolute net movement. An');
        po('                   account whose gross exceeds ' || TO_CHAR(k_cy_infl) || ' times its net is listed. The');
        po('                   count is informative, not an accounting error.');
        p_verdict('CAL-07', 'Account whose gross movement is not a usable statistic',
                  v_cnt, v_cy_nb, NULL, 'MEDIUM');

        -- -----------------------------------------------------
        print_sub('4.2 The revaluation of the portfolio');
        po('  A book carried at fair value has to be revalued. The impairment');
        po('  provision account ' || k_cy_prov || ' is where Calypso posts that revaluation.');
        po('  If it stops moving, the portfolio stops being marked to market, and');
        po('  the balance sheet keeps showing a price that is no longer the price.');
        SELECT COUNT(*), NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0),
               MIN(h.trn_dt), MAX(h.trn_dt), COUNT(DISTINCT TRUNC(h.trn_dt))
          INTO v_cnt2, v_mt, v_cy_d1, v_d_max, v_cnt3
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND h.ac_no = k_cy_prov;
        print_kv('Revaluation lines posted (' || k_cy_prov || ')', fnum(v_cnt2));
        print_kv('Distinct dates on which the portfolio was revalued', fnum(v_cnt3));
        print_kv('First revaluation',  fdt(v_cy_d1));
        print_kv('Last revaluation',   fdt(v_d_max));
        print_kv('Balance left on the provision account', famt(v_mt));
        print_kv('Months since the last revaluation, at ' || fdt(k_cy_to),
                 CASE WHEN v_d_max IS NULL THEN 'never revalued'
                      ELSE ftx(ROUND(MONTHS_BETWEEN(k_cy_to, v_d_max), 1)) || ' months' END);
        p_test('CAL-08', 'The portfolio is still being marked to market');
        p_obj('a portfolio held at fair value that is not revalued is carried');
        po('                   at a price nobody has checked since the day the engine stopped.');
        po('                   The unrecognised gain or loss grows silently, and no entry in');
        po('                   the ledger will ever reveal its size.');
        p_how('date of the last movement on the provision account ' || k_cy_prov || ',');
        po('                   compared with the cut off ' || fdt(k_cy_to) || '. More than ' || TO_CHAR(k_cy_val_m) || ' months without a');
        po('                   revaluation is a finding, and no revaluation at all is the same');
        po('                   finding in its worst form.');
        IF v_d_max IS NULL
           OR MONTHS_BETWEEN(k_cy_to, v_d_max) > k_cy_val_m THEN
            v_cnt := 1;
        ELSE
            v_cnt := 0;
        END IF;
        SELECT NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0) INTO v_tot
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND h.ac_no IN (k_cy_bond, k_cy_bill);
        p_verdict('CAL-08', 'Portfolio not revalued within the tolerated period',
                  v_cnt, 1, ABS(v_tot), 'CRITICAL');
        IF v_cnt > 0 THEN
            po('     The amount carried by this finding is the FACE VALUE OF THE WHOLE');
            po('     PORTFOLIO, ' || fmio(v_tot) || ', because that is the exposure carried at a');
            po('     price that has not been challenged. Where the revaluation was');
            po('     posted, check as well which account it credited: a fair value');
            po('     book revalued through the income statement rather than through');
            po('     equity is a second finding, and one the entries can show but not');
            po('     resolve on their own.');
        END IF;

        -- -----------------------------------------------------
        print_sub('4.3 The calendar, the four eyes and the value dates');
        po('  Three checks on the mechanics of the interface itself: does every day');
        po('  balance, does it post when the bank is closed, and who approves it.');

        SELECT COUNT(*), NVL(SUM(ABS(sgn)), 0) INTO v_cnt, v_mt
          FROM (SELECT TRUNC(h.trn_dt) dt, SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) sgn
                  FROM actb_history h
                 WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                 GROUP BY TRUNC(h.trn_dt)
                HAVING ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs);
        p_test('CAL-09', 'Every posting day balances on its own');
        p_obj('an interface sends a day as a whole. If the debits and the');
        po('                   credits of one day do not match, a leg was lost in transmission,');
        po('                   and the general ledger absorbed the difference silently.');
        p_how('signed total of the Calypso lines per TRN_DT, tolerance ' || famt(k_tol_abs));
        po('                   XAF. The whole population balancing is not enough: two days can');
        po('                   compensate each other and both be wrong.');
        p_verdict('CAL-09', 'Posting day whose entries do not balance',
                  v_cnt, NULL, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            tbl_head('4,20,22,30,30',
                     'N#|POSTING DAY|LINES|GROSS AMOUNT|OUT OF BALANCE BY',
                     '|TRN_DT|TRN_REF_NO|LCY_AMOUNT|LCY_AMOUNT',
                     'RLRRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT TRUNC(h.trn_dt) dt, COUNT(*) nb,
                               SUM(ABS(NVL(h.lcy_amount, 0))) gr,
                               SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) sgn
                          FROM actb_history h
                         WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                         GROUP BY TRUNC(h.trn_dt)
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.dt), 20) || '|'
                    || fpadl(fnum(r.nb), 22) || '|' || fpadl(fmio(r.gr), 30) || '|'
                    || fpadl(famt(r.sgn), 30) || '|');
            END LOOP;
            tbl_line('4,20,22,30,30');
        END IF;

        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND TRUNC(h.trn_dt) - TRUNC(h.trn_dt, 'IW') >= 5;
        p_test('CAL-10', 'The interface posts on business days only');
        p_obj('an accounting day that does not exist in the bank calendar is a');
        po('                   day nobody reconciles, nobody reviews and nobody closes. It is');
        po('                   also the classic window for an entry that is meant not to be');
        po('                   seen.');
        p_how('Calypso lines whose TRN_DT falls on a Saturday or a Sunday,');
        po('                   computed from the ISO week so that no language setting can');
        po('                   change the result.');
        p_verdict('CAL-10', 'Calypso entry posted on a Saturday or a Sunday',
                  v_cnt, v_cy_nb, v_mt, 'MEDIUM');

        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND NVL(h.auth_id, ' ') = NVL(h.user_id, ' ');
        p_test('CAL-11', 'Who approves what the interface posts');
        p_obj('an automated interface entering and approving its own entries is');
        po('                   acceptable in itself, but it means the four eyes control does');
        po('                   not exist inside FLEXCUBE. It exists, if it exists, inside');
        po('                   Calypso, where nobody in accounting can see it. This control');
        po('                   measures the size of that blind area rather than condemning it.');
        p_how('Calypso lines whose AUTH_ID equals USER_ID. The expected');
        po('                   result is the whole population; what matters is that the reader');
        po('                   knows it, and that evidence of the approval workflow inside');
        po('                   Calypso is obtained and kept in the file.');
        p_verdict('CAL-11', 'Entry entered and approved by the same identity',
                  v_cnt, v_cy_nb, v_mt, 'MEDIUM');

        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND h.value_dt IS NOT NULL
           AND TRUNC(h.trn_dt) - TRUNC(h.value_dt) > k_cy_back_d;
        p_test('CAL-12', 'The value date is not pushed back into a closed period');
        p_obj('an entry posted today with a value date well in the past moves');
        po('                   interest, and sometimes a result, into a month that has already');
        po('                   been reported. On an automated interface it also signals a');
        po('                   replay or a late catch up that nobody validated.');
        p_how('Calypso lines whose VALUE_DT is more than ' || TO_CHAR(k_cy_back_d) || ' days before');
        po('                   TRN_DT.');
        p_verdict('CAL-12', 'Entry back valued beyond the tolerated delay',
                  v_cnt, v_cy_nb, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            tbl_head('4,26,18,18,14,22,20,30',
                     'N#|FLEXCUBE REFERENCE|POSTED ON|VALUE DATE|DAYS BACK|ACCOUNT'
                     || '|DIRECTION|AMOUNT',
                     '|TRN_REF_NO|TRN_DT|VALUE_DT| |AC_NO|DRCR_IND|LCY_AMOUNT',
                     'RLLLRLLR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.trn_dt dt, h.value_dt vd,
                               TRUNC(h.trn_dt) - TRUNC(h.value_dt) nbj,
                               h.ac_no, h.drcr_ind, NVL(h.lcy_amount, 0) mt
                          FROM actb_history h
                         WHERE h.module = k_cy_mod
                                   AND h.product = k_cy_prod
                                   AND LOWER(h.user_id) LIKE k_cy_upat
                                   AND h.trn_dt >= k_cy_from
                                   AND h.trn_dt <  k_cy_to + 1
                           AND h.value_dt IS NOT NULL
                           AND TRUNC(h.trn_dt) - TRUNC(h.value_dt) > k_cy_back_d
                         ORDER BY TRUNC(h.trn_dt) - TRUNC(h.value_dt) DESC,
                                  NVL(h.lcy_amount, 0) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 26) || '|'
                    || fpad(fdt(r.dt), 18) || '|' || fpad(fdt(r.vd), 18) || '|'
                    || fpadl(fnum(r.nbj), 14) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(r.drcr_ind, 20) || '|' || fpadl(famt(r.mt), 30) || '|');
            END LOOP;
            tbl_line('4,26,18,18,14,22,20,30');
        END IF;

        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_cy_mod
                   AND h.product = k_cy_prod
                   AND LOWER(h.user_id) LIKE k_cy_upat
                   AND h.trn_dt >= k_cy_from
                   AND h.trn_dt <  k_cy_to + 1
           AND SUBSTR(h.ac_no, 1, LENGTH(k_cy_excl)) = k_cy_excl;
        p_test('CAL-13', 'The account family left out of the first extract');
        p_obj('the extract this analysis was first built on filtered out the');
        po('                   accounts beginning with ' || k_cy_excl || '. If Calypso posts there, part of its');
        po('                   behaviour was invisible, and every conclusion drawn from that');
        po('                   extract was drawn on an incomplete population. This control');
        po('                   settles the question one way or the other.');
        p_how('Calypso lines whose AC_NO begins with ' || k_cy_excl || '. A count above nil');
        po('                   is not an accounting error: it is an extraction error, and the');
        po('                   analysis has to be redone without the filter.');
        p_verdict('CAL-13', 'Calypso entry on the account family left out of the extract',
                  v_cnt, v_cy_nb, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            tbl_head('4,20,44,22,30,18,18',
                     'N#|ACCOUNT|ACCOUNT NAME|LINES|BALANCE (C minus D)|FIRST|LAST',
                     '|AC_NO|AC_GL_DESC|TRN_REF_NO|LCY_AMOUNT|TRN_DT|TRN_DT',
                     'RLLRRLL');
            v_row := 0;
            FOR r IN (SELECT h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                             SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END) sgn,
                             MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                        FROM actb_history h
                        LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                     FROM sttb_account GROUP BY ac_gl_no) s
                               ON s.ac_gl_no = h.ac_no
                       WHERE h.module = k_cy_mod
                               AND h.product = k_cy_prod
                               AND LOWER(h.user_id) LIKE k_cy_upat
                               AND h.trn_dt >= k_cy_from
                               AND h.trn_dt <  k_cy_to + 1
                         AND SUBSTR(h.ac_no, 1, LENGTH(k_cy_excl)) = k_cy_excl
                       GROUP BY h.ac_no
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > k_top;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|'
                    || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 22) || '|'
                    || fpadl(famt(r.sgn), 30) || '|' || fpad(fdt(r.d1), 18) || '|'
                    || fpad(fdt(r.d2), 18) || '|');
            END LOOP;
            tbl_line('4,20,44,22,30,18,18');
        END IF;

        -- -----------------------------------------------------
        print_sub('4.4 What the entries cannot say, and what to ask Calypso');
        po('  This part reverse engineers a front office system from its accounting');
        po('  output. Some things are genuinely unknowable that way, and no control');
        po('  should ever be built on an assumption about them. They are listed here');
        po('  so the file records what was not testable, and why.');
        po('');
        po('  1. DEAL TERMS. No nominal, rate, value date or maturity is sent. The');
        po('     instrument label carries a maturity and a coupon inside free text,');
        po('     but free text is not a field and cannot be recomputed. Ask whether');
        po('     the interface can transmit the structured attributes of the deal.');
        po('  2. QUANTITIES. Amounts only, never a number of securities. A position');
        po('     cannot be reconciled in units against a custodian statement. Ask');
        po('     where the securities position report is produced and who reconciles');
        po('     it to ' || k_cy_bond || ' and ' || k_cy_bill || '.');
        po('  3. CANCELLATIONS. Ask how a cancelled or amended deal reaches');
        po('     FLEXCUBE. If cancellations are netted before the interface, the');
        po('     ledger will never show them and no control here can.');
        po('  4. VALUATION. The entries show when the portfolio was revalued, never');
        po('     against what price. Ask for the price source and the model.');
        po('  5. THE MAPPING. The Calypso books are a front office convention. Their');
        po('     mapping to the chart of accounts is invisible from the ledger and,');
        po('     as part 3 shows, not internally consistent. Ask for the documented');
        po('     mapping table between books and general ledger accounts.');
        po('  6. COUNTERPARTIES. The narrative carries a counterparty code with no');
        po('     link to the FLEXCUBE customer file except on client sales. Ask for');
        po('     the counterparty mapping table.');
        po('  7. THE NARRATIVE CONTRACT. Section 1.3 measures how many formats are');
        po('     in the data. Any change to that string silently breaks every');
        po('     reconciliation built on it, and has already happened once without');
        po('     notice. Ask for the interface contract to be written down and');
        po('     versioned, and for accounting to be told before it changes.');
        po('');
        po('  RECOMMENDATION. Ask for a monthly Calypso position and profit and loss');
        po('  report delivered directly to accounting. Without it this whole part');
        po('  has to be rebuilt from scratch every time the front office changes');
        po('  something, and the bank will keep learning about those changes from');
        po('  the accounts rather than from the system that made them.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 5 : SUMMARY OF ALL TESTS');
    -- ########################################################################

    print_section('5. SUMMARY');
    BEGIN
        po('  Every control run, in the order of the report. CASES is the number of');
        po('  occurrences found, BASE the population it is measured against, and');
        po('  AMOUNT the financial exposure where it can be quantified.');
        po('');
        tbl_head('4,14,64,14,16,10,26,12,16',
                 'N#|CODE|CONTROL|CASES|BASE|SHARE|AMOUNT|SEVERITY|VERDICT',
                 '| | | | | | | | ',
                 'RLLRRRRLR');
        FOR i IN 1 .. g_n LOOP
            po('  |' || fpadl(TO_CHAR(i), 4) || '|' || fpad(g_res(i).code, 14) || '|'
                || fpad(g_res(i).lib, 64) || '|' || fpadl(fnum(g_res(i).nb), 14) || '|'
                || fpadl(CASE WHEN NVL(g_res(i).base, 0) > 0
                              THEN fnum(g_res(i).base) ELSE '-' END, 16) || '|'
                || fpadl(CASE WHEN NVL(g_res(i).base, 0) > 0
                              THEN fpct(g_res(i).nb, g_res(i).base) ELSE '-' END, 10) || '|'
                || fpadl(CASE WHEN g_res(i).mt IS NULL THEN '-'
                              ELSE fmio(g_res(i).mt) END, 26) || '|'
                || fpad(CASE WHEN g_res(i).nb = 0 THEN '-' ELSE g_res(i).crit END, 12) || '|'
                || fpadl(CASE WHEN g_res(i).nb = 0 THEN 'PASS'
                              WHEN g_res(i).crit = 'INFO' THEN 'INFORMATION'
                              ELSE 'FINDING' END, 16) || '|');
        END LOOP;
        tbl_line('4,14,64,14,16,10,26,12,16');

        print_sub('5.1 Headline counts');
        print_kv('Controls run',                       fnum(g_n));
        print_kv('Controls with no finding',           fnum(g_n - g_find));
        print_kv('Controls raising at least one case', fnum(g_find));
        print_kv('Of which CRITICAL or HIGH',          fnum(g_sev));

        print_sub('5.2 Findings by severity');
        tbl_head('4,22,18,18,28',
                 'N#|SEVERITY|CONTROLS|CASES|CUMULATIVE AMOUNT',
                 '| | | | ',
                 'RLRRR');
        v_row := 0;
        FOR r IN (SELECT 1 ord, 'CRITICAL' c FROM DUAL UNION ALL
                  SELECT 2, 'HIGH' FROM DUAL UNION ALL
                  SELECT 3, 'MEDIUM' FROM DUAL UNION ALL
                  SELECT 4, 'LOW' FROM DUAL UNION ALL
                  SELECT 5, 'INFO' FROM DUAL
                  ORDER BY 1) LOOP
            v_cnt := 0;
            v_cnt2 := 0;
            v_mt := 0;
            FOR i IN 1 .. g_n LOOP
                IF g_res(i).crit = r.c AND g_res(i).nb > 0 THEN
                    v_cnt  := v_cnt + 1;
                    v_cnt2 := v_cnt2 + g_res(i).nb;
                    v_mt   := v_mt + NVL(g_res(i).mt, 0);
                END IF;
            END LOOP;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.c, 22) || '|'
                || fpadl(fnum(v_cnt), 18) || '|' || fpadl(fnum(v_cnt2), 18) || '|'
                || fpadl(fmio(v_mt), 28) || '|');
        END LOOP;
        tbl_line('4,22,18,18,28');

        print_sub('5.3 What each control covers');
        tbl_head('4,12,60,16,26',
                 'N#|CODE|WHAT IT TESTS|PART|CLOSED IN THE DATABASE',
                 '| | | | ',
                 'RLLLL');
        v_row := 0;
        FOR r IN (SELECT n, cd, obj, prt, closed FROM (
                    SELECT 1 n, 'CAL-01' cd, 'The bridge accounts return to nil' obj,
                           '2' prt, 'yes' closed FROM DUAL
                    UNION ALL SELECT 2, 'CAL-02', 'No bridge item beyond the tolerated age',
                           '2', 'yes' FROM DUAL
                    UNION ALL SELECT 3, 'CAL-03', 'The paired accounts offset each other',
                           '2', 'yes' FROM DUAL
                    UNION ALL SELECT 4, 'CAL-04', 'Every security is attached to an instrument',
                           '3', 'yes' FROM DUAL
                    UNION ALL SELECT 5, 'CAL-05', 'Accrued interest is not left uncollected',
                           '3', 'yes' FROM DUAL
                    UNION ALL SELECT 6, 'CAL-06', 'Collateral is released with the borrowing',
                           '3', 'yes' FROM DUAL
                    UNION ALL SELECT 7, 'CAL-07', 'Which gross totals are not usable',
                           '4', 'yes, informative' FROM DUAL
                    UNION ALL SELECT 8, 'CAL-08', 'The portfolio is still marked to market',
                           '4', 'partly, price source needed' FROM DUAL
                    UNION ALL SELECT 9, 'CAL-09', 'Every posting day balances on its own',
                           '4', 'yes' FROM DUAL
                    UNION ALL SELECT 10, 'CAL-10', 'The interface posts on business days only',
                           '4', 'yes' FROM DUAL
                    UNION ALL SELECT 11, 'CAL-11', 'Who approves what the interface posts',
                           '4', 'no, evidence needed from Calypso' FROM DUAL
                    UNION ALL SELECT 12, 'CAL-12', 'The value date is not pushed back',
                           '4', 'yes' FROM DUAL
                    UNION ALL SELECT 13, 'CAL-13', 'The account family left out of the extract',
                           '4', 'yes' FROM DUAL
                    UNION ALL SELECT 14, 'CAL-14', 'A transit account is used by the interface only',
                           '2', 'yes' FROM DUAL
                  ) ORDER BY n) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cd, 12) || '|'
                || fpad(r.obj, 60) || '|' || fpad(r.prt, 16) || '|'
                || fpad(r.closed, 26) || '|');
        END LOOP;
        tbl_line('4,12,60,16,26');
        po('');
        po('  None of the 56 controls of audit_securities.sql appears here. They');
        po('  all confront the entries with the terms of a contract, and Calypso');
        po('  sends no contract. The CAL family tests what can be tested without');
        po('  one.');

        print_sub('5.4 Scope reviewed');
        print_kv('Interface user',           k_cy_user);
        print_kv('Module, product, tag',     k_cy_mod || ' / ' || k_cy_prod || ' / ' || k_cy_tag);
        print_kv('Period reviewed',          fdt(k_cy_from) || ' to ' || fdt(k_cy_to));
        print_kv('Entry lines',              fnum(v_cy_nb));
        print_kv('Distinct deal keys',       fnum(v_cy_dl));
        print_kv('Gross flow',               famt(v_cy_mt) || ' XAF (' || fmio(v_cy_mt) || ')');
        print_kv('First entry, last entry',  fdt(v_cy_d1) || ' to ' || fdt(v_cy_d2));

        print_sub('5.5 Limitations of the review');
        po('  1. Part 2 reads the transit accounts on the WHOLE account, every');
        po('     entry whatever its origin, because an account has to return to nil');
        po('     whoever posted on it. Everywhere else the population is the');
        po('     interface only. Section 2.1 a splits the balance into what Calypso');
        po('     posted, what anything else posted and what predated the go live, so');
        po('     the two scopes can be tied together on the page.');
        po('  2. Calypso posts entries and creates no contract. Nothing here can be');
        po('     reconciled to a deal file, because none is sent. The portfolio of');
        po('     part 3 IS the portfolio, not a control against one.');
        po('  3. The business information lives in the description returned by');
        po('     webserve.FN_GET_DESC, which is code the audit does not control.');
        po('     Section 1.3 measures how far it can be trusted. If it shows more');
        po('     than one field count, the positional reading is right for one');
        po('     format only, and the token offset k_cy_p0 has to be set for the');
        po('     format that matters before the figures are used.');
        po('  4. The review is cut off at ' || fdt(k_cy_to) || '. Residual balances, positions and');
        po('     ages are all read at that date, and section 1.1 a prints how much');
        po('     activity lies beyond it.');
        po('  5. Gross totals on the accounts of section 4.1 are inflated by the');
        po('     post and reverse engine and must never be used as statistics.');
        po('  6. Seven questions cannot be answered from the ledger at all. They are');
        po('     listed in section 4.4 with what has to be asked of the front');
        po('     office. None of them should be closed on an assumption.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po('');
    po(v_sep);
    po('   REVIEW COMPLETED - ' || fdth(SYSDATE));
    po('   ' || fnum(g_n) || ' controls run, ' || fnum(g_find) || ' with findings, '
        || fnum(g_sev) || ' of them CRITICAL or HIGH.');
    po(v_sep);

END;
/

-- SPOOL OFF
