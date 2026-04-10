-- ============================================================
-- SCRIPT DE TESTS DE COHERENCE DES DONNEES INTER-TABLES
-- Base : FLEXCUBE (FCUBS) — AML/KYC
-- ============================================================
-- Ce script vérifie que les données censées représenter la même
-- information pour un client sont cohérentes entre les différentes
-- tables de la base de données.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_total         NUMBER;
    v_sep           VARCHAR2(80) := RPAD('=', 80, '=');
    v_test_no       NUMBER := 0;
    v_anomalies     NUMBER := 0;

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
                || RPAD(p_label, 55, '.') || ' '
                || p_count || ' / ' || p_total
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        ELSE
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 55, '.') || ' '
                || p_count
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        END IF;
        IF p_count > 0 THEN
            v_anomalies := v_anomalies + 1;
        END IF;
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TESTS DE COHERENCE DES DONNEES — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- 1. COHERENCE STTM_CUST_PERSONAL vs STTM_KYC_RETAIL
    --    (champs d'identité dupliqués)
    -- =========================================================
    print_section('1. COHERENCE STTM_CUST_PERSONAL vs STTM_KYC_RETAIL');

    -- 1.1 Date de naissance
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.DATE_OF_BIRTH IS NOT NULL
      AND r.BIRTH_DATE IS NOT NULL
      AND p.DATE_OF_BIRTH != r.BIRTH_DATE;
    print_test('Date naissance PERSONAL vs KYC_RETAIL', v_count);

    -- 1.2 Pays de naissance
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.BIRTH_COUNTRY IS NOT NULL AND TRIM(p.BIRTH_COUNTRY) IS NOT NULL
      AND r.BIRTH_COUNTRY IS NOT NULL AND TRIM(r.BIRTH_COUNTRY) IS NOT NULL
      AND TRIM(p.BIRTH_COUNTRY) != TRIM(r.BIRTH_COUNTRY);
    print_test('Pays naissance PERSONAL vs KYC_RETAIL', v_count);

    -- 1.3 Lieu de naissance
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PLACE_OF_BIRTH IS NOT NULL AND TRIM(p.PLACE_OF_BIRTH) IS NOT NULL
      AND r.BIRTH_PLACE IS NOT NULL AND TRIM(r.BIRTH_PLACE) IS NOT NULL
      AND UPPER(TRIM(p.PLACE_OF_BIRTH)) != UPPER(TRIM(r.BIRTH_PLACE));
    print_test('Lieu naissance PERSONAL vs KYC_RETAIL', v_count);

    -- 1.4 Numéro de passeport
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PASSPORT_NO IS NOT NULL AND TRIM(p.PASSPORT_NO) IS NOT NULL
      AND r.PASSPORT_NO IS NOT NULL AND TRIM(r.PASSPORT_NO) IS NOT NULL
      AND TRIM(p.PASSPORT_NO) != TRIM(r.PASSPORT_NO);
    print_test('N° passeport PERSONAL vs KYC_RETAIL', v_count);

    -- 1.5 Date expiration passeport
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PPT_EXP_DATE IS NOT NULL
      AND r.PASSPORT_EXPIRY_DATE IS NOT NULL
      AND p.PPT_EXP_DATE != r.PASSPORT_EXPIRY_DATE;
    print_test('Expiration passeport PERSONAL vs KYC_RETAIL', v_count);

    -- 1.6 Statut résident US (FATCA)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.US_RES_STATUS IS NOT NULL AND TRIM(p.US_RES_STATUS) IS NOT NULL
      AND r.US_RES_STATUS IS NOT NULL AND TRIM(r.US_RES_STATUS) IS NOT NULL
      AND TRIM(p.US_RES_STATUS) != TRIM(r.US_RES_STATUS);
    print_test('US_RES_STATUS PERSONAL vs KYC_RETAIL', v_count);

    -- 1.7 Procuration (PA) émise vs donnée
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PA_ISSUED IS NOT NULL AND TRIM(p.PA_ISSUED) IS NOT NULL
      AND r.PA_GIVEN IS NOT NULL AND TRIM(r.PA_GIVEN) IS NOT NULL
      AND TRIM(p.PA_ISSUED) != TRIM(r.PA_GIVEN);
    print_test('Procuration PA_ISSUED vs PA_GIVEN', v_count);

    -- 1.8 Nom du détenteur de la procuration
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PA_HOLDER_NAME IS NOT NULL AND TRIM(p.PA_HOLDER_NAME) IS NOT NULL
      AND r.PA_HOLDER_NAME IS NOT NULL AND TRIM(r.PA_HOLDER_NAME) IS NOT NULL
      AND UPPER(TRIM(p.PA_HOLDER_NAME)) != UPPER(TRIM(r.PA_HOLDER_NAME));
    print_test('PA_HOLDER_NAME PERSONAL vs KYC_RETAIL', v_count);

    -- 1.9 Statut résidence (PERSONAL.RESIDENT_STATUS vs KYC_RETAIL.RESIDENT)
    -- RESIDENT_STATUS: R/N, RESIDENT: Y/N — R correspond à Y, N correspond à N
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.RESIDENT_STATUS IS NOT NULL AND TRIM(p.RESIDENT_STATUS) IS NOT NULL
      AND r.RESIDENT IS NOT NULL AND TRIM(r.RESIDENT) IS NOT NULL
      AND (
          (TRIM(p.RESIDENT_STATUS) = 'R' AND TRIM(r.RESIDENT) != 'Y')
          OR (TRIM(p.RESIDENT_STATUS) = 'N' AND TRIM(r.RESIDENT) != 'N')
      );
    print_test('Résidence PERSONAL(R/N) vs KYC_RETAIL(Y/N)', v_count);

    -- 1.10 Nationalité STTM_CUSTOMER vs KYC_RETAIL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.NATIONALITY IS NOT NULL AND TRIM(c.NATIONALITY) IS NOT NULL
      AND r.NATIONALITY IS NOT NULL AND TRIM(r.NATIONALITY) IS NOT NULL
      AND TRIM(c.NATIONALITY) != TRIM(r.NATIONALITY);
    print_test('Nationalité CUSTOMER vs KYC_RETAIL', v_count);

    -- =========================================================
    -- 2. COHERENCE TYPE CLIENT vs TABLES DE DETAIL
    -- =========================================================
    print_section('2. COHERENCE TYPE CLIENT vs TABLES DE DETAIL');

    -- 2.1 CUSTOMER_TYPE (I=Individuel) vs KYC_CUST_TYPE (R=Retail)
    -- I doit correspondre à R, C à C, B à F
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.KYC_REF_NO IS NOT NULL AND TRIM(c.KYC_REF_NO) IS NOT NULL
      AND (
          (c.CUSTOMER_TYPE = 'I' AND m.KYC_CUST_TYPE != 'R')
          OR (c.CUSTOMER_TYPE = 'C' AND m.KYC_CUST_TYPE != 'C')
          OR (c.CUSTOMER_TYPE = 'B' AND m.KYC_CUST_TYPE != 'F')
      );
    print_test('CUSTOMER_TYPE(I/C/B) vs KYC_CUST_TYPE(R/C/F)', v_count);

    -- 2.2 Client individuel (type I) sans données personnelles
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_TYPE = 'I'
      AND NOT EXISTS (
          SELECT 1 FROM STTM_CUST_PERSONAL p
          WHERE p.CUSTOMER_NO = c.CUSTOMER_NO
      );
    print_test('Type I sans fiche STTM_CUST_PERSONAL', v_count);

    -- 2.3 Client corporel (type C) avec KYC mais sans fiche Corporate
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_TYPE = 'C'
      AND m.KYC_CUST_TYPE = 'C'
      AND NOT EXISTS (
          SELECT 1 FROM STTM_KYC_CORPORATE k
          WHERE k.KYC_REF_NO = c.KYC_REF_NO
      );
    print_test('Type C (KYC=C) sans fiche KYC_CORPORATE', v_count);

    -- 2.4 Client individuel (type I) avec KYC mais sans fiche Retail
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_TYPE = 'I'
      AND m.KYC_CUST_TYPE = 'R'
      AND NOT EXISTS (
          SELECT 1 FROM STTM_KYC_RETAIL r
          WHERE r.KYC_REF_NO = c.KYC_REF_NO
      );
    print_test('Type I (KYC=R) sans fiche KYC_RETAIL', v_count);

    -- 2.5 STAFF=Y mais catégorie != STAF
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE STAFF = 'Y'
      AND CUSTOMER_CATEGORY != 'STAF';
    print_test('STAFF=Y mais catégorie != STAF', v_count);

    -- 2.6 Catégorie STAF mais STAFF != Y
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE CUSTOMER_CATEGORY = 'STAF'
      AND (STAFF IS NULL OR STAFF != 'Y');
    print_test('Catégorie STAF mais STAFF != Y', v_count);

    -- 2.7 Catégorie PEP/FEPS mais PEP != Y dans KYC_RETAIL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PEP/FEPS'
      AND (r.PEP IS NULL OR r.PEP != 'Y');
    print_test('Catégorie PEP/FEPS mais PEP != Y (KYC)', v_count);

    -- 2.8 PEP=Y dans KYC mais catégorie != PEP/FEPS
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE r.PEP = 'Y'
      AND c.CUSTOMER_CATEGORY != 'PEP/FEPS';
    print_test('PEP=Y (KYC) mais catégorie != PEP/FEPS', v_count);

    -- =========================================================
    -- 3. COHERENCE CATEGORIE CLIENT vs AGE / REVENUS
    --    Basé sur les définitions STTM_CUSTOMER_CAT :
    --    MINORS = 0-18 ans, STUDENTS = 19-28, SENIORS = 60+
    --    CSE1 < 250K, CSE2 > 250K (fonctionnaires)
    --    PSE1 < 350K, PSE2 = 350K-1M, PSE3 > 1M (secteur privé)
    --    PFBI > 1M mensuel (indépendants)
    -- =========================================================
    print_section('3. COHERENCE CATEGORIE CLIENT vs AGE / REVENUS');

    -- 3.1 Catégorie MINORS mais âge >= 18
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'MINORS'
      AND p.DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 >= 18;
    print_test('MINORS mais âge >= 18 ans', v_count);

    -- 3.2 Catégorie MINORS mais MINOR != Y
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'MINORS'
      AND (p.MINOR IS NULL OR p.MINOR != 'Y');
    print_test('MINORS mais MINOR != Y (PERSONAL)', v_count);

    -- 3.3 MINOR=Y mais catégorie != MINORS
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE p.MINOR = 'Y'
      AND c.CUSTOMER_CATEGORY != 'MINORS';
    print_test('MINOR=Y mais catégorie != MINORS', v_count);

    -- 3.4 Catégorie SENIORS mais âge < 60
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'SENIORS'
      AND p.DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 < 60;
    print_test('SENIORS mais âge < 60 ans', v_count);

    -- 3.5 Catégorie STUDENTS mais âge hors 19-28
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'STUDENTS'
      AND p.DATE_OF_BIRTH IS NOT NULL
      AND (MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 < 19
           OR MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 > 28);
    print_test('STUDENTS mais âge hors [19-28] ans', v_count);

    -- 3.6 CSE1 (fonctionnaires < 250K) mais revenu >= 250000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'CSE1'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND r.TOTAL_INCOME >= 250000;
    print_test('CSE1 (< 250K) mais TOTAL_INCOME >= 250K', v_count);

    -- 3.7 CSE2 (fonctionnaires > 250K) mais revenu < 250000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'CSE2'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND r.TOTAL_INCOME < 250000;
    print_test('CSE2 (> 250K) mais TOTAL_INCOME < 250K', v_count);

    -- 3.8 PSE1 (secteur privé < 350K) mais revenu >= 350000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE1'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND r.TOTAL_INCOME >= 350000;
    print_test('PSE1 (< 350K) mais TOTAL_INCOME >= 350K', v_count);

    -- 3.9 PSE2 (secteur privé 350K-1M) mais revenu hors fourchette
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE2'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND (r.TOTAL_INCOME < 350000 OR r.TOTAL_INCOME > 1000000);
    print_test('PSE2 (350K-1M) mais TOTAL_INCOME hors range', v_count);

    -- 3.10 PSE3 (secteur privé > 1M) mais revenu <= 1000000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE3'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND r.TOTAL_INCOME <= 1000000;
    print_test('PSE3 (> 1M) mais TOTAL_INCOME <= 1M', v_count);

    -- 3.11 PFBI (indépendants > 1M mensuel) mais revenu annuel <= 12M
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PFBI'
      AND r.TOTAL_INCOME IS NOT NULL
      AND r.TOTAL_INCOME > 0
      AND r.TOTAL_INCOME <= 12000000;
    print_test('PFBI (rev mensuel>1M) mais annuel <= 12M', v_count);

    -- 3.12 Catégorie VPFP (pensionnés) mais âge < 50
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'VPFP'
      AND p.DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 < 50;
    print_test('VPFP (pensionnés) mais âge < 50 ans', v_count);

    -- 3.13 Catégorie individuelle (INDV, MINORS, STUDENTS, etc.) mais CUSTOMER_TYPE != I
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE CUSTOMER_CATEGORY IN ('INDV', 'MINORS', 'STUDENTS', 'SENIORS',
          'CSE1', 'CSE2', 'PSE1', 'PSE2', 'PSE3', 'PFBI', 'VPFP',
          'SAL', 'STAF', 'RSA', 'RSA1', 'ABWP', 'PEP/FEPS', 'NRA1', 'NRA2')
      AND CUSTOMER_TYPE != 'I';
    print_test('Catégorie individuelle mais TYPE != I', v_count);

    -- 3.14 Catégorie corporate (CORP, SME, etc.) mais CUSTOMER_TYPE != C
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE CUSTOMER_CATEGORY IN ('CORP', 'SME', 'NGOs', 'GOVT', 'GOVT INST',
          'INSURANCE', 'CONSTRUCTN', 'HOSPITALIT', 'OIL&GAS', 'FIN_INT')
      AND CUSTOMER_TYPE != 'C';
    print_test('Catégorie corporate mais TYPE != C', v_count);

    -- =========================================================
    -- 4. COHERENCE STATUTS COMPTES
    --    STTM_CUST_ACCOUNT vs STTB_ACCOUNT
    -- =========================================================
    print_section('4. COHERENCE STATUTS COMPTES (CUST_ACCOUNT vs STTB_ACCOUNT)');

    -- 4.1 Statut dormant discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_DORMANT IS NOT NULL AND b.AC_STAT_DORMANT IS NOT NULL
      AND a.AC_STAT_DORMANT != b.AC_STAT_DORMANT;
    print_test('Dormant discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.2 Statut frozen discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_FROZEN IS NOT NULL AND b.AC_STAT_FROZEN IS NOT NULL
      AND a.AC_STAT_FROZEN != b.AC_STAT_FROZEN;
    print_test('Frozen discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.3 Statut blocked discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_BLOCK IS NOT NULL AND b.GL_STAT_BLOCKED IS NOT NULL
      AND a.AC_STAT_BLOCK != b.GL_STAT_BLOCKED;
    print_test('Blocked discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.4 Statut no_dr discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_NO_DR IS NOT NULL AND b.AC_STAT_NO_DR IS NOT NULL
      AND a.AC_STAT_NO_DR != b.AC_STAT_NO_DR;
    print_test('No DR discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.5 Statut no_cr discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_NO_CR IS NOT NULL AND b.AC_STAT_NO_CR IS NOT NULL
      AND a.AC_STAT_NO_CR != b.AC_STAT_NO_CR;
    print_test('No CR discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.6 Statut stop_pay discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_STOP_PAY IS NOT NULL AND b.AC_STAT_STOP_PAY IS NOT NULL
      AND a.AC_STAT_STOP_PAY != b.AC_STAT_STOP_PAY;
    print_test('Stop Pay discordant CUST_ACCOUNT vs STTB', v_count);

    -- 4.7 Devise discordante
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.CCY IS NOT NULL AND TRIM(a.CCY) IS NOT NULL
      AND b.AC_GL_CCY IS NOT NULL AND TRIM(b.AC_GL_CCY) IS NOT NULL
      AND TRIM(a.CCY) != TRIM(b.AC_GL_CCY);
    print_test('Devise CCY vs AC_GL_CCY discordante', v_count);

    -- 4.8 Client FROZEN=Y mais aucun compte gelé
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.FROZEN = 'Y'
      AND EXISTS (
          SELECT 1 FROM STTM_CUST_ACCOUNT a
          WHERE a.CUST_NO = c.CUSTOMER_NO
            AND a.AC_STAT_FROZEN != 'Y'
      );
    print_test('Client FROZEN=Y avec comptes non gelés', v_count);

    -- 4.9 RECORD_STAT discordant entre les deux tables
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.RECORD_STAT IS NOT NULL AND b.AC_GL_REC_STATUS IS NOT NULL
      AND a.RECORD_STAT != b.AC_GL_REC_STATUS;
    print_test('RECORD_STAT vs AC_GL_REC_STATUS discordant', v_count);

    -- =========================================================
    -- 5. COHERENCE PAYS / ADRESSES INTER-TABLES
    -- =========================================================
    print_section('5. COHERENCE PAYS / ADRESSES INTER-TABLES');

    -- 5.1 COUNTRY (STTM_CUSTOMER) vs D_COUNTRY (STTM_CUST_PERSONAL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.COUNTRY IS NOT NULL AND TRIM(c.COUNTRY) IS NOT NULL
      AND p.D_COUNTRY IS NOT NULL AND TRIM(p.D_COUNTRY) IS NOT NULL
      AND TRIM(c.COUNTRY) != TRIM(p.D_COUNTRY);
    print_test('COUNTRY(CUSTOMER) vs D_COUNTRY(PERSONAL)', v_count);

    -- 5.2 COUNTRY (STTM_CUSTOMER) vs LOCAL_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.COUNTRY IS NOT NULL AND TRIM(c.COUNTRY) IS NOT NULL
      AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(c.COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY);
    print_test('COUNTRY(CUSTOMER) vs LOCAL_ADDR(KYC_RETAIL)', v_count);

    -- 5.3 D_COUNTRY (PERSONAL) vs LOCAL_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.D_COUNTRY IS NOT NULL AND TRIM(p.D_COUNTRY) IS NOT NULL
      AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(p.D_COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY);
    print_test('D_COUNTRY(PERSONAL) vs LOCAL_ADDR(KYC)', v_count);

    -- 5.4 P_COUNTRY (PERSONAL) vs HOME_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.P_COUNTRY IS NOT NULL AND TRIM(p.P_COUNTRY) IS NOT NULL
      AND r.HOME_ADDR_COUNTRY IS NOT NULL AND TRIM(r.HOME_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(p.P_COUNTRY) != TRIM(r.HOME_ADDR_COUNTRY);
    print_test('P_COUNTRY(PERSONAL) vs HOME_ADDR(KYC)', v_count);

    -- 5.5 Non-résident mais pays = CMR
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE p.RESIDENT_STATUS = 'N'
      AND c.COUNTRY = 'CMR';
    print_test('Non-résident mais COUNTRY = CMR', v_count);

    -- 5.6 Catégorie NRA (non-résident) mais résident dans PERSONAL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY IN ('NRA1', 'NRA2')
      AND p.RESIDENT_STATUS = 'R';
    print_test('Catégorie NRA mais RESIDENT_STATUS = R', v_count);

    -- 5.7 Catégorie FOREIGN mais NATIONALITY = CMR
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_CATEGORY = 'FOREIGN'
      AND c.NATIONALITY = 'CMR';
    print_test('Catégorie FOREIGN mais nationalité = CMR', v_count);

    -- =========================================================
    -- FIN PROVISOIRE
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TOTAL TESTS EXECUTES : ' || v_test_no);
    DBMS_OUTPUT.PUT_LINE('   TESTS AVEC ANOMALIES : ' || v_anomalies);
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
