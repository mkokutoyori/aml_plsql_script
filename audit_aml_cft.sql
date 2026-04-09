-- ============================================================
-- SCRIPT D'AUDIT AML/CFT — FLEXCUBE UNIVERSAL BANKING
-- Banque : Access Bank Cameroon
-- Référentiel : Règlement COBAC / CEMAC, FATF/GAFI
-- Date génération : 09/04/2026
-- ============================================================
-- Ce script produit un rapport d'audit structuré via DBMS_OUTPUT.
-- Chaque test est identifié par un code (AML-xxx) pour traçabilité.
-- Résultats : comptage + échantillon des cas les plus critiques.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_count2        NUMBER;
    v_total         NUMBER;
    v_row_num       NUMBER;
    v_sep           VARCHAR2(120) := RPAD('=', 110, '=');
    v_subsep        VARCHAR2(120) := RPAD('-', 110, '-');

    -- -------------------------------------------------------
    -- Utilitaires d'affichage
    -- -------------------------------------------------------
    PROCEDURE p_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE p_test(p_code VARCHAR2, p_desc VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_subsep);
        DBMS_OUTPUT.PUT_LINE('  TEST ' || p_code || ' : ' || p_desc);
        DBMS_OUTPUT.PUT_LINE(v_subsep);
    END;

    PROCEDURE p_kv(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_label, 50, '.') || ' ' || NVL(p_value, 'N/A'));
    END;

    PROCEDURE p_finding(p_severity VARCHAR2, p_msg VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  [' || p_severity || '] ' || p_msg);
    END;

    PROCEDURE p_pct(p_label VARCHAR2, p_count NUMBER, p_total NUMBER) IS
    BEGIN
        IF p_total > 0 THEN
            p_kv(p_label, TO_CHAR(p_count) || ' / ' || TO_CHAR(p_total)
                || ' (' || TO_CHAR(ROUND(p_count * 100 / p_total, 1)) || '%)');
        ELSE
            p_kv(p_label, '0 / 0 (N/A)');
        END IF;
    END;

    -- Dessine une ligne de séparation de tableau
    PROCEDURE p_tbl_line IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 6, '-')  || '+' || RPAD('-', 8, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+' || RPAD('-', 12, '-') || '+');
    END;

    -- En-tête standard des tableaux clients
    PROCEDURE p_tbl_header IS
    BEGIN
        p_tbl_line;
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' CIF', 13)         || '|' || RPAD(' NOM CLIENT', 28) || '|'
            || RPAD(' TYPE', 6)         || '|' || RPAD(' CAT', 8)        || '|'
            || RPAD(' CPT.A', 7)        || '|' || RPAD(' SOLDE TOTAL', 18)|| '|'
            || RPAD(' DERN.TXN', 12)    || '|' || RPAD(' OUVERTURE', 12) || '|');
        p_tbl_line;
    END;

    -- Ligne de données du tableau clients
    PROCEDURE p_tbl_row(
        p_num NUMBER, p_cif VARCHAR2, p_nom VARCHAR2, p_type VARCHAR2,
        p_cat VARCHAR2, p_nb_cpt NUMBER, p_solde NUMBER,
        p_last_txn DATE, p_open_dt DATE
    ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(p_num), 3) || ' |'
            || RPAD(' ' || NVL(p_cif, ''), 13)                           || '|'
            || RPAD(' ' || NVL(SUBSTR(p_nom, 1, 26), ''), 28)            || '|'
            || RPAD(' ' || NVL(p_type, ''), 6)                           || '|'
            || RPAD(' ' || NVL(SUBSTR(p_cat, 1, 6), ''), 8)             || '|'
            || LPAD(NVL(TO_CHAR(p_nb_cpt), '0'), 5) || '  |'
            || LPAD(NVL(TO_CHAR(p_solde, 'FM999G999G999G990'), '0'), 17) || ' |'
            || RPAD(' ' || NVL(TO_CHAR(p_last_txn, 'DD/MM/YYYY'), 'N/A'), 12) || '|'
            || RPAD(' ' || NVL(TO_CHAR(p_open_dt, 'DD/MM/YYYY'), 'N/A'), 12)  || '|');
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('         R A P P O R T   D '' A U D I T   A M L / C F T');
    DBMS_OUTPUT.PUT_LINE('         Access Bank Cameroon  —  FLEXCUBE Universal Banking');
    DBMS_OUTPUT.PUT_LINE('         Date du rapport : ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);

    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER;
    p_kv('Population totale clients', TO_CHAR(v_total));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT;
    p_kv('Population totale comptes', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY;
    p_kv('Population totale transactions', TO_CHAR(v_count));


    -- =========================================================
    -- SECTION 1 : KYC — COMPLETUDE & QUALITE (CDD)
    -- =========================================================
    p_section('SECTION 1 : KYC — COMPLETUDE & QUALITE (Customer Due Diligence)');

    -- ---------------------------------------------------------
    -- TEST AML-101 : Clients sans référence KYC
    -- ---------------------------------------------------------
    p_test('AML-101', 'Clients sans référence KYC (KYC_REF_NO)');

    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE KYC_REF_NO IS NULL OR KYC_REF_NO = ' ';
    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER;
    p_pct('Clients sans KYC_REF_NO', v_count, v_total);

    -- Dont avec comptes actifs
    SELECT COUNT(*) INTO v_count2 FROM STTM_CUSTOMER c
    WHERE (c.KYC_REF_NO IS NULL OR c.KYC_REF_NO = ' ')
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Dont avec au moins 1 compte actif', TO_CHAR(v_count2));

    IF v_count2 > 0 THEN
        p_finding('CRITIQUE', v_count2 || ' clients sans KYC ont des comptes ouverts et actifs.');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Clients avec comptes actifs (tri par solde décroissant) :');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUSTOMER c
                JOIN (
                    SELECT CUST_NO,
                           COUNT(*)                                                 nb_cpt,
                           SUM(ACY_CURR_BALANCE)                                    solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE)                                        first_open
                    FROM STTM_CUST_ACCOUNT
                    WHERE RECORD_STAT = 'O'
                    GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE (c.KYC_REF_NO IS NULL OR c.KYC_REF_NO = ' ')
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- Clients sans KYC SANS comptes actifs (pour mémoire)
    DBMS_OUTPUT.PUT_LINE('');
    p_kv('  Sans KYC et SANS compte actif (risque faible)', TO_CHAR(v_count - v_count2));

    -- ---------------------------------------------------------
    -- TEST AML-102 : Statut KYC non validé
    -- ---------------------------------------------------------
    p_test('AML-102', 'Clients avec KYC non validé (KYC_DETAILS != V)');

    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER;
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE KYC_DETAILS != 'V' OR KYC_DETAILS IS NULL;
    p_pct('Clients KYC non validé', v_count, v_total);

    DBMS_OUTPUT.PUT_LINE('  Répartition :');
    FOR r IN (SELECT NVL(KYC_DETAILS, 'NULL') kd, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY KYC_DETAILS ORDER BY nb DESC) LOOP
        p_kv('    KYC_DETAILS = ' || r.kd, TO_CHAR(r.nb));
    END LOOP;

    -- Dont avec comptes actifs
    SELECT COUNT(*) INTO v_count2 FROM STTM_CUSTOMER c
    WHERE (c.KYC_DETAILS != 'V' OR c.KYC_DETAILS IS NULL)
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Dont avec comptes actifs', TO_CHAR(v_count2));

    -- Dont clients récents (< 1 an) avec comptes actifs et KYC non validé
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER c
    WHERE (c.KYC_DETAILS != 'V' OR c.KYC_DETAILS IS NULL)
      AND c.CIF_CREATION_DATE >= ADD_MONTHS(SYSDATE, -12)
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Dont créés < 12 mois avec comptes actifs', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_finding('CRITIQUE', v_count || ' clients récents avec comptes actifs et KYC non validé.');
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUSTOMER c
                JOIN (
                    SELECT CUST_NO,
                           COUNT(*) nb_cpt,
                           SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O'
                    GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE (c.KYC_DETAILS != 'V' OR c.KYC_DETAILS IS NULL)
                  AND c.CIF_CREATION_DATE >= ADD_MONTHS(SYSDATE, -12)
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-103 : Revues KYC en retard
    -- ---------------------------------------------------------
    p_test('AML-103', 'Dossiers KYC avec revue périodique en retard');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE < SYSDATE AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    p_kv('KYC Retail en retard de revue', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count2 FROM STTM_KYC_CORPORATE
    WHERE KYC_NXT_REVIEW_DATE < SYSDATE AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    p_kv('KYC Corporate en retard de revue', TO_CHAR(v_count2));

    -- Ancienneté des retards Retail
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Ancienneté des retards (KYC Retail) :');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE < ADD_MONTHS(SYSDATE, -24) AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    p_kv('    Retard > 24 mois', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE < ADD_MONTHS(SYSDATE, -12)
      AND KYC_NXT_REVIEW_DATE >= ADD_MONTHS(SYSDATE, -24) AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    p_kv('    Retard 12-24 mois', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE < SYSDATE
      AND KYC_NXT_REVIEW_DATE >= ADD_MONTHS(SYSDATE, -12) AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    p_kv('    Retard < 12 mois', TO_CHAR(v_count));

    -- KYC en retard avec comptes actifs (haut risque : clients Level3)
    DBMS_OUTPUT.PUT_LINE('');
    p_finding('FOCUS', 'Clients HAUT RISQUE (Level3) avec KYC en retard ET comptes actifs :');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_MASTER m
    JOIN STTM_KYC_RETAIL kr ON kr.KYC_REF_NO = m.KYC_REF_NO
    JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = m.KYC_REF_NO
    WHERE m.RISK_LEVEL = 'Level3'
      AND kr.KYC_NXT_REVIEW_DATE < SYSDATE AND kr.KYC_NXT_REVIEW_DATE IS NOT NULL
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Nb clients Level3 en retard avec CPT actifs', TO_CHAR(v_count));

    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_KYC_MASTER m
                JOIN STTM_KYC_RETAIL kr ON kr.KYC_REF_NO = m.KYC_REF_NO
                JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = m.KYC_REF_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE m.RISK_LEVEL = 'Level3'
                  AND kr.KYC_NXT_REVIEW_DATE < SYSDATE AND kr.KYC_NXT_REVIEW_DATE IS NOT NULL
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-104 : Données personnelles incomplètes
    -- ---------------------------------------------------------
    p_test('AML-104', 'Données personnelles obligatoires manquantes');

    SELECT COUNT(*) INTO v_total FROM STTM_CUST_PERSONAL;

    DBMS_OUTPUT.PUT_LINE('  Tous clients (indiv.) :');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE DATE_OF_BIRTH IS NULL;
    p_pct('    Sans DATE_OF_BIRTH', v_count, v_total);

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (P_NATIONAL_ID IS NULL OR P_NATIONAL_ID = ' ')
      AND (PASSPORT_NO IS NULL OR PASSPORT_NO = ' ');
    p_pct('    Sans pièce identité (NI+Passeport)', v_count, v_total);

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (FIRST_NAME IS NULL OR FIRST_NAME = ' ')
       OR (LAST_NAME IS NULL OR LAST_NAME = ' ');
    p_pct('    Sans nom complet (FIRST ou LAST)', v_count, v_total);

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (P_ADDRESS1 IS NULL OR P_ADDRESS1 = ' ')
      AND (D_ADDRESS1 IS NULL OR D_ADDRESS1 = ' ');
    p_pct('    Sans aucune adresse', v_count, v_total);

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (MOBILE_NUMBER IS NULL OR MOBILE_NUMBER = ' ')
      AND (TELEPHONE IS NULL OR TELEPHONE = ' ');
    p_pct('    Sans téléphone (mobile+fixe)', v_count, v_total);

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (BIRTH_COUNTRY IS NULL OR BIRTH_COUNTRY = ' ')
      AND (PLACE_OF_BIRTH IS NULL OR PLACE_OF_BIRTH = ' ');
    p_pct('    Sans pays NI lieu de naissance', v_count, v_total);

    -- Focus : clients avec comptes actifs et aucune pièce d'identité
    DBMS_OUTPUT.PUT_LINE('');
    p_finding('FOCUS', 'Clients SANS pièce identité avec comptes actifs :');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL p
    WHERE (p.P_NATIONAL_ID IS NULL OR p.P_NATIONAL_ID = ' ')
      AND (p.PASSPORT_NO IS NULL OR p.PASSPORT_NO = ' ')
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = p.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Nb sans pièce ID + comptes actifs', TO_CHAR(v_count));

    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUST_PERSONAL p
                JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE (p.P_NATIONAL_ID IS NULL OR p.P_NATIONAL_ID = ' ')
                  AND (p.PASSPORT_NO IS NULL OR p.PASSPORT_NO = ' ')
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-105 : Documents expirés
    -- ---------------------------------------------------------
    p_test('AML-105', 'Documents d''identité expirés');

    -- Passeports expirés depuis les deux sources
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE PPT_EXP_DATE < SYSDATE AND PPT_EXP_DATE IS NOT NULL;
    p_kv('Passeports expirés (CUST_PERSONAL)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE PASSPORT_EXPIRY_DATE < SYSDATE AND PASSPORT_EXPIRY_DATE IS NOT NULL;
    p_kv('Passeports expirés (KYC_RETAIL)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE VISA_EXPIRY_DATE < SYSDATE AND VISA_EXPIRY_DATE IS NOT NULL;
    p_kv('Visas expirés', TO_CHAR(v_count));

    -- Union des deux sources pour passeports expirés, avec comptes actifs
    DBMS_OUTPUT.PUT_LINE('');
    p_finding('FOCUS', 'Passeports expirés (toutes sources) avec comptes actifs :');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
        || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
        || RPAD(' CIF', 13) || '|' || RPAD(' NOM CLIENT', 28) || '|'
        || RPAD(' PASSEPORT', 13) || '|' || RPAD(' DATE EXP.', 13) || '|'
        || RPAD(' CPT.A', 7)  || '|' || RPAD(' SOLDE TOTAL', 18) || '|');
    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
        || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');

    v_row_num := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   NVL(p.PASSPORT_NO, kr.PASSPORT_NO) passeport,
                   LEAST(NVL(p.PPT_EXP_DATE, DATE '9999-12-31'),
                         NVL(kr.PASSPORT_EXPIRY_DATE, DATE '9999-12-31')) dt_exp,
                   ac.nb_cpt, ac.solde_total
            FROM STTM_CUSTOMER c
            LEFT JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            LEFT JOIN STTM_KYC_RETAIL kr ON kr.KYC_REF_NO = c.KYC_REF_NO
            JOIN (
                SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total
                FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
            ) ac ON ac.CUST_NO = c.CUSTOMER_NO
            WHERE (p.PPT_EXP_DATE < SYSDATE AND p.PPT_EXP_DATE IS NOT NULL)
               OR (kr.PASSPORT_EXPIRY_DATE < SYSDATE AND kr.PASSPORT_EXPIRY_DATE IS NOT NULL)
            ORDER BY ac.solde_total DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
            || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13) || '|'
            || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 26), ''), 28) || '|'
            || RPAD(' ' || NVL(SUBSTR(r.passeport, 1, 11), ''), 13) || '|'
            || RPAD(' ' || CASE WHEN r.dt_exp = DATE '9999-12-31' THEN 'N/A'
                               ELSE TO_CHAR(r.dt_exp, 'DD/MM/YYYY') END, 13) || '|'
            || LPAD(NVL(TO_CHAR(r.nb_cpt), '0'), 5) || '  |'
            || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
        || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
        || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');

    -- ---------------------------------------------------------
    -- TEST AML-106 : RISK_PROFILE non renseigné
    -- ---------------------------------------------------------
    p_test('AML-106', 'Profil de risque client non renseigné');

    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE RISK_PROFILE IS NULL OR RISK_PROFILE = ' ';
    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER;
    p_pct('Clients sans RISK_PROFILE', v_count, v_total);

    IF v_count = v_total THEN
        p_finding('CRITIQUE', 'AUCUN client n''a de RISK_PROFILE dans STTM_CUSTOMER.');
        p_finding('NOTE', 'Vérification alternative via KYC_MASTER.RISK_LEVEL :');
    END IF;

    FOR r IN (SELECT RISK_LEVEL, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY RISK_LEVEL ORDER BY nb DESC) LOOP
        p_kv('    RISK_LEVEL = ' || r.RISK_LEVEL, TO_CHAR(r.nb));
    END LOOP;

    -- Clients sans risque nulle part
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER c
    WHERE (c.RISK_PROFILE IS NULL OR c.RISK_PROFILE = ' ')
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_MASTER m WHERE m.KYC_REF_NO = c.KYC_REF_NO);
    p_kv('  Clients sans risque (ni CUSTOMER ni MASTER)', TO_CHAR(v_count));

    -- ---------------------------------------------------------
    -- TEST AML-107 : Comptes actifs sans KYC
    -- ---------------------------------------------------------
    p_test('AML-107', 'Comptes avec transactions récentes MAIS client sans KYC');

    SELECT COUNT(DISTINCT a.CUST_AC_NO) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
    WHERE a.RECORD_STAT = 'O'
      AND (c.KYC_REF_NO IS NULL OR c.KYC_REF_NO = ' ')
      AND (a.DATE_LAST_CR_ACTIVITY >= ADD_MONTHS(SYSDATE, -12)
           OR a.DATE_LAST_DR_ACTIVITY >= ADD_MONTHS(SYSDATE, -12));
    p_kv('Comptes actifs < 12 mois sans KYC', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_finding('CRITIQUE', 'Des comptes opèrent sans dossier KYC.');
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUSTOMER c
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT
                    WHERE RECORD_STAT = 'O'
                      AND (DATE_LAST_CR_ACTIVITY >= ADD_MONTHS(SYSDATE, -12)
                           OR DATE_LAST_DR_ACTIVITY >= ADD_MONTHS(SYSDATE, -12))
                    GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE (c.KYC_REF_NO IS NULL OR c.KYC_REF_NO = ' ')
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;


    -- =========================================================
    -- FIN SECTION 1
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> FIN SECTION 1 — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);


    -- =========================================================
    -- SECTION 2 : PEP & CLIENTS HAUT RISQUE (EDD)
    -- =========================================================
    p_section('SECTION 2 : PEP & CLIENTS HAUT RISQUE (Enhanced Due Diligence)');

    -- ---------------------------------------------------------
    -- TEST AML-201 : Inventaire des PEP
    -- ---------------------------------------------------------
    p_test('AML-201', 'Inventaire des Personnes Politiquement Exposées (PEP)');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PEP = 'Y';
    SELECT COUNT(*) INTO v_total FROM STTM_KYC_RETAIL;
    p_pct('Total PEP déclarés', v_count, v_total);

    -- PEP avec comptes actifs
    SELECT COUNT(*) INTO v_count2 FROM STTM_KYC_RETAIL kr
    JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = kr.KYC_REF_NO
    WHERE kr.PEP = 'Y'
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  PEP avec comptes actifs', TO_CHAR(v_count2));

    IF v_count2 > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Liste des PEP avec comptes actifs (tri par solde) :');

        -- En-tête spécifique PEP
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 8, '-')  || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+' || RPAD('-', 12, '-') || '+');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' CIF', 13)         || '|' || RPAD(' NOM CLIENT', 28)       || '|'
            || RPAD(' CAT', 8)          || '|' || RPAD(' NATIONALITE', 14)      || '|'
            || RPAD(' CPT.A', 7)        || '|' || RPAD(' SOLDE TOTAL', 18)      || '|'
            || RPAD(' DERN.TXN', 12)    || '|' || RPAD(' PEP_REMARKS', 12)      || '|');
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 8, '-')  || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+' || RPAD('-', 12, '-') || '+');

        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY,
                       kr.NATIONALITY, kr.PEP_REMARKS,
                       ac.nb_cpt, ac.solde_total, ac.last_txn
                FROM STTM_KYC_RETAIL kr
                JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = kr.KYC_REF_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE kr.PEP = 'Y'
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 25
        ) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
                || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 26), ''), 28) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_CATEGORY, 1, 6), ''), 8) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.NATIONALITY, 1, 12), ''), 14) || '|'
                || LPAD(NVL(TO_CHAR(r.nb_cpt), '0'), 5) || '  |'
                || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |'
                || RPAD(' ' || CASE WHEN r.last_txn = DATE '1900-01-01' THEN 'N/A'
                                    ELSE TO_CHAR(r.last_txn, 'DD/MM/YYYY') END, 12) || '|'
                || RPAD(' ' || CASE WHEN r.PEP_REMARKS IS NOT NULL AND r.PEP_REMARKS != ' '
                                    THEN 'OUI' ELSE 'NON' END, 12) || '|');
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 8, '-')  || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+' || RPAD('-', 12, '-') || '+');
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-202 : PEP sans documentation (PEP_REMARKS)
    -- ---------------------------------------------------------
    p_test('AML-202', 'PEP sans documentation justificative (PEP_REMARKS vide)');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE PEP = 'Y' AND (PEP_REMARKS IS NULL OR PEP_REMARKS = ' ');
    p_kv('PEP sans PEP_REMARKS', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_finding('ELEVEE', v_count || ' PEP n''ont aucune remarque documentée.');
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_KYC_RETAIL kr
                JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = kr.KYC_REF_NO
                LEFT JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE kr.PEP = 'Y' AND (kr.PEP_REMARKS IS NULL OR kr.PEP_REMARKS = ' ')
                ORDER BY NVL(ac.solde_total, 0) DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, NVL(r.nb_cpt, 0), NVL(r.solde_total, 0),
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-203 : Clients Haut Risque (Level3) avec comptes actifs
    -- ---------------------------------------------------------
    p_test('AML-203', 'Clients classés Haut Risque (Level3) avec comptes actifs');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_MASTER WHERE RISK_LEVEL = 'Level3';
    p_kv('Total clients Level3', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count2 FROM STTM_KYC_MASTER m
    JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = m.KYC_REF_NO
    WHERE m.RISK_LEVEL = 'Level3'
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Dont avec comptes actifs', TO_CHAR(v_count2));

    -- Répartition par type de client
    DBMS_OUTPUT.PUT_LINE('  Répartition Level3 par type KYC :');
    FOR r IN (
        SELECT m.KYC_CUST_TYPE, COUNT(*) nb
        FROM STTM_KYC_MASTER m WHERE m.RISK_LEVEL = 'Level3'
        GROUP BY m.KYC_CUST_TYPE ORDER BY nb DESC
    ) LOOP
        p_kv('    KYC_CUST_TYPE = ' || r.KYC_CUST_TYPE, TO_CHAR(r.nb));
    END LOOP;

    IF v_count2 > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Top 20 clients Level3 avec comptes actifs (par solde) :');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_KYC_MASTER m
                JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = m.KYC_REF_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE m.RISK_LEVEL = 'Level3'
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-204 : Non-résidents avec comptes actifs
    -- ---------------------------------------------------------
    p_test('AML-204', 'Clients non-résidents avec comptes actifs');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE RESIDENT = 'N';
    p_kv('Total non-résidents (KYC Retail)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE RESIDENT_STATUS = 'N';
    p_kv('Total non-résidents (CUST_PERSONAL)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count2 FROM STTM_KYC_RETAIL kr
    JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = kr.KYC_REF_NO
    WHERE kr.RESIDENT = 'N'
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Non-résidents avec comptes actifs', TO_CHAR(v_count2));

    -- Nationalités des non-résidents
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Top 10 nationalités non-résidents (KYC) :');
    FOR r IN (
        SELECT NATIONALITY, nb FROM (
            SELECT kr.NATIONALITY, COUNT(*) nb FROM STTM_KYC_RETAIL kr
            WHERE kr.RESIDENT = 'N' AND kr.NATIONALITY IS NOT NULL AND kr.NATIONALITY != ' '
            GROUP BY kr.NATIONALITY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('    ' || r.NATIONALITY, TO_CHAR(r.nb));
    END LOOP;

    -- Top non-résidents par solde
    IF v_count2 > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Top 15 non-résidents avec comptes actifs (par solde) :');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_KYC_RETAIL kr
                JOIN STTM_CUSTOMER c ON c.KYC_REF_NO = kr.KYC_REF_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE kr.RESIDENT = 'N'
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-205 : Procuration (Power of Attorney) — risque de prête-nom
    -- ---------------------------------------------------------
    p_test('AML-205', 'Comptes avec procuration (Power of Attorney) — risque prête-nom');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PA_GIVEN = 'Y';
    p_kv('PA_GIVEN = Y (KYC Retail)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PA_ISSUED = 'Y';
    p_kv('PA_ISSUED = Y (CUST_PERSONAL)', TO_CHAR(v_count));

    -- Avec comptes actifs
    SELECT COUNT(*) INTO v_count2 FROM STTM_CUST_PERSONAL p
    WHERE p.PA_ISSUED = 'Y'
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = p.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  PA_ISSUED avec comptes actifs', TO_CHAR(v_count2));

    IF v_count2 > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        -- Tableau spécifique avec nom du mandataire
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 24, '-') || '+'
            || RPAD('-', 24, '-') || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' CIF', 13)          || '|' || RPAD(' TITULAIRE', 24)     || '|'
            || RPAD(' MANDATAIRE (PA)', 24) || '|' || RPAD(' NATIONALITE', 14) || '|'
            || RPAD(' CPT.A', 7)         || '|' || RPAD(' SOLDE TOTAL', 18)   || '|'
            || RPAD(' DERN.TXN', 12)     || '|');
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 24, '-') || '+'
            || RPAD('-', 24, '-') || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');

        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                       p.PA_HOLDER_NAME, p.PA_HOLDER_NATIONALTY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn
                FROM STTM_CUST_PERSONAL p
                JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE p.PA_ISSUED = 'Y'
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
                || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 22), ''), 24) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.PA_HOLDER_NAME, 1, 22), 'N/A'), 24) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.PA_HOLDER_NATIONALTY, 1, 12), ''), 14) || '|'
                || LPAD(NVL(TO_CHAR(r.nb_cpt), '0'), 5) || '  |'
                || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |'
                || RPAD(' ' || CASE WHEN r.last_txn = DATE '1900-01-01' THEN 'N/A'
                                    ELSE TO_CHAR(r.last_txn, 'DD/MM/YYYY') END, 12) || '|');
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 24, '-') || '+'
            || RPAD('-', 24, '-') || '+' || RPAD('-', 14, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-206 : Catégories client à risque élevé
    -- ---------------------------------------------------------
    p_test('AML-206', 'Catégories clients à surveillance renforcée');

    DBMS_OUTPUT.PUT_LINE('  Catégories sensibles identifiées dans le référentiel :');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 18, '-') || '+'
        || RPAD('-', 50, '-') || '+' || RPAD('-', 10, '-') || '+'
        || RPAD('-', 14, '-') || '+');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' CODE', 18) || '|'
        || RPAD(' DESCRIPTION', 50) || '|'
        || RPAD(' NB CLIENTS', 10) || '|'
        || RPAD(' AVEC CPT ACT', 14) || '|');
    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 18, '-') || '+'
        || RPAD('-', 50, '-') || '+' || RPAD('-', 10, '-') || '+'
        || RPAD('-', 14, '-') || '+');

    FOR r IN (
        SELECT cat.CUST_CAT, cat.CUST_CAT_DESC,
               NVL(cnt.nb, 0) nb_clients,
               NVL(cnt.nb_actif, 0) nb_actif
        FROM STTM_CUSTOMER_CAT cat
        LEFT JOIN (
            SELECT c.CUSTOMER_CATEGORY,
                   COUNT(*) nb,
                   COUNT(CASE WHEN EXISTS (
                       SELECT 1 FROM STTM_CUST_ACCOUNT a
                       WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O'
                   ) THEN 1 END) nb_actif
            FROM STTM_CUSTOMER c
            GROUP BY c.CUSTOMER_CATEGORY
        ) cnt ON cnt.CUSTOMER_CATEGORY = cat.CUST_CAT
        WHERE cat.CUST_CAT IN ('PEP/FEPS', 'BDC', 'FOREIGN', 'NRA1', 'NRA2',
                                'WALKIN', 'GATEKEEPER', 'WATCH CUST', 'GAMING',
                                'ECOMMERCE', 'CRYPTRADE', 'HIGHVALUE',
                                'IMTO', 'FTZ', 'UNKNOWN')
        ORDER BY NVL(cnt.nb, 0) DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' ' || r.CUST_CAT, 18) || '|'
            || RPAD(' ' || NVL(SUBSTR(r.CUST_CAT_DESC, 1, 48), ''), 50) || '|'
            || LPAD(TO_CHAR(r.nb_clients), 9) || ' |'
            || LPAD(TO_CHAR(r.nb_actif), 13) || ' |');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 18, '-') || '+'
        || RPAD('-', 50, '-') || '+' || RPAD('-', 10, '-') || '+'
        || RPAD('-', 14, '-') || '+');


    -- =========================================================
    -- FIN SECTION 2
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> FIN SECTION 2 — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);


    -- =========================================================
    -- SECTION 3 : CONTROLES D'IDENTITE & DOUBLONS
    -- =========================================================
    p_section('SECTION 3 : CONTROLES D''IDENTITE & DOUBLONS');

    -- ---------------------------------------------------------
    -- TEST AML-301 : Doublons de pièce nationale d'identité
    -- ---------------------------------------------------------
    p_test('AML-301', 'Doublons de P_NATIONAL_ID (même CNI pour plusieurs clients)');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT P_NATIONAL_ID FROM STTM_CUST_PERSONAL
        WHERE P_NATIONAL_ID IS NOT NULL AND P_NATIONAL_ID != ' '
        GROUP BY P_NATIONAL_ID HAVING COUNT(*) > 1
    );
    p_kv('Nb P_NATIONAL_ID en doublon', TO_CHAR(v_count));

    -- Nombre total de clients impliqués
    SELECT COUNT(*) INTO v_count2 FROM STTM_CUST_PERSONAL p
    WHERE p.P_NATIONAL_ID IN (
        SELECT P_NATIONAL_ID FROM STTM_CUST_PERSONAL
        WHERE P_NATIONAL_ID IS NOT NULL AND P_NATIONAL_ID != ' '
        GROUP BY P_NATIONAL_ID HAVING COUNT(*) > 1
    );
    p_kv('Nb clients impliqués', TO_CHAR(v_count2));

    IF v_count > 0 THEN
        p_finding('ELEVEE', 'Des CNI identiques sont partagées entre plusieurs clients.');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Échantillon doublons CNI (10 premiers, avec info comptes) :');

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 28, '-') || '+' || RPAD('-', 6, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' P_NATIONAL_ID', 18) || '|' || RPAD(' CIF', 13) || '|'
            || RPAD(' NOM CLIENT', 28)    || '|' || RPAD(' TYPE', 6) || '|'
            || RPAD(' CPT.A', 7)          || '|' || RPAD(' SOLDE TOTAL', 18) || '|'
            || RPAD(' DERN.TXN', 12)      || '|');
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 28, '-') || '+' || RPAD('-', 6, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');

        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT p.P_NATIONAL_ID, c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE,
                       NVL(ac.nb_cpt, 0) nb_cpt, NVL(ac.solde_total, 0) solde_total, ac.last_txn
                FROM STTM_CUST_PERSONAL p
                JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
                LEFT JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE p.P_NATIONAL_ID IN (
                    SELECT P_NATIONAL_ID FROM STTM_CUST_PERSONAL
                    WHERE P_NATIONAL_ID IS NOT NULL AND P_NATIONAL_ID != ' '
                    GROUP BY P_NATIONAL_ID HAVING COUNT(*) > 1
                )
                ORDER BY p.P_NATIONAL_ID, NVL(ac.solde_total, 0) DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
                || RPAD(' ' || NVL(SUBSTR(r.P_NATIONAL_ID, 1, 16), ''), 18) || '|'
                || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13)              || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 26), ''), 28) || '|'
                || RPAD(' ' || NVL(r.CUSTOMER_TYPE, ''), 6)             || '|'
                || LPAD(TO_CHAR(r.nb_cpt), 5) || '  |'
                || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |'
                || RPAD(' ' || CASE WHEN r.last_txn IS NULL OR r.last_txn = DATE '1900-01-01'
                                    THEN 'N/A' ELSE TO_CHAR(r.last_txn, 'DD/MM/YYYY') END, 12) || '|');
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 28, '-') || '+' || RPAD('-', 6, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+'
            || RPAD('-', 12, '-') || '+');
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-302 : Doublons de UNIQUE_ID_VALUE
    -- ---------------------------------------------------------
    p_test('AML-302', 'Doublons de UNIQUE_ID_VALUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT UNIQUE_ID_VALUE FROM STTM_CUSTOMER
        WHERE UNIQUE_ID_VALUE IS NOT NULL AND UNIQUE_ID_VALUE != ' '
        GROUP BY UNIQUE_ID_VALUE HAVING COUNT(*) > 1
    );
    p_kv('Nb UNIQUE_ID_VALUE en doublon', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count2 FROM STTM_CUSTOMER c
    WHERE c.UNIQUE_ID_VALUE IN (
        SELECT UNIQUE_ID_VALUE FROM STTM_CUSTOMER
        WHERE UNIQUE_ID_VALUE IS NOT NULL AND UNIQUE_ID_VALUE != ' '
        GROUP BY UNIQUE_ID_VALUE HAVING COUNT(*) > 1
    );
    p_kv('Nb clients impliqués', TO_CHAR(v_count2));

    IF v_count > 0 THEN
        p_finding('ELEVEE', 'Des identifiants uniques sont partagés entre plusieurs clients.');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Échantillon doublons UNIQUE_ID (10 premiers) :');

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 8, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' UNIQUE_ID_VALUE', 18) || '|' || RPAD(' ID_NAME', 8) || '|'
            || RPAD(' CIF', 13)    || '|' || RPAD(' NOM CLIENT', 28) || '|'
            || RPAD(' CPT.A', 7)   || '|' || RPAD(' SOLDE TOTAL', 18) || '|');
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 8, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');

        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.UNIQUE_ID_VALUE, c.UNIQUE_ID_NAME, c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                       NVL(ac.nb_cpt, 0) nb_cpt, NVL(ac.solde_total, 0) solde_total
                FROM STTM_CUSTOMER c
                LEFT JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE c.UNIQUE_ID_VALUE IN (
                    SELECT UNIQUE_ID_VALUE FROM STTM_CUSTOMER
                    WHERE UNIQUE_ID_VALUE IS NOT NULL AND UNIQUE_ID_VALUE != ' '
                    GROUP BY UNIQUE_ID_VALUE HAVING COUNT(*) > 1
                )
                ORDER BY c.UNIQUE_ID_VALUE, NVL(ac.solde_total, 0) DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
                || RPAD(' ' || NVL(SUBSTR(r.UNIQUE_ID_VALUE, 1, 16), ''), 18) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.UNIQUE_ID_NAME, 1, 6), ''), 8)   || '|'
                || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13)               || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 26), ''), 28) || '|'
                || LPAD(TO_CHAR(r.nb_cpt), 5) || '  |'
                || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |');
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 18, '-') || '+' || RPAD('-', 8, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-303 : Doublons de passeport
    -- ---------------------------------------------------------
    p_test('AML-303', 'Doublons de numéro de passeport');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT PASSPORT_NO FROM STTM_CUST_PERSONAL
        WHERE PASSPORT_NO IS NOT NULL AND PASSPORT_NO != ' '
        GROUP BY PASSPORT_NO HAVING COUNT(*) > 1
    );
    p_kv('Nb PASSPORT_NO en doublon (CUST_PERSONAL)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count2 FROM (
        SELECT PASSPORT_NO FROM STTM_KYC_RETAIL
        WHERE PASSPORT_NO IS NOT NULL AND PASSPORT_NO != ' '
        GROUP BY PASSPORT_NO HAVING COUNT(*) > 1
    );
    p_kv('Nb PASSPORT_NO en doublon (KYC_RETAIL)', TO_CHAR(v_count2));

    -- ---------------------------------------------------------
    -- TEST AML-304 : Clients sans AUCUNE identification
    -- ---------------------------------------------------------
    p_test('AML-304', 'Clients sans aucune forme d''identification');

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    LEFT JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE (c.UNIQUE_ID_VALUE IS NULL OR c.UNIQUE_ID_VALUE = ' ')
      AND (p.P_NATIONAL_ID IS NULL OR p.P_NATIONAL_ID = ' ')
      AND (p.PASSPORT_NO IS NULL OR p.PASSPORT_NO = ' ')
      AND c.CUSTOMER_TYPE = 'I';
    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER WHERE CUSTOMER_TYPE = 'I';
    p_pct('Individus sans aucune ID', v_count, v_total);

    -- Dont avec comptes actifs
    SELECT COUNT(*) INTO v_count2
    FROM STTM_CUSTOMER c
    LEFT JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE (c.UNIQUE_ID_VALUE IS NULL OR c.UNIQUE_ID_VALUE = ' ')
      AND (p.P_NATIONAL_ID IS NULL OR p.P_NATIONAL_ID = ' ')
      AND (p.PASSPORT_NO IS NULL OR p.PASSPORT_NO = ' ')
      AND c.CUSTOMER_TYPE = 'I'
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = c.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Dont avec comptes actifs', TO_CHAR(v_count2));

    IF v_count2 > 0 THEN
        p_finding('CRITIQUE', v_count2 || ' individus opèrent des comptes sans aucune pièce d''identité.');
        DBMS_OUTPUT.PUT_LINE('');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUSTOMER c
                LEFT JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE (c.UNIQUE_ID_VALUE IS NULL OR c.UNIQUE_ID_VALUE = ' ')
                  AND (p.P_NATIONAL_ID IS NULL OR p.P_NATIONAL_ID = ' ')
                  AND (p.PASSPORT_NO IS NULL OR p.PASSPORT_NO = ' ')
                  AND c.CUSTOMER_TYPE = 'I'
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-305 : Incohérence dates de naissance entre tables
    -- ---------------------------------------------------------
    p_test('AML-305', 'Incohérence DATE_OF_BIRTH (CUST_PERSONAL) vs BIRTH_DATE (KYC_RETAIL)');

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_PERSONAL p
    JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL kr ON kr.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.DATE_OF_BIRTH IS NOT NULL
      AND kr.BIRTH_DATE IS NOT NULL
      AND p.DATE_OF_BIRTH != kr.BIRTH_DATE;
    p_kv('Incohérences DATE_OF_BIRTH vs BIRTH_DATE', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_finding('MOYENNE', 'Des dates de naissance divergent entre CUST_PERSONAL et KYC_RETAIL.');
        DBMS_OUTPUT.PUT_LINE('');

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#', 4) || '|'
            || RPAD(' CIF', 13)        || '|' || RPAD(' NOM CLIENT', 28)    || '|'
            || RPAD(' DOB PERSONAL', 13) || '|' || RPAD(' DOB KYC', 13) || '|'
            || RPAD(' CPT.A', 7)       || '|' || RPAD(' SOLDE TOTAL', 18) || '|');
        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');

        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                       p.DATE_OF_BIRTH, kr.BIRTH_DATE,
                       NVL(ac.nb_cpt, 0) nb_cpt, NVL(ac.solde_total, 0) solde_total
                FROM STTM_CUST_PERSONAL p
                JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
                JOIN STTM_KYC_RETAIL kr ON kr.KYC_REF_NO = c.KYC_REF_NO
                LEFT JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE p.DATE_OF_BIRTH IS NOT NULL AND kr.BIRTH_DATE IS NOT NULL
                  AND p.DATE_OF_BIRTH != kr.BIRTH_DATE
                ORDER BY NVL(ac.solde_total, 0) DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(TO_CHAR(v_row_num), 3) || ' |'
                || RPAD(' ' || NVL(r.CUSTOMER_NO, ''), 13) || '|'
                || RPAD(' ' || NVL(SUBSTR(r.CUSTOMER_NAME1, 1, 26), ''), 28) || '|'
                || RPAD(' ' || TO_CHAR(r.DATE_OF_BIRTH, 'DD/MM/YYYY'), 13) || '|'
                || RPAD(' ' || TO_CHAR(r.BIRTH_DATE, 'DD/MM/YYYY'), 13)    || '|'
                || LPAD(TO_CHAR(r.nb_cpt), 5) || '  |'
                || LPAD(NVL(TO_CHAR(r.solde_total, 'FM999G999G999G990'), '0'), 17) || ' |');
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('  +' || RPAD('-', 4, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 28, '-') || '+'
            || RPAD('-', 13, '-') || '+' || RPAD('-', 13, '-') || '+'
            || RPAD('-', 7, '-')  || '+' || RPAD('-', 18, '-') || '+');
    END IF;

    -- ---------------------------------------------------------
    -- TEST AML-306 : Clients mineurs avec comptes actifs
    -- ---------------------------------------------------------
    p_test('AML-306', 'Clients mineurs (MINOR=Y ou âge < 18) avec comptes actifs');

    -- Depuis CUST_PERSONAL.MINOR
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE MINOR = 'Y';
    p_kv('Clients MINOR=Y (CUST_PERSONAL)', TO_CHAR(v_count));

    -- Calcul par l'âge réel (DATE_OF_BIRTH)
    SELECT COUNT(*) INTO v_count2 FROM STTM_CUST_PERSONAL
    WHERE DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, DATE_OF_BIRTH) / 12 < 18;
    p_kv('Clients âge < 18 ans (par DOB)', TO_CHAR(v_count2));

    -- Mineurs avec comptes actifs
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL p
    WHERE (p.MINOR = 'Y' OR (p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 < 18))
      AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_NO = p.CUSTOMER_NO AND a.RECORD_STAT = 'O');
    p_kv('  Mineurs avec comptes actifs', TO_CHAR(v_count));

    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  Échantillon mineurs avec comptes actifs :');
        p_tbl_header;
        v_row_num := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE, c.CUSTOMER_CATEGORY,
                       ac.nb_cpt, ac.solde_total, ac.last_txn, ac.first_open
                FROM STTM_CUST_PERSONAL p
                JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUSTOMER_NO
                JOIN (
                    SELECT CUST_NO, COUNT(*) nb_cpt, SUM(ACY_CURR_BALANCE) solde_total,
                           GREATEST(MAX(NVL(DATE_LAST_CR_ACTIVITY, DATE '1900-01-01')),
                                    MAX(NVL(DATE_LAST_DR_ACTIVITY, DATE '1900-01-01'))) last_txn,
                           MIN(AC_OPEN_DATE) first_open
                    FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT = 'O' GROUP BY CUST_NO
                ) ac ON ac.CUST_NO = c.CUSTOMER_NO
                WHERE p.MINOR = 'Y' OR (p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 < 18)
                ORDER BY ac.solde_total DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            v_row_num := v_row_num + 1;
            p_tbl_row(v_row_num, r.CUSTOMER_NO, r.CUSTOMER_NAME1, r.CUSTOMER_TYPE,
                      r.CUSTOMER_CATEGORY, r.nb_cpt, r.solde_total,
                      CASE WHEN r.last_txn = DATE '1900-01-01' THEN NULL ELSE r.last_txn END,
                      r.first_open);
        END LOOP;
        p_tbl_line;
    END IF;


    -- =========================================================
    -- FIN SECTION 3
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> FIN SECTION 3 — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
