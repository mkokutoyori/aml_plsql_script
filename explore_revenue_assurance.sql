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
    -- 4. CLTB_ACCOUNT_COMPONENTS — COMPOSANTS DE PRET & WAIVERS
    --    Angle Revenue Assurance :
    --     - un composant INTEREST/PENAL/CHARGE marqué WAIVE='Y'
    --       signifie qu'aucun intérêt/commission n'est collecté
    --       ⇒ piste majeure de fuite de revenu si abus.
    --     - les SPL_INTEREST (taux spécial dérogatoire), les
    --       NEGOTIATED_RATE et les écarts ORG_EXCH_RATE vs
    --       EXCHANGE_RATE donnent des dérogations commerciales
    --       à auditer.
    --     - le day count (DAYS_MTH / DAYS_YEAR) a un impact
    --       direct sur le revenu d'intérêts calculé.
    -- =========================================================
    print_section('4. CLTB_ACCOUNT_COMPONENTS — composants de prêt & waivers');

    -- 4.1 Volumétrie globale composants
    DBMS_OUTPUT.PUT_LINE('  [4.1 Volumétrie globale]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Total composants prêt', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Comptes prêt distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Branches distinctes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COMPONENT_NAME) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  COMPONENT_NAME distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COMPONENT_CCY) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS;
    print_kv('  Devises distinctes', TO_CHAR(v_count));

    -- 4.2 Répartition par COMPONENT_TYPE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.2 Répartition par COMPONENT_TYPE]');
    FOR r IN (
        SELECT NVL(COMPONENT_TYPE,'(NULL)') COMPONENT_TYPE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY COMPONENT_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  COMPONENT_TYPE = ' || r.COMPONENT_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.3 Top 20 COMPONENT_NAME
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.3 Top 20 COMPONENT_NAME (inclut MAIN_PNT, INTEREST, PENALTY, ...)]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY COMPONENT_NAME ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  COMPONENT_NAME = ' || r.COMPONENT_NAME, TO_CHAR(r.nb));
    END LOOP;

    -- 4.4 MAIN_COMPONENT (marque le composant principal de l'échéancier)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.4 Répartition MAIN_COMPONENT]');
    FOR r IN (
        SELECT NVL(MAIN_COMPONENT,'(NULL)') MAIN_COMPONENT, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY MAIN_COMPONENT ORDER BY nb DESC
    ) LOOP
        print_kv('  MAIN_COMPONENT = ' || r.MAIN_COMPONENT, TO_CHAR(r.nb));
    END LOOP;

    -- 4.5 WAIVE — analyse du waiver sur composant
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5 WAIVE — flag de renonciation au composant]');
    FOR r IN (
        SELECT NVL(WAIVE,'(NULL)') WAIVE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY WAIVE ORDER BY nb DESC
    ) LOOP
        print_kv('  WAIVE = ' || r.WAIVE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.5.b WAIVE='Y' par COMPONENT_TYPE (là où la fuite se matérialise)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5.b WAIVE=''Y'' par COMPONENT_TYPE]');
    FOR r IN (
        SELECT NVL(COMPONENT_TYPE,'(NULL)') COMPONENT_TYPE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        WHERE WAIVE = 'Y'
        GROUP BY COMPONENT_TYPE
        ORDER BY nb DESC
    ) LOOP
        print_kv('  TYPE waivé = ' || r.COMPONENT_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.5.c WAIVE='Y' par COMPONENT_NAME — top 15
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5.c Top 15 COMPONENT_NAME waivés (WAIVE=''Y'')]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            WHERE WAIVE = 'Y'
            GROUP BY COMPONENT_NAME
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME, TO_CHAR(r.nb) || ' composant(s) waivé(s)');
    END LOOP;

    -- 4.5.d WAIVE='Y' par BRANCH_CODE — top 15 (concentration agence)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5.d Top 15 BRANCHES utilisant des waivers]');
    FOR r IN (
        SELECT BRANCH_CODE, nb_w, nb_tot,
               ROUND(100 * nb_w / NULLIF(nb_tot,0), 2) pct
        FROM (
            SELECT BRANCH_CODE,
                   SUM(CASE WHEN WAIVE = 'Y' THEN 1 ELSE 0 END) nb_w,
                   COUNT(*) nb_tot
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY BRANCH_CODE
            ORDER BY nb_w DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  BRANCHE ' || r.BRANCH_CODE,
                 'waivés=' || TO_CHAR(r.nb_w) || ' / total=' || TO_CHAR(r.nb_tot) ||
                 ' (' || TO_CHAR(r.pct) || ' %)');
    END LOOP;

    -- 4.5.e Comptes concentrant le plus de composants waivés
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.5.e Top 15 comptes prêt avec composants waivés]');
    FOR r IN (
        SELECT ACCOUNT_NUMBER, BRANCH_CODE, nb FROM (
            SELECT ACCOUNT_NUMBER, BRANCH_CODE, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            WHERE WAIVE = 'Y'
            GROUP BY ACCOUNT_NUMBER, BRANCH_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRANCH_CODE || ' / ' || r.ACCOUNT_NUMBER,
                 TO_CHAR(r.nb) || ' composant(s) waivé(s)');
    END LOOP;

    -- 4.6 CAPITALIZED (intérêt capitalisé = reporté sur le principal)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.6 CAPITALIZED — composants capitalisés]');
    FOR r IN (
        SELECT NVL(CAPITALIZED,'(NULL)') CAPITALIZED, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY CAPITALIZED ORDER BY nb DESC
    ) LOOP
        print_kv('  CAPITALIZED = ' || r.CAPITALIZED, TO_CHAR(r.nb));
    END LOOP;

    -- 4.7 LIQUIDATION_MODE (auto/manual) — auto = collecte automatique
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.7 LIQUIDATION_MODE des composants]');
    FOR r IN (
        SELECT NVL(LIQUIDATION_MODE,'(NULL)') LIQUIDATION_MODE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY LIQUIDATION_MODE ORDER BY nb DESC
    ) LOOP
        print_kv('  LIQUIDATION_MODE = ' || r.LIQUIDATION_MODE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.8 SPL_INTEREST (intérêt spécial / dérogatoire)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.8 SPL_INTEREST — intérêts dérogatoires]');
    FOR r IN (
        SELECT NVL(SPL_INTEREST,'(NULL)') SPL_INTEREST, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY SPL_INTEREST ORDER BY nb DESC
    ) LOOP
        print_kv('  SPL_INTEREST = ' || r.SPL_INTEREST, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(MIN(SPL_INTEREST_AMT),2) mn,
               ROUND(MAX(SPL_INTEREST_AMT),2) mx,
               ROUND(AVG(SPL_INTEREST_AMT),2) av,
               ROUND(SUM(SPL_INTEREST_AMT),2) sm
        FROM CLTB_ACCOUNT_COMPONENTS
        WHERE SPL_INTEREST = 'Y' AND SPL_INTEREST_AMT IS NOT NULL
    ) LOOP
        print_kv('  SPL_INTEREST_AMT — nb', TO_CHAR(r.nb));
        print_kv('  SPL_INTEREST_AMT — min', TO_CHAR(r.mn));
        print_kv('  SPL_INTEREST_AMT — max', TO_CHAR(r.mx));
        print_kv('  SPL_INTEREST_AMT — moy', TO_CHAR(r.av));
        print_kv('  SPL_INTEREST_AMT — sum', TO_CHAR(r.sm));
    END LOOP;

    -- 4.9 Taux négociés (NEGOTIATED_RATE) — dérogations de change
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.9 Taux négociés CR (NEGOTIATED_RATE)]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE NEGOTIATED_RATE IS NOT NULL AND NEGOTIATED_RATE > 0;
    print_kv('  Composants avec NEGOTIATED_RATE renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE NEGOTIATION_REF_NO IS NOT NULL;
    print_kv('  Composants avec NEGOTIATION_REF_NO', TO_CHAR(v_count));
    FOR r IN (
        SELECT ROUND(MIN(NEGOTIATED_RATE),6) mn,
               ROUND(MAX(NEGOTIATED_RATE),6) mx,
               ROUND(AVG(NEGOTIATED_RATE),6) av
        FROM CLTB_ACCOUNT_COMPONENTS
        WHERE NEGOTIATED_RATE IS NOT NULL AND NEGOTIATED_RATE > 0
    ) LOOP
        print_kv('  NEGOTIATED_RATE min', TO_CHAR(r.mn));
        print_kv('  NEGOTIATED_RATE max', TO_CHAR(r.mx));
        print_kv('  NEGOTIATED_RATE moy', TO_CHAR(r.av));
    END LOOP;

    -- 4.9.b Ecart ORG_EXCH_RATE vs EXCHANGE_RATE (dérogation FX)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.9.b Dérogation FX : ORG_EXCH_RATE vs EXCHANGE_RATE]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE ORG_EXCH_RATE IS NOT NULL AND EXCHANGE_RATE IS NOT NULL
      AND ORG_EXCH_RATE <> 0
      AND ABS(EXCHANGE_RATE - ORG_EXCH_RATE) / ORG_EXCH_RATE > 0.001;
    print_kv('  Composants avec écart taux CR > 0,1 %', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE ORG_EXCH_RATE_DR IS NOT NULL AND EXCHANGE_RATE_DR IS NOT NULL
      AND ORG_EXCH_RATE_DR <> 0
      AND ABS(EXCHANGE_RATE_DR - ORG_EXCH_RATE_DR) / ORG_EXCH_RATE_DR > 0.001;
    print_kv('  Composants avec écart taux DR > 0,1 %', TO_CHAR(v_count));

    -- 4.10 Day count convention (impact direct sur revenu d'intérêts)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.10 Day count convention (DAYS_MTH / DAYS_YEAR)]');
    FOR r IN (
        SELECT NVL(DAYS_MTH,'(NULL)') DAYS_MTH, NVL(DAYS_YEAR,'(NULL)') DAYS_YEAR, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY DAYS_MTH, DAYS_YEAR
        ORDER BY nb DESC
    ) LOOP
        print_kv('  MONTH/' || r.DAYS_MTH || ' YEAR/' || r.DAYS_YEAR, TO_CHAR(r.nb));
    END LOOP;

    -- 4.11 IRR_APPLICABLE (composant entrant dans calcul du TAEG)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.11 IRR_APPLICABLE — entre dans le calcul TAEG]');
    FOR r IN (
        SELECT NVL(IRR_APPLICABLE,'(NULL)') IRR_APPLICABLE, COUNT(*) nb
        FROM CLTB_ACCOUNT_COMPONENTS
        GROUP BY IRR_APPLICABLE ORDER BY nb DESC
    ) LOOP
        print_kv('  IRR_APPLICABLE = ' || r.IRR_APPLICABLE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.12 PENAL_BASIS_COMP — base de calcul des pénalités
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.12 PENAL_BASIS_COMP — composant servant d''assise aux pénalités]');
    FOR r IN (
        SELECT PENAL_BASIS_COMP, nb FROM (
            SELECT NVL(PENAL_BASIS_COMP,'(NULL)') PENAL_BASIS_COMP, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY PENAL_BASIS_COMP ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PENAL_BASIS_COMP = ' || r.PENAL_BASIS_COMP, TO_CHAR(r.nb));
    END LOOP;

    -- 4.13 USE_GUARANTOR / VERIFY_FUNDS (impact recouvrement)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.13 Recouvrement : USE_GUARANTOR / VERIFY_FUNDS]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS WHERE USE_GUARANTOR = 'Y';
    print_kv('  USE_GUARANTOR = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS WHERE VERIFY_FUNDS = 'Y';
    print_kv('  VERIFY_FUNDS = Y', TO_CHAR(v_count));

    -- 4.14 Mode de paiement (DR/CR/RE) — canal de collecte
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.14 Canal de collecte CR_PAYMENT_MODE — top 10]');
    FOR r IN (
        SELECT CR_PAYMENT_MODE, nb FROM (
            SELECT NVL(CR_PAYMENT_MODE,'(NULL)') CR_PAYMENT_MODE, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY CR_PAYMENT_MODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CR_PAYMENT_MODE = ' || r.CR_PAYMENT_MODE, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.14.b Canal DR_PAYMENT_MODE — top 10]');
    FOR r IN (
        SELECT DR_PAYMENT_MODE, nb FROM (
            SELECT NVL(DR_PAYMENT_MODE,'(NULL)') DR_PAYMENT_MODE, COUNT(*) nb
            FROM CLTB_ACCOUNT_COMPONENTS
            GROUP BY DR_PAYMENT_MODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  DR_PAYMENT_MODE = ' || r.DR_PAYMENT_MODE, TO_CHAR(r.nb));
    END LOOP;

    -- 4.15 Croisement WAIVE × SPL_INTEREST (cumul de dérogations)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [4.15 Cumul de dérogations (WAIVE=''Y'' ET SPL_INTEREST=''Y'')]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE WAIVE = 'Y' AND SPL_INTEREST = 'Y';
    print_kv('  Composants cumulant waiver + intérêt spécial', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS
    WHERE WAIVE = 'Y' AND NEGOTIATED_RATE IS NOT NULL AND NEGOTIATED_RATE > 0;
    print_kv('  Composants waivés ET taux négocié', TO_CHAR(v_count));

    -- =========================================================
    -- 5. CLTB_ACCOUNT_SCHEDULES — ECHEANCES & OVERDUE
    --    Angle Revenue Assurance :
    --     - montants dus (ORIG_AMOUNT_DUE, AMOUNT_DUE) vs
    --       montants effectivement perçus (AMOUNT_SETTLED) vs
    --       montants mis en suspens, waivés ou passés en
    --       writeoff : tout écart = fuite potentielle.
    --     - échéances échues non collectées (AMOUNT_OVERDUE),
    --       vieillissement de la créance (ageing).
    --     - intérêts accrus non facturés (ACCRUED_AMOUNT)
    --       et intérêts en suspens (SUSP_AMT_*) = revenu
    --       constaté mais non réalisé.
    --     - MORA_INT (intérêts moratoires) : revenu
    --       attendu sur retards.
    -- =========================================================
    print_section('5. CLTB_ACCOUNT_SCHEDULES — échéances & overdue');

    -- 5.1 Volumétrie globale
    DBMS_OUTPUT.PUT_LINE('  [5.1 Volumétrie globale des échéances]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Total lignes échéance', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Comptes prêt distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COMPONENT_NAME) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Composants distincts (COMPONENT_NAME)', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT SETTLEMENT_CCY) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  Devises de règlement distinctes', TO_CHAR(v_count));

    -- 5.2 Plage temporelle
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.2 Plage temporelle des échéances]');
    FOR r IN (
        SELECT MIN(SCHEDULE_ST_DATE) dt_min, MAX(SCHEDULE_ST_DATE) dt_max
        FROM CLTB_ACCOUNT_SCHEDULES
    ) LOOP
        print_kv('  SCHEDULE_ST_DATE min', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  SCHEDULE_ST_DATE max', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (
        SELECT MIN(SCHEDULE_DUE_DATE) dt_min, MAX(SCHEDULE_DUE_DATE) dt_max
        FROM CLTB_ACCOUNT_SCHEDULES
    ) LOOP
        print_kv('  SCHEDULE_DUE_DATE min', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  SCHEDULE_DUE_DATE max', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (
        SELECT MIN(LAST_PMNT_VALUE_DATE) dt_min, MAX(LAST_PMNT_VALUE_DATE) dt_max
        FROM CLTB_ACCOUNT_SCHEDULES
    ) LOOP
        print_kv('  LAST_PMNT_VALUE_DATE min', TO_CHAR(r.dt_min, 'DD/MM/YYYY'));
        print_kv('  LAST_PMNT_VALUE_DATE max', TO_CHAR(r.dt_max, 'DD/MM/YYYY'));
    END LOOP;

    -- 5.3 Répartition SCHEDULE_TYPE / SCH_STATUS / SCHEDULE_FLAG / WAIVER_FLAG
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.3 Répartition SCHEDULE_TYPE]');
    FOR r IN (
        SELECT NVL(SCHEDULE_TYPE,'(NULL)') SCHEDULE_TYPE, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY SCHEDULE_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  SCHEDULE_TYPE = ' || r.SCHEDULE_TYPE, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.3.b Répartition SCH_STATUS]');
    FOR r IN (
        SELECT NVL(SCH_STATUS,'(NULL)') SCH_STATUS, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY SCH_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  SCH_STATUS = ' || r.SCH_STATUS, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.3.c Répartition SCHEDULE_FLAG]');
    FOR r IN (
        SELECT NVL(SCHEDULE_FLAG,'(NULL)') SCHEDULE_FLAG, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY SCHEDULE_FLAG ORDER BY nb DESC
    ) LOOP
        print_kv('  SCHEDULE_FLAG = ' || r.SCHEDULE_FLAG, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.3.d Répartition WAIVER_FLAG sur échéance]');
    FOR r IN (
        SELECT NVL(WAIVER_FLAG,'(NULL)') WAIVER_FLAG, COUNT(*) nb
        FROM CLTB_ACCOUNT_SCHEDULES
        GROUP BY WAIVER_FLAG ORDER BY nb DESC
    ) LOOP
        print_kv('  WAIVER_FLAG = ' || r.WAIVER_FLAG, TO_CHAR(r.nb));
    END LOOP;

    -- 5.4 Montants totaux DUS / SETTLES / OVERDUE / WAIVED / WRITEOFF
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.4 Agrégats financiers globaux (LCY_EQUIVALENT)]');
    FOR r IN (
        SELECT
            ROUND(SUM(ORIG_AMOUNT_DUE),2)  sm_orig,
            ROUND(SUM(AMOUNT_DUE),2)       sm_due,
            ROUND(SUM(AMOUNT_SETTLED),2)   sm_set,
            ROUND(SUM(AMOUNT_OVERDUE),2)   sm_over,
            ROUND(SUM(AMOUNT_WAIVED),2)    sm_waiv,
            ROUND(SUM(WRITEOFF_AMT),2)     sm_wo,
            ROUND(SUM(ACCRUED_AMOUNT),2)   sm_acc,
            ROUND(SUM(LCY_EQUIVALENT),2)   sm_lcy
        FROM CLTB_ACCOUNT_SCHEDULES
    ) LOOP
        print_kv('  SUM ORIG_AMOUNT_DUE', TO_CHAR(r.sm_orig));
        print_kv('  SUM AMOUNT_DUE', TO_CHAR(r.sm_due));
        print_kv('  SUM AMOUNT_SETTLED', TO_CHAR(r.sm_set));
        print_kv('  SUM AMOUNT_OVERDUE', TO_CHAR(r.sm_over));
        print_kv('  SUM AMOUNT_WAIVED', TO_CHAR(r.sm_waiv));
        print_kv('  SUM WRITEOFF_AMT', TO_CHAR(r.sm_wo));
        print_kv('  SUM ACCRUED_AMOUNT', TO_CHAR(r.sm_acc));
        print_kv('  SUM LCY_EQUIVALENT', TO_CHAR(r.sm_lcy));
    END LOOP;

    -- 5.4.b Agrégats par COMPONENT_NAME — top 15 en montant dû
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.4.b Top 15 COMPONENT_NAME par AMOUNT_DUE]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm_due, sm_set, sm_over, sm_waiv FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME,
                   COUNT(*) nb,
                   ROUND(SUM(AMOUNT_DUE),2)     sm_due,
                   ROUND(SUM(AMOUNT_SETTLED),2) sm_set,
                   ROUND(SUM(AMOUNT_OVERDUE),2) sm_over,
                   ROUND(SUM(AMOUNT_WAIVED),2)  sm_waiv
            FROM CLTB_ACCOUNT_SCHEDULES
            GROUP BY COMPONENT_NAME
            ORDER BY sm_due DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME,
                 'due=' || TO_CHAR(r.sm_due) ||
                 ' | set=' || TO_CHAR(r.sm_set) ||
                 ' | over=' || TO_CHAR(r.sm_over) ||
                 ' | waiv=' || TO_CHAR(r.sm_waiv));
    END LOOP;

    -- 5.5 OVERDUE — échéances échues non soldées
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.5 Echéances échues non soldées (AMOUNT_OVERDUE > 0)]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_OVERDUE > 0;
    print_kv('  Nb échéances overdue', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(AMOUNT_OVERDUE),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_OVERDUE > 0;
    print_kv('  SUM AMOUNT_OVERDUE', TO_CHAR(v_num));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_OVERDUE > 0;
    print_kv('  Comptes prêt concernés', TO_CHAR(v_count));

    -- 5.5.b Ageing des overdue (days past due)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.5.b Ageing des AMOUNT_OVERDUE vs SYSDATE]');
    FOR r IN (
        SELECT
            CASE
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   30 THEN '0-30 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   60 THEN '31-60 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   90 THEN '61-90 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=  180 THEN '91-180 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=  360 THEN '181-360 j'
                ELSE '> 360 j'
            END bucket,
            COUNT(*) nb,
            ROUND(SUM(AMOUNT_OVERDUE),2) sm
        FROM CLTB_ACCOUNT_SCHEDULES
        WHERE AMOUNT_OVERDUE > 0 AND SCHEDULE_DUE_DATE IS NOT NULL
        GROUP BY
            CASE
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   30 THEN '0-30 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   60 THEN '31-60 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=   90 THEN '61-90 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=  180 THEN '91-180 j'
                WHEN SYSDATE - SCHEDULE_DUE_DATE <=  360 THEN '181-360 j'
                ELSE '> 360 j'
            END
        ORDER BY bucket
    ) LOOP
        print_kv('  Bucket ' || r.bucket, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.5.c Overdue par COMPONENT_NAME — top 10
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.5.c Top 10 COMPONENT_NAME en overdue]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_OVERDUE),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_OVERDUE > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.6 WAIVED — montants effectivement waivés à l'échéance
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6 Montants waivés (AMOUNT_WAIVED > 0)]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_WAIVED > 0;
    print_kv('  Nb échéances avec waiver', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(AMOUNT_WAIVED),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_WAIVED > 0;
    print_kv('  SUM AMOUNT_WAIVED', TO_CHAR(v_num));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE AMOUNT_WAIVED > 0;
    print_kv('  Comptes prêt concernés', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6.b Top 10 COMPONENT_NAME les plus waivés]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_WAIVED),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_WAIVED > 0
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.6.c Top 15 BRANCHES par volume waivé]');
    FOR r IN (
        SELECT BRANCH_CODE, nb, sm FROM (
            SELECT BRANCH_CODE, COUNT(*) nb, ROUND(SUM(AMOUNT_WAIVED),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_WAIVED > 0
            GROUP BY BRANCH_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  BRANCHE ' || r.BRANCH_CODE, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.7 WRITEOFF — passage en perte
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.7 Writeoff — échéances passées en perte]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE WRITEOFF_AMT > 0;
    print_kv('  Nb échéances writeoff', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(WRITEOFF_AMT),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES WHERE WRITEOFF_AMT > 0;
    print_kv('  SUM WRITEOFF_AMT', TO_CHAR(v_num));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE WRITEOFF_AMT > 0;
    print_kv('  Comptes concernés', TO_CHAR(v_count));

    -- 5.8 SUSPENSE — intérêts en suspens (non réalisés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.8 Suspense (intérêt constaté mais non réalisé)]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE SUSP_AMT_DUE > 0;
    print_kv('  Nb lignes SUSP_AMT_DUE > 0', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(SUSP_AMT_DUE),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  SUM SUSP_AMT_DUE', TO_CHAR(v_num));
    SELECT NVL(ROUND(SUM(SUSP_AMT_SETTLED),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  SUM SUSP_AMT_SETTLED', TO_CHAR(v_num));
    SELECT NVL(ROUND(SUM(SUSP_AMT_LCY),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  SUM SUSP_AMT_LCY', TO_CHAR(v_num));

    -- 5.9 MORA_INT — intérêts moratoires
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.9 MORA_INT (intérêts moratoires sur retard)]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES WHERE MORA_INT > 0;
    print_kv('  Nb échéances avec MORA_INT > 0', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(MORA_INT),2),0) INTO v_num FROM CLTB_ACCOUNT_SCHEDULES;
    print_kv('  SUM MORA_INT', TO_CHAR(v_num));

    -- 5.10 EMI_AMOUNT (annuités)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.10 EMI_AMOUNT — stats annuités]');
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(MIN(EMI_AMOUNT),2) mn,
               ROUND(MAX(EMI_AMOUNT),2) mx,
               ROUND(AVG(EMI_AMOUNT),2) av
        FROM CLTB_ACCOUNT_SCHEDULES WHERE EMI_AMOUNT > 0
    ) LOOP
        print_kv('  EMI — nb', TO_CHAR(r.nb));
        print_kv('  EMI — min', TO_CHAR(r.mn));
        print_kv('  EMI — max', TO_CHAR(r.mx));
        print_kv('  EMI — moy', TO_CHAR(r.av));
    END LOOP;

    -- 5.11 Cohérence ORIG_AMOUNT_DUE vs AMOUNT_DUE vs AMOUNT_SETTLED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.11 Cohérences montants dus / réglés / restants]');
    -- réglé > dû (anomalie)
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES
    WHERE AMOUNT_SETTLED > ORIG_AMOUNT_DUE + 0.01
      AND ORIG_AMOUNT_DUE > 0;
    print_kv('  AMOUNT_SETTLED > ORIG_AMOUNT_DUE', TO_CHAR(v_count));
    -- dû < settlé + overdue + waived (écart global)
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES
    WHERE ABS(NVL(AMOUNT_SETTLED,0) + NVL(AMOUNT_OVERDUE,0) + NVL(AMOUNT_WAIVED,0)
              + NVL(WRITEOFF_AMT,0) - NVL(ORIG_AMOUNT_DUE,0)) > 1
      AND SCH_STATUS IN ('L','P'); -- L=Liquidated, P=Pending
    print_kv('  Ecart ORIG_DUE vs (SET+OVER+WAIV+WO) > 1 unité', TO_CHAR(v_count));
    -- échéance passée non soldée ni overdue
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SCHEDULE_DUE_DATE < SYSDATE
      AND NVL(AMOUNT_SETTLED,0) = 0
      AND NVL(AMOUNT_OVERDUE,0) = 0
      AND NVL(AMOUNT_WAIVED,0) = 0
      AND NVL(WRITEOFF_AMT,0) = 0
      AND ORIG_AMOUNT_DUE > 0;
    print_kv('  Echues non soldées / non overdue (anomalie)', TO_CHAR(v_count));

    -- 5.12 Volumétrie annuelle (échéances créées)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.12 Volumétrie annuelle par SCHEDULE_DUE_DATE]');
    FOR r IN (
        SELECT TO_CHAR(SCHEDULE_DUE_DATE,'YYYY') annee,
               COUNT(*) nb,
               ROUND(SUM(AMOUNT_DUE),2) sm_due,
               ROUND(SUM(AMOUNT_OVERDUE),2) sm_over
        FROM CLTB_ACCOUNT_SCHEDULES
        WHERE SCHEDULE_DUE_DATE IS NOT NULL
        GROUP BY TO_CHAR(SCHEDULE_DUE_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee,
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | due=' || TO_CHAR(r.sm_due) ||
                 ' | over=' || TO_CHAR(r.sm_over));
    END LOOP;

    -- 5.13 Comptes concentrant les impayés (top 15)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.13 Top 15 comptes en overdue (concentration créance)]');
    FOR r IN (
        SELECT ACCOUNT_NUMBER, BRANCH_CODE, nb, sm FROM (
            SELECT ACCOUNT_NUMBER, BRANCH_CODE,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_OVERDUE),2) sm
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE AMOUNT_OVERDUE > 0
            GROUP BY ACCOUNT_NUMBER, BRANCH_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRANCH_CODE || ' / ' || r.ACCOUNT_NUMBER,
                 'nb=' || TO_CHAR(r.nb) || ' | sum overdue=' || TO_CHAR(r.sm));
    END LOOP;

    -- 5.14 Cumul dérogation (waiver composant) vs waiver échéance
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [5.14 Alignement waiver composant vs waiver échéance]');
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_SCHEDULES s
    WHERE s.WAIVER_FLAG = 'Y'
      AND NOT EXISTS (
          SELECT 1 FROM CLTB_ACCOUNT_COMPONENTS c
          WHERE c.ACCOUNT_NUMBER = s.ACCOUNT_NUMBER
            AND c.BRANCH_CODE    = s.BRANCH_CODE
            AND c.COMPONENT_NAME = s.COMPONENT_NAME
            AND c.WAIVE = 'Y'
      );
    print_kv('  Echéances waivées sans composant marqué WAIVE', TO_CHAR(v_count));

    -- =========================================================
    -- 6. CLTB_AMOUNT_PAID / CLTB_AMOUNT_RECD / CLTB_LIQ
    --    Paiements, réceptions & liquidations prêts
    --    Angle Revenue Assurance :
    --     - CLTB_AMOUNT_RECD : tous les flux reçus du client
    --       (principal, intérêts, pénalités, commissions).
    --     - CLTB_AMOUNT_PAID : montants effectivement imputés
    --       composant par composant (AMOUNT_PAID + AMOUNT_WAIVED
    --       + AMOUNT_CAPITALIZED).
    --     - CLTB_LIQ : évènement de liquidation (rembt partiel,
    --       total, prépaiement) — permet de détecter les
    --       remises (CUST_INCENTIVE), excès (AMOUNT_EXCESS,
    --       EXCESS_PROFIT), rebates (UIDB_REBATE), reversals.
    -- =========================================================
    print_section('6. Paiements & liquidations — AMOUNT_PAID / AMOUNT_RECD / CLTB_LIQ');

    -- 6.1 Volumétrie & plages temporelles
    DBMS_OUTPUT.PUT_LINE('  [6.1 Volumétrie & plages temporelles]');
    SELECT COUNT(*) INTO v_count FROM CLTB_AMOUNT_RECD;
    print_kv('  CLTB_AMOUNT_RECD — nb lignes', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_AMOUNT_PAID;
    print_kv('  CLTB_AMOUNT_PAID — nb lignes', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ;
    print_kv('  CLTB_LIQ — nb lignes', TO_CHAR(v_count));

    FOR r IN (SELECT MIN(RECD_DATE) mn, MAX(RECD_DATE) mx FROM CLTB_AMOUNT_RECD) LOOP
        print_kv('  RECD_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  RECD_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (SELECT MIN(PAID_DATE) mn, MAX(PAID_DATE) mx FROM CLTB_AMOUNT_PAID) LOOP
        print_kv('  PAID_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  PAID_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (SELECT MIN(VALUE_DATE) mn, MAX(VALUE_DATE) mx FROM CLTB_LIQ) LOOP
        print_kv('  LIQ VALUE_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  LIQ VALUE_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    -- 6.2 CLTB_AMOUNT_RECD — répartition par RECD_TYPE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.2 CLTB_AMOUNT_RECD — répartition par RECD_TYPE]');
    FOR r IN (
        SELECT NVL(RECD_TYPE,'(NULL)') RECD_TYPE,
               COUNT(*) nb,
               ROUND(SUM(AMOUNT_RECD),2) sm
        FROM CLTB_AMOUNT_RECD
        GROUP BY RECD_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  RECD_TYPE = ' || r.RECD_TYPE, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.2.b Réceptions par COMPONENT_NAME — top 15
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.2.b Top 15 COMPONENT_NAME perçus (AMOUNT_RECD)]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_RECD),2) sm
            FROM CLTB_AMOUNT_RECD
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.2.c Réceptions par année
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.2.c Volumétrie annuelle des réceptions]');
    FOR r IN (
        SELECT TO_CHAR(RECD_DATE,'YYYY') annee,
               COUNT(*) nb, ROUND(SUM(AMOUNT_RECD),2) sm
        FROM CLTB_AMOUNT_RECD WHERE RECD_DATE IS NOT NULL
        GROUP BY TO_CHAR(RECD_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.3 CLTB_AMOUNT_PAID — répartition par PAID_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.3 CLTB_AMOUNT_PAID — répartition par PAID_STATUS]');
    FOR r IN (
        SELECT NVL(PAID_STATUS,'(NULL)') PAID_STATUS,
               COUNT(*) nb,
               ROUND(SUM(AMOUNT_PAID),2) sm_pd,
               ROUND(SUM(AMOUNT_WAIVED),2) sm_wv,
               ROUND(SUM(AMOUNT_CAPITALIZED),2) sm_cap
        FROM CLTB_AMOUNT_PAID
        GROUP BY PAID_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  PAID_STATUS = ' || r.PAID_STATUS,
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | paid=' || TO_CHAR(r.sm_pd) ||
                 ' | waiv=' || TO_CHAR(r.sm_wv) ||
                 ' | cap=' || TO_CHAR(r.sm_cap));
    END LOOP;

    -- 6.3.b Top 15 COMPONENT_NAME par AMOUNT_PAID
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.3.b Top 15 COMPONENT_NAME payés]');
    FOR r IN (
        SELECT COMPONENT_NAME, nb, sm FROM (
            SELECT NVL(COMPONENT_NAME,'(NULL)') COMPONENT_NAME,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_PAID),2) sm
            FROM CLTB_AMOUNT_PAID
            GROUP BY COMPONENT_NAME
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.COMPONENT_NAME, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.3.c Waivers et capitalisations à la liquidation
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.3.c Waivers & capitalisations — agrégats]');
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_WAIVED),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_PAID WHERE AMOUNT_WAIVED > 0;
    print_kv('  Lignes avec AMOUNT_WAIVED > 0', TO_CHAR(v_count));
    print_kv('  SUM AMOUNT_WAIVED', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_CAPITALIZED),2),0)
      INTO v_count, v_num
    FROM CLTB_AMOUNT_PAID WHERE AMOUNT_CAPITALIZED > 0;
    print_kv('  Lignes avec AMOUNT_CAPITALIZED > 0', TO_CHAR(v_count));
    print_kv('  SUM AMOUNT_CAPITALIZED', TO_CHAR(v_num));

    -- 6.3.d Retards de paiement (PAID_DATE - DUE_DATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.3.d Retards de paiement (PAID_DATE - DUE_DATE)]');
    FOR r IN (
        SELECT
            CASE
                WHEN PAID_DATE - DUE_DATE <= 0   THEN 'à temps ou avance'
                WHEN PAID_DATE - DUE_DATE <= 15  THEN '1-15 j de retard'
                WHEN PAID_DATE - DUE_DATE <= 30  THEN '16-30 j'
                WHEN PAID_DATE - DUE_DATE <= 60  THEN '31-60 j'
                WHEN PAID_DATE - DUE_DATE <= 90  THEN '61-90 j'
                WHEN PAID_DATE - DUE_DATE <= 180 THEN '91-180 j'
                ELSE '> 180 j'
            END bucket,
            COUNT(*) nb,
            ROUND(SUM(AMOUNT_PAID),2) sm
        FROM CLTB_AMOUNT_PAID
        WHERE PAID_DATE IS NOT NULL AND DUE_DATE IS NOT NULL
        GROUP BY
            CASE
                WHEN PAID_DATE - DUE_DATE <= 0   THEN 'à temps ou avance'
                WHEN PAID_DATE - DUE_DATE <= 15  THEN '1-15 j de retard'
                WHEN PAID_DATE - DUE_DATE <= 30  THEN '16-30 j'
                WHEN PAID_DATE - DUE_DATE <= 60  THEN '31-60 j'
                WHEN PAID_DATE - DUE_DATE <= 90  THEN '61-90 j'
                WHEN PAID_DATE - DUE_DATE <= 180 THEN '91-180 j'
                ELSE '> 180 j'
            END
        ORDER BY bucket
    ) LOOP
        print_kv('  ' || r.bucket, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 6.4 CLTB_LIQ — événements de liquidation (full, partial, prepay)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4 CLTB_LIQ — répartition PAYMENT_STATUS]');
    FOR r IN (
        SELECT NVL(PAYMENT_STATUS,'(NULL)') PAYMENT_STATUS, COUNT(*) nb
        FROM CLTB_LIQ GROUP BY PAYMENT_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  PAYMENT_STATUS = ' || r.PAYMENT_STATUS, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (
        SELECT NVL(AUTH_STAT,'(NULL)') AUTH_STAT, COUNT(*) nb
        FROM CLTB_LIQ GROUP BY AUTH_STAT ORDER BY nb DESC
    ) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;

    -- 6.4.b Rebates / incentives / excess (revenu perdu ou récupéré)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.b Remises & excès — fuite / excédent à la liquidation]');
    SELECT COUNT(*), NVL(ROUND(SUM(CUST_INCENTIVE),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE CUST_INCENTIVE IS NOT NULL AND CUST_INCENTIVE <> 0;
    print_kv('  CUST_INCENTIVE renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM CUST_INCENTIVE', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(UIDB_REBATE),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE UIDB_REBATE IS NOT NULL AND UIDB_REBATE <> 0;
    print_kv('  UIDB_REBATE renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM UIDB_REBATE', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(AMOUNT_EXCESS),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE AMOUNT_EXCESS IS NOT NULL AND AMOUNT_EXCESS <> 0;
    print_kv('  AMOUNT_EXCESS renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM AMOUNT_EXCESS', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(EXCESS_PROFIT),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE EXCESS_PROFIT IS NOT NULL AND EXCESS_PROFIT <> 0;
    print_kv('  EXCESS_PROFIT renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM EXCESS_PROFIT', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(BANKS_ADD_PROFIT),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE BANKS_ADD_PROFIT IS NOT NULL AND BANKS_ADD_PROFIT <> 0;
    print_kv('  BANKS_ADD_PROFIT renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM BANKS_ADD_PROFIT', TO_CHAR(v_num));
    SELECT COUNT(*), NVL(ROUND(SUM(GROSS_PROFIT),2),0)
      INTO v_count, v_num
    FROM CLTB_LIQ WHERE GROSS_PROFIT IS NOT NULL AND GROSS_PROFIT <> 0;
    print_kv('  GROSS_PROFIT renseigné — nb', TO_CHAR(v_count));
    print_kv('  SUM GROSS_PROFIT', TO_CHAR(v_num));

    -- 6.4.c Pré-paiement (impact sur intérêts non perçus)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.c Pré-paiements (PREPMNT_RECOMP_*) — recomposition intérêt]');
    FOR r IN (
        SELECT NVL(PREPMNT_RECOMP_BASIS,'(NULL)') PB, COUNT(*) nb
        FROM CLTB_LIQ GROUP BY PREPMNT_RECOMP_BASIS ORDER BY nb DESC
    ) LOOP
        print_kv('  PREPMNT_RECOMP_BASIS = ' || r.PB, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (
        SELECT NVL(PREPMNT_RECOMP_BASIS_SIMPLE,'(NULL)') PBS, COUNT(*) nb
        FROM CLTB_LIQ GROUP BY PREPMNT_RECOMP_BASIS_SIMPLE ORDER BY nb DESC
    ) LOOP
        print_kv('  PREPMNT_RECOMP_BASIS_SIMPLE = ' || r.PBS, TO_CHAR(r.nb));
    END LOOP;

    -- 6.4.d INSTALLMENT_PAYMENT vs CLOSE_RVLNG_LOAN vs ASSET_CLOSURE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.d Types de liquidation]');
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ WHERE INSTALLMENT_PAYMENT = 'Y';
    print_kv('  INSTALLMENT_PAYMENT = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ WHERE CLOSE_RVLNG_LOAN = 'Y';
    print_kv('  CLOSE_RVLNG_LOAN = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ WHERE ASSET_CLOSURE = 'Y';
    print_kv('  ASSET_CLOSURE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ WHERE SIMULATED = 'Y';
    print_kv('  SIMULATED = Y (simulation non comptabilisée)', TO_CHAR(v_count));

    -- 6.4.e Reversals de liquidation (REV_MAKER_ID renseigné)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.e Reversals de liquidation]');
    SELECT COUNT(*) INTO v_count FROM CLTB_LIQ WHERE REV_MAKER_ID IS NOT NULL;
    print_kv('  Reversals (REV_MAKER_ID renseigné)', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_LIQ WHERE REV_MAKER_ID IS NOT NULL;
    print_kv('  Comptes prêt concernés', TO_CHAR(v_count));

    -- 6.4.f Top 10 users maker / checker sur liquidations
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.f Top 10 MAKER_ID sur liquidations]');
    FOR r IN (
        SELECT MAKER_ID, nb FROM (
            SELECT MAKER_ID, COUNT(*) nb FROM CLTB_LIQ
            WHERE MAKER_ID IS NOT NULL
            GROUP BY MAKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  MAKER ' || r.MAKER_ID, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.4.g Top 10 CHECKER_ID]');
    FOR r IN (
        SELECT CHECKER_ID, nb FROM (
            SELECT CHECKER_ID, COUNT(*) nb FROM CLTB_LIQ
            WHERE CHECKER_ID IS NOT NULL
            GROUP BY CHECKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CHECKER ' || r.CHECKER_ID, TO_CHAR(r.nb));
    END LOOP;

    -- 6.5 Cohérence AMOUNT_RECD vs AMOUNT_PAID par compte
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.5 Cohérence AMOUNT_RECD vs AMOUNT_PAID — niveau compte]');
    FOR r IN (
        SELECT SUM(r_amt) sm_r, SUM(p_amt) sm_p FROM (
            SELECT SUM(AMOUNT_RECD) r_amt, TO_NUMBER(NULL) p_amt
              FROM CLTB_AMOUNT_RECD GROUP BY ACCOUNT_NUMBER
            UNION ALL
            SELECT TO_NUMBER(NULL) r_amt, SUM(AMOUNT_PAID) p_amt
              FROM CLTB_AMOUNT_PAID GROUP BY ACCOUNT_NUMBER
        )
    ) LOOP
        print_kv('  SUM AMOUNT_RECD', TO_CHAR(ROUND(NVL(r.sm_r,0),2)));
        print_kv('  SUM AMOUNT_PAID', TO_CHAR(ROUND(NVL(r.sm_p,0),2)));
        print_kv('  Ecart RECD - PAID',
                 TO_CHAR(ROUND(NVL(r.sm_r,0) - NVL(r.sm_p,0),2)));
    END LOOP;

    -- 6.5.b Comptes reçus sans paiement imputé (piste de cash non affecté)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [6.5.b Comptes avec réceptions sans imputation composant]');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT ACCOUNT_NUMBER, BRANCH_CODE FROM CLTB_AMOUNT_RECD r
        WHERE NOT EXISTS (
            SELECT 1 FROM CLTB_AMOUNT_PAID p
            WHERE p.ACCOUNT_NUMBER = r.ACCOUNT_NUMBER
              AND p.BRANCH_CODE    = r.BRANCH_CODE
        )
    );
    print_kv('  Comptes sans ligne AMOUNT_PAID associée', TO_CHAR(v_count));

    -- =========================================================
    -- 7. CLTB_ACCOUNT_APPS_MASTER — PRETS LIFECYCLE
    --    Angle Revenue Assurance :
    --     - expositions et cadres contractuels (AMOUNT_FINANCED,
    --       AMOUNT_DISBURSED, NET_PRINCIPAL, TOTAL_AMOUNT,
    --       BALLOON_AMOUNT, RESIDUAL_VALUE) = base de calcul
    --       des intérêts.
    --     - ACCOUNT_STATUS / DERIVED_STATUS / USER_DEFINED_STATUS
    --       décrivent le cycle de vie et les provisions.
    --     - STOP_ACCRUALS, STOP_DSBR, HAS_PROBLEMS =
    --       indicateurs de dégradation → risque fuite revenu.
    --     - INTEREST_SUBSIDY_ALLOWED / SUBSIDY_CUSTOMER_ID =
    --       prêts subventionnés à auditer.
    --     - UPFRONT_PROFIT_BOOKED = reconnaissance anticipée de
    --       marge (spécifique islamique / MUR).
    -- =========================================================
    print_section('7. CLTB_ACCOUNT_APPS_MASTER — Prêts lifecycle');

    -- 7.1 Volumétrie globale
    DBMS_OUTPUT.PUT_LINE('  [7.1 Volumétrie & plages temporelles]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Total comptes prêt (CL)', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CUSTOMER_ID) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Clients distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT PRODUCT_CODE) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  PRODUCT_CODE distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  Branches distinctes', TO_CHAR(v_count));

    FOR r IN (SELECT MIN(BOOK_DATE) mn, MAX(BOOK_DATE) mx FROM CLTB_ACCOUNT_APPS_MASTER) LOOP
        print_kv('  BOOK_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  BOOK_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (SELECT MIN(VALUE_DATE) mn, MAX(VALUE_DATE) mx FROM CLTB_ACCOUNT_APPS_MASTER) LOOP
        print_kv('  VALUE_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  VALUE_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (SELECT MIN(MATURITY_DATE) mn, MAX(MATURITY_DATE) mx FROM CLTB_ACCOUNT_APPS_MASTER) LOOP
        print_kv('  MATURITY_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  MATURITY_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    -- 7.2 Volumétrie annuelle (octrois)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.2 Octrois annuels (VALUE_DATE)]');
    FOR r IN (
        SELECT TO_CHAR(VALUE_DATE,'YYYY') annee,
               COUNT(*) nb,
               ROUND(SUM(AMOUNT_FINANCED),2) sm_fin,
               ROUND(SUM(AMOUNT_DISBURSED),2) sm_dsb
        FROM CLTB_ACCOUNT_APPS_MASTER
        WHERE VALUE_DATE IS NOT NULL
        GROUP BY TO_CHAR(VALUE_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee,
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | financé=' || TO_CHAR(r.sm_fin) ||
                 ' | décaissé=' || TO_CHAR(r.sm_dsb));
    END LOOP;

    -- 7.3 Statuts (ACCOUNT_STATUS / DERIVED_STATUS / USER_DEFINED_STATUS)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.3 Répartition ACCOUNT_STATUS]');
    FOR r IN (
        SELECT NVL(ACCOUNT_STATUS,'(NULL)') ACCOUNT_STATUS, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY ACCOUNT_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  ACCOUNT_STATUS = ' || r.ACCOUNT_STATUS, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.3.b Répartition DERIVED_STATUS]');
    FOR r IN (
        SELECT NVL(DERIVED_STATUS,'(NULL)') DERIVED_STATUS, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY DERIVED_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  DERIVED_STATUS = ' || r.DERIVED_STATUS, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.3.c Top 15 USER_DEFINED_STATUS (classification risque)]');
    FOR r IN (
        SELECT USER_DEFINED_STATUS, nb FROM (
            SELECT NVL(USER_DEFINED_STATUS,'(NULL)') USER_DEFINED_STATUS, COUNT(*) nb
            FROM CLTB_ACCOUNT_APPS_MASTER
            GROUP BY USER_DEFINED_STATUS ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.USER_DEFINED_STATUS, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.3.d AUTH_STAT / DELINQUENCY_STATUS]');
    FOR r IN (SELECT NVL(AUTH_STAT,'(NULL)') AUTH_STAT, COUNT(*) nb
              FROM CLTB_ACCOUNT_APPS_MASTER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.AUTH_STAT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(DELINQUENCY_STATUS,'(NULL)') DELINQUENCY_STATUS, COUNT(*) nb
              FROM CLTB_ACCOUNT_APPS_MASTER GROUP BY DELINQUENCY_STATUS ORDER BY nb DESC) LOOP
        print_kv('  DELINQUENCY_STATUS = ' || r.DELINQUENCY_STATUS, TO_CHAR(r.nb));
    END LOOP;

    -- 7.4 Flags revenue-sensibles
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.4 Flags revenue-sensibles]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE STOP_ACCRUALS = 'Y';
    print_kv('  STOP_ACCRUALS = Y (intérêts gelés)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE STOP_DSBR = 'Y';
    print_kv('  STOP_DSBR = Y (décaissement bloqué)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE HAS_PROBLEMS = 'Y';
    print_kv('  HAS_PROBLEMS = Y (prêt à problème)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE TAKEN_OVER = 'Y';
    print_kv('  TAKEN_OVER = Y (prêt repris)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE AMORTIZED = 'Y';
    print_kv('  AMORTIZED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE INSURANCE_FLAG = 'Y';
    print_kv('  INSURANCE_FLAG = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE STAFF_FINANCE = 'Y';
    print_kv('  STAFF_FINANCE = Y (prêt personnel banque)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE UPFRONT_PROFIT_BOOKED = 'Y';
    print_kv('  UPFRONT_PROFIT_BOOKED = Y (profit anticipé)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE OPEN_LINE_LOAN = 'Y';
    print_kv('  OPEN_LINE_LOAN = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE ROLLOVER_ALLOWED = 'Y';
    print_kv('  ROLLOVER_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE PACKING_CREDIT = 'Y';
    print_kv('  PACKING_CREDIT = Y', TO_CHAR(v_count));

    -- 7.5 Subventions d'intérêts
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.5 INTEREST_SUBSIDY / SUBSIDY_CUSTOMER_ID]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE INTEREST_SUBSIDY_ALLOWED = 'Y';
    print_kv('  INTEREST_SUBSIDY_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE SUBSIDY_CUSTOMER_ID IS NOT NULL;
    print_kv('  SUBSIDY_CUSTOMER_ID renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE RESIDUAL_SUBSIDY_ALLOWED = 'Y';
    print_kv('  RESIDUAL_SUBSIDY_ALLOWED = Y', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(RESIDUAL_SUBSIDY_VALUE),2),0) INTO v_num FROM CLTB_ACCOUNT_APPS_MASTER;
    print_kv('  SUM RESIDUAL_SUBSIDY_VALUE', TO_CHAR(v_num));

    -- 7.6 Expositions — stats montants
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.6 Stats financements (AMOUNT_FINANCED)]');
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(AMOUNT_FINANCED),2) sm,
               ROUND(AVG(AMOUNT_FINANCED),2) av,
               ROUND(MIN(AMOUNT_FINANCED),2) mn,
               ROUND(MAX(AMOUNT_FINANCED),2) mx
        FROM CLTB_ACCOUNT_APPS_MASTER WHERE AMOUNT_FINANCED > 0
    ) LOOP
        print_kv('  AMOUNT_FINANCED — nb', TO_CHAR(r.nb));
        print_kv('  AMOUNT_FINANCED — sum', TO_CHAR(r.sm));
        print_kv('  AMOUNT_FINANCED — moy', TO_CHAR(r.av));
        print_kv('  AMOUNT_FINANCED — min', TO_CHAR(r.mn));
        print_kv('  AMOUNT_FINANCED — max', TO_CHAR(r.mx));
    END LOOP;
    FOR r IN (
        SELECT ROUND(SUM(AMOUNT_DISBURSED),2) sm_d,
               ROUND(SUM(AMOUNT_UTILIZED),2) sm_u,
               ROUND(SUM(AMT_AVAILABLE),2) sm_a,
               ROUND(SUM(NET_PRINCIPAL),2) sm_np,
               ROUND(SUM(TOTAL_AMOUNT),2) sm_t,
               ROUND(SUM(BALLOON_AMOUNT),2) sm_b,
               ROUND(SUM(RESIDUAL_AMOUNT),2) sm_r
        FROM CLTB_ACCOUNT_APPS_MASTER
    ) LOOP
        print_kv('  SUM AMOUNT_DISBURSED', TO_CHAR(r.sm_d));
        print_kv('  SUM AMOUNT_UTILIZED', TO_CHAR(r.sm_u));
        print_kv('  SUM AMT_AVAILABLE', TO_CHAR(r.sm_a));
        print_kv('  SUM NET_PRINCIPAL', TO_CHAR(r.sm_np));
        print_kv('  SUM TOTAL_AMOUNT', TO_CHAR(r.sm_t));
        print_kv('  SUM BALLOON_AMOUNT', TO_CHAR(r.sm_b));
        print_kv('  SUM RESIDUAL_AMOUNT', TO_CHAR(r.sm_r));
    END LOOP;

    -- 7.6.b Cohérence DISBURSED <= FINANCED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.6.b Cohérence AMOUNT_DISBURSED <= AMOUNT_FINANCED]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE AMOUNT_DISBURSED > AMOUNT_FINANCED + 0.01 AND AMOUNT_FINANCED > 0;
    print_kv('  Décaissé > financé (anomalie)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE AMOUNT_DISBURSED = 0 AND AMOUNT_FINANCED > 0
      AND ACCOUNT_STATUS IN ('A','L'); -- Actif / Liquidé
    print_kv('  Actif/Liquidé mais non décaissé', TO_CHAR(v_count));

    -- 7.7 Volumétrie par PRODUCT_CATEGORY / PRODUCT_CODE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.7 Top 15 PRODUCT_CODE]');
    FOR r IN (
        SELECT PRODUCT_CODE, nb, sm FROM (
            SELECT NVL(PRODUCT_CODE,'(NULL)') PRODUCT_CODE,
                   COUNT(*) nb, ROUND(SUM(AMOUNT_FINANCED),2) sm
            FROM CLTB_ACCOUNT_APPS_MASTER
            GROUP BY PRODUCT_CODE ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT ' || r.PRODUCT_CODE, 'nb=' || TO_CHAR(r.nb) || ' | financé=' || TO_CHAR(r.sm));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.7.b Top 10 PRODUCT_CATEGORY]');
    FOR r IN (
        SELECT PRODUCT_CATEGORY, nb FROM (
            SELECT NVL(PRODUCT_CATEGORY,'(NULL)') PRODUCT_CATEGORY, COUNT(*) nb
            FROM CLTB_ACCOUNT_APPS_MASTER
            GROUP BY PRODUCT_CATEGORY ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  PRODUCT_CATEGORY = ' || r.PRODUCT_CATEGORY, TO_CHAR(r.nb));
    END LOOP;

    -- 7.8 Fréquence & tenor
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.8 Fréquence EMI & Tenor]');
    FOR r IN (
        SELECT NVL(EMI_FREQ_UNIT,'(NULL)') EMI_FREQ_UNIT, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY EMI_FREQ_UNIT ORDER BY nb DESC
    ) LOOP
        print_kv('  EMI_FREQ_UNIT = ' || r.EMI_FREQ_UNIT, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (
        SELECT NVL(MATURITY_TYPE,'(NULL)') MATURITY_TYPE, COUNT(*) nb
        FROM CLTB_ACCOUNT_APPS_MASTER
        GROUP BY MATURITY_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  MATURITY_TYPE = ' || r.MATURITY_TYPE, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (
        SELECT ROUND(MIN(MATURITY_TENOR),2) mn,
               ROUND(MAX(MATURITY_TENOR),2) mx,
               ROUND(AVG(MATURITY_TENOR),2) av
        FROM CLTB_ACCOUNT_APPS_MASTER WHERE MATURITY_TENOR IS NOT NULL
    ) LOOP
        print_kv('  MATURITY_TENOR min', TO_CHAR(r.mn));
        print_kv('  MATURITY_TENOR max', TO_CHAR(r.mx));
        print_kv('  MATURITY_TENOR moy', TO_CHAR(r.av));
    END LOOP;

    -- 7.9 Prêts post-maturité non soldés (candidats NPL)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.9 Prêts post-maturité non clôturés]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE MATURITY_DATE < SYSDATE
      AND ACCOUNT_STATUS NOT IN ('L','C') -- non liquidé / non clos
      AND MATURITY_DATE IS NOT NULL;
    print_kv('  Maturité passée & statut non L/C', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE EXPECTED_CLOSURE_DATE < SYSDATE
      AND ACCOUNT_STATUS NOT IN ('L','C')
      AND EXPECTED_CLOSURE_DATE IS NOT NULL;
    print_kv('  Clôture attendue passée & statut non L/C', TO_CHAR(v_count));

    -- 7.10 Downpayment
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.10 Downpayments]');
    SELECT COUNT(*), NVL(ROUND(SUM(DOWNPAYMENT_AMOUNT),2),0)
      INTO v_count, v_num
    FROM CLTB_ACCOUNT_APPS_MASTER WHERE DOWNPAYMENT_AMOUNT > 0;
    print_kv('  Comptes avec DOWNPAYMENT_AMOUNT > 0', TO_CHAR(v_count));
    print_kv('  SUM DOWNPAYMENT_AMOUNT', TO_CHAR(v_num));

    -- 7.11 Concentration par CUSTOMER_ID — top 15 emprunteurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [7.11 Top 15 emprunteurs (par AMOUNT_FINANCED cumulé)]');
    FOR r IN (
        SELECT CUSTOMER_ID, nb, sm FROM (
            SELECT CUSTOMER_ID, COUNT(*) nb, ROUND(SUM(AMOUNT_FINANCED),2) sm
            FROM CLTB_ACCOUNT_APPS_MASTER
            WHERE CUSTOMER_ID IS NOT NULL
            GROUP BY CUSTOMER_ID
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CUST ' || r.CUSTOMER_ID, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- =========================================================
    -- 8. LDTB — CONTRATS LOANS / DEPOSITS / MONEY MARKET
    --    Angle Revenue Assurance :
    --     - LDTB_CONTRACT_MASTER : inventaire des contrats MM/LD,
    --       taux principal (MAIN_COMP_RATE, SPREAD), subvention
    --       (SUBSIDY_PERCENTAGE).
    --     - LDTB_CONTRACT_ICCF_DETAILS : accruals & liquidations
    --       par composant ICCF (TILL_DATE_ACCRUAL,
    --       OUTSTANDING NET, UPFRONT_PROFIT_BOOKED).
    --     - LDTB_CONTRACT_ACCRUAL_HISTORY : historique des
    --       accruals (OVERDUE_INTEREST, NET_ACCRUAL).
    --     - LDTB_CONTRACT_LIQ & LIQ_SUMMARY : paiements,
    --       prépaiements, pénalités de remboursement anticipé.
    --     - LDTB_CONTRACT_ROLLOVER : rollovers (si frais/charges
    --       non appliqués = fuite).
    --     - LDTB_CONTRACT_PREFERENCE : règles arrondis, holidays,
    --       TRS_APPLICABLE, VERIFY_FUNDS.
    -- =========================================================
    print_section('8. LDTB — Contrats Loans/Deposits/MM & accruals');

    -- 8.1 Volumétrie
    DBMS_OUTPUT.PUT_LINE('  [8.1 Volumétrie des contrats]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  LDTB_CONTRACT_MASTER — total', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT PRODUCT) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Produits distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT MODULE) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Modules distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COUNTERPARTY) INTO v_count FROM LDTB_CONTRACT_MASTER;
    print_kv('  Contreparties distinctes', TO_CHAR(v_count));

    FOR r IN (
        SELECT MIN(BOOKING_DATE) mn, MAX(BOOKING_DATE) mx FROM LDTB_CONTRACT_MASTER
    ) LOOP
        print_kv('  BOOKING_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  BOOKING_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (
        SELECT MIN(VALUE_DATE) mn, MAX(VALUE_DATE) mx FROM LDTB_CONTRACT_MASTER
    ) LOOP
        print_kv('  VALUE_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  VALUE_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (
        SELECT MIN(MATURITY_DATE) mn, MAX(MATURITY_DATE) mx FROM LDTB_CONTRACT_MASTER
    ) LOOP
        print_kv('  MATURITY_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  MATURITY_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    -- 8.2 Répartition par MODULE / PRODUCT_TYPE / PAYMENT_METHOD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.2 Répartition MODULE]');
    FOR r IN (
        SELECT NVL(MODULE,'(NULL)') MODULE, COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
        FROM LDTB_CONTRACT_MASTER GROUP BY MODULE ORDER BY nb DESC
    ) LOOP
        print_kv('  MODULE = ' || r.MODULE, 'nb=' || TO_CHAR(r.nb) || ' | sum LCY=' || TO_CHAR(r.sm));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.2.b PRODUCT_TYPE]');
    FOR r IN (
        SELECT NVL(PRODUCT_TYPE,'(NULL)') PRODUCT_TYPE, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER GROUP BY PRODUCT_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  PRODUCT_TYPE = ' || r.PRODUCT_TYPE, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.2.c PAYMENT_METHOD]');
    FOR r IN (
        SELECT NVL(PAYMENT_METHOD,'(NULL)') PAYMENT_METHOD, COUNT(*) nb
        FROM LDTB_CONTRACT_MASTER GROUP BY PAYMENT_METHOD ORDER BY nb DESC
    ) LOOP
        print_kv('  PAYMENT_METHOD = ' || r.PAYMENT_METHOD, TO_CHAR(r.nb));
    END LOOP;

    -- 8.3 Statuts
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.3 Statuts contrats]');
    FOR r IN (SELECT NVL(CONTRACT_STATUS,'(NULL)') CONTRACT_STATUS, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY CONTRACT_STATUS ORDER BY nb DESC) LOOP
        print_kv('  CONTRACT_STATUS = ' || r.CONTRACT_STATUS, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(CONTRACT_DERIVED_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY CONTRACT_DERIVED_STATUS ORDER BY nb DESC) LOOP
        print_kv('  CONTRACT_DERIVED_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(USER_DEFINED_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY USER_DEFINED_STATUS ORDER BY nb DESC
              FETCH FIRST 15 ROWS ONLY) LOOP
        print_kv('  USER_DEFINED_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(SETTLEMENT_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY SETTLEMENT_STATUS ORDER BY nb DESC) LOOP
        print_kv('  SETTLEMENT_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(ICCF_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY ICCF_STATUS ORDER BY nb DESC) LOOP
        print_kv('  ICCF_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(CHARGE_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY CHARGE_STATUS ORDER BY nb DESC) LOOP
        print_kv('  CHARGE_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(TAX_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_MASTER GROUP BY TAX_STATUS ORDER BY nb DESC) LOOP
        print_kv('  TAX_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 8.4 Montants — stats MAIN_COMP_AMOUNT / LCY_AMOUNT / ORIGINAL_FACE_VALUE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.4 Stats financières des contrats]');
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(AMOUNT),2)            sm_a,
               ROUND(SUM(MAIN_COMP_AMOUNT),2)  sm_m,
               ROUND(SUM(LCY_AMOUNT),2)        sm_l,
               ROUND(SUM(ORIGINAL_FACE_VALUE),2) sm_o,
               ROUND(SUM(RISK_FREE_EXP_AMOUNT),2) sm_r,
               ROUND(SUM(MAX_DRAWDOWN_AMOUNT),2) sm_d
        FROM LDTB_CONTRACT_MASTER
    ) LOOP
        print_kv('  SUM AMOUNT', TO_CHAR(r.sm_a));
        print_kv('  SUM MAIN_COMP_AMOUNT', TO_CHAR(r.sm_m));
        print_kv('  SUM LCY_AMOUNT', TO_CHAR(r.sm_l));
        print_kv('  SUM ORIGINAL_FACE_VALUE', TO_CHAR(r.sm_o));
        print_kv('  SUM RISK_FREE_EXP_AMOUNT', TO_CHAR(r.sm_r));
        print_kv('  SUM MAX_DRAWDOWN_AMOUNT', TO_CHAR(r.sm_d));
    END LOOP;

    -- 8.5 Taux (MAIN_COMP_RATE / MAIN_COMP_SPREAD)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.5 Taux principal contrats]');
    FOR r IN (
        SELECT ROUND(MIN(MAIN_COMP_RATE),4) mn,
               ROUND(MAX(MAIN_COMP_RATE),4) mx,
               ROUND(AVG(MAIN_COMP_RATE),4) av
        FROM LDTB_CONTRACT_MASTER
        WHERE MAIN_COMP_RATE IS NOT NULL AND MAIN_COMP_RATE <> 0
    ) LOOP
        print_kv('  MAIN_COMP_RATE min', TO_CHAR(r.mn));
        print_kv('  MAIN_COMP_RATE max', TO_CHAR(r.mx));
        print_kv('  MAIN_COMP_RATE moy', TO_CHAR(r.av));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER
    WHERE MAIN_COMP_RATE IS NULL OR MAIN_COMP_RATE = 0;
    print_kv('  Contrats avec MAIN_COMP_RATE NULL / 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER
    WHERE MAIN_COMP_SPREAD IS NOT NULL AND MAIN_COMP_SPREAD <> 0;
    print_kv('  Contrats avec SPREAD non nul', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER
    WHERE CUST_MARGIN IS NOT NULL AND CUST_MARGIN <> 0;
    print_kv('  Contrats avec CUST_MARGIN non nulle', TO_CHAR(v_count));

    -- 8.6 Subvention de taux (SUBSIDY_PERCENTAGE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.6 Subvention de taux (SUBSIDY_PERCENTAGE)]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER
    WHERE SUBSIDY_PERCENTAGE IS NOT NULL AND SUBSIDY_PERCENTAGE > 0;
    print_kv('  Contrats subventionnés', TO_CHAR(v_count));
    FOR r IN (
        SELECT ROUND(MIN(SUBSIDY_PERCENTAGE),4) mn,
               ROUND(MAX(SUBSIDY_PERCENTAGE),4) mx,
               ROUND(AVG(SUBSIDY_PERCENTAGE),4) av
        FROM LDTB_CONTRACT_MASTER WHERE SUBSIDY_PERCENTAGE > 0
    ) LOOP
        print_kv('  SUBSIDY_PERCENTAGE min', TO_CHAR(r.mn));
        print_kv('  SUBSIDY_PERCENTAGE max', TO_CHAR(r.mx));
        print_kv('  SUBSIDY_PERCENTAGE moy', TO_CHAR(r.av));
    END LOOP;

    -- 8.7 Flags revenue-sensibles sur contrats
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.7 Flags contrats — ALLOW_PREPAY / ROLLOVER / AUTO_PROV]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE ALLOW_PREPAY = 'Y';
    print_kv('  ALLOW_PREPAY = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE ROLLOVER_ALLOWED = 'Y';
    print_kv('  ROLLOVER_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE ROLLOVER_COUNT > 0;
    print_kv('  ROLLOVER_COUNT > 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE AUTO_PROV_REQD = 'Y';
    print_kv('  AUTO_PROV_REQD = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE RB_PENALTY_APPLICABLE = 'Y';
    print_kv('  RB_PENALTY_APPLICABLE = Y (pénalité remb. anticipé)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE ANNUITY_LOAN = 'Y';
    print_kv('  ANNUITY_LOAN = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE ASSIGNED_CONTRACT = 'Y';
    print_kv('  ASSIGNED_CONTRACT = Y (cédé)', TO_CHAR(v_count));

    -- 8.8 LDTB_CONTRACT_ICCF_DETAILS — accruals en cours
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.8 ICCF — accruals & intérêts liquidés]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_DETAILS;
    print_kv('  Total lignes ICCF_DETAILS', TO_CHAR(v_count));
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(CURRENT_NET_ACCRUAL),2) sm_cna,
               ROUND(SUM(TILL_DATE_ACCRUAL),2)   sm_tda,
               ROUND(SUM(TOTAL_AMOUNT_LIQUIDATED),2) sm_liq
        FROM LDTB_CONTRACT_ICCF_DETAILS
    ) LOOP
        print_kv('  ICCF — nb', TO_CHAR(r.nb));
        print_kv('  SUM CURRENT_NET_ACCRUAL', TO_CHAR(r.sm_cna));
        print_kv('  SUM TILL_DATE_ACCRUAL', TO_CHAR(r.sm_tda));
        print_kv('  SUM TOTAL_AMOUNT_LIQUIDATED', TO_CHAR(r.sm_liq));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_DETAILS WHERE ACCRUAL_REQUIRED = 'Y';
    print_kv('  Composants ACCRUAL_REQUIRED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_DETAILS WHERE UPFRONT_PROFIT_BOOKED = 'Y';
    print_kv('  UPFRONT_PROFIT_BOOKED = Y', TO_CHAR(v_count));

    -- 8.8.b Top 15 COMPONENT ICCF
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.8.b Top 15 COMPONENT ICCF par accrual courant]');
    FOR r IN (
        SELECT COMPONENT, nb, sm FROM (
            SELECT NVL(COMPONENT,'(NULL)') COMPONENT, COUNT(*) nb,
                   ROUND(SUM(CURRENT_NET_ACCRUAL),2) sm
            FROM LDTB_CONTRACT_ICCF_DETAILS
            GROUP BY COMPONENT
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.COMPONENT, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 8.9 LDTB_CONTRACT_ACCRUAL_HISTORY — historique accruals
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.9 Historique des accruals — ACCRUAL_HISTORY]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ACCRUAL_HISTORY;
    print_kv('  Total lignes accrual history', TO_CHAR(v_count));
    FOR r IN (
        SELECT MIN(ACCRUAL_TO_DATE) mn, MAX(ACCRUAL_TO_DATE) mx
        FROM LDTB_CONTRACT_ACCRUAL_HISTORY
    ) LOOP
        print_kv('  ACCRUAL_TO_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  ACCRUAL_TO_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(NET_ACCRUAL),2) sm_na,
               ROUND(SUM(TILL_DATE_ACCRUAL),2) sm_tda,
               ROUND(SUM(OVERDUE_INTEREST),2) sm_od,
               ROUND(SUM(OUTSTANDING_ACCRUAL),2) sm_out,
               ROUND(SUM(AMOUNT_PREPAID),2) sm_pp
        FROM LDTB_CONTRACT_ACCRUAL_HISTORY
    ) LOOP
        print_kv('  SUM NET_ACCRUAL', TO_CHAR(r.sm_na));
        print_kv('  SUM TILL_DATE_ACCRUAL', TO_CHAR(r.sm_tda));
        print_kv('  SUM OVERDUE_INTEREST', TO_CHAR(r.sm_od));
        print_kv('  SUM OUTSTANDING_ACCRUAL', TO_CHAR(r.sm_out));
        print_kv('  SUM AMOUNT_PREPAID', TO_CHAR(r.sm_pp));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.9.b Répartition TYPE_OF_ACCRUAL]');
    FOR r IN (
        SELECT NVL(TYPE_OF_ACCRUAL,'(NULL)') TYPE_OF_ACCRUAL, COUNT(*) nb
        FROM LDTB_CONTRACT_ACCRUAL_HISTORY
        GROUP BY TYPE_OF_ACCRUAL ORDER BY nb DESC
    ) LOOP
        print_kv('  TYPE_OF_ACCRUAL = ' || r.TYPE_OF_ACCRUAL, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.9.c ACC_ENTRY_PASSED (accrual comptabilisé)]');
    FOR r IN (
        SELECT NVL(ACC_ENTRY_PASSED,'(NULL)') s, COUNT(*) nb
        FROM LDTB_CONTRACT_ACCRUAL_HISTORY
        GROUP BY ACC_ENTRY_PASSED ORDER BY nb DESC
    ) LOOP
        print_kv('  ACC_ENTRY_PASSED = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 8.10 LDTB_CONTRACT_LIQ & LIQ_SUMMARY — paiements contrats
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.10 Liquidation contrats — LDTB_CONTRACT_LIQ]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ;
    print_kv('  Lignes LIQ', TO_CHAR(v_count));
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(AMOUNT_DUE),2) sm_due,
               ROUND(SUM(AMOUNT_PAID),2) sm_pd,
               ROUND(SUM(INT_PREPAY),2) sm_ip,
               ROUND(SUM(TAX_PAID),2) sm_tx
        FROM LDTB_CONTRACT_LIQ
    ) LOOP
        print_kv('  SUM AMOUNT_DUE (LIQ)', TO_CHAR(r.sm_due));
        print_kv('  SUM AMOUNT_PAID (LIQ)', TO_CHAR(r.sm_pd));
        print_kv('  SUM INT_PREPAY', TO_CHAR(r.sm_ip));
        print_kv('  SUM TAX_PAID', TO_CHAR(r.sm_tx));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.10.b Écarts AMOUNT_DUE vs AMOUNT_PAID sur LIQ]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ
    WHERE AMOUNT_DUE > AMOUNT_PAID + 0.01 AND AMOUNT_DUE > 0;
    print_kv('  Lignes AMOUNT_DUE > AMOUNT_PAID', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ WHERE OVERDUE_DAYS > 0;
    print_kv('  Lignes OVERDUE_DAYS > 0', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.10.c LIQ_SUMMARY — prépaiements & pénalités]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ_SUMMARY;
    print_kv('  Lignes LIQ_SUMMARY', TO_CHAR(v_count));
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(TOTAL_PAID),2) sm_tp,
               ROUND(SUM(TOTAL_PREPAID),2) sm_pp,
               ROUND(SUM(PREPAYMENT_PENALTY_AMOUNT),2) sm_pen
        FROM LDTB_CONTRACT_LIQ_SUMMARY
    ) LOOP
        print_kv('  SUM TOTAL_PAID', TO_CHAR(r.sm_tp));
        print_kv('  SUM TOTAL_PREPAID', TO_CHAR(r.sm_pp));
        print_kv('  SUM PREPAYMENT_PENALTY_AMOUNT', TO_CHAR(r.sm_pen));
    END LOOP;
    FOR r IN (
        SELECT NVL(PAYMENT_STATUS,'(NULL)') s, COUNT(*) nb
        FROM LDTB_CONTRACT_LIQ_SUMMARY
        GROUP BY PAYMENT_STATUS ORDER BY nb DESC
    ) LOOP
        print_kv('  LIQ_SUMMARY PAYMENT_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 8.11 LDTB_CONTRACT_ROLLOVER — rollovers (re-conditionnement de revenu)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.11 Rollovers contrats]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER;
    print_kv('  Lignes ROLLOVER', TO_CHAR(v_count));
    FOR r IN (
        SELECT NVL(ROLLOVER_TYPE,'(NULL)') s, COUNT(*) nb
        FROM LDTB_CONTRACT_ROLLOVER GROUP BY ROLLOVER_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  ROLLOVER_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER WHERE APPLY_CHARGE = 'Y';
    print_kv('  Rollover APPLY_CHARGE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER WHERE APPLY_CHARGE = 'N';
    print_kv('  Rollover APPLY_CHARGE = N (fuite de frais)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER WHERE APPLY_TAX = 'Y';
    print_kv('  Rollover APPLY_TAX = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER WHERE APPLY_TAX = 'N';
    print_kv('  Rollover APPLY_TAX = N', TO_CHAR(v_count));

    -- 8.12 LDTB_CONTRACT_PREFERENCE — arrondis / TRS / verify funds
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.12 Preferences contrats — arrondis, TRS, verify funds]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE;
    print_kv('  Total lignes PREFERENCE', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE TRS_APPLICABLE = 'Y';
    print_kv('  TRS_APPLICABLE = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE SUBSIDY_ALLOWED = 'Y';
    print_kv('  SUBSIDY_ALLOWED = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE TRACK_RECEIVABLE_ALIQ = 'Y';
    print_kv('  TRACK_RECEIVABLE_ALIQ = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE TRACK_RECEIVABLE_MLIQ = 'Y';
    print_kv('  TRACK_RECEIVABLE_MLIQ = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE VERIFY_FUNDS = 'Y';
    print_kv('  VERIFY_FUNDS = Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_PREFERENCE WHERE ROUNDING_REQD = 'Y';
    print_kv('  ROUNDING_REQD = Y', TO_CHAR(v_count));
    FOR r IN (
        SELECT NVL(CCY_ROUND_RULE,'(NULL)') s, COUNT(*) nb
        FROM LDTB_CONTRACT_PREFERENCE
        GROUP BY CCY_ROUND_RULE ORDER BY nb DESC
    ) LOOP
        print_kv('  CCY_ROUND_RULE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 8.13 Volumétrie annuelle & concentration par contrepartie
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.13 Volumétrie annuelle BOOKING_DATE]');
    FOR r IN (
        SELECT TO_CHAR(BOOKING_DATE,'YYYY') annee,
               COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
        FROM LDTB_CONTRACT_MASTER WHERE BOOKING_DATE IS NOT NULL
        GROUP BY TO_CHAR(BOOKING_DATE,'YYYY') ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, 'nb=' || TO_CHAR(r.nb) || ' | sum LCY=' || TO_CHAR(r.sm));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [8.13.b Top 10 contreparties par exposition]');
    FOR r IN (
        SELECT COUNTERPARTY, nb, sm FROM (
            SELECT NVL(COUNTERPARTY,'(NULL)') COUNTERPARTY,
                   COUNT(*) nb, ROUND(SUM(LCY_AMOUNT),2) sm
            FROM LDTB_CONTRACT_MASTER
            GROUP BY COUNTERPARTY
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CPARTY ' || r.COUNTERPARTY, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- =========================================================
    -- 9. ICTM — PARAMETRAGE TAUX D'INTERET (IC)
    --    Angle Revenue Assurance :
    --     - ICTM_PR_INT_UDEVALS : taux par produit/classe
    --       (référentiel "catalogue" des taux appliqués).
    --     - ICTM_ACC_UDEVALS : taux par compte (dérogations
    --       individuelles, variance, spread). Un UDE_VARIANCE
    --       non nul = taux appliqué au client ≠ taux catalogue.
    --     - ICTM_EXPR : expressions de calcul de revenu IC
    --       (règles / conditions / formules). Piste d'audit
    --       : vérifier que chaque RULE_ID est bien autorisée.
    -- =========================================================
    print_section('9. ICTM — Paramétrage des taux d''intérêt');

    -- 9.1 Volumétrie globale
    DBMS_OUTPUT.PUT_LINE('  [9.1 Volumétrie]');
    SELECT COUNT(*) INTO v_count FROM ICTM_PR_INT_UDEVALS;
    print_kv('  ICTM_PR_INT_UDEVALS (taux produit/classe)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  ICTM_ACC_UDEVALS (taux compte)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_EXPR;
    print_kv('  ICTM_EXPR (expressions de calcul)', TO_CHAR(v_count));

    -- 9.2 Taux catalogue par PRODUCT_CODE — top 15
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2 Taux catalogue — top 15 PRODUCT_CODE les plus paramétrés]');
    FOR r IN (
        SELECT PRODUCT_CODE, nb FROM (
            SELECT NVL(PRODUCT_CODE,'(NULL)') PRODUCT_CODE, COUNT(*) nb
            FROM ICTM_PR_INT_UDEVALS
            GROUP BY PRODUCT_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PRODUCT ' || r.PRODUCT_CODE, TO_CHAR(r.nb) || ' lignes UDE');
    END LOOP;

    -- 9.2.b Répartition UDE_ID (types de taux : MAIN_INT_RATE, PENALTY_RATE, ...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2.b Top 15 UDE_ID (types de taux)]');
    FOR r IN (
        SELECT UDE_ID, nb FROM (
            SELECT NVL(UDE_ID,'(NULL)') UDE_ID, COUNT(*) nb
            FROM ICTM_PR_INT_UDEVALS
            GROUP BY UDE_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  UDE_ID = ' || r.UDE_ID, TO_CHAR(r.nb));
    END LOOP;

    -- 9.2.c Stats UDE_VALUE par UDE_ID principaux
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2.c Stats UDE_VALUE (taux) par UDE_ID]');
    FOR r IN (
        SELECT UDE_ID, nb, mn, mx, av FROM (
            SELECT UDE_ID,
                   COUNT(*) nb,
                   ROUND(MIN(UDE_VALUE),4) mn,
                   ROUND(MAX(UDE_VALUE),4) mx,
                   ROUND(AVG(UDE_VALUE),4) av
            FROM ICTM_PR_INT_UDEVALS
            WHERE UDE_VALUE IS NOT NULL
            GROUP BY UDE_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.UDE_ID, 'nb=' || TO_CHAR(r.nb)
                 || ' | min=' || TO_CHAR(r.mn)
                 || ' | max=' || TO_CHAR(r.mx)
                 || ' | moy=' || TO_CHAR(r.av));
    END LOOP;

    -- 9.2.d Plage temporelle des effets (UDE_EFF_DT)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2.d Plage temporelle des taux catalogue]');
    FOR r IN (
        SELECT MIN(UDE_EFF_DT) mn, MAX(UDE_EFF_DT) mx FROM ICTM_PR_INT_UDEVALS
    ) LOOP
        print_kv('  UDE_EFF_DT min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  UDE_EFF_DT max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    -- 9.2.e Taux catalogue par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.2.e Top 10 devises côté taux catalogue]');
    FOR r IN (
        SELECT CCY_CODE, nb FROM (
            SELECT NVL(CCY_CODE,'(NULL)') CCY_CODE, COUNT(*) nb
            FROM ICTM_PR_INT_UDEVALS
            GROUP BY CCY_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY ' || r.CCY_CODE, TO_CHAR(r.nb));
    END LOOP;

    -- 9.3 Taux compte (ICTM_ACC_UDEVALS) — dérogations individuelles
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3 Taux compte — ICTM_ACC_UDEVALS]');
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Total taux compte', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACC) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Comptes distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT PROD) INTO v_count FROM ICTM_ACC_UDEVALS;
    print_kv('  Produits distincts', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.b Statut d''enregistrement]');
    FOR r IN (SELECT NVL(AUTH_STAT,'(NULL)') s, COUNT(*) nb
              FROM ICTM_ACC_UDEVALS GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(RECORD_STAT,'(NULL)') s, COUNT(*) nb
              FROM ICTM_ACC_UDEVALS GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        print_kv('  RECORD_STAT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 9.3.c UDE_VARIANCE — dérogations sur taux (fuite directe)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.c UDE_VARIANCE — variance de taux par compte]');
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS
    WHERE UDE_VARIANCE IS NOT NULL AND UDE_VARIANCE <> 0;
    print_kv('  Comptes avec variance non nulle', TO_CHAR(v_count));
    FOR r IN (
        SELECT ROUND(MIN(UDE_VARIANCE),4) mn,
               ROUND(MAX(UDE_VARIANCE),4) mx,
               ROUND(AVG(UDE_VARIANCE),4) av
        FROM ICTM_ACC_UDEVALS
        WHERE UDE_VARIANCE IS NOT NULL AND UDE_VARIANCE <> 0
    ) LOOP
        print_kv('  UDE_VARIANCE min', TO_CHAR(r.mn));
        print_kv('  UDE_VARIANCE max', TO_CHAR(r.mx));
        print_kv('  UDE_VARIANCE moy', TO_CHAR(r.av));
    END LOOP;

    -- 9.3.d Variance négative (taux défavorable banque)
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS WHERE UDE_VARIANCE < 0;
    print_kv('  Variance NEGATIVE (taux en dessous catalogue)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS WHERE UDE_VARIANCE > 0;
    print_kv('  Variance POSITIVE (taux au dessus catalogue)', TO_CHAR(v_count));

    -- 9.3.e Répartition des dérogations par PROD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.e Top 15 PROD avec plus de dérogations (variance <> 0)]');
    FOR r IN (
        SELECT PROD, nb FROM (
            SELECT NVL(PROD,'(NULL)') PROD, COUNT(*) nb
            FROM ICTM_ACC_UDEVALS
            WHERE UDE_VARIANCE <> 0
            GROUP BY PROD ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PROD ' || r.PROD, TO_CHAR(r.nb));
    END LOOP;

    -- 9.3.f Comptes avec plus grand nombre de taux dérogatoires
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.f Top 15 comptes avec plus de taux dérogatoires]');
    FOR r IN (
        SELECT ACC, BRN, nb FROM (
            SELECT ACC, BRN, COUNT(*) nb
            FROM ICTM_ACC_UDEVALS
            WHERE UDE_VARIANCE <> 0
            GROUP BY ACC, BRN
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRN || ' / ' || r.ACC, TO_CHAR(r.nb));
    END LOOP;

    -- 9.3.g BASE_RATE / BASE_SPREAD — stats
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.g Stats BASE_RATE / BASE_SPREAD sur comptes]');
    FOR r IN (
        SELECT COUNT(BASE_RATE) nb_br,
               ROUND(MIN(BASE_RATE),4) mn_br,
               ROUND(MAX(BASE_RATE),4) mx_br,
               ROUND(AVG(BASE_RATE),4) av_br,
               COUNT(BASE_SPREAD) nb_bs,
               ROUND(MIN(BASE_SPREAD),4) mn_bs,
               ROUND(MAX(BASE_SPREAD),4) mx_bs,
               ROUND(AVG(BASE_SPREAD),4) av_bs
        FROM ICTM_ACC_UDEVALS
    ) LOOP
        print_kv('  BASE_RATE nb / min / max / moy',
                 TO_CHAR(r.nb_br) || ' / ' || TO_CHAR(r.mn_br) ||
                 ' / ' || TO_CHAR(r.mx_br) || ' / ' || TO_CHAR(r.av_br));
        print_kv('  BASE_SPREAD nb / min / max / moy',
                 TO_CHAR(r.nb_bs) || ' / ' || TO_CHAR(r.mn_bs) ||
                 ' / ' || TO_CHAR(r.mx_bs) || ' / ' || TO_CHAR(r.av_bs));
    END LOOP;

    -- 9.3.h Effectivité des taux (dates postérieures / antérieures)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.3.h Effectivité UDE_EFF_DT sur comptes]');
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS WHERE UDE_EFF_DT > SYSDATE;
    print_kv('  Taux futurs (eff > SYSDATE)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_ACC_UDEVALS WHERE UDE_EFF_DT <= SYSDATE;
    print_kv('  Taux actifs / passés', TO_CHAR(v_count));

    -- 9.4 ICTM_EXPR — expressions de calcul
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.4 ICTM_EXPR — expressions de calcul IC]');
    SELECT COUNT(DISTINCT RULE_ID) INTO v_count FROM ICTM_EXPR;
    print_kv('  Nb RULE_ID distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT FRM_NO) INTO v_count FROM ICTM_EXPR;
    print_kv('  Nb FRM_NO distincts', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_EXPR WHERE COND IS NOT NULL AND COND <> ' ';
    print_kv('  Lignes avec CONDITION', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ICTM_EXPR WHERE RESULT IS NOT NULL AND RESULT <> ' ';
    print_kv('  Lignes avec RESULT', TO_CHAR(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.4.b Top 15 RULE_ID par nb de lignes d''expression]');
    FOR r IN (
        SELECT RULE_ID, nb FROM (
            SELECT NVL(RULE_ID,'(NULL)') RULE_ID, COUNT(*) nb
            FROM ICTM_EXPR
            GROUP BY RULE_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  RULE_ID ' || r.RULE_ID, TO_CHAR(r.nb));
    END LOOP;

    -- 9.5 Alignement catalogue vs compte (taux compte sans catalogue correspondant)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [9.5 Cohérence catalogue vs compte]');
    SELECT COUNT(*) INTO v_count
    FROM ICTM_ACC_UDEVALS a
    WHERE NOT EXISTS (
        SELECT 1 FROM ICTM_PR_INT_UDEVALS p
        WHERE p.PRODUCT_CODE = a.PROD
          AND p.UDE_ID       = a.UDE_ID
    );
    print_kv('  Taux compte sans UDE_ID catalogué pour le produit', TO_CHAR(v_count));
END;
/
