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
            SELECT 'STTM_KYC_CORPORATE', 7 FROM DUAL
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

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Plage de création des CIF]');
    FOR r IN (SELECT MIN(CIF_CREATION_DATE) dt_min, MAX(CIF_CREATION_DATE) dt_max FROM STTM_CUSTOMER) LOOP
        print_kv('  CIF le plus ancien', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  CIF le plus récent', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
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
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE (DATE_LAST_CR_ACTIVITY < ADD_MONTHS(SYSDATE, -12) OR DATE_LAST_CR_ACTIVITY IS NULL)
      AND (DATE_LAST_DR_ACTIVITY < ADD_MONTHS(SYSDATE, -12) OR DATE_LAST_DR_ACTIVITY IS NULL);
    print_kv('  Sans activité depuis > 12 mois', TO_CHAR(v_count));

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


    -- =========================================================
    -- 9. COHERENCE INTER-TABLES
    -- =========================================================
    print_section('9. COHERENCE INTER-TABLES');

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

    -- =========================================================
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
