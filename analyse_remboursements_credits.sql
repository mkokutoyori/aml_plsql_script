-- ============================================================
-- ANALYSE DES REMBOURSEMENTS DE CREDITS — MODULE CL
-- Base : FLEXCUBE (FCUBS)
-- Composantes retenues : PRINCIPAL / MAIN_INT / TVA_MAININT
-- ============================================================
-- OBJECTIFS
--   1. Sur les credits bookes depuis janvier 2023, identifier ceux
--      qui se remboursent normalement.
--   2. Pour les credits ayant connu des retards, lister les MOIS ou
--      les remboursements ont ete irreguliers.
--   3. Chiffrer, a la date de reference, le PRINCIPAL restant a
--      recouvrer sur les credits encore en difficulte.
--
-- METHODE
--   ATTENDU  : CLTB_ACCOUNT_SCHEDULES.AMOUNT_DUE, par echeance,
--              limite aux 3 composantes retenues.
--   ENCAISSE : ACTB_HISTORY, MODULE='CL',
--              AMOUNT_TAG IN (PRINCIPAL_LIQD, MAIN_INT_LIQD, TVA_MAININT_LIQD),
--              RELATED_ACCOUNT = compte du credit,
--              restreint a la jambe "compte client" (AC_NATURAL_GL LIKE '37%')
--              pour ne compter chaque ecriture qu'une seule fois.
--              Signe : D = +LCY_AMOUNT, C = -LCY_AMOUNT
--              (les extournes s'annulent donc d'elles-memes).
--   IRREGULARITE : un mois M est declare irregulier lorsque, a la fin
--              de M, le CUMUL des echeances exigibles depasse le CUMUL
--              des encaissements. La comparaison etant cumulative, un
--              paiement en avance ou un rattrapage ulterieur regularise
--              automatiquement les mois suivants ; seuls les mois
--              reellement en souffrance ressortent.
--   RETARD (DPD) : plus ancienne echeance non couverte par le cumul
--              encaisse (imputation FIFO), en jours a la date de reference.
--
-- LIMITES CONNUES
--   - Les montants encaisses sont en monnaie locale (LCY_AMOUNT) alors
--     que AMOUNT_FINANCED est dans la devise du credit : pour un
--     portefeuille en devise, ajouter un filtre devise sur le perimetre.
--   - Seules les 3 composantes demandees sont prises en compte : penalites,
--     commissions et frais sont volontairement exclus.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET LINESIZE 250
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    -- ========================================================
    -- PARAMETRES  (les seules lignes a ajuster)
    -- ========================================================
    v_d_debut    DATE         := TO_DATE('01/01/2023','DD/MM/YYYY'); -- debut du perimetre (BOOK_DATE)
    v_d_ref      DATE         := TRUNC(SYSDATE);                     -- date d'arrete de l'analyse
    v_gl_client  VARCHAR2(10) := '37%';   -- prefixe AC_NATURAL_GL de la jambe compte client
    v_tol        NUMBER       := 1;       -- tolerance d'arrondi, en unite de compte
    c_max_lig    CONSTANT PLS_INTEGER := 30;  -- lignes max par tableau detaille
    c_max_cred   CONSTANT PLS_INTEGER := 20;  -- credits max detailles en section 4

    -- ========================================================
    -- VARIABLES TECHNIQUES
    -- ========================================================
    v_nb_mois    PLS_INTEGER;                       -- nb de mois de la periode analysee
    v_sep        VARCHAR2(200) := RPAD('=',148,'=');
    v_i          PLS_INTEGER;
    v_n          PLS_INTEGER;
    v_ecr_tot    PLS_INTEGER := 0;   -- ecritures CL de la periode
    v_ecr_ret    PLS_INTEGER := 0;   -- dont retenues par le filtre GL
    v_lig_master PLS_INTEGER := 0;   -- lignes du master sur le perimetre
    v_cle        VARCHAR2(20);  -- cle de map : 'YYYYMM' ou tranche de retard
    v_prev_acc   VARCHAR2(100);
    v_nb_cred_d  PLS_INTEGER;
    v_row        PLS_INTEGER;
    v_max_arr    NUMBER;        -- arriere du mois le plus degrade
    v_max_mois   VARCHAR2(10);  -- libelle de ce mois

    -- Compteurs de portefeuille
    v_nb_tot     PLS_INTEGER := 0;
    v_nb_nd      PLS_INTEGER := 0;   -- NON DEMARRE
    v_nb_sain    PLS_INTEGER := 0;   -- SAIN
    v_nb_reg     PLS_INTEGER := 0;   -- REGULARISE
    v_nb_dif     PLS_INTEGER := 0;   -- EN DIFFICULTE
    v_nb_solde   PLS_INTEGER := 0;   -- principal integralement rembourse
    v_nb_sans_e  PLS_INTEGER := 0;   -- sans aucun encaissement
    v_nb_sans_s  PLS_INTEGER := 0;   -- sans echeancier

    -- Cumuls de portefeuille
    v_fin_tot    NUMBER := 0;  v_du_pri  NUMBER := 0;  v_du_int  NUMBER := 0;  v_du_tva  NUMBER := 0;
    v_pa_pri     NUMBER := 0;  v_pa_int  NUMBER := 0;  v_pa_tva  NUMBER := 0;
    v_arr_tot    NUMBER := 0;  v_arr_pri NUMBER := 0;  v_rest_pri NUMBER := 0;
    v_arr_it     NUMBER := 0;  -- interets + TVA echus impayes

    -- Cumuls par classe
    TYPE t_cls IS RECORD (nb PLS_INTEGER, fin NUMBER, arr NUMBER, arr_pri NUMBER);
    TYPE t_cls_tab IS TABLE OF t_cls INDEX BY VARCHAR2(20);
    g_cls        t_cls_tab;

    -- Cumuls par tranche de retard (credits en difficulte)
    g_dpd        t_cls_tab;
    TYPE t_rst_tab IS TABLE OF NUMBER INDEX BY VARCHAR2(20);
    g_dpd_rst    t_rst_tab;   -- principal restant du par tranche

    -- Concentration mensuelle des irregularites
    TYPE t_mois IS RECORD (lib VARCHAR2(10), nb PLS_INTEGER, arr NUMBER, arr_pri NUMBER);
    TYPE t_mois_tab IS TABLE OF t_mois INDEX BY VARCHAR2(6);
    g_mois       t_mois_tab;
    v_rm         t_mois;      -- enregistrement de travail pour g_mois

    -- ========================================================
    -- CURSEUR 1 — SITUATION DE CHAQUE CREDIT A LA DATE DE REFERENCE
    -- ========================================================
    CURSOR c_credits IS
    WITH
    -- Perimetre : credits bookes sur la periode. Le GROUP BY protege
    -- d'une eventuelle duplication d'ACCOUNT_NUMBER dans le master.
    lo AS (
        SELECT m.ACCOUNT_NUMBER                 AS acc,
               MAX(m.PRIMARY_APPLICANT_NAME)    AS nom,
               MAX(m.PRODUCT_CODE)              AS prd,
               MIN(m.BOOK_DATE)                 AS dt_book,
               MAX(m.MATURITY_DATE)             AS dt_mat,
               MAX(NVL(m.AMOUNT_FINANCED,0))    AS montant,
               MAX(m.ACCOUNT_STATUS)            AS statut
        FROM   CLTB_ACCOUNT_APPS_MASTER m
        WHERE  m.BOOK_DATE >= v_d_debut
        AND    m.BOOK_DATE <= v_d_ref
        GROUP BY m.ACCOUNT_NUMBER
    ),
    -- Echeancier EXIGIBLE a la date de reference, agrege par date d'echeance
    ech AS (
        SELECT s.ACCOUNT_NUMBER AS acc, s.SCHEDULE_DUE_DATE AS dt,
               SUM(CASE WHEN s.COMPONENT_NAME='PRINCIPAL'   THEN NVL(s.AMOUNT_DUE,0) ELSE 0 END) AS du_pri,
               SUM(CASE WHEN s.COMPONENT_NAME='MAIN_INT'    THEN NVL(s.AMOUNT_DUE,0) ELSE 0 END) AS du_int,
               SUM(CASE WHEN s.COMPONENT_NAME='TVA_MAININT' THEN NVL(s.AMOUNT_DUE,0) ELSE 0 END) AS du_tva
        FROM   CLTB_ACCOUNT_SCHEDULES s
        WHERE  s.COMPONENT_NAME IN ('PRINCIPAL','MAIN_INT','TVA_MAININT')
        AND    s.SCHEDULE_DUE_DATE <= v_d_ref
        GROUP BY s.ACCOUNT_NUMBER, s.SCHEDULE_DUE_DATE
    ),
    -- Echeancier COMPLET (y compris echeances futures) : sert a mesurer
    -- le principal total restant du, au-dela du seul impaye echu.
    ech_all AS (
        SELECT s.ACCOUNT_NUMBER AS acc,
               SUM(CASE WHEN s.COMPONENT_NAME='PRINCIPAL' THEN NVL(s.AMOUNT_DUE,0) ELSE 0 END) AS pri_prevu,
               SUM(NVL(s.AMOUNT_DUE,0))                                                        AS tot_prevu,
               MAX(s.SCHEDULE_DUE_DATE)                                                        AS derniere_ech
        FROM   CLTB_ACCOUNT_SCHEDULES s
        WHERE  s.COMPONENT_NAME IN ('PRINCIPAL','MAIN_INT','TVA_MAININT')
        GROUP BY s.ACCOUNT_NUMBER
    ),
    -- Encaissements reels, jambe compte client, par jour
    enc AS (
        SELECT h.RELATED_ACCOUNT AS acc, TRUNC(h.TRN_DT) AS dt,
               SUM(CASE WHEN h.AMOUNT_TAG='PRINCIPAL_LIQD'
                        THEN CASE WHEN h.DRCR_IND='D' THEN NVL(h.LCY_AMOUNT,0) ELSE -NVL(h.LCY_AMOUNT,0) END
                        ELSE 0 END) AS pa_pri,
               SUM(CASE WHEN h.AMOUNT_TAG='MAIN_INT_LIQD'
                        THEN CASE WHEN h.DRCR_IND='D' THEN NVL(h.LCY_AMOUNT,0) ELSE -NVL(h.LCY_AMOUNT,0) END
                        ELSE 0 END) AS pa_int,
               SUM(CASE WHEN h.AMOUNT_TAG='TVA_MAININT_LIQD'
                        THEN CASE WHEN h.DRCR_IND='D' THEN NVL(h.LCY_AMOUNT,0) ELSE -NVL(h.LCY_AMOUNT,0) END
                        ELSE 0 END) AS pa_tva
        FROM   ACTB_HISTORY h
        WHERE  h.MODULE = 'CL'
        AND    h.AMOUNT_TAG IN ('PRINCIPAL_LIQD','MAIN_INT_LIQD','TVA_MAININT_LIQD')
        AND    h.TRN_DT >= v_d_debut
        AND    h.TRN_DT <= v_d_ref
        AND    EXISTS (SELECT 1 FROM STTB_ACCOUNT g
                       WHERE g.AC_GL_NO = h.AC_NO
                       AND   g.AC_NATURAL_GL LIKE v_gl_client)
        GROUP BY h.RELATED_ACCOUNT, TRUNC(h.TRN_DT)
    ),
    ech_t AS (
        SELECT acc, SUM(du_pri) AS du_pri, SUM(du_int) AS du_int, SUM(du_tva) AS du_tva,
               COUNT(*) AS nb_ech_due, MAX(dt) AS derniere_ech_due
        FROM ech GROUP BY acc
    ),
    enc_t AS (
        SELECT acc, SUM(pa_pri) AS pa_pri, SUM(pa_int) AS pa_int, SUM(pa_tva) AS pa_tva,
               MAX(CASE WHEN pa_pri+pa_int+pa_tva > 0 THEN dt END) AS dernier_pmt
        FROM enc GROUP BY acc
    ),
    -- Plus ancienne echeance non couverte (imputation FIFO du cumul encaisse)
    dpd AS (
        SELECT x.acc, MIN(x.dt) AS plus_vieille_impayee
        FROM ( SELECT e.acc, e.dt,
                      SUM(e.du_pri+e.du_int+e.du_tva) OVER (PARTITION BY e.acc ORDER BY e.dt) AS cum_du
               FROM   ech e ) x
        LEFT JOIN enc_t t ON t.acc = x.acc
        WHERE x.cum_du > NVL(t.pa_pri,0)+NVL(t.pa_int,0)+NVL(t.pa_tva,0) + v_tol
        GROUP BY x.acc
    ),
    -- Calendrier mensuel de la periode
    cal AS (
        SELECT ADD_MONTHS(TRUNC(v_d_debut,'MM'), LEVEL-1) AS mm
        FROM DUAL CONNECT BY LEVEL <= v_nb_mois
    ),
    ech_m AS (
        SELECT acc, TRUNC(dt,'MM') AS mm, SUM(du_pri) AS du_pri,
               SUM(du_pri+du_int+du_tva) AS du_tot
        FROM ech GROUP BY acc, TRUNC(dt,'MM')
    ),
    enc_m AS (
        SELECT acc, TRUNC(dt,'MM') AS mm, SUM(pa_pri) AS pa_pri,
               SUM(pa_pri+pa_int+pa_tva) AS pa_tot
        FROM enc GROUP BY acc, TRUNC(dt,'MM')
    ),
    grid AS (
        SELECT l.acc, c.mm FROM lo l JOIN cal c ON c.mm >= TRUNC(l.dt_book,'MM')
    ),
    -- Arriere cumule a la fin de chaque mois
    arr AS (
        SELECT g.acc, g.mm,
               SUM(NVL(e.du_tot,0)-NVL(p.pa_tot,0)) OVER (PARTITION BY g.acc ORDER BY g.mm) AS arriere,
               SUM(NVL(e.du_pri,0)-NVL(p.pa_pri,0)) OVER (PARTITION BY g.acc ORDER BY g.mm) AS arriere_pri
        FROM       grid  g
        LEFT JOIN  ech_m e ON e.acc = g.acc AND e.mm = g.mm
        LEFT JOIN  enc_m p ON p.acc = g.acc AND p.mm = g.mm
    ),
    irr AS (
        SELECT acc, COUNT(*) AS nb_mois_irr, MAX(arriere) AS arr_max,
               MIN(mm) AS prem_mois, MAX(mm) AS dern_mois
        FROM arr WHERE arriere > v_tol GROUP BY acc
    ),
    base AS (
        SELECT l.acc, l.nom, l.prd, l.dt_book, l.dt_mat, l.montant, l.statut,
               (SELECT MAX(p.PRODUCT_DESC) FROM CLTM_PRODUCT p WHERE p.PRODUCT_CODE = l.prd) AS prd_lib,
               NVL(ed.du_pri,0) AS du_pri, NVL(ed.du_int,0) AS du_int, NVL(ed.du_tva,0) AS du_tva,
               NVL(ed.nb_ech_due,0) AS nb_ech_due, ed.derniere_ech_due,
               NVL(ea.pri_prevu,0) AS pri_prevu, NVL(ea.tot_prevu,0) AS tot_prevu, ea.derniere_ech,
               NVL(en.pa_pri,0) AS pa_pri, NVL(en.pa_int,0) AS pa_int, NVL(en.pa_tva,0) AS pa_tva,
               en.dernier_pmt,
               NVL(ir.nb_mois_irr,0) AS nb_mois_irr, NVL(ir.arr_max,0) AS arr_max,
               ir.prem_mois, ir.dern_mois,
               dp.plus_vieille_impayee
        FROM      lo l
        LEFT JOIN ech_t   ed ON ed.acc = l.acc
        LEFT JOIN ech_all ea ON ea.acc = l.acc
        LEFT JOIN enc_t   en ON en.acc = l.acc
        LEFT JOIN irr     ir ON ir.acc = l.acc
        LEFT JOIN dpd     dp ON dp.acc = l.acc
    ),
    calc AS (
        SELECT b.*,
               b.du_pri + b.du_int + b.du_tva                             AS du_tot,
               b.pa_pri + b.pa_int + b.pa_tva                             AS pa_tot,
               (b.du_pri+b.du_int+b.du_tva) - (b.pa_pri+b.pa_int+b.pa_tva) AS arriere_tot,
               b.du_pri - b.pa_pri                                        AS arriere_pri,
               b.pri_prevu - b.pa_pri                                     AS pri_restant,
               CASE WHEN b.plus_vieille_impayee IS NULL THEN 0
                    ELSE TRUNC(v_d_ref) - TRUNC(b.plus_vieille_impayee) END AS dpd_jours
        FROM base b
    )
    SELECT c.*,
           CASE WHEN c.nb_ech_due  = 0      THEN 'NON DEMARRE'
                WHEN c.arriere_tot > v_tol  THEN 'EN DIFFICULTE'
                WHEN c.nb_mois_irr > 0      THEN 'REGULARISE'
                ELSE                             'SAIN'
           END AS classe,
           CASE WHEN c.pri_prevu > 0 AND c.pa_pri >= c.pri_prevu - v_tol
                THEN 'OUI' ELSE 'NON' END AS solde,
           CASE WHEN c.du_tot > 0 THEN 100 * c.pa_tot / c.du_tot END AS tx_rec
    FROM calc c
    ORDER BY GREATEST(c.arriere_tot,0) DESC, c.montant DESC;

    TYPE t_cred_tab IS TABLE OF c_credits%ROWTYPE INDEX BY PLS_INTEGER;
    g_cr t_cred_tab;

    -- ========================================================
    -- CURSEUR 2 — MOIS EN IRREGULARITE, CREDIT PAR CREDIT
    -- Trie par gravite : les credits ayant connu le pic d'arriere le
    -- plus eleve remontent en tete.
    -- ========================================================
    CURSOR c_mois IS
    WITH
    lo AS (
        SELECT m.ACCOUNT_NUMBER              AS acc,
               MAX(m.PRIMARY_APPLICANT_NAME) AS nom,
               MIN(m.BOOK_DATE)              AS dt_book,
               MAX(NVL(m.AMOUNT_FINANCED,0)) AS montant,
               MAX(m.ACCOUNT_STATUS)         AS statut
        FROM   CLTB_ACCOUNT_APPS_MASTER m
        WHERE  m.BOOK_DATE >= v_d_debut
        AND    m.BOOK_DATE <= v_d_ref
        GROUP BY m.ACCOUNT_NUMBER
    ),
    ech AS (
        SELECT s.ACCOUNT_NUMBER AS acc, TRUNC(s.SCHEDULE_DUE_DATE,'MM') AS mm,
               SUM(CASE WHEN s.COMPONENT_NAME='PRINCIPAL' THEN NVL(s.AMOUNT_DUE,0) ELSE 0 END) AS du_pri,
               SUM(NVL(s.AMOUNT_DUE,0))                                                        AS du_tot
        FROM   CLTB_ACCOUNT_SCHEDULES s
        WHERE  s.COMPONENT_NAME IN ('PRINCIPAL','MAIN_INT','TVA_MAININT')
        AND    s.SCHEDULE_DUE_DATE <= v_d_ref
        GROUP BY s.ACCOUNT_NUMBER, TRUNC(s.SCHEDULE_DUE_DATE,'MM')
    ),
    enc AS (
        SELECT h.RELATED_ACCOUNT AS acc, TRUNC(h.TRN_DT,'MM') AS mm,
               SUM(CASE WHEN h.AMOUNT_TAG='PRINCIPAL_LIQD'
                        THEN CASE WHEN h.DRCR_IND='D' THEN NVL(h.LCY_AMOUNT,0) ELSE -NVL(h.LCY_AMOUNT,0) END
                        ELSE 0 END) AS pa_pri,
               SUM(CASE WHEN h.DRCR_IND='D' THEN NVL(h.LCY_AMOUNT,0) ELSE -NVL(h.LCY_AMOUNT,0) END) AS pa_tot
        FROM   ACTB_HISTORY h
        WHERE  h.MODULE = 'CL'
        AND    h.AMOUNT_TAG IN ('PRINCIPAL_LIQD','MAIN_INT_LIQD','TVA_MAININT_LIQD')
        AND    h.TRN_DT >= v_d_debut
        AND    h.TRN_DT <= v_d_ref
        AND    EXISTS (SELECT 1 FROM STTB_ACCOUNT g
                       WHERE g.AC_GL_NO = h.AC_NO
                       AND   g.AC_NATURAL_GL LIKE v_gl_client)
        GROUP BY h.RELATED_ACCOUNT, TRUNC(h.TRN_DT,'MM')
    ),
    cal AS (
        SELECT ADD_MONTHS(TRUNC(v_d_debut,'MM'), LEVEL-1) AS mm
        FROM DUAL CONNECT BY LEVEL <= v_nb_mois
    ),
    grid AS (
        SELECT l.acc, c.mm FROM lo l JOIN cal c ON c.mm >= TRUNC(l.dt_book,'MM')
    ),
    arr AS (
        SELECT g.acc, g.mm,
               SUM(NVL(e.du_tot,0)) OVER (PARTITION BY g.acc ORDER BY g.mm) AS cum_du,
               SUM(NVL(p.pa_tot,0)) OVER (PARTITION BY g.acc ORDER BY g.mm) AS cum_pa,
               SUM(NVL(e.du_pri,0)-NVL(p.pa_pri,0)) OVER (PARTITION BY g.acc ORDER BY g.mm) AS arriere_pri
        FROM       grid  g
        LEFT JOIN  ech   e ON e.acc = g.acc AND e.mm = g.mm
        LEFT JOIN  enc   p ON p.acc = g.acc AND p.mm = g.mm
    )
    SELECT a.acc, l.nom, l.montant, l.statut, a.mm,
           a.cum_du, a.cum_pa, a.cum_du - a.cum_pa AS arriere, a.arriere_pri
    FROM      arr a
    JOIN      lo  l ON l.acc = a.acc
    WHERE     a.cum_du - a.cum_pa > v_tol
    ORDER BY  MAX(a.cum_du - a.cum_pa) OVER (PARTITION BY a.acc) DESC, a.acc, a.mm;

    -- ========================================================
    -- OUTILS DE MISE EN FORME
    -- ========================================================
    PROCEDURE p(t VARCHAR2) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(t); END;

    PROCEDURE section(t VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || t);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    -- Ligne de separation d'un tableau, largeurs separees par des virgules
    PROCEDURE tbl_line(p_widths VARCHAR2) IS
        v_line VARCHAR2(400) := '  +';
        v_w    VARCHAR2(400) := p_widths || ',';
        v_pos  NUMBER := 1;
        v_next NUMBER;
    BEGIN
        LOOP
            v_next := INSTR(v_w, ',', v_pos);
            EXIT WHEN v_next = 0;
            v_line := v_line || RPAD('-', TO_NUMBER(SUBSTR(v_w, v_pos, v_next-v_pos)), '-') || '+';
            v_pos  := v_next + 1;
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(v_line);
    END;

    FUNCTION f_txt(v VARCHAR2, w NUMBER) RETURN VARCHAR2 IS
    BEGIN RETURN RPAD(' ' || SUBSTR(NVL(v,'-'), 1, w-2), w) || '|'; END;

    FUNCTION f_num(v NUMBER, w NUMBER) RETURN VARCHAR2 IS
    BEGIN RETURN LPAD(TO_CHAR(NVL(v,0),'FM999G999G999G990'), w-1) || ' |'; END;

    FUNCTION f_int(v NUMBER, w NUMBER) RETURN VARCHAR2 IS
    BEGIN RETURN LPAD(TO_CHAR(NVL(v,0),'FM999G990'), w-1) || ' |'; END;

    FUNCTION f_dat(v DATE, w NUMBER) RETURN VARCHAR2 IS
    BEGIN RETURN RPAD(' ' || NVL(TO_CHAR(v,'DD/MM/YYYY'),'-'), w) || '|'; END;

    FUNCTION f_pct(v NUMBER, w NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN LPAD(CASE WHEN v IS NULL THEN '-'
                         ELSE TO_CHAR(ROUND(v,1),'FM99990D0') || '%' END, w-1) || ' |';
    END;

    -- Cumul dans une map de classe
    PROCEDURE add_cls(p_map IN OUT NOCOPY t_cls_tab, p_cle VARCHAR2,
                      p_fin NUMBER, p_arr NUMBER, p_arr_pri NUMBER) IS
        l_r t_cls;
    BEGIN
        -- Sur une collection associative de RECORD, affecter directement un
        -- champ d'un element inexistant leve NO_DATA_FOUND : on passe donc
        -- par un enregistrement de travail affecte en bloc.
        IF p_map.EXISTS(p_cle) THEN
            l_r := p_map(p_cle);
        ELSE
            l_r.nb := 0; l_r.fin := 0; l_r.arr := 0; l_r.arr_pri := 0;
        END IF;
        l_r.nb      := l_r.nb + 1;
        l_r.fin     := l_r.fin + NVL(p_fin,0);
        l_r.arr     := l_r.arr + GREATEST(NVL(p_arr,0),0);
        l_r.arr_pri := l_r.arr_pri + GREATEST(NVL(p_arr_pri,0),0);
        p_map(p_cle) := l_r;
    END;

    -- Ligne "libelle .......... valeur"
    PROCEDURE kv(lib VARCHAR2, val VARCHAR2) IS
    BEGIN DBMS_OUTPUT.PUT_LINE('    ' || RPAD(lib || ' ', 46, '.') || ' ' || val); END;

    PROCEDURE pr_cls(k VARCHAR2, lib VARCHAR2) IS
    BEGIN
        IF NOT g_cls.EXISTS(k) THEN RETURN; END IF;
        DBMS_OUTPUT.PUT_LINE('  |' || f_txt(lib,18) || f_int(g_cls(k).nb,8)
            || f_pct(CASE WHEN v_nb_tot > 0 THEN 100*g_cls(k).nb/v_nb_tot END, 8)
            || f_num(g_cls(k).fin,18) || f_num(g_cls(k).arr,18) || f_num(g_cls(k).arr_pri,18));
    END;

BEGIN
    v_nb_mois := MONTHS_BETWEEN(TRUNC(v_d_ref,'MM'), TRUNC(v_d_debut,'MM')) + 1;

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   ANALYSE DES REMBOURSEMENTS DE CREDITS (MODULE CL) — '
                         || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('   Composantes : PRINCIPAL / MAIN_INT / TVA_MAININT');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    kv('Perimetre (BOOK_DATE a partir du)',  TO_CHAR(v_d_debut,'DD/MM/YYYY'));
    kv('Date de reference (arrete)',         TO_CHAR(v_d_ref,'DD/MM/YYYY'));
    kv('Nombre de mois analyses',            TO_CHAR(v_nb_mois));
    kv('Prefixe GL jambe compte client',     v_gl_client);
    kv('Tolerance d''arrondi',               TO_CHAR(v_tol));

    -- =========================================================
    -- CHARGEMENT DE LA SITUATION DE CHAQUE CREDIT
    -- =========================================================
    v_i := 0;
    FOR r IN c_credits LOOP
        v_i := v_i + 1;
        g_cr(v_i) := r;

        v_fin_tot := v_fin_tot + r.montant;
        v_du_pri  := v_du_pri  + r.du_pri;   v_pa_pri := v_pa_pri + r.pa_pri;
        v_du_int  := v_du_int  + r.du_int;   v_pa_int := v_pa_int + r.pa_int;
        v_du_tva  := v_du_tva  + r.du_tva;   v_pa_tva := v_pa_tva + r.pa_tva;

        IF r.tot_prevu = 0        THEN v_nb_sans_s := v_nb_sans_s + 1; END IF;
        IF r.pa_tot    = 0        THEN v_nb_sans_e := v_nb_sans_e + 1; END IF;
        IF r.solde     = 'OUI'    THEN v_nb_solde  := v_nb_solde  + 1; END IF;

        CASE r.classe
            WHEN 'NON DEMARRE'   THEN v_nb_nd   := v_nb_nd   + 1;
            WHEN 'SAIN'          THEN v_nb_sain := v_nb_sain + 1;
            WHEN 'REGULARISE'    THEN v_nb_reg  := v_nb_reg  + 1;
            ELSE                      v_nb_dif  := v_nb_dif  + 1;
        END CASE;
        add_cls(g_cls, r.classe, r.montant, r.arriere_tot, r.arriere_pri);

        -- Ventilation par anciennete du retard, credits en difficulte uniquement
        IF r.classe = 'EN DIFFICULTE' THEN
            v_arr_tot  := v_arr_tot  + r.arriere_tot;
            v_arr_pri  := v_arr_pri  + GREATEST(r.arriere_pri,0);
            v_arr_it   := v_arr_it   + GREATEST(r.arriere_tot - r.arriere_pri,0);
            v_rest_pri := v_rest_pri + GREATEST(r.pri_restant,0);
            v_cle := CASE WHEN r.dpd_jours <=   0 THEN '0-non date'
                          WHEN r.dpd_jours <=  30 THEN '1-1 a 30 j'
                          WHEN r.dpd_jours <=  60 THEN '2-31 a 60 j'
                          WHEN r.dpd_jours <=  90 THEN '3-61 a 90 j'
                          WHEN r.dpd_jours <= 180 THEN '4-91 a 180 j'
                          WHEN r.dpd_jours <= 360 THEN '5-181 a 360 j'
                          ELSE                         '6-plus de 360 j'
                     END;
            add_cls(g_dpd, v_cle, r.montant, r.arriere_tot, r.arriere_pri);
            IF NOT g_dpd_rst.EXISTS(v_cle) THEN g_dpd_rst(v_cle) := 0; END IF;
            g_dpd_rst(v_cle) := g_dpd_rst(v_cle) + GREATEST(r.pri_restant,0);
        END IF;
    END LOOP;
    v_nb_tot := v_i;

    -- =========================================================
    -- 0. CONTROLES DE COUVERTURE (fiabilite des chiffres)
    -- =========================================================
    section('0. CONTROLES DE COUVERTURE');

    SELECT COUNT(*), NVL(SUM(CASE WHEN g.AC_GL_NO IS NOT NULL THEN 1 ELSE 0 END),0)
    INTO   v_ecr_tot, v_ecr_ret
    FROM   ACTB_HISTORY h
    LEFT JOIN (SELECT DISTINCT AC_GL_NO FROM STTB_ACCOUNT WHERE AC_NATURAL_GL LIKE v_gl_client) g
           ON g.AC_GL_NO = h.AC_NO
    WHERE  h.MODULE = 'CL'
    AND    h.AMOUNT_TAG IN ('PRINCIPAL_LIQD','MAIN_INT_LIQD','TVA_MAININT_LIQD')
    AND    h.TRN_DT >= v_d_debut AND h.TRN_DT <= v_d_ref;

    SELECT COUNT(*) INTO v_lig_master
    FROM   CLTB_ACCOUNT_APPS_MASTER
    WHERE  BOOK_DATE >= v_d_debut AND BOOK_DATE <= v_d_ref;

    kv('Ecritures CL (tags _LIQD) sur la periode', TO_CHAR(v_ecr_tot));
    kv('  dont retenues (jambe compte client)',
       TO_CHAR(v_ecr_ret) || '   ('
       || TO_CHAR(ROUND(CASE WHEN v_ecr_tot>0 THEN 100*v_ecr_ret/v_ecr_tot END,1),'FM990D0') || '%)');
    kv('  dont ecartees (autre contrepartie)', TO_CHAR(v_ecr_tot - v_ecr_ret));
    p('      -> les ecritures ecartees sont la contrepartie comptable (GL de');
    p('         creances). Si ce taux s''ecarte fortement de 50%, ajuster le');
    p('         parametre v_gl_client au plan comptable en vigueur.');
    kv('Lignes CLTB_ACCOUNT_APPS_MASTER',      TO_CHAR(v_lig_master));
    kv('  dont comptes distincts (perimetre)', TO_CHAR(v_nb_tot));
    kv('Credits sans echeancier',              TO_CHAR(v_nb_sans_s));
    kv('Credits sans aucun encaissement',      TO_CHAR(v_nb_sans_e));

    -- =========================================================
    -- 1. SYNTHESE DU PORTEFEUILLE
    -- =========================================================
    section('1. SYNTHESE DU PORTEFEUILLE BOOKE DEPUIS LE ' || TO_CHAR(v_d_debut,'DD/MM/YYYY'));

    kv('Nombre de credits',        TO_CHAR(v_nb_tot));
    kv('Montant finance cumule',   TO_CHAR(v_fin_tot,'FM999G999G999G990'));
    kv('Credits soldes (principal rembourse a 100%)', TO_CHAR(v_nb_solde));
    p('');
    p('  --- Exigible a la date de reference vs encaisse, par composante ---');
    tbl_line('16,20,20,20,14');
    p('  |' || RPAD(' COMPOSANTE',16) || '|' || RPAD(' EXIGIBLE A DATE',20) || '|'
            || RPAD(' ENCAISSE',20) || '|' || RPAD(' ECART',20) || '|' || RPAD(' TX RECOUVR.',14) || '|');
    tbl_line('16,20,20,20,14');
    p('  |' || f_txt('PRINCIPAL',16)   || f_num(v_du_pri,20) || f_num(v_pa_pri,20)
            || f_num(v_du_pri-v_pa_pri,20)
            || f_pct(CASE WHEN v_du_pri>0 THEN 100*v_pa_pri/v_du_pri END,14));
    p('  |' || f_txt('MAIN_INT',16)    || f_num(v_du_int,20) || f_num(v_pa_int,20)
            || f_num(v_du_int-v_pa_int,20)
            || f_pct(CASE WHEN v_du_int>0 THEN 100*v_pa_int/v_du_int END,14));
    p('  |' || f_txt('TVA_MAININT',16) || f_num(v_du_tva,20) || f_num(v_pa_tva,20)
            || f_num(v_du_tva-v_pa_tva,20)
            || f_pct(CASE WHEN v_du_tva>0 THEN 100*v_pa_tva/v_du_tva END,14));
    tbl_line('16,20,20,20,14');
    p('  |' || f_txt('TOTAL',16)
            || f_num(v_du_pri+v_du_int+v_du_tva,20)
            || f_num(v_pa_pri+v_pa_int+v_pa_tva,20)
            || f_num((v_du_pri+v_du_int+v_du_tva)-(v_pa_pri+v_pa_int+v_pa_tva),20)
            || f_pct(CASE WHEN v_du_pri+v_du_int+v_du_tva>0
                          THEN 100*(v_pa_pri+v_pa_int+v_pa_tva)/(v_du_pri+v_du_int+v_du_tva) END,14));
    tbl_line('16,20,20,20,14');

    -- =========================================================
    -- 2. CLASSIFICATION DES CREDITS
    -- =========================================================
    section('2. CLASSIFICATION DES CREDITS A LA DATE DE REFERENCE');
    p('  SAIN          : aucune echeance en souffrance depuis le booking');
    p('  REGULARISE    : a connu des mois d''arriere mais est a jour aujourd''hui');
    p('  EN DIFFICULTE : arriere constate a la date de reference');
    p('  NON DEMARRE   : aucune echeance encore exigible');
    p('');
    tbl_line('18,8,8,18,18,18');
    p('  |' || RPAD(' CLASSE',18) || '|' || RPAD(' NB',8) || '|' || RPAD(' %',8) || '|'
            || RPAD(' MONTANT FINANCE',18) || '|' || RPAD(' ARRIERE TOTAL',18) || '|'
            || RPAD(' DONT PRINCIPAL',18) || '|');
    tbl_line('18,8,8,18,18,18');
    pr_cls('SAIN',          'SAIN');
    pr_cls('REGULARISE',    'REGULARISE');
    pr_cls('EN DIFFICULTE', 'EN DIFFICULTE');
    pr_cls('NON DEMARRE',   'NON DEMARRE');
    tbl_line('18,8,8,18,18,18');

    IF v_nb_dif > 0 THEN
        p('');
        p('  --- Anciennete du retard des credits en difficulte (imputation FIFO) ---');
        tbl_line('18,8,20,22,22');
        p('  |' || RPAD(' TRANCHE RETARD',18) || '|' || RPAD(' NB',8) || '|'
                || RPAD(' ARRIERE TOTAL',20) || '|' || RPAD(' PRINCIPAL IMPAYE',22) || '|'
                || RPAD(' PRINCIPAL RESTANT DU',22) || '|');
        tbl_line('18,8,20,22,22');
        v_cle := g_dpd.FIRST;
        WHILE v_cle IS NOT NULL LOOP
            p('  |' || f_txt(SUBSTR(v_cle,3),18) || f_int(g_dpd(v_cle).nb,8)
                    || f_num(g_dpd(v_cle).arr,20) || f_num(g_dpd(v_cle).arr_pri,22)
                    || f_num(g_dpd_rst(v_cle),22));
            v_cle := g_dpd.NEXT(v_cle);
        END LOOP;
        tbl_line('18,8,20,22,22');
        p('  |' || f_txt('TOTAL',18) || f_int(v_nb_dif,8) || f_num(v_arr_tot,20)
                || f_num(v_arr_pri,22) || f_num(v_rest_pri,22));
        tbl_line('18,8,20,22,22');
        p('  Note : au sens COBAC, les tranches au-dela de 90 jours constituent');
        p('         des creances en souffrance a declasser et a provisionner.');
    END IF;

    -- =========================================================
    -- 3. CREDITS QUI SE REMBOURSENT BIEN
    -- =========================================================
    section('3. CREDITS QUI SE REMBOURSENT BIEN (classe SAIN) — ' || v_nb_sain || ' credit(s)');
    IF v_nb_sain = 0 THEN
        p('  Aucun credit sans aucun incident de paiement sur la periode.');
    ELSE
        p('  Aucun mois d''arriere depuis le booking. Tries par montant finance.');
        p('');
        tbl_line('4,20,24,12,12,16,16,9,7,12');
        p('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' CLIENT',24) || '|'
                || RPAD(' BOOKING',12) || '|' || RPAD(' ECHEANCE',12) || '|' || RPAD(' FINANCE',16) || '|'
                || RPAD(' ENCAISSE',16) || '|' || RPAD(' % REMB',9) || '|' || RPAD(' SOLDE',7) || '|'
                || RPAD(' DER. PMT',12) || '|');
        tbl_line('4,20,24,12,12,16,16,9,7,12');
        v_row := 0;
        FOR i IN 1 .. v_nb_tot LOOP
            EXIT WHEN v_row >= c_max_lig;
            IF g_cr(i).classe = 'SAIN' THEN
                v_row := v_row + 1;
                p('  |' || LPAD(v_row,3) || ' |' || f_txt(g_cr(i).acc,20)
                        || f_txt(g_cr(i).nom,24) || f_dat(g_cr(i).dt_book,12)
                        || f_dat(g_cr(i).dt_mat,12) || f_num(g_cr(i).montant,16)
                        || f_num(g_cr(i).pa_tot,16) || f_pct(g_cr(i).tx_rec,9)
                        || f_txt(g_cr(i).solde,7) || f_dat(g_cr(i).dernier_pmt,12));
            END IF;
        END LOOP;
        tbl_line('4,20,24,12,12,16,16,9,7,12');
        IF v_nb_sain > c_max_lig THEN
            p('  ... ' || (v_nb_sain - c_max_lig) || ' autre(s) credit(s) sain(s) non affiche(s).');
        END IF;
    END IF;

    -- =========================================================
    -- 4. MOIS EN IRREGULARITE, CREDIT PAR CREDIT
    -- =========================================================
    section('4. CREDITS AYANT CONNU DES RETARDS — MOIS EN IRREGULARITE');
    p('  Un mois est retenu lorsque, a sa cloture, le cumul des echeances');
    p('  exigibles depasse le cumul des encaissements. Les credits sont tries');
    p('  par gravite (pic d''arriere le plus eleve).');
    p('');
    tbl_line('4,20,24,9,16,16,16,16');
    p('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' CLIENT',24) || '|'
            || RPAD(' MOIS',9) || '|' || RPAD(' CUMUL DU',16) || '|' || RPAD(' CUMUL ENCAISSE',16) || '|'
            || RPAD(' ARRIERE',16) || '|' || RPAD(' DONT PRINCIPAL',16) || '|');
    tbl_line('4,20,24,9,16,16,16,16');

    v_prev_acc  := NULL;
    v_nb_cred_d := 0;
    v_row       := 0;
    FOR m IN c_mois LOOP
        -- Alimentation de la concentration mensuelle du portefeuille
        v_cle := TO_CHAR(m.mm,'YYYYMM');
        IF g_mois.EXISTS(v_cle) THEN
            v_rm := g_mois(v_cle);
        ELSE
            v_rm.lib := TO_CHAR(m.mm,'MM/YYYY');
            v_rm.nb  := 0; v_rm.arr := 0; v_rm.arr_pri := 0;
        END IF;
        v_rm.nb      := v_rm.nb + 1;
        v_rm.arr     := v_rm.arr + m.arriere;
        v_rm.arr_pri := v_rm.arr_pri + GREATEST(m.arriere_pri,0);
        g_mois(v_cle) := v_rm;
        v_row := v_row + 1;

        -- Rupture sur le credit
        v_n := CASE WHEN NVL(v_prev_acc,'~') = m.acc THEN 0 ELSE 1 END;
        IF v_n = 1 THEN
            v_nb_cred_d := v_nb_cred_d + 1;
            v_prev_acc  := m.acc;
            IF v_nb_cred_d > 1 AND v_nb_cred_d <= c_max_cred THEN
                tbl_line('4,20,24,9,16,16,16,16');
            END IF;
        END IF;

        IF v_nb_cred_d <= c_max_cred THEN
            DBMS_OUTPUT.PUT_LINE('  |'
                || CASE WHEN v_n = 1 THEN LPAD(v_nb_cred_d,3) || ' |' ELSE RPAD(' ',4) || '|' END
                || f_txt(CASE WHEN v_n = 1 THEN m.acc ELSE ' ' END, 20)
                || f_txt(CASE WHEN v_n = 1 THEN m.nom ELSE ' ' END, 24)
                || f_txt(TO_CHAR(m.mm,'MM/YYYY'), 9)
                || f_num(m.cum_du,16) || f_num(m.cum_pa,16)
                || f_num(m.arriere,16) || f_num(m.arriere_pri,16));
        END IF;
    END LOOP;
    tbl_line('4,20,24,9,16,16,16,16');

    IF v_nb_cred_d = 0 THEN
        p('  Aucun credit n''a connu de mois en irregularite sur la periode.');
    ELSE
        kv('Credits ayant connu au moins un mois de retard', TO_CHAR(v_nb_cred_d));
        kv('Nombre total de mois-credit en irregularite',    TO_CHAR(v_row));
        IF v_nb_cred_d > c_max_cred THEN
            p('  ... ' || (v_nb_cred_d - c_max_cred) || ' autre(s) credit(s) non detaille(s) '
              || '(augmenter c_max_cred pour les afficher).');
        END IF;
    END IF;

    -- =========================================================
    -- 5. CONCENTRATION MENSUELLE DES IRREGULARITES (PORTEFEUILLE)
    -- =========================================================
    section('5. MOIS OU LE PORTEFEUILLE A CONNU DES IRREGULARITES');
    IF g_mois.COUNT = 0 THEN
        p('  Aucune irregularite mensuelle detectee sur la periode.');
    ELSE
        p('  Photographie a la cloture de chaque mois : nombre de credits en');
        p('  souffrance et montant de l''arriere cumule correspondant.');
        p('');
        tbl_line('9,24,26,20');
        p('  |' || RPAD(' MOIS',9) || '|' || RPAD(' NB CREDITS EN ARRIERE',24) || '|'
                || RPAD(' ARRIERE TOTAL FIN DE MOIS',26) || '|' || RPAD(' DONT PRINCIPAL',20) || '|');
        tbl_line('9,24,26,20');
        v_max_arr  := -1;
        v_max_mois := NULL;
        v_cle := g_mois.FIRST;
        WHILE v_cle IS NOT NULL LOOP
            p('  |' || f_txt(g_mois(v_cle).lib,9) || f_int(g_mois(v_cle).nb,24)
                    || f_num(g_mois(v_cle).arr,26) || f_num(g_mois(v_cle).arr_pri,20));
            IF g_mois(v_cle).arr > v_max_arr THEN
                v_max_arr  := g_mois(v_cle).arr;
                v_max_mois := g_mois(v_cle).lib;
            END IF;
            v_cle := g_mois.NEXT(v_cle);
        END LOOP;
        tbl_line('9,24,26,20');
        kv('Mois de plus fort arriere', v_max_mois || '  ('
           || TO_CHAR(v_max_arr,'FM999G999G999G990') || ')');
    END IF;

    -- =========================================================
    -- 6. RESTE A RECOUVRER SUR LES CREDITS ENCORE EN DIFFICULTE
    -- =========================================================
    section('6. RESTE A RECOUVRER — CREDITS ENCORE EN DIFFICULTE A CE JOUR');
    IF v_nb_dif = 0 THEN
        p('  Aucun credit en difficulte a la date de reference.');
    ELSE
        p('  PRINCIPAL IMPAYE   : principal echu non encaisse (exigible immediatement).');
        p('  PRINCIPAL RESTANT  : principal total non encaisse, echeances futures incluses');
        p('                       (exposition residuelle sur le credit).');
        p('');
        tbl_line('4,20,24,10,19,19,19,12');
        p('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' CLIENT',24) || '|'
                || RPAD(' RETARD (J)',10) || '|' || RPAD(' PRINCIPAL IMPAYE',19) || '|'
                || RPAD(' PRINCIPAL RESTANT',19) || '|' || RPAD(' INT + TVA IMPAYES',19) || '|'
                || RPAD(' DER. PMT',12) || '|');
        tbl_line('4,20,24,10,19,19,19,12');
        v_row := 0;
        FOR i IN 1 .. v_nb_tot LOOP
            EXIT WHEN v_row >= c_max_lig;
            IF g_cr(i).classe = 'EN DIFFICULTE' THEN
                v_row := v_row + 1;
                p('  |' || LPAD(v_row,3) || ' |' || f_txt(g_cr(i).acc,20)
                        || f_txt(g_cr(i).nom,24) || f_int(g_cr(i).dpd_jours,10)
                        || f_num(GREATEST(g_cr(i).arriere_pri,0),19)
                        || f_num(GREATEST(g_cr(i).pri_restant,0),19)
                        || f_num(GREATEST(g_cr(i).arriere_tot - g_cr(i).arriere_pri,0),19)
                        || f_dat(g_cr(i).dernier_pmt,12));
            END IF;
        END LOOP;
        tbl_line('4,20,24,10,19,19,19,12');
        p('  |' || f_txt('TOTAL (' || v_nb_dif || ' credits en difficulte)', 61)
                || f_num(v_arr_pri,19) || f_num(v_rest_pri,19)
                || f_num(v_arr_it,19) || RPAD(' ',12) || '|');
        tbl_line('4,20,24,10,19,19,19,12');
        IF v_nb_dif > c_max_lig THEN
            p('  ... ' || (v_nb_dif - c_max_lig) || ' autre(s) credit(s) en difficulte non affiche(s) ;');
            p('      les totaux ci-dessus portent bien sur la totalite des ' || v_nb_dif || ' credits.');
        END IF;
    END IF;

    -- =========================================================
    -- 7. SYNTHESE
    -- =========================================================
    section('7. SYNTHESE');
    kv('Credits bookes depuis le ' || TO_CHAR(v_d_debut,'DD/MM/YYYY'), TO_CHAR(v_nb_tot));
    kv('  se remboursant sans incident (SAIN)',
       TO_CHAR(v_nb_sain) || '   ('
       || TO_CHAR(ROUND(CASE WHEN v_nb_tot>0 THEN 100*v_nb_sain/v_nb_tot END,1),'FM990D0') || '%)');
    kv('  ayant eu des retards mais regularises',      TO_CHAR(v_nb_reg));
    kv('  encore en difficulte a ce jour',
       TO_CHAR(v_nb_dif) || '   ('
       || TO_CHAR(ROUND(CASE WHEN v_nb_tot>0 THEN 100*v_nb_dif/v_nb_tot END,1),'FM990D0') || '%)');
    kv('  sans echeance encore exigible',              TO_CHAR(v_nb_nd));
    p('');
    kv('Exigible a date (P+I+TVA)',   TO_CHAR(v_du_pri+v_du_int+v_du_tva,'FM999G999G999G990'));
    kv('Encaisse a date (P+I+TVA)',   TO_CHAR(v_pa_pri+v_pa_int+v_pa_tva,'FM999G999G999G990'));
    kv('Taux de recouvrement global',
       TO_CHAR(ROUND(CASE WHEN v_du_pri+v_du_int+v_du_tva > 0
                          THEN 100*(v_pa_pri+v_pa_int+v_pa_tva)/(v_du_pri+v_du_int+v_du_tva) END,2),
               'FM990D00') || '%');
    p('');
    p('  RESTE A RECOUVRER SUR LES CREDITS EN DIFFICULTE');
    kv('  Principal echu impaye (exigible)',   TO_CHAR(v_arr_pri,'FM999G999G999G990'));
    kv('  Interets + TVA echus impayes',       TO_CHAR(v_arr_it,'FM999G999G999G990'));
    kv('  Principal total restant du',         TO_CHAR(v_rest_pri,'FM999G999G999G990'));
    kv('  Taux de principal impaye / finance',
       TO_CHAR(ROUND(CASE WHEN v_fin_tot > 0 THEN 100*v_arr_pri/v_fin_tot END,2),'FM990D00') || '%');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE,'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
