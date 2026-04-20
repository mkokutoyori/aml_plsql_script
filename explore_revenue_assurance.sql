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
END;
/
