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
    v_row_num       NUMBER := 0;

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

    -- Dessine une ligne de séparation paramétrable
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

    -- Affiche une ligne de données formatée
    PROCEDURE tbl_cell(p_val VARCHAR2, p_width NUMBER, p_align VARCHAR2 DEFAULT 'L') IS
    BEGIN
        NULL; -- helper inline ci-dessous
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
    WHERE p.DATE_OF_BIRTH IS NOT NULL AND r.BIRTH_DATE IS NOT NULL
      AND p.DATE_OF_BIRTH != r.BIRTH_DATE;
    print_test('Date naissance PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.DATE_OF_BIRTH',22) || '|' || RPAD(' KYC_RETAIL.BIRTH_DATE',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TO_CHAR(p.DATE_OF_BIRTH,'DD/MM/YYYY') AS val_a,
                   TO_CHAR(r.BIRTH_DATE,'DD/MM/YYYY') AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.DATE_OF_BIRTH IS NOT NULL AND r.BIRTH_DATE IS NOT NULL AND p.DATE_OF_BIRTH != r.BIRTH_DATE
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.2 Pays de naissance
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.BIRTH_COUNTRY IS NOT NULL AND TRIM(p.BIRTH_COUNTRY) IS NOT NULL
      AND r.BIRTH_COUNTRY IS NOT NULL AND TRIM(r.BIRTH_COUNTRY) IS NOT NULL
      AND TRIM(p.BIRTH_COUNTRY) != TRIM(r.BIRTH_COUNTRY);
    print_test('Pays naissance PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.BIRTH_COUNTRY',22) || '|' || RPAD(' KYC_RETAIL.BIRTH_COUNTRY',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRIM(p.BIRTH_COUNTRY) AS val_a, TRIM(r.BIRTH_COUNTRY) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.BIRTH_COUNTRY IS NOT NULL AND TRIM(p.BIRTH_COUNTRY) IS NOT NULL
              AND r.BIRTH_COUNTRY IS NOT NULL AND TRIM(r.BIRTH_COUNTRY) IS NOT NULL
              AND TRIM(p.BIRTH_COUNTRY) != TRIM(r.BIRTH_COUNTRY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.3 Lieu de naissance
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PLACE_OF_BIRTH IS NOT NULL AND TRIM(p.PLACE_OF_BIRTH) IS NOT NULL
      AND r.BIRTH_PLACE IS NOT NULL AND TRIM(r.BIRTH_PLACE) IS NOT NULL
      AND UPPER(TRIM(p.PLACE_OF_BIRTH)) != UPPER(TRIM(r.BIRTH_PLACE));
    print_test('Lieu naissance PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.PLACE_OF_BIRTH',22) || '|' || RPAD(' KYC_RETAIL.BIRTH_PLACE',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   SUBSTR(TRIM(p.PLACE_OF_BIRTH),1,20) AS val_a,
                   SUBSTR(TRIM(r.BIRTH_PLACE),1,20) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.PLACE_OF_BIRTH IS NOT NULL AND TRIM(p.PLACE_OF_BIRTH) IS NOT NULL
              AND r.BIRTH_PLACE IS NOT NULL AND TRIM(r.BIRTH_PLACE) IS NOT NULL
              AND UPPER(TRIM(p.PLACE_OF_BIRTH)) != UPPER(TRIM(r.BIRTH_PLACE))
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.4 Numéro de passeport
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PASSPORT_NO IS NOT NULL AND TRIM(p.PASSPORT_NO) IS NOT NULL
      AND r.PASSPORT_NO IS NOT NULL AND TRIM(r.PASSPORT_NO) IS NOT NULL
      AND TRIM(p.PASSPORT_NO) != TRIM(r.PASSPORT_NO);
    print_test('N° passeport PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.PASSPORT_NO',22) || '|' || RPAD(' KYC_RETAIL.PASSPORT_NO',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   SUBSTR(TRIM(p.PASSPORT_NO),1,20) AS val_a, SUBSTR(TRIM(r.PASSPORT_NO),1,20) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.PASSPORT_NO IS NOT NULL AND TRIM(p.PASSPORT_NO) IS NOT NULL
              AND r.PASSPORT_NO IS NOT NULL AND TRIM(r.PASSPORT_NO) IS NOT NULL
              AND TRIM(p.PASSPORT_NO) != TRIM(r.PASSPORT_NO)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.5 Date expiration passeport
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PPT_EXP_DATE IS NOT NULL AND r.PASSPORT_EXPIRY_DATE IS NOT NULL
      AND p.PPT_EXP_DATE != r.PASSPORT_EXPIRY_DATE;
    print_test('Expiration passeport PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.PPT_EXP_DATE',22) || '|' || RPAD(' KYC_R.PASSPORT_EXP_DT',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TO_CHAR(p.PPT_EXP_DATE,'DD/MM/YYYY') AS val_a,
                   TO_CHAR(r.PASSPORT_EXPIRY_DATE,'DD/MM/YYYY') AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.PPT_EXP_DATE IS NOT NULL AND r.PASSPORT_EXPIRY_DATE IS NOT NULL
              AND p.PPT_EXP_DATE != r.PASSPORT_EXPIRY_DATE
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.6 Statut résident US (FATCA)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.US_RES_STATUS IS NOT NULL AND TRIM(p.US_RES_STATUS) IS NOT NULL
      AND r.US_RES_STATUS IS NOT NULL AND TRIM(r.US_RES_STATUS) IS NOT NULL
      AND TRIM(p.US_RES_STATUS) != TRIM(r.US_RES_STATUS);
    print_test('US_RES_STATUS PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.US_RES_STATUS',22) || '|' || RPAD(' KYC_R.US_RES_STATUS',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRIM(p.US_RES_STATUS) AS val_a, TRIM(r.US_RES_STATUS) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.US_RES_STATUS IS NOT NULL AND TRIM(p.US_RES_STATUS) IS NOT NULL
              AND r.US_RES_STATUS IS NOT NULL AND TRIM(r.US_RES_STATUS) IS NOT NULL
              AND TRIM(p.US_RES_STATUS) != TRIM(r.US_RES_STATUS)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.7 Procuration (PA) émise vs donnée
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PA_ISSUED IS NOT NULL AND TRIM(p.PA_ISSUED) IS NOT NULL
      AND r.PA_GIVEN IS NOT NULL AND TRIM(r.PA_GIVEN) IS NOT NULL
      AND TRIM(p.PA_ISSUED) != TRIM(r.PA_GIVEN);
    print_test('Procuration PA_ISSUED vs PA_GIVEN', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.PA_ISSUED',22) || '|' || RPAD(' KYC_RETAIL.PA_GIVEN',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRIM(p.PA_ISSUED) AS val_a, TRIM(r.PA_GIVEN) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.PA_ISSUED IS NOT NULL AND TRIM(p.PA_ISSUED) IS NOT NULL
              AND r.PA_GIVEN IS NOT NULL AND TRIM(r.PA_GIVEN) IS NOT NULL
              AND TRIM(p.PA_ISSUED) != TRIM(r.PA_GIVEN)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.8 Nom du détenteur de la procuration
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.PA_HOLDER_NAME IS NOT NULL AND TRIM(p.PA_HOLDER_NAME) IS NOT NULL
      AND r.PA_HOLDER_NAME IS NOT NULL AND TRIM(r.PA_HOLDER_NAME) IS NOT NULL
      AND UPPER(TRIM(p.PA_HOLDER_NAME)) != UPPER(TRIM(r.PA_HOLDER_NAME));
    print_test('PA_HOLDER_NAME PERSONAL vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.PA_HOLDER_NM',22) || '|' || RPAD(' KYC_R.PA_HOLDER_NAME',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   SUBSTR(TRIM(p.PA_HOLDER_NAME),1,20) AS val_a,
                   SUBSTR(TRIM(r.PA_HOLDER_NAME),1,20) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.PA_HOLDER_NAME IS NOT NULL AND TRIM(p.PA_HOLDER_NAME) IS NOT NULL
              AND r.PA_HOLDER_NAME IS NOT NULL AND TRIM(r.PA_HOLDER_NAME) IS NOT NULL
              AND UPPER(TRIM(p.PA_HOLDER_NAME)) != UPPER(TRIM(r.PA_HOLDER_NAME))
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.9 Statut résidence (PERSONAL.RESIDENT_STATUS vs KYC_RETAIL.RESIDENT)
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
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.RESIDENT_STAT',22) || '|' || RPAD(' KYC_RETAIL.RESIDENT',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRIM(p.RESIDENT_STATUS) AS val_a, TRIM(r.RESIDENT) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.RESIDENT_STATUS IS NOT NULL AND TRIM(p.RESIDENT_STATUS) IS NOT NULL
              AND r.RESIDENT IS NOT NULL AND TRIM(r.RESIDENT) IS NOT NULL
              AND ((TRIM(p.RESIDENT_STATUS) = 'R' AND TRIM(r.RESIDENT) != 'Y')
                   OR (TRIM(p.RESIDENT_STATUS) = 'N' AND TRIM(r.RESIDENT) != 'N'))
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- 1.10 Nationalité STTM_CUSTOMER vs KYC_RETAIL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.NATIONALITY IS NOT NULL AND TRIM(c.NATIONALITY) IS NOT NULL
      AND r.NATIONALITY IS NOT NULL AND TRIM(r.NATIONALITY) IS NOT NULL
      AND TRIM(c.NATIONALITY) != TRIM(r.NATIONALITY);
    print_test('Nationalité CUSTOMER vs KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,22,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.NATIONALITY',22) || '|' || RPAD(' KYC_RETAIL.NATIONALITY',22) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,22,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRIM(c.NATIONALITY) AS val_a, TRIM(r.NATIONALITY) AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.NATIONALITY IS NOT NULL AND TRIM(c.NATIONALITY) IS NOT NULL
              AND r.NATIONALITY IS NOT NULL AND TRIM(r.NATIONALITY) IS NOT NULL
              AND TRIM(c.NATIONALITY) != TRIM(r.NATIONALITY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),22) || '|' || RPAD(' ' || NVL(d.val_b,''),22) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,22,18');
    END IF;

    -- =========================================================
    -- 2. COHERENCE TYPE CLIENT vs TABLES DE DETAIL
    -- =========================================================
    print_section('2. COHERENCE TYPE CLIENT vs TABLES DE DETAIL');

    -- 2.1 CUSTOMER_TYPE (I=Individuel) vs KYC_CUST_TYPE (R=Retail)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.KYC_REF_NO IS NOT NULL AND TRIM(c.KYC_REF_NO) IS NOT NULL
      AND ((c.CUSTOMER_TYPE = 'I' AND m.KYC_CUST_TYPE != 'R')
          OR (c.CUSTOMER_TYPE = 'C' AND m.KYC_CUST_TYPE != 'C')
          OR (c.CUSTOMER_TYPE = 'B' AND m.KYC_CUST_TYPE != 'F'));
    print_test('CUSTOMER_TYPE(I/C/B) vs KYC_CUST_TYPE(R/C/F)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_TYPE',20) || '|' || RPAD(' KYC_M.KYC_CUST_TYPE',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE AS val_a, m.KYC_CUST_TYPE AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.KYC_REF_NO IS NOT NULL AND TRIM(c.KYC_REF_NO) IS NOT NULL
              AND ((c.CUSTOMER_TYPE='I' AND m.KYC_CUST_TYPE!='R') OR (c.CUSTOMER_TYPE='C' AND m.KYC_CUST_TYPE!='C') OR (c.CUSTOMER_TYPE='B' AND m.KYC_CUST_TYPE!='F'))
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.2 Client individuel (type I) sans données personnelles
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_TYPE = 'I'
      AND NOT EXISTS (SELECT 1 FROM STTM_CUST_PERSONAL p WHERE p.CUSTOMER_NO = c.CUSTOMER_NO);
    print_test('Type I sans fiche STTM_CUST_PERSONAL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_TYPE',20) || '|' || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE AS val_a, NVL(c.CUSTOMER_CATEGORY,'-') AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c
            WHERE c.CUSTOMER_TYPE = 'I'
              AND NOT EXISTS (SELECT 1 FROM STTM_CUST_PERSONAL p WHERE p.CUSTOMER_NO = c.CUSTOMER_NO)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.3 Client corporel (type C) avec KYC mais sans fiche Corporate
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_TYPE = 'C' AND m.KYC_CUST_TYPE = 'C'
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_CORPORATE k WHERE k.KYC_REF_NO = c.KYC_REF_NO);
    print_test('Type C (KYC=C) sans fiche KYC_CORPORATE', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_TYPE',20) || '|' || RPAD(' KYC_CORPORATE',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE AS val_a,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_TYPE = 'C' AND m.KYC_CUST_TYPE = 'C'
              AND NOT EXISTS (SELECT 1 FROM STTM_KYC_CORPORATE k WHERE k.KYC_REF_NO = c.KYC_REF_NO)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ABSENTE',20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.4 Client individuel (type I) avec KYC mais sans fiche Retail
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_TYPE = 'I' AND m.KYC_CUST_TYPE = 'R'
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_RETAIL r WHERE r.KYC_REF_NO = c.KYC_REF_NO);
    print_test('Type I (KYC=R) sans fiche KYC_RETAIL', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_TYPE',20) || '|' || RPAD(' KYC_RETAIL',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_TYPE AS val_a,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_MASTER m ON m.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_TYPE = 'I' AND m.KYC_CUST_TYPE = 'R'
              AND NOT EXISTS (SELECT 1 FROM STTM_KYC_RETAIL r WHERE r.KYC_REF_NO = c.KYC_REF_NO)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ABSENTE',20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.5 STAFF=Y mais catégorie != STAF
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER WHERE STAFF = 'Y' AND CUSTOMER_CATEGORY != 'STAF';
    print_test('STAFF=Y mais catégorie != STAF', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.STAFF',20) || '|' || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.STAFF AS val_a, c.CUSTOMER_CATEGORY AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c WHERE c.STAFF = 'Y' AND c.CUSTOMER_CATEGORY != 'STAF'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.6 Catégorie STAF mais STAFF != Y
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER WHERE CUSTOMER_CATEGORY = 'STAF' AND (STAFF IS NULL OR STAFF != 'Y');
    print_test('Catégorie STAF mais STAFF != Y', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' CUSTOMER.STAFF',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY AS val_a, NVL(c.STAFF,'NULL') AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c WHERE c.CUSTOMER_CATEGORY = 'STAF' AND (c.STAFF IS NULL OR c.STAFF != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.7 Catégorie PEP/FEPS mais PEP != Y dans KYC_RETAIL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PEP/FEPS' AND (r.PEP IS NULL OR r.PEP != 'Y');
    print_test('Catégorie PEP/FEPS mais PEP != Y (KYC)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' KYC_RETAIL.PEP',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY AS val_a, NVL(r.PEP,'NULL') AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'PEP/FEPS' AND (r.PEP IS NULL OR r.PEP != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 2.8 PEP=Y dans KYC mais catégorie != PEP/FEPS
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE r.PEP = 'Y' AND c.CUSTOMER_CATEGORY != 'PEP/FEPS';
    print_test('PEP=Y (KYC) mais catégorie != PEP/FEPS', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' KYC_RETAIL.PEP',20) || '|' || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, 'Y' AS val_a, c.CUSTOMER_CATEGORY AS val_b,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE r.PEP = 'Y' AND c.CUSTOMER_CATEGORY != 'PEP/FEPS'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.val_a,''),20) || '|' || RPAD(' ' || NVL(d.val_b,''),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

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
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'MINORS' AND p.DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH) / 12 >= 18;
    print_test('MINORS mais âge >= 18 ans', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,6,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.DATE_OF_BIRTH',22) || '|' || RPAD(' AGE',6) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,6,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRUNC(MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12) AS age_val,
                   TO_CHAR(p.DATE_OF_BIRTH,'DD/MM/YYYY') AS dob,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY = 'MINORS' AND p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 >= 18
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.dob,''),22) || '|' || LPAD(d.age_val,5) || ' |'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,6,18');
    END IF;

    -- 3.2 Catégorie MINORS mais MINOR != Y
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'MINORS' AND (p.MINOR IS NULL OR p.MINOR != 'Y');
    print_test('MINORS mais MINOR != Y (PERSONAL)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' PERSONAL.MINOR',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, NVL(p.MINOR,'NULL') AS minor_val,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY = 'MINORS' AND (p.MINOR IS NULL OR p.MINOR != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' MINORS',20) || '|' || RPAD(' ' || d.minor_val,20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 3.3 MINOR=Y mais catégorie != MINORS
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE p.MINOR = 'Y' AND c.CUSTOMER_CATEGORY != 'MINORS';
    print_test('MINOR=Y mais catégorie != MINORS', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.MINOR',20) || '|' || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE p.MINOR = 'Y' AND c.CUSTOMER_CATEGORY != 'MINORS'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' Y',20) || '|' || RPAD(' ' || NVL(d.CUSTOMER_CATEGORY,'-'),20) || '|'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 3.4 Catégorie SENIORS mais âge < 60
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'SENIORS' AND p.DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 60;
    print_test('SENIORS mais âge < 60 ans', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,6,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.DATE_OF_BIRTH',22) || '|' || RPAD(' AGE',6) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,6,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRUNC(MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12) AS age_val,
                   TO_CHAR(p.DATE_OF_BIRTH,'DD/MM/YYYY') AS dob,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY = 'SENIORS' AND p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 60
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.dob,''),22) || '|' || LPAD(d.age_val,5) || ' |'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,6,18');
    END IF;

    -- 3.5 Catégorie STUDENTS mais âge hors 19-28
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'STUDENTS' AND p.DATE_OF_BIRTH IS NOT NULL
      AND (MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 19 OR MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 > 28);
    print_test('STUDENTS mais âge hors [19-28] ans', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,22,6,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' PERSONAL.DATE_OF_BIRTH',22) || '|' || RPAD(' AGE',6) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,22,6,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRUNC(MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12) AS age_val,
                   TO_CHAR(p.DATE_OF_BIRTH,'DD/MM/YYYY') AS dob,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY = 'STUDENTS' AND p.DATE_OF_BIRTH IS NOT NULL
              AND (MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 19 OR MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 > 28)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' ' || NVL(d.dob,''),22) || '|' || LPAD(d.age_val,5) || ' |'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,22,6,18');
    END IF;

    -- 3.6 CSE1 (fonctionnaires < 250K) mais revenu >= 250000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'CSE1' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME >= 250000;
    print_test('CSE1 (< 250K) mais TOTAL_INCOME >= 250K', v_count);
    IF v_count > 0 THEN
        tbl_line('4,13,28,20,20,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',28) || '|'
            || RPAD(' CUSTOMER.CUST_CAT',20) || '|' || RPAD(' KYC_R.TOTAL_INCOME',20) || '|' || RPAD(' SOLDE TOTAL',18) || '|');
        tbl_line('4,13,28,20,20,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'CSE1' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME >= 250000
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUSTOMER_NO,13) || '|' || RPAD(' ' || SUBSTR(d.CUSTOMER_NAME1,1,26),28) || '|'
                || RPAD(' CSE1',20) || '|' || LPAD(TO_CHAR(d.TOTAL_INCOME,'FM999G999G999'),19) || ' |'
                || LPAD(TO_CHAR(d.total_solde,'FM999G999G999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,13,28,20,20,18');
    END IF;

    -- 3.7 CSE2 (fonctionnaires > 250K) mais revenu < 250000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'CSE2' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME < 250000;
    print_test('CSE2 (> 250K) mais TOTAL_INCOME < 250K', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'CSE2' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME < 250000
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=CSE2 Income=' || TO_CHAR(d.TOTAL_INCOME,'FM999G999G999')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.8 PSE1 (secteur privé < 350K) mais revenu >= 350000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE1' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME >= 350000;
    print_test('PSE1 (< 350K) mais TOTAL_INCOME >= 350K', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'PSE1' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME >= 350000
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=PSE1 Income=' || TO_CHAR(d.TOTAL_INCOME,'FM999G999G999')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.9 PSE2 (secteur privé 350K-1M) mais revenu hors fourchette
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE2' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0
      AND (r.TOTAL_INCOME < 350000 OR r.TOTAL_INCOME > 1000000);
    print_test('PSE2 (350K-1M) mais TOTAL_INCOME hors range', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'PSE2' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0
              AND (r.TOTAL_INCOME < 350000 OR r.TOTAL_INCOME > 1000000)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=PSE2 Income=' || TO_CHAR(d.TOTAL_INCOME,'FM999G999G999')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.10 PSE3 (secteur privé > 1M) mais revenu <= 1000000
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PSE3' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME <= 1000000;
    print_test('PSE3 (> 1M) mais TOTAL_INCOME <= 1M', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'PSE3' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME <= 1000000
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=PSE3 Income=' || TO_CHAR(d.TOTAL_INCOME,'FM999G999G999')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.11 PFBI (indépendants > 1M mensuel) mais revenu annuel <= 12M
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.CUSTOMER_CATEGORY = 'PFBI' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME <= 12000000;
    print_test('PFBI (rev mensuel>1M) mais annuel <= 12M', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, r.TOTAL_INCOME,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.CUSTOMER_CATEGORY = 'PFBI' AND r.TOTAL_INCOME IS NOT NULL AND r.TOTAL_INCOME > 0 AND r.TOTAL_INCOME <= 12000000
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=PFBI Income=' || TO_CHAR(d.TOTAL_INCOME,'FM999G999G999')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.12 Catégorie VPFP (pensionnés) mais âge < 50
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY = 'VPFP' AND p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 50;
    print_test('VPFP (pensionnés) mais âge < 50 ans', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   TRUNC(MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12) AS age_val,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY = 'VPFP' AND p.DATE_OF_BIRTH IS NOT NULL AND MONTHS_BETWEEN(SYSDATE, p.DATE_OF_BIRTH)/12 < 50
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=VPFP Âge=' || d.age_val
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.13 Catégorie individuelle mais CUSTOMER_TYPE != I
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE CUSTOMER_CATEGORY IN ('INDV','MINORS','STUDENTS','SENIORS','CSE1','CSE2','PSE1','PSE2','PSE3','PFBI','VPFP','SAL','STAF','RSA','RSA1','ABWP','PEP/FEPS','NRA1','NRA2')
      AND CUSTOMER_TYPE != 'I';
    print_test('Catégorie individuelle mais TYPE != I', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY, c.CUSTOMER_TYPE,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.CUSTOMER_CATEGORY IN ('INDV','MINORS','STUDENTS','SENIORS','CSE1','CSE2','PSE1','PSE2','PSE3','PFBI','VPFP','SAL','STAF','RSA','RSA1','ABWP','PEP/FEPS','NRA1','NRA2')
              AND c.CUSTOMER_TYPE != 'I'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=' || d.CUSTOMER_CATEGORY || ' Type=' || d.CUSTOMER_TYPE
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

    -- 3.14 Catégorie corporate mais CUSTOMER_TYPE != C
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE CUSTOMER_CATEGORY IN ('CORP','SME','NGOs','GOVT','GOVT INST','INSURANCE','CONSTRUCTN','HOSPITALIT','OIL&GAS','FIN_INT')
      AND CUSTOMER_TYPE != 'C';
    print_test('Catégorie corporate mais TYPE != C', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY, c.CUSTOMER_TYPE,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.CUSTOMER_CATEGORY IN ('CORP','SME','NGOs','GOVT','GOVT INST','INSURANCE','CONSTRUCTN','HOSPITALIT','OIL&GAS','FIN_INT')
              AND c.CUSTOMER_TYPE != 'C'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | Cat=' || d.CUSTOMER_CATEGORY || ' Type=' || d.CUSTOMER_TYPE
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,50));
        END LOOP;
    END IF;

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
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_DORMANT AS cust_val, b.AC_STAT_DORMANT AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_DORMANT IS NOT NULL AND b.AC_STAT_DORMANT IS NOT NULL
              AND a.AC_STAT_DORMANT != b.AC_STAT_DORMANT
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.2 Statut frozen discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_FROZEN IS NOT NULL AND b.AC_STAT_FROZEN IS NOT NULL
      AND a.AC_STAT_FROZEN != b.AC_STAT_FROZEN;
    print_test('Frozen discordant CUST_ACCOUNT vs STTB', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_FROZEN AS cust_val, b.AC_STAT_FROZEN AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_FROZEN IS NOT NULL AND b.AC_STAT_FROZEN IS NOT NULL
              AND a.AC_STAT_FROZEN != b.AC_STAT_FROZEN
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.3 Statut blocked discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_BLOCK IS NOT NULL AND b.GL_STAT_BLOCKED IS NOT NULL
      AND a.AC_STAT_BLOCK != b.GL_STAT_BLOCKED;
    print_test('Blocked discordant CUST_ACCOUNT vs STTB', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_BLOCK AS cust_val, b.GL_STAT_BLOCKED AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_BLOCK IS NOT NULL AND b.GL_STAT_BLOCKED IS NOT NULL
              AND a.AC_STAT_BLOCK != b.GL_STAT_BLOCKED
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.4 Statut no_dr discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_NO_DR IS NOT NULL AND b.AC_STAT_NO_DR IS NOT NULL
      AND a.AC_STAT_NO_DR != b.AC_STAT_NO_DR;
    print_test('No DR discordant CUST_ACCOUNT vs STTB', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_NO_DR AS cust_val, b.AC_STAT_NO_DR AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_NO_DR IS NOT NULL AND b.AC_STAT_NO_DR IS NOT NULL
              AND a.AC_STAT_NO_DR != b.AC_STAT_NO_DR
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.5 Statut no_cr discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_NO_CR IS NOT NULL AND b.AC_STAT_NO_CR IS NOT NULL
      AND a.AC_STAT_NO_CR != b.AC_STAT_NO_CR;
    print_test('No CR discordant CUST_ACCOUNT vs STTB', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_NO_CR AS cust_val, b.AC_STAT_NO_CR AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_NO_CR IS NOT NULL AND b.AC_STAT_NO_CR IS NOT NULL
              AND a.AC_STAT_NO_CR != b.AC_STAT_NO_CR
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.6 Statut stop_pay discordant
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.AC_STAT_STOP_PAY IS NOT NULL AND b.AC_STAT_STOP_PAY IS NOT NULL
      AND a.AC_STAT_STOP_PAY != b.AC_STAT_STOP_PAY;
    print_test('Stop Pay discordant CUST_ACCOUNT vs STTB', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.AC_STAT_STOP_PAY AS cust_val, b.AC_STAT_STOP_PAY AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.AC_STAT_STOP_PAY IS NOT NULL AND b.AC_STAT_STOP_PAY IS NOT NULL
              AND a.AC_STAT_STOP_PAY != b.AC_STAT_STOP_PAY
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CUST=' || d.cust_val || ' STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 4.7 Devise discordante
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.CCY IS NOT NULL AND TRIM(a.CCY) IS NOT NULL
      AND b.AC_GL_CCY IS NOT NULL AND TRIM(b.AC_GL_CCY) IS NOT NULL
      AND TRIM(a.CCY) != TRIM(b.AC_GL_CCY);
    print_test('Devise CCY vs AC_GL_CCY discordante', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, TRIM(a.CCY) AS cust_ccy, TRIM(b.AC_GL_CCY) AS sttb_ccy,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.CCY IS NOT NULL AND TRIM(a.CCY) IS NOT NULL
              AND b.AC_GL_CCY IS NOT NULL AND TRIM(b.AC_GL_CCY) IS NOT NULL
              AND TRIM(a.CCY) != TRIM(b.AC_GL_CCY)
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | CCY_CUST=' || d.cust_ccy || ' CCY_STTB=' || d.sttb_ccy
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

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
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO||'('||NVL(a.AC_STAT_FROZEN,'N')||')',', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.FROZEN = 'Y'
              AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO = c.CUSTOMER_NO AND a.AC_STAT_FROZEN != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,30)
                || ' | FROZEN=Y'
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,60));
        END LOOP;
    END IF;

    -- 4.9 RECORD_STAT discordant entre les deux tables
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
    WHERE a.RECORD_STAT IS NOT NULL AND b.AC_GL_REC_STATUS IS NOT NULL
      AND a.RECORD_STAT != b.AC_GL_REC_STATUS;
    print_test('RECORD_STAT vs AC_GL_REC_STATUS discordant', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, a.RECORD_STAT AS cust_val, b.AC_GL_REC_STATUS AS sttb_val,
                   a.ACY_CURR_BALANCE AS solde,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO=a.CUST_NO),'-') AS nom
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT b ON b.AC_GL_NO = a.CUST_AC_NO AND b.BRANCH_CODE = a.BRANCH_CODE
            WHERE a.RECORD_STAT IS NOT NULL AND b.AC_GL_REC_STATUS IS NOT NULL
              AND a.RECORD_STAT != b.AC_GL_REC_STATUS
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.nom,1,25)
                || ' | REC_CUST=' || d.cust_val || ' REC_STTB=' || d.sttb_val
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

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
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, TRIM(c.COUNTRY) AS country_cust, TRIM(p.D_COUNTRY) AS d_country_pers,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.COUNTRY IS NOT NULL AND TRIM(c.COUNTRY) IS NOT NULL
              AND p.D_COUNTRY IS NOT NULL AND TRIM(p.D_COUNTRY) IS NOT NULL
              AND TRIM(c.COUNTRY) != TRIM(p.D_COUNTRY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | COUNTRY=' || d.country_cust || ' D_COUNTRY=' || d.d_country_pers
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.2 COUNTRY (STTM_CUSTOMER) vs LOCAL_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE c.COUNTRY IS NOT NULL AND TRIM(c.COUNTRY) IS NOT NULL
      AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(c.COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY);
    print_test('COUNTRY(CUSTOMER) vs LOCAL_ADDR(KYC_RETAIL)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, TRIM(c.COUNTRY) AS country_cust, TRIM(r.LOCAL_ADDR_COUNTRY) AS local_addr,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE c.COUNTRY IS NOT NULL AND TRIM(c.COUNTRY) IS NOT NULL
              AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
              AND TRIM(c.COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | COUNTRY=' || d.country_cust || ' LOCAL_ADDR=' || d.local_addr
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.3 D_COUNTRY (PERSONAL) vs LOCAL_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.D_COUNTRY IS NOT NULL AND TRIM(p.D_COUNTRY) IS NOT NULL
      AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(p.D_COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY);
    print_test('D_COUNTRY(PERSONAL) vs LOCAL_ADDR(KYC)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, TRIM(p.D_COUNTRY) AS d_country, TRIM(r.LOCAL_ADDR_COUNTRY) AS local_addr,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.D_COUNTRY IS NOT NULL AND TRIM(p.D_COUNTRY) IS NOT NULL
              AND r.LOCAL_ADDR_COUNTRY IS NOT NULL AND TRIM(r.LOCAL_ADDR_COUNTRY) IS NOT NULL
              AND TRIM(p.D_COUNTRY) != TRIM(r.LOCAL_ADDR_COUNTRY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | D_COUNTRY=' || d.d_country || ' LOCAL_ADDR=' || d.local_addr
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.4 P_COUNTRY (PERSONAL) vs HOME_ADDR_COUNTRY (KYC_RETAIL)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
    WHERE p.P_COUNTRY IS NOT NULL AND TRIM(p.P_COUNTRY) IS NOT NULL
      AND r.HOME_ADDR_COUNTRY IS NOT NULL AND TRIM(r.HOME_ADDR_COUNTRY) IS NOT NULL
      AND TRIM(p.P_COUNTRY) != TRIM(r.HOME_ADDR_COUNTRY);
    print_test('P_COUNTRY(PERSONAL) vs HOME_ADDR(KYC)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, TRIM(p.P_COUNTRY) AS p_country, TRIM(r.HOME_ADDR_COUNTRY) AS home_addr,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = c.KYC_REF_NO
            WHERE p.P_COUNTRY IS NOT NULL AND TRIM(p.P_COUNTRY) IS NOT NULL
              AND r.HOME_ADDR_COUNTRY IS NOT NULL AND TRIM(r.HOME_ADDR_COUNTRY) IS NOT NULL
              AND TRIM(p.P_COUNTRY) != TRIM(r.HOME_ADDR_COUNTRY)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | P_COUNTRY=' || d.p_country || ' HOME_ADDR=' || d.home_addr
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.5 Non-résident mais pays = CMR
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE p.RESIDENT_STATUS = 'N'
      AND c.COUNTRY = 'CMR';
    print_test('Non-résident mais COUNTRY = CMR', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY, c.NATIONALITY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE p.RESIDENT_STATUS = 'N' AND c.COUNTRY = 'CMR'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | NonRés COUNTRY=CMR Cat=' || d.CUSTOMER_CATEGORY || ' Nat=' || NVL(d.NATIONALITY,'-')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.6 Catégorie NRA (non-résident) mais résident dans PERSONAL
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
    WHERE c.CUSTOMER_CATEGORY IN ('NRA1', 'NRA2')
      AND p.RESIDENT_STATUS = 'R';
    print_test('Catégorie NRA mais RESIDENT_STATUS = R', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY, c.COUNTRY, c.NATIONALITY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            JOIN STTM_CUST_PERSONAL p ON p.CUSTOMER_NO = c.CUSTOMER_NO
            WHERE c.CUSTOMER_CATEGORY IN ('NRA1', 'NRA2') AND p.RESIDENT_STATUS = 'R'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | Cat=' || d.CUSTOMER_CATEGORY || ' RES=R Pays=' || NVL(d.COUNTRY,'-') || ' Nat=' || NVL(d.NATIONALITY,'-')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 5.7 Catégorie FOREIGN mais NATIONALITY = CMR
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_CATEGORY = 'FOREIGN'
      AND c.NATIONALITY = 'CMR';
    print_test('Catégorie FOREIGN mais nationalité = CMR', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.COUNTRY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.CUSTOMER_CATEGORY = 'FOREIGN' AND c.NATIONALITY = 'CMR'
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | FOREIGN Nat=CMR Pays=' || NVL(d.COUNTRY,'-')
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- =========================================================
    -- 6. COHERENCE UDF (CSTM_FUNCTION_USERDEF_FIELDS) vs TABLES
    -- =========================================================
    print_section('6. COHERENCE UDF vs TABLES PRINCIPALES');

    -- 6.1 STDCIF : compliance_watchlist=Y mais client non FROZEN
    SELECT COUNT(*) INTO v_count
    FROM cstm_function_userdef_fields u
    JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = SUBSTR(u.rec_key, 1, INSTR(u.rec_key, '~', 1, 1) - 1)
    WHERE u.function_id = 'STDCIF'
      AND UPPER(TRIM(u.field_val_18)) = 'Y'
      AND (c.FROZEN IS NULL OR c.FROZEN != 'Y');
    print_test('UDF compliance_watchlist=Y mais non FROZEN', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, NVL(c.FROZEN,'N') AS frozen_val,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM cstm_function_userdef_fields u
            JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = SUBSTR(u.rec_key, 1, INSTR(u.rec_key, '~', 1, 1) - 1)
            WHERE u.function_id = 'STDCIF'
              AND UPPER(TRIM(u.field_val_18)) = 'Y'
              AND (c.FROZEN IS NULL OR c.FROZEN != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | Watchlist=Y FROZEN=' || d.frozen_val
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 6.2 STDKYCMN : pep_status vs PEP dans KYC_RETAIL
    SELECT COUNT(*) INTO v_count
    FROM cstm_function_userdef_fields u
    JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = SUBSTR(u.rec_key, 1, LENGTH(u.rec_key) - 1)
    WHERE u.function_id = 'STDKYCMN'
      AND u.field_val_1 IS NOT NULL AND UPPER(TRIM(u.field_val_1)) = 'Y'
      AND (r.PEP IS NULL OR r.PEP != 'Y');
    print_test('UDF PEP_STATUS=Y mais KYC PEP != Y', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT r.KYC_REF_NO,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS nom,
                   NVL(r.PEP,'NULL') AS pep_kyc,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) AS total_solde
            FROM cstm_function_userdef_fields u
            JOIN STTM_KYC_RETAIL r ON r.KYC_REF_NO = SUBSTR(u.rec_key, 1, LENGTH(u.rec_key) - 1)
            WHERE u.function_id = 'STDKYCMN'
              AND u.field_val_1 IS NOT NULL AND UPPER(TRIM(u.field_val_1)) = 'Y'
              AND (r.PEP IS NULL OR r.PEP != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | UDF_PEP=Y KYC_PEP=' || d.pep_kyc || ' KYC=' || d.KYC_REF_NO
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 6.3 STDKYCMN : PEP=Y dans KYC mais pep_status UDF != Y
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_RETAIL r
    JOIN cstm_function_userdef_fields u
      ON SUBSTR(u.rec_key, 1, LENGTH(u.rec_key) - 1) = r.KYC_REF_NO
      AND u.function_id = 'STDKYCMN'
    WHERE r.PEP = 'Y'
      AND (u.field_val_1 IS NULL OR UPPER(TRIM(u.field_val_1)) != 'Y');
    print_test('KYC PEP=Y mais UDF pep_status != Y', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT r.KYC_REF_NO, NVL(UPPER(TRIM(u.field_val_1)),'NULL') AS udf_pep,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS nom,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) AS total_solde
            FROM STTM_KYC_RETAIL r
            JOIN cstm_function_userdef_fields u
              ON SUBSTR(u.rec_key, 1, LENGTH(u.rec_key) - 1) = r.KYC_REF_NO
              AND u.function_id = 'STDKYCMN'
            WHERE r.PEP = 'Y'
              AND (u.field_val_1 IS NULL OR UPPER(TRIM(u.field_val_1)) != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | KYC_PEP=Y UDF_PEP=' || d.udf_pep || ' KYC=' || d.KYC_REF_NO
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 6.4 SMDUSRDF : email vide pour des utilisateurs actifs
    SELECT COUNT(*) INTO v_count
    FROM cstm_function_userdef_fields u
    WHERE u.function_id = 'SMDUSRDF'
      AND (u.field_val_1 IS NULL OR TRIM(u.field_val_1) IS NULL);
    SELECT COUNT(*) INTO v_total
    FROM cstm_function_userdef_fields
    WHERE function_id = 'SMDUSRDF';
    print_test('SMDUSRDF : utilisateurs sans email UDF', v_count, v_total);

    -- 6.5 STDCUSAC : account_no UDF vs STTM_CUST_ACCOUNT — comptes orphelins
    SELECT COUNT(*) INTO v_count
    FROM cstm_function_userdef_fields u
    WHERE u.function_id = 'STDCUSAC'
      AND NOT EXISTS (
          SELECT 1 FROM STTM_CUST_ACCOUNT a
          WHERE a.CUST_AC_NO = SUBSTR(u.rec_key, INSTR(u.rec_key, '~', 1, 1) + 1,
                INSTR(u.rec_key, '~', 1, 2) - INSTR(u.rec_key, '~', 1, 1) - 1)
      );
    print_test('STDCUSAC : UDF sans compte CUST_ACCOUNT', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (premiers rec_key) :');
        FOR d IN (SELECT * FROM (
            SELECT u.rec_key,
                   SUBSTR(u.rec_key, 1, INSTR(u.rec_key, '~', 1, 1) - 1) AS branch,
                   SUBSTR(u.rec_key, INSTR(u.rec_key, '~', 1, 1) + 1,
                          INSTR(u.rec_key, '~', 1, 2) - INSTR(u.rec_key, '~', 1, 1) - 1) AS ac_no
            FROM cstm_function_userdef_fields u
            WHERE u.function_id = 'STDCUSAC'
              AND NOT EXISTS (
                  SELECT 1 FROM STTM_CUST_ACCOUNT a
                  WHERE a.CUST_AC_NO = SUBSTR(u.rec_key, INSTR(u.rec_key, '~', 1, 1) + 1,
                        INSTR(u.rec_key, '~', 1, 2) - INSTR(u.rec_key, '~', 1, 1) - 1)
              )
            ORDER BY u.rec_key
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    REC_KEY=' || SUBSTR(d.rec_key,1,50) || ' | AC_NO=' || d.ac_no);
        END LOOP;
    END IF;

    -- 6.6 STDCIF : nombre d'enregistrements UDF vs nombre de clients
    SELECT COUNT(*) INTO v_count
    FROM cstm_function_userdef_fields WHERE function_id = 'STDCIF';
    SELECT COUNT(*) INTO v_total FROM STTM_CUSTOMER;
    DBMS_OUTPUT.PUT_LINE('  [INFO] Nb UDF STDCIF: ' || v_count || ' vs Nb clients: ' || v_total);
    IF v_count != v_total THEN
        v_test_no := v_test_no + 1;
        DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
            || RPAD('Écart volumétrie STDCIF vs STTM_CUSTOMER', 55, '.')
            || ' ' || ABS(v_count - v_total) || '  *** ÉCART ***');
        v_anomalies := v_anomalies + 1;
    ELSE
        v_test_no := v_test_no + 1;
        DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
            || RPAD('Volumétrie STDCIF = STTM_CUSTOMER', 55, '.')
            || ' 0  OK');
    END IF;

    -- =========================================================
    -- 7. COHERENCE KYC / RISQUE / INTEGRITE REFERENTIELLE
    -- =========================================================
    print_section('7. COHERENCE KYC / RISQUE / INTEGRITE REFERENTIELLE');

    -- 7.1 KYC_REF_NO dans STTM_CUSTOMER mais absent de KYC_MASTER
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.KYC_REF_NO IS NOT NULL AND TRIM(c.KYC_REF_NO) IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM STTM_KYC_MASTER m WHERE m.KYC_REF_NO = c.KYC_REF_NO
      );
    print_test('KYC_REF_NO orphelins (absent de MASTER)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.KYC_REF_NO, c.CUSTOMER_CATEGORY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.KYC_REF_NO IS NOT NULL AND TRIM(c.KYC_REF_NO) IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM STTM_KYC_MASTER m WHERE m.KYC_REF_NO = c.KYC_REF_NO)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | KYC=' || d.KYC_REF_NO || ' Cat=' || d.CUSTOMER_CATEGORY
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 7.2 KYC_MASTER non référencé par aucun client
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_MASTER m
    WHERE NOT EXISTS (
        SELECT 1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO = m.KYC_REF_NO
    );
    print_test('KYC_MASTER sans client associé', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (premiers KYC_REF_NO) :');
        FOR d IN (SELECT * FROM (
            SELECT m.KYC_REF_NO, m.KYC_TYPE, NVL(m.MAKER_ID,'-') AS maker, NVL(TO_CHAR(m.MAKER_DT_STAMP,'DD/MM/YYYY'),'-') AS dt
            FROM STTM_KYC_MASTER m
            WHERE NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO = m.KYC_REF_NO)
            ORDER BY m.KYC_REF_NO
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    KYC=' || d.KYC_REF_NO || ' | Type=' || NVL(d.KYC_TYPE,'-')
                || ' | Maker=' || d.maker || ' | Date=' || d.dt);
        END LOOP;
    END IF;

    -- 7.3 AML_REQUIRED=Y mais sans KYC
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.AML_REQUIRED = 'Y'
      AND (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL);
    print_test('AML_REQUIRED=Y mais sans KYC_REF_NO', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.AML_REQUIRED = 'Y' AND (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | AML=Y KYC=NULL Cat=' || d.CUSTOMER_CATEGORY
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 7.4 KYC_DETAILS=V (vérifié) mais KYC_REF_NO absent
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.KYC_DETAILS = 'V'
      AND (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL);
    print_test('KYC_DETAILS=V mais sans KYC_REF_NO', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1, c.CUSTOMER_CATEGORY,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO,', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.KYC_DETAILS = 'V' AND (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | KYC_DET=V KYC=NULL Cat=' || d.CUSTOMER_CATEGORY
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,40));
        END LOOP;
    END IF;

    -- 7.5 KYC Review dépassée (Retail)
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_RETAIL r
    WHERE r.KYC_NXT_REVIEW_DATE IS NOT NULL
      AND r.KYC_NXT_REVIEW_DATE < SYSDATE;
    print_test('KYC Retail : review date dépassée', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT r.KYC_REF_NO, TO_CHAR(r.KYC_NXT_REVIEW_DATE,'DD/MM/YYYY') AS review_dt,
                   TRUNC(SYSDATE - r.KYC_NXT_REVIEW_DATE) AS jours_retard,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS nom,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) AS total_solde
            FROM STTM_KYC_RETAIL r
            WHERE r.KYC_NXT_REVIEW_DATE IS NOT NULL AND r.KYC_NXT_REVIEW_DATE < SYSDATE
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | Review=' || d.review_dt || ' Retard=' || d.jours_retard || 'j'
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 7.6 KYC Review dépassée (Corporate)
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_CORPORATE k
    WHERE k.KYC_NXT_REVIEW_DATE IS NOT NULL
      AND k.KYC_NXT_REVIEW_DATE < SYSDATE;
    print_test('KYC Corporate : review date dépassée', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT k.KYC_REF_NO, TO_CHAR(k.KYC_NXT_REVIEW_DATE,'DD/MM/YYYY') AS review_dt,
                   TRUNC(SYSDATE - k.KYC_NXT_REVIEW_DATE) AS jours_retard,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=k.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=k.KYC_REF_NO AND ROWNUM=1),'-') AS nom,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=k.KYC_REF_NO AND ROWNUM=1)),0) AS total_solde
            FROM STTM_KYC_CORPORATE k
            WHERE k.KYC_NXT_REVIEW_DATE IS NOT NULL AND k.KYC_NXT_REVIEW_DATE < SYSDATE
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=k.KYC_REF_NO AND ROWNUM=1)),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | Review=' || d.review_dt || ' Retard=' || d.jours_retard || 'j'
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 7.7 PEP=Y mais pas de PEP_REMARKS
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_RETAIL r
    WHERE r.PEP = 'Y'
      AND (r.PEP_REMARKS IS NULL OR TRIM(r.PEP_REMARKS) IS NULL);
    print_test('PEP=Y mais PEP_REMARKS vide', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT r.KYC_REF_NO,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1),'-') AS nom,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) AS total_solde
            FROM STTM_KYC_RETAIL r
            WHERE r.PEP = 'Y' AND (r.PEP_REMARKS IS NULL OR TRIM(r.PEP_REMARKS) IS NULL)
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=(SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=r.KYC_REF_NO AND ROWNUM=1)),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | PEP=Y REMARKS=NULL KYC=' || d.KYC_REF_NO
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 7.8 Clients avec compte mais sans entrée STTM_CUSTOMER
    SELECT COUNT(DISTINCT a.CUST_NO) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE NOT EXISTS (
        SELECT 1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO = a.CUST_NO
    );
    print_test('Comptes avec CUST_NO absent de CUSTOMER', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, a.CUST_AC_NO, a.ACY_CURR_BALANCE AS solde, a.CCY, a.AC_DESC
            FROM STTM_CUST_ACCOUNT a
            WHERE NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER c WHERE c.CUSTOMER_NO = a.CUST_NO)
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    CUST_NO=' || d.CUST_NO || ' | Cpte=' || d.CUST_AC_NO
                || ' | ' || NVL(SUBSTR(d.AC_DESC,1,20),'-')
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00') || ' ' || NVL(d.CCY,'-'));
        END LOOP;
    END IF;

    -- 7.9 Doublons : même P_NATIONAL_ID pour des clients différents
    SELECT COUNT(*) INTO v_count FROM (
        SELECT P_NATIONAL_ID FROM STTM_CUST_PERSONAL
        WHERE P_NATIONAL_ID IS NOT NULL AND TRIM(P_NATIONAL_ID) IS NOT NULL
        GROUP BY P_NATIONAL_ID HAVING COUNT(*) > 1
    );
    print_test('P_NATIONAL_ID en doublon (nb IDs)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 doublons (par nb occurrences) :');
        FOR d IN (SELECT * FROM (
            SELECT p.P_NATIONAL_ID, COUNT(*) AS nb,
                   LISTAGG(p.CUSTOMER_NO, ', ') WITHIN GROUP(ORDER BY p.CUSTOMER_NO) AS clients
            FROM STTM_CUST_PERSONAL p
            WHERE p.P_NATIONAL_ID IS NOT NULL AND TRIM(p.P_NATIONAL_ID) IS NOT NULL
            GROUP BY p.P_NATIONAL_ID HAVING COUNT(*) > 1
            ORDER BY COUNT(*) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ID=' || d.P_NATIONAL_ID || ' | x' || d.nb
                || ' | Clients=' || SUBSTR(d.clients,1,60));
        END LOOP;
    END IF;

    -- 7.10 Doublons : même UNIQUE_ID_VALUE pour des clients différents
    SELECT COUNT(*) INTO v_count FROM (
        SELECT UNIQUE_ID_VALUE FROM STTM_CUSTOMER
        WHERE UNIQUE_ID_VALUE IS NOT NULL AND TRIM(UNIQUE_ID_VALUE) IS NOT NULL
        GROUP BY UNIQUE_ID_VALUE HAVING COUNT(*) > 1
    );
    print_test('UNIQUE_ID_VALUE en doublon (nb IDs)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 doublons (par nb occurrences) :');
        FOR d IN (SELECT * FROM (
            SELECT c.UNIQUE_ID_VALUE, COUNT(*) AS nb,
                   LISTAGG(c.CUSTOMER_NO, ', ') WITHIN GROUP(ORDER BY c.CUSTOMER_NO) AS clients
            FROM STTM_CUSTOMER c
            WHERE c.UNIQUE_ID_VALUE IS NOT NULL AND TRIM(c.UNIQUE_ID_VALUE) IS NOT NULL
            GROUP BY c.UNIQUE_ID_VALUE HAVING COUNT(*) > 1
            ORDER BY COUNT(*) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    UID=' || SUBSTR(d.UNIQUE_ID_VALUE,1,25) || ' | x' || d.nb
                || ' | Clients=' || SUBSTR(d.clients,1,60));
        END LOOP;
    END IF;

    -- 7.11 Client DECEASED=Y avec des comptes non bloqués
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.DECEASED = 'Y'
      AND EXISTS (
          SELECT 1 FROM STTM_CUST_ACCOUNT a
          WHERE a.CUST_NO = c.CUSTOMER_NO
            AND a.AC_STAT_BLOCK != 'Y'
            AND a.AC_STAT_FROZEN != 'Y'
      );
    print_test('Client DECEASED avec comptes non bloqués', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT c.CUSTOMER_NO, c.CUSTOMER_NAME1,
                   NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) AS total_solde,
                   NVL((SELECT LISTAGG(a.CUST_AC_NO||'(B='||NVL(a.AC_STAT_BLOCK,'N')||' F='||NVL(a.AC_STAT_FROZEN,'N')||')',', ') WITHIN GROUP(ORDER BY a.CUST_AC_NO) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),'AUCUN') AS comptes
            FROM STTM_CUSTOMER c
            WHERE c.DECEASED = 'Y'
              AND EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO = c.CUSTOMER_NO AND a.AC_STAT_BLOCK != 'Y' AND a.AC_STAT_FROZEN != 'Y')
            ORDER BY NVL((SELECT SUM(a.ACY_CURR_BALANCE) FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO=c.CUSTOMER_NO),0) DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUSTOMER_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | DECEASED=Y'
                || ' | Solde=' || TO_CHAR(d.total_solde,'FM999G999G999G999D00') || ' | Cptes=' || SUBSTR(d.comptes,1,60));
        END LOOP;
    END IF;

    -- 7.12 Comptes avec transactions mais client sans KYC
    SELECT COUNT(DISTINCT h.AC_NO) INTO v_count
    FROM ACTB_HISTORY h
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
    JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
    WHERE (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL);
    print_test('Comptes actifs (txn) sans KYC client', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par solde) :');
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_AC_NO, a.CUST_NO, c.CUSTOMER_NAME1, a.ACY_CURR_BALANCE AS solde,
                   (SELECT COUNT(*) FROM ACTB_HISTORY h WHERE h.AC_NO = a.CUST_AC_NO) AS nb_txn
            FROM STTM_CUST_ACCOUNT a
            JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE (c.KYC_REF_NO IS NULL OR TRIM(c.KYC_REF_NO) IS NULL)
              AND EXISTS (SELECT 1 FROM ACTB_HISTORY h WHERE h.AC_NO = a.CUST_AC_NO)
            ORDER BY a.ACY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.CUST_AC_NO || ' | ' || d.CUST_NO || ' | ' || SUBSTR(d.CUSTOMER_NAME1,1,25)
                || ' | KYC=NULL Txns=' || d.nb_txn
                || ' | Solde=' || TO_CHAR(d.solde,'FM999G999G999G999D00'));
        END LOOP;
    END IF;

    -- 7.13 Maker = Checker sur les dossiers KYC (ségrégation)
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_MASTER
    WHERE MAKER_ID IS NOT NULL AND CHECKER_ID IS NOT NULL
      AND MAKER_ID = CHECKER_ID
      AND MAKER_ID != 'MIGRATION';
    print_test('KYC Maker=Checker (hors MIGRATION)', v_count);
    IF v_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('    TOP 30 (par date) :');
        FOR d IN (SELECT * FROM (
            SELECT m.KYC_REF_NO, m.MAKER_ID, NVL(TO_CHAR(m.MAKER_DT_STAMP,'DD/MM/YYYY'),'-') AS dt,
                   NVL((SELECT c.CUSTOMER_NO FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=m.KYC_REF_NO AND ROWNUM=1),'-') AS cust_no,
                   NVL((SELECT c.CUSTOMER_NAME1 FROM STTM_CUSTOMER c WHERE c.KYC_REF_NO=m.KYC_REF_NO AND ROWNUM=1),'-') AS nom
            FROM STTM_KYC_MASTER m
            WHERE m.MAKER_ID IS NOT NULL AND m.CHECKER_ID IS NOT NULL
              AND m.MAKER_ID = m.CHECKER_ID AND m.MAKER_ID != 'MIGRATION'
            ORDER BY m.MAKER_DT_STAMP DESC NULLS LAST
        ) WHERE ROWNUM <= 30) LOOP
            DBMS_OUTPUT.PUT_LINE('    ' || d.cust_no || ' | ' || SUBSTR(d.nom,1,25)
                || ' | KYC=' || d.KYC_REF_NO || ' Maker=Checker=' || d.MAKER_ID || ' Date=' || d.dt);
        END LOOP;
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
