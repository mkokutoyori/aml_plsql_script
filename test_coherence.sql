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
