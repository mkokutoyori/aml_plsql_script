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

    -- =========================================================
    -- 10. GLTB_GL_BAL — REVENUS & CHARGES AU GRAND LIVRE
    --    Angle Revenue Assurance :
    --     - GLTB_GL_BAL contient les soldes et mouvements par
    --       GL / agence / devise / période. Les GL revenus
    --       (intérêts perçus, commissions, frais) et GL charges
    --       (intérêts servis) sont la traduction comptable
    --       finale du revenu.
    --     - Comparaison GL (position comptable) vs ACTB_HISTORY
    --       (flux) vs sous-systèmes (LDTB/CLTB) = boucle de
    --       rapprochement revenue assurance.
    --     - Mouvements suspects : OPEN vs CR/DR MOV, OLD vs new.
    -- =========================================================
    print_section('10. GLTB_GL_BAL — Revenus & charges au grand livre');

    -- 10.1 Volumétrie
    DBMS_OUTPUT.PUT_LINE('  [10.1 Volumétrie GLTB_GL_BAL]');
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Total lignes GL_BAL', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT GL_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  GL_CODE distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Branches distinctes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CCY_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Devises distinctes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT FIN_YEAR) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Années fiscales couvertes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT PERIOD_CODE) INTO v_count FROM GLTB_GL_BAL;
    print_kv('  Périodes distinctes', TO_CHAR(v_count));

    -- 10.2 Répartition CATEGORY (Asset, Liability, Income, Expense, ...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.2 Répartition CATEGORY (P/L vs Bilan)]');
    FOR r IN (
        SELECT NVL(CATEGORY,'(NULL)') CATEGORY, COUNT(*) nb
        FROM GLTB_GL_BAL GROUP BY CATEGORY ORDER BY nb DESC
    ) LOOP
        print_kv('  CATEGORY = ' || r.CATEGORY, TO_CHAR(r.nb));
    END LOOP;

    -- 10.3 Répartition LEAF (feuille = GL opérationnel)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.3 LEAF (feuille vs agrégat)]');
    FOR r IN (
        SELECT NVL(LEAF,'(NULL)') LEAF, COUNT(*) nb
        FROM GLTB_GL_BAL GROUP BY LEAF ORDER BY nb DESC
    ) LOOP
        print_kv('  LEAF = ' || r.LEAF, TO_CHAR(r.nb));
    END LOOP;

    -- 10.4 Mouvements par CATEGORY (INCOME / EXPENSE) — focus revenu
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.4 Mouvements GL — revenus (INCOME) / charges (EXPENSE)]');
    FOR r IN (
        SELECT CATEGORY,
               COUNT(*) nb,
               ROUND(SUM(CR_MOV_LCY),2) sm_cr,
               ROUND(SUM(DR_MOV_LCY),2) sm_dr,
               ROUND(SUM(CR_BAL_LCY),2) sm_crb,
               ROUND(SUM(DR_BAL_LCY),2) sm_drb
        FROM GLTB_GL_BAL
        WHERE CATEGORY IN ('I','E','INCOME','EXPENSE','REVENUE','CHARGE')
        GROUP BY CATEGORY
    ) LOOP
        print_kv('  CAT ' || r.CATEGORY,
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | CR mov=' || TO_CHAR(r.sm_cr) ||
                 ' | DR mov=' || TO_CHAR(r.sm_dr));
        print_kv('  CAT ' || r.CATEGORY || ' soldes',
                 'CR bal=' || TO_CHAR(r.sm_crb) ||
                 ' | DR bal=' || TO_CHAR(r.sm_drb));
    END LOOP;

    -- 10.5 Revenus par année fiscale (tous GL)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.5 Mouvements par FIN_YEAR (tous GL)]');
    FOR r IN (
        SELECT FIN_YEAR, COUNT(*) nb,
               ROUND(SUM(CR_MOV_LCY),2) sm_cr,
               ROUND(SUM(DR_MOV_LCY),2) sm_dr
        FROM GLTB_GL_BAL
        WHERE FIN_YEAR IS NOT NULL
        GROUP BY FIN_YEAR ORDER BY FIN_YEAR
    ) LOOP
        print_kv('  FY ' || r.FIN_YEAR,
                 'nb=' || TO_CHAR(r.nb) ||
                 ' | CR=' || TO_CHAR(r.sm_cr) ||
                 ' | DR=' || TO_CHAR(r.sm_dr));
    END LOOP;

    -- 10.6 Top 20 GL_CODE par CR_MOV_LCY (candidats comptes revenu)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.6 Top 20 GL_CODE par CR_MOV_LCY (revenus)]');
    FOR r IN (
        SELECT GL_CODE, sm FROM (
            SELECT GL_CODE, ROUND(SUM(CR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            GROUP BY GL_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  GL ' || r.GL_CODE, 'CR mov LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.7 Top 20 GL_CODE par DR_MOV_LCY (candidats comptes charges)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.7 Top 20 GL_CODE par DR_MOV_LCY (charges)]');
    FOR r IN (
        SELECT GL_CODE, sm FROM (
            SELECT GL_CODE, ROUND(SUM(DR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            GROUP BY GL_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  GL ' || r.GL_CODE, 'DR mov LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.8 Revenus par agence (top 15)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.8 Top 15 BRANCH_CODE par CR_MOV_LCY total]');
    FOR r IN (
        SELECT BRANCH_CODE, sm FROM (
            SELECT BRANCH_CODE, ROUND(SUM(CR_MOV_LCY),2) sm
            FROM GLTB_GL_BAL
            GROUP BY BRANCH_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  BRANCHE ' || r.BRANCH_CODE, 'CR mov LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 10.9 Revenus par CCY (top 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.9 Top 10 devises (CR_MOV_LCY)]');
    FOR r IN (
        SELECT CCY_CODE, sm, sm_fcy FROM (
            SELECT CCY_CODE,
                   ROUND(SUM(CR_MOV_LCY),2) sm,
                   ROUND(SUM(CR_MOV),2) sm_fcy
            FROM GLTB_GL_BAL
            GROUP BY CCY_CODE
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY ' || r.CCY_CODE,
                 'CR LCY=' || TO_CHAR(r.sm) || ' | CR FCY=' || TO_CHAR(r.sm_fcy));
    END LOOP;

    -- 10.10 UNCOLLECTED (solde non collecté sur GL)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.10 UNCOLLECTED (fonds non collectés sur GL)]');
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL WHERE UNCOLLECTED IS NOT NULL AND UNCOLLECTED <> 0;
    print_kv('  Lignes avec UNCOLLECTED non nul', TO_CHAR(v_count));
    SELECT NVL(ROUND(SUM(UNCOLLECTED),2),0) INTO v_num FROM GLTB_GL_BAL;
    print_kv('  SUM UNCOLLECTED', TO_CHAR(v_num));

    -- 10.11 Écart OLD vs NEW mouvements (indicateur reprise/correction)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.11 Ecart CR_MOV_LCY vs CR_MOV_LCY_OLD]');
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL
    WHERE NVL(CR_MOV_LCY,0) <> NVL(CR_MOV_LCY_OLD,0);
    print_kv('  Lignes avec CR_MOV_LCY <> CR_MOV_LCY_OLD', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL
    WHERE NVL(DR_MOV_LCY,0) <> NVL(DR_MOV_LCY_OLD,0);
    print_kv('  Lignes avec DR_MOV_LCY <> DR_MOV_LCY_OLD', TO_CHAR(v_count));

    -- 10.12 Turnovers intraday ACY/LCY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.12 Turnovers intraday (ACY/LCY today)]');
    FOR r IN (
        SELECT ROUND(SUM(ACY_TODAY_TOVER_CR),2) a_cr,
               ROUND(SUM(ACY_TODAY_TOVER_DR),2) a_dr,
               ROUND(SUM(LCY_TODAY_TOVER_CR),2) l_cr,
               ROUND(SUM(LCY_TODAY_TOVER_DR),2) l_dr
        FROM GLTB_GL_BAL
    ) LOOP
        print_kv('  SUM ACY_TODAY_TOVER_CR', TO_CHAR(r.a_cr));
        print_kv('  SUM ACY_TODAY_TOVER_DR', TO_CHAR(r.a_dr));
        print_kv('  SUM LCY_TODAY_TOVER_CR', TO_CHAR(r.l_cr));
        print_kv('  SUM LCY_TODAY_TOVER_DR', TO_CHAR(r.l_dr));
    END LOOP;

    -- 10.13 Cohérence GL (solde + mov) — ouverture + mov = balance
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.13 Cohérence OPEN + MOV vs BAL (LCY)]');
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL
    WHERE ABS(NVL(OPEN_CR_BAL_LCY,0) + NVL(CR_MOV_LCY,0) - NVL(CR_BAL_LCY,0)) > 1
      AND CR_BAL_LCY IS NOT NULL;
    print_kv('  Ecart CR : OPEN+MOV vs BAL > 1', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM GLTB_GL_BAL
    WHERE ABS(NVL(OPEN_DR_BAL_LCY,0) + NVL(DR_MOV_LCY,0) - NVL(DR_BAL_LCY,0)) > 1
      AND DR_BAL_LCY IS NOT NULL;
    print_kv('  Ecart DR : OPEN+MOV vs BAL > 1', TO_CHAR(v_count));

    -- 10.14 Rapprochement ACTB_HISTORY vs GLTB_GL_BAL (par année x GL)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [10.14 Rapprochement ACTB vs GL (top 10 plus gros écarts sur agrégats)]');
    FOR r IN (
        SELECT gl, sm_actb, sm_gl, ecart FROM (
            SELECT a.gl,
                   ROUND(a.sm,2) sm_actb,
                   ROUND(NVL(g.sm,0),2) sm_gl,
                   ROUND(a.sm - NVL(g.sm,0),2) ecart
            FROM (
                SELECT NVL(AC_GL_NO, AC_NO) gl,
                       SUM(CASE WHEN DRCR_IND = 'C' THEN LCY_AMOUNT ELSE 0 END) sm
                FROM ACTB_HISTORY
                GROUP BY NVL(AC_GL_NO, AC_NO)
            ) a
            LEFT JOIN (
                SELECT GL_CODE gl, SUM(CR_MOV_LCY) sm
                FROM GLTB_GL_BAL GROUP BY GL_CODE
            ) g ON g.gl = a.gl
            ORDER BY ABS(a.sm - NVL(g.sm,0)) DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  GL ' || r.gl,
                 'ACTB=' || TO_CHAR(r.sm_actb) ||
                 ' | GL=' || TO_CHAR(r.sm_gl) ||
                 ' | ecart=' || TO_CHAR(r.ecart));
    END LOOP;

    -- =========================================================
    -- 11. RVTB_ACC_REVAL — REEVALUATION FX & P&L
    --    Angle Revenue Assurance :
    --     - Les positions en devises sont réévaluées
    --       périodiquement. L'écart entre OLD_LCY_EQUIVALENT
    --       et NEW_LCY_EQUIVALENT (NEW_RATE appliqué sur
    --       ACCOUNT_BALANCE) génère un gain/perte FX =
    --       P&L à auditer.
    --     - Croisé avec CYTB_RATES_HISTORY pour vérifier que
    --       les taux utilisés correspondent bien au cours du
    --       jour de réévaluation.
    -- =========================================================
    print_section('11. RVTB_ACC_REVAL — Réévaluation FX & P&L');

    -- 11.1 Volumétrie & plage
    DBMS_OUTPUT.PUT_LINE('  [11.1 Volumétrie RVTB_ACC_REVAL]');
    SELECT COUNT(*) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Total lignes réévaluation', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Comptes réévalués distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CCY) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Devises réévaluées', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM RVTB_ACC_REVAL;
    print_kv('  Branches concernées', TO_CHAR(v_count));
    FOR r IN (SELECT MIN(REVAL_DATE) mn, MAX(REVAL_DATE) mx FROM RVTB_ACC_REVAL) LOOP
        print_kv('  REVAL_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  REVAL_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    -- 11.2 Répartition REVAL_IND (P/L revalué ou non)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.2 REVAL_IND (sens P&L)]');
    FOR r IN (
        SELECT NVL(REVAL_IND,'(NULL)') REVAL_IND, COUNT(*) nb
        FROM RVTB_ACC_REVAL GROUP BY REVAL_IND ORDER BY nb DESC
    ) LOOP
        print_kv('  REVAL_IND = ' || r.REVAL_IND, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.2.b PL_SPLIT_FLAG & TRADING_PL_INDICATOR]');
    FOR r IN (SELECT NVL(PL_SPLIT_FLAG,'(NULL)') s, COUNT(*) nb
              FROM RVTB_ACC_REVAL GROUP BY PL_SPLIT_FLAG ORDER BY nb DESC) LOOP
        print_kv('  PL_SPLIT_FLAG = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(TRADING_PL_INDICATOR,'(NULL)') s, COUNT(*) nb
              FROM RVTB_ACC_REVAL GROUP BY TRADING_PL_INDICATOR ORDER BY nb DESC) LOOP
        print_kv('  TRADING_PL_INDICATOR = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(GLMIS_UPD_STATUS,'(NULL)') s, COUNT(*) nb
              FROM RVTB_ACC_REVAL GROUP BY GLMIS_UPD_STATUS ORDER BY nb DESC) LOOP
        print_kv('  GLMIS_UPD_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 11.3 Agrégats P&L FX
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.3 Agrégats P&L FX]');
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(OLD_LCY_EQUIVALENT),2) sm_o,
               ROUND(SUM(NEW_LCY_EQUIVALENT),2) sm_n,
               ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) sm_pl
        FROM RVTB_ACC_REVAL
    ) LOOP
        print_kv('  SUM OLD_LCY_EQUIVALENT', TO_CHAR(r.sm_o));
        print_kv('  SUM NEW_LCY_EQUIVALENT', TO_CHAR(r.sm_n));
        print_kv('  SUM P&L FX (NEW - OLD)', TO_CHAR(r.sm_pl));
    END LOOP;

    -- 11.3.b Trading P&L (si séparation)
    FOR r IN (
        SELECT COUNT(*) nb,
               ROUND(SUM(TRADING_OLD_LCY_EQUIVALENT),2) sm_o,
               ROUND(SUM(TRADING_NEW_LCY_EQUIVALENT),2) sm_n,
               ROUND(SUM(TRADING_NEW_LCY_EQUIVALENT - TRADING_OLD_LCY_EQUIVALENT),2) sm_pl
        FROM RVTB_ACC_REVAL
        WHERE TRADING_OLD_LCY_EQUIVALENT IS NOT NULL
           OR TRADING_NEW_LCY_EQUIVALENT IS NOT NULL
    ) LOOP
        print_kv('  Trading — nb lignes', TO_CHAR(r.nb));
        print_kv('  Trading — SUM OLD LCY', TO_CHAR(r.sm_o));
        print_kv('  Trading — SUM NEW LCY', TO_CHAR(r.sm_n));
        print_kv('  Trading — SUM P&L FX', TO_CHAR(r.sm_pl));
    END LOOP;

    -- 11.4 Réévaluation par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.4 Top 10 devises par volume réévalué (|NEW-OLD|)]');
    FOR r IN (
        SELECT CCY, nb, sm FROM (
            SELECT NVL(CCY,'(NULL)') CCY, COUNT(*) nb,
                   ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) sm
            FROM RVTB_ACC_REVAL
            GROUP BY CCY
            ORDER BY ABS(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT)) DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  CCY ' || r.CCY, 'nb=' || TO_CHAR(r.nb) || ' | P&L FX=' || TO_CHAR(r.sm));
    END LOOP;

    -- 11.5 Réévaluation par année
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.5 Réévaluation P&L FX par année]');
    FOR r IN (
        SELECT TO_CHAR(REVAL_DATE,'YYYY') annee,
               COUNT(*) nb,
               ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) sm
        FROM RVTB_ACC_REVAL
        WHERE REVAL_DATE IS NOT NULL
        GROUP BY TO_CHAR(REVAL_DATE,'YYYY')
        ORDER BY annee
    ) LOOP
        print_kv('  ' || r.annee, 'nb=' || TO_CHAR(r.nb) || ' | P&L FX=' || TO_CHAR(r.sm));
    END LOOP;

    -- 11.6 Top 15 comptes avec le plus grand |ecart FX| (comptes matériels)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.6 Top 15 comptes par |P&L FX|]');
    FOR r IN (
        SELECT ACCOUNT, BRANCH_CODE, CCY, sm FROM (
            SELECT ACCOUNT, BRANCH_CODE, CCY,
                   ROUND(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),2) sm
            FROM RVTB_ACC_REVAL
            GROUP BY ACCOUNT, BRANCH_CODE, CCY
            ORDER BY ABS(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT)) DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRANCH_CODE || '/' || r.ACCOUNT || '/' || r.CCY,
                 'P&L=' || TO_CHAR(r.sm));
    END LOOP;

    -- 11.7 Top comptes PNL / REVAL_ACCOUNT (GL revenus FX)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.7 Top 10 PNL_ACCOUNT utilisés]');
    FOR r IN (
        SELECT PNL_ACCOUNT, nb FROM (
            SELECT NVL(PNL_ACCOUNT,'(NULL)') PNL_ACCOUNT, COUNT(*) nb
            FROM RVTB_ACC_REVAL
            GROUP BY PNL_ACCOUNT ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  PNL_ACCOUNT ' || r.PNL_ACCOUNT, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.7.b Top 10 REVAL_ACCOUNT]');
    FOR r IN (
        SELECT REVAL_ACCOUNT, nb FROM (
            SELECT NVL(REVAL_ACCOUNT,'(NULL)') REVAL_ACCOUNT, COUNT(*) nb
            FROM RVTB_ACC_REVAL
            GROUP BY REVAL_ACCOUNT ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  REVAL_ACCOUNT ' || r.REVAL_ACCOUNT, TO_CHAR(r.nb));
    END LOOP;

    -- 11.8 CYTB_RATES_HISTORY — volumétrie & plage temporelle
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.8 CYTB_RATES_HISTORY — cours de change historiques]');
    SELECT COUNT(*) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  Total lignes taux', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CCY1 || CCY2) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  Couples CCY1/CCY2 distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT RATE_TYPE) INTO v_count FROM CYTB_RATES_HISTORY;
    print_kv('  RATE_TYPE distincts', TO_CHAR(v_count));
    FOR r IN (SELECT MIN(RATE_DATE) mn, MAX(RATE_DATE) mx FROM CYTB_RATES_HISTORY) LOOP
        print_kv('  RATE_DATE min', TO_CHAR(r.mn,'DD/MM/YYYY'));
        print_kv('  RATE_DATE max', TO_CHAR(r.mx,'DD/MM/YYYY'));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.8.b Top 10 couples devises par nb de cotations]');
    FOR r IN (
        SELECT CCY1, CCY2, nb FROM (
            SELECT CCY1, CCY2, COUNT(*) nb
            FROM CYTB_RATES_HISTORY
            GROUP BY CCY1, CCY2 ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.CCY1 || '/' || r.CCY2, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.8.c Répartition RATE_TYPE]');
    FOR r IN (
        SELECT NVL(RATE_TYPE,'(NULL)') RATE_TYPE, COUNT(*) nb
        FROM CYTB_RATES_HISTORY GROUP BY RATE_TYPE ORDER BY nb DESC
    ) LOOP
        print_kv('  RATE_TYPE = ' || r.RATE_TYPE, TO_CHAR(r.nb));
    END LOOP;

    -- 11.8.d Spread BUY/SALE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.8.d Spread BUY vs SALE par RATE_TYPE]');
    FOR r IN (
        SELECT RATE_TYPE,
               ROUND(AVG(SALE_RATE - BUY_RATE),6) av_spread,
               ROUND(MAX(SALE_RATE - BUY_RATE),6) mx_spread
        FROM CYTB_RATES_HISTORY
        WHERE BUY_RATE IS NOT NULL AND SALE_RATE IS NOT NULL
          AND SALE_RATE >= BUY_RATE
        GROUP BY RATE_TYPE
        ORDER BY av_spread DESC NULLS LAST
    ) LOOP
        print_kv('  ' || r.RATE_TYPE,
                 'spread moy=' || TO_CHAR(r.av_spread) ||
                 ' | max=' || TO_CHAR(r.mx_spread));
    END LOOP;

    -- 11.8.e Anomalies : SALE < BUY (cours inversés)
    SELECT COUNT(*) INTO v_count FROM CYTB_RATES_HISTORY
    WHERE BUY_RATE IS NOT NULL AND SALE_RATE IS NOT NULL
      AND SALE_RATE < BUY_RATE;
    print_kv('  Anomalie SALE_RATE < BUY_RATE', TO_CHAR(v_count));

    -- 11.9 CYTB_DERIVED_RATES_HISTORY — taux dérivés (croisés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.9 CYTB_DERIVED_RATES_HISTORY — taux dérivés]');
    SELECT COUNT(*) INTO v_count FROM CYTB_DERIVED_RATES_HISTORY;
    print_kv('  Total taux dérivés', TO_CHAR(v_count));
    FOR r IN (SELECT NVL(RATE_FLAG,'(NULL)') s, COUNT(*) nb
              FROM CYTB_DERIVED_RATES_HISTORY GROUP BY RATE_FLAG ORDER BY nb DESC) LOOP
        print_kv('  RATE_FLAG = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 11.10 Rapprochement NEW_RATE RVTB vs CYTB cours du jour
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [11.10 Contrôles cohérence NEW_RATE / ACCOUNT_BALANCE / NEW_LCY]');
    SELECT COUNT(*) INTO v_count FROM RVTB_ACC_REVAL
    WHERE ACCOUNT_BALANCE IS NOT NULL AND NEW_RATE IS NOT NULL
      AND NEW_LCY_EQUIVALENT IS NOT NULL AND NEW_RATE <> 0
      AND ABS(ACCOUNT_BALANCE * NEW_RATE - NEW_LCY_EQUIVALENT) > 1;
    print_kv('  Ecart ACCOUNT_BALANCE*NEW_RATE vs NEW_LCY > 1', TO_CHAR(v_count));

    ----------------------------------------------------------------
    -- SECTION 12 : Comptes clients — turnovers, overdraft, dormance
    --   Revenue Assurance : traquer les comptes dormants mal taris
    --   les overdrafts non facturés (TOD), les turnovers anormaux
    --   (base d'assiette commissions) et les statuts de compte qui
    --   pourraient bloquer la perception de commissions/charges.
    ----------------------------------------------------------------
    print_section('SECTION 12 — Comptes clients (turnovers / overdraft / dormance)');

    -- 12.1 Volumétrie STTM_CUST_ACCOUNT
    DBMS_OUTPUT.PUT_LINE('  [12.1 Volumétrie STTM_CUST_ACCOUNT]');
    safe_count('STTM_CUST_ACCOUNT', '  Total comptes clients');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AUTH_STAT='A';
    print_kv('  Autorisés (A)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AUTH_STAT='U';
    print_kv('  Non autorisés (U)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT='C';
    print_kv('  Clôturés (RECORD_STAT=C)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE RECORD_STAT='O';
    print_kv('  Ouverts (RECORD_STAT=O)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE ONCE_AUTH='N';
    print_kv('  Jamais autorisés (ONCE_AUTH=N)', TO_CHAR(v_count));

    -- 12.2 Répartition par ACCOUNT_CLASS (top 20)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.2 Top ACCOUNT_CLASS (volume de comptes)]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(ACCOUNT_CLASS,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT GROUP BY ACCOUNT_CLASS
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 12.3 Répartition par ACCOUNT_TYPE / CCY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.3 Répartition ACCOUNT_TYPE]');
    FOR r IN (SELECT NVL(ACCOUNT_TYPE,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUST_ACCOUNT GROUP BY ACCOUNT_TYPE ORDER BY nb DESC) LOOP
        print_kv('  TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.3.b Top 15 devises CCY]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CCY,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT GROUP BY CCY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CCY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 12.4 Statuts RA-sensibles (dormant / frozen / stop_pay / no_cr / no_dr / block / depost)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.4 Statuts RA-sensibles (flags Y)]');
    FOR r IN (
        SELECT 'AC_STAT_DORMANT=Y'   lbl, COUNT(*) nb FROM STTM_CUST_ACCOUNT WHERE AC_STAT_DORMANT='Y' UNION ALL
        SELECT 'AC_STAT_FROZEN=Y',          COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_FROZEN='Y' UNION ALL
        SELECT 'AC_STAT_STOP_PAY=Y',        COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_STOP_PAY='Y' UNION ALL
        SELECT 'AC_STAT_NO_CR=Y',           COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_NO_CR='Y' UNION ALL
        SELECT 'AC_STAT_NO_DR=Y',           COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_NO_DR='Y' UNION ALL
        SELECT 'AC_STAT_BLOCK=Y',           COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_BLOCK='Y' UNION ALL
        SELECT 'AC_STAT_DE_POST=Y',         COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_DE_POST='Y' UNION ALL
        SELECT 'ACCOUNT_AUTO_CLOSED=Y',     COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE ACCOUNT_AUTO_CLOSED='Y' UNION ALL
        SELECT 'AC_SET_CLOSE=Y',            COUNT(*)    FROM STTM_CUST_ACCOUNT WHERE AC_SET_CLOSE='Y'
    ) LOOP
        print_kv('  ' || r.lbl, TO_CHAR(r.nb));
    END LOOP;

    -- 12.4.b ACCOUNT_DERIVED_STATUS (statut IC — STATUS_CODE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.4.b ACCOUNT_DERIVED_STATUS (top 20)]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(ACCOUNT_DERIVED_STATUS,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT GROUP BY ACCOUNT_DERIVED_STATUS
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 12.4.c ACC_STATUS (statut IC — évolution)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.4.c ACC_STATUS (IC) top 20]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(ACC_STATUS,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT GROUP BY ACC_STATUS
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 12.5 Ancienneté & ouverture
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.5 Ouverture des comptes — AC_OPEN_DATE]');
    FOR r IN (
        SELECT TO_CHAR(AC_OPEN_DATE,'YYYY') yr, COUNT(*) nb
        FROM STTM_CUST_ACCOUNT WHERE AC_OPEN_DATE IS NOT NULL
        GROUP BY TO_CHAR(AC_OPEN_DATE,'YYYY')
        ORDER BY yr DESC
    ) LOOP
        print_kv('  ' || r.yr, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE AC_OPEN_DATE IS NULL;
    print_kv('  AC_OPEN_DATE IS NULL', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_OPEN_DATE IS NOT NULL AND AC_OPEN_DATE > SYSDATE;
    print_kv('  AC_OPEN_DATE > SYSDATE (anomalie)', TO_CHAR(v_count));

    -- 12.6 Dormance — paramètre + date + dormancy_days
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.6 Dormance — DORMANT_PARAM / DORMANCY_DATE / DORMANCY_DAYS]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='Y';
    print_kv('  Comptes dormants', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='Y' AND DORMANCY_DATE IS NULL;
    print_kv('  Dormants SANS DORMANCY_DATE (anomalie RA)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='N' AND DORMANCY_DATE IS NOT NULL;
    print_kv('  Non-dormants AVEC DORMANCY_DATE (anomalie RA)', TO_CHAR(v_count));

    FOR r IN (SELECT NVL(DORMANT_PARAM,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUST_ACCOUNT GROUP BY DORMANT_PARAM
              ORDER BY nb DESC) LOOP
        print_kv('  DORMANT_PARAM = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.6.b Tranches DORMANCY_DAYS]');
    FOR r IN (
        SELECT CASE
                 WHEN DORMANCY_DAYS IS NULL THEN '(NULL)'
                 WHEN DORMANCY_DAYS <= 0   THEN '0 ou négatif'
                 WHEN DORMANCY_DAYS <= 90  THEN '1-90j'
                 WHEN DORMANCY_DAYS <= 180 THEN '91-180j'
                 WHEN DORMANCY_DAYS <= 365 THEN '181-365j'
                 WHEN DORMANCY_DAYS <= 730 THEN '1-2ans'
                 WHEN DORMANCY_DAYS <=1825 THEN '2-5ans'
                 ELSE '5+ans'
               END tr,
               COUNT(*) nb
        FROM STTM_CUST_ACCOUNT
        GROUP BY CASE
                 WHEN DORMANCY_DAYS IS NULL THEN '(NULL)'
                 WHEN DORMANCY_DAYS <= 0   THEN '0 ou négatif'
                 WHEN DORMANCY_DAYS <= 90  THEN '1-90j'
                 WHEN DORMANCY_DAYS <= 180 THEN '91-180j'
                 WHEN DORMANCY_DAYS <= 365 THEN '181-365j'
                 WHEN DORMANCY_DAYS <= 730 THEN '1-2ans'
                 WHEN DORMANCY_DAYS <=1825 THEN '2-5ans'
                 ELSE '5+ans'
               END
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ' || r.tr, TO_CHAR(r.nb));
    END LOOP;

    -- 12.7 Overdraft (TOD) — limites et dépassements
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.7 Overdraft (TOD) — limites & dépassements]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE TOD_LIMIT IS NOT NULL AND TOD_LIMIT > 0;
    print_kv('  Comptes avec TOD_LIMIT > 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE TOD_SINCE IS NOT NULL;
    print_kv('  Comptes en TOD (TOD_SINCE renseigné)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE TOD_SINCE IS NOT NULL AND TOD_LIMIT_START_DATE IS NOT NULL
      AND TOD_SINCE < TOD_LIMIT_START_DATE;
    print_kv('  TOD_SINCE AVANT TOD_LIMIT_START_DATE (leak RA)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE TOD_LIMIT_END_DATE IS NOT NULL AND TOD_LIMIT_END_DATE < SYSDATE
      AND (TOD_LIMIT IS NOT NULL AND TOD_LIMIT > 0);
    print_kv('  TOD_LIMIT actif mais END_DATE passée', TO_CHAR(v_count));

    SELECT NVL(SUM(TOD_LIMIT),0) INTO v_num FROM STTM_CUST_ACCOUNT WHERE TOD_LIMIT IS NOT NULL;
    print_kv('  Somme TOD_LIMIT (toutes devises)', TO_CHAR(v_num));

    -- 12.7.b Overdraft réel : ACY_CURR_BALANCE < 0 sans TOD_LIMIT
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE ACY_CURR_BALANCE < 0 AND NVL(TOD_LIMIT,0) = 0;
    print_kv('  Débiteurs SANS TOD_LIMIT (overdraft non couvert)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE ACY_CURR_BALANCE < 0 AND TOD_LIMIT IS NOT NULL
      AND ABS(ACY_CURR_BALANCE) > TOD_LIMIT;
    print_kv('  Débiteurs au-delà de TOD_LIMIT (dépassement)', TO_CHAR(v_count));

    -- 12.7.c OVERDRAFT_SINCE, OVERLINE_OD_SINCE
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE OVERDRAFT_SINCE IS NOT NULL;
    print_kv('  OVERDRAFT_SINCE renseigné', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE OVERLINE_OD_SINCE IS NOT NULL;
    print_kv('  OVERLINE_OD_SINCE renseigné', TO_CHAR(v_count));

    -- 12.8 Balances négatives courantes (top 15 par |LCY_CURR_BALANCE|)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.8 Top 15 comptes débiteurs par |LCY_CURR_BALANCE|]');
    FOR r IN (
        SELECT * FROM (
            SELECT BRANCH_CODE, CUST_AC_NO, CCY,
                   ACY_CURR_BALANCE acy, LCY_CURR_BALANCE lcy,
                   TOD_LIMIT tod
            FROM STTM_CUST_ACCOUNT
            WHERE LCY_CURR_BALANCE IS NOT NULL
              AND LCY_CURR_BALANCE < 0
            ORDER BY LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRANCH_CODE || '/' || r.CUST_AC_NO,
                 'CCY=' || r.CCY ||
                 ' | ACY=' || TO_CHAR(r.acy) ||
                 ' | LCY=' || TO_CHAR(r.lcy) ||
                 ' | TOD=' || NVL(TO_CHAR(r.tod),'(NULL)'));
    END LOOP;

    -- 12.9 Turnovers — MTD / YTD / Today (DR/CR)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.9 Turnovers agrégés (STTM_CUST_ACCOUNT)]');
    SELECT NVL(SUM(ACY_TODAY_TOVER_DR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_TODAY_TOVER_DR', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_TODAY_TOVER_CR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_TODAY_TOVER_CR', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_MTD_TOVER_DR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_MTD_TOVER_DR', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_MTD_TOVER_CR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_MTD_TOVER_CR', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_TOVER_CR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_TOVER_CR (cumul)', TO_CHAR(v_num));
    SELECT NVL(SUM(LCY_MTD_TOVER_DR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme LCY_MTD_TOVER_DR', TO_CHAR(v_num));
    SELECT NVL(SUM(LCY_MTD_TOVER_CR),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme LCY_MTD_TOVER_CR', TO_CHAR(v_num));

    -- 12.9.b Comptes MTD déséquilibrés (DR vs CR très asymétrique)
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE LCY_MTD_TOVER_DR IS NOT NULL AND LCY_MTD_TOVER_CR IS NOT NULL
      AND GREATEST(LCY_MTD_TOVER_DR, LCY_MTD_TOVER_CR) > 0
      AND LEAST(LCY_MTD_TOVER_DR, LCY_MTD_TOVER_CR) = 0
      AND GREATEST(LCY_MTD_TOVER_DR, LCY_MTD_TOVER_CR) > 1000000;
    print_kv('  Comptes MTD unidirectionnels > 1M LCY', TO_CHAR(v_count));

    -- 12.9.c Top 15 comptes par LCY_MTD_TOVER_DR
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.9.c Top 15 comptes par LCY_MTD_TOVER_DR]');
    FOR r IN (
        SELECT * FROM (
            SELECT BRANCH_CODE, CUST_AC_NO, CCY,
                   LCY_MTD_TOVER_DR dr, LCY_MTD_TOVER_CR cr,
                   TRNOVER_LMT_CODE lmt
            FROM STTM_CUST_ACCOUNT
            WHERE LCY_MTD_TOVER_DR IS NOT NULL
            ORDER BY LCY_MTD_TOVER_DR DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.BRANCH_CODE || '/' || r.CUST_AC_NO,
                 'CCY=' || r.CCY ||
                 ' | DR=' || TO_CHAR(r.dr) ||
                 ' | CR=' || TO_CHAR(r.cr) ||
                 ' | LMT=' || NVL(r.lmt,'(NULL)'));
    END LOOP;

    -- 12.9.d Turnover limits (TRNOVER_LMT_CODE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.9.d Répartition TRNOVER_LMT_CODE (top 15)]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(TRNOVER_LMT_CODE,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUST_ACCOUNT GROUP BY TRNOVER_LMT_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 12.10 Intérêts accrus / dûs (DR_INT_DUE, CHG_DUE, RECEIVABLE_AMOUNT)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.10 Intérêts/charges accrus au niveau compte]');
    SELECT NVL(SUM(ACY_ACCRUED_DR_IC),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_ACCRUED_DR_IC (intérêts débit à facturer)', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_ACCRUED_CR_IC),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme ACY_ACCRUED_CR_IC (intérêts crédit à payer)', TO_CHAR(v_num));
    SELECT NVL(SUM(DR_INT_DUE),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme DR_INT_DUE', TO_CHAR(v_num));
    SELECT NVL(SUM(CHG_DUE),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme CHG_DUE (charges dues)', TO_CHAR(v_num));
    SELECT NVL(SUM(RECEIVABLE_AMOUNT),0) INTO v_num FROM STTM_CUST_ACCOUNT;
    print_kv('  Somme RECEIVABLE_AMOUNT', TO_CHAR(v_num));

    -- 12.10.b Comptes avec charges dues non recouvrées mais dormants
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='Y' AND NVL(CHG_DUE,0) > 0;
    print_kv('  Dormants AVEC CHG_DUE > 0 (leakage)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='Y' AND NVL(DR_INT_DUE,0) > 0;
    print_kv('  Dormants AVEC DR_INT_DUE > 0 (leakage)', TO_CHAR(v_count));

    -- 12.11 DEFAULT_WAIVER sur comptes (ICCF/charges par défaut waive)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.11 DEFAULT_WAIVER sur STTM_CUST_ACCOUNT]');
    FOR r IN (SELECT NVL(DEFAULT_WAIVER,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUST_ACCOUNT GROUP BY DEFAULT_WAIVER
              ORDER BY nb DESC) LOOP
        print_kv('  DEFAULT_WAIVER = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE DEFAULT_WAIVER='Y';
    print_kv('  Comptes default_waiver=Y (RA: vérifier justification)', TO_CHAR(v_count));

    -- 12.12 Derniers mouvements (DATE_LAST_CR / DATE_LAST_DR)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.12 Dernier mouvement (DATE_LAST_CR / DATE_LAST_DR)]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE DATE_LAST_CR IS NULL AND DATE_LAST_DR IS NULL;
    print_kv('  Jamais mouvementés (LAST_CR & LAST_DR NULL)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE GREATEST(NVL(DATE_LAST_CR,DATE '1900-01-01'),
                   NVL(DATE_LAST_DR,DATE '1900-01-01')) < ADD_MONTHS(SYSDATE,-12)
      AND AC_STAT_DORMANT <> 'Y';
    print_kv('  Inactifs >12 mois NON dormants (RA: reclasser)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE GREATEST(NVL(DATE_LAST_CR,DATE '1900-01-01'),
                   NVL(DATE_LAST_DR,DATE '1900-01-01')) < ADD_MONTHS(SYSDATE,-24)
      AND AC_STAT_DORMANT <> 'Y' AND NVL(CHG_DUE,0)=0;
    print_kv('  Inactifs >24 mois NON dormants sans CHG_DUE', TO_CHAR(v_count));

    -- 12.13 Historique solde journalier ACTB_ACCBAL_HISTORY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.13 ACTB_ACCBAL_HISTORY (snapshot soldes EOD)]');
    safe_count('ACTB_ACCBAL_HISTORY', '  Total lignes');
    SELECT MIN(BKG_DATE), MAX(BKG_DATE) INTO v_num, v_count FROM (
        SELECT MIN(BKG_DATE) BKG_DATE FROM ACTB_ACCBAL_HISTORY
        UNION ALL SELECT MAX(BKG_DATE) FROM ACTB_ACCBAL_HISTORY);
    FOR r IN (SELECT MIN(BKG_DATE) mn, MAX(BKG_DATE) mx,
                     COUNT(DISTINCT BKG_DATE) nb_j,
                     COUNT(DISTINCT ACCOUNT) nb_acc
              FROM ACTB_ACCBAL_HISTORY) LOOP
        print_kv('  Plage BKG_DATE', TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
        print_kv('  Nb jours distincts', TO_CHAR(r.nb_j));
        print_kv('  Nb comptes distincts', TO_CHAR(r.nb_acc));
    END LOOP;

    -- 12.13.b Agrégats derniers 12 mois
    FOR r IN (SELECT NVL(SUM(ACY_DR_TUR),0) dr, NVL(SUM(ACY_CR_TUR),0) cr,
                     NVL(SUM(LCY_DR_TUR),0) ldr, NVL(SUM(LCY_CR_TUR),0) lcr
              FROM ACTB_ACCBAL_HISTORY
              WHERE BKG_DATE >= ADD_MONTHS(SYSDATE,-12)) LOOP
        print_kv('  ACY_DR_TUR 12m', TO_CHAR(r.dr));
        print_kv('  ACY_CR_TUR 12m', TO_CHAR(r.cr));
        print_kv('  LCY_DR_TUR 12m', TO_CHAR(r.ldr));
        print_kv('  LCY_CR_TUR 12m', TO_CHAR(r.lcr));
    END LOOP;

    -- 12.13.c Jours avec solde débiteur (overdraft réel)
    SELECT COUNT(*) INTO v_count FROM ACTB_ACCBAL_HISTORY
    WHERE ACY_CLOSING_BAL < 0;
    print_kv('  Jours/comptes en solde débiteur EOD', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT) INTO v_count FROM ACTB_ACCBAL_HISTORY
    WHERE ACY_CLOSING_BAL < 0;
    print_kv('  Comptes distincts avec EOD débiteur', TO_CHAR(v_count));

    -- 12.13.d Ecarts OPENING (J) vs CLOSING (J-1)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.13.d Contrôle continuité OPENING_J vs CLOSING_J-1]');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.BRANCH_CODE, a.ACCOUNT, a.BKG_DATE,
               a.ACY_OPENING_BAL,
               LAG(a.ACY_CLOSING_BAL) OVER (PARTITION BY a.BRANCH_CODE, a.ACCOUNT
                                             ORDER BY a.BKG_DATE) prev_close
        FROM ACTB_ACCBAL_HISTORY a
        WHERE a.BKG_DATE >= ADD_MONTHS(SYSDATE,-3)
    ) WHERE prev_close IS NOT NULL
        AND ABS(ACY_OPENING_BAL - prev_close) > 0.01;
    print_kv('  Jours avec discontinuité open/close (3 derniers mois)', TO_CHAR(v_count));

    -- 12.14 ACTB_VD_BAL — balances valeur-date
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.14 ACTB_VD_BAL — soldes à date de valeur]');
    safe_count('ACTB_VD_BAL', '  Total lignes');
    SELECT COUNT(DISTINCT ACC) INTO v_count FROM ACTB_VD_BAL;
    print_kv('  Comptes distincts', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_VD_BAL WHERE HAS_TOV='Y';
    print_kv('  Lignes HAS_TOV=Y (jour avec mouvement)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_VD_BAL WHERE BAL < 0;
    print_kv('  Lignes BAL < 0 (overdraft VD)', TO_CHAR(v_count));

    FOR r IN (SELECT MIN(VAL_DT) mn, MAX(VAL_DT) mx FROM ACTB_VD_BAL) LOOP
        print_kv('  Plage VAL_DT', TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    -- 12.14.b VAL_DT futures (anomalie)
    SELECT COUNT(*) INTO v_count FROM ACTB_VD_BAL WHERE VAL_DT > SYSDATE + 365;
    print_kv('  VAL_DT > SYSDATE+1an (forward extrême)', TO_CHAR(v_count));

    -- 12.15 Cross-check : comptes débiteurs VD mais STTM non signalé
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.15 Cohérence VD/STTM]');
    SELECT COUNT(DISTINCT v.ACC) INTO v_count FROM ACTB_VD_BAL v
    JOIN STTM_CUST_ACCOUNT s ON s.CUST_AC_NO = v.ACC AND s.BRANCH_CODE = v.BRN
    WHERE v.BAL < 0 AND v.VAL_DT = (SELECT MAX(VAL_DT) FROM ACTB_VD_BAL v2 WHERE v2.ACC=v.ACC AND v2.BRN=v.BRN)
      AND s.OVERDRAFT_SINCE IS NULL;
    print_kv('  VD négatif actuel mais OVERDRAFT_SINCE vide', TO_CHAR(v_count));

    -- 12.16 Classes de comptes dormants-enabled sans dormants réels
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [12.16 ACCOUNT_CLASS : dormance paramétrée vs observée]');
    FOR r IN (
        SELECT * FROM (
            SELECT c.ACCOUNT_CODE cls,
                   SUM(CASE WHEN a.AC_STAT_DORMANT='Y' THEN 1 ELSE 0 END) nb_dorm,
                   COUNT(*) nb_tot
            FROM STTM_ACCOUNT_CLASS c
            JOIN STTM_CUST_ACCOUNT a ON a.ACCOUNT_CLASS = c.ACCOUNT_CODE
            WHERE c.DORMANT_PARAM IS NOT NULL
            GROUP BY c.ACCOUNT_CODE
            ORDER BY nb_tot DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.cls,
                 'dormants=' || TO_CHAR(r.nb_dorm) || ' / total=' || TO_CHAR(r.nb_tot));
    END LOOP;

    ----------------------------------------------------------------
    -- SECTION 13 : SITB — Standing Instructions & frais d'échec
    --   Revenue Assurance : Les SI génèrent du revenu de commission
    --   à chaque succès/échec. Anomalies typiques :
    --    - SI sans frais appliqués (APPLY_CHG_* = N sur tout)
    --    - Retries saturés sans charge d'échec
    --    - Cycles exécutés sans montant
    --    - SI expirée mais encore active / cycles générés après
    ----------------------------------------------------------------
    print_section('SECTION 13 — SITB Standing Instructions & frais d''échec');

    -- 13.1 Volumétrie SITB_CONTRACT_MASTER
    DBMS_OUTPUT.PUT_LINE('  [13.1 Volumétrie SITB_CONTRACT_MASTER]');
    safe_count('SITB_CONTRACT_MASTER', '  Total SI');
    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count FROM SITB_CONTRACT_MASTER;
    print_kv('  Contrats SI distincts', TO_CHAR(v_count));

    -- 13.2 Répartition EVENT_CODE (INIT/BOOK/LIQD/MODY/CANC/REVR ...)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.2 Répartition EVENT_CODE]');
    FOR r IN (SELECT NVL(EVENT_CODE,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY EVENT_CODE
              ORDER BY nb DESC) LOOP
        print_kv('  EVENT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.3 TRANSFER_TYPE (A=Account→Account, etc.)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.3 TRANSFER_TYPE]');
    FOR r IN (SELECT NVL(TRANSFER_TYPE,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY TRANSFER_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.4 CHARGE_WHOM (qui paie les frais : bénéf / ordonnateur / share)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.4 CHARGE_WHOM]');
    FOR r IN (SELECT NVL(CHARGE_WHOM,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY CHARGE_WHOM
              ORDER BY nb DESC) LOOP
        print_kv('  CHARGE_WHOM = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.5 Application des frais — SUCCESS / REJECT / PARTIAL EXEC
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.5 APPLY_CHG_* — leakage RA si tout = N]');
    FOR r IN (
        SELECT 'APPLY_CHG_SUXS=Y' lbl, COUNT(*) nb FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_SUXS='Y' UNION ALL
        SELECT 'APPLY_CHG_SUXS=N',     COUNT(*)    FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_SUXS='N' UNION ALL
        SELECT 'APPLY_CHG_REJT=Y',     COUNT(*)    FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_REJT='Y' UNION ALL
        SELECT 'APPLY_CHG_REJT=N',     COUNT(*)    FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_REJT='N' UNION ALL
        SELECT 'APPLY_CHG_PEXC=Y',     COUNT(*)    FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_PEXC='Y' UNION ALL
        SELECT 'APPLY_CHG_PEXC=N',     COUNT(*)    FROM SITB_CONTRACT_MASTER WHERE APPLY_CHG_PEXC='N'
    ) LOOP
        print_kv('  ' || r.lbl, TO_CHAR(r.nb));
    END LOOP;

    -- 13.5.b SI sans aucune facturation prévue (leakage potentiel)
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE NVL(APPLY_CHG_SUXS,'N')='N'
      AND NVL(APPLY_CHG_REJT,'N')='N'
      AND NVL(APPLY_CHG_PEXC,'N')='N';
    print_kv('  SI avec AUCUN APPLY_CHG_* (leakage potentiel)', TO_CHAR(v_count));

    -- 13.5.c SI avec frais succès mais pas frais échec (asymétrie suspecte)
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE APPLY_CHG_SUXS='Y' AND NVL(APPLY_CHG_REJT,'N')='N';
    print_kv('  SI APPLY_CHG_SUXS=Y mais APPLY_CHG_REJT=N', TO_CHAR(v_count));

    -- 13.6 ACTION_CODE_AMT (politique si solde insuffisant)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.6 ACTION_CODE_AMT]');
    FOR r IN (SELECT NVL(ACTION_CODE_AMT,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY ACTION_CODE_AMT
              ORDER BY nb DESC) LOOP
        print_kv('  ACTION = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.7 SI tanked status & subsystem status
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.7 SI_TANKED_STAT / SUBSYSTEM_STAT]');
    FOR r IN (SELECT NVL(SI_TANKED_STAT,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY SI_TANKED_STAT
              ORDER BY nb DESC) LOOP
        print_kv('  TANKED = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(SUBSYSTEM_STAT,'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY SUBSYSTEM_STAT
              ORDER BY nb DESC) LOOP
        print_kv('  SUBSYS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.8 Montants SI (SI_AMT / CALC_SI_AMT / devise)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.8 Montants SI]');
    SELECT NVL(SUM(SI_AMT),0) INTO v_num FROM SITB_CONTRACT_MASTER;
    print_kv('  Somme SI_AMT (brute, toutes devises)', TO_CHAR(v_num));
    SELECT NVL(SUM(CALC_SI_AMT),0) INTO v_num FROM SITB_CONTRACT_MASTER;
    print_kv('  Somme CALC_SI_AMT', TO_CHAR(v_num));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE SI_AMT IS NULL OR SI_AMT = 0;
    print_kv('  SI avec SI_AMT NULL ou 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE SI_AMT IS NOT NULL AND CALC_SI_AMT IS NOT NULL
      AND ABS(SI_AMT - CALC_SI_AMT) > 0.01;
    print_kv('  Ecart SI_AMT <> CALC_SI_AMT', TO_CHAR(v_count));

    -- 13.8.b Répartition devise SI_AMT_CCY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.8.b Top 15 SI_AMT_CCY]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(SI_AMT_CCY,'(NULL)') s, COUNT(*) nb, NVL(SUM(SI_AMT),0) sm
            FROM SITB_CONTRACT_MASTER GROUP BY SI_AMT_CCY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.s, 'nb=' || TO_CHAR(r.nb) || ' | sum=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.9 Expiration — SI active mais expirée
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.9 SI expirées — SI_EXPIRY_DATE]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER WHERE SI_EXPIRY_DATE IS NULL;
    print_kv('  SI_EXPIRY_DATE IS NULL', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE SI_EXPIRY_DATE IS NOT NULL AND SI_EXPIRY_DATE < TRUNC(SYSDATE);
    print_kv('  SI_EXPIRY_DATE < aujourd''hui', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE SI_EXPIRY_DATE IS NOT NULL AND SI_EXPIRY_DATE < TRUNC(SYSDATE) - 365;
    print_kv('  Expirée depuis >1 an (purge à étudier)', TO_CHAR(v_count));

    -- 13.10 Max retry count & priorité
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.10 MAX_RETRY_COUNT / PRIORITY]');
    FOR r IN (SELECT NVL(TO_CHAR(MAX_RETRY_COUNT),'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY MAX_RETRY_COUNT
              ORDER BY nb DESC) LOOP
        print_kv('  MAX_RETRY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(TO_CHAR(PRIORITY),'(NULL)') s, COUNT(*) nb
              FROM SITB_CONTRACT_MASTER GROUP BY PRIORITY
              ORDER BY nb DESC) LOOP
        print_kv('  PRIORITY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.11 Couples DR/CR — branches identiques vs cross-branch
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.11 Typologie DR/CR accounts]');
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE DR_ACC_BR = CR_ACC_BR;
    print_kv('  DR & CR même branche', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE DR_ACC_BR <> CR_ACC_BR;
    print_kv('  DR & CR branches différentes', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE DR_ACC_CCY <> CR_ACC_CCY;
    print_kv('  SI cross-currency (DR_CCY <> CR_CCY)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER
    WHERE DR_ACCOUNT = CR_ACCOUNT AND DR_ACC_BR = CR_ACC_BR;
    print_kv('  SI DR=CR (auto-transfert absurde)', TO_CHAR(v_count));

    -- 13.12 SITB_CYCLE_DETAIL — exécutions de SI
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12 SITB_CYCLE_DETAIL — volumétrie]');
    safe_count('SITB_CYCLE_DETAIL', '  Total cycles');
    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count FROM SITB_CYCLE_DETAIL;
    print_kv('  SI distinctes exécutées', TO_CHAR(v_count));

    -- 13.12.b EVENT_CODE dans cycles
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12.b EVENT_CODE cycles]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(EVENT_CODE,'(NULL)') s, COUNT(*) nb
            FROM SITB_CYCLE_DETAIL GROUP BY EVENT_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.12.c Agrégats AMT_DEBITED / CREDITED / EXECUTED
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12.c Agrégats exécutions]');
    SELECT NVL(SUM(AMT_DEBITED),0) INTO v_num FROM SITB_CYCLE_DETAIL;
    print_kv('  Somme AMT_DEBITED', TO_CHAR(v_num));
    SELECT NVL(SUM(AMT_CREDITED),0) INTO v_num FROM SITB_CYCLE_DETAIL;
    print_kv('  Somme AMT_CREDITED', TO_CHAR(v_num));
    SELECT NVL(SUM(AMT_EXECUTED_LCY),0) INTO v_num FROM SITB_CYCLE_DETAIL;
    print_kv('  Somme AMT_EXECUTED_LCY', TO_CHAR(v_num));
    SELECT NVL(SUM(SI_AMT_EXECUTED),0) INTO v_num FROM SITB_CYCLE_DETAIL;
    print_kv('  Somme SI_AMT_EXECUTED', TO_CHAR(v_num));

    -- 13.12.d Cohérence DEBITED vs CREDITED (même devise attendue)
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL
    WHERE DR_ACC_CCY = CR_ACC_CCY
      AND AMT_DEBITED IS NOT NULL AND AMT_CREDITED IS NOT NULL
      AND ABS(AMT_DEBITED - AMT_CREDITED) > 0.01;
    print_kv('  Ecart DR/CR même devise (leakage)', TO_CHAR(v_count));

    -- 13.12.e Cycles échoués (ni debited ni credited)
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL
    WHERE NVL(AMT_DEBITED,0) = 0 AND NVL(AMT_CREDITED,0) = 0;
    print_kv('  Cycles AMT_DEBITED=0 & AMT_CREDITED=0', TO_CHAR(v_count));

    -- 13.12.f Retries — distribution
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12.f RETRY_SEQ_NO distribution]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(TO_CHAR(RETRY_SEQ_NO),'(NULL)') s, COUNT(*) nb
            FROM SITB_CYCLE_DETAIL GROUP BY RETRY_SEQ_NO
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  RETRY_SEQ_NO = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 13.12.g Retries excessifs : existence de cycles sans charge d'échec
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.12.g Retries & frais d''échec]');
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL c
    WHERE NVL(c.RETRY_SEQ_NO,0) >= 1
      AND NVL(c.AMT_EXECUTED_LCY,0) = 0
      AND EXISTS (
        SELECT 1 FROM SITB_CONTRACT_MASTER m
        WHERE m.CONTRACT_REF_NO = c.CONTRACT_REF_NO
          AND NVL(m.APPLY_CHG_REJT,'N') = 'N'
      );
    print_kv('  Echecs SI avec APPLY_CHG_REJT=N (leakage sûr)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL c
    WHERE NVL(c.RETRY_SEQ_NO,0) >= 1
      AND NVL(c.AMT_EXECUTED_LCY,0) = 0
      AND EXISTS (
        SELECT 1 FROM SITB_CONTRACT_MASTER m
        WHERE m.CONTRACT_REF_NO = c.CONTRACT_REF_NO
          AND m.APPLY_CHG_REJT = 'Y'
      );
    print_kv('  Echecs SI avec APPLY_CHG_REJT=Y (à vérifier: frais présents ?)', TO_CHAR(v_count));

    -- 13.12.h Retries > MAX_RETRY_COUNT (dépassement)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT c.CONTRACT_REF_NO, MAX(c.RETRY_SEQ_NO) mx
        FROM SITB_CYCLE_DETAIL c
        GROUP BY c.CONTRACT_REF_NO
    ) x
    JOIN SITB_CONTRACT_MASTER m ON m.CONTRACT_REF_NO = x.CONTRACT_REF_NO
    WHERE m.MAX_RETRY_COUNT IS NOT NULL
      AND x.mx > m.MAX_RETRY_COUNT;
    print_kv('  SI avec retries au-delà de MAX_RETRY_COUNT', TO_CHAR(v_count));

    -- 13.13 Cycles sur SI expirée
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.13 Cohérence cycles vs expiration SI]');
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL c
    JOIN SITB_CONTRACT_MASTER m ON m.CONTRACT_REF_NO = c.CONTRACT_REF_NO
    WHERE m.SI_EXPIRY_DATE IS NOT NULL
      AND c.RETRY_DATE IS NOT NULL
      AND c.RETRY_DATE > m.SI_EXPIRY_DATE;
    print_kv('  Cycles RETRY_DATE APRES SI_EXPIRY_DATE', TO_CHAR(v_count));

    -- 13.14 Top 10 SI par AMT_EXECUTED_LCY cumulé
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.14 Top 10 SI par cumul AMT_EXECUTED_LCY]');
    FOR r IN (
        SELECT * FROM (
            SELECT CONTRACT_REF_NO, COUNT(*) nb_cyc,
                   NVL(SUM(AMT_EXECUTED_LCY),0) sm
            FROM SITB_CYCLE_DETAIL
            GROUP BY CONTRACT_REF_NO
            ORDER BY sm DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.CONTRACT_REF_NO,
                 'cycles=' || TO_CHAR(r.nb_cyc) || ' | sum_LCY=' || TO_CHAR(r.sm));
    END LOOP;

    -- 13.15 Cycles orphelins (CONTRACT_REF_NO absent du master)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [13.15 Intégrité référentielle]');
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL c
    WHERE NOT EXISTS (SELECT 1 FROM SITB_CONTRACT_MASTER m
                      WHERE m.CONTRACT_REF_NO = c.CONTRACT_REF_NO);
    print_kv('  Cycles sans SI master (orphelins)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SITB_CONTRACT_MASTER m
    WHERE NOT EXISTS (SELECT 1 FROM SITB_CYCLE_DETAIL c
                      WHERE c.CONTRACT_REF_NO = m.CONTRACT_REF_NO);
    print_kv('  SI master SANS aucun cycle', TO_CHAR(v_count));

    ----------------------------------------------------------------
    -- SECTION 14 : Cohérences globales & anomalies Revenue Assurance
    --   Synthèse transverse : on croise les tables déjà parcourues
    --   (ACTB_HISTORY, GLTB_GL_BAL, CLTB_*, LDTB_*, STTM_CUST_ACCOUNT,
    --    RVTB_ACC_REVAL, SITB_*) pour détecter :
    --    - intérêts courus non portés en GL
    --    - échéances dues mais non facturées
    --    - liquidations partielles orphelines
    --    - waivers massifs / exceptions RA
    --    - comptes débiteurs hors OD sans frais
    --    - FX revaluation orpheline
    --    - écarts accrual vs paiement
    ----------------------------------------------------------------
    print_section('SECTION 14 — Cohérences globales & anomalies RA');

    -- 14.1 ACTB_HISTORY vs GLTB_GL_BAL : mouvements GL cohérents ?
    DBMS_OUTPUT.PUT_LINE('  [14.1 Rapprochement ACTB_HISTORY <-> GLTB_GL_BAL]');
    -- Somme LCY par GL pour un échantillon mois récent et compare avec DR_MOV/CR_MOV
    FOR r IN (
        SELECT * FROM (
            SELECT h.AC_NO gl,
                   NVL(SUM(CASE WHEN h.DRCR_IND='D' THEN h.LCY_AMOUNT END),0) dr_hist,
                   NVL(SUM(CASE WHEN h.DRCR_IND='C' THEN h.LCY_AMOUNT END),0) cr_hist,
                   COUNT(*) nb
            FROM ACTB_HISTORY h
            WHERE h.TRN_DT >= TRUNC(SYSDATE,'MM')
              AND h.AC_NO IS NOT NULL
            GROUP BY h.AC_NO
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 5
    ) LOOP
        print_kv('  GL ' || r.gl,
                 'hist_DR=' || TO_CHAR(r.dr_hist) ||
                 ' | hist_CR=' || TO_CHAR(r.cr_hist) ||
                 ' | mvts=' || TO_CHAR(r.nb));
    END LOOP;

    -- 14.2 Intérêts accrus comptes sans entrée GL correspondante
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.2 Accruals intérêts — matière à facturer]');
    SELECT NVL(SUM(ACY_ACCRUED_DR_IC),0) INTO v_num FROM STTM_CUST_ACCOUNT
    WHERE NVL(ACY_ACCRUED_DR_IC,0) <> 0;
    print_kv('  Σ ACY_ACCRUED_DR_IC (intérêts clients à percevoir)', TO_CHAR(v_num));
    SELECT NVL(SUM(ACY_ACCRUED_CR_IC),0) INTO v_num FROM STTM_CUST_ACCOUNT
    WHERE NVL(ACY_ACCRUED_CR_IC,0) <> 0;
    print_kv('  Σ ACY_ACCRUED_CR_IC (intérêts clients à payer)', TO_CHAR(v_num));
    print_kv('  Net à percevoir (DR - CR)', TO_CHAR(
        (SELECT NVL(SUM(ACY_ACCRUED_DR_IC),0) - NVL(SUM(ACY_ACCRUED_CR_IC),0)
         FROM STTM_CUST_ACCOUNT)));

    -- 14.3 Débiteurs permanents sans TOD_LIMIT — RA leakage potentiel
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.3 Overdraft tacite — comptes en rouge sans TOD]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE ACY_CURR_BALANCE < 0
      AND NVL(TOD_LIMIT,0) = 0
      AND AC_STAT_DORMANT <> 'Y';
    print_kv('  Actifs débiteurs sans TOD_LIMIT', TO_CHAR(v_count));

    SELECT NVL(SUM(ABS(LCY_CURR_BALANCE)),0) INTO v_num FROM STTM_CUST_ACCOUNT
    WHERE LCY_CURR_BALANCE < 0
      AND NVL(TOD_LIMIT,0) = 0;
    print_kv('  Σ débit LCY sur ces comptes', TO_CHAR(v_num));

    -- 14.4 Comptes dormants avec accruals : recette gelée
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.4 Dormants avec matière imposable]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT
    WHERE AC_STAT_DORMANT='Y'
      AND (NVL(ACY_ACCRUED_DR_IC,0) > 0 OR NVL(CHG_DUE,0) > 0 OR NVL(DR_INT_DUE,0) > 0);
    print_kv('  Dormants avec accrued/charges > 0', TO_CHAR(v_count));
    SELECT NVL(SUM(ACY_ACCRUED_DR_IC + NVL(CHG_DUE,0) + NVL(DR_INT_DUE,0)),0) INTO v_num
    FROM STTM_CUST_ACCOUNT WHERE AC_STAT_DORMANT='Y';
    print_kv('  Σ matière gelée (dormants)', TO_CHAR(v_num));

    -- 14.5 Waivers sur comptes clients vs composants de prêt
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.5 Waivers — synthèse RA]');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_ACCOUNT WHERE DEFAULT_WAIVER='Y';
    print_kv('  Comptes DEFAULT_WAIVER=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS WHERE WAIVER='Y';
    print_kv('  Composants prêt WAIVER=Y', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count FROM CLTB_ACCOUNT_COMPONENTS WHERE WAIVER='Y';
    print_kv('  Prêts distincts avec au moins un WAIVER', TO_CHAR(v_count));

    -- 14.6 Echéances prêts dues non payées — unbilled loss
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.6 Echéances prêts en souffrance]');
    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
      AND NVL(AMOUNT_DUE,0) > NVL(AMOUNT_SETTLED,0);
    print_kv('  Ech. CL en retard (AMT_DUE > AMT_SETTLED)', TO_CHAR(v_count));
    SELECT NVL(SUM(NVL(AMOUNT_DUE,0) - NVL(AMOUNT_SETTLED,0)),0) INTO v_num
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
      AND NVL(AMOUNT_DUE,0) > NVL(AMOUNT_SETTLED,0);
    print_kv('  Σ arriérés CL (AMT_DUE - AMT_SETTLED)', TO_CHAR(v_num));

    -- 14.7 Liquidations sans paiement associé (CLTB_AMOUNT_LIQ orphelines)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.7 Cohérence liquidations / paiements CL]');
    BEGIN
      SELECT COUNT(*) INTO v_count FROM CLTB_AMOUNT_LIQ l
      WHERE NOT EXISTS (
        SELECT 1 FROM CLTB_AMOUNT_PAID p
        WHERE p.ACCOUNT_NUMBER = l.ACCOUNT_NUMBER
          AND p.EVENT_SEQ_NO  = l.EVENT_SEQ_NO
      );
      print_kv('  Liquidations sans paiement associé', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Liquidations sans paiement associé', 'N/A (' || SQLERRM || ')');
    END;

    -- 14.8 Prêts actifs sans composants : paramétrage incomplet
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.8 Prêts actifs sans composants ICCF]');
    BEGIN
      SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER a
      WHERE NVL(a.MODULE_CODE,'CL') = 'CL'
        AND a.USER_DEFINED_STATUS <> 'LIQD'
        AND NOT EXISTS (
          SELECT 1 FROM CLTB_ACCOUNT_COMPONENTS c
          WHERE c.ACCOUNT_NUMBER = a.ACCOUNT_NUMBER
        );
      print_kv('  Prêts ouverts sans aucun composant', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Prêts ouverts sans composant', 'N/A (' || SQLERRM || ')');
    END;

    -- 14.9 RVTB_ACC_REVAL — comptes réévalués mais inexistants dans STTB_ACCOUNT
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.9 Revaluation sur comptes fantômes]');
    BEGIN
      SELECT COUNT(DISTINCT r.ACCOUNT) INTO v_count FROM RVTB_ACC_REVAL r
      WHERE NOT EXISTS (
        SELECT 1 FROM STTB_ACCOUNT s WHERE s.AC_GL_NO = r.ACCOUNT
        UNION ALL
        SELECT 1 FROM STTM_CUST_ACCOUNT c WHERE c.CUST_AC_NO = r.ACCOUNT
      );
      print_kv('  Comptes RVTB inconnus en STTB/STTM', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Comptes RVTB inconnus', 'N/A (' || SQLERRM || ')');
    END;

    -- 14.10 FX revaluation : P&L cumulé par statut GLMIS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.10 P&L FX par statut GLMIS_UPD_STATUS]');
    FOR r IN (
        SELECT NVL(GLMIS_UPD_STATUS,'(NULL)') s,
               NVL(SUM(NEW_LCY_EQUIVALENT - OLD_LCY_EQUIVALENT),0) pl,
               COUNT(*) nb
        FROM RVTB_ACC_REVAL
        GROUP BY GLMIS_UPD_STATUS
        ORDER BY nb DESC
    ) LOOP
        print_kv('  GLMIS ' || r.s,
                 'P&L=' || TO_CHAR(r.pl) || ' | nb=' || TO_CHAR(r.nb));
    END LOOP;

    -- 14.11 ACTB_HISTORY : flags AML_EXCEPTION / DONT_SHOWIN_STMT
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.11 ACTB_HISTORY flags sensibles]');
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE AML_EXCEPTION='Y';
    print_kv('  AML_EXCEPTION=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE DONT_SHOWIN_STMT='Y';
    print_kv('  DONT_SHOWIN_STMT=Y (caché dans relevé)', TO_CHAR(v_count));
    SELECT NVL(SUM(LCY_AMOUNT),0) INTO v_num FROM ACTB_HISTORY WHERE DONT_SHOWIN_STMT='Y';
    print_kv('  Σ LCY sur DONT_SHOWIN_STMT=Y', TO_CHAR(v_num));

    -- 14.12 ACTB_HISTORY : EXCH_RATE anormaux
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.12 ACTB_HISTORY — taux de change anormaux]');
    -- On détecte sans dépendre de CYTM_CCY_DEFN : écart FCY/LCY significatif
    -- avec EXCH_RATE = 0 ou 1 alors que les montants diffèrent (ccy <> LCY).
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY
    WHERE FCY_AMOUNT IS NOT NULL AND FCY_AMOUNT <> 0
      AND LCY_AMOUNT IS NOT NULL AND LCY_AMOUNT <> 0
      AND NVL(EXCH_RATE,0) IN (0,1)
      AND ABS(LCY_AMOUNT - FCY_AMOUNT) / GREATEST(ABS(FCY_AMOUNT),1) > 0.01;
    print_kv('  Mouvements EXCH_RATE ∈ {0,1} mais LCY<>FCY (suspect)', TO_CHAR(v_count));

    -- 14.13 Contrats prêts inactifs depuis > 12 mois sans liquidation
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.13 Prêts CL figés (pas de cycle récent)]');
    BEGIN
      SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER a
      WHERE a.USER_DEFINED_STATUS NOT IN ('LIQD','CANC','CLOS')
        AND NOT EXISTS (
          SELECT 1 FROM CLTB_AMOUNT_LIQ l
          WHERE l.ACCOUNT_NUMBER = a.ACCOUNT_NUMBER
            AND l.LIQ_DATE >= ADD_MONTHS(SYSDATE,-12)
        );
      print_kv('  Prêts actifs sans liquidation 12m', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Prêts actifs sans liquidation 12m', 'N/A (' || SQLERRM || ')');
    END;

    -- 14.14 SI inactives mais encore exécutées (cycle post-expiry)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.14 SI exécutées post-expiration]');
    SELECT COUNT(*) INTO v_count FROM SITB_CYCLE_DETAIL c
    JOIN SITB_CONTRACT_MASTER m ON m.CONTRACT_REF_NO = c.CONTRACT_REF_NO
    WHERE m.SI_EXPIRY_DATE IS NOT NULL
      AND c.RETRY_DATE IS NOT NULL
      AND c.RETRY_DATE > m.SI_EXPIRY_DATE
      AND c.AMT_EXECUTED_LCY > 0;
    print_kv('  Exécutions SI après SI_EXPIRY_DATE (> 0)', TO_CHAR(v_count));

    -- 14.15 GL income mouvementés sur l'exercice (top 10 CR)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.15 Top 10 GL ''INCOME'' par CR_MOV_LCY (FIN_YEAR courant)]');
    FOR r IN (
        SELECT * FROM (
            SELECT g.GL_CODE, g.CCY_CODE, g.BRANCH_CODE,
                   NVL(g.CR_MOV_LCY,0) cr_mov_lcy,
                   NVL(g.DR_MOV_LCY,0) dr_mov_lcy
            FROM GLTB_GL_BAL g
            WHERE UPPER(NVL(g.CATEGORY,'')) IN ('I','INCOME','REVENUE','P')
              AND g.FIN_YEAR = TO_CHAR(SYSDATE,'YYYY')
            ORDER BY NVL(g.CR_MOV_LCY,0) DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.GL_CODE || '/' || r.BRANCH_CODE || '/' || r.CCY_CODE,
                 'CR_mov_LCY=' || TO_CHAR(r.cr_mov_lcy) ||
                 ' | DR_mov_LCY=' || TO_CHAR(r.dr_mov_lcy));
    END LOOP;

    -- 14.16 Scoring final RA : synthèse des leakages détectés
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [14.16 Synthèse finale — indicateurs RA consolidés]');
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD('-',76,'-'));

    DECLARE
      v_leak_waiver_cl    NUMBER := 0;
      v_leak_waiver_acc   NUMBER := 0;
      v_leak_dormant_chg  NUMBER := 0;
      v_leak_overdraft    NUMBER := 0;
      v_leak_si_nocharge  NUMBER := 0;
      v_leak_si_expired   NUMBER := 0;
      v_leak_sched_overdue NUMBER := 0;
      v_amt_sched_overdue  NUMBER := 0;
      v_amt_accrued        NUMBER := 0;
    BEGIN
      BEGIN SELECT COUNT(*) INTO v_leak_waiver_cl FROM CLTB_ACCOUNT_COMPONENTS WHERE WAIVER='Y';
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*) INTO v_leak_waiver_acc FROM STTM_CUST_ACCOUNT WHERE DEFAULT_WAIVER='Y';
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*) INTO v_leak_dormant_chg FROM STTM_CUST_ACCOUNT
            WHERE AC_STAT_DORMANT='Y' AND NVL(CHG_DUE,0) > 0;
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*) INTO v_leak_overdraft FROM STTM_CUST_ACCOUNT
            WHERE ACY_CURR_BALANCE < 0 AND NVL(TOD_LIMIT,0) = 0;
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*) INTO v_leak_si_nocharge FROM SITB_CONTRACT_MASTER
            WHERE NVL(APPLY_CHG_SUXS,'N')='N'
              AND NVL(APPLY_CHG_REJT,'N')='N'
              AND NVL(APPLY_CHG_PEXC,'N')='N';
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*) INTO v_leak_si_expired FROM SITB_CONTRACT_MASTER
            WHERE SI_EXPIRY_DATE IS NOT NULL AND SI_EXPIRY_DATE < TRUNC(SYSDATE);
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT COUNT(*), NVL(SUM(NVL(AMOUNT_DUE,0) - NVL(AMOUNT_SETTLED,0)),0)
            INTO v_leak_sched_overdue, v_amt_sched_overdue
            FROM CLTB_ACCOUNT_SCHEDULES
            WHERE SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
              AND NVL(AMOUNT_DUE,0) > NVL(AMOUNT_SETTLED,0);
      EXCEPTION WHEN OTHERS THEN NULL; END;

      BEGIN SELECT NVL(SUM(ACY_ACCRUED_DR_IC),0) - NVL(SUM(ACY_ACCRUED_CR_IC),0)
            INTO v_amt_accrued FROM STTM_CUST_ACCOUNT;
      EXCEPTION WHEN OTHERS THEN NULL; END;

      print_kv('  [W1] Composants prêt avec WAIVER',           TO_CHAR(v_leak_waiver_cl));
      print_kv('  [W2] Comptes DEFAULT_WAIVER=Y',              TO_CHAR(v_leak_waiver_acc));
      print_kv('  [D1] Dormants avec CHG_DUE > 0',             TO_CHAR(v_leak_dormant_chg));
      print_kv('  [O1] Débiteurs sans TOD_LIMIT',              TO_CHAR(v_leak_overdraft));
      print_kv('  [S1] SI sans APPLY_CHG_*',                   TO_CHAR(v_leak_si_nocharge));
      print_kv('  [S2] SI expirées',                           TO_CHAR(v_leak_si_expired));
      print_kv('  [E1] Echéances CL en retard (#)',            TO_CHAR(v_leak_sched_overdue));
      print_kv('  [E2] Σ arriérés CL (LCY ccy native)',        TO_CHAR(v_amt_sched_overdue));
      print_kv('  [A1] Net accrued intérêts clients (DR-CR)',  TO_CHAR(v_amt_accrued));
    END;

    DBMS_OUTPUT.PUT_LINE('  ' || RPAD('-',76,'-'));
    DBMS_OUTPUT.PUT_LINE('  Synthèse RA enregistrée. Prioriser les indicateurs :');
    DBMS_OUTPUT.PUT_LINE('   - [W*] waivers à justifier (revue contractuelle)');
    DBMS_OUTPUT.PUT_LINE('   - [D*] dormance : CHG_DUE à extraire avant radiation');
    DBMS_OUTPUT.PUT_LINE('   - [O*] overdraft tacite : application de taux OD/pénalités');
    DBMS_OUTPUT.PUT_LINE('   - [S*] SI : paramétrage frais succès/échec & expirations');
    DBMS_OUTPUT.PUT_LINE('   - [E*] échéances : recouvrement & pénalités de retard');
    DBMS_OUTPUT.PUT_LINE('   - [A*] accruals : rapprocher avec le GL revenus');

    ----------------------------------------------------------------
    -- SECTION 15 : LDTB ICCF détaillé — calculs, rollovers & accruals
    --   Approfondissement de la section 8 : on descend dans les
    --   tables de calcul ICCF (Interest/Charge/Commission/Fee) pour
    --   détecter :
    --    - RATE à 0 / CALC_METHOD invalide
    --    - périodes ICCF qui chevauchent
    --    - upfront profit booké sans liquidation aval
    --    - rollovers avec APPLY_CHARGE=N / APPLY_TAX=N (leakage)
    --    - accrual ref absente de l'historique (drift)
    ----------------------------------------------------------------
    print_section('SECTION 15 — LDTB ICCF détaillé : calculs, rollovers, accruals');

    -- 15.1 LDTB_CONTRACT_ICCF_CALC — volumétrie & structure
    DBMS_OUTPUT.PUT_LINE('  [15.1 Volumétrie ICCF_CALC]');
    safe_count('LDTB_CONTRACT_ICCF_CALC', '  Total lignes calcul ICCF');
    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC;
    print_kv('  Contrats avec calcul ICCF', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COMPONENT) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC;
    print_kv('  Composants ICCF distincts', TO_CHAR(v_count));

    -- 15.1.b Top 15 composants (volume de lignes)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.1.b Top 15 composants ICCF]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(COMPONENT,'(NULL)') s, COUNT(*) nb,
                   NVL(SUM(CALCULATED_AMOUNT),0) sm
            FROM LDTB_CONTRACT_ICCF_CALC GROUP BY COMPONENT
            ORDER BY sm DESC NULLS LAST
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.s, 'nb=' || TO_CHAR(r.nb) || ' | Σ calc=' || TO_CHAR(r.sm));
    END LOOP;

    -- 15.1.c ICCF_CALC_METHOD — anomalies paramétrage
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.1.c Méthodes de calcul ICCF_CALC_METHOD]');
    FOR r IN (SELECT NVL(ICCF_CALC_METHOD,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ICCF_CALC GROUP BY ICCF_CALC_METHOD
              ORDER BY nb DESC) LOOP
        print_kv('  METHOD = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 15.2 RATE anormaux & CALCULATED_AMOUNT = 0
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.2 RATE & CALCULATED_AMOUNT — anomalies]');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE NVL(RATE,0) = 0 AND NVL(CALCULATED_AMOUNT,0) <> 0;
    print_kv('  RATE=0 mais CALCULATED_AMOUNT <> 0 (incohérent)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE BASIS_AMOUNT IS NOT NULL AND BASIS_AMOUNT > 0
      AND NVL(CALCULATED_AMOUNT,0) = 0;
    print_kv('  BASIS_AMOUNT > 0 mais CALC = 0 (leakage ICCF)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE NO_OF_DAYS IS NOT NULL AND NO_OF_DAYS < 0;
    print_kv('  NO_OF_DAYS < 0 (anomalie période)', TO_CHAR(v_count));

    -- 15.2.b Ordre chronologique START/END
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE START_DATE IS NOT NULL AND END_DATE IS NOT NULL
      AND START_DATE > END_DATE;
    print_kv('  START_DATE > END_DATE', TO_CHAR(v_count));

    -- 15.2.c Taux extrêmes
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE RATE IS NOT NULL AND RATE > 100;
    print_kv('  RATE > 100 % (extrême - à vérifier)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_CALC
    WHERE RATE IS NOT NULL AND RATE < 0;
    print_kv('  RATE négatif', TO_CHAR(v_count));

    -- 15.3 LDTB_CONTRACT_ICCF_DETAILS — détails par composant
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.3 LDTB_CONTRACT_ICCF_DETAILS]');
    safe_count('LDTB_CONTRACT_ICCF_DETAILS', '  Total lignes details ICCF');
    FOR r IN (SELECT NVL(ACCRUAL_REQUIRED,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ICCF_DETAILS GROUP BY ACCRUAL_REQUIRED
              ORDER BY nb DESC) LOOP
        print_kv('  ACCRUAL_REQUIRED = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(PAYMENT_METHOD,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ICCF_DETAILS GROUP BY PAYMENT_METHOD
              ORDER BY nb DESC) LOOP
        print_kv('  PAYMENT_METHOD = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 15.3.b Upfront profit booké sans liquidation
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_DETAILS
    WHERE NVL(UPFRONT_PROFIT_BOOKED,0) <> 0
      AND NVL(TOTAL_AMOUNT_LIQUIDATED,0) = 0;
    print_kv('  UPFRONT_PROFIT_BOOKED <> 0 & TOT_LIQUIDATED=0', TO_CHAR(v_count));

    -- 15.3.c Accrued courant vs liquidé (drift)
    SELECT NVL(SUM(CURRENT_NET_ACCRUAL),0) INTO v_num FROM LDTB_CONTRACT_ICCF_DETAILS;
    print_kv('  Σ CURRENT_NET_ACCRUAL', TO_CHAR(v_num));
    SELECT NVL(SUM(TILL_DATE_ACCRUAL),0) INTO v_num FROM LDTB_CONTRACT_ICCF_DETAILS;
    print_kv('  Σ TILL_DATE_ACCRUAL', TO_CHAR(v_num));
    SELECT NVL(SUM(TOTAL_AMOUNT_LIQUIDATED),0) INTO v_num FROM LDTB_CONTRACT_ICCF_DETAILS;
    print_kv('  Σ TOTAL_AMOUNT_LIQUIDATED', TO_CHAR(v_num));

    -- 15.3.d Liquidations anciennes (dernier > 365j)
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ICCF_DETAILS
    WHERE LAST_LIQUIDATION_DATE IS NOT NULL
      AND LAST_LIQUIDATION_DATE < SYSDATE - 365
      AND NVL(CURRENT_NET_ACCRUAL,0) > 0;
    print_kv('  Accrued > 0 mais dern. liq > 365j (leakage)', TO_CHAR(v_count));

    -- 15.4 LDTB_CONTRACT_LIQ — Liquidations LD par composant
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.4 LDTB_CONTRACT_LIQ — événements de liquidation]');
    safe_count('LDTB_CONTRACT_LIQ', '  Total liquidations LD');
    SELECT NVL(SUM(AMOUNT_DUE),0) INTO v_num FROM LDTB_CONTRACT_LIQ;
    print_kv('  Σ AMOUNT_DUE', TO_CHAR(v_num));
    SELECT NVL(SUM(AMOUNT_PAID),0) INTO v_num FROM LDTB_CONTRACT_LIQ;
    print_kv('  Σ AMOUNT_PAID', TO_CHAR(v_num));
    SELECT NVL(SUM(TAX_PAID),0) INTO v_num FROM LDTB_CONTRACT_LIQ;
    print_kv('  Σ TAX_PAID', TO_CHAR(v_num));

    -- 15.4.b Liquidations partielles (AMOUNT_PAID < AMOUNT_DUE)
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ
    WHERE AMOUNT_DUE IS NOT NULL AND AMOUNT_PAID IS NOT NULL
      AND AMOUNT_PAID < AMOUNT_DUE;
    print_kv('  Liquidations partielles (PAID < DUE)', TO_CHAR(v_count));

    SELECT NVL(SUM(AMOUNT_DUE - NVL(AMOUNT_PAID,0)),0) INTO v_num FROM LDTB_CONTRACT_LIQ
    WHERE AMOUNT_DUE IS NOT NULL AND AMOUNT_DUE > NVL(AMOUNT_PAID,0);
    print_kv('  Σ impayé (DUE - PAID)', TO_CHAR(v_num));

    -- 15.4.c OVERDUE_DAYS distribution
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.4.c Tranches OVERDUE_DAYS]');
    FOR r IN (
        SELECT CASE
                 WHEN OVERDUE_DAYS IS NULL THEN '(NULL)'
                 WHEN OVERDUE_DAYS <= 0   THEN 'à jour'
                 WHEN OVERDUE_DAYS <= 30  THEN '1-30j'
                 WHEN OVERDUE_DAYS <= 90  THEN '31-90j'
                 WHEN OVERDUE_DAYS <= 180 THEN '91-180j'
                 WHEN OVERDUE_DAYS <= 365 THEN '181-365j'
                 ELSE '365+ j'
               END tr, COUNT(*) nb,
               NVL(SUM(AMOUNT_DUE - NVL(AMOUNT_PAID,0)),0) sm
        FROM LDTB_CONTRACT_LIQ
        GROUP BY CASE
                 WHEN OVERDUE_DAYS IS NULL THEN '(NULL)'
                 WHEN OVERDUE_DAYS <= 0   THEN 'à jour'
                 WHEN OVERDUE_DAYS <= 30  THEN '1-30j'
                 WHEN OVERDUE_DAYS <= 90  THEN '31-90j'
                 WHEN OVERDUE_DAYS <= 180 THEN '91-180j'
                 WHEN OVERDUE_DAYS <= 365 THEN '181-365j'
                 ELSE '365+ j'
               END
        ORDER BY nb DESC
    ) LOOP
        print_kv('  ' || r.tr, 'nb=' || TO_CHAR(r.nb) || ' | impayé=' || TO_CHAR(r.sm));
    END LOOP;

    -- 15.5 LDTB_CONTRACT_LIQ_SUMMARY — pénalités de remboursement anticipé
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.5 LIQ_SUMMARY — pénalités prépayement]');
    safe_count('LDTB_CONTRACT_LIQ_SUMMARY', '  Total summary');
    SELECT NVL(SUM(PREPAYMENT_PENALTY_AMOUNT),0) INTO v_num FROM LDTB_CONTRACT_LIQ_SUMMARY;
    print_kv('  Σ PREPAYMENT_PENALTY_AMOUNT', TO_CHAR(v_num));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_LIQ_SUMMARY
    WHERE NVL(TOTAL_PREPAID,0) > 0 AND NVL(PREPAYMENT_PENALTY_AMOUNT,0) = 0;
    print_kv('  Prépayés SANS pénalité (leakage potentiel)', TO_CHAR(v_count));
    SELECT NVL(SUM(TOTAL_PAID),0) INTO v_num FROM LDTB_CONTRACT_LIQ_SUMMARY;
    print_kv('  Σ TOTAL_PAID', TO_CHAR(v_num));
    SELECT NVL(SUM(TOTAL_PREPAID),0) INTO v_num FROM LDTB_CONTRACT_LIQ_SUMMARY;
    print_kv('  Σ TOTAL_PREPAID', TO_CHAR(v_num));

    -- 15.5.b PAYMENT_STATUS
    FOR r IN (SELECT NVL(PAYMENT_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_LIQ_SUMMARY GROUP BY PAYMENT_STATUS
              ORDER BY nb DESC) LOOP
        print_kv('  STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 15.5.c REJ_REASON (paiements rejetés)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.5.c Top REJ_REASON]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(REJ_REASON,'(NULL)') s, COUNT(*) nb
            FROM LDTB_CONTRACT_LIQ_SUMMARY
            WHERE REJ_REASON IS NOT NULL
            GROUP BY REJ_REASON
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 15.6 LDTB_CONTRACT_ROLLOVER — rollovers & waivers charges/taxes
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.6 ROLLOVERS — APPLY_CHARGE / APPLY_TAX]');
    safe_count('LDTB_CONTRACT_ROLLOVER', '  Total rollovers');
    FOR r IN (SELECT NVL(APPLY_CHARGE,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ROLLOVER GROUP BY APPLY_CHARGE
              ORDER BY nb DESC) LOOP
        print_kv('  APPLY_CHARGE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(APPLY_TAX,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ROLLOVER GROUP BY APPLY_TAX
              ORDER BY nb DESC) LOOP
        print_kv('  APPLY_TAX = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLLOVER
    WHERE NVL(APPLY_CHARGE,'N')='N' AND NVL(APPLY_TAX,'N')='N';
    print_kv('  Rollovers SANS charge & SANS tax (leakage)', TO_CHAR(v_count));

    -- 15.6.b ROLLOVER_TYPE / ROLL_INST_STATUS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.6.b ROLLOVER_TYPE]');
    FOR r IN (SELECT NVL(ROLLOVER_TYPE,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ROLLOVER GROUP BY ROLLOVER_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(ROLL_INST_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ROLLOVER GROUP BY ROLL_INST_STATUS
              ORDER BY nb DESC) LOOP
        print_kv('  ROLL_INST_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 15.7 LDTB_CONTRACT_ROLL_INT_RATES — taux de rollover
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.7 Taux de rollover — RATE / SPREAD / MARGIN]');
    safe_count('LDTB_CONTRACT_ROLL_INT_RATES', '  Total lignes');
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_ROLL_INT_RATES
    WHERE NVL(RATE,0) = 0 AND NVL(SPREAD,0) = 0 AND NVL(MARGIN,0) = 0;
    print_kv('  RATE, SPREAD & MARGIN tous nuls', TO_CHAR(v_count));
    SELECT NVL(AVG(RATE),0), NVL(AVG(SPREAD),0), NVL(AVG(MARGIN),0)
    INTO v_num, v_count, v_count
    FROM LDTB_CONTRACT_ROLL_INT_RATES WHERE RATE IS NOT NULL;
    print_kv('  Moyenne RATE (non NULL)', TO_CHAR(v_num));

    -- 15.8 LDTB_CONTRACT_ACCRUAL_HISTORY — historique accruals
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.8 Historique accruals LDTB]');
    safe_count('LDTB_CONTRACT_ACCRUAL_HISTORY', '  Total entrées');
    FOR r IN (SELECT MIN(TRANSACTION_DATE) mn, MAX(TRANSACTION_DATE) mx
              FROM LDTB_CONTRACT_ACCRUAL_HISTORY) LOOP
        print_kv('  Plage TRANSACTION_DATE',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    -- 15.8.b Accruals passés sans écriture compta (ACC_ENTRY_PASSED=N)
    FOR r IN (SELECT NVL(ACC_ENTRY_PASSED,'(NULL)') s, COUNT(*) nb
              FROM LDTB_CONTRACT_ACCRUAL_HISTORY GROUP BY ACC_ENTRY_PASSED
              ORDER BY nb DESC) LOOP
        print_kv('  ACC_ENTRY_PASSED = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    SELECT NVL(SUM(NET_ACCRUAL),0) INTO v_num FROM LDTB_CONTRACT_ACCRUAL_HISTORY
    WHERE NVL(ACC_ENTRY_PASSED,'N')='N';
    print_kv('  Σ NET_ACCRUAL non encore comptabilisé', TO_CHAR(v_num));

    -- 15.8.c TYPE_OF_ACCRUAL
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.8.c TYPE_OF_ACCRUAL]');
    FOR r IN (SELECT NVL(TYPE_OF_ACCRUAL,'(NULL)') s, COUNT(*) nb,
                     NVL(SUM(NET_ACCRUAL),0) sm
              FROM LDTB_CONTRACT_ACCRUAL_HISTORY GROUP BY TYPE_OF_ACCRUAL
              ORDER BY nb DESC) LOOP
        print_kv('  ' || r.s, 'nb=' || TO_CHAR(r.nb) || ' | Σ=' || TO_CHAR(r.sm));
    END LOOP;

    -- 15.8.d Overdue interest encore à encaisser
    SELECT NVL(SUM(OVERDUE_INTEREST),0) INTO v_num FROM LDTB_CONTRACT_ACCRUAL_HISTORY
    WHERE NVL(OVERDUE_INTEREST,0) > 0;
    print_kv('  Σ OVERDUE_INTEREST (> 0)', TO_CHAR(v_num));

    -- 15.8.e Top 10 contrats par OUTSTANDING_ACCRUAL
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.8.e Top 10 contrats OUTSTANDING_ACCRUAL]');
    FOR r IN (
        SELECT * FROM (
            SELECT CONTRACT_REF_NO, NVL(SUM(OUTSTANDING_ACCRUAL),0) sm,
                   NVL(MAX(USER_DEFINED_STATUS),'(NULL)') stat
            FROM LDTB_CONTRACT_ACCRUAL_HISTORY
            GROUP BY CONTRACT_REF_NO
            ORDER BY sm DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.CONTRACT_REF_NO,
                 'Σ_OUT=' || TO_CHAR(r.sm) || ' | stat=' || r.stat);
    END LOOP;

    -- 15.9 LDTB_PERIODIC_ACCRUAL_DATE — dates d'accrual périodique par produit
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [15.9 LDTB_PERIODIC_ACCRUAL_DATE]');
    safe_count('LDTB_PERIODIC_ACCRUAL_DATE', '  Total lignes');
    FOR r IN (SELECT MIN(PREVIOUS_ACCRUAL_TO_DATE) mn, MAX(PREVIOUS_ACCRUAL_TO_DATE) mx
              FROM LDTB_PERIODIC_ACCRUAL_DATE) LOOP
        print_kv('  Plage PREVIOUS_ACCRUAL_TO_DATE',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM LDTB_PERIODIC_ACCRUAL_DATE
    WHERE PREVIOUS_ACCRUAL_TO_DATE < SYSDATE - 90;
    print_kv('  Produits sans accrual depuis >90j', TO_CHAR(v_count));

    ----------------------------------------------------------------
    -- SECTION 16 : Clientèle & KYC — STTM_CUSTOMER / KYC / Personal
    --   Revenue Assurance : un statut client peut bloquer / fausser
    --   la facturation. On explore :
    --    - CIF_STATUS / DECEASED / FROZEN / WHEREABOUTS_UNKNOWN
    --    - WHT_PCT (withholding tax) & TAX_GROUP / CHARGE_GROUP
    --    - KYC expirés (KYC_NXT_REVIEW_DATE passée) encore actifs
    --    - AML_REQUIRED non aligné avec AML_CUSTOMER_GRP
    --    - Catégorie client vs profil risque
    ----------------------------------------------------------------
    print_section('SECTION 16 — Clientèle & KYC');

    -- 16.1 Volumétrie STTM_CUSTOMER
    DBMS_OUTPUT.PUT_LINE('  [16.1 Volumétrie STTM_CUSTOMER]');
    safe_count('STTM_CUSTOMER', '  Total clients');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE AUTH_STAT='A';
    print_kv('  Autorisés (A)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE AUTH_STAT='U';
    print_kv('  Non autorisés (U)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE RECORD_STAT='C';
    print_kv('  Fermés (RECORD_STAT=C)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE RECORD_STAT='O';
    print_kv('  Ouverts (RECORD_STAT=O)', TO_CHAR(v_count));

    -- 16.2 CUSTOMER_TYPE / CUSTOMER_CATEGORY
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.2 CUSTOMER_TYPE]');
    FOR r IN (SELECT NVL(CUSTOMER_TYPE,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUSTOMER GROUP BY CUSTOMER_TYPE ORDER BY nb DESC) LOOP
        print_kv('  TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.2.b Top 15 CUSTOMER_CATEGORY]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CUSTOMER_CATEGORY,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUSTOMER GROUP BY CUSTOMER_CATEGORY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CAT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.3 CIF_STATUS (statut client globale : actif / gelé / contentieux…)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.3 CIF_STATUS]');
    FOR r IN (SELECT NVL(CIF_STATUS,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUSTOMER GROUP BY CIF_STATUS ORDER BY nb DESC) LOOP
        print_kv('  CIF_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.3.b Clients sensibles
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE DECEASED='Y';
    print_kv('  DECEASED=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE FROZEN='Y';
    print_kv('  FROZEN=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE WHEREABOUTS_UNKNOWN='Y';
    print_kv('  WHEREABOUTS_UNKNOWN=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE AML_REQUIRED='Y';
    print_kv('  AML_REQUIRED=Y', TO_CHAR(v_count));

    -- 16.3.c Clients décédés avec comptes encore actifs (leakage)
    SELECT COUNT(DISTINCT c.CUSTOMER_NO) INTO v_count FROM STTM_CUSTOMER c
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_NO = c.CUSTOMER_NO
    WHERE c.DECEASED='Y'
      AND NVL(a.AC_STAT_DORMANT,'N')<>'Y'
      AND NVL(a.AC_STAT_FROZEN,'N')<>'Y';
    print_kv('  DECEASED avec comptes non gelés (anomalie RA)', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT c.CUSTOMER_NO) INTO v_count FROM STTM_CUSTOMER c
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_NO = c.CUSTOMER_NO
    WHERE c.FROZEN='Y'
      AND NVL(a.ACY_CURR_BALANCE,0) <> 0;
    print_kv('  FROZEN avec balance <> 0', TO_CHAR(v_count));

    -- 16.4 Ancienneté relation client (CIF_CREATION_DATE)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.4 CIF_CREATION_DATE — cohortes d''ouverture]');
    FOR r IN (
        SELECT TO_CHAR(CIF_CREATION_DATE,'YYYY') yr, COUNT(*) nb
        FROM STTM_CUSTOMER
        WHERE CIF_CREATION_DATE IS NOT NULL
        GROUP BY TO_CHAR(CIF_CREATION_DATE,'YYYY')
        ORDER BY yr DESC
    ) LOOP
        print_kv('  ' || r.yr, TO_CHAR(r.nb));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER WHERE CIF_CREATION_DATE IS NULL;
    print_kv('  CIF_CREATION_DATE NULL', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE CIF_CREATION_DATE IS NOT NULL AND CIF_CREATION_DATE > SYSDATE;
    print_kv('  CIF_CREATION_DATE > SYSDATE (anomalie)', TO_CHAR(v_count));

    -- 16.5 Ségrégation fiscale & commerciale (CHARGE_GROUP, TAX_GROUP, WHT_PCT)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.5 CHARGE_GROUP / TAX_GROUP / WHT_PCT]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CHARGE_GROUP,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUSTOMER GROUP BY CHARGE_GROUP
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CHARGE_GROUP = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(TAX_GROUP,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUSTOMER GROUP BY TAX_GROUP
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  TAX_GROUP = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.5.b WHT_PCT distribution
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.5.b WHT_PCT (retenue à la source)]');
    FOR r IN (SELECT NVL(TO_CHAR(WHT_PCT),'(NULL)') s, COUNT(*) nb
              FROM STTM_CUSTOMER GROUP BY WHT_PCT ORDER BY nb DESC) LOOP
        print_kv('  WHT_PCT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE WHT_PCT IS NOT NULL AND WHT_PCT > 0;
    print_kv('  Clients avec WHT_PCT > 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER
    WHERE WHT_PCT IS NOT NULL AND (WHT_PCT < 0 OR WHT_PCT > 100);
    print_kv('  WHT_PCT hors [0..100] (anomalie)', TO_CHAR(v_count));

    -- 16.6 Risque — CREDIT_RATING / RISK_CATEGORY / RISK_PROFILE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.6 Profil de risque]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CREDIT_RATING,'(NULL)') s, COUNT(*) nb
            FROM STTM_CUSTOMER GROUP BY CREDIT_RATING
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CREDIT_RATING = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(RISK_CATEGORY,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUSTOMER GROUP BY RISK_CATEGORY ORDER BY nb DESC) LOOP
        print_kv('  RISK_CATEGORY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(RISK_PROFILE,'(NULL)') s, COUNT(*) nb
              FROM STTM_CUSTOMER GROUP BY RISK_PROFILE ORDER BY nb DESC) LOOP
        print_kv('  RISK_PROFILE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.7 STTM_CUSTOMER_CAT — référentiel catégories
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.7 Référentiel STTM_CUSTOMER_CAT]');
    safe_count('STTM_CUSTOMER_CAT', '  Total catégories');
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER_CAT WHERE AUTH_STAT='A';
    print_kv('  Catégories autorisées', TO_CHAR(v_count));
    FOR r IN (
        SELECT * FROM (
            SELECT CUST_CAT, CUST_CAT_DESC
            FROM STTM_CUSTOMER_CAT
            WHERE RECORD_STAT='O' AND AUTH_STAT='A'
            ORDER BY CUST_CAT
        ) WHERE ROWNUM <= 20
    ) LOOP
        print_kv('  ' || r.CUST_CAT, SUBSTR(NVL(r.CUST_CAT_DESC,''),1,60));
    END LOOP;

    -- 16.7.b Catégories client non référencées
    SELECT COUNT(DISTINCT c.CUSTOMER_CATEGORY) INTO v_count FROM STTM_CUSTOMER c
    WHERE c.CUSTOMER_CATEGORY IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM STTM_CUSTOMER_CAT cc
        WHERE cc.CUST_CAT = c.CUSTOMER_CATEGORY
      );
    print_kv('  Catégories clients non référencées (FK cassée)', TO_CHAR(v_count));

    -- 16.8 STTM_CUST_PERSONAL — clients particuliers / mineurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.8 STTM_CUST_PERSONAL]');
    safe_count('STTM_CUST_PERSONAL', '  Total personnes');
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL WHERE MINOR='Y';
    print_kv('  Mineurs', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE DATE_OF_BIRTH IS NOT NULL
      AND MONTHS_BETWEEN(SYSDATE, DATE_OF_BIRTH)/12 > 110;
    print_kv('  Âge > 110 ans (anomalie données)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE DATE_OF_BIRTH IS NOT NULL
      AND DATE_OF_BIRTH > SYSDATE;
    print_kv('  DATE_OF_BIRTH future (anomalie)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE DATE_OF_BIRTH IS NULL;
    print_kv('  DATE_OF_BIRTH NULL', TO_CHAR(v_count));

    -- 16.8.b Mineurs sans guardian
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE MINOR='Y' AND LEGAL_GUARDIAN IS NULL;
    print_kv('  Mineurs SANS LEGAL_GUARDIAN', TO_CHAR(v_count));

    -- 16.8.c Passports expirés
    SELECT COUNT(*) INTO v_count FROM STTM_CUST_PERSONAL
    WHERE PPT_EXP_DATE IS NOT NULL AND PPT_EXP_DATE < TRUNC(SYSDATE);
    print_kv('  Passeport expiré', TO_CHAR(v_count));

    -- 16.9 STTM_KYC_MASTER — pilotage KYC
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.9 STTM_KYC_MASTER — RISK_LEVEL]');
    safe_count('STTM_KYC_MASTER', '  Total KYC master');
    FOR r IN (SELECT NVL(RISK_LEVEL,'(NULL)') s, COUNT(*) nb
              FROM STTM_KYC_MASTER GROUP BY RISK_LEVEL ORDER BY nb DESC) LOOP
        print_kv('  RISK_LEVEL = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(KYC_CUST_TYPE,'(NULL)') s, COUNT(*) nb
              FROM STTM_KYC_MASTER GROUP BY KYC_CUST_TYPE ORDER BY nb DESC) LOOP
        print_kv('  KYC_CUST_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.10 KYC Retail — PEP, nationality, revenus
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.10 KYC RETAIL]');
    safe_count('STTM_KYC_RETAIL', '  Total KYC retail');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL WHERE PEP='Y';
    print_kv('  PEP=Y (politically exposed person)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE IS NOT NULL
      AND KYC_NXT_REVIEW_DATE < TRUNC(SYSDATE);
    print_kv('  KYC retail revue DUE (en retard)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_RETAIL
    WHERE KYC_NXT_REVIEW_DATE IS NOT NULL
      AND KYC_NXT_REVIEW_DATE < ADD_MONTHS(TRUNC(SYSDATE),-12);
    print_kv('  KYC retail revue DUE > 1 an', TO_CHAR(v_count));

    -- 16.11 KYC Corporate
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.11 KYC CORPORATE]');
    safe_count('STTM_KYC_CORPORATE', '  Total KYC corporate');
    SELECT COUNT(*) INTO v_count FROM STTM_KYC_CORPORATE
    WHERE KYC_NXT_REVIEW_DATE IS NOT NULL
      AND KYC_NXT_REVIEW_DATE < TRUNC(SYSDATE);
    print_kv('  KYC corporate revue DUE', TO_CHAR(v_count));
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(COMPANY_TYPE,'(NULL)') s, COUNT(*) nb
            FROM STTM_KYC_CORPORATE GROUP BY COMPANY_TYPE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  COMPANY_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 16.12 Cohérence : clients avec comptes mais sans KYC
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [16.12 Cohérence clients/KYC]');
    SELECT COUNT(DISTINCT c.CUSTOMER_NO) INTO v_count FROM STTM_CUSTOMER c
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_NO = c.CUSTOMER_NO
    WHERE c.AML_REQUIRED='Y'
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_RETAIL k    WHERE k.KYC_REF_NO = c.CUSTOMER_NO)
      AND NOT EXISTS (SELECT 1 FROM STTM_KYC_CORPORATE kc WHERE kc.KYC_REF_NO = c.CUSTOMER_NO);
    print_kv('  AML_REQUIRED=Y et sans fiche KYC', TO_CHAR(v_count));

    ----------------------------------------------------------------
    -- SECTION 17 : Produits & paramétrage
    --   Revenue Assurance : le paramétrage produit détermine
    --   comment le revenu est calculé. On inspecte :
    --    - CSTM_PRODUCT (core service product — charges / taxes)
    --    - LDTM_PRODUCT_MASTER (LD/MM)
    --    - LDTM_PRODUCT_DFLT_SCHEDULES (schedules par défaut)
    --    - LDTM_PRODUCT_LIQ_ORDER (ordre de liquidation)
    --    - LDTM_PRODUCT_ROLLOVER (rollover : taxes/brokerage)
    --    - CSTB_AMOUNT_TAG (tags de montants : charge/tax allowed)
    --    - CLTM_PRODUCT_COMP_FRM_EXPR (formules ICCF CL)
    --    - LDTM_BRANCH_PARAMETERS (paramètres branches)
    ----------------------------------------------------------------
    print_section('SECTION 17 — Produits & paramétrage RA');

    -- 17.1 CSTM_PRODUCT — référentiel produits (transverse)
    DBMS_OUTPUT.PUT_LINE('  [17.1 CSTM_PRODUCT — volumétrie]');
    safe_count('CSTM_PRODUCT', '  Total produits');
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT WHERE AUTH_STAT='A';
    print_kv('  Autorisés', TO_CHAR(v_count));

    -- 17.1.b Produits par MODULE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.1.b Produits par MODULE]');
    FOR r IN (SELECT NVL(MODULE,'(NULL)') s, COUNT(*) nb
              FROM CSTM_PRODUCT GROUP BY MODULE ORDER BY nb DESC) LOOP
        print_kv('  MODULE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 17.1.c Produits expirés encore actifs
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT
    WHERE PRODUCT_END_DATE IS NOT NULL AND PRODUCT_END_DATE < TRUNC(SYSDATE);
    print_kv('  PRODUCT_END_DATE passée', TO_CHAR(v_count));

    -- 17.1.d Variance de taux
    SELECT COUNT(*) INTO v_count FROM CSTM_PRODUCT
    WHERE MAXIMUM_RATE_VARIANCE IS NOT NULL
      AND NORMAL_RATE_VARIANCE IS NOT NULL
      AND NORMAL_RATE_VARIANCE > MAXIMUM_RATE_VARIANCE;
    print_kv('  NORMAL_RATE_VARIANCE > MAXIMUM (incohérent)', TO_CHAR(v_count));

    -- 17.2 LDTM_PRODUCT_MASTER — produits LD/MM
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.2 LDTM_PRODUCT_MASTER]');
    safe_count('LDTM_PRODUCT_MASTER', '  Total produits LD/MM');

    -- 17.2.b Fréquences d'accrual
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.2.b ACCRUAL_FREQUENCY]');
    FOR r IN (SELECT NVL(ACCRUAL_FREQUENCY,'(NULL)') s, COUNT(*) nb
              FROM LDTM_PRODUCT_MASTER GROUP BY ACCRUAL_FREQUENCY
              ORDER BY nb DESC) LOOP
        print_kv('  FREQ = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 17.2.c Produits bloqués mais encore actifs dans contrats
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER WHERE BLOCK_PRODUCT='Y';
    print_kv('  Produits BLOCK_PRODUCT=Y', TO_CHAR(v_count));

    BEGIN
      SELECT COUNT(DISTINCT c.PRODUCT) INTO v_count FROM LDTB_CONTRACT_MASTER c
      JOIN LDTM_PRODUCT_MASTER p ON p.PRODUCT_CODE = c.PRODUCT
      WHERE p.BLOCK_PRODUCT='Y'
        AND NVL(c.CONTRACT_STATUS,'A') NOT IN ('L','C');
      print_kv('  Contrats actifs sur produits bloqués', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Contrats actifs sur produits bloqués', 'N/A (' || SQLERRM || ')');
    END;

    -- 17.2.d Autorisations RA-sensibles
    FOR r IN (
        SELECT 'ALLOW_PREPAY_INT=Y'         lbl, COUNT(*) nb FROM LDTM_PRODUCT_MASTER WHERE ALLOW_PREPAY_INT='Y' UNION ALL
        SELECT 'ALLOW_PREPAY_INT=N',              COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE ALLOW_PREPAY_INT='N' UNION ALL
        SELECT 'AMEND_PAST_PAID_SCH=Y',           COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE AMEND_PAST_PAID_SCH='Y' UNION ALL
        SELECT 'ALLOW_SCHED_AMEND_AFTER_SGEN=Y',  COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE ALLOW_SCHED_AMEND_AFTER_SGEN='Y' UNION ALL
        SELECT 'BOOK_UNEARNED_INTEREST=Y',        COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE BOOK_UNEARNED_INTEREST='Y' UNION ALL
        SELECT 'AUTO_PROV_REQUIRED=Y',            COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE AUTO_PROV_REQUIRED='Y' UNION ALL
        SELECT 'BROKERAGE_APPLICABLE=Y',          COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE BROKERAGE_APPLICABLE='Y' UNION ALL
        SELECT 'ASSIGNMENT_ALLOWED=Y',            COUNT(*)    FROM LDTM_PRODUCT_MASTER WHERE ASSIGNMENT_ALLOWED='Y'
    ) LOOP
        print_kv('  ' || r.lbl, TO_CHAR(r.nb));
    END LOOP;

    -- 17.3 LDTM_PRODUCT_DFLT_SCHEDULES — schedules par défaut
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.3 LDTM_PRODUCT_DFLT_SCHEDULES]');
    safe_count('LDTM_PRODUCT_DFLT_SCHEDULES', '  Total lignes');
    FOR r IN (SELECT NVL(FREQUENCY_UNIT,'(NULL)') s, COUNT(*) nb
              FROM LDTM_PRODUCT_DFLT_SCHEDULES GROUP BY FREQUENCY_UNIT
              ORDER BY nb DESC) LOOP
        print_kv('  FREQUENCY_UNIT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(DISTINCT PRODUCT) INTO v_count FROM LDTM_PRODUCT_DFLT_SCHEDULES;
    print_kv('  Produits avec schedule par défaut', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_MASTER m
    WHERE NOT EXISTS (SELECT 1 FROM LDTM_PRODUCT_DFLT_SCHEDULES d
                      WHERE d.PRODUCT = m.PRODUCT_CODE);
    print_kv('  Produits LD SANS schedule par défaut', TO_CHAR(v_count));

    -- 17.4 LDTM_PRODUCT_LIQ_ORDER — ordre de liquidation (priorité)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.4 LDTM_PRODUCT_LIQ_ORDER]');
    safe_count('LDTM_PRODUCT_LIQ_ORDER', '  Total lignes');
    FOR r IN (
        SELECT * FROM (
            SELECT PRODUCT, COUNT(*) nb_comp, MIN(LIQ_ORDER) mn, MAX(LIQ_ORDER) mx
            FROM LDTM_PRODUCT_LIQ_ORDER
            GROUP BY PRODUCT
            ORDER BY nb_comp DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.PRODUCT,
                 'nb_comp=' || TO_CHAR(r.nb_comp) || ' | order=[' || TO_CHAR(r.mn) || '..' || TO_CHAR(r.mx) || ']');
    END LOOP;

    -- 17.4.b Doublons de LIQ_ORDER par produit
    SELECT COUNT(*) INTO v_count FROM (
        SELECT PRODUCT, LIQ_ORDER, COUNT(*) nb
        FROM LDTM_PRODUCT_LIQ_ORDER
        GROUP BY PRODUCT, LIQ_ORDER
        HAVING COUNT(*) > 1
    );
    print_kv('  Doublons (PRODUCT, LIQ_ORDER)', TO_CHAR(v_count));

    -- 17.5 LDTM_PRODUCT_ROLLOVER — rollover paramétrage
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.5 LDTM_PRODUCT_ROLLOVER]');
    safe_count('LDTM_PRODUCT_ROLLOVER', '  Total lignes');
    FOR r IN (SELECT NVL(APPLY_TAX,'(NULL)') s, COUNT(*) nb
              FROM LDTM_PRODUCT_ROLLOVER GROUP BY APPLY_TAX
              ORDER BY nb DESC) LOOP
        print_kv('  APPLY_TAX = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(APPLY_BROKERAGE,'(NULL)') s, COUNT(*) nb
              FROM LDTM_PRODUCT_ROLLOVER GROUP BY APPLY_BROKERAGE
              ORDER BY nb DESC) LOOP
        print_kv('  APPLY_BROKERAGE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(AUTO_MAN_ROLLOVER,'(NULL)') s, COUNT(*) nb
              FROM LDTM_PRODUCT_ROLLOVER GROUP BY AUTO_MAN_ROLLOVER
              ORDER BY nb DESC) LOOP
        print_kv('  AUTO_MAN_ROLLOVER = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    SELECT COUNT(*) INTO v_count FROM LDTM_PRODUCT_ROLLOVER
    WHERE NVL(APPLY_TAX,'N')='N' AND NVL(APPLY_BROKERAGE,'N')='N';
    print_kv('  Rollover sans tax ni brokerage (leakage paramétrage)', TO_CHAR(v_count));

    -- 17.6 CSTB_AMOUNT_TAG — tags RA
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.6 CSTB_AMOUNT_TAG — typologie]');
    safe_count('CSTB_AMOUNT_TAG', '  Total tags');

    FOR r IN (
        SELECT 'CHARGE_ALLOWED=Y'     lbl, COUNT(*) nb FROM CSTB_AMOUNT_TAG WHERE CHARGE_ALLOWED='Y' UNION ALL
        SELECT 'COMMISSION_ALLOWED=Y',      COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE COMMISSION_ALLOWED='Y' UNION ALL
        SELECT 'INTEREST_ALLOWED=Y',        COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE INTEREST_ALLOWED='Y' UNION ALL
        SELECT 'TAX_ALLOWED=Y',             COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE TAX_ALLOWED='Y' UNION ALL
        SELECT 'ISSR_TAX_ALLOWED=Y',        COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE ISSR_TAX_ALLOWED='Y' UNION ALL
        SELECT 'TRAN_TAX_ALLOWED=Y',        COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE TRAN_TAX_ALLOWED='Y' UNION ALL
        SELECT 'TRACK_RECEIVABLE=Y',        COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE TRACK_RECEIVABLE='Y' UNION ALL
        SELECT 'TRACK_PAYABLE=Y',           COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE TRACK_PAYABLE='Y' UNION ALL
        SELECT 'UNREALISED=Y',              COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE UNREALISED='Y' UNION ALL
        SELECT 'USER_DEFINED=Y',            COUNT(*)    FROM CSTB_AMOUNT_TAG WHERE USER_DEFINED='Y'
    ) LOOP
        print_kv('  ' || r.lbl, TO_CHAR(r.nb));
    END LOOP;

    -- 17.6.b Tags custom non autorisés pour aucune nature (probable dead)
    SELECT COUNT(*) INTO v_count FROM CSTB_AMOUNT_TAG
    WHERE NVL(CHARGE_ALLOWED,'N')='N'
      AND NVL(COMMISSION_ALLOWED,'N')='N'
      AND NVL(INTEREST_ALLOWED,'N')='N'
      AND NVL(TAX_ALLOWED,'N')='N';
    print_kv('  Tags sans aucune autorisation (potentiellement morts)', TO_CHAR(v_count));

    -- 17.7 CLTM_PRODUCT_COMP_FRM_EXPR — formules ICCF CL
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.7 CLTM_PRODUCT_COMP_FRM_EXPR]');
    safe_count('CLTM_PRODUCT_COMP_FRM_EXPR', '  Total formules/lignes');
    SELECT COUNT(DISTINCT PRODUCT_CODE) INTO v_count FROM CLTM_PRODUCT_COMP_FRM_EXPR;
    print_kv('  Produits CL avec formule', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COMPONENT_NAME) INTO v_count FROM CLTM_PRODUCT_COMP_FRM_EXPR;
    print_kv('  Composants CL distincts', TO_CHAR(v_count));

    FOR r IN (SELECT NVL(FORMULA_TYPE,'(NULL)') s, COUNT(*) nb
              FROM CLTM_PRODUCT_COMP_FRM_EXPR GROUP BY FORMULA_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  FORMULA_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(EXPR_TYPE,'(NULL)') s, COUNT(*) nb
              FROM CLTM_PRODUCT_COMP_FRM_EXPR GROUP BY EXPR_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  EXPR_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 17.7.b Formules RESULT vide (leakage potentiel)
    SELECT COUNT(*) INTO v_count FROM CLTM_PRODUCT_COMP_FRM_EXPR
    WHERE RESULT IS NULL OR TRIM(RESULT) IS NULL;
    print_kv('  Formules avec RESULT vide', TO_CHAR(v_count));

    -- 17.8 LDTM_BRANCH_PARAMETERS — paramètres de branche LD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.8 LDTM_BRANCH_PARAMETERS]');
    safe_count('LDTM_BRANCH_PARAMETERS', '  Total branches paramétrées');
    FOR r IN (SELECT NVL(ACCRUAL_LEVEL,'(NULL)') s, COUNT(*) nb
              FROM LDTM_BRANCH_PARAMETERS GROUP BY ACCRUAL_LEVEL
              ORDER BY nb DESC) LOOP
        print_kv('  ACCRUAL_LEVEL = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(CONS_BILLING,'(NULL)') s, COUNT(*) nb
              FROM LDTM_BRANCH_PARAMETERS GROUP BY CONS_BILLING
              ORDER BY nb DESC) LOOP
        print_kv('  CONS_BILLING = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(TAX_COMPUTATION_BASIS,'(NULL)') s, COUNT(*) nb
              FROM LDTM_BRANCH_PARAMETERS GROUP BY TAX_COMPUTATION_BASIS
              ORDER BY nb DESC) LOOP
        print_kv('  TAX_COMPUTATION_BASIS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 17.8.b PROCESS_TILL
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [17.8.b PROCESS_TILL — avancement branche]');
    FOR r IN (SELECT NVL(PROCESS_TILL,'(NULL)') s, COUNT(*) nb
              FROM LDTM_BRANCH_PARAMETERS GROUP BY PROCESS_TILL
              ORDER BY nb DESC) LOOP
        print_kv('  PROCESS_TILL = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    ----------------------------------------------------------------
    -- SECTION 18 : Sécurité & traçabilité (SMTB_*)
    --   Revenue Assurance : la traçabilité utilisateur est cruciale
    --   pour documenter les dérogations (waivers, overrides, manual
    --   postings). On inspecte :
    --    - SMTB_USER / SMTB_USERLOG_DETAILS : inactivité, comptes
    --      dormants mais non désactivés, comptes auto-auth
    --    - SMTB_ROLE_MASTER / SMTB_ROLE_FUNC_LIMIT_DETAIL : limites
    --      d'approbation par rôle (leak possible si trop larges)
    --    - SMTB_SMS_LOG / SMTB_SMS_ACTION_LOG : trafic logs
    --    - SMTB_PARAMETERS : politique globale mots de passe
    ----------------------------------------------------------------
    print_section('SECTION 18 — Sécurité & audit trail');

    -- 18.1 SMTB_USER — volumétrie & statuts
    DBMS_OUTPUT.PUT_LINE('  [18.1 SMTB_USER — volumétrie]');
    safe_count('SMTB_USER', '  Total utilisateurs');
    FOR r IN (SELECT NVL(USER_STATUS,'(NULL)') s, COUNT(*) nb
              FROM SMTB_USER GROUP BY USER_STATUS ORDER BY nb DESC) LOOP
        print_kv('  USER_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(AUTH_STAT,'(NULL)') s, COUNT(*) nb
              FROM SMTB_USER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        print_kv('  AUTH_STAT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 18.1.b Utilisateurs avec AUTO_AUTH (auto-authorizer — risque RA)
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE AUTO_AUTH='Y';
    print_kv('  AUTO_AUTH=Y (auto-authorizer, risque SoD)', TO_CHAR(v_count));

    -- 18.1.c Utilisateurs expirés encore actifs
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
    WHERE END_DATE IS NOT NULL AND END_DATE < TRUNC(SYSDATE)
      AND NVL(USER_STATUS,'E') = 'E';
    print_kv('  END_DATE passée mais USER_STATUS=E (actif)', TO_CHAR(v_count));

    -- 18.1.d Utilisateurs jamais connectés
    BEGIN
      SELECT COUNT(*) INTO v_count FROM SMTB_USER u
      WHERE NOT EXISTS (SELECT 1 FROM SMTB_USERLOG_DETAILS d
                        WHERE d.USER_ID = u.USER_ID
                          AND d.LAST_SIGNED_ON IS NOT NULL);
      print_kv('  Utilisateurs jamais connectés', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
      print_kv('  Utilisateurs jamais connectés', 'N/A (' || SQLERRM || ')');
    END;

    -- 18.1.e Mot de passe pas changé depuis longtemps
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
    WHERE PWD_CHANGED_ON IS NOT NULL
      AND PWD_CHANGED_ON < ADD_MONTHS(TRUNC(SYSDATE),-12);
    print_kv('  PWD non changé depuis > 12 mois', TO_CHAR(v_count));

    -- 18.2 SMTB_USERLOG_DETAILS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.2 SMTB_USERLOG_DETAILS]');
    safe_count('SMTB_USERLOG_DETAILS', '  Total utilisateurs avec log');
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS
    WHERE LAST_SIGNED_ON IS NOT NULL AND LAST_SIGNED_ON < ADD_MONTHS(TRUNC(SYSDATE),-6);
    print_kv('  Inactifs > 6 mois', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS
    WHERE LAST_SIGNED_ON IS NOT NULL AND LAST_SIGNED_ON < ADD_MONTHS(TRUNC(SYSDATE),-12);
    print_kv('  Inactifs > 12 mois', TO_CHAR(v_count));
    SELECT NVL(MAX(NO_SUCCESSIVE_LOGINS),0), NVL(AVG(NO_SUCCESSIVE_LOGINS),0)
    INTO v_num, v_num FROM SMTB_USERLOG_DETAILS;
    print_kv('  MAX NO_SUCCESSIVE_LOGINS', TO_CHAR(v_num));

    -- 18.3 SMTB_ROLE_MASTER — rôles
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.3 SMTB_ROLE_MASTER]');
    safe_count('SMTB_ROLE_MASTER', '  Total rôles');
    FOR r IN (SELECT NVL(BRANCH_ROLE,'(NULL)') s, COUNT(*) nb
              FROM SMTB_ROLE_MASTER GROUP BY BRANCH_ROLE ORDER BY nb DESC) LOOP
        print_kv('  BRANCH_ROLE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(BRANCH_ROLE_CAT,'(NULL)') s, COUNT(*) nb
              FROM SMTB_ROLE_MASTER GROUP BY BRANCH_ROLE_CAT ORDER BY nb DESC) LOOP
        print_kv('  ROLE_CAT = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(BRANCH_ROLE_LEVEL,'(NULL)') s, COUNT(*) nb
              FROM SMTB_ROLE_MASTER GROUP BY BRANCH_ROLE_LEVEL ORDER BY nb DESC) LOOP
        print_kv('  ROLE_LEVEL = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 18.4 SMTB_USER_ROLE — attribution rôles/utilisateurs
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.4 SMTB_USER_ROLE]');
    safe_count('SMTB_USER_ROLE', '  Total attributions');
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_ROLE;
    print_kv('  Utilisateurs avec ≥1 rôle', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_USER_ROLE;
    print_kv('  Rôles réellement attribués', TO_CHAR(v_count));

    -- 18.4.b Rôles jamais attribués (dead)
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER m
    WHERE NOT EXISTS (SELECT 1 FROM SMTB_USER_ROLE u WHERE u.ROLE_ID = m.ROLE_ID);
    print_kv('  Rôles définis mais jamais attribués', TO_CHAR(v_count));

    -- 18.4.c Utilisateurs cumulant trop de rôles (top 10)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.4.c Top 10 utilisateurs par nb de rôles]');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, COUNT(DISTINCT ROLE_ID) nb
            FROM SMTB_USER_ROLE GROUP BY USER_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.USER_ID, TO_CHAR(r.nb) || ' rôles');
    END LOOP;

    -- 18.5 SMTB_ROLE_FUNC_LIMIT_DETAIL — limites par fonction
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.5 SMTB_ROLE_FUNC_LIMIT_DETAIL]');
    safe_count('SMTB_ROLE_FUNC_LIMIT_DETAIL', '  Total limites');

    -- 18.5.b Limites très élevées (par devise : top 15)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.5.b Top 15 limites d''input]');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_ID, FUNCTION_ID, LIMIT_CCY, INPUT_LIMIT_AMOUNT
            FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
            WHERE INPUT_LIMIT_AMOUNT IS NOT NULL
            ORDER BY INPUT_LIMIT_AMOUNT DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.ROLE_ID || '/' || r.FUNCTION_ID,
                 r.LIMIT_CCY || ' ' || TO_CHAR(r.INPUT_LIMIT_AMOUNT));
    END LOOP;

    -- 18.5.c Limites à 0 ou NULL (utilisateurs sans limite réelle)
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
    WHERE NVL(INPUT_LIMIT_AMOUNT,0) = 0;
    print_kv('  Limites à 0 ou NULL', TO_CHAR(v_count));

    -- 18.6 SMTB_SMS_LOG — trafic de logs (connexions / fonctions)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.6 SMTB_SMS_LOG]');
    safe_count('SMTB_SMS_LOG', '  Total lignes logs');

    FOR r IN (SELECT MIN(START_TIME) mn, MAX(START_TIME) mx FROM SMTB_SMS_LOG) LOOP
        print_kv('  Plage START_TIME',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    FOR r IN (SELECT NVL(LOG_TYPE,'(NULL)') s, COUNT(*) nb
              FROM SMTB_SMS_LOG GROUP BY LOG_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  LOG_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 18.6.b Top 10 utilisateurs par volume d'activité (dernier mois)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.6.b Top 10 users — activité 30 derniers jours]');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, COUNT(*) nb
            FROM SMTB_SMS_LOG
            WHERE START_TIME >= SYSDATE - 30
            GROUP BY USER_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.USER_ID, TO_CHAR(r.nb));
    END LOOP;

    -- 18.6.c Top 10 fonctions utilisées
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.6.c Top 10 FUNCTION_ID — activité 30j]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(FUNCTION_ID,'(NULL)') fn, COUNT(*) nb
            FROM SMTB_SMS_LOG
            WHERE START_TIME >= SYSDATE - 30
            GROUP BY FUNCTION_ID
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.fn, TO_CHAR(r.nb));
    END LOOP;

    -- 18.6.d Sessions hors horaires (22h-06h) — risque
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
    WHERE START_TIME >= SYSDATE - 90
      AND (TO_NUMBER(TO_CHAR(START_TIME,'HH24')) >= 22
           OR TO_NUMBER(TO_CHAR(START_TIME,'HH24')) < 6);
    print_kv('  Connexions hors horaire (22h-06h) 90j', TO_CHAR(v_count));

    -- 18.6.e Sessions weekend (RA : activités manuelles douteuses)
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
    WHERE START_TIME >= SYSDATE - 90
      AND TO_CHAR(START_TIME,'D','NLS_DATE_LANGUAGE=ENGLISH') IN ('1','7','6','7');
    print_kv('  Connexions weekend (90j, approx.)', TO_CHAR(v_count));

    -- 18.7 SMTB_SMS_ACTION_LOG — trace actions (audit granularité XML)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.7 SMTB_SMS_ACTION_LOG]');
    safe_count('SMTB_SMS_ACTION_LOG', '  Total lignes');
    FOR r IN (SELECT NVL(ACTION,'(NULL)') s, COUNT(*) nb
              FROM SMTB_SMS_ACTION_LOG GROUP BY ACTION
              ORDER BY nb DESC) LOOP
        print_kv('  ACTION = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 18.7.b Actions cross-branch (CURR_BRANCH <> HOME_BRANCH)
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_ACTION_LOG
    WHERE CURR_BRANCH IS NOT NULL AND HOME_BRANCH IS NOT NULL
      AND CURR_BRANCH <> HOME_BRANCH;
    print_kv('  Actions CURR_BRANCH <> HOME_BRANCH', TO_CHAR(v_count));

    -- 18.7.c EXITFLAG erreurs
    FOR r IN (SELECT NVL(EXITFLAG,'(NULL)') s, COUNT(*) nb
              FROM SMTB_SMS_ACTION_LOG GROUP BY EXITFLAG
              ORDER BY nb DESC) LOOP
        print_kv('  EXITFLAG = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 18.8 SMTB_USER_DISABLE — désactivations / incidents
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.8 SMTB_USER_DISABLE]');
    safe_count('SMTB_USER_DISABLE', '  Désactivations totales');
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_DISABLE;
    print_kv('  Utilisateurs distincts désactivés', TO_CHAR(v_count));

    -- 18.9 SMTB_PARAMETERS — politique sécurité
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.9 SMTB_PARAMETERS — politique globale]');
    FOR r IN (
        SELECT MIN_PWD_LENGTH        mn, MAX_PWD_LENGTH        mx,
               FREQ_PWD_CHG          fc, INVALID_LOGINS_CUM    ilc,
               INVALID_LOGINS_SUC    ils, DORMANCY_DAYS         dd,
               ARCHIVAL_PERIOD       ap
        FROM SMTB_PARAMETERS
        WHERE ROWNUM = 1
    ) LOOP
        print_kv('  MIN_PWD_LENGTH',       TO_CHAR(r.mn));
        print_kv('  MAX_PWD_LENGTH',       TO_CHAR(r.mx));
        print_kv('  FREQ_PWD_CHG (jours)', TO_CHAR(r.fc));
        print_kv('  INVALID_LOGINS_CUM',   TO_CHAR(r.ilc));
        print_kv('  INVALID_LOGINS_SUC',   TO_CHAR(r.ils));
        print_kv('  DORMANCY_DAYS (users)',TO_CHAR(r.dd));
        print_kv('  ARCHIVAL_PERIOD',      TO_CHAR(r.ap));
    END LOOP;

    -- 18.10 SMTB_PASSWORD_HISTORY — rotation
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.10 SMTB_PASSWORD_HISTORY]');
    safe_count('SMTB_PASSWORD_HISTORY', '  Total entrées');
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_PASSWORD_HISTORY;
    print_kv('  Utilisateurs avec historique PWD', TO_CHAR(v_count));

    -- 18.11 SMTB_ACTION_CONTROLS — contrôles d'actions (approvals)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [18.11 SMTB_ACTION_CONTROLS]');
    safe_count('SMTB_ACTION_CONTROLS', '  Total contrôles');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(ACTION_NAME,'(NULL)') s, COUNT(*) nb
            FROM SMTB_ACTION_CONTROLS GROUP BY ACTION_NAME
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    ----------------------------------------------------------------
    -- SECTION 19 : Branches, facilités, codes & chéquiers
    --   Revenue Assurance :
    --    - FBTM_BRANCH / FBTM_BRANCH_INFO : arrêtés de date, branches
    --    - GETM_FACILITY : lignes de crédit, utilisation, expiration
    --      (revenu commissions d'engagement / utilisation)
    --    - STTM_TRN_CODE : codes tran et paramétrage IC/interest
    --    - CATM_CHECK_BOOK : chéquiers émis, frais d'émission
    --    - STTM_ACCOUNT_CLASS : référentiel classes de compte
    ----------------------------------------------------------------
    print_section('SECTION 19 — Branches, facilités, codes & chéquiers');

    -- 19.1 FBTM_BRANCH — branches
    DBMS_OUTPUT.PUT_LINE('  [19.1 FBTM_BRANCH]');
    safe_count('FBTM_BRANCH', '  Total branches');
    SELECT COUNT(*) INTO v_count FROM FBTM_BRANCH WHERE NVL(END_OF_INPUT,'N')='Y';
    print_kv('  Branches END_OF_INPUT=Y (journée clôturée)', TO_CHAR(v_count));

    -- 19.2 FBTM_BRANCH_INFO — arrêtés de date, LCY par branche
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.2 FBTM_BRANCH_INFO]');
    safe_count('FBTM_BRANCH_INFO', '  Total infos branches');

    FOR r IN (SELECT MIN(CURRENTPOSTINGDATE) mn, MAX(CURRENTPOSTINGDATE) mx
              FROM FBTM_BRANCH_INFO) LOOP
        print_kv('  Plage CURRENTPOSTINGDATE',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    -- 19.2.b Branches en retard de posting (arrêté en arrière)
    SELECT COUNT(*) INTO v_count FROM FBTM_BRANCH_INFO
    WHERE CURRENTPOSTINGDATE IS NOT NULL
      AND CURRENTPOSTINGDATE < TRUNC(SYSDATE) - 3;
    print_kv('  CURRENTPOSTINGDATE en retard >3j (batch figé ?)', TO_CHAR(v_count));

    -- 19.2.c Distribution LCY des branches
    FOR r IN (SELECT NVL(BRANCH_LCY,'(NULL)') s, COUNT(*) nb
              FROM FBTM_BRANCH_INFO GROUP BY BRANCH_LCY
              ORDER BY nb DESC) LOOP
        print_kv('  BRANCH_LCY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.3 FBTB_USER — utilisateurs FCC front-end
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.3 FBTB_USER]');
    safe_count('FBTB_USER', '  Total users FCC');
    FOR r IN (SELECT NVL(USER_STATUS,'(NULL)') s, COUNT(*) nb
              FROM FBTB_USER GROUP BY USER_STATUS
              ORDER BY nb DESC) LOOP
        print_kv('  USER_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    FOR r IN (SELECT NVL(LOGINSTATUS,'(NULL)') s, COUNT(*) nb
              FROM FBTB_USER GROUP BY LOGINSTATUS
              ORDER BY nb DESC) LOOP
        print_kv('  LOGINSTATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.3.b Users avec MAXTXNAMT/MAXAUTHAMT élevés
    SELECT COUNT(*) INTO v_count FROM FBTB_USER
    WHERE MAXTXNAMT IS NOT NULL AND MAXTXNAMT > 0;
    print_kv('  Users avec MAXTXNAMT défini', TO_CHAR(v_count));

    FOR r IN (
        SELECT * FROM (
            SELECT USERID, LIMITCCY,
                   MAXTXNAMT, MAXAUTHAMT, USERTXNLIMIT
            FROM FBTB_USER
            WHERE MAXAUTHAMT IS NOT NULL
            ORDER BY MAXAUTHAMT DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.USERID,
                 r.LIMITCCY || ' MAXAUTH=' || TO_CHAR(r.MAXAUTHAMT) ||
                 ' MAXTXN=' || TO_CHAR(r.MAXTXNAMT));
    END LOOP;

    -- 19.4 GETM_FACILITY — lignes de crédit
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.4 GETM_FACILITY — facilités]');
    safe_count('GETM_FACILITY', '  Total facilités');
    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE AUTH_STAT='A';
    print_kv('  Autorisées', TO_CHAR(v_count));

    -- 19.4.b CATEGORY
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CATEGORY,'(NULL)') s, COUNT(*) nb
            FROM GETM_FACILITY GROUP BY CATEGORY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  CATEGORY = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.4.c Agrégats montants
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.4.c Agrégats GETM_FACILITY]');
    SELECT NVL(SUM(APPROVED_AMT),0) INTO v_num FROM GETM_FACILITY;
    print_kv('  Σ APPROVED_AMT', TO_CHAR(v_num));
    SELECT NVL(SUM(AVAILABLE_AMOUNT),0) INTO v_num FROM GETM_FACILITY;
    print_kv('  Σ AVAILABLE_AMOUNT', TO_CHAR(v_num));
    SELECT NVL(SUM(AMOUNT_UTILISED_TODAY),0) INTO v_num FROM GETM_FACILITY;
    print_kv('  Σ AMOUNT_UTILISED_TODAY', TO_CHAR(v_num));
    SELECT NVL(SUM(BLOCK_AMOUNT),0) INTO v_num FROM GETM_FACILITY;
    print_kv('  Σ BLOCK_AMOUNT', TO_CHAR(v_num));

    -- 19.4.d Taux d'utilisation moyen
    FOR r IN (
        SELECT ROUND(AVG(CASE WHEN APPROVED_AMT > 0
                              THEN (APPROVED_AMT - AVAILABLE_AMOUNT) / APPROVED_AMT * 100
                              END),2) pct_util,
               COUNT(*) nb
        FROM GETM_FACILITY
        WHERE APPROVED_AMT IS NOT NULL AND APPROVED_AMT > 0
          AND AVAILABLE_AMOUNT IS NOT NULL
    ) LOOP
        print_kv('  Taux d''utilisation moyen (%)', TO_CHAR(r.pct_util) || ' (sur ' || TO_CHAR(r.nb) || ' lignes)');
    END LOOP;

    -- 19.4.e Lignes expirées mais encore AVAILABLE
    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY
    WHERE LINE_EXPIRY_DATE IS NOT NULL
      AND LINE_EXPIRY_DATE < TRUNC(SYSDATE)
      AND NVL(AVAILABLE_AMOUNT,0) > 0;
    print_kv('  Lignes expirées avec AVAILABLE > 0 (leak RA)', TO_CHAR(v_count));

    -- 19.4.f Lignes sur-utilisées (utilisation > approuvé)
    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY
    WHERE APPROVED_AMT IS NOT NULL AND AVAILABLE_AMOUNT IS NOT NULL
      AND (APPROVED_AMT - AVAILABLE_AMOUNT) > APPROVED_AMT
      AND APPROVED_AMT > 0;
    print_kv('  Lignes dépassées (util > approuvé)', TO_CHAR(v_count));

    -- 19.4.g Overdraft historique (DATE_OF_LAST_OD récent)
    SELECT COUNT(*) INTO v_count FROM GETM_FACILITY
    WHERE DATE_OF_LAST_OD IS NOT NULL
      AND DATE_OF_LAST_OD >= TRUNC(SYSDATE) - 90;
    print_kv('  Lignes avec OD dans les 90 derniers jours', TO_CHAR(v_count));

    -- 19.4.h Top 10 facilités par APPROVED_AMT
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.4.h Top 10 facilités par APPROVED_AMT]');
    FOR r IN (
        SELECT * FROM (
            SELECT LINE_CODE, CATEGORY,
                   APPROVED_AMT, AVAILABLE_AMOUNT, LINE_EXPIRY_DATE
            FROM GETM_FACILITY
            WHERE APPROVED_AMT IS NOT NULL
            ORDER BY APPROVED_AMT DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.LINE_CODE,
                 'appr=' || TO_CHAR(r.APPROVED_AMT) ||
                 ' avail=' || TO_CHAR(r.AVAILABLE_AMOUNT) ||
                 ' expiry=' || TO_CHAR(r.LINE_EXPIRY_DATE,'YYYY-MM-DD'));
    END LOOP;

    -- 19.5 STTM_TRN_CODE — codes transaction & paramétrage IC
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.5 STTM_TRN_CODE]');
    safe_count('STTM_TRN_CODE', '  Total codes tran');

    FOR r IN (SELECT NVL(COMPONENT_TYPE,'(NULL)') s, COUNT(*) nb
              FROM STTM_TRN_CODE GROUP BY COMPONENT_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  COMPONENT_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.5.b Flags IC (inclusion dans calcul intérêt / turnover)
    FOR r IN (
        SELECT 'IC_BAL_INCLUSION=Y'   lbl, COUNT(*) nb FROM STTM_TRN_CODE WHERE IC_BAL_INCLUSION='Y'   UNION ALL
        SELECT 'IC_BAL_INCLUSION=N',         COUNT(*)    FROM STTM_TRN_CODE WHERE IC_BAL_INCLUSION='N'   UNION ALL
        SELECT 'IC_TOVER_INCLUSION=Y',       COUNT(*)    FROM STTM_TRN_CODE WHERE IC_TOVER_INCLUSION='Y' UNION ALL
        SELECT 'IC_TOVER_INCLUSION=N',       COUNT(*)    FROM STTM_TRN_CODE WHERE IC_TOVER_INCLUSION='N' UNION ALL
        SELECT 'IC_PENALTY=Y',               COUNT(*)    FROM STTM_TRN_CODE WHERE IC_PENALTY='Y'        UNION ALL
        SELECT 'EXEMPT_ADV_INTEREST=Y',      COUNT(*)    FROM STTM_TRN_CODE WHERE EXEMPT_ADV_INTEREST='Y' UNION ALL
        SELECT 'AML_MONITORING=Y',           COUNT(*)    FROM STTM_TRN_CODE WHERE AML_MONITORING='Y'
    ) LOOP
        print_kv('  ' || r.lbl, TO_CHAR(r.nb));
    END LOOP;

    -- 19.5.c Codes tran exemptés d'intérêt (impact RA direct)
    SELECT COUNT(*) INTO v_count FROM STTM_TRN_CODE
    WHERE EXEMPT_ADV_INTEREST='Y' AND AUTH_STAT='A';
    print_kv('  Codes tran exemptés intérêt (autorisés)', TO_CHAR(v_count));

    -- 19.6 CATM_CHECK_BOOK — chéquiers
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.6 CATM_CHECK_BOOK]');
    safe_count('CATM_CHECK_BOOK', '  Total chéquiers');
    SELECT COUNT(*) INTO v_count FROM CATM_CHECK_BOOK WHERE AUTH_STAT='A';
    print_kv('  Autorisés', TO_CHAR(v_count));
    SELECT NVL(SUM(CHECK_LEAVES),0) INTO v_num FROM CATM_CHECK_BOOK;
    print_kv('  Σ CHECK_LEAVES émises', TO_CHAR(v_num));

    -- 19.6.b Par CHEQUE_BOOK_TYPE
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CHEQUE_BOOK_TYPE,'(NULL)') s, COUNT(*) nb,
                   NVL(SUM(CHECK_LEAVES),0) lv
            FROM CATM_CHECK_BOOK GROUP BY CHEQUE_BOOK_TYPE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.s, 'nb=' || TO_CHAR(r.nb) || ' | leaves=' || TO_CHAR(r.lv));
    END LOOP;

    -- 19.6.c Delivery status
    FOR r IN (SELECT NVL(CHQBOOK_DELIVERD,'(NULL)') s, COUNT(*) nb
              FROM CATM_CHECK_BOOK GROUP BY CHQBOOK_DELIVERD
              ORDER BY nb DESC) LOOP
        print_kv('  DELIVERED = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.6.d Commandés mais non livrés depuis > 60j
    SELECT COUNT(*) INTO v_count FROM CATM_CHECK_BOOK
    WHERE NVL(CHQBOOK_DELIVERD,'N')='N'
      AND ORDER_DATE IS NOT NULL
      AND ORDER_DATE < TRUNC(SYSDATE) - 60;
    print_kv('  Non livrés > 60j depuis commande', TO_CHAR(v_count));

    -- 19.6.e Volume par année d'émission
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.6.e Chéquiers émis par année]');
    FOR r IN (
        SELECT TO_CHAR(ISSUE_DATE,'YYYY') yr, COUNT(*) nb
        FROM CATM_CHECK_BOOK
        WHERE ISSUE_DATE IS NOT NULL
        GROUP BY TO_CHAR(ISSUE_DATE,'YYYY')
        ORDER BY yr DESC
    ) LOOP
        print_kv('  ' || r.yr, TO_CHAR(r.nb));
    END LOOP;

    -- 19.7 STTM_ACCOUNT_CLASS — référentiel classes
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [19.7 STTM_ACCOUNT_CLASS]');
    safe_count('STTM_ACCOUNT_CLASS', '  Total classes');
    SELECT COUNT(*) INTO v_count FROM STTM_ACCOUNT_CLASS WHERE AUTH_STAT='A';
    print_kv('  Autorisées', TO_CHAR(v_count));
    FOR r IN (SELECT NVL(AC_CLASS_TYPE,'(NULL)') s, COUNT(*) nb
              FROM STTM_ACCOUNT_CLASS GROUP BY AC_CLASS_TYPE
              ORDER BY nb DESC) LOOP
        print_kv('  AC_CLASS_TYPE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 19.7.b Classes avec END_DATE passée mais encore référencées
    SELECT COUNT(DISTINCT a.ACCOUNT_CLASS) INTO v_count FROM STTM_CUST_ACCOUNT a
    JOIN STTM_ACCOUNT_CLASS c ON c.ACCOUNT_CODE = a.ACCOUNT_CLASS
    WHERE c.END_DATE IS NOT NULL
      AND c.END_DATE < TRUNC(SYSDATE)
      AND NVL(a.RECORD_STAT,'O')='O';
    print_kv('  Classes END_DATE passée utilisées par cptes ouverts', TO_CHAR(v_count));

    ----------------------------------------------------------------
    -- SECTION 20 : Automatic Process / EOD jobs / MIS
    --   Revenue Assurance : les jobs EOD portent l'accrual, la
    --   liquidation automatique et la réévaluation. Un job bloqué
    --   = revenu non comptabilisé. On regarde aussi :
    --    - LDTB_AUTO_FUNCTION_DETAILS / PROCESS_QUEUE : avancement
    --    - LDTB_COMPUTATION_HANDOFF : handoff accrual → compta
    --    - LDTB_ACCRUAL_FOR_LIMITS : accrual utilisé pour exposition
    --    - LDTB_CONTRACT_BALANCE : encours contrats
    --    - LDTB_HOLIDAY_CURRENCIES : jours fériés devises
    --    - MITB_CLASS_MAPPING : ventilation MIS des revenus
    ----------------------------------------------------------------
    print_section('SECTION 20 — Automatic Process, EOD jobs & MIS');

    -- 20.1 LDTB_AUTOMATIC_PROCESS_MASTER
    DBMS_OUTPUT.PUT_LINE('  [20.1 LDTB_AUTOMATIC_PROCESS_MASTER]');
    safe_count('LDTB_AUTOMATIC_PROCESS_MASTER', '  Total processes définis');
    FOR r IN (SELECT NVL(MODULE,'(NULL)') s, COUNT(*) nb
              FROM LDTB_AUTOMATIC_PROCESS_MASTER GROUP BY MODULE
              ORDER BY nb DESC) LOOP
        print_kv('  MODULE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTOMATIC_PROCESS_MASTER WHERE INVOKE_DURING_EOD='Y';
    print_kv('  INVOKE_DURING_EOD=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTOMATIC_PROCESS_MASTER WHERE INVOKE_DURING_BOD='Y';
    print_kv('  INVOKE_DURING_BOD=Y', TO_CHAR(v_count));

    -- 20.2 LDTB_AUTOMATIC_PROCESS_QUEUE — exécutions
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.2 LDTB_AUTOMATIC_PROCESS_QUEUE]');
    safe_count('LDTB_AUTOMATIC_PROCESS_QUEUE', '  Total entrées queue');

    FOR r IN (SELECT NVL(PROCESS_STATUS,'(NULL)') s, COUNT(*) nb
              FROM LDTB_AUTOMATIC_PROCESS_QUEUE GROUP BY PROCESS_STATUS
              ORDER BY nb DESC) LOOP
        print_kv('  PROCESS_STATUS = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 20.2.b Plage PROCESSING_DATE
    FOR r IN (SELECT MIN(PROCESSING_DATE) mn, MAX(PROCESSING_DATE) mx
              FROM LDTB_AUTOMATIC_PROCESS_QUEUE) LOOP
        print_kv('  Plage PROCESSING_DATE',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    -- 20.2.c Jobs en erreur / halt récent
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTOMATIC_PROCESS_QUEUE
    WHERE UPPER(NVL(PROCESS_STATUS,'')) IN ('E','H','F','ERROR','FAILED','HALTED');
    print_kv('  Jobs en statut erreur/halt', TO_CHAR(v_count));

    -- 20.2.d Jobs longs (>6h)
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTOMATIC_PROCESS_QUEUE
    WHERE START_TIME IS NOT NULL AND END_TIME IS NOT NULL
      AND (END_TIME - START_TIME) * 24 > 6;
    print_kv('  Jobs > 6h de durée', TO_CHAR(v_count));

    -- 20.2.e Jobs ouverts (START sans END)
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTOMATIC_PROCESS_QUEUE
    WHERE START_TIME IS NOT NULL AND END_TIME IS NULL;
    print_kv('  Jobs ouverts (START sans END)', TO_CHAR(v_count));

    -- 20.2.f Top 10 jobs par durée moyenne
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.2.f Top 10 jobs par durée moyenne (sec)]');
    FOR r IN (
        SELECT * FROM (
            SELECT PROCESS_NAME,
                   COUNT(*) nb_exec,
                   ROUND(AVG((END_TIME - START_TIME) * 86400),1) avg_sec,
                   ROUND(MAX((END_TIME - START_TIME) * 86400),1) max_sec
            FROM LDTB_AUTOMATIC_PROCESS_QUEUE
            WHERE START_TIME IS NOT NULL AND END_TIME IS NOT NULL
            GROUP BY PROCESS_NAME
            ORDER BY avg_sec DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.PROCESS_NAME,
                 'nb=' || TO_CHAR(r.nb_exec) ||
                 ' | avg=' || TO_CHAR(r.avg_sec) || 's' ||
                 ' | max=' || TO_CHAR(r.max_sec) || 's');
    END LOOP;

    -- 20.3 LDTB_AUTO_FUNCTION_SETUP — parallélisme EOD
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.3 LDTB_AUTO_FUNCTION_SETUP — parallélisme]');
    safe_count('LDTB_AUTO_FUNCTION_SETUP', '  Total setups');
    FOR r IN (
        SELECT MODULE,
               NVL(PARALLELIZE_AUTO_FUNCTION,'(NULL)') par,
               NVL(MAX_PARALLEL_PROCESSORS,0) mp,
               NVL(MAX_HALTED_PROCESSORS,0) mh,
               NVL(WAIT_TIME_FOR_PROCESSORS,0) wt
        FROM LDTB_AUTO_FUNCTION_SETUP
    ) LOOP
        print_kv('  ' || r.MODULE,
                 'par=' || r.par || ' | max_proc=' || TO_CHAR(r.mp) ||
                 ' | max_halt=' || TO_CHAR(r.mh) ||
                 ' | wait=' || TO_CHAR(r.wt));
    END LOOP;

    -- 20.4 LDTB_AUTO_FUNCTION_DETAILS — avancement accrual par branche
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.4 LDTB_AUTO_FUNCTION_DETAILS]');
    safe_count('LDTB_AUTO_FUNCTION_DETAILS', '  Total lignes');

    -- 20.4.b Branches en retard sur accrual (>30j)
    SELECT COUNT(*) INTO v_count FROM LDTB_AUTO_FUNCTION_DETAILS
    WHERE CURRENT_PROCESSING_DATE IS NOT NULL
      AND CURRENT_PROCESSING_DATE < TRUNC(SYSDATE) - 30;
    print_kv('  Branches accrual en retard >30j', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM LDTB_AUTO_FUNCTION_DETAILS
    WHERE NVL(WORK_IN_PROGRESS,'N')='Y';
    print_kv('  Branches WORK_IN_PROGRESS=Y (verrouillées)', TO_CHAR(v_count));

    -- 20.4.c Écart PREVIOUS vs CURRENT_PROCESS_TILL_DATE
    FOR r IN (
        SELECT BRANCH,
               PREVIOUS_PROCESS_TILL_DATE prev_d,
               CURRENT_PROCESS_TILL_DATE  curr_d,
               CURRENT_PROCESSING_DATE    proc_d
        FROM LDTB_AUTO_FUNCTION_DETAILS
        WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.BRANCH,
                 'prev=' || TO_CHAR(r.prev_d,'YYYY-MM-DD') ||
                 ' curr=' || TO_CHAR(r.curr_d,'YYYY-MM-DD') ||
                 ' proc=' || TO_CHAR(r.proc_d,'YYYY-MM-DD'));
    END LOOP;

    -- 20.5 LDTB_COMPUTATION_HANDOFF — handoff accrual → compta
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.5 LDTB_COMPUTATION_HANDOFF]');
    safe_count('LDTB_COMPUTATION_HANDOFF', '  Total lignes pending');
    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count FROM LDTB_COMPUTATION_HANDOFF;
    print_kv('  Contrats en handoff', TO_CHAR(v_count));
    SELECT NVL(SUM(AMOUNT),0) INTO v_num FROM LDTB_COMPUTATION_HANDOFF;
    print_kv('  Σ AMOUNT en handoff', TO_CHAR(v_num));

    FOR r IN (SELECT MIN(EFFECTIVE_DATE) mn, MAX(EFFECTIVE_DATE) mx
              FROM LDTB_COMPUTATION_HANDOFF) LOOP
        print_kv('  Plage EFFECTIVE_DATE handoff',
                 TO_CHAR(r.mn,'YYYY-MM-DD') || ' → ' || TO_CHAR(r.mx,'YYYY-MM-DD'));
    END LOOP;

    -- 20.5.b Handoff ancien (> 7j) — signe batch bloqué
    SELECT COUNT(*) INTO v_count FROM LDTB_COMPUTATION_HANDOFF
    WHERE EFFECTIVE_DATE IS NOT NULL
      AND EFFECTIVE_DATE < TRUNC(SYSDATE) - 7;
    print_kv('  Handoffs > 7j non traités (leak RA)', TO_CHAR(v_count));

    -- 20.6 LDTB_ACCRUAL_FOR_LIMITS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.6 LDTB_ACCRUAL_FOR_LIMITS]');
    safe_count('LDTB_ACCRUAL_FOR_LIMITS', '  Total lignes');
    SELECT NVL(SUM(TOTAL_CURRENT_NET_ACCRUAL),0) INTO v_num FROM LDTB_ACCRUAL_FOR_LIMITS;
    print_kv('  Σ TOTAL_CURRENT_NET_ACCRUAL (limites exposition)', TO_CHAR(v_num));

    -- 20.7 LDTB_CONTRACT_BALANCE — encours contrat
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.7 LDTB_CONTRACT_BALANCE]');
    safe_count('LDTB_CONTRACT_BALANCE', '  Total lignes');
    SELECT NVL(SUM(CURRENT_FACE_VALUE),0) INTO v_num FROM LDTB_CONTRACT_BALANCE;
    print_kv('  Σ CURRENT_FACE_VALUE', TO_CHAR(v_num));
    SELECT NVL(SUM(PRINCIPAL_OUTSTANDING_BAL),0) INTO v_num FROM LDTB_CONTRACT_BALANCE;
    print_kv('  Σ PRINCIPAL_OUTSTANDING_BAL', TO_CHAR(v_num));

    -- 20.7.b Face_value < 0 ou outstanding > face (anomalie)
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_BALANCE
    WHERE CURRENT_FACE_VALUE IS NOT NULL AND CURRENT_FACE_VALUE < 0;
    print_kv('  FACE_VALUE < 0', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_BALANCE
    WHERE PRINCIPAL_OUTSTANDING_BAL IS NOT NULL AND CURRENT_FACE_VALUE IS NOT NULL
      AND PRINCIPAL_OUTSTANDING_BAL > CURRENT_FACE_VALUE + 0.01;
    print_kv('  PRINCIPAL_OUTSTANDING > FACE_VALUE (anomalie)', TO_CHAR(v_count));

    -- 20.8 LDTB_CONTRACT_CONTROL — traçabilité process
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.8 LDTB_CONTRACT_CONTROL]');
    safe_count('LDTB_CONTRACT_CONTROL', '  Total lignes');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(PROCESS_CODE,'(NULL)') s, COUNT(*) nb
            FROM LDTB_CONTRACT_CONTROL GROUP BY PROCESS_CODE
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        print_kv('  PROCESS_CODE = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 20.8.b Top 10 utilisateurs saisissant (ENTRY_BY)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.8.b Top 10 utilisateurs - saisies contrat]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(ENTRY_BY,'(NULL)') s, COUNT(*) nb
            FROM LDTB_CONTRACT_CONTROL GROUP BY ENTRY_BY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 20.9 LDTB_HOLIDAY_CURRENCIES
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.9 LDTB_HOLIDAY_CURRENCIES]');
    safe_count('LDTB_HOLIDAY_CURRENCIES', '  Total lignes');
    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count FROM LDTB_HOLIDAY_CURRENCIES;
    print_kv('  Contrats avec devises holiday', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CCY) INTO v_count FROM LDTB_HOLIDAY_CURRENCIES;
    print_kv('  Devises holiday distinctes', TO_CHAR(v_count));

    -- 20.10 MITB_CLASS_MAPPING — ventilation MIS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.10 MITB_CLASS_MAPPING — ventilation analytique]');
    safe_count('MITB_CLASS_MAPPING', '  Total mappings MIS');
    SELECT COUNT(DISTINCT CUSTOMER) INTO v_count FROM MITB_CLASS_MAPPING;
    print_kv('  Clients couverts', TO_CHAR(v_count));

    FOR r IN (SELECT NVL(CALC_METHOD,'(NULL)') s, COUNT(*) nb
              FROM MITB_CLASS_MAPPING GROUP BY CALC_METHOD
              ORDER BY nb DESC) LOOP
        print_kv('  CALC_METHOD = ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    -- 20.10.b Clients clés sans MIS mapping (leakage analytique)
    SELECT COUNT(*) INTO v_count FROM STTM_CUSTOMER c
    WHERE c.AUTH_STAT='A'
      AND NOT EXISTS (SELECT 1 FROM MITB_CLASS_MAPPING m
                      WHERE m.CUSTOMER = c.CUSTOMER_NO);
    print_kv('  Clients autorisés sans MIS mapping', TO_CHAR(v_count));

    -- 20.10.c Top 5 devises MIS
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [20.10.c Top 5 devises MIS]');
    FOR r IN (
        SELECT * FROM (
            SELECT NVL(CCY,'(NULL)') s, COUNT(*) nb
            FROM MITB_CLASS_MAPPING GROUP BY CCY
            ORDER BY nb DESC
        ) WHERE ROWNUM <= 5
    ) LOOP
        print_kv('  ' || r.s, TO_CHAR(r.nb));
    END LOOP;

    ----------------------------------------------------------------
    -- CLOTURE : bannière fin exploration
    ----------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> FIN DE L''EXPLORATION REVENUE ASSURANCE (20 SECTIONS)');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('  Sections couvertes :');
    DBMS_OUTPUT.PUT_LINE('   0.  En-tête / volumétrie générale');
    DBMS_OUTPUT.PUT_LINE('   1.  Volumétrie RA');
    DBMS_OUTPUT.PUT_LINE('   2.  Référentiels revenue');
    DBMS_OUTPUT.PUT_LINE('   3.  ACTB_HISTORY');
    DBMS_OUTPUT.PUT_LINE('   4.  CLTB_ACCOUNT_COMPONENTS & waivers prêts');
    DBMS_OUTPUT.PUT_LINE('   5.  CLTB_ACCOUNT_SCHEDULES — échéances & overdue');
    DBMS_OUTPUT.PUT_LINE('   6.  CLTB_AMOUNT_PAID/RECD/LIQ');
    DBMS_OUTPUT.PUT_LINE('   7.  CLTB_ACCOUNT_APPS_MASTER lifecycle');
    DBMS_OUTPUT.PUT_LINE('   8.  LDTB contrats & accruals');
    DBMS_OUTPUT.PUT_LINE('   9.  ICTM paramétrage taux');
    DBMS_OUTPUT.PUT_LINE('   10. GLTB_GL_BAL revenus GL');
    DBMS_OUTPUT.PUT_LINE('   11. RVTB_ACC_REVAL réévaluation FX');
    DBMS_OUTPUT.PUT_LINE('   12. Comptes clients — turnovers/overdraft/dormance');
    DBMS_OUTPUT.PUT_LINE('   13. SITB Standing Instructions & frais');
    DBMS_OUTPUT.PUT_LINE('   14. Cohérences globales & anomalies RA');
    DBMS_OUTPUT.PUT_LINE('   15. LDTB ICCF détaillé — calculs/rollovers/accruals');
    DBMS_OUTPUT.PUT_LINE('   16. Clientèle & KYC');
    DBMS_OUTPUT.PUT_LINE('   17. Produits & paramétrage');
    DBMS_OUTPUT.PUT_LINE('   18. Sécurité & audit trail');
    DBMS_OUTPUT.PUT_LINE('   19. Branches, facilités, codes & chéquiers');
    DBMS_OUTPUT.PUT_LINE('   20. Automatic Process / EOD jobs & MIS');
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
