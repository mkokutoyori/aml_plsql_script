-- ============================================================================
-- SECURITIES PORTFOLIO AUDIT SCRIPT - MONEY MARKET MODULE (MM)
-- ============================================================================
--
-- PURPOSE
--   Audit of the bank's securities portfolio held in FLEXCUBE: sovereign
--   paper (treasury bonds and treasury bills) booked in the MM module.
--   The report is produced in English.
--
--   The script has two faces. It DESCRIBES the portfolio and the accounting
--   scheme actually applied, then it TESTS a reference framework of 56
--   controls covering the life cycle of a security from subscription to
--   redemption, the integrity of the accounting, and the static data.
--
--   Every finding names the securities concerned. A control that raises an
--   exception always prints the contracts behind it, with their reference,
--   product, issuer, nominal, rate, booking date, value date and maturity.
--
-- COLUMN NAMING CONVENTION
--   Every table prints its heading on two lines: the business label first,
--   then the DATABASE COLUMN NAME between parentheses. A reader can
--   therefore rebuild any figure of this report with a query of their own.
--
-- HOW TO RUN
--   Single anonymous PL/SQL block, read only, no DDL, no COMMIT: it runs
--   with a plain read grant. One pass, one terminating slash.
--   SQL Developer : open, F5. SQL*Plus : @audit_securities.sql
--   No substitution variable and no bind variable, so no input window
--   opens at launch.
--
-- REPORT LAYOUT
--   PART 0  - scope, parameters, chart of accounts, legend
--   PART 1  - THE BANK'S SECURITIES PORTFOLIO                 (to be added)
--   PART 2  - SECURITIES LIFE CYCLE      LC-01 to LC-06, LIF-01 to LIF-07
--   PART 3  - EXTRACTION INTEGRITY       EXT-01 to EXT-04
--   PART 4  - DOUBLE ENTRY               DBL-01 to DBL-04
--   PART 5  - ACCOUNT MAPPING            MAP-01 to MAP-06
--   PART 6  - INTEREST ACCURACY          INT-01 to INT-07
--   PART 7  - REVERSALS AND AMENDMENTS   REV-01 to REV-06
--   PART 8  - CASH RECONCILIATION        CSH-01 to CSH-03
--   PART 9  - PERIOD END                 CUT-01 to CUT-05
--   PART 10 - CLASSIFICATION             CLS-01 to CLS-03
--   PART 11 - STATIC DATA                STA-01 to STA-05
--   PART 12 - SUMMARY OF ALL TESTS
--
-- SCOPE CONVENTION
--   LDTB_CONTRACT_MASTER holds one row per contract VERSION. The script
--   keeps the LAST VERSION of every contract reference everywhere:
--       m.module = 'MM'
--       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
--                            WHERE v.contract_ref_no = m.contract_ref_no)
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
-- SPOOL securities_audit_report.txt

DECLARE

    -- ========================================================================
    -- ENGAGEMENT PARAMETERS - the only values to adjust
    -- ========================================================================

    -- Reporting date and audited period (on BOOKING_DATE)
    k_asof        DATE := TRUNC(SYSDATE);
    k_dt_from     DATE := TO_DATE('01/01/2000', 'DD/MM/YYYY');
    k_dt_to       DATE := TO_DATE('31/12/2099', 'DD/MM/YYYY');

    -- Recalculation tolerances
    k_tol_abs     NUMBER := 1;           -- absolute tolerance, in XAF
    k_tol_pct     NUMBER := 0.01;        -- relative tolerance, in percent

    -- Business thresholds
    k_mt_signif   NUMBER := 1000000000;  -- materiality threshold, in XAF
    k_mt_large    NUMBER := 5000000000;  -- large deal walkthrough threshold (5 Bn)
    k_rate_high   NUMBER := 8;           -- high rate walkthrough threshold, in percent
    k_rate_max    NUMBER := 15;          -- upper plausible rate, in percent
    k_rate_min    NUMBER := 0.5;         -- lower plausible rate, in percent
    k_rate_dec    NUMBER := 1;           -- below this, a rate looks captured as a decimal
    k_retro_d     NUMBER := 5;           -- tolerated back valuation, in calendar days
    k_late_d      NUMBER := 5;           -- tolerated settlement delay, in days
    k_gap_d       NUMBER := 3;           -- tolerated gap in the accrual series, in days
    k_old_d       NUMBER := 90;          -- age from which a matured deal is reported
    k_day_basis   NUMBER := 360;         -- day count basis used for estimates
    k_conc_lim    NUMBER := 500000000000;-- ALM concentration limit per issuer, in XAF

    -- Number of detail lines printed per test
    k_top         NUMBER := 30;

    -- ========================================================================
    -- CHART OF ACCOUNTS OF THE MODULE
    -- Exact account numbers (ACTB_HISTORY.AC_NO) and the four digit
    -- accounting classes they belong to. The class is what the tests group
    -- on, so that a sub account opened later inside the same class is
    -- caught without changing the script.
    -- ========================================================================
    k_ac_bond_pl  VARCHAR2(20) := '511410100'; -- OTAP treasury bonds, investment book
    k_ac_bill_pl  VARCHAR2(20) := '511200100'; -- MTPD treasury bills, investment book
    k_ac_bill_tr  VARCHAR2(20) := '512200100'; -- TBTR and BTTR treasury bills, trading book
    k_ac_accr_pl  VARCHAR2(20) := '511800100'; -- accrued interest receivable, investment
    k_ac_accr_tr  VARCHAR2(20) := '512800100'; -- accrued interest receivable, trading
    k_ac_defer    VARCHAR2(20) := '472200100'; -- deferred income, pre counted interest
    k_ac_inc_bond VARCHAR2(20) := '733400100'; -- income on bonds
    k_ac_inc_bill VARCHAR2(20) := '733200100'; -- income on treasury bills
    k_ac_nostro   VARCHAR2(20) := '099ACO00001'; -- BEAC nostro, settlement leg

    -- Four digit accounting classes
    k_cl_bond_pl  VARCHAR2(8) := '5114';  -- treasury bonds, investment book
    k_cl_bill_pl  VARCHAR2(8) := '5112';  -- treasury bills, investment book
    k_cl_bill_tr  VARCHAR2(8) := '5122';  -- treasury bills, trading book
    k_cl_accr_pl  VARCHAR2(8) := '5118';  -- accrued interest receivable, investment
    k_cl_accr_tr  VARCHAR2(8) := '5128';  -- accrued interest receivable, trading
    k_cl_defer    VARCHAR2(8) := '4722';  -- deferred income
    k_cl_inc_bond VARCHAR2(8) := '7334';  -- income on bonds
    k_cl_inc_bill VARCHAR2(8) := '7332';  -- income on treasury bills
    k_cl_invest   VARCHAR2(8) := '511';   -- investment book, all securities
    k_cl_trading  VARCHAR2(8) := '512';   -- trading book, all securities
    k_cl_income   VARCHAR2(8) := '733';   -- income accounts, all securities
    k_cl_cash     VARCHAR2(8) := '56';    -- treasury and BEAC settlement accounts

    -- Products in scope, tested with
    --   INSTR(',' || k_prod_all || ',', ',' || TRIM(m.product) || ',') > 0
    k_prod_all    VARCHAR2(60) := 'OTAP,BTTR,TBTR,MTPD';
    k_prod_post   VARCHAR2(60) := 'OTAP,BTTR';  -- interest collected at maturity
    k_prod_pre    VARCHAR2(60) := 'TBTR,MTPD';  -- interest deducted up front
    k_prod_bond   VARCHAR2(60) := 'OTAP';       -- bonds, income on 7334

    -- Module and external application
    k_mod         VARCHAR2(4)  := 'MM';
    k_ext_pat     VARCHAR2(30) := '%CALYPSO%';

    -- ========================================================================
    -- Test registry, fed by p_verdict and printed in part 12
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
    v_nb_ctr  NUMBER := 0;    -- contracts in scope, reference denominator
    v_mt_ctr  NUMBER := 0;    -- cumulative nominal in scope
    v_d_last  DATE;           -- last accounting entry of the module
    v_d_accr  DATE;           -- last interest accrual of the module
    v_lib     VARCHAR2(200);  -- account description buffer

    -- Column widths of the securities detail table (see sec_head below)
    k_sec_w   VARCHAR2(60) := '4,24,11,26,22,18,16,14,17,30';

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

    -- Result of a test: prints the verdict and records it for part 12.
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
    -- THE SECURITIES DETAIL TABLE
    -- Every control that raises an exception prints the securities behind
    -- it with this single layout, so that a finding is always traceable to
    -- named contracts. Widths are held in k_sec_w, declared with the other
    -- parameters because PL/SQL requires every variable to be declared
    -- before the first subprogram of the block.
    -- ========================================================================
    PROCEDURE sec_head(p_find VARCHAR2 DEFAULT 'FINDING') IS
    BEGIN
        po('     Securities concerned .');
        tbl_head(k_sec_w,
                 'N#|CONTRACT|PRODUCT|ISSUER|NOMINAL|RATE|BOOKED|VALUE|MATURITY|' || p_find,
                 '|CONTRACT_REF_NO|PRODUCT|CUSTOMER_NAME1|LCY_AMOUNT|MAIN_COMP_RATE'
                 || '|BOOKING_DATE|VALUE_DATE|MATURITY_DATE|',
                 'RLLLRRLLLR');
    END;

    PROCEDURE sec_row(p_n    NUMBER,
                      p_ref  VARCHAR2,
                      p_prod VARCHAR2,
                      p_iss  VARCHAR2,
                      p_nom  NUMBER,
                      p_rate NUMBER,
                      p_bd   DATE,
                      p_vd   DATE,
                      p_md   DATE,
                      p_find VARCHAR2) IS
    BEGIN
        po('  |' || fpadl(TO_CHAR(p_n), 4) || '|' || fpad(p_ref, 24) || '|'
            || fpad(p_prod, 11) || '|' || fpad(p_iss, 26) || '|'
            || fpadl(famt(p_nom), 22) || '|' || fpadl(ftx(p_rate), 18) || '|'
            || fpad(fdt(p_bd), 16) || '|' || fpad(fdt(p_vd), 14) || '|'
            || fpad(fdt(p_md), 17) || '|' || fpadl(p_find, 30) || '|');
    END;

    PROCEDURE sec_foot IS
    BEGIN
        tbl_line(k_sec_w);
    END;

    -- Row count of a table, tolerant to a missing or unreadable object
    FUNCTION f_count(p_tab VARCHAR2, p_where VARCHAR2 DEFAULT NULL)
        RETURN NUMBER IS
        v_n NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_tab
                          || CASE WHEN p_where IS NULL THEN ''
                                  ELSE ' WHERE ' || p_where END
                     INTO v_n;
        RETURN v_n;
    EXCEPTION
        WHEN OTHERS THEN RETURN -1;
    END;

