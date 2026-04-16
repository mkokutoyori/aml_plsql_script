-- ============================================================
-- SCRIPT D'EXPLORATION REVENUE ASSURANCE (FCUBS / Oracle)
-- ------------------------------------------------------------
-- Objet : Inventorier de façon exhaustive les données utiles
--         à un audit Revenue Assurance sur Flexcube Universal
--         Banking (détection de fuites de revenus, waivers
--         abusifs, écarts calcul/collecte, anomalies
--         d'accruals, revenus non facturés, etc.).
--
-- Stratégie : chaque section explore un pan fonctionnel
--             (référentiels, transactions, prêts, accruals,
--             GL revenus, etc.) de manière indépendante.
-- ============================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count     NUMBER;
    v_num       NUMBER;
    v_sep       VARCHAR2(80) := RPAD('=', 80, '=');

    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE print_kv(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_label, 50, '.') || ' ' || NVL(p_value, 'NULL / NON RENSEIGNE'));
    END;

    PROCEDURE safe_count(p_table VARCHAR2, p_label VARCHAR2 DEFAULT NULL) IS
        l_cnt NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_table INTO l_cnt;
        print_kv(NVL(p_label, p_table), TO_CHAR(l_cnt) || ' lignes');
    EXCEPTION
        WHEN OTHERS THEN
            print_kv(NVL(p_label, p_table), 'TABLE ABSENTE / ERREUR : ' || SQLERRM);
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION REVENUE ASSURANCE — DEMARRAGE');
    DBMS_OUTPUT.PUT_LINE('>>> ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- 1. VOLUMETRIE GENERALE DES TABLES REVENUE ASSURANCE
    -- =========================================================
    print_section('1. VOLUMETRIE GENERALE DES TABLES REVENUE ASSURANCE');

    DBMS_OUTPUT.PUT_LINE('  [Référentiels revenue / charges]');
    safe_count('CSTB_AMOUNT_TAG',     'CSTB_AMOUNT_TAG (tags montants)');
    safe_count('STTM_TRN_CODE',       'STTM_TRN_CODE (codes transaction)');
    safe_count('CSTM_PRODUCT',        'CSTM_PRODUCT (produits Flexcube)');
    safe_count('LDTM_PRODUCT_MASTER', 'LDTM_PRODUCT_MASTER (produits LD)');
    safe_count('STTM_ACCOUNT_CLASS',  'STTM_ACCOUNT_CLASS (classes comptes)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptabilité & GL]');
    safe_count('ACTB_HISTORY',         'ACTB_HISTORY (écritures comptables)');
    safe_count('ACTB_ACCBAL_HISTORY',  'ACTB_ACCBAL_HISTORY (historique soldes)');
    safe_count('ACTB_VD_BAL',          'ACTB_VD_BAL (soldes date valeur)');
    safe_count('GLTB_GL_BAL',          'GLTB_GL_BAL (soldes GL)');
    safe_count('STTB_ACCOUNT',         'STTB_ACCOUNT (comptes GL)');
    safe_count('RVTB_ACC_REVAL',       'RVTB_ACC_REVAL (réévaluations FX)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Clientèle & comptes opérationnels]');
    safe_count('STTM_CUSTOMER',    'STTM_CUSTOMER');
    safe_count('STTM_CUST_ACCOUNT','STTM_CUST_ACCOUNT');
    safe_count('STTM_CUSTOMER_CAT','STTM_CUSTOMER_CAT');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Prêts consumer (module CL)]');
    safe_count('CLTB_ACCOUNT_APPS_MASTER', 'CLTB_ACCOUNT_APPS_MASTER (maître prêts)');
    safe_count('CLTB_ACCOUNT_COMPONENTS',  'CLTB_ACCOUNT_COMPONENTS (composants prêt)');
    safe_count('CLTB_ACCOUNT_SCHEDULES',   'CLTB_ACCOUNT_SCHEDULES (échéances)');
    safe_count('CLTB_AMOUNT_PAID',         'CLTB_AMOUNT_PAID (paiements)');
    safe_count('CLTB_AMOUNT_RECD',         'CLTB_AMOUNT_RECD (réceptions)');
    safe_count('CLTB_LIQ',                 'CLTB_LIQ (liquidations prêts)');
    safe_count('CLTM_PRODUCT_COMP_FRM_EXPR','CLTM_PRODUCT_COMP_FRM_EXPR (formules prod)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Contrats Loans/Deposits (module LD)]');
    safe_count('LDTB_CONTRACT_MASTER',          'LDTB_CONTRACT_MASTER');
    safe_count('LDTB_CONTRACT_BALANCE',         'LDTB_CONTRACT_BALANCE');
    safe_count('LDTB_CONTRACT_PREFERENCE',      'LDTB_CONTRACT_PREFERENCE');
    safe_count('LDTB_CONTRACT_SCHEDULES',       'LDTB_CONTRACT_SCHEDULES');
    safe_count('LDTB_CONTRACT_ICCF_CALC',       'LDTB_CONTRACT_ICCF_CALC');
    safe_count('LDTB_CONTRACT_ICCF_DETAILS',    'LDTB_CONTRACT_ICCF_DETAILS');
    safe_count('LDTB_CONTRACT_ACCRUAL_HISTORY', 'LDTB_CONTRACT_ACCRUAL_HISTORY');
    safe_count('LDTB_CONTRACT_LIQ',             'LDTB_CONTRACT_LIQ');
    safe_count('LDTB_CONTRACT_LIQ_SUMMARY',     'LDTB_CONTRACT_LIQ_SUMMARY');
    safe_count('LDTB_CONTRACT_ROLLOVER',        'LDTB_CONTRACT_ROLLOVER');
    safe_count('LDTB_CONTRACT_CONTROL',         'LDTB_CONTRACT_CONTROL');
    safe_count('LDTB_ACCRUAL_FOR_LIMITS',       'LDTB_ACCRUAL_FOR_LIMITS');
    safe_count('LDTB_COMPUTATION_HANDOFF',      'LDTB_COMPUTATION_HANDOFF');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Interest & Charges (IC) — paramétrage taux]');
    safe_count('ICTM_ACC_UDEVALS',     'ICTM_ACC_UDEVALS (taux par compte)');
    safe_count('ICTM_PR_INT_UDEVALS',  'ICTM_PR_INT_UDEVALS (taux par produit)');
    safe_count('ICTM_EXPR',            'ICTM_EXPR (expressions IC)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Autres — facilités, SI, MIS, Forex]');
    safe_count('GETM_FACILITY',            'GETM_FACILITY (facilités)');
    safe_count('SITB_CONTRACT_MASTER',     'SITB_CONTRACT_MASTER (SI)');
    safe_count('SITB_CYCLE_DETAIL',        'SITB_CYCLE_DETAIL (cycles SI)');
    safe_count('MITB_CLASS_MAPPING',       'MITB_CLASS_MAPPING (mapping MIS)');
    safe_count('CYTB_RATES_HISTORY',       'CYTB_RATES_HISTORY (taux change)');
    safe_count('CYTB_DERIVED_RATES_HISTORY','CYTB_DERIVED_RATES_HISTORY');
    safe_count('CSTB_AMOUNT_TAG',          'CSTB_AMOUNT_TAG');

    -- =========================================================
    -- FIN PROVISOIRE (sections suivantes à venir)
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> SECTION 1 TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
