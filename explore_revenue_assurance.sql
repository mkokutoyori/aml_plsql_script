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
END;
/
