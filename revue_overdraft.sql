-- ============================================================
-- SCRIPT DE REVUE DES OVERDRAFTS (DECOUVERTS BANCAIRES)
-- Base : FLEXCUBE (FCUBS) — Audit Interne / Risque de Credit
-- ============================================================
-- Ce script identifie les anomalies et zones de risque liees a
-- la gestion des decouverts (overdrafts) et des lignes de credit
-- rattachees aux comptes de la clientele.
--
-- PLAN DE LA REVUE
--   0.  Panorama du portefeuille overdraft (informatif)
--   1.  Overdrafts depassant leur limite
--   2.  Overdrafts expires mais toujours utilises
--   3.  Overdrafts sans approbation identifiable
--   4.  Overdrafts depasses pendant une longue periode
--   5.  Clients avec plusieurs overdrafts
--   6.  Augmentations de limites importantes
--   7.  Augmentations de limites juste avant un depassement
--   8.  Overdrafts proches ou superieurs aux seuils d'approbation
--   9.  Transactions manuelles sur comptes overdrawn
--   10. Overdrafts presentant des regularisations inhabituelles
--   11. Overdrafts dont les interets / frais n'ont pas ete appliques
--   12. Comptes presentant des depassements recurrents
--
-- TABLES UTILISEES
--   GETM_FACILITY             : lignes de credit / facilites (limites)
--   GETM_FACILITY_VD_DETAILS  : historique value-date des montants de limite
--   GETM_LIAB                 : liabilities (groupes de risque / clients)
--   STTM_CUST_ACCOUNT         : comptes clientele (soldes, TOD, dates OD)
--   STTM_CUSTOMER             : referentiel clients
--   STTM_ACCOUNT_CLASS        : classes de comptes (OVERDRAFT_FACILITY, IC)
--   ACTB_HISTORY              : ecritures comptables (module DE = saisie manuelle)
--   ACTB_ACCBAL_HISTORY       : soldes journaliers par compte (BKG_DATE)
--   ICTM_ACC_UDEVALS          : parametrage des taux au niveau du compte
--
-- CONVENTIONS
--   - Un solde debiteur (compte en overdraft) est NEGATIF dans FLEXCUBE
--     (ACY_CURR_BALANCE / LCY_CURR_BALANCE < 0).
--   - Les montants affiches "M" sont exprimes en MILLIONS de la devise
--     de reference (XAF sauf mention contraire).
--   - Les limites en devise etrangere sont ramenees au montant de
--     reporting (REPORTING_AMOUNT) lorsqu'il est renseigne ; la colonne
--     CCY est systematiquement affichee pour permettre le controle.
--   - Les seuils de la revue sont parametrables dans le bloc PARAMETRES
--     ci-dessous : ils DOIVENT etre alignes sur la grille de delegation
--     de pouvoirs en vigueur dans l'etablissement.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET LINESIZE 400
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_total         NUMBER;
    v_sep           VARCHAR2(80) := RPAD('=', 80, '=');
    v_test_no       NUMBER := 0;
    v_anomalies     NUMBER := 0;
    v_row_num       NUMBER := 0;
    v_montant       NUMBER;

    -- =========================================================
    -- PARAMETRES DE LA REVUE (a adapter au dispositif interne)
    -- =========================================================
    -- Nombre maximum de lignes affichees par test
    c_max_rows          CONSTANT NUMBER := 30;

    -- Anciennete consideree comme "longue periode" de depassement
    c_jours_long        CONSTANT NUMBER := 90;    -- 3 mois
    c_jours_tres_long   CONSTANT NUMBER := 180;   -- 6 mois
    -- Duree maximale normale d'un TOD (decouvert temporaire)
    c_jours_tod_max     CONSTANT NUMBER := 30;

    -- Augmentation de limite consideree comme importante
    c_pct_augm          CONSTANT NUMBER := 25;            -- +25 %
    c_mnt_augm          CONSTANT NUMBER := 25000000;      -- ou +25 M
    -- Fenetre "augmentation juste avant un depassement"
    c_jours_avant       CONSTANT NUMBER := 30;

    -- Grille des seuils d'approbation (a aligner sur la delegation)
    c_seuil_1           CONSTANT NUMBER := 10000000;      -- 10 M
    c_seuil_2           CONSTANT NUMBER := 50000000;      -- 50 M
    c_seuil_3           CONSTANT NUMBER := 250000000;     -- 250 M
    c_seuil_4           CONSTANT NUMBER := 1000000000;    -- 1 000 M
    -- Bande "juste en dessous du seuil" (evitement du palier)
    c_pct_proche        CONSTANT NUMBER := 90;            -- 90 % du seuil

    -- Montant significatif d'ecriture / de decouvert
    c_mnt_signif        CONSTANT NUMBER := 5000000;       -- 5 M
    -- Profondeur d'analyse des historiques (en mois)
    c_mois_hist         CONSTANT NUMBER := 12;
    -- Nombre de jours en depassement au-dela duquel on parle de recurrence
    c_jours_recur       CONSTANT NUMBER := 60;
    -- Nombre d'episodes distincts d'overdraft caracterisant la recurrence
    c_nb_episodes       CONSTANT NUMBER := 4;
    -- Ecart maximum (en jours) d'un aller-retour credit/debit (habillage)
    c_jours_ar          CONSTANT NUMBER := 5;

    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE print_test(p_label VARCHAR2, p_count NUMBER, p_total NUMBER DEFAULT NULL) IS
    BEGIN
        v_test_no := v_test_no + 1;
        IF p_total IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 60, '.') || ' '
                || p_count || ' / ' || p_total
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        ELSE
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 60, '.') || ' '
                || p_count
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        END IF;
        IF p_count > 0 THEN
            v_anomalies := v_anomalies + 1;
        END IF;
    END;

    -- Ligne informative (statistique de cadrage, non comptee comme test)
    PROCEDURE print_info(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('    ' || RPAD(p_label, 55, '.') || ' ' || p_value);
    END;

    -- Dessine une ligne de separation parametrable
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
        DBMS_OUTPUT.PUT_LINE(v_line);
    END;

    -- Formatage d'un montant en millions
    FUNCTION fmt_m(p_amt NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_amt,0)/1000000, 'FM999G999G990D00') || ' M';
    END;

    -- Formatage d'un entier
    FUNCTION fmt_n(p_val NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_val,0), 'FM999G999G999G990');
    END;

    -- Formatage d'une date
    FUNCTION fmt_d(p_dt DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN NVL(TO_CHAR(p_dt, 'DD/MM/YYYY'), '-');
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   REVUE DES OVERDRAFTS — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- SECTION 0 : PANORAMA DU PORTEFEUILLE OVERDRAFT (INFORMATIF)
    -- =========================================================
    print_section('0. PANORAMA DU PORTEFEUILLE OVERDRAFT');

    -- 0.1 Rappel des parametres de la revue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Parametres de la revue]');
    print_info('Longue periode de depassement (jours)', fmt_n(c_jours_long));
    print_info('Tres longue periode de depassement (jours)', fmt_n(c_jours_tres_long));
    print_info('Duree maximale normale d''un TOD (jours)', fmt_n(c_jours_tod_max));
    print_info('Augmentation de limite importante (%)', fmt_n(c_pct_augm) || ' %');
    print_info('Augmentation de limite importante (montant)', fmt_m(c_mnt_augm));
    print_info('Fenetre augmentation / depassement (jours)', fmt_n(c_jours_avant));
    print_info('Seuil d''approbation 1', fmt_m(c_seuil_1));
    print_info('Seuil d''approbation 2', fmt_m(c_seuil_2));
    print_info('Seuil d''approbation 3', fmt_m(c_seuil_3));
    print_info('Seuil d''approbation 4', fmt_m(c_seuil_4));
    print_info('Bande "juste en dessous du seuil" (%)', fmt_n(c_pct_proche) || ' %');
    print_info('Profondeur d''analyse des historiques (mois)', fmt_n(c_mois_hist));

    -- 0.2 Portefeuille des lignes de credit (GETM_FACILITY)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Lignes de credit — GETM_FACILITY]');

    SELECT COUNT(*) INTO v_total FROM GETM_FACILITY;
    print_info('Nombre total de lignes', fmt_n(v_total));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE RECORD_STAT = 'O';
    print_info('Lignes ouvertes (RECORD_STAT = O)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE AUTH_STAT = 'A';
    print_info('Lignes autorisees (AUTH_STAT = A)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE NVL(AUTH_STAT,'U') != 'A';
    print_info('Lignes NON autorisees', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE NVL(UTILISATION,0) > 0;
    print_info('Lignes avec utilisation > 0', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY
    WHERE LINE_EXPIRY_DATE IS NOT NULL AND LINE_EXPIRY_DATE < TRUNC(SYSDATE);
    print_info('Lignes expirees', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE LINE_EXPIRY_DATE IS NULL;
    print_info('Lignes sans date d''expiration', fmt_n(v_count));

    SELECT NVL(SUM(LIMIT_AMOUNT),0) INTO v_montant FROM GETM_FACILITY WHERE RECORD_STAT = 'O';
    print_info('Total des limites accordees (lignes ouvertes)', fmt_m(v_montant));

    SELECT NVL(SUM(UTILISATION),0) INTO v_montant FROM GETM_FACILITY WHERE RECORD_STAT = 'O';
    print_info('Total des utilisations (lignes ouvertes)', fmt_m(v_montant));

    -- Repartition par devise de ligne
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition des lignes par devise]');
    FOR d IN (SELECT NVL(LINE_CURRENCY,'-') AS ccy, COUNT(*) AS nb,
                     NVL(SUM(LIMIT_AMOUNT),0) AS mnt
              FROM GETM_FACILITY
              GROUP BY NVL(LINE_CURRENCY,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Devise ' || d.ccy, fmt_n(d.nb) || ' ligne(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 0.3 Rattachement des lignes aux comptes (STTM_CUST_ACCOUNT.LINE_ID)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Rattachement lignes / comptes]');

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE LINE_ID IS NOT NULL AND TRIM(LINE_ID) IS NOT NULL;
    print_info('Comptes portant une LINE_ID', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY f
    WHERE EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID));
    print_info('Lignes rattachees a au moins un compte', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY f
    WHERE NVL(f.UTILISATION,0) > 0
      AND NOT EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                      WHERE a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID));
    print_info('Lignes utilisees SANS compte rattache', fmt_n(v_count));

    -- 0.4 Comptes en position debitrice
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptes clientele en position debitrice]');

    SELECT COUNT(*) INTO v_total FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O';
    print_info('Comptes ouverts', fmt_n(v_total));

    SELECT COUNT(*), NVL(SUM(ABS(LCY_CURR_BALANCE)),0) INTO v_count, v_montant
    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' AND NVL(ACY_CURR_BALANCE,0) < 0;
    print_info('Comptes en solde debiteur', fmt_n(v_count));
    print_info('Encours debiteur total (contre-valeur)', fmt_m(v_montant));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE RECORD_STAT = 'O' AND OVERDRAFT_SINCE IS NOT NULL;
    print_info('Comptes avec OVERDRAFT_SINCE renseigne', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE RECORD_STAT = 'O' AND OVERLINE_OD_SINCE IS NOT NULL;
    print_info('Comptes en depassement de ligne (OVERLINE)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE RECORD_STAT = 'O' AND NVL(TOD_LIMIT,0) > 0;
    print_info('Comptes avec un TOD (decouvert temporaire)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE RECORD_STAT = 'O' AND TOD_SINCE IS NOT NULL;
    print_info('Comptes avec TOD_SINCE renseigne', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE RECORD_STAT = 'O' AND NVL(ACY_CURR_BALANCE,0) < 0
      AND (LINE_ID IS NULL OR TRIM(LINE_ID) IS NULL) AND NVL(TOD_LIMIT,0) = 0;
    print_info('Comptes debiteurs sans ligne ni TOD', fmt_n(v_count));

    -- 0.5 Top 15 des encours debiteurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 des encours debiteurs]');
    tbl_line('4,13,30,22,6,14,18,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',30) || '|'
        || RPAD(' COMPTE',22) || '|' || RPAD(' CCY',6) || '|' || RPAD(' AGENCE',14) || '|'
        || RPAD(' SOLDE (M)',18) || '|' || RPAD(' OD DEPUIS',14) || '|');
    tbl_line('4,13,30,22,6,14,18,14');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               NVL(a.BRANCH_CODE,'-') AS brn, a.LCY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE
        FROM STTM_CUST_ACCOUNT a
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
        ORDER BY a.LCY_CURR_BALANCE ASC
    ) WHERE ROWNUM <= 15) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.CUST_NO,13) || '|' || RPAD(' ' || SUBSTR(d.nom,1,28),30) || '|'
            || RPAD(' ' || d.CUST_AC_NO,22) || '|' || RPAD(' ' || d.ccy,6) || '|'
            || RPAD(' ' || d.brn,14) || '|'
            || LPAD(fmt_m(d.solde),17) || ' |'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),14) || '|');
    END LOOP;
    tbl_line('4,13,30,22,6,14,18,14');
    IF v_row_num = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  (aucun compte en position debitrice)');
    END IF;

    -- =========================================================
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TOTAL TESTS EXECUTES : ' || v_test_no);
    DBMS_OUTPUT.PUT_LINE('   TESTS AVEC ANOMALIES : ' || v_anomalies);
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
