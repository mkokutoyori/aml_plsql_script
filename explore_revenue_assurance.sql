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
    v_num2      NUMBER;
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
    -- 2. REFERENTIELS REVENUE — CSTB_AMOUNT_TAG / STTM_TRN_CODE
    --    / CSTM_PRODUCT / LDTM_PRODUCT_MASTER
    -- =========================================================
    print_section('2. REFERENTIELS REVENUE (tags, codes trn, produits)');

    -- 2.1 CSTB_AMOUNT_TAG : typologie des montants (intérêts, commissions, charges, taxes)
    DBMS_OUTPUT.PUT_LINE('  [2.1 CSTB_AMOUNT_TAG — Répartition par MODULE]');
    FOR r IN (
        SELECT MODULE, COUNT(DISTINCT AMOUNT_TAG) nb_tags, COUNT(*) nb
        FROM CSTB_AMOUNT_TAG
        GROUP BY MODULE ORDER BY nb DESC
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, TO_CHAR(r.nb_tags) || ' tags / ' || TO_CHAR(r.nb) || ' lignes');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.1.b Tags autorisés pour CHARGE / COMMISSION / INTEREST / TAX]');
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE CHARGE_ALLOWED = 'Y';
    print_kv('  Tags CHARGE_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE COMMISSION_ALLOWED = 'Y';
    print_kv('  Tags COMMISSION_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE INTEREST_ALLOWED = 'Y';
    print_kv('  Tags INTEREST_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE TAX_ALLOWED = 'Y';
    print_kv('  Tags TAX_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE TRACK_RECEIVABLES = 'Y';
    print_kv('  Tags TRACK_RECEIVABLES = Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT AMOUNT_TAG) INTO v_count FROM CSTB_AMOUNT_TAG WHERE UNREALISED = 'Y';
    print_kv('  Tags UNREALISED = Y (produit non réalisé)', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.1.c Répartition AMOUNT_TAG_TYPE]');
    FOR r IN (
        SELECT AMOUNT_TAG_TYPE, COUNT(*) nb FROM CSTB_AMOUNT_TAG
        GROUP BY AMOUNT_TAG_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  AMOUNT_TAG_TYPE = ' || r.AMOUNT_TAG_TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.1.d Top 15 tags par module utilisés (distinct AMOUNT_TAG)]');
    FOR r IN (
        SELECT MODULE, AMOUNT_TAG FROM (
            SELECT DISTINCT MODULE, AMOUNT_TAG
            FROM CSTB_AMOUNT_TAG
            WHERE CHARGE_ALLOWED = 'Y' OR COMMISSION_ALLOWED = 'Y' OR INTEREST_ALLOWED = 'Y'
            ORDER BY MODULE, AMOUNT_TAG
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.MODULE || ' / ' || r.AMOUNT_TAG, 'tag revenue');
    END LOOP;

    -- 2.2 STTM_TRN_CODE : codes transaction et paramètres AML / IC
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.2 STTM_TRN_CODE — Paramétrages IC / AVAIL / PENAL]');
    FOR r IN (SELECT IC_TXN_COUNT, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY IC_TXN_COUNT ORDER BY nb DESC) LOOP
        print_kv('  IC_TXN_COUNT = ' || r.IC_TXN_COUNT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT IC_TOVER_INCLUSION, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY IC_TOVER_INCLUSION ORDER BY nb DESC) LOOP
        print_kv('  IC_TOVER_INCLUSION = ' || r.IC_TOVER_INCLUSION, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT IC_BAL_INCLUSION, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY IC_BAL_INCLUSION ORDER BY nb DESC) LOOP
        print_kv('  IC_BAL_INCLUSION = ' || r.IC_BAL_INCLUSION, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT IC_PENALTY, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY IC_PENALTY ORDER BY nb DESC) LOOP
        print_kv('  IC_PENALTY = ' || r.IC_PENALTY, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT CONSIDER_FOR_ACTIVITY, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY CONSIDER_FOR_ACTIVITY ORDER BY nb DESC) LOOP
        print_kv('  CONSIDER_FOR_ACTIVITY = ' || r.CONSIDER_FOR_ACTIVITY, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT EXEMPT_ADV_INTEREST, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY EXEMPT_ADV_INTEREST ORDER BY nb DESC) LOOP
        print_kv('  EXEMPT_ADV_INTEREST = ' || r.EXEMPT_ADV_INTEREST, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.2.b Statut enregistrement des TRN_CODE]');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM STTM_TRN_CODE GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.RECORD_STAT, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.2.c Répartition PRODUCT_CAT des TRN_CODE]');
    FOR r IN (
        SELECT PRODUCT_CAT, nb FROM (
            SELECT PRODUCT_CAT, COUNT(*) nb FROM STTM_TRN_CODE
            GROUP BY PRODUCT_CAT ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT_CAT = ' || r.PRODUCT_CAT, TO_CHAR(r.nb));
    END LOOP;

    -- 2.3 CSTM_PRODUCT : produits Flexcube
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3 CSTM_PRODUCT — Produits par MODULE]');
    FOR r IN (
        SELECT MODULE, COUNT(*) nb FROM CSTM_PRODUCT
        GROUP BY MODULE ORDER BY nb DESC
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3.b Produits par PRODUCT_TYPE]');
    FOR r IN (
        SELECT PRODUCT_TYPE, COUNT(*) nb FROM CSTM_PRODUCT
        GROUP BY PRODUCT_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  PRODUCT_TYPE = ' || r.PRODUCT_TYPE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3.c Statut produits]');
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM CSTM_PRODUCT GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.RECORD_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM CSTM_PRODUCT GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3.d Produits EXPIRÉS (PRODUCT_END_DATE < SYSDATE)]');
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT
    WHERE PRODUCT_END_DATE < SYSDATE AND PRODUCT_END_DATE IS NOT NULL;
    print_kv('  Produits expirés (fin passée)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT
    WHERE PRODUCT_END_DATE IS NULL;
    print_kv('  Produits SANS date de fin', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3.e Top 15 PRODUCT_GROUP]');
    FOR r IN (
        SELECT PRODUCT_GROUP, nb FROM (
            SELECT PRODUCT_GROUP, COUNT(*) nb FROM CSTM_PRODUCT
            WHERE PRODUCT_GROUP IS NOT NULL
            GROUP BY PRODUCT_GROUP ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT_GROUP = ' || r.PRODUCT_GROUP, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.3.f Produits avec variance de taux autorisée]');
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT WHERE NORMAL_RATE_VARIANCE > 0;
    print_kv('  Avec NORMAL_RATE_VARIANCE > 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT WHERE MAXIMUM_RATE_VARIANCE > 0;
    print_kv('  Avec MAXIMUM_RATE_VARIANCE > 0', TO_CHAR(v_count));
    FOR r IN (
        SELECT ROUND(MAX(NORMAL_RATE_VARIANCE),4) mx_n,
               ROUND(MAX(MAXIMUM_RATE_VARIANCE),4) mx_m,
               ROUND(AVG(NORMAL_RATE_VARIANCE),4) av_n
        FROM CSTM_PRODUCT
    ) LOOP
        print_kv('  MAX NORMAL_RATE_VARIANCE', TO_CHAR(r.mx_n));
        print_kv('  MAX MAXIMUM_RATE_VARIANCE', TO_CHAR(r.mx_m));
        print_kv('  AVG NORMAL_RATE_VARIANCE', TO_CHAR(r.av_n));
    END LOOP;

    -- 2.4 LDTM_PRODUCT_MASTER : produits prêts/dépôts
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.4 LDTM_PRODUCT_MASTER — PRODUCT_TYPE / PAYMENT_METHOD]');
    FOR r IN (SELECT PRODUCT_TYPE, COUNT(*) nb FROM LDTM_PRODUCT_MASTER GROUP BY PRODUCT_TYPE ORDER BY nb DESC) LOOP
        print_kv('  PRODUCT_TYPE = ' || r.PRODUCT_TYPE, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT PAYMENT_METHOD, COUNT(*) nb FROM LDTM_PRODUCT_MASTER GROUP BY PAYMENT_METHOD ORDER BY nb DESC) LOOP
        print_kv('  PAYMENT_METHOD = ' || r.PAYMENT_METHOD, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT ACCRUAL_FREQUENCY, COUNT(*) nb FROM LDTM_PRODUCT_MASTER GROUP BY ACCRUAL_FREQUENCY ORDER BY nb DESC) LOOP
        print_kv('  ACCRUAL_FREQUENCY = ' || r.ACCRUAL_FREQUENCY, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT CAPITALISE, COUNT(*) nb FROM LDTM_PRODUCT_MASTER GROUP BY CAPITALISE ORDER BY nb DESC) LOOP
        print_kv('  CAPITALISE = ' || r.CAPITALISE, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT LIQUIDATION_MODE, COUNT(*) nb FROM LDTM_PRODUCT_MASTER GROUP BY LIQUIDATION_MODE ORDER BY nb DESC) LOOP
        print_kv('  LIQUIDATION_MODE = ' || r.LIQUIDATION_MODE, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.4.b Produits LD avec fonctionnalités revenu]');
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE TAX_APPLICABLE = 'Y';
    print_kv('  TAX_APPLICABLE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE BROKERAGE_APPLICABLE = 'Y';
    print_kv('  BROKERAGE_APPLICABLE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE PREPAYMENT_PENALTY = 'Y';
    print_kv('  PREPAYMENT_PENALTY = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE TRACK_ACCRUED_INTEREST = 'Y';
    print_kv('  TRACK_ACCRUED_INTEREST = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE AUTO_PROV_REQUIRED = 'Y';
    print_kv('  AUTO_PROV_REQUIRED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE BLOCK_PRODUCT = 'Y';
    print_kv('  BLOCK_PRODUCT = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE SUBSIDY_ALLOWED = 'Y';
    print_kv('  SUBSIDY_ALLOWED = Y', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [2.4.c Stats taux TRS (taux de transfert)]');
    FOR r IN (
        SELECT ROUND(MIN(TRS_RATE),4) mn, ROUND(MAX(TRS_RATE),4) mx,
               ROUND(AVG(TRS_RATE),4) av,
               COUNT(CASE WHEN TRS_RATE IS NULL OR TRS_RATE = 0 THEN 1 END) nb_zero
        FROM LDTM_PRODUCT_MASTER WHERE TRS_APPLICABLE = 'Y'
    ) LOOP
        print_kv('  TRS_RATE MIN', TO_CHAR(r.mn));
        print_kv('  TRS_RATE MAX', TO_CHAR(r.mx));
        print_kv('  TRS_RATE AVG', TO_CHAR(r.av));
        print_kv('  TRS applicable à 0 ou NULL', TO_CHAR(r.nb_zero));
    END LOOP;

    -- =========================================================
    -- FIN PROVISOIRE (sections suivantes à venir)
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- 3. ACTB_HISTORY — REVENUS & CHARGES COMPTABILISES
    --    Angle Revenue Assurance : tous les amount tags typés
    --    "revenue" (intérêts, commissions, frais, pénalités)
    --    doivent être cohérents avec le paramétrage et le GL.
    -- =========================================================
    print_section('3. ACTB_HISTORY — Revenus & charges comptabilisés');
 
    -- 3.1 Plage temporelle
    DBMS_OUTPUT.PUT_LINE('  [3.1 Plage temporelle des écritures]');
    FOR r IN (SELECT MIN(TRN_DT) dt_min, MAX(TRN_DT) dt_max FROM ACTB_HISTORY) LOOP
        print_kv('  Ecriture la plus ancienne (TRN_DT)', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  Ecriture la plus récente (TRN_DT)', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (SELECT MIN(VALUE_DT) dt_min, MAX(VALUE_DT) dt_max FROM ACTB_HISTORY) LOOP
        print_kv('  VALUE_DT min', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  VALUE_DT max', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;
 
    -- 3.2 Volumétrie par année / mois / module
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.2 Volumétrie annuelle (écritures & total LCY)]');
    FOR r IN (
        SELECT TO_CHAR(TRN_DT, 'YYYY') annee, COUNT(*) nb,
               ROUND(SUM(LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY
        WHERE TRN_DT IS NOT NULL
        GROUP BY TO_CHAR(TRN_DT, 'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee || ' — nb écritures', TO_CHAR(r.nb));
        print_kv('  ' || r.annee || ' — total LCY', TO_CHAR(r.sm));
    END LOOP;
 
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.2.b Répartition MODULE (hors AML) — total LCY par module]');
    FOR r IN (
        SELECT MODULE, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY
        GROUP BY MODULE
        ORDER BY sm DESC NULLS LAST
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, 'nb=' || TO_CHAR(r.nb) || ' | sum LCY=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.3 Focus sur les AMOUNT_TAG typés revenue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.3 Top 25 AMOUNT_TAG par volume LCY (DR+CR)]');
    FOR r IN (
        SELECT AMOUNT_TAG, nb, sm FROM (
            SELECT AMOUNT_TAG,
                   COUNT(*) nb,
                   ROUND(SUM(LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY
            GROUP BY AMOUNT_TAG
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 25
    ) LOOP
        print_kv('  TAG ' || r.AMOUNT_TAG, 'nb=' || TO_CHAR(r.nb) || ' | sum LCY=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.4 Revenus = tags marqués INTEREST/CHARGE/COMMISSION dans CSTB_AMOUNT_TAG
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.4 Revenus comptabilisés par type (jointure CSTB_AMOUNT_TAG)]');
    -- Intérêts
    SELECT COUNT(*), NVL(ROUND(SUM(h.LCY_AMOUNT),2),0)
      INTO v_count, v_num
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND t.INTEREST_ALLOWED = 'Y'
    );
    print_kv('  Ecritures INTEREST — nb', TO_CHAR(v_count));
    print_kv('  Ecritures INTEREST — sum LCY', TO_CHAR(v_num));
 
    -- Charges (frais)
    SELECT COUNT(*), NVL(ROUND(SUM(h.LCY_AMOUNT),2),0)
      INTO v_count, v_num
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND t.CHARGE_ALLOWED = 'Y'
    );
    print_kv('  Ecritures CHARGE — nb', TO_CHAR(v_count));
    print_kv('  Ecritures CHARGE — sum LCY', TO_CHAR(v_num));
 
    -- Commissions
    SELECT COUNT(*), NVL(ROUND(SUM(h.LCY_AMOUNT),2),0)
      INTO v_count, v_num
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND t.COMMISSION_ALLOWED = 'Y'
    );
    print_kv('  Ecritures COMMISSION — nb', TO_CHAR(v_count));
    print_kv('  Ecritures COMMISSION — sum LCY', TO_CHAR(v_num));
 
    -- Taxes
    SELECT COUNT(*), NVL(ROUND(SUM(h.LCY_AMOUNT),2),0)
      INTO v_count, v_num
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND t.TAX_ALLOWED = 'Y'
    );
    print_kv('  Ecritures TAX — nb', TO_CHAR(v_count));
    print_kv('  Ecritures TAX — sum LCY', TO_CHAR(v_num));
 
    -- Unrealised (produit non réalisé)
    SELECT COUNT(*), NVL(ROUND(SUM(h.LCY_AMOUNT),2),0)
      INTO v_count, v_num
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND t.UNREALISED = 'Y'
    );
    print_kv('  Ecritures UNREALISED — nb', TO_CHAR(v_count));
    print_kv('  Ecritures UNREALISED — sum LCY', TO_CHAR(v_num));
 
    -- 3.5 Revenus par année x MODULE (intérêts + commissions + charges)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.5 Revenus comptabilisés par année × MODULE]');
    FOR r IN (
        SELECT TO_CHAR(h.TRN_DT, 'YYYY') annee, h.MODULE,
               COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY h
        WHERE EXISTS (
            SELECT 1 FROM CSTB_AMOUNT_TAG t
            WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
              AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
        )
          AND h.TRN_DT IS NOT NULL
        GROUP BY TO_CHAR(h.TRN_DT, 'YYYY'), h.MODULE
        ORDER BY annee, sm DESC NULLS LAST
    ) LOOP
        print_kv('  ' || r.annee || ' / ' || r.MODULE, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.6 Revenus par branche (top 15)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.6 Top 15 AGENCES par revenus (sum LCY tags revenue)]');
    FOR r IN (
        SELECT AC_BRANCH, sm, nb FROM (
            SELECT h.AC_BRANCH, COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY h
            WHERE EXISTS (
                SELECT 1 FROM CSTB_AMOUNT_TAG t
                WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
                  AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
            )
            GROUP BY h.AC_BRANCH
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  AGENCE ' || r.AC_BRANCH, 'sum=' || TO_CHAR(r.sm) || ' | nb=' || TO_CHAR(r.nb));
    END LOOP;
 
    -- 3.7 Revenus par devise (top 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.7 Top 10 devises sur écritures revenue]');
    FOR r IN (
        SELECT AC_CCY, nb, sm_lcy, sm_fcy FROM (
            SELECT h.AC_CCY, COUNT(*) nb,
                   ROUND(SUM(h.LCY_AMOUNT),2) sm_lcy,
                   ROUND(SUM(h.FCY_AMOUNT),2) sm_fcy
            FROM ACTB_HISTORY h
            WHERE EXISTS (
                SELECT 1 FROM CSTB_AMOUNT_TAG t
                WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
                  AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
            )
            GROUP BY h.AC_CCY
            ORDER BY sm_lcy DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY ' || r.AC_CCY, 'LCY=' || TO_CHAR(r.sm_lcy) || ' | FCY=' || TO_CHAR(r.sm_fcy) || ' | nb=' || TO_CHAR(r.nb));
    END LOOP;
 
    -- 3.8 Écritures manuelles (MODULE = MM / GL / JE) - piste d'ajustements suspects
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.8 Écritures potentiellement manuelles (MODULE=GL,MM,JE)]');
    FOR r IN (
        SELECT MODULE, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY
        WHERE MODULE IN ('GL','MM','JE','MG','XL')
        GROUP BY MODULE
        ORDER BY nb DESC
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.9 Répartition DRCR_IND sur écritures revenue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.9 Sens DR/CR des écritures revenue]');
    FOR r IN (
        SELECT h.DRCR_IND, COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY h
        WHERE EXISTS (
            SELECT 1 FROM CSTB_AMOUNT_TAG t
            WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
              AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
        )
        GROUP BY h.DRCR_IND
        ORDER BY nb DESC
    ) LOOP
        print_kv('  DRCR_IND = ' || r.DRCR_IND, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.10 Contrôles de cohérence FCY / EXCH_RATE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.10 Cohérence FCY / LCY / EXCH_RATE]');
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY
    WHERE FCY_AMOUNT = 0 AND LCY_AMOUNT <> 0;
    print_kv('  FCY=0 mais LCY <> 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY
    WHERE EXCH_RATE IS NULL OR EXCH_RATE = 0;
    print_kv('  EXCH_RATE NULL / 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY
    WHERE FCY_AMOUNT > 0 AND LCY_AMOUNT > 0
      AND EXCH_RATE IS NOT NULL AND EXCH_RATE > 0
      AND ABS(FCY_AMOUNT * EXCH_RATE - LCY_AMOUNT) > 1;
    print_kv('  Ecart FCY*EXCH_RATE vs LCY > 1 unité', TO_CHAR(v_count));
 
    -- 3.11 Top 15 TRN_CODE pour les tags revenue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.11 Top 15 TRN_CODE sur écritures revenue]');
    FOR r IN (
        SELECT TRN_CODE, nb, sm FROM (
            SELECT h.TRN_CODE, COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY h
            WHERE EXISTS (
                SELECT 1 FROM CSTB_AMOUNT_TAG t
                WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
                  AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
            )
            GROUP BY h.TRN_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  TRN_CODE ' || r.TRN_CODE, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.12 Top 15 PRODUCT générateurs de revenu
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.12 Top 15 PRODUCT par revenus générés]');
    FOR r IN (
        SELECT PRODUCT, nb, sm FROM (
            SELECT h.PRODUCT, COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY h
            WHERE EXISTS (
                SELECT 1 FROM CSTB_AMOUNT_TAG t
                WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
                  AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
            )
            GROUP BY h.PRODUCT
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT ' || r.PRODUCT, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.13 Top 10 USER_ID passant des écritures revenue (back-office / système)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.13 Top 10 USER_ID sur écritures revenue]');
    FOR r IN (
        SELECT USER_ID, nb, sm FROM (
            SELECT h.USER_ID, COUNT(*) nb, ROUND(SUM(h.LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY h
            WHERE EXISTS (
                SELECT 1 FROM CSTB_AMOUNT_TAG t
                WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
                  AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
            )
            GROUP BY h.USER_ID
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  USER ' || r.USER_ID, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.14 Écritures reversées (EVENT = REVR / RVRV / DRVR)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.14 Écritures de reversal (impact revenue négatif)]');
    FOR r IN (
        SELECT EVENT, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
        FROM ACTB_HISTORY
        WHERE EVENT LIKE '%REV%' OR EVENT LIKE '%RVR%'
        GROUP BY EVENT
        ORDER BY nb DESC
    ) LOOP
        print_kv('  EVENT = ' || r.EVENT, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;
 
    -- 3.15 Rapprochement GL d'origine ORIG_PNL_GL (si existe)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [3.15 Top 10 ORIG_PNL_GL — comptes résultat utilisés]');
    FOR r IN (
        SELECT ORIG_PNL_GL, nb, sm FROM (
            SELECT ORIG_PNL_GL, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
            FROM ACTB_HISTORY
            WHERE ORIG_PNL_GL IS NOT NULL AND ORIG_PNL_GL <> ' '
            GROUP BY ORIG_PNL_GL
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ORIG_PNL_GL ' || r.ORIG_PNL_GL, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- =========================================================
    -- 4. CLTB_ACCOUNT_COMPONENTS — COMPOSANTS DE PRETS & WAIVERS
    --    Enjeu RA : les waivers de composants d'intérêts / frais
    --    sur les prêts Consumer Loans constituent la 1ère source
    --    de revenue leakage. Cette section quantifie les waivers,
    --    les composants capitalisés, les SPL_INTEREST (taux
    --    négocié), et les bases de calcul non standard.
    -- =========================================================
    print_section('4. CLTB_ACCOUNT_COMPONENTS — Composants de prêts & waivers');

    -- 4.1 Volumétrie globale
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Total composants', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Comptes distincts avec composants', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT COMPONENT_NAME) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Noms de composants distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT COMPONENT_CCY) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Devises composants distinctes', TO_CHAR(v_count));

    -- 4.2 Répartition par COMPONENT_TYPE (INTEREST/PRINCIPAL/CHARGE/PENALTY...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.2 Répartition par COMPONENT_TYPE]');
    FOR r IN (
        SELECT COMPONENT_TYPE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY COMPONENT_TYPE
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TYPE = ' || NVL(r.COMPONENT_TYPE, '<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- 4.3 Top 25 noms de composants (pour identifier les interests/frais)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.3 Top 25 COMPONENT_NAME]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY COMPONENT_NAME
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 25
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME, '<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- 4.4 ALERTE RA : waivers (WAIVE = 'Y')
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.4 ** ALERTE RA ** — composants waivés (WAIVE = Y)]');
    FOR r IN (
        SELECT NVL(WAIVE, '<NULL>') wv, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(WAIVE, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  WAIVE = ' || r.wv, TO_CHAR(r.nb));
    END LOOP;

    -- 4.4.b Détail waivers par COMPONENT_NAME
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.4.b Top 25 composants waivés par COMPONENT_NAME]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            WHERE WAIVE = 'Y'
            GROUP BY COMPONENT_NAME
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 25
    ) LOOP
        print_kv('  WAIVED ' || NVL(r.COMPONENT_NAME, '<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- 4.4.c Waivers par COMPONENT_TYPE (enjeu leakage typé)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.4.c Waivers par COMPONENT_TYPE]');
    FOR r IN (
        SELECT NVL(COMPONENT_TYPE,'<NULL>') ct, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        WHERE WAIVE = 'Y'
        GROUP BY NVL(COMPONENT_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  WAIVED TYPE = ' || r.ct, TO_CHAR(r.nb));
    END LOOP;

    -- 4.4.d Top 15 comptes avec le plus de composants waivés
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.4.d Top 15 ACCOUNT_NUMBER avec composants waivés]');
    FOR r IN (
        SELECT ACCOUNT_NUMBER, nb FROM (
            SELECT ACCOUNT_NUMBER, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            WHERE WAIVE = 'Y'
            GROUP BY ACCOUNT_NUMBER
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Compte ' || r.ACCOUNT_NUMBER, 'nb composants waivés = ' || TO_CHAR(r.nb));
    END LOOP;

    -- 4.5 Composants capitalisés (interest ajouté au principal — suivi IRR)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5 Composants CAPITALIZED (capitalisation intérêts)]');
    FOR r IN (
        SELECT NVL(CAPITALIZED, '<NULL>') cp, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(CAPITALIZED, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CAPITALIZED = ' || r.cp, TO_CHAR(r.nb));
    END LOOP;

    -- 4.6 SPL_INTEREST (taux spécial négocié — fréquent vecteur de leakage)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.6 ** ALERTE RA ** — SPL_INTEREST (taux négocié / override)]');
    FOR r IN (
        SELECT NVL(SPL_INTEREST, '<NULL>') si, COUNT(*) nb,
               NVL(ROUND(AVG(SPL_INTEREST_AMT),4),0) avg_amt,
               NVL(ROUND(MIN(SPL_INTEREST_AMT),4),0) min_amt,
               NVL(ROUND(MAX(SPL_INTEREST_AMT),4),0) max_amt
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(SPL_INTEREST, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  SPL_INTEREST = ' || r.si, 'nb=' || TO_CHAR(r.nb) ||
                 ' | avg_amt=' || TO_CHAR(r.avg_amt) ||
                 ' | min=' || TO_CHAR(r.min_amt) ||
                 ' | max=' || TO_CHAR(r.max_amt));
    END LOOP;

    -- 4.7 IRR_APPLICABLE (calcul rendement effectif — obligatoire IFRS9)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.7 IRR_APPLICABLE (rendement effectif IFRS9)]');
    FOR r IN (
        SELECT NVL(IRR_APPLICABLE, '<NULL>') ir, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(IRR_APPLICABLE, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  IRR_APPLICABLE = ' || r.ir, TO_CHAR(r.nb));
    END LOOP;

    -- 4.8 Base de calcul DAYS_MTH x DAYS_YEAR (impact direct sur revenus d'intérêts)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.8 Base de calcul intérêts — DAYS_MTH x DAYS_YEAR]');
    FOR r IN (
        SELECT NVL(DAYS_MTH,'<NULL>') dm, NVL(DAYS_YEAR,'<NULL>') dy, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(DAYS_MTH,'<NULL>'), NVL(DAYS_YEAR,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  DAYS_MTH=' || r.dm || ' / DAYS_YEAR=' || r.dy, TO_CHAR(r.nb));
    END LOOP;

    -- 4.9 MAIN_COMPONENT (principal vs accessoires)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.9 Répartition MAIN_COMPONENT]');
    FOR r IN (
        SELECT NVL(MAIN_COMPONENT, '<NULL>') mc, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(MAIN_COMPONENT, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  MAIN_COMPONENT = ' || r.mc, TO_CHAR(r.nb));
    END LOOP;

    -- 4.10 LIQUIDATION_MODE (auto vs manual — waivers manuels plus probables)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.10 LIQUIDATION_MODE des composants]');
    FOR r IN (
        SELECT NVL(LIQUIDATION_MODE, '<NULL>') lm, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(LIQUIDATION_MODE, '<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  LIQUIDATION_MODE = ' || r.lm, TO_CHAR(r.nb));
    END LOOP;

    -- 4.11 COMPONENT_CCY vs SETTLEMENT_CCY — incohérence = FX leakage
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.11 ** ALERTE RA ** — COMPONENT_CCY != SETTLEMENT_CCY (FX)]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_COMPONENTS
    WHERE COMPONENT_CCY <> SETTLEMENT_CCY
      AND COMPONENT_CCY IS NOT NULL
      AND SETTLEMENT_CCY IS NOT NULL;
    print_kv('  Composants avec CCY différente du settlement', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.11.b Top paires (COMPONENT_CCY, SETTLEMENT_CCY)]');
    FOR r IN (
        SELECT cc, sc, nb FROM (
            SELECT NVL(COMPONENT_CCY,'<NULL>') cc, NVL(SETTLEMENT_CCY,'<NULL>') sc, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            WHERE COMPONENT_CCY <> SETTLEMENT_CCY
              AND COMPONENT_CCY IS NOT NULL
              AND SETTLEMENT_CCY IS NOT NULL
            GROUP BY NVL(COMPONENT_CCY,'<NULL>'), NVL(SETTLEMENT_CCY,'<NULL>')
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.cc || ' -> ' || r.sc, TO_CHAR(r.nb));
    END LOOP;

    -- 4.12 Taux négocié vs taux d'origine (NEGOTIATED_RATE vs ORG_EXCH_RATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.12 ** ALERTE RA ** — écart EXCHANGE_RATE vs NEGOTIATED_RATE]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_COMPONENTS
    WHERE NEGOTIATED_RATE IS NOT NULL
      AND EXCHANGE_RATE IS NOT NULL
      AND NEGOTIATED_RATE <> EXCHANGE_RATE;
    print_kv('  Composants avec taux négocié différent du taux standard', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_COMPONENTS
    WHERE NEGOTIATION_REF_NO IS NOT NULL
      AND TRIM(NEGOTIATION_REF_NO) IS NOT NULL;
    print_kv('  Composants avec référence de négociation FX', TO_CHAR(v_count));

    -- 4.13 PENAL_BASIS_COMP (composants de base pénalité — leakage si mal paramétré)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.13 PENAL_BASIS_COMP — composants bases de pénalités]');
    FOR r IN (
        SELECT NVL(PENAL_BASIS_COMP,'<NULL>') pb, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(PENAL_BASIS_COMP,'<NULL>')
        HAVING COUNT(*) > 0
        ORDER BY nb DESC
    ) LOOP
        print_kv('  PENAL_BASIS = ' || r.pb, TO_CHAR(r.nb));
    END LOOP;

    -- 4.14 FUND_DURING_INIT / FUND_DURING_ROLL (impact sur revenus)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.14 FUND_DURING_INIT vs FUND_DURING_ROLL]');
    FOR r IN (
        SELECT NVL(FUND_DURING_INIT,'<NULL>') fi, NVL(FUND_DURING_ROLL,'<NULL>') fr, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY NVL(FUND_DURING_INIT,'<NULL>'), NVL(FUND_DURING_ROLL,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  INIT=' || r.fi || ' / ROLL=' || r.fr, TO_CHAR(r.nb));
    END LOOP;

    -- 4.15 Croisement waivers avec comptes actifs / clos (CLTB_ACCOUNT_APPS_MASTER)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.15 Croisement waivers x statut prêt (CLTB_ACCOUNT_APPS_MASTER)]');
    FOR r IN (
        SELECT NVL(m.USER_DEFINED_STATUS,'<NULL>') st, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS c
        JOIN CLTB_ACCOUNT_APPS_MASTER m
          ON m.ACCOUNT_NUMBER = c.ACCOUNT_NUMBER
         AND m.BRANCH_CODE = c.BRANCH_CODE
        WHERE c.WAIVE = 'Y'
        GROUP BY NVL(m.USER_DEFINED_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  STATUS=' || r.st || ' | nb composants waivés', TO_CHAR(r.nb));
    END LOOP;

    -- =========================================================
    -- 5. CLTB_ACCOUNT_SCHEDULES — ECHEANCES, OVERDUE & ACCRUALS
    --    Enjeu RA : les échéances calculées (AMOUNT_DUE) doivent
    --    être liquidées intégralement. Tout montant :
    --      - AMOUNT_OVERDUE > 0 non suivi,
    --      - AMOUNT_WAIVED > 0,
    --      - WRITEOFF_AMT > 0,
    --      - ACCRUED_AMOUNT non comptabilisé,
    --      - SUSP_AMT_DUE sans contrepartie,
    --    constitue un risque de revenue leakage.
    -- =========================================================
    print_section('5. CLTB_ACCOUNT_SCHEDULES — Echeances, overdue & accruals');

    -- 5.1 Volumétrie globale
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Total échéances', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Comptes distincts avec échéances', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT COMPONENT_NAME) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Composants échéanciers distincts', TO_CHAR(v_count));

    -- 5.2 Plage temporelle des échéances
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.2 Plage temporelle des échéances]');
    FOR r IN (SELECT MIN(SCHEDULE_DUE_DATE) dmin, MAX(SCHEDULE_DUE_DATE) dmax,
                     MIN(SCHEDULE_ST_DATE) smin, MAX(SCHEDULE_ST_DATE) smax
              FROM CLTB_ACCOUNT_SCHEDULES) LOOP
        print_kv('  SCHEDULE_DUE_DATE min', TO_CHAR(r.dmin, 'DD/MM/YYYY'));
        print_kv('  SCHEDULE_DUE_DATE max', TO_CHAR(r.dmax, 'DD/MM/YYYY'));
        print_kv('  SCHEDULE_ST_DATE min', TO_CHAR(r.smin, 'DD/MM/YYYY'));
        print_kv('  SCHEDULE_ST_DATE max', TO_CHAR(r.smax, 'DD/MM/YYYY'));
    END LOOP;

    -- 5.3 Répartition par SCHEDULE_TYPE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.3 Répartition SCHEDULE_TYPE (I=Intérêt, P=Principal...)]');
    FOR r IN (
        SELECT NVL(SCHEDULE_TYPE,'<NULL>') st, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_DUE),2),0) due_tot,
               NVL(ROUND(SUM(AMOUNT_SETTLED),2),0) settled_tot
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY NVL(SCHEDULE_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TYPE=' || r.st, 'nb=' || TO_CHAR(r.nb) ||
                 ' | due=' || TO_CHAR(r.due_tot) ||
                 ' | settled=' || TO_CHAR(r.settled_tot));
    END LOOP;

    -- 5.4 SCH_STATUS (ouvert, liquidé, etc.)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.4 Répartition SCH_STATUS]');
    FOR r IN (
        SELECT NVL(SCH_STATUS,'<NULL>') ss, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY NVL(SCH_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  SCH_STATUS=' || r.ss, TO_CHAR(r.nb));
    END LOOP;

    -- 5.5 SCHEDULE_FLAG (Normal/Special)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.5 Répartition SCHEDULE_FLAG]');
    FOR r IN (
        SELECT NVL(SCHEDULE_FLAG,'<NULL>') sf, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY NVL(SCHEDULE_FLAG,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  SCHEDULE_FLAG=' || r.sf, TO_CHAR(r.nb));
    END LOOP;

    -- 5.6 ** ALERTE RA ** — OVERDUE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6 ** ALERTE RA ** — Echéances avec AMOUNT_OVERDUE > 0]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_OVERDUE),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE AMOUNT_OVERDUE > 0;
    print_kv('  Nb échéances overdue', TO_CHAR(v_count));
    print_kv('  Total overdue (CCY composant)', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6.b Overdue par COMPONENT_NAME]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(AMOUNT_OVERDUE),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_OVERDUE > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6.c Ancienneté overdue (bucket jours)]');
    FOR r IN (
        SELECT bucket, nb, sm FROM (
            SELECT CASE
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 30 THEN '01_0-30j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 60 THEN '02_31-60j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 90 THEN '03_61-90j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 180 THEN '04_91-180j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 365 THEN '05_181-365j'
                     ELSE '06_>365j'
                   END bucket,
                   COUNT(*) nb,
                   ROUND(SUM(AMOUNT_OVERDUE),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_OVERDUE > 0
            GROUP BY CASE
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 30 THEN '01_0-30j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 60 THEN '02_31-60j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 90 THEN '03_61-90j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 180 THEN '04_91-180j'
                     WHEN TRUNC(SYSDATE) - SCHEDULE_DUE_DATE <= 365 THEN '05_181-365j'
                     ELSE '06_>365j'
                   END
        ) ORDER BY bucket
    ) LOOP
        print_kv('  Ancienneté ' || r.bucket, 'nb=' || TO_CHAR(r.nb) || ' | sum overdue=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.7 ** ALERTE RA ** — WAIVER_FLAG & AMOUNT_WAIVED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.7 ** ALERTE RA ** — WAIVER_FLAG & AMOUNT_WAIVED]');
    FOR r IN (
        SELECT NVL(WAIVER_FLAG,'<NULL>') wf, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_WAIVED),2),0) sm
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY NVL(WAIVER_FLAG,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  WAIVER_FLAG=' || r.wf, 'nb=' || TO_CHAR(r.nb) || ' | sum waived=' || TO_CHAR(r.sm));
    END LOOP;

    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_WAIVED),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE AMOUNT_WAIVED > 0;
    print_kv('  Echéances avec AMOUNT_WAIVED > 0', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_WAIVED', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.7.b Top 20 composants avec AMOUNT_WAIVED > 0]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(AMOUNT_WAIVED),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_WAIVED > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.8 ** ALERTE RA ** — WRITEOFF_AMT (abandon créance)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.8 ** ALERTE RA ** — WRITEOFF_AMT]');
    SELECT COUNT(*), NVL(ROUND(SUM(WRITEOFF_AMT),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE WRITEOFF_AMT > 0;
    print_kv('  Echéances avec WRITEOFF_AMT > 0', TO_CHAR(v_count));
    print_kv('  Cumul WRITEOFF', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.8.b WRITEOFF par composant]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(WRITEOFF_AMT),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE WRITEOFF_AMT > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.9 ACCRUED_AMOUNT vs AMOUNT_DUE (revenus courus mais non liquidés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.9 ACCRUED_AMOUNT — intérêts courus non liquidés]');
    SELECT COUNT(*), NVL(ROUND(SUM(ACCRUED_AMOUNT),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE ACCRUED_AMOUNT > 0;
    print_kv('  Echéances avec ACCRUED_AMOUNT > 0', TO_CHAR(v_count));
    print_kv('  Cumul ACCRUED', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.9.b Cumul accrued par COMPONENT_NAME]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(ACCRUED_AMOUNT),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE ACCRUED_AMOUNT > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.10 Suspense (SUSP_AMT_DUE/SETTLED/LCY)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.10 ** ALERTE RA ** — Comptes de suspense]');
    SELECT COUNT(*), NVL(ROUND(SUM(SUSP_AMT_DUE),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SUSP_AMT_DUE > 0;
    print_kv('  Echéances avec SUSP_AMT_DUE > 0', TO_CHAR(v_count));
    print_kv('  Cumul SUSP_AMT_DUE', TO_CHAR(v_num));

    SELECT COUNT(*), NVL(ROUND(SUM(SUSP_AMT_SETTLED),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SUSP_AMT_SETTLED > 0;
    print_kv('  Echéances avec SUSP_AMT_SETTLED > 0', TO_CHAR(v_count));
    print_kv('  Cumul SUSP_AMT_SETTLED', TO_CHAR(v_num));

    SELECT NVL(ROUND(SUM(SUSP_AMT_LCY),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Cumul SUSP_AMT_LCY global', TO_CHAR(v_num));

    -- 5.11 Cohérence AMOUNT_DUE = AMOUNT_SETTLED + AMOUNT_OVERDUE + AMOUNT_WAIVED + WRITEOFF
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.11 ** ALERTE RA ** — Incohérence AMOUNT_DUE vs composantes]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE ABS(NVL(AMOUNT_DUE,0)
            - NVL(AMOUNT_SETTLED,0)
            - NVL(AMOUNT_OVERDUE,0)
            - NVL(AMOUNT_WAIVED,0)
            - NVL(WRITEOFF_AMT,0)) > 0.01;
    print_kv('  Echéances où DUE != SETTLED+OVERDUE+WAIVED+WRITEOFF', TO_CHAR(v_count));

    -- 5.12 Echéances avec ORIG_AMOUNT_DUE != AMOUNT_DUE (ré-ajustement AMT_READJUSTED)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.12 Ré-ajustements d''échéances (ADJ_AMOUNT / AMOUNT_READJUSTED)]');
    SELECT COUNT(*), NVL(ROUND(SUM(ADJ_AMOUNT),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE NVL(ADJ_AMOUNT,0) <> 0;
    print_kv('  Echéances ADJ_AMOUNT != 0', TO_CHAR(v_count));
    print_kv('  Cumul ADJ_AMOUNT', TO_CHAR(v_num));

    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_READJUSTED),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE NVL(AMOUNT_READJUSTED,0) <> 0;
    print_kv('  Echéances AMOUNT_READJUSTED != 0', TO_CHAR(v_count));
    print_kv('  Cumul READJUSTED', TO_CHAR(v_num));

    -- 5.13 Echéances capitalisées (CAPITALIZED='Y')
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.13 Echéances CAPITALIZED=Y]');
    FOR r IN (
        SELECT NVL(CAPITALIZED,'<NULL>') cp, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_DUE),2),0) sm
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY NVL(CAPITALIZED,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CAPITALIZED=' || r.cp, 'nb=' || TO_CHAR(r.nb) || ' | sum DUE=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.14 Volumétrie annuelle des échéances (par année de due date)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.14 Volumétrie par année de SCHEDULE_DUE_DATE]');
    FOR r IN (
        SELECT annee, nb, due, settled, overdue FROM (
            SELECT TO_CHAR(SCHEDULE_DUE_DATE,'YYYY') annee,
                   COUNT(*) nb,
                   ROUND(SUM(AMOUNT_DUE),2) due,
                   ROUND(SUM(AMOUNT_SETTLED),2) settled,
                   ROUND(SUM(AMOUNT_OVERDUE),2) overdue
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE SCHEDULE_DUE_DATE IS NOT NULL
            GROUP BY TO_CHAR(SCHEDULE_DUE_DATE,'YYYY')
            ORDER BY annee
        )
    ) LOOP
        print_kv('  ' || r.annee || ' — nb', TO_CHAR(r.nb));
        print_kv('  ' || r.annee || '   DUE', TO_CHAR(r.due));
        print_kv('  ' || r.annee || '   SETTLED', TO_CHAR(r.settled));
        print_kv('  ' || r.annee || '   OVERDUE', TO_CHAR(r.overdue));
    END LOOP;

    -- 5.15 Top 15 comptes par AMOUNT_OVERDUE (concentration)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.15 Top 15 ACCOUNT_NUMBER par cumul AMOUNT_OVERDUE]');
    FOR r IN (
        SELECT ACCOUNT_NUMBER, sm, nb FROM (
            SELECT ACCOUNT_NUMBER, ROUND(SUM(AMOUNT_OVERDUE),2) sm, COUNT(*) nb
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_OVERDUE > 0
            GROUP BY ACCOUNT_NUMBER
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Compte ' || r.ACCOUNT_NUMBER, 'nb=' || TO_CHAR(r.nb) || ' | overdue=' || TO_CHAR(r.sm));
    END LOOP;

    -- =========================================================
    -- 6. CLTB_AMOUNT_PAID / CLTB_AMOUNT_RECD / CLTB_LIQ
    --    Paiements et liquidations des échéances de prêts.
    --    Enjeu RA : s'assurer que tout paiement reçu est :
    --      - correctement affecté au composant revenu attendu,
    --      - non waivé à tort (AMOUNT_WAIVED dans CLTB_AMOUNT_PAID),
    --      - non reversé discrètement (REV_MAKER_ID dans CLTB_LIQ),
    --      - liquidé en temps voulu (écart DUE_DATE / PAID_DATE).
    -- =========================================================
    print_section('6. CLTB_AMOUNT_PAID / RECD / LIQ — Paiements & liquidations');

    -- 6.1 CLTB_AMOUNT_PAID — volumétrie globale
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_PAID),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_PAID;
    print_kv('  Total paiements (CLTB_AMOUNT_PAID)', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_PAID', TO_CHAR(v_num));

    SELECT NVL(ROUND(SUM(AMOUNT_WAIVED),2),0),
           NVL(ROUND(SUM(AMOUNT_CAPITALIZED),2),0)
      INTO v_num, v_num2
    FROM CLTB_AMOUNT_PAID;
    print_kv('  Cumul AMOUNT_WAIVED (AMOUNT_PAID)', TO_CHAR(v_num));
    print_kv('  Cumul AMOUNT_CAPITALIZED (AMOUNT_PAID)', TO_CHAR(v_num2));

    -- 6.2 Plage temporelle
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.2 Plage temporelle des paiements]');
    FOR r IN (SELECT MIN(PAID_DATE) dmin, MAX(PAID_DATE) dmax,
                     MIN(DUE_DATE) ddmin, MAX(DUE_DATE) ddmax
              FROM CLTB_AMOUNT_PAID) LOOP
        print_kv('  PAID_DATE min / max', TO_CHAR(r.dmin,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.dmax,'DD/MM/YYYY'));
        print_kv('  DUE_DATE  min / max', TO_CHAR(r.ddmin,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.ddmax,'DD/MM/YYYY'));
    END LOOP;

    -- 6.3 Répartition PAID_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.3 Répartition PAID_STATUS]');
    FOR r IN (
        SELECT NVL(PAID_STATUS,'<NULL>') ps, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_PAID),2),0) sm
        FROM CLTB_AMOUNT_PAID
        GROUP BY NVL(PAID_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  PAID_STATUS=' || r.ps, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.4 Top 20 composants payés (par cumul AMOUNT_PAID)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4 Top 20 COMPONENT_NAME par AMOUNT_PAID]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(AMOUNT_PAID),2) sm
            FROM CLTB_AMOUNT_PAID
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.5 ** ALERTE RA ** — Waivers au paiement (AMOUNT_WAIVED > 0)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.5 ** ALERTE RA ** — AMOUNT_WAIVED > 0 dans CLTB_AMOUNT_PAID]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_WAIVED),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_PAID
    WHERE AMOUNT_WAIVED > 0;
    print_kv('  Paiements avec AMOUNT_WAIVED > 0', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_WAIVED', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.5.b Top 20 composants waivés au paiement]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT COMPONENT_NAME, COUNT(*) nb, ROUND(SUM(AMOUNT_WAIVED),2) sm
            FROM CLTB_AMOUNT_PAID
            WHERE AMOUNT_WAIVED > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || NVL(r.COMPONENT_NAME,'<NULL>'), 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.5.c Top 15 comptes avec cumul AMOUNT_WAIVED > 0]');
    FOR r IN (
        SELECT ACCOUNT_NUMBER, sm, nb FROM (
            SELECT ACCOUNT_NUMBER, ROUND(SUM(AMOUNT_WAIVED),2) sm, COUNT(*) nb
            FROM CLTB_AMOUNT_PAID
            WHERE AMOUNT_WAIVED > 0
            GROUP BY ACCOUNT_NUMBER
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Compte ' || r.ACCOUNT_NUMBER, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.6 AMOUNT_CAPITALIZED > 0 (capitalisation — à rapprocher du principal)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.6 AMOUNT_CAPITALIZED > 0 (capitalisation intérêts)]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_CAPITALIZED),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_PAID
    WHERE AMOUNT_CAPITALIZED > 0;
    print_kv('  Paiements avec AMOUNT_CAPITALIZED > 0', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_CAPITALIZED', TO_CHAR(v_num));

    -- 6.7 Ecart DUE_DATE vs PAID_DATE (retards à la liquidation)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.7 Retards PAID_DATE - DUE_DATE (bucket jours)]');
    FOR r IN (
        SELECT bucket, nb, sm FROM (
            SELECT CASE
                     WHEN PAID_DATE - DUE_DATE <= 0 THEN '01_le_jour_ou_avant'
                     WHEN PAID_DATE - DUE_DATE <= 5 THEN '02_1-5j'
                     WHEN PAID_DATE - DUE_DATE <= 15 THEN '03_6-15j'
                     WHEN PAID_DATE - DUE_DATE <= 30 THEN '04_16-30j'
                     WHEN PAID_DATE - DUE_DATE <= 90 THEN '05_31-90j'
                     ELSE '06_>90j'
                   END bucket,
                   COUNT(*) nb,
                   ROUND(SUM(AMOUNT_PAID),2) sm
            FROM CLTB_AMOUNT_PAID
            WHERE PAID_DATE IS NOT NULL AND DUE_DATE IS NOT NULL
            GROUP BY CASE
                     WHEN PAID_DATE - DUE_DATE <= 0 THEN '01_le_jour_ou_avant'
                     WHEN PAID_DATE - DUE_DATE <= 5 THEN '02_1-5j'
                     WHEN PAID_DATE - DUE_DATE <= 15 THEN '03_6-15j'
                     WHEN PAID_DATE - DUE_DATE <= 30 THEN '04_16-30j'
                     WHEN PAID_DATE - DUE_DATE <= 90 THEN '05_31-90j'
                     ELSE '06_>90j'
                   END
        ) ORDER BY bucket
    ) LOOP
        print_kv('  Retard ' || r.bucket, 'nb=' || TO_CHAR(r.nb) || ' | sum paid=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.8 Volumétrie annuelle des paiements
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.8 Volumétrie annuelle par PAID_DATE]');
    FOR r IN (
        SELECT TO_CHAR(PAID_DATE,'YYYY') annee,
               COUNT(*) nb,
               ROUND(SUM(AMOUNT_PAID),2) sm_paid,
               ROUND(SUM(AMOUNT_WAIVED),2) sm_wv
        FROM CLTB_AMOUNT_PAID
        WHERE PAID_DATE IS NOT NULL
        GROUP BY TO_CHAR(PAID_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee || ' — nb', TO_CHAR(r.nb));
        print_kv('  ' || r.annee || '   PAID', TO_CHAR(r.sm_paid));
        print_kv('  ' || r.annee || '   WAIVED', TO_CHAR(r.sm_wv));
    END LOOP;

    -- 6.9 CLTB_AMOUNT_RECD — reçus entrants (versus amount_paid sorti du compte)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.9 CLTB_AMOUNT_RECD — encaissements]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_RECD),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_RECD;
    print_kv('  Nb enregistrements', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_RECD', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.9.b RECD_TYPE]');
    FOR r IN (
        SELECT NVL(RECD_TYPE,'<NULL>') rt, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_RECD),2),0) sm
        FROM CLTB_AMOUNT_RECD
        GROUP BY NVL(RECD_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  RECD_TYPE=' || r.rt, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.10 CLTB_LIQ — volumétrie globale des liquidations
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.10 CLTB_LIQ — événements de liquidation]');
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ;
    print_kv('  Nb événements liquidation', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_LIQ;
    print_kv('  Comptes distincts liquidés', TO_CHAR(v_count));

    -- 6.11 PAYMENT_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.11 Répartition PAYMENT_STATUS]');
    FOR r IN (
        SELECT NVL(PAYMENT_STATUS,'<NULL>') ps, COUNT(*) nb
        FROM CLTB_LIQ
        GROUP BY NVL(PAYMENT_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  PAYMENT_STATUS=' || r.ps, TO_CHAR(r.nb));
    END LOOP;

    -- 6.12 AUTH_STAT (autorisées vs non) & SIMULATED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.12 AUTH_STAT & SIMULATED]');
    FOR r IN (
        SELECT NVL(AUTH_STAT,'<NULL>') au, NVL(SIMULATED,'<NULL>') si, COUNT(*) nb
        FROM CLTB_LIQ
        GROUP BY NVL(AUTH_STAT,'<NULL>'), NVL(SIMULATED,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  AUTH_STAT=' || r.au || ' / SIMULATED=' || r.si, TO_CHAR(r.nb));
    END LOOP;

    -- 6.13 ** ALERTE RA ** — Liquidations reversées (REV_MAKER_ID non null)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.13 ** ALERTE RA ** — Liquidations reversées]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_LIQ
    WHERE REV_MAKER_ID IS NOT NULL;
    print_kv('  Liquidations avec REV_MAKER_ID non null', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.13.b Top 10 REV_MAKER_ID]');
    FOR r IN (
        SELECT REV_MAKER_ID, nb FROM (
            SELECT REV_MAKER_ID, COUNT(*) nb
            FROM CLTB_LIQ
            WHERE REV_MAKER_ID IS NOT NULL
            GROUP BY REV_MAKER_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  REV_MAKER_ID=' || r.REV_MAKER_ID, TO_CHAR(r.nb));
    END LOOP;

    -- 6.14 Top 10 MAKER_ID / CHECKER_ID (back-office concentration)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.14 Top 10 MAKER_ID (créateurs de liquidations)]');
    FOR r IN (
        SELECT MAKER_ID, nb FROM (
            SELECT MAKER_ID, COUNT(*) nb
            FROM CLTB_LIQ
            GROUP BY MAKER_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  MAKER_ID=' || NVL(r.MAKER_ID,'<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.14.b Top 10 CHECKER_ID (autorisateurs)]');
    FOR r IN (
        SELECT CHECKER_ID, nb FROM (
            SELECT CHECKER_ID, COUNT(*) nb
            FROM CLTB_LIQ
            GROUP BY CHECKER_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CHECKER_ID=' || NVL(r.CHECKER_ID,'<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- 6.15 ** ALERTE RA ** — MAKER_ID = CHECKER_ID (self-authorization)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.15 ** ALERTE RA ** — MAKER_ID = CHECKER_ID (auto-authentication)]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_LIQ
    WHERE MAKER_ID = CHECKER_ID
      AND MAKER_ID IS NOT NULL;
    print_kv('  Liquidations auto-authentifiées', TO_CHAR(v_count));

    -- 6.16 PREPMNT_RECOMP_BASIS (impact recalcul intérêts prepayment)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.16 Base de recompute prepayment (PREPMNT_RECOMP_BASIS)]');
    FOR r IN (
        SELECT NVL(PREPMNT_RECOMP_BASIS,'<NULL>') pb, COUNT(*) nb
        FROM CLTB_LIQ
        GROUP BY NVL(PREPMNT_RECOMP_BASIS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  PREPMNT_RECOMP_BASIS=' || r.pb, TO_CHAR(r.nb));
    END LOOP;

    -- 6.17 ** ALERTE RA ** — AMOUNT_EXCESS (trop-perçu non ventilé)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.17 ** ALERTE RA ** — AMOUNT_EXCESS > 0 (surpaiements)]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_EXCESS),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ
    WHERE AMOUNT_EXCESS > 0;
    print_kv('  Liquidations avec AMOUNT_EXCESS > 0', TO_CHAR(v_count));
    print_kv('  Cumul AMOUNT_EXCESS', TO_CHAR(v_num));

    -- =========================================================
    -- 7. CLTB_ACCOUNT_APPS_MASTER — LIFECYCLE DES PRETS
    --    Vue maître des prêts CL. Enjeux RA :
    --      - STOP_ACCRUALS='Y' : arrêts d'accrual (perte revenus),
    --      - DELINQUENCY_STATUS : impact classement IFRS9,
    --      - BOOK_UNEARNED_INTEREST / UPFRONT_PROFIT_BOOKED : produits
    --        constatés d'avance,
    --      - AMOUNT_FINANCED vs AMOUNT_DISBURSED : non-déboursements,
    --      - AMEND_PAST_PAID_SCHEDULE='Y' : modifications post-paiement,
    --      - MAKER=CHECKER : défaut de 4 yeux.
    -- =========================================================
    print_section('7. CLTB_ACCOUNT_APPS_MASTER — Lifecycle des prêts');

    -- 7.1 Volumétrie
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Total prêts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CUSTOMER_ID) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Clients distincts emprunteurs', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT PRODUCT_CODE) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  PRODUCT_CODE distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CURRENCY) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Devises distinctes', TO_CHAR(v_count));

    -- 7.2 Plage temporelle
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.2 Plage temporelle (BOOK_DATE / VALUE_DATE / MATURITY_DATE)]');
    FOR r IN (SELECT MIN(BOOK_DATE) bmn, MAX(BOOK_DATE) bmx,
                     MIN(VALUE_DATE) vmn, MAX(VALUE_DATE) vmx,
                     MIN(MATURITY_DATE) mmn, MAX(MATURITY_DATE) mmx
              FROM CLTB_ACCOUNT_APPS_MASTER) LOOP
        print_kv('  BOOK_DATE', TO_CHAR(r.bmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.bmx,'DD/MM/YYYY'));
        print_kv('  VALUE_DATE', TO_CHAR(r.vmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.vmx,'DD/MM/YYYY'));
        print_kv('  MATURITY_DATE', TO_CHAR(r.mmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.mmx,'DD/MM/YYYY'));
    END LOOP;

    -- 7.3 Encours global
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.3 Encours global des prêts]');
    SELECT NVL(ROUND(SUM(AMOUNT_FINANCED),2),0),
           NVL(ROUND(SUM(AMOUNT_DISBURSED),2),0),
           NVL(ROUND(SUM(AMOUNT_UTILIZED),2),0)
      INTO v_num, v_num2, v_count
    FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Cumul AMOUNT_FINANCED', TO_CHAR(v_num));
    print_kv('  Cumul AMOUNT_DISBURSED', TO_CHAR(v_num2));
    print_kv('  Cumul AMOUNT_UTILIZED', TO_CHAR(v_count));

    -- 7.4 ** ALERTE RA ** — STOP_ACCRUALS (arrêt accrual = perte revenus)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.4 ** ALERTE RA ** — STOP_ACCRUALS]');
    FOR r IN (
        SELECT NVL(STOP_ACCRUALS,'<NULL>') sa, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_FINANCED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(STOP_ACCRUALS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  STOP_ACCRUALS=' || r.sa, 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.5 ** ALERTE RA ** — STOP_DSBR (arrêt déboursement)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.5 STOP_DSBR (arrêt déboursement)]');
    FOR r IN (
        SELECT NVL(STOP_DSBR,'<NULL>') sd, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(STOP_DSBR,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  STOP_DSBR=' || r.sd, TO_CHAR(r.nb));
    END LOOP;

    -- 7.6 DELINQUENCY_STATUS (IFRS9 — impact provisioning)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.6 DELINQUENCY_STATUS]');
    FOR r IN (
        SELECT NVL(DELINQUENCY_STATUS,'<NULL>') ds, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_FINANCED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(DELINQUENCY_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  DELINQUENCY=' || r.ds, 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.7 USER_DEFINED_STATUS (NORM, NPA, ...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.7 USER_DEFINED_STATUS]');
    FOR r IN (
        SELECT NVL(USER_DEFINED_STATUS,'<NULL>') us, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_FINANCED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(USER_DEFINED_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  USER_DEFINED_STATUS=' || r.us, 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.8 DERIVED_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.8 DERIVED_STATUS]');
    FOR r IN (
        SELECT NVL(DERIVED_STATUS,'<NULL>') ds, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(DERIVED_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  DERIVED_STATUS=' || r.ds, TO_CHAR(r.nb));
    END LOOP;

    -- 7.9 ACCOUNT_STATUS (O=Opened, L=Liquidated...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.9 ACCOUNT_STATUS]');
    FOR r IN (
        SELECT NVL(ACCOUNT_STATUS,'<NULL>') ast, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_FINANCED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(ACCOUNT_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ACCOUNT_STATUS=' || r.ast, 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.10 AUTH_STAT (autorisés vs non)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.10 AUTH_STAT prêts]');
    FOR r IN (
        SELECT NVL(AUTH_STAT,'<NULL>') au, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(AUTH_STAT,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  AUTH_STAT=' || r.au, TO_CHAR(r.nb));
    END LOOP;

    -- 7.11 Top 15 PRODUCT_CODE (concentration produits)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.11 Top 15 PRODUCT_CODE par encours]');
    FOR r IN (
        SELECT PRODUCT_CODE, nb, sm FROM (
            SELECT PRODUCT_CODE, COUNT(*) nb, ROUND(SUM(AMOUNT_FINANCED),2) sm
            FROM CLTB_ACCOUNT_APPS_MASTER
            GROUP BY PRODUCT_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT=' || NVL(r.PRODUCT_CODE,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.12 Devises
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.12 Répartition devises prêts]');
    FOR r IN (
        SELECT NVL(CURRENCY,'<NULL>') ccy, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT_FINANCED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(CURRENCY,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CCY=' || r.ccy, 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.13 ** ALERTE RA ** — AMOUNT_DISBURSED > AMOUNT_FINANCED (anomalie)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.13 ** ALERTE RA ** — AMOUNT_DISBURSED > AMOUNT_FINANCED]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE NVL(AMOUNT_DISBURSED,0) > NVL(AMOUNT_FINANCED,0) + 0.01;
    print_kv('  Prêts avec DISBURSED > FINANCED', TO_CHAR(v_count));

    -- 7.14 ** ALERTE RA ** — Prêts non entièrement déboursés mais accruals en cours
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.14 Prêts partiellement déboursés (DISBURSED/FINANCED < 100%)]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE NVL(AMOUNT_FINANCED,0) > 0
      AND NVL(AMOUNT_DISBURSED,0) < NVL(AMOUNT_FINANCED,0) * 0.999;
    print_kv('  Prêts sous-déboursés', TO_CHAR(v_count));

    -- 7.15 BOOK_UNEARNED_INTEREST / UPFRONT_PROFIT_BOOKED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.15 Produits constatés d''avance / upfront]');
    FOR r IN (
        SELECT NVL(BOOK_UNEARNED_INTEREST,'<NULL>') bu, COUNT(*) nb,
               NVL(ROUND(SUM(UPFRONT_PROFIT_BOOKED),2),0) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(BOOK_UNEARNED_INTEREST,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  BOOK_UNEARNED_INTEREST=' || r.bu,
                 'nb=' || TO_CHAR(r.nb) || ' | upfront=' || TO_CHAR(r.sm));
    END LOOP;

    SELECT NVL(ROUND(SUM(UPFRONT_PROFIT_BOOKED),2),0) INTO v_num
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE NVL(UPFRONT_PROFIT_BOOKED,0) > 0;
    print_kv('  Cumul UPFRONT_PROFIT_BOOKED > 0', TO_CHAR(v_num));

    -- 7.16 ** ALERTE RA ** — AMEND_PAST_PAID_SCHEDULE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.16 ** ALERTE RA ** — AMEND_PAST_PAID_SCHEDULE]');
    FOR r IN (
        SELECT NVL(AMEND_PAST_PAID_SCHEDULE,'<NULL>') ap, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(AMEND_PAST_PAID_SCHEDULE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  AMEND_PAST_PAID_SCHEDULE=' || r.ap, TO_CHAR(r.nb));
    END LOOP;

    -- 7.17 LIQ_BACK_VALUED_SCHEDULES / BACK_VAL_EFF_DT (back-dating)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.17 Back-dating des prêts]');
    FOR r IN (
        SELECT NVL(LIQ_BACK_VALUED_SCHEDULES,'<NULL>') lb,
               NVL(ALLOW_BACK_PERIOD_ENTRY,'<NULL>') ab, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(LIQ_BACK_VALUED_SCHEDULES,'<NULL>'),
                 NVL(ALLOW_BACK_PERIOD_ENTRY,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  LIQ_BACK_VAL=' || r.lb || ' / ALLOW_BACK=' || r.ab, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE BACK_VAL_EFF_DT IS NOT NULL;
    print_kv('  Prêts avec BACK_VAL_EFF_DT non null', TO_CHAR(v_count));

    -- 7.18 HAS_PROBLEMS (flag système)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.18 HAS_PROBLEMS]');
    FOR r IN (
        SELECT NVL(HAS_PROBLEMS,'<NULL>') hp, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(HAS_PROBLEMS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  HAS_PROBLEMS=' || r.hp, TO_CHAR(r.nb));
    END LOOP;

    -- 7.19 ** ALERTE RA ** — MAKER_ID = CHECKER_ID
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.19 ** ALERTE RA ** — MAKER_ID = CHECKER_ID (4 yeux violé)]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    print_kv('  Prêts avec MAKER=CHECKER', TO_CHAR(v_count));

    -- 7.20 Volumétrie annuelle des octrois (BOOK_DATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.20 Prêts octroyés par année (BOOK_DATE)]');
    FOR r IN (
        SELECT TO_CHAR(BOOK_DATE,'YYYY') annee, COUNT(*) nb,
               ROUND(SUM(AMOUNT_FINANCED),2) sm
        FROM CLTB_ACCOUNT_APPS_MASTER
        WHERE BOOK_DATE IS NOT NULL
        GROUP BY TO_CHAR(BOOK_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, 'nb=' || TO_CHAR(r.nb) || ' | financement=' || TO_CHAR(r.sm));
    END LOOP;

    -- 7.21 INTEREST_SUBSIDY_ALLOWED (subventions taux)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.21 INTEREST_SUBSIDY_ALLOWED (subventions)]');
    FOR r IN (
        SELECT NVL(INTEREST_SUBSIDY_ALLOWED,'<NULL>') isa, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY NVL(INTEREST_SUBSIDY_ALLOWED,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  INTEREST_SUBSIDY=' || r.isa, TO_CHAR(r.nb));
    END LOOP;

    -- 7.22 Prêts avec MIGRATION_DATE (héritage système précédent)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.22 Prêts migrés (MIGRATION_DATE non null)]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_FINANCED),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE MIGRATION_DATE IS NOT NULL;
    print_kv('  Prêts migrés — nb', TO_CHAR(v_count));
    print_kv('  Prêts migrés — encours', TO_CHAR(v_num));

    -- 7.23 Cohérence NEXT_ACCR_DATE passée (accruals en retard)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.23 ** ALERTE RA ** — NEXT_ACCR_DATE en retard]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE NEXT_ACCR_DATE IS NOT NULL
      AND NEXT_ACCR_DATE < TRUNC(SYSDATE) - 30
      AND NVL(STOP_ACCRUALS,'N') <> 'Y'
      AND NVL(ACCOUNT_STATUS,'X') NOT IN ('L','C');
    print_kv('  Prêts actifs avec NEXT_ACCR_DATE >30j passé', TO_CHAR(v_count));

    -- =========================================================
    -- 8. LDTB — CONTRATS LD / MM (Loans, Deposits, Money Market)
    --    Différent du module CL : contrats corporate & interbancaires.
    --    Enjeux RA :
    --      - AMOUNT vs LCY_AMOUNT / INT_ROLLED_AMT (intérêts rolled),
    --      - ICCF_STATUS / CHARGE_STATUS / TAX_STATUS : statut de
    --        calcul des revenus accessoires,
    --      - LDTB_CONTRACT_LIQ_FCC : OVERDUE_DAYS & INT_PREPAY,
    --      - LDTB_CONTRACT_ICCF_CALC_FCC : RATE × BASIS × NO_OF_DAYS,
    --      - SUBSIDY_PERCENTAGE : dérogations tarifaires.
    -- =========================================================
    print_section('8. LDTB — Contrats LD / Money Market & accruals');

    -- 8.1 LDTB_CONTRACT_MASTER — volumétrie
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Total contrats LD', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT COUNTERPARTY) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Contreparties distinctes', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT PRODUCT) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Produits LD distincts', TO_CHAR(v_count));

    -- 8.2 Répartition MODULE / PRODUCT_TYPE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.2 Répartition MODULE x PRODUCT_TYPE (L=Loan, D=Deposit)]');
    FOR r IN (
        SELECT NVL(MODULE,'<NULL>') md, NVL(PRODUCT_TYPE,'<NULL>') pt, COUNT(*) nb,
               NVL(ROUND(SUM(LCY_AMOUNT),2),0) sm
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(MODULE,'<NULL>'), NVL(PRODUCT_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  MODULE=' || r.md || ' / TYPE=' || r.pt,
                 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- 8.3 Plage temporelle
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.3 Plage temporelle (BOOKING_DATE / VALUE_DATE / MATURITY_DATE)]');
    FOR r IN (SELECT MIN(BOOKING_DATE) bmn, MAX(BOOKING_DATE) bmx,
                     MIN(VALUE_DATE) vmn, MAX(VALUE_DATE) vmx,
                     MIN(MATURITY_DATE) mmn, MAX(MATURITY_DATE) mmx
              FROM LDTB_CONTRACT_MASTER) LOOP
        print_kv('  BOOKING_DATE', TO_CHAR(r.bmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.bmx,'DD/MM/YYYY'));
        print_kv('  VALUE_DATE', TO_CHAR(r.vmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.vmx,'DD/MM/YYYY'));
        print_kv('  MATURITY_DATE', TO_CHAR(r.mmn,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.mmx,'DD/MM/YYYY'));
    END LOOP;

    -- 8.4 Encours par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.4 Encours par devise (CURRENCY)]');
    FOR r IN (
        SELECT NVL(CURRENCY,'<NULL>') ccy, COUNT(*) nb,
               NVL(ROUND(SUM(AMOUNT),2),0) sm_fcy,
               NVL(ROUND(SUM(LCY_AMOUNT),2),0) sm_lcy
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(CURRENCY,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CCY=' || r.ccy, 'nb=' || TO_CHAR(r.nb) ||
                                      ' | FCY=' || TO_CHAR(r.sm_fcy) ||
                                      ' | LCY=' || TO_CHAR(r.sm_lcy));
    END LOOP;

    -- 8.5 CONTRACT_STATUS / CONTRACT_DERIVED_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.5 CONTRACT_STATUS / DERIVED_STATUS / USER_DEFINED_STATUS]');
    FOR r IN (
        SELECT NVL(CONTRACT_STATUS,'<NULL>') cs,
               NVL(CONTRACT_DERIVED_STATUS,'<NULL>') cds,
               NVL(USER_DEFINED_STATUS,'<NULL>') uds,
               COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(CONTRACT_STATUS,'<NULL>'),
                 NVL(CONTRACT_DERIVED_STATUS,'<NULL>'),
                 NVL(USER_DEFINED_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CS=' || r.cs || ' / DS=' || r.cds || ' / UDS=' || r.uds, TO_CHAR(r.nb));
    END LOOP;

    -- 8.6 ** ALERTE RA ** — ICCF_STATUS / CHARGE_STATUS / TAX_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.6 Statut calcul revenus accessoires (ICCF / CHARGE / TAX / BROKERAGE)]');
    FOR r IN (
        SELECT NVL(ICCF_STATUS,'<NULL>') ic, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(ICCF_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ICCF_STATUS=' || r.ic, TO_CHAR(r.nb));
    END LOOP;

    FOR r IN (
        SELECT NVL(CHARGE_STATUS,'<NULL>') cs, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(CHARGE_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CHARGE_STATUS=' || r.cs, TO_CHAR(r.nb));
    END LOOP;

    FOR r IN (
        SELECT NVL(TAX_STATUS,'<NULL>') ts, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(TAX_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TAX_STATUS=' || r.ts, TO_CHAR(r.nb));
    END LOOP;

    FOR r IN (
        SELECT NVL(BROKERAGE_STATUS,'<NULL>') bs, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        GROUP BY NVL(BROKERAGE_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  BROKERAGE_STATUS=' || r.bs, TO_CHAR(r.nb));
    END LOOP;

    -- 8.7 Intérêts rollés (INT_ROLLED_AMT) & ROLLOVER
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.7 Intérêts rollés & rollovers]');
    SELECT COUNT(*), NVL(ROUND(SUM(INT_ROLLED_AMT),2),0)
      INTO v_count, v_num
    FROM LDTB_CONTRACT_MASTER
    WHERE NVL(INT_ROLLED_AMT,0) <> 0;
    print_kv('  Contrats avec INT_ROLLED_AMT != 0', TO_CHAR(v_count));
    print_kv('  Cumul INT_ROLLED_AMT', TO_CHAR(v_num));

    FOR r IN (
        SELECT ROLLOVER_COUNT rc, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        WHERE NVL(ROLLOVER_COUNT,0) > 0
        GROUP BY ROLLOVER_COUNT
        ORDER BY rc
    ) LOOP
        print_kv('  ROLLOVER_COUNT=' || TO_CHAR(r.rc), TO_CHAR(r.nb));
    END LOOP;

    -- 8.8 Subventions de taux (SUBSIDY_PERCENTAGE > 0)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.8 ** ALERTE RA ** — SUBSIDY_PERCENTAGE > 0]');
    SELECT COUNT(*), NVL(ROUND(AVG(SUBSIDY_PERCENTAGE),4),0),
           NVL(ROUND(MAX(SUBSIDY_PERCENTAGE),4),0)
      INTO v_count, v_num, v_num2
    FROM LDTB_CONTRACT_MASTER
    WHERE SUBSIDY_PERCENTAGE > 0;
    print_kv('  Contrats subventionnés', TO_CHAR(v_count));
    print_kv('  % moyen subvention', TO_CHAR(v_num));
    print_kv('  % max subvention', TO_CHAR(v_num2));

    -- 8.9 MAIN_COMP_RATE / MAIN_COMP_SPREAD (taux principal)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.9 Statistiques MAIN_COMP_RATE]');
    FOR r IN (
        SELECT ROUND(MIN(MAIN_COMP_RATE),4) mn,
               ROUND(MAX(MAIN_COMP_RATE),4) mx,
               ROUND(AVG(MAIN_COMP_RATE),4) av,
               ROUND(STDDEV(MAIN_COMP_RATE),4) sd,
               COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER
        WHERE MAIN_COMP_RATE IS NOT NULL
    ) LOOP
        print_kv('  MAIN_COMP_RATE min/max/avg/std', TO_CHAR(r.mn) || ' / ' || TO_CHAR(r.mx) ||
                                                     ' / ' || TO_CHAR(r.av) || ' / ' || TO_CHAR(r.sd));
        print_kv('  Contrats avec taux', TO_CHAR(r.nb));
    END LOOP;

    -- 8.10 Contrats avec MAIN_COMP_RATE nul ou zero (leakage intérêts)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.10 ** ALERTE RA ** — Contrats actifs avec MAIN_COMP_RATE = 0 / NULL]');
    SELECT COUNT(*) INTO v_count
    FROM LDTB_CONTRACT_MASTER
    WHERE (MAIN_COMP_RATE IS NULL OR MAIN_COMP_RATE = 0)
      AND NVL(CONTRACT_STATUS,'X') NOT IN ('L','V');
    print_kv('  Contrats actifs à taux nul', TO_CHAR(v_count));

    -- 8.11 LDTB_CONTRACT_LIQ_FCC — liquidations & overdue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.11 LDTB_CONTRACT_LIQ_FCC — liquidations]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ_FCC;
    print_kv('  Nb liquidations (LD)', TO_CHAR(v_count));

    SELECT NVL(ROUND(SUM(AMOUNT_DUE),2),0),
           NVL(ROUND(SUM(AMOUNT_PAID),2),0),
           NVL(ROUND(SUM(INT_PREPAY),2),0),
           NVL(ROUND(SUM(TAX_PAID),2),0)
      INTO v_num, v_num2, v_count, v_count
    FROM LDTB_CONTRACT_LIQ_FCC;
    print_kv('  Cumul AMOUNT_DUE', TO_CHAR(v_num));
    print_kv('  Cumul AMOUNT_PAID', TO_CHAR(v_num2));

    SELECT NVL(ROUND(SUM(INT_PREPAY),2),0), NVL(ROUND(SUM(TAX_PAID),2),0)
      INTO v_num, v_num2
    FROM LDTB_CONTRACT_LIQ_FCC;
    print_kv('  Cumul INT_PREPAY', TO_CHAR(v_num));
    print_kv('  Cumul TAX_PAID', TO_CHAR(v_num2));

    -- 8.12 ** ALERTE RA ** — AMOUNT_DUE > AMOUNT_PAID (non-liquidés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.12 ** ALERTE RA ** — Echéances LD non liquidées (DUE > PAID)]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_DUE - NVL(AMOUNT_PAID,0)),2),0)
      INTO v_count, v_num
    FROM LDTB_CONTRACT_LIQ_FCC
    WHERE AMOUNT_DUE > NVL(AMOUNT_PAID,0) + 0.01;
    print_kv('  Nb échéances non liquidées', TO_CHAR(v_count));
    print_kv('  Cumul écart DUE-PAID', TO_CHAR(v_num));

    -- 8.13 OVERDUE_DAYS distribution
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.13 Distribution OVERDUE_DAYS]');
    FOR r IN (
        SELECT bucket, nb FROM (
            SELECT CASE
                     WHEN NVL(OVERDUE_DAYS,0) = 0 THEN '01_0j'
                     WHEN OVERDUE_DAYS <= 30 THEN '02_1-30j'
                     WHEN OVERDUE_DAYS <= 90 THEN '03_31-90j'
                     WHEN OVERDUE_DAYS <= 180 THEN '04_91-180j'
                     ELSE '05_>180j'
                   END bucket,
                   COUNT(*) nb
            FROM LDTB_CONTRACT_LIQ_FCC
            GROUP BY CASE
                     WHEN NVL(OVERDUE_DAYS,0) = 0 THEN '01_0j'
                     WHEN OVERDUE_DAYS <= 30 THEN '02_1-30j'
                     WHEN OVERDUE_DAYS <= 90 THEN '03_31-90j'
                     WHEN OVERDUE_DAYS <= 180 THEN '04_91-180j'
                     ELSE '05_>180j'
                   END
        ) ORDER BY bucket
    ) LOOP
        print_kv('  Bucket ' || r.bucket, TO_CHAR(r.nb));
    END LOOP;

    -- 8.14 LDTB_CONTRACT_ICCF_CALC_FCC — calculs ICCF (cohérence RATE × BASIS × NO_OF_DAYS)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.14 LDTB_CONTRACT_ICCF_CALC_FCC — calculs ICCF]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC_FCC;
    print_kv('  Nb lignes calculs ICCF', TO_CHAR(v_count));

    SELECT NVL(ROUND(SUM(CALCULATED_AMOUNT),2),0),
           NVL(ROUND(AVG(RATE),4),0)
      INTO v_num, v_num2
    FROM LDTB_CONTRACT_ICCF_CALC_FCC;
    print_kv('  Cumul CALCULATED_AMOUNT', TO_CHAR(v_num));
    print_kv('  RATE moyen', TO_CHAR(v_num2));

    -- 8.14.b Lignes ICCF avec RATE=0 mais BASIS>0 (leakage potentiel)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.14.b ** ALERTE RA ** — ICCF RATE=0 mais BASIS_AMOUNT>0]');
    SELECT COUNT(*), NVL(ROUND(SUM(BASIS_AMOUNT),2),0)
      INTO v_count, v_num
    FROM LDTB_CONTRACT_ICCF_CALC_FCC
    WHERE NVL(RATE,0) = 0 AND NVL(BASIS_AMOUNT,0) > 0;
    print_kv('  Nb lignes RATE=0 / BASIS>0', TO_CHAR(v_count));
    print_kv('  Cumul BASIS concerné', TO_CHAR(v_num));

    -- 8.14.c Lignes ICCF avec CALCULATED_AMOUNT=0 mais RATE>0 ET BASIS>0
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.14.c ** ALERTE RA ** — CALCULATED_AMOUNT=0 mais RATE>0 & BASIS>0]');
    SELECT COUNT(*) INTO v_count
    FROM LDTB_CONTRACT_ICCF_CALC_FCC
    WHERE NVL(CALCULATED_AMOUNT,0) = 0
      AND NVL(RATE,0) > 0
      AND NVL(BASIS_AMOUNT,0) > 0;
    print_kv('  Nb lignes ICCF anormales', TO_CHAR(v_count));

    -- 8.15 LDTB_CONTRACT_PREFERENCE — TRS_APPLICABLE / SUBSIDY_ALLOWED / TRACK_RECEIVABLE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.15 LDTB_CONTRACT_PREFERENCE — préférences RA]');
    FOR r IN (
        SELECT NVL(TRS_APPLICABLE,'<NULL>') tr,
               NVL(SUBSIDY_ALLOWED,'<NULL>') sa,
               NVL(TRACK_RECEIVABLE_MLIQ,'<NULL>') trm,
               NVL(TRACK_RECEIVABLE_ALIQ,'<NULL>') tra,
               COUNT(*) nb
        FROM LDTB_CONTRACT_PREFERENCE
        GROUP BY NVL(TRS_APPLICABLE,'<NULL>'),
                 NVL(SUBSIDY_ALLOWED,'<NULL>'),
                 NVL(TRACK_RECEIVABLE_MLIQ,'<NULL>'),
                 NVL(TRACK_RECEIVABLE_ALIQ,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TRS=' || r.tr || ' / SUBS=' || r.sa || ' / TRKM=' || r.trm || ' / TRKA=' || r.tra,
                 TO_CHAR(r.nb));
    END LOOP;

    -- 8.16 AMORTISATION_TYPE (R=Reducing, B=Balloon, etc.)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.16 AMORTISATION_TYPE]');
    FOR r IN (
        SELECT NVL(AMORTISATION_TYPE,'<NULL>') at, COUNT(*) nb
        FROM LDTB_CONTRACT_PREFERENCE
        GROUP BY NVL(AMORTISATION_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  AMORTISATION_TYPE=' || r.at, TO_CHAR(r.nb));
    END LOOP;

    -- 8.17 MAX_INT_PAY_PERIOD & MAX_RATE_REV_PERIOD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.17 MAX_INT_PAY_PERIOD / MAX_RATE_REV_PERIOD — plafonds]');
    FOR r IN (SELECT ROUND(AVG(MAX_INT_PAY_PERIOD),2) av1,
                     ROUND(MAX(MAX_INT_PAY_PERIOD),2) mx1,
                     ROUND(AVG(MAX_RATE_REV_PERIOD),2) av2,
                     ROUND(MAX(MAX_RATE_REV_PERIOD),2) mx2
              FROM LDTB_CONTRACT_PREFERENCE) LOOP
        print_kv('  MAX_INT_PAY_PERIOD avg/max', TO_CHAR(r.av1) || ' / ' || TO_CHAR(r.mx1));
        print_kv('  MAX_RATE_REV_PERIOD avg/max', TO_CHAR(r.av2) || ' / ' || TO_CHAR(r.mx2));
    END LOOP;

    -- 8.18 Top 15 COUNTERPARTY par encours LD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.18 Top 15 COUNTERPARTY par encours]');
    FOR r IN (
        SELECT COUNTERPARTY, nb, sm FROM (
            SELECT COUNTERPARTY, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
            FROM LDTB_CONTRACT_MASTER
            GROUP BY COUNTERPARTY
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CP=' || NVL(r.COUNTERPARTY,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | encours=' || TO_CHAR(r.sm));
    END LOOP;

    -- =========================================================
    -- 9. ICTM — PARAMETRAGE TAUX & ELEMENTS DEFINIS UTILISATEUR (UDE)
    --    Enjeux RA :
    --      - Référentiel taux par produit (ICTM_PR_INT_UDEVALS),
    --      - Overrides par compte (ICTM_ACC_UDEVALS) — vecteur majeur
    --        de revenue leakage si mauvaise dérogation,
    --      - UDE_VARIANCE : écart cible vs spread (dérogation tarif),
    --      - Règles IC (ICTM_EXPR) : conditions de calcul/exonération.
    -- =========================================================
    print_section('9. ICTM — Paramétrage taux & éléments UDE');

    -- 9.1 ICTM_PR_INT_UDEVALS — UDE au niveau produit
    DBMS_OUTPUT.PUT_LINE('  [9.1 ICTM_PR_INT_UDEVALS — UDE niveau produit]');
    SELECT COUNT(*) INTO v_count FROM ICTM_PR_INT_UDEVALS;
    print_kv('  Nb UDE produit', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT PRODUCT_CODE) INTO v_count FROM ICTM_PR_INT_UDEVALS;
    print_kv('  PRODUCT_CODE distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT UDE_ID) INTO v_count FROM ICTM_PR_INT_UDEVALS;
    print_kv('  UDE_ID distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY_CODE) INTO v_count FROM ICTM_PR_INT_UDEVALS;
    print_kv('  Devises couvertes', TO_CHAR(v_count));

    -- 9.2 Répartition par UDE_ID (type de taux)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2 Répartition par UDE_ID (type d''élément tarifaire)]');
    FOR r IN (
        SELECT UDE_ID, COUNT(*) nb,
               ROUND(MIN(UDE_VALUE),6) mn,
               ROUND(MAX(UDE_VALUE),6) mx,
               ROUND(AVG(UDE_VALUE),6) av
        FROM ICTM_PR_INT_UDEVALS
        GROUP BY UDE_ID
        ORDER BY nb DESC
    ) LOOP
        print_kv('  UDE=' || NVL(r.UDE_ID,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | min=' || TO_CHAR(r.mn) ||
                 ' / max=' || TO_CHAR(r.mx) || ' / avg=' || TO_CHAR(r.av));
    END LOOP;

    -- 9.3 Nb versions d'UDE par produit (révisions de taux)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3 Top 15 produits avec le plus de versions d''UDE (révisions)]');
    FOR r IN (
        SELECT PRODUCT_CODE, nb FROM (
            SELECT PRODUCT_CODE, COUNT(*) nb
            FROM ICTM_PR_INT_UDEVALS
            GROUP BY PRODUCT_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT=' || r.PRODUCT_CODE, 'nb versions UDE=' || TO_CHAR(r.nb));
    END LOOP;

    -- 9.4 Plage temporelle UDE_EFF_DT (dates d'effet)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.4 Plage UDE_EFF_DT]');
    FOR r IN (SELECT MIN(UDE_EFF_DT) dmin, MAX(UDE_EFF_DT) dmax FROM ICTM_PR_INT_UDEVALS) LOOP
        print_kv('  min / max', TO_CHAR(r.dmin,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.dmax,'DD/MM/YYYY'));
    END LOOP;

    -- 9.5 UDE avec valeur nulle ou zero
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.5 ** ALERTE RA ** — UDE produit à 0 ou NULL]');
    SELECT COUNT(*) INTO v_count
    FROM ICTM_PR_INT_UDEVALS
    WHERE NVL(UDE_VALUE,0) = 0;
    print_kv('  UDE produit à 0 ou NULL', TO_CHAR(v_count));

    -- 9.6 ICTM_ACC_UDEVALS — UDE au niveau compte (overrides)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.6 ICTM_ACC_UDEVALS — overrides au compte]');
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Nb overrides compte', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACC) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Comptes avec override taux', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT PROD) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Produits avec override compte', TO_CHAR(v_count));

    -- 9.7 Répartition overrides par UDE_ID
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.7 Overrides par UDE_ID]');
    FOR r IN (
        SELECT UDE_ID, COUNT(*) nb,
               ROUND(MIN(UDE_VALUE),6) mn,
               ROUND(MAX(UDE_VALUE),6) mx,
               ROUND(AVG(UDE_VALUE),6) av
        FROM ICTM_ACC_UDEVALS
        GROUP BY UDE_ID
        ORDER BY nb DESC
    ) LOOP
        print_kv('  UDE=' || NVL(r.UDE_ID,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | min=' || TO_CHAR(r.mn) ||
                 ' / max=' || TO_CHAR(r.mx) || ' / avg=' || TO_CHAR(r.av));
    END LOOP;

    -- 9.8 ** ALERTE RA ** — UDE_VARIANCE (dérogations tarifaires chiffrées)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.8 ** ALERTE RA ** — UDE_VARIANCE (dérogations tarif)]');
    FOR r IN (SELECT COUNT(*) nb,
                     ROUND(MIN(UDE_VARIANCE),6) mn,
                     ROUND(MAX(UDE_VARIANCE),6) mx,
                     ROUND(AVG(UDE_VARIANCE),6) av
              FROM ICTM_ACC_UDEVALS
              WHERE NVL(UDE_VARIANCE,0) <> 0) LOOP
        print_kv('  Overrides avec variance non nulle', TO_CHAR(r.nb));
        print_kv('  Variance min / max / moy', TO_CHAR(r.mn) || ' / ' || TO_CHAR(r.mx) || ' / ' || TO_CHAR(r.av));
    END LOOP;

    -- 9.8.b Top 15 comptes avec variance négative (favorables au client)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.8.b Top 15 comptes avec UDE_VARIANCE négative (clients favorisés)]');
    FOR r IN (
        SELECT ACC, BRN, PROD, variance, UDE_ID FROM (
            SELECT ACC, BRN, PROD, UDE_ID,
                   ROUND(MIN(UDE_VARIANCE),6) variance
            FROM ICTM_ACC_UDEVALS
            WHERE UDE_VARIANCE < 0
            GROUP BY ACC, BRN, PROD, UDE_ID
            ORDER BY variance ASC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Cpt=' || r.ACC || ' / BRN=' || r.BRN || ' / PROD=' || r.PROD || ' / UDE=' || r.UDE_ID,
                 'variance=' || TO_CHAR(r.variance));
    END LOOP;

    -- 9.9 BASE_RATE vs BASE_SPREAD (override structure)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.9 BASE_RATE / BASE_SPREAD distribution overrides]');
    FOR r IN (SELECT ROUND(MIN(BASE_RATE),6) bmn, ROUND(MAX(BASE_RATE),6) bmx,
                     ROUND(AVG(BASE_RATE),6) bav,
                     ROUND(MIN(BASE_SPREAD),6) smn, ROUND(MAX(BASE_SPREAD),6) smx,
                     ROUND(AVG(BASE_SPREAD),6) sav
              FROM ICTM_ACC_UDEVALS
              WHERE BASE_RATE IS NOT NULL OR BASE_SPREAD IS NOT NULL) LOOP
        print_kv('  BASE_RATE min/max/avg', TO_CHAR(r.bmn) || ' / ' || TO_CHAR(r.bmx) || ' / ' || TO_CHAR(r.bav));
        print_kv('  BASE_SPREAD min/max/avg', TO_CHAR(r.smn) || ' / ' || TO_CHAR(r.smx) || ' / ' || TO_CHAR(r.sav));
    END LOOP;

    -- 9.10 AUTH_STAT / RECORD_STAT des overrides
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.10 AUTH_STAT & RECORD_STAT des overrides taux]');
    FOR r IN (
        SELECT NVL(AUTH_STAT,'<NULL>') au, NVL(RECORD_STAT,'<NULL>') rs, COUNT(*) nb
        FROM ICTM_ACC_UDEVALS
        GROUP BY NVL(AUTH_STAT,'<NULL>'), NVL(RECORD_STAT,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  AUTH=' || r.au || ' / REC=' || r.rs, TO_CHAR(r.nb));
    END LOOP;

    -- 9.11 ** ALERTE RA ** — overrides avec UDE_VALUE < taux produit correspondant
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.11 ** ALERTE RA ** — override < taux produit (dérogation à la baisse)]');
    SELECT COUNT(*) INTO v_count
    FROM ICTM_ACC_UDEVALS a
    WHERE EXISTS (
        SELECT 1 FROM ICTM_PR_INT_UDEVALS p
        WHERE p.PRODUCT_CODE = a.PROD
          AND p.UDE_ID = a.UDE_ID
          AND NVL(a.UDE_VALUE,0) < NVL(p.UDE_VALUE,0) - 0.0001
    );
    print_kv('  Overrides compte < taux produit', TO_CHAR(v_count));

    -- 9.12 ICTM_EXPR — règles expressionnelles (exemptions)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.12 ICTM_EXPR — règles conditionnelles]');
    SELECT COUNT(*) INTO v_count FROM ICTM_EXPR;
    print_kv('  Nb lignes règles', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT RULE_ID) INTO v_count FROM ICTM_EXPR;
    print_kv('  Règles distinctes (RULE_ID)', TO_CHAR(v_count));

    -- 9.13 Top 10 RULE_ID (règles les plus volumineuses)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.13 Top 10 RULE_ID par nb de lignes]');
    FOR r IN (
        SELECT RULE_ID, nb FROM (
            SELECT RULE_ID, COUNT(*) nb
            FROM ICTM_EXPR
            GROUP BY RULE_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  RULE_ID=' || NVL(r.RULE_ID,'<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- 9.14 Devises les plus fréquentes dans les UDE produit
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.14 Top 10 devises dans UDE produit]');
    FOR r IN (
        SELECT CCY_CODE, nb FROM (
            SELECT CCY_CODE, COUNT(*) nb
            FROM ICTM_PR_INT_UDEVALS
            GROUP BY CCY_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY=' || NVL(r.CCY_CODE,'<NULL>'), TO_CHAR(r.nb));
    END LOOP;

    -- =========================================================
    -- 10. GLTB_GL_BAL — GRAND LIVRE (soldes & mouvements)
    --    Enjeux RA :
    --      - CATEGORY I (Income) & E (Expense) pour les revenus/charges
    --      - Soldes anormaux (CR sur GL de type asset, DR sur liability)
    --      - Mouvements annuels par nature de compte
    --      - GL feuilles (LEAF='Y') vs agrégés
    --      - Cohérence CR_BAL - DR_BAL vs mouvements cumulés
    -- =========================================================
    print_section('10. GLTB_GL_BAL — Grand livre, soldes & mouvements');

    -- 10.1 Volumétrie
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Nb lignes GLTB_GL_BAL', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT GL_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  GL_CODE distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT FIN_YEAR) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  FIN_YEAR distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  BRANCH_CODE distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Devises GL distinctes', TO_CHAR(v_count));

    -- 10.2 Répartition par CATEGORY (A=Actif, L=Passif, I=Income, E=Expense)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.2 Répartition par CATEGORY (A/L/I/E/X)]');
    FOR r IN (
        SELECT NVL(CATEGORY,'<NULL>') ct, COUNT(*) nb,
               NVL(ROUND(SUM(DR_MOV_LCY),2),0) dr_mv,
               NVL(ROUND(SUM(CR_MOV_LCY),2),0) cr_mv
        FROM GLTB_GL_BAL
        GROUP BY NVL(CATEGORY,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CATEGORY=' || r.ct, 'nb=' || TO_CHAR(r.nb) ||
                                         ' | DR_MOV_LCY=' || TO_CHAR(r.dr_mv) ||
                                         ' | CR_MOV_LCY=' || TO_CHAR(r.cr_mv));
    END LOOP;

    -- 10.3 Volumétrie par FIN_YEAR (exercices comptables)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.3 Mouvements par FIN_YEAR (LCY)]');
    FOR r IN (
        SELECT FIN_YEAR,
               COUNT(*) nb,
               ROUND(SUM(DR_MOV_LCY),2) dr_mv,
               ROUND(SUM(CR_MOV_LCY),2) cr_mv
        FROM GLTB_GL_BAL
        GROUP BY FIN_YEAR
        ORDER BY FIN_YEAR
    ) LOOP
        print_kv('  FY=' || NVL(r.FIN_YEAR,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | DR=' || TO_CHAR(r.dr_mv) ||
                 ' | CR=' || TO_CHAR(r.cr_mv));
    END LOOP;

    -- 10.4 Revenus (CATEGORY=I) — focus RA
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.4 ** RA ** — Revenus (CATEGORY=I) cumul mouvements]');
    FOR r IN (
        SELECT FIN_YEAR,
               ROUND(SUM(CR_MOV_LCY),2) cr_mv_lcy,
               ROUND(SUM(DR_MOV_LCY),2) dr_mv_lcy,
               ROUND(SUM(CR_MOV_LCY - DR_MOV_LCY),2) net_revenue
        FROM GLTB_GL_BAL
        WHERE CATEGORY = 'I'
        GROUP BY FIN_YEAR
        ORDER BY FIN_YEAR
    ) LOOP
        print_kv('  FY=' || r.FIN_YEAR || ' — CR revenus', TO_CHAR(r.cr_mv_lcy));
        print_kv('  FY=' || r.FIN_YEAR || '   DR revenus (stornos)', TO_CHAR(r.dr_mv_lcy));
        print_kv('  FY=' || r.FIN_YEAR || '   Net revenues', TO_CHAR(r.net_revenue));
    END LOOP;

    -- 10.5 Charges (CATEGORY=E)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.5 Charges (CATEGORY=E) cumul mouvements]');
    FOR r IN (
        SELECT FIN_YEAR,
               ROUND(SUM(DR_MOV_LCY),2) dr_mv_lcy,
               ROUND(SUM(CR_MOV_LCY),2) cr_mv_lcy,
               ROUND(SUM(DR_MOV_LCY - CR_MOV_LCY),2) net_expense
        FROM GLTB_GL_BAL
        WHERE CATEGORY = 'E'
        GROUP BY FIN_YEAR
        ORDER BY FIN_YEAR
    ) LOOP
        print_kv('  FY=' || r.FIN_YEAR || ' — DR charges', TO_CHAR(r.dr_mv_lcy));
        print_kv('  FY=' || r.FIN_YEAR || '   CR charges (remb)', TO_CHAR(r.cr_mv_lcy));
        print_kv('  FY=' || r.FIN_YEAR || '   Net charges', TO_CHAR(r.net_expense));
    END LOOP;

    -- 10.6 Top 20 GL de revenus par solde CR
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.6 Top 20 GL revenus (CATEGORY=I) par CR_MOV_LCY cumulé]');
    FOR r IN (
        SELECT GL_CODE, sm FROM (
            SELECT GL_CODE, ROUND(SUM(CR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            WHERE CATEGORY = 'I'
            GROUP BY GL_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  GL=' || NVL(r.GL_CODE,'<NULL>'), 'CR_MOV_LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.7 Top 20 GL de charges par solde DR
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.7 Top 20 GL charges (CATEGORY=E) par DR_MOV_LCY cumulé]');
    FOR r IN (
        SELECT GL_CODE, sm FROM (
            SELECT GL_CODE, ROUND(SUM(DR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            WHERE CATEGORY = 'E'
            GROUP BY GL_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  GL=' || NVL(r.GL_CODE,'<NULL>'), 'DR_MOV_LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.8 ** ALERTE RA ** — revenus avec solde anormal DR (revenu en négatif)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.8 ** ALERTE RA ** — GL revenus avec DR_MOV > CR_MOV]');
    SELECT COUNT(*) INTO v_count
    FROM GLTB_GL_BAL
    WHERE CATEGORY = 'I'
      AND NVL(DR_MOV_LCY,0) > NVL(CR_MOV_LCY,0) + 0.01;
    print_kv('  Nb lignes GL revenus avec DR>CR', TO_CHAR(v_count));

    -- 10.9 GL feuilles vs agrégés
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.9 GL feuilles (LEAF) vs agrégés]');
    FOR r IN (
        SELECT NVL(LEAF,'<NULL>') lf, COUNT(*) nb
        FROM GLTB_GL_BAL
        GROUP BY NVL(LEAF,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  LEAF=' || r.lf, TO_CHAR(r.nb));
    END LOOP;

    -- 10.10 Ventilation revenus par devise (CATEGORY=I)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.10 Revenus par devise (CATEGORY=I)]');
    FOR r IN (
        SELECT CCY_CODE, COUNT(*) nb, ROUND(SUM(CR_MOV_LCY),2) sm
        FROM GLTB_GL_BAL
        WHERE CATEGORY = 'I'
        GROUP BY CCY_CODE
        ORDER BY sm DESC NULLS LAST
    ) LOOP
        print_kv('  CCY=' || NVL(r.CCY_CODE,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | CR_MOV_LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.11 Revenus par agence (top 15)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.11 Top 15 agences par revenus (CATEGORY=I, CR_MOV_LCY)]');
    FOR r IN (
        SELECT BRANCH_CODE, nb, sm FROM (
            SELECT BRANCH_CODE, COUNT(*) nb, ROUND(SUM(CR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            WHERE CATEGORY = 'I'
            GROUP BY BRANCH_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  BRN=' || NVL(r.BRANCH_CODE,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | revenus=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.12 Mouvements vs balances (sanity check — BAL = OPEN_BAL + MOV)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.12 Cohérence LCY : BAL vs OPEN_BAL + MOV (LCY)]');
    SELECT COUNT(*) INTO v_count
    FROM GLTB_GL_BAL
    WHERE ABS(NVL(DR_BAL_LCY,0) - NVL(OPEN_DR_BAL_LCY,0) - NVL(DR_MOV_LCY,0)) > 0.01
       OR ABS(NVL(CR_BAL_LCY,0) - NVL(OPEN_CR_BAL_LCY,0) - NVL(CR_MOV_LCY,0)) > 0.01;
    print_kv('  Lignes GL avec incohérence BAL / OPEN+MOV', TO_CHAR(v_count));

    -- 10.13 UNCOLLECTED (créances non collectées)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.13 UNCOLLECTED — cumul GL avec créance non recouvrée]');
    SELECT COUNT(*), NVL(ROUND(SUM(UNCOLLECTED),2),0)
      INTO v_count, v_num
    FROM GLTB_GL_BAL
    WHERE NVL(UNCOLLECTED,0) > 0;
    print_kv('  Nb lignes UNCOLLECTED > 0', TO_CHAR(v_count));
    print_kv('  Cumul UNCOLLECTED', TO_CHAR(v_num));

    -- 10.14 Rapprochement ACTB_HISTORY (CATEGORY=I) vs GLTB_GL_BAL (CATEGORY=I)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.14 Rapprochement ACTB_HISTORY ↔ GLTB_GL_BAL (CATEGORY=I)]');
    SELECT NVL(ROUND(SUM(CR_MOV_LCY - DR_MOV_LCY),2),0) INTO v_num
    FROM GLTB_GL_BAL WHERE CATEGORY = 'I';
    print_kv('  Net GLTB (CR-DR, CATEGORY=I)', TO_CHAR(v_num));

    SELECT NVL(ROUND(SUM(CASE WHEN h.DRCR_IND='C' THEN h.LCY_AMOUNT
                              WHEN h.DRCR_IND='D' THEN -h.LCY_AMOUNT
                              ELSE 0 END),2),0) INTO v_num2
    FROM ACTB_HISTORY h
    WHERE EXISTS (
        SELECT 1 FROM CSTB_AMOUNT_TAG t
        WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
          AND (t.INTEREST_ALLOWED = 'Y' OR t.CHARGE_ALLOWED = 'Y' OR t.COMMISSION_ALLOWED = 'Y')
    );
    print_kv('  Net ACTB (CR-DR, tags revenue)', TO_CHAR(v_num2));
    print_kv('  Ecart brut GLTB - ACTB', TO_CHAR(NVL(v_num,0) - NVL(v_num2,0)));

    -- 10.15 Top 20 GL par HAS_TOV='Y' (GL avec turnover du jour)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.15 GL avec HAS_TOV=Y (turnover journalier)]');
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL WHERE HAS_TOV = 'Y';
    print_kv('  Nb GL actifs aujourd''hui', TO_CHAR(v_count));

    -- =========================================================
    -- 11. RVTB_ACC_REVAL & CYTB — REEVALUATION FX / P&L DE CHANGE
    --    Enjeu RA : les gains/pertes de change sur réévaluation
    --    sont un vecteur majeur de revenus non liés aux intérêts.
    --    Il faut s'assurer que :
    --      - la réévaluation porte sur tous les comptes FCY,
    --      - NEW_RATE est cohérent avec CYTB_RATES_HISTORY,
    --      - le P&L (NEW-OLD LCY_EQUIVALENT) est passé en compta.
    -- =========================================================
    print_section('11. RVTB_ACC_REVAL & CYTB — Réévaluation FX & P&L');

    -- 11.1 RVTB_ACC_REVAL — volumétrie
    SELECT COUNT(*) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Nb lignes RVTB_ACC_REVAL', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACCOUNT) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Comptes FCY réévalués', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Devises réévaluées', TO_CHAR(v_count));

    -- 11.2 Plage temporelle REVAL_DATE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.2 Plage REVAL_DATE]');
    FOR r IN (SELECT MIN(REVAL_DATE) dmin, MAX(REVAL_DATE) dmax FROM RVTB_ACC_REVAL) LOOP
        print_kv('  min / max', TO_CHAR(r.dmin,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.dmax,'DD/MM/YYYY'));
    END LOOP;

    -- 11.3 Volumétrie annuelle des réévaluations
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.3 Volumétrie annuelle des réévaluations]');
    FOR r IN (
        SELECT TO_CHAR(REVAL_DATE,'YYYY') annee, COUNT(*) nb,
               ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) pnl
        FROM RVTB_ACC_REVAL
        WHERE REVAL_DATE IS NOT NULL
        GROUP BY TO_CHAR(REVAL_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, 'nb=' || TO_CHAR(r.nb) || ' | P&L net=' || TO_CHAR(r.pnl));
    END LOOP;

    -- 11.4 P&L par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.4 P&L réévaluation par devise]');
    FOR r IN (
        SELECT CCY, COUNT(*) nb,
               ROUND(SUM(OLD_LCY_EQUIVALENT),2) old_lcy,
               ROUND(SUM(NEW_LCY_EQUIVALENT),2) new_lcy,
               ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) pnl
        FROM RVTB_ACC_REVAL
        GROUP BY CCY
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CCY=' || NVL(r.CCY,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | OLD=' || TO_CHAR(r.old_lcy) ||
                 ' | NEW=' || TO_CHAR(r.new_lcy) || ' | P&L=' || TO_CHAR(r.pnl));
    END LOOP;

    -- 11.5 REVAL_IND (gain/loss indicator)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.5 Répartition REVAL_IND]');
    FOR r IN (
        SELECT NVL(REVAL_IND,'<NULL>') ri, COUNT(*) nb,
               ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) pnl
        FROM RVTB_ACC_REVAL
        GROUP BY NVL(REVAL_IND,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  REVAL_IND=' || r.ri, 'nb=' || TO_CHAR(r.nb) || ' | P&L=' || TO_CHAR(r.pnl));
    END LOOP;

    -- 11.6 P&L trading vs non-trading
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.6 TRADING_PL_INDICATOR & P&L trading]');
    FOR r IN (
        SELECT NVL(TRADING_PL_INDICATOR,'<NULL>') ti, COUNT(*) nb,
               ROUND(SUM(TRADING_NEW_LCY_EQUIVALENT - TRADING_OLD_LCY_EQUIVALENT),2) pnl
        FROM RVTB_ACC_REVAL
        GROUP BY NVL(TRADING_PL_INDICATOR,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TRADING_PL=' || r.ti, 'nb=' || TO_CHAR(r.nb) || ' | P&L trading=' || TO_CHAR(r.pnl));
    END LOOP;

    -- 11.7 PL_SPLIT_FLAG (séparation gains latents vs réalisés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.7 PL_SPLIT_FLAG]');
    FOR r IN (
        SELECT NVL(PL_SPLIT_FLAG,'<NULL>') ps, COUNT(*) nb
        FROM RVTB_ACC_REVAL
        GROUP BY NVL(PL_SPLIT_FLAG,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  PL_SPLIT_FLAG=' || r.ps, TO_CHAR(r.nb));
    END LOOP;

    -- 11.8 GLMIS_UPD_STATUS (intégration MIS — doit être 'P' processed)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.8 GLMIS_UPD_STATUS (intégration MIS)]');
    FOR r IN (
        SELECT NVL(GLMIS_UPD_STATUS,'<NULL>') gs, COUNT(*) nb
        FROM RVTB_ACC_REVAL
        GROUP BY NVL(GLMIS_UPD_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  GLMIS_UPD_STATUS=' || r.gs, TO_CHAR(r.nb));
    END LOOP;

    -- 11.9 ** ALERTE RA ** — variations de taux suspectes (NEW_RATE min/max/avg par CCY)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.9 NEW_RATE statistiques par devise]');
    FOR r IN (
        SELECT CCY,
               ROUND(MIN(NEW_RATE),8) mn,
               ROUND(MAX(NEW_RATE),8) mx,
               ROUND(AVG(NEW_RATE),8) av,
               ROUND(STDDEV(NEW_RATE),8) sd
        FROM RVTB_ACC_REVAL
        WHERE NEW_RATE IS NOT NULL
        GROUP BY CCY
        ORDER BY CCY
    ) LOOP
        print_kv('  CCY=' || NVL(r.CCY,'<NULL>'),
                 'min=' || TO_CHAR(r.mn) || ' / max=' || TO_CHAR(r.mx) ||
                 ' / avg=' || TO_CHAR(r.av) || ' / std=' || TO_CHAR(r.sd));
    END LOOP;

    -- 11.10 Top 15 comptes par P&L absolu
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.10 Top 15 comptes par |P&L réévaluation|]');
    FOR r IN (
        SELECT ACCOUNT, CCY, pnl FROM (
            SELECT ACCOUNT, CCY,
                   ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) pnl
            FROM RVTB_ACC_REVAL
            GROUP BY ACCOUNT, CCY
            ORDER BY ABS(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT)) DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ACC=' || r.ACCOUNT || ' / CCY=' || r.CCY, 'P&L=' || TO_CHAR(r.pnl));
    END LOOP;

    -- 11.11 Réévaluations sans P&L (NEW = OLD) — possible manque d'effet
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.11 ** ALERTE RA ** — Réévaluations sans écart (NEW=OLD)]');
    SELECT COUNT(*) INTO v_count
    FROM RVTB_ACC_REVAL
    WHERE ABS(NVL(NEW_LCY_EQUIVALENT,0) - NVL(OLD_LCY_EQUIVALENT,0)) < 0.01
      AND NVL(ACCOUNT_BALANCE,0) <> 0;
    print_kv('  Réévaluations plates (anomalie potentielle)', TO_CHAR(v_count));

    -- 11.12 CYTB_RATES_HISTORY — volumétrie
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.12 CYTB_RATES_HISTORY — historique cours FX]');
    SELECT COUNT(*) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  Nb cotations historiques', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY1 || '-' || CCY2) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  Paires CCY distinctes', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT RATE_TYPE) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  RATE_TYPE distincts', TO_CHAR(v_count));

    -- 11.13 Plage CYTB_RATES_HISTORY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.13 Plage RATE_DATE]');
    FOR r IN (SELECT MIN(RATE_DATE) dmin, MAX(RATE_DATE) dmax FROM CYTB_RATES_HISTORY) LOOP
        print_kv('  min / max', TO_CHAR(r.dmin,'DD/MM/YYYY') || ' — ' || TO_CHAR(r.dmax,'DD/MM/YYYY'));
    END LOOP;

    -- 11.14 Spread BUY-SALE par devise (proxy P&L trading)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.14 Spread BUY_RATE vs SALE_RATE par paire (moyenne)]');
    FOR r IN (
        SELECT CCY1, CCY2, COUNT(*) nb,
               ROUND(AVG(SALE_RATE - BUY_RATE),6) sp_avg,
               ROUND(MAX(SALE_RATE - BUY_RATE),6) sp_max
        FROM CYTB_RATES_HISTORY
        WHERE BUY_RATE IS NOT NULL AND SALE_RATE IS NOT NULL
        GROUP BY CCY1, CCY2
        HAVING COUNT(*) > 10
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ' || r.CCY1 || '/' || r.CCY2,
                 'nb=' || TO_CHAR(r.nb) || ' | spread avg=' || TO_CHAR(r.sp_avg) ||
                 ' | spread max=' || TO_CHAR(r.sp_max));
    END LOOP;

    -- 11.15 ** ALERTE RA ** — cours à 0 ou négatif
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.15 ** ALERTE RA ** — Cours MID/BUY/SALE <= 0]');
    SELECT COUNT(*) INTO v_count
    FROM CYTB_RATES_HISTORY
    WHERE NVL(MID_RATE,0) <= 0 OR NVL(BUY_RATE,0) <= 0 OR NVL(SALE_RATE,0) <= 0;
    print_kv('  Cotations anormales', TO_CHAR(v_count));

    -- 11.16 ** ALERTE RA ** — inversion BUY > SALE (arbitrage impossible)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.16 ** ALERTE RA ** — BUY_RATE > SALE_RATE (inversion)]');
    SELECT COUNT(*) INTO v_count
    FROM CYTB_RATES_HISTORY
    WHERE BUY_RATE > SALE_RATE;
    print_kv('  Cotations inversées', TO_CHAR(v_count));

    -- 11.17 CYTB_DERIVED_RATES_HISTORY — cours dérivés (cross-rates)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.17 CYTB_DERIVED_RATES_HISTORY — cours dérivés]');
    SELECT COUNT(*) INTO v_count FROM CYTB_DERIVED_RATES_HISTORY;
    print_kv('  Nb cours dérivés', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY1 || '-' || CCY2) INTO v_count FROM CYTB_DERIVED_RATES_HISTORY;
    print_kv('  Paires dérivées distinctes', TO_CHAR(v_count));

    -- =========================================================
    -- 12. STTM_CUST_ACCOUNT — COMPTES CLIENTS / TOD / DORMANCE
    --    Enjeux RA :
    --      - Overdraft non autorisé (solde < 0 sans TOD) : frais
    --        d'intérêts débiteurs à calculer,
    --      - Comptes dormants : suivi frais de dormance,
    --      - DEFAULT_WAIVER = 'Y' : désactivation charges par défaut,
    --      - INF_WAIVE_ACC_OPEN_CHARGE : frais d'ouverture waivés,
    --      - Soldes créditeurs sur comptes sans rémunération d'intérêts.
    -- =========================================================
    print_section('12. STTM_CUST_ACCOUNT — Comptes clients, TOD & dormance');

    -- 12.1 Volumétrie
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT;
    print_kv('  Total comptes', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CUST_NO) INTO v_count FROM STTM_CUST_ACCOUNT;
    print_kv('  Clients distincts titulaires', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ACCOUNT_CLASS) INTO v_count FROM STTM_CUST_ACCOUNT;
    print_kv('  ACCOUNT_CLASS distincts', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT CCY) INTO v_count FROM STTM_CUST_ACCOUNT;
    print_kv('  Devises distinctes', TO_CHAR(v_count));

    -- 12.2 Soldes agrégés LCY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.2 Soldes cumulés (LCY)]');
    SELECT NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0),
           NVL(ROUND(SUM(CASE WHEN LCY_CURR_BALANCE > 0 THEN LCY_CURR_BALANCE ELSE 0 END),2),0),
           NVL(ROUND(SUM(CASE WHEN LCY_CURR_BALANCE < 0 THEN LCY_CURR_BALANCE ELSE 0 END),2),0)
      INTO v_num, v_num2, v_count
    FROM STTM_CUST_ACCOUNT;
    print_kv('  Solde net LCY', TO_CHAR(v_num));
    print_kv('  Cumul créditeurs LCY', TO_CHAR(v_num2));
    print_kv('  Cumul débiteurs LCY', TO_CHAR(v_count));

    -- 12.3 Répartition ACC_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.3 Répartition ACC_STATUS]');
    FOR r IN (
        SELECT NVL(ACC_STATUS,'<NULL>') st, COUNT(*) nb,
               NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0) sm
        FROM STTM_CUST_ACCOUNT
        GROUP BY NVL(ACC_STATUS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ACC_STATUS=' || r.st, 'nb=' || TO_CHAR(r.nb) || ' | solde=' || TO_CHAR(r.sm));
    END LOOP;

    -- 12.4 Top 15 ACCOUNT_CLASS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.4 Top 15 ACCOUNT_CLASS par nb comptes]');
    FOR r IN (
        SELECT ACCOUNT_CLASS, nb, sm FROM (
            SELECT ACCOUNT_CLASS, COUNT(*) nb, ROUND(SUM(LCY_CURR_BALANCE),2) sm
            FROM STTM_CUST_ACCOUNT
            GROUP BY ACCOUNT_CLASS
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  AC_CLASS=' || NVL(r.ACCOUNT_CLASS,'<NULL>'),
                 'nb=' || TO_CHAR(r.nb) || ' | solde=' || TO_CHAR(r.sm));
    END LOOP;

    -- 12.5 Répartition par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.5 Répartition par devise]');
    FOR r IN (
        SELECT NVL(CCY,'<NULL>') ccy, COUNT(*) nb,
               NVL(ROUND(SUM(ACY_CURR_BALANCE),2),0) sm_fcy,
               NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0) sm_lcy
        FROM STTM_CUST_ACCOUNT
        GROUP BY NVL(CCY,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CCY=' || r.ccy,
                 'nb=' || TO_CHAR(r.nb) || ' | FCY=' || TO_CHAR(r.sm_fcy) || ' | LCY=' || TO_CHAR(r.sm_lcy));
    END LOOP;

    -- 12.6 ** ALERTE RA ** — soldes débiteurs SANS TOD_LIMIT actif (overdraft non autorisé)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.6 ** ALERTE RA ** — soldes débiteurs sans TOD_LIMIT]');
    SELECT COUNT(*), NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0)
      INTO v_count, v_num
    FROM STTM_CUST_ACCOUNT
    WHERE LCY_CURR_BALANCE < 0
      AND NVL(TOD_LIMIT,0) = 0;
    print_kv('  Comptes débiteurs sans TOD', TO_CHAR(v_count));
    print_kv('  Cumul débiteurs non autorisés (LCY)', TO_CHAR(v_num));

    -- 12.7 Comptes avec TOD_LIMIT > 0 (découvert autorisé)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.7 Comptes avec TOD_LIMIT > 0]');
    SELECT COUNT(*), NVL(ROUND(SUM(TOD_LIMIT),2),0),
           NVL(ROUND(AVG(TOD_LIMIT),2),0)
      INTO v_count, v_num, v_num2
    FROM STTM_CUST_ACCOUNT
    WHERE NVL(TOD_LIMIT,0) > 0;
    print_kv('  Comptes avec TOD', TO_CHAR(v_count));
    print_kv('  Cumul TOD_LIMIT', TO_CHAR(v_num));
    print_kv('  TOD_LIMIT moyen', TO_CHAR(v_num2));

    -- 12.8 ** ALERTE RA ** — comptes dépassant le TOD_LIMIT
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.8 ** ALERTE RA ** — dépassement TOD_LIMIT]');
    SELECT COUNT(*), NVL(ROUND(SUM(ABS(LCY_CURR_BALANCE) - TOD_LIMIT),2),0)
      INTO v_count, v_num
    FROM STTM_CUST_ACCOUNT
    WHERE LCY_CURR_BALANCE < 0
      AND NVL(TOD_LIMIT,0) > 0
      AND ABS(LCY_CURR_BALANCE) > NVL(TOD_LIMIT,0);
    print_kv('  Comptes dépassant TOD', TO_CHAR(v_count));
    print_kv('  Cumul dépassement', TO_CHAR(v_num));

    -- 12.9 Ancienneté TOD (TOD_SINCE — bucket)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.9 Ancienneté TOD_SINCE (bucket)]');
    FOR r IN (
        SELECT bucket, nb FROM (
            SELECT CASE
                     WHEN TOD_SINCE IS NULL THEN '00_pas_de_TOD'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 30 THEN '01_0-30j'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 90 THEN '02_31-90j'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 365 THEN '03_91-365j'
                     ELSE '04_>365j'
                   END bucket, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT
            GROUP BY CASE
                     WHEN TOD_SINCE IS NULL THEN '00_pas_de_TOD'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 30 THEN '01_0-30j'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 90 THEN '02_31-90j'
                     WHEN TRUNC(SYSDATE) - TOD_SINCE <= 365 THEN '03_91-365j'
                     ELSE '04_>365j'
                   END
        ) ORDER BY bucket
    ) LOOP
        print_kv('  ' || r.bucket, TO_CHAR(r.nb));
    END LOOP;

    -- 12.10 Comptes dormants (DORMANCY_DATE non null / DORMANCY_DAYS > 0)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.10 Comptes dormants]');
    SELECT COUNT(*), NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0)
      INTO v_count, v_num
    FROM STTM_CUST_ACCOUNT
    WHERE DORMANCY_DATE IS NOT NULL;
    print_kv('  Comptes dormants', TO_CHAR(v_count));
    print_kv('  Soldes dormants (LCY)', TO_CHAR(v_num));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.10.b Distribution DORMANCY_DAYS]');
    FOR r IN (
        SELECT bucket, nb, sm FROM (
            SELECT CASE
                     WHEN NVL(DORMANCY_DAYS,0) = 0 THEN '00_actif'
                     WHEN DORMANCY_DAYS <= 180 THEN '01_1-180j'
                     WHEN DORMANCY_DAYS <= 365 THEN '02_181-365j'
                     WHEN DORMANCY_DAYS <= 730 THEN '03_1-2ans'
                     ELSE '04_>2ans'
                   END bucket,
                   COUNT(*) nb,
                   ROUND(SUM(LCY_CURR_BALANCE),2) sm
            FROM STTM_CUST_ACCOUNT
            GROUP BY CASE
                     WHEN NVL(DORMANCY_DAYS,0) = 0 THEN '00_actif'
                     WHEN DORMANCY_DAYS <= 180 THEN '01_1-180j'
                     WHEN DORMANCY_DAYS <= 365 THEN '02_181-365j'
                     WHEN DORMANCY_DAYS <= 730 THEN '03_1-2ans'
                     ELSE '04_>2ans'
                   END
        ) ORDER BY bucket
    ) LOOP
        print_kv('  ' || r.bucket, 'nb=' || TO_CHAR(r.nb) || ' | solde=' || TO_CHAR(r.sm));
    END LOOP;

    -- 12.11 ** ALERTE RA ** — DEFAULT_WAIVER = 'Y'
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.11 ** ALERTE RA ** — DEFAULT_WAIVER = Y]');
    FOR r IN (
        SELECT NVL(DEFAULT_WAIVER,'<NULL>') dw, COUNT(*) nb,
               NVL(ROUND(SUM(LCY_CURR_BALANCE),2),0) sm
        FROM STTM_CUST_ACCOUNT
        GROUP BY NVL(DEFAULT_WAIVER,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  DEFAULT_WAIVER=' || r.dw, 'nb=' || TO_CHAR(r.nb) || ' | solde=' || TO_CHAR(r.sm));
    END LOOP;

    -- 12.12 INF_WAIVE_ACC_OPEN_CHARGE (frais d'ouverture waivés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.12 INF_WAIVE_ACC_OPEN_CHARGE (waivers à l''ouverture)]');
    FOR r IN (
        SELECT NVL(INF_WAIVE_ACC_OPEN_CHARGE,'<NULL>') w, COUNT(*) nb
        FROM STTM_CUST_ACCOUNT
        GROUP BY NVL(INF_WAIVE_ACC_OPEN_CHARGE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  INF_WAIVE_ACC_OPEN_CHARGE=' || r.w, TO_CHAR(r.nb));
    END LOOP;

    -- 12.13 Top 15 comptes par solde créditeur (enjeu rémunération)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.13 Top 15 comptes par solde créditeur (LCY)]');
    FOR r IN (
        SELECT CUST_AC_NO, CCY, sm FROM (
            SELECT CUST_AC_NO, CCY, LCY_CURR_BALANCE sm
            FROM STTM_CUST_ACCOUNT
            WHERE LCY_CURR_BALANCE > 0
            ORDER BY LCY_CURR_BALANCE DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Cpt=' || r.CUST_AC_NO || ' / CCY=' || r.CCY, 'solde=' || TO_CHAR(r.sm));
    END LOOP;

    -- 12.14 Top 15 comptes par solde débiteur (enjeu recouvrement)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.14 Top 15 comptes par solde débiteur (LCY)]');
    FOR r IN (
        SELECT CUST_AC_NO, CCY, sm, tod FROM (
            SELECT CUST_AC_NO, CCY, LCY_CURR_BALANCE sm, TOD_LIMIT tod
            FROM STTM_CUST_ACCOUNT
            WHERE LCY_CURR_BALANCE < 0
            ORDER BY LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  Cpt=' || r.CUST_AC_NO || ' / CCY=' || r.CCY,
                 'solde=' || TO_CHAR(r.sm) || ' | TOD=' || TO_CHAR(NVL(r.tod,0)));
    END LOOP;

    -- 12.15 Volumétrie annuelle d'ouverture (AC_OPEN_DATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.15 Ouvertures de comptes par année]');
    FOR r IN (
        SELECT TO_CHAR(AC_OPEN_DATE,'YYYY') annee, COUNT(*) nb
        FROM STTM_CUST_ACCOUNT
        WHERE AC_OPEN_DATE IS NOT NULL
        GROUP BY TO_CHAR(AC_OPEN_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, TO_CHAR(r.nb));
    END LOOP;

    -- 12.16 INTERIM_DEBIT_AMT / INTERIM_CREDIT_AMT (turnovers provisoires)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.16 Turnovers provisoires (INTERIM_DEBIT_AMT / INTERIM_CREDIT_AMT)]');
    SELECT NVL(ROUND(SUM(INTERIM_DEBIT_AMT),2),0),
           NVL(ROUND(SUM(INTERIM_CREDIT_AMT),2),0)
      INTO v_num, v_num2
    FROM STTM_CUST_ACCOUNT;
    print_kv('  Cumul INTERIM_DEBIT_AMT', TO_CHAR(v_num));
    print_kv('  Cumul INTERIM_CREDIT_AMT', TO_CHAR(v_num2));

    -- 12.17 ACCOUNT_AUTO_CLOSED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.17 ACCOUNT_AUTO_CLOSED]');
    FOR r IN (
        SELECT NVL(ACCOUNT_AUTO_CLOSED,'<NULL>') ac, COUNT(*) nb
        FROM STTM_CUST_ACCOUNT
        GROUP BY NVL(ACCOUNT_AUTO_CLOSED,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ACCOUNT_AUTO_CLOSED=' || r.ac, TO_CHAR(r.nb));
    END LOOP;

    -- =========================================================
    -- 13. SITB_CONTRACT_MASTER & SITB_CYCLE_DETAIL
    --     Standing Instructions : impact sur revenus de commissions
    --     et risques de leakage via APPLY_CHG_* flags.
    --     Enjeux RA :
    --       - APPLY_CHG_SUXS/PEXC/REJT : charges appliquées ou non
    --         lors de succès / exécution partielle / rejet.
    --         'N' systématique = perte de revenus de frais SI,
    --       - ACTION_CODE_AMT : action si fonds insuffisants (R=reject,
    --         P=partial, F=force). Proportion de rejets = frais perdus,
    --       - MAX_RETRY_COUNT : nombre max de tentatives ;
    --         retries nombreux sans frais = leakage,
    --       - SITB_CYCLE_DETAIL : suivi des exécutions, retry_seq_no,
    --         agrégation des montants exécutés LCY,
    --       - SI_EXPIRY_DATE < aujourd'hui + SUBSYSTEM_STAT actif :
    --         incohérence (SI expirées mais non clôturées),
    --       - Auto-approbation (pas de CHECKER distinct) : contrôles
    --         4 yeux contournés sur setup SI.
    -- =========================================================
    print_section('13. SITB_CONTRACT_MASTER / SITB_CYCLE_DETAIL — Standing Instructions');

    -- 13.1 Volumétrie
    DBMS_OUTPUT.PUT_LINE('  [13.1 Volumétrie SI]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER;
    print_kv('  SITB_CONTRACT_MASTER (contrats SI)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL;
    print_kv('  SITB_CYCLE_DETAIL  (exécutions cycles)', TO_CHAR(v_count));

    -- 13.2 SUBSYSTEM_STAT (statut SI)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.2 Statut SUBSYSTEM_STAT (SITB_CONTRACT_MASTER)]');
    FOR r IN (
        SELECT NVL(SUBSYSTEM_STAT,'<NULL>') st, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(SUBSYSTEM_STAT,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  SUBSYSTEM_STAT=' || r.st, TO_CHAR(r.nb));
    END LOOP;

    -- 13.3 TRANSFER_TYPE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.3 TRANSFER_TYPE]');
    FOR r IN (
        SELECT NVL(TRANSFER_TYPE,'<NULL>') tt, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(TRANSFER_TYPE,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TRANSFER_TYPE=' || r.tt, TO_CHAR(r.nb));
    END LOOP;

    -- 13.4 ACTION_CODE_AMT : action sur fonds insuffisants
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.4 ACTION_CODE_AMT (action si montant insuffisant)]');
    FOR r IN (
        SELECT NVL(ACTION_CODE_AMT,'<NULL>') ac, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(ACTION_CODE_AMT,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ACTION_CODE_AMT=' || r.ac, TO_CHAR(r.nb));
    END LOOP;

    -- 13.5 APPLY_CHG_SUXS (charge sur exécution réussie)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.5 APPLY_CHG_SUXS (charges sur succès)]');
    FOR r IN (
        SELECT NVL(APPLY_CHG_SUXS,'<NULL>') f, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(APPLY_CHG_SUXS,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  APPLY_CHG_SUXS=' || r.f, TO_CHAR(r.nb));
    END LOOP;

    -- 13.6 APPLY_CHG_PEXC (exécution partielle)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.6 APPLY_CHG_PEXC (charges sur exécution partielle)]');
    FOR r IN (
        SELECT NVL(APPLY_CHG_PEXC,'<NULL>') f, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(APPLY_CHG_PEXC,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  APPLY_CHG_PEXC=' || r.f, TO_CHAR(r.nb));
    END LOOP;

    -- 13.7 APPLY_CHG_REJT (rejet)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.7 APPLY_CHG_REJT (charges sur rejet)]');
    FOR r IN (
        SELECT NVL(APPLY_CHG_REJT,'<NULL>') f, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(APPLY_CHG_REJT,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  APPLY_CHG_REJT=' || r.f, TO_CHAR(r.nb));
    END LOOP;

    -- 13.8 ** ALERTE RA ** : SI sans AUCUNE charge paramétrée (SUXS=PEXC=REJT='N')
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.8 ** ALERTE RA ** SI sans charge paramétrée (SUXS=PEXC=REJT=N)]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
     WHERE NVL(APPLY_CHG_SUXS,'N')='N'
       AND NVL(APPLY_CHG_PEXC,'N')='N'
       AND NVL(APPLY_CHG_REJT,'N')='N';
    print_kv('  Nombre SI sans charges', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(SI_AMT),2),0) INTO v_num FROM SITB_CONTRACT_MASTER
     WHERE NVL(APPLY_CHG_SUXS,'N')='N'
       AND NVL(APPLY_CHG_PEXC,'N')='N'
       AND NVL(APPLY_CHG_REJT,'N')='N';
    print_kv('  Cumul SI_AMT concerné', TO_CHAR(v_num));

    -- 13.9 ** ALERTE RA ** : SI rejet sans charge (APPLY_CHG_REJT='N')
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.9 ** ALERTE RA ** SI avec rejet non facturé (APPLY_CHG_REJT=N)]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
     WHERE NVL(APPLY_CHG_REJT,'N')='N';
    print_kv('  Nb SI rejet non facturé', TO_CHAR(v_count));

    -- 13.10 MAX_RETRY_COUNT distribution
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.10 MAX_RETRY_COUNT (distribution)]');
    FOR r IN (
        SELECT NVL(TO_CHAR(MAX_RETRY_COUNT),'<NULL>') mx, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(TO_CHAR(MAX_RETRY_COUNT),'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  MAX_RETRY_COUNT=' || r.mx, TO_CHAR(r.nb));
    END LOOP;

    -- 13.11 SI_AMT : devises & cumuls
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.11 SI_AMT par SI_AMT_CCY (TOP 10)]');
    FOR r IN (
        SELECT ccy, nb, sm FROM (
            SELECT NVL(SI_AMT_CCY,'<NULL>') ccy,
                   COUNT(*) nb,
                   NVL(ROUND(SUM(SI_AMT),2),0) sm
            FROM SITB_CONTRACT_MASTER
            GROUP BY NVL(SI_AMT_CCY,'<NULL>')
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY=' || r.ccy, 'nb=' || TO_CHAR(r.nb) || ' | sum SI_AMT=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.12 ** ALERTE RA ** : SI expirées mais encore actives
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12 ** ALERTE RA ** SI_EXPIRY_DATE passée mais SI non clôturée]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
     WHERE SI_EXPIRY_DATE IS NOT NULL
       AND SI_EXPIRY_DATE < TRUNC(SYSDATE)
       AND NVL(SUBSYSTEM_STAT,'A') NOT IN ('C','L','V','X');
    print_kv('  Nb SI expirées mais actives', TO_CHAR(v_count));

    -- 13.13 CHARGE_WHOM (qui paie la charge ?)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.13 CHARGE_WHOM]');
    FOR r IN (
        SELECT NVL(CHARGE_WHOM,'<NULL>') c, COUNT(*) nb
        FROM SITB_CONTRACT_MASTER
        GROUP BY NVL(CHARGE_WHOM,'<NULL>')
        ORDER BY nb DESC
    ) LOOP
        print_kv('  CHARGE_WHOM=' || r.c, TO_CHAR(r.nb));
    END LOOP;

    -- 13.14 SITB_CYCLE_DETAIL : EVENT_CODE (types d'événements)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.14 EVENT_CODE (SITB_CYCLE_DETAIL) — TOP 15]');
    FOR r IN (
        SELECT ec, nb FROM (
            SELECT NVL(EVENT_CODE,'<NULL>') ec, COUNT(*) nb
            FROM SITB_CYCLE_DETAIL
            GROUP BY NVL(EVENT_CODE,'<NULL>')
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  EVENT_CODE=' || r.ec, TO_CHAR(r.nb));
    END LOOP;

    -- 13.15 RETRY_SEQ_NO distribution : volume de retries
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.15 RETRY_SEQ_NO (distribution SITB_CYCLE_DETAIL)]');
    FOR r IN (
        SELECT rsq, nb FROM (
            SELECT NVL(TO_CHAR(RETRY_SEQ_NO),'<NULL>') rsq, COUNT(*) nb
            FROM SITB_CYCLE_DETAIL
            GROUP BY NVL(TO_CHAR(RETRY_SEQ_NO),'<NULL>')
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  RETRY_SEQ_NO=' || r.rsq, TO_CHAR(r.nb));
    END LOOP;

    -- 13.16 ** ALERTE RA ** : retries nombreux (RETRY_SEQ_NO >= 3)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.16 ** ALERTE RA ** Retries >= 3 (SITB_CYCLE_DETAIL)]');
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL
     WHERE RETRY_SEQ_NO >= 3;
    print_kv('  Nb lignes cycle avec retry >=3', TO_CHAR(v_count));

    -- 13.17 AMT_EXECUTED_LCY / SI_AMT_EXECUTED cumuls
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.17 Cumuls d''exécution SITB_CYCLE_DETAIL]');
    SELECT NVL(ROUND(SUM(AMT_EXECUTED_LCY),2),0),
           NVL(ROUND(SUM(SI_AMT_EXECUTED),2),0)
      INTO v_num, v_num2
    FROM SITB_CYCLE_DETAIL;
    print_kv('  SUM AMT_EXECUTED_LCY', TO_CHAR(v_num));
    print_kv('  SUM SI_AMT_EXECUTED ', TO_CHAR(v_num2));

    -- 13.18 AMT_DEBITED vs AMT_CREDITED (écarts)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.18 ** ALERTE RA ** Écarts AMT_DEBITED vs AMT_CREDITED]');
    SELECT NVL(ROUND(SUM(AMT_DEBITED),2),0),
           NVL(ROUND(SUM(AMT_CREDITED),2),0)
      INTO v_num, v_num2
    FROM SITB_CYCLE_DETAIL;
    print_kv('  SUM AMT_DEBITED ', TO_CHAR(v_num));
    print_kv('  SUM AMT_CREDITED', TO_CHAR(v_num2));
    print_kv('  ECART (DR - CR) ', TO_CHAR(ROUND(v_num - v_num2,2)));

    -- 13.19 Comptes débiteurs les plus sollicités (TOP 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.19 TOP DR_ACCOUNT (comptes SI débiteurs)]');
    FOR r IN (
        SELECT ac, nb, sm FROM (
            SELECT DR_ACCOUNT ac, COUNT(*) nb,
                   NVL(ROUND(SUM(AMT_DEBITED),2),0) sm
            FROM SITB_CYCLE_DETAIL
            WHERE DR_ACCOUNT IS NOT NULL
            GROUP BY DR_ACCOUNT
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  DR=' || r.ac, 'nb=' || TO_CHAR(r.nb) || ' | debit=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.20 Comptes créditeurs les plus sollicités (TOP 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.20 TOP CR_ACCOUNT (comptes SI créditeurs)]');
    FOR r IN (
        SELECT ac, nb, sm FROM (
            SELECT CR_ACCOUNT ac, COUNT(*) nb,
                   NVL(ROUND(SUM(AMT_CREDITED),2),0) sm
            FROM SITB_CYCLE_DETAIL
            WHERE CR_ACCOUNT IS NOT NULL
            GROUP BY CR_ACCOUNT
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CR=' || r.ac, 'nb=' || TO_CHAR(r.nb) || ' | credit=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.21 Volumétrie par année d'exécution (RETRY_DATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.21 Exécutions SI par année (RETRY_DATE)]');
    FOR r IN (
        SELECT TO_CHAR(RETRY_DATE,'YYYY') an, COUNT(*) nb,
               NVL(ROUND(SUM(AMT_EXECUTED_LCY),2),0) sm
        FROM SITB_CYCLE_DETAIL
        WHERE RETRY_DATE IS NOT NULL
        GROUP BY TO_CHAR(RETRY_DATE,'YYYY')
        ORDER BY an
    ) LOOP
        print_kv('  ' || r.an,
                 'nb=' || TO_CHAR(r.nb) || ' | executed_lcy=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.22 Contrats SI les plus exécutés (TOP 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.22 TOP contrats SI par nombre d''exécutions]');
    FOR r IN (
        SELECT ref, nb, sm FROM (
            SELECT CONTRACT_REF_NO ref, COUNT(*) nb,
                   NVL(ROUND(SUM(AMT_EXECUTED_LCY),2),0) sm
            FROM SITB_CYCLE_DETAIL
            GROUP BY CONTRACT_REF_NO
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  Ref=' || r.ref, 'nb=' || TO_CHAR(r.nb) || ' | lcy=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.23 ** ALERTE RA ** : cycles avec SI_AMT_EXECUTED < SI_AMT (exec partielles)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.23 ** ALERTE RA ** Exécutions partielles vs montant SI défini]');
    SELECT COUNT(*) INTO v_count
    FROM SITB_CYCLE_DETAIL d
    JOIN SITB_CONTRACT_MASTER m ON m.CONTRACT_REF_NO = d.CONTRACT_REF_NO
    WHERE d.SI_AMT_EXECUTED IS NOT NULL
      AND m.SI_AMT IS NOT NULL
      AND d.SI_AMT_EXECUTED > 0
      AND d.SI_AMT_EXECUTED < m.SI_AMT;
    print_kv('  Nb cycles en exécution partielle', TO_CHAR(v_count));

    -- 13.24 PRIORITY (distribution)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.24 PRIORITY (SITB_CONTRACT_MASTER)]');
    FOR r IN (
        SELECT pr, nb FROM (
            SELECT NVL(TO_CHAR(PRIORITY),'<NULL>') pr, COUNT(*) nb
            FROM SITB_CONTRACT_MASTER
            GROUP BY NVL(TO_CHAR(PRIORITY),'<NULL>')
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  PRIORITY=' || r.pr, TO_CHAR(r.nb));
    END LOOP;
END;
/