BEGIN
    -- ########################################################################
    -- PART 0 : SCOPE, PARAMETERS AND CHART OF ACCOUNTS
    -- ########################################################################
    po(v_sep);
    po('   SECURITIES PORTFOLIO AUDIT - MONEY MARKET MODULE (' || k_mod || ')');
    po('   Report produced on ' || fdth(SYSDATE));
    po(v_sep);

    print_section('0. SCOPE, PARAMETERS AND CHART OF ACCOUNTS');
    BEGIN
        print_sub('0.1 Execution context');
        print_kv('Database',        SYS_CONTEXT('USERENV', 'DB_NAME'));
        print_kv('Instance',        SYS_CONTEXT('USERENV', 'INSTANCE_NAME'));
        print_kv('Schema',          SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        print_kv('Session user',    SYS_CONTEXT('USERENV', 'SESSION_USER'));

        print_sub('0.2 Engagement parameters');
        print_kv('Reporting date',                       fdt(k_asof));
        print_kv('Audited period on BOOKING_DATE',       fdt(k_dt_from) || ' to ' || fdt(k_dt_to));
        print_kv('Absolute tolerance on recalculations', famt(k_tol_abs) || ' XAF');
        print_kv('Relative tolerance on recalculations', TO_CHAR(k_tol_pct) || ' %');
        print_kv('Materiality threshold',                famt(k_mt_signif) || ' XAF (' || fmio(k_mt_signif) || ')');
        print_kv('Large deal walkthrough threshold',     famt(k_mt_large) || ' XAF (' || fmio(k_mt_large) || ')');
        print_kv('High rate walkthrough threshold',      ftx(k_rate_high));
        print_kv('Plausible rate range',                 ftx(k_rate_min) || ' to ' || ftx(k_rate_max));
        print_kv('Tolerated back valuation',             TO_CHAR(k_retro_d) || ' days');
        print_kv('Tolerated settlement delay',           TO_CHAR(k_late_d) || ' days');
        print_kv('Tolerated gap in the accrual series',  TO_CHAR(k_gap_d) || ' days');
        print_kv('Age at which a matured deal is flagged', TO_CHAR(k_old_d) || ' days');
        print_kv('Day count basis used for estimates',   TO_CHAR(k_day_basis));
        print_kv('ALM concentration limit per issuer',   fmio(k_conc_lim));
        print_kv('Detail lines printed per test',        TO_CHAR(k_top));

        print_sub('0.3 Audit scope');
        po('  LDTB_CONTRACT_MASTER is shared with the LD module and holds one row');
        po('  per contract VERSION. The script keeps the last version of every');
        po('  contract reference everywhere.');
        po('');
        SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master WHERE module = k_mod;
        print_kv('Rows of LDTB_CONTRACT_MASTER for module ' || k_mod, fnum(v_cnt));
        SELECT COUNT(DISTINCT contract_ref_no) INTO v_cnt2
          FROM ldtb_contract_master WHERE module = k_mod;
        print_kv('Distinct contract references', fnum(v_cnt2));

        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_nb_ctr, v_mt_ctr
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_from AND k_dt_to
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Contracts retained in scope',    fnum(v_nb_ctr));
        print_kv('Cumulative nominal in scope',    famt(v_mt_ctr) || ' XAF (' || fmio(v_mt_ctr) || ')');

        SELECT COUNT(*) INTO v_cnt FROM actb_history WHERE module = k_mod;
        print_kv('Accounting entries of the module', fnum(v_cnt));
        SELECT MAX(trn_dt) INTO v_d_last FROM actb_history WHERE module = k_mod;
        print_kv('Last accounting entry of the module', fdt(v_d_last));
        SELECT MAX(h.trn_dt) INTO v_d_accr
          FROM actb_history h WHERE h.module = k_mod AND h.event = 'ACCR';
        print_kv('Last interest accrual of the module (ACTB_HISTORY)', fdt(v_d_accr));
        SELECT MAX(accrual_to_date) INTO v_d_max
          FROM ldtb_contract_accrual_history WHERE module = k_mod;
        print_kv('Same date read from the accrual history table',
                 fdt(v_d_max) || CASE WHEN TRUNC(NVL(v_d_max, k_asof)) = TRUNC(NVL(v_d_accr, k_asof))
                                      THEN '   (agrees)'
                                      ELSE '   (DISAGREES with the entries)' END);
        po('  The first date is the one used by every test of this report. The');
        po('  second is printed only as a cross check: where the management table');
        po('  disagrees with the entries, the entries are right and the difference');
        po('  is itself a finding.');

        print_sub('0.4 Chart of accounts of the module');
        po('  The accounting scheme below is the reference against which part 5');
        po('  (MAP) tests the entries. Each product has one security account, one');
        po('  interest mechanism and one income account. The settlement leg is');
        po('  common to all products.');
        po('');
        tbl_head('4,10,22,14,44,20,18',
                 'N#|PRODUCT|ACCOUNT|CLASS|ACCOUNT NAME|ROLE|BOOK',
                 '|PRODUCT|AC_NO| |AC_GL_DESC| | ',
                 'RLLLLLL');
        v_row := 0;
        FOR r IN (
            SELECT n, prod, ac, cl, rol, bk FROM (
                SELECT 1 n, 'OTAP' prod, '511410100' ac, '5114' cl,
                       'security account' rol, 'investment' bk FROM DUAL UNION ALL
                SELECT 2, 'MTPD', '511200100', '5112', 'security account', 'investment' FROM DUAL UNION ALL
                SELECT 3, 'TBTR', '512200100', '5122', 'security account', 'trading' FROM DUAL UNION ALL
                SELECT 4, 'BTTR', '512200100', '5122', 'security account', 'trading' FROM DUAL UNION ALL
                SELECT 5, 'OTAP', '511800100', '5118', 'accrued interest receivable', 'investment' FROM DUAL UNION ALL
                SELECT 6, 'BTTR', '512800100', '5128', 'accrued interest receivable', 'trading' FROM DUAL UNION ALL
                SELECT 7, 'TBTR', '472200100', '4722', 'deferred income', 'trading' FROM DUAL UNION ALL
                SELECT 8, 'MTPD', '472200100', '4722', 'deferred income', 'investment' FROM DUAL UNION ALL
                SELECT 9, 'OTAP', '733400100', '7334', 'income account', 'profit and loss' FROM DUAL UNION ALL
                SELECT 10, 'BTTR', '733200100', '7332', 'income account', 'profit and loss' FROM DUAL UNION ALL
                SELECT 11, 'TBTR', '733200100', '7332', 'income account', 'profit and loss' FROM DUAL UNION ALL
                SELECT 12, 'MTPD', '733200100', '7332', 'income account', 'profit and loss' FROM DUAL UNION ALL
                SELECT 13, 'all', '099ACO00001', '56', 'settlement leg, BEAC nostro', 'treasury' FROM DUAL
            ) ORDER BY n
        ) LOOP
            v_row := v_row + 1;
            SELECT MAX(a.ac_gl_desc) INTO v_lib FROM sttb_account a WHERE a.ac_gl_no = r.ac;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac, 22) || '|' || fpad(r.cl, 14) || '|' || fpad(v_lib, 44) || '|'
                || fpad(r.rol, 20) || '|' || fpad(r.bk, 18) || '|');
        END LOOP;
        tbl_line('4,10,22,14,44,20,18');
        po('');
        po('  The tests group on the four digit CLASS rather than on the exact');
        po('  account number, so that a sub account opened later inside the same');
        po('  class is caught without amending the script.');

        print_sub('0.5 The two interest mechanisms');
        po('  POST COUNTED products (' || k_prod_post || ') - interest is collected at maturity');
        po('    1. Subscription   DEBIT  security account       CREDIT treasury');
        po('    2. Daily accrual  DEBIT  accrued receivable     CREDIT income');
        po('    3. Collection     DEBIT  treasury               CREDIT accrued receivable');
        po('    4. Redemption     DEBIT  treasury               CREDIT security account');
        po('');
        po('  PRE COUNTED products (' || k_prod_pre || ') - interest is deducted up front');
        po('    1. Subscription   DEBIT  security account       CREDIT treasury');
        po('                      the discount is credited to deferred income');
        po('    2. Daily release  DEBIT  deferred income        CREDIT income');
        po('    3. Redemption     DEBIT  treasury               CREDIT security account');
        po('');
        po('  Both mechanisms must end on the same result: the total income');
        po('  recognised over the life of the deal equals MAIN_COMP_AMOUNT.');

        print_sub('0.6 Reading the report');
        po('  TEST codes    LC   securities life cycle, from the accounting analysis');
        po('                EXT  extraction integrity and completeness');
        po('                DBL  double entry');
        po('                MAP  account mapping');
        po('                INT  interest accuracy');
        po('                LIF  life cycle of the positions on the balance sheet');
        po('                REV  reversals, cancellations and amendments');
        po('                CSH  cash reconciliation');
        po('                CUT  period end');
        po('                CLS  classification and valuation');
        po('                STA  static data and limits');
        po('  Severity      CRITICAL > HIGH > MEDIUM > LOW > INFO');
        po('  Verdicts      PASS, FINDING, or FOR INFORMATION when the test is a');
        po('                measurement rather than a rule');
        po('  Amounts       columns labelled " M" are in millions of XAF');
        po('  Headings      every table prints the DATABASE COLUMN NAME between');
        po('                parentheses under the business label');
        po('  Signed sums   a reversal in ACTB_HISTORY keeps the direction of the');
        po('                original entry and carries a NEGATIVE amount. Every');
        po('                total in this report is therefore a SIGNED sum:');
        po('                debit minus credit, never gross against gross.');

        print_sub('0.7 Source of truth');
        po('  ACTB_HISTORY IS THE ONLY PLACE WHERE THE LIFE CYCLE OF A CONTRACT');
        po('  REALLY LIVES. It is the table that tells the truth. Every other table');
        po('  is secondary.');
        po('');
        po('  A contract exists, earns interest, is accrued, is collected, is');
        po('  redeemed and is reversed in ACTB_HISTORY and nowhere else. The entries');
        po('  are the facts; the rest is the front office intention, or a management');
        po('  view of it. This report is built on that principle without exception:');
        po('');
        po('    redemption      the PRINCIPAL_LIQD tag, not a row in a liquidation table');
        po('    collection      the INT_%_LIQD tags');
        po('    accrual         EVENT = ACCR');
        po('    position closed the signed balance of the security account is nil,');
        po('                    not a status column saying so');
        po('');
        po('  LDTB_CONTRACT_MASTER is used for the TERMS of the deal only: nominal,');
        po('  rate, dates, product, counterparty. It says what the deal should have');
        po('  produced; ACTB_HISTORY proves what it did produce. The last version of');
        po('  the contract is always the one read.');
        po('');
        po('  The management tables (liquidation, balances, accrual history, contract');
        po('  status) are printed here and there as a cross check. Where they');
        po('  disagree with the entries, THE ENTRIES WIN, and the disagreement is');
        po('  itself reported as a finding.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 2 : SECURITIES LIFE CYCLE');
    -- ########################################################################
    po('');
    po('  A security that has been redeemed must leave nothing behind on the');
    po('  balance sheet: no security account, no accrued receivable, no deferred');
    po('  income. A security still alive must carry exactly its nominal and the');
    po('  interest earned so far. This part reads the balance sheet contract by');
    po('  contract and confronts it with the state expected at ' || fdt(k_asof) || '.');
    po('');
    po('  MATRIX COVERAGE . the ten tests of this part carry thirteen references');
    po('  of the control matrix: LC-01 to LC-06, from the accounting analysis of');
    po('  the transaction life cycle, and LIF-01 to LIF-07. Where a LC control');
    po('  and a LIF control test the same object, the test carries both codes and');
    po('  is run once, so that nothing is counted twice in the summary.');
    po('');
    po('  SIGNED BALANCE . balance = sum of debits minus sum of credits on the');
    po('  accounts of the family. A nil balance means the position has left the');
    po('  balance sheet. Reversals carry negative amounts and are therefore');
    po('  netted correctly by this convention.');
    po('');
    po('  ACCOUNT FAMILIES USED BY THIS PART, BY FOUR DIGIT CLASS');
    po('    securities            ' || k_cl_bond_pl || ' ' || k_ac_bond_pl || '   treasury bonds, investment');
    po('                          ' || k_cl_bill_pl || ' ' || k_ac_bill_pl || '   treasury bills, investment');
    po('                          ' || k_cl_bill_tr || ' ' || k_ac_bill_tr || '   treasury bills, trading');
    po('    accrued receivable    ' || k_cl_accr_pl || ' ' || k_ac_accr_pl || '   investment book');
    po('                          ' || k_cl_accr_tr || ' ' || k_ac_accr_tr || '   trading book');
    po('    deferred income       ' || k_cl_defer || ' ' || k_ac_defer || '   pre counted interest');
    po('    income                ' || k_cl_inc_bond || ' ' || k_ac_inc_bond || '   bonds');
    po('                          ' || k_cl_inc_bill || ' ' || k_ac_inc_bill || '   treasury bills');
    po('    settlement            ' || k_cl_cash || '   ' || k_ac_nostro || ' BEAC nostro');

    -- =========================================================
    -- 2. LIFE CYCLE TESTS
    -- =========================================================
    print_section('2. LIFE CYCLE OF THE SECURITIES POSITIONS');
    BEGIN

        -- -----------------------------------------------------
        p_test('LIF-01', 'Every matured contract has been redeemed');
        p_obj('a contract whose maturity has passed must carry a PRINCIPAL_LIQD');
        po('                   entry. Its absence means the redemption was never booked, so');
        po('                   the bank still shows an asset it should have been repaid for.');
        p_how('contracts of LDTB_CONTRACT_MASTER whose MATURITY_DATE is past and');
        po('                   which do carry entries in ACTB_HISTORY, but none tagged');
        po('                   PRINCIPAL_LIQD.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.maturity_date <= k_asof
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND EXISTS (SELECT 1 FROM actb_history h
                        WHERE h.trn_ref_no = c.contract_ref_no AND h.module = k_mod)
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = c.contract_ref_no
                              AND h.module = k_mod
                              AND h.amount_tag = 'PRINCIPAL_LIQD');
        p_verdict('LIF-01', 'Matured contract with no redemption entry',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('DAYS PAST MATURITY');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               TRUNC(k_asof) - TRUNC(c.maturity_date) age
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.maturity_date <= k_asof
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = c.contract_ref_no AND h.module = k_mod)
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = c.contract_ref_no
                                              AND h.module = k_mod
                                              AND h.amount_tag = 'PRINCIPAL_LIQD')
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.age) || ' d');
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LC-01 / LIF-02', 'The security account is nil after redemption');
        p_obj('once PRINCIPAL_LIQD has been booked, the security has left the');
        po('                   bank. The signed balance of classes ' || k_cl_bond_pl || ', ' || k_cl_bill_pl
            || ' and ' || k_cl_bill_tr || ' must');
        po('                   therefore be nil. A residue is an incomplete redemption: the');
        po('                   asset is still on the balance sheet although it was repaid.');
        p_how('per contract, signed balance of the security accounts, restricted');
        po('                   to contracts carrying at least one PRINCIPAL_LIQD entry.');
        SELECT COUNT(*), NVL(SUM(ABS(bal_sec)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no ref,
                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                     IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END) bal_sec,
                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE n_liq > 0 AND ABS(bal_sec) > k_tol_abs;
        p_verdict('LC-01 / LIF-02', 'Security account not nil after redemption',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('RESIDUAL BALANCE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_sec, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                     IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) bal_sec,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN 1 ELSE 0 END) n_liq
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE a.n_liq > 0 AND ABS(a.bal_sec) > k_tol_abs
                         ORDER BY ABS(a.bal_sec) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.bal_sec));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LC-03 / LIF-03', 'Post counted deals: the accrued receivable is cleared');
        p_obj('for ' || k_prod_post || ', interest accrues daily on classes ' || k_cl_accr_pl
            || ' and ' || k_cl_accr_tr || ',');
        po('                   then is collected at maturity. Once matured, the receivable must');
        po('                   be nil AND an INT_%_LIQD entry must prove the cash came in. A');
        po('                   receivable left standing is income recognised but never received.');
        p_how('per matured contract of the post counted products, signed balance');
        po('                   of the accrued receivable classes, and count of collection tags.');
        SELECT COUNT(*), NVL(SUM(ABS(bal_accr)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, a.bal_accr, a.n_int
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                             IN (k_cl_accr_pl, k_cl_accr_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) bal_accr,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD' THEN 1 ELSE 0 END) n_int
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                 WHERE INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0
                   AND c.maturity_date <= k_asof)
         WHERE ABS(bal_accr) > k_tol_abs OR n_int = 0;
        p_verdict('LC-03 / LIF-03', 'Accrued receivable not cleared or interest never collected',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('RESIDUAL / COLLECTIONS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_accr, a.n_int, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                     IN (k_cl_accr_pl, k_cl_accr_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) bal_accr,
                                       SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                                THEN 1 ELSE 0 END) n_int
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0
                           AND c.maturity_date <= k_asof
                           AND (ABS(a.bal_accr) > k_tol_abs OR a.n_int = 0)
                         ORDER BY ABS(a.bal_accr) DESC, c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.bal_accr) || ' / ' || fnum(r.n_int));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LC-02 / LIF-04', 'Pre counted deals: the deferred income is released');
        p_obj('for ' || k_prod_pre || ', the discount is cashed in on day one and credited to');
        po('                   class ' || k_cl_defer || ' (' || k_ac_defer || '), then released to income day by day.');
        po('                   At maturity the deferred income must be nil: the amount cashed');
        po('                   in at the start equals the sum of the daily releases. A residue');
        po('                   is income collected but never taken to the profit and loss.');
        p_how('per matured contract of the pre counted products, signed balance');
        po('                   of class ' || k_cl_defer || ', which covers every sub account of that class.');
        SELECT COUNT(*), NVL(SUM(ABS(bal_def)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, a.bal_def
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4) = k_cl_defer
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) bal_def
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                 WHERE INSTR(',' || k_prod_pre || ',', ',' || TRIM(c.product) || ',') > 0
                   AND c.maturity_date <= k_asof)
         WHERE ABS(bal_def) > k_tol_abs;
        p_verdict('LC-02 / LIF-04', 'Deferred income not released at maturity',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('DEFERRED INCOME LEFT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_def, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4) = k_cl_defer
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) bal_def
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE INSTR(',' || k_prod_pre || ',', ',' || TRIM(c.product) || ',') > 0
                           AND c.maturity_date <= k_asof
                           AND ABS(a.bal_def) > k_tol_abs
                         ORDER BY ABS(a.bal_def) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.bal_def));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LC-04', 'Total income over the life equals the deal interest');
        p_obj('whatever the mechanism, the income recognised over the life of a');
        po('                   deal must equal MAIN_COMP_AMOUNT. Pre counted or post counted,');
        po('                   the route differs but the destination does not. A gap means the');
        po('                   profit and loss carries more, or less, than the deal earned.');
        p_how('per matured contract, signed income on class ' || k_cl_income || ' (credits minus');
        po('                   debits) against MAIN_COMP_AMOUNT of the last contract version.');
        po('                   Also carries matrix reference INT-01.');
        SELECT COUNT(*), NVL(SUM(ABS(gap)), 0) INTO v_cnt, v_mt
          FROM (SELECT c.contract_ref_no, NVL(c.main_comp_amount, 0)
                       - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END)
                                FROM actb_history h
                               WHERE h.trn_ref_no = c.contract_ref_no
                                 AND h.module = k_mod
                                 AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0) gap
                  FROM ldtb_contract_master c
                 WHERE c.module = k_mod
                   AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                   AND c.maturity_date <= k_asof
                   AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = c.contract_ref_no)
                   AND NVL(c.main_comp_amount, 0) > 0
                   AND EXISTS (SELECT 1 FROM actb_history h
                                WHERE h.trn_ref_no = c.contract_ref_no AND h.module = k_mod))
         WHERE ABS(gap) > k_tol_abs;
        p_verdict('LC-04', 'Income recognised different from the deal interest',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('DEAL INT. / BOOKED / GAP');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               NVL(c.main_comp_amount, 0) deal_int,
                               NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                               ELSE -NVL(h.lcy_amount, 0) END)
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = c.contract_ref_no
                                       AND h.module = k_mod
                                       AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0) booked
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.maturity_date <= k_asof
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND NVL(c.main_comp_amount, 0) > 0
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = c.contract_ref_no AND h.module = k_mod)
                           AND ABS(NVL(c.main_comp_amount, 0)
                                   - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                            FROM actb_history h
                                           WHERE h.trn_ref_no = c.contract_ref_no
                                             AND h.module = k_mod
                                             AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0)) > k_tol_abs
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.deal_int - r.booked));
            END LOOP;
            sec_foot;
            print_sub('LC-04 a. Deal interest against income booked, deal by deal');
            tbl_head('4,24,11,24,24,24,20',
                     'N#|CONTRACT|PRODUCT|DEAL INTEREST|INCOME BOOKED|GAP|GAP IN PERCENT',
                     '|CONTRACT_REF_NO|PRODUCT|MAIN_COMP_AMOUNT|LCY_AMOUNT on 733| | ',
                     'RLLRRRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product,
                               NVL(c.main_comp_amount, 0) deal_int,
                               NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                               ELSE -NVL(h.lcy_amount, 0) END)
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = c.contract_ref_no
                                       AND h.module = k_mod
                                       AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0) booked
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.maturity_date <= k_asof
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND NVL(c.main_comp_amount, 0) > 0
                           AND ABS(NVL(c.main_comp_amount, 0)
                                   - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                            FROM actb_history h
                                           WHERE h.trn_ref_no = c.contract_ref_no
                                             AND h.module = k_mod
                                             AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0)) > k_tol_abs
                         ORDER BY ABS(NVL(c.main_comp_amount, 0)
                                   - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                            FROM actb_history h
                                           WHERE h.trn_ref_no = c.contract_ref_no
                                             AND h.module = k_mod
                                             AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 11) || '|' || fpadl(famt(r.deal_int), 24) || '|'
                    || fpadl(famt(r.booked), 24) || '|'
                    || fpadl(famt(r.deal_int - r.booked), 24) || '|'
                    || fpadl(fpct(ABS(r.deal_int - r.booked), r.deal_int), 20) || '|');
            END LOOP;
            tbl_line('4,24,11,24,24,24,20');
        END IF;

        -- -----------------------------------------------------
        p_test('LC-06', 'No accrual outside the life of the contract');
        p_obj('an accrual dated before the value date, or after maturity, or after');
        po('                   an early redemption, is interest recognised over a period during');
        po('                   which the bank did not hold the security. It inflates the profit');
        po('                   and loss of a period it does not belong to.');
        p_how('accrual entries (EVENT = ACCR, debit side) whose TRN_DT falls');
        po('                   outside VALUE_DATE and the earlier of MATURITY_DATE and the');
        po('                   first PRINCIPAL_LIQD date. Also carries matrix reference INT-04.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.trn_dt dt, NVL(h.lcy_amount, 0) mt,
                       (SELECT MAX(c.value_date) FROM ldtb_contract_master c
                         WHERE c.contract_ref_no = h.trn_ref_no AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)) vd,
                       (SELECT MAX(c.maturity_date) FROM ldtb_contract_master c
                         WHERE c.contract_ref_no = h.trn_ref_no
                           AND c.version_no = (SELECT MAX(v.version_no)
                                                 FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)) md,
                       (SELECT MIN(x.trn_dt) FROM actb_history x
                         WHERE x.trn_ref_no = h.trn_ref_no
                           AND x.module = k_mod
                           AND x.amount_tag = 'PRINCIPAL_LIQD'
                           AND NVL(x.lcy_amount, 0) > 0) dliq
                  FROM actb_history h
                 WHERE h.module = k_mod
                   AND h.event = 'ACCR'
                   AND h.drcr_ind = 'D')
         WHERE vd IS NOT NULL
           AND (TRUNC(dt) < TRUNC(vd)
             OR TRUNC(dt) > TRUNC(NVL(LEAST(NVL(dliq, md), NVL(md, dliq)), md)) + 1);
        print_kv('Accrual entries outside the life of their contract', fnum(v_cnt));
        p_verdict('LC-06', 'Accrual booked outside the life of the contract',
                  v_cnt2, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt2 > 0 THEN
            sec_head('ENTRIES / AMOUNT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, q.mt, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT ref, COUNT(*) nb, SUM(ABS(mt)) mt FROM (
                                    SELECT h.trn_ref_no ref, h.trn_dt dt, NVL(h.lcy_amount, 0) mt,
                                           (SELECT MAX(c2.value_date) FROM ldtb_contract_master c2
                                             WHERE c2.contract_ref_no = h.trn_ref_no
                                               AND c2.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                            WHERE v.contract_ref_no = c2.contract_ref_no)) vd,
                                           (SELECT MAX(c2.maturity_date) FROM ldtb_contract_master c2
                                             WHERE c2.contract_ref_no = h.trn_ref_no
                                               AND c2.version_no = (SELECT MAX(v.version_no)
                                                                      FROM ldtb_contract_master v
                                                                     WHERE v.contract_ref_no
                                                                           = c2.contract_ref_no)) md,
                                           (SELECT MIN(x.trn_dt) FROM actb_history x
                                             WHERE x.trn_ref_no = h.trn_ref_no
                                               AND x.module = k_mod
                                               AND x.amount_tag = 'PRINCIPAL_LIQD'
                                               AND NVL(x.lcy_amount, 0) > 0) dliq
                                      FROM actb_history h
                                     WHERE h.module = k_mod
                                       AND h.event = 'ACCR'
                                       AND h.drcr_ind = 'D')
                                 WHERE vd IS NOT NULL
                                   AND (TRUNC(dt) < TRUNC(vd)
                                     OR TRUNC(dt) > TRUNC(NVL(LEAST(NVL(dliq, md),
                                                                   NVL(md, dliq)), md)) + 1)
                                 GROUP BY ref) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.mt DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.nb) || ' / ' || fmio(r.mt));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LC-05', 'Every negative entry is matched to its original');
        p_obj('in ACTB_HISTORY a reversal does not flip the direction: it repeats');
        po('                   the same direction with a NEGATIVE amount. Every negative line');
        po('                   must therefore find a positive line of the same contract, same');
        po('                   tag, same account and same absolute amount. An unmatched');
        po('                   negative line is an over reversal: it takes off the balance');
        po('                   sheet an amount that was never put on it.');
        p_how('entries grouped by contract, tag, account, direction and absolute');
        po('                   amount; the group is flagged when the negatives outnumber the');
        po('                   positives. Also carries matrix reference REV-01.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.amount_tag, h.ac_no, h.drcr_ind,
                       ABS(NVL(h.lcy_amount, 0)) mt,
                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                       SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END) n_pos
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                          ABS(NVL(h.lcy_amount, 0)))
         WHERE n_neg > n_pos;
        print_kv('Unmatched negative groups', fnum(v_cnt));
        p_verdict('LC-05', 'Negative entry with no matching original',
                  v_cnt2, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt2 > 0 THEN
            sec_head('GROUPS / AMOUNT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, q.mt, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT ref, COUNT(*) nb, SUM(mt) mt FROM (
                                    SELECT h.trn_ref_no ref, ABS(NVL(h.lcy_amount, 0)) mt,
                                           SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0
                                                    THEN 1 ELSE 0 END) n_neg,
                                           SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0
                                                    THEN 1 ELSE 0 END) n_pos
                                      FROM actb_history h
                                     WHERE h.module = k_mod
                                     GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                                              ABS(NVL(h.lcy_amount, 0)))
                                 WHERE n_neg > n_pos
                                 GROUP BY ref) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.mt DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.nb) || ' / ' || fmio(r.mt));
            END LOOP;
            sec_foot;
            print_sub('LC-05 a. The unmatched negative entries, line by line');
            tbl_head('4,24,20,22,8,14,14,24',
                     'N#|CONTRACT|AMOUNT TAG|ACCOUNT|D/C|NEGATIVES|POSITIVES|UNIT AMOUNT',
                     '|TRN_REF_NO|AMOUNT_TAG|AC_NO|DRCR_IND| | |LCY_AMOUNT',
                     'RLLLLRRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.amount_tag, h.ac_no, h.drcr_ind,
                               ABS(NVL(h.lcy_amount, 0)) mt,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END) n_pos
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                                  ABS(NVL(h.lcy_amount, 0))
                        HAVING SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END)
                             > SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END)
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.amount_tag, 20) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(r.drcr_ind, 8) || '|' || fpadl(fnum(r.n_neg), 14) || '|'
                    || fpadl(fnum(r.n_pos), 14) || '|' || fpadl(famt(r.mt), 24) || '|');
            END LOOP;
            tbl_line('4,24,20,22,8,14,14,24');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-05', 'Early redemptions are identified and documented');
        p_obj('a redemption of the principal booked before the contractual');
        po('                   maturity is a sale or an early repayment. It changes the yield of');
        po('                   the deal, and the accruals must stop on that date. Each case must');
        po('                   be documented by the front office.');
        p_how('first PRINCIPAL_LIQD entry with a positive amount, compared with');
        po('                   MATURITY_DATE, beyond a tolerance of ' || TO_CHAR(k_late_d) || ' days. The last accrual');
        po('                   date is printed so that the stop can be checked at a glance.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, c.lcy_amount nom, a.dliq, c.maturity_date md
                  FROM (SELECT h.trn_ref_no ref, MIN(h.trn_dt) dliq
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND h.amount_tag = 'PRINCIPAL_LIQD'
                           AND NVL(h.lcy_amount, 0) > 0
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no))
         WHERE TRUNC(md) - TRUNC(dliq) > k_late_d;
        p_verdict('LIF-05', 'Principal redeemed before contractual maturity',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('REDEEMED / DAYS EARLY');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.dliq, a.d_accr, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       MIN(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                 AND NVL(h.lcy_amount, 0) > 0
                                                THEN h.trn_dt END) dliq,
                                       MAX(CASE WHEN h.event = 'ACCR' THEN h.trn_dt END) d_accr
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE a.dliq IS NOT NULL
                           AND TRUNC(c.maturity_date) - TRUNC(a.dliq) > k_late_d
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fdt(r.dliq) || ' / '
                        || fnum(TRUNC(r.maturity_date) - TRUNC(r.dliq)) || ' d');
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-06', 'Live contracts carry the right security balance');
        p_obj('on a contract that is neither matured nor redeemed, the signed');
        po('                   balance of the security account must equal the nominal. A lower');
        po('                   balance points to a partial exit that was never tracked, a higher');
        po('                   one to a double booking.');
        p_how('per contract with no PRINCIPAL_LIQD entry and a maturity beyond');
        po('                   ' || fdt(k_asof) || ', signed balance of the security classes against LCY_AMOUNT.');
        SELECT COUNT(*), NVL(SUM(ABS(bal_sec - nom)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, a.bal_sec, c.lcy_amount nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                             IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) bal_sec,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                 WHERE a.n_liq = 0 AND c.maturity_date > k_asof)
         WHERE ABS(bal_sec - nom) > k_tol_abs;
        p_verdict('LIF-06', 'Live contract whose security balance differs from the nominal',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('BALANCE / GAP');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_sec, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                     IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) bal_sec,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN 1 ELSE 0 END) n_liq
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE a.n_liq = 0 AND c.maturity_date > k_asof
                           AND ABS(a.bal_sec - c.lcy_amount) > k_tol_abs
                         ORDER BY ABS(a.bal_sec - c.lcy_amount) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.bal_sec) || ' / ' || famt(r.bal_sec - r.lcy_amount));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-07', 'No matured position left open on the balance sheet');
        p_obj('a contract past maturity whose security account is not nil means');
        po('                   either the counterparty has not repaid, or the exit entry was');
        po('                   missed. Either way the position still sits in the assets when it');
        po('                   should not, and the bank may be carrying an unrecognised loss.');
        p_how('per contract with MATURITY_DATE at or before ' || fdt(k_asof) || ', signed balance');
        po('                   of the security classes, flagged when it is not nil.');
        SELECT COUNT(*), NVL(SUM(ABS(bal_sec)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, a.bal_sec
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                             IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) bal_sec
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                 WHERE c.maturity_date <= k_asof)
         WHERE ABS(bal_sec) > k_tol_abs;
        p_verdict('LIF-07', 'Matured position still open on the balance sheet',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('OPEN BALANCE / DAYS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_sec, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                     IN (k_cl_bond_pl, k_cl_bill_pl, k_cl_bill_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) bal_sec
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE c.maturity_date <= k_asof
                           AND ABS(a.bal_sec) > k_tol_abs
                         ORDER BY ABS(a.bal_sec) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.bal_sec) || ' / '
                        || fnum(TRUNC(k_asof) - TRUNC(r.maturity_date)) || ' d');
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 3 : EXTRACTION INTEGRITY AND COMPLETENESS');
    -- ########################################################################
    po('');
    po('  Before any figure can be relied on, the extraction itself must be');
    po('  proved neither to create nor to destroy lines. A join that fans out and');
    po('  a DISTINCT that flattens produce the same wrong report, in two opposite');
    po('  directions.');

    print_section('3. EXT CONTROLS : EXTRACTION INTEGRITY');
    BEGIN

        -- -----------------------------------------------------
        p_test('EXT-01', 'Each accounting line is extracted once and only once');
        p_obj('two distinct risks. First, STTB_ACCOUNT may hold several rows for');
        po('                   one AC_GL_NO, one per currency, branch or version, and a direct');
        po('                   join on AC_GL_NO would then multiply every entry. Second, the');
        po('                   journal line key may not be unique, in which case the count');
        po('                   itself is wrong.');
        p_how('accounts of STTB_ACCOUNT carrying more than one row, and the');
        po('                   number of entries of the module each of them receives.');
        SELECT COUNT(*) INTO v_cnt
          FROM (SELECT ac_gl_no FROM sttb_account
                 GROUP BY ac_gl_no HAVING COUNT(*) > 1);
        SELECT COUNT(DISTINCT ac_gl_no) INTO v_tot FROM sttb_account;
        print_kv('Distinct accounts in STTB_ACCOUNT', fnum(v_tot));
        print_kv('Of which carry several rows',      fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        p_verdict('EXT-01', 'Accounts that would fan out the entries on a direct join',
                  v_cnt, v_tot, NULL, 'CRITICAL');
        IF v_cnt > 0 THEN
            po('     CONTROL APPLIED BY THIS SCRIPT . every join to STTB_ACCOUNT goes');
            po('     through a pre aggregated view');
            po('       LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib');
            po('                    FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no');
            po('     which returns one row and only one per account. No total of this');
            po('     report is therefore multiplied by that join.');
            po('');
            tbl_head('4,22,44,16,22',
                     'N#|ACCOUNT|ACCOUNT NAME|ROWS HELD|ENTRIES IN MODULE',
                     '|AC_GL_NO|AC_GL_DESC| | ',
                     'RLLRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ac_gl_no, MAX(a.ac_gl_desc) lib, COUNT(*) nb,
                               NVL(u.nb_mm, 0) nb_mm
                          FROM sttb_account a
                          LEFT JOIN (SELECT h.ac_no, COUNT(*) nb_mm
                                       FROM actb_history h
                                      WHERE h.module = k_mod
                                      GROUP BY h.ac_no) u ON u.ac_no = a.ac_gl_no
                         GROUP BY a.ac_gl_no, NVL(u.nb_mm, 0)
                        HAVING COUNT(*) > 1
                         ORDER BY NVL(u.nb_mm, 0) DESC, COUNT(*) DESC, a.ac_gl_no
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_gl_no, 22) || '|'
                    || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fnum(r.nb_mm), 22) || '|');
            END LOOP;
            tbl_line('4,22,44,16,22');
        END IF;

        print_sub('EXT-01 a. Uniqueness of the journal line key');
        po('  Three candidate keys are tested on the entries of the module. A key');
        po('  that is not unique makes any reliable de-duplication impossible.');
        tbl_head('4,50,20,22,16',
                 'N#|CANDIDATE KEY|LINES|DISTINCT KEYS|VERDICT',
                 '| | | | ',
                 'RLRRR');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        v_cnt := 0;
        SELECT COUNT(DISTINCT h.ac_branch || '|' || h.ac_entry_sr_no) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        IF v_cnt2 <> v_tot THEN v_cnt := v_cnt + 1; END IF;
        po('  |' || fpadl('1', 4) || '|' || fpad('AC_BRANCH + AC_ENTRY_SR_NO', 50) || '|'
            || fpadl(fnum(v_tot), 20) || '|' || fpadl(fnum(v_cnt2), 22) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NOT UNIQUE' END, 16) || '|');
        SELECT COUNT(DISTINCT h.ac_branch || '|' || h.entry_seq_no) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        IF v_cnt2 <> v_tot THEN v_cnt := v_cnt + 1; END IF;
        po('  |' || fpadl('2', 4) || '|' || fpad('AC_BRANCH + ENTRY_SEQ_NO', 50) || '|'
            || fpadl(fnum(v_tot), 20) || '|' || fpadl(fnum(v_cnt2), 22) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NOT UNIQUE' END, 16) || '|');
        SELECT COUNT(DISTINCT h.trn_ref_no || '|' || h.event_sr_no || '|' || h.ac_no
                              || '|' || h.drcr_ind || '|' || h.amount_tag) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        po('  |' || fpadl('3', 4) || '|' || fpad('TRN_REF_NO + EVENT_SR_NO + AC_NO + DRCR_IND + AMOUNT_TAG', 50) || '|'
            || fpadl(fnum(v_tot), 20) || '|' || fpadl(fnum(v_cnt2), 22) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NOT UNIQUE' END, 16) || '|');
        tbl_line('4,50,20,22,16');
        p_verdict('EXT-01b', 'Technical line keys that are not unique on the module',
                  v_cnt, 2, NULL, 'CRITICAL');

        -- -----------------------------------------------------
        p_test('EXT-02', 'De-duplication uses the line key, never the whole row');
        p_obj('a SELECT DISTINCT on the whole row flattens lines that are');
        po('                   legitimately identical: a reversal and the entry it cancels differ');
        po('                   only by their technical key. The test measures how many lines a');
        po('                   DISTINCT would make disappear. Any non nil figure proves that a');
        po('                   DISTINCT based de-duplication destroys accounting information.');
        p_how('count of rows against count of distinct business tuples');
        po('                   (TRN_REF_NO, EVENT, AC_NO, DRCR_IND, AMOUNT_TAG, LCY_AMOUNT, TRN_DT).');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        SELECT COUNT(*) INTO v_cnt2
          FROM (SELECT DISTINCT h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                       h.lcy_amount, h.trn_dt
                  FROM actb_history h WHERE h.module = k_mod);
        v_cnt := v_tot - v_cnt2;
        print_kv('Lines of the module',                       fnum(v_tot));
        print_kv('Lines left after a business DISTINCT',      fnum(v_cnt2));
        print_kv('Lines a DISTINCT would make disappear',     fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        SELECT NVL(SUM(mt), 0) INTO v_mt
          FROM (SELECT (COUNT(*) - 1) * MAX(NVL(h.lcy_amount, 0)) mt
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                          h.trn_dt, h.lcy_amount
                HAVING COUNT(*) > 1);
        p_verdict('EXT-02', 'Accounting lines a DISTINCT de-duplication would destroy',
                  v_cnt, v_tot, ABS(v_mt), 'CRITICAL');
        IF v_cnt > 0 THEN
            po('     The groups below hold several strictly identical lines on the');
            po('     business columns. They are legitimate: only the technical key');
            po('     separates them. This script never de-duplicates.');
            SELECT COUNT(DISTINCT trn_ref_no) INTO v_cnt3
              FROM (SELECT h.trn_ref_no
                      FROM actb_history h
                     WHERE h.module = k_mod
                     GROUP BY h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                              h.trn_dt, h.lcy_amount
                    HAVING COUNT(*) > 1);
            print_kv('Contracts concerned', fnum(v_cnt3));
            sec_head('DUPLICATE LINES');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT trn_ref_no ref, SUM(nb - 1) nb FROM (
                                    SELECT h.trn_ref_no, COUNT(*) nb
                                      FROM actb_history h
                                     WHERE h.module = k_mod
                                     GROUP BY h.trn_ref_no, h.event, h.ac_no, h.drcr_ind,
                                              h.amount_tag, h.trn_dt, h.lcy_amount
                                    HAVING COUNT(*) > 1)
                                 GROUP BY trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.nb DESC, c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.nb));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('EXT-03', 'Every contract of the deal master carries accounting entries');
        p_obj('on the four money market products (' || k_prod_all || '), every');
        po('                   contract must have at least one entry in ACTB_HISTORY. A contract');
        po('                   without entries exists in the front office and nowhere in the');
        po('                   accounts: the position is invisible to the balance sheet.');
        p_how('contracts of the last version, in scope and on the four products,');
        po('                   with no matching TRN_REF_NO in ACTB_HISTORY.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND INSTR(',' || k_prod_all || ',', ',' || TRIM(c.product) || ',') > 0
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = c.contract_ref_no
                              AND h.module = k_mod);
        p_verdict('EXT-03', 'Money market contract with no accounting entry at all',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('CONTRACT_STATUS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date, TRIM(c.contract_status) st
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND INSTR(',' || k_prod_all || ',', ',' || TRIM(c.product) || ',') > 0
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = c.contract_ref_no
                                              AND h.module = k_mod)
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.st);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('EXT-04', 'No orphan accounting entry');
        p_obj('every TRN_REF_NO of the module must match a CONTRACT_REF_NO of the');
        po('                   deal master. An orphan entry is either a contract purged while its');
        po('                   accounting survives, or an entry booked on a reference that does');
        po('                   not exist. Neither can be explained to a reviewer.');
        p_how('entries of the module whose TRN_REF_NO is absent from');
        po('                   LDTB_CONTRACT_MASTER, all versions taken together.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master c
                            WHERE c.contract_ref_no = h.trn_ref_no);
        print_kv('Distinct orphan references', fnum(v_cnt2));
        p_verdict('EXT-04', 'Accounting entry with no matching contract',
                  v_cnt, NULL, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            po('     These entries carry no contract, so no security can be named:');
            po('     the reference itself is what has to be investigated.');
            tbl_head('4,26,14,12,20,8,24,24',
                     'N#|ORPHAN REFERENCE|DATE|EVENT|AMOUNT TAG|D/C|ACCOUNT|AMOUNT',
                     '|TRN_REF_NO|TRN_DT|EVENT|AMOUNT_TAG|DRCR_IND|AC_NO|LCY_AMOUNT',
                     'RLLLLLLR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.trn_dt dt, h.event, h.amount_tag,
                               h.drcr_ind, h.ac_no, h.lcy_amount mt
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master c
                                            WHERE c.contract_ref_no = h.trn_ref_no)
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 26) || '|'
                    || fpad(fdt(r.dt), 14) || '|' || fpad(r.event, 12) || '|'
                    || fpad(r.amount_tag, 20) || '|' || fpad(r.drcr_ind, 8) || '|'
                    || fpad(r.ac_no, 24) || '|' || fpadl(famt(r.mt), 24) || '|');
            END LOOP;
            tbl_line('4,26,14,12,20,8,24,24');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 4 : DOUBLE ENTRY');
    -- ########################################################################
    po('');
    po('  Balance is tested at three nested levels. An imbalance at event level');
    po('  can offset itself at contract level, and an imbalance at contract level');
    po('  can offset itself over a whole day. The finest level is the only one');
    po('  that hides nothing.');
    po('');
    po('  All sums are SIGNED: debit positive, credit negative. Reversals carry');
    po('  negative amounts, so a gross debit against gross credit total would');
    po('  read them backwards and inflate both columns.');

    print_section('4. DBL CONTROLS : DOUBLE ENTRY');
    BEGIN

        -- -----------------------------------------------------
        p_test('DBL-01', 'Each contract balances over its whole life');
        p_obj('over the life of a contract, the signed sum of its entries must be');
        po('                   nil. A contract that does not balance carries an entry whose');
        po('                   counterpart was never booked, and the balance sheet is off by');
        po('                   that amount.');
        p_how('signed sum grouped by TRN_REF_NO, flagged beyond ' || famt(k_tol_abs) || ' XAF.');
        SELECT COUNT(*), NVL(SUM(ABS(bal)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) bal
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE ABS(bal) > k_tol_abs;
        p_verdict('DBL-01', 'Contract whose signed sum of entries is not nil',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('IMBALANCE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal, a.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref, COUNT(*) nb,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) bal
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE ABS(a.bal) > k_tol_abs
                         ORDER BY ABS(a.bal) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.bal));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-02', 'Each event balances (contract, date and amount tag)');
        p_obj('the fine level. A half posted entry, whose counterpart was');
        po('                   forgotten, offsets itself at contract level as soon as another');
        po('                   entry is symmetrically wrong. It never offsets itself at the');
        po('                   contract, date and tag level.');
        p_how('signed sum grouped by TRN_REF_NO, TRN_DT and AMOUNT_TAG.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(bal)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.trn_dt, h.amount_tag,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) bal
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.trn_dt, h.amount_tag)
         WHERE ABS(bal) > k_tol_abs;
        print_kv('Unbalanced events', fnum(v_cnt));
        p_verdict('DBL-02', 'Unbalanced accounting event (contract, date, tag)',
                  v_cnt2, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt2 > 0 THEN
            sec_head('EVENTS / IMBALANCE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, q.bal, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT ref, COUNT(*) nb, SUM(ABS(bal)) bal FROM (
                                    SELECT h.trn_ref_no ref, h.trn_dt, h.amount_tag,
                                           SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                        ELSE -NVL(h.lcy_amount, 0) END) bal
                                      FROM actb_history h
                                     WHERE h.module = k_mod
                                     GROUP BY h.trn_ref_no, h.trn_dt, h.amount_tag)
                                 WHERE ABS(bal) > k_tol_abs
                                 GROUP BY ref) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.bal DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.nb) || ' / ' || famt(r.bal));
            END LOOP;
            sec_foot;
            print_sub('DBL-02 a. The unbalanced events, one by one');
            tbl_head('4,24,14,20,24,24,24',
                     'N#|CONTRACT|DATE|AMOUNT TAG|TOTAL DEBIT|TOTAL CREDIT|SIGNED BALANCE',
                     '|TRN_REF_NO|TRN_DT|AMOUNT_TAG|LCY_AMOUNT|LCY_AMOUNT| ',
                     'RLLLRRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.trn_dt dt, h.amount_tag,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) bal
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no, h.trn_dt, h.amount_tag
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.dt), 14) || '|' || fpad(r.amount_tag, 20) || '|'
                    || fpadl(famt(r.deb), 24) || '|' || fpadl(famt(r.cre), 24) || '|'
                    || fpadl(famt(r.bal), 24) || '|');
            END LOOP;
            tbl_line('4,24,14,20,24,24,24');
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-03', 'The whole portfolio balances on every accounting date');
        p_obj('the signed sum of all the entries of the module must be nil every');
        po('                   day. A daily imbalance points to an entry booked without its');
        po('                   counterpart, or to a counterpart dated another day, which would');
        po('                   distort the daily position sent to the treasury.');
        p_how('signed sum grouped by TRN_DT over the whole module.');
        SELECT COUNT(*), NVL(SUM(ABS(bal)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_dt,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) bal
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_dt)
         WHERE ABS(bal) > k_tol_abs;
        SELECT COUNT(DISTINCT h.trn_dt) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        print_kv('Accounting dates with movements', fnum(v_tot));
        p_verdict('DBL-03', 'Accounting date on which the module does not balance',
                  v_cnt, v_tot, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            tbl_head('4,16,20,26,26,26',
                     'N#|DATE|ENTRIES|TOTAL DEBIT|TOTAL CREDIT|SIGNED BALANCE',
                     '|TRN_DT| |LCY_AMOUNT|LCY_AMOUNT| ',
                     'RLRRRR');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_dt dt, COUNT(*) nb,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) bal
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_dt
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.dt), 16) || '|'
                    || fpadl(fnum(r.nb), 20) || '|' || fpadl(fmio(r.deb), 26) || '|'
                    || fpadl(fmio(r.cre), 26) || '|' || fpadl(famt(r.bal), 26) || '|');
            END LOOP;
            tbl_line('4,16,20,26,26,26');
            print_sub('DBL-03 a. Securities carrying entries on the unbalanced dates');
            sec_head('ENTRIES ON THOSE DATES');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref, COUNT(*) nb
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND h.trn_dt IN (SELECT trn_dt FROM (
                                         SELECT h2.trn_dt,
                                                SUM(CASE h2.drcr_ind WHEN 'D' THEN NVL(h2.lcy_amount, 0)
                                                                     ELSE -NVL(h2.lcy_amount, 0) END) bal
                                           FROM actb_history h2
                                          WHERE h2.module = k_mod
                                          GROUP BY h2.trn_dt)
                                        WHERE ABS(bal) > k_tol_abs)
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.nb DESC, c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.nb));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-04', 'No entry with a nil amount or a missing qualifier');
        p_obj('an entry with no amount, no direction or no amount tag can neither');
        po('                   be reconciled nor interpreted. It silently distorts every control');
        po('                   that relies on those columns, this report included.');
        p_how('five defects counted separately on the entries of the module.');
        tbl_head('4,52,20,16,26',
                 'N#|DEFECT TESTED|LINES|SHARE OF MODULE|AMOUNT CONCERNED',
                 '| | | |LCY_AMOUNT',
                 'RLRRR');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        v_cnt := 0;
        v_mt  := 0;
        v_row := 0;
        FOR r IN (SELECT 'LCY_AMOUNT nil or not populated' lib, 1 ord FROM DUAL UNION ALL
                  SELECT 'DRCR_IND not populated',           2 FROM DUAL UNION ALL
                  SELECT 'AMOUNT_TAG not populated',         3 FROM DUAL UNION ALL
                  SELECT 'AC_NO not populated',              4 FROM DUAL UNION ALL
                  SELECT 'TRN_DT not populated',             5 FROM DUAL
                  ORDER BY 2) LOOP
            SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt2, v_tot2
              FROM actb_history h
             WHERE h.module = k_mod
               AND ((r.ord = 1 AND NVL(h.lcy_amount, 0) = 0)
                 OR (r.ord = 2 AND TRIM(h.drcr_ind) IS NULL)
                 OR (r.ord = 3 AND TRIM(h.amount_tag) IS NULL)
                 OR (r.ord = 4 AND TRIM(h.ac_no) IS NULL)
                 OR (r.ord = 5 AND h.trn_dt IS NULL));
            v_cnt := v_cnt + v_cnt2;
            v_mt  := v_mt + v_tot2;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 52) || '|'
                || fpadl(fnum(v_cnt2), 20) || '|' || fpadl(fpct(v_cnt2, v_tot), 16) || '|'
                || fpadl(fmio(v_tot2), 26) || '|');
        END LOOP;
        tbl_line('4,52,20,16,26');
        p_verdict('DBL-04', 'Entry with a nil amount or a missing qualifier',
                  v_cnt, v_tot, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            sec_head('DEFECTIVE ENTRIES');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref, COUNT(*) nb
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND (NVL(h.lcy_amount, 0) = 0
                                     OR TRIM(h.drcr_ind) IS NULL
                                     OR TRIM(h.amount_tag) IS NULL
                                     OR TRIM(h.ac_no) IS NULL
                                     OR h.trn_dt IS NULL)
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.nb DESC, c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.nb));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 5 : ACCOUNT MAPPING');
    -- ########################################################################
    po('');
    po('  A wrong mapping unbalances nothing: double entry stays satisfied. It');
    po('  distorts the reading of the balance sheet and of the profit and loss,');
    po('  and it therefore escapes every balance control of part 4. The expected');
    po('  scheme is the one printed in section 0.4.');
    po('');
    po('  All the tests of this part group on the FOUR DIGIT CLASS of AC_NO, so');
    po('  that a sub account opened later inside an authorised class is caught');
    po('  without amending the script.');

    print_section('5. MAP CONTROLS : ACCOUNT MAPPING');
    BEGIN

        -- -----------------------------------------------------
        p_test('MAP-01', 'Each product uses only its authorised security account');
        p_obj('on the PRINCIPAL and PRINCIPAL_LIQD tags, the security leg must');
        po('                   hit the account of the product and no other. A bond booked on the');
        po('                   bill account moves the position from one balance sheet line to');
        po('                   another without any imbalance appearing.');
        p_how('cross tab product against account on the debit security leg;');
        po('                   authorised pairs are OTAP-' || k_ac_bond_pl || ', MTPD-' || k_ac_bill_pl
            || ', TBTR and BTTR-' || k_ac_bill_tr || '.');
        print_sub('MAP-01 a. Product against security account, as actually booked');
        tbl_head('4,10,22,14,40,18,26,16',
                 'N#|PRODUCT|ACCOUNT|CLASS|ACCOUNT NAME|ENTRIES|AMOUNT|VERDICT',
                 '|PRODUCT|AC_NO| |AC_GL_DESC| |LCY_AMOUNT| ',
                 'RLLLLRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                         SUM(NVL(h.lcy_amount, 0)) mt
                    FROM actb_history h
                    JOIN (SELECT contract_ref_no, MAX(product) prod
                            FROM ldtb_contract_master
                           WHERE module = k_mod
                           GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                     AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                     AND h.drcr_ind = 'D'
                     AND SUBSTR(h.ac_no, 1, 3) IN (k_cl_invest, k_cl_trading)
                   GROUP BY p.prod, h.ac_no
                   ORDER BY p.prod, COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF (r.prod = 'OTAP' AND r.ac_no = k_ac_bond_pl)
            OR (r.prod = 'MTPD' AND r.ac_no = k_ac_bill_pl)
            OR (r.prod IN ('TBTR', 'BTTR') AND r.ac_no = k_ac_bill_tr) THEN
                v_cnt2 := 0;
            ELSE
                v_cnt2 := 1;
                v_cnt := v_cnt + r.nb;
                v_mt  := v_mt + ABS(r.mt);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(SUBSTR(r.ac_no, 1, 4), 14) || '|'
                || fpad(r.lib, 40) || '|' || fpadl(fnum(r.nb), 18) || '|'
                || fpadl(fmio(r.mt), 26) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'AUTHORISED' ELSE 'OFF SCHEME' END, 16) || '|');
        END LOOP;
        tbl_line('4,10,22,14,40,18,26,16');
        p_verdict('MAP-01', 'Security leg booked on an account not authorised for the product',
                  v_cnt, NULL, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('ACCOUNT USED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.ac_no, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT DISTINCT h.trn_ref_no ref, h.ac_no
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                   AND h.drcr_ind = 'D'
                                   AND SUBSTR(h.ac_no, 1, 3) IN (k_cl_invest, k_cl_trading)) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE NOT ((c.product = 'OTAP' AND q.ac_no = k_ac_bond_pl)
                                 OR (c.product = 'MTPD' AND q.ac_no = k_ac_bill_pl)
                                 OR (c.product IN ('TBTR', 'BTTR') AND q.ac_no = k_ac_bill_tr))
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.ac_no);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MAP-02', 'The interest mechanism matches the product');
        p_obj('pre counted products (' || k_prod_pre || ') go through deferred income,');
        po('                   class ' || k_cl_defer || '. Post counted products (' || k_prod_post || ') go through the');
        po('                   accrued receivable, classes ' || k_cl_accr_pl || ' and ' || k_cl_accr_tr || '. Mixing the two on one');
        po('                   product distorts the pace at which income reaches the profit and');
        po('                   loss, without ever unbalancing the trial balance.');
        p_how('interest tags (AMOUNT_TAG starting with INT) hitting the class of');
        po('                   the other mechanism.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          JOIN (SELECT contract_ref_no, MAX(product) prod
                  FROM ldtb_contract_master WHERE module = k_mod
                 GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
         WHERE h.module = k_mod
           AND h.amount_tag LIKE 'INT%'
           AND ((INSTR(',' || k_prod_post || ',', ',' || p.prod || ',') > 0
                 AND SUBSTR(h.ac_no, 1, 4) = k_cl_defer)
             OR (INSTR(',' || k_prod_pre || ',', ',' || p.prod || ',') > 0
                 AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)));
        p_verdict('MAP-02', 'Pre counted and post counted mechanisms mixed on one product',
                  v_cnt, NULL, v_mt, 'HIGH');
        print_sub('MAP-02 a. Product against account on the interest tags');
        tbl_head('4,10,22,14,40,20,18,26',
                 'N#|PRODUCT|ACCOUNT|CLASS|ACCOUNT NAME|MECHANISM READ|ENTRIES|AMOUNT',
                 '|PRODUCT|AC_NO| |AC_GL_DESC| | |LCY_AMOUNT',
                 'RLLLLLRR');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                           SUM(NVL(h.lcy_amount, 0)) mt
                      FROM actb_history h
                      JOIN (SELECT contract_ref_no, MAX(product) prod
                              FROM ldtb_contract_master WHERE module = k_mod
                             GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                      LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                   FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                     WHERE h.module = k_mod
                       AND h.amount_tag LIKE 'INT%'
                     GROUP BY p.prod, h.ac_no
                     ORDER BY p.prod, COUNT(*) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(SUBSTR(r.ac_no, 1, 4), 14) || '|'
                || fpad(r.lib, 40) || '|'
                || fpad(CASE WHEN SUBSTR(r.ac_no, 1, 4) = k_cl_defer THEN 'pre counted'
                             WHEN SUBSTR(r.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                                  THEN 'post counted'
                             WHEN SUBSTR(r.ac_no, 1, 3) = k_cl_income THEN 'profit and loss'
                             ELSE 'other' END, 20) || '|'
                || fpadl(fnum(r.nb), 18) || '|' || fpadl(fmio(r.mt), 26) || '|');
        END LOOP;
        tbl_line('4,10,22,14,40,20,18,26');
        IF v_cnt > 0 THEN
            sec_head('MECHANISM CONFLICT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.ac_no, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT DISTINCT h.trn_ref_no ref, h.ac_no
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND h.amount_tag LIKE 'INT%') q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE ((INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0
                                 AND SUBSTR(q.ac_no, 1, 4) = k_cl_defer)
                             OR (INSTR(',' || k_prod_pre || ',', ',' || TRIM(c.product) || ',') > 0
                                 AND SUBSTR(q.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)))
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.ac_no);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MAP-03', 'The income account matches the instrument');
        p_obj('bonds (' || k_prod_bond || ') feed ' || k_ac_inc_bond || ', class ' || k_cl_inc_bond
            || '. Treasury bills feed');
        po('                   ' || k_ac_inc_bill || ', class ' || k_cl_inc_bill || '. An inversion moves the revenue from one');
        po('                   line of the profit and loss to another, which is exactly what the');
        po('                   regulatory reporting reads.');
        p_how('entries on the income class ' || k_cl_income || ' whose account does not match');
        po('                   the product of the contract.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          JOIN (SELECT contract_ref_no, MAX(product) prod
                  FROM ldtb_contract_master WHERE module = k_mod
                 GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
         WHERE h.module = k_mod
           AND SUBSTR(h.ac_no, 1, 3) = k_cl_income
           AND ((INSTR(',' || k_prod_bond || ',', ',' || p.prod || ',') > 0
                 AND SUBSTR(h.ac_no, 1, 4) <> k_cl_inc_bond)
             OR (INSTR(',' || k_prod_bond || ',', ',' || p.prod || ',') = 0
                 AND SUBSTR(h.ac_no, 1, 4) <> k_cl_inc_bill));
        p_verdict('MAP-03', 'Income account not matching the instrument',
                  v_cnt, NULL, v_mt, 'HIGH');
        print_sub('MAP-03 a. Product against income account');
        tbl_head('4,10,22,14,40,18,26,16',
                 'N#|PRODUCT|ACCOUNT|CLASS|ACCOUNT NAME|ENTRIES|AMOUNT|VERDICT',
                 '|PRODUCT|AC_NO| |AC_GL_DESC| |LCY_AMOUNT| ',
                 'RLLLLRRR');
        v_row := 0;
        FOR r IN (SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                         SUM(NVL(h.lcy_amount, 0)) mt
                    FROM actb_history h
                    JOIN (SELECT contract_ref_no, MAX(product) prod
                            FROM ldtb_contract_master WHERE module = k_mod
                           GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                     AND SUBSTR(h.ac_no, 1, 3) = k_cl_income
                   GROUP BY p.prod, h.ac_no
                   ORDER BY p.prod, COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(SUBSTR(r.ac_no, 1, 4), 14) || '|'
                || fpad(r.lib, 40) || '|' || fpadl(fnum(r.nb), 18) || '|'
                || fpadl(fmio(r.mt), 26) || '|'
                || fpadl(CASE WHEN INSTR(',' || k_prod_bond || ',', ',' || r.prod || ',') > 0
                                   AND SUBSTR(r.ac_no, 1, 4) = k_cl_inc_bond THEN 'AUTHORISED'
                              WHEN INSTR(',' || k_prod_bond || ',', ',' || r.prod || ',') = 0
                                   AND SUBSTR(r.ac_no, 1, 4) = k_cl_inc_bill THEN 'AUTHORISED'
                              ELSE 'OFF SCHEME' END, 16) || '|');
        END LOOP;
        tbl_line('4,10,22,14,40,18,26,16');
        IF v_cnt > 0 THEN
            sec_head('INCOME ACCOUNT USED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.ac_no, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT DISTINCT h.trn_ref_no ref, h.ac_no
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND SUBSTR(h.ac_no, 1, 3) = k_cl_income) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE ((INSTR(',' || k_prod_bond || ',', ',' || TRIM(c.product) || ',') > 0
                                 AND SUBSTR(q.ac_no, 1, 4) <> k_cl_inc_bond)
                             OR (INSTR(',' || k_prod_bond || ',', ',' || TRIM(c.product) || ',') = 0
                                 AND SUBSTR(q.ac_no, 1, 4) <> k_cl_inc_bill))
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.ac_no);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MAP-04', 'The settlement leg always hits a cash account');
        p_obj('on PRINCIPAL and PRINCIPAL_LIQD the counterpart of the security leg');
        po('                   is a payment or a receipt: it must hit the nostro ' || k_ac_nostro);
        po('                   or an account of class ' || k_cl_cash || '. A settlement leg parked on a security,');
        po('                   an accrual or a suspense account means the cash never moved.');
        p_how('legs of those two tags that are neither a security account nor a');
        po('                   cash account, read from AC_NO and from AC_NATURAL_GL.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                       FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
         WHERE h.module = k_mod
           AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
           AND SUBSTR(h.ac_no, 1, 3) NOT IN (k_cl_invest, k_cl_trading)
           AND h.ac_no <> k_ac_nostro
           AND SUBSTR(h.ac_no, 1, 2) <> k_cl_cash
           AND NVL(s.nat, ' ') NOT LIKE k_cl_cash || '%';
        print_kv('Contracts concerned', fnum(v_cnt2));
        p_verdict('MAP-04', 'Settlement leg outside any cash account',
                  v_cnt, NULL, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('ACCOUNT USED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.ac_no, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT DISTINCT h.trn_ref_no ref, h.ac_no
                                  FROM actb_history h
                                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                                               FROM sttb_account GROUP BY ac_gl_no) s
                                         ON s.ac_gl_no = h.ac_no
                                 WHERE h.module = k_mod
                                   AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                   AND SUBSTR(h.ac_no, 1, 3) NOT IN (k_cl_invest, k_cl_trading)
                                   AND h.ac_no <> k_ac_nostro
                                   AND SUBSTR(h.ac_no, 1, 2) <> k_cl_cash
                                   AND NVL(s.nat, ' ') NOT LIKE k_cl_cash || '%') q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.ac_no);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MAP-05', 'Every account used exists and is neither closed nor blocked');
        p_obj('an account unknown to the chart of accounts, unauthorised, closed,');
        po('                   blocked, frozen or barred from posting should receive no entry at');
        po('                   all. One that does means the posting bypassed a control that was');
        po('                   put there on purpose.');
        p_how('distinct accounts of the module joined to STTB_ACCOUNT, reading');
        po('                   AUTH_STAT, GL_STAT_BLOCKED, AC_STAT_FROZEN and GL_STAT_DE_POST.');
        tbl_head('4,22,38,10,10,10,10,10,18,16',
                 'N#|ACCOUNT|ACCOUNT NAME|EXISTS|AUTH|BLOCKED|FROZEN|NO POST|ENTRIES|VERDICT',
                 '|AC_NO|AC_GL_DESC| |AUTH_STAT|GL_STAT_BLOCKED|AC_STAT_FROZEN|GL_STAT_DE_POST| | ',
                 'RLLLLLLLRR');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT h.ac_no, COUNT(*) nb,
                         MAX(s.lib) lib, MAX(s.au) au, MAX(s.bl) bl, MAX(s.fr) fr,
                         MAX(s.dp) dp, MAX(s.ex) ex
                    FROM actb_history h
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib, MAX(auth_stat) au,
                                      MAX(NVL(gl_stat_blocked, 'N')) bl,
                                      MAX(NVL(ac_stat_frozen, 'N')) fr,
                                      MAX(NVL(gl_stat_de_post, 'N')) dp, 'Y' ex
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                   GROUP BY h.ac_no
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF r.ex IS NULL OR NVL(r.au, 'X') <> 'A' OR NVL(r.bl, 'N') = 'Y'
               OR NVL(r.fr, 'N') = 'Y' OR NVL(r.dp, 'N') = 'Y' THEN
                v_cnt := v_cnt + 1;
                v_cnt2 := 1;
            ELSE
                v_cnt2 := 0;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|'
                || fpad(r.lib, 38) || '|' || fpad(NVL(r.ex, 'NO'), 10) || '|'
                || fpad(NVL(r.au, '-'), 10) || '|' || fpad(NVL(r.bl, '-'), 10) || '|'
                || fpad(NVL(r.fr, '-'), 10) || '|' || fpad(NVL(r.dp, '-'), 10) || '|'
                || fpadl(fnum(r.nb), 18) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'OK' ELSE 'TO EXPLAIN' END, 16) || '|');
        END LOOP;
        tbl_line('4,22,38,10,10,10,10,10,18,16');
        p_verdict('MAP-05', 'Account used that is unknown, unauthorised, blocked, frozen or barred',
                  v_cnt, v_row, NULL, 'MEDIUM');

        -- -----------------------------------------------------
        p_test('MAP-06', 'No money market entry lands in a suspense account');
        p_obj('the authorised list holds nine account numbers. Anything outside');
        po('                   it must be challenged: suspense account, inter branch account, sub');
        po('                   account opened outside the procedure, or the nostro of a');
        po('                   counterparty other than the BEAC.');
        p_how('entries of the module whose AC_NO is none of the nine authorised');
        po('                   accounts, listed by account and then by security.');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no NOT IN (k_ac_bond_pl, k_ac_bill_pl, k_ac_bill_tr,
                               k_ac_accr_pl, k_ac_accr_tr, k_ac_defer,
                               k_ac_inc_bond, k_ac_inc_bill, k_ac_nostro);
        SELECT COUNT(*) INTO v_cnt2
          FROM (SELECT DISTINCT h.ac_no FROM actb_history h
                 WHERE h.module = k_mod
                   AND h.ac_no NOT IN (k_ac_bond_pl, k_ac_bill_pl, k_ac_bill_tr,
                                       k_ac_accr_pl, k_ac_accr_tr, k_ac_defer,
                                       k_ac_inc_bond, k_ac_inc_bill, k_ac_nostro));
        print_kv('Distinct accounts outside the authorised list', fnum(v_cnt2));
        p_verdict('MAP-06', 'Entry booked on an account outside the nine authorised ones',
                  v_cnt, NULL, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            tbl_head('4,22,14,14,40,18,26,26,16',
                     'N#|ACCOUNT|CLASS|NATURAL GL|ACCOUNT NAME|ENTRIES|TOTAL DEBIT|TOTAL CREDIT|CONTRACTS',
                     '|AC_NO| |AC_NATURAL_GL|AC_GL_DESC| |LCY_AMOUNT|LCY_AMOUNT|TRN_REF_NO',
                     'RLLLLRRRR');
            v_row := 0;
            FOR r IN (SELECT h.ac_no, MAX(s.nat) nat, MAX(s.lib) lib, COUNT(*) nb,
                             SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                             SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                             COUNT(DISTINCT h.trn_ref_no) nbc
                        FROM actb_history h
                        LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                     FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                       WHERE h.module = k_mod
                         AND h.ac_no NOT IN (k_ac_bond_pl, k_ac_bill_pl, k_ac_bill_tr,
                                             k_ac_accr_pl, k_ac_accr_tr, k_ac_defer,
                                             k_ac_inc_bond, k_ac_inc_bill, k_ac_nostro)
                       GROUP BY h.ac_no
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > k_top;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(SUBSTR(r.ac_no, 1, 4), 14) || '|' || fpad(r.nat, 14) || '|'
                    || fpad(r.lib, 40) || '|' || fpadl(fnum(r.nb), 18) || '|'
                    || fpadl(fmio(r.deb), 26) || '|' || fpadl(fmio(r.cre), 26) || '|'
                    || fpadl(fnum(r.nbc), 16) || '|');
            END LOOP;
            tbl_line('4,22,14,14,40,18,26,26,16');
            sec_head('OFF LIST ACCOUNTS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref, COUNT(DISTINCT h.ac_no) nb
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND h.ac_no NOT IN (k_ac_bond_pl, k_ac_bill_pl, k_ac_bill_tr,
                                                       k_ac_accr_pl, k_ac_accr_tr, k_ac_defer,
                                                       k_ac_inc_bond, k_ac_inc_bill, k_ac_nostro)
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.nb) || ' account(s)');
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 6 : INTEREST ACCURACY');
    -- ########################################################################
    po('');
    po('  Two of the seven INT controls have already been run in part 2, because');
    po('  they close the life cycle: INT-01, income over the life against the deal');
    po('  interest, is carried by LC-04, and INT-04, no accrual outside the life');
    po('  of the contract, is carried by LC-06. This part carries the five others.');
    po('');
    po('  The remaining question is whether the interest amount of the deal is');
    po('  arithmetically right, and whether the accounting recorded it at the');
    po('  right pace, day by day, with no gap and no overshoot.');

    print_section('6. INT CONTROLS : INTEREST ACCURACY');
    BEGIN
        SELECT MAX(h.trn_dt) INTO v_d_accr
          FROM actb_history h WHERE h.module = k_mod AND h.event = 'ACCR';
        print_kv('Last accrual entry of the module (ACTB_HISTORY)', fdt(v_d_accr));
        po('  The pace tests are bounded at that date. Beyond it, a missing accrual');
        po('  is not a gap in the series but the module having stopped accruing.');

        -- -----------------------------------------------------
        p_test('INT-02', 'The deal interest amount is arithmetically exact');
        p_obj('independent recalculation: nominal times rate times tenor divided');
        po('                   by ' || TO_CHAR(k_day_basis) || '. A gap reveals a wrong rate, a wrong basis or a wrong');
        po('                   tenor inside the contract itself, before any accounting is done.');
        p_how('LCY_AMOUNT times MAIN_COMP_RATE divided by 100, times');
        po('                   MATURITY_DATE minus VALUE_DATE, divided by ' || TO_CHAR(k_day_basis)
            || ', against MAIN_COMP_AMOUNT.');
        SELECT COUNT(*), NVL(SUM(ABS(gap)), 0) INTO v_cnt, v_mt
          FROM (SELECT c.contract_ref_no,
                       NVL(c.main_comp_amount, 0)
                       - ROUND(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                               * (c.maturity_date - c.value_date) / k_day_basis, 2) gap
                  FROM ldtb_contract_master c
                 WHERE c.module = k_mod
                   AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                   AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = c.contract_ref_no)
                   AND NVL(c.main_comp_amount, 0) > 0
                   AND c.maturity_date > c.value_date)
         WHERE ABS(gap) > k_tol_abs;
        p_verdict('INT-02', 'Deal interest different from the nominal times rate times tenor',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('DEAL INT. / RECOMPUTED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               NVL(c.main_comp_amount, 0) deal_int,
                               ROUND(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                     * (c.maturity_date - c.value_date) / k_day_basis, 2) th
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND NVL(c.main_comp_amount, 0) > 0
                           AND c.maturity_date > c.value_date
                           AND ABS(NVL(c.main_comp_amount, 0)
                                   - ROUND(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                           * (c.maturity_date - c.value_date) / k_day_basis, 2))
                               > k_tol_abs
                         ORDER BY ABS(NVL(c.main_comp_amount, 0)
                                   - ROUND(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                           * (c.maturity_date - c.value_date) / k_day_basis, 2)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.deal_int) || ' / ' || famt(r.th));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('INT-03', 'The daily accrual is a whole multiple of the theoretical day');
        p_obj('one day of accrual is worth MAIN_COMP_AMOUNT divided by the tenor.');
        po('                   A catch up after a weekend or a public holiday is worth two or');
        po('                   three times that amount: it stays a whole multiple. An accrual');
        po('                   that is not a whole multiple points to a different rate applied,');
        po('                   or to a manual adjustment.');
        p_how('accrual entries grouped by contract and date on classes ' || k_cl_accr_pl
            || ' and ' || k_cl_accr_tr || ',');
        po('                   divided by the theoretical day, flagged when the ratio is not');
        po('                   within 0.02 of a whole number.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT q.ref, q.dt, q.mt, q.day_int,
                       ABS(q.mt / q.day_int - ROUND(q.mt / q.day_int)) gap
                  FROM (SELECT h.trn_ref_no ref, h.trn_dt dt,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) mt,
                               MAX((SELECT NVL(c.main_comp_amount, 0)
                                           / NULLIF(c.maturity_date - c.value_date, 0)
                                      FROM ldtb_contract_master c
                                     WHERE c.contract_ref_no = h.trn_ref_no
                                       AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no))) day_int
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND h.event = 'ACCR'
                           AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                         GROUP BY h.trn_ref_no, h.trn_dt) q
                 WHERE NVL(q.day_int, 0) > 0 AND ABS(q.mt) > 0)
         WHERE gap > 0.02;
        print_kv('Accrual days that are not a whole multiple', fnum(v_cnt));
        p_verdict('INT-03', 'Daily accrual that is not a whole multiple of the theoretical day',
                  v_cnt2, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt2 > 0 THEN
            sec_head('DAYS / AMOUNT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT z.ref, z.nb, z.mt, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT ref, COUNT(*) nb, SUM(ABS(mt)) mt FROM (
                                    SELECT q.ref, q.mt
                                      FROM (SELECT h.trn_ref_no ref, h.trn_dt dt,
                                                   SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                       ELSE -NVL(h.lcy_amount, 0) END) mt,
                                                   MAX((SELECT NVL(c2.main_comp_amount, 0)
                                                               / NULLIF(c2.maturity_date - c2.value_date, 0)
                                                          FROM ldtb_contract_master c2
                                                         WHERE c2.contract_ref_no = h.trn_ref_no
                                                           AND c2.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                            WHERE v.contract_ref_no = c2.contract_ref_no))) day_int
                                              FROM actb_history h
                                             WHERE h.module = k_mod
                                               AND h.event = 'ACCR'
                                               AND SUBSTR(h.ac_no, 1, 4)
                                                   IN (k_cl_accr_pl, k_cl_accr_tr)
                                             GROUP BY h.trn_ref_no, h.trn_dt) q
                                     WHERE NVL(q.day_int, 0) > 0 AND ABS(q.mt) > 0
                                       AND ABS(q.mt / q.day_int - ROUND(q.mt / q.day_int)) > 0.02)
                                 GROUP BY ref) z
                          JOIN ldtb_contract_master c ON c.contract_ref_no = z.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY z.mt DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.nb) || ' / ' || fmio(r.mt));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('INT-05', 'No gap in the accrual series');
        p_obj('the number of days actually accrued, catch ups included, must equal');
        po('                   the number of days elapsed. A gap means income the bank earned but');
        po('                   never recognised, and a balance sheet understated by that amount.');
        p_how('sum of the accrual amounts divided by the theoretical day gives');
        po('                   the days accrued, compared with the days elapsed up to ' || fdt(v_d_accr) || '.');
        po('                   Tolerance of ' || TO_CHAR(k_gap_d) || ' days for public holidays.');
        SELECT COUNT(*), NVL(SUM(ABS(missing * day_int)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.day_int, q.d_accrued,
                       q.d_elapsed - q.d_accrued missing
                  FROM (SELECT c.contract_ref_no ref,
                               NVL(c.main_comp_amount, 0)
                                 / NULLIF(c.maturity_date - c.value_date, 0) day_int,
                               TRUNC(LEAST(v_d_accr, c.maturity_date)) - TRUNC(c.value_date) d_elapsed,
                               NVL((SELECT ROUND(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                          / NULLIF(NVL(c.main_comp_amount, 0)
                                                   / NULLIF(c.maturity_date - c.value_date, 0), 0))
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = c.contract_ref_no
                                       AND h.module = k_mod
                                       AND h.event = 'ACCR'
                                       AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                                       AND h.trn_dt <= v_d_accr), 0) d_accrued
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0
                           AND NVL(c.main_comp_amount, 0) > 0
                           AND c.value_date < v_d_accr) q
                 WHERE q.d_elapsed > 0)
         WHERE missing > k_gap_d;
        p_verdict('INT-05', 'Gap in the accrual series before the module stopped accruing',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('DAYS MISSING / AMOUNT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.missing, q.day_int, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT z.ref, z.day_int, z.d_elapsed - z.d_accrued missing
                                  FROM (SELECT c2.contract_ref_no ref,
                                               NVL(c2.main_comp_amount, 0)
                                                 / NULLIF(c2.maturity_date - c2.value_date, 0) day_int,
                                               TRUNC(LEAST(v_d_accr, c2.maturity_date))
                                                 - TRUNC(c2.value_date) d_elapsed,
                                               NVL((SELECT ROUND(SUM(CASE h.drcr_ind
                                                                        WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                        ELSE -NVL(h.lcy_amount, 0) END)
                                                          / NULLIF(NVL(c2.main_comp_amount, 0)
                                                                   / NULLIF(c2.maturity_date
                                                                            - c2.value_date, 0), 0))
                                                      FROM actb_history h
                                                     WHERE h.trn_ref_no = c2.contract_ref_no
                                                       AND h.module = k_mod
                                                       AND h.event = 'ACCR'
                                                       AND SUBSTR(h.ac_no, 1, 4)
                                                           IN (k_cl_accr_pl, k_cl_accr_tr)
                                                       AND h.trn_dt <= v_d_accr), 0) d_accrued
                                          FROM ldtb_contract_master c2
                                         WHERE c2.module = k_mod
                                           AND c2.booking_date BETWEEN k_dt_from AND k_dt_to
                                           AND c2.version_no = (SELECT MAX(v.version_no)
                                                                  FROM ldtb_contract_master v
                                                                 WHERE v.contract_ref_no
                                                                       = c2.contract_ref_no)
                                           AND INSTR(',' || k_prod_post || ',',
                                                     ',' || TRIM(c2.product) || ',') > 0
                                           AND NVL(c2.main_comp_amount, 0) > 0
                                           AND c2.value_date < v_d_accr) z
                                 WHERE z.d_elapsed > 0
                                   AND z.d_elapsed - z.d_accrued > k_gap_d) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.missing * q.day_int DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.missing) || ' d / ' || famt(r.missing * r.day_int));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('INT-06', 'The day count basis is consistent within each product');
        p_obj('implied basis equals nominal times rate times tenor divided by the');
        po('                   deal interest. It should be ' || TO_CHAR(k_day_basis) || ' across the whole portfolio. A');
        po('                   365 basis on a few deals of one product is an exception to be');
        po('                   justified: it changes the yield actually earned.');
        p_how('implied basis computed deal by deal, then minimum, maximum and');
        po('                   median per product. A product is flagged when the spread exceeds');
        po('                   two days.');
        tbl_head('4,10,20,18,18,18,18,16',
                 'N#|PRODUCT|IMPLIED BASIS|CONTRACTS|MINIMUM|MAXIMUM|MEDIAN|VERDICT',
                 '|PRODUCT| | | | | | ',
                 'RLLRRRRR');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT q.product, ROUND(MEDIAN(q.basis)) bmed, COUNT(*) nb,
                         ROUND(MIN(q.basis)) bmin, ROUND(MAX(q.basis)) bmax
                    FROM (SELECT c.product,
                                 NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                   * (c.maturity_date - c.value_date)
                                   / NULLIF(NVL(c.main_comp_amount, 0), 0) basis
                            FROM ldtb_contract_master c
                           WHERE c.module = k_mod
                             AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                  WHERE v.contract_ref_no = c.contract_ref_no)
                             AND NVL(c.main_comp_amount, 0) > 0
                             AND NVL(c.main_comp_rate, 0) > 0
                             AND c.maturity_date > c.value_date) q
                   WHERE q.basis BETWEEN 300 AND 400
                   GROUP BY q.product
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF ABS(r.bmax - r.bmin) > 2 THEN
                v_cnt := v_cnt + 1;
                v_cnt2 := 1;
            ELSE
                v_cnt2 := 0;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 10) || '|'
                || fpad(TO_CHAR(r.bmed) || ' days', 20) || '|' || fpadl(fnum(r.nb), 18) || '|'
                || fpadl(TO_CHAR(r.bmin), 18) || '|' || fpadl(TO_CHAR(r.bmax), 18) || '|'
                || fpadl(TO_CHAR(r.bmed), 18) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'CONSISTENT' ELSE 'SPREAD' END, 16) || '|');
        END LOOP;
        tbl_line('4,10,20,18,18,18,18,16');
        p_verdict('INT-06', 'Product whose day count basis is not consistent',
                  v_cnt, v_row, NULL, 'MEDIUM');
        IF v_cnt > 0 THEN
            print_sub('INT-06 a. The deals whose implied basis is not ' || TO_CHAR(k_day_basis));
            sec_head('IMPLIED BASIS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               ROUND(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                     * (c.maturity_date - c.value_date)
                                     / NULLIF(NVL(c.main_comp_amount, 0), 0), 1) basis
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND NVL(c.main_comp_amount, 0) > 0
                           AND NVL(c.main_comp_rate, 0) > 0
                           AND c.maturity_date > c.value_date
                           AND ABS(NVL(c.lcy_amount, 0) * NVL(c.main_comp_rate, 0) / 100
                                   * (c.maturity_date - c.value_date)
                                   / NULLIF(NVL(c.main_comp_amount, 0), 0) - k_day_basis) > 2
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        TO_CHAR(r.basis) || ' days');
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('INT-07', 'The rate is populated and plausible');
        p_obj('a rate that is nil, missing or outside the range agreed with the');
        po('                   treasury (' || ftx(k_rate_min) || ' to ' || ftx(k_rate_max) || ') either produces no interest at all or');
        po('                   an amount nobody can justify to the counterparty.');
        p_how('MAIN_COMP_RATE of the last contract version against the range.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND (c.main_comp_rate IS NULL
                OR c.main_comp_rate < k_rate_min
                OR c.main_comp_rate > k_rate_max);
        p_verdict('INT-07', 'Rate missing, nil or outside the agreed range',
                  v_cnt, v_nb_ctr, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            sec_head('RATE FOUND');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND (c.main_comp_rate IS NULL
                                OR c.main_comp_rate < k_rate_min
                                OR c.main_comp_rate > k_rate_max)
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, ftx(r.main_comp_rate));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 7 : REVERSALS, CANCELLATIONS AND AMENDMENTS');
    -- ########################################################################
    po('');
    po('  REV-01, every negative entry matched to its original, has already been');
    po('  run in part 2 as LC-05: an over reversal takes a security off the');
    po('  balance sheet, so it belongs to the life cycle. This part carries the');
    po('  five other REV controls.');

    print_section('7. REV CONTROLS : REVERSALS AND AMENDMENTS');
    BEGIN

        -- -----------------------------------------------------
        p_test('REV-02', 'Fully reversed contracts are re-booked or formally cancelled');
        p_obj('a contract whose balances have all returned to zero with no');
        po('                   redemption has been cancelled in the accounts. It must have been');
        po('                   re-booked under another reference, or its cancellation must be');
        po('                   confirmed by the front office. Left unexplained, it is a deal that');
        po('                   existed, consumed cash, and vanished.');
        p_how('contracts with negative entries, no PRINCIPAL_LIQD and a nil');
        po('                   signed balance; the script then looks for a replacement carrying');
        po('                   the same nominal, rate, value date and maturity.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, c.lcy_amount nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) bal,
                               SUM(ABS(NVL(h.lcy_amount, 0))) gross,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                 WHERE a.n_liq = 0 AND a.n_neg > 0 AND a.gross > 0
                   AND ABS(a.bal) <= k_tol_abs);
        p_verdict('REV-02', 'Contract fully reversed, neither redeemed nor obviously re-booked',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('REPLACEMENT FOUND');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               (SELECT MIN(y.contract_ref_no) FROM ldtb_contract_master y
                                 WHERE y.module = k_mod
                                   AND y.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = y.contract_ref_no)
                                   AND y.contract_ref_no <> c.contract_ref_no
                                   AND y.lcy_amount = c.lcy_amount
                                   AND NVL(y.main_comp_rate, -1) = NVL(c.main_comp_rate, -1)
                                   AND y.value_date = c.value_date
                                   AND y.maturity_date = c.maturity_date) repl
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) bal,
                                       SUM(ABS(NVL(h.lcy_amount, 0))) gross,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN 1 ELSE 0 END) n_liq,
                                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0
                                                THEN 1 ELSE 0 END) n_neg
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE a.n_liq = 0 AND a.n_neg > 0 AND a.gross > 0
                           AND ABS(a.bal) <= k_tol_abs
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, NVL(r.repl, 'NONE FOUND'));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('REV-03', 'Reversals are summed signed, never gross against gross');
        p_obj('a demonstration on this very portfolio. The same entries are');
        po('                   totalled twice: signed, the method used throughout this report,');
        po('                   and in absolute values, the trapping method. The gap measures');
        po('                   exactly what a gross report would overstate.');
        p_how('two totals over the whole module, then the difference. This is');
        po('                   not a defect of the database: it is the size of the risk taken by');
        po('                   any report that sums gross.');
        SELECT NVL(SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'D' THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'C' THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END), 0)
          INTO v_mt, v_tot, v_tot2, v_mt2
          FROM actb_history h WHERE h.module = k_mod;
        tbl_head('4,46,28,28,26',
                 'N#|SUMMING METHOD|TOTAL DEBIT|TOTAL CREDIT|DEBIT MINUS CREDIT',
                 '| |LCY_AMOUNT|LCY_AMOUNT| ',
                 'RLRRR');
        po('  |' || fpadl('1', 4) || '|' || fpad('Signed amounts, reversals negative', 46) || '|'
            || fpadl(fmio(v_mt), 28) || '|' || fpadl(fmio(v_tot), 28) || '|'
            || fpadl(famt(v_mt - v_tot), 26) || '|');
        po('  |' || fpadl('2', 4) || '|' || fpad('Absolute amounts, the trapping method', 46) || '|'
            || fpadl(fmio(v_tot2), 28) || '|' || fpadl(fmio(v_mt2), 28) || '|'
            || fpadl(famt(v_tot2 - v_mt2), 26) || '|');
        tbl_line('4,46,28,28,26');
        print_kv('Debit overstated by the gross method',  fmio(v_tot2 - v_mt));
        print_kv('Credit overstated by the gross method', fmio(v_mt2 - v_tot));
        IF ABS(v_tot2 - v_mt) > k_tol_abs OR ABS(v_mt2 - v_tot) > k_tol_abs THEN
            v_cnt := 1;
        ELSE
            v_cnt := 0;
        END IF;
        p_verdict('REV-03', 'A gross summation would misstate the accounts of the module',
                  v_cnt, 1, ABS(v_tot2 - v_mt) + ABS(v_mt2 - v_tot), 'HIGH');

        -- -----------------------------------------------------
        p_test('REV-04', 'No entry posted into a period already closed');
        p_obj('two signals. The period code of an entry must match the month of');
        po('                   its accounting date; and the accounting date must not precede the');
        po('                   booking date of the contract, which would mean booking an');
        po('                   operation before it existed.');
        p_how('PERIOD_CODE against the month of TRN_DT, then TRN_DT against the');
        po('                   earliest BOOKING_DATE of the contract.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.period_code IS NOT NULL
           AND h.trn_dt IS NOT NULL
           AND TRIM(h.period_code) <> TO_CHAR(h.trn_dt, 'MM');
        print_kv('Contracts concerned', fnum(v_cnt2));
        p_verdict('REV-04', 'Entry whose period code does not match its accounting date',
                  v_cnt, NULL, v_mt, 'HIGH');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt3, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND TRUNC(h.trn_dt) < (SELECT TRUNC(MIN(c.booking_date))
                                    FROM ldtb_contract_master c
                                   WHERE c.contract_ref_no = h.trn_ref_no);
        print_kv('Contracts concerned', fnum(v_cnt3));
        p_verdict('REV-04b', 'Entry dated before the booking date of its contract',
                  v_cnt, NULL, v_mt, 'HIGH');
        IF v_cnt2 + v_cnt3 > 0 THEN
            sec_head('OFF PERIOD ENTRIES');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.nb, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref, COUNT(*) nb
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND ((h.period_code IS NOT NULL AND h.trn_dt IS NOT NULL
                                         AND TRIM(h.period_code) <> TO_CHAR(h.trn_dt, 'MM'))
                                     OR TRUNC(h.trn_dt) < (SELECT TRUNC(MIN(c2.booking_date))
                                                             FROM ldtb_contract_master c2
                                                            WHERE c2.contract_ref_no = h.trn_ref_no))
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         ORDER BY q.nb DESC, c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.nb) || ' entries');
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('REV-05', 'A rate amendment is followed by an accrual catch up');
        p_obj('LDTB_CONTRACT_MASTER keeps one row per version. A different rate');
        po('                   between two versions is an amendment: the accruals must have been');
        po('                   recomputed from the amendment date, and the total must still tie');
        po('                   to the amended interest amount.');
        p_how('contracts carrying more than one distinct MAIN_COMP_RATE or');
        po('                   MATURITY_DATE across versions, then income booked against the');
        po('                   MAIN_COMP_AMOUNT of the last version.');
        SELECT COUNT(*) INTO v_tot
          FROM (SELECT c.contract_ref_no
                  FROM ldtb_contract_master c
                 WHERE c.module = k_mod
                 GROUP BY c.contract_ref_no
                HAVING COUNT(DISTINCT NVL(c.main_comp_rate, -1)) > 1
                    OR COUNT(DISTINCT c.maturity_date) > 1);
        print_kv('Amended contracts (rate or maturity changed)', fnum(v_tot));
        SELECT COUNT(*), NVL(SUM(ABS(gap)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.contract_ref_no,
                       NVL((SELECT MAX(NVL(y.main_comp_amount, 0)) FROM ldtb_contract_master y
                             WHERE y.contract_ref_no = a.contract_ref_no
                               AND y.version_no = (SELECT MAX(v.version_no)
                                                     FROM ldtb_contract_master v
                                                    WHERE v.contract_ref_no = a.contract_ref_no)), 0)
                       - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END)
                                FROM actb_history h
                               WHERE h.trn_ref_no = a.contract_ref_no
                                 AND h.module = k_mod
                                 AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0) gap
                  FROM (SELECT c.contract_ref_no
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                         GROUP BY c.contract_ref_no
                        HAVING COUNT(DISTINCT NVL(c.main_comp_rate, -1)) > 1
                            OR COUNT(DISTINCT c.maturity_date) > 1) a
                 WHERE EXISTS (SELECT 1 FROM ldtb_contract_master z
                                WHERE z.contract_ref_no = a.contract_ref_no
                                  AND z.maturity_date <= k_asof))
         WHERE ABS(gap) > k_tol_abs;
        p_verdict('REV-05', 'Amended contract whose accruals were never caught up',
                  v_cnt, v_tot, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('INTEREST GAP');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               NVL(c.main_comp_amount, 0)
                               - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                 ELSE -NVL(h.lcy_amount, 0) END)
                                        FROM actb_history h
                                       WHERE h.trn_ref_no = a.contract_ref_no
                                         AND h.module = k_mod
                                         AND SUBSTR(h.ac_no, 1, 3) = k_cl_income), 0) gap
                          FROM (SELECT c2.contract_ref_no
                                  FROM ldtb_contract_master c2
                                 WHERE c2.module = k_mod
                                 GROUP BY c2.contract_ref_no
                                HAVING COUNT(DISTINCT NVL(c2.main_comp_rate, -1)) > 1
                                    OR COUNT(DISTINCT c2.maturity_date) > 1) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.contract_ref_no
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE c.maturity_date <= k_asof
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.gap));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('REV-06', 'Income recognised then cancelled inside the month is monitored');
        p_obj('a revenue booked then cancelled in the same month disappears from');
        po('                   the net balance but stays in the gross credits. Using the gross');
        po('                   figure to steer performance overstates the revenue.');
        p_how('per month, gross credits and gross debits of the income class '
            || k_cl_income || ',');
        po('                   against the net. A month carrying debits has cancellations.');
        tbl_head('4,14,18,26,26,26,18',
                 'N#|MONTH|ENTRIES|GROSS CREDIT|GROSS DEBIT|NET INCOME|STATUS',
                 '|TRN_DT| |LCY_AMOUNT|LCY_AMOUNT| | ',
                 'RLRRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mth, COUNT(*) nb,
                         SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                         SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb
                    FROM actb_history h
                   WHERE h.module = k_mod
                     AND SUBSTR(h.ac_no, 1, 3) = k_cl_income
                   GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM')
                   ORDER BY 1) LOOP
            v_row := v_row + 1;
            IF ABS(r.deb) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(r.deb);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mth, 14) || '|'
                || fpadl(fnum(r.nb), 18) || '|' || fpadl(fmio(r.cre), 26) || '|'
                || fpadl(fmio(r.deb), 26) || '|' || fpadl(fmio(r.cre - r.deb), 26) || '|'
                || fpadl(CASE WHEN ABS(r.deb) > k_tol_abs THEN 'CANCELLATIONS'
                              ELSE '-' END, 18) || '|');
        END LOOP;
        tbl_line('4,14,18,26,26,26,18');
        p_verdict('REV-06', 'Month carrying cancellations of income already recognised',
                  v_cnt, v_row, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            sec_head('INCOME CANCELLED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.mt, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(NVL(h.lcy_amount, 0)) mt
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND SUBSTR(h.ac_no, 1, 3) = k_cl_income
                                   AND h.drcr_ind = 'D'
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master c ON c.contract_ref_no = q.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                         WHERE v.contract_ref_no = c.contract_ref_no)
                         WHERE ABS(q.mt) > k_tol_abs
                         ORDER BY ABS(q.mt) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.mt));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 8 : CASH RECONCILIATION');
    -- ########################################################################
    po('');
    po('  This is the only control that proves the money actually moved. An entry');
    po('  that balances, is correctly mapped and perfectly accrued can still');
    po('  describe a payment that never happened.');
    po('');
    po('  LIMIT . the BEAC account statement is not in the database. The script');
    po('  therefore tests what can be tested from the entries (existence,');
    po('  direction and consistency of the cash leg) and prepares, in the');
    po('  extraction tables, the list of movements to tick against the statement.');

    print_section('8. CSH CONTROLS : CASH RECONCILIATION');
    BEGIN

        -- -----------------------------------------------------
        p_test('CSH-01', 'Purchases and redemptions are backed by a cash movement');
        p_obj('every PRINCIPAL or PRINCIPAL_LIQD entry must come with a leg on');
        po('                   ' || k_ac_nostro || ' or on an account of class ' || k_cl_cash || '. Its absence means the');
        po('                   counterpart of the operation is not the treasury, so no cash left');
        po('                   or entered the bank for a deal the accounts say was settled.');
        p_how('per contract, count of principal tags against count of those');
        po('                   carrying a cash leg.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, MAX(c.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                        THEN 1 ELSE 0 END) n_pr,
                               SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                         AND (h.ac_no = k_ac_nostro
                                              OR SUBSTR(h.ac_no, 1, 2) = k_cl_cash)
                                        THEN 1 ELSE 0 END) n_cash
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no)
                                                                   FROM ldtb_contract_master v
                                                                  WHERE v.contract_ref_no
                                                                        = c.contract_ref_no)
                 WHERE a.n_pr > 0 AND a.n_cash = 0
                 GROUP BY a.ref);
        p_verdict('CSH-01', 'Purchase or redemption with no cash leg',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('PRINCIPAL TAGS, NO CASH');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.n_pr, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                                THEN 1 ELSE 0 END) n_pr,
                                       SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                                 AND (h.ac_no = k_ac_nostro
                                                      OR SUBSTR(h.ac_no, 1, 2) = k_cl_cash)
                                                THEN 1 ELSE 0 END) n_cash
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE a.n_pr > 0 AND a.n_cash = 0
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.n_pr) || ' entries');
            END LOOP;
            sec_foot;
        END IF;

        print_sub('CSH-01 a. Movements to tick against the BEAC statement');
        po('  Movements of the nostro ' || k_ac_nostro || ' carried by the module, largest');
        po('  first. Each line must be found on the statement, same date and same');
        po('  amount. The TICKED column is to be served by hand during the');
        po('  reconciliation.');
        tbl_head('4,24,16,16,20,10,26,12',
                 'N#|CONTRACT|VALUE DATE|BOOKING DATE|AMOUNT TAG|D/C|AMOUNT|TICKED',
                 '|TRN_REF_NO|VALUE_DT|TRN_DT|AMOUNT_TAG|DRCR_IND|LCY_AMOUNT| ',
                 'RLLLLLRL');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT h.trn_ref_no ref, h.value_dt vd, h.trn_dt dt, h.amount_tag,
                           h.drcr_ind, h.lcy_amount mt
                      FROM actb_history h
                     WHERE h.module = k_mod
                       AND h.ac_no = k_ac_nostro
                       AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                     ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                || fpad(fdt(r.vd), 16) || '|' || fpad(fdt(r.dt), 16) || '|'
                || fpad(r.amount_tag, 20) || '|' || fpad(r.drcr_ind, 10) || '|'
                || fpadl(famt(r.mt), 26) || '|' || fpad('[    ]', 12) || '|');
        END LOOP;
        tbl_line('4,24,16,16,20,10,26,12');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no = k_ac_nostro
           AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD');
        print_kv('Principal movements to tick on the statement', fnum(v_cnt));
        print_kv('Cumulative amount to tick',                    fmio(v_mt));

        -- -----------------------------------------------------
        p_test('CSH-02', 'Interest collections are backed by a cash movement');
        p_obj('same reasoning on the interest collection tags. An interest');
        po('                   liquidated in the accounts with no cash movement is income');
        po('                   recognised against a receipt that never arrived.');
        p_how('per contract, count of INT_%_LIQD tags against those carrying a');
        po('                   cash leg.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, MAX(c.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD' THEN 1 ELSE 0 END) n_int,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                         AND (h.ac_no = k_ac_nostro
                                              OR SUBSTR(h.ac_no, 1, 2) = k_cl_cash)
                                        THEN 1 ELSE 0 END) n_cash
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no)
                                                                   FROM ldtb_contract_master v
                                                                  WHERE v.contract_ref_no
                                                                        = c.contract_ref_no)
                 WHERE a.n_int > 0 AND a.n_cash = 0
                 GROUP BY a.ref);
        p_verdict('CSH-02', 'Interest collection with no cash leg',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('COLLECTION TAGS, NO CASH');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.n_int, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                                THEN 1 ELSE 0 END) n_int,
                                       SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                                 AND (h.ac_no = k_ac_nostro
                                                      OR SUBSTR(h.ac_no, 1, 2) = k_cl_cash)
                                                THEN 1 ELSE 0 END) n_cash
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE a.n_int > 0 AND a.n_cash = 0
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, fnum(r.n_int) || ' entries');
            END LOOP;
            sec_foot;
        END IF;
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no = k_ac_nostro
           AND h.amount_tag LIKE 'INT%LIQD';
        print_kv('Interest collections to tick on the statement', fnum(v_cnt));
        print_kv('Cumulative amount to tick',                     fmio(v_mt));

        -- -----------------------------------------------------
        p_test('CSH-03', 'Cancelled contracts: did the cash really move back');
        p_obj('an accounting reversal does not bring the money back. For every');
        po('                   fully reversed contract, the cash that went out and the cash that');
        po('                   came back must both be found on the statement. A deal cancelled in');
        po('                   the books whose cash never returned is a loss nobody has booked.');
        p_how('per fully reversed contract, cash out (credit of the nostro, a');
        po('                   positive amount) and cash back (any negative amount on the nostro).');
        SELECT COUNT(*), NVL(SUM(ABS(cash)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, a.cash
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) bal,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                               SUM(CASE WHEN h.ac_no = k_ac_nostro
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) cash
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                 WHERE a.n_neg > 0 AND a.n_liq = 0 AND ABS(a.bal) <= k_tol_abs);
        p_verdict('CSH-03', 'Cancelled contract whose cash return is still to be proved',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('CASH OUT / CASH BACK');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.out_cash, a.back_cash, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) bal,
                                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0
                                                THEN 1 ELSE 0 END) n_neg,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN 1 ELSE 0 END) n_liq,
                                       SUM(CASE WHEN h.ac_no = k_ac_nostro AND h.drcr_ind = 'C'
                                                 AND NVL(h.lcy_amount, 0) > 0
                                                THEN NVL(h.lcy_amount, 0) ELSE 0 END) out_cash,
                                       SUM(CASE WHEN h.ac_no = k_ac_nostro
                                                 AND NVL(h.lcy_amount, 0) < 0
                                                THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END) back_cash
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE a.n_neg > 0 AND a.n_liq = 0 AND ABS(a.bal) <= k_tol_abs
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fmio(r.out_cash) || ' / ' || fmio(r.back_cash));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 9 : PERIOD END');
    -- ########################################################################
    po('');
    po('  At every reporting date four balance sheet figures must be justified');
    po('  line by line from the live portfolio: the securities, the accrued');
    po('  receivable, the deferred income and the income of the month. The script');
    po('  rebuilds each of them from the entries and from the terms of the deals,');
    po('  and confronts the two.');
    po('');
    po('  LIMIT . the trial balance and the securities position report are not in');
    po('  the database. The final reconciliation with those two statements stays');
    po('  to be done on paper; the script provides the rebuilt figure.');

    print_section('9. CUT CONTROLS : PERIOD END');
    BEGIN
        SELECT MAX(h.trn_dt) INTO v_d_accr
          FROM actb_history h WHERE h.module = k_mod AND h.event = 'ACCR';
        print_kv('Last accrual entry of the module (ACTB_HISTORY)', fdt(v_d_accr));

        -- -----------------------------------------------------
        p_test('CUT-01', 'Accruals run to the last calendar day of the month');
        p_obj('at every month end, a live contract must carry an accrual dated the');
        po('                   last calendar day of the month. A missing month end accrual');
        po('                   understates both the income of the month and the balance sheet.');
        p_how('live contracts at the last month end preceding ' || fdt(v_d_accr) || ', with no');
        po('                   ACCR entry on that date. The test is bounded at that date because');
        po('                   beyond it the module simply stopped accruing.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND c.value_date < TRUNC(v_d_accr, 'MM')
           AND c.maturity_date > LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1))
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = c.contract_ref_no
                              AND h.module = k_mod
                              AND h.event = 'ACCR'
                              AND TRUNC(h.trn_dt)
                                  = LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1)));
        p_verdict('CUT-01', 'Live contract with no accrual at the month end tested',
                  v_cnt, v_nb_ctr, v_mt, 'CRITICAL');
        IF v_cnt > 0 THEN
            sec_head('MONTH END MISSED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND c.value_date < TRUNC(v_d_accr, 'MM')
                           AND c.maturity_date > LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1))
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = c.contract_ref_no
                                              AND h.module = k_mod
                                              AND h.event = 'ACCR'
                                              AND TRUNC(h.trn_dt)
                                                  = LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1)))
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fdt(LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1))));
            END LOOP;
            sec_foot;
        END IF;

        print_sub('CUT-01 a. Month end coverage of the accruals');
        tbl_head('4,18,20,22,18,26',
                 'N#|MONTH END|LIVE CONTRACTS|ACCRUED THAT DAY|COVERAGE|ACCRUAL OF THE DAY',
                 '|TRN_DT| |TRN_REF_NO| |LCY_AMOUNT',
                 'RLRRRR');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT * FROM (
                    SELECT LAST_DAY(TRUNC(h.trn_dt, 'MM')) me, SUM(NVL(h.lcy_amount, 0)) mt,
                           COUNT(DISTINCT h.trn_ref_no) nb_acc
                      FROM actb_history h
                     WHERE h.module = k_mod
                       AND h.event = 'ACCR'
                       AND h.drcr_ind = 'D'
                       AND TRUNC(h.trn_dt) = LAST_DAY(TRUNC(h.trn_dt, 'MM'))
                     GROUP BY LAST_DAY(TRUNC(h.trn_dt, 'MM'))
                     ORDER BY 1 DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            SELECT COUNT(*) INTO v_cnt2
              FROM ldtb_contract_master c
             WHERE c.module = k_mod
               AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = c.contract_ref_no)
               AND c.value_date <= r.me
               AND c.maturity_date > r.me;
            IF r.nb_acc < v_cnt2 THEN
                v_cnt := v_cnt + 1;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.me), 18) || '|'
                || fpadl(fnum(v_cnt2), 20) || '|' || fpadl(fnum(r.nb_acc), 22) || '|'
                || fpadl(fpct(r.nb_acc, v_cnt2), 18) || '|' || fpadl(fmio(r.mt), 26) || '|');
        END LOOP;
        tbl_line('4,18,20,22,18,26');
        p_verdict('CUT-01b', 'Month end at which not every live contract was accrued',
                  v_cnt, v_row, NULL, 'HIGH');

        -- -----------------------------------------------------
        p_test('CUT-02', 'The accruals of the month reach the profit and loss');
        p_obj('the accruals booked in a month must equal the movement of the');
        po('                   income class ' || k_cl_income || ' over the same month. A gap means an accrual that');
        po('                   never found its income account, or income recognised with no');
        po('                   accrual behind it.');
        p_how('per month, accrual debits on classes ' || k_cl_accr_pl || ' and ' || k_cl_accr_tr || ' against the net');
        po('                   income of class ' || k_cl_income || '. Pre counted deals feed the income from the');
        po('                   deferred account instead, which explains part of any gap.');
        tbl_head('4,14,20,26,26,26,14',
                 'N#|MONTH|ACCRUAL ENTRIES|ACCRUALS OF THE MONTH|INCOME OF THE MONTH|GAP|VERDICT',
                 '|TRN_DT| |LCY_AMOUNT|LCY_AMOUNT| | ',
                 'RLRRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT * FROM (
                    SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mth,
                           SUM(CASE WHEN h.event = 'ACCR' AND h.drcr_ind = 'D'
                                     AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                                    THEN NVL(h.lcy_amount, 0) ELSE 0 END) accr,
                           COUNT(CASE WHEN h.event = 'ACCR' AND h.drcr_ind = 'D'
                                       AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                                      THEN 1 END) nb,
                           SUM(CASE WHEN SUBSTR(h.ac_no, 1, 3) = k_cl_income
                                    THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END
                                    ELSE 0 END) inc
                      FROM actb_history h
                     WHERE h.module = k_mod
                     GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM')
                     ORDER BY 1 DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            IF ABS(r.accr - r.inc) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(r.accr - r.inc);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mth, 14) || '|'
                || fpadl(fnum(r.nb), 20) || '|' || fpadl(fmio(r.accr), 26) || '|'
                || fpadl(fmio(r.inc), 26) || '|' || fpadl(famt(r.accr - r.inc), 26) || '|'
                || fpadl(CASE WHEN ABS(r.accr - r.inc) > k_tol_abs THEN 'GAP' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,14,20,26,26,26,14');
        p_verdict('CUT-02', 'Month whose accruals do not reach the profit and loss',
                  v_cnt, v_row, v_mt, 'CRITICAL');

        -- -----------------------------------------------------
        p_test('CUT-03', 'Security balances are justified by the live portfolio');
        p_obj('for each security account, the signed accounting balance must equal');
        po('                   the sum of the nominals of the live contracts attached to it. The');
        po('                   rebuilt figure below is the one to confront with the securities');
        po('                   position report.');
        p_how('per account, signed balance from ACTB_HISTORY against the sum of');
        po('                   LCY_AMOUNT of the contracts still alive at ' || fdt(k_asof) || '.');
        tbl_head('4,22,14,38,28,28,26,14',
                 'N#|ACCOUNT|CLASS|ACCOUNT NAME|ACCOUNTING BALANCE|REBUILT POSITION|GAP|VERDICT',
                 '|AC_NO| |AC_GL_DESC|LCY_AMOUNT|LCY_AMOUNT| | ',
                 'RLLLRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT 1 ord, k_ac_bond_pl ac, 'OTAP' prod FROM DUAL UNION ALL
                  SELECT 2, k_ac_bill_pl, 'MTPD' FROM DUAL UNION ALL
                  SELECT 3, k_ac_bill_tr, 'TBTR,BTTR' FROM DUAL
                  ORDER BY 1) LOOP
            SELECT NVL(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                           ELSE -NVL(h.lcy_amount, 0) END), 0)
              INTO v_tot
              FROM actb_history h
             WHERE h.module = k_mod AND h.ac_no = r.ac;
            SELECT NVL(SUM(c.lcy_amount), 0) INTO v_tot2
              FROM ldtb_contract_master c
             WHERE c.module = k_mod
               AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = c.contract_ref_no)
               AND c.maturity_date > k_asof
               AND INSTR(',' || r.prod || ',', ',' || TRIM(c.product) || ',') > 0
               AND EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = c.contract_ref_no
                              AND h.module = k_mod
                              AND h.ac_no = r.ac);
            SELECT MAX(a.ac_gl_desc) INTO v_lib FROM sttb_account a WHERE a.ac_gl_no = r.ac;
            v_row := v_row + 1;
            IF ABS(v_tot - v_tot2) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(v_tot - v_tot2);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac, 22) || '|'
                || fpad(SUBSTR(r.ac, 1, 4), 14) || '|' || fpad(v_lib, 38) || '|'
                || fpadl(fmio(v_tot), 28) || '|' || fpadl(fmio(v_tot2), 28) || '|'
                || fpadl(famt(v_tot - v_tot2), 26) || '|'
                || fpadl(CASE WHEN ABS(v_tot - v_tot2) > k_tol_abs THEN 'GAP' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,22,14,38,28,28,26,14');
        p_verdict('CUT-03', 'Security account whose balance is not justified by the portfolio',
                  v_cnt, v_row, v_mt, 'CRITICAL');

        -- -----------------------------------------------------
        p_test('CUT-04', 'Deferred income equals the unearned interest of the live book');
        p_obj('for pre counted deals, the balance of class ' || k_cl_defer || ' must equal the');
        po('                   share of interest not yet earned on the live contracts, that is');
        po('                   interest times days remaining divided by the tenor. A residue');
        po('                   carried by a matured deal is a release that never happened.');
        p_how('signed balance of class ' || k_cl_defer || ' from ACTB_HISTORY against the rebuilt');
        po('                   unearned interest of the live pre counted contracts.');
        SELECT NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0)
          INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod
           AND SUBSTR(h.ac_no, 1, 4) = k_cl_defer;
        SELECT NVL(SUM(ROUND(NVL(c.main_comp_amount, 0)
                             * (TRUNC(c.maturity_date) - TRUNC(k_asof))
                             / NULLIF(c.maturity_date - c.value_date, 0), 2)), 0)
          INTO v_tot2
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND c.maturity_date > k_asof
           AND INSTR(',' || k_prod_pre || ',', ',' || TRIM(c.product) || ',') > 0;
        print_kv('Accounting balance of the deferred income',        fmio(v_tot));
        print_kv('Unearned interest of the live pre counted deals',  fmio(v_tot2));
        print_kv('Gap',                                              famt(v_tot - v_tot2));
        IF ABS(v_tot - v_tot2) > k_tol_abs THEN v_cnt := 1; ELSE v_cnt := 0; END IF;
        p_verdict('CUT-04', 'Deferred income not justified by the live contracts',
                  v_cnt, 1, ABS(v_tot - v_tot2), 'CRITICAL');
        IF v_cnt > 0 THEN
            print_sub('CUT-04 a. Deferred income still carried by matured deals');
            sec_head('DEFERRED LEFT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_def, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) bal_def
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND SUBSTR(h.ac_no, 1, 4) = k_cl_defer
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE c.maturity_date <= k_asof
                           AND ABS(a.bal_def) > k_tol_abs
                         ORDER BY ABS(a.bal_def) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, famt(r.bal_def));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('CUT-05', 'Accrued receivable equals the uncollected interest of the live book');
        p_obj('for post counted deals, the balance of classes ' || k_cl_accr_pl || ' and ' || k_cl_accr_tr || ' must');
        po('                   equal the interest earned and not yet collected on the live');
        po('                   contracts. The theoretical figure is bounded at ' || fdt(v_d_accr) || ', the module');
        po('                   having stopped accruing after that date.');
        p_how('signed balance of the accrued classes from ACTB_HISTORY against');
        po('                   the rebuilt earned interest of the live post counted contracts.');
        SELECT NVL(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0)
          INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod
           AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr);
        SELECT NVL(SUM(ROUND(NVL(c.main_comp_amount, 0)
                             * (TRUNC(LEAST(v_d_accr, c.maturity_date)) - TRUNC(c.value_date))
                             / NULLIF(c.maturity_date - c.value_date, 0), 2)), 0)
          INTO v_tot2
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND c.maturity_date > k_asof
           AND c.value_date < v_d_accr
           AND INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0;
        print_kv('Accounting balance of the accrued receivable',        fmio(v_tot));
        print_kv('Earned and uncollected interest of the live deals',   fmio(v_tot2));
        print_kv('Gap',                                                 famt(v_tot - v_tot2));
        IF ABS(v_tot - v_tot2) > k_tol_abs THEN v_cnt := 1; ELSE v_cnt := 0; END IF;
        p_verdict('CUT-05', 'Accrued receivable not justified by the live contracts',
                  v_cnt, 1, ABS(v_tot - v_tot2), 'CRITICAL');
        IF v_cnt > 0 THEN
            print_sub('CUT-05 a. Live deals whose accrued receivable differs from the theory');
            sec_head('BOOKED / THEORY');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.bal_accr, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               ROUND(NVL(c.main_comp_amount, 0)
                                     * (TRUNC(LEAST(v_d_accr, c.maturity_date)) - TRUNC(c.value_date))
                                     / NULLIF(c.maturity_date - c.value_date, 0), 2) th
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) bal_accr
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND SUBSTR(h.ac_no, 1, 4) IN (k_cl_accr_pl, k_cl_accr_tr)
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE c.maturity_date > k_asof
                           AND c.value_date < v_d_accr
                           AND INSTR(',' || k_prod_post || ',', ',' || TRIM(c.product) || ',') > 0
                           AND ABS(a.bal_accr
                                   - ROUND(NVL(c.main_comp_amount, 0)
                                           * (TRUNC(LEAST(v_d_accr, c.maturity_date))
                                              - TRUNC(c.value_date))
                                           / NULLIF(c.maturity_date - c.value_date, 0), 2)) > k_tol_abs
                         ORDER BY ABS(a.bal_accr) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fmio(r.bal_accr) || ' / ' || fmio(r.th));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 10 : CLASSIFICATION AND VALUATION');
    -- ########################################################################
    po('');
    po('  Classifying a security in the investment book (class ' || k_cl_invest || ') or in the');
    po('  trading book (class ' || k_cl_trading || ') decides its accounting treatment: a trading');
    po('  security is marked to market, an investment security is amortised. The');
    po('  classification is decided at inception and does not change.');

    print_section('10. CLS CONTROLS : CLASSIFICATION AND VALUATION');
    BEGIN

        -- -----------------------------------------------------
        p_test('CLS-01', 'The investment or trading classification is stable');
        p_obj('a contract must touch one and only one of the two security book');
        po('                   families over its whole life. A contract touching both has changed');
        po('                   book, and that transfer must be approved and documented: it moves');
        po('                   the security from an amortised treatment to a marked one.');
        p_how('per contract, count of entries on classes ' || k_cl_invest || ' and on class '
            || k_cl_trading || ',');
        po('                   read from ACTB_HISTORY, flagged when both are present.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT a.ref, MAX(c.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                             IN (k_cl_bond_pl, k_cl_bill_pl) THEN 1 ELSE 0 END) n_inv,
                               SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4) = k_cl_bill_tr
                                        THEN 1 ELSE 0 END) n_trd
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) a
                  JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                             AND c.version_no = (SELECT MAX(v.version_no)
                                                                   FROM ldtb_contract_master v
                                                                  WHERE v.contract_ref_no
                                                                        = c.contract_ref_no)
                 WHERE a.n_inv > 0 AND a.n_trd > 0
                 GROUP BY a.ref);
        p_verdict('CLS-01', 'Contract having touched both the investment and the trading book',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('BOTH BOOKS TOUCHED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ref, a.n_inv, a.n_trd, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                     IN (k_cl_bond_pl, k_cl_bill_pl)
                                                THEN 1 ELSE 0 END) n_inv,
                                       SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4) = k_cl_bill_tr
                                                THEN 1 ELSE 0 END) n_trd
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) a
                          JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                     AND c.version_no = (SELECT MAX(v.version_no)
                                                                           FROM ldtb_contract_master v
                                                                          WHERE v.contract_ref_no
                                                                                = c.contract_ref_no)
                         WHERE a.n_inv > 0 AND a.n_trd > 0
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        fnum(r.n_inv) || ' inv / ' || fnum(r.n_trd) || ' trd');
            END LOOP;
            sec_foot;
        END IF;
        print_sub('CLS-01 a. The portfolio split between the two books');
        tbl_head('4,12,26,20,28,18',
                 'N#|PRODUCT|BOOK|CONTRACTS|NOMINAL|SHARE',
                 '|PRODUCT| |TRN_REF_NO|LCY_AMOUNT| ',
                 'RLLRRR');
        v_row := 0;
        FOR r IN (SELECT p.prod, p.book, COUNT(*) nb, SUM(p.nom) mt FROM (
                    SELECT a.ref, MAX(c.product) prod, MAX(c.lcy_amount) nom,
                           CASE WHEN MAX(a.n_inv) > 0 AND MAX(a.n_trd) > 0 THEN 'both books'
                                WHEN MAX(a.n_inv) > 0 THEN 'investment (' || k_cl_invest || ')'
                                WHEN MAX(a.n_trd) > 0 THEN 'trading (' || k_cl_trading || ')'
                                ELSE 'no security account' END book
                      FROM (SELECT h.trn_ref_no ref,
                                   SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4)
                                                 IN (k_cl_bond_pl, k_cl_bill_pl)
                                            THEN 1 ELSE 0 END) n_inv,
                                   SUM(CASE WHEN SUBSTR(h.ac_no, 1, 4) = k_cl_bill_tr
                                            THEN 1 ELSE 0 END) n_trd
                              FROM actb_history h
                             WHERE h.module = k_mod
                             GROUP BY h.trn_ref_no) a
                      JOIN ldtb_contract_master c ON c.contract_ref_no = a.ref
                                                 AND c.version_no = (SELECT MAX(v.version_no)
                                                                       FROM ldtb_contract_master v
                                                                      WHERE v.contract_ref_no
                                                                            = c.contract_ref_no)
                     GROUP BY a.ref) p
                   GROUP BY p.prod, p.book
                   ORDER BY SUM(p.nom) DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 12) || '|'
                || fpad(r.book, 26) || '|' || fpadl(fnum(r.nb), 20) || '|'
                || fpadl(fmio(r.mt), 28) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 18) || '|');
        END LOOP;
        tbl_line('4,12,26,20,28,18');

        -- -----------------------------------------------------
        p_test('CLS-02', 'Trading securities are valued if the policy requires it');
        p_obj('a security classified as trading is marked to market at every');
        po('                   reporting date. A complete absence of valuation entries on class');
        po('                   ' || k_cl_trading || ' is a finding in itself: either the accounting policy does not');
        po('                   require it and the trading classification is to be challenged, or');
        po('                   it does and the valuation is simply not being done.');
        p_how('valuation entries looked for in ACTB_HISTORY on the trading class,');
        po('                   and in RVTB_ACC_REVAL, the revaluation table.');
        SELECT COUNT(*) INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod AND SUBSTR(h.ac_no, 1, 4) = k_cl_bill_tr;
        print_kv('Entries on the trading security account', fnum(v_tot));
        v_cnt := 0;
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM rvtb_acc_reval z
             WHERE z.account = k_ac_bill_tr
                OR z.reval_account = k_ac_bill_tr
                OR z.pnl_account = k_ac_bill_tr;
            print_kv('Valuation entries in RVTB_ACC_REVAL', fnum(v_cnt));
        EXCEPTION
            WHEN OTHERS THEN po('    !! RVTB_ACC_REVAL not readable : ' || SQLERRM);
        END;
        SELECT COUNT(*) INTO v_cnt2
          FROM actb_history h
         WHERE h.module = k_mod
           AND SUBSTR(h.ac_no, 1, 4) = k_cl_bill_tr
           AND (h.event LIKE '%VAL%' OR h.amount_tag LIKE '%REVAL%');
        print_kv('Valuation entries inside the module', fnum(v_cnt2));
        p_verdict('CLS-02', 'No valuation at all on the securities classified as trading',
                  CASE WHEN v_tot > 0 AND v_cnt + v_cnt2 = 0 THEN 1 ELSE 0 END,
                  1, NULL, 'HIGH');

        -- -----------------------------------------------------
        p_test('CLS-03', 'Premium or discount on the purchase of bonds');
        p_obj('if the amount debited to the security account at inception differs');
        po('                   from the nominal of the contract, the bond was bought above or');
        po('                   below par. The difference is a premium or a discount to be');
        po('                   amortised over the life, not left as it is.');
        p_how('signed debit of the PRINCIPAL tag on ' || k_ac_bond_pl || ' against LCY_AMOUNT,');
        po('                   for the bond products only.');
        SELECT COUNT(*), NVL(SUM(ABS(gap)), 0) INTO v_cnt, v_mt
          FROM (SELECT c.contract_ref_no,
                       NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                       ELSE -NVL(h.lcy_amount, 0) END)
                              FROM actb_history h
                             WHERE h.trn_ref_no = c.contract_ref_no
                               AND h.module = k_mod
                               AND h.amount_tag = 'PRINCIPAL'
                               AND SUBSTR(h.ac_no, 1, 4) = k_cl_bond_pl), 0)
                       - NVL(c.lcy_amount, 0) gap
                  FROM ldtb_contract_master c
                 WHERE c.module = k_mod
                   AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                   AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = c.contract_ref_no)
                   AND INSTR(',' || k_prod_bond || ',', ',' || TRIM(c.product) || ',') > 0
                   AND EXISTS (SELECT 1 FROM actb_history h
                                WHERE h.trn_ref_no = c.contract_ref_no
                                  AND h.module = k_mod
                                  AND h.amount_tag = 'PRINCIPAL'))
         WHERE ABS(gap) > k_tol_abs;
        p_verdict('CLS-03', 'Bond bought off par, premium or discount to amortise',
                  v_cnt, v_nb_ctr, v_mt, 'MEDIUM');
        IF v_cnt > 0 THEN
            sec_head('BOOKED / PREMIUM');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                               ELSE -NVL(h.lcy_amount, 0) END)
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = c.contract_ref_no
                                       AND h.module = k_mod
                                       AND h.amount_tag = 'PRINCIPAL'
                                       AND SUBSTR(h.ac_no, 1, 4) = k_cl_bond_pl), 0) booked
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND INSTR(',' || k_prod_bond || ',', ',' || TRIM(c.product) || ',') > 0
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = c.contract_ref_no
                                          AND h.module = k_mod
                                          AND h.amount_tag = 'PRINCIPAL')
                           AND ABS(NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)
                                          FROM actb_history h
                                         WHERE h.trn_ref_no = c.contract_ref_no
                                           AND h.module = k_mod
                                           AND h.amount_tag = 'PRINCIPAL'
                                           AND SUBSTR(h.ac_no, 1, 4) = k_cl_bond_pl), 0)
                                    - NVL(c.lcy_amount, 0)) > k_tol_abs
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        famt(r.booked) || ' / ' || famt(r.booked - r.lcy_amount));
            END LOOP;
            sec_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 11 : STATIC DATA AND LIMITS');
    -- ########################################################################
    po('');
    po('  Capture errors on the terms of a deal propagate to everything that');
    po('  follows: interest, accruals, schedule, accounting. They are caught');
    po('  upstream, on the contract itself, before any entry is produced.');
    po('');
    po('  This is the one part that reads LDTB_CONTRACT_MASTER as the subject and');
    po('  not as a reference, because the terms of the deal are exactly what it is');
    po('  authoritative for.');

    print_section('11. STA CONTROLS : STATIC DATA AND LIMITS');
    BEGIN

        -- -----------------------------------------------------
        p_test('STA-01', 'Date consistency: booking, value and maturity');
        p_obj('the chain BOOKING_DATE at or before VALUE_DATE, itself before');
        po('                   MATURITY_DATE, must always hold. A nil or negative tenor makes the');
        po('                   interest calculation impossible; a value date long before the');
        po('                   booking date means interest ran before the deal was recorded.');
        p_how('the three dates of the last contract version, with a tolerance of');
        po('                   ' || TO_CHAR(k_retro_d) || ' days on the back valuation, which covers the normal');
        po('                   settlement lag.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND (c.maturity_date <= c.value_date
                OR TRUNC(c.booking_date) - TRUNC(c.value_date) > k_retro_d
                OR c.value_date IS NULL
                OR c.maturity_date IS NULL
                OR c.booking_date IS NULL);
        p_verdict('STA-01', 'Inconsistent date chain or nil tenor',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            sec_head('INCONSISTENCY');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date,
                               CASE WHEN c.value_date IS NULL THEN 'VALUE DATE MISSING'
                                    WHEN c.maturity_date IS NULL THEN 'MATURITY MISSING'
                                    WHEN c.booking_date IS NULL THEN 'BOOKING DATE MISSING'
                                    WHEN c.maturity_date <= c.value_date THEN 'NIL OR NEGATIVE TENOR'
                                    ELSE 'BACK VALUED '
                                         || TO_CHAR(TRUNC(c.booking_date)
                                                    - TRUNC(c.value_date)) || ' d' END why
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND (c.maturity_date <= c.value_date
                                OR TRUNC(c.booking_date) - TRUNC(c.value_date) > k_retro_d
                                OR c.value_date IS NULL
                                OR c.maturity_date IS NULL
                                OR c.booking_date IS NULL)
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date, r.why);
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('STA-02', 'No deal booked twice under two references');
        p_obj('two contracts carrying the same counterparty, product, nominal,');
        po('                   rate, value date and maturity are either a deal deliberately split');
        po('                   or a double capture. A double capture doubles the position and the');
        po('                   cash that went out with it.');
        p_how('groups of more than one contract sharing those six terms.');
        SELECT COUNT(*), NVL(SUM(mt), 0) INTO v_cnt, v_mt
          FROM (SELECT COUNT(*) nb, SUM(c.lcy_amount) mt
                  FROM ldtb_contract_master c
                 WHERE c.module = k_mod
                   AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                   AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = c.contract_ref_no)
                 GROUP BY c.counterparty, c.product, c.lcy_amount,
                          NVL(c.main_comp_rate, -1), c.value_date, c.maturity_date
                HAVING COUNT(*) > 1);
        p_verdict('STA-02', 'Group of contracts identical on nominal, rate and dates',
                  v_cnt, v_nb_ctr, v_mt, 'HIGH');
        IF v_cnt > 0 THEN
            tbl_head('4,16,12,26,14,16,16,10,28,52',
                     'N#|ISSUER|PRODUCT|NOMINAL|RATE|VALUE|MATURITY|COUNT|TOTAL|REFERENCES',
                     '|COUNTERPARTY|PRODUCT|LCY_AMOUNT|MAIN_COMP_RATE|VALUE_DATE|MATURITY_DATE| |'
                     || ' |CONTRACT_REF_NO',
                     'RLLRRLLRRL');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.counterparty cif, c.product, c.lcy_amount nom,
                               c.main_comp_rate rate, c.value_date vd, c.maturity_date md,
                               COUNT(*) nb, SUM(c.lcy_amount) mt,
                               MIN(c.contract_ref_no) || '  ...  '
                                 || MAX(c.contract_ref_no) refs
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                         GROUP BY c.counterparty, c.product, c.lcy_amount,
                                  c.main_comp_rate, c.value_date, c.maturity_date
                        HAVING COUNT(*) > 1
                         ORDER BY SUM(c.lcy_amount) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cif, 16) || '|'
                    || fpad(r.product, 12) || '|' || fpadl(famt(r.nom), 26) || '|'
                    || fpadl(ftx(r.rate), 14) || '|' || fpad(fdt(r.vd), 16) || '|'
                    || fpad(fdt(r.md), 16) || '|' || fpadl(fnum(r.nb), 10) || '|'
                    || fpadl(famt(r.mt), 28) || '|' || fpad(r.refs, 52) || '|');
            END LOOP;
            tbl_line('4,16,12,26,14,16,16,10,28,52');
        END IF;

        -- -----------------------------------------------------
        p_test('STA-03', 'Amounts and rates captured with the right unit');
        p_obj('MAIN_COMP_RATE must be stored as a percentage (6.25) and not as a');
        po('                   decimal (0.0625). A rate below ' || ftx(k_rate_dec) || ' on a sovereign portfolio is the');
        po('                   symptom of a decimal capture, which would divide the interest by a');
        po('                   hundred and understate the income of the whole deal.');
        p_how('distribution of MAIN_COMP_RATE across four ranges, and the deals');
        po('                   below ' || ftx(k_rate_dec) || ' listed one by one.');
        SELECT COUNT(*), NVL(SUM(c.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master c
         WHERE c.module = k_mod
           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = c.contract_ref_no)
           AND NVL(c.main_comp_rate, 0) > 0
           AND c.main_comp_rate < k_rate_dec;
        p_verdict('STA-03', 'Rate apparently captured as a decimal instead of a percentage',
                  v_cnt, v_nb_ctr, v_mt, 'MEDIUM');
        print_sub('STA-03 a. Rate capture convention across the portfolio');
        tbl_head('4,44,20,16,18,18',
                 'N#|RATE RANGE|CONTRACTS|SHARE|MINIMUM|MAXIMUM',
                 '|MAIN_COMP_RATE|TRN_REF_NO| |MAIN_COMP_RATE|MAIN_COMP_RATE',
                 'RLRRRR');
        v_row := 0;
        FOR r IN (SELECT rg, COUNT(*) nb, MIN(rate) rmin, MAX(rate) rmax FROM (
                    SELECT c.main_comp_rate rate,
                           CASE WHEN c.main_comp_rate IS NULL THEN '4. rate not populated'
                                WHEN c.main_comp_rate = 0 THEN '3. rate nil'
                                WHEN c.main_comp_rate < k_rate_dec
                                     THEN '1. below one, decimal capture likely'
                                ELSE '2. one or above, captured as a percentage' END rg
                      FROM ldtb_contract_master c
                     WHERE c.module = k_mod
                       AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                       AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = c.contract_ref_no))
                   GROUP BY rg ORDER BY rg) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.rg, 44) || '|'
                || fpadl(fnum(r.nb), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 16) || '|'
                || fpadl(ftx(r.rmin), 18) || '|' || fpadl(ftx(r.rmax), 18) || '|');
        END LOOP;
        tbl_line('4,44,20,16,18,18');
        IF v_cnt > 0 THEN
            sec_head('RATE AS CAPTURED');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.product, c.counterparty,
                               (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                 WHERE x.customer_no = c.counterparty) issuer,
                               c.lcy_amount, c.main_comp_rate, c.booking_date,
                               c.value_date, c.maturity_date
                          FROM ldtb_contract_master c
                         WHERE c.module = k_mod
                           AND c.booking_date BETWEEN k_dt_from AND k_dt_to
                           AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = c.contract_ref_no)
                           AND NVL(c.main_comp_rate, 0) > 0
                           AND c.main_comp_rate < k_rate_dec
                         ORDER BY c.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                sec_row(v_row, r.ref, r.product, r.issuer, r.lcy_amount, r.main_comp_rate,
                        r.booking_date, r.value_date, r.maturity_date,
                        TO_CHAR(r.main_comp_rate));
            END LOOP;
            sec_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('STA-04', 'Issuer concentration stays within the limits');
        p_obj('live exposure per sovereign issuer against the limit set by the ALM');
        po('                   committee (' || fmio(k_conc_lim) || '). A breach is a risk the committee has not');
        po('                   authorised, on a counterparty the bank cannot diversify away.');
        p_how('sum of LCY_AMOUNT of the contracts still alive at ' || fdt(k_asof) || ', per');
        po('                   counterparty. THE LIMIT IS A PARAMETER OF THIS SCRIPT: align it');
        po('                   with the committee decision before concluding.');
        tbl_head('4,16,34,20,28,28,18,14',
                 'N#|CIF|ISSUER|CONTRACTS|LIVE EXPOSURE|ALM LIMIT|UTILISATION|VERDICT',
                 '|COUNTERPARTY|CUSTOMER_NAME1|TRN_REF_NO|LCY_AMOUNT| | | ',
                 'RLLRRRRR');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT c.counterparty cif,
                         MAX((SELECT MAX(x.customer_name1) FROM sttm_customer x
                               WHERE x.customer_no = c.counterparty)) issuer,
                         COUNT(*) nb, SUM(c.lcy_amount) mt
                    FROM ldtb_contract_master c
                   WHERE c.module = k_mod
                     AND c.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                          WHERE v.contract_ref_no = c.contract_ref_no)
                     AND c.maturity_date > k_asof
                   GROUP BY c.counterparty
                   ORDER BY SUM(c.lcy_amount) DESC) LOOP
            v_row := v_row + 1;
            IF r.mt > k_conc_lim THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + (r.mt - k_conc_lim);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cif, 16) || '|'
                || fpad(r.issuer, 34) || '|' || fpadl(fnum(r.nb), 20) || '|'
                || fpadl(fmio(r.mt), 28) || '|' || fpadl(fmio(k_conc_lim), 28) || '|'
                || fpadl(fpct(r.mt, k_conc_lim), 18) || '|'
                || fpadl(CASE WHEN r.mt > k_conc_lim THEN 'BREACHED' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,16,34,20,28,28,18,14');
        p_verdict('STA-04', 'Issuer whose live exposure breaches the ALM limit',
                  v_cnt, v_row, v_mt, 'HIGH');

        -- -----------------------------------------------------
        p_test('STA-05', 'The nature of an entry is read from AMOUNT_TAG');
        p_obj('a control report must never identify the nature of an entry from a');
        po('                   narrative. ACTB_HISTORY carries no description column at all in');
        po('                   this database, so the nature is read from AMOUNT_TAG, which must');
        po('                   therefore be populated on every line.');
        p_how('fill rate of AMOUNT_TAG and inventory of the tags actually used.');
        SELECT COUNT(*), SUM(CASE WHEN TRIM(h.amount_tag) IS NULL THEN 1 ELSE 0 END),
               COUNT(DISTINCT h.amount_tag)
          INTO v_tot, v_cnt, v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        print_kv('Entries of the module',            fnum(v_tot));
        print_kv('Of which carry no amount tag',     fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        print_kv('Distinct amount tags in use',      fnum(v_cnt2));
        po('     This report keys every accounting control on AMOUNT_TAG and on');
        po('     AC_NO, never on a narrative.');
        p_verdict('STA-05', 'Entry with no amount tag, therefore not qualifiable',
                  v_cnt, v_tot, NULL, 'LOW');
        tbl_head('4,24,18,18,28,18,18',
                 'N#|AMOUNT TAG|ENTRIES|CONTRACTS|AMOUNT|FIRST ENTRY|LAST ENTRY',
                 '|AMOUNT_TAG| |TRN_REF_NO|LCY_AMOUNT|TRN_DT|TRN_DT',
                 'RLRRRLL');
        v_row := 0;
        FOR r IN (SELECT h.amount_tag, COUNT(*) nb, COUNT(DISTINCT h.trn_ref_no) nbc,
                         SUM(NVL(h.lcy_amount, 0)) mt, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                    FROM actb_history h
                   WHERE h.module = k_mod
                   GROUP BY h.amount_tag
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.amount_tag, 24) || '|'
                || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nbc), 18) || '|'
                || fpadl(fmio(r.mt), 28) || '|' || fpad(fdt(r.d1), 18) || '|'
                || fpad(fdt(r.d2), 18) || '|');
        END LOOP;
        tbl_line('4,24,18,18,28,18,18');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERRUPTED : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PART 12 : SUMMARY OF ALL TESTS');
    -- ########################################################################

    print_section('12. SUMMARY');
    BEGIN
        po('  Every control run, in the order of the report. CASES is the number of');
        po('  occurrences found, BASE the population it is measured against, and');
        po('  AMOUNT the financial exposure where it can be quantified.');
        po('');
        tbl_head('4,18,62,14,14,10,24,12,16',
                 'N#|CODE|CONTROL|CASES|BASE|SHARE|AMOUNT|SEVERITY|VERDICT',
                 '| | | | | | | | ',
                 'RLLRRRRLR');
        FOR i IN 1 .. g_n LOOP
            po('  |' || fpadl(TO_CHAR(i), 4) || '|' || fpad(g_res(i).code, 18) || '|'
                || fpad(g_res(i).lib, 62) || '|' || fpadl(fnum(g_res(i).nb), 14) || '|'
                || fpadl(CASE WHEN NVL(g_res(i).base, 0) > 0
                              THEN fnum(g_res(i).base) ELSE '-' END, 14) || '|'
                || fpadl(CASE WHEN NVL(g_res(i).base, 0) > 0
                              THEN fpct(g_res(i).nb, g_res(i).base) ELSE '-' END, 10) || '|'
                || fpadl(CASE WHEN g_res(i).mt IS NULL THEN '-'
                              ELSE fmio(g_res(i).mt) END, 24) || '|'
                || fpad(CASE WHEN g_res(i).nb = 0 THEN '-' ELSE g_res(i).crit END, 12) || '|'
                || fpadl(CASE WHEN g_res(i).nb = 0 THEN 'PASS'
                              WHEN g_res(i).crit = 'INFO' THEN 'INFORMATION'
                              ELSE 'FINDING' END, 16) || '|');
        END LOOP;
        tbl_line('4,18,62,14,14,10,24,12,16');

        print_sub('12.1 Headline counts');
        print_kv('Controls run',                            fnum(g_n));
        print_kv('Controls with no finding',                fnum(g_n - g_find));
        print_kv('Controls raising at least one case',      fnum(g_find));
        print_kv('Of which CRITICAL or HIGH',               fnum(g_sev));

        print_sub('12.2 Findings by severity');
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

        print_sub('12.3 The ten findings carrying the largest exposure');
        tbl_head('4,18,62,14,28,12',
                 'N#|CODE|CONTROL|CASES|AMOUNT|SEVERITY',
                 '| | | | | ',
                 'RLLRRL');
        DECLARE
            v_used  VARCHAR2(4000) := ',';
            v_bi    PLS_INTEGER;
            v_bv    NUMBER;
        BEGIN
            FOR n IN 1 .. 10 LOOP
                v_bi := 0;
                v_bv := -1;
                FOR i IN 1 .. g_n LOOP
                    IF g_res(i).nb > 0
                       AND NVL(g_res(i).mt, 0) > v_bv
                       AND INSTR(v_used, ',' || TO_CHAR(i) || ',') = 0 THEN
                        v_bi := i;
                        v_bv := NVL(g_res(i).mt, 0);
                    END IF;
                END LOOP;
                EXIT WHEN v_bi = 0;
                v_used := v_used || TO_CHAR(v_bi) || ',';
                po('  |' || fpadl(TO_CHAR(n), 4) || '|' || fpad(g_res(v_bi).code, 18) || '|'
                    || fpad(g_res(v_bi).lib, 62) || '|' || fpadl(fnum(g_res(v_bi).nb), 14) || '|'
                    || fpadl(fmio(g_res(v_bi).mt), 28) || '|'
                    || fpad(g_res(v_bi).crit, 12) || '|');
            END LOOP;
        END;
        tbl_line('4,18,62,14,28,12');

        print_sub('12.4 Coverage of the control matrix');
        po('  The matrix holds 56 references: LC-01 to LC-06 from the accounting');
        po('  analysis of the transaction life cycle, and the 50 controls of the');
        po('  audit framework. Where two references test the same object, one test');
        po('  carries both codes and runs once, so nothing is counted twice.');
        po('');
        tbl_head('4,10,52,10,18,22',
                 'N#|FAMILY|SCOPE OF THE FAMILY|COUNT|PART|CLOSED IN THE DATABASE',
                 '| | | | | ',
                 'RLLRLL');
        FOR r IN (
            SELECT n, fam, obj, nb, prt, closed FROM (
                SELECT 1 n, 'LC' fam, 'Life cycle, from the accounting analysis' obj,
                       '6' nb, '2' prt, 'yes' closed FROM DUAL UNION ALL
                SELECT 2, 'LIF', 'Life cycle of the positions on the balance sheet',
                       '7', '2', 'yes' FROM DUAL UNION ALL
                SELECT 3, 'EXT', 'Extraction integrity and completeness',
                       '4', '3', 'yes' FROM DUAL UNION ALL
                SELECT 4, 'DBL', 'Double entry at three nested levels',
                       '4', '4', 'yes' FROM DUAL UNION ALL
                SELECT 5, 'MAP', 'Account mapping against the expected scheme',
                       '6', '5', 'yes' FROM DUAL UNION ALL
                SELECT 6, 'INT', 'Interest accuracy and pace',
                       '7', '2 and 6', 'yes' FROM DUAL UNION ALL
                SELECT 7, 'REV', 'Reversals, cancellations and amendments',
                       '6', '2 and 7', 'yes' FROM DUAL UNION ALL
                SELECT 8, 'CSH', 'Cash reconciliation',
                       '3', '8', 'partly, BEAC statement needed' FROM DUAL UNION ALL
                SELECT 9, 'CUT', 'Period end and justification of the balances',
                       '5', '9', 'partly, trial balance needed' FROM DUAL UNION ALL
                SELECT 10, 'CLS', 'Classification and valuation',
                       '3', '10', 'partly, accounting policy needed' FROM DUAL UNION ALL
                SELECT 11, 'STA', 'Static data, duplicates and limits',
                       '5', '11', 'yes, ALM limit to be set' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.fam, 10) || '|'
                || fpad(r.obj, 52) || '|' || fpadl(r.nb, 10) || '|'
                || fpad(r.prt, 18) || '|' || fpad(r.closed, 22) || '|');
        END LOOP;
        tbl_line('4,10,52,10,18,22');
        po('');
        po('  Three tests carry two matrix references each:');
        po('    LC-01 / LIF-02   security account nil after redemption');
        po('    LC-03 / LIF-03   accrued receivable cleared after collection');
        po('    LC-02 / LIF-04   deferred income released at maturity');
        po('  and three more carry a second reference on their own:');
        po('    LC-04 also covers INT-01, income over the life against the deal');
        po('    LC-06 also covers INT-04, no accrual outside the life');
        po('    LC-05 also covers REV-01, negative entries matched to their original');

        print_sub('12.5 Scope reviewed');
        print_kv('Module audited',              k_mod);
        print_kv('Audited period',              fdt(k_dt_from) || ' to ' || fdt(k_dt_to));
        print_kv('Reporting date',              fdt(k_asof));
        print_kv('Contracts retained',          fnum(v_nb_ctr));
        print_kv('Cumulative nominal',          famt(v_mt_ctr) || ' XAF (' || fmio(v_mt_ctr) || ')');
        print_kv('Last accounting entry',       fdt(v_d_last));
        print_kv('Last accrual entry',          fdt(v_d_accr));

        print_sub('12.6 Limitations of the review');
        po('  1. The controls read the data recorded in FLEXCUBE. They do not');
        po('     replace the inspection of the subscription files, of the');
        po('     counterparty confirmations or of the custodian statements.');
        po('  2. ACTB_HISTORY is treated as the source of truth for the life cycle,');
        po('     as stated in section 0.7. Where a management table disagrees with');
        po('     the entries, the entries are taken as right and the disagreement is');
        po('     reported. That choice is deliberate and is the backbone of this');
        po('     report.');
        po('  3. Eight controls cannot be closed inside the database: CSH-01 to');
        po('     CSH-03 need the BEAC account statement, CUT-02 to CUT-05 need the');
        po('     trial balance and the securities position report, and CLS-02 needs');
        po('     the valuation policy. The script runs the verifiable half and');
        po('     prints the figure to be matched. None of those eight can be');
        po('     declared satisfied until the supporting document is obtained.');
        po('  4. The ALM concentration limit used by STA-04 is a parameter of this');
        po('     script (' || fmio(k_conc_lim) || '). It must be aligned with the committee');
        po('     decision before concluding on that test.');
        po('  5. The pace tests (INT-03, INT-05, CUT-01) are bounded at the last');
        po('     accrual entry of the module, ' || fdt(v_d_accr) || '. Beyond that date the absence');
        po('     of an accrual is the module having stopped, not a gap in the');
        po('     series, and it is reported as such.');
        po('  6. Operations are attached to the LAST VERSION of their contract.');
        po('     Amendments are detected by REV-05 but earlier versions are not');
        po('     replayed line by line.');

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
