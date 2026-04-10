-- ============================================================
-- SCRIPT D'EXPLORATION AML/KYC  (version corrigée ROWNUM)
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_sep           VARCHAR2(80) := RPAD('=', 80, '=');

    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE print_kv(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_label, 40, '.') || ' ' || NVL(p_value, 'NULL / NON RENSEIGNE'));
    END;

BEGIN

    -- =========================================================
    -- 1. VOLUMETRIE GENERALE
    -- =========================================================
    print_section('1. VOLUMETRIE GENERALE DES TABLES');

    FOR t IN (
        SELECT table_name FROM (
            SELECT 'STTM_CUSTOMER'      AS table_name, 1 AS ord FROM DUAL UNION ALL
            SELECT 'STTM_CUST_PERSONAL', 2 FROM DUAL UNION ALL
            SELECT 'STTM_CUST_ACCOUNT',  3 FROM DUAL UNION ALL
            SELECT 'STTB_ACCOUNT',       4 FROM DUAL UNION ALL
            SELECT 'STTM_KYC_MASTER',    5 FROM DUAL UNION ALL
            SELECT 'STTM_KYC_RETAIL',    6 FROM DUAL UNION ALL
            SELECT 'STTM_KYC_CORPORATE', 7 FROM DUAL UNION ALL
            SELECT 'ACTB_HISTORY',        8 FROM DUAL UNION ALL
            SELECT 'STTM_ACCOUNT_CLASS',  9 FROM DUAL UNION ALL
            SELECT 'STTM_CUSTOMER_CAT',  10 FROM DUAL UNION ALL
            SELECT 'STTM_KYC_CORP_KEYPERSONS', 11 FROM DUAL UNION ALL
            SELECT 'CSTM_FUNCTION_USERDEF_FIELDS', 12 FROM DUAL
        ) ORDER BY ord
    ) LOOP
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.table_name INTO v_count;
        print_kv(t.table_name, TO_CHAR(v_count) || ' lignes');
    END LOOP;


    -- =========================================================
    -- 2. STTM_CUSTOMER
    -- =========================================================
    print_section('2. STTM_CUSTOMER — Fiche client principale');

    DBMS_OUTPUT.PUT_LINE('  [Répartition par CUSTOMER_TYPE]');
    FOR r IN (SELECT CUSTOMER_TYPE, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY CUSTOMER_TYPE ORDER BY nb DESC) LOOP
        print_kv('  Type : ' || r.CUSTOMER_TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition par CUSTOMER_CATEGORY]');
    FOR r IN (SELECT CUSTOMER_CATEGORY, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY CUSTOMER_CATEGORY ORDER BY nb DESC) LOOP
        print_kv('  Catégorie : ' || r.CUSTOMER_CATEGORY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statut AML (AML_REQUIRED)]');
    FOR r IN (SELECT AML_REQUIRED, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY AML_REQUIRED ORDER BY nb DESC) LOOP
        print_kv('  AML_REQUIRED = ' || r.AML_REQUIRED, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statut KYC (KYC_DETAILS)]');
    FOR r IN (SELECT KYC_DETAILS, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY KYC_DETAILS ORDER BY nb DESC) LOOP
        print_kv('  KYC_DETAILS = ' || r.KYC_DETAILS, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [KYC_REF_NO renseigné ?]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE KYC_REF_NO IS NOT NULL AND KYC_REF_NO != ' ';
    print_kv('  Avec KYC_REF_NO', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE KYC_REF_NO IS NULL OR KYC_REF_NO = ' ';
    print_kv('  Sans KYC_REF_NO', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Indicateurs sensibles]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE FROZEN = 'Y';
    print_kv('  Clients GELÉS (FROZEN=Y)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE DECEASED = 'Y';
    print_kv('  Clients DÉCÉDÉS (DECEASED=Y)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE WHEREABOUTS_UNKNOWN = 'Y';
    print_kv('  Clients INTROUVABLES', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition RISK_PROFILE]');
    FOR r IN (SELECT RISK_PROFILE, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY RISK_PROFILE ORDER BY nb DESC) LOOP
        print_kv('  RISK_PROFILE = ' || r.RISK_PROFILE, TO_CHAR(r.nb));
    END LOOP;

    -- *** CORRECTION : ROWNUM au lieu de FETCH FIRST ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays (COUNTRY)]');
    FOR r IN (
        SELECT COUNTRY, nb FROM (
            SELECT COUNTRY, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Pays : ' || r.COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Nationalité ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 nationalités (NATIONALITY)]');
    FOR r IN (
        SELECT NATIONALITY, nb FROM (
            SELECT NATIONALITY, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY NATIONALITY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Nationalité : ' || r.NATIONALITY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Pays d'exposition ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays exposition (EXPOSURE_COUNTRY)]');
    FOR r IN (
        SELECT EXPOSURE_COUNTRY, nb FROM (
            SELECT EXPOSURE_COUNTRY, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY EXPOSURE_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  EXPOSURE_COUNTRY : ' || r.EXPOSURE_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Classification client ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition CUST_CLASSIFICATION]');
    FOR r IN (SELECT CUST_CLASSIFICATION, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY CUST_CLASSIFICATION ORDER BY nb DESC) LOOP
        print_kv('  Classification : ' || r.CUST_CLASSIFICATION, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Statut CIF ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition CIF_STATUS]');
    FOR r IN (SELECT CIF_STATUS, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY CIF_STATUS ORDER BY nb DESC) LOOP
        print_kv('  CIF_STATUS : ' || r.CIF_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Statut enregistrement ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [AUTH_STAT / RECORD_STAT des fiches client]');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.RECORD_STAT, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Indicateurs supplémentaires ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Indicateurs complémentaires]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE STAFF = 'Y';
    print_kv('  Clients STAFF (employés banque)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE PRIVATE_CUSTOMER = 'Y';
    print_kv('  Clients PRIVÉS (banque privée)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE JOINT_VENTURE = 'Y';
    print_kv('  JOINT_VENTURE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE CRM_CUSTOMER = 'Y';
    print_kv('  CRM_CUSTOMER = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE TREASURY_CUSTOMER = 'Y';
    print_kv('  TREASURY_CUSTOMER = Y', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Complétude identifiants ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Complétude des identifiants uniques]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE UNIQUE_ID_VALUE IS NULL OR UNIQUE_ID_VALUE = ' ';
    print_kv('  Sans UNIQUE_ID_VALUE', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE UNIQUE_ID_VALUE IS NOT NULL AND UNIQUE_ID_VALUE != ' ';
    print_kv('  Avec UNIQUE_ID_VALUE', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition UNIQUE_ID_NAME]');
    FOR r IN (
        SELECT UNIQUE_ID_NAME, nb FROM (
            SELECT UNIQUE_ID_NAME, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY UNIQUE_ID_NAME ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ID Type : ' || r.UNIQUE_ID_NAME, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Introducteurs ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE INTRODUCER IS NOT NULL AND INTRODUCER != ' ';
    print_kv('  Clients avec INTRODUCTEUR', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE INTRODUCER IS NULL OR INTRODUCER = ' ';
    print_kv('  Clients sans INTRODUCTEUR', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Notation de crédit ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition CREDIT_RATING]');
    FOR r IN (SELECT CREDIT_RATING, COUNT(*) nb FROM STTM_CUSTOMER GROUP BY CREDIT_RATING ORDER BY nb DESC) LOOP
        print_kv('  CREDIT_RATING = ' || r.CREDIT_RATING, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Plage de création des CIF]');
    FOR r IN (SELECT MIN(CIF_CREATION_DATE) dt_min, MAX(CIF_CREATION_DATE) dt_max FROM STTM_CUSTOMER) LOOP
        print_kv('  CIF le plus ancien', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  CIF le plus récent', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;

    -- *** ENRICHISSEMENT : Répartition des créations par année ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Créations CIF par année]');
    FOR r IN (
        SELECT TO_CHAR(CIF_CREATION_DATE, 'YYYY') annee, COUNT(*) nb
        FROM STTM_CUSTOMER
        WHERE CIF_CREATION_DATE IS NOT NULL
        GROUP BY TO_CHAR(CIF_CREATION_DATE, 'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  Année ' || r.annee, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 3. STTM_CUST_PERSONAL
    -- =========================================================
    print_section('3. STTM_CUST_PERSONAL — Données personnelles');

    DBMS_OUTPUT.PUT_LINE('  [Complétude des champs identitaires]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE P_NATIONAL_ID IS NULL OR P_NATIONAL_ID = ' ';
    print_kv('  Sans P_NATIONAL_ID', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PASSPORT_NO IS NULL OR PASSPORT_NO = ' ';
    print_kv('  Sans PASSPORT_NO', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE DATE_OF_BIRTH IS NULL;
    print_kv('  Sans DATE_OF_BIRTH', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE E_MAIL IS NULL OR E_MAIL = ' ';
    print_kv('  Sans E_MAIL', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE MOBILE_NUMBER IS NULL OR MOBILE_NUMBER = ' ';
    print_kv('  Sans MOBILE_NUMBER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE (P_ADDRESS1 IS NULL OR P_ADDRESS1 = ' ')
      AND (D_ADDRESS1 IS NULL OR D_ADDRESS1 = ' ');
    print_kv('  Sans aucune adresse (P ni D)', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PPT_EXP_DATE < SYSDATE AND PPT_EXP_DATE IS NOT NULL;
    print_kv('  Passeports EXPIRÉS', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition par SEX]');
    FOR r IN (SELECT SEX, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY SEX ORDER BY nb DESC) LOOP
        print_kv('  SEX = ' || r.SEX, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE MINOR = 'Y';
    print_kv('  Clients MINEURS (MINOR=Y)', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [RESIDENT_STATUS]');
    FOR r IN (SELECT RESIDENT_STATUS, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY RESIDENT_STATUS ORDER BY nb DESC) LOOP
        print_kv('  Statut : ' || r.RESIDENT_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Pays de naissance ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 BIRTH_COUNTRY]');
    FOR r IN (
        SELECT BIRTH_COUNTRY, nb FROM (
            SELECT BIRTH_COUNTRY, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY BIRTH_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Pays naissance : ' || r.BIRTH_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Lieu de naissance ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PLACE_OF_BIRTH IS NULL OR PLACE_OF_BIRTH = ' ';
    print_kv('  Sans PLACE_OF_BIRTH', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PLACE_OF_BIRTH IS NOT NULL AND PLACE_OF_BIRTH != ' ';
    print_kv('  Avec PLACE_OF_BIRTH', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Pays domicile / permanent ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays domicile (D_COUNTRY)]');
    FOR r IN (
        SELECT D_COUNTRY, nb FROM (
            SELECT D_COUNTRY, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY D_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  D_COUNTRY : ' || r.D_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays permanent (P_COUNTRY)]');
    FOR r IN (
        SELECT P_COUNTRY, nb FROM (
            SELECT P_COUNTRY, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY P_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  P_COUNTRY : ' || r.P_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Procuration (Power of Attorney) ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Procuration (Power of Attorney)]');
    FOR r IN (SELECT PA_ISSUED, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY PA_ISSUED ORDER BY nb DESC) LOOP
        print_kv('  PA_ISSUED = ' || r.PA_ISSUED, TO_CHAR(r.nb));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE PA_HOLDER_NAME IS NOT NULL AND PA_HOLDER_NAME != ' ';
    print_kv('  Avec PA_HOLDER_NAME renseigné', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : FATCA (US_RES_STATUS) ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [US_RES_STATUS — Conformité FATCA]');
    FOR r IN (SELECT US_RES_STATUS, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY US_RES_STATUS ORDER BY nb DESC) LOOP
        print_kv('  US_RES_STATUS = ' || r.US_RES_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Preuve d'âge ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [AGE_PROOF_SUBMITTED]');
    FOR r IN (SELECT AGE_PROOF_SUBMITTED, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY AGE_PROOF_SUBMITTED ORDER BY nb DESC) LOOP
        print_kv('  AGE_PROOF = ' || r.AGE_PROOF_SUBMITTED, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Mode de communication ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Mode de communication préféré]');
    FOR r IN (SELECT CUST_COMM_MODE, COUNT(*) nb FROM STTM_CUST_PERSONAL GROUP BY CUST_COMM_MODE ORDER BY nb DESC) LOOP
        print_kv('  CUST_COMM_MODE = ' || r.CUST_COMM_MODE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Complétude noms ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Complétude des noms]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE FIRST_NAME IS NULL OR FIRST_NAME = ' ';
    print_kv('  Sans FIRST_NAME', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE LAST_NAME IS NULL OR LAST_NAME = ' ';
    print_kv('  Sans LAST_NAME', TO_CHAR(v_count));


    -- =========================================================
    -- 4. STTM_CUST_ACCOUNT
    -- =========================================================
    print_section('4. STTM_CUST_ACCOUNT — Comptes clients');

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('  [Top 10 devises (CCY)]');
    FOR r IN (
        SELECT CCY, nb FROM (
            SELECT CCY, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY CCY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY = ' || r.CCY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 classes de compte (ACCOUNT_CLASS)]');
    FOR r IN (
        SELECT ACCOUNT_CLASS, nb FROM (
            SELECT ACCOUNT_CLASS, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY ACCOUNT_CLASS ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ACCOUNT_CLASS = ' || r.ACCOUNT_CLASS, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptes avec restrictions actives]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_DORMANT = 'Y';
    print_kv('  Comptes DORMANTS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_FROZEN = 'Y';
    print_kv('  Comptes GELÉS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_NO_DR = 'Y';
    print_kv('  Bloqués au DÉBIT', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_NO_CR = 'Y';
    print_kv('  Bloqués au CRÉDIT', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_STOP_PAY = 'Y';
    print_kv('  STOP PAYMENT', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_STAT_BLOCK = 'Y';
    print_kv('  Comptes BLOQUÉS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE NSF_BLACKLIST_STATUS = 'Y';
    print_kv('  Liste noire NSF', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques soldes (ACY_CURR_BALANCE)]');
    FOR r IN (
        SELECT
            ROUND(MIN(ACY_CURR_BALANCE),2)  bal_min,
            ROUND(MAX(ACY_CURR_BALANCE),2)  bal_max,
            ROUND(AVG(ACY_CURR_BALANCE),2)  bal_avg,
            ROUND(SUM(ACY_CURR_BALANCE),2)  bal_sum,
            COUNT(CASE WHEN ACY_CURR_BALANCE < 0 THEN 1 END) nb_negatif
        FROM STTM_CUST_ACCOUNT
    ) LOOP
        print_kv('  Solde MIN', TO_CHAR(r.bal_min));
        print_kv('  Solde MAX', TO_CHAR(r.bal_max));
        print_kv('  Solde MOYEN', TO_CHAR(r.bal_avg));
        print_kv('  Solde TOTAL (SUM)', TO_CHAR(r.bal_sum));
        print_kv('  Comptes à solde NÉGATIF', TO_CHAR(r.nb_negatif));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE OVERDRAFT_SINCE IS NOT NULL;
    print_kv('  En OVERDRAFT', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    FOR r IN (SELECT MIN(AC_OPEN_DATE) dt_min, MAX(AC_OPEN_DATE) dt_max FROM STTM_CUST_ACCOUNT) LOOP
        print_kv('  Compte le plus ancien', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  Compte le plus récent', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Inactivité des comptes]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE (DATE_LAST_CR_ACTIVITY < ADD_MONTHS(SYSDATE, -12) OR DATE_LAST_CR_ACTIVITY IS NULL)
      AND (DATE_LAST_DR_ACTIVITY < ADD_MONTHS(SYSDATE, -12) OR DATE_LAST_DR_ACTIVITY IS NULL);
    print_kv('  Sans activité depuis > 12 mois', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE (DATE_LAST_CR_ACTIVITY < ADD_MONTHS(SYSDATE, -6) OR DATE_LAST_CR_ACTIVITY IS NULL)
      AND (DATE_LAST_DR_ACTIVITY < ADD_MONTHS(SYSDATE, -6) OR DATE_LAST_DR_ACTIVITY IS NULL);
    print_kv('  Sans activité depuis > 6 mois', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE (DATE_LAST_CR_ACTIVITY < ADD_MONTHS(SYSDATE, -24) OR DATE_LAST_CR_ACTIVITY IS NULL)
      AND (DATE_LAST_DR_ACTIVITY < ADD_MONTHS(SYSDATE, -24) OR DATE_LAST_DR_ACTIVITY IS NULL);
    print_kv('  Sans activité depuis > 24 mois', TO_CHAR(v_count));

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 agences (BRANCH_CODE)]');
    FOR r IN (
        SELECT BRANCH_CODE, nb FROM (
            SELECT BRANCH_CODE, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Agence : ' || r.BRANCH_CODE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Type de compte ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition ACCOUNT_TYPE]');
    FOR r IN (SELECT ACCOUNT_TYPE, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY ACCOUNT_TYPE ORDER BY nb DESC) LOOP
        print_kv('  ACCOUNT_TYPE = ' || r.ACCOUNT_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Mode d'opération ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [MODE_OF_OPERATION]');
    FOR r IN (SELECT MODE_OF_OPERATION, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY MODE_OF_OPERATION ORDER BY nb DESC) LOOP
        print_kv('  Mode : ' || r.MODE_OF_OPERATION, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Comptes joints ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptes joints]');
    FOR r IN (SELECT JOINT_AC_INDICATOR, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY JOINT_AC_INDICATOR ORDER BY nb DESC) LOOP
        print_kv('  JOINT_AC_INDICATOR = ' || r.JOINT_AC_INDICATOR, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Comptes salaire ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE SALARY_ACCOUNT = 'Y';
    print_kv('  Comptes SALAIRE', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : AUTH_STAT / RECORD_STAT ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statut enregistrement des comptes]');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM STTM_CUST_ACCOUNT GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.RECORD_STAT, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Dormance ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Analyse dormance]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE DORMANCY_DATE IS NOT NULL;
    print_kv('  Comptes avec DORMANCY_DATE', TO_CHAR(v_count));
    FOR r IN (
        SELECT MIN(DORMANCY_DATE) dt_min, MAX(DORMANCY_DATE) dt_max
        FROM STTM_CUST_ACCOUNT WHERE DORMANCY_DATE IS NOT NULL
    ) LOOP
        print_kv('  Dormance la plus ancienne', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  Dormance la plus récente', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;

    -- *** ENRICHISSEMENT : Turnovers ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques turnovers (ACY)]');
    FOR r IN (
        SELECT
            ROUND(SUM(ACY_TODAY_TOVER_DR),2) sum_dr,
            ROUND(SUM(ACY_TODAY_TOVER_CR),2) sum_cr,
            ROUND(SUM(ACY_MTD_TOVER_DR),2)  mtd_dr,
            ROUND(SUM(ACY_MTD_TOVER_CR),2)  mtd_cr
        FROM STTM_CUST_ACCOUNT
    ) LOOP
        print_kv('  Total DR today (SUM)', TO_CHAR(r.sum_dr));
        print_kv('  Total CR today (SUM)', TO_CHAR(r.sum_cr));
        print_kv('  Total DR MTD (SUM)', TO_CHAR(r.mtd_dr));
        print_kv('  Total CR MTD (SUM)', TO_CHAR(r.mtd_cr));
    END LOOP;

    -- *** ENRICHISSEMENT : Multi-comptes par client ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Clients multi-comptes]');
    FOR r IN (
        SELECT nb_comptes, COUNT(*) nb_clients FROM (
            SELECT CUST_NO, COUNT(*) nb_comptes FROM STTM_CUST_ACCOUNT GROUP BY CUST_NO
        ) GROUP BY nb_comptes ORDER BY nb_comptes
    ) LOOP
        print_kv('  Clients avec ' || r.nb_comptes || ' compte(s)', TO_CHAR(r.nb_clients));
    END LOOP;


    -- =========================================================
    -- 5. STTB_ACCOUNT
    -- =========================================================
    print_section('5. STTB_ACCOUNT — Comptes GL / Comptabilité');

    SELECT COUNT(*) INTO v_count FROM STTB_ACCOUNT WHERE AC_STAT_DORMANT = 'Y';
    print_kv('  Comptes GL DORMANTS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTB_ACCOUNT WHERE AC_STAT_FROZEN = 'Y';
    print_kv('  Comptes GL GELÉS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTB_ACCOUNT WHERE GL_STAT_BLOCKED = 'Y';
    print_kv('  GL BLOQUÉS', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition AC_OR_GL]');
    FOR r IN (SELECT AC_OR_GL, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY AC_OR_GL ORDER BY nb DESC) LOOP
        print_kv('  AC_OR_GL = ' || r.AC_OR_GL, TO_CHAR(r.nb));
    END LOOP;

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 catégories GL]');
    FOR r IN (
        SELECT GL_CATEGORY, nb FROM (
            SELECT GL_CATEGORY, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY GL_CATEGORY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  GL_CATEGORY = ' || r.GL_CATEGORY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : AUTH_STAT / RECORD_STAT ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statut enregistrement STTB_ACCOUNT]');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT AC_GL_REC_STATUS, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY AC_GL_REC_STATUS ORDER BY nb DESC) LOOP
        print_kv('  AC_GL_REC_STATUS = ' || r.AC_GL_REC_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Top devises ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 devises (AC_GL_CCY)]');
    FOR r IN (
        SELECT AC_GL_CCY, nb FROM (
            SELECT AC_GL_CCY, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY AC_GL_CCY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  AC_GL_CCY = ' || r.AC_GL_CCY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Top branches ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 agences (BRANCH_CODE)]');
    FOR r IN (
        SELECT BRANCH_CODE, nb FROM (
            SELECT BRANCH_CODE, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Agence : ' || r.BRANCH_CODE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Type classe GL ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition GL_ACLASS_TYPE]');
    FOR r IN (SELECT GL_ACLASS_TYPE, COUNT(*) nb FROM STTB_ACCOUNT GROUP BY GL_ACLASS_TYPE ORDER BY nb DESC) LOOP
        print_kv('  GL_ACLASS_TYPE = ' || r.GL_ACLASS_TYPE, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 6. STTM_KYC_MASTER
    -- =========================================================
    print_section('6. STTM_KYC_MASTER — Référentiel KYC');

    DBMS_OUTPUT.PUT_LINE('  [Répartition KYC_CUST_TYPE]');
    FOR r IN (SELECT KYC_CUST_TYPE, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY KYC_CUST_TYPE ORDER BY nb DESC) LOOP
        print_kv('  KYC_CUST_TYPE = ' || r.KYC_CUST_TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition RISK_LEVEL]');
    FOR r IN (SELECT RISK_LEVEL, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY RISK_LEVEL ORDER BY nb DESC) LOOP
        print_kv('  RISK_LEVEL = ' || r.RISK_LEVEL, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [AUTH_STAT des dossiers KYC]');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : RECORD_STAT ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [RECORD_STAT des dossiers KYC]');
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.RECORD_STAT, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Croisement RISK_LEVEL x KYC_CUST_TYPE ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Croisement RISK_LEVEL x KYC_CUST_TYPE]');
    FOR r IN (
        SELECT KYC_CUST_TYPE, RISK_LEVEL, COUNT(*) nb
        FROM STTM_KYC_MASTER
        GROUP BY KYC_CUST_TYPE, RISK_LEVEL
        ORDER BY KYC_CUST_TYPE, nb DESC
    ) LOOP
        print_kv('  ' || r.KYC_CUST_TYPE || ' / ' || r.RISK_LEVEL, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Contrôle maker/checker (même personne ?) ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Contrôle Maker = Checker (ségrégation des tâches)]');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_MASTER
    WHERE MAKER_ID IS NOT NULL AND CHECKER_ID IS NOT NULL AND MAKER_ID = CHECKER_ID;
    print_kv('  KYC où MAKER_ID = CHECKER_ID', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Description KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_MASTER WHERE KYC_DESC IS NULL OR KYC_DESC = ' ';
    print_kv('  KYC sans description (KYC_DESC)', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Top makers ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 MAKER_ID (créateurs dossiers KYC)]');
    FOR r IN (
        SELECT MAKER_ID, nb FROM (
            SELECT MAKER_ID, COUNT(*) nb FROM STTM_KYC_MASTER GROUP BY MAKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Maker : ' || r.MAKER_ID, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 7. STTM_KYC_RETAIL
    -- =========================================================
    print_section('7. STTM_KYC_RETAIL — KYC Particuliers');

    DBMS_OUTPUT.PUT_LINE('  [PEP — Personnes Politiquement Exposées]');
    FOR r IN (SELECT PEP, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY PEP ORDER BY nb DESC) LOOP
        print_kv('  PEP = ' || r.PEP, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [RESIDENT]');
    FOR r IN (SELECT RESIDENT, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY RESIDENT ORDER BY nb DESC) LOOP
        print_kv('  RESIDENT = ' || r.RESIDENT, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques TOTAL_INCOME déclaré]');
    FOR r IN (
        SELECT MIN(TOTAL_INCOME) mn, MAX(TOTAL_INCOME) mx,
               ROUND(AVG(TOTAL_INCOME),2) av,
               COUNT(CASE WHEN TOTAL_INCOME IS NULL OR TOTAL_INCOME = 0 THEN 1 END) nb_zero
        FROM STTM_KYC_RETAIL
    ) LOOP
        print_kv('  MIN', TO_CHAR(r.mn));
        print_kv('  MAX', TO_CHAR(r.mx));
        print_kv('  MOYENNE', TO_CHAR(r.av));
        print_kv('  Sans revenu déclaré (NULL ou 0)', TO_CHAR(r.nb_zero));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE VISA_EXPIRY_DATE < SYSDATE AND VISA_EXPIRY_DATE IS NOT NULL;
    print_kv('  Visas EXPIRÉS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PASSPORT_EXPIRY_DATE < SYSDATE AND PASSPORT_EXPIRY_DATE IS NOT NULL;
    print_kv('  Passeports EXPIRÉS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE KYC_NXT_REVIEW_DATE < SYSDATE AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    print_kv('  KYC Review DATE DÉPASSÉE', TO_CHAR(v_count));

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 ACC_PURPOSE]');
    FOR r IN (
        SELECT ACC_PURPOSE, nb FROM (
            SELECT ACC_PURPOSE, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY ACC_PURPOSE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Objet : ' || r.ACC_PURPOSE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [US_RES_STATUS — Conformité FATCA]');
    FOR r IN (SELECT US_RES_STATUS, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY US_RES_STATUS ORDER BY nb DESC) LOOP
        print_kv('  US_RES_STATUS = ' || r.US_RES_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Détail des sources de revenus (champs VARCHAR2) ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Détail des sources de revenus renseignées]');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE SALARY_INCOME IS NOT NULL AND SALARY_INCOME != ' ';
    print_kv('  Avec SALARY_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE RENTAL_INCOME IS NOT NULL AND RENTAL_INCOME != ' ';
    print_kv('  Avec RENTAL_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE INVESTMENT_INCOME IS NOT NULL AND INVESTMENT_INCOME != ' ';
    print_kv('  Avec INVESTMENT_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE BUSINESS_INCOME IS NOT NULL AND BUSINESS_INCOME != ' ';
    print_kv('  Avec BUSINESS_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PROF_BUSINESS_INCOME IS NOT NULL AND PROF_BUSINESS_INCOME != ' ';
    print_kv('  Avec PROF_BUSINESS_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE OVERSEAS_INCOME IS NOT NULL AND OVERSEAS_INCOME != ' ';
    print_kv('  Avec OVERSEAS_INCOME renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE OTHR_INCOME_SOURCES IS NOT NULL AND OTHR_INCOME_SOURCES != ' ';
    print_kv('  Avec OTHR_INCOME_SOURCES renseigné', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Patrimoine net ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques TOTAL_NET_WORTH]');
    FOR r IN (
        SELECT MIN(TOTAL_NET_WORTH) mn, MAX(TOTAL_NET_WORTH) mx,
               ROUND(AVG(TOTAL_NET_WORTH),2) av,
               COUNT(CASE WHEN TOTAL_NET_WORTH IS NULL OR TOTAL_NET_WORTH = 0 THEN 1 END) nb_zero
        FROM STTM_KYC_RETAIL
    ) LOOP
        print_kv('  NET_WORTH MIN', TO_CHAR(r.mn));
        print_kv('  NET_WORTH MAX', TO_CHAR(r.mx));
        print_kv('  NET_WORTH MOYEN', TO_CHAR(r.av));
        print_kv('  Sans patrimoine (NULL ou 0)', TO_CHAR(r.nb_zero));
    END LOOP;

    -- *** ENRICHISSEMENT : Nationalité KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 nationalités KYC Retail]');
    FOR r IN (
        SELECT NATIONALITY, nb FROM (
            SELECT NATIONALITY, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY NATIONALITY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Nationalité : ' || r.NATIONALITY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Pays de naissance KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 BIRTH_COUNTRY KYC Retail]');
    FOR r IN (
        SELECT BIRTH_COUNTRY, nb FROM (
            SELECT BIRTH_COUNTRY, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY BIRTH_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Pays naissance : ' || r.BIRTH_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Type de compte KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [ACC_TYPE KYC Retail]');
    FOR r IN (SELECT ACC_TYPE, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY ACC_TYPE ORDER BY nb DESC) LOOP
        print_kv('  ACC_TYPE = ' || r.ACC_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Déclaration ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [DECLARED]');
    FOR r IN (SELECT DECLARED, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY DECLARED ORDER BY nb DESC) LOOP
        print_kv('  DECLARED = ' || r.DECLARED, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Procuration KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [PA_GIVEN (Power of Attorney)]');
    FOR r IN (SELECT PA_GIVEN, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY PA_GIVEN ORDER BY nb DESC) LOOP
        print_kv('  PA_GIVEN = ' || r.PA_GIVEN, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : PEP avec remarques ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PEP = 'Y' AND (PEP_REMARKS IS NULL OR PEP_REMARKS = ' ');
    print_kv('  PEP=Y MAIS sans PEP_REMARKS', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PEP = 'Y' AND PEP_REMARKS IS NOT NULL AND PEP_REMARKS != ' ';
    print_kv('  PEP=Y avec PEP_REMARKS', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Devise des montants KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Devise des montants KYC (KYC_AMTS_CCY)]');
    FOR r IN (SELECT KYC_AMTS_CCY, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY KYC_AMTS_CCY ORDER BY nb DESC) LOOP
        print_kv('  KYC_AMTS_CCY = ' || r.KYC_AMTS_CCY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Pays adresses KYC ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 LOCAL_ADDR_COUNTRY]');
    FOR r IN (
        SELECT LOCAL_ADDR_COUNTRY, nb FROM (
            SELECT LOCAL_ADDR_COUNTRY, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY LOCAL_ADDR_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  LOCAL_ADDR_COUNTRY : ' || r.LOCAL_ADDR_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 HOME_ADDR_COUNTRY]');
    FOR r IN (
        SELECT HOME_ADDR_COUNTRY, nb FROM (
            SELECT HOME_ADDR_COUNTRY, COUNT(*) nb FROM STTM_KYC_RETAIL GROUP BY HOME_ADDR_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  HOME_ADDR_COUNTRY : ' || r.HOME_ADDR_COUNTRY, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 8. STTM_KYC_CORPORATE
    -- =========================================================
    print_section('8. STTM_KYC_CORPORATE — KYC Entreprises');

    DBMS_OUTPUT.PUT_LINE('  [Répartition COMPANY_TYPE]');
    FOR r IN (SELECT COMPANY_TYPE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY COMPANY_TYPE ORDER BY nb DESC) LOOP
        print_kv('  Type société : ' || r.COMPANY_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 sources de fonds (FUNDS_SOURCE)]');
    FOR r IN (
        SELECT FUNDS_SOURCE, nb FROM (
            SELECT FUNDS_SOURCE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY FUNDS_SOURCE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Fonds : ' || r.FUNDS_SOURCE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques ANNUAL_TURNOVER]');
    FOR r IN (
        SELECT MIN(ANNUAL_TURNOVER) mn, MAX(ANNUAL_TURNOVER) mx,
               ROUND(AVG(ANNUAL_TURNOVER),2) av,
               COUNT(CASE WHEN ANNUAL_TURNOVER IS NULL OR ANNUAL_TURNOVER = 0 THEN 1 END) nb_zero
        FROM STTM_KYC_CORPORATE
    ) LOOP
        print_kv('  CA MIN', TO_CHAR(r.mn));
        print_kv('  CA MAX', TO_CHAR(r.mx));
        print_kv('  CA MOYEN', TO_CHAR(r.av));
        print_kv('  CA non renseigné (NULL ou 0)', TO_CHAR(r.nb_zero));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE KYC_NXT_REVIEW_DATE < SYSDATE AND KYC_NXT_REVIEW_DATE IS NOT NULL;
    print_kv('  KYC Review DATE DÉPASSÉE', TO_CHAR(v_count));

    -- *** CORRECTION : ROWNUM ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays maison mère (PARENT_CMPNY_COUNTRY)]');
    FOR r IN (
        SELECT PARENT_CMPNY_COUNTRY, nb FROM (
            SELECT PARENT_CMPNY_COUNTRY, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY PARENT_CMPNY_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Pays : ' || r.PARENT_CMPNY_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Nature d'activité ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 BUSINESS_NATURE]');
    FOR r IN (
        SELECT BUSINESS_NATURE, nb FROM (
            SELECT BUSINESS_NATURE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY BUSINESS_NATURE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Activité : ' || r.BUSINESS_NATURE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Objet du compte ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 ACC_PURPOSE Corporate]');
    FOR r IN (
        SELECT ACC_PURPOSE, nb FROM (
            SELECT ACC_PURPOSE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY ACC_PURPOSE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Objet : ' || r.ACC_PURPOSE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Produits échangés ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 PRODUCTS_TRADED]');
    FOR r IN (
        SELECT PRODUCTS_TRADED, nb FROM (
            SELECT PRODUCTS_TRADED, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY PRODUCTS_TRADED ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Produits : ' || r.PRODUCTS_TRADED, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Mode de paiement salaires ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Mode paiement salaires (SALARY_MODE)]');
    FOR r IN (SELECT SALARY_MODE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY SALARY_MODE ORDER BY nb DESC) LOOP
        print_kv('  SALARY_MODE = ' || r.SALARY_MODE, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Nombre d'employés ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques EMPLOYEE_NUMBER]');
    FOR r IN (
        SELECT MIN(EMPLOYEE_NUMBER) mn, MAX(EMPLOYEE_NUMBER) mx,
               ROUND(AVG(EMPLOYEE_NUMBER),2) av,
               COUNT(CASE WHEN EMPLOYEE_NUMBER IS NULL OR EMPLOYEE_NUMBER = 0 THEN 1 END) nb_zero
        FROM STTM_KYC_CORPORATE
    ) LOOP
        print_kv('  Employés MIN', TO_CHAR(r.mn));
        print_kv('  Employés MAX', TO_CHAR(r.mx));
        print_kv('  Employés MOYEN', TO_CHAR(r.av));
        print_kv('  Non renseigné (NULL ou 0)', TO_CHAR(r.nb_zero));
    END LOOP;

    -- *** ENRICHISSEMENT : Conformité et sollicitation ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Conformité et sollicitation]');
    FOR r IN (SELECT ACC_SOLICITED, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY ACC_SOLICITED ORDER BY nb DESC) LOOP
        print_kv('  ACC_SOLICITED = ' || r.ACC_SOLICITED, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT COMPLIANCE_CLEARANCE, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY COMPLIANCE_CLEARANCE ORDER BY nb DESC) LOOP
        print_kv('  COMPLIANCE_CLEARANCE = ' || r.COMPLIANCE_CLEARANCE, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT BUSINESS_APPROVAL, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY BUSINESS_APPROVAL ORDER BY nb DESC) LOOP
        print_kv('  BUSINESS_APPROVAL = ' || r.BUSINESS_APPROVAL, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Licence commerciale ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE TRADE_LICENCE_NO IS NULL OR TRADE_LICENCE_NO = ' ';
    print_kv('  Sans TRADE_LICENCE_NO', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE TRADE_LICENCE_NO IS NOT NULL AND TRADE_LICENCE_NO != ' ';
    print_kv('  Avec TRADE_LICENCE_NO', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Introducteur entreprise ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE INTRODUCER_DTL IS NULL OR INTRODUCER_DTL = ' ';
    print_kv('  Sans INTRODUCER_DTL', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE INTRODUCER_DTL IS NOT NULL AND INTRODUCER_DTL != ' ';
    print_kv('  Avec INTRODUCER_DTL', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Date d'audit ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Analyse AUDIT_DATE]');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE AUDIT_DATE IS NULL;
    print_kv('  Sans AUDIT_DATE', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE WHERE AUDIT_DATE < ADD_MONTHS(SYSDATE, -12) AND AUDIT_DATE IS NOT NULL;
    print_kv('  AUDIT_DATE > 12 mois', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Localisation succursales ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [LOCAL_ABROAD_BRN]');
    FOR r IN (SELECT LOCAL_ABROAD_BRN, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY LOCAL_ABROAD_BRN ORDER BY nb DESC) LOOP
        print_kv('  LOCAL_ABROAD_BRN = ' || r.LOCAL_ABROAD_BRN, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Nom de groupe ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 GROUP_NAME]');
    FOR r IN (
        SELECT GROUP_NAME, nb FROM (
            SELECT GROUP_NAME, COUNT(*) nb FROM STTM_KYC_CORPORATE
            WHERE GROUP_NAME IS NOT NULL AND GROUP_NAME != ' '
            GROUP BY GROUP_NAME ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Groupe : ' || r.GROUP_NAME, TO_CHAR(r.nb));
    END LOOP;

    -- *** ENRICHISSEMENT : Devise KYC Corporate ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [KYC_AMTS_CCY Corporate]');
    FOR r IN (SELECT KYC_AMTS_CCY, COUNT(*) nb FROM STTM_KYC_CORPORATE GROUP BY KYC_AMTS_CCY ORDER BY nb DESC) LOOP
        print_kv('  KYC_AMTS_CCY = ' || r.KYC_AMTS_CCY, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 9. ACTB_HISTORY — Historique des transactions
    -- =========================================================
    print_section('9. ACTB_HISTORY — Historique des transactions (CRITIQUE AML)');

    DBMS_OUTPUT.PUT_LINE('  [Plage temporelle des transactions]');
    FOR r IN (SELECT MIN(TRN_DT) dt_min, MAX(TRN_DT) dt_max FROM ACTB_HISTORY) LOOP
        print_kv('  Transaction la plus ancienne', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  Transaction la plus récente', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition DRCR_IND (Débit/Crédit)]');
    FOR r IN (SELECT DRCR_IND, COUNT(*) nb FROM ACTB_HISTORY GROUP BY DRCR_IND ORDER BY nb DESC) LOOP
        print_kv('  DRCR_IND = ' || r.DRCR_IND, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques montants (LCY_AMOUNT — monnaie locale)]');
    FOR r IN (
        SELECT
            ROUND(MIN(LCY_AMOUNT),2) mn,
            ROUND(MAX(LCY_AMOUNT),2) mx,
            ROUND(AVG(LCY_AMOUNT),2) av,
            ROUND(SUM(LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY
    ) LOOP
        print_kv('  LCY_AMOUNT MIN', TO_CHAR(r.mn));
        print_kv('  LCY_AMOUNT MAX', TO_CHAR(r.mx));
        print_kv('  LCY_AMOUNT MOYEN', TO_CHAR(r.av));
        print_kv('  LCY_AMOUNT TOTAL', TO_CHAR(r.sm));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Statistiques montants (FCY_AMOUNT — devise étrangère)]');
    FOR r IN (
        SELECT
            ROUND(MIN(FCY_AMOUNT),2) mn,
            ROUND(MAX(FCY_AMOUNT),2) mx,
            ROUND(AVG(FCY_AMOUNT),2) av,
            COUNT(CASE WHEN FCY_AMOUNT != LCY_AMOUNT AND FCY_AMOUNT > 0 THEN 1 END) nb_fcy
        FROM ACTB_HISTORY
    ) LOOP
        print_kv('  FCY_AMOUNT MIN', TO_CHAR(r.mn));
        print_kv('  FCY_AMOUNT MAX', TO_CHAR(r.mx));
        print_kv('  FCY_AMOUNT MOYEN', TO_CHAR(r.av));
        print_kv('  Transactions en devise étrangère', TO_CHAR(r.nb_fcy));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 devises (AC_CCY)]');
    FOR r IN (
        SELECT AC_CCY, nb FROM (
            SELECT AC_CCY, COUNT(*) nb FROM ACTB_HISTORY GROUP BY AC_CCY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  AC_CCY = ' || r.AC_CCY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 codes transaction (TRN_CODE)]');
    FOR r IN (
        SELECT TRN_CODE, nb FROM (
            SELECT TRN_CODE, COUNT(*) nb FROM ACTB_HISTORY GROUP BY TRN_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  TRN_CODE = ' || r.TRN_CODE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 modules (MODULE)]');
    FOR r IN (
        SELECT MODULE, nb FROM (
            SELECT MODULE, COUNT(*) nb FROM ACTB_HISTORY GROUP BY MODULE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 produits (PRODUCT)]');
    FOR r IN (
        SELECT PRODUCT, nb FROM (
            SELECT PRODUCT, COUNT(*) nb FROM ACTB_HISTORY GROUP BY PRODUCT ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  PRODUCT = ' || r.PRODUCT, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 agences (AC_BRANCH)]');
    FOR r IN (
        SELECT AC_BRANCH, nb FROM (
            SELECT AC_BRANCH, COUNT(*) nb FROM ACTB_HISTORY GROUP BY AC_BRANCH ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  AC_BRANCH = ' || r.AC_BRANCH, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition TYPE]');
    FOR r IN (SELECT TYPE, COUNT(*) nb FROM ACTB_HISTORY GROUP BY TYPE ORDER BY nb DESC) LOOP
        print_kv('  TYPE = ' || r.TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition CATEGORY]');
    FOR r IN (SELECT CATEGORY, COUNT(*) nb FROM ACTB_HISTORY GROUP BY CATEGORY ORDER BY nb DESC) LOOP
        print_kv('  CATEGORY = ' || r.CATEGORY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Répartition CUST_GL]');
    FOR r IN (SELECT CUST_GL, COUNT(*) nb FROM ACTB_HISTORY GROUP BY CUST_GL ORDER BY nb DESC) LOOP
        print_kv('  CUST_GL = ' || r.CUST_GL, TO_CHAR(r.nb));
    END LOOP;

    -- *** AML : Exceptions AML ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [AML_EXCEPTION]');
    FOR r IN (SELECT AML_EXCEPTION, COUNT(*) nb FROM ACTB_HISTORY GROUP BY AML_EXCEPTION ORDER BY nb DESC) LOOP
        print_kv('  AML_EXCEPTION = ' || r.AML_EXCEPTION, TO_CHAR(r.nb));
    END LOOP;

    -- *** Volume par année ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Volume transactions par année]');
    FOR r IN (
        SELECT TO_CHAR(TRN_DT, 'YYYY') annee, COUNT(*) nb,
               ROUND(SUM(LCY_AMOUNT),2) total_lcy
        FROM ACTB_HISTORY
        WHERE TRN_DT IS NOT NULL
        GROUP BY TO_CHAR(TRN_DT, 'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee || ' — nb txns', TO_CHAR(r.nb));
        print_kv('  ' || r.annee || ' — total LCY', TO_CHAR(r.total_lcy));
    END LOOP;

    -- *** Top utilisateurs ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 USER_ID (opérateurs)]');
    FOR r IN (
        SELECT USER_ID, nb FROM (
            SELECT USER_ID, COUNT(*) nb FROM ACTB_HISTORY GROUP BY USER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  USER_ID : ' || r.USER_ID, TO_CHAR(r.nb));
    END LOOP;

    -- *** Transactions avec taux de change ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE EXCH_RATE IS NOT NULL AND EXCH_RATE != 1 AND EXCH_RATE != 0;
    print_kv('  Transactions avec taux change != 1', TO_CHAR(v_count));

    -- *** Events ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 EVENT]');
    FOR r IN (
        SELECT EVENT, nb FROM (
            SELECT EVENT, COUNT(*) nb FROM ACTB_HISTORY GROUP BY EVENT ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  EVENT = ' || r.EVENT, TO_CHAR(r.nb));
    END LOOP;

    -- *** Transactions liées à d'autres comptes ***
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE RELATED_ACCOUNT IS NOT NULL AND RELATED_ACCOUNT != ' ';
    print_kv('  Avec RELATED_ACCOUNT', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE RELATED_CUSTOMER IS NOT NULL AND RELATED_CUSTOMER != ' ';
    print_kv('  Avec RELATED_CUSTOMER', TO_CHAR(v_count));


    -- =========================================================
    -- 10. STTM_ACCOUNT_CLASS — Référentiel des classes de comptes
    -- =========================================================
    print_section('10. STTM_ACCOUNT_CLASS — Référentiel classes de comptes');

    DBMS_OUTPUT.PUT_LINE('  [Répartition AC_CLASS_TYPE]');
    FOR r IN (SELECT AC_CLASS_TYPE, COUNT(*) nb FROM STTM_ACCOUNT_CLASS GROUP BY AC_CLASS_TYPE ORDER BY nb DESC) LOOP
        print_kv('  AC_CLASS_TYPE = ' || r.AC_CLASS_TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Facilités]');
    SELECT COUNT(*) INTO v_count FROM STTM_ACCOUNT_CLASS WHERE OVERDRAFT_FACILITY = 'Y';
    print_kv('  Avec OVERDRAFT_FACILITY', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_ACCOUNT_CLASS WHERE CHEQUE_BOOK_FACILITY = 'Y';
    print_kv('  Avec CHEQUE_BOOK_FACILITY', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_ACCOUNT_CLASS WHERE ATM_FACILITY = 'Y';
    print_kv('  Avec ATM_FACILITY', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_ACCOUNT_CLASS WHERE PASSBOOK_FACILITY = 'Y';
    print_kv('  Avec PASSBOOK_FACILITY', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Dormance et statut]');
    FOR r IN (SELECT DORMANCY, COUNT(*) nb FROM STTM_ACCOUNT_CLASS GROUP BY DORMANCY ORDER BY nb DESC) LOOP
        print_kv('  DORMANCY = ' || r.DORMANCY, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_ACCOUNT_CLASS GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 ACCOUNT_CLASS avec description]');
    FOR r IN (
        SELECT ACCOUNT_CLASS, DESCRIPTION FROM (
            SELECT ACCOUNT_CLASS, DESCRIPTION FROM STTM_ACCOUNT_CLASS ORDER BY ACCOUNT_CLASS
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.ACCOUNT_CLASS, NVL(r.DESCRIPTION, 'N/A'));
    END LOOP;


    -- =========================================================
    -- 11. STTM_CUSTOMER_CAT — Référentiel catégories clients
    -- =========================================================
    print_section('11. STTM_CUSTOMER_CAT — Référentiel catégories clients');

    DBMS_OUTPUT.PUT_LINE('  [Liste complète des catégories]');
    FOR r IN (SELECT CUST_CAT, CUST_CAT_DESC FROM STTM_CUSTOMER_CAT ORDER BY CUST_CAT) LOOP
        print_kv('  ' || r.CUST_CAT, NVL(r.CUST_CAT_DESC, 'N/A'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_CUSTOMER_CAT GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;


    -- =========================================================
    -- 12. STTM_KYC_CORP_KEYPERSONS — Personnes clés entreprises
    -- =========================================================
    print_section('12. STTM_KYC_CORP_KEYPERSONS — Personnes clés (bénéficiaires effectifs)');

    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS;
    print_kv('  Nombre total de personnes clés', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(DISTINCT KYC_REF_NO) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS;
    print_kv('  Nombre de KYC Corporate avec keypersons', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Nombre de keypersons par dossier KYC]');
    FOR r IN (
        SELECT nb_kp, COUNT(*) nb_dossiers FROM (
            SELECT KYC_REF_NO, COUNT(*) nb_kp FROM STTM_KYC_CORP_KEYPERSONS GROUP BY KYC_REF_NO
        ) GROUP BY nb_kp ORDER BY nb_kp
    ) LOOP
        print_kv('  Dossiers avec ' || r.nb_kp || ' personne(s)', TO_CHAR(r.nb_dossiers));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 RELATIONSHIP]');
    FOR r IN (
        SELECT RELATIONSHIP, nb FROM (
            SELECT RELATIONSHIP, COUNT(*) nb FROM STTM_KYC_CORP_KEYPERSONS GROUP BY RELATIONSHIP ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Relation : ' || r.RELATIONSHIP, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 NATIONALITY keypersons]');
    FOR r IN (
        SELECT NATIONALITY, nb FROM (
            SELECT NATIONALITY, COUNT(*) nb FROM STTM_KYC_CORP_KEYPERSONS GROUP BY NATIONALITY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Nationalité : ' || r.NATIONALITY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 10 pays adresse (ADDRESS_COUNTRY)]');
    FOR r IN (
        SELECT ADDRESS_COUNTRY, nb FROM (
            SELECT ADDRESS_COUNTRY, COUNT(*) nb FROM STTM_KYC_CORP_KEYPERSONS GROUP BY ADDRESS_COUNTRY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Pays : ' || r.ADDRESS_COUNTRY, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Complétude SHARE_HOLDING]');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS WHERE SHARE_HOLDING IS NULL OR SHARE_HOLDING = 0;
    print_kv('  Sans SHARE_HOLDING (NULL ou 0)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS WHERE SHARE_HOLDING > 0;
    print_kv('  Avec SHARE_HOLDING > 0', TO_CHAR(v_count));
    FOR r IN (
        SELECT MIN(SHARE_HOLDING) mn, MAX(SHARE_HOLDING) mx, ROUND(AVG(SHARE_HOLDING),2) av
        FROM STTM_KYC_CORP_KEYPERSONS WHERE SHARE_HOLDING > 0
    ) LOOP
        print_kv('  SHARE_HOLDING MIN', TO_CHAR(r.mn));
        print_kv('  SHARE_HOLDING MAX', TO_CHAR(r.mx));
        print_kv('  SHARE_HOLDING MOYEN', TO_CHAR(r.av));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS WHERE TIN IS NULL OR TIN = ' ';
    print_kv('  Sans TIN (Tax ID)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORP_KEYPERSONS WHERE TIN IS NOT NULL AND TIN != ' ';
    print_kv('  Avec TIN (Tax ID)', TO_CHAR(v_count));


    -- =========================================================
    -- 13. COHERENCE INTER-TABLES
    -- =========================================================
    print_section('13. COHERENCE INTER-TABLES');

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE NOT EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a WHERE a.CUST_NO = c.CUSTOMER_NO);
    print_kv('  Clients sans compte (STTM_CUST_ACCOUNT)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_TYPE = 'I'
      AND NOT EXISTS (SELECT 1 FROM STTM_CUST_PERSONAL p WHERE p.CUSTOMER_NO = c.CUSTOMER_NO);
    print_kv('  Clients indiv. sans données perso.', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER
    WHERE AML_REQUIRED = 'Y'
      AND (KYC_REF_NO IS NULL OR KYC_REF_NO = ' ');
    print_kv('  AML requis MAIS sans KYC_REF_NO', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.KYC_REF_NO IS NOT NULL AND c.KYC_REF_NO != ' '
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_MASTER m WHERE m.KYC_REF_NO = c.KYC_REF_NO);
    print_kv('  KYC_REF_NO orphelins (pas dans MASTER)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE NOT EXISTS (SELECT 1 FROM STTB_ACCOUNT b WHERE b.CUST_NO = a.CUST_NO AND b.PKEY = a.CUST_AC_NO);
    print_kv('  Comptes sans entrée STTB_ACCOUNT', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : KYC Retail vs Corporate cohérence ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Cohérence KYC type vs tables détail]');
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_MASTER m
    WHERE m.KYC_CUST_TYPE = 'I'
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_RETAIL r WHERE r.KYC_REF_NO = m.KYC_REF_NO);
    print_kv('  KYC type I sans fiche RETAIL', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_MASTER m
    WHERE m.KYC_CUST_TYPE = 'C'
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_CORPORATE c WHERE c.KYC_REF_NO = m.KYC_REF_NO);
    print_kv('  KYC type C sans fiche CORPORATE', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Corporates sans keypersons ***
    SELECT COUNT(*) INTO v_count
    FROM STTM_KYC_CORPORATE c
    WHERE NOT EXISTS (SELECT 1 FROM STTM_KYC_CORP_KEYPERSONS k WHERE k.KYC_REF_NO = c.KYC_REF_NO);
    print_kv('  KYC Corporate sans KEYPERSONS', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Clients gelés mais comptes actifs ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Anomalies AML/KYC]');
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.FROZEN = 'Y'
      AND EXISTS (
          SELECT 1 FROM STTM_CUST_ACCOUNT a
          WHERE a.CUST_NO = c.CUSTOMER_NO
            AND a.AC_STAT_FROZEN != 'Y'
      );
    print_kv('  Clients GELÉS avec comptes NON gelés', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Clients décédés avec comptes actifs ***
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUSTOMER c
    WHERE c.DECEASED = 'Y'
      AND EXISTS (
          SELECT 1 FROM STTM_CUST_ACCOUNT a
          WHERE a.CUST_NO = c.CUSTOMER_NO
            AND a.AC_STAT_BLOCK != 'Y'
            AND a.AC_STAT_FROZEN != 'Y'
      );
    print_kv('  Clients DÉCÉDÉS avec comptes actifs', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Comptes avec transactions mais sans KYC ***
    SELECT COUNT(DISTINCT h.AC_NO) INTO v_count
    FROM ACTB_HISTORY h
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
    JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
    WHERE (c.KYC_REF_NO IS NULL OR c.KYC_REF_NO = ' ');
    print_kv('  Comptes actifs (avec txn) sans KYC', TO_CHAR(v_count));

    -- *** ENRICHISSEMENT : Doublons potentiels ***
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Doublons potentiels]');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT P_NATIONAL_ID FROM STTM_CUST_PERSONAL
        WHERE P_NATIONAL_ID IS NOT NULL AND P_NATIONAL_ID != ' '
        GROUP BY P_NATIONAL_ID HAVING COUNT(*) > 1
    );
    print_kv('  P_NATIONAL_ID en doublon (nb IDs)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM (
        SELECT PASSPORT_NO FROM STTM_CUST_PERSONAL
        WHERE PASSPORT_NO IS NOT NULL AND PASSPORT_NO != ' '
        GROUP BY PASSPORT_NO HAVING COUNT(*) > 1
    );
    print_kv('  PASSPORT_NO en doublon (nb passports)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM (
        SELECT UNIQUE_ID_VALUE FROM STTM_CUSTOMER
        WHERE UNIQUE_ID_VALUE IS NOT NULL AND UNIQUE_ID_VALUE != ' '
        GROUP BY UNIQUE_ID_VALUE HAVING COUNT(*) > 1
    );
    print_kv('  UNIQUE_ID_VALUE en doublon (nb IDs)', TO_CHAR(v_count));

    -- =========================================================
    -- 14. CSTM_FUNCTION_USERDEF_FIELDS — Champs personnalisés
    -- =========================================================
    print_section('14. CSTM_FUNCTION_USERDEF_FIELDS — Champs personnalisés (UDF)');

    -- Volumétrie par FUNCTION_ID
    DBMS_OUTPUT.PUT_LINE('  [Volumétrie par FUNCTION_ID]');
    FOR r IN (
        SELECT function_id, COUNT(*) nb
        FROM cstm_function_userdef_fields
        GROUP BY function_id
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ' || r.function_id, TO_CHAR(r.nb) || ' lignes');
    END LOOP;

    -- 14.1 GEDCOLLT — Collatéraux
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.1 GEDCOLLT — Collatéraux]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS collateral_id,
                field_val_1 AS coll_address,
                field_val_2 AS coll_state,
                field_val_3 AS collateral_status,
                field_val_4 AS collateral_value_mgr_est,
                field_val_5 AS collateral_value_omv,
                field_val_6 AS collateral_value_fsv,
                field_val_7 AS perfection_status,
                field_val_8 AS valuers,
                field_val_9 AS insurer,
                field_val_10 AS od_creation_type,
                field_val_11 AS od_facility_type,
                field_val_12 AS collateral_owner,
                field_val_13 AS crms_ref_no,
                field_val_14 AS charge_type,
                field_val_15 AS documentation_status,
                field_val_16 AS perfection_status_new,
                field_val_17 AS revaluation_date,
                field_val_18 AS valuation_date,
                field_val_19 AS valuer_name
            FROM cstm_function_userdef_fields
            WHERE function_id = 'GEDCOLLT'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Collateral ID: ' || r.collateral_id || ' ---');
        print_kv('    Adresse', r.coll_address);
        print_kv('    État', r.coll_state);
        print_kv('    Statut collatéral', r.collateral_status);
        print_kv('    Valeur MGR Est.', r.collateral_value_mgr_est);
        print_kv('    Valeur OMV', r.collateral_value_omv);
        print_kv('    Valeur FSV', r.collateral_value_fsv);
        print_kv('    Statut perfection', r.perfection_status);
        print_kv('    Évaluateurs', r.valuers);
        print_kv('    Assureur', r.insurer);
        print_kv('    Type création OD', r.od_creation_type);
        print_kv('    Type facilité OD', r.od_facility_type);
        print_kv('    Propriétaire', r.collateral_owner);
        print_kv('    Réf CRMS', r.crms_ref_no);
        print_kv('    Type charge', r.charge_type);
        print_kv('    Statut documentation', r.documentation_status);
        print_kv('    Statut perfection (new)', r.perfection_status_new);
        print_kv('    Date réévaluation', r.revaluation_date);
        print_kv('    Date évaluation', r.valuation_date);
        print_kv('    Nom évaluateur', r.valuer_name);
    END LOOP;

    -- 14.2 GEDFACLT — Facilités
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.2 GEDFACLT — Facilités]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS facility_id,
                field_val_1 AS irr_value,
                field_val_2 AS facility_collaterized
            FROM cstm_function_userdef_fields
            WHERE function_id = 'GEDFACLT'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Facility ID: ' || r.facility_id || ' ---');
        print_kv('    Valeur IRR', r.irr_value);
        print_kv('    Facilité collatéralisée', r.facility_collaterized);
    END LOOP;

    -- 14.3 GEDMLIAB — Engagements (Liabilities)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.3 GEDMLIAB — Engagements (Liabilities)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS liability_no,
                field_val_1 AS or_rating,
                field_val_2 AS customer_credit_rating
            FROM cstm_function_userdef_fields
            WHERE function_id = 'GEDMLIAB'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Liability No: ' || r.liability_no || ' ---');
        print_kv('    OR Rating', r.or_rating);
        print_kv('    Customer Credit Rating', r.customer_credit_rating);
    END LOOP;

    -- 14.4 GLDCHACC — Comptes GL (ownership)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.4 GLDCHACC — Comptes GL (ownership)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS gl_code,
                field_val_1 AS gl_ownership
            FROM cstm_function_userdef_fields
            WHERE function_id = 'GLDCHACC'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- GL Code: ' || r.gl_code || ' ---');
        print_kv('    GL Ownership', r.gl_ownership);
    END LOOP;

    -- 14.5 SMDROLDF — Rôles utilisateurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.5 SMDROLDF — Rôles utilisateurs]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                rec_key,
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS role_id,
                field_val_1 AS privilege_acclass_list,
                field_val_2 AS privilege_role
            FROM cstm_function_userdef_fields
            WHERE function_id = 'SMDROLDF'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Role ID: ' || r.role_id || ' (rec_key: ' || r.rec_key || ') ---');
        print_kv('    Privilege AC Class List', r.privilege_acclass_list);
        print_kv('    Privilege Role', r.privilege_role);
    END LOOP;

    -- 14.6 SMDUSRDF — Utilisateurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.6 SMDUSRDF — Utilisateurs]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                rec_key,
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS user_id,
                field_val_1 AS email_address,
                field_val_2 AS staff_id
            FROM cstm_function_userdef_fields
            WHERE function_id = 'SMDUSRDF'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- User ID: ' || r.user_id || ' (rec_key: ' || r.rec_key || ') ---');
        print_kv('    Email', r.email_address);
        print_kv('    Staff ID', r.staff_id);
    END LOOP;

    -- 14.7 STDACCLS — Classes de comptes (privilège)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.7 STDACCLS — Classes de comptes (privilège)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                rec_key,
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS account_class,
                field_val_1 AS privilege
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDACCLS'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Account Class: ' || r.account_class || ' (rec_key: ' || r.rec_key || ') ---');
        print_kv('    Privilège', r.privilege);
    END LOOP;

    -- 14.8 STDBRANC — Agences (téléphone)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.8 STDBRANC — Agences (téléphone)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS branch_code,
                field_val_1 AS branch_phone_no
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDBRANC'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Branch Code: ' || r.branch_code || ' ---');
        print_kv('    Téléphone agence', r.branch_phone_no);
    END LOOP;

    -- 14.9 STDCIF — Fiche client (UDF enrichis)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.9 STDCIF — Fiche client (UDF enrichis)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS customer_no,
                field_val_1 AS profession,
                field_val_2 AS religion,
                field_val_3 AS income_band,
                field_val_4 AS second_nationality,
                field_val_5 AS wedding_anniversary,
                field_val_6 AS tax_id_number,
                field_val_7 AS id_expiry_date,
                field_val_8 AS customer_old_name,
                field_val_9 AS customer_risk_rating,
                field_val_10 AS id_required,
                field_val_11 AS id_type,
                field_val_12 AS id_number,
                field_val_13 AS issuing_authority,
                field_val_14 AS issuing_authority_np,
                field_val_15 AS issue_date,
                field_val_16 AS expiry_date,
                field_val_17 AS revalidation_req,
                field_val_18 AS compliance_watchlist,
                field_val_19 AS compliance_watchlist_reason,
                field_val_20 AS director_1_name,
                field_val_21 AS director_2_name,
                field_val_22 AS director_3_name,
                field_val_23 AS director_4_name,
                field_val_24 AS director_5_name,
                field_val_25 AS alternative_email,
                field_val_26 AS aml_cft_risk_rating,
                field_val_27 AS broker_id,
                field_val_28 AS aml_cft_risk_score,
                field_val_29 AS mothers_maiden_name,
                field_val_30 AS ins_relat,
                field_val_31 AS sector_of_activity
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDCIF'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Customer No: ' || r.customer_no || ' ---');
        print_kv('    Profession', r.profession);
        print_kv('    Religion', r.religion);
        print_kv('    Tranche revenus', r.income_band);
        print_kv('    2e nationalité', r.second_nationality);
        print_kv('    Anniversaire mariage', r.wedding_anniversary);
        print_kv('    NIF (Tax ID)', r.tax_id_number);
        print_kv('    Date expiration ID', r.id_expiry_date);
        print_kv('    Ancien nom client', r.customer_old_name);
        print_kv('    Rating risque client', r.customer_risk_rating);
        print_kv('    ID requis', r.id_required);
        print_kv('    Type ID', r.id_type);
        print_kv('    Numéro ID', r.id_number);
        print_kv('    Autorité émettrice', r.issuing_authority);
        print_kv('    Autorité émettrice NP', r.issuing_authority_np);
        print_kv('    Date émission', r.issue_date);
        print_kv('    Date expiration', r.expiry_date);
        print_kv('    Revalidation requise', r.revalidation_req);
        print_kv('    Watchlist compliance', r.compliance_watchlist);
        print_kv('    Raison watchlist', r.compliance_watchlist_reason);
        print_kv('    Directeur 1', r.director_1_name);
        print_kv('    Directeur 2', r.director_2_name);
        print_kv('    Directeur 3', r.director_3_name);
        print_kv('    Directeur 4', r.director_4_name);
        print_kv('    Directeur 5', r.director_5_name);
        print_kv('    Email alternatif', r.alternative_email);
        print_kv('    Rating AML/CFT', r.aml_cft_risk_rating);
        print_kv('    Broker ID', r.broker_id);
        print_kv('    Score AML/CFT', r.aml_cft_risk_score);
        print_kv('    Nom jeune fille mère', r.mothers_maiden_name);
        print_kv('    Relation assurance', r.ins_relat);
        print_kv('    Secteur activité', r.sector_of_activity);
    END LOOP;

    -- 14.10 STDCUSAC — Comptes clients (UDF)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.10 STDCUSAC — Comptes clients (UDF)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                rec_key,
                SUBSTR(rec_key, INSTR(rec_key, '~', 1, 1) + 1,
                       INSTR(rec_key, '~', 1, 2) - INSTR(rec_key, '~', 1, 1) - 1) AS account_no,
                field_val_1 AS registration_number,
                field_val_2 AS wedding_anniversary_date,
                field_val_3 AS account_old_name,
                field_val_4 AS card_required,
                field_val_5 AS source_of_closure_request,
                field_val_6 AS reason_for_closure,
                field_val_7 AS mode_of_close_out_withdrawal,
                field_val_8 AS branch_of_account_closure,
                field_val_9 AS correlation_id,
                field_val_10 AS customer_ibu,
                field_val_11 AS ibu_status
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDCUSAC'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- Account No: ' || r.account_no || ' (rec_key: ' || r.rec_key || ') ---');
        print_kv('    N° enregistrement', r.registration_number);
        print_kv('    Date anniversaire mariage', r.wedding_anniversary_date);
        print_kv('    Ancien nom compte', r.account_old_name);
        print_kv('    Carte requise', r.card_required);
        print_kv('    Source demande fermeture', r.source_of_closure_request);
        print_kv('    Raison fermeture', r.reason_for_closure);
        print_kv('    Mode retrait clôture', r.mode_of_close_out_withdrawal);
        print_kv('    Agence fermeture', r.branch_of_account_closure);
        print_kv('    Correlation ID', r.correlation_id);
        print_kv('    Customer IBU', r.customer_ibu);
        print_kv('    Statut IBU', r.ibu_status);
    END LOOP;

    -- 14.11 STDKYCMN — KYC Master (PEP, source revenu)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.11 STDKYCMN — KYC Master (PEP, source revenu)]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                SUBSTR(rec_key, 1, LENGTH(rec_key) - 1) AS kyc_ref_no,
                field_val_1 AS pep_status,
                field_val_2 AS pep_status_others,
                field_val_3 AS pep_office,
                field_val_4 AS pep_relationship,
                field_val_5 AS pep_relationship_others,
                field_val_6 AS corp_ac_name_assoc_pep,
                field_val_7 AS corp_ac_sign_or_director,
                field_val_8 AS source_of_income_on_kyc_form
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDKYCMN'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- KYC Ref No: ' || r.kyc_ref_no || ' ---');
        print_kv('    Statut PEP', r.pep_status);
        print_kv('    PEP autres', r.pep_status_others);
        print_kv('    Fonction PEP', r.pep_office);
        print_kv('    Relation PEP', r.pep_relationship);
        print_kv('    Relation PEP autres', r.pep_relationship_others);
        print_kv('    Nom corp. associé PEP', r.corp_ac_name_assoc_pep);
        print_kv('    Signataire/Directeur', r.corp_ac_sign_or_director);
        print_kv('    Source revenu (KYC)', r.source_of_income_on_kyc_form);
    END LOOP;

    -- 14.12 STDSTCHN — Changements de statut comptes
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.12 STDSTCHN — Changements de statut comptes]');
    DBMS_OUTPUT.PUT_LINE('  Échantillon (Top 5) :');
    FOR r IN (
        SELECT * FROM (
            SELECT
                rec_key,
                SUBSTR(rec_key, 1, INSTR(rec_key, '~', 1, 1) - 1) AS ac_no,
                SUBSTR(rec_key, INSTR(rec_key, '~', 1, 1) + 1,
                       INSTR(rec_key, '~', 1, 2) - INSTR(rec_key, '~', 1, 1) - 1) AS branch_code,
                SUBSTR(rec_key, INSTR(rec_key, '~', 1, 2) + 1,
                       INSTR(rec_key, '~', 1, 3) - INSTR(rec_key, '~', 1, 2) - 1) AS trans_date,
                field_val_1 AS status_change_reason,
                field_val_2 AS reason_pnd,
                field_val_3 AS status_write_off_reason
            FROM cstm_function_userdef_fields
            WHERE function_id = 'STDSTCHN'
            ORDER BY rec_key
        ) WHERE ROWNUM <= 5
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('    --- AC No: ' || r.ac_no || ' | Agence: ' || r.branch_code || ' | Date: ' || r.trans_date || ' ---');
        print_kv('    Raison changement statut', r.status_change_reason);
        print_kv('    Raison PND', r.reason_pnd);
        print_kv('    Raison write-off', r.status_write_off_reason);
    END LOOP;

    -- =========================================================
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
