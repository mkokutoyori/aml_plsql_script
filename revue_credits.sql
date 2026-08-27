-- ============================================================
-- SCRIPT DE REVUE DU PORTEFEUILLE DE CREDITS
-- Base : FLEXCUBE (FCUBS) — Audit Interne / Risque de Credit
-- ============================================================
-- Ce script identifie les anomalies et zones de risque du
-- portefeuille de credits : impayes, echeances non honorees,
-- defauts d'approbation, restructurations, abandons de creances
-- et coherence du declassement prudentiel.
--
-- PLAN DE LA REVUE
--   0.  Panorama du portefeuille de credits (informatif)
--   1.  Credits en impaye — arrieres et anciennete
--   2.  Credits echus non soldes
--   3.  Credits sans approbation identifiable
--   4.  Anomalies de decaissement
--   5.  Clients cumulant plusieurs credits (concentration)
--   6.  Credits restructures ou reechelonnes
--   7.  Abandons de creances : waivers, penalites, passages en perte
--   8.  Credits proches ou superieurs aux seuils d'approbation
--   9.  Credits sans garantie, sans ligne de credit, sans assurance
--   10. Credits au personnel et parties liees
--   11. Coherence du declassement et du provisionnement
--   12. Anomalies de parametrage et de donnees
--
-- TABLES UTILISEES
--   CLTB_ACCOUNT_APPS_MASTER  : dossiers de credit (module CL — retail/PME)
--   CLTB_ACCOUNT_SCHEDULES    : echeanciers (du, regle, impaye, par composante)
--   CLTB_ACCOUNT_COMPONENTS   : composantes du credit (principal, interets, ...)
--   CLTB_AMOUNT_PAID          : reglements par echeance (date due / date payee)
--   CLTB_LIQ                  : liquidations (remboursements) et leurs auteurs
--   LDTB_CONTRACT_MASTER      : contrats de pret (module LD — corporate / MM)
--   LDTB_CONTRACT_BALANCE     : encours principal des contrats LD
--   GETM_FACILITY / GETM_LIAB : lignes de credit et groupes de risque
--   STTM_CUSTOMER             : referentiel clients
--   STTM_CUST_ACCOUNT         : comptes de reglement
--   STTB_ACCOUNT              : GL naturel des comptes (perimetre clientelise)
--   CSTM_PRODUCT              : referentiel produits
--
-- PERIMETRE
--   Le portefeuille analyse couvre les deux modules de credit presents :
--   CL (credits amortissables a la clientele) et LD (prets et avances
--   corporate). Les tests de detail portent principalement sur le module
--   CL, ou se trouvent l'echeancier et l'historique de reglement ; le
--   module LD est couvert au panorama et sur les tests applicables.
--   Un compte de reglement est dit CLIENTELISE lorsque son GL naturel
--   commence par 37 (STTB_ACCOUNT.AC_NATURAL_GL, rattachement
--   AC_GL_NO = CUST_AC_NO) : un credit rembourse depuis un compte interne
--   constitue une anomalie et non un flux client.
--
-- CONVENTIONS
--   - Les montants affiches "M" sont exprimes en MILLIONS de la devise
--     de reference (XAF sauf mention contraire) ; la colonne CCY est
--     affichee des lors que plusieurs devises coexistent.
--   - L'impaye d'une echeance est AMOUNT_OVERDUE, complete par l'ecart
--     AMOUNT_DUE - AMOUNT_SETTLED pour les echeances echues.
--   - Les seuils de la revue sont parametrables dans le bloc PARAMETRES
--     ci-dessous : ils DOIVENT etre alignes sur la grille de delegation
--     de pouvoirs et sur les regles de declassement en vigueur.
--
-- PERFORMANCE
--   Les tests portant sur l'echeancier (157 000 lignes) et l'historique
--   de reglement sont executes en UN SEUL passage : le comptage des
--   anomalies est obtenu par COUNT(*) OVER () dans la requete de detail,
--   dont les lignes sont mises en tampon (v_lignes) puis restituees apres
--   la ligne de resultat du test. Le temps d'execution de chaque section
--   est affiche en fin de section.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET LINESIZE 400
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_total         NUMBER;
    v_sep           VARCHAR2(80) := RPAD('=', 80, '=');
    v_test_no       NUMBER := 0;
    v_anomalies     NUMBER := 0;
    v_row_num       NUMBER := 0;
    v_montant       NUMBER;

    -- Tampon des lignes de detail (permet d'obtenir le nombre d'anomalies
    -- et les lignes a afficher en un seul passage sur les grosses tables)
    TYPE t_lignes IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    v_lignes        t_lignes;

    -- Chronometrage par section
    v_sec_start     NUMBER := DBMS_UTILITY.GET_TIME;
    v_sec_titre     VARCHAR2(200);

    -- =========================================================
    -- PARAMETRES DE LA REVUE (a adapter au dispositif interne)
    -- =========================================================
    -- Nombre maximum de lignes affichees par test
    c_max_rows          CONSTANT NUMBER := 30;

    -- Prefixe du GL naturel identifiant les comptes CLIENTELISES
    c_gl_client         CONSTANT VARCHAR2(10) := '37';

    -- Paliers d'anciennete d'impaye (jours) — regles de declassement
    c_impaye_1          CONSTANT NUMBER := 30;
    c_impaye_2          CONSTANT NUMBER := 90;    -- seuil de declassement
    c_impaye_3          CONSTANT NUMBER := 180;
    c_impaye_4          CONSTANT NUMBER := 360;

    -- Retard de reglement considere comme significatif (jours)
    c_retard_signif     CONSTANT NUMBER := 30;
    -- Nombre de retards caracterisant un mauvais historique de paiement
    c_nb_retards        CONSTANT NUMBER := 3;

    -- Grille des seuils d'approbation (a aligner sur la delegation)
    c_seuil_1           CONSTANT NUMBER := 10000000;      -- 10 M
    c_seuil_2           CONSTANT NUMBER := 50000000;      -- 50 M
    c_seuil_3           CONSTANT NUMBER := 250000000;     -- 250 M
    c_seuil_4           CONSTANT NUMBER := 1000000000;    -- 1 000 M
    -- Bande "juste en dessous du seuil" (evitement du palier)
    c_pct_proche        CONSTANT NUMBER := 90;            -- 90 % du seuil

    -- Montant significatif (ecriture, impaye, abandon)
    c_mnt_signif        CONSTANT NUMBER := 5000000;       -- 5 M
    -- Montant d'abandon (waiver) considere comme significatif
    c_mnt_waiver        CONSTANT NUMBER := 500000;        -- 0,5 M
    -- Profondeur d'analyse des historiques (en mois)
    c_mois_hist         CONSTANT NUMBER := 12;
    -- Profondeur d'analyse des restructurations (en mois)
    c_mois_restr        CONSTANT NUMBER := 24;
    -- Nombre de versions au-dela duquel un dossier est dit tres amende
    c_nb_versions       CONSTANT NUMBER := 5;
    -- Ecart tolere entre montant finance et montant decaisse
    c_tol_decaiss       CONSTANT NUMBER := 1;             -- 1 unite de devise

    -- Affiche le temps d'execution de la section qui vient de s'achever
    PROCEDURE print_temps IS
    BEGIN
        IF v_sec_titre IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('  ... section executee en '
                || TO_CHAR((DBMS_UTILITY.GET_TIME - v_sec_start) / 100, 'FM999G990D0') || ' s');
        END IF;
    END;

    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        print_temps;
        v_sec_titre := p_title;
        v_sec_start := DBMS_UTILITY.GET_TIME;
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
                || RPAD(p_label, 60, '.') || ' '
                || p_count || ' / ' || p_total
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        ELSE
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 60, '.') || ' '
                || p_count
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        END IF;
        IF p_count > 0 THEN
            v_anomalies := v_anomalies + 1;
        END IF;
    END;

    -- Ligne informative (statistique de cadrage, non comptee comme test)
    PROCEDURE print_info(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('    ' || RPAD(p_label, 55, '.') || ' ' || p_value);
    END;

    -- Restitue le tampon de lignes de detail puis le vide
    PROCEDURE flush_lignes IS
    BEGIN
        FOR i IN 1 .. v_lignes.COUNT LOOP
            DBMS_OUTPUT.PUT_LINE(v_lignes(i));
        END LOOP;
        v_lignes.DELETE;
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

    -- Formatage d'un montant en millions
    FUNCTION fmt_m(p_amt NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_amt,0)/1000000, 'FM999G999G990D00') || ' M';
    END;

    -- Formatage d'un entier
    FUNCTION fmt_n(p_val NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_val,0), 'FM999G999G999G990');
    END;

    -- Formatage d'une date
    FUNCTION fmt_d(p_dt DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN NVL(TO_CHAR(p_dt, 'DD/MM/YYYY'), '-');
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   REVUE DU PORTEFEUILLE DE CREDITS — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- SECTION 0 : PANORAMA DU PORTEFEUILLE DE CREDITS (INFORMATIF)
    -- =========================================================
    print_section('0. PANORAMA DU PORTEFEUILLE DE CREDITS');

    -- 0.1 Rappel des parametres de la revue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Parametres de la revue]');
    print_info('Paliers d''impaye (jours)', fmt_n(c_impaye_1) || ' / ' || fmt_n(c_impaye_2)
        || ' / ' || fmt_n(c_impaye_3) || ' / ' || fmt_n(c_impaye_4));
    print_info('Seuil de declassement retenu (jours)', fmt_n(c_impaye_2));
    print_info('Retard de reglement significatif (jours)', fmt_n(c_retard_signif));
    print_info('Nombre de retards caracterisant un mauvais payeur', fmt_n(c_nb_retards));
    print_info('Seuil d''approbation 1', fmt_m(c_seuil_1));
    print_info('Seuil d''approbation 2', fmt_m(c_seuil_2));
    print_info('Seuil d''approbation 3', fmt_m(c_seuil_3));
    print_info('Seuil d''approbation 4', fmt_m(c_seuil_4));
    print_info('Bande "juste en dessous du seuil" (%)', fmt_n(c_pct_proche) || ' %');
    print_info('Montant significatif', fmt_m(c_mnt_signif));
    print_info('Abandon (waiver) significatif', fmt_m(c_mnt_waiver));
    print_info('Profondeur d''analyse des historiques (mois)', fmt_n(c_mois_hist));
    print_info('Profondeur d''analyse des restructurations (mois)', fmt_n(c_mois_restr));
    print_info('GL naturel des comptes clientelises', c_gl_client || 'xx');

    -- 0.2 Module CL — dossiers de credit
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Module CL — dossiers de credit]');

    SELECT COUNT(*) INTO v_total FROM CLTB_ACCOUNT_APPS_MASTER;
    print_info('Nombre total de dossiers', fmt_n(v_total));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE AUTH_STAT = 'A';
    print_info('Dossiers autorises (AUTH_STAT = A)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE NVL(AUTH_STAT,'U') != 'A';
    print_info('Dossiers NON autorises', fmt_n(v_count));

    SELECT NVL(SUM(AMOUNT_FINANCED),0), NVL(SUM(AMOUNT_DISBURSED),0)
      INTO v_montant, v_total FROM CLTB_ACCOUNT_APPS_MASTER;
    print_info('Total finance', fmt_m(v_montant));
    print_info('Total decaisse', fmt_m(v_total));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER
    WHERE MATURITY_DATE IS NOT NULL AND MATURITY_DATE < TRUNC(SYSDATE);
    print_info('Dossiers dont la maturite est depassee', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE NVL(STOP_ACCRUALS,'N') = 'Y';
    print_info('Dossiers avec arret des accruals', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE NVL(HAS_PROBLEMS,'N') = 'Y';
    print_info('Dossiers signales en anomalie (HAS_PROBLEMS)', fmt_n(v_count));

    SELECT COUNT(*) INTO v_count FROM CLTB_ACCOUNT_APPS_MASTER WHERE MIGRATION_DATE IS NOT NULL;
    print_info('Dossiers issus d''une migration', fmt_n(v_count));

    -- Repartition par statut de compte
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition par ACCOUNT_STATUS]');
    FOR d IN (SELECT NVL(ACCOUNT_STATUS,'-') AS st, COUNT(*) AS nb,
                     NVL(SUM(AMOUNT_FINANCED),0) AS mnt
              FROM CLTB_ACCOUNT_APPS_MASTER
              GROUP BY NVL(ACCOUNT_STATUS,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Statut ' || d.st, fmt_n(d.nb) || ' dossier(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- Repartition par statut de classification
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition par USER_DEFINED_STATUS — classification]');
    FOR d IN (SELECT NVL(USER_DEFINED_STATUS,'-') AS st, COUNT(*) AS nb,
                     NVL(SUM(AMOUNT_FINANCED),0) AS mnt
              FROM CLTB_ACCOUNT_APPS_MASTER
              GROUP BY NVL(USER_DEFINED_STATUS,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Classification ' || d.st, fmt_n(d.nb) || ' dossier(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- Repartition par produit
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 produits de credit]');
    FOR d IN (SELECT * FROM (
                SELECT NVL(m.PRODUCT_CODE,'-') AS prd,
                       NVL(MAX(p.PRODUCT_DESCRIPTION),'-') AS lib,
                       COUNT(*) AS nb, NVL(SUM(m.AMOUNT_FINANCED),0) AS mnt
                FROM CLTB_ACCOUNT_APPS_MASTER m
                LEFT JOIN CSTM_PRODUCT p ON p.PRODUCT_CODE = m.PRODUCT_CODE
                GROUP BY m.PRODUCT_CODE
                ORDER BY NVL(SUM(m.AMOUNT_FINANCED),0) DESC
              ) WHERE ROWNUM <= 15) LOOP
        print_info(RPAD(d.prd,6) || ' ' || SUBSTR(d.lib,1,30),
            fmt_n(d.nb) || ' dossier(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- Repartition par devise
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition par devise]');
    FOR d IN (SELECT NVL(CURRENCY,'-') AS ccy, COUNT(*) AS nb,
                     NVL(SUM(AMOUNT_FINANCED),0) AS mnt
              FROM CLTB_ACCOUNT_APPS_MASTER
              GROUP BY NVL(CURRENCY,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Devise ' || d.ccy, fmt_n(d.nb) || ' dossier(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- Repartition par agence
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition par agence]');
    FOR d IN (SELECT NVL(BRANCH_CODE,'-') AS brn, COUNT(*) AS nb,
                     NVL(SUM(AMOUNT_FINANCED),0) AS mnt
              FROM CLTB_ACCOUNT_APPS_MASTER
              GROUP BY NVL(BRANCH_CODE,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Agence ' || d.brn, fmt_n(d.nb) || ' dossier(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 0.3 Echeancier et impayes
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Echeancier — CLTB_ACCOUNT_SCHEDULES]');

    SELECT COUNT(*) INTO v_total FROM CLTB_ACCOUNT_SCHEDULES;
    print_info('Nombre total de lignes d''echeancier', fmt_n(v_total));

    SELECT COUNT(*), NVL(SUM(AMOUNT_DUE),0) INTO v_count, v_montant
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE SCHEDULE_DUE_DATE < TRUNC(SYSDATE);
    print_info('Echeances echues', fmt_n(v_count) || ' — ' || fmt_m(v_montant));

    SELECT COUNT(*), NVL(SUM(AMOUNT_OVERDUE),0) INTO v_count, v_montant
    FROM CLTB_ACCOUNT_SCHEDULES
    WHERE NVL(AMOUNT_OVERDUE,0) > 0;
    print_info('Echeances portant un impaye', fmt_n(v_count) || ' — ' || fmt_m(v_montant));

    SELECT COUNT(DISTINCT ACCOUNT_NUMBER) INTO v_count
    FROM CLTB_ACCOUNT_SCHEDULES WHERE NVL(AMOUNT_OVERDUE,0) > 0;
    print_info('Dossiers concernes par un impaye', fmt_n(v_count));

    SELECT NVL(SUM(WRITEOFF_AMT),0), NVL(SUM(AMOUNT_WAIVED),0) INTO v_montant, v_total
    FROM CLTB_ACCOUNT_SCHEDULES;
    print_info('Total passe en perte (WRITEOFF_AMT)', fmt_m(v_montant));
    print_info('Total abandonne (AMOUNT_WAIVED)', fmt_m(v_total));

    -- Ventilation des impayes par anciennete
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Ventilation des impayes par anciennete]');
    FOR d IN (SELECT tranche, COUNT(DISTINCT compte) AS nb_dossiers,
                     COUNT(*) AS nb_ech, NVL(SUM(mnt),0) AS total
              FROM (SELECT s.ACCOUNT_NUMBER AS compte,
                           CASE
                             WHEN TRUNC(SYSDATE) - TRUNC(s.SCHEDULE_DUE_DATE) <= c_impaye_1 THEN '1. 0 a 30 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(s.SCHEDULE_DUE_DATE) <= c_impaye_2 THEN '2. 31 a 90 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(s.SCHEDULE_DUE_DATE) <= c_impaye_3 THEN '3. 91 a 180 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(s.SCHEDULE_DUE_DATE) <= c_impaye_4 THEN '4. 181 a 360 jours'
                             ELSE '5. plus de 360 jours'
                           END AS tranche,
                           NVL(s.AMOUNT_OVERDUE,0) AS mnt
                    FROM CLTB_ACCOUNT_SCHEDULES s
                    WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                      AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE))
              GROUP BY tranche
              ORDER BY tranche) LOOP
        print_info(d.tranche, fmt_n(d.nb_dossiers) || ' dossier(s), '
            || fmt_n(d.nb_ech) || ' echeance(s) — ' || fmt_m(d.total));
    END LOOP;

    -- 0.4 Module LD — contrats de pret
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Module LD — contrats de pret / avances]');

    SELECT COUNT(*), NVL(SUM(LCY_AMOUNT),0) INTO v_count, v_montant FROM LDTB_CONTRACT_MASTER;
    print_info('Nombre de contrats', fmt_n(v_count));
    print_info('Montant total (contre-valeur)', fmt_m(v_montant));

    SELECT NVL(SUM(b.PRINCIPAL_OUTSTANDING_BAL),0) INTO v_montant
    FROM LDTB_CONTRACT_BALANCE b;
    print_info('Encours principal restant du', fmt_m(v_montant));

    SELECT COUNT(*) INTO v_count FROM LDTB_CONTRACT_MASTER
    WHERE MATURITY_DATE IS NOT NULL AND MATURITY_DATE < TRUNC(SYSDATE);
    print_info('Contrats dont la maturite est depassee', fmt_n(v_count));

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition des contrats LD par statut]');
    FOR d IN (SELECT NVL(CONTRACT_STATUS,'-') AS st, COUNT(*) AS nb,
                     NVL(SUM(LCY_AMOUNT),0) AS mnt
              FROM LDTB_CONTRACT_MASTER
              GROUP BY NVL(CONTRACT_STATUS,'-')
              ORDER BY COUNT(*) DESC) LOOP
        print_info('Statut ' || d.st, fmt_n(d.nb) || ' contrat(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 0.5 Top 15 des encours de credit (module CL)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 des dossiers par montant finance]');
    tbl_line('4,12,26,22,6,17,17,12,10');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',26) || '|'
        || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',6) || '|'
        || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|' || RPAD(' MATURITE',12) || '|'
        || RPAD(' STATUT',10) || '|');
    tbl_line('4,12,26,22,6,17,17,12,10');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT m.CUSTOMER_ID, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
               NVL(m.CURRENCY,'-') AS ccy, NVL(m.AMOUNT_FINANCED,0) AS finance,
               NVL(m.AMOUNT_DISBURSED,0) AS decaisse, m.MATURITY_DATE,
               NVL(m.USER_DEFINED_STATUS,'-') AS st
        FROM CLTB_ACCOUNT_APPS_MASTER m
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
    ) WHERE ROWNUM <= 15) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.CUSTOMER_ID,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,6) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),12) || '|'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|');
    END LOOP;
    tbl_line('4,12,26,22,6,17,17,12,10');
    IF v_row_num = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  (aucun dossier de credit)');
    END IF;

    -- =========================================================
    -- SECTION 1 : CREDITS EN IMPAYE — ARRIERES ET ANCIENNETE
    -- =========================================================
    -- L'impaye est la premiere manifestation du risque de credit.
    -- Son anciennete commande le declassement, le provisionnement et
    -- l'arret de la comptabilisation des interets. Les tests ci-dessous
    -- mesurent l'encours impaye, son age et sa concentration.
    -- =========================================================
    print_section('1. CREDITS EN IMPAYE — ARRIERES ET ANCIENNETE');

    -- 1.1 Dossiers portant un impaye, tous ages confondus
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, NVL(m.CURRENCY,'-') AS ccy, i.impaye, i.nb_ech,
                   i.plus_ancienne, i.anciennete, NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye, COUNT(*) AS nb_ech,
                       MIN(s.SCHEDULE_DUE_DATE) AS plus_ancienne,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
            ) i
            LEFT JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ) q
        ORDER BY q.impaye DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.impaye),16) || ' |'
            || LPAD(fmt_n(d.nb_ech),8) || ' |'
            || RPAD(' ' || fmt_d(d.plus_ancienne),13) || '|'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|';
    END LOOP;
    print_test('Dossiers portant un impaye', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,9,13,9,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' IMPAYE',17) || '|' || RPAD(' NB ECH.',9) || '|' || RPAD(' + ANCIENNE',13) || '|'
            || RPAD(' JOURS',9) || '|' || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,5,17,9,13,9,10');
        flush_lignes;
        tbl_line('4,12,24,22,5,17,9,13,9,10');
    END IF;

    -- 1.2 Dossiers dont l'impaye le plus ancien depasse le seuil de
    --     declassement
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, NVL(m.CURRENCY,'-') AS ccy, i.impaye, i.anciennete,
                   NVL(m.AMOUNT_FINANCED,0) AS finance,
                   NVL(m.USER_DEFINED_STATUS,'-') AS st,
                   NVL(m.STOP_ACCRUALS,'N') AS stop_acc
            FROM (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
                HAVING TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) > c_impaye_2
            ) i
            LEFT JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ) q
        ORDER BY q.anciennete DESC, q.impaye DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.impaye),16) || ' |'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|'
            || RPAD(' ' || d.stop_acc,8) || '|';
    END LOOP;
    print_test('Impayes de plus de ' || c_impaye_2 || ' jours (declassement)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,9,10,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' IMPAYE',17) || '|'
            || RPAD(' JOURS',9) || '|' || RPAD(' STATUT',10) || '|' || RPAD(' STOP AC',8) || '|');
        tbl_line('4,12,24,22,17,17,9,10,8');
        flush_lignes;
        tbl_line('4,12,24,22,17,17,9,10,8');
    END IF;

    -- 1.3 Impayes tres anciens (creances a passer en contentieux)
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, i.impaye, i.anciennete, i.plus_ancienne,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye,
                       MIN(s.SCHEDULE_DUE_DATE) AS plus_ancienne,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
                HAVING TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) > c_impaye_4
            ) i
            LEFT JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ) q
        ORDER BY q.anciennete DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.impaye),16) || ' |'
            || RPAD(' ' || fmt_d(d.plus_ancienne),13) || '|'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|';
    END LOOP;
    print_test('Impayes de plus de ' || c_impaye_4 || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,13,9,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' IMPAYE',17) || '|'
            || RPAD(' + ANCIENNE',13) || '|' || RPAD(' JOURS',9) || '|' || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,17,17,13,9,10');
        flush_lignes;
        tbl_line('4,12,24,22,17,17,13,9,10');
    END IF;

    -- 1.4 Echeances echues incompletement reglees mais sans impaye
    --     enregistre : le suivi des arrieres ne reflete pas le solde du
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT s.ACCOUNT_NUMBER, s.COMPONENT_NAME, s.SCHEDULE_DUE_DATE,
                   NVL(s.AMOUNT_DUE,0) AS du, NVL(s.AMOUNT_SETTLED,0) AS regle,
                   NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0) AS ecart,
                   NVL(s.SCH_STATUS,'-') AS sch_st,
                   TRUNC(SYSDATE) - TRUNC(s.SCHEDULE_DUE_DATE) AS anciennete
            FROM CLTB_ACCOUNT_SCHEDULES s
            WHERE s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
              AND NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0) > 0
              AND NVL(s.AMOUNT_OVERDUE,0) = 0
              AND NVL(s.WRITEOFF_AMT,0) = 0
              AND NVL(s.AMOUNT_WAIVED,0) = 0
        ) q
        ORDER BY q.ecart DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || RPAD(' ' || SUBSTR(d.COMPONENT_NAME,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.SCHEDULE_DUE_DATE),13) || '|'
            || LPAD(fmt_m(d.du),16) || ' |' || LPAD(fmt_m(d.regle),16) || ' |'
            || LPAD(fmt_m(d.ecart),16) || ' |'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.sch_st,1,6),8) || '|';
    END LOOP;
    print_test('Echeances echues non soldees sans impaye enregistre', v_count);
    IF v_count > 0 THEN
        tbl_line('4,22,16,13,17,17,17,9,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DOSSIER',22) || '|' || RPAD(' COMPOSANTE',16) || '|'
            || RPAD(' ECHEANCE',13) || '|' || RPAD(' DU',17) || '|' || RPAD(' REGLE',17) || '|'
            || RPAD(' ECART',17) || '|' || RPAD(' JOURS',9) || '|' || RPAD(' STAT',8) || '|');
        tbl_line('4,22,16,13,17,17,17,9,8');
        flush_lignes;
        tbl_line('4,22,16,13,17,17,17,9,8');
    END IF;

    -- 1.5 Impayes portant sur la composante principale (capital)
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, i.composante, i.impaye, i.nb_ech, i.anciennete,
                   NVL(m.AMOUNT_FINANCED,0) AS finance
            FROM (
                SELECT s.ACCOUNT_NUMBER, MAX(s.COMPONENT_NAME) AS composante,
                       SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye, COUNT(*) AS nb_ech,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                JOIN CLTB_ACCOUNT_COMPONENTS k ON k.ACCOUNT_NUMBER = s.ACCOUNT_NUMBER
                     AND k.BRANCH_CODE = s.BRANCH_CODE
                     AND k.COMPONENT_NAME = s.COMPONENT_NAME
                     AND NVL(k.MAIN_COMPONENT,'N') = 'Y'
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
            ) i
            LEFT JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ) q
        ORDER BY q.impaye DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || RPAD(' ' || SUBSTR(d.composante,1,12),14) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.impaye),16) || ' |'
            || LPAD(fmt_n(d.nb_ech),8) || ' |'
            || LPAD(fmt_n(d.anciennete),8) || ' |';
    END LOOP;
    print_test('Impayes sur la composante principale (capital)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,14,17,17,9,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' COMPOSANTE',14) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' IMPAYE CAPITAL',17) || '|' || RPAD(' NB ECH.',9) || '|'
            || RPAD(' JOURS',9) || '|');
        tbl_line('4,12,24,22,14,17,17,9,9');
        flush_lignes;
        tbl_line('4,12,24,22,14,17,17,9,9');
    END IF;

    -- 1.6 Dossiers cumulant plusieurs echeances impayees
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, i.nb_ech, i.impaye, i.anciennete,
                   NVL(m.NO_OF_INSTALLMENTS,0) AS nb_ech_total,
                   NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM (
                SELECT s.ACCOUNT_NUMBER, COUNT(*) AS nb_ech,
                       SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
                HAVING COUNT(*) >= c_nb_retards
            ) i
            LEFT JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
        ) q
        ORDER BY q.nb_ech DESC, q.impaye DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_n(d.nb_ech),9) || ' |'
            || LPAD(fmt_n(d.nb_ech_total),9) || ' |'
            || LPAD(fmt_m(d.impaye),16) || ' |'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|';
    END LOOP;
    print_test('Dossiers avec au moins ' || c_nb_retards || ' echeances impayees', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,10,10,17,9,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' ECH. IMP.',10) || '|' || RPAD(' ECH. TOT.',10) || '|'
            || RPAD(' IMPAYE',17) || '|' || RPAD(' JOURS',9) || '|' || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,10,10,17,9,10');
        flush_lignes;
        tbl_line('4,12,24,22,10,10,17,9,10');
    END IF;

    -- 1.7 Impayes significatifs au regard du montant finance
    --     (plus de la moitie du credit reste impayee)
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   i.ACCOUNT_NUMBER, i.impaye, NVL(m.AMOUNT_FINANCED,0) AS finance,
                   ROUND(i.impaye * 100 / NULLIF(m.AMOUNT_FINANCED,0), 1) AS pct,
                   i.anciennete, NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM (
                SELECT s.ACCOUNT_NUMBER, SUM(NVL(s.AMOUNT_OVERDUE,0)) AS impaye,
                       TRUNC(SYSDATE) - TRUNC(MIN(s.SCHEDULE_DUE_DATE)) AS anciennete
                FROM CLTB_ACCOUNT_SCHEDULES s
                WHERE NVL(s.AMOUNT_OVERDUE,0) > 0
                  AND s.SCHEDULE_DUE_DATE < TRUNC(SYSDATE)
                GROUP BY s.ACCOUNT_NUMBER
            ) i
            JOIN CLTB_ACCOUNT_APPS_MASTER m ON m.ACCOUNT_NUMBER = i.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AMOUNT_FINANCED,0) > 0
              AND i.impaye >= 0.5 * m.AMOUNT_FINANCED
        ) q
        ORDER BY q.impaye DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.impaye),16) || ' |'
            || LPAD(TO_CHAR(NVL(d.pct,0),'FM99990D0') || ' %',9) || ' |'
            || LPAD(fmt_n(d.anciennete),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|';
    END LOOP;
    print_test('Impayes representant plus de 50 % du montant finance', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,10,9,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' IMPAYE',17) || '|'
            || RPAD(' % FINANCE',10) || '|' || RPAD(' JOURS',9) || '|' || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,17,17,10,9,10');
        flush_lignes;
        tbl_line('4,12,24,22,17,17,10,9,10');
    END IF;

    -- =========================================================
    -- SECTION 2 : CREDITS ECHUS NON SOLDES
    -- =========================================================
    -- Un credit arrive a maturite doit etre solde, proroge par un
    -- avenant formalise, ou declasse. Un dossier echu qui conserve un
    -- solde restant du sans decision documentee traduit un defaut de
    -- suivi et fausse l'anciennete du risque.
    -- NB : les tests reposent sur la substance economique (solde restant
    --      du apres maturite) plutot que sur les codes de statut, dont la
    --      signification depend du parametrage de l'installation ; le
    --      statut est affiche en colonne pour permettre le rapprochement.
    -- =========================================================
    print_section('2. CREDITS ECHUS NON SOLDES');

    -- 2.1 Dossiers echus conservant un solde restant du
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   m.ACCOUNT_NUMBER, NVL(m.CURRENCY,'-') AS ccy,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, r.reste, m.MATURITY_DATE,
                   TRUNC(SYSDATE) - TRUNC(m.MATURITY_DATE) AS jours_echu,
                   NVL(m.ACCOUNT_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            JOIN (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) AS reste
                FROM CLTB_ACCOUNT_SCHEDULES s
                GROUP BY s.ACCOUNT_NUMBER
                HAVING SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) > 0
            ) r ON r.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.MATURITY_DATE IS NOT NULL
              AND m.MATURITY_DATE < TRUNC(SYSDATE)
        ) q
        ORDER BY q.reste DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.reste),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || LPAD(fmt_n(d.jours_echu),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,6),8) || '|';
    END LOOP;
    print_test('Dossiers echus conservant un solde restant du', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,17,13,9,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' RESTE DU',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' J.ECHU',9) || '|' || RPAD(' STAT',8) || '|');
        tbl_line('4,12,24,22,5,17,17,13,9,8');
        flush_lignes;
        tbl_line('4,12,24,22,5,17,17,13,9,8');
    END IF;

    -- 2.2 Dossiers echus de longue date et toujours non soldes
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   m.ACCOUNT_NUMBER, r.reste, m.MATURITY_DATE,
                   TRUNC(SYSDATE) - TRUNC(m.MATURITY_DATE) AS jours_echu,
                   NVL(m.USER_DEFINED_STATUS,'-') AS st,
                   NVL(m.STOP_ACCRUALS,'N') AS stop_acc
            FROM CLTB_ACCOUNT_APPS_MASTER m
            JOIN (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) AS reste
                FROM CLTB_ACCOUNT_SCHEDULES s
                GROUP BY s.ACCOUNT_NUMBER
                HAVING SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) > 0
            ) r ON r.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.MATURITY_DATE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(m.MATURITY_DATE) > c_impaye_3
        ) q
        ORDER BY q.jours_echu DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.reste),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || LPAD(fmt_n(d.jours_echu),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|'
            || RPAD(' ' || d.stop_acc,8) || '|';
    END LOOP;
    print_test('Dossiers echus depuis plus de ' || c_impaye_3 || ' jours non soldes', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,9,10,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' RESTE DU',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' J.ECHU',9) || '|' || RPAD(' STATUT',10) || '|' || RPAD(' STOP AC',8) || '|');
        tbl_line('4,12,24,22,17,13,9,10,8');
        flush_lignes;
        tbl_line('4,12,24,22,17,13,9,10,8');
    END IF;

    -- 2.3 Dossiers echus dont la comptabilisation des interets n'est pas
    --     arretee : les produits continuent d'etre constates sur une
    --     creance dont le recouvrement n'est plus assure
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   m.ACCOUNT_NUMBER, r.reste, m.MATURITY_DATE,
                   TRUNC(SYSDATE) - TRUNC(m.MATURITY_DATE) AS jours_echu,
                   m.NEXT_ACCR_DATE, NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            JOIN (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) AS reste
                FROM CLTB_ACCOUNT_SCHEDULES s
                GROUP BY s.ACCOUNT_NUMBER
                HAVING SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) > 0
            ) r ON r.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.MATURITY_DATE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(m.MATURITY_DATE) > c_impaye_2
              AND NVL(m.STOP_ACCRUALS,'N') != 'Y'
        ) q
        ORDER BY q.reste DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.reste),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || LPAD(fmt_n(d.jours_echu),8) || ' |'
            || RPAD(' ' || fmt_d(d.NEXT_ACCR_DATE),13) || '|'
            || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|';
    END LOOP;
    print_test('Dossiers echus > ' || c_impaye_2 || ' j sans arret des accruals', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,9,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' RESTE DU',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' J.ECHU',9) || '|' || RPAD(' PROCH. ACCR',13) || '|' || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,17,13,9,13,10');
        flush_lignes;
        tbl_line('4,12,24,22,17,13,9,13,10');
    END IF;

    -- 2.4 Echeances programmees au-dela de la date de maturite
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, m.ACCOUNT_NUMBER, m.MATURITY_DATE,
                   x.derniere_ech, x.nb_apres,
                   TRUNC(x.derniere_ech) - TRUNC(m.MATURITY_DATE) AS ecart,
                   NVL(m.AMOUNT_FINANCED,0) AS finance
            FROM CLTB_ACCOUNT_APPS_MASTER m
            JOIN (
                SELECT s.ACCOUNT_NUMBER, MAX(s.SCHEDULE_DUE_DATE) AS derniere_ech,
                       COUNT(*) AS nb_apres
                FROM CLTB_ACCOUNT_SCHEDULES s
                JOIN CLTB_ACCOUNT_APPS_MASTER m2 ON m2.ACCOUNT_NUMBER = s.ACCOUNT_NUMBER
                WHERE m2.MATURITY_DATE IS NOT NULL
                  AND s.SCHEDULE_DUE_DATE > m2.MATURITY_DATE
                GROUP BY s.ACCOUNT_NUMBER
            ) x ON x.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER
            WHERE m.MATURITY_DATE IS NOT NULL
        ) q
        ORDER BY q.ecart DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.finance),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || RPAD(' ' || fmt_d(d.derniere_ech),13) || '|'
            || LPAD(fmt_n(d.ecart),8) || ' |'
            || LPAD(fmt_n(d.nb_apres),9) || ' |';
    END LOOP;
    print_test('Echeances programmees apres la date de maturite', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,17,13,13,9,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' DOSSIER',22) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' MATURITE',13) || '|' || RPAD(' DERN. ECH.',13) || '|'
            || RPAD(' ECART(j)',9) || '|' || RPAD(' NB ECH.',10) || '|');
        tbl_line('4,12,22,17,13,13,9,10');
        flush_lignes;
        tbl_line('4,12,22,17,13,13,9,10');
    END IF;

    -- 2.5 Contrats LD echus conservant un encours principal
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(t.COUNTERPARTY,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   t.CONTRACT_REF_NO, NVL(t.CURRENCY,'-') AS ccy,
                   NVL(t.AMOUNT,0) AS montant, NVL(b.PRINCIPAL_OUTSTANDING_BAL,0) AS encours,
                   t.MATURITY_DATE,
                   TRUNC(SYSDATE) - TRUNC(t.MATURITY_DATE) AS jours_echu,
                   NVL(t.CONTRACT_STATUS,'-') AS st
            FROM LDTB_CONTRACT_MASTER t
            JOIN LDTB_CONTRACT_BALANCE b ON b.CONTRACT_REF_NO = t.CONTRACT_REF_NO
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = t.COUNTERPARTY
            WHERE t.MATURITY_DATE IS NOT NULL
              AND t.MATURITY_DATE < TRUNC(SYSDATE)
              AND NVL(b.PRINCIPAL_OUTSTANDING_BAL,0) > 0
        ) q
        ORDER BY q.encours DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.CONTRACT_REF_NO,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.montant),16) || ' |' || LPAD(fmt_m(d.encours),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || LPAD(fmt_n(d.jours_echu),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,6),8) || '|';
    END LOOP;
    print_test('Contrats LD echus avec encours principal residuel', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,17,13,9,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' CONTREPARTIE',24) || '|'
            || RPAD(' CONTRAT',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' MONTANT',17) || '|' || RPAD(' ENCOURS',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' J.ECHU',9) || '|' || RPAD(' STAT',8) || '|');
        tbl_line('4,12,24,22,5,17,17,13,9,8');
        flush_lignes;
        tbl_line('4,12,24,22,5,17,17,13,9,8');
    END IF;

    -- 2.6 Dossiers dont la cloture attendue est depassee
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   m.ACCOUNT_NUMBER, r.reste, m.EXPECTED_CLOSURE_DATE, m.MATURITY_DATE,
                   TRUNC(SYSDATE) - TRUNC(m.EXPECTED_CLOSURE_DATE) AS retard,
                   NVL(m.ACCOUNT_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            JOIN (
                SELECT s.ACCOUNT_NUMBER,
                       SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) AS reste
                FROM CLTB_ACCOUNT_SCHEDULES s
                GROUP BY s.ACCOUNT_NUMBER
                HAVING SUM(NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) > 0
            ) r ON r.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.EXPECTED_CLOSURE_DATE IS NOT NULL
              AND m.EXPECTED_CLOSURE_DATE < TRUNC(SYSDATE)
        ) q
        ORDER BY q.retard DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_m(d.reste),16) || ' |'
            || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
            || RPAD(' ' || fmt_d(d.EXPECTED_CLOSURE_DATE),13) || '|'
            || LPAD(fmt_n(d.retard),8) || ' |'
            || RPAD(' ' || SUBSTR(d.st,1,6),8) || '|';
    END LOOP;
    print_test('Dossiers non soldes au-dela de la cloture attendue', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,13,9,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' RESTE DU',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' CLOTURE ATT.',13) || '|' || RPAD(' RETARD',9) || '|' || RPAD(' STAT',8) || '|');
        tbl_line('4,12,24,22,17,13,13,9,8');
        flush_lignes;
        tbl_line('4,12,24,22,17,13,13,9,8');
    END IF;

    -- 2.7 Dossiers sans date de maturite renseignee
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE m.MATURITY_DATE IS NULL;
    print_test('Dossiers sans date de maturite', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,13,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' DATE VALEUR',13) || '|' || RPAD(' BOOK DATE',13) || '|'
            || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,5,17,13,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   m.ACCOUNT_NUMBER, NVL(m.CURRENCY,'-') AS ccy,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, m.VALUE_DATE, m.BOOK_DATE,
                   NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.MATURITY_DATE IS NULL
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|' || RPAD(' ' || fmt_d(d.BOOK_DATE),13) || '|'
                || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|');
        END LOOP;
        tbl_line('4,12,24,22,5,17,13,13,10');
    END IF;

    -- =========================================================
    -- SECTION 3 : CREDITS SANS APPROBATION IDENTIFIABLE
    -- =========================================================
    -- Tout concours doit etre rattachable a une decision de credit
    -- formalisee, a un agent d'octroi et a un valideur distinct de
    -- l'initiateur (principe des quatre yeux). Les remboursements et
    -- leurs annulations relevent du meme principe.
    -- NB : le module LD ne porte pas les champs maker / checker dans la
    --      table contrat ; les tests d'approbation portent sur le
    --      module CL.
    -- =========================================================
    print_section('3. CREDITS SANS APPROBATION IDENTIFIABLE');

    -- 3.1 Dossiers non autorises dans le systeme mais deja decaisses
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.AUTH_STAT,'U') != 'A'
      AND NVL(m.AMOUNT_DISBURSED,0) > 0;
    print_test('Dossiers non autorises (AUTH_STAT != A) et decaisses', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,6,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|'
            || RPAD(' AUTH',6) || '|' || RPAD(' MAKER',16) || '|' || RPAD(' SAISIE LE',13) || '|');
        tbl_line('4,12,24,22,17,17,6,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   NVL(m.AUTH_STAT,'-') AS auth, NVL(m.MAKER_ID,'-') AS maker, m.MAKER_DT_STAMP
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AUTH_STAT,'U') != 'A'
              AND NVL(m.AMOUNT_DISBURSED,0) > 0
            ORDER BY NVL(m.AMOUNT_DISBURSED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || d.auth,6) || '|' || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,17,6,16,13');
    END IF;

    -- 3.2 Dossiers sans valideur identifie
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE (m.CHECKER_ID IS NULL OR TRIM(m.CHECKER_ID) IS NULL)
      AND NVL(m.AMOUNT_FINANCED,0) > 0;
    print_test('Dossiers sans valideur identifie (CHECKER_ID absent)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|'
            || RPAD(' MAKER',16) || '|' || RPAD(' SAISIE LE',13) || '|');
        tbl_line('4,12,24,22,17,17,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   NVL(m.MAKER_ID,'-') AS maker, m.MAKER_DT_STAMP
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE (m.CHECKER_ID IS NULL OR TRIM(m.CHECKER_ID) IS NULL)
              AND NVL(m.AMOUNT_FINANCED,0) > 0
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,17,16,13');
    END IF;

    -- 3.3 Dossiers auto-approuves (initiateur = valideur)
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE m.MAKER_ID IS NOT NULL AND m.CHECKER_ID IS NOT NULL
      AND UPPER(TRIM(m.MAKER_ID)) = UPPER(TRIM(m.CHECKER_ID))
      AND NVL(m.AMOUNT_FINANCED,0) > 0;
    print_test('Dossiers auto-approuves (MAKER_ID = CHECKER_ID)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|'
            || RPAD(' UTILISATEUR',16) || '|' || RPAD(' VALIDE LE',13) || '|');
        tbl_line('4,12,24,22,17,17,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   m.MAKER_ID AS usr, m.CHECKER_DT_STAMP
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.MAKER_ID IS NOT NULL AND m.CHECKER_ID IS NOT NULL
              AND UPPER(TRIM(m.MAKER_ID)) = UPPER(TRIM(m.CHECKER_ID))
              AND NVL(m.AMOUNT_FINANCED,0) > 0
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,17,16,13');
    END IF;

    -- 3.4 Dossiers sans agent d'octroi identifie
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE (m.SANCTIONING_OFFICER IS NULL OR TRIM(m.SANCTIONING_OFFICER) IS NULL)
      AND NVL(m.AMOUNT_FINANCED,0) > 0;
    print_test('Dossiers sans agent d''octroi (SANCTIONING_OFFICER)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' OCTROI LE',13) || '|'
            || RPAD(' MAKER',16) || '|' || RPAD(' CHECKER',16) || '|');
        tbl_line('4,12,24,22,17,13,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, m.BOOK_DATE,
                   NVL(m.MAKER_ID,'-') AS maker, NVL(m.CHECKER_ID,'-') AS checker
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE (m.SANCTIONING_OFFICER IS NULL OR TRIM(m.SANCTIONING_OFFICER) IS NULL)
              AND NVL(m.AMOUNT_FINANCED,0) > 0
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),13) || '|'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,13,16,16');
    END IF;

    -- 3.5 Dossiers significatifs non rattaches a une ligne de credit :
    --     l'engagement echappe au suivi des limites
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE (m.LINE_ID IS NULL OR TRIM(m.LINE_ID) IS NULL)
      AND NVL(m.AMOUNT_FINANCED,0) >= c_mnt_signif;
    print_test('Dossiers >= ' || fmt_m(c_mnt_signif) || ' sans ligne de credit', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,17,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,5,17,17,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.CURRENCY,'-') AS ccy, NVL(m.AMOUNT_FINANCED,0) AS finance,
                   NVL(m.AMOUNT_DISBURSED,0) AS decaisse, m.MATURITY_DATE,
                   NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE (m.LINE_ID IS NULL OR TRIM(m.LINE_ID) IS NULL)
              AND NVL(m.AMOUNT_FINANCED,0) >= c_mnt_signif
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
                || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|');
        END LOOP;
        tbl_line('4,12,24,22,5,17,17,13,10');
    END IF;

    -- 3.6 Liquidations (remboursements) non autorisees ou auto-autorisees
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT l.ACCOUNT_NUMBER, l.EVENT_SEQ_NO, l.VALUE_DATE,
                   NVL(pm.mnt,0) AS montant,
                   NVL(l.AUTH_STAT,'-') AS auth, NVL(l.MAKER_ID,'-') AS maker,
                   NVL(l.CHECKER_ID,'-') AS checker,
                   CASE WHEN NVL(l.AUTH_STAT,'U') != 'A' THEN 'NON AUTORISE'
                        ELSE 'AUTO-VALIDE' END AS motif
            FROM CLTB_LIQ l
            LEFT JOIN (
                SELECT ACCOUNT_NUMBER, EVENT_SEQ_NO, SUM(NVL(AMOUNT_PAID,0)) AS mnt
                FROM CLTB_AMOUNT_PAID
                GROUP BY ACCOUNT_NUMBER, EVENT_SEQ_NO
            ) pm ON pm.ACCOUNT_NUMBER = l.ACCOUNT_NUMBER AND pm.EVENT_SEQ_NO = l.EVENT_SEQ_NO
            WHERE NVL(l.AUTH_STAT,'U') != 'A'
               OR (l.MAKER_ID IS NOT NULL AND l.CHECKER_ID IS NOT NULL
                   AND UPPER(TRIM(l.MAKER_ID)) = UPPER(TRIM(l.CHECKER_ID)))
        ) q
        ORDER BY q.montant DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_n(d.EVENT_SEQ_NO),7) || ' |'
            || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|'
            || LPAD(fmt_m(d.montant),16) || ' |'
            || RPAD(' ' || d.auth,6) || '|'
            || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
            || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|'
            || RPAD(' ' || d.motif,15) || '|';
    END LOOP;
    print_test('Liquidations non autorisees ou auto-validees', v_count);
    IF v_count > 0 THEN
        tbl_line('4,22,8,13,17,6,16,16,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DOSSIER',22) || '|' || RPAD(' ESN',8) || '|'
            || RPAD(' DATE VALEUR',13) || '|' || RPAD(' MONTANT',17) || '|' || RPAD(' AUTH',6) || '|'
            || RPAD(' MAKER',16) || '|' || RPAD(' CHECKER',16) || '|' || RPAD(' MOTIF',15) || '|');
        tbl_line('4,22,8,13,17,6,16,16,15');
        flush_lignes;
        tbl_line('4,22,8,13,17,6,16,16,15');
    END IF;

    -- 3.7 Liquidations annulees : un remboursement enregistre puis
    --     contre-passe efface une reduction de creance
    v_lignes.DELETE; v_count := 0; v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT q.*, COUNT(*) OVER () AS nb_total FROM (
            SELECT l.ACCOUNT_NUMBER, l.EVENT_SEQ_NO, l.VALUE_DATE,
                   NVL(pm.mnt,0) AS montant,
                   NVL(l.MAKER_ID,'-') AS maker, NVL(l.REV_MAKER_ID,'-') AS rev_maker,
                   l.REV_MAKER_DT_STAMP,
                   CASE WHEN l.MAKER_ID IS NOT NULL AND l.REV_MAKER_ID IS NOT NULL
                             AND UPPER(TRIM(l.MAKER_ID)) = UPPER(TRIM(l.REV_MAKER_ID))
                        THEN 'MEME AGENT' ELSE '-' END AS alerte
            FROM CLTB_LIQ l
            LEFT JOIN (
                SELECT ACCOUNT_NUMBER, EVENT_SEQ_NO, SUM(NVL(AMOUNT_PAID,0)) AS mnt
                FROM CLTB_AMOUNT_PAID
                GROUP BY ACCOUNT_NUMBER, EVENT_SEQ_NO
            ) pm ON pm.ACCOUNT_NUMBER = l.ACCOUNT_NUMBER AND pm.EVENT_SEQ_NO = l.EVENT_SEQ_NO
            WHERE l.REV_MAKER_ID IS NOT NULL
        ) q
        ORDER BY q.montant DESC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_count := d.nb_total;
        v_row_num := v_row_num + 1;
        v_lignes(v_row_num) := '  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
            || LPAD(fmt_n(d.EVENT_SEQ_NO),7) || ' |'
            || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|'
            || LPAD(fmt_m(d.montant),16) || ' |'
            || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
            || RPAD(' ' || SUBSTR(d.rev_maker,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.REV_MAKER_DT_STAMP),13) || '|'
            || RPAD(' ' || d.alerte,13) || '|';
    END LOOP;
    print_test('Liquidations annulees (contre-passations)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,22,8,13,17,16,16,13,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' DOSSIER',22) || '|' || RPAD(' ESN',8) || '|'
            || RPAD(' DATE VALEUR',13) || '|' || RPAD(' MONTANT',17) || '|' || RPAD(' MAKER',16) || '|'
            || RPAD(' ANNULE PAR',16) || '|' || RPAD(' ANNULE LE',13) || '|' || RPAD(' ALERTE',13) || '|');
        tbl_line('4,22,8,13,17,16,16,13,13');
        flush_lignes;
        tbl_line('4,22,8,13,17,16,16,13,13');
    END IF;

    -- =========================================================
    -- SECTION 4 : ANOMALIES DE DECAISSEMENT
    -- =========================================================
    -- Le decaissement est l'acte par lequel le risque se materialise :
    -- il doit etre posterieur a l'approbation, limite au montant accorde,
    -- adosse a un echeancier et conforme aux blocages en vigueur.
    -- =========================================================
    print_section('4. ANOMALIES DE DECAISSEMENT');

    -- 4.1 Montant decaisse superieur au montant finance
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.AMOUNT_DISBURSED,0) > NVL(m.AMOUNT_FINANCED,0) + c_tol_decaiss;
    print_test('Decaissement superieur au montant finance', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,17,17,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|' || RPAD(' ECART',17) || '|'
            || RPAD(' DATE VALEUR',13) || '|');
        tbl_line('4,12,24,22,5,17,17,17,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.CURRENCY,'-') AS ccy, NVL(m.AMOUNT_FINANCED,0) AS finance,
                   NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   NVL(m.AMOUNT_DISBURSED,0) - NVL(m.AMOUNT_FINANCED,0) AS ecart, m.VALUE_DATE
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AMOUNT_DISBURSED,0) > NVL(m.AMOUNT_FINANCED,0) + c_tol_decaiss
            ORDER BY NVL(m.AMOUNT_DISBURSED,0) - NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || LPAD(fmt_m(d.ecart),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,5,17,17,17,13');
    END IF;

    -- 4.2 Dossiers accordes mais jamais decaisses
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.AMOUNT_FINANCED,0) > 0
      AND NVL(m.AMOUNT_DISBURSED,0) = 0;
    print_test('Dossiers accordes mais jamais decaisses', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,13,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FINANCE',17) || '|' || RPAD(' BOOK DATE',13) || '|' || RPAD(' ANCIENNETE',13) || '|'
            || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,5,17,13,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.CURRENCY,'-') AS ccy, NVL(m.AMOUNT_FINANCED,0) AS finance, m.BOOK_DATE,
                   TRUNC(SYSDATE) - TRUNC(m.BOOK_DATE) AS anciennete,
                   NVL(m.ACCOUNT_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AMOUNT_FINANCED,0) > 0
              AND NVL(m.AMOUNT_DISBURSED,0) = 0
            ORDER BY NVL(m.AMOUNT_FINANCED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),13) || '|'
                || LPAD(fmt_n(d.anciennete) || ' j',12) || ' |'
                || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|');
        END LOOP;
        tbl_line('4,12,24,22,5,17,13,13,10');
    END IF;

    -- 4.3 Decaissements partiels anciens : une part du concours accorde
    --     reste immobilisee sans decision de renonciation
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.AMOUNT_DISBURSED,0) > 0
      AND NVL(m.AMOUNT_DISBURSED,0) < NVL(m.AMOUNT_FINANCED,0) - c_tol_decaiss
      AND m.BOOK_DATE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(m.BOOK_DATE) > c_impaye_3;
    print_test('Decaissements partiels de plus de ' || c_impaye_3 || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,17,10,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|'
            || RPAD(' RESTE A DEC.',17) || '|' || RPAD(' % DEC.',10) || '|' || RPAD(' BOOK DATE',13) || '|');
        tbl_line('4,12,24,22,17,17,17,10,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   NVL(m.AMOUNT_FINANCED,0) - NVL(m.AMOUNT_DISBURSED,0) AS reste,
                   ROUND(NVL(m.AMOUNT_DISBURSED,0) * 100 / NULLIF(m.AMOUNT_FINANCED,0), 1) AS pct,
                   m.BOOK_DATE
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AMOUNT_DISBURSED,0) > 0
              AND NVL(m.AMOUNT_DISBURSED,0) < NVL(m.AMOUNT_FINANCED,0) - c_tol_decaiss
              AND m.BOOK_DATE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(m.BOOK_DATE) > c_impaye_3
            ORDER BY NVL(m.AMOUNT_FINANCED,0) - NVL(m.AMOUNT_DISBURSED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || LPAD(fmt_m(d.reste),16) || ' |'
                || LPAD(TO_CHAR(NVL(d.pct,0),'FM990D0') || ' %',9) || ' |'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,17,17,10,13');
    END IF;

    -- 4.4 Credits prenant effet AVANT leur validation
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE m.VALUE_DATE IS NOT NULL AND m.CHECKER_DT_STAMP IS NOT NULL
      AND m.VALUE_DATE < TRUNC(m.CHECKER_DT_STAMP);
    print_test('Credits prenant effet avant leur validation', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,13,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DATE VALEUR',13) || '|'
            || RPAD(' VALIDE LE',13) || '|' || RPAD(' ECART',9) || '|' || RPAD(' CHECKER',16) || '|');
        tbl_line('4,12,24,22,17,13,13,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, m.VALUE_DATE, m.CHECKER_DT_STAMP,
                   TRUNC(m.CHECKER_DT_STAMP) - TRUNC(m.VALUE_DATE) AS ecart,
                   NVL(m.CHECKER_ID,'-') AS checker
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.VALUE_DATE IS NOT NULL AND m.CHECKER_DT_STAMP IS NOT NULL
              AND m.VALUE_DATE < TRUNC(m.CHECKER_DT_STAMP)
            ORDER BY TRUNC(m.CHECKER_DT_STAMP) - TRUNC(m.VALUE_DATE) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|'
                || LPAD(fmt_n(d.ecart) || ' j',8) || ' |'
                || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,13,13,9,16');
    END IF;

    -- 4.5 Credits a date de valeur retroactive par rapport a la saisie
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE m.VALUE_DATE IS NOT NULL AND m.BOOK_DATE IS NOT NULL
      AND m.VALUE_DATE < m.BOOK_DATE;
    print_test('Credits a date de valeur anterieure a la saisie', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,13,13,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DATE VALEUR',13) || '|'
            || RPAD(' BOOK DATE',13) || '|' || RPAD(' RETRO',9) || '|' || RPAD(' MAKER',16) || '|');
        tbl_line('4,12,24,22,17,13,13,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, m.VALUE_DATE, m.BOOK_DATE,
                   TRUNC(m.BOOK_DATE) - TRUNC(m.VALUE_DATE) AS retro,
                   NVL(m.MAKER_ID,'-') AS maker
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.VALUE_DATE IS NOT NULL AND m.BOOK_DATE IS NOT NULL
              AND m.VALUE_DATE < m.BOOK_DATE
            ORDER BY TRUNC(m.BOOK_DATE) - TRUNC(m.VALUE_DATE) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),13) || '|'
                || LPAD(fmt_n(d.retro) || ' j',8) || ' |'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,13,13,9,16');
    END IF;

    -- 4.6 Dossiers decaisses sans echeancier : aucun plan de remboursement
    --     n'encadre le recouvrement
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.AMOUNT_DISBURSED,0) > 0
      AND NOT EXISTS (SELECT 1 FROM CLTB_ACCOUNT_SCHEDULES s
                      WHERE s.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER);
    print_test('Dossiers decaisses sans echeancier', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,5,17,13,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' DECAISSE',17) || '|' || RPAD(' DATE VALEUR',13) || '|' || RPAD(' MATURITE',13) || '|'
            || RPAD(' STATUT',10) || '|');
        tbl_line('4,12,24,22,5,17,13,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.CURRENCY,'-') AS ccy, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   m.VALUE_DATE, m.MATURITY_DATE, NVL(m.USER_DEFINED_STATUS,'-') AS st
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.AMOUNT_DISBURSED,0) > 0
              AND NOT EXISTS (SELECT 1 FROM CLTB_ACCOUNT_SCHEDULES s
                              WHERE s.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER)
            ORDER BY NVL(m.AMOUNT_DISBURSED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|' || RPAD(' ' || fmt_d(d.MATURITY_DATE),13) || '|'
                || RPAD(' ' || SUBSTR(d.st,1,8),10) || '|');
        END LOOP;
        tbl_line('4,12,24,22,5,17,13,13,10');
    END IF;

    -- 4.7 Dossiers portant un blocage de decaissement pourtant decaisses
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE NVL(m.STOP_DSBR,'N') = 'Y'
      AND NVL(m.AMOUNT_DISBURSED,0) > 0;
    print_test('Dossiers decaisses malgre un blocage de decaissement', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,17,17,13,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' FINANCE',17) || '|' || RPAD(' DECAISSE',17) || '|'
            || RPAD(' DATE VALEUR',13) || '|' || RPAD(' MAKER',16) || '|' || RPAD(' MODIFIE LE',13) || '|');
        tbl_line('4,12,24,22,17,17,13,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   NVL(m.AMOUNT_FINANCED,0) AS finance, NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   m.VALUE_DATE, NVL(m.MAKER_ID,'-') AS maker, m.MAKER_DT_STAMP
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE NVL(m.STOP_DSBR,'N') = 'Y'
              AND NVL(m.AMOUNT_DISBURSED,0) > 0
            ORDER BY NVL(m.AMOUNT_DISBURSED,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || LPAD(fmt_m(d.finance),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),13) || '|'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,22,17,17,13,16,13');
    END IF;

    -- 4.8 Decaissement superieur a la limite de la ligne rattachee
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_APPS_MASTER m
    WHERE m.LINE_ID IS NOT NULL AND TRIM(m.LINE_ID) IS NOT NULL
      AND NVL(m.AMOUNT_DISBURSED,0) >
          NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
               WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID),0)
      AND EXISTS (SELECT 1 FROM GETM_FACILITY f
                  WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID);
    print_test('Decaissement superieur a la limite de la ligne rattachee', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,22,16,17,17,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' DOSSIER',22) || '|' || RPAD(' LIGNE',16) || '|'
            || RPAD(' LIMITE LIGNE',17) || '|' || RPAD(' DECAISSE',17) || '|' || RPAD(' DEPASSEMENT',17) || '|');
        tbl_line('4,12,24,22,16,17,17,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.CUSTOMER_ID,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, m.ACCOUNT_NUMBER,
                   m.LINE_ID,
                   NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                        WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID),0) AS limite,
                   NVL(m.AMOUNT_DISBURSED,0) AS decaisse,
                   NVL(m.AMOUNT_DISBURSED,0)
                   - NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                          WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID),0) AS depass
            FROM CLTB_ACCOUNT_APPS_MASTER m
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = m.CUSTOMER_ID
            WHERE m.LINE_ID IS NOT NULL AND TRIM(m.LINE_ID) IS NOT NULL
              AND NVL(m.AMOUNT_DISBURSED,0) >
                  NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                       WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID),0)
              AND EXISTS (SELECT 1 FROM GETM_FACILITY f
                          WHERE f.LINE_CODE = m.LINE_ID OR TO_CHAR(f.ID) = m.LINE_ID)
            ORDER BY depass DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.ACCOUNT_NUMBER,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_ID,1,14),16) || '|'
                || LPAD(fmt_m(d.limite),16) || ' |' || LPAD(fmt_m(d.decaisse),16) || ' |'
                || LPAD(fmt_m(d.depass),16) || ' |');
        END LOOP;
        tbl_line('4,12,24,22,16,17,17,17');
    END IF;

    -- =========================================================
    -- FIN
    -- =========================================================
    print_temps;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TOTAL TESTS EXECUTES : ' || v_test_no);
    DBMS_OUTPUT.PUT_LINE('   TESTS AVEC ANOMALIES : ' || v_anomalies);
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
