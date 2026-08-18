-- ============================================================
-- SCRIPT D'AUDIT DE LA TRESORERIE ET DU PORTEFEUILLE-TITRES
-- Base : FLEXCUBE (FCUBS) — Module MM (Money Market / Titres)
-- Referentiel : COBAC / CEMAC — PCEC
-- ============================================================
-- Ce script controle la structure du portefeuille de tresorerie,
-- ses composantes, le calcul des interets, la comptabilisation,
-- les liquidations, les rollovers, les normes prudentielles COBAC
-- et le dispositif de controle interne.
--
-- Il s'execute EN UNE SEULE FOIS, en LECTURE SEULE.
-- Aucun objet n'est cree, aucune donnee n'est modifiee.
--
-- Utilisation :
--     SPOOL rapport_audit_tresorerie_mm.txt
--     @audit_tresorerie_mm.sql
--     SPOOL OFF
--
-- IMPORTANT : renseigner p_fpn_xaf (fonds propres nets) dans le
-- bloc PARAMETRES ci-dessous pour activer les ratios prudentiels.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 32767
SET PAGESIZE 0
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE

    -- =========================================================
    -- PARAMETRES  (a ajuster avant execution)
    -- =========================================================
    p_module            VARCHAR2(3)  := 'MM';        -- module audite
    p_ccy_locale        VARCHAR2(3)  := 'XAF';       -- devise locale
    p_fpn_xaf           NUMBER       := NULL;        -- fonds propres nets (XAF) — A RENSEIGNER
    p_date_arrete       DATE         := NULL;        -- NULL = derniere date comptable MM
    p_mois_periode      NUMBER       := 24;          -- profondeur d'analyse des flux (mois)

    p_tol_interet       NUMBER       := 1;           -- tolerance absolue recalcul interet
    p_tol_interet_pct   NUMBER       := 0.01;        -- tolerance relative recalcul interet (1%)
    p_tol_compta        NUMBER       := 1;           -- tolerance equilibre comptable (XAF)
    p_tol_change_pct    NUMBER       := 0.01;        -- tolerance ecart de cours (1%)

    p_seuil_grand_risq  NUMBER       := 15;          -- grand risque : % FPN  (R-2010/02)
    p_seuil_benef_max   NUMBER       := 25;          -- plafond / beneficiaire : % FPN (R-2020/01)
    p_seuil_gr_cumul    NUMBER       := 800;         -- plafond cumul grands risques : % FPN
    p_seuil_chg_devise  NUMBER       := 15;          -- position de change / devise : % FPN (R-2003/02)
    p_seuil_chg_global  NUMBER       := 45;          -- position de change globale : % FPN (R-2003/02)
    p_seuil_concentr    NUMBER       := 10;          -- alerte concentration : % de l'encours MM

    p_jours_retard_1    NUMBER       := 30;          -- paliers d'anciennete d'impaye
    p_jours_retard_2    NUMBER       := 90;
    p_jours_retard_3    NUMBER       := 180;
    p_jours_retard_4    NUMBER       := 360;
    p_jours_accrual_max NUMBER       := 5;           -- retard max admis d'accrual (jours)
    p_ecart_taux_bps    NUMBER       := 200;         -- ecart de taux hors marche (points de base)
    p_rollover_max      NUMBER       := 6;           -- nb de renouvellements au-dela duquel on alerte
    p_backval_max       NUMBER       := 5;           -- jours de back-value tolere

    p_echantillon       NUMBER       := 25;          -- nb de lignes detaillees par test
    p_users_techniques  VARCHAR2(400) := ',SYSTEM,SYSTEMUSER,BATCH,AUTOUSER,FLEXSWITCH,';

    -- =========================================================
    -- VARIABLES DE TRAVAIL
    -- =========================================================
    v_count         NUMBER;
    v_count2        NUMBER;
    v_count3        NUMBER;
    v_total         NUMBER;
    v_num1          NUMBER;
    v_num2          NUMBER;
    v_num3          NUMBER;
    v_num4          NUMBER;
    v_date1         DATE;
    v_date2         DATE;
    v_txt1          VARCHAR2(200);
    v_sep           VARCHAR2(120) := RPAD('=', 100, '=');
    v_test_no       NUMBER := 0;
    v_anomalies     NUMBER := 0;
    v_nb_crit       NUMBER := 0;
    v_nb_maj        NUMBER := 0;
    v_nb_min        NUMBER := 0;
    v_row_num       NUMBER := 0;
    v_debut         DATE;
    v_dt_deb        DATE;
    v_dt_fin        DATE;
    v_encours_tot   NUMBER := 0;

    -- =========================================================
    -- UTILITAIRES D'AFFICHAGE
    -- =========================================================
    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE print_sub(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  --- ' || p_title || ' ' || RPAD('-', GREATEST(4, 90 - LENGTH(p_title)), '-'));
    END;

    -- Test standard : libelle, nb de cas, population, criticite
    PROCEDURE print_test(p_label VARCHAR2, p_count NUMBER,
                         p_total NUMBER DEFAULT NULL,
                         p_crit  VARCHAR2 DEFAULT 'MAJEUR') IS
        v_val VARCHAR2(80);
    BEGIN
        v_test_no := v_test_no + 1;
        IF p_total IS NOT NULL THEN
            v_val := TO_CHAR(p_count) || ' / ' || TO_CHAR(p_total);
        ELSE
            v_val := TO_CHAR(p_count);
        END IF;
        DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
            || RPAD(p_label, 68, '.') || ' ' || LPAD(v_val, 16)
            || CASE WHEN NVL(p_count,0) > 0
                    THEN '  *** ANOMALIE (' || p_crit || ') ***'
                    ELSE '  OK' END);
        IF NVL(p_count,0) > 0 THEN
            v_anomalies := v_anomalies + 1;
            IF    p_crit = 'CRITIQUE' THEN v_nb_crit := v_nb_crit + 1;
            ELSIF p_crit = 'MAJEUR'   THEN v_nb_maj  := v_nb_maj  + 1;
            ELSE                           v_nb_min  := v_nb_min  + 1;
            END IF;
        END IF;
    END;

    -- Ligne d'information (ne compte pas comme un test)
    PROCEDURE print_kv(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_label, 68, '.') || ' ' || NVL(p_value, 'N/A'));
    END;

    PROCEDURE print_note(p_msg VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || p_msg);
    END;

    PROCEDURE print_blank IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
    END;

    -- Dessine une ligne de separation parametrable
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

