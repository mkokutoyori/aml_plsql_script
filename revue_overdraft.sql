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
    -- SECTION 1 : OVERDRAFTS DEPASSANT LEUR LIMITE
    -- =========================================================
    -- Un depassement de limite doit faire l'objet d'une autorisation
    -- prealable (delegation de pouvoirs) et d'un suivi rapproche.
    -- NB : le montant effectif d'une ligne FLEXCUBE correspond a
    --      LIMIT_AMOUNT + COLLATERAL_CONTRIBUTION.
    -- =========================================================
    print_section('1. OVERDRAFTS DEPASSANT LEUR LIMITE');

    -- 1.1 Lignes dont l'utilisation depasse la limite nominale
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0)
      AND NVL(f.UTILISATION,0) > 0;
    print_test('Lignes : utilisation > limite nominale', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,5,15,15,15,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' SER',5) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|'
            || RPAD(' EXPIRE LE',12) || '|');
        tbl_line('4,12,24,16,5,5,15,15,15,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, f.LINE_SERIAL, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) AS depass,
                   f.LINE_EXPIRY_DATE
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0)
              AND NVL(f.UTILISATION,0) > 0
            ORDER BY NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || LPAD(NVL(d.LINE_SERIAL,0),4) || ' |'
                || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || LPAD(fmt_m(d.depass),14) || ' |'
                || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,5,15,15,15,12');
    END IF;

    -- 1.2 Lignes dont l'utilisation depasse le montant effectif
    --     (limite + contribution du collateral) => depassement non couvert
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0) + NVL(f.COLLATERAL_CONTRIBUTION,0)
      AND NVL(f.UTILISATION,0) > 0;
    print_test('Lignes : utilisation > limite + collateral', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,15,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' COLLATERAL',15) || '|' || RPAD(' UTILISE',15) || '|'
            || RPAD(' NON COUVERT',15) || '|');
        tbl_line('4,12,24,16,5,15,15,15,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.COLLATERAL_CONTRIBUTION,0) AS collat,
                   NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) - NVL(f.COLLATERAL_CONTRIBUTION,0) AS ecart
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0) + NVL(f.COLLATERAL_CONTRIBUTION,0)
              AND NVL(f.UTILISATION,0) > 0
            ORDER BY NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) - NVL(f.COLLATERAL_CONTRIBUTION,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.collat),14) || ' |'
                || LPAD(fmt_m(d.util),14) || ' |' || LPAD(fmt_m(d.ecart),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,15,15');
    END IF;

    -- 1.3 Lignes dont le disponible calcule par FLEXCUBE est negatif
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.AVAILABLE_AMOUNT,0) < 0;
    print_test('Lignes avec AVAILABLE_AMOUNT negatif', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,15,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DISPONIBLE',15) || '|'
            || RPAD(' STATUT',12) || '|');
        tbl_line('4,12,24,16,5,15,15,15,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.AVAILABLE_AMOUNT,0) AS dispo,
                   NVL(f.USER_DEFINE_STATUS,'-') AS statut
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.AVAILABLE_AMOUNT,0) < 0
            ORDER BY NVL(f.AVAILABLE_AMOUNT,0) ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || LPAD(fmt_m(d.dispo),14) || ' |'
                || RPAD(' ' || SUBSTR(d.statut,1,10),12) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,15,12');
    END IF;

    -- 1.4 Comptes dont le solde debiteur excede l'autorisation
    --     (limite de la ligne rattachee + TOD accorde)
    --     NB : le TOD est pris en compte quelle que soit sa validite ;
    --          les TOD expires sont traites en section 2.
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CUST_AC_NO
        FROM STTM_CUST_ACCOUNT a
        WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
          AND ABS(a.ACY_CURR_BALANCE) >
              NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                   WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                     AND f.RECORD_STAT = 'O'),0)
              + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)
    );
    print_test('Comptes : solde debiteur > autorisation (ligne+TOD)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,15,15,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE DEB.',15) || '|' || RPAD(' AUTORISE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|'
            || RPAD(' OD DEPUIS',15) || '|');
        tbl_line('4,12,24,20,5,15,15,15,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   ABS(a.ACY_CURR_BALANCE) AS solde_deb,
                   NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                        WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                          AND f.RECORD_STAT = 'O'),0)
                   + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0) AS autorise,
                   ABS(a.ACY_CURR_BALANCE)
                   - (NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                           WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                             AND f.RECORD_STAT = 'O'),0)
                      + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)) AS depass,
                   a.OVERDRAFT_SINCE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND ABS(a.ACY_CURR_BALANCE) >
                  NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                       WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                         AND f.RECORD_STAT = 'O'),0)
                  + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)
            ORDER BY depass DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde_deb),14) || ' |' || LPAD(fmt_m(d.autorise),14) || ' |'
                || LPAD(fmt_m(d.depass),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),15) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,15,15,15');
    END IF;

    -- 1.5 Comptes marques en depassement de ligne par FLEXCUBE (OVERLINE)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O' AND a.OVERLINE_OD_SINCE IS NOT NULL;
    print_test('Comptes en depassement de ligne (OVERLINE_OD_SINCE)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,14,14,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OVERLINE LE',14) || '|' || RPAD(' OD DEPUIS',14) || '|'
            || RPAD(' JOURS',10) || '|');
        tbl_line('4,12,24,20,5,15,14,14,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERLINE_OD_SINCE, a.OVERDRAFT_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) AS nb_jours
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND a.OVERLINE_OD_SINCE IS NOT NULL
            ORDER BY a.OVERLINE_OD_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERLINE_OD_SINCE),14) || '|'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),14) || '|'
                || LPAD(fmt_n(d.nb_jours),9) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,14,14,10');
    END IF;

    -- 1.6 Lignes portant un depassement exceptionnel enregistre
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.EXCEP_BREACH,0) > 0 OR NVL(f.EXCEP_TXN_AMT,0) > 0;
    print_test('Lignes avec depassement exceptionnel (EXCEP_BREACH)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,14,14');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' MNT EXCEPT.',15) || '|' || RPAD(' NB BREACH',14) || '|'
            || RPAD(' DERNIER OD',14) || '|');
        tbl_line('4,12,24,16,5,15,15,14,14');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.EXCEP_TXN_AMT,0) AS mnt_exc,
                   NVL(f.EXCEP_BREACH,0) AS nb_breach, f.DATE_OF_LAST_OD
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.EXCEP_BREACH,0) > 0 OR NVL(f.EXCEP_TXN_AMT,0) > 0
            ORDER BY NVL(f.EXCEP_TXN_AMT,0) DESC, NVL(f.EXCEP_BREACH,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.mnt_exc),14) || ' |'
                || LPAD(fmt_n(d.nb_breach),13) || ' |'
                || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),14) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,14,14');
    END IF;

    -- 1.7 Lignes dont l'utilisation depasse le montant approuve
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.APPROVED_AMT,0) > 0
      AND NVL(f.UTILISATION,0) > NVL(f.APPROVED_AMT,0);
    print_test('Lignes : utilisation > montant approuve (APPROVED_AMT)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,15,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' APPROUVE',15) || '|' || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|'
            || RPAD(' ECART',15) || '|');
        tbl_line('4,12,24,16,5,15,15,15,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.APPROVED_AMT,0) AS approuve, NVL(f.LIMIT_AMOUNT,0) AS limite,
                   NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.APPROVED_AMT,0) AS ecart
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.APPROVED_AMT,0) > 0
              AND NVL(f.UTILISATION,0) > NVL(f.APPROVED_AMT,0)
            ORDER BY NVL(f.UTILISATION,0) - NVL(f.APPROVED_AMT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.approuve),14) || ' |' || LPAD(fmt_m(d.limite),14) || ' |'
                || LPAD(fmt_m(d.util),14) || ' |' || LPAD(fmt_m(d.ecart),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,15,15');
    END IF;

    -- 1.8 Sous-lignes dont l'utilisation cumulee depasse la ligne mere
    SELECT COUNT(*) INTO v_count FROM (
        SELECT f.MAIN_LINE_ID
        FROM GETM_FACILITY f
        JOIN GETM_FACILITY p ON p.ID = f.MAIN_LINE_ID
        WHERE f.MAIN_LINE_ID IS NOT NULL AND f.MAIN_LINE_ID != f.ID
        GROUP BY f.MAIN_LINE_ID, p.LIMIT_AMOUNT
        HAVING NVL(SUM(f.UTILISATION),0) > NVL(p.LIMIT_AMOUNT,0)
    );
    print_test('Sous-lignes : utilisation cumulee > ligne mere', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,8,15,15,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE MERE',16) || '|' || RPAD(' NB SOUS',8) || '|'
            || RPAD(' LIMITE MERE',15) || '|' || RPAD(' UTIL. CUMULEE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|');
        tbl_line('4,12,24,16,8,15,15,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   p.LINE_CODE AS ligne_mere, COUNT(*) AS nb_sous,
                   NVL(p.LIMIT_AMOUNT,0) AS limite_mere,
                   NVL(SUM(f.UTILISATION),0) AS util_cum,
                   NVL(SUM(f.UTILISATION),0) - NVL(p.LIMIT_AMOUNT,0) AS depass
            FROM GETM_FACILITY f
            JOIN GETM_FACILITY p ON p.ID = f.MAIN_LINE_ID
            LEFT JOIN GETM_LIAB l ON l.ID = p.LIAB_ID
            WHERE f.MAIN_LINE_ID IS NOT NULL AND f.MAIN_LINE_ID != f.ID
            GROUP BY p.ID, l.LIAB_NO, l.LIAB_NAME, p.LINE_CODE, p.LIMIT_AMOUNT
            HAVING NVL(SUM(f.UTILISATION),0) > NVL(p.LIMIT_AMOUNT,0)
            ORDER BY NVL(SUM(f.UTILISATION),0) - NVL(p.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ligne_mere,1,14),16) || '|' || LPAD(fmt_n(d.nb_sous),7) || ' |'
                || LPAD(fmt_m(d.limite_mere),14) || ' |' || LPAD(fmt_m(d.util_cum),14) || ' |'
                || LPAD(fmt_m(d.depass),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,8,15,15,15');
    END IF;

    -- =========================================================
    -- SECTION 2 : OVERDRAFTS EXPIRES MAIS TOUJOURS UTILISES
    -- =========================================================
    -- Une ligne echue doit etre soit renouvelee formellement, soit
    -- apuree. Le maintien d'une utilisation apres l'echeance revient
    -- a accorder un concours sans decision de credit valide.
    -- =========================================================
    print_section('2. OVERDRAFTS EXPIRES MAIS TOUJOURS UTILISES');

    -- 2.1 Lignes expirees dont l'utilisation reste positive
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.LINE_EXPIRY_DATE IS NOT NULL
      AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
      AND NVL(f.UTILISATION,0) > 0;
    print_test('Lignes expirees avec utilisation > 0', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,13,10,6');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' EXPIRE LE',13) || '|'
            || RPAD(' J.RETARD',10) || '|' || RPAD(' DISPO',6) || '|');
        tbl_line('4,12,24,16,5,15,15,13,10,6');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.LINE_EXPIRY_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_EXPIRY_DATE) AS nb_jours,
                   NVL(f.AVAILABILITY_FLAG,'-') AS dispo
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
              AND NVL(f.UTILISATION,0) > 0
            ORDER BY NVL(f.UTILISATION,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),9) || ' |'
                || RPAD(' ' || d.dispo,6) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,13,10,6');
    END IF;

    -- 2.2 Lignes expirees mais toujours declarees disponibles
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.LINE_EXPIRY_DATE IS NOT NULL
      AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
      AND NVL(f.AVAILABILITY_FLAG,'N') = 'Y'
      AND f.RECORD_STAT = 'O';
    print_test('Lignes expirees encore disponibles (AVAILABILITY=Y)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' DISPONIBLE',15) || '|' || RPAD(' EXPIRE LE',13) || '|'
            || RPAD(' J.RETARD',10) || '|');
        tbl_line('4,12,24,16,5,15,15,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.AVAILABLE_AMOUNT,0) AS dispo,
                   f.LINE_EXPIRY_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_EXPIRY_DATE) AS nb_jours
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
              AND NVL(f.AVAILABILITY_FLAG,'N') = 'Y'
              AND f.RECORD_STAT = 'O'
            ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.dispo),14) || ' |'
                || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),9) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,13,10');
    END IF;

    -- 2.3 Comptes debiteurs rattaches a une (ou des) ligne(s) toutes expirees
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CUST_AC_NO
        FROM STTM_CUST_ACCOUNT a
        JOIN GETM_FACILITY f ON (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
        WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
        GROUP BY a.CUST_AC_NO
        HAVING MAX(f.LINE_EXPIRY_DATE) < TRUNC(SYSDATE)
           AND COUNT(CASE WHEN f.LINE_EXPIRY_DATE IS NULL THEN 1 END) = 0
    );
    print_test('Comptes debiteurs sur ligne(s) toutes expirees', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,16,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' DERN. LIGNE',16) || '|' || RPAD(' EXPIREE LE',13) || '|'
            || RPAD(' J.RETARD',10) || '|');
        tbl_line('4,12,24,20,5,15,16,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   MIN(a.ACY_CURR_BALANCE) AS solde,
                   MAX(a.LINE_ID) AS ligne,
                   MAX(f.LINE_EXPIRY_DATE) AS expiry,
                   TRUNC(SYSDATE) - TRUNC(MAX(f.LINE_EXPIRY_DATE)) AS nb_jours
            FROM STTM_CUST_ACCOUNT a
            JOIN GETM_FACILITY f ON (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
            GROUP BY a.CUST_NO, c.CUSTOMER_NAME1, a.CUST_AC_NO, a.CCY
            HAVING MAX(f.LINE_EXPIRY_DATE) < TRUNC(SYSDATE)
               AND COUNT(CASE WHEN f.LINE_EXPIRY_DATE IS NULL THEN 1 END) = 0
            ORDER BY MIN(a.ACY_CURR_BALANCE) ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.expiry),13) || '|'
                || LPAD(fmt_n(d.nb_jours),9) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,16,13,10');
    END IF;

    -- 2.4 TOD (decouverts temporaires) expires et compte toujours debiteur
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND NVL(a.TOD_LIMIT,0) > 0
      AND a.TOD_LIMIT_END_DATE IS NOT NULL
      AND a.TOD_LIMIT_END_DATE < TRUNC(SYSDATE);
    print_test('TOD expires avec compte encore debiteur', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,15,13,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' TOD',15) || '|' || RPAD(' DEBUT TOD',13) || '|'
            || RPAD(' FIN TOD',13) || '|' || RPAD(' J.RETARD',9) || '|');
        tbl_line('4,12,24,20,5,15,15,13,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, NVL(a.TOD_LIMIT,0) AS tod,
                   a.TOD_LIMIT_START_DATE, a.TOD_LIMIT_END_DATE,
                   TRUNC(SYSDATE) - TRUNC(a.TOD_LIMIT_END_DATE) AS nb_jours
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND NVL(a.TOD_LIMIT,0) > 0
              AND a.TOD_LIMIT_END_DATE IS NOT NULL
              AND a.TOD_LIMIT_END_DATE < TRUNC(SYSDATE)
            ORDER BY a.TOD_LIMIT_END_DATE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |' || LPAD(fmt_m(d.tod),14) || ' |'
                || RPAD(' ' || fmt_d(d.TOD_LIMIT_START_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.TOD_LIMIT_END_DATE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,15,13,13,9');
    END IF;

    -- 2.5 Mouvements debiteurs enregistres APRES l'expiration de la ligne
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CUST_AC_NO
        FROM STTM_CUST_ACCOUNT a
        JOIN GETM_FACILITY f ON (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
        JOIN ACTB_HISTORY h ON h.AC_NO = a.CUST_AC_NO
             AND h.DRCR_IND = 'D'
             AND h.TRN_DT > f.LINE_EXPIRY_DATE
             AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        WHERE a.RECORD_STAT = 'O'
          AND f.LINE_EXPIRY_DATE IS NOT NULL
          AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
        GROUP BY a.CUST_AC_NO
    );
    print_test('Comptes : debits posterieurs a l''expiration de la ligne', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,16,13,9,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' LIGNE',16) || '|' || RPAD(' EXPIREE LE',13) || '|'
            || RPAD(' NB DEBITS',9) || '|' || RPAD(' TOTAL DEBITS',17) || '|');
        tbl_line('4,12,24,20,16,13,9,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO,
                   MAX(a.LINE_ID) AS ligne, MAX(f.LINE_EXPIRY_DATE) AS expiry,
                   COUNT(*) AS nb_deb, SUM(h.LCY_AMOUNT) AS total_deb
            FROM STTM_CUST_ACCOUNT a
            JOIN GETM_FACILITY f ON (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
            JOIN ACTB_HISTORY h ON h.AC_NO = a.CUST_AC_NO
                 AND h.DRCR_IND = 'D'
                 AND h.TRN_DT > f.LINE_EXPIRY_DATE
                 AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
            GROUP BY a.CUST_NO, c.CUSTOMER_NAME1, a.CUST_AC_NO
            ORDER BY SUM(h.LCY_AMOUNT) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.expiry),13) || '|'
                || LPAD(fmt_n(d.nb_deb),8) || ' |'
                || LPAD(fmt_m(d.total_deb),16) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,16,13,9,17');
    END IF;

    -- 2.6 Lignes utilisees sans date d'expiration (concours perpetuel)
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.LINE_EXPIRY_DATE IS NULL
      AND NVL(f.UTILISATION,0) > 0
      AND f.RECORD_STAT = 'O';
    print_test('Lignes utilisees sans date d''expiration', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,13,11');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DEBUT LE',13) || '|'
            || RPAD(' ANCIENNETE',11) || '|');
        tbl_line('4,12,24,16,5,15,15,13,11');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.LINE_START_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_START_DATE) AS anciennete
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NULL
              AND NVL(f.UTILISATION,0) > 0
              AND f.RECORD_STAT = 'O'
            ORDER BY NVL(f.UTILISATION,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || fmt_d(d.LINE_START_DATE),13) || '|'
                || LPAD(fmt_n(d.anciennete) || ' j',10) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,13,11');
    END IF;

    -- 2.7 Incoherences de dates sur les lignes (expiration <= debut)
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.LINE_START_DATE IS NOT NULL AND f.LINE_EXPIRY_DATE IS NOT NULL
      AND f.LINE_EXPIRY_DATE <= f.LINE_START_DATE;
    print_test('Lignes : date d''expiration <= date de debut', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,13,13,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' DEBUT',13) || '|' || RPAD(' EXPIRATION',13) || '|'
            || RPAD(' UTILISE',15) || '|');
        tbl_line('4,12,24,16,5,15,13,13,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, f.LINE_START_DATE, f.LINE_EXPIRY_DATE,
                   NVL(f.UTILISATION,0) AS util
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_START_DATE IS NOT NULL AND f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE <= f.LINE_START_DATE
            ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |'
                || RPAD(' ' || fmt_d(d.LINE_START_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
                || LPAD(fmt_m(d.util),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,5,15,13,13,15');
    END IF;

    -- =========================================================
    -- SECTION 3 : OVERDRAFTS SANS APPROBATION IDENTIFIABLE
    -- =========================================================
    -- Tout concours doit etre rattachable a une decision de credit
    -- formalisee et a un valideur distinct de l'initiateur
    -- (principe des quatre yeux / separation des taches).
    -- =========================================================
    print_section('3. OVERDRAFTS SANS APPROBATION IDENTIFIABLE');

    -- 3.1 Lignes non autorisees dans le systeme mais deja utilisees
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.AUTH_STAT,'U') != 'A'
      AND NVL(f.UTILISATION,0) > 0;
    print_test('Lignes non autorisees (AUTH_STAT != A) et utilisees', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,6,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' AUTH',6) || '|'
            || RPAD(' MAKER',16) || '|' || RPAD(' SAISIE LE',13) || '|');
        tbl_line('4,12,24,16,5,15,15,6,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.AUTH_STAT,'-') AS auth, NVL(f.MAKER_ID,'-') AS maker, f.MAKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.AUTH_STAT,'U') != 'A'
              AND NVL(f.UTILISATION,0) > 0
            ORDER BY NVL(f.UTILISATION,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || d.auth,6) || '|' || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,6,16,13');
    END IF;

    -- 3.2 Lignes ouvertes sans valideur identifie (CHECKER_ID absent)
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.RECORD_STAT = 'O'
      AND (f.CHECKER_ID IS NULL OR TRIM(f.CHECKER_ID) IS NULL)
      AND NVL(f.LIMIT_AMOUNT,0) > 0;
    print_test('Lignes sans valideur identifie (CHECKER_ID absent)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' MAKER',16) || '|'
            || RPAD(' SAISIE LE',13) || '|');
        tbl_line('4,12,24,16,5,15,15,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.MAKER_ID,'-') AS maker, f.MAKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O'
              AND (f.CHECKER_ID IS NULL OR TRIM(f.CHECKER_ID) IS NULL)
              AND NVL(f.LIMIT_AMOUNT,0) > 0
            ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,16,13');
    END IF;

    -- 3.3 Lignes auto-approuvees (initiateur = valideur)
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.MAKER_ID IS NOT NULL AND f.CHECKER_ID IS NOT NULL
      AND UPPER(TRIM(f.MAKER_ID)) = UPPER(TRIM(f.CHECKER_ID))
      AND NVL(f.LIMIT_AMOUNT,0) > 0;
    print_test('Lignes auto-approuvees (MAKER_ID = CHECKER_ID)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' UTILISATEUR',16) || '|'
            || RPAD(' VALIDE LE',13) || '|');
        tbl_line('4,12,24,16,5,15,15,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.MAKER_ID AS usr, f.CHECKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.MAKER_ID IS NOT NULL AND f.CHECKER_ID IS NOT NULL
              AND UPPER(TRIM(f.MAKER_ID)) = UPPER(TRIM(f.CHECKER_ID))
              AND NVL(f.LIMIT_AMOUNT,0) > 0
            ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,16,13');
    END IF;

    -- 3.4 Lignes accordees sans montant approuve renseigne
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.RECORD_STAT = 'O'
      AND NVL(f.LIMIT_AMOUNT,0) > 0
      AND NVL(f.APPROVED_AMT,0) = 0;
    print_test('Lignes avec limite > 0 mais APPROVED_AMT absent', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,5,15,15,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' CHECKER',16) || '|'
            || RPAD(' VALIDE LE',13) || '|');
        tbl_line('4,12,24,16,5,15,15,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.CHECKER_ID,'-') AS checker, f.CHECKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O'
              AND NVL(f.LIMIT_AMOUNT,0) > 0
              AND NVL(f.APPROVED_AMT,0) = 0
            ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,5,15,15,16,13');
    END IF;

    -- 3.5 Comptes debiteurs sans aucune autorisation (ni ligne, ni TOD)
    --     => decouvert de fait, accorde hors dispositif
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND (a.LINE_ID IS NULL OR TRIM(a.LINE_ID) IS NULL)
      AND NVL(a.TOD_LIMIT,0) = 0
      AND NVL(a.SUBLIMIT,0) = 0;
    print_test('Comptes debiteurs sans ligne ni TOD (decouvert de fait)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,13,13,14');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OD DEPUIS',13) || '|' || RPAD(' CL. COMPTE',13) || '|'
            || RPAD(' AGENCE',14) || '|');
        tbl_line('4,12,24,20,5,15,13,13,14');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
                   NVL(a.ACCOUNT_CLASS,'-') AS cl, NVL(a.BRANCH_CODE,'-') AS brn
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND (a.LINE_ID IS NULL OR TRIM(a.LINE_ID) IS NULL)
              AND NVL(a.TOD_LIMIT,0) = 0
              AND NVL(a.SUBLIMIT,0) = 0
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || RPAD(' ' || SUBSTR(d.cl,1,11),13) || '|'
                || RPAD(' ' || d.brn,14) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,13,13,14');
    END IF;

    -- 3.6 TOD accordes sans periode de validite renseignee
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.TOD_LIMIT,0) > 0
      AND (a.TOD_LIMIT_START_DATE IS NULL OR a.TOD_LIMIT_END_DATE IS NULL);
    print_test('TOD sans periode de validite (dates absentes)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,15,13,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' TOD',15) || '|' || RPAD(' SOLDE',15) || '|' || RPAD(' DEBUT TOD',13) || '|'
            || RPAD(' FIN TOD',13) || '|');
        tbl_line('4,12,24,20,5,15,15,13,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   NVL(a.TOD_LIMIT,0) AS tod, a.ACY_CURR_BALANCE AS solde,
                   a.TOD_LIMIT_START_DATE, a.TOD_LIMIT_END_DATE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.TOD_LIMIT,0) > 0
              AND (a.TOD_LIMIT_START_DATE IS NULL OR a.TOD_LIMIT_END_DATE IS NULL)
            ORDER BY NVL(a.TOD_LIMIT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.tod),14) || ' |' || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.TOD_LIMIT_START_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.TOD_LIMIT_END_DATE),13) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,15,13,13');
    END IF;

    -- 3.7 Comptes debiteurs sur une classe n'autorisant pas le decouvert
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTM_ACCOUNT_CLASS ac ON ac.ACCOUNT_CLASS = a.ACCOUNT_CLASS
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND NVL(ac.OVERDRAFT_FACILITY,'N') != 'Y';
    print_test('Comptes debiteurs sur classe sans OVERDRAFT_FACILITY', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,12,26,7');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' CLASSE',12) || '|' || RPAD(' LIBELLE CLASSE',26) || '|'
            || RPAD(' OD FAC.',7) || '|');
        tbl_line('4,12,24,20,5,15,12,26,7');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.ACCOUNT_CLASS AS cl,
                   NVL(ac.DESCRIPTION,'-') AS cl_lib, NVL(ac.OVERDRAFT_FACILITY,'-') AS od_fac
            FROM STTM_CUST_ACCOUNT a
            JOIN STTM_ACCOUNT_CLASS ac ON ac.ACCOUNT_CLASS = a.ACCOUNT_CLASS
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND NVL(ac.OVERDRAFT_FACILITY,'N') != 'Y'
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || SUBSTR(d.cl,1,10),12) || '|'
                || RPAD(' ' || SUBSTR(d.cl_lib,1,24),26) || '|'
                || RPAD(' ' || d.od_fac,7) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,12,26,7');
    END IF;

    -- 3.8 Comptes rattaches a une LINE_ID inexistante dans GETM_FACILITY
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.LINE_ID IS NOT NULL AND TRIM(a.LINE_ID) IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM GETM_FACILITY f
                      WHERE f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID);
    print_test('Comptes rattaches a une ligne inexistante (LINE_ID orpheline)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,18,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' LINE_ID INCONNUE',18) || '|' || RPAD(' OD DEPUIS',13) || '|');
        tbl_line('4,12,24,20,5,15,18,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.LINE_ID, a.OVERDRAFT_SINCE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.LINE_ID IS NOT NULL AND TRIM(a.LINE_ID) IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM GETM_FACILITY f
                              WHERE f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || SUBSTR(d.LINE_ID,1,16),18) || '|'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,18,13');
    END IF;

    -- 3.9 Liabilities non autorisees portant des lignes utilisees
    SELECT COUNT(*) INTO v_count FROM (
        SELECT l.ID
        FROM GETM_LIAB l
        JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
        WHERE NVL(l.AUTH_STAT,'U') != 'A'
          AND NVL(f.UTILISATION,0) > 0
        GROUP BY l.ID
    );
    print_test('Liabilities non autorisees avec lignes utilisees', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,8,16,16,8,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' LIAB_NO',12) || '|' || RPAD(' NOM',26) || '|'
            || RPAD(' AUTH',8) || '|' || RPAD(' LIMITE GLOB.',16) || '|' || RPAD(' UTIL. CUMULEE',16) || '|'
            || RPAD(' NB LIGNES',8) || '|' || RPAD(' MAKER',16) || '|');
        tbl_line('4,12,26,8,16,16,8,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(l.AUTH_STAT,'-') AS auth, NVL(l.OVERALL_LIMIT,0) AS lim_glob,
                   NVL(SUM(f.UTILISATION),0) AS util, COUNT(*) AS nb_lignes,
                   NVL(MAX(l.MAKER_ID),'-') AS maker
            FROM GETM_LIAB l
            JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
            WHERE NVL(l.AUTH_STAT,'U') != 'A'
              AND NVL(f.UTILISATION,0) > 0
            GROUP BY l.ID, l.LIAB_NO, l.LIAB_NAME, l.AUTH_STAT, l.OVERALL_LIMIT
            ORDER BY NVL(SUM(f.UTILISATION),0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || RPAD(' ' || d.auth,8) || '|'
                || LPAD(fmt_m(d.lim_glob),15) || ' |' || LPAD(fmt_m(d.util),15) || ' |'
                || LPAD(fmt_n(d.nb_lignes),7) || ' |'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,26,8,16,16,8,16');
    END IF;

    -- =========================================================
    -- SECTION 4 : OVERDRAFTS DEPASSES PENDANT UNE LONGUE PERIODE
    -- =========================================================
    -- Un decouvert durablement immobilise n'est plus une facilite de
    -- tresorerie mais un credit de fait : il doit etre consolide,
    -- provisionne et declasse selon les regles prudentielles.
    -- =========================================================
    print_section('4. OVERDRAFTS DEPASSES PENDANT UNE LONGUE PERIODE');

    -- Ventilation de l'anciennete des positions debitrices (informatif)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Anciennete des positions debitrices — OVERDRAFT_SINCE]');
    FOR d IN (SELECT tranche, COUNT(*) AS nb, NVL(SUM(ABS(solde)),0) AS mnt
              FROM (SELECT CASE
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 30  THEN '1. 0 a 30 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 90  THEN '2. 31 a 90 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 180 THEN '3. 91 a 180 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 365 THEN '4. 181 a 365 jours'
                             ELSE '5. plus de 365 jours'
                           END AS tranche,
                           a.LCY_CURR_BALANCE AS solde
                    FROM STTM_CUST_ACCOUNT a
                    WHERE a.RECORD_STAT = 'O'
                      AND NVL(a.ACY_CURR_BALANCE,0) < 0
                      AND a.OVERDRAFT_SINCE IS NOT NULL)
              GROUP BY tranche
              ORDER BY tranche) LOOP
        print_info(d.tranche, fmt_n(d.nb) || ' compte(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 4.1 Comptes en position debitrice depuis plus de c_jours_long
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND a.OVERDRAFT_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_long;
    print_test('Comptes debiteurs depuis plus de ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,13,9,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OD DEPUIS',13) || '|' || RPAD(' JOURS',9) || '|'
            || RPAD(' INT. DUS',15) || '|');
        tbl_line('4,12,24,20,5,15,13,9,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) AS nb_jours,
                   NVL(a.DR_INT_DUE,0) AS int_dus
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND a.OVERDRAFT_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_long
            ORDER BY a.OVERDRAFT_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || LPAD(fmt_m(d.int_dus),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,13,9,15');
    END IF;

    -- 4.2 Comptes en depassement de ligne depuis plus de c_jours_long
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.OVERLINE_OD_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) > c_jours_long;
    print_test('Comptes en depassement de ligne > ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,14,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OVERLINE LE',14) || '|' || RPAD(' JOURS',9) || '|'
            || RPAD(' LIGNE',16) || '|');
        tbl_line('4,12,24,20,5,15,14,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERLINE_OD_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) AS nb_jours,
                   NVL(a.LINE_ID,'-') AS ligne
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.OVERLINE_OD_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) > c_jours_long
            ORDER BY a.OVERLINE_OD_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERLINE_OD_SINCE),14) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,14,9,16');
    END IF;

    -- 4.3 TOD utilises au-dela de la duree normale d'un decouvert temporaire
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.TOD_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) > c_jours_tod_max;
    print_test('TOD en cours depuis plus de ' || c_jours_tod_max || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,15,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' TOD',15) || '|' || RPAD(' TOD DEPUIS',13) || '|'
            || RPAD(' JOURS',9) || '|');
        tbl_line('4,12,24,20,5,15,15,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, NVL(a.TOD_LIMIT,0) AS tod, a.TOD_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) AS nb_jours
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.TOD_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) > c_jours_tod_max
            ORDER BY a.TOD_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |' || LPAD(fmt_m(d.tod),14) || ' |'
                || RPAD(' ' || fmt_d(d.TOD_SINCE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,15,13,9');
    END IF;

    -- 4.4 Lignes en depassement dont le premier decouvert est ancien
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.DATE_OF_FIRST_OD IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) > c_jours_tres_long
      AND NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0);
    print_test('Lignes en depassement depuis plus de ' || c_jours_tres_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,15,15,13,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|'
            || RPAD(' 1er OD LE',13) || '|' || RPAD(' DERN. OD LE',13) || '|' || RPAD(' JOURS',9) || '|');
        tbl_line('4,12,24,16,15,15,13,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, f.LINE_CODE,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.DATE_OF_FIRST_OD, f.DATE_OF_LAST_OD,
                   TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) AS nb_jours
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.DATE_OF_FIRST_OD IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) > c_jours_tres_long
              AND NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0)
            ORDER BY f.DATE_OF_FIRST_OD ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || fmt_d(d.DATE_OF_FIRST_OD),13) || '|'
                || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,15,15,13,13,9');
    END IF;

    -- 4.5 Plus longue periode CONTINUE de solde debiteur sur la periode
    --     (reconstituee a partir des soldes journaliers ACTB_ACCBAL_HISTORY)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT ACCOUNT
        FROM (
            SELECT ACCOUNT, grp, MAX(BKG_DATE) - MIN(BKG_DATE) + 1 AS duree
            FROM (
                SELECT ACCOUNT, BKG_DATE,
                       SUM(top_dep) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS grp
                FROM (
                    SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                           CASE WHEN NVL(LAG(ACY_CLOSING_BAL)
                                OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE),0) < 0
                                THEN 0 ELSE 1 END AS top_dep
                    FROM ACTB_ACCBAL_HISTORY
                    WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                )
                WHERE ACY_CLOSING_BAL < 0
            )
            GROUP BY ACCOUNT, grp
        )
        GROUP BY ACCOUNT
        HAVING MAX(duree) > c_jours_long
    );
    print_test('Comptes : periode continue debitrice > ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,13,13,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' DEBUT',13) || '|' || RPAD(' FIN',13) || '|'
            || RPAD(' DUREE(j)',9) || '|' || RPAD(' PIRE SOLDE',16) || '|');
        tbl_line('4,12,24,20,13,13,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT x.ACCOUNT, NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   x.deb, x.fin, x.duree, x.pire
            FROM (
                SELECT ACCOUNT, deb, fin, duree, pire,
                       ROW_NUMBER() OVER (PARTITION BY ACCOUNT ORDER BY duree DESC) AS rn
                FROM (
                    SELECT ACCOUNT, grp, MIN(BKG_DATE) AS deb, MAX(BKG_DATE) AS fin,
                           MAX(BKG_DATE) - MIN(BKG_DATE) + 1 AS duree,
                           MIN(ACY_CLOSING_BAL) AS pire
                    FROM (
                        SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                               SUM(top_dep) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS grp
                        FROM (
                            SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                                   CASE WHEN NVL(LAG(ACY_CLOSING_BAL)
                                        OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE),0) < 0
                                        THEN 0 ELSE 1 END AS top_dep
                            FROM ACTB_ACCBAL_HISTORY
                            WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                        )
                        WHERE ACY_CLOSING_BAL < 0
                    )
                    GROUP BY ACCOUNT, grp
                )
            ) x
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = x.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE x.rn = 1 AND x.duree > c_jours_long
            ORDER BY x.duree DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || RPAD(' ' || fmt_d(d.deb),13) || '|' || RPAD(' ' || fmt_d(d.fin),13) || '|'
                || LPAD(fmt_n(d.duree),8) || ' |'
                || LPAD(fmt_m(d.pire),15) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,13,13,9,16');
    END IF;

    -- 4.6 Comptes jamais revenus en position creditrice sur la periode
    --     => decouvert structurel (credit deguise)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT h.ACCOUNT
        FROM ACTB_ACCBAL_HISTORY h
        WHERE h.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        GROUP BY h.ACCOUNT
        HAVING MAX(h.ACY_CLOSING_BAL) < 0
           AND COUNT(*) >= c_jours_long
    );
    print_test('Comptes constamment debiteurs sur ' || c_mois_hist || ' mois', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,9,16,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' NB JOURS',9) || '|'
            || RPAD(' SOLDE MOYEN',16) || '|' || RPAD(' PIRE SOLDE',16) || '|' || RPAD(' SOLDE FINAL',16) || '|');
        tbl_line('4,12,24,20,9,16,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT x.ACCOUNT, NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   x.nb_jours, x.moyen, x.pire, x.dernier
            FROM (
                SELECT h.ACCOUNT, COUNT(*) AS nb_jours, AVG(h.ACY_CLOSING_BAL) AS moyen,
                       MIN(h.ACY_CLOSING_BAL) AS pire,
                       MAX(h.ACY_CLOSING_BAL) KEEP (DENSE_RANK LAST ORDER BY h.BKG_DATE) AS dernier
                FROM ACTB_ACCBAL_HISTORY h
                WHERE h.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                GROUP BY h.ACCOUNT
                HAVING MAX(h.ACY_CLOSING_BAL) < 0
                   AND COUNT(*) >= c_jours_long
            ) x
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = x.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            ORDER BY x.pire ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || LPAD(fmt_m(d.moyen),15) || ' |' || LPAD(fmt_m(d.pire),15) || ' |'
                || LPAD(fmt_m(d.dernier),15) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,9,16,16,16');
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