BEGIN

    v_debut := SYSDATE;

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('      A U D I T   D E   L A   T R E S O R E R I E   —   M O D U L E   M M');
    DBMS_OUTPUT.PUT_LINE('      FLEXCUBE Universal Banking  —  Referentiel COBAC / CEMAC');
    DBMS_OUTPUT.PUT_LINE('      Date du rapport : ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- SECTION 0 : INITIALISATION, GARDE-FOUS ET CADRAGE
    -- =========================================================
    print_section('SECTION 0 : INITIALISATION, GARDE-FOUS ET CADRAGE');

    -- Determination de la date d'arrete
    IF p_date_arrete IS NULL THEN
        SELECT NVL(MAX(TRN_DT), TRUNC(SYSDATE)) INTO p_date_arrete
        FROM   ACTB_HISTORY WHERE MODULE = p_module;
    END IF;
    v_dt_fin := p_date_arrete;
    v_dt_deb := ADD_MONTHS(p_date_arrete, -p_mois_periode);

    print_sub('Parametres appliques');
    print_kv('Module audite', p_module);
    print_kv('Devise locale', p_ccy_locale);
    print_kv('Date d''arrete', TO_CHAR(v_dt_fin, 'DD/MM/YYYY'));
    print_kv('Periode d''analyse des flux', TO_CHAR(v_dt_deb, 'DD/MM/YYYY') || ' -> ' || TO_CHAR(v_dt_fin, 'DD/MM/YYYY'));
    print_kv('Fonds propres nets (XAF)',
             CASE WHEN p_fpn_xaf IS NULL THEN 'NON RENSEIGNES — ratios prudentiels en mode degrade'
                  ELSE TO_CHAR(p_fpn_xaf, 'FM999G999G999G999G990') END);
    print_kv('Tolerance recalcul interet', TO_CHAR(p_tol_interet) || ' / ' || TO_CHAR(p_tol_interet_pct * 100) || '%');
    print_kv('Tolerance equilibre comptable', TO_CHAR(p_tol_compta) || ' ' || p_ccy_locale);
    print_kv('Plafond par beneficiaire (R-2020/01)', TO_CHAR(p_seuil_benef_max) || '% FPN');
    print_kv('Seuil grand risque (R-2010/02)', TO_CHAR(p_seuil_grand_risq) || '% FPN');
    print_kv('Plafond cumul grands risques', TO_CHAR(p_seuil_gr_cumul) || '% FPN');
    print_kv('Position de change / devise (R-2003/02)', TO_CHAR(p_seuil_chg_devise) || '% FPN');
    print_kv('Comptes techniques exclus du maker/checker', RTRIM(LTRIM(p_users_techniques, ','), ','));

    -- ---------------------------------------------------------
    -- TRS-002 / TRS-003 : garde-fous de perimetre
    -- ---------------------------------------------------------
    print_sub('Garde-fous de perimetre');

    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Lignes LDTB_CONTRACT_MASTER (module MM, ttes versions)', TO_CHAR(v_count));
    IF v_count = 0 THEN
        print_note('*** ARRET : aucun contrat du module ' || p_module || ' — le perimetre est vide.');
    END IF;

    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE MODULE = p_module;
    print_kv('Ecritures ACTB_HISTORY (module MM)', TO_CHAR(v_count));

    -- TRS-004 : coherence de la devise locale declaree
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_BRANCH_PARAMETERS
    WHERE  REPORTING_CCY IS NOT NULL AND TRIM(REPORTING_CCY) IS NOT NULL
    AND    TRIM(REPORTING_CCY) <> p_ccy_locale;
    print_test('TRS-004 Agences dont REPORTING_CCY <> devise locale parametree', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-006 : cadrage volumetrique
    -- ---------------------------------------------------------
    print_sub('Cadrage volumetrique du portefeuille');

    SELECT COUNT(DISTINCT CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Contrats MM distincts', TO_CHAR(v_count));
    v_total := v_count;

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT m.CONTRACT_REF_NO, m.MATURITY_DATE, m.CONTRACT_STATUS,
                   ROW_NUMBER() OVER (PARTITION BY m.CONTRACT_REF_NO
                        ORDER BY m.VERSION_NO DESC, m.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER m WHERE m.MODULE = p_module)
        WHERE rn = 1
        AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin));
    print_kv('  dont non echus a la date d''arrete', TO_CHAR(v_count));
    print_kv('  dont echus a la date d''arrete', TO_CHAR(v_total - v_count));

    SELECT NVL(SUM(b.PRINCIPAL_OUTSTANDING_BAL), 0) INTO v_encours_tot
    FROM   LDTB_CONTRACT_BALANCE b
    WHERE  b.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);
    print_kv('Encours principal total (devise contrat, brut)', TO_CHAR(v_encours_tot, 'FM999G999G999G999G990'));

    SELECT NVL(SUM(m.LCY_AMOUNT), 0) INTO v_num1 FROM (
        SELECT * FROM (
            SELECT c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m;
    print_kv('Nominal total contrats (contre-valeur ' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G999G990'));

    SELECT COUNT(DISTINCT PRODUCT) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Produits MM distincts', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT COUNTERPARTY) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Contreparties distinctes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CURRENCY) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Devises distinctes', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH) INTO v_count FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Agences de booking distinctes', TO_CHAR(v_count));

    SELECT MIN(BOOKING_DATE), MAX(BOOKING_DATE) INTO v_date1, v_date2
    FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module;
    print_kv('Plage des dates de booking',
             TO_CHAR(v_date1, 'DD/MM/YYYY') || ' -> ' || TO_CHAR(v_date2, 'DD/MM/YYYY'));

    SELECT COUNT(*), NVL(SUM(CASE WHEN DRCR_IND = 'D' THEN LCY_AMOUNT ELSE 0 END), 0),
                     NVL(SUM(CASE WHEN DRCR_IND = 'C' THEN LCY_AMOUNT ELSE 0 END), 0)
    INTO   v_count, v_num1, v_num2
    FROM   ACTB_HISTORY WHERE MODULE = p_module AND TRN_DT BETWEEN v_dt_deb AND v_dt_fin;
    print_kv('Ecritures MM sur la periode', TO_CHAR(v_count));
    print_kv('  Total debits (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G999G990'));
    print_kv('  Total credits (' || p_ccy_locale || ')', TO_CHAR(v_num2, 'FM999G999G999G999G990'));
    print_kv('  Ecart debits/credits', TO_CHAR(v_num1 - v_num2, 'FM999G999G999G999G990'));

    -- ---------------------------------------------------------
    -- TRS-001 : accessibilite des objets du perimetre
    -- ---------------------------------------------------------
    print_sub('TRS-001 : Accessibilite des objets du perimetre');
    v_count := 0;
    FOR d IN (
        SELECT 'LDTB_CONTRACT_MASTER'          t FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_MASTER_FCC'        FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_PREFERENCE'        FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_SCHEDULES'         FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_ICCF_DETAILS'      FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_ICCF_CALC'         FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_ACCRUAL_HISTORY'   FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_LIQ'               FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_LIQ_SUMMARY'       FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_BALANCE'           FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_ROLLOVER'          FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_SWIFT_MESSAGE'     FROM DUAL UNION ALL
        SELECT 'LDTB_CONTRACT_CONTROL'           FROM DUAL UNION ALL
        SELECT 'LDTM_PRODUCT_MASTER'             FROM DUAL UNION ALL
        SELECT 'LDTM_BRANCH_PARAMETERS'          FROM DUAL UNION ALL
        SELECT 'ACTB_HISTORY'                    FROM DUAL UNION ALL
        SELECT 'GLTB_GL_BAL'                     FROM DUAL UNION ALL
        SELECT 'STTB_ACCOUNT'                    FROM DUAL UNION ALL
        SELECT 'STTM_CUSTOMER'                   FROM DUAL UNION ALL
        SELECT 'GETM_FACILITY'                   FROM DUAL UNION ALL
        SELECT 'RVTB_ACC_REVAL'                  FROM DUAL UNION ALL
        SELECT 'CYTB_RATES_HISTORY'              FROM DUAL UNION ALL
        SELECT 'SMTB_USER'                       FROM DUAL) LOOP
        SELECT COUNT(*) INTO v_count2 FROM ALL_OBJECTS
        WHERE  OBJECT_NAME = d.t AND OBJECT_TYPE IN ('TABLE','VIEW','SYNONYM');
        IF v_count2 = 0 THEN
            v_count := v_count + 1;
            print_note('    -> OBJET NON VISIBLE : ' || d.t);
        END IF;
    END LOOP;
    print_test('TRS-001 Objets du perimetre non visibles depuis ce compte', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-005 : coherence des bornes de la periode d'analyse
    -- ---------------------------------------------------------
    IF v_dt_deb >= v_dt_fin THEN
        print_test('TRS-005 Bornes de periode incoherentes (debut >= arrete)', 1, NULL, 'MAJEUR');
        v_dt_deb := ADD_MONTHS(v_dt_fin, -24);
        print_note('    -> correction automatique : debut ramene a ' || TO_CHAR(v_dt_deb,'DD/MM/YYYY'));
    ELSE
        print_test('TRS-005 Bornes de periode incoherentes (debut >= arrete)', 0, NULL, 'MAJEUR');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY WHERE MODULE = p_module AND TRN_DT > v_dt_fin;
    print_test('TRS-005 Ecritures MM posterieures a la date d''arrete', v_count, NULL, 'MAJEUR');


    -- =========================================================
    -- SECTION 1 : REFERENTIEL PRODUITS ET PARAMETRAGE
    -- =========================================================
    print_section('SECTION 1 : REFERENTIEL PRODUITS ET PARAMETRAGE');

    -- ---------------------------------------------------------
    -- TRS-101 : inventaire des produits MM
    -- ---------------------------------------------------------
    print_sub('TRS-101 : Inventaire des produits du module MM');
    tbl_line('4,10,34,6,5,6,16,9,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' LIBELLE',34) || '|'
        || RPAD(' TYPE',6) || '|' || RPAD(' PAY',5) || '|' || RPAD(' ACCR',6) || '|'
        || RPAD(' TENOR MIN/MAX',16) || '|' || RPAD(' NB CTR',9) || '|' || RPAD(' NOMINAL (M XAF)',20) || '|');
    tbl_line('4,10,34,6,5,6,16,9,20');
    v_row_num := 0;
    FOR d IN (
        SELECT mm.PRODUCT,
               NVL(SUBSTR(cp.PRODUCT_DESCRIPTION,1,32),'-')            AS libelle,
               NVL(pm.PRODUCT_TYPE,'-')                                AS ptype,
               NVL(pm.PAYMENT_METHOD,'-')                              AS pmeth,
               NVL(pm.ACCRUAL_FREQUENCY,'-')                           AS accr,
               NVL(TO_CHAR(pm.MIN_TENOR),'?') || '/' || NVL(TO_CHAR(pm.MAX_TENOR),'?')
                   || ' ' || NVL(pm.TENOR_UNIT,'')                     AS tenor,
               COUNT(*)                                                AS nb_ctr,
               NVL(SUM(mm.LCY_AMOUNT),0)                               AS nominal
        FROM  (SELECT * FROM (
                   SELECT c.PRODUCT, c.LCY_AMOUNT,
                          ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                               ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                   FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
               WHERE rn = 1) mm
        LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
        LEFT JOIN CSTM_PRODUCT        cp ON cp.PRODUCT_CODE = mm.PRODUCT
        GROUP BY mm.PRODUCT, cp.PRODUCT_DESCRIPTION, pm.PRODUCT_TYPE, pm.PAYMENT_METHOD,
                 pm.ACCRUAL_FREQUENCY, pm.MIN_TENOR, pm.MAX_TENOR, pm.TENOR_UNIT
        ORDER BY NVL(SUM(mm.LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || d.libelle,34) || '|'
            || RPAD(' ' || d.ptype,6) || '|' || RPAD(' ' || d.pmeth,5) || '|'
            || RPAD(' ' || d.accr,6) || '|' || RPAD(' ' || SUBSTR(d.tenor,1,14),16) || '|'
            || LPAD(TO_CHAR(d.nb_ctr,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.nominal/1000000,'FM999G999G990D00') || ' M',19) || ' |');
    END LOOP;
    tbl_line('4,10,34,6,5,6,16,9,20');

    -- ---------------------------------------------------------
    -- TRS-102 : coherence PRODUCT_TYPE / sens comptable dominant
    -- ---------------------------------------------------------
    print_sub('TRS-102 : Coherence PRODUCT_TYPE / sens comptable dominant a l''initiation');
    tbl_line('4,10,8,12,12,14,14,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' TYPE',8) || '|'
        || RPAD(' NB ECR DEB',12) || '|' || RPAD(' NB ECR CRE',12) || '|'
        || RPAD(' DEBIT (M)',14) || '|' || RPAD(' CREDIT (M)',14) || '|' || RPAD(' SENS DOM.',12) || '|');
    tbl_line('4,10,8,12,12,14,14,12');
    v_row_num := 0;
    FOR d IN (
        SELECT h.PRODUCT,
               NVL(pm.PRODUCT_TYPE,'-') AS ptype,
               SUM(CASE WHEN h.DRCR_IND = 'D' THEN 1 ELSE 0 END)          AS nb_d,
               SUM(CASE WHEN h.DRCR_IND = 'C' THEN 1 ELSE 0 END)          AS nb_c,
               SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) AS mt_d,
               SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) AS mt_c
        FROM   ACTB_HISTORY h
        LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = h.PRODUCT
        WHERE  h.MODULE = p_module AND h.EVENT = 'INIT'
        GROUP BY h.PRODUCT, pm.PRODUCT_TYPE
        ORDER BY SUM(h.LCY_AMOUNT) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || d.ptype,8) || '|'
            || LPAD(TO_CHAR(d.nb_d,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.nb_c,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt_d/1000000,'FM999G999G990D00'),13) || ' |'
            || LPAD(TO_CHAR(d.mt_c/1000000,'FM999G999G990D00'),13) || ' |'
            || RPAD(' ' || CASE WHEN d.mt_d > d.mt_c THEN 'DEBIT' ELSE 'CREDIT' END,12) || '|');
    END LOOP;
    tbl_line('4,10,8,12,12,14,14,12');
    print_note('Lecture : un produit de placement (emploi) doit etre debiteur a l''initiation,');
    print_note('un produit d''emprunt (ressource) crediteur. Toute inversion est a justifier.');

    -- Produits sans PRODUCT_TYPE renseigne
    SELECT COUNT(DISTINCT mm.PRODUCT) INTO v_count
    FROM  (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
    WHERE pm.PRODUCT_TYPE IS NULL OR TRIM(pm.PRODUCT_TYPE) IS NULL;
    print_test('TRS-102 Produits MM sans PRODUCT_TYPE renseigne', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-103 : produits utilises absents du referentiel
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTM_PRODUCT_MASTER pm WHERE pm.PRODUCT = mm.PRODUCT);
    print_test('TRS-103 Produits utilises absents de LDTM_PRODUCT_MASTER', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        FOR d IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER m
                  WHERE m.MODULE = p_module
                  AND NOT EXISTS (SELECT 1 FROM LDTM_PRODUCT_MASTER pm WHERE pm.PRODUCT = m.PRODUCT)) LOOP
            print_note('    -> produit inconnu : ' || d.PRODUCT);
        END LOOP;
    END IF;

    -- ---------------------------------------------------------
    -- TRS-104 : produits bloques mais utilises
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT m.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_MASTER m
    JOIN   LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = m.PRODUCT
    WHERE  m.MODULE = p_module AND pm.BLOCK_PRODUCT = 'Y';
    print_test('TRS-104 Contrats portes par un produit bloque (BLOCK_PRODUCT=Y)', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-105 : produits porteurs d'interet sans accrual
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (pm.ACCRUAL_FREQUENCY IS NULL OR TRIM(pm.ACCRUAL_FREQUENCY) IS NULL
           OR NVL(pm.TRACK_ACCRUED_INTEREST,'N') <> 'Y');
    print_test('TRS-105 Produits MM sans accrual ou sans suivi des interets courus', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        FOR d IN (SELECT pm.PRODUCT, NVL(pm.ACCRUAL_FREQUENCY,'-') af, NVL(pm.TRACK_ACCRUED_INTEREST,'-') tr
                  FROM LDTM_PRODUCT_MASTER pm
                  WHERE pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
                  AND (pm.ACCRUAL_FREQUENCY IS NULL OR TRIM(pm.ACCRUAL_FREQUENCY) IS NULL
                       OR NVL(pm.TRACK_ACCRUED_INTEREST,'N') <> 'Y')) LOOP
            print_note('    -> ' || RPAD(d.PRODUCT,10) || ' ACCRUAL_FREQUENCY=' || d.af
                       || '  TRACK_ACCRUED_INTEREST=' || d.tr);
        END LOOP;
    END IF;

    -- ---------------------------------------------------------
    -- TRS-106 : frequence d'accrual non quotidienne
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    pm.ACCRUAL_FREQUENCY IS NOT NULL AND TRIM(pm.ACCRUAL_FREQUENCY) IS NOT NULL
    AND    pm.ACCRUAL_FREQUENCY <> 'D';
    print_test('TRS-106 Produits MM a frequence d''accrual non quotidienne', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-107 : traitement de la decote / interets non acquis (R-2003/03)
    -- ---------------------------------------------------------
    print_sub('TRS-107 : Parametrage decote / interets non acquis (COBAC R-2003/03)');
    tbl_line('4,10,10,10,10,10,10,10');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' DISC_ACC',10) || '|'
        || RPAD(' UNEARNED',10) || '|' || RPAD(' CAPITAL.',10) || '|' || RPAD(' CD',10) || '|'
        || RPAD(' NEGOC.',10) || '|' || RPAD(' PAY_METH',10) || '|');
    tbl_line('4,10,10,10,10,10,10,10');
    v_row_num := 0;
    FOR d IN (SELECT pm.PRODUCT, NVL(pm.DISC_ACCR_APPLICABLE,'-') da, NVL(pm.BOOK_UNEARNED_INTEREST,'-') bu,
                     NVL(pm.CAPITALISE,'-') cap, NVL(pm.CERTIFICATE_OF_DEPOSIT,'-') cd,
                     NVL(pm.NEGOTIABLE,'-') neg, NVL(pm.PAYMENT_METHOD,'-') pmt
              FROM LDTM_PRODUCT_MASTER pm
              WHERE pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              ORDER BY pm.PRODUCT) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || d.da,10) || '|' || RPAD(' ' || d.bu,10) || '|'
            || RPAD(' ' || d.cap,10) || '|' || RPAD(' ' || d.cd,10) || '|' || RPAD(' ' || d.neg,10) || '|'
            || RPAD(' ' || d.pmt,10) || '|');
    END LOOP;
    tbl_line('4,10,10,10,10,10,10,10');

    -- ---------------------------------------------------------
    -- TRS-108 : provisionnement automatique
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(pm.AUTO_PROV_REQUIRED,'N') <> 'Y';
    print_test('TRS-108 Produits MM sans provisionnement automatique', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-109 : tolerances de taux non parametrees
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (NVL(pm.NORMAL_RATE_VARIANCE,0) = 0 OR NVL(pm.MAXIMUM_RATE_VARIANCE,0) = 0);
    print_test('TRS-109 Produits MM sans garde-fou de variance de taux', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-110 : bornes de duree incoherentes
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (pm.MIN_TENOR IS NULL OR pm.MAX_TENOR IS NULL OR pm.MIN_TENOR > pm.MAX_TENOR);
    print_test('TRS-110 Produits MM a bornes de duree absentes ou incoherentes', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-111 : contrats bookes hors periode de validite du produit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_MASTER m
    JOIN   CSTM_PRODUCT cp ON cp.PRODUCT_CODE = m.PRODUCT
    WHERE  m.MODULE = p_module
    AND   (m.BOOKING_DATE < cp.PRODUCT_START_DATE
           OR (cp.PRODUCT_END_DATE IS NOT NULL AND m.BOOKING_DATE > cp.PRODUCT_END_DATE));
    print_test('TRS-111 Contrats bookes hors periode de validite du produit', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-112 : autorisation du parametrage produit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   CSTM_PRODUCT cp
    WHERE  cp.PRODUCT_CODE IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (NVL(cp.AUTH_STAT,'U') <> 'A' OR cp.MAKER_ID = cp.CHECKER_ID);
    print_test('TRS-112 Produits MM non autorises ou maker = checker', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        tbl_line('4,10,34,8,18,18,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' LIBELLE',34) || '|'
            || RPAD(' AUTH',8) || '|' || RPAD(' MAKER',18) || '|' || RPAD(' CHECKER',18) || '|' || RPAD(' MOD_NO',8) || '|');
        tbl_line('4,10,34,8,18,18,8');
        v_row_num := 0;
        FOR d IN (SELECT cp.PRODUCT_CODE, NVL(SUBSTR(cp.PRODUCT_DESCRIPTION,1,32),'-') lib,
                         NVL(cp.AUTH_STAT,'-') auth, NVL(cp.MAKER_ID,'-') mk, NVL(cp.CHECKER_ID,'-') ck,
                         NVL(cp.MOD_NO,0) md
                  FROM CSTM_PRODUCT cp
                  WHERE cp.PRODUCT_CODE IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
                  AND (NVL(cp.AUTH_STAT,'U') <> 'A' OR cp.MAKER_ID = cp.CHECKER_ID)) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.PRODUCT_CODE,10) || '|' || RPAD(' ' || d.lib,34) || '|'
                || RPAD(' ' || d.auth,8) || '|' || RPAD(' ' || SUBSTR(d.mk,1,16),18) || '|'
                || RPAD(' ' || SUBSTR(d.ck,1,16),18) || '|' || LPAD(TO_CHAR(d.md),7) || ' |');
        END LOOP;
        tbl_line('4,10,34,8,18,18,8');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-113 : parametres d'agence
    -- ---------------------------------------------------------
    print_sub('TRS-113 : Parametres d''agence du module LD/MM');
    tbl_line('4,10,12,12,16,16,10,18,18');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AGENCE',10) || '|' || RPAD(' PROC_TILL',12) || '|'
        || RPAD(' ACCR_LEVEL',12) || '|' || RPAD(' TAX_BASIS',16) || '|' || RPAD(' RESIDUAL_AMT',16) || '|'
        || RPAD(' REP_CCY',10) || '|' || RPAD(' MAKER',18) || '|' || RPAD(' CHECKER',18) || '|');
    tbl_line('4,10,12,12,16,16,10,18,18');
    v_row_num := 0;
    FOR d IN (SELECT BRANCH_CODE, NVL(PROCESS_TILL,'-') pt, NVL(ACCRUAL_LEVEL,'-') al,
                     NVL(TAX_COMPUTATION_BASIS,'-') tb, NVL(RESIDUAL_AMOUNT,0) ra,
                     NVL(REPORTING_CCY,'-') rc, NVL(MAKER_ID,'-') mk, NVL(CHECKER_ID,'-') ck
              FROM LDTM_BRANCH_PARAMETERS ORDER BY BRANCH_CODE) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.BRANCH_CODE,10) || '|' || RPAD(' ' || d.pt,12) || '|' || RPAD(' ' || d.al,12) || '|'
            || RPAD(' ' || SUBSTR(d.tb,1,14),16) || '|' || LPAD(TO_CHAR(d.ra,'FM999G999G990'),15) || ' |'
            || RPAD(' ' || d.rc,10) || '|' || RPAD(' ' || SUBSTR(d.mk,1,16),18) || '|'
            || RPAD(' ' || SUBSTR(d.ck,1,16),18) || '|');
    END LOOP;
    tbl_line('4,10,12,12,16,16,10,18,18');

    SELECT COUNT(*) INTO v_count
    FROM   LDTM_BRANCH_PARAMETERS
    WHERE  MAKER_ID = CHECKER_ID OR NVL(AUTH_STAT,'U') <> 'A';
    print_test('TRS-113 Parametres d''agence non autorises ou maker = checker', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-114 : ordre de liquidation non defini
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTM_PRODUCT_LIQ_ORDER lo WHERE lo.PRODUCT = mm.PRODUCT);
    print_test('TRS-114 Produits MM sans ordre de liquidation defini', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-115 : rollover automatique
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_ROLLOVER pr
    WHERE  pr.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    pr.AUTO_MAN_ROLLOVER = 'A';
    print_test('TRS-115 Produits MM en rollover AUTOMATIQUE', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        FOR d IN (SELECT pr.PRODUCT, NVL(pr.ROLLOVER_WITH_INTEREST,'-') ri, NVL(pr.ROLLOVER_METHOD,'-') rm,
                         NVL(pr.DEDUCT_TAX_ON_ROLLOVER,'-') dt
                  FROM LDTM_PRODUCT_ROLLOVER pr
                  WHERE pr.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
                  AND pr.AUTO_MAN_ROLLOVER = 'A') LOOP
            print_note('    -> ' || RPAD(d.PRODUCT,10) || ' avec interets=' || d.ri
                       || '  methode=' || d.rm || '  taxe=' || d.dt);
        END LOOP;
    END IF;

    -- ---------------------------------------------------------
    -- TRS-116 : echeanciers par defaut absents
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTM_PRODUCT_DFLT_SCHEDULES ds WHERE ds.PRODUCT = mm.PRODUCT);
    print_test('TRS-116 Produits MM sans echeancier par defaut', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-117 : ecarts referentiel produit / table miroir
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTM_PRODUCT_MASTER pm
    JOIN   LDTM_PRODUCT_MASTER_FCC pf ON pf.PRODUCT = pm.PRODUCT
    WHERE  pm.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (NVL(pm.ACCRUAL_FREQUENCY,'#')   <> NVL(pf.ACCRUAL_FREQUENCY,'#')
        OR NVL(pm.PAYMENT_METHOD,'#')      <> NVL(pf.PAYMENT_METHOD,'#')
        OR NVL(pm.PRODUCT_TYPE,'#')        <> NVL(pf.PRODUCT_TYPE,'#')
        OR NVL(pm.LIQUIDATION_MODE,'#')    <> NVL(pf.LIQUIDATION_MODE,'#')
        OR NVL(pm.MAX_TENOR,-1)            <> NVL(pf.MAX_TENOR,-1));
    print_test('TRS-117 Ecarts LDTM_PRODUCT_MASTER vs table miroir _FCC', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-118 : cartographie des AMOUNT_TAG comptables MM
    -- ---------------------------------------------------------
    print_sub('TRS-118 : Cartographie des AMOUNT_TAG du module MM');
    tbl_line('4,24,40,10,12,18,18');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AMOUNT_TAG',24) || '|' || RPAD(' DESCRIPTION',40) || '|'
        || RPAD(' TYPE',10) || '|' || RPAD(' NB ECR',12) || '|' || RPAD(' DEBIT (M XAF)',18) || '|'
        || RPAD(' CREDIT (M XAF)',18) || '|');
    tbl_line('4,24,40,10,12,18,18');
    v_row_num := 0;
    FOR d IN (
        SELECT h.AMOUNT_TAG,
               NVL(SUBSTR(MAX(t.DESCRIPTION),1,38),'(inconnu du referentiel)') AS descr,
               NVL(MAX(t.AMOUNT_TAG_TYPE),'-')                                 AS ttype,
               COUNT(*)                                                        AS nb,
               SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END)    AS mt_d,
               SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END)    AS mt_c
        FROM   ACTB_HISTORY h
        LEFT JOIN CSTB_AMOUNT_TAG t ON t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE
        WHERE  h.MODULE = p_module
        GROUP BY h.AMOUNT_TAG
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        EXIT WHEN v_row_num > 40;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(SUBSTR(d.AMOUNT_TAG,1,22),'(vide)'),24) || '|' || RPAD(' ' || d.descr,40) || '|'
            || RPAD(' ' || d.ttype,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt_d/1000000,'FM999G999G990D00'),17) || ' |'
            || LPAD(TO_CHAR(d.mt_c/1000000,'FM999G999G990D00'),17) || ' |');
    END LOOP;
    tbl_line('4,24,40,10,12,18,18');

    SELECT COUNT(DISTINCT h.AMOUNT_TAG) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM CSTB_AMOUNT_TAG t
                       WHERE t.AMOUNT_TAG = h.AMOUNT_TAG AND t.MODULE = h.MODULE);
    print_test('TRS-118 AMOUNT_TAG MM inconnus du referentiel CSTB_AMOUNT_TAG', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-119 : codes transaction MM
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.TRN_CODE) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM STTM_TRN_CODE t WHERE t.TRN_CODE = h.TRN_CODE);
    print_test('TRS-119 Codes transaction MM absents du referentiel STTM_TRN_CODE', v_count, NULL, 'MAJEUR');

    SELECT COUNT(DISTINCT h.TRN_CODE) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   STTM_TRN_CODE t ON t.TRN_CODE = h.TRN_CODE
    WHERE  h.MODULE = p_module AND NVL(t.RECORD_STAT,'O') <> 'O';
    print_test('TRS-119 Codes transaction MM fermes au referentiel', v_count, NULL, 'MAJEUR');


    -- =========================================================
    -- SECTION 2 : STRUCTURE DU PORTEFEUILLE
    -- =========================================================
    print_section('SECTION 2 : STRUCTURE DU PORTEFEUILLE');

    -- ---------------------------------------------------------
    -- TRS-201 : repartition par produit (encours et taux moyen)
    -- ---------------------------------------------------------
    print_sub('TRS-201 : Repartition de l''encours par produit');
    tbl_line('4,10,34,9,20,9,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' LIBELLE',34) || '|'
        || RPAD(' NB CTR',9) || '|' || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',9) || '|'
        || RPAD(' TX MOY %',12) || '|' || RPAD(' DUREE MOY',12) || '|');
    tbl_line('4,10,34,9,20,9,12,12');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT, c.AMOUNT, c.MAIN_COMP_RATE,
                       c.VALUE_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT mm.PRODUCT,
               NVL(SUBSTR(MAX(cp.PRODUCT_DESCRIPTION),1,32),'-')                  AS libelle,
               COUNT(*)                                                           AS nb_ctr,
               NVL(SUM(mm.LCY_AMOUNT),0)                                          AS encours,
               ROUND(RATIO_TO_REPORT(NVL(SUM(mm.LCY_AMOUNT),0)) OVER () * 100, 2)  AS pct,
               ROUND(SUM(NVL(mm.MAIN_COMP_RATE,0) * NVL(mm.LCY_AMOUNT,0))
                     / NULLIF(SUM(NVL(mm.LCY_AMOUNT,0)),0), 3)                    AS tx_moy,
               ROUND(AVG(mm.MATURITY_DATE - mm.VALUE_DATE), 0)                    AS duree
        FROM   mm
        LEFT JOIN CSTM_PRODUCT cp ON cp.PRODUCT_CODE = mm.PRODUCT
        GROUP BY mm.PRODUCT
        ORDER BY NVL(SUM(mm.LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || d.libelle,34) || '|'
            || LPAD(TO_CHAR(d.nb_ctr,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |'
            || LPAD(TO_CHAR(NVL(d.tx_moy,0),'FM990D000'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.duree,0),'FM999G990') || ' j',11) || ' |');
    END LOOP;
    tbl_line('4,10,34,9,20,9,12,12');

    -- ---------------------------------------------------------
    -- TRS-203 : repartition par devise
    -- ---------------------------------------------------------
    print_sub('TRS-203 : Repartition par devise');
    tbl_line('4,10,9,22,22,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DEVISE',10) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' MONTANT DEVISE',22) || '|' || RPAD(' CONTRE-VAL (M XAF)',22) || '|' || RPAD(' % TOTAL',9) || '|');
    tbl_line('4,10,9,22,22,9');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CURRENCY, c.AMOUNT, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT NVL(CURRENCY,'(vide)') AS ccy, COUNT(*) AS nb,
               NVL(SUM(AMOUNT),0) AS mt_dev, NVL(SUM(LCY_AMOUNT),0) AS mt_lcy,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) AS pct
        FROM   mm GROUP BY CURRENCY ORDER BY NVL(SUM(LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.ccy,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.mt_dev,'FM999G999G999G990'),21) || ' |'
            || LPAD(TO_CHAR(d.mt_lcy/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |');
    END LOOP;
    tbl_line('4,10,9,22,22,9');

    -- ---------------------------------------------------------
    -- TRS-204 / TRS-205 : repartition par contrepartie
    -- ---------------------------------------------------------
    print_sub('TRS-204 : Principales contreparties (encours decroissant)');
    tbl_line('4,13,32,8,12,9,20,9,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' CONTREPARTIE',32) || '|'
        || RPAD(' TYPE',8) || '|' || RPAD(' CATEGORIE',12) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',9) || '|' || RPAD(' PAYS',12) || '|');
    tbl_line('4,13,32,8,12,9,20,9,12');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1),
        agg AS (
            SELECT mm.COUNTERPARTY,
                   NVL(SUBSTR(MAX(cu.CUSTOMER_NAME1),1,30),'(inconnu)') AS nom,
                   NVL(MAX(cu.CUSTOMER_TYPE),'-')                       AS ctype,
                   NVL(MAX(cu.CUSTOMER_CATEGORY),'-')                   AS ccat,
                   NVL(MAX(cu.COUNTRY),'-')                             AS pays,
                   COUNT(*)                                             AS nb,
                   NVL(SUM(mm.LCY_AMOUNT),0)                            AS encours,
                   ROUND(RATIO_TO_REPORT(NVL(SUM(mm.LCY_AMOUNT),0)) OVER () * 100, 2) AS pct
            FROM   mm
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY
            GROUP BY mm.COUNTERPARTY)
        SELECT * FROM (SELECT * FROM agg ORDER BY encours DESC) WHERE ROWNUM <= 30) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.COUNTERPARTY,'(vide)'),13) || '|' || RPAD(' ' || d.nom,32) || '|'
            || RPAD(' ' || d.ctype,8) || '|' || RPAD(' ' || SUBSTR(d.ccat,1,10),12) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |' || RPAD(' ' || d.pays,12) || '|');
    END LOOP;
    tbl_line('4,13,32,8,12,9,20,9,12');

    print_sub('TRS-205 : Repartition par categorie de contrepartie');
    tbl_line('4,16,40,9,20,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CATEGORIE',16) || '|' || RPAD(' LIBELLE',40) || '|'
        || RPAD(' NB CTR',9) || '|' || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',9) || '|');
    tbl_line('4,16,40,9,20,9');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT NVL(cu.CUSTOMER_CATEGORY,'(inconnue)') AS cat,
               NVL(SUBSTR(MAX(cc.CUST_CAT_DESC),1,38),'-') AS lib,
               COUNT(*) AS nb, NVL(SUM(mm.LCY_AMOUNT),0) AS encours,
               ROUND(RATIO_TO_REPORT(NVL(SUM(mm.LCY_AMOUNT),0)) OVER () * 100, 2) AS pct
        FROM   mm
        LEFT JOIN STTM_CUSTOMER     cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY
        LEFT JOIN STTM_CUSTOMER_CAT cc ON cc.CUST_CAT    = cu.CUSTOMER_CATEGORY
        GROUP BY cu.CUSTOMER_CATEGORY
        ORDER BY NVL(SUM(mm.LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.cat,1,14),16) || '|' || RPAD(' ' || d.lib,40) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |');
    END LOOP;
    tbl_line('4,16,40,9,20,9');

    -- ---------------------------------------------------------
    -- TRS-206 : repartition par agence de booking
    -- ---------------------------------------------------------
    print_sub('TRS-206 : Repartition par agence de booking');
    tbl_line('4,10,9,20,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AGENCE',10) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',9) || '|');
    tbl_line('4,10,9,20,9');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.BRANCH, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT NVL(BRANCH,'(vide)') AS br, COUNT(*) AS nb, NVL(SUM(LCY_AMOUNT),0) AS encours,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) AS pct
        FROM mm GROUP BY BRANCH ORDER BY NVL(SUM(LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.br,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |');
    END LOOP;
    tbl_line('4,10,9,20,9');

    -- ---------------------------------------------------------
    -- TRS-207 : bandes de maturite residuelle (liquidite)
    -- ---------------------------------------------------------
    print_sub('TRS-207 : Echeancier par bande de maturite residuelle (contrats non echus)');
    tbl_line('4,18,9,20,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' BANDE',18) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',9) || '|');
    tbl_line('4,18,9,20,9');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND MATURITY_DATE > v_dt_fin),
        bandes AS (
            SELECT CASE
                     WHEN MATURITY_DATE - v_dt_fin <=   31 THEN '1. <= 1 mois'
                     WHEN MATURITY_DATE - v_dt_fin <=   92 THEN '2. 1 a 3 mois'
                     WHEN MATURITY_DATE - v_dt_fin <=  183 THEN '3. 3 a 6 mois'
                     WHEN MATURITY_DATE - v_dt_fin <=  366 THEN '4. 6 a 12 mois'
                     WHEN MATURITY_DATE - v_dt_fin <=  731 THEN '5. 1 a 2 ans'
                     WHEN MATURITY_DATE - v_dt_fin <= 1827 THEN '6. 2 a 5 ans'
                     ELSE                                       '7. > 5 ans'
                   END AS bande, LCY_AMOUNT
            FROM mm)
        SELECT bande, COUNT(*) AS nb, NVL(SUM(LCY_AMOUNT),0) AS encours,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) AS pct
        FROM bandes GROUP BY bande ORDER BY bande) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.bande,18) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |');
    END LOOP;
    tbl_line('4,18,9,20,9');

    -- ---------------------------------------------------------
    -- TRS-209 : distribution des taux par produit
    -- ---------------------------------------------------------
    print_sub('TRS-209 : Distribution des taux d''interet par produit');
    tbl_line('4,10,9,11,11,11,11,11,13');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' MIN %',11) || '|' || RPAD(' Q1 %',11) || '|' || RPAD(' MEDIANE %',11) || '|'
        || RPAD(' Q3 %',11) || '|' || RPAD(' MAX %',11) || '|' || RPAD(' TX MOY POND',13) || '|');
    tbl_line('4,10,9,11,11,11,11,11,13');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.PRODUCT, c.MAIN_COMP_RATE, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND MAIN_COMP_RATE IS NOT NULL)
        SELECT PRODUCT, COUNT(*) AS nb,
               MIN(MAIN_COMP_RATE) AS tmin,
               PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY MAIN_COMP_RATE) AS q1,
               PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY MAIN_COMP_RATE) AS med,
               PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY MAIN_COMP_RATE) AS q3,
               MAX(MAIN_COMP_RATE) AS tmax,
               ROUND(SUM(MAIN_COMP_RATE * NVL(LCY_AMOUNT,0)) / NULLIF(SUM(NVL(LCY_AMOUNT,0)),0), 4) AS tmoy
        FROM mm GROUP BY PRODUCT ORDER BY PRODUCT) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.tmin,'FM990D0000'),10) || ' |' || LPAD(TO_CHAR(d.q1,'FM990D0000'),10) || ' |'
            || LPAD(TO_CHAR(d.med,'FM990D0000'),10) || ' |' || LPAD(TO_CHAR(d.q3,'FM990D0000'),10) || ' |'
            || LPAD(TO_CHAR(d.tmax,'FM990D0000'),10) || ' |'
            || LPAD(TO_CHAR(NVL(d.tmoy,0),'FM990D0000'),12) || ' |');
    END LOOP;
    tbl_line('4,10,9,11,11,11,11,11,13');

    -- ---------------------------------------------------------
    -- TRS-210 : contrats a taux nul ou negatif
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE, c.MAIN_COMP,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(MAIN_COMP_RATE,0) <= 0);
    print_test('TRS-210 Contrats MM a taux d''interet nul ou negatif', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-211 : repartition par statut de contrat
    -- ---------------------------------------------------------
    print_sub('TRS-211 : Repartition par statut de contrat');
    tbl_line('4,14,18,18,9,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRACT_STAT',14) || '|'
        || RPAD(' DERIVED_STATUS',18) || '|' || RPAD(' USER_DEF_STATUS',18) || '|'
        || RPAD(' NB CTR',9) || '|' || RPAD(' ENCOURS (M XAF)',20) || '|');
    tbl_line('4,14,18,18,9,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_STATUS, c.CONTRACT_DERIVED_STATUS, c.USER_DEFINED_STATUS, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT NVL(CONTRACT_STATUS,'(vide)') st, NVL(CONTRACT_DERIVED_STATUS,'(vide)') ds,
               NVL(USER_DEFINED_STATUS,'(vide)') us, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) encours
        FROM mm GROUP BY CONTRACT_STATUS, CONTRACT_DERIVED_STATUS, USER_DEFINED_STATUS
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.st,14) || '|' || RPAD(' ' || SUBSTR(d.ds,1,16),18) || '|'
            || RPAD(' ' || SUBSTR(d.us,1,16),18) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.encours/1000000,'FM999G999G990D00') || ' M',19) || ' |');
    END LOOP;
    tbl_line('4,14,18,18,9,20');

    -- ---------------------------------------------------------
    -- TRS-212 : concentration par dealer / methode de negociation
    -- ---------------------------------------------------------
    print_sub('TRS-212 : Activite par dealer et methode de negociation');
    tbl_line('4,20,16,14,9,20,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DEALER',20) || '|' || RPAD(' DEALING_METH',16) || '|'
        || RPAD(' BROKER',14) || '|' || RPAD(' NB CTR',9) || '|' || RPAD(' NOMINAL (M XAF)',20) || '|'
        || RPAD(' % TOTAL',9) || '|');
    tbl_line('4,20,16,14,9,20,9');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.DEALER, c.DEALING_METHOD, c.BROKER_CODE, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1),
        agg AS (
            SELECT NVL(DEALER,'(vide)') dl, NVL(DEALING_METHOD,'-') dm, NVL(BROKER_CODE,'-') bk,
                   COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
                   ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) pct
            FROM mm GROUP BY DEALER, DEALING_METHOD, BROKER_CODE)
        SELECT * FROM (SELECT * FROM agg ORDER BY mt DESC) WHERE ROWNUM <= 25) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.dl,1,18),20) || '|' || RPAD(' ' || SUBSTR(d.dm,1,14),16) || '|'
            || RPAD(' ' || SUBSTR(d.bk,1,12),14) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),8) || ' |');
    END LOOP;
    tbl_line('4,20,16,14,9,20,9');

    -- ---------------------------------------------------------
    -- TRS-213 : evolution temporelle des mises en place
    -- ---------------------------------------------------------
    print_sub('TRS-213 : Evolution mensuelle des mises en place (sur la periode)');
    tbl_line('4,12,9,20,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' MOIS',12) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' NOMINAL (M XAF)',20) || '|' || RPAD(' TICKET MOY (M)',20) || '|');
    tbl_line('4,12,9,20,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.BOOKING_DATE, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND BOOKING_DATE BETWEEN v_dt_deb AND v_dt_fin)
        SELECT TO_CHAR(TRUNC(BOOKING_DATE,'MM'),'MM/YYYY') AS mois,
               TRUNC(BOOKING_DATE,'MM') AS tri,
               COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt, NVL(AVG(LCY_AMOUNT),0) moy
        FROM mm GROUP BY TRUNC(BOOKING_DATE,'MM') ORDER BY TRUNC(BOOKING_DATE,'MM')) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.mois,12) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.moy/1000000,'FM999G999G990D00') || ' M',19) || ' |');
    END LOOP;
    tbl_line('4,12,9,20,20');

    -- ---------------------------------------------------------
    -- TRS-215 : concentration du portefeuille
    -- ---------------------------------------------------------
    print_sub('TRS-215 : Concentration du portefeuille par contrepartie');
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1),
    parts AS (
        SELECT COUNTERPARTY,
               RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100 AS pct
        FROM   mm GROUP BY COUNTERPARTY)
    SELECT COUNT(*) INTO v_count FROM parts WHERE pct > p_seuil_concentr;
    print_test('TRS-215 Contreparties pesant plus de ' || TO_CHAR(p_seuil_concentr)
               || '% de l''encours MM', v_count, NULL, 'MAJEUR');

    -- Indice de Herfindahl-Hirschman
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1),
    parts AS (
        SELECT RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100 AS pct
        FROM   mm GROUP BY COUNTERPARTY)
    SELECT ROUND(SUM(POWER(pct, 2)), 0) INTO v_num1 FROM parts;
    print_kv('Indice de Herfindahl-Hirschman (contreparties)', TO_CHAR(NVL(v_num1,0)));
    print_note('Reperes : < 1500 portefeuille disperse ; 1500-2500 modere ; > 2500 concentre.');

    -- ---------------------------------------------------------
    -- TRS-217 : decote / prime a l'acquisition (titres)
    -- ---------------------------------------------------------
    SELECT COUNT(*), NVL(SUM(ORIGINAL_FACE_VALUE - AMOUNT), 0) INTO v_count, v_num1 FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.ORIGINAL_FACE_VALUE, c.AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1
        AND   ORIGINAL_FACE_VALUE IS NOT NULL AND ORIGINAL_FACE_VALUE <> 0
        AND   ABS(ORIGINAL_FACE_VALUE - AMOUNT) > 0.01);
    print_test('TRS-217 Contrats avec decote/prime (FACE_VALUE <> AMOUNT)', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        print_kv('  Decote nette cumulee (devise contrat)', TO_CHAR(v_num1, 'FM999G999G999G990'));
        print_note('  Rappel COBAC R-2003/03 : la decote/prime doit etre etalee sur la duree residuelle.');
    END IF;


    -- ---------------------------------------------------------
    -- TRS-202 : emplois / ressources et position nette
    -- ---------------------------------------------------------
    print_sub('TRS-202 : Emplois (placements) et ressources (emprunts)');
    tbl_line('4,26,12,22,12,14,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' NATURE',26) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' ENCOURS (M XAF)',22) || '|' || RPAD(' % TOTAL',12) || '|' || RPAD(' TX MOY POND',14) || '|'
        || RPAD(' DUREE MOY',14) || '|');
    tbl_line('4,26,12,22,12,14,14');
    v_row_num := 0;
    v_num1 := 0; v_num2 := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT, c.MAIN_COMP_RATE,
                       c.VALUE_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
        sens AS (
            SELECT CASE UPPER(NVL(pm.PRODUCT_TYPE,'?'))
                     WHEN 'P' THEN '1. EMPLOI (placement)'
                     WHEN 'B' THEN '2. RESSOURCE (emprunt)'
                     ELSE          '3. INDETERMINE'
                   END AS nature,
                   mm.LCY_AMOUNT, mm.MAIN_COMP_RATE, mm.VALUE_DATE, mm.MATURITY_DATE
            FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT)
        SELECT nature, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) pct,
               ROUND(SUM(NVL(MAIN_COMP_RATE,0) * NVL(LCY_AMOUNT,0))
                     / NULLIF(SUM(NVL(LCY_AMOUNT,0)),0), 4) tx,
               ROUND(AVG(MATURITY_DATE - VALUE_DATE),0) duree
        FROM   sens GROUP BY nature ORDER BY nature) LOOP
        v_row_num := v_row_num + 1;
        IF d.nature LIKE '1.%' THEN v_num1 := d.mt; END IF;
        IF d.nature LIKE '2.%' THEN v_num2 := d.mt; END IF;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.nature,26) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.tx,0),'FM990D0000'),13) || ' |'
            || LPAD(TO_CHAR(NVL(d.duree,0),'FM999G990') || ' j',13) || ' |');
    END LOOP;
    tbl_line('4,26,12,22,12,14,14');
    print_kv('Position nette MM (emplois - ressources, ' || p_ccy_locale || ')',
             TO_CHAR(v_num1 - v_num2, 'FMS999G999G999G999G990'));

    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1) m
        LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = m.PRODUCT
        WHERE UPPER(NVL(pm.PRODUCT_TYPE,'?')) NOT IN ('P','B'));
    print_test('TRS-202 Contrats dont le sens (emploi/ressource) est indetermine',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-208 : repartition par duree initiale
    -- ---------------------------------------------------------
    print_sub('TRS-208 : Repartition par duree initiale (a la mise en place)');
    tbl_line('4,20,12,22,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DUREE INITIALE',20) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' NOMINAL (M XAF)',22) || '|' || RPAD(' % TOTAL',12) || '|');
    tbl_line('4,20,12,22,12');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.LCY_AMOUNT, c.VALUE_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND VALUE_DATE IS NOT NULL AND MATURITY_DATE IS NOT NULL),
        bandes AS (
            SELECT CASE
                     WHEN MATURITY_DATE - VALUE_DATE <=    7 THEN '1. <= 1 semaine'
                     WHEN MATURITY_DATE - VALUE_DATE <=   31 THEN '2. 1 sem a 1 mois'
                     WHEN MATURITY_DATE - VALUE_DATE <=   92 THEN '3. 1 a 3 mois'
                     WHEN MATURITY_DATE - VALUE_DATE <=  183 THEN '4. 3 a 6 mois'
                     WHEN MATURITY_DATE - VALUE_DATE <=  366 THEN '5. 6 a 12 mois'
                     WHEN MATURITY_DATE - VALUE_DATE <= 1827 THEN '6. 1 a 5 ans'
                     ELSE                                         '7. > 5 ans'
                   END AS bande, LCY_AMOUNT
            FROM mm)
        SELECT bande, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) pct
        FROM bandes GROUP BY bande ORDER BY bande) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.bande,20) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |');
    END LOOP;
    tbl_line('4,20,12,22,12');

    -- ---------------------------------------------------------
    -- TRS-214 : ticket moyen et dispersion par produit
    -- ---------------------------------------------------------
    print_sub('TRS-214 : Ticket moyen et dispersion des montants par produit');
    tbl_line('4,10,10,20,20,20,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' NB CTR',10) || '|'
        || RPAD(' MIN (M XAF)',20) || '|' || RPAD(' MEDIANE (M XAF)',20) || '|' || RPAD(' MOYEN (M XAF)',20) || '|'
        || RPAD(' MAX (M XAF)',20) || '|');
    tbl_line('4,10,10,20,20,20,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT PRODUCT, COUNT(*) nb, MIN(LCY_AMOUNT) mini,
               PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY LCY_AMOUNT) med,
               AVG(LCY_AMOUNT) moy, MAX(LCY_AMOUNT) maxi
        FROM mm GROUP BY PRODUCT ORDER BY PRODUCT) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),9) || ' |'
            || LPAD(TO_CHAR(NVL(d.mini,0)/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(NVL(d.med,0)/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(NVL(d.moy,0)/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(NVL(d.maxi,0)/1000000,'FM999G999G990D00'),19) || ' |');
    END LOOP;
    tbl_line('4,10,10,20,20,20,20');

    -- Contrats hors normes : montant > 10 x la mediane du produit
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1),
    med AS (
        SELECT mm.*, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY LCY_AMOUNT)
                     OVER (PARTITION BY PRODUCT) AS mediane,
               COUNT(*) OVER (PARTITION BY PRODUCT) AS nb_prod
        FROM   mm)
    SELECT COUNT(*) INTO v_count
    FROM   med WHERE nb_prod >= 5 AND mediane > 0 AND LCY_AMOUNT > 10 * mediane;
    print_test('TRS-214 Contrats dont le montant depasse 10 x la mediane du produit',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-216 : identification des titres publics (BTA / OTA)
    -- ---------------------------------------------------------
    print_sub('TRS-216 : Classement par profil de titre public CEMAC (BTA / OTA)');
    tbl_line('4,30,12,22,12,16');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PROFIL',30) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' ENCOURS (M XAF)',22) || '|' || RPAD(' % TOTAL',12) || '|' || RPAD(' DUREE MOY',16) || '|');
    tbl_line('4,30,12,22,12,16');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                       c.VALUE_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND VALUE_DATE IS NOT NULL AND MATURITY_DATE IS NOT NULL
            AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
        prof AS (
            SELECT CASE
                     WHEN cu.CUSTOMER_NO IS NULL THEN '4. Contrepartie non identifiee'
                     WHEN (UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'GOVT%'
                        OR UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSE%')
                          AND mm.MATURITY_DATE - mm.VALUE_DATE <= 371  THEN '1. Profil BTA (<= 52 semaines)'
                     WHEN (UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'GOVT%'
                        OR UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSE%')
                                                                        THEN '2. Profil OTA (> 1 an)'
                     ELSE                                                    '3. Hors titres publics'
                   END AS profil, mm.LCY_AMOUNT,
                   mm.MATURITY_DATE - mm.VALUE_DATE AS duree
            FROM   mm LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY)
        SELECT profil, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) pct,
               ROUND(AVG(duree),0) duree_moy
        FROM prof GROUP BY profil ORDER BY profil) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.profil,30) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.duree_moy,0),'FM999G990') || ' j',15) || ' |');
    END LOOP;
    tbl_line('4,30,12,22,12,16');
    print_note('Classement indicatif fonde sur la categorie de contrepartie et la duree.');
    print_note('A valider avec la tresorerie : le referentiel FLEXCUBE ne porte pas l''ISIN.');


    -- =========================================================
    -- SECTION 3 : COHERENCE DES DONNEES CONTRACTUELLES
    -- =========================================================
    print_section('SECTION 3 : COHERENCE DES DONNEES CONTRACTUELLES');

    -- ---------------------------------------------------------
    -- TRS-301 : anomalies de versioning
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, VERSION_NO, EVENT_SEQ_NO, COUNT(*) nb
        FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module
        GROUP BY CONTRACT_REF_NO, VERSION_NO, EVENT_SEQ_NO
        HAVING COUNT(*) > 1);
    print_test('TRS-301 Triplets (contrat, version, event_seq) en doublon', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO
        FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module
        GROUP BY CONTRACT_REF_NO
        HAVING MAX(VERSION_NO) <> COUNT(DISTINCT VERSION_NO));
    print_test('TRS-301 Contrats a numerotation de version non continue', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-302 : contrats orphelins des tables filles
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_PREFERENCE p WHERE p.CONTRACT_REF_NO = mm.CONTRACT_REF_NO);
    print_test('TRS-302 Contrats sans ligne LDTB_CONTRACT_PREFERENCE', v_count, v_total, 'MAJEUR');

    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_ICCF_DETAILS i WHERE i.CONTRACT_REF_NO = mm.CONTRACT_REF_NO);
    print_test('TRS-302 Contrats sans ligne LDTB_CONTRACT_ICCF_DETAILS', v_count, v_total, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) mm
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_BALANCE b WHERE b.CONTRACT_REF_NO = mm.CONTRACT_REF_NO);
    print_test('TRS-302 Contrats sans ligne LDTB_CONTRACT_BALANCE', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-303 : ecarts avec la table miroir _FCC
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER_FCC WHERE MODULE = p_module) f
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_MASTER m
                      WHERE m.CONTRACT_REF_NO = f.CONTRACT_REF_NO AND m.MODULE = p_module);
    print_test('TRS-303 Contrats presents dans _FCC et absents de la table principale', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count
    FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_MASTER_FCC f
                      WHERE f.CONTRACT_REF_NO = m.CONTRACT_REF_NO AND f.MODULE = p_module);
    print_test('TRS-303 Contrats absents de la table miroir _FCC', v_count, NULL, 'MINEUR');

    WITH mp AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.MATURITY_DATE, c.CONTRACT_STATUS, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1),
    mf AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.MATURITY_DATE, c.CONTRACT_STATUS, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER_FCC c WHERE c.MODULE = p_module)
        WHERE rn = 1)
    SELECT COUNT(*) INTO v_count
    FROM   mp JOIN mf ON mf.CONTRACT_REF_NO = mp.CONTRACT_REF_NO
    WHERE  NVL(mp.AMOUNT,-1)          <> NVL(mf.AMOUNT,-1)
       OR  NVL(mp.MATURITY_DATE, DATE '1900-01-01') <> NVL(mf.MATURITY_DATE, DATE '1900-01-01')
       OR  NVL(mp.CONTRACT_STATUS,'#') <> NVL(mf.CONTRACT_STATUS,'#')
       OR  NVL(mp.MAIN_COMP_RATE,-1)   <> NVL(mf.MAIN_COMP_RATE,-1);
    print_test('TRS-303 Contrats divergents entre table principale et _FCC', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-304 : chronologie des dates cles
    -- ---------------------------------------------------------
    print_sub('TRS-304 : Chronologie des dates cles du contrat');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.TRADE_DATE, c.BOOKING_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND TRADE_DATE IS NOT NULL AND BOOKING_DATE IS NOT NULL
        AND   TRADE_DATE > BOOKING_DATE);
    print_test('TRS-304 Contrats ou TRADE_DATE > BOOKING_DATE', v_count, v_total, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.VALUE_DATE, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND VALUE_DATE IS NOT NULL AND MATURITY_DATE IS NOT NULL
        AND   VALUE_DATE >= MATURITY_DATE);
    print_test('TRS-304 Contrats ou VALUE_DATE >= MATURITY_DATE', v_count, v_total, 'CRITIQUE');
    IF v_count > 0 THEN
        tbl_line('4,22,28,8,6,18,12,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' PROD',8) || '|' || RPAD(' CCY',6) || '|' || RPAD(' MONTANT (M)',18) || '|'
            || RPAD(' VALUE_DT',12) || '|' || RPAD(' MATUR_DT',12) || '|');
        tbl_line('4,22,28,8,6,18,12,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT m.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                   m.PRODUCT, m.CURRENCY, m.LCY_AMOUNT, m.VALUE_DATE, m.MATURITY_DATE
            FROM (SELECT * FROM (
                     SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.LCY_AMOUNT, c.COUNTERPARTY,
                            c.VALUE_DATE, c.MATURITY_DATE,
                            ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                 ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                     FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                  WHERE rn = 1) m
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
            WHERE m.VALUE_DATE IS NOT NULL AND m.MATURITY_DATE IS NOT NULL
            AND   m.VALUE_DATE >= m.MATURITY_DATE
            ORDER BY m.LCY_AMOUNT DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || d.PRODUCT,8) || '|' || RPAD(' ' || d.CURRENCY,6) || '|'
                || LPAD(TO_CHAR(NVL(d.LCY_AMOUNT,0)/1000000,'FM999G999G990D00'),17) || ' |'
                || RPAD(' ' || TO_CHAR(d.VALUE_DATE,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.MATURITY_DATE,'DD/MM/YYYY'),12) || '|');
        END LOOP;
        tbl_line('4,22,28,8,6,18,12,12');
    END IF;

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.ORIGINAL_START_DATE, c.VALUE_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND ORIGINAL_START_DATE IS NOT NULL AND VALUE_DATE IS NOT NULL
        AND   ORIGINAL_START_DATE > VALUE_DATE);
    print_test('TRS-304 Contrats ou ORIGINAL_START_DATE > VALUE_DATE', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-305 : dates aberrantes
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.BOOKING_DATE, c.VALUE_DATE, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1
        AND  (BOOKING_DATE  < DATE '1990-01-01' OR MATURITY_DATE < DATE '1990-01-01'
           OR MATURITY_DATE > ADD_MONTHS(v_dt_fin, 12 * 30)
           OR BOOKING_DATE IS NULL OR VALUE_DATE IS NULL));
    print_test('TRS-305 Contrats a dates aberrantes ou obligatoires manquantes', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-306 : contrats a date de valeur future deja comptabilises
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.VALUE_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND VALUE_DATE > v_dt_fin) m
        WHERE EXISTS (SELECT 1 FROM ACTB_HISTORY h
                      WHERE h.TRN_REF_NO = m.CONTRACT_REF_NO AND h.MODULE = p_module));
    print_test('TRS-306 Contrats a date de valeur future deja comptabilises', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-307 : coherence TENOR / duree calendaire
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.TENOR, c.VALUE_DATE, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND TENOR IS NOT NULL AND TENOR > 0
        AND   VALUE_DATE IS NOT NULL AND MATURITY_DATE IS NOT NULL
        AND   ABS(TENOR - (MATURITY_DATE - VALUE_DATE)) > 1);
    print_test('TRS-307 Contrats ou TENOR <> (MATURITY_DATE - VALUE_DATE)', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-308 / TRS-309 / TRS-310 : contreparties
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (COUNTERPARTY IS NULL OR TRIM(COUNTERPARTY) IS NULL));
    print_test('TRS-308 Contrats sans contrepartie renseignee', v_count, v_total, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND COUNTERPARTY IS NOT NULL AND TRIM(COUNTERPARTY) IS NOT NULL) m
        WHERE NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER cu WHERE cu.CUSTOMER_NO = m.COUNTERPARTY));
    print_test('TRS-309 Contrats dont la contrepartie est absente de STTM_CUSTOMER', v_count, v_total, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE NVL(cu.FROZEN,'N') = 'Y' OR NVL(cu.DECEASED,'N') = 'Y'
       OR NVL(cu.WHEREABOUTS_UNKNOWN,'N') = 'Y' OR NVL(cu.RECORD_STAT,'O') <> 'O';
    print_test('TRS-310 Contrats sur contrepartie gelee / decedee / fermee', v_count, v_total, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-311 / TRS-312 : devise et montant
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.CURRENCY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (CURRENCY IS NULL OR TRIM(CURRENCY) IS NULL));
    print_test('TRS-311 Contrats sans devise renseignee', v_count, v_total, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (NVL(AMOUNT,0) <= 0 OR NVL(LCY_AMOUNT,0) <= 0));
    print_test('TRS-312 Contrats a montant nul ou negatif', v_count, v_total, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-313 : coherence du taux de change implicite
    -- ---------------------------------------------------------
    print_sub('TRS-313 : Coherence du taux de change implicite (contrats en devises)');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO,
               m.LCY_AMOUNT / NULLIF(m.AMOUNT,0) AS taux_implicite,
               (SELECT MAX(r.MID_RATE) KEEP (DENSE_RANK LAST ORDER BY r.RATE_DATE)
                FROM   CYTB_RATES_HISTORY r
                WHERE  r.CCY1 = m.CURRENCY AND r.CCY2 = p_ccy_locale
                AND    r.RATE_DATE <= m.VALUE_DATE) AS taux_ref
        FROM (SELECT * FROM (
                 SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.AMOUNT, c.LCY_AMOUNT, c.VALUE_DATE,
                        ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                             ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                 FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
              WHERE rn = 1 AND CURRENCY <> p_ccy_locale AND NVL(AMOUNT,0) <> 0) m)
    WHERE taux_ref IS NOT NULL AND taux_ref <> 0
    AND   ABS(taux_implicite - taux_ref) / NULLIF(taux_ref,0) > p_tol_change_pct;
    print_test('TRS-313 Contrats en devise a taux de change hors reference CYTB', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        tbl_line('4,22,8,20,20,16,16,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CCY',8) || '|'
            || RPAD(' MONTANT DEVISE',20) || '|' || RPAD(' CONTRE-VALEUR',20) || '|'
            || RPAD(' TX IMPLICITE',16) || '|' || RPAD(' TX REFERENCE',16) || '|' || RPAD(' ECART %',12) || '|');
        tbl_line('4,22,8,20,20,16,16,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT CONTRACT_REF_NO, CURRENCY, AMOUNT, LCY_AMOUNT, taux_implicite, taux_ref,
                   ROUND((taux_implicite - taux_ref) / NULLIF(taux_ref,0) * 100, 2) AS ecart_pct
            FROM (
                SELECT m.CONTRACT_REF_NO, m.CURRENCY, m.AMOUNT, m.LCY_AMOUNT,
                       m.LCY_AMOUNT / NULLIF(m.AMOUNT,0) AS taux_implicite,
                       (SELECT MAX(r.MID_RATE) KEEP (DENSE_RANK LAST ORDER BY r.RATE_DATE)
                        FROM   CYTB_RATES_HISTORY r
                        WHERE  r.CCY1 = m.CURRENCY AND r.CCY2 = p_ccy_locale
                        AND    r.RATE_DATE <= m.VALUE_DATE) AS taux_ref
                FROM (SELECT * FROM (
                         SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.AMOUNT, c.LCY_AMOUNT, c.VALUE_DATE,
                                ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                     ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                         FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                      WHERE rn = 1 AND CURRENCY <> p_ccy_locale AND NVL(AMOUNT,0) <> 0) m)
            WHERE taux_ref IS NOT NULL AND taux_ref <> 0
            AND   ABS(taux_implicite - taux_ref) / NULLIF(taux_ref,0) > p_tol_change_pct
            ORDER BY ABS(LCY_AMOUNT) DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.CURRENCY,8) || '|'
                || LPAD(TO_CHAR(d.AMOUNT,'FM999G999G999G990'),19) || ' |'
                || LPAD(TO_CHAR(d.LCY_AMOUNT,'FM999G999G999G990'),19) || ' |'
                || LPAD(TO_CHAR(d.taux_implicite,'FM999G990D0000'),15) || ' |'
                || LPAD(TO_CHAR(d.taux_ref,'FM999G990D0000'),15) || ' |'
                || LPAD(TO_CHAR(d.ecart_pct,'FM9990D00') || ' %',11) || ' |');
        END LOOP;
        tbl_line('4,22,8,20,20,16,16,12');
    END IF;

    -- TRS-314 : devise etrangere avec contre-valeur identique
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.AMOUNT, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND CURRENCY <> p_ccy_locale AND AMOUNT = LCY_AMOUNT AND NVL(AMOUNT,0) <> 0);
    print_test('TRS-314 Contrats en devise dont LCY_AMOUNT = AMOUNT (taux = 1)', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-315 : statuts de sous-systemes non aboutis
    -- ---------------------------------------------------------
    print_sub('TRS-315 : Statuts des sous-systemes (contrats non echus)');
    tbl_line('4,14,14,14,14,14,9,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' ICCF_STATUS',14) || '|' || RPAD(' SETTLE_STAT',14) || '|'
        || RPAD(' TAX_STATUS',14) || '|' || RPAD(' BROKER_STAT',14) || '|' || RPAD(' CHARGE_STAT',14) || '|'
        || RPAD(' NB CTR',9) || '|' || RPAD(' ENCOURS (M XAF)',20) || '|');
    tbl_line('4,14,14,14,14,14,9,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.ICCF_STATUS, c.SETTLEMENT_STATUS, c.TAX_STATUS,
                       c.BROKERAGE_STATUS, c.CHARGE_STATUS, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin))
        SELECT NVL(ICCF_STATUS,'(vide)') a, NVL(SETTLEMENT_STATUS,'(vide)') b, NVL(TAX_STATUS,'(vide)') c,
               NVL(BROKERAGE_STATUS,'(vide)') d, NVL(CHARGE_STATUS,'(vide)') e,
               COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt
        FROM mm GROUP BY ICCF_STATUS, SETTLEMENT_STATUS, TAX_STATUS, BROKERAGE_STATUS, CHARGE_STATUS
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.a,14) || '|' || RPAD(' ' || d.b,14) || '|' || RPAD(' ' || d.c,14) || '|'
            || RPAD(' ' || d.d,14) || '|' || RPAD(' ' || d.e,14) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |');
    END LOOP;
    tbl_line('4,14,14,14,14,14,9,20');

    -- ---------------------------------------------------------
    -- TRS-316 : contrats rejetes toujours actifs
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.REJ_REASON, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND REJ_REASON IS NOT NULL AND TRIM(REJ_REASON) IS NOT NULL);
    print_test('TRS-316 Contrats portant un motif de rejet (REJ_REASON)', v_count, v_total, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-317 / TRS-318 / TRS-328 : completude des attributs de gestion
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.DEALER,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (DEALER IS NULL OR TRIM(DEALER) IS NULL));
    print_test('TRS-317 Contrats sans DEALER renseigne', v_count, v_total, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.DFLT_SETTLE_AC,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (DFLT_SETTLE_AC IS NULL OR TRIM(DFLT_SETTLE_AC) IS NULL));
    print_test('TRS-318 Contrats sans compte de reglement par defaut', v_count, v_total, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.USER_REF_NO,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (USER_REF_NO IS NULL OR TRIM(USER_REF_NO) IS NULL));
    print_test('TRS-328 Contrats sans reference utilisateur (USER_REF_NO)', v_count, v_total, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-319 / TRS-320 : lignes de credit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.CREDIT_LINE, c.VALUE_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND CREDIT_LINE IS NOT NULL AND TRIM(CREDIT_LINE) IS NOT NULL) m
        WHERE NOT EXISTS (SELECT 1 FROM GETM_FACILITY f WHERE f.LINE_CODE = m.CREDIT_LINE));
    print_test('TRS-319 Contrats referencant une ligne absente de GETM_FACILITY', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.CREDIT_LINE, c.VALUE_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND CREDIT_LINE IS NOT NULL AND TRIM(CREDIT_LINE) IS NOT NULL) m
        WHERE (SELECT MAX(f.LINE_EXPIRY_DATE) FROM GETM_FACILITY f WHERE f.LINE_CODE = m.CREDIT_LINE)
              < m.VALUE_DATE);
    print_test('TRS-319 Contrats mis en place sur une ligne expiree', v_count, NULL, 'MAJEUR');

    WITH enc AS (
        SELECT m.CREDIT_LINE, SUM(m.LCY_AMOUNT) AS encours
        FROM (SELECT * FROM (
                 SELECT c.CONTRACT_REF_NO, c.CREDIT_LINE, c.LCY_AMOUNT, c.MATURITY_DATE,
                        ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                             ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                 FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
              WHERE rn = 1 AND CREDIT_LINE IS NOT NULL AND TRIM(CREDIT_LINE) IS NOT NULL
              AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
        GROUP BY m.CREDIT_LINE),
    lim AS (
        SELECT f.LINE_CODE, MAX(f.LIMIT_AMOUNT) AS limite
        FROM   GETM_FACILITY f GROUP BY f.LINE_CODE)
    SELECT COUNT(*) INTO v_count
    FROM   enc JOIN lim ON lim.LINE_CODE = enc.CREDIT_LINE
    WHERE  enc.encours > NVL(lim.limite, 0);
    print_test('TRS-320 Lignes de credit en depassement sur encours MM', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-322 : doublons potentiels
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.CURRENCY, c.AMOUNT,
                   c.VALUE_DATE, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1),
    grp AS (
        SELECT COUNTERPARTY, CURRENCY, AMOUNT, VALUE_DATE, MATURITY_DATE
        FROM   mm
        GROUP BY COUNTERPARTY, CURRENCY, AMOUNT, VALUE_DATE, MATURITY_DATE
        HAVING COUNT(*) > 1)
    SELECT COUNT(*) INTO v_count FROM grp;
    print_test('TRS-322 Groupes de contrats potentiellement en doublon', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        tbl_line('4,28,8,20,12,12,9,40');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTREPARTIE',28) || '|' || RPAD(' CCY',8) || '|'
            || RPAD(' MONTANT',20) || '|' || RPAD(' VALUE_DT',12) || '|' || RPAD(' MATUR_DT',12) || '|'
            || RPAD(' NB',9) || '|' || RPAD(' REFERENCES',40) || '|');
        tbl_line('4,28,8,20,12,12,9,40');
        v_row_num := 0;
        FOR d IN (
            WITH mm AS (
                SELECT * FROM (
                    SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.CURRENCY, c.AMOUNT,
                           c.VALUE_DATE, c.MATURITY_DATE,
                           ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                    FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                WHERE rn = 1),
            dbl AS (
                SELECT NVL(SUBSTR(MAX(cu.CUSTOMER_NAME1),1,26),MAX(mm.COUNTERPARTY)) nom,
                       mm.CURRENCY, mm.AMOUNT, mm.VALUE_DATE, mm.MATURITY_DATE,
                       COUNT(*) nb,
                       SUBSTR(LISTAGG(mm.CONTRACT_REF_NO, ' ')
                              WITHIN GROUP (ORDER BY mm.CONTRACT_REF_NO),1,38) refs
                FROM   mm LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY
                GROUP BY mm.COUNTERPARTY, mm.CURRENCY, mm.AMOUNT, mm.VALUE_DATE, mm.MATURITY_DATE
                HAVING COUNT(*) > 1)
            SELECT * FROM (SELECT * FROM dbl ORDER BY AMOUNT DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.nom,28) || '|' || RPAD(' ' || d.CURRENCY,8) || '|'
                || LPAD(TO_CHAR(d.AMOUNT,'FM999G999G999G990'),19) || ' |'
                || RPAD(' ' || TO_CHAR(d.VALUE_DATE,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.MATURITY_DATE,'DD/MM/YYYY'),12) || '|'
                || LPAD(TO_CHAR(d.nb),8) || ' |' || RPAD(' ' || d.refs,40) || '|');
        END LOOP;
        tbl_line('4,28,8,20,12,12,9,40');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-323 / TRS-324 / TRS-325 : confirmations SWIFT
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1) m
        JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY AND cu.CUSTOMER_TYPE = 'B'
        WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_SWIFT_MESSAGE s
                          WHERE s.CONTRACT_REF_NO = m.CONTRACT_REF_NO));
    print_test('TRS-323 Contrats sur contrepartie bancaire sans message SWIFT', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN (SELECT CONTRACT_REF_NO, MAX(INTEREST_RATE) KEEP (DENSE_RANK LAST ORDER BY EVENT_SEQ_NO) tx
          FROM LDTB_CONTRACT_SWIFT_MESSAGE GROUP BY CONTRACT_REF_NO) s
      ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE s.tx IS NOT NULL AND m.MAIN_COMP_RATE IS NOT NULL
    AND   ABS(s.tx - m.MAIN_COMP_RATE) > 0.0001;
    print_test('TRS-324 Ecart entre taux du contrat et taux de la confirmation SWIFT', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN (SELECT CONTRACT_REF_NO, MAX(CONTRACT_BALANCE) KEEP (DENSE_RANK LAST ORDER BY EVENT_SEQ_NO) bal
          FROM LDTB_CONTRACT_SWIFT_MESSAGE GROUP BY CONTRACT_REF_NO) s
      ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE s.bal IS NOT NULL AND m.AMOUNT IS NOT NULL AND ABS(s.bal - m.AMOUNT) > 1;
    print_test('TRS-325 Ecart entre montant du contrat et solde de la confirmation SWIFT', v_count, NULL, 'MAJEUR');


    -- ---------------------------------------------------------
    -- TRS-321 / TRS-326 / TRS-327 : origines et natures particulieres
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN INTERFACE_REF_NO IS NOT NULL AND TRIM(INTERFACE_REF_NO) IS NOT NULL
                    THEN 1 ELSE 0 END),
           SUM(CASE WHEN NVL(MULTIPLE_CIF,'N') = 'Y' THEN 1 ELSE 0 END),
           COUNT(*)
    INTO   v_count, v_count2, v_total
    FROM  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.INTERFACE_REF_NO, c.MULTIPLE_CIF,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1);
    print_kv('TRS-321 Contrats MM issus d''une interface externe', TO_CHAR(v_count));
    print_test('TRS-326 Contrats MM a contreparties multiples (MULTIPLE_CIF = Y)',
               v_count2, v_total, 'MINEUR');

    SELECT COUNT(*) INTO v_count
    FROM  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m
    JOIN   LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = m.PRODUCT
    WHERE  NVL(pm.INTRA_DAY_DEAL,'N') = 'Y';
    print_kv('TRS-327 Contrats MM portes par un produit intra-day', TO_CHAR(v_count));

    -- Contrats d'interface a attributs incomplets
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.INTERFACE_REF_NO, c.DEALER, c.USER_REF_NO,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND INTERFACE_REF_NO IS NOT NULL AND TRIM(INTERFACE_REF_NO) IS NOT NULL
        AND  (DEALER IS NULL OR TRIM(DEALER) IS NULL
              OR USER_REF_NO IS NULL OR TRIM(USER_REF_NO) IS NULL));
    print_test('TRS-321 Contrats d''interface a attributs de gestion incomplets',
               v_count, NULL, 'MINEUR');


    -- =========================================================
    -- SECTION 4 : COMPOSANTES ET ECHEANCIERS
    -- =========================================================
    print_section('SECTION 4 : COMPOSANTES ET ECHEANCIERS');

    -- ---------------------------------------------------------
    -- TRS-401 : inventaire des composantes
    -- ---------------------------------------------------------
    print_sub('TRS-401 : Inventaire des composantes du portefeuille MM');
    tbl_line('4,20,8,10,10,9,22,22');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPOSANTE',20) || '|' || RPAD(' CCY',8) || '|'
        || RPAD(' ACCR_REQ',10) || '|' || RPAD(' PAY_METH',10) || '|' || RPAD(' NB CTR',9) || '|'
        || RPAD(' ACCRUAL A DATE',22) || '|' || RPAD(' TOTAL LIQUIDE',22) || '|');
    tbl_line('4,20,8,10,10,9,22,22');
    v_row_num := 0;
    FOR d IN (
        SELECT i.COMPONENT, NVL(i.COMPONENT_CURRENCY,'-') ccy, NVL(i.ACCRUAL_REQUIRED,'-') ar,
               NVL(i.PAYMENT_METHOD,'-') pm, COUNT(*) nb,
               NVL(SUM(i.TILL_DATE_ACCRUAL),0) acc, NVL(SUM(i.TOTAL_AMOUNT_LIQUIDATED),0) liq
        FROM   LDTB_CONTRACT_ICCF_DETAILS i
        WHERE  i.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY i.COMPONENT, i.COMPONENT_CURRENCY, i.ACCRUAL_REQUIRED, i.PAYMENT_METHOD
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.COMPONENT,1,18),20) || '|' || RPAD(' ' || d.ccy,8) || '|'
            || RPAD(' ' || d.ar,10) || '|' || RPAD(' ' || d.pm,10) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.acc,'FM999G999G999G990'),21) || ' |'
            || LPAD(TO_CHAR(d.liq,'FM999G999G999G990'),21) || ' |');
    END LOOP;
    tbl_line('4,20,8,10,10,9,22,22');

    -- ---------------------------------------------------------
    -- TRS-402 : contrats porteurs d'interet sans composante
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND NVL(MAIN_COMP_RATE,0) > 0) m
        WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_ICCF_DETAILS i
                          WHERE i.CONTRACT_REF_NO = m.CONTRACT_REF_NO));
    print_test('TRS-402 Contrats a taux > 0 sans composante d''interet', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-403 : devise de composante differente de celle du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.CURRENCY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN LDTB_CONTRACT_ICCF_DETAILS i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE i.COMPONENT_CURRENCY IS NOT NULL AND TRIM(i.COMPONENT_CURRENCY) IS NOT NULL
    AND   TRIM(i.COMPONENT_CURRENCY) <> TRIM(m.CURRENCY);
    print_test('TRS-403 Composantes en devise differente du contrat', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-404 : accrual non requis sur contrat non echu
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)
        AND   NVL(MAIN_COMP_RATE,0) > 0) m
    JOIN LDTB_CONTRACT_ICCF_DETAILS i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(i.ACCRUAL_REQUIRED,'N') <> 'Y';
    print_test('TRS-404 Composantes sans accrual requis sur contrat non echu', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-405 : contrats actifs sans echeancier
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
        WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_SCHEDULES s
                          WHERE s.CONTRACT_REF_NO = m.CONTRACT_REF_NO));
    print_test('TRS-405 Contrats non echus sans echeancier', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-406 : somme des echeances de principal <> montant du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO, m.AMOUNT, s.tot
        FROM (SELECT * FROM (
                 SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.MAIN_COMP,
                        ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                             ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                 FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
              WHERE rn = 1) m
        JOIN (SELECT sc.CONTRACT_REF_NO, SUM(sc.AMOUNT) tot
              FROM   LDTB_CONTRACT_SCHEDULES sc
              WHERE  UPPER(sc.COMPONENT) LIKE 'PRINCIP%'
              AND    sc.VERSION_NO = (SELECT MAX(s2.VERSION_NO) FROM LDTB_CONTRACT_SCHEDULES s2
                                      WHERE s2.CONTRACT_REF_NO = sc.CONTRACT_REF_NO)
              GROUP BY sc.CONTRACT_REF_NO) s ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
        WHERE ABS(NVL(s.tot,0) - NVL(m.AMOUNT,0)) > 1);
    print_test('TRS-406 Echeanciers de principal <> montant du contrat', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-407 / TRS-408 : echeances hors bornes du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.VALUE_DATE, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN LDTB_CONTRACT_SCHEDULES s ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE s.START_DATE > m.MATURITY_DATE;
    print_test('TRS-407 Echeances posterieures a la maturite du contrat', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.VALUE_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN LDTB_CONTRACT_SCHEDULES s ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE s.START_DATE < m.VALUE_DATE;
    print_test('TRS-408 Echeances anterieures a la date de valeur du contrat', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-409 / TRS-410 : qualite de l'echeancier
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_SCHEDULES s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(s.AMOUNT,0) <= 0;
    print_test('TRS-409 Echeances a montant nul ou negatif', v_count, NULL, 'MAJEUR');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_SCHEDULES s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (s.FREQUENCY IS NULL OR TRIM(s.FREQUENCY) IS NULL OR NVL(s.FREQUENCY_UNIT,0) <= 0);
    print_test('TRS-410 Echeances a frequence non renseignee ou aberrante', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-412 : echeanciers definis par l'utilisateur
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_PREFERENCE p
    WHERE  p.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(p.USER_DEFINED_SCHED,'N') = 'Y';
    print_test('TRS-412 Contrats a echeancier defini par l''utilisateur', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-413 : ecarts echeancier / table miroir
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT s.CONTRACT_REF_NO, s.COMPONENT, s.START_DATE
        FROM   LDTB_CONTRACT_SCHEDULES s
        WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        MINUS
        SELECT f.CONTRACT_REF_NO, f.COMPONENT, f.START_DATE
        FROM   LDTB_CONTRACT_SCHEDULES_FCC f);
    print_test('TRS-413 Echeances presentes dans la table principale et absentes de _FCC', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-415 : traitement des jours feries
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_PREFERENCE p
    WHERE  p.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(p.IGNORE_HOLIDAYS,'N') = 'Y';
    print_test('TRS-415 Contrats ignorant les jours feries dans l''echeancier', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-416 : parametres d'arrondi
    -- ---------------------------------------------------------
    print_sub('TRS-416 : Parametres d''arrondi appliques aux contrats MM');
    tbl_line('4,12,12,12,12,9');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' ROUND_REQD',12) || '|' || RPAD(' ROUND_RULE',12) || '|'
        || RPAD(' DECIMALS',12) || '|' || RPAD(' ROUND_UNIT',12) || '|' || RPAD(' NB CTR',9) || '|');
    tbl_line('4,12,12,12,12,9');
    v_row_num := 0;
    FOR d IN (SELECT NVL(p.ROUNDING_REQD,'-') rr, NVL(p.CCY_ROUND_RULE,'-') cr,
                     NVL(TO_CHAR(p.CCY_DECIMALS),'-') cd, NVL(TO_CHAR(p.CCY_ROUND_UNIT),'-') cu,
                     COUNT(*) nb
              FROM   LDTB_CONTRACT_PREFERENCE p
              WHERE  p.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY p.ROUNDING_REQD, p.CCY_ROUND_RULE, p.CCY_DECIMALS, p.CCY_ROUND_UNIT
              ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.rr,12) || '|' || RPAD(' ' || d.cr,12) || '|' || RPAD(' ' || d.cd,12) || '|'
            || RPAD(' ' || d.cu,12) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |');
    END LOOP;
    tbl_line('4,12,12,12,12,9');

    -- ---------------------------------------------------------
    -- TRS-420 : encours incoherent avec le montant du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN LDTB_CONTRACT_BALANCE b ON b.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(b.PRINCIPAL_OUTSTANDING_BAL,0) > NVL(m.AMOUNT,0) + 1;
    print_test('TRS-420 Encours de principal superieur au montant du contrat', v_count, NULL, 'CRITIQUE');


    -- ---------------------------------------------------------
    -- TRS-411 : ecart echeancier contractuel / echeancier par defaut du produit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT s.CONTRACT_REF_NO, s.COMPONENT
        FROM   LDTB_CONTRACT_SCHEDULES s
        JOIN  (SELECT * FROM (
                  SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                         ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                              ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                  FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
               WHERE rn = 1) m ON m.CONTRACT_REF_NO = s.CONTRACT_REF_NO
        JOIN   LDTM_PRODUCT_DFLT_SCHEDULES ds
          ON   ds.PRODUCT = m.PRODUCT AND ds.COMPONENT = s.COMPONENT
        WHERE  NVL(s.FREQUENCY,'#') <> NVL(ds.FREQUENCY,'#')
           OR  NVL(s.FREQUENCY_UNIT,-1) <> NVL(ds.FREQUENCY_UNIT,-1)
        GROUP BY s.CONTRACT_REF_NO, s.COMPONENT);
    print_test('TRS-411 Echeanciers derogeant au parametrage par defaut du produit',
               v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-414 : coherence type d'amortissement / profil d'echeancier
    -- ---------------------------------------------------------
    print_sub('TRS-414 : Types d''amortissement rencontres');
    tbl_line('4,20,20,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AMORT_TYPE',20) || '|' || RPAD(' SCHEDULE_TYPE',20) || '|'
        || RPAD(' NB CTR',12) || '|' || RPAD(' NB ECHEANCES',12) || '|');
    tbl_line('4,20,20,12,12');
    v_row_num := 0;
    FOR d IN (
        WITH prefs AS (
            SELECT p.CONTRACT_REF_NO,
                   NVL(p.AMORTISATION_TYPE,'(vide)')      AS amort,
                   NVL(p.CONTRACT_SCHEDULE_TYPE,'(vide)') AS sched
            FROM   LDTB_CONTRACT_PREFERENCE p
            WHERE  p.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO
                                         FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module)),
        nb_sch AS (
            SELECT CONTRACT_REF_NO, COUNT(*) AS nb_ech
            FROM   LDTB_CONTRACT_SCHEDULES
            GROUP BY CONTRACT_REF_NO)
        SELECT prefs.amort, prefs.sched,
               COUNT(DISTINCT prefs.CONTRACT_REF_NO) AS nb,
               NVL(SUM(nb_sch.nb_ech),0)             AS nbe
        FROM   prefs LEFT JOIN nb_sch ON nb_sch.CONTRACT_REF_NO = prefs.CONTRACT_REF_NO
        GROUP BY prefs.amort, prefs.sched
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.amort,20) || '|' || RPAD(' ' || d.sched,20) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.nbe,'FM999G999G990'),11) || ' |');
    END LOOP;
    tbl_line('4,20,20,12,12');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_PREFERENCE p
    WHERE  p.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    p.AMORTISATION_TYPE IS NOT NULL AND TRIM(p.AMORTISATION_TYPE) IS NOT NULL
    AND    NOT EXISTS (SELECT 1
                       FROM   LDTB_CONTRACT_SCHEDULES s
                       WHERE  s.CONTRACT_REF_NO = p.CONTRACT_REF_NO
                       AND    UPPER(s.COMPONENT) LIKE 'PRINCIP%'
                       GROUP BY s.CONTRACT_REF_NO
                       HAVING COUNT(*) > 1);
    print_test('TRS-414 Contrats amortissables sans echeancier de principal multiple',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-417 : periodes maximales d'interet et de revision
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_PREFERENCE p
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.VALUE_DATE, c.MATURITY_DATE,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = p.CONTRACT_REF_NO
    WHERE  NVL(p.MAX_INT_PAY_PERIOD,0) > 0
    AND   (m.MATURITY_DATE - m.VALUE_DATE) > p.MAX_INT_PAY_PERIOD;
    print_test('TRS-417 Contrats depassant la periode maximale de paiement d''interet',
               v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-418 / TRS-419 : contrats a taux revisable
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE_CODE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MAIN_COMP_RATE_CODE IS NOT NULL
        AND   TRIM(MAIN_COMP_RATE_CODE) IS NOT NULL);
    print_kv('TRS-418 Contrats MM a taux revisable (RATE_CODE renseigne)', TO_CHAR(v_count));

    IF v_count > 0 THEN
        SELECT COUNT(*) INTO v_count2 FROM (
            SELECT m.CONTRACT_REF_NO FROM (
                SELECT * FROM (
                    SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE_CODE,
                           ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                    FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                WHERE rn = 1 AND MAIN_COMP_RATE_CODE IS NOT NULL
                AND   TRIM(MAIN_COMP_RATE_CODE) IS NOT NULL) m
            WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_SCHEDULES s
                              WHERE s.CONTRACT_REF_NO = m.CONTRACT_REF_NO
                              AND   s.SCHEDULE_TYPE = 'R'));
        print_test('TRS-418 Contrats a taux revisable sans echeancier de revision',
                   v_count2, v_count, 'MAJEUR');

        SELECT COUNT(*) INTO v_count2 FROM (
            SELECT m.CONTRACT_REF_NO FROM (
                SELECT * FROM (
                    SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE_CODE, c.MAIN_COMP,
                           ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                    FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                WHERE rn = 1 AND MAIN_COMP_RATE_CODE IS NOT NULL
                AND   TRIM(MAIN_COMP_RATE_CODE) IS NOT NULL) m
            WHERE NOT EXISTS (SELECT 1
                              FROM   LDTB_CONTRACT_ICCF_CALC i
                              WHERE  i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
                              AND    i.COMPONENT = m.MAIN_COMP
                              GROUP BY i.CONTRACT_REF_NO, i.COMPONENT
                              HAVING COUNT(DISTINCT i.RATE) > 1));
        print_test('TRS-419 Contrats a taux revisable n''ayant jamais ete revises',
                   v_count2, v_count, 'MAJEUR');
    ELSE
        print_test('TRS-418 Contrats a taux revisable sans echeancier de revision', 0, NULL, 'MAJEUR');
        print_test('TRS-419 Contrats a taux revisable n''ayant jamais ete revises', 0, NULL, 'MAJEUR');
    END IF;


    -- =========================================================
    -- SECTION 5 : RECALCUL INDEPENDANT DES INTERETS
    -- =========================================================
    print_section('SECTION 5 : RECALCUL INDEPENDANT DES INTERETS');
    print_note('Methode : pour chaque ligne de LDTB_CONTRACT_ICCF_CALC, l''interet est recalcule');
    print_note('          selon les trois conventions usuelles (base 360, 365 et 366 jours) :');
    print_note('             Interet = BASIS_AMOUNT x (RATE / 100) x (NO_OF_DAYS / BASE)');
    print_note('          La base retenue est celle qui reproduit le mieux CALCULATED_AMOUNT.');
    print_note('          Si aucune base ne le reproduit dans la tolerance, la ligne est en ECART.');

    -- ---------------------------------------------------------
    -- TRS-506 : qualite de la donnee NO_OF_DAYS
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_total
    FROM   LDTB_CONTRACT_ICCF_CALC c
    WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);
    print_kv('Lignes de calcul d''interet analysees', TO_CHAR(v_total));

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_ICCF_CALC c
    WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (c.NO_OF_DAYS IS NULL OR TRIM(c.NO_OF_DAYS) IS NULL
           OR NOT REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$'));
    print_test('TRS-506 Lignes a NO_OF_DAYS absent ou non numerique', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-507 : coherence NO_OF_DAYS / (END_DATE - START_DATE)
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT c.CONTRACT_REF_NO,
               CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj,
               c.END_DATE - c.START_DATE      AS ecart_cal
        FROM   LDTB_CONTRACT_ICCF_CALC c
        WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
        AND    c.START_DATE IS NOT NULL AND c.END_DATE IS NOT NULL)
    WHERE ABS(nbj - ecart_cal) > 1;
    print_test('TRS-507 Lignes ou NO_OF_DAYS <> (END_DATE - START_DATE)', v_count, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-501 : distribution des bases de calcul detectees
    -- ---------------------------------------------------------
    print_sub('TRS-501 : Base de calcul (day count) detectee par produit et par devise');
    tbl_line('4,10,8,12,12,12,14,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' CCY',8) || '|'
        || RPAD(' BASE 360',12) || '|' || RPAD(' BASE 365',12) || '|' || RPAD(' BASE 366',12) || '|'
        || RPAD(' INDETERMINE',14) || '|' || RPAD(' TOTAL',12) || '|');
    tbl_line('4,10,8,12,12,12,14,12');
    v_row_num := 0;
    FOR d IN (
        WITH ic AS (
            SELECT c.CONTRACT_REF_NO, c.COMPONENT, c.PRODUCT, c.CURRENCY,
                   c.BASIS_AMOUNT, c.RATE, c.CALCULATED_AMOUNT,
                   CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj
            FROM   LDTB_CONTRACT_ICCF_CALC c
            WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')),
        calc AS (
            SELECT ic.*,
                   ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/360 - NVL(CALCULATED_AMOUNT,0)) AS e360,
                   ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/365 - NVL(CALCULATED_AMOUNT,0)) AS e365,
                   ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/366 - NVL(CALCULATED_AMOUNT,0)) AS e366
            FROM   ic),
        best AS (
            SELECT calc.*,
                   LEAST(e360, e365, e366) AS ecart_min,
                   GREATEST(p_tol_interet, p_tol_interet_pct * ABS(NVL(CALCULATED_AMOUNT,0))) AS tol,
                   CASE WHEN e360 <= e365 AND e360 <= e366 THEN 360
                        WHEN e365 <= e366                  THEN 365
                        ELSE 366 END AS base_det
            FROM   calc)
        SELECT PRODUCT, CURRENCY,
               SUM(CASE WHEN ecart_min <= tol AND base_det = 360 THEN 1 ELSE 0 END) n360,
               SUM(CASE WHEN ecart_min <= tol AND base_det = 365 THEN 1 ELSE 0 END) n365,
               SUM(CASE WHEN ecart_min <= tol AND base_det = 366 THEN 1 ELSE 0 END) n366,
               SUM(CASE WHEN ecart_min >  tol THEN 1 ELSE 0 END) nind,
               COUNT(*) ntot
        FROM   best
        GROUP BY PRODUCT, CURRENCY
        ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.PRODUCT,'-'),10) || '|' || RPAD(' ' || NVL(d.CURRENCY,'-'),8) || '|'
            || LPAD(TO_CHAR(d.n360,'FM999G990'),11) || ' |' || LPAD(TO_CHAR(d.n365,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.n366,'FM999G990'),11) || ' |' || LPAD(TO_CHAR(d.nind,'FM999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.ntot,'FM999G990'),11) || ' |');
    END LOOP;
    tbl_line('4,10,8,12,12,12,14,12');

    -- ---------------------------------------------------------
    -- TRS-502 : contrats a base de calcul heterogene
    -- ---------------------------------------------------------
    WITH ic AS (
        SELECT c.CONTRACT_REF_NO, c.COMPONENT, c.BASIS_AMOUNT, c.RATE, c.CALCULATED_AMOUNT,
               CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj
        FROM   LDTB_CONTRACT_ICCF_CALC c
        WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')),
    calc AS (
        SELECT ic.*,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/360 - NVL(CALCULATED_AMOUNT,0)) AS e360,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/365 - NVL(CALCULATED_AMOUNT,0)) AS e365,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/366 - NVL(CALCULATED_AMOUNT,0)) AS e366
        FROM   ic),
    best AS (
        SELECT calc.*,
               LEAST(e360, e365, e366) AS ecart_min,
               GREATEST(p_tol_interet, p_tol_interet_pct * ABS(NVL(CALCULATED_AMOUNT,0))) AS tol,
               CASE WHEN e360 <= e365 AND e360 <= e366 THEN 360
                    WHEN e365 <= e366                  THEN 365
                    ELSE 366 END AS base_det
        FROM   calc)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, COMPONENT
        FROM   best WHERE ecart_min <= tol
        GROUP BY CONTRACT_REF_NO, COMPONENT
        HAVING COUNT(DISTINCT base_det) > 1);
    print_test('TRS-502 Composantes a base de calcul heterogene entre periodes', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-503 / TRS-504 : synthese des ecarts de recalcul
    -- ---------------------------------------------------------
    WITH ic AS (
        SELECT c.CONTRACT_REF_NO, c.COMPONENT, c.BASIS_AMOUNT, c.RATE, c.CALCULATED_AMOUNT,
               CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj
        FROM   LDTB_CONTRACT_ICCF_CALC c
        WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')),
    calc AS (
        SELECT ic.*,
               NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/360 AS i360,
               NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/365 AS i365,
               NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/366 AS i366
        FROM   ic),
    best AS (
        SELECT calc.*,
               LEAST(ABS(i360 - NVL(CALCULATED_AMOUNT,0)),
                     ABS(i365 - NVL(CALCULATED_AMOUNT,0)),
                     ABS(i366 - NVL(CALCULATED_AMOUNT,0))) AS ecart_min,
               GREATEST(p_tol_interet, p_tol_interet_pct * ABS(NVL(CALCULATED_AMOUNT,0))) AS tol
        FROM   calc)
    SELECT COUNT(*), SUM(CASE WHEN ecart_min > tol THEN 1 ELSE 0 END),
           NVL(SUM(CASE WHEN ecart_min > tol THEN ecart_min ELSE 0 END), 0),
           COUNT(DISTINCT CASE WHEN ecart_min > tol THEN CONTRACT_REF_NO END)
    INTO   v_total, v_count, v_num1, v_count2
    FROM   best;

    print_test('TRS-503 Lignes de calcul non reproductibles dans la tolerance', v_count, v_total, 'CRITIQUE');
    print_kv('  Contrats concernes', TO_CHAR(v_count2));
    print_kv('  Ecart absolu cumule (devise composante)', TO_CHAR(ROUND(v_num1, 2), 'FM999G999G999G990D00'));
    IF v_total > 0 THEN
        print_kv('  Taux de reproductibilite du calcul',
                 TO_CHAR(ROUND((v_total - v_count) * 100 / v_total, 2)) || ' %');
    END IF;

    IF v_count > 0 THEN
        print_sub('TRS-504 : Detail des ecarts de recalcul les plus significatifs');
        tbl_line('4,22,14,20,10,7,7,18,18,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' COMPOSANTE',14) || '|'
            || RPAD(' ASSIETTE',20) || '|' || RPAD(' TAUX %',10) || '|' || RPAD(' JOURS',7) || '|'
            || RPAD(' BASE',7) || '|' || RPAD(' FLEXCUBE',18) || '|' || RPAD(' RECALCULE',18) || '|'
            || RPAD(' ECART',16) || '|');
        tbl_line('4,22,14,20,10,7,7,18,18,16');
        v_row_num := 0;
        FOR d IN (
            WITH ic AS (
                SELECT c.CONTRACT_REF_NO, c.COMPONENT, c.BASIS_AMOUNT, c.RATE, c.CALCULATED_AMOUNT,
                       CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj
                FROM   LDTB_CONTRACT_ICCF_CALC c
                WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
                AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')),
            calc AS (
                SELECT ic.*,
                       NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/360 AS i360,
                       NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/365 AS i365,
                       NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/366 AS i366
                FROM   ic),
            best AS (
                SELECT calc.*,
                       CASE WHEN ABS(i360 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i365 - NVL(CALCULATED_AMOUNT,0))
                             AND ABS(i360 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i366 - NVL(CALCULATED_AMOUNT,0)) THEN 360
                            WHEN ABS(i365 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i366 - NVL(CALCULATED_AMOUNT,0)) THEN 365
                            ELSE 366 END AS base_det,
                       CASE WHEN ABS(i360 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i365 - NVL(CALCULATED_AMOUNT,0))
                             AND ABS(i360 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i366 - NVL(CALCULATED_AMOUNT,0)) THEN i360
                            WHEN ABS(i365 - NVL(CALCULATED_AMOUNT,0)) <= ABS(i366 - NVL(CALCULATED_AMOUNT,0)) THEN i365
                            ELSE i366 END AS i_recalc,
                       LEAST(ABS(i360 - NVL(CALCULATED_AMOUNT,0)),
                             ABS(i365 - NVL(CALCULATED_AMOUNT,0)),
                             ABS(i366 - NVL(CALCULATED_AMOUNT,0))) AS ecart_min,
                       GREATEST(p_tol_interet, p_tol_interet_pct * ABS(NVL(CALCULATED_AMOUNT,0))) AS tol
                FROM   calc),
            ecarts AS (
                SELECT CONTRACT_REF_NO, COMPONENT, BASIS_AMOUNT, RATE, nbj, base_det,
                       CALCULATED_AMOUNT, i_recalc, (CALCULATED_AMOUNT - i_recalc) AS ecart,
                       ecart_min
                FROM   best WHERE ecart_min > tol)
            SELECT * FROM (SELECT * FROM ecarts ORDER BY ecart_min DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.COMPONENT,1,12),14) || '|'
                || LPAD(TO_CHAR(NVL(d.BASIS_AMOUNT,0),'FM999G999G999G990'),19) || ' |'
                || LPAD(TO_CHAR(NVL(d.RATE,0),'FM990D0000'),9) || ' |'
                || LPAD(TO_CHAR(d.nbj),6) || ' |' || LPAD(TO_CHAR(d.base_det),6) || ' |'
                || LPAD(TO_CHAR(NVL(d.CALCULATED_AMOUNT,0),'FM999G999G990D00'),17) || ' |'
                || LPAD(TO_CHAR(ROUND(d.i_recalc,2),'FM999G999G990D00'),17) || ' |'
                || LPAD(TO_CHAR(ROUND(d.ecart,2),'FM999G999G990D00'),15) || ' |');
        END LOOP;
        tbl_line('4,22,14,20,10,7,7,18,18,16');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-508 : assiette de calcul incoherente avec l'encours
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1) m
    JOIN LDTB_CONTRACT_ICCF_CALC i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(i.BASIS_AMOUNT,0) > NVL(m.AMOUNT,0) + 1;
    print_test('TRS-508 Lignes dont l''assiette depasse le montant du contrat', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-509 : taux applique different du taux du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MAIN_COMP, c.MAIN_COMP_RATE, c.MAIN_COMP_RATE_CODE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1
        AND  (MAIN_COMP_RATE_CODE IS NULL OR TRIM(MAIN_COMP_RATE_CODE) IS NULL)) m
    JOIN LDTB_CONTRACT_ICCF_CALC i
      ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO AND i.COMPONENT = m.MAIN_COMP
    WHERE i.RATE IS NOT NULL AND m.MAIN_COMP_RATE IS NOT NULL
    AND   ABS(i.RATE - m.MAIN_COMP_RATE) > 0.0001;
    print_test('TRS-509 Taux applique <> taux du contrat (hors taux revisable)', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-511 / TRS-512 : continuite des periodes de calcul
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, COMPONENT, START_DATE, END_DATE,
               LAG(END_DATE) OVER (PARTITION BY CONTRACT_REF_NO, COMPONENT ORDER BY START_DATE) AS fin_prec
        FROM   LDTB_CONTRACT_ICCF_CALC
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module))
    WHERE fin_prec IS NOT NULL AND START_DATE < fin_prec;
    print_test('TRS-511 Periodes de calcul qui se chevauchent', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, COMPONENT, START_DATE, END_DATE,
               LAG(END_DATE) OVER (PARTITION BY CONTRACT_REF_NO, COMPONENT ORDER BY START_DATE) AS fin_prec
        FROM   LDTB_CONTRACT_ICCF_CALC
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module))
    WHERE fin_prec IS NOT NULL AND START_DATE > fin_prec + 1;
    print_test('TRS-512 Discontinuites (trous) entre periodes de calcul', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-513 : periodes de calcul posterieures a la maturite
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE IS NOT NULL) m
    JOIN LDTB_CONTRACT_ICCF_CALC i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE i.END_DATE > m.MATURITY_DATE;
    print_test('TRS-513 Periodes de calcul posterieures a la maturite du contrat', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-514 : somme des calculs vs accrual a date
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT i.CONTRACT_REF_NO, i.COMPONENT,
               NVL(SUM(i.CALCULATED_AMOUNT),0) AS tot_calc,
               MAX(NVL(d.TILL_DATE_ACCRUAL,0))  AS accrual
        FROM   LDTB_CONTRACT_ICCF_CALC i
        JOIN   LDTB_CONTRACT_ICCF_DETAILS d
          ON   d.CONTRACT_REF_NO = i.CONTRACT_REF_NO AND d.COMPONENT = i.COMPONENT
        WHERE  i.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY i.CONTRACT_REF_NO, i.COMPONENT
        HAVING ABS(NVL(SUM(i.CALCULATED_AMOUNT),0) - MAX(NVL(d.TILL_DATE_ACCRUAL,0))) > p_tol_interet);
    print_test('TRS-514 Ecart somme(CALCULATED_AMOUNT) vs TILL_DATE_ACCRUAL', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-515 : ecarts avec la table miroir _FCC
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, COMPONENT, START_DATE, CALCULATED_AMOUNT
        FROM   LDTB_CONTRACT_ICCF_CALC
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        MINUS
        SELECT CONTRACT_REF_NO, COMPONENT, START_DATE, CALCULATED_AMOUNT
        FROM   LDTB_CONTRACT_ICCF_CALC_FCC);
    print_test('TRS-515 Lignes de calcul divergentes entre table principale et _FCC', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-517 : taux hors marche par rapport aux operations comparables
    -- ---------------------------------------------------------
    print_sub('TRS-517 : Contrats a taux significativement hors marche');
    print_note('Comparaison au taux moyen pondere des contrats de meme produit, meme devise,');
    print_note('meme trimestre de mise en place. Seuil d''alerte : ' || TO_CHAR(p_ecart_taux_bps) || ' points de base.');

    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.MAIN_COMP_RATE, c.LCY_AMOUNT,
                   c.VALUE_DATE, c.COUNTERPARTY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MAIN_COMP_RATE IS NOT NULL AND VALUE_DATE IS NOT NULL),
    ref AS (
        SELECT mm.*,
               AVG(MAIN_COMP_RATE) OVER (PARTITION BY PRODUCT, CURRENCY, TRUNC(VALUE_DATE,'Q')) AS tx_ref,
               COUNT(*)            OVER (PARTITION BY PRODUCT, CURRENCY, TRUNC(VALUE_DATE,'Q')) AS nb_ref
        FROM   mm)
    SELECT COUNT(*) INTO v_count
    FROM   ref
    WHERE  nb_ref >= 3 AND ABS(MAIN_COMP_RATE - tx_ref) * 100 > p_ecart_taux_bps;
    print_test('TRS-517 Contrats a taux hors marche (> ' || TO_CHAR(p_ecart_taux_bps) || ' bps)',
               v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        tbl_line('4,22,28,10,8,12,12,12,20');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' PRODUIT',10) || '|' || RPAD(' CCY',8) || '|' || RPAD(' TAUX %',12) || '|'
            || RPAD(' TX REF %',12) || '|' || RPAD(' ECART BPS',12) || '|' || RPAD(' MONTANT (M)',20) || '|');
        tbl_line('4,22,28,10,8,12,12,12,20');
        v_row_num := 0;
        FOR d IN (
            WITH mm AS (
                SELECT * FROM (
                    SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.MAIN_COMP_RATE, c.LCY_AMOUNT,
                           c.VALUE_DATE, c.COUNTERPARTY,
                           ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                    FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                WHERE rn = 1 AND MAIN_COMP_RATE IS NOT NULL AND VALUE_DATE IS NOT NULL),
            ref AS (
                SELECT mm.*,
                       AVG(MAIN_COMP_RATE) OVER (PARTITION BY PRODUCT, CURRENCY, TRUNC(VALUE_DATE,'Q')) AS tx_ref,
                       COUNT(*)            OVER (PARTITION BY PRODUCT, CURRENCY, TRUNC(VALUE_DATE,'Q')) AS nb_ref
                FROM   mm),
            hors_marche AS (
                SELECT r.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                       r.PRODUCT, r.CURRENCY, r.MAIN_COMP_RATE, r.tx_ref,
                       ROUND((r.MAIN_COMP_RATE - r.tx_ref) * 100, 0) AS bps, r.LCY_AMOUNT,
                       ABS(r.MAIN_COMP_RATE - r.tx_ref) * NVL(r.LCY_AMOUNT,0) AS materialite
                FROM   ref r LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = r.COUNTERPARTY
                WHERE  r.nb_ref >= 3 AND ABS(r.MAIN_COMP_RATE - r.tx_ref) * 100 > p_ecart_taux_bps)
            SELECT * FROM (SELECT * FROM hors_marche ORDER BY materialite DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || d.CURRENCY,8) || '|'
                || LPAD(TO_CHAR(d.MAIN_COMP_RATE,'FM990D0000'),11) || ' |'
                || LPAD(TO_CHAR(d.tx_ref,'FM990D0000'),11) || ' |'
                || LPAD(TO_CHAR(d.bps,'FMS99990'),11) || ' |'
                || LPAD(TO_CHAR(NVL(d.LCY_AMOUNT,0)/1000000,'FM999G999G990D00') || ' M',19) || ' |');
        END LOOP;
        tbl_line('4,22,28,10,8,12,12,12,20');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-518 : interets calcules sur contrat a montant nul
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(AMOUNT,0) = 0) m
    JOIN LDTB_CONTRACT_ICCF_CALC i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(i.CALCULATED_AMOUNT,0) <> 0;
    print_test('TRS-518 Interets calcules sur des contrats a montant nul', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-519 : methode de calcul heterogene au sein d'un produit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT PRODUCT FROM LDTB_CONTRACT_ICCF_CALC
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY PRODUCT
        HAVING COUNT(DISTINCT ICCF_CALC_METHOD) > 1);
    print_test('TRS-519 Produits a methode de calcul ICCF heterogene', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-520 : coherence des contrats decotes (titres)
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.ORIGINAL_FACE_VALUE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND ORIGINAL_FACE_VALUE IS NOT NULL AND ORIGINAL_FACE_VALUE <> 0
        AND   ABS(ORIGINAL_FACE_VALUE - AMOUNT) > 1) m
    JOIN (SELECT CONTRACT_REF_NO, SUM(NVL(UPFRONT_PROFIT_BOOKED,0)) upb
          FROM LDTB_CONTRACT_ICCF_DETAILS GROUP BY CONTRACT_REF_NO) i
      ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE ABS(i.upb - (m.ORIGINAL_FACE_VALUE - m.AMOUNT)) > 1;
    print_test('TRS-520 Contrats decotes : profit constate <> decote a l''acquisition', v_count, NULL, 'CRITIQUE');


    -- ---------------------------------------------------------
    -- TRS-505 : base detectee vs base declaree (INT_BASIS)
    -- ---------------------------------------------------------
    WITH ic AS (
        SELECT c.CONTRACT_REF_NO, c.COMPONENT, c.BASIS_AMOUNT, c.RATE, c.CALCULATED_AMOUNT,
               CASE WHEN REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')
                    THEN TO_NUMBER(TRIM(c.NO_OF_DAYS)) END AS nbj
        FROM   LDTB_CONTRACT_ICCF_CALC c
        WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    REGEXP_LIKE(TRIM(c.NO_OF_DAYS), '^[0-9]+(\.[0-9]+)?$')),
    calc AS (
        SELECT ic.*,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/360 - NVL(CALCULATED_AMOUNT,0)) AS e360,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/365 - NVL(CALCULATED_AMOUNT,0)) AS e365,
               ABS(NVL(BASIS_AMOUNT,0) * NVL(RATE,0)/100 * nbj/366 - NVL(CALCULATED_AMOUNT,0)) AS e366
        FROM   ic),
    best AS (
        SELECT calc.CONTRACT_REF_NO, calc.COMPONENT,
               LEAST(e360, e365, e366) AS ecart_min,
               GREATEST(p_tol_interet, p_tol_interet_pct * ABS(NVL(CALCULATED_AMOUNT,0))) AS tol,
               CASE WHEN e360 <= e365 AND e360 <= e366 THEN '360'
                    WHEN e365 <= e366                  THEN '365'
                    ELSE '366' END AS base_det
        FROM   calc),
    decl AS (
        SELECT r.CONTRACT_REF_NO, r.COMPONENT,
               MAX(TRIM(r.INT_BASIS)) KEEP (DENSE_RANK LAST ORDER BY r.EVENT_SEQ_NO) AS base_decl
        FROM   LDTB_CONTRACT_ROLL_INT_RATES r
        WHERE  r.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    r.INT_BASIS IS NOT NULL AND TRIM(r.INT_BASIS) IS NOT NULL
        GROUP BY r.CONTRACT_REF_NO, r.COMPONENT)
    SELECT COUNT(*) INTO v_count
    FROM   best JOIN decl
      ON   decl.CONTRACT_REF_NO = best.CONTRACT_REF_NO AND decl.COMPONENT = best.COMPONENT
    WHERE  best.ecart_min <= best.tol
    AND    INSTR(decl.base_decl, best.base_det) = 0;
    print_test('TRS-505 Base detectee incoherente avec INT_BASIS declaree', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-510 : taux hors bornes de variance du produit
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.MAIN_COMP_RATE, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MAIN_COMP_RATE IS NOT NULL),
    ref AS (
        SELECT mm.*,
               AVG(MAIN_COMP_RATE) OVER (PARTITION BY PRODUCT) AS tx_prod,
               COUNT(*)            OVER (PARTITION BY PRODUCT) AS nb_prod
        FROM   mm)
    SELECT COUNT(*) INTO v_count
    FROM   ref JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = ref.PRODUCT
    WHERE  ref.nb_prod >= 3 AND NVL(pm.MAXIMUM_RATE_VARIANCE,0) > 0
    AND    ABS(ref.MAIN_COMP_RATE - ref.tx_prod) > pm.MAXIMUM_RATE_VARIANCE;
    print_test('TRS-510 Taux au-dela de la variance maximale autorisee par le produit',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-516 : taux atypiques (queues de distribution)
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MAIN_COMP_RATE IS NOT NULL),
    bornes AS (
        SELECT mm.*,
               PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY MAIN_COMP_RATE)
                   OVER (PARTITION BY PRODUCT) AS p01,
               PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY MAIN_COMP_RATE)
                   OVER (PARTITION BY PRODUCT) AS p99,
               COUNT(*) OVER (PARTITION BY PRODUCT) AS nb_prod
        FROM   mm)
    SELECT COUNT(*) INTO v_count
    FROM   bornes
    WHERE  nb_prod >= 20 AND (MAIN_COMP_RATE < p01 OR MAIN_COMP_RATE > p99);
    print_test('TRS-516 Contrats a taux atypique (hors percentiles 1 et 99 du produit)',
               v_count, NULL, 'MAJEUR');


    -- =========================================================
    -- SECTION 6 : ACCRUALS ET SEPARATION DES EXERCICES
    -- =========================================================
    print_section('SECTION 6 : ACCRUALS ET SEPARATION DES EXERCICES');

    -- ---------------------------------------------------------
    -- TRS-601 : contrats non echus porteurs d'interet sans accrual
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE, c.MAIN_COMP_RATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND NVL(MAIN_COMP_RATE,0) > 0
            AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
        WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_ACCRUAL_HISTORY a
                          WHERE a.CONTRACT_REF_NO = m.CONTRACT_REF_NO));
    print_test('TRS-601 Contrats non echus porteurs d''interet sans aucun accrual', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        tbl_line('4,22,28,8,6,20,12,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' PROD',8) || '|' || RPAD(' CCY',6) || '|' || RPAD(' MONTANT (M XAF)',20) || '|'
            || RPAD(' TAUX %',12) || '|' || RPAD(' MATUR_DT',12) || '|');
        tbl_line('4,22,28,8,6,20,12,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT m.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                   m.PRODUCT, m.CURRENCY, m.LCY_AMOUNT, m.MAIN_COMP_RATE, m.MATURITY_DATE
            FROM (SELECT * FROM (
                     SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.LCY_AMOUNT, c.COUNTERPARTY,
                            c.MAIN_COMP_RATE, c.MATURITY_DATE,
                            ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                 ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                     FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                  WHERE rn = 1 AND NVL(MAIN_COMP_RATE,0) > 0
                  AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
            WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_ACCRUAL_HISTORY a
                              WHERE a.CONTRACT_REF_NO = m.CONTRACT_REF_NO)
            ORDER BY m.LCY_AMOUNT DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || d.PRODUCT,8) || '|' || RPAD(' ' || d.CURRENCY,6) || '|'
                || LPAD(TO_CHAR(NVL(d.LCY_AMOUNT,0)/1000000,'FM999G999G990D00') || ' M',19) || ' |'
                || LPAD(TO_CHAR(NVL(d.MAIN_COMP_RATE,0),'FM990D0000'),11) || ' |'
                || RPAD(' ' || TO_CHAR(d.MATURITY_DATE,'DD/MM/YYYY'),12) || '|');
        END LOOP;
        tbl_line('4,22,28,8,6,20,12,12');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-602 : accruals sans ecriture comptable passee
    -- ---------------------------------------------------------
    SELECT COUNT(*), NVL(SUM(NVL(a.NET_ACCRUAL,0)),0) INTO v_count, v_num1
    FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
    WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(a.ACC_ENTRY_PASSED,'N') <> 'Y';
    print_test('TRS-602 Accruals sans ecriture comptable (ACC_ENTRY_PASSED <> Y)', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Montant d''accrual non comptabilise', TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));
    END IF;

    -- ---------------------------------------------------------
    -- TRS-603 : fraicheur des accruals
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(MAIN_COMP_RATE,0) > 0
        AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
    JOIN LDTB_CONTRACT_ICCF_DETAILS i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(i.ACCRUAL_REQUIRED,'N') = 'Y'
    AND  (i.PREVIOUS_ACCRUAL_TO_DATE IS NULL
          OR i.PREVIOUS_ACCRUAL_TO_DATE < v_dt_fin - p_jours_accrual_max);
    print_test('TRS-603 Composantes actives dont l''accrual date de plus de '
               || TO_CHAR(p_jours_accrual_max) || ' jours', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-605 : coherence historique des accruals vs cumul a date
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CONTRACT_REF_NO, a.COMPONENT,
               NVL(SUM(a.NET_ACCRUAL),0)         AS somme_hist,
               MAX(NVL(i.TILL_DATE_ACCRUAL,0))   AS cumul_ref
        FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
        JOIN   LDTB_CONTRACT_ICCF_DETAILS i
          ON   i.CONTRACT_REF_NO = a.CONTRACT_REF_NO AND i.COMPONENT = a.COMPONENT
        WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY a.CONTRACT_REF_NO, a.COMPONENT
        HAVING ABS(NVL(SUM(a.NET_ACCRUAL),0) - MAX(NVL(i.TILL_DATE_ACCRUAL,0))) > p_tol_interet);
    print_test('TRS-605 Ecart somme(NET_ACCRUAL) vs TILL_DATE_ACCRUAL', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-606 / TRS-607 / TRS-609 : anomalies de l'historique
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN NVL(a.NET_ACCRUAL,0) < 0 THEN 1 ELSE 0 END),
           SUM(CASE WHEN a.ACCRUAL_TO_DATE > a.TRANSACTION_DATE THEN 1 ELSE 0 END),
           SUM(CASE WHEN a.ACCRUAL_TO_DATE > v_dt_fin THEN 1 ELSE 0 END),
           COUNT(*)
    INTO   v_count, v_count2, v_count3, v_total
    FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
    WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);
    print_kv('Lignes d''historique d''accrual analysees', TO_CHAR(v_total));
    print_test('TRS-607 Accruals a montant negatif (reprises)', v_count, v_total, 'MAJEUR');
    print_test('TRS-609 Accruals dont ACCRUAL_TO_DATE > TRANSACTION_DATE', v_count2, v_total, 'MAJEUR');
    print_test('TRS-609 Accruals au-dela de la date d''arrete', v_count3, v_total, 'MAJEUR');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
    JOIN   LDTB_CONTRACT_ICCF_DETAILS i
      ON   i.CONTRACT_REF_NO = a.CONTRACT_REF_NO AND i.COMPONENT = a.COMPONENT
    WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    i.LAST_LIQUIDATION_DATE IS NOT NULL
    AND    a.TRANSACTION_DATE > i.LAST_LIQUIDATION_DATE;
    print_test('TRS-606 Accruals posterieurs a la derniere liquidation', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-611 : separation des exercices
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
    WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    a.ACCRUAL_TO_DATE IS NOT NULL AND a.TRANSACTION_DATE IS NOT NULL
    AND    TO_CHAR(a.ACCRUAL_TO_DATE,'YYYY') <> TO_CHAR(a.TRANSACTION_DATE,'YYYY');
    print_test('TRS-611 Accruals rattaches a un exercice different de leur comptabilisation',
               v_count, NULL, 'CRITIQUE');

    print_sub('TRS-611 : Ventilation des accruals par exercice de rattachement');
    tbl_line('4,10,12,24,24');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' EXERCICE',10) || '|' || RPAD(' NB ACCRUALS',12) || '|'
        || RPAD(' NET_ACCRUAL CUMULE',24) || '|' || RPAD(' DONT NON COMPTABILISE',24) || '|');
    tbl_line('4,10,12,24,24');
    v_row_num := 0;
    FOR d IN (SELECT TO_CHAR(a.ACCRUAL_TO_DATE,'YYYY') AS ex, COUNT(*) nb,
                     NVL(SUM(a.NET_ACCRUAL),0) tot,
                     NVL(SUM(CASE WHEN NVL(a.ACC_ENTRY_PASSED,'N') <> 'Y'
                                  THEN a.NET_ACCRUAL ELSE 0 END),0) non_cpt
              FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
              WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              AND    a.ACCRUAL_TO_DATE IS NOT NULL
              GROUP BY TO_CHAR(a.ACCRUAL_TO_DATE,'YYYY')
              ORDER BY 1) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.ex,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.tot,'FM999G999G999G990'),23) || ' |'
            || LPAD(TO_CHAR(d.non_cpt,'FM999G999G999G990'),23) || ' |');
    END LOOP;
    tbl_line('4,10,12,24,24');

    -- ---------------------------------------------------------
    -- TRS-612 / TRS-613 : rapprochement accrual / comptabilite
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CONTRACT_REF_NO,
               NVL(SUM(a.NET_ACCRUAL),0) AS acc_gestion,
               NVL(MAX(h.mt),0)          AS acc_compta
        FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
        LEFT JOIN (SELECT TRN_REF_NO,
                          SUM(CASE WHEN DRCR_IND = 'D' THEN LCY_AMOUNT ELSE -LCY_AMOUNT END) mt
                   FROM   ACTB_HISTORY
                   WHERE  MODULE = p_module AND EVENT IN ('ACCR','IACR','MACR')
                   GROUP BY TRN_REF_NO) h ON h.TRN_REF_NO = a.CONTRACT_REF_NO
        WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    NVL(a.ACC_ENTRY_PASSED,'N') = 'Y'
        GROUP BY a.CONTRACT_REF_NO
        HAVING ABS(NVL(SUM(a.NET_ACCRUAL),0) - ABS(NVL(MAX(h.mt),0))) > p_tol_compta);
    print_test('TRS-612 Contrats dont l''accrual de gestion <> accrual comptabilise', v_count, NULL, 'CRITIQUE');
    print_note('  Note : test base sur les evenements ACCR / IACR / MACR — voir TRS-721 pour');
    print_note('         la liste effective des evenements comptables du module.');

    SELECT COUNT(DISTINCT h.TRN_REF_NO) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module AND h.EVENT IN ('ACCR','IACR','MACR')
    AND    NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_ACCRUAL_HISTORY a
                       WHERE a.CONTRACT_REF_NO = h.TRN_REF_NO);
    print_test('TRS-613 Ecritures d''accrual sans historique d''accrual correspondant', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-614 : accrual residuel sur contrat echu
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE < v_dt_fin) m
    JOIN LDTB_CONTRACT_ICCF_DETAILS i ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE ABS(NVL(i.CURRENT_NET_ACCRUAL,0)) > p_tol_interet;
    print_test('TRS-614 Accrual net non solde sur contrat echu', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-615 : interets courus non echus a la date d'arrete
    -- ---------------------------------------------------------
    print_sub('TRS-615 : Interets courus non echus (ICNE) a la date d''arrete');
    print_note('Rappel PCEC : les ICNE doivent figurer aux comptes de creances / dettes rattachees.');
    tbl_line('4,10,8,9,24,24,24');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' CCY',8) || '|'
        || RPAD(' NB CTR',9) || '|' || RPAD(' ACCRUAL CUMULE',24) || '|' || RPAD(' DEJA LIQUIDE',24) || '|'
        || RPAD(' ICNE (NON LIQUIDE)',24) || '|');
    tbl_line('4,10,8,9,24,24,24');
    v_row_num := 0;
    v_num1 := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT mm.PRODUCT, mm.CURRENCY, COUNT(DISTINCT mm.CONTRACT_REF_NO) nb,
               NVL(SUM(i.TILL_DATE_ACCRUAL),0)        acc,
               NVL(SUM(i.TOTAL_AMOUNT_LIQUIDATED),0)  liq,
               NVL(SUM(i.TILL_DATE_ACCRUAL),0) - NVL(SUM(i.TOTAL_AMOUNT_LIQUIDATED),0) icne
        FROM   mm JOIN LDTB_CONTRACT_ICCF_DETAILS i ON i.CONTRACT_REF_NO = mm.CONTRACT_REF_NO
        GROUP BY mm.PRODUCT, mm.CURRENCY
        ORDER BY 6 DESC) LOOP
        v_row_num := v_row_num + 1;
        v_num1 := v_num1 + NVL(d.icne, 0);
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.PRODUCT,'-'),10) || '|' || RPAD(' ' || NVL(d.CURRENCY,'-'),8) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),8) || ' |'
            || LPAD(TO_CHAR(d.acc,'FM999G999G999G990'),23) || ' |'
            || LPAD(TO_CHAR(d.liq,'FM999G999G999G990'),23) || ' |'
            || LPAD(TO_CHAR(d.icne,'FM999G999G999G990'),23) || ' |');
    END LOOP;
    tbl_line('4,10,8,9,24,24,24');
    print_kv('ICNE total du portefeuille MM (toutes devises confondues)',
             TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));

    -- ---------------------------------------------------------
    -- TRS-616 : ICNE superieur au principal
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(AMOUNT,0) > 0) m
    JOIN (SELECT CONTRACT_REF_NO,
                 SUM(NVL(TILL_DATE_ACCRUAL,0) - NVL(TOTAL_AMOUNT_LIQUIDATED,0)) icne
          FROM LDTB_CONTRACT_ICCF_DETAILS GROUP BY CONTRACT_REF_NO) i
      ON i.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE i.icne > m.AMOUNT;
    print_test('TRS-616 Contrats dont l''ICNE depasse le principal', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-617 / TRS-618 : traitements automatiques (EOD/BOD)
    -- ---------------------------------------------------------
    print_sub('TRS-617 : Etat des traitements automatiques du module');
    tbl_line('4,10,26,14,14,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AGENCE',10) || '|' || RPAD(' PROCESSUS',26) || '|'
        || RPAD(' STATUT',14) || '|' || RPAD(' NB OCCUR.',14) || '|' || RPAD(' 1ere DATE',12) || '|'
        || RPAD(' DERN. DATE',12) || '|');
    tbl_line('4,10,26,14,14,12,12');
    v_row_num := 0;
    FOR d IN (SELECT NVL(q.BRANCH,'-') br, NVL(SUBSTR(q.PROCESS_NAME,1,24),'-') pn,
                     NVL(q.PROCESS_STATUS,'(vide)') st, COUNT(*) nb,
                     MIN(q.PROCESSING_DATE) d1, MAX(q.PROCESSING_DATE) d2
              FROM   LDTB_AUTOMATIC_PROCESS_QUEUE q
              WHERE  q.MODULE = p_module
              GROUP BY q.BRANCH, q.PROCESS_NAME, q.PROCESS_STATUS
              ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        EXIT WHEN v_row_num > 30;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.br,10) || '|' || RPAD(' ' || d.pn,26) || '|' || RPAD(' ' || d.st,14) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),12) || '|'
            || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),12) || '|');
    END LOOP;
    tbl_line('4,10,26,14,14,12,12');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_AUTOMATIC_PROCESS_QUEUE q
    WHERE  q.MODULE = p_module AND NVL(q.PROCESS_STATUS,'X') NOT IN ('C','S','Y')
    AND    q.PROCESSING_DATE BETWEEN v_dt_deb AND v_dt_fin;
    print_test('TRS-617 Traitements automatiques MM non aboutis sur la periode', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_AUTO_FUNCTION_DETAILS f
    WHERE  f.MODULE = p_module AND NVL(f.WORK_IN_PROGRESS,'N') = 'Y';
    print_test('TRS-618 Traitements restes en cours (WORK_IN_PROGRESS = Y)', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_AUTO_FUNCTION_DETAILS f
    WHERE  f.MODULE = p_module
    AND   (f.CURRENT_PROCESS_TILL_DATE IS NULL OR f.CURRENT_PROCESS_TILL_DATE < v_dt_fin - p_jours_accrual_max);
    print_test('TRS-618 Agences dont le traitement MM est en retard', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-619 : dates de dernier accrual par produit / agence
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_PERIODIC_ACCRUAL_DATE p
    WHERE  p.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND   (p.PREVIOUS_ACCRUAL_TO_DATE IS NULL
           OR p.PREVIOUS_ACCRUAL_TO_DATE < v_dt_fin - p_jours_accrual_max);
    print_test('TRS-619 Couples produit/agence dont l''accrual periodique est en retard',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-620 : lignes en attente de transfert
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_COMPUTATION_HANDOFF h
    WHERE  h.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);
    print_test('TRS-620 Lignes MM en attente dans LDTB_COMPUTATION_HANDOFF', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-621 : ecarts ICCF details vs table miroir
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, COMPONENT, TILL_DATE_ACCRUAL, TOTAL_AMOUNT_LIQUIDATED
        FROM   LDTB_CONTRACT_ICCF_DETAILS
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        MINUS
        SELECT CONTRACT_REF_NO, COMPONENT, TILL_DATE_ACCRUAL, TOTAL_AMOUNT_LIQUIDATED
        FROM   LDTB_CONTRACT_ICCF_DETAILS_FCC);
    print_test('TRS-621 Composantes divergentes entre ICCF_DETAILS et _FCC', v_count, NULL, 'MINEUR');


    -- ---------------------------------------------------------
    -- TRS-604 : trous dans la chronologie des accruals
    -- ---------------------------------------------------------
    WITH acc AS (
        SELECT a.CONTRACT_REF_NO, a.COMPONENT, a.ACCRUAL_TO_DATE,
               LAG(a.ACCRUAL_TO_DATE) OVER (PARTITION BY a.CONTRACT_REF_NO, a.COMPONENT
                                            ORDER BY a.ACCRUAL_TO_DATE) AS prec
        FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
        WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        AND    a.ACCRUAL_TO_DATE IS NOT NULL)
    SELECT COUNT(*) INTO v_count
    FROM   acc
    WHERE  prec IS NOT NULL AND ACCRUAL_TO_DATE - prec > p_jours_accrual_max;
    print_test('TRS-604 Discontinuites de plus de ' || TO_CHAR(p_jours_accrual_max)
               || ' jours dans la chronologie d''accrual', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-608 : accruals de rattrapage
    -- ---------------------------------------------------------
    print_sub('TRS-608 : Types d''accrual rencontres');
    tbl_line('4,20,16,26,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' TYPE_OF_ACCRUAL',20) || '|' || RPAD(' NB',16) || '|'
        || RPAD(' NET_ACCRUAL CUMULE',26) || '|' || RPAD(' NB CONTRATS',20) || '|');
    tbl_line('4,20,16,26,20');
    v_row_num := 0;
    FOR d IN (SELECT NVL(a.TYPE_OF_ACCRUAL,'(vide)') ta, COUNT(*) nb,
                     NVL(SUM(a.NET_ACCRUAL),0) mt, COUNT(DISTINCT a.CONTRACT_REF_NO) nbc
              FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
              WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY a.TYPE_OF_ACCRUAL ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.ta,20) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),15) || ' |'
            || LPAD(TO_CHAR(d.mt,'FM999G999G999G990'),25) || ' |'
            || LPAD(TO_CHAR(d.nbc,'FM999G990'),19) || ' |');
    END LOOP;
    tbl_line('4,20,16,26,20');
    print_note('Un volume eleve d''accruals de rattrapage signale une defaillance recurrente du batch.');

    -- ---------------------------------------------------------
    -- TRS-610 : accruals chevauchant la cloture annuelle
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_ICCF_CALC i
    WHERE  i.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    i.START_DATE IS NOT NULL AND i.END_DATE IS NOT NULL
    AND    TO_CHAR(i.START_DATE,'YYYY') <> TO_CHAR(i.END_DATE,'YYYY');
    print_test('TRS-610 Periodes de calcul chevauchant deux exercices sans coupure',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-622 : accruals pris en compte pour les limites
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT l.CONTRACT_REF_NO,
               MAX(NVL(l.TOTAL_CURRENT_NET_ACCRUAL,0)) AS pour_limites,
               MAX(i.cumul)                            AS cumul_iccf
        FROM   LDTB_ACCRUAL_FOR_LIMITS l
        JOIN  (SELECT CONTRACT_REF_NO, SUM(NVL(CURRENT_NET_ACCRUAL,0)) cumul
               FROM   LDTB_CONTRACT_ICCF_DETAILS GROUP BY CONTRACT_REF_NO) i
          ON   i.CONTRACT_REF_NO = l.CONTRACT_REF_NO
        WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY l.CONTRACT_REF_NO
        HAVING ABS(MAX(NVL(l.TOTAL_CURRENT_NET_ACCRUAL,0)) - MAX(i.cumul)) > p_tol_interet);
    print_test('TRS-622 Ecart accrual pour limites vs accrual net des composantes',
               v_count, NULL, 'MINEUR');


    -- =========================================================
    -- SECTION 7 : COMPTABILISATION ET RAPPROCHEMENT
    -- =========================================================
    print_section('SECTION 7 : COMPTABILISATION ET RAPPROCHEMENT GESTION / COMPTABILITE');

    -- ---------------------------------------------------------
    -- TRS-721 : evenements comptables rencontres
    -- ---------------------------------------------------------
    print_sub('TRS-721 : Evenements comptables du module MM');
    tbl_line('4,10,12,12,22,22,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' EVENT',10) || '|' || RPAD(' NB ECR',12) || '|'
        || RPAD(' NB CTR',12) || '|' || RPAD(' DEBIT (M XAF)',22) || '|' || RPAD(' CREDIT (M XAF)',22) || '|'
        || RPAD(' 1ere DATE',12) || '|' || RPAD(' DERN. DATE',12) || '|');
    tbl_line('4,10,12,12,22,22,12,12');
    v_row_num := 0;
    FOR d IN (SELECT h.EVENT, COUNT(*) nb, COUNT(DISTINCT h.TRN_REF_NO) nbc,
                     SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) mt_d,
                     SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) mt_c,
                     MIN(h.TRN_DT) d1, MAX(h.TRN_DT) d2
              FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
              GROUP BY h.EVENT ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.EVENT,'(vide)'),10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.nbc,'FM999G999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt_d/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.mt_c/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),12) || '|'
            || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),12) || '|');
    END LOOP;
    tbl_line('4,10,12,12,22,22,12,12');

    -- ---------------------------------------------------------
    -- TRS-701 : contrats sans ecriture comptable
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO FROM (
            SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
        WHERE NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                          WHERE h.TRN_REF_NO = m.CONTRACT_REF_NO AND h.MODULE = p_module));
    print_test('TRS-701 Contrats MM sans aucune ecriture comptable', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        tbl_line('4,22,28,8,6,20,12,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' PROD',8) || '|' || RPAD(' CCY',6) || '|' || RPAD(' MONTANT (M XAF)',20) || '|'
            || RPAD(' VALUE_DT',12) || '|' || RPAD(' MATUR_DT',12) || '|');
        tbl_line('4,22,28,8,6,20,12,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT m.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                   m.PRODUCT, m.CURRENCY, m.LCY_AMOUNT, m.VALUE_DATE, m.MATURITY_DATE
            FROM (SELECT * FROM (
                     SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.CURRENCY, c.LCY_AMOUNT, c.COUNTERPARTY,
                            c.VALUE_DATE, c.MATURITY_DATE,
                            ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                 ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                     FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                  WHERE rn = 1) m
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
            WHERE NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                              WHERE h.TRN_REF_NO = m.CONTRACT_REF_NO AND h.MODULE = p_module)
            ORDER BY m.LCY_AMOUNT DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || d.PRODUCT,8) || '|' || RPAD(' ' || d.CURRENCY,6) || '|'
                || LPAD(TO_CHAR(NVL(d.LCY_AMOUNT,0)/1000000,'FM999G999G990D00') || ' M',19) || ' |'
                || RPAD(' ' || TO_CHAR(d.VALUE_DATE,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.MATURITY_DATE,'DD/MM/YYYY'),12) || '|');
        END LOOP;
        tbl_line('4,22,28,8,6,20,12,12');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-702 : ecritures sans contrat sous-jacent
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.TRN_REF_NO), COUNT(*), NVL(SUM(h.LCY_AMOUNT),0)
    INTO   v_count, v_count2, v_num1
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_MASTER m
                       WHERE m.CONTRACT_REF_NO = h.TRN_REF_NO AND m.MODULE = p_module);
    print_test('TRS-702 References comptables MM sans contrat sous-jacent', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Nombre d''ecritures concernees', TO_CHAR(v_count2));
        print_kv('  Montant cumule (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
        print_note('  Piste : contrats archives, purges, ou operations d''un autre perimetre.');
        tbl_line('4,24,10,10,24,12,12,18');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' TRN_REF_NO',24) || '|' || RPAD(' EVENT',10) || '|'
            || RPAD(' PRODUIT',10) || '|' || RPAD(' MONTANT (M XAF)',24) || '|' || RPAD(' 1ere DATE',12) || '|'
            || RPAD(' DERN. DATE',12) || '|' || RPAD(' NB ECRITURES',18) || '|');
        tbl_line('4,24,10,10,24,12,12,18');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.TRN_REF_NO, MAX(h.EVENT) ev, MAX(h.PRODUCT) pr,
                   SUM(ABS(h.LCY_AMOUNT)) mt, MIN(h.TRN_DT) d1, MAX(h.TRN_DT) d2, COUNT(*) nb
            FROM   ACTB_HISTORY h
            WHERE  h.MODULE = p_module
            AND    NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_MASTER m
                               WHERE m.CONTRACT_REF_NO = h.TRN_REF_NO AND m.MODULE = p_module)
            GROUP BY h.TRN_REF_NO
            ORDER BY SUM(ABS(h.LCY_AMOUNT)) DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,22),24) || '|' || RPAD(' ' || NVL(d.ev,'-'),10) || '|'
                || RPAD(' ' || NVL(d.pr,'-'),10) || '|'
                || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',23) || ' |'
                || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),12) || '|'
                || LPAD(TO_CHAR(d.nb,'FM999G990'),17) || ' |');
        END LOOP;
        tbl_line('4,24,10,10,24,12,12,18');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-703 / TRS-704 : equilibre des ecritures
    -- ---------------------------------------------------------
    SELECT COUNT(*), NVL(SUM(ABS(ecart)),0) INTO v_count, v_num1 FROM (
        SELECT h.TRN_REF_NO, h.EVENT_SR_NO,
               SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END) AS ecart
        FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
        GROUP BY h.TRN_REF_NO, h.EVENT_SR_NO
        HAVING ABS(SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END)) > p_tol_compta);
    print_test('TRS-703 Evenements comptables desequilibres (debit <> credit)', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Montant cumule du desequilibre', TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));
        tbl_line('4,24,10,10,24,24,20');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',24) || '|' || RPAD(' EVT_SR',10) || '|'
            || RPAD(' EVENT',10) || '|' || RPAD(' DEBIT (XAF)',24) || '|' || RPAD(' CREDIT (XAF)',24) || '|'
            || RPAD(' ECART (XAF)',20) || '|');
        tbl_line('4,24,10,10,24,24,20');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.TRN_REF_NO, h.EVENT_SR_NO, MAX(h.EVENT) ev,
                   SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) mt_d,
                   SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) mt_c,
                   SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END) ecart
            FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
            GROUP BY h.TRN_REF_NO, h.EVENT_SR_NO
            HAVING ABS(SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END)) > p_tol_compta
            ORDER BY ABS(SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END)) DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,22),24) || '|' || LPAD(TO_CHAR(d.EVENT_SR_NO),9) || ' |'
                || RPAD(' ' || NVL(d.ev,'-'),10) || '|'
                || LPAD(TO_CHAR(d.mt_d,'FM999G999G999G990'),23) || ' |'
                || LPAD(TO_CHAR(d.mt_c,'FM999G999G999G990'),23) || ' |'
                || LPAD(TO_CHAR(d.ecart,'FMS999G999G999G990'),19) || ' |');
        END LOOP;
        tbl_line('4,24,10,10,24,24,20');
    END IF;

    SELECT NVL(SUM(CASE WHEN DRCR_IND = 'D' THEN LCY_AMOUNT ELSE -LCY_AMOUNT END),0)
    INTO   v_num1 FROM ACTB_HISTORY WHERE MODULE = p_module;
    print_kv('TRS-704 Desequilibre global du module MM (toutes dates)',
             TO_CHAR(ROUND(v_num1,2), 'FMS999G999G999G990D00'));
    IF ABS(v_num1) > p_tol_compta THEN
        print_test('TRS-704 Comptabilite MM globalement desequilibree', 1, NULL, 'CRITIQUE');
    ELSE
        print_test('TRS-704 Comptabilite MM globalement desequilibree', 0, NULL, 'CRITIQUE');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-705 / TRS-706 / TRS-730 : qualite des ecritures
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN NVL(h.LCY_AMOUNT,0) <= 0 THEN 1 ELSE 0 END),
           SUM(CASE WHEN NVL(h.FCY_AMOUNT,0) <> 0 AND NVL(h.EXCH_RATE,0) = 0 THEN 1 ELSE 0 END),
           SUM(CASE WHEN h.AMOUNT_TAG IS NULL OR TRIM(h.AMOUNT_TAG) IS NULL THEN 1 ELSE 0 END),
           COUNT(*)
    INTO   v_count, v_count2, v_count3, v_total
    FROM   ACTB_HISTORY h WHERE h.MODULE = p_module;
    print_test('TRS-705 Ecritures MM a montant LCY nul ou negatif', v_count, v_total, 'MAJEUR');
    print_test('TRS-706 Ecritures en devise sans taux de change', v_count2, v_total, 'CRITIQUE');
    print_test('TRS-730 Ecritures MM sans AMOUNT_TAG', v_count3, v_total, 'MAJEUR');

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NVL(h.FCY_AMOUNT,0) <> 0 AND NVL(h.EXCH_RATE,0) <> 0
    AND    ABS(h.FCY_AMOUNT * h.EXCH_RATE - h.LCY_AMOUNT) > GREATEST(p_tol_compta, ABS(h.LCY_AMOUNT) * 0.001);
    print_test('TRS-706 Ecritures ou FCY_AMOUNT x EXCH_RATE <> LCY_AMOUNT', v_count, v_total, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-708 / TRS-709 : agences comptables
    -- ---------------------------------------------------------
    print_sub('TRS-708 : Ventilation des ecritures MM par agence comptable');
    tbl_line('4,10,14,22,22,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' AGENCE',10) || '|' || RPAD(' NB ECRITURES',14) || '|'
        || RPAD(' DEBIT (M XAF)',22) || '|' || RPAD(' CREDIT (M XAF)',22) || '|' || RPAD(' % ECR',12) || '|');
    tbl_line('4,10,14,22,22,12');
    v_row_num := 0;
    FOR d IN (SELECT NVL(h.AC_BRANCH,'(vide)') br, COUNT(*) nb,
                     SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) mt_d,
                     SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) mt_c,
                     ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 2) pct
              FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
              GROUP BY h.AC_BRANCH ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.br,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt_d/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.mt_c/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |');
    END LOOP;
    tbl_line('4,10,14,22,22,12');

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.BRANCH,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE h.MODULE = p_module AND h.AC_BRANCH <> m.BRANCH;
    print_test('TRS-709 Ecritures dont l''agence comptable <> agence de booking', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-711 / TRS-712 / TRS-713 : comptes d'imputation
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.AC_NO) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM STTB_ACCOUNT a WHERE a.AC_GL_NO = h.AC_NO);
    print_test('TRS-711 Comptes/GL d''imputation MM absents de STTB_ACCOUNT', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   STTB_ACCOUNT a ON a.AC_GL_NO = h.AC_NO
    WHERE  h.MODULE = p_module
    AND   (NVL(a.AC_STAT_DORMANT,'N') = 'Y' OR NVL(a.AC_STAT_FROZEN,'N') = 'Y'
           OR NVL(a.GL_STAT_BLOCKED,'N') = 'Y');
    print_test('TRS-712 Ecritures MM sur compte dormant, gele ou bloque', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   STTB_ACCOUNT a ON a.AC_GL_NO = h.AC_NO
    WHERE  h.MODULE = p_module
    AND    a.AC_GL_CCY IS NOT NULL AND TRIM(a.AC_GL_CCY) IS NOT NULL
    AND    TRIM(a.AC_GL_CCY) <> TRIM(h.AC_CCY);
    print_test('TRS-713 Ecritures dont la devise <> devise du compte impute', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-714 / TRS-715 : dates de valeur
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN h.VALUE_DT < h.TRN_DT - p_backval_max THEN 1 ELSE 0 END),
           SUM(CASE WHEN h.VALUE_DT > h.TRN_DT THEN 1 ELSE 0 END)
    INTO   v_count, v_count2
    FROM   ACTB_HISTORY h WHERE h.MODULE = p_module;
    print_test('TRS-714 Ecritures MM en date de valeur anterieure (> '
               || TO_CHAR(p_backval_max) || ' j)', v_count, v_total, 'MAJEUR');
    print_test('TRS-715 Ecritures MM en date de valeur posterieure', v_count2, v_total, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-716 : ecritures hors bornes du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.VALUE_DATE, c.MATURITY_DATE,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE h.MODULE = p_module
    AND  (h.VALUE_DT < m.VALUE_DATE - 1 OR h.VALUE_DT > m.MATURITY_DATE + 1);
    print_test('TRS-716 Ecritures en date de valeur hors bornes du contrat', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-717 : rapprochement encours gestion / comptabilite
    -- ---------------------------------------------------------
    print_sub('TRS-717 : Rapprochement encours de gestion / mouvements comptables de principal');
    SELECT COUNT(*) INTO v_count3
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module AND UPPER(h.AMOUNT_TAG) LIKE '%PRINCIP%';
    IF v_count3 = 0 THEN
        print_note('Aucun AMOUNT_TAG contenant "PRINCIP" : le rapprochement automatique n''est pas');
        print_note('realisable. Identifier les tags de principal avec la comptabilite (voir TRS-118).');
    ELSE
        SELECT NVL(SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END),0)
        INTO   v_num2
        FROM   ACTB_HISTORY h
        WHERE  h.MODULE = p_module AND UPPER(h.AMOUNT_TAG) LIKE '%PRINCIP%'
        AND    h.TRN_DT <= v_dt_fin;

        SELECT NVL(SUM(m.LCY_AMOUNT),0) INTO v_num3 FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m;

        print_kv('Encours de gestion, contrats non echus (' || p_ccy_locale || ')',
                 TO_CHAR(v_num3, 'FM999G999G999G999G990'));
        print_kv('Solde net des mouvements de principal (' || p_ccy_locale || ')',
                 TO_CHAR(v_num2, 'FMS999G999G999G999G990'));
        print_kv('Ecart gestion / comptabilite',
                 TO_CHAR(v_num3 - ABS(v_num2), 'FMS999G999G999G999G990'));
        IF v_num3 <> 0 AND ABS(v_num3 - ABS(v_num2)) / v_num3 > 0.01 THEN
            print_test('TRS-717 Ecart significatif gestion / comptabilite (> 1%)', 1, NULL, 'CRITIQUE');
        ELSE
            print_test('TRS-717 Ecart significatif gestion / comptabilite (> 1%)', 0, NULL, 'CRITIQUE');
        END IF;
        print_note('Note : rapprochement indicatif, fonde sur les AMOUNT_TAG contenant "PRINCIP".');
        print_note('Il doit etre valide contre la balance comptable officielle (voir BRD, REC-F04).');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-720 : schemas comptables (event / tag / sens)
    -- ---------------------------------------------------------
    print_sub('TRS-720 : Schemas comptables du module MM (evenement / tag / sens)');
    tbl_line('4,10,24,6,10,14,24');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' EVENT',10) || '|' || RPAD(' AMOUNT_TAG',24) || '|'
        || RPAD(' D/C',6) || '|' || RPAD(' CUST_GL',10) || '|' || RPAD(' NB ECRITURES',14) || '|'
        || RPAD(' MONTANT (M XAF)',24) || '|');
    tbl_line('4,10,24,6,10,14,24');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT h.EVENT, NVL(h.AMOUNT_TAG,'(vide)') tag, h.DRCR_IND, NVL(h.CUST_GL,'-') cg,
               COUNT(*) nb, SUM(h.LCY_AMOUNT) mt
        FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
        GROUP BY h.EVENT, h.AMOUNT_TAG, h.DRCR_IND, h.CUST_GL
        ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 40) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.EVENT,'-'),10) || '|' || RPAD(' ' || SUBSTR(d.tag,1,22),24) || '|'
            || RPAD(' ' || d.DRCR_IND,6) || '|' || RPAD(' ' || d.cg,10) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',23) || ' |');
    END LOOP;
    tbl_line('4,10,24,6,10,14,24');

    -- ---------------------------------------------------------
    -- TRS-724 : coherence periode comptable
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    h.FINANCIAL_CYCLE IS NOT NULL AND TRIM(h.FINANCIAL_CYCLE) IS NOT NULL
    AND    TRIM(h.FINANCIAL_CYCLE) <> TO_CHAR(h.TRN_DT, 'YYYY');
    print_test('TRS-724 Ecritures dont FINANCIAL_CYCLE <> annee de TRN_DT', v_count, v_total, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-725 : batch vs saisie
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN h.BATCH_NO IS NOT NULL AND TRIM(h.BATCH_NO) IS NOT NULL THEN 1 ELSE 0 END),
           SUM(CASE WHEN h.BATCH_NO IS NULL OR TRIM(h.BATCH_NO) IS NULL THEN 1 ELSE 0 END)
    INTO   v_count, v_count2
    FROM   ACTB_HISTORY h WHERE h.MODULE = p_module;
    print_kv('TRS-725 Ecritures MM issues d''un batch', TO_CHAR(v_count));
    print_kv('TRS-725 Ecritures MM hors batch', TO_CHAR(v_count2));

    -- ---------------------------------------------------------
    -- TRS-726 : produit de l'ecriture <> produit du contrat
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE h.MODULE = p_module AND h.PRODUCT IS NOT NULL AND h.PRODUCT <> m.PRODUCT;
    print_test('TRS-726 Ecritures dont le produit <> produit du contrat', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-727 / TRS-728 : reevaluation de change
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.AC_NO) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module AND h.AC_CCY <> p_ccy_locale
    AND    NOT EXISTS (SELECT 1 FROM RVTB_ACC_REVAL r WHERE r.ACCOUNT = h.AC_NO);
    print_test('TRS-727 Comptes MM en devises jamais reevalues', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   RVTB_ACC_REVAL r
    WHERE  r.ACCOUNT IN (SELECT DISTINCT AC_NO FROM ACTB_HISTORY WHERE MODULE = p_module)
    AND    NVL(r.NEW_RATE,0) <> 0
    AND    ABS(NVL(r.ACCOUNT_BALANCE,0) * r.NEW_RATE - NVL(r.NEW_LCY_EQUIVALENT,0))
           > GREATEST(p_tol_compta, ABS(NVL(r.NEW_LCY_EQUIVALENT,0)) * 0.001);
    print_test('TRS-728 Reevaluations ou solde x taux <> contre-valeur recalculee', v_count, NULL, 'MAJEUR');


    -- ---------------------------------------------------------
    -- TRS-707 : taux de change des ecritures vs cours de reference
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT h.TRN_REF_NO, h.EXCH_RATE,
               (SELECT MAX(r.MID_RATE) KEEP (DENSE_RANK LAST ORDER BY r.RATE_DATE)
                FROM   CYTB_RATES_HISTORY r
                WHERE  r.CCY1 = h.AC_CCY AND r.CCY2 = p_ccy_locale
                AND    r.RATE_DATE <= h.TRN_DT) AS taux_ref
        FROM   ACTB_HISTORY h
        WHERE  h.MODULE = p_module AND h.AC_CCY <> p_ccy_locale
        AND    NVL(h.EXCH_RATE,0) > 0)
    WHERE taux_ref IS NOT NULL AND taux_ref <> 0
    AND   ABS(EXCH_RATE - taux_ref) / NULLIF(taux_ref,0) > p_tol_change_pct;
    print_test('TRS-707 Ecritures MM a taux de change hors cours de reference',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-710 : imputation compte client vs compte general
    -- ---------------------------------------------------------
    print_sub('TRS-710 : Imputation des ecritures MM (compte client / compte general)');
    tbl_line('4,12,24,14,24,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CUST_GL',12) || '|' || RPAD(' AMOUNT_TAG',24) || '|'
        || RPAD(' NB ECRITURES',14) || '|' || RPAD(' MONTANT (M XAF)',24) || '|' || RPAD(' % ECR',12) || '|');
    tbl_line('4,12,24,14,24,12');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT NVL(h.CUST_GL,'(vide)') cg, NVL(SUBSTR(h.AMOUNT_TAG,1,22),'(vide)') tag,
               COUNT(*) nb, SUM(h.LCY_AMOUNT) mt,
               ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 2) pct
        FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
        GROUP BY h.CUST_GL, h.AMOUNT_TAG
        ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 25) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cg,12) || '|' || RPAD(' ' || d.tag,24) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',23) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |');
    END LOOP;
    tbl_line('4,12,24,14,24,12');

    -- ---------------------------------------------------------
    -- TRS-718 : rapprochement ICNE gestion / comptabilite
    -- ---------------------------------------------------------
    print_sub('TRS-718 : Rapprochement des interets courus non echus');
    SELECT COUNT(*) INTO v_count3
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND   (UPPER(h.AMOUNT_TAG) LIKE '%INTACC%' OR UPPER(h.AMOUNT_TAG) LIKE '%_ACCR%'
           OR UPPER(h.AMOUNT_TAG) LIKE 'INT%ACC%');
    IF v_count3 = 0 THEN
        print_note('Aucun AMOUNT_TAG d''accrual identifiable par nommage : rapprochement ICNE non');
        print_note('automatisable. Identifier les comptes de creances rattachees avec la comptabilite.');
    ELSE
        SELECT NVL(SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END),0)
        INTO   v_num2
        FROM   ACTB_HISTORY h
        WHERE  h.MODULE = p_module AND h.TRN_DT <= v_dt_fin
        AND   (UPPER(h.AMOUNT_TAG) LIKE '%INTACC%' OR UPPER(h.AMOUNT_TAG) LIKE '%_ACCR%'
               OR UPPER(h.AMOUNT_TAG) LIKE 'INT%ACC%');

        SELECT NVL(SUM(NVL(i.TILL_DATE_ACCRUAL,0) - NVL(i.TOTAL_AMOUNT_LIQUIDATED,0)),0)
        INTO   v_num3
        FROM   LDTB_CONTRACT_ICCF_DETAILS i
        WHERE  i.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);

        print_kv('ICNE de gestion (accrual non liquide)', TO_CHAR(ROUND(v_num3,2), 'FMS999G999G999G990D00'));
        print_kv('Solde net comptable des tags d''accrual', TO_CHAR(ROUND(v_num2,2), 'FMS999G999G999G990D00'));
        print_kv('Ecart', TO_CHAR(ROUND(v_num3 - ABS(v_num2),2), 'FMS999G999G999G990D00'));
        IF v_num3 <> 0 AND ABS(v_num3 - ABS(v_num2)) / ABS(v_num3) > 0.01 THEN
            print_test('TRS-718 Ecart significatif sur les ICNE (> 1%)', 1, NULL, 'CRITIQUE');
        ELSE
            print_test('TRS-718 Ecart significatif sur les ICNE (> 1%)', 0, NULL, 'CRITIQUE');
        END IF;
    END IF;

    -- ---------------------------------------------------------
    -- TRS-719 : rapprochement produits et charges d'interet
    -- ---------------------------------------------------------
    print_sub('TRS-719 : Produits et charges d''interet MM par exercice');
    tbl_line('4,10,14,26,26,26');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' EXERCICE',10) || '|' || RPAD(' NB ECRITURES',14) || '|'
        || RPAD(' ACCRUAL COMPTABILISE',26) || '|' || RPAD(' ACCRUAL DE GESTION',26) || '|'
        || RPAD(' ECART',26) || '|');
    tbl_line('4,10,14,26,26,26');
    v_row_num := 0;
    FOR d IN (
        WITH cpt AS (
            SELECT TO_CHAR(h.TRN_DT,'YYYY') ex, COUNT(*) nb,
                   SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) mt
            FROM   ACTB_HISTORY h
            WHERE  h.MODULE = p_module AND h.EVENT IN ('ACCR','IACR','MACR')
            GROUP BY TO_CHAR(h.TRN_DT,'YYYY')),
        ges AS (
            SELECT TO_CHAR(a.TRANSACTION_DATE,'YYYY') ex, NVL(SUM(a.NET_ACCRUAL),0) mt
            FROM   LDTB_CONTRACT_ACCRUAL_HISTORY a
            WHERE  a.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    a.TRANSACTION_DATE IS NOT NULL
            GROUP BY TO_CHAR(a.TRANSACTION_DATE,'YYYY'))
        SELECT NVL(cpt.ex, ges.ex) ex, NVL(cpt.nb,0) nb,
               NVL(cpt.mt,0) mt_cpt, NVL(ges.mt,0) mt_ges,
               NVL(cpt.mt,0) - NVL(ges.mt,0) ecart
        FROM   cpt FULL OUTER JOIN ges ON ges.ex = cpt.ex
        ORDER BY 1) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.ex,10) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt_cpt,'FM999G999G999G990'),25) || ' |'
            || LPAD(TO_CHAR(d.mt_ges,'FM999G999G999G990'),25) || ' |'
            || LPAD(TO_CHAR(d.ecart,'FMS999G999G999G990'),25) || ' |');
    END LOOP;
    tbl_line('4,10,14,26,26,26');

    -- ---------------------------------------------------------
    -- TRS-722 / TRS-723 : extournes et contre-passations
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT h.TRN_REF_NO), NVL(SUM(h.LCY_AMOUNT),0)
    INTO   v_count, v_count2, v_num1
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND   (UPPER(h.EVENT) LIKE 'REV%' OR UPPER(h.EVENT) IN ('RVSL','REVR','DLQD'));
    print_test('TRS-722 Ecritures d''extourne / contre-passation MM', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Contrats concernes', TO_CHAR(v_count2));
        print_kv('  Montant extourne (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
    END IF;

    -- Paires debit/credit de meme montant sur un meme contrat et un meme tag
    SELECT COUNT(*) INTO v_count FROM (
        SELECT h.TRN_REF_NO, h.AMOUNT_TAG, h.LCY_AMOUNT
        FROM   ACTB_HISTORY h WHERE h.MODULE = p_module
        GROUP BY h.TRN_REF_NO, h.AMOUNT_TAG, h.LCY_AMOUNT
        HAVING SUM(CASE WHEN h.DRCR_IND = 'D' THEN 1 ELSE 0 END) >= 2
           AND SUM(CASE WHEN h.DRCR_IND = 'C' THEN 1 ELSE 0 END) >= 2);
    print_test('TRS-723 Contrats presentant des cycles de comptabilisation repetes',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-729 : couverture des comptes MM dans la balance generale
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT h.AC_NO, h.AC_BRANCH
        FROM   ACTB_HISTORY h
        JOIN   STTB_ACCOUNT a ON a.AC_GL_NO = h.AC_NO
        WHERE  h.MODULE = p_module AND a.AC_OR_GL <> 'A') g
    WHERE NOT EXISTS (SELECT 1 FROM GLTB_GL_BAL b
                      WHERE b.GL_CODE = g.AC_NO AND b.BRANCH_CODE = g.AC_BRANCH);
    print_test('TRS-729 Comptes generaux mouvementes par MM absents de la balance GL',
               v_count, NULL, 'CRITIQUE');

    print_sub('TRS-729 : Poids du module MM dans les principaux comptes generaux');
    tbl_line('4,22,10,14,24,24,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' GL',22) || '|' || RPAD(' AGENCE',10) || '|'
        || RPAD(' NB ECR MM',14) || '|' || RPAD(' MOUVEMENT MM (M)',24) || '|'
        || RPAD(' SOLDE GL (M XAF)',24) || '|' || RPAD(' DEVISE',12) || '|');
    tbl_line('4,22,10,14,24,24,12');
    v_row_num := 0;
    FOR d IN (
        WITH gl AS (
            SELECT b.GL_CODE, b.BRANCH_CODE,
                   SUM(NVL(b.DR_BAL_LCY,0) - NVL(b.CR_BAL_LCY,0)) AS solde
            FROM   GLTB_GL_BAL b
            GROUP BY b.GL_CODE, b.BRANCH_CODE),
        mv AS (
            SELECT h.AC_NO, h.AC_BRANCH, COUNT(*) nb,
                   SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE -h.LCY_AMOUNT END) mvt,
                   MAX(h.AC_CCY) ccy
            FROM   ACTB_HISTORY h
            JOIN   STTB_ACCOUNT a ON a.AC_GL_NO = h.AC_NO
            WHERE  h.MODULE = p_module AND a.AC_OR_GL <> 'A'
            GROUP BY h.AC_NO, h.AC_BRANCH)
        SELECT * FROM (
            SELECT mv.AC_NO, mv.AC_BRANCH, mv.nb, mv.mvt, gl.solde, mv.ccy
            FROM   mv LEFT JOIN gl
              ON   gl.GL_CODE = mv.AC_NO AND gl.BRANCH_CODE = mv.AC_BRANCH
            ORDER BY mv.nb DESC)
        WHERE ROWNUM <= 25) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.AC_NO,1,20),22) || '|' || RPAD(' ' || d.AC_BRANCH,10) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mvt/1000000,'FMS999G999G990D00'),23) || ' |'
            || LPAD(CASE WHEN d.solde IS NULL THEN 'n/a'
                    ELSE TO_CHAR(d.solde/1000000,'FMS999G999G990D00') END, 23) || ' |'
            || RPAD(' ' || NVL(d.ccy,'-'),12) || '|');
    END LOOP;
    tbl_line('4,22,10,14,24,24,12');
    print_note('Le solde GL couvre tous les modules : l''ecart avec le mouvement MM est normal.');
    print_note('Ce tableau sert a identifier les comptes ou MM est preponderant, pour le');
    print_note('rapprochement manuel avec la balance comptable officielle.');


    -- =========================================================
    -- SECTION 8 : LIQUIDATIONS, IMPAYES ET REMBOURSEMENTS ANTICIPES
    -- =========================================================
    print_section('SECTION 8 : LIQUIDATIONS, IMPAYES ET REMBOURSEMENTS ANTICIPES');

    -- ---------------------------------------------------------
    -- TRS-801 : impayes
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT l.CONTRACT_REF_NO),
           NVL(SUM(NVL(l.AMOUNT_DUE,0) - NVL(l.AMOUNT_PAID,0)),0)
    INTO   v_count, v_count2, v_num1
    FROM   LDTB_CONTRACT_LIQ l
    WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01;
    print_test('TRS-801 Echeances MM echues et non integralement reglees', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Contrats concernes', TO_CHAR(v_count2));
        print_kv('  Montant total impaye (devise composante)', TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));
    END IF;

    -- ---------------------------------------------------------
    -- TRS-802 : ventilation par palier d'anciennete (COBAC R-2018/01)
    -- ---------------------------------------------------------
    print_sub('TRS-802 : Anciennete des impayes (rattachement COBAC R-2018/01)');
    tbl_line('4,24,12,12,26');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PALIER',24) || '|' || RPAD(' NB ECH.',12) || '|'
        || RPAD(' NB CTR',12) || '|' || RPAD(' MONTANT IMPAYE',26) || '|');
    tbl_line('4,24,12,12,26');
    v_row_num := 0;
    FOR d IN (
        SELECT palier, COUNT(*) nb, COUNT(DISTINCT CONTRACT_REF_NO) nbc,
               NVL(SUM(du_restant),0) mt
        FROM (
            SELECT CONTRACT_REF_NO,
                   NVL(AMOUNT_DUE,0) - NVL(AMOUNT_PAID,0) AS du_restant,
                   CASE
                     WHEN NVL(OVERDUE_DAYS,0) <= p_jours_retard_1
                          THEN '1. 0 a ' || TO_CHAR(p_jours_retard_1) || ' jours'
                     WHEN NVL(OVERDUE_DAYS,0) <= p_jours_retard_2
                          THEN '2. ' || TO_CHAR(p_jours_retard_1+1) || ' a ' || TO_CHAR(p_jours_retard_2) || ' jours'
                     WHEN NVL(OVERDUE_DAYS,0) <= p_jours_retard_3
                          THEN '3. ' || TO_CHAR(p_jours_retard_2+1) || ' a ' || TO_CHAR(p_jours_retard_3) || ' jours'
                     WHEN NVL(OVERDUE_DAYS,0) <= p_jours_retard_4
                          THEN '4. ' || TO_CHAR(p_jours_retard_3+1) || ' a ' || TO_CHAR(p_jours_retard_4) || ' jours'
                     ELSE      '5. plus de ' || TO_CHAR(p_jours_retard_4) || ' jours'
                   END AS palier
            FROM   LDTB_CONTRACT_LIQ
            WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO
                                       FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    NVL(AMOUNT_DUE,0) > NVL(AMOUNT_PAID,0) + 0.01)
        GROUP BY palier
        ORDER BY palier) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.palier,24) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.nbc,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt,'FM999G999G999G990'),25) || ' |');
    END LOOP;
    tbl_line('4,24,12,12,26');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01
    AND    NVL(l.OVERDUE_DAYS,0) > p_jours_retard_2;
    print_test('TRS-802 Impayes de plus de ' || TO_CHAR(p_jours_retard_2)
               || ' jours (seuil de declassement)', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-803 : impayes sur contrepartie bancaire
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT l.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = l.CONTRACT_REF_NO
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY AND cu.CUSTOMER_TYPE = 'B'
    WHERE  NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01;
    print_test('TRS-803 Contrats en impaye sur contrepartie bancaire', v_count, NULL, 'CRITIQUE');

    IF v_count > 0 THEN
        print_sub('TRS-801/803 : Detail des principaux impayes');
        tbl_line('4,22,28,14,20,20,10,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' COMPOSANTE',14) || '|' || RPAD(' MONTANT DU',20) || '|' || RPAD(' MONTANT PAYE',20) || '|'
            || RPAD(' RETARD J',10) || '|' || RPAD(' TYPE CPTIE',12) || '|');
        tbl_line('4,22,28,14,20,20,10,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT l.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                   l.COMPONENT, l.AMOUNT_DUE, l.AMOUNT_PAID, l.OVERDUE_DAYS,
                   NVL(cu.CUSTOMER_TYPE,'-') ctype
            FROM   LDTB_CONTRACT_LIQ l
            JOIN  (SELECT * FROM (
                      SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                             ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                  ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                      FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                   WHERE rn = 1) m ON m.CONTRACT_REF_NO = l.CONTRACT_REF_NO
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
            WHERE  NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01
            ORDER BY (NVL(l.AMOUNT_DUE,0) - NVL(l.AMOUNT_PAID,0)) DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || SUBSTR(d.COMPONENT,1,12),14) || '|'
                || LPAD(TO_CHAR(NVL(d.AMOUNT_DUE,0),'FM999G999G999G990'),19) || ' |'
                || LPAD(TO_CHAR(NVL(d.AMOUNT_PAID,0),'FM999G999G999G990'),19) || ' |'
                || LPAD(TO_CHAR(NVL(d.OVERDUE_DAYS,0),'FM999G990'),9) || ' |'
                || RPAD(' ' || d.ctype,12) || '|');
        END LOOP;
        tbl_line('4,22,28,14,20,20,10,12');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-804 / TRS-805 / TRS-806 : contrats echus
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE, c.CONTRACT_STATUS,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE < v_dt_fin AND NVL(CONTRACT_STATUS,'A') = 'A');
    print_test('TRS-804 Contrats echus toujours au statut actif', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*), NVL(SUM(b.PRINCIPAL_OUTSTANDING_BAL),0) INTO v_count, v_num1 FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE < v_dt_fin) m
    JOIN LDTB_CONTRACT_BALANCE b ON b.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(b.PRINCIPAL_OUTSTANDING_BAL,0) > 1;
    print_test('TRS-805 Contrats echus avec encours de principal non nul', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Encours residuel sur contrats echus', TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));
    END IF;

    -- ---------------------------------------------------------
    -- TRS-808 / TRS-809 : rapprochement liquidations / comptabilite
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT l.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(l.AMOUNT_PAID,0) > 0
    AND    NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                       WHERE h.TRN_REF_NO = l.CONTRACT_REF_NO AND h.MODULE = p_module
                       AND   h.EVENT IN ('LIQD','MLIQ','ALIQ','ILIQ','PLIQ'));
    print_test('TRS-808 Contrats liquides sans ecriture de liquidation', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(DISTINCT h.TRN_REF_NO) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module AND h.EVENT IN ('LIQD','MLIQ','ALIQ','ILIQ','PLIQ')
    AND    NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_LIQ l WHERE l.CONTRACT_REF_NO = h.TRN_REF_NO);
    print_test('TRS-809 Ecritures de liquidation sans ligne de liquidation', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-810 : coherence liquidations detail / synthese
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT l.CONTRACT_REF_NO, l.EVENT_SEQ_NO,
               NVL(SUM(l.AMOUNT_PAID),0) AS detail,
               MAX(NVL(s.TOTAL_PAID,0))  AS synthese
        FROM   LDTB_CONTRACT_LIQ l
        JOIN   LDTB_CONTRACT_LIQ_SUMMARY s
          ON   s.CONTRACT_REF_NO = l.CONTRACT_REF_NO AND s.EVENT_SEQ_NO = l.EVENT_SEQ_NO
        WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY l.CONTRACT_REF_NO, l.EVENT_SEQ_NO
        HAVING ABS(NVL(SUM(l.AMOUNT_PAID),0) - MAX(NVL(s.TOTAL_PAID,0))) > 1);
    print_test('TRS-810 Ecart somme(AMOUNT_PAID) vs TOTAL_PAID de la synthese', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-811 / TRS-812 / TRS-813 : remboursements anticipes
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT s.CONTRACT_REF_NO), NVL(SUM(s.TOTAL_PREPAID),0)
    INTO   v_count, v_count2, v_num1
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(s.TOTAL_PREPAID,0) > 0;
    print_test('TRS-811 Operations de remboursement anticipe', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        print_kv('  Contrats concernes', TO_CHAR(v_count2));
        print_kv('  Montant total rembourse par anticipation', TO_CHAR(ROUND(v_num1,2), 'FM999G999G999G990D00'));
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = s.CONTRACT_REF_NO
    JOIN   LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = m.PRODUCT
    WHERE  NVL(s.TOTAL_PREPAID,0) > 0 AND NVL(pm.PREPAYMENT_PENALTY,'N') = 'Y'
    AND    NVL(s.PREPAYMENT_PENALTY_AMOUNT,0) = 0;
    print_test('TRS-812 Remboursements anticipes sans penalite alors que le produit en prevoit',
               v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(s.PREPAYMENT_PENALTY_RATE,0) > 0 AND NVL(s.TOTAL_PREPAID,0) > 0
    AND    ABS(NVL(s.PREPAYMENT_PENALTY_AMOUNT,0)
               - s.TOTAL_PREPAID * s.PREPAYMENT_PENALTY_RATE / 100) > 1;
    print_test('TRS-813 Penalites de remboursement anticipe non reproductibles', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-814 : prorogations d'echeance
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT s.CONTRACT_REF_NO) INTO v_count, v_count2
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    s.OLD_MATURITY_DATE IS NOT NULL AND s.NEW_MATURITY_DATE IS NOT NULL
    AND    s.NEW_MATURITY_DATE > s.OLD_MATURITY_DATE;
    print_test('TRS-814 Prorogations d''echeance constatees', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Contrats concernes', TO_CHAR(v_count2));
        print_note('  Attention : une prorogation repetee peut masquer un impaye (COBAC R-2018/01).');
        tbl_line('4,22,28,12,12,12,20');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
            || RPAD(' ANC. MATUR',12) || '|' || RPAD(' NEW MATUR',12) || '|' || RPAD(' JOURS',12) || '|'
            || RPAD(' NB PROROGATIONS',20) || '|');
        tbl_line('4,22,28,12,12,12,20');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT s.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
                   s.OLD_MATURITY_DATE od, s.NEW_MATURITY_DATE nd,
                   (s.NEW_MATURITY_DATE - s.OLD_MATURITY_DATE) nj,
                   COUNT(*) OVER (PARTITION BY s.CONTRACT_REF_NO) nb
            FROM   LDTB_CONTRACT_LIQ_SUMMARY s
            LEFT JOIN (SELECT * FROM (
                          SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY,
                                 ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                      ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                          FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                       WHERE rn = 1) m ON m.CONTRACT_REF_NO = s.CONTRACT_REF_NO
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
            WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    s.OLD_MATURITY_DATE IS NOT NULL AND s.NEW_MATURITY_DATE IS NOT NULL
            AND    s.NEW_MATURITY_DATE > s.OLD_MATURITY_DATE
            ORDER BY (s.NEW_MATURITY_DATE - s.OLD_MATURITY_DATE) DESC)
            WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
                || RPAD(' ' || TO_CHAR(d.od,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.nd,'DD/MM/YYYY'),12) || '|'
                || LPAD(TO_CHAR(d.nj,'FM999G990'),11) || ' |'
                || LPAD(TO_CHAR(d.nb,'FM999G990'),19) || ' |');
        END LOOP;
        tbl_line('4,22,28,12,12,12,20');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-815 / TRS-816 : anomalies de traitement
    -- ---------------------------------------------------------
    SELECT SUM(CASE WHEN s.REJ_REASON IS NOT NULL AND TRIM(s.REJ_REASON) IS NOT NULL THEN 1 ELSE 0 END),
           COUNT(*)
    INTO   v_count, v_total
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module);
    print_test('TRS-815 Liquidations portant un motif de rejet', v_count, v_total, 'MAJEUR');

    print_sub('TRS-816 : Repartition des statuts de paiement');
    tbl_line('4,18,12,26');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PAYMENT_STATUS',18) || '|' || RPAD(' NB',12) || '|'
        || RPAD(' TOTAL PAYE',26) || '|');
    tbl_line('4,18,12,26');
    v_row_num := 0;
    FOR d IN (SELECT NVL(s.PAYMENT_STATUS,'(vide)') st, COUNT(*) nb, NVL(SUM(s.TOTAL_PAID),0) mt
              FROM   LDTB_CONTRACT_LIQ_SUMMARY s
              WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY s.PAYMENT_STATUS ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.st,18) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt,'FM999G999G999G990'),25) || ' |');
    END LOOP;
    tbl_line('4,18,12,26');

    -- ---------------------------------------------------------
    -- TRS-818 : valeur nominale liquidee (titres)
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.ORIGINAL_FACE_VALUE,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1 AND ORIGINAL_FACE_VALUE IS NOT NULL AND ORIGINAL_FACE_VALUE <> 0) m
      ON m.CONTRACT_REF_NO = s.CONTRACT_REF_NO
    WHERE NVL(s.LIQUIDATED_FACE_VALUE,0) > m.ORIGINAL_FACE_VALUE + 1;
    print_test('TRS-818 Valeur nominale liquidee superieure a la valeur nominale d''origine',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-821 : taxes prelevees
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT l.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.TAX_SCHEME,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1 AND TAX_SCHEME IS NOT NULL AND TRIM(TAX_SCHEME) IS NOT NULL) m
      ON m.CONTRACT_REF_NO = l.CONTRACT_REF_NO
    WHERE NVL(l.AMOUNT_PAID,0) > 0 AND NVL(l.TAX_PAID,0) = 0;
    print_test('TRS-821 Contrats taxables regles sans prelevement de taxe', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-822 : ecarts avec les tables miroir
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT CONTRACT_REF_NO, EVENT_SEQ_NO, COMPONENT, AMOUNT_DUE, AMOUNT_PAID
        FROM   LDTB_CONTRACT_LIQ
        WHERE  CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        MINUS
        SELECT CONTRACT_REF_NO, EVENT_SEQ_NO, COMPONENT, AMOUNT_DUE, AMOUNT_PAID
        FROM   LDTB_CONTRACT_LIQ_FCC);
    print_test('TRS-822 Liquidations divergentes entre table principale et _FCC', v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-823 : provisionnement des impayes anciens
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT l.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01
    AND    NVL(l.OVERDUE_DAYS,0) > p_jours_retard_2
    AND    NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                       WHERE h.TRN_REF_NO = l.CONTRACT_REF_NO AND h.MODULE = p_module
                       AND  (UPPER(h.AMOUNT_TAG) LIKE '%PROV%' OR UPPER(h.EVENT) LIKE '%PROV%'));
    print_test('TRS-823 Impayes > ' || TO_CHAR(p_jours_retard_2)
               || ' j sans ecriture de provision (COBAC R-2018/01)', v_count, NULL, 'CRITIQUE');


    -- ---------------------------------------------------------
    -- TRS-807 : contrats soldes avec echeances restant dues
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT l.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ l
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.CONTRACT_STATUS, c.MATURITY_DATE,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1 AND NVL(CONTRACT_STATUS,'A') <> 'A') m
      ON m.CONTRACT_REF_NO = l.CONTRACT_REF_NO
    WHERE NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01;
    print_test('TRS-807 Contrats non actifs conservant des echeances dues', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.CONTRACT_STATUS,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(CONTRACT_STATUS,'A') = 'L') m
    JOIN LDTB_CONTRACT_BALANCE b ON b.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE NVL(b.PRINCIPAL_OUTSTANDING_BAL,0) > 1;
    print_test('TRS-806 Contrats liquides conservant un encours de principal', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-817 : liquidations en date de valeur anterieure
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    JOIN   LDTB_CONTRACT_PREFERENCE p ON p.CONTRACT_REF_NO = s.CONTRACT_REF_NO
    WHERE  s.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(p.LIQ_BACK_VALUED_SCHEDULES,'N') = 'Y'
    AND    s.VALUE_DATE < v_dt_fin - p_backval_max;
    print_test('TRS-817 Liquidations autorisant une date de valeur anterieure', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-819 : liquidations partielles sous le minimum du produit
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_LIQ_SUMMARY s
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = s.CONTRACT_REF_NO
    JOIN   LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = m.PRODUCT
    WHERE  NVL(pm.MIN_AMT_PARTIAL_LIQ,0) > 0
    AND    NVL(s.TOTAL_PAID,0) > 0 AND s.TOTAL_PAID < pm.MIN_AMT_PARTIAL_LIQ;
    print_test('TRS-819 Liquidations partielles inferieures au minimum du produit',
               v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-820 : respect de l'ordre d'imputation des reglements
    -- ---------------------------------------------------------
    print_sub('TRS-820 : Ordre d''imputation parametre et composantes effectivement reglees');
    tbl_line('4,10,20,12,14,26');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PRODUIT',10) || '|' || RPAD(' COMPOSANTE',20) || '|'
        || RPAD(' LIQ_ORDER',12) || '|' || RPAD(' NB REGLEE',14) || '|' || RPAD(' MONTANT REGLE',26) || '|');
    tbl_line('4,10,20,12,14,26');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT lo.PRODUCT, lo.COMPONENT, lo.LIQ_ORDER,
               NVL(SUM(CASE WHEN NVL(l.AMOUNT_PAID,0) > 0 THEN 1 ELSE 0 END),0) nb,
               NVL(SUM(l.AMOUNT_PAID),0) mt
        FROM   LDTM_PRODUCT_LIQ_ORDER lo
        LEFT JOIN (SELECT * FROM (
                      SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                             ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                                  ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                      FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
                   WHERE rn = 1) m ON m.PRODUCT = lo.PRODUCT
        LEFT JOIN LDTB_CONTRACT_LIQ l
               ON l.CONTRACT_REF_NO = m.CONTRACT_REF_NO AND l.COMPONENT = lo.COMPONENT
        WHERE  lo.PRODUCT IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        GROUP BY lo.PRODUCT, lo.COMPONENT, lo.LIQ_ORDER
        ORDER BY lo.PRODUCT, lo.LIQ_ORDER) WHERE ROWNUM <= 30) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.PRODUCT,10) || '|' || RPAD(' ' || SUBSTR(d.COMPONENT,1,18),20) || '|'
            || LPAD(TO_CHAR(d.LIQ_ORDER),11) || ' |' || LPAD(TO_CHAR(d.nb,'FM999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt,'FM999G999G999G990'),25) || ' |');
    END LOOP;
    tbl_line('4,10,20,12,14,26');

    -- Principal regle alors que des interets du meme contrat restent dus
    SELECT COUNT(DISTINCT lp.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_LIQ lp
    WHERE  lp.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    UPPER(lp.COMPONENT) LIKE 'PRINCIP%' AND NVL(lp.AMOUNT_PAID,0) > 0
    AND    EXISTS (SELECT 1 FROM LDTB_CONTRACT_LIQ li
                   WHERE li.CONTRACT_REF_NO = lp.CONTRACT_REF_NO
                   AND   UPPER(li.COMPONENT) NOT LIKE 'PRINCIP%'
                   AND   NVL(li.AMOUNT_DUE,0) > NVL(li.AMOUNT_PAID,0) + 0.01);
    print_test('TRS-820 Principal regle alors que des interets restent dus', v_count, NULL, 'MAJEUR');


    -- =========================================================
    -- SECTION 9 : ROLLOVERS (RENOUVELLEMENTS)
    -- =========================================================
    print_section('SECTION 9 : ROLLOVERS (RENOUVELLEMENTS)');

    -- ---------------------------------------------------------
    -- TRS-901 : inventaire des rollovers
    -- ---------------------------------------------------------
    print_sub('TRS-901 : Inventaire des contrats renouveles');
    tbl_line('4,18,12,20,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' NB ROLLOVERS',18) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' DUREE MOY CUMULEE',20) || '|');
    tbl_line('4,18,12,20,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.ROLLOVER_COUNT, c.LCY_AMOUNT,
                       c.ORIGINAL_START_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT NVL(ROLLOVER_COUNT,0) nbr, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
               ROUND(AVG(MATURITY_DATE - ORIGINAL_START_DATE),0) duree
        FROM mm GROUP BY NVL(ROLLOVER_COUNT,0) ORDER BY 1) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || LPAD(TO_CHAR(d.nbr,'FM999G990'),17) || ' |' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(NVL(d.duree,0),'FM999G990') || ' j',19) || ' |');
    END LOOP;
    tbl_line('4,18,12,20,20');

    -- ---------------------------------------------------------
    -- TRS-902 : rollovers en serie
    -- ---------------------------------------------------------
    SELECT COUNT(*), NVL(SUM(LCY_AMOUNT),0) INTO v_count, v_num1 FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.ROLLOVER_COUNT, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(ROLLOVER_COUNT,0) > p_rollover_max);
    print_test('TRS-902 Contrats renouveles plus de ' || TO_CHAR(p_rollover_max) || ' fois',
               v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Encours concerne (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
        print_note('  Impact : un placement court renouvele en serie est en realite immobilise.');
        print_note('  Consequence prudentielle : liquidite et coefficient de transformation fausses.');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-903 : duree affichee vs duree effective
    -- ---------------------------------------------------------
    print_sub('TRS-903 : Duree contractuelle affichee vs duree effective (avec rollovers)');
    tbl_line('4,22,28,12,16,16,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CONTRAT',22) || '|' || RPAD(' CONTREPARTIE',28) || '|'
        || RPAD(' NB ROLLOV',12) || '|' || RPAD(' DUREE AFFICHEE',16) || '|' || RPAD(' DUREE EFFECTIVE',16) || '|'
        || RPAD(' RATIO',12) || '|');
    tbl_line('4,22,28,12,16,16,12');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT m.CONTRACT_REF_NO, NVL(SUBSTR(cu.CUSTOMER_NAME1,1,26),'(inconnu)') nom,
               NVL(m.ROLLOVER_COUNT,0) nbr,
               (m.MATURITY_DATE - m.VALUE_DATE)          AS duree_aff,
               (m.MATURITY_DATE - m.ORIGINAL_START_DATE) AS duree_eff
        FROM (SELECT * FROM (
                 SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.ROLLOVER_COUNT,
                        c.VALUE_DATE, c.MATURITY_DATE, c.ORIGINAL_START_DATE, c.LCY_AMOUNT,
                        ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                             ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                 FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
              WHERE rn = 1 AND NVL(ROLLOVER_COUNT,0) > 0
              AND   ORIGINAL_START_DATE IS NOT NULL AND VALUE_DATE IS NOT NULL
              AND   MATURITY_DATE IS NOT NULL) m
        LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
        ORDER BY (m.MATURITY_DATE - m.ORIGINAL_START_DATE) DESC) WHERE ROWNUM <= p_echantillon) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.nom,28) || '|'
            || LPAD(TO_CHAR(d.nbr,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.duree_aff,'FM999G990') || ' j',15) || ' |'
            || LPAD(TO_CHAR(d.duree_eff,'FM999G990') || ' j',15) || ' |'
            || LPAD(TO_CHAR(ROUND(d.duree_eff / NULLIF(d.duree_aff,0), 1),'FM990D0') || ' x',11) || ' |');
    END LOOP;
    tbl_line('4,22,28,12,16,16,12');

    -- ---------------------------------------------------------
    -- TRS-905 : chainage parent / enfant
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT m.CONTRACT_REF_NO, m.PARENT_CONTRACT_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PARENT_CONTRACT_REF_NO,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND PARENT_CONTRACT_REF_NO IS NOT NULL
            AND   TRIM(PARENT_CONTRACT_REF_NO) IS NOT NULL) m
        WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_MASTER p
                          WHERE p.CONTRACT_REF_NO = m.PARENT_CONTRACT_REF_NO));
    print_test('TRS-905 Contrats dont le contrat parent est introuvable', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-904 / TRS-911 : instructions de rollover
    -- ---------------------------------------------------------
    print_sub('TRS-904 : Caracteristiques des instructions de rollover');
    tbl_line('4,14,14,14,14,12,24');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' ROLL_TYPE',14) || '|' || RPAD(' AMT_TYPE',14) || '|'
        || RPAD(' MATUR_TYPE',14) || '|' || RPAD(' INST_STATUS',14) || '|' || RPAD(' NB',12) || '|'
        || RPAD(' MONTANT ROLLOVER',24) || '|');
    tbl_line('4,14,14,14,14,12,24');
    v_row_num := 0;
    FOR d IN (SELECT NVL(r.ROLLOVER_TYPE,'-') rt, NVL(r.ROLLOVER_AMOUNT_TYPE,'-') amt_type,
                     NVL(r.MATURITY_TYPE,'-') mt, NVL(r.ROLL_INST_STATUS,'(vide)') st,
                     COUNT(*) nb, NVL(SUM(r.ROLLOVER_AMT),0) montant
              FROM   LDTB_CONTRACT_ROLLOVER r
              WHERE  r.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY r.ROLLOVER_TYPE, r.ROLLOVER_AMOUNT_TYPE, r.MATURITY_TYPE, r.ROLL_INST_STATUS
              ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.rt,14) || '|' || RPAD(' ' || d.amt_type,14) || '|' || RPAD(' ' || d.mt,14) || '|'
            || RPAD(' ' || d.st,14) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.montant,'FM999G999G999G990'),23) || ' |');
    END LOOP;
    tbl_line('4,14,14,14,14,12,24');

    -- ---------------------------------------------------------
    -- TRS-908 : rollover malgre des impayes
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT r.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_ROLLOVER r
    WHERE  r.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(r.LIQUIDATE_OD_SCHEDULES,'N') <> 'Y'
    AND    EXISTS (SELECT 1 FROM LDTB_CONTRACT_LIQ l
                   WHERE l.CONTRACT_REF_NO = r.CONTRACT_REF_NO
                   AND   NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01);
    print_test('TRS-908 Rollovers sur contrats presentant des impayes non liquides',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-910 : rollover sans ecriture comptable
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT r.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_ROLLOVER r
    WHERE  r.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    NVL(r.ROLLOVER_AMT,0) > 0
    AND    NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                       WHERE h.TRN_REF_NO = r.CONTRACT_REF_NO AND h.MODULE = p_module
                       AND   UPPER(h.EVENT) LIKE 'ROL%');
    print_test('TRS-910 Rollovers sans ecriture comptable de renouvellement', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-913 : taux de rollover
    -- ---------------------------------------------------------
    print_sub('TRS-913 : Taux appliques aux renouvellements');
    tbl_line('4,20,12,12,12,12,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPOSANTE',20) || '|' || RPAD(' NB',12) || '|'
        || RPAD(' TX MIN %',12) || '|' || RPAD(' TX MOY %',12) || '|' || RPAD(' TX MAX %',12) || '|'
        || RPAD(' SPREAD MOY',12) || '|' || RPAD(' INT_BASIS',12) || '|');
    tbl_line('4,20,12,12,12,12,12,12');
    v_row_num := 0;
    FOR d IN (SELECT r.COMPONENT, COUNT(*) nb, MIN(r.RATE) tmin, AVG(r.RATE) tmoy, MAX(r.RATE) tmax,
                     AVG(NVL(r.SPREAD,0)) spr, NVL(MAX(r.INT_BASIS),'-') basis
              FROM   LDTB_CONTRACT_ROLL_INT_RATES r
              WHERE  r.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY r.COMPONENT ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.COMPONENT,1,18),20) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.tmin,0),'FM990D0000'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.tmoy,0),'FM990D0000'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.tmax,0),'FM990D0000'),11) || ' |'
            || LPAD(TO_CHAR(NVL(d.spr,0),'FM990D0000'),11) || ' |'
            || RPAD(' ' || SUBSTR(d.basis,1,10),12) || '|');
    END LOOP;
    tbl_line('4,20,12,12,12,12,12,12');

    -- ---------------------------------------------------------
    -- TRS-914 : concentration des rollovers
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.ROLLOVER_COUNT, c.LCY_AMOUNT,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND NVL(ROLLOVER_COUNT,0) > 0),
    conc AS (
        SELECT COUNTERPARTY FROM mm GROUP BY COUNTERPARTY HAVING COUNT(*) >= 5)
    SELECT COUNT(*) INTO v_count FROM conc;
    print_test('TRS-914 Contreparties concentrant 5 renouvellements ou plus', v_count, NULL, 'MAJEUR');


    -- ---------------------------------------------------------
    -- TRS-906 : rollover avec capitalisation des interets
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT r.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_ROLLOVER r
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.AMOUNT, c.INT_ROLLED_AMT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = r.CONTRACT_REF_NO
    JOIN   LDTM_PRODUCT_ROLLOVER pr ON pr.PRODUCT = m.PRODUCT
    WHERE  NVL(pr.ROLLOVER_WITH_INTEREST,'N') = 'Y'
    AND    NVL(m.INT_ROLLED_AMT,0) = 0;
    print_test('TRS-906 Rollovers avec interets mais sans montant d''interet capitalise',
               v_count, NULL, 'MAJEUR');

    SELECT COUNT(DISTINCT r.CONTRACT_REF_NO) INTO v_count
    FROM   LDTB_CONTRACT_ROLLOVER r
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.AMOUNT, c.INT_ROLLED_AMT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = r.CONTRACT_REF_NO
    WHERE  NVL(r.ROLLOVER_AMT,0) > 0 AND NVL(m.INT_ROLLED_AMT,0) > 0
    AND    ABS(r.ROLLOVER_AMT - (NVL(m.AMOUNT,0) + NVL(m.INT_ROLLED_AMT,0))) > 1;
    print_test('TRS-906 Montant renouvele <> principal + interets capitalises', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-907 : ecart de taux entre contrat parent et contrat renouvele
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PARENT_CONTRACT_REF_NO, c.MAIN_COMP_RATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND PARENT_CONTRACT_REF_NO IS NOT NULL
        AND   TRIM(PARENT_CONTRACT_REF_NO) IS NOT NULL AND MAIN_COMP_RATE IS NOT NULL) e
    JOIN (SELECT * FROM (
             SELECT c.CONTRACT_REF_NO, c.MAIN_COMP_RATE,
                    ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                         ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
             FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
          WHERE rn = 1) p ON p.CONTRACT_REF_NO = e.PARENT_CONTRACT_REF_NO
    WHERE p.MAIN_COMP_RATE IS NOT NULL
    AND   ABS(e.MAIN_COMP_RATE - p.MAIN_COMP_RATE) * 100 > p_ecart_taux_bps;
    print_test('TRS-907 Renouvellements avec ecart de taux > ' || TO_CHAR(p_ecart_taux_bps)
               || ' bps vs contrat parent', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-909 : renouvellement tardif
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PARENT_CONTRACT_REF_NO, c.VALUE_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND PARENT_CONTRACT_REF_NO IS NOT NULL
        AND   TRIM(PARENT_CONTRACT_REF_NO) IS NOT NULL) e
    JOIN (SELECT * FROM (
             SELECT c.CONTRACT_REF_NO, c.MATURITY_DATE,
                    ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                         ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
             FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
          WHERE rn = 1) p ON p.CONTRACT_REF_NO = e.PARENT_CONTRACT_REF_NO
    WHERE e.VALUE_DATE > p.MATURITY_DATE + p_backval_max;
    print_test('TRS-909 Renouvellements demarrant plus de ' || TO_CHAR(p_backval_max)
               || ' j apres l''echeance du parent', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-912 : coherence des regles de taxe au rollover
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_ROLLOVER r
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.PRODUCT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = r.CONTRACT_REF_NO
    JOIN   LDTM_PRODUCT_ROLLOVER pr ON pr.PRODUCT = m.PRODUCT
    WHERE  NVL(r.APPLY_TAX,'#') <> NVL(pr.APPLY_TAX,'#');
    print_test('TRS-912 Regle de taxe au rollover divergente entre contrat et produit',
               v_count, NULL, 'MINEUR');


    -- =========================================================
    -- SECTION 10 : INDICATEURS PRUDENTIELS COBAC
    -- =========================================================
    print_section('SECTION 10 : INDICATEURS PRUDENTIELS COBAC');
    print_note('Convention de sens retenue : LDTM_PRODUCT_MASTER.PRODUCT_TYPE = P -> EMPLOI (placement),');
    print_note('                             B -> RESSOURCE (emprunt). Mapping a confirmer (BRD, PAC-03).');
    IF p_fpn_xaf IS NULL THEN
        print_note('');
        print_note('*** FONDS PROPRES NETS NON RENSEIGNES : les ratios reglementaires ne sont pas');
        print_note('    calcules. Seule la concentration relative est produite. Renseigner p_fpn_xaf.');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-1001 : exposition par contrepartie
    -- ---------------------------------------------------------
    print_sub('TRS-1001 : Exposition MM par contrepartie a la date d''arrete');
    tbl_line('4,13,30,10,20,10,12,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' CONTREPARTIE',30) || '|'
        || RPAD(' CATEGORIE',10) || '|' || RPAD(' EXPOSITION (M XAF)',20) || '|' || RPAD(' % ENCOURS',10) || '|'
        || RPAD(' % FPN',12) || '|' || RPAD(' QUALIF. COBAC',14) || '|');
    tbl_line('4,13,30,10,20,10,12,14');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.PRODUCT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
        expo AS (
            SELECT mm.COUNTERPARTY,
                   NVL(SUBSTR(MAX(cu.CUSTOMER_NAME1),1,28),'(inconnu)') nom,
                   NVL(MAX(cu.CUSTOMER_CATEGORY),'-') cat,
                   NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P'
                                THEN mm.LCY_AMOUNT ELSE 0 END),0) AS exposition,
                   ROUND(RATIO_TO_REPORT(NVL(SUM(mm.LCY_AMOUNT),0)) OVER () * 100, 2) pct_enc
            FROM   mm
            LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY
            LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
            GROUP BY mm.COUNTERPARTY)
        SELECT * FROM (SELECT * FROM expo ORDER BY exposition DESC) WHERE ROWNUM <= 30) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || NVL(d.COUNTERPARTY,'(vide)'),13) || '|' || RPAD(' ' || d.nom,30) || '|'
            || RPAD(' ' || SUBSTR(d.cat,1,8),10) || '|'
            || LPAD(TO_CHAR(d.exposition/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct_enc,'FM990D00'),9) || ' |'
            || LPAD(CASE WHEN p_fpn_xaf IS NULL OR p_fpn_xaf = 0 THEN 'n/a'
                         ELSE TO_CHAR(ROUND(d.exposition * 100 / p_fpn_xaf, 2),'FM99990D00') END, 11) || ' |'
            || RPAD(' ' || CASE
                     WHEN p_fpn_xaf IS NULL OR p_fpn_xaf = 0 THEN '-'
                     WHEN d.exposition * 100 / p_fpn_xaf > p_seuil_benef_max  THEN 'DEPASSEMENT'
                     WHEN d.exposition * 100 / p_fpn_xaf > p_seuil_grand_risq THEN 'GRAND RISQUE'
                     ELSE 'CONFORME' END, 14) || '|');
    END LOOP;
    tbl_line('4,13,30,10,20,10,12,14');

    -- ---------------------------------------------------------
    -- TRS-1002 / TRS-1003 / TRS-1004 : division des risques
    -- ---------------------------------------------------------
    IF p_fpn_xaf IS NOT NULL AND p_fpn_xaf > 0 THEN
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.PRODUCT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
        expo AS (
            SELECT mm.COUNTERPARTY,
                   NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P'
                                THEN mm.LCY_AMOUNT ELSE 0 END),0) AS exposition
            FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
            GROUP BY mm.COUNTERPARTY)
        SELECT SUM(CASE WHEN exposition * 100 / p_fpn_xaf > p_seuil_benef_max  THEN 1 ELSE 0 END),
               SUM(CASE WHEN exposition * 100 / p_fpn_xaf > p_seuil_grand_risq THEN 1 ELSE 0 END),
               NVL(SUM(CASE WHEN exposition * 100 / p_fpn_xaf > p_seuil_grand_risq
                            THEN exposition ELSE 0 END),0)
        INTO   v_count, v_count2, v_num1
        FROM   expo;

        print_test('TRS-1002 Contreparties depassant ' || TO_CHAR(p_seuil_benef_max)
                   || '% des FPN (R-2020/01)', v_count, NULL, 'CRITIQUE');
        print_kv('TRS-1003 Nombre de grands risques (> ' || TO_CHAR(p_seuil_grand_risq) || '% FPN)',
                 TO_CHAR(v_count2));
        print_kv('TRS-1004 Somme des grands risques (' || p_ccy_locale || ')',
                 TO_CHAR(v_num1, 'FM999G999G999G999G990'));
        print_kv('TRS-1004 Somme des grands risques en % des FPN',
                 TO_CHAR(ROUND(v_num1 * 100 / p_fpn_xaf, 2)) || ' % (plafond '
                 || TO_CHAR(p_seuil_gr_cumul) || ' %)');
        IF v_num1 * 100 / p_fpn_xaf > p_seuil_gr_cumul THEN
            print_test('TRS-1004 Depassement du plafond cumule des grands risques', 1, NULL, 'CRITIQUE');
        ELSE
            print_test('TRS-1004 Depassement du plafond cumule des grands risques', 0, NULL, 'CRITIQUE');
        END IF;
    ELSE
        print_kv('TRS-1002/1003/1004 Ratios de division des risques', 'NON CALCULES (FPN absents)');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-1005 : concentration relative (calculable sans FPN)
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
    expo AS (
        SELECT COUNTERPARTY, NVL(SUM(LCY_AMOUNT),0) exposition
        FROM   mm GROUP BY COUNTERPARTY),
    rang AS (
        SELECT exposition, ROW_NUMBER() OVER (ORDER BY exposition DESC) rg,
               SUM(exposition) OVER () total
        FROM   expo)
    SELECT MAX(CASE WHEN rg = 1 THEN ROUND(exposition * 100 / NULLIF(total,0), 2) END),
           ROUND(SUM(CASE WHEN rg <= 5  THEN exposition ELSE 0 END) * 100 / NULLIF(MAX(total),0), 2),
           ROUND(SUM(CASE WHEN rg <= 10 THEN exposition ELSE 0 END) * 100 / NULLIF(MAX(total),0), 2)
    INTO   v_num1, v_num2, v_num3
    FROM   rang;
    print_kv('TRS-1005 Part de la 1ere contrepartie dans l''encours MM', TO_CHAR(NVL(v_num1,0)) || ' %');
    print_kv('TRS-1005 Part des 5 premieres contreparties', TO_CHAR(NVL(v_num2,0)) || ' %');
    print_kv('TRS-1005 Part des 10 premieres contreparties', TO_CHAR(NVL(v_num3,0)) || ' %');

    -- ---------------------------------------------------------
    -- TRS-1006 : expositions sur apparentes
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT m.CONTRACT_REF_NO), NVL(SUM(m.LCY_AMOUNT),0)
    INTO   v_count, v_num1
    FROM  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.MATURITY_DATE,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE  NVL(cu.RP_CUSTOMER,'N') = 'Y' OR NVL(cu.STAFF,'N') = 'Y';
    print_test('TRS-1006 Contrats MM sur contreparties apparentees (RP_CUSTOMER / STAFF)',
               v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Exposition sur apparentes (' || p_ccy_locale || ')',
                 TO_CHAR(v_num1, 'FM999G999G999G990'));
        IF p_fpn_xaf IS NOT NULL AND p_fpn_xaf > 0 THEN
            print_kv('  Exposition apparentes en % des FPN',
                     TO_CHAR(ROUND(v_num1 * 100 / p_fpn_xaf, 2)) || ' %');
        END IF;
    END IF;

    -- ---------------------------------------------------------
    -- TRS-1007 : exposition souveraine
    -- ---------------------------------------------------------
    print_sub('TRS-1007 : Exposition souveraine et titres publics');
    tbl_line('4,13,32,12,20,16,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' EMETTEUR',32) || '|'
        || RPAD(' CATEGORIE',12) || '|' || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' NB CONTRATS',16) || '|'
        || RPAD(' MATUR. MOY',14) || '|');
    tbl_line('4,13,32,12,20,16,14');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.VALUE_DATE, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin))
        SELECT mm.COUNTERPARTY, NVL(SUBSTR(MAX(cu.CUSTOMER_NAME1),1,30),'(inconnu)') nom,
               NVL(MAX(cu.CUSTOMER_CATEGORY),'-') cat,
               NVL(SUM(mm.LCY_AMOUNT),0) mt, COUNT(*) nb,
               ROUND(AVG(mm.MATURITY_DATE - mm.VALUE_DATE),0) duree
        FROM   mm JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY
        WHERE  UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'GOVT%'
           OR  UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSE%'
           OR  UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSC%'
        GROUP BY mm.COUNTERPARTY
        ORDER BY NVL(SUM(mm.LCY_AMOUNT),0) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.COUNTERPARTY,13) || '|' || RPAD(' ' || d.nom,32) || '|'
            || RPAD(' ' || SUBSTR(d.cat,1,10),12) || '|'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.nb,'FM999G990'),15) || ' |'
            || LPAD(TO_CHAR(NVL(d.duree,0),'FM999G990') || ' j',13) || ' |');
    END LOOP;
    tbl_line('4,13,32,12,20,16,14');
    IF v_row_num = 0 THEN
        print_note('(aucune contrepartie souveraine identifiee par la categorie client)');
    END IF;
    print_note('Reperes marche des titres publics CEMAC : BTA = 13/26/52 semaines (VN 1 000 000 FCFA),');
    print_note('OTA = 2 a 10 ans. Voir le classement par duree ci-dessus.');

    -- ---------------------------------------------------------
    -- TRS-1010 / TRS-1011 : echeancier de liquidite emplois / ressources
    -- ---------------------------------------------------------
    print_sub('TRS-1010 : Echeancier de liquidite MM (emplois / ressources par bande)');
    tbl_line('4,18,20,20,20,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' BANDE',18) || '|' || RPAD(' EMPLOIS (M XAF)',20) || '|'
        || RPAD(' RESSOURCES (M XAF)',20) || '|' || RPAD(' GAP (M XAF)',20) || '|'
        || RPAD(' GAP CUMULE (M)',20) || '|');
    tbl_line('4,18,20,20,20,20');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND MATURITY_DATE > v_dt_fin),
        classe AS (
            SELECT CASE
                     WHEN mm.MATURITY_DATE - v_dt_fin <=   31 THEN '1. <= 1 mois'
                     WHEN mm.MATURITY_DATE - v_dt_fin <=   92 THEN '2. 1 a 3 mois'
                     WHEN mm.MATURITY_DATE - v_dt_fin <=  183 THEN '3. 3 a 6 mois'
                     WHEN mm.MATURITY_DATE - v_dt_fin <=  366 THEN '4. 6 a 12 mois'
                     WHEN mm.MATURITY_DATE - v_dt_fin <=  731 THEN '5. 1 a 2 ans'
                     WHEN mm.MATURITY_DATE - v_dt_fin <= 1827 THEN '6. 2 a 5 ans'
                     ELSE                                          '7. > 5 ans'
                   END AS bande,
                   CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P' THEN mm.LCY_AMOUNT ELSE 0 END AS emploi,
                   CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B' THEN mm.LCY_AMOUNT ELSE 0 END AS ressource
            FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT),
        agg AS (
            SELECT bande, NVL(SUM(emploi),0) emplois, NVL(SUM(ressource),0) ressources
            FROM   classe GROUP BY bande)
        SELECT bande, emplois, ressources, emplois - ressources AS gap,
               SUM(emplois - ressources) OVER (ORDER BY bande) AS gap_cumule
        FROM   agg ORDER BY bande) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.bande,18) || '|'
            || LPAD(TO_CHAR(d.emplois/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(d.ressources/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(d.gap/1000000,'FMS999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(d.gap_cumule/1000000,'FMS999G999G990D00'),19) || ' |');
    END LOOP;
    tbl_line('4,18,20,20,20,20');
    print_note('Norme COBAC : rapport de liquidite >= 100 % (disponibilites / exigibilites a 1 mois),');
    print_note('coefficient de transformation a long terme >= 50 % (emplois / ressources > 5 ans).');
    print_note('Les montants ci-dessus ne couvrent que le module MM : ils alimentent le ratio,');
    print_note('ils ne le constituent pas.');

    -- ---------------------------------------------------------
    -- TRS-1020 / TRS-1021 / TRS-1022 : positions de change
    -- ---------------------------------------------------------
    print_sub('TRS-1020 : Position de change issue des operations MM (R-2003/02)');
    tbl_line('4,10,20,20,22,12,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DEVISE',10) || '|' || RPAD(' EMPLOIS (M XAF)',20) || '|'
        || RPAD(' RESSOURCES (M XAF)',20) || '|' || RPAD(' POSITION NETTE (M)',22) || '|' || RPAD(' % FPN',12) || '|'
        || RPAD(' SENS',14) || '|');
    tbl_line('4,10,20,20,22,12,14');
    v_row_num := 0;
    v_num4 := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.PRODUCT, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin))
        SELECT mm.CURRENCY,
               NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P' THEN mm.LCY_AMOUNT ELSE 0 END),0) emplois,
               NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B' THEN mm.LCY_AMOUNT ELSE 0 END),0) ressources
        FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
        WHERE  mm.CURRENCY <> p_ccy_locale
        GROUP BY mm.CURRENCY
        ORDER BY ABS(NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P' THEN mm.LCY_AMOUNT ELSE 0 END),0)
                   - NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B' THEN mm.LCY_AMOUNT ELSE 0 END),0)) DESC) LOOP
        v_row_num := v_row_num + 1;
        v_num4 := v_num4 + ABS(d.emplois - d.ressources);
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.CURRENCY,10) || '|'
            || LPAD(TO_CHAR(d.emplois/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR(d.ressources/1000000,'FM999G999G990D00'),19) || ' |'
            || LPAD(TO_CHAR((d.emplois - d.ressources)/1000000,'FMS999G999G990D00'),21) || ' |'
            || LPAD(CASE WHEN p_fpn_xaf IS NULL OR p_fpn_xaf = 0 THEN 'n/a'
                    ELSE TO_CHAR(ROUND(ABS(d.emplois - d.ressources) * 100 / p_fpn_xaf, 2),'FM9990D00') END, 11) || ' |'
            || RPAD(' ' || CASE WHEN d.emplois > d.ressources THEN 'LONGUE'
                                WHEN d.emplois < d.ressources THEN 'COURTE'
                                ELSE 'EQUILIBREE' END, 14) || '|');
    END LOOP;
    tbl_line('4,10,20,20,22,12,14');
    IF v_row_num = 0 THEN
        print_note('(aucune operation MM en devises etrangeres)');
    ELSE
        print_kv('Position de change globale MM (somme des valeurs absolues, ' || p_ccy_locale || ')',
                 TO_CHAR(v_num4, 'FM999G999G999G999G990'));
        IF p_fpn_xaf IS NOT NULL AND p_fpn_xaf > 0 THEN
            print_kv('Position globale en % des FPN',
                     TO_CHAR(ROUND(v_num4 * 100 / p_fpn_xaf, 2)) || ' % (limite parametree : '
                     || TO_CHAR(p_seuil_chg_global) || ' %)');
            IF v_num4 * 100 / p_fpn_xaf > p_seuil_chg_global THEN
                print_test('TRS-1022 Depassement de la limite de position de change globale', 1, NULL, 'CRITIQUE');
            ELSE
                print_test('TRS-1022 Depassement de la limite de position de change globale', 0, NULL, 'CRITIQUE');
            END IF;
        END IF;
        print_note('Les seuils de R-2003/02 doivent etre confirmes sur le texte officiel (BRD, PAC-08).');
    END IF;

    -- ---------------------------------------------------------
    -- TRS-1024 : fraicheur des cours de change
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT m.CURRENCY FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND CURRENCY <> p_ccy_locale
            AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
        WHERE NVL((SELECT MAX(r.RATE_DATE) FROM CYTB_RATES_HISTORY r
                   WHERE r.CCY1 = m.CURRENCY AND r.CCY2 = p_ccy_locale),
                  DATE '1900-01-01') < v_dt_fin - 7);
    print_test('TRS-1024 Devises en position dont le dernier cours date de plus de 7 jours',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1030 : ventilation par nature de contrepartie
    -- ---------------------------------------------------------
    print_sub('TRS-1030 : Ventilation de l''encours par nature de contrepartie');
    tbl_line('4,28,12,20,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' NATURE',28) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' ENCOURS (M XAF)',20) || '|' || RPAD(' % TOTAL',12) || '|');
    tbl_line('4,28,12,20,12');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)),
        nat AS (
            SELECT CASE
                     WHEN UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'GOVT%' THEN '1. Souverain / Etat'
                     WHEN UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSE%'
                       OR UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE 'PSC%'  THEN '2. Secteur public'
                     WHEN cu.CUSTOMER_TYPE = 'B'
                       AND NVL(cu.COUNTRY,'') IN ('CMR','CAF','TCD','COG','GAB','GNQ',
                                                  'CM','CF','TD','CG','GA','GQ')      THEN '3. Banque zone CEMAC'
                     WHEN cu.CUSTOMER_TYPE = 'B'                            THEN '4. Banque hors CEMAC'
                     WHEN UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) IN ('OFI','FIN_INT','INSURANCE')
                                                                            THEN '5. Autre inst. financiere'
                     WHEN cu.CUSTOMER_NO IS NULL                            THEN '7. Contrepartie inconnue'
                     ELSE                                                        '6. Clientele non financiere'
                   END AS nature, mm.LCY_AMOUNT
            FROM   mm LEFT JOIN STTM_CUSTOMER cu ON cu.CUSTOMER_NO = mm.COUNTERPARTY)
        SELECT nature, COUNT(*) nb, NVL(SUM(LCY_AMOUNT),0) mt,
               ROUND(RATIO_TO_REPORT(NVL(SUM(LCY_AMOUNT),0)) OVER () * 100, 2) pct
        FROM   nat GROUP BY nature ORDER BY nature) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.nature,28) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',19) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),11) || ' |');
    END LOOP;
    tbl_line('4,28,12,20,12');

    -- ---------------------------------------------------------
    -- TRS-1032 : categorie d'exposition non renseignee
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.EXPOSURE_CATEGORY,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND (EXPOSURE_CATEGORY IS NULL OR TRIM(EXPOSURE_CATEGORY) IS NULL));
    print_test('TRS-1032 Contrats sans categorie d''exposition renseignee', v_count, NULL, 'MAJEUR');


    -- ---------------------------------------------------------
    -- TRS-1012 / TRS-1013 : contributions liquidite et transformation
    -- ---------------------------------------------------------
    print_sub('TRS-1012 / TRS-1013 : Contribution du module MM aux ratios structurels');
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE > v_dt_fin)
    SELECT NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P'
                         AND mm.MATURITY_DATE - v_dt_fin <= 31 THEN mm.LCY_AMOUNT ELSE 0 END),0),
           NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B'
                         AND mm.MATURITY_DATE - v_dt_fin <= 31 THEN mm.LCY_AMOUNT ELSE 0 END),0),
           NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'P'
                         AND mm.MATURITY_DATE - v_dt_fin > 1827 THEN mm.LCY_AMOUNT ELSE 0 END),0),
           NVL(SUM(CASE WHEN UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B'
                         AND mm.MATURITY_DATE - v_dt_fin > 1827 THEN mm.LCY_AMOUNT ELSE 0 END),0)
    INTO   v_num1, v_num2, v_num3, v_num4
    FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT;

    print_kv('Emplois MM a moins d''un mois (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
    print_kv('Ressources MM a moins d''un mois (' || p_ccy_locale || ')', TO_CHAR(v_num2, 'FM999G999G999G990'));
    IF v_num2 > 0 THEN
        print_kv('TRS-1012 Contribution MM au rapport de liquidite',
                 TO_CHAR(ROUND(v_num1 * 100 / v_num2, 1)) || ' % (norme globale COBAC : >= 100 %)');
    ELSE
        print_kv('TRS-1012 Contribution MM au rapport de liquidite', 'aucune exigibilite MM a un mois');
    END IF;
    print_kv('Emplois MM a plus de 5 ans (' || p_ccy_locale || ')', TO_CHAR(v_num3, 'FM999G999G999G990'));
    print_kv('Ressources MM a plus de 5 ans (' || p_ccy_locale || ')', TO_CHAR(v_num4, 'FM999G999G999G990'));
    IF v_num3 > 0 THEN
        print_kv('TRS-1013 Couverture MM des emplois longs par des ressources longues',
                 TO_CHAR(ROUND(v_num4 * 100 / v_num3, 1)) || ' % (norme globale COBAC : >= 50 %)');
    ELSE
        print_kv('TRS-1013 Couverture MM des emplois longs', 'aucun emploi MM a plus de 5 ans');
    END IF;
    print_note('Ces indicateurs sont des contributions du seul module MM : ils ne constituent pas');
    print_note('les ratios reglementaires, qui se calculent sur l''ensemble du bilan.');

    -- ---------------------------------------------------------
    -- TRS-1014 : concentration des ressources sur une echeance
    -- ---------------------------------------------------------
    WITH mm AS (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.PRODUCT, c.LCY_AMOUNT, c.MATURITY_DATE,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND MATURITY_DATE > v_dt_fin),
    res AS (
        SELECT mm.MATURITY_DATE, SUM(mm.LCY_AMOUNT) mt
        FROM   mm LEFT JOIN LDTM_PRODUCT_MASTER pm ON pm.PRODUCT = mm.PRODUCT
        WHERE  UPPER(NVL(pm.PRODUCT_TYPE,'?')) = 'B'
        GROUP BY mm.MATURITY_DATE),
    part AS (
        SELECT MATURITY_DATE, mt, RATIO_TO_REPORT(mt) OVER () * 100 pct FROM res)
    SELECT COUNT(*) INTO v_count FROM part WHERE pct > 25;
    print_test('TRS-1014 Dates d''echeance concentrant plus de 25% des ressources MM',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1015 : echeancier retraite du comportement de rollover
    -- ---------------------------------------------------------
    print_sub('TRS-1015 : Echeancier retraite (maturite effective des contrats renouveles)');
    tbl_line('4,18,22,22,22');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' BANDE',18) || '|'
        || RPAD(' ENCOURS AFFICHE (M)',22) || '|' || RPAD(' ENCOURS RETRAITE (M)',22) || '|'
        || RPAD(' ECART (M XAF)',22) || '|');
    tbl_line('4,18,22,22,22');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.LCY_AMOUNT, c.MATURITY_DATE,
                       c.ORIGINAL_START_DATE, c.VALUE_DATE, NVL(c.ROLLOVER_COUNT,0) nbr,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND MATURITY_DATE > v_dt_fin),
        proj AS (
            SELECT LCY_AMOUNT,
                   MATURITY_DATE - v_dt_fin AS j_affiche,
                   CASE WHEN nbr > 0 AND ORIGINAL_START_DATE IS NOT NULL AND VALUE_DATE IS NOT NULL
                             AND VALUE_DATE > ORIGINAL_START_DATE
                             AND MATURITY_DATE > VALUE_DATE
                        THEN (MATURITY_DATE - v_dt_fin)
                             * GREATEST(1, ROUND((MATURITY_DATE - ORIGINAL_START_DATE)
                                                 / (MATURITY_DATE - VALUE_DATE)))
                        ELSE (MATURITY_DATE - v_dt_fin)
                   END AS j_retraite
            FROM   mm),
        cls AS (
            SELECT CASE WHEN j_affiche <=   31 THEN '1. <= 1 mois'
                        WHEN j_affiche <=   92 THEN '2. 1 a 3 mois'
                        WHEN j_affiche <=  183 THEN '3. 3 a 6 mois'
                        WHEN j_affiche <=  366 THEN '4. 6 a 12 mois'
                        WHEN j_affiche <=  731 THEN '5. 1 a 2 ans'
                        WHEN j_affiche <= 1827 THEN '6. 2 a 5 ans'
                        ELSE                        '7. > 5 ans' END AS b_aff,
                   CASE WHEN j_retraite <=   31 THEN '1. <= 1 mois'
                        WHEN j_retraite <=   92 THEN '2. 1 a 3 mois'
                        WHEN j_retraite <=  183 THEN '3. 3 a 6 mois'
                        WHEN j_retraite <=  366 THEN '4. 6 a 12 mois'
                        WHEN j_retraite <=  731 THEN '5. 1 a 2 ans'
                        WHEN j_retraite <= 1827 THEN '6. 2 a 5 ans'
                        ELSE                         '7. > 5 ans' END AS b_ret,
                   LCY_AMOUNT
            FROM   proj),
        aff AS (SELECT b_aff bande, SUM(LCY_AMOUNT) mt FROM cls GROUP BY b_aff),
        ret AS (SELECT b_ret bande, SUM(LCY_AMOUNT) mt FROM cls GROUP BY b_ret)
        SELECT NVL(aff.bande, ret.bande) bande, NVL(aff.mt,0) mt_aff, NVL(ret.mt,0) mt_ret,
               NVL(ret.mt,0) - NVL(aff.mt,0) ecart
        FROM   aff FULL OUTER JOIN ret ON ret.bande = aff.bande
        ORDER BY 1) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.bande,18) || '|'
            || LPAD(TO_CHAR(d.mt_aff/1000000,'FM999G999G990D00'),21) || ' |'
            || LPAD(TO_CHAR(d.mt_ret/1000000,'FM999G999G990D00'),21) || ' |'
            || LPAD(TO_CHAR(d.ecart/1000000,'FMS999G999G990D00'),21) || ' |');
    END LOOP;
    tbl_line('4,18,22,22,22');
    print_note('Retraitement : la maturite des contrats renouveles est etendue au prorata du');
    print_note('nombre de renouvellements deja observes. Indicateur d''alerte, non normatif.');

    -- ---------------------------------------------------------
    -- TRS-1023 : devises en position sans reevaluation recente
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT m.CURRENCY FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.CURRENCY, c.MATURITY_DATE,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND CURRENCY <> p_ccy_locale
            AND  (MATURITY_DATE IS NULL OR MATURITY_DATE > v_dt_fin)) m
        WHERE NOT EXISTS (SELECT 1 FROM RVTB_ACC_REVAL r
                          WHERE r.CCY = m.CURRENCY AND r.REVAL_DATE >= v_dt_fin - 31));
    print_test('TRS-1023 Devises en position sans reevaluation dans le dernier mois',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1031 : creances en souffrance et provisionnement (R-2018/01)
    -- ---------------------------------------------------------
    print_sub('TRS-1031 : Creances MM en souffrance et couverture par provisions');
    tbl_line('4,24,12,26,26,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PALIER',24) || '|' || RPAD(' NB CTR',12) || '|'
        || RPAD(' IMPAYE',26) || '|' || RPAD(' PROVISION CONSTATEE',26) || '|' || RPAD(' TX COUV.',14) || '|');
    tbl_line('4,24,12,26,26,14');
    v_row_num := 0;
    FOR d IN (
        WITH imp AS (
            SELECT l.CONTRACT_REF_NO,
                   CASE WHEN MAX(NVL(l.OVERDUE_DAYS,0)) <= p_jours_retard_2 THEN '1. <= 90 jours'
                        WHEN MAX(NVL(l.OVERDUE_DAYS,0)) <= p_jours_retard_3 THEN '2. 91 a 180 jours'
                        WHEN MAX(NVL(l.OVERDUE_DAYS,0)) <= p_jours_retard_4 THEN '3. 181 a 360 jours'
                        ELSE                                                     '4. plus de 360 jours'
                   END AS palier,
                   SUM(NVL(l.AMOUNT_DUE,0) - NVL(l.AMOUNT_PAID,0)) AS impaye
            FROM   LDTB_CONTRACT_LIQ l
            WHERE  l.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    NVL(l.AMOUNT_DUE,0) > NVL(l.AMOUNT_PAID,0) + 0.01
            GROUP BY l.CONTRACT_REF_NO),
        prov AS (
            SELECT h.TRN_REF_NO, SUM(h.LCY_AMOUNT) mt
            FROM   ACTB_HISTORY h
            WHERE  h.MODULE = p_module
            AND   (UPPER(h.AMOUNT_TAG) LIKE '%PROV%' OR UPPER(h.EVENT) LIKE '%PROV%')
            GROUP BY h.TRN_REF_NO)
        SELECT imp.palier, COUNT(*) nb, SUM(imp.impaye) tot_imp, NVL(SUM(prov.mt),0) tot_prov
        FROM   imp LEFT JOIN prov ON prov.TRN_REF_NO = imp.CONTRACT_REF_NO
        GROUP BY imp.palier ORDER BY imp.palier) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.palier,24) || '|' || LPAD(TO_CHAR(d.nb,'FM999G990'),11) || ' |'
            || LPAD(TO_CHAR(d.tot_imp,'FM999G999G999G990'),25) || ' |'
            || LPAD(TO_CHAR(d.tot_prov,'FM999G999G999G990'),25) || ' |'
            || LPAD(CASE WHEN NVL(d.tot_imp,0) = 0 THEN 'n/a'
                    ELSE TO_CHAR(ROUND(d.tot_prov * 100 / d.tot_imp, 1),'FM9990D0') || ' %' END, 13) || ' |');
    END LOOP;
    tbl_line('4,24,12,26,26,14');
    IF v_row_num = 0 THEN
        print_note('(aucune creance MM en souffrance a la date d''arrete)');
    ELSE
        print_note('COBAC R-2018/01 : le classement et le provisionnement dependent de la nature de');
        print_note('la contrepartie et des garanties. Le taux de couverture ci-dessus est indicatif.');
    END IF;


    -- =========================================================
    -- SECTION 11 : CONTROLE INTERNE ET HABILITATIONS
    -- =========================================================
    print_section('SECTION 11 : CONTROLE INTERNE ET HABILITATIONS (COBAC R-2016/04)');

    -- ---------------------------------------------------------
    -- TRS-1101 / TRS-1102 : separation des taches
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT h.TRN_REF_NO), NVL(SUM(h.LCY_AMOUNT),0)
    INTO   v_count, v_count2, v_num1
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    h.USER_ID = h.AUTH_ID
    AND    INSTR(p_users_techniques, ',' || TRIM(h.USER_ID) || ',') = 0;
    print_test('TRS-1101 Ecritures MM auto-validees (maker = checker)', v_count, NULL, 'CRITIQUE');
    IF v_count > 0 THEN
        print_kv('  Contrats concernes', TO_CHAR(v_count2));
        print_kv('  Montant cumule (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
        tbl_line('4,20,32,14,22,12,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' UTILISATEUR',20) || '|' || RPAD(' NOM',32) || '|'
            || RPAD(' NB ECRITURES',14) || '|' || RPAD(' MONTANT (M XAF)',22) || '|' || RPAD(' 1ere DATE',12) || '|'
            || RPAD(' DERN. DATE',12) || '|');
        tbl_line('4,20,32,14,22,12,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.USER_ID, NVL(SUBSTR(MAX(u.USER_NAME),1,30),'(inconnu)') nom,
                   COUNT(*) nb, SUM(h.LCY_AMOUNT) mt, MIN(h.TRN_DT) d1, MAX(h.TRN_DT) d2
            FROM   ACTB_HISTORY h
            LEFT JOIN SMTB_USER u ON u.USER_ID = h.USER_ID
            WHERE  h.MODULE = p_module AND h.USER_ID = h.AUTH_ID
            AND    INSTR(p_users_techniques, ',' || TRIM(h.USER_ID) || ',') = 0
            GROUP BY h.USER_ID
            ORDER BY SUM(h.LCY_AMOUNT) DESC) WHERE ROWNUM <= p_echantillon) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.USER_ID,1,18),20) || '|' || RPAD(' ' || d.nom,32) || '|'
                || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
                || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',21) || ' |'
                || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),12) || '|'
                || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),12) || '|');
        END LOOP;
        tbl_line('4,20,32,14,22,12,12');
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module AND (h.AUTH_ID IS NULL OR TRIM(h.AUTH_ID) IS NULL);
    print_test('TRS-1102 Ecritures MM sans valideur (AUTH_ID absent)', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1103 : concentration de l'activite par operateur
    -- ---------------------------------------------------------
    print_sub('TRS-1103 : Principaux operateurs sur le module MM');
    tbl_line('4,20,30,14,22,10,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' UTILISATEUR',20) || '|' || RPAD(' NOM',30) || '|'
        || RPAD(' NB ECRITURES',14) || '|' || RPAD(' MONTANT (M XAF)',22) || '|' || RPAD(' % ECR',10) || '|'
        || RPAD(' STATUT',12) || '|');
    tbl_line('4,20,30,14,22,10,12');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT h.USER_ID, NVL(SUBSTR(MAX(u.USER_NAME),1,28),'(inconnu)') nom,
               COUNT(*) nb, SUM(h.LCY_AMOUNT) mt,
               ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 2) pct,
               NVL(MAX(u.USER_STATUS),'-') st
        FROM   ACTB_HISTORY h
        LEFT JOIN SMTB_USER u ON u.USER_ID = h.USER_ID
        WHERE  h.MODULE = p_module
        GROUP BY h.USER_ID
        ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 20) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.USER_ID,1,18),20) || '|' || RPAD(' ' || d.nom,30) || '|'
            || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.mt/1000000,'FM999G999G990D00') || ' M',21) || ' |'
            || LPAD(TO_CHAR(d.pct,'FM990D00'),9) || ' |' || RPAD(' ' || d.st,12) || '|');
    END LOOP;
    tbl_line('4,20,30,14,22,10,12');

    -- ---------------------------------------------------------
    -- TRS-1104 / TRS-1105 : habilitations
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.USER_ID) INTO v_count
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = h.USER_ID);
    print_test('TRS-1104 Operateurs MM absents du referentiel utilisateurs', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(DISTINCT h.USER_ID) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   SMTB_USER u ON u.USER_ID = h.USER_ID
    WHERE  h.MODULE = p_module AND NVL(u.USER_STATUS,'E') <> 'E';
    print_test('TRS-1104 Operateurs MM dont le compte n''est pas actif', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(DISTINCT h.USER_ID) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   SMTB_USER u ON u.USER_ID = h.USER_ID
    WHERE  h.MODULE = p_module
    AND    NOT EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.USER_ID = u.USER_ID);
    print_test('TRS-1105 Operateurs MM sans role attribue', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(DISTINCT u.USER_ID) INTO v_count
    FROM   SMTB_USER u
    WHERE  NVL(u.AUTO_AUTH,'N') = 'Y'
    AND    EXISTS (SELECT 1 FROM ACTB_HISTORY h WHERE h.USER_ID = u.USER_ID AND h.MODULE = p_module);
    print_test('TRS-1105 Operateurs MM disposant de l''auto-autorisation (AUTO_AUTH = Y)',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1106 : depassement des limites utilisateur
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   SMTB_USER u ON u.USER_ID = h.USER_ID
    WHERE  h.MODULE = p_module
    AND    NVL(u.MAX_TXN_AMT,0) > 0 AND h.LCY_AMOUNT > u.MAX_TXN_AMT;
    print_test('TRS-1106 Ecritures MM au-dela de la limite de saisie de l''operateur',
               v_count, NULL, 'CRITIQUE');

    SELECT COUNT(*) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   SMTB_USER u ON u.USER_ID = h.AUTH_ID
    WHERE  h.MODULE = p_module
    AND    NVL(u.MAX_AUTH_AMT,0) > 0 AND h.LCY_AMOUNT > u.MAX_AUTH_AMT;
    print_test('TRS-1106 Ecritures MM au-dela de la limite de validation du valideur',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1108 : operations en week-end
    -- ---------------------------------------------------------
    SELECT COUNT(*), COUNT(DISTINCT h.TRN_REF_NO) INTO v_count, v_count2
    FROM   ACTB_HISTORY h
    WHERE  h.MODULE = p_module
    AND    TO_CHAR(h.TRN_DT, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') IN ('SAT','SUN')
    AND    INSTR(p_users_techniques, ',' || TRIM(h.USER_ID) || ',') = 0;
    print_test('TRS-1108 Ecritures MM saisies un week-end par un operateur humain',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1109 : piste d'audit contractuelle
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
    WHERE NOT EXISTS (SELECT 1 FROM LDTB_CONTRACT_CONTROL c WHERE c.CONTRACT_REF_NO = m.CONTRACT_REF_NO);
    print_test('TRS-1109 Contrats sans trace dans LDTB_CONTRACT_CONTROL', v_count, NULL, 'MAJEUR');

    print_sub('TRS-1109 : Processus traces sur les contrats MM');
    tbl_line('4,24,14,20,12,12');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PROCESS_CODE',24) || '|' || RPAD(' NB',14) || '|'
        || RPAD(' NB UTILISATEURS',20) || '|' || RPAD(' 1ere DATE',12) || '|' || RPAD(' DERN. DATE',12) || '|');
    tbl_line('4,24,14,20,12,12');
    v_row_num := 0;
    FOR d IN (SELECT NVL(c.PROCESS_CODE,'(vide)') pc, COUNT(*) nb,
                     COUNT(DISTINCT c.ENTRY_BY) nbu, MIN(c.ENTRY_TIME) d1, MAX(c.ENTRY_TIME) d2
              FROM   LDTB_CONTRACT_CONTROL c
              WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY c.PROCESS_CODE ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        EXIT WHEN v_row_num > 25;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.pc,1,22),24) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),13) || ' |'
            || LPAD(TO_CHAR(d.nbu,'FM999G990'),19) || ' |'
            || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),12) || '|'
            || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),12) || '|');
    END LOOP;
    tbl_line('4,24,14,20,12,12');

    -- ---------------------------------------------------------
    -- TRS-1111 / TRS-1112 : separation front / back office
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT m.DEALER) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.DEALER,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND DEALER IS NOT NULL AND TRIM(DEALER) IS NOT NULL) m
    WHERE NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = m.DEALER);
    print_test('TRS-1111 Dealers MM non recenses au referentiel utilisateurs', v_count, NULL, 'MAJEUR');

    SELECT COUNT(DISTINCT h.TRN_REF_NO) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.DEALER,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1 AND DEALER IS NOT NULL AND TRIM(DEALER) IS NOT NULL) m
      ON m.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE h.MODULE = p_module AND (h.USER_ID = m.DEALER OR h.AUTH_ID = m.DEALER);
    print_test('TRS-1112 Contrats dont le dealer intervient aussi en comptabilite',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1114 / TRS-1115 : modifications de parametrage
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count
    FROM   CSTM_PRODUCT cp
    WHERE  cp.PRODUCT_CODE IN (SELECT DISTINCT PRODUCT FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    cp.CHECKER_DT_STAMP BETWEEN v_dt_deb AND v_dt_fin;
    print_test('TRS-1114 Produits MM modifies sur la periode auditee', v_count, NULL, 'MAJEUR');


    -- ---------------------------------------------------------
    -- TRS-1107 : operations hors plage horaire ouvrable
    -- ---------------------------------------------------------
    print_sub('TRS-1107 : Repartition horaire des interventions sur contrats MM');
    tbl_line('4,20,16,20');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' PLAGE HORAIRE',20) || '|'
        || RPAD(' NB INTERVENTIONS',16) || '|' || RPAD(' NB UTILISATEURS',20) || '|');
    tbl_line('4,20,16,20');
    v_row_num := 0;
    FOR d IN (
        SELECT plage, COUNT(*) nb, COUNT(DISTINCT operateur) nbu
        FROM (
            SELECT c.ENTRY_BY AS operateur,
                   CASE
                     WHEN TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) <  7 THEN '1. 00h - 07h'
                     WHEN TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) < 12 THEN '2. 07h - 12h'
                     WHEN TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) < 18 THEN '3. 12h - 18h'
                     WHEN TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) < 21 THEN '4. 18h - 21h'
                     ELSE                                                   '5. 21h - 24h'
                   END AS plage
            FROM   LDTB_CONTRACT_CONTROL c
            WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO
                                         FROM   LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
            AND    c.ENTRY_TIME IS NOT NULL)
        GROUP BY plage
        ORDER BY plage) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.plage,20) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),15) || ' |'
            || LPAD(TO_CHAR(d.nbu,'FM999G990'),19) || ' |');
    END LOOP;
    tbl_line('4,20,16,20');

    SELECT COUNT(*) INTO v_count
    FROM   LDTB_CONTRACT_CONTROL c
    WHERE  c.CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    AND    c.ENTRY_TIME IS NOT NULL
    AND   (TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) < 7 OR TO_NUMBER(TO_CHAR(c.ENTRY_TIME,'HH24')) >= 21)
    AND    INSTR(p_users_techniques, ',' || TRIM(c.ENTRY_BY) || ',') = 0;
    print_test('TRS-1107 Interventions humaines sur contrats MM hors plage 07h-21h',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1110 : cumul des fonctions saisie contrat / validation comptable
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.TRN_REF_NO) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN   LDTB_CONTRACT_CONTROL c ON c.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE  h.MODULE = p_module
    AND    h.AUTH_ID = c.ENTRY_BY
    AND    INSTR(p_users_techniques, ',' || TRIM(h.AUTH_ID) || ',') = 0;
    print_test('TRS-1110 Contrats ou l''intervenant a aussi valide l''ecriture comptable',
               v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1113 : activite de connexion des operateurs MM
    -- ---------------------------------------------------------
    print_sub('TRS-1113 : Activite de connexion des principaux operateurs MM');
    tbl_line('4,20,16,16,14,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' UTILISATEUR',20) || '|' || RPAD(' NB SESSIONS',16) || '|'
        || RPAD(' NB JOURS',16) || '|' || RPAD(' 1ere DATE',14) || '|' || RPAD(' DERN. DATE',14) || '|');
    tbl_line('4,20,16,16,14,14');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT l.USER_ID, COUNT(*) nb, COUNT(DISTINCT TRUNC(l.START_TIME)) nbj,
               MIN(l.START_TIME) d1, MAX(l.START_TIME) d2
        FROM   SMTB_SMS_LOG l
        WHERE  l.USER_ID IN (SELECT DISTINCT USER_ID FROM ACTB_HISTORY WHERE MODULE = p_module)
        AND    l.START_TIME BETWEEN v_dt_deb AND v_dt_fin + 1
        GROUP BY l.USER_ID
        ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 15) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.USER_ID,1,18),20) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),15) || ' |'
            || LPAD(TO_CHAR(d.nbj,'FM999G990'),15) || ' |'
            || RPAD(' ' || TO_CHAR(d.d1,'DD/MM/YYYY'),14) || '|'
            || RPAD(' ' || TO_CHAR(d.d2,'DD/MM/YYYY'),14) || '|');
    END LOOP;
    tbl_line('4,20,16,16,14,14');
    IF v_row_num = 0 THEN
        print_note('(aucune trace de connexion sur la periode pour les operateurs MM)');
    END IF;


    -- =========================================================
    -- SECTION 12 : QUALITE DE DONNEES ET REFERENTIELS
    -- =========================================================
    print_section('SECTION 12 : QUALITE DE DONNEES ET REFERENTIELS');

    -- ---------------------------------------------------------
    -- TRS-1201 : completude des colonnes cles
    -- ---------------------------------------------------------
    print_sub('TRS-1201 : Completude des attributs cles du contrat');
    SELECT COUNT(*) INTO v_total FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1);
    tbl_line('4,30,14,14,14');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' ATTRIBUT',30) || '|' || RPAD(' RENSEIGNES',14) || '|'
        || RPAD(' MANQUANTS',14) || '|' || RPAD(' % COMPLET',14) || '|');
    tbl_line('4,30,14,14,14');
    v_row_num := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.CURRENCY, c.DEALER, c.BROKER_CODE,
                       c.CREDIT_LINE, c.USER_REF_NO, c.DFLT_SETTLE_AC, c.EXPOSURE_CATEGORY,
                       c.MATURITY_DATE, c.TRADE_DATE, c.DEALING_METHOD, c.TAX_SCHEME,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT 'COUNTERPARTY'      AS att, COUNT(TRIM(COUNTERPARTY))      AS ok FROM mm UNION ALL
        SELECT 'CURRENCY',              COUNT(TRIM(CURRENCY))                  FROM mm UNION ALL
        SELECT 'DEALER',                COUNT(TRIM(DEALER))                    FROM mm UNION ALL
        SELECT 'BROKER_CODE',           COUNT(TRIM(BROKER_CODE))               FROM mm UNION ALL
        SELECT 'CREDIT_LINE',           COUNT(TRIM(CREDIT_LINE))               FROM mm UNION ALL
        SELECT 'USER_REF_NO',           COUNT(TRIM(USER_REF_NO))               FROM mm UNION ALL
        SELECT 'DFLT_SETTLE_AC',        COUNT(TRIM(DFLT_SETTLE_AC))            FROM mm UNION ALL
        SELECT 'EXPOSURE_CATEGORY',     COUNT(TRIM(EXPOSURE_CATEGORY))         FROM mm UNION ALL
        SELECT 'MATURITY_DATE',         COUNT(MATURITY_DATE)                   FROM mm UNION ALL
        SELECT 'TRADE_DATE',            COUNT(TRADE_DATE)                      FROM mm UNION ALL
        SELECT 'DEALING_METHOD',        COUNT(TRIM(DEALING_METHOD))            FROM mm UNION ALL
        SELECT 'TAX_SCHEME',            COUNT(TRIM(TAX_SCHEME))                FROM mm) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.att,30) || '|' || LPAD(TO_CHAR(d.ok,'FM999G990'),13) || ' |'
            || LPAD(TO_CHAR(v_total - d.ok,'FM999G990'),13) || ' |'
            || LPAD(CASE WHEN v_total = 0 THEN 'n/a'
                    ELSE TO_CHAR(ROUND(d.ok * 100 / v_total, 1),'FM990D0') || ' %' END, 13) || ' |');
    END LOOP;
    tbl_line('4,30,14,14,14');

    -- ---------------------------------------------------------
    -- TRS-1203 a TRS-1206 : qualite des contreparties (lien AML/CFT)
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT cu.CUSTOMER_NO) INTO v_count
    FROM  (SELECT DISTINCT COUNTERPARTY FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE  NVL(cu.KYC_DETAILS,'N') <> 'V'
       OR  cu.KYC_REF_NO IS NULL OR TRIM(cu.KYC_REF_NO) IS NULL;
    print_test('TRS-1203 Contreparties MM sans KYC valide', v_count, NULL, 'CRITIQUE');

    SELECT COUNT(DISTINCT cu.CUSTOMER_NO) INTO v_count
    FROM  (SELECT DISTINCT COUNTERPARTY FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE  cu.RISK_PROFILE IS NULL OR TRIM(cu.RISK_PROFILE) IS NULL;
    print_test('TRS-1204 Contreparties MM sans profil de risque renseigne', v_count, NULL, 'MAJEUR');

    SELECT COUNT(DISTINCT cu.CUSTOMER_NO), NVL(SUM(m.LCY_AMOUNT),0) INTO v_count, v_num1
    FROM  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.COUNTERPARTY, c.LCY_AMOUNT,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE  NVL(cu.COUNTRY,'') NOT IN ('CMR','CAF','TCD','COG','GAB','GNQ',
                                      'CM','CF','TD','CG','GA','GQ');
    print_test('TRS-1205 Contreparties MM domiciliees hors zone CEMAC', v_count, NULL, 'MAJEUR');
    IF v_count > 0 THEN
        print_kv('  Encours correspondant (' || p_ccy_locale || ')', TO_CHAR(v_num1, 'FM999G999G999G990'));
    END IF;

    SELECT COUNT(DISTINCT cu.CUSTOMER_NO) INTO v_count
    FROM  (SELECT DISTINCT COUNTERPARTY FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module) m
    JOIN   STTM_CUSTOMER cu ON cu.CUSTOMER_NO = m.COUNTERPARTY
    WHERE  UPPER(NVL(cu.CUSTOMER_CATEGORY,'')) LIKE '%PEP%';
    print_test('TRS-1206 Contreparties MM categorisees PEP', v_count, NULL, 'CRITIQUE');

    -- ---------------------------------------------------------
    -- TRS-1210 : coherence des devises de bout en bout
    -- ---------------------------------------------------------
    SELECT COUNT(DISTINCT h.TRN_REF_NO) INTO v_count
    FROM   ACTB_HISTORY h
    JOIN  (SELECT * FROM (
              SELECT c.CONTRACT_REF_NO, c.CURRENCY,
                     ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                          ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
              FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
           WHERE rn = 1) m ON m.CONTRACT_REF_NO = h.TRN_REF_NO
    WHERE  h.MODULE = p_module
    AND    h.AC_CCY <> m.CURRENCY AND h.AC_CCY <> p_ccy_locale;
    print_test('TRS-1210 Contrats dont des ecritures portent une devise tierce', v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1211 : mots-cles d'alerte dans les remarques
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.REMARKS,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1 AND REMARKS IS NOT NULL
        AND  (UPPER(REMARKS) LIKE '%REGULARIS%' OR UPPER(REMARKS) LIKE '%DEROGAT%'
           OR UPPER(REMARKS) LIKE '%EXCEPTION%' OR UPPER(REMARKS) LIKE '%A CORRIGER%'
           OR UPPER(REMARKS) LIKE '%ERREUR%'    OR UPPER(REMARKS) LIKE '%ANNUL%'));
    print_test('TRS-1211 Contrats dont les remarques contiennent un mot-cle d''alerte',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1212 : coherence des effectifs entre tables liees
    -- ---------------------------------------------------------
    print_sub('TRS-1212 : Effectifs par table du perimetre MM');
    tbl_line('4,40,16,16');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' TABLE',40) || '|' || RPAD(' NB LIGNES',16) || '|'
        || RPAD(' NB CONTRATS',16) || '|');
    tbl_line('4,40,16,16');
    v_row_num := 0;
    FOR d IN (
        SELECT 'LDTB_CONTRACT_MASTER' t, COUNT(*) nb, COUNT(DISTINCT CONTRACT_REF_NO) nbc
        FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module
        UNION ALL
        SELECT 'LDTB_CONTRACT_PREFERENCE', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_PREFERENCE
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_SCHEDULES', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_SCHEDULES
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_ICCF_DETAILS', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_ICCF_DETAILS
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_ICCF_CALC', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_ICCF_CALC
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_ACCRUAL_HISTORY', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_ACCRUAL_HISTORY
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_LIQ', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_LIQ
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_LIQ_SUMMARY', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_LIQ_SUMMARY
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_ROLLOVER', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_ROLLOVER
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_BALANCE', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_BALANCE
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_SWIFT_MESSAGE', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_SWIFT_MESSAGE
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'LDTB_CONTRACT_CONTROL', COUNT(*), COUNT(DISTINCT CONTRACT_REF_NO)
        FROM LDTB_CONTRACT_CONTROL
        WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
        UNION ALL
        SELECT 'ACTB_HISTORY (module MM)', COUNT(*), COUNT(DISTINCT TRN_REF_NO)
        FROM ACTB_HISTORY WHERE MODULE = p_module) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.t,40) || '|' || LPAD(TO_CHAR(d.nb,'FM999G999G990'),15) || ' |'
            || LPAD(TO_CHAR(d.nbc,'FM999G999G990'),15) || ' |');
    END LOOP;
    tbl_line('4,40,16,16');


    -- ---------------------------------------------------------
    -- TRS-1202 : attributs uniformement vides sur tout le portefeuille
    -- ---------------------------------------------------------
    v_count := 0;
    FOR d IN (
        WITH mm AS (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.BROKER_CODE, c.CREDIT_LINE, c.EXPOSURE_CATEGORY,
                       c.DEALING_METHOD, c.TAX_SCHEME, c.TRADE_DATE, c.REL_REFERENCE,
                       c.INTERNAL_SWAP_REF_NO, c.CLUSTER_ID, c.SYNDICATION_REF_NO,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1)
        SELECT 'BROKER_CODE' att,           COUNT(TRIM(BROKER_CODE)) ok           FROM mm UNION ALL
        SELECT 'CREDIT_LINE',               COUNT(TRIM(CREDIT_LINE))              FROM mm UNION ALL
        SELECT 'EXPOSURE_CATEGORY',         COUNT(TRIM(EXPOSURE_CATEGORY))        FROM mm UNION ALL
        SELECT 'DEALING_METHOD',            COUNT(TRIM(DEALING_METHOD))           FROM mm UNION ALL
        SELECT 'TAX_SCHEME',                COUNT(TRIM(TAX_SCHEME))               FROM mm UNION ALL
        SELECT 'TRADE_DATE',                COUNT(TRADE_DATE)                     FROM mm UNION ALL
        SELECT 'REL_REFERENCE',             COUNT(TRIM(REL_REFERENCE))            FROM mm UNION ALL
        SELECT 'INTERNAL_SWAP_REF_NO',      COUNT(TRIM(INTERNAL_SWAP_REF_NO))     FROM mm UNION ALL
        SELECT 'CLUSTER_ID',                COUNT(TRIM(CLUSTER_ID))               FROM mm UNION ALL
        SELECT 'SYNDICATION_REF_NO',        COUNT(TRIM(SYNDICATION_REF_NO))       FROM mm) LOOP
        IF d.ok = 0 THEN
            v_count := v_count + 1;
            print_note('    -> attribut jamais alimente : ' || d.att);
        END IF;
    END LOOP;
    print_test('TRS-1202 Attributs contractuels jamais alimentes sur le portefeuille',
               v_count, NULL, 'MAJEUR');

    -- ---------------------------------------------------------
    -- TRS-1207 : format des references contractuelles
    -- ---------------------------------------------------------
    print_sub('TRS-1207 : Formats de reference contractuelle rencontres');
    tbl_line('4,16,16,30');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' LONGUEUR',16) || '|' || RPAD(' NB CONTRATS',16) || '|'
        || RPAD(' EXEMPLE',30) || '|');
    tbl_line('4,16,16,30');
    v_row_num := 0;
    FOR d IN (SELECT LENGTH(CONTRACT_REF_NO) lg, COUNT(*) nb, MIN(CONTRACT_REF_NO) ex
              FROM  (SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
              GROUP BY LENGTH(CONTRACT_REF_NO) ORDER BY COUNT(*) DESC) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || LPAD(TO_CHAR(d.lg),15) || ' |' || LPAD(TO_CHAR(d.nb,'FM999G990'),15) || ' |'
            || RPAD(' ' || SUBSTR(d.ex,1,28),30) || '|');
    END LOOP;
    tbl_line('4,16,16,30');

    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = p_module)
    WHERE INSTR(CONTRACT_REF_NO, p_module) = 0;
    print_test('TRS-1207 References contractuelles ne portant pas le code module',
               v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-1208 : doublons de reference utilisateur
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT USER_REF_NO FROM (
            SELECT * FROM (
                SELECT c.CONTRACT_REF_NO, c.USER_REF_NO,
                       ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                            ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
                FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
            WHERE rn = 1 AND USER_REF_NO IS NOT NULL AND TRIM(USER_REF_NO) IS NOT NULL)
        GROUP BY USER_REF_NO HAVING COUNT(*) > 1);
    print_test('TRS-1208 References utilisateur partagees par plusieurs contrats',
               v_count, NULL, 'MINEUR');

    -- ---------------------------------------------------------
    -- TRS-1209 : caracteres de controle dans les libelles
    -- ---------------------------------------------------------
    SELECT COUNT(*) INTO v_count FROM (
        SELECT * FROM (
            SELECT c.CONTRACT_REF_NO, c.REMARKS, c.USER_REF_NO,
                   ROW_NUMBER() OVER (PARTITION BY c.CONTRACT_REF_NO
                        ORDER BY c.VERSION_NO DESC, c.EVENT_SEQ_NO DESC) rn
            FROM LDTB_CONTRACT_MASTER c WHERE c.MODULE = p_module)
        WHERE rn = 1
        AND  (REGEXP_LIKE(NVL(REMARKS,'x'), '[[:cntrl:]]')
           OR REGEXP_LIKE(NVL(USER_REF_NO,'x'), '[[:cntrl:]]')));
    print_test('TRS-1209 Contrats dont les libelles contiennent des caracteres de controle',
               v_count, NULL, 'MINEUR');


    -- =========================================================
    -- SECTION 13 : SYNTHESE DES DEFAILLANCES
    -- =========================================================
    print_section('SECTION 13 : SYNTHESE DES DEFAILLANCES');

    print_sub('Repartition des tests par criticite');
    tbl_line('4,20,16,16');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CRITICITE',20) || '|'
        || RPAD(' TESTS EN ANOMALIE',16) || '|' || RPAD(' PONDERATION',16) || '|');
    tbl_line('4,20,16,16');
    DBMS_OUTPUT.PUT_LINE('  |' || LPAD(1,3) || ' |' || RPAD(' CRITIQUE',20) || '|'
        || LPAD(TO_CHAR(v_nb_crit),15) || ' |' || LPAD('x 10',15) || ' |');
    DBMS_OUTPUT.PUT_LINE('  |' || LPAD(2,3) || ' |' || RPAD(' MAJEUR',20) || '|'
        || LPAD(TO_CHAR(v_nb_maj),15) || ' |' || LPAD('x 4',15) || ' |');
    DBMS_OUTPUT.PUT_LINE('  |' || LPAD(3,3) || ' |' || RPAD(' MINEUR',20) || '|'
        || LPAD(TO_CHAR(v_nb_min),15) || ' |' || LPAD('x 1',15) || ' |');
    tbl_line('4,20,16,16');

    v_num1 := GREATEST(0, 100 - (10 * v_nb_crit + 4 * v_nb_maj + 1 * v_nb_min));
    print_blank;
    print_kv('Tests executes', TO_CHAR(v_test_no));
    print_kv('Tests conformes', TO_CHAR(v_test_no - v_anomalies));
    print_kv('Tests en anomalie', TO_CHAR(v_anomalies));
    IF v_test_no > 0 THEN
        print_kv('Taux de conformite',
                 TO_CHAR(ROUND((v_test_no - v_anomalies) * 100 / v_test_no, 1)) || ' %');
    END IF;
    print_kv('SCORE DE MAITRISE (0 a 100)', TO_CHAR(v_num1));
    print_kv('Appreciation',
             CASE WHEN v_num1 >= 85 THEN 'DISPOSITIF MAITRISE'
                  WHEN v_num1 >= 70 THEN 'MAITRISE SATISFAISANTE AVEC RESERVES'
                  WHEN v_num1 >= 50 THEN 'MAITRISE INSUFFISANTE'
                  ELSE                   'DISPOSITIF DEFAILLANT' END);
    print_blank;
    print_note('La ponderation du score est conventionnelle : elle sert a hierarchiser, non a conclure.');
    print_note('La conclusion d''audit reste fondee sur le jugement professionnel, apres validation');
    print_note('contradictoire des anomalies avec la direction de la tresorerie.');

    print_sub('Points de vigilance methodologiques');
    print_note('1. Les seuils COBAC parametres doivent etre confrontes aux textes officiels avant');
    print_note('   emission du rapport (R-2003/02, R-2003/03, R-2010/01, R-2010/02, R-2020/01).');
    print_note('2. Le mapping PRODUCT_TYPE (P = emploi / B = ressource) doit etre confirme.');
    print_note('3. La semantique des tables _FCC doit etre confirmee avec l''equipe applicative.');
    print_note('4. Les fonds propres nets sont exogenes a FLEXCUBE : source = declaration COBAC.');
    print_note('5. Les ecarts de recalcul d''interet peuvent provenir de regles d''arrondi ou de');
    print_note('   decalage de jours feries : voir TRS-415 et TRS-416 avant de conclure.');

    -- =========================================================
    -- FIN
    -- =========================================================
    print_blank;
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TOTAL TESTS EXECUTES ....... ' || v_test_no);
    DBMS_OUTPUT.PUT_LINE('   TESTS AVEC ANOMALIES ....... ' || v_anomalies);
    DBMS_OUTPUT.PUT_LINE('     dont CRITIQUES ........... ' || v_nb_crit);
    DBMS_OUTPUT.PUT_LINE('     dont MAJEURS ............. ' || v_nb_maj);
    DBMS_OUTPUT.PUT_LINE('     dont MINEURS ............. ' || v_nb_min);
    DBMS_OUTPUT.PUT_LINE('   DUREE D''EXECUTION .......... '
        || TO_CHAR(ROUND((SYSDATE - v_debut) * 24 * 60, 1)) || ' minutes');
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
