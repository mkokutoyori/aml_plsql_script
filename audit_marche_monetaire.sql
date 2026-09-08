-- ============================================================================
-- SCRIPT D'AUDIT - REVUE DES OPERATIONS DE MARCHE MONETAIRE (MODULE MM)
-- Base : FLEXCUBE (FCUBS)
-- ============================================================================
-- OBJET
--   Revue d'audit des operations de marche monetaire (titres souverains,
--   placements et emprunts interbancaires) enregistrees dans le module MM de
--   FLEXCUBE, table LDTB_CONTRACT_MASTER et ses tables satellites.
--
--   Le script fait deux choses :
--     1. il DECRIT la structure du portefeuille (produits, Etats emetteurs,
--        montants, taux, durees, repartition mensuelle, echeancier) ;
--     2. il TESTE les controles d'audit : calcul des interets, provisions,
--        remboursements, retards, comptabilisation, piste d'audit.
--
--   Il s'appuie sur les constats du script d'exploration explore_mm_operations.sql
--   (rapport money_marker_exploration_report.txt) : seules les colonnes reellement
--   alimentees sont exploitees, les colonnes vides ne sont pas testees a l'aveugle.
--
-- LECTURE SEULE
--   Le script ne contient que des SELECT. Aucun INSERT, UPDATE, DELETE, aucun
--   ordre DDL, aucun COMMIT : il s'execute avec un simple droit de lecture.
--
-- UN SEUL BLOC, UNE SEULE EXECUTION
--   Tout tient dans un unique bloc PL/SQL anonyme termine par un seul '/'.
--   Chaque section est encapsulee dans son propre gestionnaire d'erreur : si une
--   section echoue (objet absent, droit manquant), elle affiche le message et le
--   script poursuit avec la section suivante.
--
-- AUCUNE SAISIE DEMANDEE
--   Aucune variable de substitution, aucune variable de liaison, aucun caractere
--   esperluette, aucun deux-points colle a une lettre : aucune fenetre de saisie
--   ne doit s'ouvrir au lancement sous SQL Developer.
--
-- UTILISATION SOUS SQL DEVELOPER
--   1. Ouvrir le fichier (Fichier > Ouvrir).
--   2. Se connecter au schema FLEXCUBE.
--   3. Lancer avec  F5  (Executer un script) et NON avec Ctrl+Entree.
--   4. Le rapport s'affiche dans l'onglet "Sortie de script".
--      Pour l'enregistrer dans un fichier, decommenter les lignes SPOOL.
--
-- UTILISATION SOUS SQLPLUS
--   sqlplus utilisateur/motdepasse@base
--   SQL> spool audit_mm_report.txt
--   SQL> @audit_marche_monetaire.sql
--   SQL> spool off
--
-- PARAMETRAGE
--   Tous les seuils sont regroupes dans le bloc "PARAMETRES DE LA MISSION" en
--   tete de la section DECLARE. Ce sont les seules valeurs a ajuster pour
--   adapter la revue a une periode ou a un seuil de signification differents.
--
-- PLAN DU RAPPORT
--   PARTIE 0 - section  0       : cadrage, parametres, perimetre, legendes,
--                                 couverture des candidats et controles ecartes
--   PARTIE 1 - sections 1 a 8   : STRUCTURE DU PORTEFEUILLE
--   PARTIE 2 - sections 9 a 10  : controles MM-1xx referentiel / MM-2xx dates
--   PARTIE 3 - section 11       : controles MM-3xx CALCUL DES INTERETS
--   PARTIE 4 - sections 12 a 13 : controles MM-4xx REMBOURSEMENTS / MM-5xx RETARDS
--   PARTIE 5 - sections 14, 14B : controles MM-6xx rapprochement comptable
--                                 et MM-62x SCHEMAS COMPTABLES ET CYCLE DE VIE
--   PARTIE 6 - section 15       : controles MM-7xx GOUVERNANCE ET PISTE D'AUDIT
--   PARTIE 7 - sections 17 a 26 : REFERENTIEL DE CONTROLE COMPTABLE
--                                 EXT integrite de l'extraction, DBL partie double,
--                                 MAP mapping des comptes, INT exactitude des interets,
--                                 LIF cycle de vie, REV extournes, CSH tresorerie,
--                                 CUT arrete de periode, CLS classification,
--                                 STA donnees statiques
--   PARTIE 8 - section 27       : SYNTHESE DE TOUS LES TESTS
--
-- CONVENTION DE PERIMETRE
--   LDTB_CONTRACT_MASTER contient une ligne par version de contrat. Le script
--   ne retient partout que la DERNIERE VERSION de chaque contrat :
--       m.module = 'MM'
--       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
--                            WHERE v.contract_ref_no = m.contract_ref_no)
--
-- DUREE
--   Les sections 14 et 15 lisent ACTB_HISTORY (plusieurs millions de lignes) :
--   prevoir quelques minutes d'execution.
-- ============================================================================

SET DEFINE OFF
SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SET LINESIZE 500
SET PAGESIZE 0
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED

-- SPOOL C:\temp\audit_mm_report.txt

DECLARE

    -- ========================================================================
    -- PARAMETRES DE LA MISSION  (seules valeurs a ajuster)
    -- ========================================================================
    -- Date d'arrete des controles. Mettre une date fixe pour une revue
    -- retrospective, par exemple TO_DATE('30/06/2025', 'DD/MM/YYYY').
    k_arrete      DATE   := SYSDATE;

    -- Bornes de la periode auditee (appliquees sur BOOKING_DATE).
    k_dt_deb      DATE   := TO_DATE('01/01/2000', 'DD/MM/YYYY');
    k_dt_fin      DATE   := TO_DATE('31/12/2099', 'DD/MM/YYYY');

    -- Tolerances sur le recalcul des interets
    k_tol_abs     NUMBER := 5;        -- ecart absolu tolere, en XAF
    k_tol_pct     NUMBER := 0.01;     -- ecart relatif tolere, en pourcentage

    -- Seuils metier
    k_mt_signif   NUMBER := 1000000000;  -- seuil de signification, en XAF (1 Md)
    k_taux_max    NUMBER := 15;          -- taux plafond juge normal, en pourcentage
    k_taux_min    NUMBER := 0.5;         -- taux plancher juge normal, en pourcentage
    k_retro_j     NUMBER := 5;           -- retroactivite de saisie toleree, en jours calendaires
    k_ecart_taux  NUMBER := 2;           -- ecart de taux tolere vs moyenne produit, en points
    k_ret_liq     NUMBER := 5;           -- retard de liquidation tolere, en jours
    k_ret_accr    NUMBER := 35;          -- anciennete maximale de la derniere provision, en jours
    k_ech_ancien  NUMBER := 90;          -- anciennete a partir de laquelle un contrat echu est signale
    k_base_jours  NUMBER := 360;         -- base de jours retenue pour les estimations d'interets

    -- Nombre de lignes de detail affichees par test
    k_top         NUMBER := 30;

    -- ---------- Plan comptable du module (section 14 BIS) ----------
    -- Prefixes des comptes generaux naturels (STTB_ACCOUNT.AC_NATURAL_GL)
    -- mouvementes par les operations de marche monetaire. Valeurs issues de
    -- l'analyse des schemas comptables sur echantillon de contrats ; a ajuster
    -- si le plan comptable de la banque differe.
    k_gl_crat_pl  VARCHAR2(8) := '5118';  -- creances rattachees - placement
    k_gl_crat_tr  VARCHAR2(8) := '5128';  -- creances rattachees - transaction
    k_gl_tit_pl   VARCHAR2(8) := '511';   -- titres de placement
    k_gl_tit_tr   VARCHAR2(8) := '512';   -- titres de transaction
    k_gl_pca      VARCHAR2(8) := '472';   -- produits constates ou percus d'avance
    k_gl_prod     VARCHAR2(8) := '733';   -- revenus des titres (resultat)
    k_gl_treso    VARCHAR2(8) := '56';    -- tresorerie, compte de reglement BEAC

    -- ---------- Plan comptable detaille (parties 7 : EXT a STA) ----------
    -- Numeros de compte EXACTS (ACTB_HISTORY.AC_NO) autorises pour le module.
    -- Ce sont les comptes attendus par le referentiel de controle de la
    -- direction financiere ; tout compte hors de cette liste est a challenger.
    k_ac_tit_otap VARCHAR2(20) := '511410100';   -- OTAP : obligations du tresor - placement
    k_ac_tit_mtpd VARCHAR2(20) := '511200100';   -- MTPD : bons du tresor - placement
    k_ac_tit_tr   VARCHAR2(20) := '512200100';   -- TBTR et BTTR : bons du tresor - transaction
    k_ac_crat_pl  VARCHAR2(20) := '511800100';   -- creances rattachees - placement
    k_ac_crat_tr  VARCHAR2(20) := '512800100';   -- creances rattachees - transaction
    k_ac_pca      VARCHAR2(20) := '472200100';   -- produits percus d'avance
    k_ac_prod_ob  VARCHAR2(20) := '733400100';   -- revenus d'obligations
    k_ac_prod_bt  VARCHAR2(20) := '733200100';   -- revenus de bons du tresor
    k_ac_nostro   VARCHAR2(20) := '099ACO00001'; -- nostro BEAC, jambe de reglement

    -- Produits de marche monetaire couverts par les controles de la partie 7.
    -- Teste par INSTR(',' || k_prod_mm || ',', ',' || m.product || ',') > 0
    k_prod_mm     VARCHAR2(60) := 'OTAP,BTTR,TBTR,MTPD';
    -- Produits a interets POST-comptes (creances rattachees) et PRE-comptes (PCA)
    k_prod_post   VARCHAR2(60) := 'OTAP,BTTR';
    k_prod_pre    VARCHAR2(60) := 'TBTR,MTPD';
    -- Produits obligataires (revenus 733400100) et bons du tresor (733200100)
    k_prod_oblig  VARCHAR2(60) := 'OTAP';

    -- Seuils propres a la partie 7
    k_tol_jour    NUMBER := 3;           -- trou tolere dans la serie des provisions, en jours
    k_conc_lim    NUMBER := 500000000000;-- limite de concentration par emetteur (comite ALM), en XAF
    k_taux_dec    NUMBER := 1;           -- sous ce taux, on soupconne une saisie en decimal (0.0625)

    -- Module et application externe
    k_mod         VARCHAR2(4)  := 'MM';
    k_pat         VARCHAR2(30) := '%CALYPSO%';

    -- ========================================================================
    -- Variables de travail
    -- ========================================================================
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_sub     VARCHAR2(200) := RPAD('-', 116, '-');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_tot2    NUMBER;
    v_mt      NUMBER;
    v_mt2     NUMBER;
    v_row     NUMBER;
    v_nb_ctr  NUMBER := 0;    -- nombre de contrats du perimetre (denominateur de reference)
    v_mt_ctr  NUMBER := 0;    -- encours nominal cumule du perimetre
    v_d_max   DATE;           -- derniere ecriture comptable du module MM
    v_d_glob  DATE;           -- derniere ecriture comptable tous modules
    v_d_accr  DATE;           -- derniere provision d'interets du module MM
    v_lib     VARCHAR2(200);  -- libelle de compte, partie 7

    -- ========================================================================
    -- Registre des tests, alimente par p_verdict et restitue en section 16
    -- ========================================================================
    TYPE t_res IS RECORD (
        code VARCHAR2(12),
        lib  VARCHAR2(100),
        nb   NUMBER,
        base NUMBER,
        mt   NUMBER,
        crit VARCHAR2(12)
    );
    TYPE t_tab IS TABLE OF t_res INDEX BY PLS_INTEGER;
    g_res     t_tab;
    g_n       PLS_INTEGER := 0;
    g_anom    PLS_INTEGER := 0;
    g_crit    PLS_INTEGER := 0;

    -- ========================================================================
    -- Helpers d'affichage
    -- ========================================================================
    PROCEDURE po(t VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(t);
    END;

    PROCEDURE print_part(t VARCHAR2) IS
    BEGIN
        po('');
        po(v_sep);
        po('   ' || t);
        po(v_sep);
    END;

    PROCEDURE print_section(t VARCHAR2) IS
    BEGIN
        po('');
        po(v_sep);
        po('>>> ' || t);
        po(v_sep);
    END;

    PROCEDURE print_sub(t VARCHAR2) IS
    BEGIN
        po('');
        po('  [' || t || ']');
    END;

    PROCEDURE print_kv(l VARCHAR2, v VARCHAR2) IS
    BEGIN
        po('  ' || RPAD(SUBSTR(l, 1, 66), 68, '.') || ' ' || NVL(v, 'NON RENSEIGNE'));
    END;

    -- Cellule alignee a gauche / a droite
    FUNCTION fpad(x VARCHAR2, n NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN RPAD(' ' || NVL(SUBSTR(x, 1, n - 2), '-'), n);
    END;

    FUNCTION fpadl(x VARCHAR2, n NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN LPAD(NVL(SUBSTR(x, 1, n - 1), '-') || ' ', n);
    END;

    FUNCTION fnum(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G999G990D00');
    END;

    -- Montant exprime en millions de XAF
    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G999G990D00') || ' M';
    END;

    FUNCTION ftx(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF x IS NULL THEN RETURN '-'; END IF;
        RETURN TO_CHAR(x, 'FM990D0000') || ' %';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
    END;

    -- Horodatage SANS deux-points : sous SQL Developer un deux-points suivi
    -- d'une lettre serait pris pour une variable de liaison.
    FUNCTION fdth(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY HH24"h"MI');
    END;

    FUNCTION fpct(p_part NUMBER, p_tot NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF NVL(p_tot, 0) = 0 THEN
            RETURN '-';
        END IF;
        RETURN TO_CHAR(ROUND(100 * p_part / p_tot, 1), 'FM990D0') || ' %';
    END;

    -- Ligne de separation d'un tableau : tbl_line('4,20,12')
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
        po(v_line);
    END;

    -- ========================================================================
    -- Helpers d'audit
    -- ========================================================================

    -- En-tete d'un test
    PROCEDURE p_test(p_code VARCHAR2, p_desc VARCHAR2) IS
    BEGIN
        po('');
        po('  ' || v_sub);
        po('  TEST ' || RPAD(p_code, 9) || ' ' || p_desc);
        po('  ' || v_sub);
    END;

    -- Objectif / methode du test (une ligne d'explication)
    PROCEDURE p_obj(t VARCHAR2) IS
    BEGIN
        po('  Objectif . ' || t);
    END;

    -- Resultat d'un test : affiche le verdict et l'enregistre pour la synthese.
    -- p_crit : CRITIQUE / ELEVE / MOYEN / FAIBLE / INFO
    PROCEDURE p_verdict(p_code VARCHAR2,
                        p_lib  VARCHAR2,
                        p_nb   NUMBER,
                        p_base NUMBER   DEFAULT NULL,
                        p_mt   NUMBER   DEFAULT NULL,
                        p_crit VARCHAR2 DEFAULT 'MOYEN') IS
        v_r t_res;
        v_l VARCHAR2(400);
    BEGIN
        v_r.code := p_code;
        v_r.lib  := SUBSTR(p_lib, 1, 100);
        v_r.nb   := NVL(p_nb, 0);
        v_r.base := p_base;
        v_r.mt   := p_mt;
        v_r.crit := p_crit;
        g_n := g_n + 1;
        g_res(g_n) := v_r;

        v_l := '  >> RESULTAT . ' || fnum(p_nb) || ' cas';
        IF NVL(p_base, 0) > 0 THEN
            v_l := v_l || ' sur ' || fnum(p_base) || ' (' || fpct(p_nb, p_base) || ')';
        END IF;
        IF p_mt IS NOT NULL THEN
            v_l := v_l || ' - montant concerne ' || fmio(p_mt);
        END IF;

        IF NVL(p_nb, 0) = 0 THEN
            v_l := v_l || '   [ OK ]';
        ELSIF p_crit = 'INFO' THEN
            v_l := v_l || '   [ POUR INFORMATION ]';
        ELSE
            v_l := v_l || '   [ ANOMALIE - ' || p_crit || ' ]';
            g_anom := g_anom + 1;
            IF p_crit IN ('CRITIQUE', 'ELEVE') THEN
                g_crit := g_crit + 1;
            END IF;
        END IF;
        po(v_l);
    END;

    -- Message affiche lorsqu'un test ne remonte aucun cas
    PROCEDURE p_ras IS
    BEGIN
        po('     (aucun cas a detailler)');
    END;

    -- ------------------------------------------------------------------------
    -- Tableau de detail standard des tests portant sur un contrat.
    -- La derniere colonne INDICATEUR recoit la valeur specifique au test
    -- (ecart, nombre de jours, montant recalcule, etc.).
    -- ------------------------------------------------------------------------
    PROCEDURE d_head(p_ind VARCHAR2 DEFAULT 'INDICATEUR') IS
    BEGIN
        tbl_line('4,20,7,12,26,18,9,12,12,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('PROD', 7) || '|'
            || fpad('CIF', 12) || '|' || fpad('ETAT EMETTEUR', 26) || '|' || fpadl('MONTANT LCY', 18) || '|'
            || fpadl('TAUX', 9) || '|' || fpad('BOOKING', 12) || '|' || fpad('VALEUR', 12) || '|'
            || fpad('ECHEANCE', 12) || '|' || fpadl(p_ind, 20) || '|');
        tbl_line('4,20,7,12,26,18,9,12,12,12,20');
    END;

    PROCEDURE d_row(p_n    NUMBER,
                    p_ref  VARCHAR2,
                    p_prod VARCHAR2,
                    p_cif  VARCHAR2,
                    p_nom  VARCHAR2,
                    p_mt   NUMBER,
                    p_tx   NUMBER,
                    p_bd   DATE,
                    p_vd   DATE,
                    p_md   DATE,
                    p_ind  VARCHAR2) IS
    BEGIN
        po('  |' || fpadl(TO_CHAR(p_n), 4) || '|' || fpad(p_ref, 20) || '|' || fpad(p_prod, 7) || '|'
            || fpad(p_cif, 12) || '|' || fpad(p_nom, 26) || '|' || fpadl(famt(p_mt), 18) || '|'
            || fpadl(ftx(p_tx), 9) || '|' || fpad(fdt(p_bd), 12) || '|' || fpad(fdt(p_vd), 12) || '|'
            || fpad(fdt(p_md), 12) || '|' || fpadl(p_ind, 20) || '|');
    END;

    PROCEDURE d_foot IS
    BEGIN
        tbl_line('4,20,7,12,26,18,9,12,12,12,20');
    END;

    FUNCTION f_meth_lib(p_meth VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE p_meth
                 WHEN '1' THEN '30(Euro)/360'
                 WHEN '2' THEN '30(US)/360'
                 WHEN '3' THEN 'Actual/360'
                 WHEN '4' THEN '30(Euro)/365'
                 WHEN '5' THEN '30(US)/365'
                 WHEN '6' THEN 'Actual/365'
                 WHEN '7' THEN '30(Euro)/Actual'
                 WHEN '8' THEN '30(US)/Actual'
                 WHEN '9' THEN 'Actual/Actual'
                 ELSE 'methode ' || NVL(p_meth, 'NULL')
               END;
    END;

    -- Comptage tolerant aux objets absents
    FUNCTION f_count(p_tab VARCHAR2, p_where VARCHAR2 DEFAULT NULL) RETURN NUMBER IS
        v NUMBER;
        s VARCHAR2(4000);
    BEGIN
        s := 'SELECT COUNT(*) FROM ' || p_tab;
        IF p_where IS NOT NULL THEN
            s := s || ' WHERE ' || p_where;
        END IF;
        EXECUTE IMMEDIATE s INTO v;
        RETURN v;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN -1;
    END;

    FUNCTION f_lbl_cnt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN x < 0 THEN 'OBJET ABSENT OU INACCESSIBLE' ELSE fnum(x) || ' lignes' END;
    END;

BEGIN

    po(v_sep);
    po('');
    po('        R E V U E   D E S   O P E R A T I O N S   D E   M A R C H E   M O N E T A I R E');
    po('        FLEXCUBE Universal Banking  -  module ' || k_mod);
    po('        Rapport genere le ' || fdth(SYSDATE));
    po('');
    po(v_sep);

    -- ########################################################################
    print_part('PARTIE 0 : CADRAGE DE LA REVUE');
    -- ########################################################################

    -- =========================================================
    -- 0. CONTEXTE, PARAMETRES ET PERIMETRE
    -- =========================================================
    print_section('0. CONTEXTE, PARAMETRES ET PERIMETRE DE LA REVUE');
    BEGIN

        print_sub('0.1 Contexte d''execution');
        print_kv('Date / heure du rapport',        fdth(SYSDATE));
        print_kv('Date d''arrete des controles',   fdt(k_arrete));
        print_kv('Utilisateur connecte',           SYS_CONTEXT('USERENV', 'SESSION_USER'));
        print_kv('Schema courant',                 SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        print_kv('Base de donnees',                SYS_CONTEXT('USERENV', 'DB_NAME'));
        print_kv('Instance',                       SYS_CONTEXT('USERENV', 'INSTANCE_NAME'));

        print_sub('0.2 Parametres retenus pour la mission');
        print_kv('Periode auditee (BOOKING_DATE)', fdt(k_dt_deb) || ' au ' || fdt(k_dt_fin));
        print_kv('Tolerance absolue sur les interets recalcules', famt(k_tol_abs) || ' XAF');
        print_kv('Tolerance relative sur les interets recalcules', TO_CHAR(k_tol_pct) || ' %');
        print_kv('Seuil de signification',         famt(k_mt_signif) || ' XAF (' || fmio(k_mt_signif) || ')');
        print_kv('Bornes de taux jugees normales', ftx(k_taux_min) || ' a ' || ftx(k_taux_max));
        print_kv('Ecart de taux tolere vs moyenne produit', TO_CHAR(k_ecart_taux) || ' points');
        print_kv('Retroactivite de saisie toleree', TO_CHAR(k_retro_j) || ' jours');
        print_kv('Retard de liquidation tolere',   TO_CHAR(k_ret_liq) || ' jours');
        print_kv('Anciennete maximale de la derniere provision', TO_CHAR(k_ret_accr) || ' jours');
        print_kv('Anciennete signalee pour un contrat echu', TO_CHAR(k_ech_ancien) || ' jours');
        print_kv('Base de jours des estimations d''interets', TO_CHAR(k_base_jours));
        print_kv('Nombre de lignes de detail par test', TO_CHAR(k_top));

        print_sub('0.3 Perimetre d''audit');
        po('  Le module MM partage la table LDTB_CONTRACT_MASTER avec le module LD.');
        po('  Une ligne de cette table est une VERSION de contrat : le script ne retient');
        po('  partout que la derniere version de chaque reference de contrat.');
        po('');

        SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master WHERE module = k_mod;
        print_kv('Lignes LDTB_CONTRACT_MASTER pour le module ' || k_mod, fnum(v_cnt));

        SELECT COUNT(DISTINCT contract_ref_no) INTO v_cnt2
          FROM ldtb_contract_master WHERE module = k_mod;
        print_kv('References de contrat distinctes', fnum(v_cnt2));
        print_kv('Contrats amendes (plusieurs versions)', fnum(v_cnt - v_cnt2));

        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0)
          INTO v_nb_ctr, v_mt_ctr
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);

        SELECT MIN(m.booking_date), MAX(m.booking_date) INTO v_d_max, v_d_accr
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);

        print_kv('>>> CONTRATS RETENUS DANS LE PERIMETRE', fnum(v_nb_ctr));
        print_kv('>>> ENCOURS NOMINAL CUMULE', famt(v_mt_ctr) || '  (' || fmio(v_mt_ctr) || ')');
        print_kv('Premiere date de booking',       fdt(v_d_max));
        print_kv('Derniere date de booking',       fdt(v_d_accr));

        print_sub('0.4 Dates cles du module ' || k_mod);
        SELECT MAX(trn_dt) INTO v_d_max   FROM actb_history WHERE module = k_mod;
        SELECT MAX(trn_dt) INTO v_d_glob  FROM actb_history;
        SELECT MAX(accrual_to_date) INTO v_d_accr FROM ldtb_contract_accrual_history WHERE module = k_mod;

        print_kv('Derniere ecriture comptable du module ' || k_mod, fdt(v_d_max));
        print_kv('Derniere ecriture comptable tous modules',        fdt(v_d_glob));
        print_kv('Derniere provision d''interets du module ' || k_mod, fdt(v_d_accr));
        IF v_d_max IS NOT NULL AND v_d_glob IS NOT NULL THEN
            print_kv('Decalage entre les deux dernieres ecritures',
                     fnum(TRUNC(v_d_glob) - TRUNC(v_d_max)) || ' jours');
            IF TRUNC(v_d_glob) - TRUNC(v_d_max) > 60 THEN
                po('');
                po('  !! POINT D''ATTENTION MAJEUR : le module ' || k_mod || ' n''enregistre plus aucune');
                po('     ecriture depuis le ' || fdt(v_d_max) || ' alors que la base continue d''etre');
                po('     alimentee jusqu''au ' || fdt(v_d_glob) || '. Cette rupture est analysee en');
                po('     detail dans la section 15 (test MM-710).');
            END IF;
        END IF;

        print_sub('0.5 Legende des codes utilises dans ce rapport');
        po('  CONTRACT_STATUS   A = actif        L = liquide       V = extourne / annule');
        po('  PAYMENT_METHOD    B = Bearing (interets payes a l''echeance)');
        po('                    D = Discounted (interets precomptes a la souscription)');
        po('  MATURITY_TYPE     F = echeance fixe');
        po('  COMPONENT         PRINCIPAL = capital   INT_BT = interets bons du tresor');
        po('                    INT_OB = interets obligations');
        po('  EVENT comptable   INIT = mise en place  ACCR = provision d''interets');
        po('                    LIQD = liquidation    REVC = extourne de contrat');
        po('                    REVP = extourne de paiement');
        po('  TRN_CODE          IAC = interest accrual              ITC = initiate sync operations');
        po('                    PAL = principal amount liquidation');
        po('  ICCF_CALC_METHOD  1 = 30(Euro)/360   2 = 30(US)/360   3 = Actual/360');
        po('                    4 = 30(Euro)/365   5 = 30(US)/365   6 = Actual/365');
        po('                    7 = 30(Euro)/Act   8 = 30(US)/Act   9 = Actual/Actual');
        po('  Criticite         CRITIQUE > ELEVE > MOYEN > FAIBLE > INFO');
        po('  Montants          les colonnes en " M" sont exprimees en millions de XAF');
        po('  BOOKING           date de comptabilisation du contrat (BOOKING_DATE) ; elle');
        po('                    figure sur chaque ligne d''exception pour permettre de');
        po('                    rattacher immediatement l''anomalie a son exercice');
        po('  ECHEANCE          date d''echeance contractuelle (MATURITY_DATE) ; elle figure');
        po('                    egalement sur chaque ligne d''exception');
        po('  COMPTE (AC_NO)    numero de compte mouvemente dans ACTB_HISTORY. Les controles');
        po('                    comptables sont indexes sur AC_NO, le compte general naturel');
        po('                    (AC_NATURAL_GL de STTB_ACCOUNT) n''etant pas toujours');
        po('                    renseigne, en particulier pour les comptes generaux. Il est');
        po('                    utilise en second rang, quand il est disponible.');

        print_sub('0.6 Couverture des controles candidats issus du script d''exploration');
        po('  La section 30 du rapport d''exploration (money_marker_exploration_report.txt)');
        po('  a dimensionne 35 controles candidats. Le tableau ci-dessous indique, pour');
        po('  chacun, la suite qui lui a ete donnee. Les 35 candidats sont traites ;');
        po('  le script ajoute par ailleurs les controles de recalcul des interets, de');
        po('  provisions, de remboursement, de retard et de rapprochement comptable, qui');
        po('  ne figuraient pas dans la liste preparatoire.');
        po('');
        po('  Un candidat porte soit un code de test (il donne alors un verdict), soit');
        po('  la mention INFO : le controle a ete ecarte comme verdict parce qu''il ne');
        po('  discrimine rien sur ce portefeuille (colonne jamais alimentee, ou');
        po('  caracteristique normale des titres souverains), et l''information est');
        po('  restituee sous forme descriptive. La section 0.7 detaille ces arbitrages.');
        po('');
        tbl_line('4,62,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT (rapport d''exploration)', 62) || '|'
            || fpad('SUITE', 12) || '|');
        tbl_line('4,62,12');
        FOR r IN (
            SELECT n, lib, test FROM (
                SELECT 1 n, 'Contrepartie absente du referentiel clients' lib, 'MM-102' test FROM DUAL UNION ALL
                SELECT 2, 'Contrepartie non renseignee', 'MM-102' FROM DUAL UNION ALL
                SELECT 3, 'Contrepartie sans reference KYC', 'INFO' FROM DUAL UNION ALL
                SELECT 4, 'Contrepartie gelee, decedee ou introuvable', 'MM-103' FROM DUAL UNION ALL
                SELECT 5, 'Contrepartie non autorisee (AUTH_STAT different de A)', 'MM-103' FROM DUAL UNION ALL
                SELECT 6, 'Contrepartie a risque KYC eleve (RISK_LEVEL)', 'INFO' FROM DUAL UNION ALL
                SELECT 7, 'Contrepartie qui n''est pas un etablissement bancaire', 'INFO' FROM DUAL UNION ALL
                SELECT 8, 'Taux MAIN_COMP_RATE non renseigne', 'MM-308' FROM DUAL UNION ALL
                SELECT 9, 'Taux MAIN_COMP_RATE egal a zero', 'MM-308' FROM DUAL UNION ALL
                SELECT 10, 'Taux superieur a 15 pourcent', 'MM-308' FROM DUAL UNION ALL
                SELECT 11, 'Montant du contrat nul ou negatif', 'MM-210' FROM DUAL UNION ALL
                SELECT 12, 'Montant superieur a 1 milliard', 'INFO' FROM DUAL UNION ALL
                SELECT 13, 'Montant rond au million (operation forfaitaire)', 'INFO' FROM DUAL UNION ALL
                SELECT 14, 'Echeance anterieure a la date de valeur', 'MM-201' FROM DUAL UNION ALL
                SELECT 15, 'Date de valeur anterieure a la date de booking', 'MM-202' FROM DUAL UNION ALL
                SELECT 16, 'Contrat echu depuis plus de 90 jours', 'MM-503' FROM DUAL UNION ALL
                SELECT 17, 'Contrat echu avec encours residuel non nul', 'MM-402' FROM DUAL UNION ALL
                SELECT 18, 'Contrat sans aucune ecriture comptable', 'MM-601' FROM DUAL UNION ALL
                SELECT 19, 'Contrat sans composante d''interet (ICCF)', 'MM-114' FROM DUAL UNION ALL
                SELECT 20, 'Contrat sans echeancier', 'MM-114' FROM DUAL UNION ALL
                SELECT 21, 'Contrat sans confirmation SWIFT', 'MM-113' FROM DUAL UNION ALL
                SELECT 22, 'Produit absent du referentiel CSTM_PRODUCT', 'MM-107' FROM DUAL UNION ALL
                SELECT 23, 'Produit absent du parametrage LDTM_PRODUCT_MASTER', 'MM-107' FROM DUAL UNION ALL
                SELECT 24, 'Duree hors bornes du produit (TENOR sous MIN ou sur MAX)', 'MM-204' FROM DUAL UNION ALL
                SELECT 25, 'Contrat renouvele au moins une fois', 'MM-410' FROM DUAL UNION ALL
                SELECT 26, 'Contrat renouvele plus de trois fois', 'MM-411' FROM DUAL UNION ALL
                SELECT 27, 'Contrat sans DEALER identifie', 'MM-112' FROM DUAL UNION ALL
                SELECT 28, 'Contrat sans compte de reglement par defaut', 'MM-111' FROM DUAL UNION ALL
                SELECT 29, 'Contrat sans ligne de credit rattachee', 'MM-112' FROM DUAL UNION ALL
                SELECT 30, 'Contrat sans remarque / justification', 'MM-112' FROM DUAL UNION ALL
                SELECT 31, 'Contrat booke un samedi ou un dimanche', 'MM-205' FROM DUAL UNION ALL
                SELECT 32, 'Reference ne commencant pas par le code agence', 'MM-109' FROM DUAL UNION ALL
                SELECT 33, 'Contrat non confirme par la contrepartie', 'MM-113' FROM DUAL UNION ALL
                SELECT 34, 'Ecritures saisies par l''application externe', 'MM-703' FROM DUAL UNION ALL
                SELECT 35, 'Ecritures auto-autorisees (saisie = autorisation)', 'MM-701' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.lib, 62) || '|' || fpad(r.test, 12) || '|');
        END LOOP;
        tbl_line('4,62,12');

        print_sub('0.7 Controles ecartes et arbitrages de calibrage');
        po('  Un test qui se declenche sur la quasi-totalite du portefeuille ne designe');
        po('  pas une anomalie : il designe une caracteristique du portefeuille ou une');
        po('  colonne que cette installation n''alimente pas. Conserve comme verdict, il');
        po('  gonfle artificiellement l''enjeu financier de la revue et noie les constats');
        po('  reels. Les controles ci-dessous ont donc ete retires du decompte des tests.');
        po('  L''information qu''ils portaient reste imprimee, en clair, sous forme');
        po('  descriptive.');
        po('');
        tbl_line('4,16,40,58');
        po('  |' || fpad('N#', 4) || '|' || fpad('ANCIEN CODE', 16) || '|' || fpad('OBJET', 40) || '|'
            || fpad('MOTIF DU RETRAIT', 58) || '|');
        tbl_line('4,16,40,58');
        FOR r IN (
            SELECT n, cod, obj, mot FROM (
                SELECT 1 n, 'MM-104 / MM-105' cod, 'KYC de la contrepartie' obj,
                       'releve de la revue LCB-FT ; porterait sur quelques tiers' mot FROM DUAL UNION ALL
                SELECT 2, 'MM-106', 'Contrepartie non typee banque',
                       'les emetteurs sont des Etats (GOVT) : typage attendu' FROM DUAL UNION ALL
                SELECT 3, 'MM-112b/c/d', 'Ligne de credit, remarks, canal',
                       'colonnes jamais alimentees : fondues dans MM-112' FROM DUAL UNION ALL
                SELECT 4, 'MM-113 (statut)', 'CPARTY_CONFIRM_STATUS',
                       'colonne jamais alimentee : fondue dans MM-112' FROM DUAL UNION ALL
                SELECT 5, 'MM-209', 'Duree contre STD_TENOR du produit',
                       'STD_TENOR vaut 182 j par defaut, sans lien avec des obligations' FROM DUAL UNION ALL
                SELECT 6, 'MM-211', 'Operations au-dessus du seuil',
                       'perimetre d''echantillonnage et non anomalie' FROM DUAL UNION ALL
                SELECT 7, 'MM-212', 'Nominaux ronds',
                       'la rondeur est la norme sur les titres souverains' FROM DUAL UNION ALL
                SELECT 8, 'MM-305', 'Lignes de calcul a base nulle',
                       'periodes de l''echeancier non encore courues : normal' FROM DUAL UNION ALL
                SELECT 9, 'MM-306', 'Interets contrat contre somme des lignes',
                       'MAIN_COMP_AMOUNT couvre toute la vie du contrat, pas ICCF_CALC' FROM DUAL UNION ALL
                SELECT 10, 'MM-405', 'Interets encaisses contre contractuels',
                       'interets precomptes sur titres decotes : comparaison sans objet' FROM DUAL UNION ALL
                SELECT 11, 'MM-407', 'Remboursement anticipe',
                       'se declenchait sur chaque evenement de liquidation' FROM DUAL UNION ALL
                SELECT 12, 'MM-506', 'Population des echus de longue date',
                       'population deja portee par MM-402, MM-503 et MM-608' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.cod, 16) || '|' || fpad(r.obj, 40) || '|'
                || fpad(r.mot, 58) || '|');
        END LOOP;
        tbl_line('4,16,40,58');
        po('');
        po('  Quatre tests ont ete conserves mais recalibres :');
        tbl_line('4,12,50,52');
        po('  |' || fpad('N#', 4) || '|' || fpad('TEST', 12) || '|' || fpad('OBJET', 50) || '|'
            || fpad('RECALIBRAGE', 52) || '|');
        tbl_line('4,12,50,52');
        FOR r IN (
            SELECT n, cod, obj, mot FROM (
                SELECT 1 n, 'MM-202' cod, 'Date de valeur retroactive' obj,
                       'seuil de ' || TO_CHAR(k_retro_j) || ' jours ; en deca c''est le delai de reglement' mot FROM DUAL UNION ALL
                SELECT 2, 'MM-404', 'Capital rembourse contre nominal',
                       'liquidations extournees neutralisees (double comptage)' FROM DUAL UNION ALL
                SELECT 3, 'MM-501', 'Retard de paiement declare',
                       'enjeu en valeur absolue (montants dus negatifs sur decotes)' FROM DUAL UNION ALL
                SELECT 4, 'MM-607', 'Ecritures d''extourne',
                       'ramene en INFO : une extourne est un mecanisme normal' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.cod, 12) || '|' || fpad(r.obj, 50) || '|'
                || fpad(r.mot, 52) || '|');
        END LOOP;
        tbl_line('4,12,50,52');

        print_sub('0.8 Referentiel de controle comptable (partie 7)');
        po('  La partie 7 porte le referentiel de 51 controles transmis par la');
        po('  direction de l''audit interne. Les codes d''origine sont conserves tels');
        po('  quels, de sorte que la matrice de controle et le rapport se lisent l''un');
        po('  contre l''autre, ligne a ligne.');
        po('');
        tbl_line('4,8,54,10,10,44');
        po('  |' || fpad('N#', 4) || '|' || fpad('FAM.', 8) || '|' || fpad('OBJET DE LA FAMILLE', 54) || '|'
            || fpadl('NB', 10) || '|' || fpad('SECT.', 10) || '|' || fpad('BOUCLABLE EN BASE', 44) || '|');
        tbl_line('4,8,54,10,10,44');
        FOR r IN (
            SELECT n, fam, obj, nb, sec, bou FROM (
                SELECT 1 n, 'EXT' fam, 'Integrite de l''extraction et exhaustivite' obj,
                       '5' nb, '17' sec, 'oui, integralement' bou FROM DUAL UNION ALL
                SELECT 2, 'DBL', 'Respect de la partie double a trois mailles',
                       '4', '18', 'oui, integralement' FROM DUAL UNION ALL
                SELECT 3, 'MAP', 'Mapping produit x compte du schema comptable',
                       '6', '19', 'oui, integralement' FROM DUAL UNION ALL
                SELECT 4, 'INT', 'Exactitude et rythme des interets',
                       '7', '20', 'oui, integralement' FROM DUAL UNION ALL
                SELECT 5, 'LIF', 'Cycle de vie des positions au bilan',
                       '7', '21', 'oui, integralement' FROM DUAL UNION ALL
                SELECT 6, 'REV', 'Extournes, annulations et amendements',
                       '7', '22', 'oui, integralement' FROM DUAL UNION ALL
                SELECT 7, 'CSH', 'Rapprochement avec la tresorerie',
                       '3', '23', 'partiel, releve BEAC a pointer' FROM DUAL UNION ALL
                SELECT 8, 'CUT', 'Arrete de periode et justification des soldes',
                       '6', '24', 'partiel, balance et position a pointer' FROM DUAL UNION ALL
                SELECT 9, 'CLS', 'Classification placement contre transaction',
                       '3', '25', 'partiel, politique comptable a produire' FROM DUAL UNION ALL
                SELECT 10, 'STA', 'Donnees statiques, doublons et limites',
                       '5', '26', 'oui, limite ALM a parametrer' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.fam, 8) || '|' || fpad(r.obj, 54) || '|'
                || fpadl(r.nb, 10) || '|' || fpad(r.sec, 10) || '|' || fpad(r.bou, 44) || '|');
        END LOOP;
        tbl_line('4,8,54,10,10,44');
        po('');
        po('  Huit controles ne peuvent etre clos sans une piece exterieure a la base.');
        po('  Le script en execute la part verifiable et prepare le terme a rapprocher.');
        tbl_line('4,12,50,58');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE', 12) || '|' || fpad('CE QUE LE SCRIPT ETABLIT', 50) || '|'
            || fpad('PIECE A OBTENIR POUR CONCLURE', 58) || '|');
        tbl_line('4,12,50,58');
        FOR r IN (
            SELECT n, cod, fai, piece FROM (
                SELECT 1 n, 'CSH-01' cod, 'existence et sens de la jambe de tresorerie' fai,
                       'releve de compte BEAC, pointage date et montant' piece FROM DUAL UNION ALL
                SELECT 2, 'CSH-02', 'existence de la jambe sur les encaissements',
                       'releve de compte BEAC' FROM DUAL UNION ALL
                SELECT 3, 'CSH-03', 'sortie et retour de tresorerie des annules',
                       'releve BEAC a la date de valeur d''origine' FROM DUAL UNION ALL
                SELECT 4, 'CUT-02', 'provisions du mois contre produits du mois',
                       'balance generale, mouvement des comptes 733' FROM DUAL UNION ALL
                SELECT 5, 'CUT-03', 'solde titres contre portefeuille reconstitue',
                       'etat de position titres, instrument par instrument' FROM DUAL UNION ALL
                SELECT 6, 'CUT-04', 'solde 472 contre interets non courus',
                       'balance generale au ' || TO_CHAR(k_arrete, 'DD/MM/YYYY') FROM DUAL UNION ALL
                SELECT 7, 'CUT-05', 'solde 5118 contre interets courus',
                       'balance generale au ' || TO_CHAR(k_arrete, 'DD/MM/YYYY') FROM DUAL UNION ALL
                SELECT 8, 'CLS-02', 'presence ou absence d''ecritures de valorisation',
                       'politique comptable sur les titres de transaction' FROM DUAL
            ) ORDER BY n
        ) LOOP
            po('  |' || fpadl(TO_CHAR(r.n), 4) || '|' || fpad(r.cod, 12) || '|' || fpad(r.fai, 50) || '|'
                || fpad(r.piece, 58) || '|');
        END LOOP;
        tbl_line('4,12,50,58');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 1 : STRUCTURE DU PORTEFEUILLE');
    -- ########################################################################

    -- =========================================================
    -- 1. SYNTHESE GENERALE
    -- =========================================================
    print_section('1. SYNTHESE GENERALE DU PORTEFEUILLE');
    BEGIN
        po('  Photographie d''ensemble des operations retenues dans le perimetre.');

        print_sub('1.1 Volumes et montants');
        FOR r IN (
            SELECT COUNT(*) nb,
                   COUNT(DISTINCT m.product) nb_prod,
                   COUNT(DISTINCT m.counterparty) nb_cp,
                   COUNT(DISTINCT m.currency) nb_ccy,
                   COUNT(DISTINCT m.branch) nb_br,
                   SUM(m.lcy_amount) mt,
                   AVG(m.lcy_amount) moy,
                   MEDIAN(m.lcy_amount) med,
                   MIN(m.lcy_amount) mn,
                   MAX(m.lcy_amount) mx,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx_pond,
                   AVG(m.main_comp_rate) tx_moy,
                   MIN(m.main_comp_rate) tx_mn,
                   MAX(m.main_comp_rate) tx_mx,
                   AVG(m.maturity_date - m.value_date) dur_moy,
                   MEDIAN(m.maturity_date - m.value_date) dur_med,
                   MIN(m.maturity_date - m.value_date) dur_mn,
                   MAX(m.maturity_date - m.value_date) dur_mx,
                   SUM(m.main_comp_amount) int_tot
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
        ) LOOP
            print_kv('Nombre de contrats',              fnum(r.nb));
            print_kv('Nombre de produits distincts',    fnum(r.nb_prod));
            print_kv('Nombre de contreparties',         fnum(r.nb_cp));
            print_kv('Nombre de devises',               fnum(r.nb_ccy));
            print_kv('Nombre d''agences',               fnum(r.nb_br));
            po('');
            print_kv('Encours nominal cumule',          famt(r.mt) || '  (' || fmio(r.mt) || ')');
            print_kv('Montant moyen par contrat',       famt(r.moy));
            print_kv('Montant median',                  famt(r.med));
            print_kv('Montant minimum',                 famt(r.mn));
            print_kv('Montant maximum',                 famt(r.mx));
            po('');
            print_kv('Taux moyen pondere par les montants', ftx(ROUND(r.tx_pond, 4)));
            print_kv('Taux moyen arithmetique',          ftx(ROUND(r.tx_moy, 4)));
            print_kv('Taux minimum / maximum',           ftx(r.tx_mn) || '  /  ' || ftx(r.tx_mx));
            po('');
            print_kv('Duree moyenne (jours)',            TO_CHAR(ROUND(r.dur_moy, 1)));
            print_kv('Duree mediane (jours)',            TO_CHAR(ROUND(r.dur_med, 1)));
            print_kv('Duree minimum / maximum (jours)',  fnum(r.dur_mn) || '  /  ' || fnum(r.dur_mx));
            po('');
            print_kv('Interets contractuels cumules (MAIN_COMP_AMOUNT)',
                     famt(r.int_tot) || '  (' || fmio(r.int_tot) || ')');
            print_kv('Poids des interets sur le nominal', fpct(r.int_tot, r.mt));
        END LOOP;

        print_sub('1.2 Nature des operations');
        tbl_line('4,34,12,20,10,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('CARACTERISTIQUE', 34) || '|' || fpadl('NB', 12) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MT', 10) || '|' || fpadl('TAUX POND.', 14) || '|');
        tbl_line('4,34,12,20,10,14');
        v_row := 0;
        FOR r IN (
            SELECT dd.ord ord,
                   dd.cat || ' . ' || NVL(TRIM(CASE dd.ord
                        WHEN 1 THEN TRIM(m.payment_method)
                        WHEN 2 THEN TRIM(m.contract_status)
                        WHEN 3 THEN TRIM(m.rollover_allowed)
                        WHEN 4 THEN TRIM(m.maturity_type)
                        WHEN 5 THEN TRIM(m.main_comp)
                        WHEN 6 THEN TRIM(m.currency)
                        WHEN 7 THEN TRIM(m.branch)
                   END), '(vide)') lib,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx
              FROM ldtb_contract_master m
             CROSS JOIN (
                   SELECT 'Methode de paiement' cat, 1 ord FROM DUAL UNION ALL
                   SELECT 'Statut du contrat',       2 FROM DUAL UNION ALL
                   SELECT 'Renouvellement autorise', 3 FROM DUAL UNION ALL
                   SELECT 'Type d''echeance',        4 FROM DUAL UNION ALL
                   SELECT 'Composante principale',   5 FROM DUAL UNION ALL
                   SELECT 'Devise',                  6 FROM DUAL UNION ALL
                   SELECT 'Agence',                  7 FROM DUAL
             ) dd
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY dd.ord, dd.cat,
                      CASE dd.ord
                        WHEN 1 THEN TRIM(m.payment_method)
                        WHEN 2 THEN TRIM(m.contract_status)
                        WHEN 3 THEN TRIM(m.rollover_allowed)
                        WHEN 4 THEN TRIM(m.maturity_type)
                        WHEN 5 THEN TRIM(m.main_comp)
                        WHEN 6 THEN TRIM(m.currency)
                        WHEN 7 THEN TRIM(m.branch)
                      END
             ORDER BY dd.ord, SUM(m.lcy_amount) DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 34) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|'
                || fpadl(ftx(ROUND(r.tx, 4)), 14) || '|');
        END LOOP;
        tbl_line('4,34,12,20,10,14');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 2. REPARTITION PAR PRODUIT
    -- =========================================================
    print_section('2. STRUCTURE DU PORTEFEUILLE PAR PRODUIT');
    BEGIN
        po('  Nature des instruments detenus ou emis, rapprochee du parametrage');
        po('  produit (LDTM_PRODUCT_MASTER) qui fixe les bornes de duree autorisees.');

        print_sub('2.1 Contrats par produit');
        tbl_line('4,8,38,8,8,20,8,12,12,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PROD', 8) || '|' || fpad('LIBELLE DU PRODUIT', 38) || '|'
            || fpadl('NB', 8) || '|' || fpadl('% NB', 8) || '|' || fpadl('MONTANT LCY', 20) || '|'
            || fpadl('% MT', 8) || '|' || fpadl('TAUX POND.', 12) || '|' || fpadl('DUREE MOY', 12) || '|'
            || fpadl('BORNES PRODUIT', 16) || '|');
        tbl_line('4,8,38,8,8,20,8,12,12,16');
        v_row := 0;
        FOR r IN (
            SELECT m.product,
                   (SELECT MAX(p.product_description) FROM cstm_product p
                     WHERE p.product_code = m.product AND p.module = k_mod) lib,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx,
                   AVG(m.maturity_date - m.value_date) dur,
                   (SELECT MAX(l.min_tenor) FROM ldtm_product_master l WHERE l.product = m.product) tmin,
                   (SELECT MAX(l.max_tenor) FROM ldtm_product_master l WHERE l.product = m.product) tmax
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.product
             ORDER BY SUM(m.lcy_amount) DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 8) || '|' || fpad(r.lib, 38) || '|'
                || fpadl(fnum(r.nb), 8) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 8) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 8) || '|'
                || fpadl(ftx(ROUND(r.tx, 4)), 12) || '|' || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 12) || '|'
                || fpadl(fnum(r.tmin) || ' a ' || fnum(r.tmax) || ' j', 16) || '|');
        END LOOP;
        tbl_line('4,8,38,8,8,20,8,12,12,16');

        print_sub('2.2 Produits du module ' || k_mod || ' declares mais non utilises sur la periode');
        v_row := 0;
        FOR r IN (
            SELECT p.product_code, p.product_description, p.record_stat, p.auth_stat
              FROM cstm_product p
             WHERE p.module = k_mod
               AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m
                                WHERE m.product = p.product_code AND m.module = k_mod)
             ORDER BY p.product_code
        ) LOOP
            v_row := v_row + 1;
            print_kv('  ' || RPAD(r.product_code, 6) || ' ' || r.product_description,
                     'record ' || r.record_stat || ' / auth ' || r.auth_stat);
        END LOOP;
        IF v_row = 0 THEN
            po('    (tous les produits declares ont ete utilises)');
        ELSE
            po('    => ' || fnum(v_row) || ' produits ouverts dans le parametrage mais jamais mouvementes.');
            po('       Un parametrage dormant elargit inutilement la surface de risque.');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 3. REPARTITION PAR ETAT EMETTEUR
    -- =========================================================
    print_section('3. STRUCTURE DU PORTEFEUILLE PAR ETAT EMETTEUR (CONTREPARTIE)');
    BEGIN
        po('  Les titres du portefeuille sont adosses a des emetteurs souverains.');
        po('  Cette section mesure l''exposition de la banque par Etat, en nominal,');
        po('  en encours vivant a la date d''arrete et en interets contractuels.');

        print_sub('3.1 Exposition par Etat emetteur');
        tbl_line('4,12,30,6,8,8,20,8,12,11,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 12) || '|' || fpad('ETAT EMETTEUR', 30) || '|'
            || fpad('PAYS', 6) || '|' || fpadl('NB', 8) || '|' || fpadl('% NB', 8) || '|'
            || fpadl('NOMINAL', 20) || '|' || fpadl('% MT', 8) || '|' || fpadl('TAUX POND.', 12) || '|'
            || fpadl('DUREE MOY', 11) || '|' || fpadl('VIVANT A L''ARRETE', 20) || '|');
        tbl_line('4,12,30,6,8,8,20,8,12,11,20');
        v_row := 0;
        FOR r IN (
            SELECT m.counterparty cif,
                   (SELECT MAX(c.customer_name1) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) nom,
                   (SELECT MAX(c.country) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) pays,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx,
                   AVG(m.maturity_date - m.value_date) dur,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.lcy_amount ELSE 0 END) vivant
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.counterparty
             ORDER BY SUM(m.lcy_amount) DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cif, 12) || '|' || fpad(r.nom, 30) || '|'
                || fpad(r.pays, 6) || '|' || fpadl(fnum(r.nb), 8) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 8) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 8) || '|'
                || fpadl(ftx(ROUND(r.tx, 4)), 12) || '|' || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 11) || '|'
                || fpadl(fmio(r.vivant), 20) || '|');
        END LOOP;
        tbl_line('4,12,30,6,8,8,20,8,12,11,20');

        print_sub('3.2 Interets contractuels et interets provisionnes par Etat');
        tbl_line('4,30,10,20,20,20,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('ETAT EMETTEUR', 30) || '|' || fpadl('NB', 10) || '|'
            || fpadl('NOMINAL', 20) || '|' || fpadl('INTERETS PREVUS', 20) || '|'
            || fpadl('PROVISIONS CUMULEES', 20) || '|' || fpadl('% PROV.', 14) || '|');
        tbl_line('4,30,10,20,20,20,14');
        v_row := 0;
        FOR r IN (
            SELECT (SELECT MAX(c.customer_name1) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) nom,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.main_comp_amount) itot,
                   SUM((SELECT NVL(SUM(d.till_date_accrual), 0)
                          FROM ldtb_contract_iccf_details d
                         WHERE d.contract_ref_no = m.contract_ref_no
                           AND d.component <> 'PRINCIPAL')) iprov
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.counterparty
             ORDER BY SUM(m.lcy_amount) DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.nom, 30) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fmio(r.itot), 20) || '|'
                || fpadl(fmio(r.iprov), 20) || '|' || fpadl(fpct(r.iprov, r.itot), 14) || '|');
        END LOOP;
        tbl_line('4,30,10,20,20,20,14');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 4. CROISEMENT ETAT EMETTEUR x PRODUIT
    -- =========================================================
    print_section('4. CROISEMENT ETAT EMETTEUR x PRODUIT');
    BEGIN
        po('  Quelle nature de titre est detenue sur quel Etat. Une concentration');
        po('  forte sur un couple Etat / produit merite une justification de la');
        po('  politique de placement.');
        po('');

        tbl_line('4,30,8,36,8,20,10,12,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('ETAT EMETTEUR', 30) || '|' || fpad('PROD', 8) || '|'
            || fpad('LIBELLE DU PRODUIT', 36) || '|' || fpadl('NB', 8) || '|' || fpadl('MONTANT LCY', 20) || '|'
            || fpadl('% TOTAL', 10) || '|' || fpadl('TAUX POND.', 12) || '|' || fpadl('DUREE MOY', 12) || '|');
        tbl_line('4,30,8,36,8,20,10,12,12');
        v_row := 0;
        FOR r IN (
            SELECT (SELECT MAX(c.customer_name1) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) nom,
                   m.product,
                   (SELECT MAX(p.product_description) FROM cstm_product p
                     WHERE p.product_code = m.product AND p.module = k_mod) lib,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx,
                   AVG(m.maturity_date - m.value_date) dur
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.counterparty, m.product
             ORDER BY 1, SUM(m.lcy_amount) DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.nom, 30) || '|' || fpad(r.product, 8) || '|'
                || fpad(r.lib, 36) || '|' || fpadl(fnum(r.nb), 8) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|' || fpadl(ftx(ROUND(r.tx, 4)), 12) || '|'
                || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 12) || '|');
        END LOOP;
        tbl_line('4,30,8,36,8,20,10,12,12');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 5. REPARTITION DANS LE TEMPS
    -- =========================================================
    print_section('5. REPARTITION DANS LE TEMPS (PRODUCTION, TOMBEES, ECHEANCIER)');
    BEGIN
        po('  Rythme de souscription des operations, profil des tombees passees et');
        po('  echeancier previsionnel restant a la date d''arrete.');

        print_sub('5.1 Production mensuelle (mois de la date de valeur)');
        tbl_line('4,12,10,20,10,12,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('MOIS', 12) || '|' || fpadl('NB', 10) || '|'
            || fpadl('MONTANT SOUSCRIT', 20) || '|' || fpadl('% MT', 10) || '|'
            || fpadl('TAUX POND.', 12) || '|' || fpadl('DUREE MOY', 12) || '|'
            || fpadl('CUMUL PRODUCTION', 20) || '|');
        tbl_line('4,12,10,20,10,12,12,20');
        v_row := 0;
        v_mt  := 0;
        FOR r IN (
            SELECT TO_CHAR(m.value_date, 'YYYY-MM') mois,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx,
                   AVG(m.maturity_date - m.value_date) dur
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TO_CHAR(m.value_date, 'YYYY-MM')
             ORDER BY 1
        ) LOOP
            v_row := v_row + 1;
            v_mt  := v_mt + NVL(r.mt, 0);
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mois, 12) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|'
                || fpadl(ftx(ROUND(r.tx, 4)), 12) || '|' || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 12) || '|'
                || fpadl(fmio(v_mt), 20) || '|');
        END LOOP;
        tbl_line('4,12,10,20,10,12,12,20');

        print_sub('5.2 Production annuelle par Etat emetteur');
        tbl_line('4,8,30,10,20,10,12,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('ANNEE', 8) || '|' || fpad('ETAT EMETTEUR', 30) || '|'
            || fpadl('NB', 10) || '|' || fpadl('MONTANT SOUSCRIT', 20) || '|' || fpadl('% ANNEE', 10) || '|'
            || fpadl('TAUX POND.', 12) || '|' || fpadl('DUREE MOY', 12) || '|');
        tbl_line('4,8,30,10,20,10,12,12');
        v_row := 0;
        FOR r IN (
            SELECT TO_CHAR(m.value_date, 'YYYY') an,
                   (SELECT MAX(c.customer_name1) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) nom,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(SUM(m.lcy_amount)) OVER (PARTITION BY TO_CHAR(m.value_date, 'YYYY')) mt_an,
                   SUM(m.lcy_amount * m.main_comp_rate) / NULLIF(SUM(m.lcy_amount), 0) tx,
                   AVG(m.maturity_date - m.value_date) dur
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TO_CHAR(m.value_date, 'YYYY'), m.counterparty
             ORDER BY 1, 4 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.an, 8) || '|' || fpad(r.nom, 30) || '|'
                || fpadl(fnum(r.nb), 10) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, r.mt_an), 10) || '|' || fpadl(ftx(ROUND(r.tx, 4)), 12) || '|'
                || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 12) || '|');
        END LOOP;
        tbl_line('4,8,30,10,20,10,12,12');

        print_sub('5.3 Tombees mensuelles (mois de la date d''echeance, toute la duree de vie)');
        tbl_line('4,12,10,20,20,20,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('MOIS', 12) || '|' || fpadl('NB', 10) || '|'
            || fpadl('PRINCIPAL', 20) || '|' || fpadl('INTERETS PREVUS', 20) || '|'
            || fpadl('TOTAL ATTENDU', 20) || '|' || fpadl('SITUATION', 14) || '|');
        tbl_line('4,12,10,20,20,20,14');
        v_row := 0;
        FOR r IN (
            SELECT TO_CHAR(m.maturity_date, 'YYYY-MM') mois,
                   MIN(m.maturity_date) d_min,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.main_comp_amount) it
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TO_CHAR(m.maturity_date, 'YYYY-MM')
             ORDER BY 1
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mois, 12) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fmio(r.it), 20) || '|'
                || fpadl(fmio(NVL(r.mt, 0) + NVL(r.it, 0)), 20) || '|'
                || fpadl(CASE WHEN r.d_min <= k_arrete THEN 'ECHU' ELSE 'A VENIR' END, 14) || '|');
        END LOOP;
        tbl_line('4,12,10,20,20,20,14');

        print_sub('5.4 Echeancier previsionnel restant a la date d''arrete du ' || fdt(k_arrete));
        SELECT NVL(SUM(m.lcy_amount), 0) INTO v_mt2
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.maturity_date > k_arrete
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Encours nominal restant a echoir', famt(v_mt2) || '  (' || fmio(v_mt2) || ')');
        po('');
        tbl_line('4,12,10,20,20,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('MOIS', 12) || '|' || fpadl('NB', 10) || '|'
            || fpadl('PRINCIPAL', 20) || '|' || fpadl('INTERETS PREVUS', 20) || '|'
            || fpadl('TOTAL ATTENDU', 20) || '|' || fpadl('ENCOURS RESIDUEL', 20) || '|');
        tbl_line('4,12,10,20,20,20,20');
        v_row := 0;
        v_mt  := v_mt2;
        FOR r IN (
            SELECT TO_CHAR(m.maturity_date, 'YYYY-MM') mois,
                   COUNT(*) nb,
                   SUM(m.lcy_amount) mt,
                   SUM(m.main_comp_amount) it
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.maturity_date > k_arrete
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TO_CHAR(m.maturity_date, 'YYYY-MM')
             ORDER BY 1
        ) LOOP
            v_row := v_row + 1;
            v_mt  := v_mt - NVL(r.mt, 0);
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mois, 12) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fmio(r.it), 20) || '|'
                || fpadl(fmio(NVL(r.mt, 0) + NVL(r.it, 0)), 20) || '|' || fpadl(fmio(v_mt), 20) || '|');
        END LOOP;
        tbl_line('4,12,10,20,20,20,20');
        IF v_row = 0 THEN
            po('    (aucune tombee posterieure a la date d''arrete)');
        END IF;

        print_sub('5.5 Saisonnalite : jour de la semaine de la date de booking');
        tbl_line('4,20,12,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('JOUR', 20) || '|' || fpadl('NB', 12) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('% NB', 12) || '|');
        tbl_line('4,20,12,20,12');
        v_row := 0;
        FOR r IN (
            SELECT TRUNC(m.booking_date) - TRUNC(m.booking_date, 'IW') + 1 jr,
                   COUNT(*) nb, SUM(m.lcy_amount) mt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TRUNC(m.booking_date) - TRUNC(m.booking_date, 'IW') + 1
             ORDER BY 1
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
                || fpad(CASE r.jr WHEN 1 THEN 'lundi' WHEN 2 THEN 'mardi' WHEN 3 THEN 'mercredi'
                                  WHEN 4 THEN 'jeudi' WHEN 5 THEN 'vendredi' WHEN 6 THEN 'SAMEDI'
                                  WHEN 7 THEN 'DIMANCHE' END, 20) || '|'
                || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|');
        END LOOP;
        tbl_line('4,20,12,20,12');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 6. REPARTITION PAR TRANCHES
    -- =========================================================
    print_section('6. REPARTITION PAR TRANCHES DE MONTANT, DE TAUX ET DE DUREE');
    BEGIN
        po('  Ces trois distributions servent de base a l''echantillonnage : elles');
        po('  montrent ou se concentrent les montants et ou se situent les valeurs');
        po('  extremes a examiner en priorite.');

        print_sub('6.1 Par tranche de montant');
        tbl_line('4,26,10,10,20,10,12,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('TRANCHE', 26) || '|' || fpadl('NB', 10) || '|'
            || fpadl('% NB', 10) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MT', 10) || '|'
            || fpadl('TAUX POND.', 12) || '|' || fpadl('DUREE MOY', 12) || '|');
        tbl_line('4,26,10,10,20,10,12,12');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt,
                   SUM(mt * tx) / NULLIF(SUM(mt), 0) txp, AVG(dur) dur
              FROM (
                SELECT CASE
                         WHEN m.lcy_amount <          10000000 THEN '1. moins de 10 M'
                         WHEN m.lcy_amount <          50000000 THEN '2. 10 a 50 M'
                         WHEN m.lcy_amount <         100000000 THEN '3. 50 a 100 M'
                         WHEN m.lcy_amount <         500000000 THEN '4. 100 a 500 M'
                         WHEN m.lcy_amount <        1000000000 THEN '5. 500 M a 1 Md'
                         WHEN m.lcy_amount <        5000000000 THEN '6. 1 a 5 Md'
                         ELSE                                       '7. 5 Md et plus'
                       END tr,
                       m.lcy_amount mt, m.main_comp_rate tx,
                       m.maturity_date - m.value_date dur
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
              )
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 26) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 10) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|' || fpadl(ftx(ROUND(r.txp, 4)), 12) || '|'
                || fpadl(TO_CHAR(ROUND(r.dur)) || ' j', 12) || '|');
        END LOOP;
        tbl_line('4,26,10,10,20,10,12,12');

        print_sub('6.2 Par tranche de taux');
        tbl_line('4,26,10,10,20,10,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('TRANCHE DE TAUX', 26) || '|' || fpadl('NB', 10) || '|'
            || fpadl('% NB', 10) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MT', 10) || '|'
            || fpadl('MONTANT MOYEN', 20) || '|' || fpadl('INTERETS PREVUS', 20) || '|');
        tbl_line('4,26,10,10,20,10,20,20');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt, AVG(mt) moy, SUM(it) it
              FROM (
                SELECT CASE
                         WHEN m.main_comp_rate IS NULL THEN '0. taux non renseigne'
                         WHEN m.main_comp_rate =  0    THEN '1. taux nul'
                         WHEN m.main_comp_rate <  2    THEN '2. moins de 2 %'
                         WHEN m.main_comp_rate <  4    THEN '3. 2 a 4 %'
                         WHEN m.main_comp_rate <  6    THEN '4. 4 a 6 %'
                         WHEN m.main_comp_rate <  8    THEN '5. 6 a 8 %'
                         WHEN m.main_comp_rate < 12    THEN '6. 8 a 12 %'
                         ELSE                               '7. 12 % et plus'
                       END tr,
                       m.lcy_amount mt, m.main_comp_amount it
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
              )
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 26) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 10) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|' || fpadl(famt(r.moy), 20) || '|'
                || fpadl(fmio(r.it), 20) || '|');
        END LOOP;
        tbl_line('4,26,10,10,20,10,20,20');

        print_sub('6.3 Par duree reelle (echeance moins date de valeur)');
        tbl_line('4,26,10,10,20,10,12,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('DUREE', 26) || '|' || fpadl('NB', 10) || '|'
            || fpadl('% NB', 10) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MT', 10) || '|'
            || fpadl('TAUX POND.', 12) || '|' || fpadl('JOURS MOYENS', 14) || '|');
        tbl_line('4,26,10,10,20,10,12,14');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt,
                   SUM(mt * tx) / NULLIF(SUM(mt), 0) txp, AVG(d) dm
              FROM (
                SELECT CASE
                         WHEN m.maturity_date - m.value_date <=   1 THEN '1. au jour le jour'
                         WHEN m.maturity_date - m.value_date <=   7 THEN '2. 2 a 7 jours'
                         WHEN m.maturity_date - m.value_date <=  31 THEN '3. 8 a 31 jours'
                         WHEN m.maturity_date - m.value_date <=  92 THEN '4. 1 a 3 mois'
                         WHEN m.maturity_date - m.value_date <= 184 THEN '5. 3 a 6 mois'
                         WHEN m.maturity_date - m.value_date <= 366 THEN '6. 6 a 12 mois'
                         WHEN m.maturity_date - m.value_date <= 731 THEN '7. 1 a 2 ans'
                         WHEN m.maturity_date - m.value_date <=1827 THEN '8. 2 a 5 ans'
                         ELSE                                            '9. plus de 5 ans'
                       END tr,
                       m.lcy_amount mt, m.main_comp_rate tx,
                       m.maturity_date - m.value_date d
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
              )
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 26) || '|' || fpadl(fnum(r.nb), 10) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 10) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_mt_ctr), 10) || '|' || fpadl(ftx(ROUND(r.txp, 4)), 12) || '|'
                || fpadl(TO_CHAR(ROUND(r.dm, 1)), 14) || '|');
        END LOOP;
        tbl_line('4,26,10,10,20,10,12,14');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 7. ETAT DU PORTEFEUILLE A LA DATE D'ARRETE
    -- =========================================================
    print_section('7. ETAT DU PORTEFEUILLE A LA DATE D''ARRETE DU ' || fdt(k_arrete));
    BEGIN
        po('  Distinction entre les operations encore vivantes (echeance posterieure a');
        po('  la date d''arrete) et les operations echues, puis confrontation avec le');
        po('  statut porte par le contrat et avec l''encours comptable.');

        print_sub('7.1 Vivant / echu');
        FOR r IN (
            SELECT COUNT(*) nb,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN 1 ELSE 0 END) nb_viv,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.lcy_amount ELSE 0 END) mt_viv,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN 1 ELSE 0 END) nb_ech,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN m.lcy_amount ELSE 0 END) mt_ech,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.main_comp_amount ELSE 0 END) it_viv
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
        ) LOOP
            print_kv('Contrats vivants (echeance a venir)', fnum(r.nb_viv) || '   ' || fpct(r.nb_viv, r.nb));
            print_kv('Nominal vivant',                      famt(r.mt_viv) || '  (' || fmio(r.mt_viv) || ')');
            print_kv('Interets restant a percevoir sur le vivant',
                                                            famt(r.it_viv) || '  (' || fmio(r.it_viv) || ')');
            print_kv('Contrats echus',                      fnum(r.nb_ech) || '   ' || fpct(r.nb_ech, r.nb));
            print_kv('Nominal echu',                        famt(r.mt_ech) || '  (' || fmio(r.mt_ech) || ')');
        END LOOP;

        SELECT NVL(SUM(b.principal_outstanding_bal), 0), NVL(SUM(b.current_face_value), 0)
          INTO v_mt, v_mt2
          FROM ldtb_contract_balance b
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = b.contract_ref_no AND m.module = k_mod);
        print_kv('Somme PRINCIPAL_OUTSTANDING_BAL (LDTB_CONTRACT_BALANCE)',
                 famt(v_mt) || '  (' || fmio(v_mt) || ')');
        print_kv('Somme CURRENT_FACE_VALUE',
                 famt(v_mt2) || '  (' || fmio(v_mt2) || ')');

        print_sub('7.2 Situation reelle par Etat emetteur');
        tbl_line('4,30,10,20,10,20,10,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('ETAT EMETTEUR', 30) || '|' || fpadl('NB VIVANT', 10) || '|'
            || fpadl('NOMINAL VIVANT', 20) || '|' || fpadl('NB ECHU', 10) || '|'
            || fpadl('NOMINAL ECHU', 20) || '|' || fpadl('% VIVANT', 10) || '|'
            || fpadl('INT. A PERCEVOIR', 20) || '|');
        tbl_line('4,30,10,20,10,20,10,20');
        v_row := 0;
        FOR r IN (
            SELECT (SELECT MAX(c.customer_name1) FROM sttm_customer c
                     WHERE c.customer_no = m.counterparty) nom,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN 1 ELSE 0 END) nb_viv,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.lcy_amount ELSE 0 END) mt_viv,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN 1 ELSE 0 END) nb_ech,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN m.lcy_amount ELSE 0 END) mt_ech,
                   SUM(m.lcy_amount) mt,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.main_comp_amount ELSE 0 END) it_viv
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.counterparty
             ORDER BY 3 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.nom, 30) || '|' || fpadl(fnum(r.nb_viv), 10) || '|'
                || fpadl(fmio(r.mt_viv), 20) || '|' || fpadl(fnum(r.nb_ech), 10) || '|'
                || fpadl(fmio(r.mt_ech), 20) || '|' || fpadl(fpct(r.mt_viv, r.mt), 10) || '|'
                || fpadl(fmio(r.it_viv), 20) || '|');
        END LOOP;
        tbl_line('4,30,10,20,10,20,10,20');

        print_sub('7.3 Situation reelle par produit');
        tbl_line('4,8,36,10,20,10,20,10');
        po('  |' || fpad('N#', 4) || '|' || fpad('PROD', 8) || '|' || fpad('LIBELLE DU PRODUIT', 36) || '|'
            || fpadl('NB VIVANT', 10) || '|' || fpadl('NOMINAL VIVANT', 20) || '|' || fpadl('NB ECHU', 10) || '|'
            || fpadl('NOMINAL ECHU', 20) || '|' || fpadl('% VIVANT', 10) || '|');
        tbl_line('4,8,36,10,20,10,20,10');
        v_row := 0;
        FOR r IN (
            SELECT m.product,
                   (SELECT MAX(p.product_description) FROM cstm_product p
                     WHERE p.product_code = m.product AND p.module = k_mod) lib,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN 1 ELSE 0 END) nb_viv,
                   SUM(CASE WHEN m.maturity_date > k_arrete THEN m.lcy_amount ELSE 0 END) mt_viv,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN 1 ELSE 0 END) nb_ech,
                   SUM(CASE WHEN m.maturity_date <= k_arrete THEN m.lcy_amount ELSE 0 END) mt_ech,
                   SUM(m.lcy_amount) mt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY m.product
             ORDER BY 4 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 8) || '|' || fpad(r.lib, 36) || '|'
                || fpadl(fnum(r.nb_viv), 10) || '|' || fpadl(fmio(r.mt_viv), 20) || '|'
                || fpadl(fnum(r.nb_ech), 10) || '|' || fpadl(fmio(r.mt_ech), 20) || '|'
                || fpadl(fpct(r.mt_viv, r.mt), 10) || '|');
        END LOOP;
        tbl_line('4,8,36,10,20,10,20,10');

        print_sub('7.4 Statut porte par le contrat croise avec la situation reelle');
        po('  Un contrat de statut A (actif) dont l''echeance est passee, ou un contrat');
        po('  de statut L (liquide) dont l''echeance est a venir, doit etre explique.');
        po('');
        tbl_line('4,20,20,12,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_STATUS', 20) || '|' || fpad('SITUATION REELLE', 20) || '|'
            || fpadl('NB', 12) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('% NB', 12) || '|');
        tbl_line('4,20,20,12,20,12');
        v_row := 0;
        FOR r IN (
            SELECT TRIM(m.contract_status) st,
                   CASE WHEN m.maturity_date > k_arrete THEN 'VIVANT' ELSE 'ECHU' END sit,
                   COUNT(*) nb, SUM(m.lcy_amount) mt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
             GROUP BY TRIM(m.contract_status),
                      CASE WHEN m.maturity_date > k_arrete THEN 'VIVANT' ELSE 'ECHU' END
             ORDER BY 1, 2
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
                || fpad(r.st || ' - ' || CASE r.st WHEN 'A' THEN 'actif' WHEN 'L' THEN 'liquide'
                                                   WHEN 'V' THEN 'extourne' ELSE 'autre' END, 20) || '|'
                || fpad(r.sit, 20) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|');
        END LOOP;
        tbl_line('4,20,20,12,20,12');

        print_sub('7.5 Avancement des liquidations');
        SELECT COUNT(DISTINCT s.contract_ref_no), NVL(SUM(s.total_paid), 0)
          INTO v_cnt, v_mt
          FROM ldtb_contract_liq_summary s
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = s.contract_ref_no AND m.module = k_mod);
        print_kv('Contrats ayant fait l''objet d''au moins une liquidation', fnum(v_cnt));
        print_kv('Total paye enregistre (LDTB_CONTRACT_LIQ_SUMMARY)',
                 famt(v_mt) || '  (' || fmio(v_mt) || ')');

        SELECT COUNT(*), NVL(SUM(l.amount_due), 0), NVL(SUM(l.amount_paid), 0)
          INTO v_cnt, v_mt, v_mt2
          FROM ldtb_contract_liq l
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = l.contract_ref_no AND m.module = k_mod);
        print_kv('Lignes de liquidation par composante (LDTB_CONTRACT_LIQ)', fnum(v_cnt));
        print_kv('Total du (AMOUNT_DUE)',   famt(v_mt)  || '  (' || fmio(v_mt) || ')');
        print_kv('Total paye (AMOUNT_PAID)', famt(v_mt2) || '  (' || fmio(v_mt2) || ')');
        print_kv('Reste du',                 famt(v_mt - v_mt2) || '  (' || fmio(v_mt - v_mt2) || ')');

        po('');
        tbl_line('4,20,12,20,20,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPOSANTE', 20) || '|' || fpadl('NB LIGNES', 12) || '|'
            || fpadl('MONTANT DU', 20) || '|' || fpadl('MONTANT PAYE', 20) || '|'
            || fpadl('RESTE DU', 20) || '|' || fpadl('% PAYE', 12) || '|');
        tbl_line('4,20,12,20,20,20,12');
        v_row := 0;
        FOR r IN (
            SELECT l.component, COUNT(*) nb,
                   SUM(l.amount_due) du, SUM(l.amount_paid) paye
              FROM ldtb_contract_liq l
             WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = l.contract_ref_no AND m.module = k_mod)
             GROUP BY l.component
             ORDER BY 3 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.component, 20) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.du), 20) || '|' || fpadl(fmio(r.paye), 20) || '|'
                || fpadl(fmio(NVL(r.du, 0) - NVL(r.paye, 0)), 20) || '|' || fpadl(fpct(r.paye, r.du), 12) || '|');
        END LOOP;
        tbl_line('4,20,12,20,20,20,12');

        print_sub('7.6 Renouvellements (rollover)');
        SELECT COUNT(*) INTO v_cnt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod AND NVL(m.rollover_count, 0) > 0
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Contrats renouveles au moins une fois (ROLLOVER_COUNT)', fnum(v_cnt));
        SELECT COUNT(*) INTO v_cnt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod AND TRIM(m.rollover_allowed) = 'Y'
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Contrats autorisant le renouvellement', fnum(v_cnt));
        SELECT COUNT(*) INTO v_cnt
          FROM ldtb_contract_rollover r
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = r.contract_ref_no AND m.module = k_mod);
        print_kv('Instructions de renouvellement enregistrees', fnum(v_cnt));
        SELECT COUNT(*) INTO v_cnt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod AND m.parent_contract_ref_no IS NOT NULL
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Contrats issus d''un contrat parent', fnum(v_cnt));

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 8. CONCENTRATION ET EXPOSITIONS INDIVIDUELLES
    -- =========================================================
    print_section('8. CONCENTRATION ET EXPOSITIONS INDIVIDUELLES');
    BEGIN
        po('  Poids des operations les plus importantes dans le portefeuille. Ces');
        po('  contrats constituent l''echantillon a examiner en priorite sur piece.');

        print_sub('8.1 Les 25 operations les plus importantes');
        tbl_line('4,20,12,7,28,20,10,12,12,10,10');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|'
            || fpad('PROD', 7) || '|'
            || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('TAUX', 10) || '|'
            || fpad('VALEUR', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('% TOTAL', 10) || '|'
            || fpadl('SITUATION', 10) || '|');
        tbl_line('4,20,12,7,28,20,10,12,12,10,10');
        v_row := 0;
        v_mt  := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT m.contract_ref_no, m.product, m.lcy_amount, m.main_comp_rate,
                       m.booking_date, m.value_date, m.maturity_date,
                       (SELECT MAX(c.customer_name1) FROM sttm_customer c
                         WHERE c.customer_no = m.counterparty) nom
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                 ORDER BY m.lcy_amount DESC, m.contract_ref_no
            ) WHERE ROWNUM <= 25
        ) LOOP
            v_row := v_row + 1;
            v_mt  := v_mt + NVL(r.lcy_amount, 0);
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 20) || '|'
                || fpad(fdt(r.booking_date), 12) || '|'
                || fpad(r.product, 7) || '|' || fpad(r.nom, 28) || '|' || fpadl(famt(r.lcy_amount), 20) || '|'
                || fpadl(ftx(r.main_comp_rate), 10) || '|' || fpad(fdt(r.value_date), 12) || '|'
                || fpad(fdt(r.maturity_date), 12) || '|' || fpadl(fpct(r.lcy_amount, v_mt_ctr), 10) || '|'
                || fpadl(CASE WHEN r.maturity_date > k_arrete THEN 'VIVANT' ELSE 'ECHU' END, 10) || '|');
        END LOOP;
        tbl_line('4,20,12,7,28,20,10,12,12,10,10');
        print_kv('Poids cumule de ces 25 operations', fmio(v_mt) || '   ' || fpct(v_mt, v_mt_ctr));

        print_sub('8.2 Courbe de concentration');
        tbl_line('4,30,12,20,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('TRANCHE', 30) || '|' || fpadl('NB CONTRATS', 12) || '|'
            || fpadl('MONTANT CUMULE', 20) || '|' || fpadl('% DU TOTAL', 14) || '|');
        tbl_line('4,30,12,20,14');
        v_row := 0;
        FOR r IN (
            SELECT lib, seuil FROM (
                SELECT 'Les 5 plus grosses operations' lib,   5 seuil, 1 ord FROM DUAL UNION ALL
                SELECT 'Les 10 plus grosses operations',     10, 2 FROM DUAL UNION ALL
                SELECT 'Les 25 plus grosses operations',     25, 3 FROM DUAL UNION ALL
                SELECT 'Les 50 plus grosses operations',     50, 4 FROM DUAL UNION ALL
                SELECT 'Les 100 plus grosses operations',   100, 5 FROM DUAL
            ) ORDER BY ord
        ) LOOP
            SELECT NVL(SUM(lcy_amount), 0), COUNT(*) INTO v_mt, v_cnt
              FROM (SELECT m.lcy_amount
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                     ORDER BY m.lcy_amount DESC)
             WHERE ROWNUM <= r.seuil;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 30) || '|' || fpadl(fnum(v_cnt), 12) || '|'
                || fpadl(fmio(v_mt), 20) || '|' || fpadl(fpct(v_mt, v_mt_ctr), 14) || '|');
        END LOOP;
        tbl_line('4,30,12,20,14');

        print_sub('8.3 Operations vivantes superieures au seuil de signification');
        print_kv('Seuil de signification retenu', famt(k_mt_signif) || ' XAF');
        po('');
        d_head('JOURS RESTANTS');
        v_row := 0;
        v_mt  := 0;
        FOR r IN (
            SELECT * FROM (
                SELECT m.contract_ref_no, m.product, m.counterparty, m.lcy_amount,
                       m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                       (SELECT MAX(c.customer_name1) FROM sttm_customer c
                         WHERE c.customer_no = m.counterparty) nom
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.maturity_date > k_arrete
                   AND m.lcy_amount >= k_mt_signif
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                 ORDER BY m.lcy_amount DESC
            ) WHERE ROWNUM <= k_top
        ) LOOP
            v_row := v_row + 1;
            v_mt  := v_mt + NVL(r.lcy_amount, 0);
            d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom, r.lcy_amount,
                  r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                  fnum(TRUNC(r.maturity_date) - TRUNC(k_arrete)) || ' j');
        END LOOP;
        d_foot;
        IF v_row = 0 THEN
            p_ras;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 2 : CONTROLES SUR LE REFERENTIEL, LES TIERS ET LES DATES');
    -- ########################################################################

    -- =========================================================
    -- 9. MM-1xx : REFERENTIEL, TIERS ET IDENTIFICATION
    -- =========================================================
    print_section('9. CONTROLES MM-1xx : REFERENTIEL, TIERS ET IDENTIFICATION');
    BEGIN

        -- -----------------------------------------------------
        p_test('MM-101', 'Operations potentiellement saisies en double');
        p_obj('detecter deux contrats de meme contrepartie, meme produit, meme montant,');
        po('             meme date de valeur, meme echeance et meme taux.');
        SELECT COUNT(*), NVL(SUM(mt), 0) INTO v_cnt, v_mt
          FROM (SELECT SUM(m.lcy_amount) mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                 GROUP BY m.counterparty, m.product, m.lcy_amount, m.value_date,
                          m.maturity_date, m.main_comp_rate
                HAVING COUNT(*) > 1);
        p_verdict('MM-101', 'Operations potentiellement saisies en double', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,28,7,20,10,12,12,10,40');
            po('  |' || fpad('N#', 4) || '|' || fpad('ETAT EMETTEUR', 28) || '|' || fpad('PROD', 7) || '|'
                || fpadl('MONTANT LCY', 20) || '|' || fpadl('TAUX', 10) || '|' || fpad('VALEUR', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpadl('NB', 10) || '|' || fpad('REFERENCES CONCERNEES', 40) || '|');
            tbl_line('4,28,7,20,10,12,12,10,40');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.product, m.lcy_amount, m.main_comp_rate, m.value_date,
                               m.maturity_date, COUNT(*) nb,
                               LISTAGG(m.contract_ref_no, ' ') WITHIN GROUP (ORDER BY m.contract_ref_no) refs
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                         GROUP BY m.counterparty, m.product, m.lcy_amount, m.value_date,
                                  m.maturity_date, m.main_comp_rate
                        HAVING COUNT(*) > 1
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.nom, 28) || '|' || fpad(r.product, 7) || '|'
                    || fpadl(famt(r.lcy_amount), 20) || '|' || fpadl(ftx(r.main_comp_rate), 10) || '|'
                    || fpad(fdt(r.value_date), 12) || '|' || fpad(fdt(r.maturity_date), 12) || '|'
                    || fpadl(fnum(r.nb), 10) || '|' || fpad(r.refs, 40) || '|');
            END LOOP;
            tbl_line('4,28,7,20,10,12,12,10,40');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-102', 'Contrepartie absente du referentiel clients');
        p_obj('toute operation doit etre adossee a un tiers existant dans STTM_CUSTOMER.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (m.counterparty IS NULL
                OR NOT EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty));
        p_verdict('MM-102', 'Contrepartie absente du referentiel clients', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('CIF INTROUVABLE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty, m.lcy_amount,
                               m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (m.counterparty IS NULL
                                OR NOT EXISTS (SELECT 1 FROM sttm_customer c
                                                WHERE c.customer_no = m.counterparty))
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, 'INTROUVABLE',
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      NVL(r.counterparty, 'NULL'));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-103', 'Contrepartie gelee, cloturee ou non autorisee');
        p_obj('aucune operation ne doit etre portee par un tiers gele, decede,');
        po('             disparu, ferme (RECORD_STAT = C) ou non autorise (AUTH_STAT <> A).');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
          JOIN sttm_customer c ON c.customer_no = m.counterparty
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (NVL(TRIM(c.frozen), 'N') = 'Y'
                OR NVL(TRIM(c.deceased), 'N') = 'Y'
                OR NVL(TRIM(c.whereabouts_unknown), 'N') = 'Y'
                OR NVL(TRIM(c.record_stat), 'O') <> 'O'
                OR NVL(TRIM(c.auth_stat), 'A') <> 'A');
        p_verdict('MM-103', 'Contrepartie gelee, cloturee ou non autorisee', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('MOTIF');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty, c.customer_name1 nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               CASE WHEN NVL(TRIM(c.frozen), 'N') = 'Y' THEN 'GELE'
                                    WHEN NVL(TRIM(c.deceased), 'N') = 'Y' THEN 'DECEDE'
                                    WHEN NVL(TRIM(c.whereabouts_unknown), 'N') = 'Y' THEN 'DISPARU'
                                    WHEN NVL(TRIM(c.record_stat), 'O') <> 'O' THEN 'FERME'
                                    ELSE 'NON AUTORISE' END motif
                          FROM ldtb_contract_master m
                          JOIN sttm_customer c ON c.customer_no = m.counterparty
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (NVL(TRIM(c.frozen), 'N') = 'Y'
                                OR NVL(TRIM(c.deceased), 'N') = 'Y'
                                OR NVL(TRIM(c.whereabouts_unknown), 'N') = 'Y'
                                OR NVL(TRIM(c.record_stat), 'O') <> 'O'
                                OR NVL(TRIM(c.auth_stat), 'A') <> 'A')
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, r.motif);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        print_sub('Inventaire des contreparties du portefeuille (information)');
        po('  Le portefeuille n''est porte que par une poignee d''emetteurs souverains.');
        po('  Le tableau les recense avec leur typage, leur rattachement KYC et leur');
        po('  niveau de risque. La diligence sur les tiers eux-memes releve de la revue');
        po('  LCB-FT (audit_aml_cft.sql) et n''est pas comptee ici comme une anomalie de');
        po('  transaction : un manquement porterait sur quelques tiers, pas sur les');
        po('  centaines de contrats qu''ils portent.');
        tbl_line('4,14,32,8,8,8,16,10,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 14) || '|' || fpad('CONTREPARTIE', 32) || '|'
            || fpad('TYPE', 8) || '|' || fpad('CAT.', 8) || '|' || fpad('PAYS', 8) || '|'
            || fpad('REFERENCE KYC', 16) || '|' || fpad('RISQUE', 10) || '|'
            || fpadl('NB CONTRATS', 12) || '|' || fpadl('MONTANT LCY', 20) || '|');
        tbl_line('4,14,32,8,8,8,16,10,12,20');
        v_row := 0;
        FOR r IN (SELECT c.customer_no, c.customer_name1, c.customer_type, c.customer_category,
                         c.country, c.kyc_ref_no,
                         (SELECT MAX(k.risk_level) FROM sttm_kyc_master k
                           WHERE k.kyc_ref_no = c.kyc_ref_no) rl,
                         COUNT(*) nb, SUM(m.lcy_amount) mt
                    FROM ldtb_contract_master m
                    JOIN sttm_customer c ON c.customer_no = m.counterparty
                   WHERE m.module = k_mod
                     AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                     AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                          WHERE v.contract_ref_no = m.contract_ref_no)
                   GROUP BY c.customer_no, c.customer_name1, c.customer_type,
                            c.customer_category, c.country, c.kyc_ref_no
                   ORDER BY 9 DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.customer_no, 14) || '|'
                || fpad(r.customer_name1, 32) || '|' || fpad(r.customer_type, 8) || '|'
                || fpad(r.customer_category, 8) || '|' || fpad(r.country, 8) || '|'
                || fpad(NVL(r.kyc_ref_no, '(absent)'), 16) || '|' || fpad(NVL(r.rl, '-'), 10) || '|'
                || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.mt), 20) || '|');
        END LOOP;
        tbl_line('4,14,32,8,8,8,16,10,12,20');
        -- -----------------------------------------------------
        print_sub('Repartition des operations par nature de contrepartie (information)');
        po('  Sur ce portefeuille les contreparties sont des Etats (CUSTOMER_CATEGORY');
        po('  = GOVT), ce qui est la nature attendue d''un porteur de titres souverains.');
        po('  Le typage n''est donc pas teste comme une anomalie : il est restitue ici');
        po('  pour que la composition du risque de contrepartie soit visible.');
        tbl_line('4,14,10,14,34,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('TYPE', 14) || '|' || fpad('CAT.', 10) || '|'
            || fpad('PAYS', 14) || '|' || fpad('CONTREPARTIE', 34) || '|' || fpadl('NB', 12) || '|'
            || fpadl('MONTANT LCY', 20) || '|');
        tbl_line('4,14,10,14,34,12,20');
        v_row := 0;
        FOR r IN (SELECT c.customer_type, c.customer_category, c.country, c.customer_name1,
                         COUNT(*) nb, SUM(m.lcy_amount) mt
                    FROM ldtb_contract_master m
                    JOIN sttm_customer c ON c.customer_no = m.counterparty
                   WHERE m.module = k_mod
                     AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                     AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                          WHERE v.contract_ref_no = m.contract_ref_no)
                   GROUP BY c.customer_type, c.customer_category, c.country, c.customer_name1
                   ORDER BY 6 DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.customer_type, 14) || '|'
                || fpad(r.customer_category, 10) || '|' || fpad(r.country, 14) || '|'
                || fpad(r.customer_name1, 34) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|');
        END LOOP;
        tbl_line('4,14,10,14,34,12,20');

        -- -----------------------------------------------------
        p_test('MM-107', 'Produit absent du referentiel ou du parametrage');
        p_obj('tout produit utilise doit exister dans CSTM_PRODUCT et etre parametre');
        po('             dans LDTM_PRODUCT_MASTER.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (NOT EXISTS (SELECT 1 FROM cstm_product p
                             WHERE p.product_code = m.product AND p.module = m.module)
                OR NOT EXISTS (SELECT 1 FROM ldtm_product_master l WHERE l.product = m.product));
        p_verdict('MM-107', 'Produit absent du referentiel ou du parametrage', v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-108', 'Produit ferme ou non autorise utilise');
        p_obj('un produit dont RECORD_STAT = C (ferme) ou AUTH_STAT <> A ne devrait');
        po('             plus porter d''operations nouvelles.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
          JOIN cstm_product p ON p.product_code = m.product AND p.module = m.module
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (NVL(TRIM(p.record_stat), 'O') <> 'O' OR NVL(TRIM(p.auth_stat), 'A') <> 'A'
                OR (p.product_end_date IS NOT NULL AND m.booking_date > p.product_end_date));
        p_verdict('MM-108', 'Produit ferme ou non autorise utilise', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('ETAT DU PRODUIT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               'stat ' || p.record_stat || ' auth ' || p.auth_stat etat
                          FROM ldtb_contract_master m
                          JOIN cstm_product p ON p.product_code = m.product AND p.module = m.module
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (NVL(TRIM(p.record_stat), 'O') <> 'O' OR NVL(TRIM(p.auth_stat), 'A') <> 'A'
                                OR (p.product_end_date IS NOT NULL AND m.booking_date > p.product_end_date))
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, r.etat);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-109', 'Structure de la reference de contrat');
        p_obj('la reference FLEXCUBE se lit 3 caracteres d''agence, 4 de produit,');
        po('             2 d''annee, 3 de jour julien et 4 de sequence, soit 16 caracteres.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (LENGTH(m.contract_ref_no) <> 16
                OR SUBSTR(m.contract_ref_no, 1, 3) <> m.branch
                OR SUBSTR(m.contract_ref_no, 4, 4) <> m.product);
        p_verdict('MM-109', 'Reference de contrat non conforme a la nomenclature', v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MM-110', 'Devise du contrat differente de la devise de reglement');
        p_obj('une operation libellee dans une devise reglee dans une autre expose la');
        po('             banque a un risque de change non couvert.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(TRIM(m.dflt_settle_ccy), 'X') <> NVL(TRIM(m.currency), 'Y');
        p_verdict('MM-110', 'Devise du contrat differente de la devise de reglement', v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MM-111', 'Contrat sans compte de reglement par defaut');
        p_obj('sans compte de reglement, le denouement de l''operation ne peut pas');
        po('             etre trace automatiquement.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND TRIM(m.dflt_settle_ac) IS NULL;
        p_verdict('MM-111', 'Contrat sans compte de reglement par defaut', v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        print_sub('MM-111 bis. Comptes de reglement utilises');
        tbl_line('4,20,40,10,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE', 20) || '|' || fpad('LIBELLE', 40) || '|'
            || fpad('DEVISE', 10) || '|' || fpadl('NB CONTRATS', 12) || '|' || fpadl('MONTANT LCY', 20) || '|');
        tbl_line('4,20,40,10,12,20');
        v_row := 0;
        FOR r IN (SELECT m.dflt_settle_ac ac,
                         (SELECT MAX(a.ac_gl_desc) FROM sttb_account a WHERE a.ac_gl_no = m.dflt_settle_ac) lib,
                         MAX(m.dflt_settle_ccy) ccy, COUNT(*) nb, SUM(m.lcy_amount) mt
                    FROM ldtb_contract_master m
                   WHERE m.module = k_mod
                     AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                     AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                          WHERE v.contract_ref_no = m.contract_ref_no)
                   GROUP BY m.dflt_settle_ac
                   ORDER BY 5 DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac, 20) || '|' || fpad(r.lib, 40) || '|'
                || fpad(r.ccy, 10) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.mt), 20) || '|');
        END LOOP;
        tbl_line('4,20,40,10,12,20');

        -- -----------------------------------------------------
        p_test('MM-112', 'Colonnes de tracabilite de la negociation et de la confirmation');
        p_obj('une operation de marche doit garder la trace de qui l''a negociee, par');
        po('             quel canal, sur quelle ligne de contrepartie, avec quelle');
        po('             justification, et de sa confirmation par la contrepartie. Le test');
        po('             porte sur le PARAMETRAGE : il compte les colonnes de tracabilite');
        po('             entierement vides sur le portefeuille, et non les contrats un a un.');
        SELECT COUNT(*) INTO v_tot
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        tbl_line('4,16,44,16,14,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('COLONNE', 16) || '|' || fpad('CE QU''ELLE TRACE', 44) || '|'
            || fpadl('RENSEIGNEE', 16) || '|' || fpadl('TAUX', 14) || '|' || fpadl('ETAT', 18) || '|');
        tbl_line('4,16,44,16,14,18');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT 'DEALER' col, 'operateur de marche ayant negocie l''operation' lib, 1 ord FROM DUAL UNION ALL
                  SELECT 'DEALING_METHOD', 'canal de negociation (telephone, plateforme...)', 2 FROM DUAL UNION ALL
                  SELECT 'CREDIT_LINE',    'ligne de credit de contrepartie consommee',       3 FROM DUAL UNION ALL
                  SELECT 'REMARKS',        'justification saisie par l''operateur',           4 FROM DUAL UNION ALL
                  SELECT 'CPARTY_CONFIRM_STATUS', 'confirmation recue de la contrepartie',    5 FROM DUAL
                  ORDER BY 3) LOOP
            SELECT COUNT(*) INTO v_cnt2
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
               AND ((r.ord = 1 AND TRIM(m.dealer) IS NOT NULL)
                 OR (r.ord = 2 AND TRIM(m.dealing_method) IS NOT NULL)
                 OR (r.ord = 3 AND TRIM(m.credit_line) IS NOT NULL)
                 OR (r.ord = 4 AND TRIM(m.remarks) IS NOT NULL)
                 OR (r.ord = 5 AND TRIM(m.cparty_confirm_status) IS NOT NULL));
            v_row := v_row + 1;
            IF v_cnt2 = 0 THEN
                v_cnt := v_cnt + 1;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.col, 16) || '|' || fpad(r.lib, 44) || '|'
                || fpadl(fnum(v_cnt2), 16) || '|' || fpadl(fpct(v_cnt2, v_tot), 14) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'JAMAIS RENSEIGNEE'
                              WHEN v_cnt2 < v_tot THEN 'PARTIELLE'
                              ELSE 'COMPLETE' END, 18) || '|');
        END LOOP;
        tbl_line('4,16,44,16,14,18');
        print_kv('Contrats du perimetre', fnum(v_tot));
        p_verdict('MM-112', 'Colonnes de tracabilite de la negociation jamais renseignees',
                  v_cnt, 5, NULL, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-113', 'Confirmation de la contrepartie effectivement enregistree');
        p_obj('au dela du statut de confirmation, un message de confirmation doit');
        po('             exister dans LDTB_CONTRACT_SWIFT_MESSAGE. Contrairement au statut,');
        po('             cette colonne est alimentee : le test est donc discriminant.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_swift_message s
                            WHERE s.contract_ref_no = m.contract_ref_no
                              AND NVL(TRIM(s.confirmation_indicator), 'N') = 'Y');
        p_verdict('MM-113', 'Contrat sans message de confirmation enregistre', v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        -- -----------------------------------------------------
        p_test('MM-114', 'Contrats orphelins de leurs tables satellites');
        p_obj('un contrat sans preference, sans encours, sans composante d''interet ou');
        po('             sans echeancier est un contrat incomplet dans le systeme.');
        tbl_line('4,44,12,12,20,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('TABLE SATELLITE ATTENDUE', 44) || '|'
            || fpadl('CONTRATS OK', 12) || '|' || fpadl('MANQUANTS', 12) || '|'
            || fpadl('MONTANT MANQUANT', 20) || '|' || fpadl('VERDICT', 14) || '|');
        tbl_line('4,44,12,12,20,14');
        v_row := 0;
        FOR r IN (
            SELECT 'LDTB_CONTRACT_PREFERENCE (preferences)' lib, 1 ord FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_BALANCE (encours)',            2 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_DETAILS (composantes)',   3 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_CALC (calcul interets)',  4 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SCHEDULES (echeancier)',       5 FROM DUAL
        ) LOOP
            v_cnt := 0; v_mt := 0;
            CASE r.ord
              WHEN 1 THEN
                SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NOT EXISTS (SELECT 1 FROM ldtb_contract_preference t
                                    WHERE t.contract_ref_no = m.contract_ref_no);
              WHEN 2 THEN
                SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NOT EXISTS (SELECT 1 FROM ldtb_contract_balance t
                                    WHERE t.contract_ref_no = m.contract_ref_no);
              WHEN 3 THEN
                SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NOT EXISTS (SELECT 1 FROM ldtb_contract_iccf_details t
                                    WHERE t.contract_ref_no = m.contract_ref_no);
              WHEN 4 THEN
                SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NOT EXISTS (SELECT 1 FROM ldtb_contract_iccf_calc t
                                    WHERE t.contract_ref_no = m.contract_ref_no);
              ELSE
                SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NOT EXISTS (SELECT 1 FROM ldtb_contract_schedules t
                                    WHERE t.contract_ref_no = m.contract_ref_no);
            END CASE;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 44) || '|'
                || fpadl(fnum(v_nb_ctr - v_cnt), 12) || '|' || fpadl(fnum(v_cnt), 12) || '|'
                || fpadl(fmio(v_mt), 20) || '|'
                || fpadl(CASE WHEN v_cnt = 0 THEN 'OK' ELSE 'ANOMALIE' END, 14) || '|');
            IF r.ord = 1 THEN v_tot2 := v_cnt; ELSE v_tot2 := v_tot2 + v_cnt; END IF;
        END LOOP;
        tbl_line('4,44,12,12,20,14');
        p_verdict('MM-114', 'Rattachements manquants a une table satellite (cumul des 5 tables)',
                  v_tot2, NULL, NULL, 'ELEVE');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 10. MM-2xx : DATES, DUREES ET PARAMETRAGE
    -- =========================================================
    print_section('10. CONTROLES MM-2xx : DATES, DUREES ET PARAMETRAGE PRODUIT');
    BEGIN

        -- -----------------------------------------------------
        p_test('MM-201', 'Echeance anterieure ou egale a la date de valeur');
        p_obj('une operation dont l''echeance precede la prise d''effet est impossible.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.maturity_date <= m.value_date;
        p_verdict('MM-201', 'Echeance anterieure ou egale a la date de valeur', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('DUREE (JOURS)');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND m.maturity_date <= m.value_date
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      fnum(r.maturity_date - r.value_date) || ' j');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-202', 'Operation saisie avec une date de valeur retroactive');
        p_obj('une date de valeur anterieure a la date de saisie fait courir les');
        po('             interets avant l''enregistrement comptable. Un decalage de un a deux');
        po('             jours correspond au delai normal de reglement ; seule la retroactivite');
        po('             au dela de ' || TO_CHAR(k_retro_j) || ' jours est retenue comme anomalie. La distribution');
        po('             complete, tolerance comprise, est donnee juste apres.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND TRUNC(m.booking_date) - TRUNC(m.value_date) > k_retro_j;
        p_verdict('MM-202', 'Date de valeur retroactive de plus de ' || TO_CHAR(k_retro_j) || ' jours',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        print_sub('MM-202 bis. Amplitude de la retroactivite');
        tbl_line('4,30,12,20,12,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('RETARD DE SAISIE', 30) || '|' || fpadl('NB', 12) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('% NB', 12) || '|' || fpadl('MAX (JOURS)', 14) || '|');
        tbl_line('4,30,12,20,12,14');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt, MAX(d) mx
              FROM (SELECT CASE
                             WHEN m.booking_date - m.value_date <= 0   THEN '0. aucune retroactivite'
                             WHEN m.booking_date - m.value_date <= 1   THEN '1. 1 jour'
                             WHEN m.booking_date - m.value_date <= 5   THEN '2. 2 a 5 jours'
                             WHEN m.booking_date - m.value_date <= 30  THEN '3. 6 a 30 jours'
                             WHEN m.booking_date - m.value_date <= 90  THEN '4. 31 a 90 jours'
                             ELSE                                           '5. plus de 90 jours'
                           END tr,
                           m.lcy_amount mt, m.booking_date - m.value_date d
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 30) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|'
                || fpadl(fnum(r.mx), 14) || '|');
        END LOOP;
        tbl_line('4,30,12,20,12,14');

        IF v_cnt > 0 THEN
            print_sub('MM-202 ter. Operations les plus retroactives');
            d_head('RETARD (JOURS)');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.booking_date - m.value_date ret
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND m.value_date < m.booking_date
                         ORDER BY m.booking_date - m.value_date DESC, m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      fnum(r.ret) || ' j');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-203', 'TENOR declare different de la duree calculee');
        p_obj('le TENOR porte par le contrat doit egaler MATURITY_DATE moins VALUE_DATE.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.tenor, -1) <> (m.maturity_date - m.value_date);
        p_verdict('MM-203', 'TENOR declare different de la duree calculee', v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            d_head('TENOR / CALCULE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.tenor, m.maturity_date - m.value_date calc
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.tenor, -1) <> (m.maturity_date - m.value_date)
                         ORDER BY ABS(NVL(m.tenor, 0) - (m.maturity_date - m.value_date)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      fnum(r.tenor) || ' / ' || fnum(r.calc));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-204', 'Duree hors des bornes autorisees par le produit');
        p_obj('la duree doit rester comprise entre MIN_TENOR et MAX_TENOR du');
        po('             parametrage LDTM_PRODUCT_MASTER.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
          JOIN ldtm_product_master p ON p.product = m.product
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND ((p.min_tenor IS NOT NULL AND (m.maturity_date - m.value_date) < p.min_tenor)
                OR (p.max_tenor IS NOT NULL AND (m.maturity_date - m.value_date) > p.max_tenor));
        p_verdict('MM-204', 'Duree hors des bornes autorisees par le produit', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('DUREE / BORNES');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.maturity_date - m.value_date dur, p.min_tenor, p.max_tenor
                          FROM ldtb_contract_master m
                          JOIN ldtm_product_master p ON p.product = m.product
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND ((p.min_tenor IS NOT NULL AND (m.maturity_date - m.value_date) < p.min_tenor)
                                OR (p.max_tenor IS NOT NULL AND (m.maturity_date - m.value_date) > p.max_tenor))
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      fnum(r.dur) || ' hors ' || fnum(r.min_tenor) || '-' || fnum(r.max_tenor));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-205', 'Operation enregistree un samedi ou un dimanche');
        p_obj('une saisie hors jour ouvre peut signaler une regularisation manuelle');
        po('             ou un traitement par lot non maitrise.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (TRUNC(m.booking_date) - TRUNC(m.booking_date, 'IW') + 1) IN (6, 7);
        p_verdict('MM-205', 'Operation enregistree un samedi ou un dimanche', v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            d_head('JOUR DE BOOKING');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               TRUNC(m.booking_date) - TRUNC(m.booking_date, 'IW') + 1 jr
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (TRUNC(m.booking_date) - TRUNC(m.booking_date, 'IW') + 1) IN (6, 7)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      CASE r.jr WHEN 6 THEN 'SAMEDI ' ELSE 'DIMANCHE ' END || fdt(r.booking_date));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-206', 'Date encodee dans la reference incoherente avec la date de booking');
        p_obj('les positions 8 a 12 de la reference portent l''annee et le jour julien');
        po('             de creation. Une divergence signale une reference forcee ou rejouee.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND LENGTH(m.contract_ref_no) = 16
           AND SUBSTR(m.contract_ref_no, 8, 5) <> TO_CHAR(m.booking_date, 'YYDDD');
        p_verdict('MM-206', 'Date de la reference incoherente avec la date de booking',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            d_head('REF / BOOKING');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               SUBSTR(m.contract_ref_no, 8, 5) seg,
                               TO_CHAR(m.booking_date, 'YYDDD') att
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND LENGTH(m.contract_ref_no) = 16
                           AND SUBSTR(m.contract_ref_no, 8, 5) <> TO_CHAR(m.booking_date, 'YYDDD')
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      r.seg || ' vs ' || r.att);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-207', 'Echeance systeme differente de l''echeance saisie par l''utilisateur');
        p_obj('un ecart entre MATURITY_DATE et USER_INPUT_MATURITY_DATE traduit un');
        po('             decalage d''echeance applique par le systeme (jour ferie, prorogation).');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.user_input_maturity_date IS NOT NULL
           AND m.user_input_maturity_date <> m.maturity_date;
        p_verdict('MM-207', 'Echeance systeme differente de l''echeance saisie', v_cnt, v_nb_ctr, v_mt, 'FAIBLE');

        -- -----------------------------------------------------
        p_test('MM-208', 'Date de negociation differente de la date de valeur');
        p_obj('un ecart entre TRADE_DATE et VALUE_DATE correspond a un decalage de');
        po('             reglement. Au dela de deux jours ouvres il doit etre justifie.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.trade_date IS NOT NULL
           AND ABS(m.trade_date - m.value_date) > 2;
        p_verdict('MM-208', 'Ecart de plus de 2 jours entre negociation et date de valeur',
                  v_cnt, v_nb_ctr, v_mt, 'FAIBLE');

        -- -----------------------------------------------------
        p_test('MM-210', 'Montant du contrat nul ou negatif');
        p_obj('un contrat de marche monetaire porte necessairement un nominal');
        po('             strictement positif.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.lcy_amount, 0) <= 0;
        p_verdict('MM-210', 'Montant du contrat nul ou negatif', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('MONTANT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.lcy_amount, 0) <= 0
                         ORDER BY m.lcy_amount
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      famt(r.lcy_amount));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        print_sub('Operations au-dessus du seuil de signification (perimetre d''echantillonnage)');
        po('  Ce n''est pas un controle mais la delimitation de la population a examiner');
        po('  en priorite sur piece. Elle n''entre donc pas dans le decompte des tests.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.lcy_amount >= k_mt_signif;
        print_kv('Seuil applique', famt(k_mt_signif) || ' XAF');
        print_kv('Couverture en montant du perimetre', fpct(v_mt, v_mt_ctr));
        print_kv('Operations au-dessus du seuil', fnum(v_cnt) || '   ' || fpct(v_cnt, v_nb_ctr));
        print_kv('Montant cumule de ces operations', fmio(v_mt));

        -- -----------------------------------------------------
        print_sub('Granularite des nominaux (information)');
        po('  Les titres souverains sont souscrits par blocs ronds : la rondeur du');
        po('  nominal est la norme et non un signal. Le tableau est conserve pour');
        po('  eclairer la nature du portefeuille, sans etre compte comme un controle.');
        tbl_line('4,34,12,12,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('GRANULARITE DU NOMINAL', 34) || '|' || fpadl('NB', 12) || '|'
            || fpadl('% NB', 12) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MT', 12) || '|');
        tbl_line('4,34,12,12,20,12');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt
              FROM (SELECT CASE
                             WHEN MOD(m.lcy_amount, 1000000000) = 0 THEN '1. multiple du milliard'
                             WHEN MOD(m.lcy_amount,  100000000) = 0 THEN '2. multiple de 100 millions'
                             WHEN MOD(m.lcy_amount,   10000000) = 0 THEN '3. multiple de 10 millions'
                             WHEN MOD(m.lcy_amount,    1000000) = 0 THEN '4. multiple du million'
                             WHEN MOD(m.lcy_amount,       1000) = 0 THEN '5. multiple du millier'
                             ELSE                                       '6. montant non rond'
                           END tr, m.lcy_amount mt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND NVL(m.lcy_amount, 0) > 0
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 34) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_mt_ctr), 12) || '|');
        END LOOP;
        tbl_line('4,34,12,12,20,12');

        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.lcy_amount, 0) > 0
           AND MOD(m.lcy_amount, 1000000) = 0;
        print_kv('Nominaux multiples du million', fnum(v_cnt) || '   ' || fpct(v_cnt, v_nb_ctr));

        -- -----------------------------------------------------
        p_test('MM-213', 'Coherence interne des colonnes de montant du contrat');
        p_obj('AMOUNT, LCY_AMOUNT et MAX_DRAWDOWN_AMOUNT decrivent le meme nominal.');
        po('             Toute divergence signale une reprise de donnees ou un amendement partiel.');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(m.amount, 0) - NVL(m.max_drawdown_amount, 0))), 0)
          INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.max_drawdown_amount IS NOT NULL
           AND ABS(NVL(m.amount, 0) - NVL(m.max_drawdown_amount, 0)) > k_tol_abs;
        p_verdict('MM-213', 'Nominal different du montant maximal de tirage', v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        SELECT COUNT(*), NVL(SUM(ABS(NVL(m.amount, 0) - NVL(m.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND ABS(NVL(m.amount, 0) - NVL(m.lcy_amount, 0)) > k_tol_abs;
        p_verdict('MM-213b', 'Montant en devise different du montant en monnaie locale',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,7,10,28,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('DEVISE', 10) || '|' || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('AMOUNT', 20) || '|'
                || fpadl('LCY_AMOUNT', 20) || '|' || fpadl('ECART', 20) || '|');
            tbl_line('4,20,12,12,7,10,28,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT m.contract_ref_no ref, m.product, m.currency ccy, m.amount, m.lcy_amount,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) etat
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND ABS(NVL(m.amount, 0) - NVL(m.lcy_amount, 0)) > k_tol_abs
                         ORDER BY ABS(NVL(m.amount, 0) - NVL(m.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.ccy, 10) || '|' || fpad(r.etat, 28) || '|' || fpadl(famt(r.amount), 20) || '|'
                    || fpadl(famt(r.lcy_amount), 20) || '|'
                    || fpadl(famt(NVL(r.amount, 0) - NVL(r.lcy_amount, 0)), 20) || '|');
            END LOOP;
            tbl_line('4,20,12,12,7,10,28,20,20,20');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 3 : CALCUL DES INTERETS ET PROVISIONS');
    -- ########################################################################

    -- =========================================================
    -- 11. MM-3xx : CALCUL DES INTERETS
    -- =========================================================
    print_section('11. CONTROLES MM-3xx : CALCUL DES INTERETS ET DES PROVISIONS');
    BEGIN
        po('  MECANIQUE DU CALCUL DANS FLEXCUBE');
        po('    LDTB_CONTRACT_MASTER      MAIN_COMP_RATE = taux du contrat');
        po('                              MAIN_COMP_AMOUNT = interets totaux attendus');
        po('    LDTB_CONTRACT_ICCF_CALC   une ligne par periode de calcul, avec la base');
        po('                              (BASIS_AMOUNT), le taux, le nombre de jours');
        po('                              (NO_OF_DAYS), la convention (ICCF_CALC_METHOD)');
        po('                              et le montant obtenu (CALCULATED_AMOUNT)');
        po('    LDTB_CONTRACT_ICCF_DETAILS provisions cumulees par composante');
        po('    LDTB_CONTRACT_ACCRUAL_HISTORY historique detaille des provisions');
        po('    LDTB_CONTRACT_SWIFT_MESSAGE  interets annonces a la contrepartie');
        po('');
        po('  FORMULE DE RECALCUL RETENUE');
        po('    interets = base x taux x nombre de jours / (100 x denominateur)');
        po('    le denominateur depend de la convention ICCF_CALC_METHOD (360, 365 ou');
        po('    nombre reel de jours de l''annee).');

        -- -----------------------------------------------------
        print_sub('11.1 Conventions de calcul rencontrees');
        tbl_line('4,10,24,14,14,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('METHODE', 10) || '|' || fpad('CONVENTION', 24) || '|'
            || fpadl('NB LIGNES', 14) || '|' || fpadl('NB CONTRATS', 14) || '|'
            || fpadl('BASE CUMULEE', 20) || '|' || fpadl('INTERETS CALCULES', 20) || '|');
        tbl_line('4,10,24,14,14,20,20');
        v_row := 0;
        FOR r IN (
            SELECT c.iccf_calc_method meth, COUNT(*) nb,
                   COUNT(DISTINCT c.contract_ref_no) nbc,
                   SUM(c.basis_amount) base, SUM(c.calculated_amount) itc
              FROM ldtb_contract_iccf_calc c
             WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = c.contract_ref_no
                              AND m.module = k_mod
                              AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
             GROUP BY c.iccf_calc_method
             ORDER BY 2 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.meth, 10) || '|'
                || fpad(f_meth_lib(r.meth), 24) || '|' || fpadl(fnum(r.nb), 14) || '|'
                || fpadl(fnum(r.nbc), 14) || '|' || fpadl(fmio(r.base), 20) || '|'
                || fpadl(fmio(r.itc), 20) || '|');
        END LOOP;
        tbl_line('4,10,24,14,14,20,20');

        -- -----------------------------------------------------
        p_test('MM-301', 'Recalcul independant des interets, ligne de calcul par ligne de calcul');
        p_obj('recalculer chaque ligne de LDTB_CONTRACT_ICCF_CALC et confronter le');
        po('             resultat au montant enregistre par le systeme.');
        print_kv('Tolerance retenue', famt(k_tol_abs) || ' XAF ou ' || TO_CHAR(k_tol_pct) || ' %');

        print_sub('MM-301 a. Convention qui reconcilie effectivement le montant enregistre');
        SELECT COUNT(*),
               SUM(CASE WHEN ok_ret = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN ok_360 = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN ok_365 = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN ok_act = 1 THEN 1 ELSE 0 END),
               SUM(CASE WHEN ok_360 + ok_365 + ok_act = 0 THEN 1 ELSE 0 END)
          INTO v_tot, v_cnt, v_cnt2, v_cnt3, v_row, v_tot2
          FROM (
            SELECT CASE WHEN ABS(y.calc - y.th)    <= GREATEST(k_tol_abs, ABS(y.th)    * k_tol_pct / 100) THEN 1 ELSE 0 END ok_ret,
                   CASE WHEN ABS(y.calc - y.th360) <= GREATEST(k_tol_abs, ABS(y.th360) * k_tol_pct / 100) THEN 1 ELSE 0 END ok_360,
                   CASE WHEN ABS(y.calc - y.th365) <= GREATEST(k_tol_abs, ABS(y.th365) * k_tol_pct / 100) THEN 1 ELSE 0 END ok_365,
                   CASE WHEN ABS(y.calc - y.thact) <= GREATEST(k_tol_abs, ABS(y.thact) * k_tol_pct / 100) THEN 1 ELSE 0 END ok_act
              FROM (
                SELECT x.calc,
                       ROUND(x.basis * x.taux * x.nd / (100 * x.den), 2) th,
                       ROUND(x.basis * x.taux * x.nd / 36000, 2)         th360,
                       ROUND(x.basis * x.taux * x.nd / 36500, 2)         th365,
                       ROUND(x.basis * x.taux * x.nd / (100 * x.dact), 2) thact
                  FROM (
                    SELECT c.basis_amount basis, c.rate taux, NVL(c.calculated_amount, 0) calc,
                           CASE WHEN REGEXP_LIKE(TRIM(c.no_of_days), '^[0-9]+$')
                                THEN TO_NUMBER(TRIM(c.no_of_days)) END nd,
                           CASE WHEN c.iccf_calc_method IN ('1', '2', '3') THEN 360
                                WHEN c.iccf_calc_method IN ('4', '5', '6') THEN 365
                                ELSE ADD_MONTHS(TRUNC(c.start_date, 'YYYY'), 12)
                                     - TRUNC(c.start_date, 'YYYY')
                           END den,
                           ADD_MONTHS(TRUNC(c.start_date, 'YYYY'), 12)
                                     - TRUNC(c.start_date, 'YYYY') dact
                      FROM ldtb_contract_iccf_calc c
                     WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                    WHERE m.contract_ref_no = c.contract_ref_no
                                      AND m.module = k_mod
                                      AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                  ) x
                 WHERE x.basis > 0 AND x.nd IS NOT NULL AND x.taux IS NOT NULL
              ) y
          );
        tbl_line('4,44,14,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONVENTION TESTEE', 44) || '|'
            || fpadl('LIGNES OK', 14) || '|' || fpadl('% LIGNES', 14) || '|');
        tbl_line('4,44,14,14');
        po('  |' || fpadl('1', 4) || '|' || fpad('Convention declaree par ICCF_CALC_METHOD', 44) || '|'
            || fpadl(fnum(v_cnt), 14) || '|' || fpadl(fpct(v_cnt, v_tot), 14) || '|');
        po('  |' || fpadl('2', 4) || '|' || fpad('Base 360 (Actual/360)', 44) || '|'
            || fpadl(fnum(v_cnt2), 14) || '|' || fpadl(fpct(v_cnt2, v_tot), 14) || '|');
        po('  |' || fpadl('3', 4) || '|' || fpad('Base 365 (Actual/365)', 44) || '|'
            || fpadl(fnum(v_cnt3), 14) || '|' || fpadl(fpct(v_cnt3, v_tot), 14) || '|');
        po('  |' || fpadl('4', 4) || '|' || fpad('Base annee reelle (Actual/Actual)', 44) || '|'
            || fpadl(fnum(v_row), 14) || '|' || fpadl(fpct(v_row, v_tot), 14) || '|');
        po('  |' || fpadl('5', 4) || '|' || fpad('AUCUNE convention ne reconcilie', 44) || '|'
            || fpadl(fnum(v_tot2), 14) || '|' || fpadl(fpct(v_tot2, v_tot), 14) || '|');
        tbl_line('4,44,14,14');
        print_kv('Lignes de calcul testees (base et jours renseignes)', fnum(v_tot));

        p_verdict('MM-301', 'Lignes d''interets qu''aucune convention de calcul ne reconcilie',
                  v_tot2, v_tot, NULL, 'CRITIQUE');

        IF v_tot2 > 0 THEN
            print_sub('MM-301 b. Lignes de calcul non reconciliees (les ' || TO_CHAR(k_top) || ' plus significatives)');
            tbl_line('4,20,12,12,9,12,12,20,9,8,7,18,18,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpad('DEBUT', 12) || '|' || fpad('FIN', 12) || '|' || fpadl('BASE', 20) || '|'
                || fpadl('TAUX', 9) || '|' || fpadl('JOURS', 8) || '|' || fpad('METH', 7) || '|'
                || fpadl('MONTANT SYSTEME', 18) || '|' || fpadl('RECALCUL', 18) || '|'
                || fpadl('ECART', 16) || '|');
            tbl_line('4,20,12,12,9,12,12,20,9,8,7,18,18,16');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT y.* FROM (
                    SELECT x.ref, x.comp, x.sd, x.ed, x.basis, x.taux, x.nd, x.meth, x.calc,
                           ROUND(x.basis * x.taux * x.nd / (100 * x.den), 2) th,
                           ROUND(x.basis * x.taux * x.nd / 36000, 2)         th360,
                           ROUND(x.basis * x.taux * x.nd / 36500, 2)         th365,
                           ROUND(x.basis * x.taux * x.nd / (100 * x.dact), 2) thact
                      FROM (
                        SELECT c.contract_ref_no ref, c.component comp, c.start_date sd, c.end_date ed,
                               c.basis_amount basis, c.rate taux, NVL(c.calculated_amount, 0) calc,
                               c.iccf_calc_method meth,
                               CASE WHEN REGEXP_LIKE(TRIM(c.no_of_days), '^[0-9]+$')
                                    THEN TO_NUMBER(TRIM(c.no_of_days)) END nd,
                               CASE WHEN c.iccf_calc_method IN ('1', '2', '3') THEN 360
                                    WHEN c.iccf_calc_method IN ('4', '5', '6') THEN 365
                                    ELSE ADD_MONTHS(TRUNC(c.start_date, 'YYYY'), 12)
                                         - TRUNC(c.start_date, 'YYYY')
                               END den,
                               ADD_MONTHS(TRUNC(c.start_date, 'YYYY'), 12)
                                         - TRUNC(c.start_date, 'YYYY') dact
                          FROM ldtb_contract_iccf_calc c
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = c.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                      ) x
                     WHERE x.basis > 0 AND x.nd IS NOT NULL AND x.taux IS NOT NULL
                ) y
                WHERE ABS(y.calc - y.th360) > GREATEST(k_tol_abs, ABS(y.th360) * k_tol_pct / 100)
                  AND ABS(y.calc - y.th365) > GREATEST(k_tol_abs, ABS(y.th365) * k_tol_pct / 100)
                  AND ABS(y.calc - y.thact) > GREATEST(k_tol_abs, ABS(y.thact) * k_tol_pct / 100)
                ORDER BY ABS(y.calc - y.th) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpad(fdt(r.sd), 12) || '|' || fpad(fdt(r.ed), 12) || '|' || fpadl(famt(r.basis), 20) || '|'
                    || fpadl(ftx(r.taux), 9) || '|' || fpadl(fnum(r.nd), 8) || '|' || fpad(r.meth, 7) || '|'
                    || fpadl(famt(r.calc), 18) || '|' || fpadl(famt(r.th), 18) || '|'
                    || fpadl(famt(r.calc - r.th), 16) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,12,20,9,8,7,18,18,16');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-302', 'Nombre de jours declare different du nombre de jours calendaires');
        p_obj('NO_OF_DAYS doit correspondre a END_DATE moins START_DATE de la periode');
        po('             de calcul. Un ecart fausse mecaniquement le montant des interets.');
        SELECT COUNT(*), NVL(SUM(ABS(ecart_int)), 0) INTO v_cnt, v_mt
          FROM (
            SELECT c.contract_ref_no,
                   CASE WHEN REGEXP_LIKE(TRIM(c.no_of_days), '^[0-9]+$')
                        THEN TO_NUMBER(TRIM(c.no_of_days)) END nd,
                   c.end_date - c.start_date ndc,
                   c.basis_amount * c.rate
                     * (NVL(CASE WHEN REGEXP_LIKE(TRIM(c.no_of_days), '^[0-9]+$')
                                 THEN TO_NUMBER(TRIM(c.no_of_days)) END, 0)
                        - (c.end_date - c.start_date)) / 36000 ecart_int
              FROM ldtb_contract_iccf_calc c
             WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = c.contract_ref_no
                              AND m.module = k_mod
                              AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
          )
         WHERE nd IS NOT NULL AND nd <> ndc;
        p_verdict('MM-302', 'Nombre de jours declare different du nombre de jours calendaires',
                  v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,9,12,12,10,10,20,9,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpad('DEBUT', 12) || '|' || fpad('FIN', 12) || '|' || fpadl('DECLARE', 10) || '|'
                || fpadl('CALENDR.', 10) || '|' || fpadl('BASE', 20) || '|' || fpadl('TAUX', 9) || '|'
                || fpadl('IMPACT INTERETS', 20) || '|');
            tbl_line('4,20,12,12,9,12,12,10,10,20,9,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT z.* FROM (
                    SELECT c.contract_ref_no ref, c.component comp, c.start_date sd, c.end_date ed,
                           c.basis_amount basis, c.rate taux,
                           CASE WHEN REGEXP_LIKE(TRIM(c.no_of_days), '^[0-9]+$')
                                THEN TO_NUMBER(TRIM(c.no_of_days)) END nd,
                           c.end_date - c.start_date ndc
                      FROM ldtb_contract_iccf_calc c
                     WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                    WHERE m.contract_ref_no = c.contract_ref_no
                                      AND m.module = k_mod
                                      AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                ) z
                WHERE z.nd IS NOT NULL AND z.nd <> z.ndc
                ORDER BY ABS(z.basis * z.taux * (z.nd - z.ndc) / 36000) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpad(fdt(r.sd), 12) || '|' || fpad(fdt(r.ed), 12) || '|' || fpadl(fnum(r.nd), 10) || '|'
                    || fpadl(fnum(r.ndc), 10) || '|' || fpadl(famt(r.basis), 20) || '|'
                    || fpadl(ftx(r.taux), 9) || '|'
                    || fpadl(famt(ROUND(r.basis * r.taux * (r.nd - r.ndc) / 36000, 2)), 20) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,12,10,10,20,9,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-303', 'Taux applique au calcul different du taux du contrat');
        p_obj('le taux porte par chaque ligne de calcul doit etre celui du contrat.');
        SELECT COUNT(*), COUNT(DISTINCT c.contract_ref_no) INTO v_cnt, v_cnt2
          FROM ldtb_contract_iccf_calc c
          JOIN ldtb_contract_master m ON m.contract_ref_no = c.contract_ref_no
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND c.rate IS NOT NULL
           AND ABS(NVL(c.rate, 0) - NVL(m.main_comp_rate, 0)) > 0.0001;
        p_verdict('MM-303', 'Taux applique au calcul different du taux du contrat',
                  v_cnt, NULL, NULL, 'ELEVE');
        IF v_cnt > 0 THEN
            print_kv('Contrats concernes', fnum(v_cnt2));
            tbl_line('4,20,12,12,9,12,12,20,12,12,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpad('DEBUT', 12) || '|' || fpad('FIN', 12) || '|' || fpadl('BASE', 20) || '|'
                || fpadl('TAUX CALCUL', 12) || '|' || fpadl('TAUX CONTRAT', 12) || '|'
                || fpadl('ECART (PTS)', 14) || '|');
            tbl_line('4,20,12,12,9,12,12,20,12,12,14');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.component comp, c.start_date sd, c.end_date ed,
                               c.basis_amount basis, c.rate tc, m.main_comp_rate tm
                          FROM ldtb_contract_iccf_calc c
                          JOIN ldtb_contract_master m ON m.contract_ref_no = c.contract_ref_no
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND c.rate IS NOT NULL
                           AND ABS(NVL(c.rate, 0) - NVL(m.main_comp_rate, 0)) > 0.0001
                         ORDER BY ABS(NVL(c.rate, 0) - NVL(m.main_comp_rate, 0)) DESC, c.basis_amount DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpad(fdt(r.sd), 12) || '|' || fpad(fdt(r.ed), 12) || '|' || fpadl(famt(r.basis), 20) || '|'
                    || fpadl(ftx(r.tc), 12) || '|' || fpadl(ftx(r.tm), 12) || '|'
                    || fpadl(TO_CHAR(ROUND(NVL(r.tc, 0) - NVL(r.tm, 0), 4)), 14) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,12,20,12,12,14');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-304', 'Base de calcul differente du nominal du contrat');
        p_obj('sur un placement in fine, la base des interets doit egaler le nominal.');
        po('             Les lignes de base nulle sont exclues : dans FLEXCUBE elles');
        po('             correspondent aux periodes de l''echeancier non encore courues.');
        SELECT COUNT(*), COUNT(DISTINCT c.contract_ref_no) INTO v_cnt, v_cnt2
          FROM ldtb_contract_iccf_calc c
          JOIN ldtb_contract_master m ON m.contract_ref_no = c.contract_ref_no
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(c.basis_amount, 0) > 0
           AND ABS(NVL(c.basis_amount, 0) - NVL(m.lcy_amount, 0)) > 1;
        p_verdict('MM-304', 'Base de calcul differente du nominal du contrat', v_cnt, NULL, NULL, 'ELEVE');
        IF v_cnt > 0 THEN
            print_kv('Contrats concernes', fnum(v_cnt2));
            tbl_line('4,20,12,12,9,12,12,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpad('DEBUT', 12) || '|' || fpad('FIN', 12) || '|' || fpadl('BASE DE CALCUL', 20) || '|'
                || fpadl('NOMINAL CONTRAT', 20) || '|' || fpadl('ECART', 20) || '|');
            tbl_line('4,20,12,12,9,12,12,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT c.contract_ref_no ref, c.component comp, c.start_date sd, c.end_date ed,
                               c.basis_amount basis, m.lcy_amount nom
                          FROM ldtb_contract_iccf_calc c
                          JOIN ldtb_contract_master m ON m.contract_ref_no = c.contract_ref_no
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(c.basis_amount, 0) > 0
                           AND ABS(NVL(c.basis_amount, 0) - NVL(m.lcy_amount, 0)) > 1
                         ORDER BY ABS(NVL(c.basis_amount, 0) - NVL(m.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpad(fdt(r.sd), 12) || '|' || fpad(fdt(r.ed), 12) || '|' || fpadl(famt(r.basis), 20) || '|'
                    || fpadl(famt(r.nom), 20) || '|' || fpadl(famt(r.basis - r.nom), 20) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,12,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-307', 'Interets annonces a la contrepartie differents des interets du contrat');
        p_obj('confronter TOTAL_INTEREST_AMOUNT du message de confirmation au montant');
        po('             d''interets porte par le contrat.');
        SELECT COUNT(*), NVL(SUM(ABS(ecart)), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.contract_ref_no,
                   NVL(m.main_comp_amount, 0)
                     - NVL((SELECT MAX(s.total_interest_amount) FROM ldtb_contract_swift_message s
                             WHERE s.contract_ref_no = m.contract_ref_no
                               AND s.total_interest_amount IS NOT NULL), 0) ecart,
                   (SELECT COUNT(*) FROM ldtb_contract_swift_message s
                     WHERE s.contract_ref_no = m.contract_ref_no
                       AND s.total_interest_amount IS NOT NULL) nb_sw
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE nb_sw > 0 AND ABS(ecart) > k_tol_abs;
        p_verdict('MM-307', 'Interets confirmes differents des interets du contrat',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-308', 'Taux hors des bornes jugees normales');
        p_obj('reperer les taux nuls, non renseignes ou situes hors de la fourchette');
        po('             de ' || ftx(k_taux_min) || ' a ' || ftx(k_taux_max) || '.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (m.main_comp_rate IS NULL
                OR m.main_comp_rate < k_taux_min
                OR m.main_comp_rate > k_taux_max);
        p_verdict('MM-308', 'Taux nul, non renseigne ou hors bornes', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('INTERETS ATTENDUS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.main_comp_amount it
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (m.main_comp_rate IS NULL
                                OR m.main_comp_rate < k_taux_min
                                OR m.main_comp_rate > k_taux_max)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, famt(r.it));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-309', 'Taux ecarte des conditions de marche du mois');
        p_obj('comparer le taux de chaque operation a la moyenne des operations du');
        po('             meme produit souscrites le meme mois (groupes de 3 operations minimum).');
        print_kv('Ecart tolere', TO_CHAR(k_ecart_taux) || ' points');
        SELECT COUNT(*), NVL(SUM(mt), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.lcy_amount mt, m.main_comp_rate tx,
                   AVG(m.main_comp_rate) OVER (PARTITION BY m.product,
                                                            TO_CHAR(m.value_date, 'YYYY-MM')) txm,
                   COUNT(*)              OVER (PARTITION BY m.product,
                                                            TO_CHAR(m.value_date, 'YYYY-MM')) nbm
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE nbm >= 3 AND ABS(tx - txm) > k_ecart_taux;
        p_verdict('MM-309', 'Taux ecarte de la moyenne du produit sur le mois', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,7,28,20,10,12,12,14,12');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpadl('TAUX', 10) || '|'
                || fpad('MOIS', 12) || '|' || fpadl('TAUX MOYEN', 12) || '|' || fpadl('ECART (PTS)', 14) || '|'
                || fpadl('NB DU MOIS', 12) || '|');
            tbl_line('4,20,12,12,7,28,20,10,12,12,14,12');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT w.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.main_comp_rate tx,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           TO_CHAR(m.value_date, 'YYYY-MM') mois,
                           AVG(m.main_comp_rate) OVER (PARTITION BY m.product,
                                                        TO_CHAR(m.value_date, 'YYYY-MM')) txm,
                           COUNT(*)              OVER (PARTITION BY m.product,
                                                        TO_CHAR(m.value_date, 'YYYY-MM')) nbm
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) w
                WHERE w.nbm >= 3 AND ABS(w.tx - w.txm) > k_ecart_taux
                ORDER BY ABS(w.tx - w.txm) DESC, w.nom DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpadl(ftx(r.tx), 10) || '|'
                    || fpad(r.mois, 12) || '|' || fpadl(ftx(ROUND(r.txm, 4)), 12) || '|'
                    || fpadl(TO_CHAR(ROUND(r.tx - r.txm, 4)), 14) || '|' || fpadl(fnum(r.nbm), 12) || '|');
            END LOOP;
            tbl_line('4,20,12,12,7,28,20,10,12,12,14,12');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 11 BIS. MM-31x : PROVISIONS D'INTERETS (ACCRUALS)
    -- =========================================================
    print_section('11 BIS. CONTROLES MM-31x : PROVISIONS D''INTERETS (ACCRUALS)');
    BEGIN
        po('  Les interets courus sont provisionnes quotidiennement par le traitement de');
        po('  fin de journee. LDTB_CONTRACT_ICCF_DETAILS porte le cumul par composante,');
        po('  LDTB_CONTRACT_ACCRUAL_HISTORY en conserve le detail evenement par evenement.');

        print_sub('11B.1 Volumetrie des provisions');
        SELECT COUNT(*), COUNT(DISTINCT contract_ref_no), MIN(accrual_to_date), MAX(accrual_to_date),
               NVL(SUM(net_accrual), 0)
          INTO v_cnt, v_cnt2, v_d_max, v_d_accr, v_mt
          FROM ldtb_contract_accrual_history
         WHERE module = k_mod;
        print_kv('Lignes d''historique de provision',   fnum(v_cnt));
        print_kv('Contrats provisionnes',               fnum(v_cnt2));
        print_kv('Premiere provision',                  fdt(v_d_max));
        print_kv('Derniere provision',                  fdt(v_d_accr));
        print_kv('Somme des provisions nettes',         famt(v_mt) || '  (' || fmio(v_mt) || ')');

        print_sub('11B.2 Provisions par annee');
        tbl_line('4,10,14,14,20,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('ANNEE', 10) || '|' || fpadl('NB LIGNES', 14) || '|'
            || fpadl('NB CONTRATS', 14) || '|' || fpadl('PROVISION NETTE', 20) || '|'
            || fpadl('DONT POSITIVE', 20) || '|' || fpadl('DONT NEGATIVE', 20) || '|');
        tbl_line('4,10,14,14,20,20,20');
        v_row := 0;
        FOR r IN (
            SELECT TO_CHAR(a.accrual_to_date, 'YYYY') an, COUNT(*) nb,
                   COUNT(DISTINCT a.contract_ref_no) nbc,
                   SUM(a.net_accrual) net,
                   SUM(CASE WHEN a.net_accrual > 0 THEN a.net_accrual ELSE 0 END) pos,
                   SUM(CASE WHEN a.net_accrual < 0 THEN a.net_accrual ELSE 0 END) neg
              FROM ldtb_contract_accrual_history a
             WHERE a.module = k_mod
             GROUP BY TO_CHAR(a.accrual_to_date, 'YYYY')
             ORDER BY 1
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.an, 10) || '|' || fpadl(fnum(r.nb), 14) || '|'
                || fpadl(fnum(r.nbc), 14) || '|' || fpadl(fmio(r.net), 20) || '|'
                || fpadl(fmio(r.pos), 20) || '|' || fpadl(fmio(r.neg), 20) || '|');
        END LOOP;
        tbl_line('4,10,14,14,20,20,20');

        -- -----------------------------------------------------
        p_test('MM-310', 'Provision du contrat incoherente avec l''historique des provisions');
        p_obj('TILL_DATE_ACCRUAL de LDTB_CONTRACT_ICCF_DETAILS doit egaler le dernier');
        po('             cumul enregistre dans LDTB_CONTRACT_ACCRUAL_HISTORY.');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(cum, 0) - NVL(hist, 0))), 0) INTO v_cnt, v_mt
          FROM (
            SELECT d.contract_ref_no, d.component, d.till_date_accrual cum,
                   (SELECT MAX(a.till_date_accrual)
                             KEEP (DENSE_RANK LAST ORDER BY a.accrual_to_date, a.event_seq_no)
                      FROM ldtb_contract_accrual_history a
                     WHERE a.contract_ref_no = d.contract_ref_no
                       AND a.component = d.component) hist
              FROM ldtb_contract_iccf_details d
             WHERE d.component <> 'PRINCIPAL'
               AND EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = d.contract_ref_no
                              AND m.module = k_mod
                              AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
          )
         WHERE hist IS NOT NULL AND ABS(NVL(cum, 0) - NVL(hist, 0)) > k_tol_abs;
        p_verdict('MM-310', 'Provision du contrat incoherente avec son historique',
                  v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,9,20,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpadl('CUMUL CONTRAT', 20) || '|' || fpadl('CUMUL HISTORIQUE', 20) || '|'
                || fpadl('ECART', 20) || '|' || fpadl('DERNIERE PROVISION', 20) || '|');
            tbl_line('4,20,12,12,9,20,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT q.* FROM (
                    SELECT d.contract_ref_no ref, d.component comp, d.till_date_accrual cum,
                           d.previous_accrual_to_date dt,
                           (SELECT MAX(a.till_date_accrual)
                                     KEEP (DENSE_RANK LAST ORDER BY a.accrual_to_date, a.event_seq_no)
                              FROM ldtb_contract_accrual_history a
                             WHERE a.contract_ref_no = d.contract_ref_no
                               AND a.component = d.component) hist
                      FROM ldtb_contract_iccf_details d
                     WHERE d.component <> 'PRINCIPAL'
                       AND EXISTS (SELECT 1 FROM ldtb_contract_master m
                                    WHERE m.contract_ref_no = d.contract_ref_no
                                      AND m.module = k_mod
                                      AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                ) q
                WHERE q.hist IS NOT NULL AND ABS(NVL(q.cum, 0) - NVL(q.hist, 0)) > k_tol_abs
                ORDER BY ABS(NVL(q.cum, 0) - NVL(q.hist, 0)) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpadl(famt(r.cum), 20) || '|' || fpadl(famt(r.hist), 20) || '|'
                    || fpadl(famt(NVL(r.cum, 0) - NVL(r.hist, 0)), 20) || '|'
                    || fpadl(fdt(r.dt), 20) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,20,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-311', 'Provisions negatives');
        p_obj('une provision nette negative correspond a une reprise. Son ampleur et');
        po('             sa recurrence doivent etre justifiees.');
        SELECT COUNT(*), COUNT(DISTINCT contract_ref_no), NVL(SUM(net_accrual), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM ldtb_contract_accrual_history
         WHERE module = k_mod AND net_accrual < 0;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-311', 'Ecritures de provision negatives (reprises)', v_cnt, NULL, ABS(v_mt), 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,9,12,12,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpad('DATE PROV.', 12) || '|' || fpad('VALEUR', 12) || '|'
                || fpadl('PROVISION NETTE', 20) || '|' || fpadl('CUMUL A LA DATE', 20) || '|'
                || fpadl('ENCOURS PROV.', 20) || '|');
            tbl_line('4,20,12,12,9,12,12,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT a.contract_ref_no ref, a.component comp, a.accrual_to_date dt,
                               a.value_date vd, a.net_accrual net, a.till_date_accrual cum,
                               a.outstanding_accrual enc
                          FROM ldtb_contract_accrual_history a
                         WHERE a.module = k_mod AND a.net_accrual < 0
                         ORDER BY a.net_accrual ASC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpad(fdt(r.dt), 12) || '|' || fpad(fdt(r.vd), 12) || '|' || fpadl(famt(r.net), 20) || '|'
                    || fpadl(famt(r.cum), 20) || '|' || fpadl(famt(r.enc), 20) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,12,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-312', 'Provision cumulee superieure aux interets contractuels');
        p_obj('la provision cumulee sur un contrat ne peut pas depasser les interets');
        po('             totaux prevus au contrat, sauf sur un contrat proroge.');
        SELECT COUNT(*), NVL(SUM(prov - it), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.contract_ref_no, NVL(m.main_comp_amount, 0) it,
                   NVL((SELECT SUM(d.till_date_accrual) FROM ldtb_contract_iccf_details d
                         WHERE d.contract_ref_no = m.contract_ref_no
                           AND d.component <> 'PRINCIPAL'), 0) prov
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE it > 0 AND prov > it + k_tol_abs;
        p_verdict('MM-312', 'Provision cumulee superieure aux interets contractuels',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,7,28,20,10,20,20,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpadl('TAUX', 10) || '|'
                || fpadl('INT. CONTRAT', 20) || '|' || fpadl('PROVISION CUMULEE', 20) || '|'
                || fpadl('SUR-PROVISION', 18) || '|');
            tbl_line('4,20,12,12,7,28,20,10,20,20,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT s.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.main_comp_rate tx,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           NVL(m.main_comp_amount, 0) it,
                           NVL((SELECT SUM(d.till_date_accrual) FROM ldtb_contract_iccf_details d
                                 WHERE d.contract_ref_no = m.contract_ref_no
                                   AND d.component <> 'PRINCIPAL'), 0) prov
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) s
                WHERE s.it > 0 AND s.prov > s.it + k_tol_abs
                ORDER BY s.prov - s.it DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpadl(ftx(r.tx), 10) || '|'
                    || fpadl(famt(r.it), 20) || '|' || fpadl(famt(r.prov), 20) || '|'
                    || fpadl(famt(r.prov - r.it), 18) || '|');
            END LOOP;
            tbl_line('4,20,12,12,7,28,20,10,20,20,18');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-313', 'Provision enregistree apres l''echeance du contrat');
        p_obj('un contrat echu ne doit plus generer de provision d''interets.');
        SELECT COUNT(*), COUNT(DISTINCT a.contract_ref_no), NVL(SUM(a.net_accrual), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM ldtb_contract_accrual_history a
          JOIN ldtb_contract_master m ON m.contract_ref_no = a.contract_ref_no
         WHERE a.module = k_mod
           AND m.module = k_mod
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND a.accrual_to_date > m.maturity_date;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-313', 'Provision enregistree apres l''echeance du contrat',
                  v_cnt, NULL, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-314', 'Contrat sans aucune provision alors que la provision est requise');
        p_obj('une composante d''interet marquee ACCRUAL_REQUIRED = Y doit avoir');
        po('             genere au moins une ecriture de provision.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND EXISTS (SELECT 1 FROM ldtb_contract_iccf_details d
                        WHERE d.contract_ref_no = m.contract_ref_no
                          AND d.component <> 'PRINCIPAL'
                          AND NVL(TRIM(d.accrual_required), 'N') = 'Y')
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_accrual_history a
                            WHERE a.contract_ref_no = m.contract_ref_no);
        p_verdict('MM-314', 'Contrat sans provision alors que la provision est requise',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('INTERETS ATTENDUS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.main_comp_amount it
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND EXISTS (SELECT 1 FROM ldtb_contract_iccf_details d
                                        WHERE d.contract_ref_no = m.contract_ref_no
                                          AND d.component <> 'PRINCIPAL'
                                          AND NVL(TRIM(d.accrual_required), 'N') = 'Y')
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_accrual_history a
                                            WHERE a.contract_ref_no = m.contract_ref_no)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, famt(r.it));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-315', 'Contrat vivant dont la provision n''est plus mise a jour');
        p_obj('sur un contrat non echu, la derniere provision ne doit pas remonter a');
        po('             plus de ' || TO_CHAR(k_ret_accr) || ' jours avant la date d''arrete du ' || fdt(k_arrete) || '.');
        SELECT COUNT(*), NVL(SUM(lcy), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.lcy_amount lcy,
                   (SELECT MAX(a.accrual_to_date) FROM ldtb_contract_accrual_history a
                     WHERE a.contract_ref_no = m.contract_ref_no) d_last
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.maturity_date > k_arrete
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE d_last IS NULL OR TRUNC(k_arrete) - TRUNC(d_last) > k_ret_accr;
        p_verdict('MM-315', 'Contrat vivant dont la provision n''est plus mise a jour',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('DERNIERE PROVISION');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                SELECT t.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.counterparty cif,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) nom,
                           m.lcy_amount lcy, m.main_comp_rate tx, m.booking_date bd, m.value_date vd, m.maturity_date md,
                           (SELECT MAX(a.accrual_to_date) FROM ldtb_contract_accrual_history a
                             WHERE a.contract_ref_no = m.contract_ref_no) d_last
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.maturity_date > k_arrete
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) t
                WHERE t.d_last IS NULL OR TRUNC(k_arrete) - TRUNC(t.d_last) > k_ret_accr
                ORDER BY t.lcy DESC
            ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.ref, r.product, r.cif, r.nom, r.lcy, r.tx, r.bd, r.vd, r.md,
                      NVL(fdt(r.d_last), 'JAMAIS') || ' ('
                      || fnum(TRUNC(k_arrete) - TRUNC(NVL(r.d_last, k_arrete))) || ' j)');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-316', 'Estimation des interets courus non provisionnes');
        p_obj('chiffrer, pour les contrats vivants dont la provision est arretee, les');
        po('             interets economiquement courus mais absents de la comptabilite.');
        po('             Estimation = nominal x taux x jours non provisionnes / base de jours.');
        print_kv('Base de jours retenue pour l''estimation', TO_CHAR(k_base_jours));
        SELECT COUNT(*), NVL(SUM(lcy), 0),
               NVL(SUM(lcy * tx / 100 * jours / k_base_jours), 0),
               NVL(SUM(lcy * tx / 100 * jours / 365), 0)
          INTO v_cnt, v_mt, v_tot, v_tot2
          FROM (
            SELECT m.lcy_amount lcy, m.main_comp_rate tx,
                   LEAST(TRUNC(k_arrete), TRUNC(m.maturity_date))
                     - TRUNC((SELECT MAX(a.accrual_to_date) FROM ldtb_contract_accrual_history a
                               WHERE a.contract_ref_no = m.contract_ref_no)) jours
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.maturity_date > k_arrete
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE jours > k_ret_accr;
        print_kv('Contrats concernes',                     fnum(v_cnt));
        print_kv('Nominal porte par ces contrats',         famt(v_mt) || '  (' || fmio(v_mt) || ')');
        print_kv('Interets courus non provisionnes (base ' || TO_CHAR(k_base_jours) || ')',
                 famt(v_tot) || '  (' || fmio(v_tot) || ')');
        print_kv('Meme estimation en base 365',            famt(v_tot2) || '  (' || fmio(v_tot2) || ')');
        p_verdict('MM-316', 'Interets courus non provisionnes sur contrats vivants',
                  v_cnt, v_nb_ctr, v_tot, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,7,28,20,10,12,12,12,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpadl('TAUX', 10) || '|'
                || fpad('DERN. PROV.', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('JOURS', 12) || '|' || fpadl('INT. A COMPTAB.', 18) || '|');
            tbl_line('4,20,12,7,28,20,10,12,12,12,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                SELECT u.*, ROUND(u.lcy * u.tx / 100 * u.jours / k_base_jours, 2) est FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount lcy, m.main_comp_rate tx,
                           m.maturity_date md,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           (SELECT MAX(a.accrual_to_date) FROM ldtb_contract_accrual_history a
                             WHERE a.contract_ref_no = m.contract_ref_no) d_last,
                           LEAST(TRUNC(k_arrete), TRUNC(m.maturity_date))
                             - TRUNC((SELECT MAX(a.accrual_to_date) FROM ldtb_contract_accrual_history a
                                       WHERE a.contract_ref_no = m.contract_ref_no)) jours
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.maturity_date > k_arrete
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) u
                WHERE u.jours > k_ret_accr
                ORDER BY u.lcy * u.tx * u.jours DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.lcy), 20) || '|' || fpadl(ftx(r.tx), 10) || '|'
                    || fpad(fdt(r.d_last), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(fnum(r.jours), 12) || '|' || fpadl(famt(r.est), 18) || '|');
            END LOOP;
            tbl_line('4,20,12,7,28,20,10,12,12,12,18');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 4 : REMBOURSEMENTS, LIQUIDATIONS ET RETARDS');
    -- ########################################################################

    -- =========================================================
    -- 12. MM-4xx : REMBOURSEMENTS ET LIQUIDATIONS
    -- =========================================================
    print_section('12. CONTROLES MM-4xx : REMBOURSEMENTS ET LIQUIDATIONS');
    BEGIN
        po('  MECANIQUE DU REMBOURSEMENT DANS FLEXCUBE');
        po('    LDTB_CONTRACT_LIQ          une ligne par composante liquidee, avec le');
        po('                               montant du (AMOUNT_DUE), le montant paye');
        po('                               (AMOUNT_PAID) et le retard (OVERDUE_DAYS)');
        po('    LDTB_CONTRACT_LIQ_SUMMARY  synthese par evenement de liquidation, avec');
        po('                               la date de valeur, le total paye et le statut');
        po('    LDTB_CONTRACT_BALANCE      encours restant apres liquidation');

        -- -----------------------------------------------------
        p_test('MM-401', 'Contrat echu sans aucune liquidation enregistree');
        p_obj('a l''echeance, le capital doit avoir ete rembourse et l''operation');
        po('             liquidee dans le systeme.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.maturity_date <= k_arrete
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_liq_summary s
                            WHERE s.contract_ref_no = m.contract_ref_no);
        p_verdict('MM-401', 'Contrat echu sans aucune liquidation enregistree', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('ECHU DEPUIS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.maturity_date <= k_arrete
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_liq_summary s
                                            WHERE s.contract_ref_no = m.contract_ref_no)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      fnum(TRUNC(k_arrete) - TRUNC(r.maturity_date)) || ' j');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-402', 'Contrat echu conservant un encours residuel');
        p_obj('apres liquidation, PRINCIPAL_OUTSTANDING_BAL doit etre nul.');
        SELECT COUNT(*), NVL(SUM(b.principal_outstanding_bal), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
          JOIN ldtb_contract_balance b ON b.contract_ref_no = m.contract_ref_no
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.maturity_date <= k_arrete
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(b.principal_outstanding_bal, 0) > 0;
        p_verdict('MM-402', 'Contrat echu conservant un encours residuel', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('ENCOURS RESIDUEL');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               b.principal_outstanding_bal enc
                          FROM ldtb_contract_master m
                          JOIN ldtb_contract_balance b ON b.contract_ref_no = m.contract_ref_no
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.maturity_date <= k_arrete
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(b.principal_outstanding_bal, 0) > 0
                         ORDER BY b.principal_outstanding_bal DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, famt(r.enc));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-403', 'Liquidation partielle : montant paye inferieur au montant du');
        p_obj('sur chaque composante liquidee, AMOUNT_PAID doit couvrir AMOUNT_DUE.');
        SELECT COUNT(*), COUNT(DISTINCT l.contract_ref_no),
               NVL(SUM(NVL(l.amount_due, 0) - NVL(l.amount_paid, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM ldtb_contract_liq l
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = l.contract_ref_no
                          AND m.module = k_mod
                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
           AND NVL(l.amount_due, 0) - NVL(l.amount_paid, 0) > k_tol_abs;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-403', 'Composante liquidee partiellement', v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,9,12,20,20,20,12');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpadl('EVENEMENT', 12) || '|' || fpadl('MONTANT DU', 20) || '|'
                || fpadl('MONTANT PAYE', 20) || '|' || fpadl('RESTE DU', 20) || '|'
                || fpadl('RETARD (J)', 12) || '|');
            tbl_line('4,20,12,12,9,12,20,20,20,12');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT l.contract_ref_no ref, l.component comp, l.event_seq_no ev,
                               l.amount_due du, l.amount_paid paye, l.overdue_days od
                          FROM ldtb_contract_liq l
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = l.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                           AND NVL(l.amount_due, 0) - NVL(l.amount_paid, 0) > k_tol_abs
                         ORDER BY NVL(l.amount_due, 0) - NVL(l.amount_paid, 0) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpadl(fnum(r.ev), 12) || '|' || fpadl(famt(r.du), 20) || '|'
                    || fpadl(famt(r.paye), 20) || '|'
                    || fpadl(famt(NVL(r.du, 0) - NVL(r.paye, 0)), 20) || '|'
                    || fpadl(fnum(r.od), 12) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,20,20,20,12');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-404', 'Capital rembourse different du nominal du contrat');
        p_obj('sur un contrat echu et liquide, la somme des paiements de la composante');
        po('             PRINCIPAL doit egaler le nominal. Les evenements de liquidation');
        po('             extournes (PAYMENT_STATUS <> A) sont neutralises, faute de quoi un');
        po('             remboursement extourne puis rejoue serait compte deux fois.');
        SELECT COUNT(*), NVL(SUM(ABS(nom - rembt)), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.contract_ref_no, m.lcy_amount nom,
                   NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                         WHERE l.contract_ref_no = m.contract_ref_no
                           AND l.component = 'PRINCIPAL'
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_liq_summary q
                                            WHERE q.contract_ref_no = l.contract_ref_no
                                              AND q.event_seq_no = l.event_seq_no
                                              AND NVL(TRIM(q.payment_status), 'A') <> 'A')), 0) rembt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.maturity_date <= k_arrete
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
               AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                            WHERE l.contract_ref_no = m.contract_ref_no
                              AND l.component = 'PRINCIPAL')
          )
         WHERE ABS(nom - rembt) > k_tol_abs;
        p_verdict('MM-404', 'Capital rembourse different du nominal du contrat', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,7,28,20,12,20,20,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('CAPITAL REMBOURSE', 20) || '|' || fpadl('ECART', 20) || '|'
                || fpadl('% ECART', 18) || '|');
            tbl_line('4,20,12,7,28,20,12,20,20,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                SELECT g.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.maturity_date md,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                                 WHERE l.contract_ref_no = m.contract_ref_no
                                   AND l.component = 'PRINCIPAL'), 0) rembt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.maturity_date <= k_arrete
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                       AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                                    WHERE l.contract_ref_no = m.contract_ref_no
                                      AND l.component = 'PRINCIPAL')
                ) g
                WHERE ABS(g.nom - g.rembt) > k_tol_abs
                ORDER BY ABS(g.nom - g.rembt) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.rembt), 20) || '|' || fpadl(famt(r.nom - r.rembt), 20) || '|'
                    || fpadl(fpct(ABS(r.nom - r.rembt), r.nom), 18) || '|');
            END LOOP;
            tbl_line('4,20,12,7,28,20,12,20,20,18');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-406', 'Liquidation extournee ou en statut anormal');
        p_obj('une liquidation de statut different de A (autorisee) doit etre justifiee.');
        SELECT COUNT(*), COUNT(DISTINCT s.contract_ref_no), NVL(SUM(s.total_paid), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM ldtb_contract_liq_summary s
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = s.contract_ref_no
                          AND m.module = k_mod
                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
           AND NVL(TRIM(s.payment_status), 'X') <> 'A';
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-406', 'Liquidation en statut anormal (extournee)', v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,12,12,20,12,20,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('EVENEMENT', 12) || '|'
                || fpad('VALEUR', 12) || '|' || fpadl('TOTAL PAYE', 20) || '|' || fpad('STATUT', 12) || '|'
                || fpad('ECHEANCE INITIALE', 20) || '|' || fpad('OBSERVATION', 24) || '|');
            tbl_line('4,20,12,12,12,12,20,12,20,24');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT s.contract_ref_no ref, s.event_seq_no ev, s.value_date vd,
                               s.total_paid tp, s.payment_status st, s.old_maturity_date omd,
                               s.payment_remarks rem
                          FROM ldtb_contract_liq_summary s
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = s.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                           AND NVL(TRIM(s.payment_status), 'X') <> 'A'
                         ORDER BY s.total_paid DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpadl(fnum(r.ev), 12) || '|'
                    || fpad(fdt(r.vd), 12) || '|' || fpadl(famt(r.tp), 20) || '|' || fpad(r.st, 12) || '|'
                    || fpad(fdt(r.omd), 20) || '|' || fpad(r.rem, 24) || '|');
            END LOOP;
            tbl_line('4,20,12,12,12,12,20,12,20,24');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-408', 'Prorogation de l''echeance a l''occasion d''une liquidation');
        p_obj('lorsque NEW_MATURITY_DATE differe de OLD_MATURITY_DATE, l''echeance a ete');
        po('             repoussee. Ces prorogations doivent etre autorisees et tracees.');
        SELECT COUNT(*), COUNT(DISTINCT s.contract_ref_no), NVL(SUM(s.total_paid), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM ldtb_contract_liq_summary s
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = s.contract_ref_no
                          AND m.module = k_mod
                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
           AND s.old_maturity_date IS NOT NULL
           AND s.new_maturity_date IS NOT NULL
           AND s.new_maturity_date <> s.old_maturity_date;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-408', 'Echeance prorogee lors d''une liquidation', v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,12,12,12,20,16,16,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('EVENEMENT', 12) || '|'
                || fpad('VALEUR', 12) || '|' || fpadl('TOTAL PAYE', 20) || '|'
                || fpad('ANCIENNE ECH.', 16) || '|' || fpad('NOUVELLE ECH.', 16) || '|'
                || fpadl('DECALAGE (J)', 14) || '|');
            tbl_line('4,20,12,12,12,12,20,16,16,14');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT s.contract_ref_no ref, s.event_seq_no ev, s.value_date vd,
                               s.total_paid tp, s.old_maturity_date omd, s.new_maturity_date nmd
                          FROM ldtb_contract_liq_summary s
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = s.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                           AND s.old_maturity_date IS NOT NULL
                           AND s.new_maturity_date IS NOT NULL
                           AND s.new_maturity_date <> s.old_maturity_date
                         ORDER BY ABS(s.new_maturity_date - s.old_maturity_date) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpadl(fnum(r.ev), 12) || '|'
                    || fpad(fdt(r.vd), 12) || '|' || fpadl(famt(r.tp), 20) || '|'
                    || fpad(fdt(r.omd), 16) || '|' || fpad(fdt(r.nmd), 16) || '|'
                    || fpadl(fnum(r.nmd - r.omd), 14) || '|');
            END LOOP;
            tbl_line('4,20,12,12,12,12,20,16,16,14');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-409', 'Statut du contrat incoherent avec l''etat des liquidations');
        p_obj('un contrat de statut L (liquide) dont le capital n''est pas integralement');
        po('             rembourse, ou de statut A (actif) alors qu''il est solde, est mal classe.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND ((TRIM(m.contract_status) = 'L'
                 AND NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                           WHERE l.contract_ref_no = m.contract_ref_no
                             AND l.component = 'PRINCIPAL'), 0) < m.lcy_amount - k_tol_abs)
                OR (TRIM(m.contract_status) = 'A'
                    AND NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                              WHERE l.contract_ref_no = m.contract_ref_no
                                AND l.component = 'PRINCIPAL'), 0) >= m.lcy_amount - k_tol_abs));
        p_verdict('MM-409', 'Statut du contrat incoherent avec l''etat des liquidations',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,7,28,20,10,12,20,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpad('STATUT', 10) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpadl('CAPITAL REMBOURSE', 20) || '|'
                || fpadl('RESTE DU', 18) || '|');
            tbl_line('4,20,12,7,28,20,10,12,20,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                SELECT hh.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.maturity_date md,
                           TRIM(m.contract_status) st,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                                 WHERE l.contract_ref_no = m.contract_ref_no
                                   AND l.component = 'PRINCIPAL'), 0) rembt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) hh
                WHERE (hh.st = 'L' AND hh.rembt < hh.nom - k_tol_abs)
                   OR (hh.st = 'A' AND hh.rembt >= hh.nom - k_tol_abs)
                ORDER BY ABS(hh.nom - hh.rembt) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpad(r.st, 10) || '|'
                    || fpad(fdt(r.md), 12) || '|' || fpadl(famt(r.rembt), 20) || '|'
                    || fpadl(famt(r.nom - r.rembt), 18) || '|');
            END LOOP;
            tbl_line('4,20,12,7,28,20,10,12,20,18');
        END IF;


        -- -----------------------------------------------------
        p_test('MM-410', 'Contrat renouvele (rollover)');
        p_obj('un renouvellement prolonge l''operation sans nouvelle decision');
        po('             d''investissement. Il doit rester tracable et autorise.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.rollover_count, 0) > 0;
        p_verdict('MM-410', 'Contrat renouvele au moins une fois', v_cnt, v_nb_ctr, v_mt, 'INFO');

        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.rollover_count, 0) > 3;
        p_verdict('MM-411', 'Contrat renouvele plus de trois fois', v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('NB RENOUVELLEMENTS');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.rollover_count rc
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.rollover_count, 0) > 3
                         ORDER BY m.rollover_count DESC, m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, fnum(r.rc));
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-412', 'Instruction de renouvellement enregistree mais jamais executee');
        p_obj('un contrat porteur d''une instruction de rollover dans');
        po('             LDTB_CONTRACT_ROLLOVER mais dont ROLLOVER_COUNT reste a zero et dont');
        po('             ROLLOVER_INDICATOR vaut N revele un parametrage dormant : la banque');
        po('             croit disposer d''un renouvellement automatique qui ne se declenche pas.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.rollover_count, 0) = 0
           AND EXISTS (SELECT 1 FROM ldtb_contract_rollover o
                        WHERE o.contract_ref_no = m.contract_ref_no);
        p_verdict('MM-412', 'Instruction de renouvellement enregistree mais jamais executee',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,7,28,20,12,12,12,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpad('ROLL. AUT.', 12) || '|' || fpad('INDICATEUR', 12) || '|'
                || fpadl('TYPE / METHODE', 14) || '|');
            tbl_line('4,20,12,7,28,20,12,12,12,14');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                        SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.maturity_date md,
                               TRIM(m.rollover_allowed) ra, TRIM(m.rollover_indicator) ri,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) etat,
                               (SELECT MAX(TRIM(o.rollover_type) || ' / ' || TRIM(o.roll_by))
                                  FROM ldtb_contract_rollover o
                                 WHERE o.contract_ref_no = m.contract_ref_no) typ
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.rollover_count, 0) = 0
                           AND EXISTS (SELECT 1 FROM ldtb_contract_rollover o
                                        WHERE o.contract_ref_no = m.contract_ref_no)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpad(r.ra, 12) || '|' || fpad(r.ri, 12) || '|' || fpadl(r.typ, 14) || '|');
            END LOOP;
            tbl_line('4,20,12,7,28,20,12,12,12,14');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 13. MM-5xx : RETARDS ET DELAIS
    -- =========================================================
    print_section('13. CONTROLES MM-5xx : RETARDS ET DELAIS');
    BEGIN
        po('  Trois delais sont mesures : le retard de paiement declare par le systeme,');
        po('  le retard de liquidation par rapport a l''echeance contractuelle et le');
        po('  delai de prise en compte comptable des operations.');

        -- -----------------------------------------------------
        p_test('MM-501', 'Retard de paiement declare par le systeme');
        p_obj('OVERDUE_DAYS de LDTB_CONTRACT_LIQ porte le nombre de jours de retard');
        po('             constate par FLEXCUBE sur chaque composante liquidee. Sur les titres');
        po('             decotes le montant du est negatif (interets precomptes) : l''enjeu est');
        po('             donc exprime en valeur absolue, et le reste du est donne a part.');
        SELECT COUNT(*), COUNT(DISTINCT l.contract_ref_no), NVL(SUM(ABS(NVL(l.amount_due, 0))), 0),
               MAX(l.overdue_days)
          INTO v_cnt, v_cnt2, v_mt, v_tot
          FROM ldtb_contract_liq l
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = l.contract_ref_no
                          AND m.module = k_mod
                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
           AND NVL(l.overdue_days, 0) > 0;
        print_kv('Contrats concernes',      fnum(v_cnt2));
        print_kv('Retard maximal constate', fnum(v_tot) || ' jours');
        p_verdict('MM-501', 'Composante liquidee avec un retard declare', v_cnt, NULL, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            print_sub('MM-501 bis. Distribution des retards declares');
            SELECT COUNT(*) INTO v_tot2
              FROM ldtb_contract_liq l
             WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = l.contract_ref_no
                              AND m.module = k_mod
                              AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin);
            tbl_line('4,28,12,20,12');
            po('  |' || fpad('N#', 4) || '|' || fpad('RETARD', 28) || '|' || fpadl('NB LIGNES', 12) || '|'
                || fpadl('MONTANT DU', 20) || '|' || fpadl('% LIGNES', 12) || '|');
            tbl_line('4,28,12,20,12');
            v_row := 0;
            FOR r IN (
                SELECT tr, COUNT(*) nb, SUM(du) mt
                  FROM (SELECT CASE
                                 WHEN NVL(l.overdue_days, 0) = 0  THEN '0. aucun retard'
                                 WHEN l.overdue_days <= 5         THEN '1. 1 a 5 jours'
                                 WHEN l.overdue_days <= 30        THEN '2. 6 a 30 jours'
                                 WHEN l.overdue_days <= 90        THEN '3. 31 a 90 jours'
                                 WHEN l.overdue_days <= 180       THEN '4. 91 a 180 jours'
                                 ELSE                                  '5. plus de 180 jours'
                               END tr, l.amount_due du
                          FROM ldtb_contract_liq l
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = l.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin))
                 GROUP BY tr ORDER BY tr
            ) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 28) || '|' || fpadl(fnum(r.nb), 12) || '|'
                    || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_tot2), 12) || '|');
            END LOOP;
            tbl_line('4,28,12,20,12');

            tbl_line('4,20,12,12,9,12,20,20,20,12');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('COMPOS.', 9) || '|'
                || fpadl('EVENEMENT', 12) || '|' || fpadl('MONTANT DU', 20) || '|'
                || fpadl('MONTANT PAYE', 20) || '|' || fpadl('RESTE DU', 20) || '|'
                || fpadl('RETARD (J)', 12) || '|');
            tbl_line('4,20,12,12,9,12,20,20,20,12');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT l.contract_ref_no ref, l.component comp, l.event_seq_no ev,
                               l.amount_due du, l.amount_paid paye, l.overdue_days od
                          FROM ldtb_contract_liq l
                         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                        WHERE m.contract_ref_no = l.contract_ref_no
                                          AND m.module = k_mod
                                          AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin)
                           AND NVL(l.overdue_days, 0) > 0
                         ORDER BY l.overdue_days DESC, l.amount_due DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.comp, 9) || '|'
                    || fpadl(fnum(r.ev), 12) || '|' || fpadl(famt(r.du), 20) || '|'
                    || fpadl(famt(r.paye), 20) || '|'
                    || fpadl(famt(NVL(r.du, 0) - NVL(r.paye, 0)), 20) || '|'
                    || fpadl(fnum(r.od), 12) || '|');
            END LOOP;
            tbl_line('4,20,12,12,9,12,20,20,20,12');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-502', 'Liquidation intervenue apres l''echeance contractuelle');
        p_obj('comparer la date de valeur de la liquidation du capital a l''echeance');
        po('             du contrat. Au dela de ' || TO_CHAR(k_ret_liq) || ' jours le retard est considere comme anormal.');

        print_sub('MM-502 a. Distribution du delai de liquidation du capital');
        tbl_line('4,30,12,20,12,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('DELAI DE LIQUIDATION', 30) || '|' || fpadl('NB CONTRATS', 12) || '|'
            || fpadl('NOMINAL', 20) || '|' || fpadl('% NB', 12) || '|' || fpadl('MAX (JOURS)', 14) || '|');
        tbl_line('4,30,12,20,12,14');
        v_row := 0;
        v_tot := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(nom) mt, MAX(d) mx
              FROM (SELECT CASE
                             WHEN d < 0    THEN '0. liquide par anticipation'
                             WHEN d = 0    THEN '1. liquide a l''echeance'
                             WHEN d <= 5   THEN '2. 1 a 5 jours de retard'
                             WHEN d <= 30  THEN '3. 6 a 30 jours de retard'
                             WHEN d <= 90  THEN '4. 31 a 90 jours de retard'
                             ELSE               '5. plus de 90 jours de retard'
                           END tr, nom, d
                      FROM (SELECT m.lcy_amount nom,
                                   TRUNC((SELECT MIN(s.value_date) FROM ldtb_contract_liq_summary s
                                           WHERE s.contract_ref_no = m.contract_ref_no
                                             AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                                                          WHERE l.contract_ref_no = s.contract_ref_no
                                                            AND l.event_seq_no = s.event_seq_no
                                                            AND l.component = 'PRINCIPAL'
                                                            AND NVL(l.amount_paid, 0) > 0)))
                                     - TRUNC(m.maturity_date) d
                              FROM ldtb_contract_master m
                             WHERE m.module = k_mod
                               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                    WHERE v.contract_ref_no = m.contract_ref_no))
                     WHERE d IS NOT NULL)
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            v_tot := v_tot + r.nb;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 30) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|'
                || fpadl(fnum(r.mx), 14) || '|');
        END LOOP;
        tbl_line('4,30,12,20,12,14');
        print_kv('Contrats dont le capital a ete liquide', fnum(v_tot));

        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT m.lcy_amount nom,
                       TRUNC((SELECT MIN(s.value_date) FROM ldtb_contract_liq_summary s
                               WHERE s.contract_ref_no = m.contract_ref_no
                                 AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                                              WHERE l.contract_ref_no = s.contract_ref_no
                                                AND l.event_seq_no = s.event_seq_no
                                                AND l.component = 'PRINCIPAL'
                                                AND NVL(l.amount_paid, 0) > 0)))
                         - TRUNC(m.maturity_date) d
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no))
         WHERE d > k_ret_liq;
        p_verdict('MM-502', 'Capital liquide plus de ' || TO_CHAR(k_ret_liq) || ' jours apres l''echeance',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('RETARD (JOURS)');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                SELECT j.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.counterparty cif,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) nom,
                           m.lcy_amount lcy, m.main_comp_rate tx, m.booking_date bd, m.value_date vd, m.maturity_date md,
                           TRUNC((SELECT MIN(s.value_date) FROM ldtb_contract_liq_summary s
                                   WHERE s.contract_ref_no = m.contract_ref_no
                                     AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                                                  WHERE l.contract_ref_no = s.contract_ref_no
                                                    AND l.event_seq_no = s.event_seq_no
                                                    AND l.component = 'PRINCIPAL'
                                                    AND NVL(l.amount_paid, 0) > 0)))
                             - TRUNC(m.maturity_date) d
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) j
                WHERE j.d > k_ret_liq
                ORDER BY j.d DESC, j.lcy DESC
            ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.ref, r.product, r.cif, r.nom, r.lcy, r.tx, r.bd, r.vd, r.md,
                      fnum(r.d) || ' j');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-503', 'Contrat echu depuis longtemps et toujours non liquide');
        p_obj('identifier les operations echues depuis plus de ' || TO_CHAR(k_ech_ancien) || ' jours dont le');
        po('             capital n''a pas ete integralement rembourse.');
        SELECT COUNT(*), NVL(SUM(nom - rembt), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.lcy_amount nom, m.maturity_date md,
                   NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                         WHERE l.contract_ref_no = m.contract_ref_no
                           AND l.component = 'PRINCIPAL'
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_liq_summary q
                                            WHERE q.contract_ref_no = l.contract_ref_no
                                              AND q.event_seq_no = l.event_seq_no
                                              AND NVL(TRIM(q.payment_status), 'A') <> 'A')), 0) rembt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE TRUNC(k_arrete) - TRUNC(md) > k_ech_ancien
           AND rembt < nom - k_tol_abs;
        p_verdict('MM-503', 'Contrat echu depuis plus de ' || TO_CHAR(k_ech_ancien)
                  || ' jours et non integralement rembourse', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,12,7,28,20,12,14,20,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 20) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('ECHU DEPUIS (J)', 14) || '|' || fpadl('CAPITAL REMBOURSE', 20) || '|'
                || fpadl('RESTE DU', 18) || '|');
            tbl_line('4,20,12,7,28,20,12,14,20,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                SELECT kk.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom, m.maturity_date md,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                                 WHERE l.contract_ref_no = m.contract_ref_no
                                   AND l.component = 'PRINCIPAL'), 0) rembt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                ) kk
                WHERE TRUNC(k_arrete) - TRUNC(kk.md) > k_ech_ancien
                  AND kk.rembt < kk.nom - k_tol_abs
                ORDER BY kk.nom - kk.rembt DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 20) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(fnum(TRUNC(k_arrete) - TRUNC(r.md)), 14) || '|' || fpadl(famt(r.rembt), 20) || '|'
                    || fpadl(famt(r.nom - r.rembt), 18) || '|');
            END LOOP;
            tbl_line('4,20,12,7,28,20,12,14,20,18');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-504', 'Delai de comptabilisation de la mise en place');
        p_obj('mesurer l''ecart entre la date de valeur du contrat et la premiere');
        po('             ecriture comptable qui le constate.');
        print_sub('MM-504 a. Distribution du delai de comptabilisation');
        tbl_line('4,32,12,20,12,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('DELAI', 32) || '|' || fpadl('NB CONTRATS', 12) || '|'
            || fpadl('NOMINAL', 20) || '|' || fpadl('% NB', 12) || '|' || fpadl('MAX (JOURS)', 14) || '|');
        tbl_line('4,32,12,20,12,14');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(nom) mt, MAX(d) mx
              FROM (SELECT CASE
                             WHEN d IS NULL THEN '9. aucune ecriture comptable'
                             WHEN d < 0     THEN '0. comptabilise avant la valeur'
                             WHEN d = 0     THEN '1. le jour meme'
                             WHEN d <= 2    THEN '2. 1 a 2 jours'
                             WHEN d <= 5    THEN '3. 3 a 5 jours'
                             WHEN d <= 30   THEN '4. 6 a 30 jours'
                             ELSE                '5. plus de 30 jours'
                           END tr, nom, d
                      FROM (SELECT m.lcy_amount nom,
                                   TRUNC((SELECT MIN(h.trn_dt) FROM actb_history h
                                           WHERE h.trn_ref_no = m.contract_ref_no
                                             AND h.module = k_mod))
                                     - TRUNC(m.value_date) d
                              FROM ldtb_contract_master m
                             WHERE m.module = k_mod
                               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                    WHERE v.contract_ref_no = m.contract_ref_no)))
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 32) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|'
                || fpadl(fnum(r.mx), 14) || '|');
        END LOOP;
        tbl_line('4,32,12,20,12,14');

        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT m.lcy_amount nom,
                       TRUNC((SELECT MIN(h.trn_dt) FROM actb_history h
                               WHERE h.trn_ref_no = m.contract_ref_no
                                 AND h.module = k_mod))
                         - TRUNC(m.value_date) d
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no))
         WHERE d > 5;
        p_verdict('MM-504', 'Mise en place comptabilisee plus de 5 jours apres la date de valeur',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MM-505', 'Synthese des retards par Etat emetteur');
        p_obj('rapprocher les retards constates de chaque emetteur souverain afin');
        po('             d''orienter le suivi du risque de contrepartie.');
        tbl_line('4,30,12,20,14,20,14,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('ETAT EMETTEUR', 30) || '|' || fpadl('NB ECHUS', 12) || '|'
            || fpadl('NOMINAL ECHU', 20) || '|' || fpadl('NB EN RETARD', 14) || '|'
            || fpadl('MONTANT EN RETARD', 20) || '|' || fpadl('RETARD MOYEN', 14) || '|'
            || fpadl('RETARD MAXIMAL', 20) || '|');
        tbl_line('4,30,12,20,14,20,14,20');
        v_row := 0;
        FOR r IN (
            SELECT etat,
                   COUNT(*) nb,
                   SUM(nom) mt,
                   SUM(CASE WHEN d > k_ret_liq THEN 1 ELSE 0 END) nbr,
                   SUM(CASE WHEN d > k_ret_liq THEN nom ELSE 0 END) mtr,
                   AVG(CASE WHEN d > k_ret_liq THEN d END) dm,
                   MAX(d) dmax
              FROM (SELECT (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           m.lcy_amount nom,
                           TRUNC((SELECT MIN(s.value_date) FROM ldtb_contract_liq_summary s
                                   WHERE s.contract_ref_no = m.contract_ref_no
                                     AND EXISTS (SELECT 1 FROM ldtb_contract_liq l
                                                  WHERE l.contract_ref_no = s.contract_ref_no
                                                    AND l.event_seq_no = s.event_seq_no
                                                    AND l.component = 'PRINCIPAL'
                                                    AND NVL(l.amount_paid, 0) > 0)))
                             - TRUNC(m.maturity_date) d
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.maturity_date <= k_arrete
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
             GROUP BY etat
             ORDER BY 3 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.etat, 30) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fnum(r.nbr), 14) || '|'
                || fpadl(fmio(r.mtr), 20) || '|'
                || fpadl(CASE WHEN r.dm IS NULL THEN '-' ELSE TO_CHAR(ROUND(r.dm, 1)) || ' j' END, 14) || '|'
                || fpadl(CASE WHEN r.dmax IS NULL THEN '-' ELSE fnum(r.dmax) || ' j' END, 20) || '|');
        END LOOP;
        tbl_line('4,30,12,20,14,20,14,20');


        -- -----------------------------------------------------
        print_sub('Population des contrats echus de longue date (information)');
        po('  Les operations echues depuis plus de ' || TO_CHAR(k_ech_ancien) || ' jours, quel que soit leur etat');
        po('  de remboursement. Ce n''est pas une anomalie mais la population qui devrait');
        po('  etre entierement denouee et soldee comptablement ; elle sert de base aux');
        po('  tests MM-402, MM-503 et MM-608, qui portent les verdicts.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND TRUNC(k_arrete) - TRUNC(m.maturity_date) > k_ech_ancien;
        print_kv('Contrats echus depuis plus de ' || TO_CHAR(k_ech_ancien) || ' jours',
                 fnum(v_cnt) || '   ' || fpct(v_cnt, v_nb_ctr));
        print_kv('Nominal cumule de cette population', fmio(v_mt));

        print_sub('Anciennete des contrats echus');
        tbl_line('4,30,12,20,12,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('ANCIENNETE DE L''ECHEANCE', 30) || '|' || fpadl('NB', 12) || '|'
            || fpadl('NOMINAL', 20) || '|' || fpadl('% NB', 12) || '|' || fpadl('DONT NON SOLDE', 20) || '|');
        tbl_line('4,30,12,20,12,20');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(nom) mt,
                   SUM(CASE WHEN rembt < nom - k_tol_abs THEN nom ELSE 0 END) ns
              FROM (SELECT CASE
                             WHEN TRUNC(k_arrete) - TRUNC(m.maturity_date) < 0    THEN '0. non echu'
                             WHEN TRUNC(k_arrete) - TRUNC(m.maturity_date) <= 30  THEN '1. moins de 30 jours'
                             WHEN TRUNC(k_arrete) - TRUNC(m.maturity_date) <= 90  THEN '2. 31 a 90 jours'
                             WHEN TRUNC(k_arrete) - TRUNC(m.maturity_date) <= 365 THEN '3. 91 a 365 jours'
                             WHEN TRUNC(k_arrete) - TRUNC(m.maturity_date) <= 730 THEN '4. 1 a 2 ans'
                             ELSE                                                      '5. plus de 2 ans'
                           END tr,
                           m.lcy_amount nom,
                           NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                                 WHERE l.contract_ref_no = m.contract_ref_no
                                   AND l.component = 'PRINCIPAL'), 0) rembt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 30) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|'
                || fpadl(fmio(r.ns), 20) || '|');
        END LOOP;
        tbl_line('4,30,12,20,12,20');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 5 : RAPPROCHEMENT COMPTABLE');
    -- ########################################################################

    -- =========================================================
    -- 14. MM-6xx : COMPTABILISATION
    -- =========================================================
    print_section('14. CONTROLES MM-6xx : RAPPROCHEMENT AVEC LA COMPTABILITE');
    BEGIN
        po('  Les ecritures du module sont stockees dans ACTB_HISTORY. La cle de');
        po('  rapprochement est TRN_REF_NO, egal au CONTRACT_REF_NO du contrat.');
        po('  ATTENTION : cette section lit une table volumineuse, comptez quelques minutes.');

        print_sub('14.1 Cartographie des ecritures du module ' || k_mod);
        tbl_line('4,12,10,16,14,20,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('EVENEMENT', 12) || '|' || fpad('SENS', 10) || '|'
            || fpad('TAG DE MONTANT', 16) || '|' || fpadl('NB ECRITURES', 14) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('1ERE ECRITURE', 20) || '|'
            || fpadl('DERNIERE ECRITURE', 20) || '|');
        tbl_line('4,12,10,16,14,20,20,20');
        v_row := 0;
        FOR r IN (
            SELECT h.event, h.drcr_ind, h.amount_tag, COUNT(*) nb,
                   SUM(NVL(h.lcy_amount, 0)) mt, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
              FROM actb_history h
             WHERE h.module = k_mod
             GROUP BY h.event, h.drcr_ind, h.amount_tag
             ORDER BY 4 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.event, 12) || '|' || fpad(r.drcr_ind, 10) || '|'
                || fpad(r.amount_tag, 16) || '|' || fpadl(fnum(r.nb), 14) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fdt(r.d1), 20) || '|' || fpadl(fdt(r.d2), 20) || '|');
        END LOOP;
        tbl_line('4,12,10,16,14,20,20,20');

        print_sub('14.2 Comptes et generaux mouvementes par le module ' || k_mod);
        tbl_line('4,22,40,8,8,14,20,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE / GENERAL', 22) || '|' || fpad('LIBELLE', 40) || '|'
            || fpad('CCY', 8) || '|' || fpad('C/GL', 8) || '|' || fpadl('NB ECRITURES', 14) || '|'
            || fpadl('TOTAL DEBIT', 20) || '|' || fpadl('TOTAL CREDIT', 20) || '|');
        tbl_line('4,22,40,8,8,14,20,20');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT h.ac_no,
                           (SELECT MAX(a.ac_gl_desc) FROM sttb_account a WHERE a.ac_gl_no = h.ac_no) lib,
                           MAX(h.ac_ccy) ccy, MAX(h.cust_gl) cgl, COUNT(*) nb,
                           SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                           SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                      FROM actb_history h
                     WHERE h.module = k_mod
                     GROUP BY h.ac_no
                     ORDER BY COUNT(*) DESC
                  ) WHERE ROWNUM <= 40) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 40) || '|'
                || fpad(r.ccy, 8) || '|' || fpad(r.cgl, 8) || '|' || fpadl(fnum(r.nb), 14) || '|'
                || fpadl(fmio(r.deb), 20) || '|' || fpadl(fmio(r.cre), 20) || '|');
        END LOOP;
        tbl_line('4,22,40,8,8,14,20,20');

        -- -----------------------------------------------------
        p_test('MM-601', 'Contrat sans aucune ecriture comptable');
        p_obj('toute operation enregistree doit etre traduite en comptabilite.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no);
        p_verdict('MM-601', 'Contrat sans aucune ecriture comptable', v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('STATUT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               TRIM(m.contract_status) st
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = m.contract_ref_no)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date, 'statut ' || r.st);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('MM-602', 'Ecriture du module sans contrat correspondant');
        p_obj('toute ecriture du module doit se rattacher a un contrat existant.');
        SELECT COUNT(*), NVL(SUM(NVL(h.lcy_amount, 0)), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = h.trn_ref_no);
        p_verdict('MM-602', 'Ecriture comptable sans contrat correspondant', v_cnt, NULL, v_mt, 'CRITIQUE');

        -- -----------------------------------------------------
        p_test('MM-603', 'Desequilibre entre debits et credits');
        p_obj('pour chaque contrat, la somme des debits doit egaler la somme des credits.');
        SELECT COUNT(*), NVL(SUM(ABS(deb - cre)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                       SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE ABS(deb - cre) > k_tol_abs;
        p_verdict('MM-603', 'Contrat dont les debits et credits ne s''equilibrent pas',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,14,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('NB ECRITURES', 14) || '|'
                || fpadl('TOTAL DEBIT', 20) || '|' || fpadl('TOTAL CREDIT', 20) || '|'
                || fpadl('ECART', 20) || '|');
            tbl_line('4,22,12,12,14,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.trn_ref_no) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.trn_ref_no) mat_x
                 FROM (SELECT * FROM (
                        SELECT trn_ref_no, nb, deb, cre FROM (
                            SELECT h.trn_ref_no, COUNT(*) nb,
                                   SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                                   SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                              FROM actb_history h
                             WHERE h.module = k_mod
                             GROUP BY h.trn_ref_no)
                         WHERE ABS(deb - cre) > k_tol_abs
                         ORDER BY ABS(deb - cre) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_ref_no, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(famt(r.deb), 20) || '|'
                    || fpadl(famt(r.cre), 20) || '|' || fpadl(famt(r.deb - r.cre), 20) || '|');
            END LOOP;
            tbl_line('4,22,12,12,14,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-604', 'Montant comptabilise a la mise en place different du nominal');
        p_obj('le debit passe sous le tag PRINCIPAL a l''initiation doit egaler le');
        po('             nominal du contrat.');
        SELECT COUNT(*), NVL(SUM(ABS(nom - cpt)), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.contract_ref_no, m.lcy_amount nom,
                   NVL((SELECT SUM(NVL(h.lcy_amount, 0)) FROM actb_history h
                         WHERE h.trn_ref_no = m.contract_ref_no
                           AND h.module = k_mod
                           AND h.amount_tag = 'PRINCIPAL'
                           AND h.drcr_ind = 'D'), 0) cpt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
               AND EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no
                              AND h.module = k_mod
                              AND h.amount_tag = 'PRINCIPAL')
          )
         WHERE ABS(nom - cpt) > k_tol_abs;
        p_verdict('MM-604', 'Montant comptabilise a la mise en place different du nominal',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,7,28,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 7) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL CONTRAT', 20) || '|'
                || fpadl('DEBIT COMPTABLE', 20) || '|' || fpadl('ECART', 20) || '|');
            tbl_line('4,22,12,12,7,28,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                SELECT n.* FROM (
                    SELECT m.contract_ref_no ref, m.product, m.lcy_amount nom,
                           (SELECT MAX(c.customer_name1) FROM sttm_customer c
                             WHERE c.customer_no = m.counterparty) etat,
                           NVL((SELECT SUM(NVL(h.lcy_amount, 0)) FROM actb_history h
                                 WHERE h.trn_ref_no = m.contract_ref_no
                                   AND h.module = k_mod
                                   AND h.amount_tag = 'PRINCIPAL'
                                   AND h.drcr_ind = 'D'), 0) cpt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no)
                       AND EXISTS (SELECT 1 FROM actb_history h
                                    WHERE h.trn_ref_no = m.contract_ref_no
                                      AND h.module = k_mod
                                      AND h.amount_tag = 'PRINCIPAL')
                ) n
                WHERE ABS(n.nom - n.cpt) > k_tol_abs
                ORDER BY ABS(n.nom - n.cpt) DESC
            ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.product, 7) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpadl(famt(r.cpt), 20) || '|'
                    || fpadl(famt(r.nom - r.cpt), 20) || '|');
            END LOOP;
            tbl_line('4,22,12,12,7,28,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-605', 'Capital liquide en comptabilite different du capital rembourse');
        p_obj('confronter le tag PRINCIPAL_LIQD des ecritures aux paiements enregistres');
        po('             sur la composante PRINCIPAL du contrat.');
        SELECT COUNT(*), NVL(SUM(ABS(rembt - cpt)), 0) INTO v_cnt, v_mt
          FROM (
            SELECT m.contract_ref_no,
                   NVL((SELECT SUM(l.amount_paid) FROM ldtb_contract_liq l
                         WHERE l.contract_ref_no = m.contract_ref_no
                           AND l.component = 'PRINCIPAL'
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_liq_summary q
                                            WHERE q.contract_ref_no = l.contract_ref_no
                                              AND q.event_seq_no = l.event_seq_no
                                              AND NVL(TRIM(q.payment_status), 'A') <> 'A')), 0) rembt,
                   NVL((SELECT SUM(NVL(h.lcy_amount, 0)) FROM actb_history h
                         WHERE h.trn_ref_no = m.contract_ref_no
                           AND h.module = k_mod
                           AND h.amount_tag = 'PRINCIPAL_LIQD'
                           AND h.drcr_ind = 'D'), 0) cpt
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE ABS(rembt - cpt) > k_tol_abs;
        p_verdict('MM-605', 'Capital liquide comptablement different du capital rembourse',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-606', 'Provisions comptabilisees differentes des provisions du contrat');
        p_obj('confronter la somme des ecritures de provision (tags se terminant par');
        po('             ACCR) au cumul des provisions nettes enregistrees sur le contrat.');
        SELECT NVL(SUM(NVL(h.lcy_amount, 0)), 0) INTO v_mt
          FROM actb_history h
         WHERE h.module = k_mod AND h.amount_tag LIKE '%ACCR' AND h.drcr_ind = 'D';
        SELECT NVL(SUM(a.net_accrual), 0) INTO v_mt2
          FROM ldtb_contract_accrual_history a
         WHERE a.module = k_mod;
        print_kv('Provisions comptabilisees (ecritures au debit)', famt(v_mt)  || '  (' || fmio(v_mt) || ')');
        print_kv('Provisions nettes du module (contrats)',         famt(v_mt2) || '  (' || fmio(v_mt2) || ')');
        print_kv('Ecart global',                                   famt(v_mt - v_mt2));
        SELECT COUNT(*), NVL(SUM(ABS(cpt - prov)), 0) INTO v_cnt, v_tot
          FROM (
            SELECT m.contract_ref_no,
                   NVL((SELECT SUM(NVL(h.lcy_amount, 0)) FROM actb_history h
                         WHERE h.trn_ref_no = m.contract_ref_no
                           AND h.module = k_mod
                           AND h.amount_tag LIKE '%ACCR'
                           AND h.drcr_ind = 'D'), 0) cpt,
                   NVL((SELECT SUM(a.net_accrual) FROM ldtb_contract_accrual_history a
                         WHERE a.contract_ref_no = m.contract_ref_no), 0) prov
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
          )
         WHERE ABS(cpt - prov) > k_tol_abs;
        p_verdict('MM-606', 'Provisions comptabilisees differentes des provisions du contrat',
                  v_cnt, v_nb_ctr, v_tot, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-607', 'Ecritures d''extourne');
        p_obj('recenser les extournes (evenements REVC, REVP, REVR). Une extourne est');
        po('             un mecanisme normal de correction : elle n''est pas une anomalie en');
        po('             soi, mais sa volumetrie doit rester maitrisee et chaque extourne');
        po('             doit trouver sa justification. Le test est restitue pour information ;');
        po('             les extournes sans ecriture d''origine sont testees en MM-625b.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod AND h.event IN ('REVC', 'REVP', 'REVR');
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-607', 'Ecritures d''extourne enregistrees', v_cnt, NULL, ABS(v_mt), 'INFO');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,10,10,22,6,20,12,16,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('EVENT', 10) || '|'
                || fpad('TRN_CODE', 10) || '|' || fpad('COMPTE', 22) || '|' || fpad('D/C', 6) || '|'
                || fpadl('MONTANT LCY', 20) || '|' || fpad('DATE', 12) || '|' || fpad('SAISI PAR', 16) || '|'
                || fpad('AUTORISE PAR', 16) || '|');
            tbl_line('4,22,12,12,10,10,22,6,20,12,16,16');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.trn_ref_no) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.trn_ref_no) mat_x
                 FROM (SELECT * FROM (
                        SELECT h.trn_ref_no, h.event, h.trn_code, h.ac_no, h.drcr_ind,
                               h.lcy_amount, h.trn_dt, h.user_id, h.auth_id
                          FROM actb_history h
                         WHERE h.module = k_mod AND h.event IN ('REVC', 'REVP', 'REVR')
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_ref_no, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(r.event, 10) || '|' || fpad(r.trn_code, 10) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(r.drcr_ind, 6) || '|' || fpadl(famt(r.lcy_amount), 20) || '|'
                    || fpad(fdt(r.trn_dt), 12) || '|' || fpad(r.user_id, 16) || '|'
                    || fpad(r.auth_id, 16) || '|');
            END LOOP;
            tbl_line('4,22,12,12,10,10,22,6,20,12,16,16');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-608', 'Ecriture posterieure a l''echeance du contrat');
        p_obj('apres la liquidation d''une operation echue, aucune ecriture nouvelle');
        po('             ne devrait plus lui etre rattachee, hors extourne justifiee.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
         WHERE h.module = k_mod
           AND m.module = k_mod
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND TRUNC(h.trn_dt) > TRUNC(m.maturity_date) + 5;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-608', 'Ecriture passee plus de 5 jours apres l''echeance', v_cnt, NULL, v_mt, 'MOYEN');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 14 BIS. MM-62x : SCHEMAS COMPTABLES ET CYCLE DE VIE DES TITRES
    -- =========================================================
    print_section('14 BIS. CONTROLES MM-62x : SCHEMAS COMPTABLES ET CYCLE DE VIE DES TITRES');
    BEGIN
        po('  ACTB_HISTORY est la table ou le cycle de vie d''une operation se');
        po('  materialise reellement. Cette section reconstitue, a partir des ecritures,');
        po('  le schema comptable applique par produit, puis controle que chaque etape du');
        po('  cycle est correctement denouee.');
        po('');
        po('  CLE DE LECTURE');
        po('    ACTB_HISTORY.TRN_REF_NO = LDTB_CONTRACT_MASTER.CONTRACT_REF_NO');
        po('    ACTB_HISTORY.AC_NO      = STTB_ACCOUNT.AC_GL_NO');
        po('    STTB_ACCOUNT.AC_NATURAL_GL donne le compte general naturel, donc la');
        po('    nature comptable reelle de la ligne.');
        po('');
        po('  REQUETE DE REFERENCE POUR DEROULER UN CONTRAT A LA MAIN');
        po('    select trn_ref_no, ac_gl_desc, ac_no, drcr_ind, a.lcy_amount, a.product,');
        po('           amount, main_comp_amount, trn_dt, amount_tag, b.main_comp_rate,');
        po('           booking_date, maturity_date, ac_natural_gl');
        po('      from actb_history a');
        po('      left join ldtb_contract_master b on b.contract_ref_no = a.trn_ref_no');
        po('      left join sttb_account on ac_no = ac_gl_no');
        po('     where trn_ref_no in (...)');
        po('     order by trn_ref_no, trn_dt, a.lcy_amount desc, drcr_ind desc;');

        print_sub('14B.0 Schema comptable attendu, par mode de comptabilisation des interets');
        po('  Les operations se repartissent en deux familles selon que l''interet est');
        po('  encaisse a la souscription ou a l''echeance. Le schema attendu en decoule.');
        po('');
        po('  FAMILLE 1 - INTERETS POSTCOMPTES (interet encaisse a l''echeance)');
        po('    1. Souscription   DEBIT  compte de titres        CREDIT tresorerie');
        po('    2. Provision      DEBIT  creances rattachees     CREDIT produits');
        po('       (une ecriture par jour jusqu''a l''echeance)');
        po('    3. Encaissement   DEBIT  tresorerie              CREDIT creances rattachees');
        po('    4. Liquidation    DEBIT  tresorerie              CREDIT compte de titres');
        po('');
        po('  FAMILLE 2 - INTERETS PRECOMPTES (interet encaisse a la souscription)');
        po('    1a. Souscription  DEBIT  compte de titres        CREDIT tresorerie');
        po('    1b. Interet recu  DEBIT  tresorerie              CREDIT produits constates');
        po('                                                            d''avance');
        po('    2.  Etalement     DEBIT  produits constates      CREDIT produits');
        po('                             d''avance');
        po('       (une ecriture par jour, la dette d''avance se resorbe)');
        po('    3.  Encaissement  neant, l''interet a ete encaisse a l''etape 1b');
        po('    4.  Liquidation   DEBIT  tresorerie              CREDIT compte de titres');
        po('');
        po('  REGLE D''OR');
        po('    Entree de tresorerie = DEBIT tresorerie. Sortie = CREDIT tresorerie.');
        po('    Le produit est toujours un CREDIT d''un compte de resultat, etale sur la');
        po('    duree de detention. Apres liquidation, les comptes de bilan du contrat');
        po('    (titres, creances rattachees, produits constates d''avance) doivent etre');
        po('    soldes.');
        po('');
        po('  Prefixes de comptes naturels retenus (parametrables en tete de script)');
        print_kv('  Titres de placement',              k_gl_tit_pl || '%');
        print_kv('  Titres de transaction',            k_gl_tit_tr || '%');
        print_kv('  Creances rattachees - placement',  k_gl_crat_pl || '%');
        print_kv('  Creances rattachees - transaction', k_gl_crat_tr || '%');
        print_kv('  Produits constates d''avance',     k_gl_pca || '%');
        print_kv('  Revenus des titres (resultat)',    k_gl_prod || '%');
        print_kv('  Tresorerie',                       k_gl_treso || '%');

        -- -----------------------------------------------------
        print_sub('14B.1 Comptes mouvementes par le module');
        po('  La cle est le numero de compte AC_NO, toujours renseigne. Le compte');
        po('  general naturel n''est affiche qu''a titre complementaire : il est souvent');
        po('  vide sur les generaux, ou le numero de compte porte deja la nature.');
        po('');
        tbl_line('4,20,42,16,26,16,22,22,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_NO)', 20) || '|' || fpad('LIBELLE', 42) || '|'
            || fpad('CPT NATUREL', 16) || '|' || fpad('NATURE RETENUE', 26) || '|'
            || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL DEBIT', 22) || '|'
            || fpadl('TOTAL CREDIT', 22) || '|' || fpadl('NB CONTRATS', 14) || '|');
        tbl_line('4,20,42,16,26,16,22,22,14');
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT h.ac_no, MAX(s.nat) nat, MAX(s.lib) lib, COUNT(*) nb,
                       SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                       SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                       COUNT(DISTINCT h.trn_ref_no) nbc,
                       MAX(CASE
                             WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%') THEN 'creances rattachees PL'
                             WHEN (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 'creances rattachees TR'
                             WHEN (h.ac_no LIKE k_gl_tit_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_pl || '%') THEN 'titres de placement'
                             WHEN (h.ac_no LIKE k_gl_tit_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_tr || '%') THEN 'titres de transaction'
                             WHEN (h.ac_no LIKE k_gl_pca || '%' OR NVL(s.nat, ' ') LIKE k_gl_pca || '%') THEN 'produits d avance'
                             WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') THEN 'produits (resultat)'
                             WHEN (h.ac_no LIKE k_gl_treso || '%' OR NVL(s.nat, ' ') LIKE k_gl_treso || '%') THEN 'tresorerie'
                             ELSE 'AUTRE A QUALIFIER'
                           END) nature
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                 WHERE h.module = k_mod
                 GROUP BY h.ac_no
                 ORDER BY COUNT(*) DESC
            ) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 40;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 20) || '|' || fpad(r.lib, 42) || '|'
                    || fpad(r.nat, 16) || '|' || fpad(r.nature, 26) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fmio(r.deb), 22) || '|' || fpadl(fmio(r.cre), 22) || '|'
                    || fpadl(fnum(r.nbc), 14) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,20,42,16,26,16,22,22,14');

        -- -----------------------------------------------------
        print_sub('14B.2 Schema comptable reconstitue : produit x tag de montant x sens');
        po('  C''est le schema REELLEMENT applique, deduit des ecritures et non du');
        po('  parametrage. Chaque ligne se lit comme une regle de comptabilisation.');
        po('');
        tbl_line('4,8,18,6,20,38,16,24,16,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('PROD', 8) || '|' || fpad('TAG DE MONTANT', 18) || '|'
            || fpad('D/C', 6) || '|' || fpad('COMPTE (AC_NO)', 20) || '|' || fpad('LIBELLE', 38) || '|'
            || fpad('CPT NATUREL', 16) || '|' || fpad('NATURE', 24) || '|'
            || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
        tbl_line('4,8,18,6,20,38,16,24,16,22');
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT h.product, h.amount_tag, h.drcr_ind, h.ac_no,
                       MAX(s.nat) nat, MAX(s.lib) lib,
                       COUNT(*) nb, SUM(NVL(h.lcy_amount, 0)) mt,
                       MAX(CASE
                             WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%') THEN 'creances rattachees PL'
                             WHEN (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 'creances rattachees TR'
                             WHEN (h.ac_no LIKE k_gl_tit_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_pl || '%') THEN 'titres de placement'
                             WHEN (h.ac_no LIKE k_gl_tit_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_tr || '%') THEN 'titres de transaction'
                             WHEN (h.ac_no LIKE k_gl_pca || '%' OR NVL(s.nat, ' ') LIKE k_gl_pca || '%') THEN 'produits d avance'
                             WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') THEN 'produits (resultat)'
                             WHEN (h.ac_no LIKE k_gl_treso || '%' OR NVL(s.nat, ' ') LIKE k_gl_treso || '%') THEN 'tresorerie'
                             ELSE 'AUTRE A QUALIFIER'
                           END) nature
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                 WHERE h.module = k_mod
                 GROUP BY h.product, h.amount_tag, h.drcr_ind, h.ac_no
                 ORDER BY h.product, h.amount_tag, h.drcr_ind DESC
            ) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 120;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 8) || '|'
                    || fpad(r.amount_tag, 18) || '|' || fpad(r.drcr_ind, 6) || '|' || fpad(r.ac_no, 20) || '|'
                    || fpad(r.lib, 38) || '|' || fpad(r.nat, 16) || '|' || fpad(r.nature, 24) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,8,18,6,20,38,16,24,16,22');

        -- -----------------------------------------------------
        print_sub('14B.3 Mode de comptabilisation des interets, par produit');
        po('  Un produit qui mouvemente un compte de produits constates d''avance');
        po('  encaisse ses interets a la souscription : il est PRECOMPTE. Un produit qui');
        po('  mouvemente un compte de creances rattachees les encaisse a l''echeance : il');
        po('  est POSTCOMPTE. Le delai median entre la date de valeur et l''encaissement');
        po('  des interets confirme le classement.');
        po('');
        tbl_line('4,8,36,14,16,16,18,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('PROD', 8) || '|' || fpad('LIBELLE DU PRODUIT', 36) || '|'
            || fpadl('NB CONTRATS', 14) || '|' || fpadl('ECR. AVANCE', 16) || '|'
            || fpadl('ECR. RATTACHEES', 16) || '|' || fpad('MODE DEDUIT', 18) || '|'
            || fpadl('DELAI MEDIAN (J)', 20) || '|');
        tbl_line('4,8,36,14,16,16,18,20');
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT h.product,
                       (SELECT MAX(p.product_description) FROM cstm_product p
                         WHERE p.product_code = h.product AND p.module = k_mod) lib,
                       COUNT(DISTINCT h.trn_ref_no) nbc,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_pca || '%' OR NVL(s.nat, ' ') LIKE k_gl_pca || '%') THEN 1 ELSE 0 END) n_pca,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%')
                                  OR (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 1 ELSE 0 END) n_crat,
                       MEDIAN(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                   THEN TRUNC(h.trn_dt) - TRUNC(m.value_date) END) dm
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                  LEFT JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                                                  AND m.version_no = 1
                 WHERE h.module = k_mod
                 GROUP BY h.product
                 ORDER BY COUNT(*) DESC
            ) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 8) || '|' || fpad(r.lib, 36) || '|'
                    || fpadl(fnum(r.nbc), 14) || '|' || fpadl(fnum(r.n_pca), 16) || '|'
                    || fpadl(fnum(r.n_crat), 16) || '|'
                    || fpad(CASE WHEN r.n_pca > 0 AND r.n_crat = 0 THEN 'PRECOMPTE'
                                 WHEN r.n_crat > 0 AND r.n_pca = 0 THEN 'POSTCOMPTE'
                                 WHEN r.n_pca > 0 AND r.n_crat > 0 THEN 'MIXTE A EXPLIQUER'
                                 ELSE 'INDETERMINE' END, 18) || '|'
                    || fpadl(CASE WHEN r.dm IS NULL THEN '-' ELSE TO_CHAR(ROUND(r.dm)) END, 20) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,8,36,14,16,16,18,20');
        po('  Un delai median proche de zero confirme un interet precompte ; un delai');
        po('  proche de la duree du contrat confirme un interet postcompte.');

        -- -----------------------------------------------------
        print_sub('14B.4 Cycle de vie detaille d''un contrat representatif par produit');
        po('  Pour chaque produit, le contrat retenu est celui qui presente le plus grand');
        po('  nombre de tags de montant distincts, donc le cycle le plus complet. Les');
        po('  provisions quotidiennes sont resumees en une ligne pour la lisibilite.');
        BEGIN
            FOR c IN (
                SELECT product, ref FROM (
                    SELECT m.product, h.trn_ref_no ref,
                           ROW_NUMBER() OVER (PARTITION BY m.product
                                              ORDER BY COUNT(DISTINCT h.amount_tag) DESC,
                                                       MAX(h.trn_dt) DESC) rn
                      FROM actb_history h
                      JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                     WHERE h.module = k_mod
                       AND m.module = k_mod
                       AND m.version_no = 1
                     GROUP BY m.product, h.trn_ref_no
                ) WHERE rn = 1
                ORDER BY product
            ) LOOP
                po('');
                po('  --- PRODUIT ' || c.product || ' - CONTRAT ' || c.ref || ' ---');
                BEGIN
                    FOR d IN (SELECT m.lcy_amount nom, m.main_comp_rate tx, m.main_comp_amount it,
                                     m.main_comp comp, m.value_date vd, m.maturity_date md,
                                     TRIM(m.contract_status) st,
                                     (SELECT MAX(x.customer_name1) FROM sttm_customer x
                                       WHERE x.customer_no = m.counterparty) etat
                                FROM ldtb_contract_master m
                               WHERE m.contract_ref_no = c.ref AND m.version_no = 1) LOOP
                        print_kv('    Contrepartie',          d.etat);
                        print_kv('    Nominal',               famt(d.nom));
                        print_kv('    Taux et composante',    ftx(d.tx) || '   ' || d.comp);
                        print_kv('    Interets contractuels', famt(d.it));
                        print_kv('    Valeur / echeance',     fdt(d.vd) || ' au ' || fdt(d.md)
                                 || '   (' || fnum(d.md - d.vd) || ' jours)');
                        print_kv('    Statut du contrat',     d.st);
                    END LOOP;
                EXCEPTION
                    WHEN OTHERS THEN po('    !! ' || SQLERRM);
                END;
                po('');
                tbl_line('4,12,10,18,6,20,34,14,20,12');
                po('  |' || fpad('N#', 4) || '|' || fpad('DATE', 12) || '|' || fpad('EVENT', 10) || '|'
                    || fpad('TAG DE MONTANT', 18) || '|' || fpad('D/C', 6) || '|'
                    || fpad('COMPTE (AC_NO)', 20) || '|' || fpad('LIBELLE DU COMPTE', 34) || '|'
                    || fpad('CPT NATUREL', 14) || '|' || fpadl('MONTANT LCY', 20) || '|'
                    || fpadl('NB LIGNES', 12) || '|');
                tbl_line('4,12,10,18,6,20,34,14,20,12');
                v_row := 0;
                BEGIN
                    FOR r IN (
                        SELECT dt, event, amount_tag, drcr_ind, ac_no, nat, lib, mt, nb, ord FROM (
                            -- toutes les ecritures hors provisions, une ligne chacune
                            SELECT TO_CHAR(h.trn_dt, 'DD/MM/YYYY') dt, h.event, h.amount_tag,
                                   h.drcr_ind, h.ac_no, s.nat, s.lib, NVL(h.lcy_amount, 0) mt, 1 nb,
                                   h.trn_dt ord
                              FROM actb_history h
                              LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                           FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                             WHERE h.trn_ref_no = c.ref
                               AND h.module = k_mod
                               AND h.event <> 'ACCR'
                            UNION ALL
                            -- provisions quotidiennes resumees en une ligne par compte et sens
                            SELECT TO_CHAR(MIN(h.trn_dt), 'DD/MM/YYYY') || ' a '
                                   || TO_CHAR(MAX(h.trn_dt), 'DD/MM'), 'ACCR', h.amount_tag,
                                   h.drcr_ind, h.ac_no, s.nat, s.lib, SUM(NVL(h.lcy_amount, 0)),
                                   COUNT(*), MIN(h.trn_dt)
                              FROM actb_history h
                              LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                           FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                             WHERE h.trn_ref_no = c.ref
                               AND h.module = k_mod
                               AND h.event = 'ACCR'
                             GROUP BY h.amount_tag, h.drcr_ind, h.ac_no, s.nat, s.lib
                        ) ORDER BY ord, mt DESC, drcr_ind DESC
                    ) LOOP
                        v_row := v_row + 1;
                        EXIT WHEN v_row > 40;
                        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.dt, 12) || '|'
                            || fpad(r.event, 10) || '|' || fpad(r.amount_tag, 18) || '|'
                            || fpad(r.drcr_ind, 6) || '|' || fpad(r.ac_no, 20) || '|'
                            || fpad(r.lib, 34) || '|' || fpad(r.nat, 14) || '|'
                            || fpadl(famt(r.mt), 20) || '|' || fpadl(fnum(r.nb), 12) || '|');
                    END LOOP;
                EXCEPTION
                    WHEN OTHERS THEN po('    !! ' || SQLERRM);
                END;
                tbl_line('4,12,10,18,6,20,34,14,20,12');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;


        -- -----------------------------------------------------
        p_test('MM-621', 'Contrat liquide dont le compte de titres n''est pas solde');
        p_obj('apres liquidation, la somme des debits du compte de titres doit egaler');
        po('             la somme de ses credits : le titre est sorti du bilan.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%')
                                  OR (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 0
                                WHEN (h.ac_no LIKE k_gl_tit_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_pl || '%')
                                  OR (h.ac_no LIKE k_gl_tit_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_tr || '%')
                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END) sld,
                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE n_liq > 0 AND ABS(sld) > k_tol_abs;
        p_verdict('MM-621', 'Contrat liquide dont le compte de titres n''est pas solde',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,8,28,20,20,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('PROD', 8) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|'
                || fpadl('SOLDE TITRES', 20) || '|' || fpad('ECHEANCE', 20) || '|');
            tbl_line('4,22,12,8,28,20,20,20');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x
                 FROM (SELECT * FROM (
                        SELECT q.ref, MAX(m.product) prod, MAX(m.lcy_amount) nom,
                               MAX(m.maturity_date) md, q.sld,
                               MAX((SELECT MAX(x.customer_name1) FROM sttm_customer x
                                     WHERE x.customer_no = m.counterparty)) etat
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%')
                                                  OR (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 0
                                                WHEN (h.ac_no LIKE k_gl_tit_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_pl || '%')
                                                  OR (h.ac_no LIKE k_gl_tit_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_tit_tr || '%')
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN 1 ELSE 0 END) n_liq
                                  FROM actb_history h
                                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                                               FROM sttb_account GROUP BY ac_gl_no) s
                                         ON s.ac_gl_no = h.ac_no
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          LEFT JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                          AND m.version_no = 1
                         WHERE q.n_liq > 0 AND ABS(q.sld) > k_tol_abs
                         GROUP BY q.ref, q.sld
                         ORDER BY ABS(q.sld) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(r.prod, 8) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpadl(famt(r.sld), 20) || '|'
                    || fpad(fdt(r.md), 20) || '|');
            END LOOP;
            tbl_line('4,22,12,8,28,20,20,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-622', 'Produits constates d''avance non resorbes a l''echeance');
        p_obj('sur un produit a interets precomptes, le compte de produits constates');
        po('             d''avance doit revenir a zero au terme de l''operation : la totalite de');
        po('             l''interet encaisse le premier jour a alors ete virement au resultat.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_pca || '%' OR NVL(s.nat, ' ') LIKE k_gl_pca || '%')
                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END) sld,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_pca || '%' OR NVL(s.nat, ' ') LIKE k_gl_pca || '%') THEN 1 ELSE 0 END) n_pca,
                       MAX(m.maturity_date) md
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                  LEFT JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                                                  AND m.version_no = 1
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE n_pca > 0 AND md <= k_arrete AND ABS(sld) > k_tol_abs;
        p_verdict('MM-622', 'Produits constates d''avance non resorbes a l''echeance',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-623', 'Creances rattachees non soldees apres encaissement des interets');
        p_obj('sur un produit a interets postcomptes, le compte de creances rattachees');
        po('             doit revenir a zero une fois l''interet encaisse.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%')
                                  OR (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%')
                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END) sld,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_crat_pl || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_pl || '%')
                                  OR (h.ac_no LIKE k_gl_crat_tr || '%' OR NVL(s.nat, ' ') LIKE k_gl_crat_tr || '%') THEN 1 ELSE 0 END) n_crat,
                       MAX(m.maturity_date) md
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                  LEFT JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                                                  AND m.version_no = 1
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE n_crat > 0 AND md <= k_arrete AND ABS(sld) > k_tol_abs;
        p_verdict('MM-623', 'Creances rattachees non soldees apres encaissement',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-624', 'Provisions comptabilisees differentes des interets contractuels');
        p_obj('la somme des provisions portees au credit du compte de produits doit');
        po('             egaler les interets prevus au contrat (MAIN_COMP_AMOUNT), une fois');
        po('             l''operation arrivee a son terme.');
        SELECT COUNT(*), NVL(SUM(ABS(prod - it)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') AND h.drcr_ind = 'C'
                                THEN NVL(h.lcy_amount, 0) ELSE 0 END)
                     - SUM(CASE WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') AND h.drcr_ind = 'D'
                                THEN NVL(h.lcy_amount, 0) ELSE 0 END) prod,
                       MAX(NVL(m.main_comp_amount, 0)) it,
                       MAX(m.maturity_date) md
                  FROM actb_history h
                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                               FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                  JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                                             AND m.version_no = 1
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE md <= k_arrete AND it > 0 AND ABS(prod - it) > k_tol_abs;
        p_verdict('MM-624', 'Produits comptabilises differents des interets contractuels',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,8,28,20,20,20,18');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 8) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|'
                || fpadl('INT. CONTRACTUELS', 20) || '|' || fpadl('PRODUITS COMPTA.', 20) || '|'
                || fpadl('ECART', 18) || '|');
            tbl_line('4,22,12,12,8,28,20,20,20,18');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT q.ref, MAX(q.prod) prod, MAX(q.it) it, MAX(m.product) pr,
                               MAX(m.lcy_amount) nom,
                               MAX((SELECT MAX(x.customer_name1) FROM sttm_customer x
                                     WHERE x.customer_no = m.counterparty)) etat
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') AND h.drcr_ind = 'C'
                                                THEN NVL(h.lcy_amount, 0) ELSE 0 END)
                                     - SUM(CASE WHEN (h.ac_no LIKE k_gl_prod || '%' OR NVL(s.nat, ' ') LIKE k_gl_prod || '%') AND h.drcr_ind = 'D'
                                                THEN NVL(h.lcy_amount, 0) ELSE 0 END) prod,
                                       MAX(NVL(m2.main_comp_amount, 0)) it,
                                       MAX(m2.maturity_date) md
                                  FROM actb_history h
                                  LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                                               FROM sttb_account GROUP BY ac_gl_no) s
                                         ON s.ac_gl_no = h.ac_no
                                  JOIN ldtb_contract_master m2 ON m2.contract_ref_no = h.trn_ref_no
                                                              AND m2.version_no = 1
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE q.md <= k_arrete AND q.it > 0 AND ABS(q.prod - q.it) > k_tol_abs
                         GROUP BY q.ref
                         ORDER BY ABS(MAX(q.prod) - MAX(q.it)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.pr, 8) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|' || fpadl(famt(r.it), 20) || '|'
                    || fpadl(famt(r.prod), 20) || '|' || fpadl(famt(r.prod - r.it), 18) || '|');
            END LOOP;
            tbl_line('4,22,12,12,8,28,20,20,20,18');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-625', 'Ecritures a montant negatif (extournes)');
        p_obj('un montant negatif signale une extourne ou une correction retroactive de');
        po('             taux. Chaque ligne negative doit trouver sa ligne d''origine ; le cumul');
        po('             par compte et par sens ne doit jamais devenir negatif.');
        SELECT COUNT(*), COUNT(DISTINCT trn_ref_no), NVL(SUM(lcy_amount), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history
         WHERE module = k_mod AND NVL(lcy_amount, 0) < 0;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-625', 'Ecritures a montant negatif', v_cnt, NULL, ABS(v_mt), 'MOYEN');

        SELECT COUNT(*) INTO v_cnt3
          FROM (SELECT h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                       SUM(NVL(h.lcy_amount, 0)) sld
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind)
         WHERE sld < -k_tol_abs;
        p_verdict('MM-625b', 'Cumul negatif par contrat, tag, compte et sens (extourne sans origine)',
                  v_cnt3, NULL, NULL, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,10,18,6,18,12,28,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('EVENT', 10) || '|' || fpad('TAG DE MONTANT', 18) || '|'
                || fpad('D/C', 6) || '|' || fpad('COMPTE (AC_NO)', 18) || '|' || fpad('GL NATUREL', 12) || '|'
                || fpad('LIBELLE DU COMPTE', 28) || '|' || fpadl('MONTANT LCY', 20) || '|');
            tbl_line('4,22,12,12,10,18,6,18,12,28,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.event, h.amount_tag, h.drcr_ind,
                               h.ac_no, s.nat, s.lib, h.lcy_amount mt,
                               (SELECT MAX(m.booking_date) FROM ldtb_contract_master m
                                 WHERE m.contract_ref_no = h.trn_ref_no) bd,
                               (SELECT MAX(m.maturity_date) FROM ldtb_contract_master m
                                 WHERE m.contract_ref_no = h.trn_ref_no) md
                          FROM actb_history h
                          LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                       FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                         WHERE h.module = k_mod AND NVL(h.lcy_amount, 0) < 0
                         ORDER BY h.lcy_amount
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|' || fpad(fdt(r.bd), 12) || '|'
                    || fpad(fdt(r.md), 12) || '|' || fpad(r.event, 10) || '|' || fpad(r.amount_tag, 18) || '|'
                    || fpad(r.drcr_ind, 6) || '|' || fpad(r.ac_no, 18) || '|' || fpad(r.nat, 12) || '|'
                    || fpad(r.lib, 28) || '|' || fpadl(famt(r.mt), 20) || '|');
            END LOOP;
            tbl_line('4,22,12,12,10,18,6,18,12,28,20');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-626', 'Provisions enregistrees apres la liquidation du contrat');
        p_obj('la liquidation peut intervenir avant l''echeance (cession ou remboursement');
        po('             anticipe). Dans ce cas les provisions doivent s''arreter a la meme date :');
        po('             toute provision posterieure gonfle indument le resultat.');
        SELECT COUNT(*), NVL(SUM(mt), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       MIN(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN h.trn_dt END) d_liq,
                       MAX(CASE WHEN h.event = 'ACCR' THEN h.trn_dt END) d_accr,
                       SUM(CASE WHEN h.event = 'ACCR' THEN NVL(h.lcy_amount, 0) ELSE 0 END) mt
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE d_liq IS NOT NULL AND d_accr IS NOT NULL
           AND TRUNC(d_accr) > TRUNC(d_liq) + 1;
        p_verdict('MM-626', 'Provisions enregistrees apres la liquidation du contrat',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,8,28,20,16,16,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('PROD', 8) || '|'
                || fpad('ETAT EMETTEUR', 28) || '|' || fpadl('NOMINAL', 20) || '|'
                || fpad('LIQUIDATION', 16) || '|' || fpad('DERN. PROVIS.', 16) || '|'
                || fpadl('ECART (JOURS)', 16) || '|');
            tbl_line('4,22,12,12,8,28,20,16,16,16');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                        SELECT q.ref, q.d_liq, q.d_accr, MAX(m.product) pr, MAX(m.lcy_amount) nom,
                               MAX((SELECT MAX(x.customer_name1) FROM sttm_customer x
                                     WHERE x.customer_no = m.counterparty)) etat
                          FROM (SELECT h.trn_ref_no ref,
                                       MIN(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                THEN h.trn_dt END) d_liq,
                                       MAX(CASE WHEN h.event = 'ACCR' THEN h.trn_dt END) d_accr
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          LEFT JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                          AND m.version_no = 1
                         WHERE q.d_liq IS NOT NULL AND q.d_accr IS NOT NULL
                           AND TRUNC(q.d_accr) > TRUNC(q.d_liq) + 1
                         GROUP BY q.ref, q.d_liq, q.d_accr
                         ORDER BY TRUNC(q.d_accr) - TRUNC(q.d_liq) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|' || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|' || fpad(r.pr, 8) || '|'
                    || fpad(r.etat, 28) || '|' || fpadl(famt(r.nom), 20) || '|'
                    || fpad(fdt(r.d_liq), 16) || '|' || fpad(fdt(r.d_accr), 16) || '|'
                    || fpadl(fnum(TRUNC(r.d_accr) - TRUNC(r.d_liq)), 16) || '|');
            END LOOP;
            tbl_line('4,22,12,12,8,28,20,16,16,16');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-627', 'Tag de montant incoherent avec la composante d''interet du contrat');
        p_obj('un contrat dont la composante principale est INT_BT doit generer des tags');
        po('             INT_BT ; un contrat en INT_OB doit generer des tags INT_OB. Un melange');
        po('             signale un parametrage produit incoherent.');
        SELECT COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0) INTO v_cnt, v_mt
          FROM actb_history h
          JOIN ldtb_contract_master m ON m.contract_ref_no = h.trn_ref_no
                                     AND m.version_no = 1
         WHERE h.module = k_mod
           AND m.module = k_mod
           AND h.amount_tag LIKE 'INT%'
           AND TRIM(m.main_comp) IS NOT NULL
           AND h.amount_tag NOT LIKE TRIM(m.main_comp) || '%';
        p_verdict('MM-627', 'Tag de montant incoherent avec la composante du contrat',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MM-628', 'Ecriture rattachee a un compte introuvable au plan comptable');
        p_obj('tout AC_NO doit exister dans STTB_ACCOUNT. A defaut, la ligne ne peut');
        po('             etre rattachee a aucun compte et sa nature reste inconnue.');
        po('             Le compte general naturel n''est PAS exige ici : il est souvent vide');
        po('             sur les generaux, ou le numero de compte porte deja la nature.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND NOT EXISTS (SELECT 1 FROM sttb_account a WHERE a.ac_gl_no = h.ac_no);
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-628', 'Ecriture dont le compte est absent de STTB_ACCOUNT',
                  v_cnt, NULL, v_mt, 'ELEVE');

        print_sub('MM-628 bis. Taux de renseignement du compte general naturel');
        po('  Pour memoire : la proportion de lignes dont AC_NATURAL_GL est vide. Un');
        po('  taux eleve est normal sur les generaux et ne constitue pas une anomalie ;');
        po('  il justifie que les tests de cette section raisonnent d''abord sur AC_NO.');
        BEGIN
            SELECT COUNT(*),
                   SUM(CASE WHEN TRIM(s.nat) IS NULL THEN 1 ELSE 0 END),
                   COUNT(DISTINCT h.ac_no),
                   COUNT(DISTINCT CASE WHEN TRIM(s.nat) IS NULL THEN h.ac_no END)
              INTO v_tot, v_cnt, v_cnt2, v_cnt3
              FROM actb_history h
              LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                           FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
             WHERE h.module = k_mod;
            print_kv('Ecritures du module',                   fnum(v_tot));
            print_kv('Dont sans compte general naturel',      fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
            print_kv('Comptes distincts mouvementes',         fnum(v_cnt2));
            print_kv('Dont sans compte general naturel',      fnum(v_cnt3) || '   ' || fpct(v_cnt3, v_cnt2));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;

        -- -----------------------------------------------------
        p_test('MM-629', 'Compte mouvemente hors du schema comptable attendu');
        p_obj('les operations ne devraient toucher que les titres, les creances');
        po('             rattachees, les produits constates d''avance, les produits et la');
        po('             tresorerie. Tout autre compte doit etre explique.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                       FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
         WHERE h.module = k_mod
           AND h.ac_no NOT LIKE k_gl_tit_pl || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_tit_pl || '%'
           AND h.ac_no NOT LIKE k_gl_tit_tr || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_tit_tr || '%'
           AND h.ac_no NOT LIKE k_gl_pca || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_pca || '%'
           AND h.ac_no NOT LIKE k_gl_prod || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_prod || '%'
           AND h.ac_no NOT LIKE k_gl_treso || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_treso || '%';
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-629', 'Compte mouvemente hors du schema comptable attendu',
                  v_cnt, NULL, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,18,12,34,16,22,22,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_NO)', 18) || '|' || fpad('GL NATUREL', 12) || '|'
                || fpad('LIBELLE', 34) || '|' || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL DEBIT', 22) || '|'
                || fpadl('TOTAL CREDIT', 22) || '|' || fpadl('NB CONTRATS', 14) || '|');
            tbl_line('4,18,12,34,16,22,22,14');
            v_row := 0;
            FOR r IN (SELECT h.ac_no, MAX(s.nat) nat, MAX(s.lib) lib, COUNT(*) nb,
                             SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                             SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                             COUNT(DISTINCT h.trn_ref_no) nbc
                        FROM actb_history h
                        LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                     FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                       WHERE h.module = k_mod
                         AND h.ac_no NOT LIKE k_gl_tit_pl || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_tit_pl || '%'
                         AND h.ac_no NOT LIKE k_gl_tit_tr || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_tit_tr || '%'
                         AND h.ac_no NOT LIKE k_gl_pca || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_pca || '%'
                         AND h.ac_no NOT LIKE k_gl_prod || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_prod || '%'
                         AND h.ac_no NOT LIKE k_gl_treso || '%' AND NVL(s.nat, ' ') NOT LIKE k_gl_treso || '%'
                       GROUP BY h.ac_no
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > k_top;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 18) || '|' || fpad(r.nat, 12) || '|'
                    || fpad(r.lib, 34) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.deb), 22) || '|'
                    || fpadl(fmio(r.cre), 22) || '|' || fpadl(fnum(r.nbc), 14) || '|');
            END LOOP;
            tbl_line('4,18,12,34,16,22,22,14');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-630', 'Desequilibre debit credit par tag de montant');
        p_obj('chaque tag de montant porte les deux jambes d''une meme ecriture : ses');
        po('             debits doivent egaler ses credits, sur l''ensemble du module.');
        tbl_line('4,20,16,22,22,22,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('TAG DE MONTANT', 20) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('TOTAL DEBIT', 22) || '|' || fpadl('TOTAL CREDIT', 22) || '|'
            || fpadl('ECART', 22) || '|' || fpadl('VERDICT', 14) || '|');
        tbl_line('4,20,16,22,22,22,14');
        v_row := 0;
        v_cnt := 0;
        BEGIN
            FOR r IN (SELECT h.amount_tag, COUNT(*) nb,
                             SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                             SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                        FROM actb_history h
                       WHERE h.module = k_mod
                       GROUP BY h.amount_tag
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                IF ABS(r.deb - r.cre) > k_tol_abs THEN
                    v_cnt := v_cnt + 1;
                END IF;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.amount_tag, 20) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(famt(r.deb), 22) || '|'
                    || fpadl(famt(r.cre), 22) || '|' || fpadl(famt(r.deb - r.cre), 22) || '|'
                    || fpadl(CASE WHEN ABS(r.deb - r.cre) > k_tol_abs THEN 'ECART' ELSE 'OK' END, 14) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,20,16,22,22,22,14');
        p_verdict('MM-630', 'Tag de montant dont les debits n''egalent pas les credits',
                  v_cnt, v_row, NULL, 'CRITIQUE');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 6 : GOUVERNANCE, SEPARATION DES TACHES ET PISTE D''AUDIT');
    -- ########################################################################

    -- =========================================================
    -- 15. MM-7xx : GOUVERNANCE ET PISTE D'AUDIT
    -- =========================================================
    print_section('15. CONTROLES MM-7xx : GOUVERNANCE ET PISTE D''AUDIT');
    BEGIN
        po('  LDTB_CONTRACT_MASTER ne conserve ni le saisisseur ni le validateur du');
        po('  contrat. La piste d''audit passe donc par ACTB_HISTORY (USER_ID et AUTH_ID)');
        po('  et par LDTB_CONTRACT_CONTROL (verrous de saisie).');

        print_sub('15.1 Qui saisit et qui autorise les operations du module ' || k_mod);
        tbl_line('4,20,20,14,16,14,20,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('SAISI PAR', 20) || '|' || fpad('AUTORISE PAR', 20) || '|'
            || fpadl('NB CONTRATS', 14) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpad('DERNIERE', 14) || '|' || fpadl('MONTANT LCY', 20) || '|'
            || fpadl('AUTO-AUTOR.', 14) || '|');
        tbl_line('4,20,20,14,16,14,20,14');
        v_row := 0;
        FOR r IN (
            SELECT h.user_id, h.auth_id, COUNT(DISTINCT h.trn_ref_no) nbc, COUNT(*) nb,
                   MAX(h.trn_dt) d2, SUM(NVL(h.lcy_amount, 0)) mt
              FROM actb_history h
             WHERE h.module = k_mod
             GROUP BY h.user_id, h.auth_id
             ORDER BY 4 DESC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 20) || '|' || fpad(r.auth_id, 20) || '|'
                || fpadl(fnum(r.nbc), 14) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpad(fdt(r.d2), 14) || '|'
                || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(CASE WHEN r.user_id = r.auth_id THEN 'OUI' ELSE 'non' END, 14) || '|');
        END LOOP;
        tbl_line('4,20,20,14,16,14,20,14');

        -- -----------------------------------------------------
        p_test('MM-701', 'Ecritures auto-autorisees par un utilisateur nominatif');
        p_obj('un meme utilisateur ne doit pas etre a la fois saisisseur et');
        po('             autorisateur. Les ecritures generees par le traitement automatique');
        po('             (SYSTEM) sont exclues et comptees separement.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.user_id = h.auth_id
           AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM';
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-701', 'Ecriture saisie et autorisee par le meme utilisateur nominatif',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        SELECT COUNT(*) INTO v_cnt3
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.user_id = h.auth_id
           AND UPPER(NVL(TRIM(h.user_id), 'X')) = 'SYSTEM';
        print_kv('Pour memoire, ecritures automatiques SYSTEM auto-autorisees', fnum(v_cnt3));

        -- -----------------------------------------------------
        p_test('MM-702', 'Intervenants disposant du privilege d''auto-autorisation');
        p_obj('un utilisateur dont AUTO_AUTH vaut Y peut valider ses propres saisies.');
        po('             Sa presence sur le module est un point de controle majeur.');
        tbl_line('4,18,30,10,10,10,10,14,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('UTILISATEUR', 18) || '|' || fpad('NOM', 30) || '|'
            || fpad('STATUT', 10) || '|' || fpad('CATEG.', 10) || '|' || fpad('AUTO_AUTH', 10) || '|'
            || fpad('AGENCE', 10) || '|' || fpadl('NB ECRITURES', 14) || '|'
            || fpadl('MONTANT LCY', 16) || '|');
        tbl_line('4,18,30,10,10,10,10,14,16');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (
            SELECT u.user_id, u.user_name, u.user_status, u.user_category, u.auto_auth,
                   u.home_branch, x.nb, x.mt
              FROM smtb_user u
              JOIN (SELECT h.user_id usr_id, COUNT(*) nb, SUM(NVL(h.lcy_amount, 0)) mt
                      FROM actb_history h WHERE h.module = k_mod
                     GROUP BY h.user_id) x ON x.usr_id = u.user_id
             ORDER BY x.nb DESC
        ) LOOP
            v_row := v_row + 1;
            IF NVL(TRIM(r.auto_auth), 'N') = 'Y' THEN
                v_cnt := v_cnt + 1;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 18) || '|' || fpad(r.user_name, 30) || '|'
                || fpad(r.user_status, 10) || '|' || fpad(r.user_category, 10) || '|'
                || fpad(r.auto_auth, 10) || '|' || fpad(r.home_branch, 10) || '|'
                || fpadl(fnum(r.nb), 14) || '|' || fpadl(fmio(r.mt), 16) || '|');
        END LOOP;
        tbl_line('4,18,30,10,10,10,10,14,16');
        p_verdict('MM-702', 'Intervenants du module disposant de l''auto-autorisation',
                  v_cnt, v_row, NULL, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MM-703', 'Operations deversees par une application externe');
        p_obj('identifier les operations dont les ecritures ont ete produites par un');
        po('             utilisateur applicatif correspondant au motif ' || k_pat || '.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND (h.user_id LIKE k_pat OR NVL(h.auth_id, 'X') LIKE k_pat);
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MM-703', 'Ecritures du module produites par l''application externe',
                  v_cnt, NULL, v_mt, 'INFO');

        print_sub('MM-703 bis. Fiche des utilisateurs applicatifs correspondant a ' || k_pat);
        v_row := 0;
        FOR r IN (SELECT u.user_id, u.user_name, u.user_status, u.user_category, u.auto_auth,
                         u.start_date, u.end_date, u.home_branch, u.dflt_module, u.ldap_user,
                         u.record_stat, u.auth_stat
                    FROM smtb_user u
                   WHERE u.user_id LIKE k_pat OR NVL(u.user_name, 'X') LIKE k_pat
                      OR NVL(u.ldap_user, 'X') LIKE k_pat
                   ORDER BY u.user_id) LOOP
            v_row := v_row + 1;
            po('');
            po('    --- UTILISATEUR . ' || r.user_id || ' ---');
            print_kv('  Nom complet',                    r.user_name);
            print_kv('  Statut (USER_STATUS)',           r.user_status);
            print_kv('  Categorie (USER_CATEGORY)',      r.user_category);
            print_kv('  Auto-autorisation (AUTO_AUTH)',  r.auto_auth);
            print_kv('  Date de debut',                  fdt(r.start_date));
            print_kv('  Date de fin',                    fdt(r.end_date));
            print_kv('  Agence de rattachement',         r.home_branch);
            print_kv('  Module par defaut',              r.dflt_module);
            print_kv('  Utilisateur LDAP',               r.ldap_user);
            print_kv('  Etat de la fiche',               r.record_stat || ' / ' || r.auth_stat);
            print_kv('  Ecritures sur le module ' || k_mod,
                     f_lbl_cnt(f_count('ACTB_HISTORY', 'MODULE = ''' || k_mod
                               || ''' AND USER_ID = ''' || r.user_id || '''')));
            print_kv('  Ecritures tous modules',
                     f_lbl_cnt(f_count('ACTB_HISTORY', 'USER_ID = ''' || r.user_id || '''')));
        END LOOP;
        IF v_row = 0 THEN
            po('    (aucun utilisateur ne correspond au motif ' || k_pat || ')');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-704', 'Concentration de la saisie sur un nombre restreint d''intervenants');
        p_obj('mesurer le poids du premier saisisseur nominatif dans les montants');
        po('             enregistres. Une concentration excessive fragilise le controle.');
        SELECT NVL(SUM(NVL(h.lcy_amount, 0)), 0) INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod
           AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM';
        tbl_line('4,20,30,14,16,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('SAISI PAR', 20) || '|' || fpad('NOM', 30) || '|'
            || fpadl('NB CONTRATS', 14) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('% MONTANT', 12) || '|');
        tbl_line('4,20,30,14,16,20,12');
        v_row := 0;
        v_mt  := 0;
        FOR r IN (
            SELECT h.user_id, COUNT(DISTINCT h.trn_ref_no) nbc, COUNT(*) nb,
                   SUM(NVL(h.lcy_amount, 0)) mt,
                   (SELECT MAX(u.user_name) FROM smtb_user u WHERE u.user_id = h.user_id) nom
              FROM actb_history h
             WHERE h.module = k_mod
               AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM'
             GROUP BY h.user_id
             ORDER BY 4 DESC
        ) LOOP
            v_row := v_row + 1;
            IF v_row = 1 THEN
                v_mt := r.mt;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 20) || '|' || fpad(r.nom, 30) || '|'
                || fpadl(fnum(r.nbc), 14) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 20) || '|'
                || fpadl(fpct(r.mt, v_tot), 12) || '|');
        END LOOP;
        tbl_line('4,20,30,14,16,20,12');
        print_kv('Poids du premier saisisseur', fpct(v_mt, v_tot));
        p_verdict('MM-704', 'Concentration de plus de 50 pourcent des montants sur un seul saisisseur',
                  CASE WHEN v_tot > 0 AND v_mt / v_tot > 0.5 THEN 1 ELSE 0 END, NULL, v_mt, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MM-705', 'Intervenants dont la fiche utilisateur est fermee ou desactivee');
        p_obj('un utilisateur ayant saisi ou autorise des operations doit avoir une');
        po('             fiche active et autorisee, ou une date de fin coherente.');
        SELECT COUNT(*) INTO v_cnt
          FROM (SELECT DISTINCT h.user_id usr_id FROM actb_history h WHERE h.module = k_mod) x
          JOIN smtb_user u ON u.user_id = x.usr_id
         WHERE NVL(TRIM(u.record_stat), 'O') <> 'O'
            OR NVL(TRIM(u.auth_stat), 'A') <> 'A'
            OR UPPER(NVL(TRIM(u.user_status), 'E')) IN ('C', 'D');
        p_verdict('MM-705', 'Intervenant du module dont la fiche est fermee ou desactivee',
                  v_cnt, NULL, NULL, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,20,30,10,10,10,14,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('UTILISATEUR', 20) || '|' || fpad('NOM', 30) || '|'
                || fpad('STATUT', 10) || '|' || fpad('REC_STAT', 10) || '|' || fpad('AUTH', 10) || '|'
                || fpad('DEBUT', 14) || '|' || fpad('FIN', 14) || '|');
            tbl_line('4,20,30,10,10,10,14,14');
            v_row := 0;
            FOR r IN (SELECT u.user_id, u.user_name, u.user_status, u.record_stat, u.auth_stat,
                             u.start_date, u.end_date
                        FROM (SELECT DISTINCT h.user_id usr_id FROM actb_history h WHERE h.module = k_mod) x
                        JOIN smtb_user u ON u.user_id = x.usr_id
                       WHERE NVL(TRIM(u.record_stat), 'O') <> 'O'
                          OR NVL(TRIM(u.auth_stat), 'A') <> 'A'
                          OR UPPER(NVL(TRIM(u.user_status), 'E')) IN ('C', 'D')
                       ORDER BY u.user_id) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 20) || '|'
                    || fpad(r.user_name, 30) || '|' || fpad(r.user_status, 10) || '|'
                    || fpad(r.record_stat, 10) || '|' || fpad(r.auth_stat, 10) || '|'
                    || fpad(fdt(r.start_date), 14) || '|' || fpad(fdt(r.end_date), 14) || '|');
            END LOOP;
            tbl_line('4,20,30,10,10,10,14,14');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-706', 'Contrats amendes apres leur mise en place');
        p_obj('un contrat portant plusieurs versions ou un numero d''evenement eleve a');
        po('             fait l''objet de modifications successives qui doivent etre justifiees.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.version_no > 1;
        p_verdict('MM-706', 'Contrat portant plusieurs versions (amendement)', v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            d_head('VERSION / EVENEMENT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date, m.value_date, m.maturity_date,
                               m.version_no, m.event_seq_no
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND m.version_no > 1
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date, r.maturity_date,
                      'v' || fnum(r.version_no) || ' / evt ' || fnum(r.event_seq_no));
            END LOOP;
            d_foot;
        END IF;

        print_sub('MM-706 bis. Distribution du nombre d''evenements par contrat');
        tbl_line('4,30,12,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('NOMBRE D''EVENEMENTS', 30) || '|' || fpadl('NB CONTRATS', 12) || '|'
            || fpadl('MONTANT LCY', 20) || '|' || fpadl('% NB', 12) || '|');
        tbl_line('4,30,12,20,12');
        v_row := 0;
        FOR r IN (
            SELECT tr, COUNT(*) nb, SUM(mt) mt
              FROM (SELECT CASE
                             WHEN m.event_seq_no = 1   THEN '1. un seul evenement'
                             WHEN m.event_seq_no <= 5  THEN '2. 2 a 5 evenements'
                             WHEN m.event_seq_no <= 20 THEN '3. 6 a 20 evenements'
                             WHEN m.event_seq_no <= 100 THEN '4. 21 a 100 evenements'
                             ELSE                           '5. plus de 100 evenements'
                           END tr, m.lcy_amount mt
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
             GROUP BY tr ORDER BY tr
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 30) || '|' || fpadl(fnum(r.nb), 12) || '|'
                || fpadl(fmio(r.mt), 20) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 12) || '|');
        END LOOP;
        tbl_line('4,30,12,20,12');

        -- -----------------------------------------------------
        p_test('MM-707', 'Verrous de saisie non liberes');
        p_obj('LDTB_CONTRACT_CONTROL conserve les contrats laisses ouverts en saisie.');
        po('             Un verrou ancien bloque le contrat et masque une saisie inachevee.');
        SELECT COUNT(*) INTO v_cnt
          FROM ldtb_contract_control c
         WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                        WHERE m.contract_ref_no = c.contract_ref_no AND m.module = k_mod);
        p_verdict('MM-707', 'Verrou de saisie encore actif sur un contrat du module',
                  v_cnt, v_nb_ctr, NULL, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,22,12,12,20,26,22,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('PROCESSUS', 20) || '|'
                || fpad('OUVERT PAR', 26) || '|' || fpad('DEPUIS LE', 22) || '|'
                || fpadl('ANCIENNETE (J)', 16) || '|');
            tbl_line('4,22,12,12,20,26,22,16');
            v_row := 0;
            FOR r IN (SELECT c.contract_ref_no, c.process_code, c.entry_by, c.entry_time,
                             (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                               WHERE mm.contract_ref_no = c.contract_ref_no) bkg_x,
                             (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                               WHERE mm.contract_ref_no = c.contract_ref_no) mat_x
                        FROM ldtb_contract_control c
                       WHERE EXISTS (SELECT 1 FROM ldtb_contract_master m
                                      WHERE m.contract_ref_no = c.contract_ref_no
                                        AND m.module = k_mod)
                       ORDER BY c.entry_time) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 22) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(r.process_code, 20) || '|' || fpad(r.entry_by, 26) || '|'
                    || fpad(fdth(r.entry_time), 22) || '|'
                    || fpadl(fnum(TRUNC(k_arrete) - TRUNC(r.entry_time)), 16) || '|');
            END LOOP;
            tbl_line('4,22,12,12,20,26,22,16');
        END IF;

        -- -----------------------------------------------------
        p_test('MM-708', 'Arret du module et continuite de la piste d''audit');
        p_obj('verifier que le module continue de produire des ecritures et des');
        po('             provisions a la date d''arrete. Un arret prolonge signale une bascule');
        po('             vers un autre outil ou un abandon du suivi comptable.');
        SELECT MAX(trn_dt) INTO v_d_max  FROM actb_history WHERE module = k_mod;
        SELECT MAX(trn_dt) INTO v_d_glob FROM actb_history;
        SELECT MAX(accrual_to_date) INTO v_d_accr FROM ldtb_contract_accrual_history WHERE module = k_mod;
        print_kv('Derniere ecriture du module ' || k_mod, fdt(v_d_max));
        print_kv('Derniere ecriture tous modules',        fdt(v_d_glob));
        print_kv('Derniere provision du module ' || k_mod, fdt(v_d_accr));
        print_kv('Date d''arrete des controles',           fdt(k_arrete));
        print_kv('Silence du module depuis',
                 fnum(TRUNC(k_arrete) - TRUNC(NVL(v_d_max, k_arrete))) || ' jours');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.maturity_date > NVL(v_d_max, k_arrete)
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no);
        print_kv('Contrats encore vivants a la derniere ecriture du module', fnum(v_cnt));
        print_kv('Nominal correspondant', famt(v_mt) || '  (' || fmio(v_mt) || ')');
        p_verdict('MM-708', 'Module sans ecriture depuis plus de 90 jours alors que des contrats sont vivants',
                  CASE WHEN v_d_max IS NOT NULL
                        AND TRUNC(k_arrete) - TRUNC(v_d_max) > 90
                        AND v_cnt > 0 THEN v_cnt ELSE 0 END,
                  v_nb_ctr, v_mt, 'CRITIQUE');

        print_sub('MM-708 bis. Derniere ecriture comptable par module');
        tbl_line('4,10,16,16,16,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpad('1ERE ECRITURE', 16) || '|'
            || fpad('DERNIERE ECRIT.', 16) || '|' || fpadl('SILENCE (J)', 16) || '|'
            || fpadl('NB ECRITURES', 20) || '|');
        tbl_line('4,10,16,16,16,20');
        v_row := 0;
        FOR r IN (
            SELECT h.module, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2, COUNT(*) nb
              FROM actb_history h
             GROUP BY h.module
             ORDER BY MAX(h.trn_dt) ASC
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module, 10) || '|' || fpad(fdt(r.d1), 16) || '|'
                || fpad(fdt(r.d2), 16) || '|'
                || fpadl(fnum(TRUNC(k_arrete) - TRUNC(r.d2)), 16) || '|' || fpadl(fnum(r.nb), 20) || '|');
        END LOOP;
        tbl_line('4,10,16,16,16,20');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 7 : REFERENTIEL DE CONTROLE COMPTABLE (EXT, DBL, MAP, INT,');
    po('               LIF, REV, CSH, CUT, CLS, STA)');
    -- ########################################################################
    po('');
    po('  Cette partie porte le referentiel de controle transmis par la direction');
    po('  de l''audit interne : 51 controles repartis en dix familles, du controle');
    po('  d''integrite de l''extraction jusqu''aux donnees statiques. Les codes sont');
    po('  ceux du referentiel (EXT-01, DBL-01, ...) de sorte que la matrice de');
    po('  controle et le present rapport se lisent l''un contre l''autre.');
    po('');
    po('  Trois familles ne peuvent etre bouclees dans la base seule :');
    po('    CSH   le rapprochement avec le releve BEAC exige le releve lui-meme ;');
    po('          le script prepare l''extraction des jambes a rapprocher et teste');
    po('          ce qui est verifiable en base (existence et sens de la jambe de');
    po('          reglement, contrepartie de tresorerie).');
    po('    CUT   le rapprochement avec la balance generale et l''etat de position');
    po('          titres exige ces deux etats ; le script reconstitue la position');
    po('          a partir des contrats et la confronte aux soldes comptables.');
    po('    CLS   la politique de valorisation releve du referentiel comptable de');
    po('          la banque ; le script constate la presence ou l''absence');
    po('          d''ecritures de valorisation, ce qui est deja un constat.');
    po('');
    po('  ATTENTION : cette partie lit ACTB_HISTORY a de nombreuses reprises.');
    po('  Comptez plusieurs minutes d''execution.');

    -- =========================================================
    -- 17. EXT : INTEGRITE DE L'EXTRACTION ET EXHAUSTIVITE
    -- =========================================================
    print_section('17. CONTROLES EXT : INTEGRITE DE L''EXTRACTION ET EXHAUSTIVITE');
    BEGIN
        po('  Avant de conclure sur les chiffres, il faut prouver que l''extraction');
        po('  elle-meme ne cree ni ne detruit de lignes. Une jointure qui demultiplie');
        po('  et un DISTINCT qui ecrase produisent le meme rapport faux, dans deux');
        po('  directions opposees.');

        -- -----------------------------------------------------
        p_test('EXT-01', 'Chaque ligne comptable est extraite une fois et une seule');
        p_obj('deux risques distincts. Premier risque : STTB_ACCOUNT porte plusieurs');
        po('             lignes pour un meme AC_GL_NO (une par devise, par agence ou par');
        po('             version), et une jointure directe sur AC_GL_NO demultiplierait alors');
        po('             chaque ecriture. Second risque : la cle de ligne du journal n''est');
        po('             pas unique, auquel cas le comptage lui-meme est faux.');

        SELECT COUNT(*) INTO v_cnt
          FROM (SELECT ac_gl_no FROM sttb_account
                 GROUP BY ac_gl_no HAVING COUNT(*) > 1);
        SELECT COUNT(DISTINCT ac_gl_no) INTO v_tot FROM sttb_account;
        print_kv('Comptes distincts dans STTB_ACCOUNT', fnum(v_tot));
        print_kv('Dont porteurs de plusieurs lignes',   fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        p_verdict('EXT-01', 'Comptes demultipliant les ecritures en cas de jointure directe',
                  v_cnt, v_tot, NULL, 'CRITIQUE');
        IF v_cnt > 0 THEN
            po('     PARADE APPLIQUEE PAR CE SCRIPT . toutes les jointures a STTB_ACCOUNT');
            po('     passent par une vue pre-agregee');
            po('       LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib');
            po('                    FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no');
            po('     qui ramene une ligne et une seule par compte. Aucun total du present');
            po('     rapport n''est donc demultiplie par cette jointure.');
            po('');
            tbl_line('4,22,44,14,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_GL_NO)', 22) || '|'
                || fpad('LIBELLE', 44) || '|' || fpadl('NB LIGNES', 14) || '|'
                || fpadl('DONT UTILISE EN MM', 20) || '|');
            tbl_line('4,22,44,14,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT a.ac_gl_no, MAX(a.ac_gl_desc) lib, COUNT(*) nb,
                               NVL(u.nb_mm, 0) nb_mm
                          FROM sttb_account a
                          LEFT JOIN (SELECT h.ac_no, COUNT(*) nb_mm
                                       FROM actb_history h
                                      WHERE h.module = k_mod
                                      GROUP BY h.ac_no) u ON u.ac_no = a.ac_gl_no
                         GROUP BY a.ac_gl_no, NVL(u.nb_mm, 0)
                        HAVING COUNT(*) > 1
                         ORDER BY NVL(u.nb_mm, 0) DESC, COUNT(*) DESC, a.ac_gl_no
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_gl_no, 22) || '|'
                    || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 14) || '|'
                    || fpadl(fnum(r.nb_mm), 20) || '|');
            END LOOP;
            tbl_line('4,22,44,14,20');
        END IF;

        print_sub('EXT-01 bis. Unicite de la cle de ligne du journal');
        po('  Trois cles candidates sont testees sur les ecritures du module. Une cle');
        po('  non unique interdit toute deduplication fiable.');
        tbl_line('4,50,18,18,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('CLE CANDIDATE', 50) || '|'
            || fpadl('NB LIGNES', 18) || '|' || fpadl('NB CLES DISTINCTES', 18) || '|'
            || fpadl('VERDICT', 14) || '|');
        tbl_line('4,50,18,18,14');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        v_cnt := 0;
        SELECT COUNT(DISTINCT h.ac_branch || '|' || h.ac_entry_sr_no) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        IF v_cnt2 <> v_tot THEN v_cnt := v_cnt + 1; END IF;
        po('  |' || fpadl('1', 4) || '|' || fpad('AC_BRANCH + AC_ENTRY_SR_NO', 50) || '|'
            || fpadl(fnum(v_tot), 18) || '|' || fpadl(fnum(v_cnt2), 18) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NON UNIQUE' END, 14) || '|');
        SELECT COUNT(DISTINCT h.ac_branch || '|' || h.entry_seq_no) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        IF v_cnt2 <> v_tot THEN v_cnt := v_cnt + 1; END IF;
        po('  |' || fpadl('2', 4) || '|' || fpad('AC_BRANCH + ENTRY_SEQ_NO', 50) || '|'
            || fpadl(fnum(v_tot), 18) || '|' || fpadl(fnum(v_cnt2), 18) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NON UNIQUE' END, 14) || '|');
        SELECT COUNT(DISTINCT h.trn_ref_no || '|' || h.event_sr_no || '|' || h.ac_no
                              || '|' || h.drcr_ind || '|' || h.amount_tag) INTO v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        po('  |' || fpadl('3', 4) || '|' || fpad('TRN_REF_NO + EVENT_SR_NO + AC_NO + SENS + TAG', 50) || '|'
            || fpadl(fnum(v_tot), 18) || '|' || fpadl(fnum(v_cnt2), 18) || '|'
            || fpadl(CASE WHEN v_cnt2 = v_tot THEN 'UNIQUE' ELSE 'NON UNIQUE' END, 14) || '|');
        tbl_line('4,50,18,18,14');
        p_verdict('EXT-01b', 'Cles techniques de ligne non uniques sur le module',
                  v_cnt, 2, NULL, 'CRITIQUE');

        -- -----------------------------------------------------
        p_test('EXT-02', 'La deduplication porte sur la cle de ligne, jamais sur la ligne entiere');
        p_obj('un SELECT DISTINCT sur la ligne entiere ecrase les lignes legitimement');
        po('             identiques : une extourne et son ecriture d''origine ne different que');
        po('             par leur cle technique. Le test mesure combien de lignes un DISTINCT');
        po('             ferait disparaitre. Toute difference non nulle prouve que la');
        po('             deduplication par DISTINCT detruit de l''information comptable.');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        SELECT COUNT(*) INTO v_cnt2
          FROM (SELECT DISTINCT h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                       h.lcy_amount, h.trn_dt
                  FROM actb_history h WHERE h.module = k_mod);
        v_cnt := v_tot - v_cnt2;
        print_kv('Lignes du module',                          fnum(v_tot));
        print_kv('Lignes restantes apres DISTINCT metier',    fnum(v_cnt2));
        print_kv('Lignes que le DISTINCT ferait disparaitre', fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        SELECT NVL(SUM(mt), 0) INTO v_mt
          FROM (SELECT h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                       h.trn_dt, (COUNT(*) - 1) * MAX(NVL(h.lcy_amount, 0)) mt
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.event, h.ac_no, h.drcr_ind, h.amount_tag,
                          h.trn_dt, h.lcy_amount
                HAVING COUNT(*) > 1);
        p_verdict('EXT-02', 'Lignes comptables qu''une deduplication par DISTINCT detruirait',
                  v_cnt, v_tot, ABS(v_mt), 'CRITIQUE');
        IF v_cnt > 0 THEN
            po('     Les groupes ci-dessous portent plusieurs lignes rigoureusement');
            po('     identiques sur les colonnes metier. Elles sont legitimes : seule la');
            po('     cle technique les separe. Le present script ne deduplique jamais.');
            tbl_line('4,22,12,12,10,18,6,20,12,10');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 22) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('EVENT', 10) || '|' || fpad('TAG DE MONTANT', 18) || '|'
                || fpad('D/C', 6) || '|' || fpadl('MONTANT LCY', 20) || '|' || fpad('DATE', 12) || '|'
                || fpadl('NB LIGNES', 10) || '|');
            tbl_line('4,22,12,12,10,18,6,20,12,10');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.event, h.amount_tag, h.drcr_ind,
                               h.lcy_amount mt, h.trn_dt dt, COUNT(*) nb
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no, h.event, h.amount_tag, h.drcr_ind,
                                  h.lcy_amount, h.trn_dt
                        HAVING COUNT(*) > 1
                         ORDER BY COUNT(*) DESC, ABS(h.lcy_amount) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 22) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(r.event, 10) || '|' || fpad(r.amount_tag, 18) || '|'
                    || fpad(r.drcr_ind, 6) || '|' || fpadl(famt(r.mt), 20) || '|'
                    || fpad(fdt(r.dt), 12) || '|' || fpadl(fnum(r.nb), 10) || '|');
            END LOOP;
            tbl_line('4,22,12,12,10,18,6,20,12,10');
        END IF;

        -- -----------------------------------------------------
        p_test('EXT-03', 'Tout contrat du referentiel porte des ecritures comptables');
        p_obj('sur les quatre produits de marche monetaire (' || k_prod_mm || '),');
        po('             tout contrat doit avoir au moins une ecriture dans ACTB_HISTORY.');
        po('             Recoupe MM-601, qui teste la meme chose sans filtre de produit.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND INSTR(',' || k_prod_mm || ',', ',' || TRIM(m.product) || ',') > 0
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no
                              AND h.module = k_mod);
        p_verdict('EXT-03', 'Contrat de marche monetaire sans aucune ecriture comptable',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('PRODUIT / STATUT');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date,
                               m.value_date, m.maturity_date, TRIM(m.contract_status) st
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND INSTR(',' || k_prod_mm || ',', ',' || TRIM(m.product) || ',') > 0
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = m.contract_ref_no
                                              AND h.module = k_mod)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date,
                      r.maturity_date, r.product || ' / statut ' || r.st);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('EXT-04', 'Aucune ecriture orpheline (ecriture sans contrat)');
        p_obj('tout TRN_REF_NO du module doit correspondre a un CONTRACT_REF_NO du');
        po('             referentiel des contrats. Une ecriture orpheline est soit un contrat');
        po('             purge alors que sa comptabilite subsiste, soit une ecriture passee');
        po('             sur une reference qui n''existe pas. Recoupe MM-602.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(NVL(h.lcy_amount, 0)), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m
                            WHERE m.contract_ref_no = h.trn_ref_no);
        print_kv('References orphelines distinctes', fnum(v_cnt2));
        p_verdict('EXT-04', 'Ecriture comptable sans contrat correspondant',
                  v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,10,18,6,22,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('REFERENCE ORPHELINE', 24) || '|'
                || fpad('DATE', 12) || '|' || fpad('EVENT', 10) || '|' || fpad('TAG DE MONTANT', 18) || '|'
                || fpad('D/C', 6) || '|' || fpad('COMPTE (AC_NO)', 22) || '|'
                || fpadl('MONTANT LCY', 20) || '|');
            tbl_line('4,24,12,10,18,6,22,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.trn_dt dt, h.event, h.amount_tag,
                               h.drcr_ind, h.ac_no, h.lcy_amount mt
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m
                                            WHERE m.contract_ref_no = h.trn_ref_no)
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.dt), 12) || '|' || fpad(r.event, 10) || '|'
                    || fpad(r.amount_tag, 18) || '|' || fpad(r.drcr_ind, 6) || '|'
                    || fpad(r.ac_no, 22) || '|' || fpadl(famt(r.mt), 20) || '|');
            END LOOP;
            tbl_line('4,24,12,10,18,6,22,20');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 18. DBL : RESPECT DE LA PARTIE DOUBLE
    -- =========================================================
    print_section('18. CONTROLES DBL : RESPECT DE LA PARTIE DOUBLE');
    BEGIN
        po('  L''equilibre est teste a trois mailles emboitees. Un desequilibre au');
        po('  niveau de l''evenement peut se compenser au niveau du contrat, et un');
        po('  desequilibre du contrat peut se compenser au niveau de la journee : la');
        po('  maille la plus fine est la seule qui ne cache rien.');
        po('');
        po('  Convention . la somme est SIGNEE (debit positif, credit negatif). Les');
        po('  extournes portent des montants negatifs : un cumul en debits bruts');
        po('  contre credits bruts les lirait a l''envers (voir REV-03).');

        -- -----------------------------------------------------
        p_test('DBL-01', 'Equilibre debit credit de chaque contrat');
        p_obj('sur la vie entiere d''un contrat, la somme signee des ecritures doit');
        po('             etre nulle. Recoupe MM-603.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) sld
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE ABS(sld) > k_tol_abs;
        p_verdict('DBL-01', 'Contrat dont la somme signee des ecritures n''est pas nulle',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,12,14,22,22,22');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpadl('NB ECRITURES', 14) || '|'
                || fpadl('TOTAL DEBIT', 22) || '|' || fpadl('TOTAL CREDIT', 22) || '|'
                || fpadl('SOLDE SIGNE', 22) || '|');
            tbl_line('4,24,12,12,14,22,22,22');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT h.trn_ref_no ref, COUNT(*) nb,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) sld
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(fmio(r.deb), 22) || '|'
                    || fpadl(fmio(r.cre), 22) || '|' || fpadl(famt(r.sld), 22) || '|');
            END LOOP;
            tbl_line('4,24,12,12,14,22,22,22');
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-02', 'Equilibre de chaque evenement (contrat, date, tag de montant)');
        p_obj('la maille fine. Une ecriture a moitie passee, dont la contrepartie a');
        po('             ete oubliee, se compense au niveau du contrat des lors qu''une autre');
        po('             ecriture est symetriquement fausse. Elle ne se compense jamais a la');
        po('             maille contrat + date + tag.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.trn_dt, h.amount_tag,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) sld
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.trn_dt, h.amount_tag)
         WHERE ABS(sld) > k_tol_abs;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('DBL-02', 'Evenement comptable desequilibre (contrat, date, tag)',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,12,12,18,22,22,22');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('DATE ECR.', 12) || '|'
                || fpad('TAG DE MONTANT', 18) || '|' || fpadl('TOTAL DEBIT', 22) || '|'
                || fpadl('TOTAL CREDIT', 22) || '|' || fpadl('SOLDE SIGNE', 22) || '|');
            tbl_line('4,24,12,12,12,18,22,22,22');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.trn_dt dt, h.amount_tag,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) sld
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no, h.trn_dt, h.amount_tag
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(fdt(r.dt), 12) || '|' || fpad(r.amount_tag, 18) || '|'
                    || fpadl(famt(r.deb), 22) || '|' || fpadl(famt(r.cre), 22) || '|'
                    || fpadl(famt(r.sld), 22) || '|');
            END LOOP;
            tbl_line('4,24,12,12,12,18,22,22,22');
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-03', 'Equilibre du portefeuille pour chaque date comptable');
        p_obj('la somme signee de toutes les ecritures du module doit etre nulle');
        po('             chaque jour. Un desequilibre journalier signale une ecriture passee');
        po('             sans sa contrepartie, ou une contrepartie datee d''un autre jour.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_dt,
                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                    ELSE -NVL(h.lcy_amount, 0) END) sld
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_dt)
         WHERE ABS(sld) > k_tol_abs;
        SELECT COUNT(DISTINCT h.trn_dt) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        print_kv('Dates comptables mouvementees', fnum(v_tot));
        p_verdict('DBL-03', 'Date comptable dont le module ne s''equilibre pas',
                  v_cnt, v_tot, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,14,16,24,24,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('DATE', 14) || '|' || fpadl('NB ECRITURES', 16) || '|'
                || fpadl('TOTAL DEBIT', 24) || '|' || fpadl('TOTAL CREDIT', 24) || '|'
                || fpadl('SOLDE SIGNE', 24) || '|');
            tbl_line('4,14,16,24,24,24');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_dt dt, COUNT(*) nb,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) sld
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_dt
                        HAVING ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                ELSE -NVL(h.lcy_amount, 0) END)) > k_tol_abs
                         ORDER BY ABS(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.dt), 14) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.deb), 24) || '|'
                    || fpadl(fmio(r.cre), 24) || '|' || fpadl(famt(r.sld), 24) || '|');
            END LOOP;
            tbl_line('4,14,16,24,24,24');
        END IF;

        -- -----------------------------------------------------
        p_test('DBL-04', 'Aucune ecriture a montant nul ou a qualifiant manquant');
        p_obj('une ecriture sans montant, sans sens ou sans tag de montant ne peut');
        po('             etre ni rapprochee ni interpretee. Elle fausse tous les controles qui');
        po('             s''appuient sur ces colonnes.');
        tbl_line('4,52,18,14,24');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEFAUT TESTE', 52) || '|' || fpadl('NB LIGNES', 18) || '|'
            || fpadl('% DU MODULE', 14) || '|' || fpadl('MONTANT CONCERNE', 24) || '|');
        tbl_line('4,52,18,14,24');
        SELECT COUNT(*) INTO v_tot FROM actb_history h WHERE h.module = k_mod;
        v_cnt := 0;
        v_mt  := 0;
        v_row := 0;
        FOR r IN (SELECT 'Montant LCY nul ou non renseigne' lib, 1 ord FROM DUAL UNION ALL
                  SELECT 'Sens debit credit non renseigne', 2 FROM DUAL UNION ALL
                  SELECT 'Tag de montant non renseigne',    3 FROM DUAL UNION ALL
                  SELECT 'Compte AC_NO non renseigne',      4 FROM DUAL UNION ALL
                  SELECT 'Date comptable non renseignee',   5 FROM DUAL
                  ORDER BY 2) LOOP
            SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt2, v_tot2
              FROM actb_history h
             WHERE h.module = k_mod
               AND ((r.ord = 1 AND NVL(h.lcy_amount, 0) = 0)
                 OR (r.ord = 2 AND TRIM(h.drcr_ind) IS NULL)
                 OR (r.ord = 3 AND TRIM(h.amount_tag) IS NULL)
                 OR (r.ord = 4 AND TRIM(h.ac_no) IS NULL)
                 OR (r.ord = 5 AND h.trn_dt IS NULL));
            v_cnt := v_cnt + v_cnt2;
            v_mt  := v_mt + v_tot2;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 52) || '|'
                || fpadl(fnum(v_cnt2), 18) || '|' || fpadl(fpct(v_cnt2, v_tot), 14) || '|'
                || fpadl(fmio(v_tot2), 24) || '|');
        END LOOP;
        tbl_line('4,52,18,14,24');
        p_verdict('DBL-04', 'Ecriture a montant nul ou a qualifiant manquant',
                  v_cnt, v_tot, v_mt, 'MOYEN');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 19. MAP : MAPPING DES COMPTES
    -- =========================================================
    print_section('19. CONTROLES MAP : MAPPING DES COMPTES');
    BEGIN
        po('  Le schema comptable attendu associe a chaque produit un compte de titres,');
        po('  un mecanisme d''interets et un compte de produits. Un mapping errone ne');
        po('  desequilibre rien : la partie double reste satisfaite. Il fausse en');
        po('  revanche la lecture du bilan et du compte de resultat, et il echappe donc');
        po('  a tous les controles d''equilibre de la section 18.');
        po('');
        print_sub('19.0 Schema de mapping attendu');
        tbl_line('4,10,20,22,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('MECANISME', 20) || '|'
            || fpad('COMPTE DE TITRES', 22) || '|' || fpad('COMPTE D''INTERETS', 22) || '|'
            || fpad('COMPTE DE PRODUITS', 22) || '|');
        tbl_line('4,10,20,22,22,22');
        po('  |' || fpadl('1', 4) || '|' || fpad('OTAP', 10) || '|' || fpad('post-compte', 20) || '|'
            || fpad(k_ac_tit_otap, 22) || '|' || fpad(k_ac_crat_pl, 22) || '|'
            || fpad(k_ac_prod_ob, 22) || '|');
        po('  |' || fpadl('2', 4) || '|' || fpad('MTPD', 10) || '|' || fpad('pre-compte', 20) || '|'
            || fpad(k_ac_tit_mtpd, 22) || '|' || fpad(k_ac_pca, 22) || '|'
            || fpad(k_ac_prod_bt, 22) || '|');
        po('  |' || fpadl('3', 4) || '|' || fpad('TBTR', 10) || '|' || fpad('pre-compte', 20) || '|'
            || fpad(k_ac_tit_tr, 22) || '|' || fpad(k_ac_pca, 22) || '|'
            || fpad(k_ac_prod_bt, 22) || '|');
        po('  |' || fpadl('4', 4) || '|' || fpad('BTTR', 10) || '|' || fpad('post-compte', 20) || '|'
            || fpad(k_ac_tit_tr, 22) || '|' || fpad(k_ac_crat_tr, 22) || '|'
            || fpad(k_ac_prod_bt, 22) || '|');
        tbl_line('4,10,20,22,22,22');
        po('  Jambe de reglement de tous les produits . ' || k_ac_nostro
            || ' ou tout compte de general naturel ' || k_gl_treso || 'xxx');

        -- -----------------------------------------------------
        p_test('MAP-01', 'Chaque produit n''utilise que son compte de titres autorise');
        p_obj('sur les tags PRINCIPAL et PRINCIPAL_LIQD, la jambe titres doit toucher');
        po('             le compte du produit et lui seul. Le tableau croise produit x compte');
        po('             donne la cartographie reelle ; le verdict compte les ecritures dont');
        po('             le couple n''est pas dans la liste autorisee.');
        print_sub('MAP-01 a. Croisement produit x compte sur la jambe titres');
        tbl_line('4,10,22,44,16,24,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('COMPTE (AC_NO)', 22) || '|'
            || fpad('LIBELLE', 44) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('MONTANT LCY', 24) || '|' || fpadl('VERDICT', 16) || '|');
        tbl_line('4,10,22,44,16,24,16');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                         SUM(NVL(h.lcy_amount, 0)) mt
                    FROM actb_history h
                    JOIN (SELECT contract_ref_no, MAX(product) prod
                            FROM ldtb_contract_master
                           WHERE module = k_mod
                           GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                     AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                     AND h.drcr_ind = 'D'
                     AND (h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                          OR EXISTS (SELECT 1 FROM sttb_account a
                                      WHERE a.ac_gl_no = h.ac_no
                                        AND (NVL(a.ac_natural_gl, ' ') LIKE k_gl_tit_pl || '%'
                                          OR NVL(a.ac_natural_gl, ' ') LIKE k_gl_tit_tr || '%')))
                   GROUP BY p.prod, h.ac_no
                   ORDER BY p.prod, COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF (r.prod = 'OTAP' AND r.ac_no = k_ac_tit_otap)
            OR (r.prod = 'MTPD' AND r.ac_no = k_ac_tit_mtpd)
            OR (r.prod IN ('TBTR', 'BTTR') AND r.ac_no = k_ac_tit_tr) THEN
                v_cnt2 := 0;
            ELSE
                v_cnt2 := 1;
                v_cnt := v_cnt + r.nb;
                v_mt  := v_mt + ABS(r.mt);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 16) || '|'
                || fpadl(fmio(r.mt), 24) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'AUTORISE' ELSE 'HORS LISTE' END, 16) || '|');
        END LOOP;
        tbl_line('4,10,22,44,16,24,16');
        p_verdict('MAP-01', 'Jambe titres portee par un compte non autorise pour le produit',
                  v_cnt, NULL, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('MAP-02', 'Le mecanisme d''interets correspond au produit');
        p_obj('les produits a interets PRE-comptes (' || k_prod_pre || ') passent par le');
        po('             compte de produits percus d''avance ; les produits a interets');
        po('             POST-comptes (' || k_prod_post || ') passent par les creances rattachees.');
        po('             Melanger les deux mecanismes sur un meme produit fausse le rythme de');
        po('             prise en resultat, sans jamais desequilibrer la balance.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          JOIN (SELECT contract_ref_no, MAX(product) prod
                  FROM ldtb_contract_master WHERE module = k_mod
                 GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
         WHERE h.module = k_mod
           AND h.amount_tag LIKE 'INT%'
           AND ((INSTR(',' || k_prod_post || ',', ',' || p.prod || ',') > 0
                 AND h.ac_no LIKE SUBSTR(k_ac_pca, 1, 3) || '%')
             OR (INSTR(',' || k_prod_pre || ',', ',' || p.prod || ',') > 0
                 AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)));
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MAP-02', 'Melange des mecanismes pre-compte et post-compte sur un produit',
                  v_cnt, NULL, v_mt, 'ELEVE');
        print_sub('MAP-02 a. Croisement produit x compte sur les tags d''interets');
        tbl_line('4,10,22,44,20,16,24');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('COMPTE (AC_NO)', 22) || '|'
            || fpad('LIBELLE', 44) || '|' || fpad('MECANISME LU', 20) || '|'
            || fpadl('NB ECRITURES', 16) || '|' || fpadl('MONTANT LCY', 24) || '|');
        tbl_line('4,10,22,44,20,16,24');
        v_row := 0;
        FOR r IN (SELECT * FROM (
                    SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                           SUM(NVL(h.lcy_amount, 0)) mt
                      FROM actb_history h
                      JOIN (SELECT contract_ref_no, MAX(product) prod
                              FROM ldtb_contract_master WHERE module = k_mod
                             GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                      LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                   FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                     WHERE h.module = k_mod
                       AND h.amount_tag LIKE 'INT%'
                     GROUP BY p.prod, h.ac_no
                     ORDER BY p.prod, COUNT(*) DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 44) || '|'
                || fpad(CASE WHEN r.ac_no LIKE SUBSTR(k_ac_pca, 1, 3) || '%' THEN 'pre-compte'
                             WHEN r.ac_no IN (k_ac_crat_pl, k_ac_crat_tr) THEN 'post-compte'
                             WHEN r.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%' THEN 'resultat'
                             ELSE 'autre' END, 20) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 24) || '|');
        END LOOP;
        tbl_line('4,10,22,44,20,16,24');

        -- -----------------------------------------------------
        p_test('MAP-03', 'Le compte de produits correspond a l''instrument');
        p_obj('les obligations (' || k_prod_oblig || ') alimentent ' || k_ac_prod_ob || ', les bons du');
        po('             tresor alimentent ' || k_ac_prod_bt || '. Une inversion deplace le revenu');
        po('             d''une ligne de compte de resultat a l''autre.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          JOIN (SELECT contract_ref_no, MAX(product) prod
                  FROM ldtb_contract_master WHERE module = k_mod
                 GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
         WHERE h.module = k_mod
           AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'
           AND ((INSTR(',' || k_prod_oblig || ',', ',' || p.prod || ',') > 0
                 AND h.ac_no <> k_ac_prod_ob)
             OR (INSTR(',' || k_prod_oblig || ',', ',' || p.prod || ',') = 0
                 AND h.ac_no <> k_ac_prod_bt));
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MAP-03', 'Compte de produits ne correspondant pas a l''instrument',
                  v_cnt, NULL, v_mt, 'ELEVE');
        print_sub('MAP-03 a. Croisement produit x compte de produits');
        tbl_line('4,10,22,44,16,24,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('COMPTE (AC_NO)', 22) || '|'
            || fpad('LIBELLE', 44) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('MONTANT LCY', 24) || '|' || fpadl('VERDICT', 16) || '|');
        tbl_line('4,10,22,44,16,24,16');
        v_row := 0;
        FOR r IN (SELECT p.prod, h.ac_no, MAX(s.lib) lib, COUNT(*) nb,
                         SUM(NVL(h.lcy_amount, 0)) mt
                    FROM actb_history h
                    JOIN (SELECT contract_ref_no, MAX(product) prod
                            FROM ldtb_contract_master WHERE module = k_mod
                           GROUP BY contract_ref_no) p ON p.contract_ref_no = h.trn_ref_no
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                     AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'
                   GROUP BY p.prod, h.ac_no
                   ORDER BY p.prod, COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 16) || '|'
                || fpadl(fmio(r.mt), 24) || '|'
                || fpadl(CASE WHEN INSTR(',' || k_prod_oblig || ',', ',' || r.prod || ',') > 0
                                   AND r.ac_no = k_ac_prod_ob THEN 'AUTORISE'
                              WHEN INSTR(',' || k_prod_oblig || ',', ',' || r.prod || ',') = 0
                                   AND r.ac_no = k_ac_prod_bt THEN 'AUTORISE'
                              ELSE 'HORS LISTE' END, 16) || '|');
        END LOOP;
        tbl_line('4,10,22,44,16,24,16');

        -- -----------------------------------------------------
        p_test('MAP-04', 'La jambe de reglement touche toujours un compte de tresorerie');
        p_obj('sur les tags PRINCIPAL et PRINCIPAL_LIQD, la contrepartie de la jambe');
        po('             titres est un decaissement ou un encaissement : elle doit toucher le');
        po('             nostro ' || k_ac_nostro || ' ou un compte de general naturel ' || k_gl_treso || 'xxx.');
        po('             Une jambe de reglement logee sur un compte de titres, de creances');
        po('             rattachees ou d''attente signifie que la tresorerie n''a pas bouge.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
          LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat
                       FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
         WHERE h.module = k_mod
           AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
           AND h.ac_no NOT IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
           AND h.ac_no <> k_ac_nostro
           AND NVL(s.nat, ' ') NOT LIKE k_gl_treso || '%';
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('MAP-04', 'Jambe de reglement hors compte de tresorerie',
                  v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,12,18,6,22,14,40,22');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('TAG DE MONTANT', 18) || '|' || fpad('D/C', 6) || '|'
                || fpad('COMPTE (AC_NO)', 22) || '|' || fpad('GL NATUREL', 14) || '|'
                || fpad('LIBELLE', 40) || '|' || fpadl('MONTANT LCY', 22) || '|');
            tbl_line('4,24,12,12,18,6,22,14,40,22');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.amount_tag, h.drcr_ind, h.ac_no,
                               s.nat, s.lib, h.lcy_amount mt
                          FROM actb_history h
                          LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                       FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                         WHERE h.module = k_mod
                           AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                           AND h.ac_no NOT IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                           AND h.ac_no <> k_ac_nostro
                           AND NVL(s.nat, ' ') NOT LIKE k_gl_treso || '%'
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(r.amount_tag, 18) || '|' || fpad(r.drcr_ind, 6) || '|'
                    || fpad(r.ac_no, 22) || '|' || fpad(r.nat, 14) || '|' || fpad(r.lib, 40) || '|'
                    || fpadl(famt(r.mt), 22) || '|');
            END LOOP;
            tbl_line('4,24,12,12,18,6,22,14,40,22');
        END IF;

        -- -----------------------------------------------------
        p_test('MAP-05', 'Tout compte mouvemente existe et n''est ni ferme ni bloque');
        p_obj('un compte inconnu du plan comptable, non autorise, ferme, bloque ou');
        po('             gele ne devrait recevoir aucune ecriture. Recoupe MM-628 pour la');
        po('             seule existence ; ce test y ajoute les statuts.');
        tbl_line('4,22,40,10,10,10,10,10,14,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_NO)', 22) || '|' || fpad('LIBELLE', 40) || '|'
            || fpad('EXISTE', 10) || '|' || fpad('AUTH', 10) || '|' || fpad('BLOQUE', 10) || '|'
            || fpad('GELE', 10) || '|' || fpad('NO POST', 10) || '|' || fpadl('NB ECRITURES', 14) || '|'
            || fpadl('VERDICT', 16) || '|');
        tbl_line('4,22,40,10,10,10,10,10,14,16');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT h.ac_no, COUNT(*) nb,
                         MAX(s.lib) lib, MAX(s.au) au, MAX(s.bl) bl, MAX(s.fr) fr,
                         MAX(s.dp) dp, MAX(s.ex) ex
                    FROM actb_history h
                    LEFT JOIN (SELECT ac_gl_no, MAX(ac_gl_desc) lib, MAX(auth_stat) au,
                                      MAX(NVL(gl_stat_blocked, 'N')) bl,
                                      MAX(NVL(ac_stat_frozen, 'N')) fr,
                                      MAX(NVL(gl_stat_de_post, 'N')) dp, 'O' ex
                                 FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                   WHERE h.module = k_mod
                   GROUP BY h.ac_no
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF r.ex IS NULL OR NVL(r.au, 'X') <> 'A' OR NVL(r.bl, 'N') = 'Y'
               OR NVL(r.fr, 'N') = 'Y' OR NVL(r.dp, 'N') = 'Y' THEN
                v_cnt := v_cnt + 1;
                v_cnt2 := 1;
            ELSE
                v_cnt2 := 0;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 40) || '|'
                || fpad(NVL(r.ex, 'NON'), 10) || '|' || fpad(NVL(r.au, '-'), 10) || '|'
                || fpad(NVL(r.bl, '-'), 10) || '|' || fpad(NVL(r.fr, '-'), 10) || '|'
                || fpad(NVL(r.dp, '-'), 10) || '|' || fpadl(fnum(r.nb), 14) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'OK' ELSE 'A EXPLIQUER' END, 16) || '|');
        END LOOP;
        tbl_line('4,22,40,10,10,10,10,10,14,16');
        p_verdict('MAP-05', 'Compte mouvemente inconnu, non autorise, bloque, gele ou interdit de saisie',
                  v_cnt, v_row, NULL, 'MOYEN');

        -- -----------------------------------------------------
        p_test('MAP-06', 'Aucune ecriture de marche monetaire en compte d''attente');
        p_obj('la liste des comptes autorises compte neuf numeros. Tout compte utilise');
        po('             hors de cette liste doit etre challenge : compte d''attente, compte de');
        po('             liaison, sous-compte cree hors procedure, ou nostro d''une autre');
        po('             contrepartie que la BEAC.');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no NOT IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr,
                               k_ac_crat_pl, k_ac_crat_tr, k_ac_pca,
                               k_ac_prod_ob, k_ac_prod_bt, k_ac_nostro);
        SELECT COUNT(*) INTO v_cnt2
          FROM (SELECT DISTINCT h.ac_no FROM actb_history h
                 WHERE h.module = k_mod
                   AND h.ac_no NOT IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr,
                                       k_ac_crat_pl, k_ac_crat_tr, k_ac_pca,
                                       k_ac_prod_ob, k_ac_prod_bt, k_ac_nostro));
        print_kv('Comptes distincts hors liste autorisee', fnum(v_cnt2));
        p_verdict('MAP-06', 'Ecriture logee sur un compte hors des neuf comptes autorises',
                  v_cnt, NULL, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,22,14,44,16,24,24,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_NO)', 22) || '|'
                || fpad('GL NATUREL', 14) || '|' || fpad('LIBELLE', 44) || '|'
                || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL DEBIT', 24) || '|'
                || fpadl('TOTAL CREDIT', 24) || '|' || fpadl('NB CONTRATS', 14) || '|');
            tbl_line('4,22,14,44,16,24,24,14');
            v_row := 0;
            FOR r IN (SELECT h.ac_no, MAX(s.nat) nat, MAX(s.lib) lib, COUNT(*) nb,
                             SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                             SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                             COUNT(DISTINCT h.trn_ref_no) nbc
                        FROM actb_history h
                        LEFT JOIN (SELECT ac_gl_no, MAX(ac_natural_gl) nat, MAX(ac_gl_desc) lib
                                     FROM sttb_account GROUP BY ac_gl_no) s ON s.ac_gl_no = h.ac_no
                       WHERE h.module = k_mod
                         AND h.ac_no NOT IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr,
                                             k_ac_crat_pl, k_ac_crat_tr, k_ac_pca,
                                             k_ac_prod_ob, k_ac_prod_bt, k_ac_nostro)
                       GROUP BY h.ac_no
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > k_top;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(r.nat, 14) || '|' || fpad(r.lib, 44) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fmio(r.deb), 24) || '|' || fpadl(fmio(r.cre), 24) || '|'
                    || fpadl(fnum(r.nbc), 14) || '|');
            END LOOP;
            tbl_line('4,22,14,44,16,24,24,14');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 20. INT : EXACTITUDE DES INTERETS
    -- =========================================================
    print_section('20. CONTROLES INT : EXACTITUDE DES INTERETS');
    BEGIN
        SELECT MAX(accrual_to_date) INTO v_d_accr
          FROM ldtb_contract_accrual_history WHERE module = k_mod;
        po('  Trois questions distinctes. Le montant d''interets porte par le contrat');
        po('  est-il arithmetiquement juste (INT-02) ? La comptabilite a-t-elle');
        po('  enregistre ce montant et lui seul (INT-01) ? L''a-t-elle enregistre au bon');
        po('  rythme, jour par jour, sans trou ni depassement (INT-03 a INT-05) ?');
        po('');
        print_kv('Derniere provision enregistree par le module', fdt(v_d_accr));
        po('  Les tests de rythme sont bornes a cette date : au dela, l''absence de');
        po('  provision ne traduit pas un trou dans la serie mais l''arret du module,');
        po('  deja chiffre par MM-315 et MM-316.');

        -- -----------------------------------------------------
        p_test('INT-01', 'Interets comptabilises sur la vie du contrat egaux aux interets du deal');
        p_obj('sur un contrat echu, le produit net reconnu au compte de resultat');
        po('             (credits moins debits des comptes ' || k_ac_prod_ob || ' et ' || k_ac_prod_bt || ')');
        po('             doit egaler MAIN_COMP_AMOUNT. Le test est indifferent au mecanisme :');
        po('             pre-compte ou post-compte, le resultat final doit etre le meme.');
        SELECT COUNT(*), NVL(SUM(ABS(ecart)), 0) INTO v_cnt, v_mt
          FROM (SELECT m.contract_ref_no, NVL(m.main_comp_amount, 0)
                       - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END)
                                FROM actb_history h
                               WHERE h.trn_ref_no = m.contract_ref_no
                                 AND h.module = k_mod
                                 AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'), 0) ecart
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.maturity_date <= k_arrete
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NVL(m.main_comp_amount, 0) > 0
                   AND EXISTS (SELECT 1 FROM actb_history h
                                WHERE h.trn_ref_no = m.contract_ref_no AND h.module = k_mod))
         WHERE ABS(ecart) > k_tol_abs;
        p_verdict('INT-01', 'Produit comptabilise different des interets du contrat (contrats echus)',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,22,22,22');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('INT. DU CONTRAT', 22) || '|' || fpadl('PRODUIT COMPTABILISE', 22) || '|'
                || fpadl('ECART', 22) || '|');
            tbl_line('4,24,8,12,12,22,22,22');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no ref, m.product, m.booking_date bd,
                               m.maturity_date md, NVL(m.main_comp_amount, 0) it,
                               NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                               ELSE -NVL(h.lcy_amount, 0) END)
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = m.contract_ref_no
                                       AND h.module = k_mod
                                       AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'), 0) pr
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.maturity_date <= k_arrete
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.main_comp_amount, 0) > 0
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = m.contract_ref_no AND h.module = k_mod)
                           AND ABS(NVL(m.main_comp_amount, 0)
                                   - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                            FROM actb_history h
                                           WHERE h.trn_ref_no = m.contract_ref_no
                                             AND h.module = k_mod
                                             AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'), 0))
                               > k_tol_abs
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.it), 22) || '|' || fpadl(famt(r.pr), 22) || '|'
                    || fpadl(famt(r.it - r.pr), 22) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,22,22,22');
        END IF;

        -- -----------------------------------------------------
        p_test('INT-02', 'Le montant d''interets du contrat est arithmetiquement exact');
        p_obj('recalcul independant : nominal x taux x duree / ' || TO_CHAR(k_base_jours) || '.');
        po('             Un ecart revele un taux, une base ou une duree faux dans le contrat');
        po('             lui-meme, avant toute comptabilisation. Ce test porte sur le deal ;');
        po('             MM-301 porte sur les lignes de calcul de FLEXCUBE.');
        SELECT COUNT(*), NVL(SUM(ABS(ecart)), 0) INTO v_cnt, v_mt
          FROM (SELECT m.contract_ref_no,
                       NVL(m.main_comp_amount, 0)
                       - ROUND(NVL(m.lcy_amount, 0) * NVL(m.main_comp_rate, 0) / 100
                               * (m.maturity_date - m.value_date) / k_base_jours, 2) ecart
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND NVL(m.main_comp_amount, 0) > 0
                   AND m.maturity_date > m.value_date)
         WHERE ABS(ecart) > k_tol_abs;
        p_verdict('INT-02', 'Interets du contrat differents du recalcul nominal x taux x duree',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,10,10,22,22,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('TAUX', 10) || '|'
                || fpadl('DUREE', 10) || '|' || fpadl('INT. DU CONTRAT', 22) || '|'
                || fpadl('RECALCUL', 22) || '|' || fpadl('ECART', 20) || '|');
            tbl_line('4,24,8,12,12,10,10,22,22,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no ref, m.product, m.booking_date bd,
                               m.maturity_date md, m.main_comp_rate tx,
                               m.maturity_date - m.value_date duree,
                               NVL(m.main_comp_amount, 0) it,
                               ROUND(NVL(m.lcy_amount, 0) * NVL(m.main_comp_rate, 0) / 100
                                     * (m.maturity_date - m.value_date) / k_base_jours, 2) th
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND NVL(m.main_comp_amount, 0) > 0
                           AND m.maturity_date > m.value_date
                           AND ABS(NVL(m.main_comp_amount, 0)
                                   - ROUND(NVL(m.lcy_amount, 0) * NVL(m.main_comp_rate, 0) / 100
                                           * (m.maturity_date - m.value_date) / k_base_jours, 2))
                               > k_tol_abs
                         ORDER BY ABS(NVL(m.main_comp_amount, 0)
                                   - ROUND(NVL(m.lcy_amount, 0) * NVL(m.main_comp_rate, 0) / 100
                                           * (m.maturity_date - m.value_date) / k_base_jours, 2)) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(ftx(r.tx), 10) || '|' || fpadl(fnum(r.duree) || ' j', 10) || '|'
                    || fpadl(famt(r.it), 22) || '|' || fpadl(famt(r.th), 22) || '|'
                    || fpadl(famt(r.it - r.th), 20) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,10,10,22,22,20');
        END IF;

        -- -----------------------------------------------------
        p_test('INT-03', 'La provision quotidienne est constante et egale a un multiple entier');
        p_obj('la provision d''un jour vaut MAIN_COMP_AMOUNT / duree. Une provision de');
        po('             rattrapage apres un week-end ou un jour ferie vaut deux ou trois fois');
        po('             ce montant : elle reste un multiple entier. Une provision qui n''est');
        po('             pas un multiple entier signale un taux applique different ou une');
        po('             regularisation manuelle.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT q.ref, q.dt, q.mt, q.jour,
                       ABS(q.mt / q.jour - ROUND(q.mt / q.jour)) ecart
                  FROM (SELECT h.trn_ref_no ref, h.trn_dt dt,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) mt,
                               MAX((SELECT NVL(m.main_comp_amount, 0)
                                           / NULLIF(m.maturity_date - m.value_date, 0)
                                      FROM ldtb_contract_master m
                                     WHERE m.contract_ref_no = h.trn_ref_no
                                       AND m.version_no = 1)) jour
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND h.event = 'ACCR'
                           AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                         GROUP BY h.trn_ref_no, h.trn_dt) q
                 WHERE NVL(q.jour, 0) > 0 AND ABS(q.mt) > 0)
         WHERE ecart > 0.02;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('INT-03', 'Provision quotidienne qui n''est pas un multiple entier du jour theorique',
                  v_cnt, NULL, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,12,12,22,22,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('DATE PROV.', 12) || '|'
                || fpadl('PROVISION DU JOUR', 22) || '|' || fpadl('JOUR THEORIQUE', 22) || '|'
                || fpadl('NB JOURS', 16) || '|');
            tbl_line('4,24,12,12,12,22,22,16');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT q.ref, q.dt, q.mt, q.jour
                          FROM (SELECT h.trn_ref_no ref, h.trn_dt dt,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) mt,
                                       MAX((SELECT NVL(m.main_comp_amount, 0)
                                                   / NULLIF(m.maturity_date - m.value_date, 0)
                                              FROM ldtb_contract_master m
                                             WHERE m.contract_ref_no = h.trn_ref_no
                                               AND m.version_no = 1)) jour
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                   AND h.event = 'ACCR'
                                   AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                 GROUP BY h.trn_ref_no, h.trn_dt) q
                         WHERE NVL(q.jour, 0) > 0 AND ABS(q.mt) > 0
                           AND ABS(q.mt / q.jour - ROUND(q.mt / q.jour)) > 0.02
                         ORDER BY ABS(q.mt) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(fdt(r.dt), 12) || '|' || fpadl(famt(r.mt), 22) || '|'
                    || fpadl(famt(r.jour), 22) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mt / r.jour, 2)), 16) || '|');
            END LOOP;
            tbl_line('4,24,12,12,12,22,22,16');
        END IF;

        -- -----------------------------------------------------
        p_test('INT-04', 'Aucune provision hors de la vie du contrat');
        p_obj('une provision datee avant la date de valeur ou apres l''echeance (ou');
        po('             apres la liquidation si elle est anterieure) est un interet reconnu');
        po('             sur une periode ou le titre n''etait pas detenu. Recoupe MM-313 et');
        po('             MM-626, sur la maille comptable cette fois.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.trn_dt dt, NVL(h.lcy_amount, 0) mt,
                       (SELECT MAX(m.value_date) FROM ldtb_contract_master m
                         WHERE m.contract_ref_no = h.trn_ref_no AND m.version_no = 1) vd,
                       (SELECT MAX(m.maturity_date) FROM ldtb_contract_master m
                         WHERE m.contract_ref_no = h.trn_ref_no
                           AND m.version_no = (SELECT MAX(v.version_no)
                                                 FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)) md,
                       (SELECT MIN(x.trn_dt) FROM actb_history x
                         WHERE x.trn_ref_no = h.trn_ref_no
                           AND x.module = k_mod
                           AND x.amount_tag = 'PRINCIPAL_LIQD') dliq
                  FROM actb_history h
                 WHERE h.module = k_mod
                   AND h.event = 'ACCR'
                   AND h.drcr_ind = 'D')
         WHERE vd IS NOT NULL
           AND (TRUNC(dt) < TRUNC(vd)
             OR TRUNC(dt) > TRUNC(NVL(LEAST(NVL(dliq, md), NVL(md, dliq)), md)) + 1);
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('INT-04', 'Provision comptabilisee hors de la vie du contrat',
                  v_cnt, NULL, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('INT-05', 'Aucun trou dans la serie des provisions');
        p_obj('le nombre de jours effectivement provisionnes, rattrapages compris, doit');
        po('             egaler le nombre de jours ecoules. Le test est borne au ' || fdt(v_d_accr) || ',');
        po('             derniere date de provision du module : au dela, l''absence de');
        po('             provision est l''arret du module, deja constate en MM-315.');
        po('             Tolerance de ' || TO_CHAR(k_tol_jour) || ' jours pour les jours feries.');
        SELECT COUNT(*), NVL(SUM(ABS(manque * jour)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.jour, q.jours_provisionnes,
                       q.jours_ecoules - q.jours_provisionnes manque
                  FROM (SELECT m.contract_ref_no ref,
                               NVL(m.main_comp_amount, 0)
                                 / NULLIF(m.maturity_date - m.value_date, 0) jour,
                               TRUNC(LEAST(v_d_accr, m.maturity_date)) - TRUNC(m.value_date) jours_ecoules,
                               NVL((SELECT ROUND(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END)
                                          / NULLIF(NVL(m.main_comp_amount, 0)
                                                   / NULLIF(m.maturity_date - m.value_date, 0), 0))
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = m.contract_ref_no
                                       AND h.module = k_mod
                                       AND h.event = 'ACCR'
                                       AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                       AND h.trn_dt <= v_d_accr), 0) jours_provisionnes
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND INSTR(',' || k_prod_post || ',', ',' || TRIM(m.product) || ',') > 0
                           AND NVL(m.main_comp_amount, 0) > 0
                           AND m.value_date < v_d_accr) q
                 WHERE q.jours_ecoules > 0)
         WHERE manque > k_tol_jour;
        p_verdict('INT-05', 'Trou dans la serie des provisions, avant l''arret du module',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('INT-06', 'La base de calcul des jours est homogene par produit');
        p_obj('base implicite = nominal x taux x duree / interets du contrat. Elle doit');
        po('             valoir ' || TO_CHAR(k_base_jours) || ' pour tout le portefeuille. Une base 365 isolee sur');
        po('             quelques contrats d''un meme produit est une exception a justifier.');
        tbl_line('4,10,20,16,16,16,16,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('BASE IMPLICITE', 20) || '|'
            || fpadl('NB CONTRATS', 16) || '|' || fpadl('BASE MIN', 16) || '|'
            || fpadl('BASE MAX', 16) || '|' || fpadl('BASE MEDIANE', 16) || '|'
            || fpadl('VERDICT', 14) || '|');
        tbl_line('4,10,20,16,16,16,16,14');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT q.product, ROUND(MEDIAN(q.base)) bmed, COUNT(*) nb,
                         ROUND(MIN(q.base)) bmin, ROUND(MAX(q.base)) bmax
                    FROM (SELECT m.product,
                                 NVL(m.lcy_amount, 0) * NVL(m.main_comp_rate, 0) / 100
                                   * (m.maturity_date - m.value_date)
                                   / NULLIF(NVL(m.main_comp_amount, 0), 0) base
                            FROM ldtb_contract_master m
                           WHERE m.module = k_mod
                             AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                             AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                  WHERE v.contract_ref_no = m.contract_ref_no)
                             AND NVL(m.main_comp_amount, 0) > 0
                             AND NVL(m.main_comp_rate, 0) > 0
                             AND m.maturity_date > m.value_date) q
                   WHERE q.base BETWEEN 300 AND 400
                   GROUP BY q.product
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            IF ABS(r.bmax - r.bmin) > 2 THEN
                v_cnt := v_cnt + 1;
                v_cnt2 := 1;
            ELSE
                v_cnt2 := 0;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 10) || '|'
                || fpad(TO_CHAR(r.bmed) || ' jours', 20) || '|' || fpadl(fnum(r.nb), 16) || '|'
                || fpadl(TO_CHAR(r.bmin), 16) || '|' || fpadl(TO_CHAR(r.bmax), 16) || '|'
                || fpadl(TO_CHAR(r.bmed), 16) || '|'
                || fpadl(CASE WHEN v_cnt2 = 0 THEN 'HOMOGENE' ELSE 'DISPERSE' END, 14) || '|');
        END LOOP;
        tbl_line('4,10,20,16,16,16,16,14');
        p_verdict('INT-06', 'Produit dont la base de calcul des jours n''est pas homogene',
                  v_cnt, v_row, NULL, 'MOYEN');

        -- -----------------------------------------------------
        p_test('INT-07', 'Le taux est renseigne et plausible');
        p_obj('taux nul, non renseigne ou hors de la fourchette convenue avec la');
        po('             tresorerie (' || ftx(k_taux_min) || ' a ' || ftx(k_taux_max) || '). Recoupe MM-308.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (m.main_comp_rate IS NULL
                OR m.main_comp_rate < k_taux_min
                OR m.main_comp_rate > k_taux_max);
        p_verdict('INT-07', 'Taux non renseigne, nul ou hors de la fourchette convenue',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            d_head('TAUX CONSTATE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date,
                               m.value_date, m.maturity_date
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (m.main_comp_rate IS NULL
                                OR m.main_comp_rate < k_taux_min
                                OR m.main_comp_rate > k_taux_max)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date,
                      r.maturity_date, ftx(r.main_comp_rate));
            END LOOP;
            d_foot;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 21. LIF : CYCLE DE VIE DES POSITIONS
    -- =========================================================
    print_section('21. CONTROLES LIF : CYCLE DE VIE DES POSITIONS');
    BEGIN
        po('  Un contrat denoue ne doit plus rien laisser au bilan : ni titre, ni');
        po('  creance rattachee, ni produit percu d''avance. Un contrat vivant doit au');
        po('  contraire porter exactement son nominal et ses interets courus. Ces sept');
        po('  tests lisent le bilan contrat par contrat et le confrontent a l''etat');
        po('  attendu au ' || fdt(k_arrete) || '.');
        po('');
        po('  Convention . solde signe = somme des debits moins somme des credits sur');
        po('  les comptes de la famille consideree. Un solde nul signifie que la');
        po('  position est sortie du bilan.');

        -- -----------------------------------------------------
        p_test('LIF-01', 'Tout contrat echu a ete liquide');
        p_obj('un contrat dont l''echeance est passee doit porter une ecriture');
        po('             PRINCIPAL_LIQD. Son absence signifie que le remboursement n''a pas ete');
        po('             comptabilise. Recoupe MM-401, sur la maille comptable.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.maturity_date <= k_arrete
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND EXISTS (SELECT 1 FROM actb_history h
                        WHERE h.trn_ref_no = m.contract_ref_no AND h.module = k_mod)
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no
                              AND h.module = k_mod
                              AND h.amount_tag = 'PRINCIPAL_LIQD');
        p_verdict('LIF-01', 'Contrat echu sans ecriture de liquidation du principal',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            d_head('JOURS DEPUIS ECHEANCE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date,
                               m.value_date, m.maturity_date,
                               TRUNC(k_arrete) - TRUNC(m.maturity_date) anc
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.maturity_date <= k_arrete
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = m.contract_ref_no AND h.module = k_mod)
                           AND NOT EXISTS (SELECT 1 FROM actb_history h
                                            WHERE h.trn_ref_no = m.contract_ref_no
                                              AND h.module = k_mod
                                              AND h.amount_tag = 'PRINCIPAL_LIQD')
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date,
                      r.maturity_date, fnum(r.anc) || ' j');
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-02', 'Le compte de titres est solde apres liquidation');
        p_obj('apres PRINCIPAL_LIQD, le solde signe des comptes de titres du contrat');
        po('             doit etre nul : le titre est sorti du bilan. Un residu est une');
        po('             liquidation incomplete. Recoupe MM-621, ici sur les comptes exacts.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT h.trn_ref_no,
                       SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                     ELSE -NVL(h.lcy_amount, 0) END
                                ELSE 0 END) sld,
                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no)
         WHERE n_liq > 0 AND ABS(sld) > k_tol_abs;
        p_verdict('LIF-02', 'Compte de titres non solde apres liquidation',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,24,16');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('NOMINAL', 24) || '|' || fpadl('SOLDE TITRES RESIDUEL', 24) || '|'
                || fpadl('NB LIQUIDATIONS', 16) || '|');
            tbl_line('4,24,8,12,12,24,24,16');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x,
                         (SELECT MAX(mm.product) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) prod_x,
                         (SELECT MAX(mm.lcy_amount) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) nom_x
                     FROM (SELECT * FROM (
                        SELECT q.ref, q.sld, q.n_liq
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                         WHERE q.n_liq > 0 AND ABS(q.sld) > k_tol_abs
                         ORDER BY ABS(q.sld) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.prod_x, 8) || '|' || fpad(fdt(r.bkg_x), 12) || '|'
                    || fpad(fdt(r.mat_x), 12) || '|' || fpadl(famt(r.nom_x), 24) || '|'
                    || fpadl(famt(r.sld), 24) || '|' || fpadl(fnum(r.n_liq), 16) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,24,16');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-03', 'Produits post-comptes : creance rattachee soldee apres encaissement');
        p_obj('pour ' || k_prod_post || ', a l''echeance la creance rattachee doit etre soldee');
        po('             et une ecriture INT_%_LIQD doit prouver que l''interet a bien ete');
        po('             encaisse. Une creance qui subsiste est un interet comptabilise mais');
        po('             jamais recu.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.sld, q.n_int
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) sld,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD' THEN 1 ELSE 0 END) n_int
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE INSTR(',' || k_prod_post || ',', ',' || TRIM(m.product) || ',') > 0
                   AND m.maturity_date <= k_arrete)
         WHERE ABS(sld) > k_tol_abs OR n_int = 0;
        p_verdict('LIF-03', 'Creance rattachee non soldee ou interet jamais encaisse (post-comptes)',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,24,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('INT. DU CONTRAT', 24) || '|' || fpadl('CREANCE RESIDUELLE', 24) || '|'
                || fpadl('NB ENCAISSEMENTS', 20) || '|');
            tbl_line('4,24,8,12,12,24,24,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.sld, q.n_int, m.product, m.booking_date bd,
                               m.maturity_date md, NVL(m.main_comp_amount, 0) it
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld,
                                       SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD' THEN 1 ELSE 0 END) n_int
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE INSTR(',' || k_prod_post || ',', ',' || TRIM(m.product) || ',') > 0
                           AND m.maturity_date <= k_arrete
                           AND (ABS(q.sld) > k_tol_abs OR q.n_int = 0)
                         ORDER BY ABS(q.sld) DESC, m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.it), 24) || '|' || fpadl(famt(r.sld), 24) || '|'
                    || fpadl(fnum(r.n_int), 20) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,24,20');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-04', 'Produits pre-comptes : produit percu d''avance solde a l''echeance');
        p_obj('pour ' || k_prod_pre || ', l''interet encaisse le premier jour est etale sur la');
        po('             duree. A l''echeance le compte ' || SUBSTR(k_ac_pca, 1, 3) || 'xxxxxx doit etre solde :');
        po('             le montant encaisse au depart egale la somme des reprises quotidiennes.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.sld
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.ac_no LIKE SUBSTR(k_ac_pca, 1, 3) || '%'
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) sld
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE INSTR(',' || k_prod_pre || ',', ',' || TRIM(m.product) || ',') > 0
                   AND m.maturity_date <= k_arrete)
         WHERE ABS(sld) > k_tol_abs;
        p_verdict('LIF-04', 'Produit percu d''avance non resorbe a l''echeance (pre-comptes)',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('INT. DU CONTRAT', 24) || '|' || fpadl('PCA RESIDUEL', 24) || '|');
            tbl_line('4,24,8,12,12,24,24');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.sld, m.product, m.booking_date bd, m.maturity_date md,
                               NVL(m.main_comp_amount, 0) it
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.ac_no LIKE SUBSTR(k_ac_pca, 1, 3) || '%'
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE INSTR(',' || k_prod_pre || ',', ',' || TRIM(m.product) || ',') > 0
                           AND m.maturity_date <= k_arrete
                           AND ABS(q.sld) > k_tol_abs
                         ORDER BY ABS(q.sld) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.it), 24) || '|' || fpadl(famt(r.sld), 24) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,24');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-05', 'Les liquidations anticipees sont identifiees et documentees');
        p_obj('une liquidation du principal anterieure a l''echeance est une cession ou');
        po('             un remboursement anticipe. Elle doit etre documentee et les');
        po('             provisions doivent s''arreter a la date de liquidation. Le test est');
        po('             cale sur le tag comptable PRINCIPAL_LIQD, seul marqueur fiable du');
        po('             remboursement du capital.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, m.lcy_amount nom, q.dliq, m.maturity_date md
                  FROM (SELECT h.trn_ref_no ref, MIN(h.trn_dt) dliq
                          FROM actb_history h
                         WHERE h.module = k_mod
                           AND h.amount_tag = 'PRINCIPAL_LIQD'
                           AND NVL(h.lcy_amount, 0) > 0
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1)
         WHERE TRUNC(md) - TRUNC(dliq) > k_ret_liq;
        p_verdict('LIF-05', 'Liquidation du principal anterieure a l''echeance contractuelle',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,12,16,24,20');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpad('LIQUIDATION', 12) || '|'
                || fpadl('ANTICIPE (J)', 16) || '|' || fpadl('NOMINAL', 24) || '|'
                || fpadl('DERN. PROVISION', 20) || '|');
            tbl_line('4,24,8,12,12,12,16,24,20');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.dliq, q.daccr, m.product, m.booking_date bd,
                               m.maturity_date md, m.lcy_amount nom
                          FROM (SELECT h.trn_ref_no ref,
                                       MIN(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD'
                                                 AND NVL(h.lcy_amount, 0) > 0 THEN h.trn_dt END) dliq,
                                       MAX(CASE WHEN h.event = 'ACCR' THEN h.trn_dt END) daccr
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE q.dliq IS NOT NULL
                           AND TRUNC(m.maturity_date) - TRUNC(q.dliq) > k_ret_liq
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpad(fdt(r.dliq), 12) || '|'
                    || fpadl(fnum(TRUNC(r.md) - TRUNC(r.dliq)), 16) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(fdt(r.daccr), 20) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,12,16,24,20');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-06', 'Les contrats vivants portent le bon solde de titres');
        p_obj('sur un contrat non echu et non liquide, le solde signe du compte de');
        po('             titres doit egaler le nominal. Un solde inferieur signale une sortie');
        po('             partielle non tracee, un solde superieur un double enregistrement.');
        SELECT COUNT(*), NVL(SUM(ABS(sld - nom)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.sld, m.lcy_amount nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) sld,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE q.n_liq = 0 AND m.maturity_date > k_arrete)
         WHERE ABS(sld - nom) > k_tol_abs;
        p_verdict('LIF-06', 'Contrat vivant dont le solde de titres differe du nominal',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,24,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('NOMINAL', 24) || '|' || fpadl('SOLDE TITRES', 24) || '|'
                || fpadl('ECART', 24) || '|');
            tbl_line('4,24,8,12,12,24,24,24');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.sld, m.product, m.booking_date bd, m.maturity_date md,
                               m.lcy_amount nom
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE q.n_liq = 0 AND m.maturity_date > k_arrete
                           AND ABS(q.sld - m.lcy_amount) > k_tol_abs
                         ORDER BY ABS(q.sld - m.lcy_amount) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(famt(r.sld), 24) || '|'
                    || fpadl(famt(r.sld - r.nom), 24) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,24,24');
        END IF;

        -- -----------------------------------------------------
        p_test('LIF-07', 'Aucune position echue restee ouverte au bilan');
        p_obj('un contrat dont l''echeance est passee et dont le compte de titres n''est');
        po('             pas solde signifie que la contrepartie n''a pas rembourse, ou que');
        po('             l''ecriture de sortie a ete oubliee. Dans les deux cas la position');
        po('             figure encore a l''actif alors qu''elle ne le devrait plus.');
        SELECT COUNT(*), NVL(SUM(ABS(sld)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.sld
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) sld
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE m.maturity_date <= k_arrete)
         WHERE ABS(sld) > k_tol_abs;
        p_verdict('LIF-07', 'Position echue toujours ouverte au bilan',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,16,24,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|'
                || fpadl('ECHU DEPUIS (J)', 16) || '|' || fpadl('NOMINAL', 24) || '|'
                || fpadl('SOLDE TITRES OUVERT', 24) || '|');
            tbl_line('4,24,8,12,12,16,24,24');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.sld, m.product, m.booking_date bd, m.maturity_date md,
                               m.lcy_amount nom
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd, k_ac_tit_tr)
                                                THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                     ELSE -NVL(h.lcy_amount, 0) END
                                                ELSE 0 END) sld
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE m.maturity_date <= k_arrete
                           AND ABS(q.sld) > k_tol_abs
                         ORDER BY ABS(q.sld) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(fnum(TRUNC(k_arrete) - TRUNC(r.md)), 16) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(famt(r.sld), 24) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,16,24,24');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 22. REV : EXTOURNES, ANNULATIONS ET AMENDEMENTS
    -- =========================================================
    print_section('22. CONTROLES REV : EXTOURNES, ANNULATIONS ET AMENDEMENTS');
    BEGIN
        po('  Dans ACTB_HISTORY une extourne n''inverse pas le sens : elle reprend le');
        po('  meme sens avec un montant NEGATIF. Un etat qui cumulerait les debits');
        po('  bruts d''un cote et les credits bruts de l''autre lirait donc les');
        po('  extournes a l''envers et gonflerait les deux colonnes. C''est le piege');
        po('  central de cette section, teste explicitement en REV-03.');

        -- -----------------------------------------------------
        p_test('REV-01', 'Toute ecriture negative trouve son ecriture d''origine');
        p_obj('une extourne doit annuler une ecriture existante : meme contrat, meme');
        po('             tag, meme compte, meme montant en valeur absolue. Une ligne negative');
        po('             non appariee est une sur-extourne, qui retire du bilan un montant qui');
        po('             n''y avait pas ete mis.');
        SELECT COUNT(*), COUNT(DISTINCT ref), NVL(SUM(ABS(mt)), 0) INTO v_cnt, v_cnt2, v_mt
          FROM (SELECT h.trn_ref_no ref, h.amount_tag, h.ac_no, h.drcr_ind,
                       ABS(NVL(h.lcy_amount, 0)) mt,
                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                       SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END) n_pos
                  FROM actb_history h
                 WHERE h.module = k_mod
                 GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                          ABS(NVL(h.lcy_amount, 0)))
         WHERE n_neg > n_pos;
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('REV-01', 'Ecriture negative sans ecriture d''origine appariee',
                  v_cnt, NULL, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,12,12,18,22,6,14,14,22');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpad('TAG DE MONTANT', 18) || '|'
                || fpad('COMPTE (AC_NO)', 22) || '|' || fpad('D/C', 6) || '|'
                || fpadl('NB NEGATIVES', 14) || '|' || fpadl('NB POSITIVES', 14) || '|'
                || fpadl('MONTANT UNITAIRE', 22) || '|');
            tbl_line('4,24,12,12,18,22,6,14,14,22');
            v_row := 0;
            FOR r IN (SELECT q0.*,
                         (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) bkg_x,
                         (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                           WHERE mm.contract_ref_no = q0.ref) mat_x
                     FROM (SELECT * FROM (
                        SELECT h.trn_ref_no ref, h.amount_tag, h.ac_no, h.drcr_ind,
                               ABS(NVL(h.lcy_amount, 0)) mt,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END) n_pos
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no, h.amount_tag, h.ac_no, h.drcr_ind,
                                  ABS(NVL(h.lcy_amount, 0))
                        HAVING SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END)
                             > SUM(CASE WHEN NVL(h.lcy_amount, 0) > 0 THEN 1 ELSE 0 END)
                         ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= k_top) q0) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                    || fpad(r.amount_tag, 18) || '|' || fpad(r.ac_no, 22) || '|'
                    || fpad(r.drcr_ind, 6) || '|' || fpadl(fnum(r.n_neg), 14) || '|'
                    || fpadl(fnum(r.n_pos), 14) || '|' || fpadl(famt(r.mt), 22) || '|');
            END LOOP;
            tbl_line('4,24,12,12,18,22,6,14,14,22');
        END IF;

        -- -----------------------------------------------------
        p_test('REV-02', 'Les contrats integralement extournes sont rebookes ou annules');
        p_obj('un contrat dont tous les soldes sont revenus a zero sans aucune');
        po('             liquidation a ete annule comptablement. Il doit avoir ete rebooke');
        po('             sous une autre reference, ou son annulation doit etre confirmee par');
        po('             le front office. Le tableau recherche un contrat de remplacement');
        po('             portant le meme nominal, le meme taux et les memes dates.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, m.lcy_amount nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) sld,
                               SUM(ABS(NVL(h.lcy_amount, 0))) brut,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE q.n_liq = 0 AND q.n_neg > 0 AND q.brut > 0
                   AND ABS(q.sld) <= k_tol_abs);
        p_verdict('REV-02', 'Contrat integralement extourne, ni liquide ni rebooke de facon evidente',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,10,24,14');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT EXTOURNE', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('NOMINAL', 24) || '|'
                || fpadl('TAUX', 10) || '|' || fpad('CONTRAT DE REMPLACEMENT', 24) || '|'
                || fpadl('NB CANDIDATS', 14) || '|');
            tbl_line('4,24,8,12,12,24,10,24,14');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, m.product, m.booking_date bd, m.maturity_date md,
                               m.lcy_amount nom, m.main_comp_rate tx,
                               (SELECT MIN(x.contract_ref_no) FROM ldtb_contract_master x
                                 WHERE x.module = k_mod
                                   AND x.version_no = 1
                                   AND x.contract_ref_no <> m.contract_ref_no
                                   AND x.lcy_amount = m.lcy_amount
                                   AND NVL(x.main_comp_rate, -1) = NVL(m.main_comp_rate, -1)
                                   AND x.value_date = m.value_date
                                   AND x.maturity_date = m.maturity_date) remp,
                               (SELECT COUNT(*) FROM ldtb_contract_master x
                                 WHERE x.module = k_mod
                                   AND x.version_no = 1
                                   AND x.contract_ref_no <> m.contract_ref_no
                                   AND x.lcy_amount = m.lcy_amount
                                   AND NVL(x.main_comp_rate, -1) = NVL(m.main_comp_rate, -1)
                                   AND x.value_date = m.value_date
                                   AND x.maturity_date = m.maturity_date) nbr
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) sld,
                                       SUM(ABS(NVL(h.lcy_amount, 0))) brut,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE q.n_liq = 0 AND q.n_neg > 0 AND q.brut > 0
                           AND ABS(q.sld) <= k_tol_abs
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(ftx(r.tx), 10) || '|'
                    || fpad(NVL(r.remp, 'AUCUN'), 24) || '|' || fpadl(fnum(r.nbr), 14) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,10,24,14');
        END IF;

        -- -----------------------------------------------------
        p_test('REV-03', 'Les extournes sont cumulees en montants signes, pas en bruts');
        p_obj('demonstration chiffree du piege. Le meme portefeuille est cumule de deux');
        po('             facons : en montants signes (methode retenue par ce script) et en');
        po('             montants absolus (methode piegeuse). L''ecart mesure exactement ce');
        po('             qu''un etat en bruts surestimerait.');
        SELECT NVL(SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'D' THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END), 0),
               NVL(SUM(CASE WHEN h.drcr_ind = 'C' THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END), 0)
          INTO v_mt, v_tot, v_tot2, v_mt2
          FROM actb_history h WHERE h.module = k_mod;
        tbl_line('4,44,26,26,24');
        po('  |' || fpad('N#', 4) || '|' || fpad('METHODE DE CUMUL', 44) || '|'
            || fpadl('TOTAL DEBIT', 26) || '|' || fpadl('TOTAL CREDIT', 26) || '|'
            || fpadl('ECART D MOINS C', 24) || '|');
        tbl_line('4,44,26,26,24');
        po('  |' || fpadl('1', 4) || '|' || fpad('Montants signes (extournes en negatif)', 44) || '|'
            || fpadl(fmio(v_mt), 26) || '|' || fpadl(fmio(v_tot), 26) || '|'
            || fpadl(famt(v_mt - v_tot), 24) || '|');
        po('  |' || fpadl('2', 4) || '|' || fpad('Montants absolus (methode piegeuse)', 44) || '|'
            || fpadl(fmio(v_tot2), 26) || '|' || fpadl(fmio(v_mt2), 26) || '|'
            || fpadl(famt(v_tot2 - v_mt2), 24) || '|');
        tbl_line('4,44,26,26,24');
        print_kv('Surestimation du debit par la methode brute',  fmio(v_tot2 - v_mt));
        print_kv('Surestimation du credit par la methode brute', fmio(v_mt2 - v_tot));
        IF ABS(v_tot2 - v_mt) > k_tol_abs OR ABS(v_mt2 - v_tot) > k_tol_abs THEN
            v_cnt := 1;
        ELSE
            v_cnt := 0;
        END IF;
        p_verdict('REV-03', 'Un cumul en montants bruts fausserait les etats du module',
                  v_cnt, 1, ABS(v_tot2 - v_mt) + ABS(v_mt2 - v_tot), 'ELEVE');
        po('     Le present script cumule partout en montants signes. Ce verdict n''est');
        po('     pas une anomalie de la base : il chiffre le risque encouru par tout');
        po('     etat qui cumulerait en bruts.');

        -- -----------------------------------------------------
        p_test('REV-04', 'Aucune ecriture passee dans une periode deja arretee');
        p_obj('deux signaux. Le code periode de l''ecriture doit correspondre au mois');
        po('             de sa date comptable ; et la date comptable ne doit pas preceder la');
        po('             date de booking du contrat, ce qui reviendrait a comptabiliser une');
        po('             operation avant qu''elle existe.');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.period_code IS NOT NULL
           AND h.trn_dt IS NOT NULL
           AND TRIM(h.period_code) <> TO_CHAR(h.trn_dt, 'MM');
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('REV-04', 'Ecriture dont le code periode ne correspond pas a sa date comptable',
                  v_cnt, NULL, v_mt, 'ELEVE');
        SELECT COUNT(*), COUNT(DISTINCT h.trn_ref_no), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0)
          INTO v_cnt, v_cnt2, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND TRUNC(h.trn_dt) < (SELECT TRUNC(MIN(m.booking_date))
                                    FROM ldtb_contract_master m
                                   WHERE m.contract_ref_no = h.trn_ref_no);
        print_kv('Contrats concernes', fnum(v_cnt2));
        p_verdict('REV-04b', 'Ecriture anterieure a la date de booking de son contrat',
                  v_cnt, NULL, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('REV-05', 'Un amendement de taux est suivi d''un rattrapage de provisions');
        p_obj('LDTB_CONTRACT_MASTER conserve une ligne par version. Un taux different');
        po('             entre deux versions est un amendement : les provisions doivent avoir');
        po('             ete recalculees a partir de la date d''amendement, et le cumul doit');
        po('             encore boucler sur le montant d''interets amende.');
        SELECT COUNT(*) INTO v_tot
          FROM (SELECT m.contract_ref_no
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                 GROUP BY m.contract_ref_no
                HAVING COUNT(DISTINCT NVL(m.main_comp_rate, -1)) > 1
                    OR COUNT(DISTINCT m.maturity_date) > 1);
        print_kv('Contrats amendes (taux ou echeance modifie)', fnum(v_tot));
        SELECT COUNT(*), NVL(SUM(ABS(ecart)), 0) INTO v_cnt, v_mt
          FROM (SELECT a.contract_ref_no,
                       NVL((SELECT MAX(NVL(x.main_comp_amount, 0)) FROM ldtb_contract_master x
                             WHERE x.contract_ref_no = a.contract_ref_no
                               AND x.version_no = (SELECT MAX(v.version_no)
                                                     FROM ldtb_contract_master v
                                                    WHERE v.contract_ref_no = a.contract_ref_no)), 0)
                       - NVL((SELECT SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END)
                                FROM actb_history h
                               WHERE h.trn_ref_no = a.contract_ref_no
                                 AND h.module = k_mod
                                 AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'), 0) ecart
                  FROM (SELECT m.contract_ref_no
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                         GROUP BY m.contract_ref_no
                        HAVING COUNT(DISTINCT NVL(m.main_comp_rate, -1)) > 1
                            OR COUNT(DISTINCT m.maturity_date) > 1) a
                 WHERE EXISTS (SELECT 1 FROM ldtb_contract_master y
                                WHERE y.contract_ref_no = a.contract_ref_no
                                  AND y.maturity_date <= k_arrete))
         WHERE ABS(ecart) > k_tol_abs;
        p_verdict('REV-05', 'Contrat amende dont les provisions n''ont pas ete rattrapees',
                  v_cnt, v_tot, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('REV-06', 'Le produit annule dans le mois est suivi');
        p_obj('un revenu comptabilise puis annule dans le meme mois disparait du solde');
        po('             net mais reste dans les credits bruts. Utiliser le brut pour piloter');
        po('             la performance surevalue le revenu. Le tableau oppose, mois par mois,');
        po('             le credit brut et le solde net des comptes de produits.');
        tbl_line('4,14,16,24,24,24,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('MOIS', 14) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('CREDIT BRUT', 24) || '|' || fpadl('DEBIT BRUT', 24) || '|'
            || fpadl('PRODUIT NET', 24) || '|' || fpadl('ECART', 16) || '|');
        tbl_line('4,14,16,24,24,24,16');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mois, COUNT(*) nb,
                         SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                         SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb
                    FROM actb_history h
                   WHERE h.module = k_mod
                     AND h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'
                   GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM')
                   ORDER BY 1) LOOP
            v_row := v_row + 1;
            IF ABS(r.deb) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(r.deb);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mois, 14) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.cre), 24) || '|'
                || fpadl(fmio(r.deb), 24) || '|' || fpadl(fmio(r.cre - r.deb), 24) || '|'
                || fpadl(CASE WHEN ABS(r.deb) > k_tol_abs THEN 'ANNULATIONS' ELSE '-' END, 16) || '|');
        END LOOP;
        tbl_line('4,14,16,24,24,24,16');
        p_verdict('REV-06', 'Mois comportant des annulations de produit deja comptabilise',
                  v_cnt, v_row, v_mt, 'MOYEN');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 23. CSH : RAPPROCHEMENT DE TRESORERIE
    -- =========================================================
    print_section('23. CONTROLES CSH : RAPPROCHEMENT DE TRESORERIE');
    BEGIN
        po('  C''est le seul controle qui prouve que l''argent a reellement bouge. Une');
        po('  ecriture equilibree, correctement mappee et parfaitement provisionnee');
        po('  peut porter sur un decaissement qui n''a jamais eu lieu.');
        po('');
        po('  LIMITE . le releve de compte BEAC n''est pas dans la base. Le script');
        po('  teste donc ici ce qui est verifiable en base (existence, sens et');
        po('  coherence de la jambe de tresorerie) et prepare, dans les tableaux');
        po('  d''extraction, la liste des mouvements a pointer sur le releve.');

        -- -----------------------------------------------------
        p_test('CSH-01', 'Achats et remboursements adosses a un mouvement de tresorerie');
        p_obj('toute ecriture PRINCIPAL ou PRINCIPAL_LIQD doit s''accompagner, pour le');
        po('             meme contrat, d''une jambe sur ' || k_ac_nostro || ' ou sur un compte');
        po('             de general naturel ' || k_gl_treso || 'xxx. Son absence signifie que la');
        po('             contrepartie de l''operation n''est pas la tresorerie.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, MAX(m.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                        THEN 1 ELSE 0 END) n_pr,
                               SUM(CASE WHEN h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                                         AND (h.ac_no = k_ac_nostro
                                              OR EXISTS (SELECT 1 FROM sttb_account a
                                                          WHERE a.ac_gl_no = h.ac_no
                                                            AND NVL(a.ac_natural_gl, ' ')
                                                                LIKE k_gl_treso || '%'))
                                        THEN 1 ELSE 0 END) n_tr
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE q.n_pr > 0 AND q.n_tr = 0
                 GROUP BY q.ref);
        p_verdict('CSH-01', 'Achat ou remboursement sans jambe de tresorerie',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');

        print_sub('CSH-01 a. Extraction des mouvements a pointer sur le releve BEAC');
        po('  Mouvements du nostro ' || k_ac_nostro || ' portes par le module, tries par');
        po('  montant decroissant. Chaque ligne doit se retrouver sur le releve a la');
        po('  meme date et pour le meme montant. La colonne POINTE est a servir');
        po('  manuellement lors du rapprochement.');
        tbl_line('4,24,12,12,12,18,6,24,10');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('BOOKING', 12) || '|'
            || fpad('ECHEANCE', 12) || '|' || fpad('DATE VALEUR', 12) || '|'
            || fpad('TAG DE MONTANT', 18) || '|' || fpad('D/C', 6) || '|'
            || fpadl('MONTANT LCY', 24) || '|' || fpad('POINTE', 10) || '|');
        tbl_line('4,24,12,12,12,18,6,24,10');
        v_row := 0;
        FOR r IN (SELECT q0.*,
                     (SELECT MAX(mm.booking_date) FROM ldtb_contract_master mm
                       WHERE mm.contract_ref_no = q0.ref) bkg_x,
                     (SELECT MAX(mm.maturity_date) FROM ldtb_contract_master mm
                       WHERE mm.contract_ref_no = q0.ref) mat_x
                 FROM (SELECT * FROM (
                    SELECT h.trn_ref_no ref, h.value_dt vd, h.amount_tag, h.drcr_ind,
                           h.lcy_amount mt
                      FROM actb_history h
                     WHERE h.module = k_mod
                       AND h.ac_no = k_ac_nostro
                       AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD')
                     ORDER BY ABS(NVL(h.lcy_amount, 0)) DESC
                  ) WHERE ROWNUM <= k_top) q0) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                || fpad(fdt(r.bkg_x), 12) || '|' || fpad(fdt(r.mat_x), 12) || '|'
                || fpad(fdt(r.vd), 12) || '|' || fpad(r.amount_tag, 18) || '|'
                || fpad(r.drcr_ind, 6) || '|' || fpadl(famt(r.mt), 24) || '|'
                || fpad('[    ]', 10) || '|');
        END LOOP;
        tbl_line('4,24,12,12,12,18,6,24,10');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no = k_ac_nostro
           AND h.amount_tag IN ('PRINCIPAL', 'PRINCIPAL_LIQD');
        print_kv('Mouvements de principal a pointer sur le releve', fnum(v_cnt));
        print_kv('Montant cumule a pointer',                        fmio(v_mt));

        -- -----------------------------------------------------
        p_test('CSH-02', 'Encaissements d''interets adosses a un mouvement de tresorerie');
        p_obj('meme raisonnement sur les tags d''encaissement d''interets. Un interet');
        po('             liquide comptablement sans mouvement de tresorerie est un produit');
        po('             reconnu sans encaissement.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, MAX(m.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD' THEN 1 ELSE 0 END) n_int,
                               SUM(CASE WHEN h.amount_tag LIKE 'INT%LIQD'
                                         AND (h.ac_no = k_ac_nostro
                                              OR EXISTS (SELECT 1 FROM sttb_account a
                                                          WHERE a.ac_gl_no = h.ac_no
                                                            AND NVL(a.ac_natural_gl, ' ')
                                                                LIKE k_gl_treso || '%'))
                                        THEN 1 ELSE 0 END) n_tr
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE q.n_int > 0 AND q.n_tr = 0
                 GROUP BY q.ref);
        p_verdict('CSH-02', 'Encaissement d''interets sans jambe de tresorerie',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        SELECT COUNT(*), NVL(SUM(ABS(NVL(h.lcy_amount, 0))), 0) INTO v_cnt, v_mt
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no = k_ac_nostro
           AND h.amount_tag LIKE 'INT%LIQD';
        print_kv('Encaissements d''interets a pointer sur le releve', fnum(v_cnt));
        print_kv('Montant cumule a pointer',                          fmio(v_mt));

        -- -----------------------------------------------------
        p_test('CSH-03', 'Contrats annules : verifier si la tresorerie a reellement bouge');
        p_obj('une extourne comptable ne fait pas revenir l''argent. Pour chaque');
        po('             contrat integralement extourne, le tableau donne la sortie de');
        po('             tresorerie d''origine et le retour eventuel : c''est sur le releve');
        po('             BEAC que se verifie leur realite.');
        SELECT COUNT(*), NVL(SUM(ABS(treso)), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, q.treso
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                            ELSE -NVL(h.lcy_amount, 0) END) sld,
                               SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                               SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                               SUM(CASE WHEN h.ac_no = k_ac_nostro
                                        THEN CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                             ELSE -NVL(h.lcy_amount, 0) END
                                        ELSE 0 END) treso
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                 WHERE q.n_neg > 0 AND q.n_liq = 0 AND ABS(q.sld) <= k_tol_abs);
        p_verdict('CSH-03', 'Contrat annule dont le retour de tresorerie reste a prouver sur piece',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,24,24,10');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT ANNULE', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('NOMINAL', 24) || '|'
                || fpadl('SORTIE DE TRESORERIE', 24) || '|' || fpadl('RETOUR CONSTATE', 24) || '|'
                || fpad('POINTE', 10) || '|');
            tbl_line('4,24,8,12,12,24,24,24,10');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT q.ref, q.sortie, q.retour, m.product, m.booking_date bd,
                               m.maturity_date md, m.lcy_amount nom
                          FROM (SELECT h.trn_ref_no ref,
                                       SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                    ELSE -NVL(h.lcy_amount, 0) END) sld,
                                       SUM(CASE WHEN NVL(h.lcy_amount, 0) < 0 THEN 1 ELSE 0 END) n_neg,
                                       SUM(CASE WHEN h.amount_tag = 'PRINCIPAL_LIQD' THEN 1 ELSE 0 END) n_liq,
                                       SUM(CASE WHEN h.ac_no = k_ac_nostro AND h.drcr_ind = 'C'
                                                 AND NVL(h.lcy_amount, 0) > 0
                                                THEN NVL(h.lcy_amount, 0) ELSE 0 END) sortie,
                                       SUM(CASE WHEN h.ac_no = k_ac_nostro AND NVL(h.lcy_amount, 0) < 0
                                                THEN ABS(NVL(h.lcy_amount, 0)) ELSE 0 END) retour
                                  FROM actb_history h
                                 WHERE h.module = k_mod
                                 GROUP BY h.trn_ref_no) q
                          JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                     AND m.version_no = 1
                         WHERE q.n_neg > 0 AND q.n_liq = 0 AND ABS(q.sld) <= k_tol_abs
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(famt(r.sortie), 24) || '|'
                    || fpadl(famt(r.retour), 24) || '|' || fpad('[    ]', 10) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,24,24,10');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 24. CUT : ARRETE DE PERIODE
    -- =========================================================
    print_section('24. CONTROLES CUT : ARRETE DE PERIODE');
    BEGIN
        SELECT MAX(accrual_to_date) INTO v_d_accr
          FROM ldtb_contract_accrual_history WHERE module = k_mod;
        po('  A chaque arrete, quatre soldes de bilan doivent se justifier ligne a');
        po('  ligne par le portefeuille vivant : les titres, les creances rattachees,');
        po('  les produits percus d''avance et le resultat du mois. Le script');
        po('  reconstitue chacun de ces quatre montants a partir des contrats et le');
        po('  confronte au solde comptable.');
        po('');
        po('  LIMITE . la balance generale et l''etat de position titres ne sont pas');
        po('  dans la base. Le rapprochement final avec ces deux etats reste a faire');
        po('  sur piece ; le script en fournit le terme reconstitue.');
        print_kv('Derniere provision enregistree par le module', fdt(v_d_accr));

        -- -----------------------------------------------------
        p_test('CUT-01', 'Les provisions vont jusqu''au dernier jour du mois');
        p_obj('a chaque fin de mois, tout contrat vivant doit porter une provision');
        po('             datee du dernier jour calendaire du mois. Le test est borne au');
        po('             ' || fdt(v_d_accr) || ', derniere provision du module : au dela, l''absence');
        po('             de provision est l''arret du module et non un defaut d''arrete.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.value_date < TRUNC(v_d_accr, 'MM')
           AND m.maturity_date > LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1))
           AND NOT EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no
                              AND h.module = k_mod
                              AND h.event = 'ACCR'
                              AND TRUNC(h.trn_dt)
                                  = LAST_DAY(ADD_MONTHS(TRUNC(v_d_accr, 'MM'), -1)));
        p_verdict('CUT-01', 'Contrat vivant sans provision au dernier jour du mois teste',
                  v_cnt, v_nb_ctr, v_mt, 'CRITIQUE');
        print_sub('CUT-01 a. Couverture des fins de mois par les provisions');
        po('  Pour chaque fin de mois de la periode active du module, nombre de');
        po('  contrats vivants et nombre d''entre eux effectivement provisionnes.');
        tbl_line('4,16,18,18,14,24');
        po('  |' || fpad('N#', 4) || '|' || fpad('FIN DE MOIS', 16) || '|'
            || fpadl('CONTRATS VIVANTS', 18) || '|' || fpadl('DONT PROVISIONNES', 18) || '|'
            || fpadl('COUVERTURE', 14) || '|' || fpadl('PROVISION DU JOUR', 24) || '|');
        tbl_line('4,16,18,18,14,24');
        v_row := 0;
        v_cnt := 0;
        FOR r IN (SELECT * FROM (
                    SELECT LAST_DAY(TRUNC(h.trn_dt, 'MM')) fm, SUM(NVL(h.lcy_amount, 0)) mt,
                           COUNT(DISTINCT CASE WHEN TRUNC(h.trn_dt)
                                                    = LAST_DAY(TRUNC(h.trn_dt, 'MM'))
                                               THEN h.trn_ref_no END) nb_prov
                      FROM actb_history h
                     WHERE h.module = k_mod
                       AND h.event = 'ACCR'
                       AND h.drcr_ind = 'D'
                       AND TRUNC(h.trn_dt) = LAST_DAY(TRUNC(h.trn_dt, 'MM'))
                     GROUP BY LAST_DAY(TRUNC(h.trn_dt, 'MM'))
                     ORDER BY 1 DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            SELECT COUNT(*) INTO v_cnt2
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.version_no = 1
               AND m.value_date <= r.fm
               AND m.maturity_date > r.fm;
            IF r.nb_prov < v_cnt2 THEN
                v_cnt := v_cnt + 1;
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(fdt(r.fm), 16) || '|'
                || fpadl(fnum(v_cnt2), 18) || '|' || fpadl(fnum(r.nb_prov), 18) || '|'
                || fpadl(fpct(r.nb_prov, v_cnt2), 14) || '|' || fpadl(fmio(r.mt), 24) || '|');
        END LOOP;
        tbl_line('4,16,18,18,14,24');
        p_verdict('CUT-01b', 'Fin de mois dont tous les contrats vivants ne sont pas provisionnes',
                  v_cnt, v_row, NULL, 'ELEVE');

        -- -----------------------------------------------------
        p_test('CUT-02', 'Les provisions du mois se retrouvent au compte de resultat');
        p_obj('la somme des provisions du mois doit egaler le mouvement des comptes');
        po('             de produits ' || k_ac_prod_ob || ' et ' || k_ac_prod_bt || ' sur le meme mois.');
        po('             Un ecart signale une provision qui n''a pas trouve son compte de');
        po('             resultat, ou un produit reconnu sans provision.');
        tbl_line('4,14,20,26,26,24,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('MOIS', 14) || '|' || fpadl('NB PROVISIONS', 20) || '|'
            || fpadl('PROVISIONS DU MOIS', 26) || '|' || fpadl('PRODUITS DU MOIS', 26) || '|'
            || fpadl('ECART', 24) || '|' || fpadl('VERDICT', 14) || '|');
        tbl_line('4,14,20,26,26,24,14');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT * FROM (
                    SELECT TO_CHAR(h.trn_dt, 'YYYY-MM') mois,
                           SUM(CASE WHEN h.event = 'ACCR' AND h.drcr_ind = 'D'
                                     AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                    THEN NVL(h.lcy_amount, 0) ELSE 0 END) prov,
                           COUNT(CASE WHEN h.event = 'ACCR' AND h.drcr_ind = 'D'
                                       AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr)
                                      THEN 1 END) nb,
                           SUM(CASE WHEN h.ac_no LIKE SUBSTR(k_ac_prod_bt, 1, 3) || '%'
                                    THEN CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                                         ELSE -NVL(h.lcy_amount, 0) END
                                    ELSE 0 END) res
                      FROM actb_history h
                     WHERE h.module = k_mod
                     GROUP BY TO_CHAR(h.trn_dt, 'YYYY-MM')
                     ORDER BY 1 DESC
                  ) WHERE ROWNUM <= k_top) LOOP
            v_row := v_row + 1;
            IF ABS(r.prov - r.res) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(r.prov - r.res);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.mois, 14) || '|'
                || fpadl(fnum(r.nb), 20) || '|' || fpadl(fmio(r.prov), 26) || '|'
                || fpadl(fmio(r.res), 26) || '|' || fpadl(famt(r.prov - r.res), 24) || '|'
                || fpadl(CASE WHEN ABS(r.prov - r.res) > k_tol_abs THEN 'ECART' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,14,20,26,26,24,14');
        p_verdict('CUT-02', 'Mois dont les provisions ne se retrouvent pas au compte de resultat',
                  v_cnt, v_row, v_mt, 'CRITIQUE');
        po('     Note . l''ecart peut provenir des produits pre-comptes, dont le');
        po('     resultat vient de la reprise du compte ' || SUBSTR(k_ac_pca, 1, 3) || 'xxxxxx et non');
        po('     d''une provision sur creances rattachees. Le rapprochement final avec');
        po('     la balance generale reste a faire sur piece.');

        -- -----------------------------------------------------
        p_test('CUT-03', 'Les soldes de titres se justifient par le portefeuille vivant');
        p_obj('pour chaque compte de titres, le solde comptable signe doit egaler la');
        po('             somme des nominaux des contrats vivants rattaches a ce compte. Le');
        po('             terme reconstitue ci-dessous est celui a confronter a l''etat de');
        po('             position titres.');
        tbl_line('4,22,40,26,26,24,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE (AC_NO)', 22) || '|' || fpad('LIBELLE', 40) || '|'
            || fpadl('SOLDE COMPTABLE', 26) || '|' || fpadl('POSITION RECONSTITUEE', 26) || '|'
            || fpadl('ECART', 24) || '|' || fpadl('VERDICT', 14) || '|');
        tbl_line('4,22,40,26,26,24,14');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT 1 ord, k_ac_tit_otap ac, 'OTAP' prod FROM DUAL UNION ALL
                  SELECT 2, k_ac_tit_mtpd, 'MTPD' FROM DUAL UNION ALL
                  SELECT 3, k_ac_tit_tr, 'TBTR,BTTR' FROM DUAL
                  ORDER BY 1) LOOP
            SELECT NVL(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                           ELSE -NVL(h.lcy_amount, 0) END), 0)
              INTO v_tot
              FROM actb_history h
             WHERE h.module = k_mod AND h.ac_no = r.ac;
            SELECT NVL(SUM(m.lcy_amount), 0) INTO v_tot2
              FROM ldtb_contract_master m
             WHERE m.module = k_mod
               AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                    WHERE v.contract_ref_no = m.contract_ref_no)
               AND m.maturity_date > k_arrete
               AND INSTR(',' || r.prod || ',', ',' || TRIM(m.product) || ',') > 0
               AND EXISTS (SELECT 1 FROM actb_history h
                            WHERE h.trn_ref_no = m.contract_ref_no
                              AND h.module = k_mod
                              AND h.ac_no = r.ac);
            SELECT MAX(a.ac_gl_desc) INTO v_lib FROM sttb_account a WHERE a.ac_gl_no = r.ac;
            v_row := v_row + 1;
            IF ABS(v_tot - v_tot2) > k_tol_abs THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + ABS(v_tot - v_tot2);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac, 22) || '|' || fpad(v_lib, 40) || '|'
                || fpadl(fmio(v_tot), 26) || '|' || fpadl(fmio(v_tot2), 26) || '|'
                || fpadl(famt(v_tot - v_tot2), 24) || '|'
                || fpadl(CASE WHEN ABS(v_tot - v_tot2) > k_tol_abs THEN 'ECART' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,22,40,26,26,24,14');
        p_verdict('CUT-03', 'Compte de titres dont le solde ne se justifie pas par le portefeuille',
                  v_cnt, v_row, v_mt, 'CRITIQUE');

        -- -----------------------------------------------------
        p_test('CUT-04', 'Le solde des produits percus d''avance egale l''interet non couru');
        p_obj('pour les produits pre-comptes, le solde du compte ' || SUBSTR(k_ac_pca, 1, 3) || 'xxxxxx doit');
        po('             egaler la part d''interets non encore courue des contrats vivants,');
        po('             soit interets x jours restants / duree totale. Un residu porte par un');
        po('             contrat deja echu est une reprise jamais passee.');
        SELECT NVL(SUM(CASE h.drcr_ind WHEN 'C' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0)
          INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no LIKE SUBSTR(k_ac_pca, 1, 3) || '%';
        SELECT NVL(SUM(ROUND(NVL(m.main_comp_amount, 0)
                             * (TRUNC(m.maturity_date) - TRUNC(k_arrete))
                             / NULLIF(m.maturity_date - m.value_date, 0), 2)), 0)
          INTO v_tot2
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.maturity_date > k_arrete
           AND INSTR(',' || k_prod_pre || ',', ',' || TRIM(m.product) || ',') > 0;
        print_kv('Solde comptable des produits percus d''avance', fmio(v_tot));
        print_kv('Interets non courus des contrats vivants pre-comptes', fmio(v_tot2));
        print_kv('Ecart', famt(v_tot - v_tot2));
        IF ABS(v_tot - v_tot2) > k_tol_abs THEN v_cnt := 1; ELSE v_cnt := 0; END IF;
        p_verdict('CUT-04', 'Solde des produits percus d''avance non justifie par les contrats vivants',
                  v_cnt, 1, ABS(v_tot - v_tot2), 'CRITIQUE');

        -- -----------------------------------------------------
        p_test('CUT-05', 'Le solde des creances rattachees egale l''interet couru non encaisse');
        p_obj('pour les produits post-comptes, le solde des comptes ' || k_ac_crat_pl || ' et');
        po('             ' || k_ac_crat_tr || ' doit egaler les interets courus et non encore encaisses');
        po('             des contrats vivants. Le terme theorique est borne a la derniere');
        po('             provision du module, le module ayant cesse de provisionner.');
        SELECT NVL(SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                       ELSE -NVL(h.lcy_amount, 0) END), 0)
          INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no IN (k_ac_crat_pl, k_ac_crat_tr);
        SELECT NVL(SUM(ROUND(NVL(m.main_comp_amount, 0)
                             * (TRUNC(LEAST(v_d_accr, m.maturity_date)) - TRUNC(m.value_date))
                             / NULLIF(m.maturity_date - m.value_date, 0), 2)), 0)
          INTO v_tot2
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND m.maturity_date > k_arrete
           AND m.value_date < v_d_accr
           AND INSTR(',' || k_prod_post || ',', ',' || TRIM(m.product) || ',') > 0;
        print_kv('Solde comptable des creances rattachees', fmio(v_tot));
        print_kv('Interets courus non encaisses des contrats vivants', fmio(v_tot2));
        print_kv('Ecart', famt(v_tot - v_tot2));
        IF ABS(v_tot - v_tot2) > k_tol_abs THEN v_cnt := 1; ELSE v_cnt := 0; END IF;
        p_verdict('CUT-05', 'Solde des creances rattachees non justifie par les contrats vivants',
                  v_cnt, 1, ABS(v_tot - v_tot2), 'CRITIQUE');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 25. CLS : CLASSIFICATION ET VALORISATION
    -- =========================================================
    print_section('25. CONTROLES CLS : CLASSIFICATION ET VALORISATION');
    BEGIN
        po('  Le classement d''un titre en portefeuille de placement (' || k_gl_tit_pl || 'xxxxxx) ou de');
        po('  transaction (' || k_gl_tit_tr || 'xxxxxx) determine son traitement comptable : le titre');
        po('  de transaction se valorise au prix de marche, le titre de placement');
        po('  s''amortit. Le classement se decide a l''entree et ne se change pas.');

        -- -----------------------------------------------------
        p_test('CLS-01', 'Le classement placement ou transaction est stable et coherent');
        p_obj('un contrat ne doit toucher qu''une seule des deux familles de comptes');
        po('             de titres sur toute sa vie. Un contrat qui touche les deux a change de');
        po('             portefeuille : ce transfert doit etre approuve et documente.');
        SELECT COUNT(*), NVL(SUM(nom), 0) INTO v_cnt, v_mt
          FROM (SELECT q.ref, MAX(m.lcy_amount) nom
                  FROM (SELECT h.trn_ref_no ref,
                               SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd)
                                        THEN 1 ELSE 0 END) n_pl,
                               SUM(CASE WHEN h.ac_no = k_ac_tit_tr THEN 1 ELSE 0 END) n_tr
                          FROM actb_history h
                         WHERE h.module = k_mod
                         GROUP BY h.trn_ref_no) q
                  JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                             AND m.version_no = 1
                 WHERE q.n_pl > 0 AND q.n_tr > 0
                 GROUP BY q.ref);
        p_verdict('CLS-01', 'Contrat ayant touche a la fois le portefeuille placement et transaction',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        print_sub('CLS-01 a. Repartition du portefeuille entre les deux livres');
        tbl_line('4,10,20,16,26,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('LIVRE', 20) || '|'
            || fpadl('NB CONTRATS', 16) || '|' || fpadl('MONTANT LCY', 26) || '|'
            || fpadl('% DU TOTAL', 16) || '|');
        tbl_line('4,10,20,16,26,16');
        v_row := 0;
        FOR r IN (SELECT p.prod, p.livre, COUNT(*) nb, SUM(p.nom) mt FROM (
                    SELECT q.ref, MAX(m.product) prod, MAX(m.lcy_amount) nom,
                           CASE WHEN MAX(q.n_pl) > 0 AND MAX(q.n_tr) > 0 THEN 'les deux'
                                WHEN MAX(q.n_pl) > 0 THEN 'placement (' || k_gl_tit_pl || ')'
                                WHEN MAX(q.n_tr) > 0 THEN 'transaction (' || k_gl_tit_tr || ')'
                                ELSE 'aucun compte titres' END livre
                      FROM (SELECT h.trn_ref_no ref,
                                   SUM(CASE WHEN h.ac_no IN (k_ac_tit_otap, k_ac_tit_mtpd)
                                            THEN 1 ELSE 0 END) n_pl,
                                   SUM(CASE WHEN h.ac_no = k_ac_tit_tr THEN 1 ELSE 0 END) n_tr
                              FROM actb_history h
                             WHERE h.module = k_mod
                             GROUP BY h.trn_ref_no) q
                      JOIN ldtb_contract_master m ON m.contract_ref_no = q.ref
                                                 AND m.version_no = 1
                     GROUP BY q.ref) p
                   GROUP BY p.prod, p.livre
                   ORDER BY SUM(p.nom) DESC) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.prod, 10) || '|'
                || fpad(r.livre, 20) || '|' || fpadl(fnum(r.nb), 16) || '|'
                || fpadl(fmio(r.mt), 26) || '|' || fpadl(fpct(r.mt, v_mt_ctr), 16) || '|');
        END LOOP;
        tbl_line('4,10,20,16,26,16');

        -- -----------------------------------------------------
        p_test('CLS-02', 'Les titres de transaction sont valorises si la politique l''exige');
        p_obj('un titre classe en transaction se valorise au prix de marche a chaque');
        po('             arrete. L''absence totale d''ecriture de valorisation sur les comptes');
        po('             ' || k_gl_tit_tr || 'xxxxxx est en soi un constat : soit la politique comptable ne');
        po('             l''exige pas et le classement en transaction est a challenger, soit');
        po('             elle l''exige et la valorisation n''est pas faite.');
        SELECT COUNT(*) INTO v_tot
          FROM actb_history h
         WHERE h.module = k_mod AND h.ac_no = k_ac_tit_tr;
        print_kv('Ecritures sur le compte de titres de transaction', fnum(v_tot));
        v_cnt := 0;
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM rvtb_acc_reval v
             WHERE v.account = k_ac_tit_tr
                OR v.reval_account = k_ac_tit_tr
                OR v.pnl_account = k_ac_tit_tr;
            print_kv('Ecritures de valorisation dans RVTB_ACC_REVAL', fnum(v_cnt));
        EXCEPTION
            WHEN OTHERS THEN po('    !! RVTB_ACC_REVAL inaccessible : ' || SQLERRM);
        END;
        SELECT COUNT(*) INTO v_cnt2
          FROM actb_history h
         WHERE h.module = k_mod
           AND h.ac_no = k_ac_tit_tr
           AND (h.event LIKE 'REV%' OR h.event LIKE '%VAL%' OR h.amount_tag LIKE '%REVAL%');
        print_kv('Ecritures de valorisation dans le module', fnum(v_cnt2));
        p_verdict('CLS-02', 'Absence de valorisation sur les titres classes en transaction',
                  CASE WHEN v_tot > 0 AND v_cnt + v_cnt2 = 0 THEN 1 ELSE 0 END,
                  1, NULL, 'ELEVE');

        -- -----------------------------------------------------
        p_test('CLS-03', 'Prime ou decote a l''achat des obligations');
        p_obj('si le montant debite au compte de titres a la mise en place differe du');
        po('             nominal du contrat, l''obligation a ete achetee au-dessus ou au-dessous');
        po('             du pair. La difference est une prime ou une decote a amortir sur la');
        po('             duree, et non a laisser en l''etat.');
        SELECT COUNT(*), NVL(SUM(ABS(ecart)), 0) INTO v_cnt, v_mt
          FROM (SELECT m.contract_ref_no,
                       NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                       ELSE -NVL(h.lcy_amount, 0) END)
                              FROM actb_history h
                             WHERE h.trn_ref_no = m.contract_ref_no
                               AND h.module = k_mod
                               AND h.amount_tag = 'PRINCIPAL'
                               AND h.ac_no = k_ac_tit_otap), 0) - NVL(m.lcy_amount, 0) ecart
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                   AND INSTR(',' || k_prod_oblig || ',', ',' || TRIM(m.product) || ',') > 0
                   AND EXISTS (SELECT 1 FROM actb_history h
                                WHERE h.trn_ref_no = m.contract_ref_no
                                  AND h.module = k_mod
                                  AND h.amount_tag = 'PRINCIPAL'))
         WHERE ABS(ecart) > k_tol_abs;
        p_verdict('CLS-03', 'Obligation achetee hors du pair, prime ou decote a amortir',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        IF v_cnt > 0 THEN
            tbl_line('4,24,8,12,12,24,26,24');
            po('  |' || fpad('N#', 4) || '|' || fpad('CONTRAT', 24) || '|' || fpad('PROD', 8) || '|'
                || fpad('BOOKING', 12) || '|' || fpad('ECHEANCE', 12) || '|' || fpadl('NOMINAL', 24) || '|'
                || fpadl('DEBIT AU COMPTE TITRES', 26) || '|' || fpadl('PRIME OU DECOTE', 24) || '|');
            tbl_line('4,24,8,12,12,24,26,24');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no ref, m.product, m.booking_date bd,
                               m.maturity_date md, NVL(m.lcy_amount, 0) nom,
                               NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                               ELSE -NVL(h.lcy_amount, 0) END)
                                      FROM actb_history h
                                     WHERE h.trn_ref_no = m.contract_ref_no
                                       AND h.module = k_mod
                                       AND h.amount_tag = 'PRINCIPAL'
                                       AND h.ac_no = k_ac_tit_otap), 0) cpt
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND INSTR(',' || k_prod_oblig || ',', ',' || TRIM(m.product) || ',') > 0
                           AND EXISTS (SELECT 1 FROM actb_history h
                                        WHERE h.trn_ref_no = m.contract_ref_no
                                          AND h.module = k_mod
                                          AND h.amount_tag = 'PRINCIPAL')
                           AND ABS(NVL((SELECT SUM(CASE h.drcr_ind WHEN 'D' THEN NVL(h.lcy_amount, 0)
                                                                   ELSE -NVL(h.lcy_amount, 0) END)
                                          FROM actb_history h
                                         WHERE h.trn_ref_no = m.contract_ref_no
                                           AND h.module = k_mod
                                           AND h.amount_tag = 'PRINCIPAL'
                                           AND h.ac_no = k_ac_tit_otap), 0)
                                    - NVL(m.lcy_amount, 0)) > k_tol_abs
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ref, 24) || '|'
                    || fpad(r.product, 8) || '|' || fpad(fdt(r.bd), 12) || '|' || fpad(fdt(r.md), 12) || '|'
                    || fpadl(famt(r.nom), 24) || '|' || fpadl(famt(r.cpt), 26) || '|'
                    || fpadl(famt(r.cpt - r.nom), 24) || '|');
            END LOOP;
            tbl_line('4,24,8,12,12,24,26,24');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 26. STA : DONNEES STATIQUES ET LIMITES
    -- =========================================================
    print_section('26. CONTROLES STA : DONNEES STATIQUES ET LIMITES');
    BEGIN
        po('  Les erreurs de saisie du contrat se propagent a tout ce qui suit :');
        po('  interets, provisions, echeancier, comptabilite. Elles se detectent en');
        po('  amont, sur le contrat lui-meme, avant toute ecriture.');

        -- -----------------------------------------------------
        p_test('STA-01', 'Coherence des dates : booking, valeur, echeance');
        p_obj('la chaine BOOKING_DATE inferieure ou egale a VALUE_DATE, elle-meme');
        po('             inferieure a MATURITY_DATE, doit toujours tenir. Une duree nulle ou');
        po('             negative rend le calcul d''interets impossible.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND (m.maturity_date <= m.value_date
                OR TRUNC(m.booking_date) - TRUNC(m.value_date) > k_retro_j
                OR m.value_date IS NULL
                OR m.maturity_date IS NULL
                OR m.booking_date IS NULL);
        p_verdict('STA-01', 'Chaine de dates incoherente ou duree nulle',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            d_head('INCOHERENCE');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.contract_ref_no, m.product, m.counterparty,
                               (SELECT MAX(c.customer_name1) FROM sttm_customer c
                                 WHERE c.customer_no = m.counterparty) nom,
                               m.lcy_amount, m.main_comp_rate, m.booking_date,
                               m.value_date, m.maturity_date,
                               CASE WHEN m.value_date IS NULL THEN 'VALEUR ABSENTE'
                                    WHEN m.maturity_date IS NULL THEN 'ECHEANCE ABSENTE'
                                    WHEN m.booking_date IS NULL THEN 'BOOKING ABSENT'
                                    WHEN m.maturity_date <= m.value_date THEN 'DUREE NULLE OU NEGATIVE'
                                    ELSE 'BOOKING APRES VALEUR' END motif
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                           AND (m.maturity_date <= m.value_date
                                OR TRUNC(m.booking_date) - TRUNC(m.value_date) > k_retro_j
                                OR m.value_date IS NULL
                                OR m.maturity_date IS NULL
                                OR m.booking_date IS NULL)
                         ORDER BY m.lcy_amount DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                d_row(v_row, r.contract_ref_no, r.product, r.counterparty, r.nom,
                      r.lcy_amount, r.main_comp_rate, r.booking_date, r.value_date,
                      r.maturity_date, r.motif);
            END LOOP;
            d_foot;
        END IF;

        -- -----------------------------------------------------
        p_test('STA-02', 'Aucune operation saisie deux fois sous deux references');
        p_obj('deux contrats portant le meme nominal, le meme taux, la meme date de');
        po('             valeur et la meme echeance sont soit une operation fractionnee');
        po('             volontairement, soit une double saisie. Chaque groupe doit etre');
        po('             justifie. Recoupe MM-101, qui utilise le meme faisceau d''indices.');
        SELECT COUNT(*), NVL(SUM(mt), 0) INTO v_cnt, v_mt
          FROM (SELECT COUNT(*) nb, SUM(m.lcy_amount) mt
                  FROM ldtb_contract_master m
                 WHERE m.module = k_mod
                   AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                   AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                        WHERE v.contract_ref_no = m.contract_ref_no)
                 GROUP BY m.counterparty, m.product, m.lcy_amount,
                          NVL(m.main_comp_rate, -1), m.value_date, m.maturity_date
                HAVING COUNT(*) > 1);
        p_verdict('STA-02', 'Groupe de contrats identiques sur nominal, taux et dates',
                  v_cnt, v_nb_ctr, v_mt, 'ELEVE');
        IF v_cnt > 0 THEN
            tbl_line('4,14,10,24,10,12,12,10,24,44');
            po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 14) || '|' || fpad('PROD', 10) || '|'
                || fpadl('NOMINAL', 24) || '|' || fpadl('TAUX', 10) || '|' || fpad('VALEUR', 12) || '|'
                || fpad('ECHEANCE', 12) || '|' || fpadl('NB', 10) || '|' || fpadl('MONTANT CUMULE', 24) || '|'
                || fpad('REFERENCES', 44) || '|');
            tbl_line('4,14,10,24,10,12,12,10,24,44');
            v_row := 0;
            FOR r IN (SELECT * FROM (
                        SELECT m.counterparty cif, m.product, m.lcy_amount nom,
                               m.main_comp_rate tx, m.value_date vd, m.maturity_date md,
                               COUNT(*) nb, SUM(m.lcy_amount) mt,
                               MIN(m.contract_ref_no) || '  ...  '
                                 || MAX(m.contract_ref_no) refs
                          FROM ldtb_contract_master m
                         WHERE m.module = k_mod
                           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                                WHERE v.contract_ref_no = m.contract_ref_no)
                         GROUP BY m.counterparty, m.product, m.lcy_amount,
                                  m.main_comp_rate, m.value_date, m.maturity_date
                        HAVING COUNT(*) > 1
                         ORDER BY SUM(m.lcy_amount) DESC
                      ) WHERE ROWNUM <= k_top) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cif, 14) || '|'
                    || fpad(r.product, 10) || '|' || fpadl(famt(r.nom), 24) || '|'
                    || fpadl(ftx(r.tx), 10) || '|' || fpad(fdt(r.vd), 12) || '|'
                    || fpad(fdt(r.md), 12) || '|' || fpadl(fnum(r.nb), 10) || '|'
                    || fpadl(famt(r.mt), 24) || '|' || fpad(r.refs, 44) || '|');
            END LOOP;
            tbl_line('4,14,10,24,10,12,12,10,24,44');
        END IF;

        -- -----------------------------------------------------
        p_test('STA-03', 'Taux et montants captures avec la bonne unite');
        p_obj('MAIN_COMP_RATE doit etre stocke en pourcentage (6.25) et non en decimal');
        po('             (0.0625). Un taux inferieur a ' || ftx(k_taux_dec) || ' sur un portefeuille');
        po('             souverain est le symptome d''une saisie en decimal, qui diviserait les');
        po('             interets par cent. Les montants doivent etre en unites de XAF.');
        SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) INTO v_cnt, v_mt
          FROM ldtb_contract_master m
         WHERE m.module = k_mod
           AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
           AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                WHERE v.contract_ref_no = m.contract_ref_no)
           AND NVL(m.main_comp_rate, 0) > 0
           AND m.main_comp_rate < k_taux_dec;
        p_verdict('STA-03', 'Taux vraisemblablement saisi en decimal et non en pourcentage',
                  v_cnt, v_nb_ctr, v_mt, 'MOYEN');
        print_sub('STA-03 a. Convention de saisie du taux sur le portefeuille');
        tbl_line('4,40,16,14,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PLAGE DE TAUX', 40) || '|' || fpadl('NB CONTRATS', 16) || '|'
            || fpadl('% NB', 14) || '|' || fpadl('TAUX MIN', 16) || '|' || fpadl('TAUX MAX', 16) || '|');
        tbl_line('4,40,16,14,16,16');
        v_row := 0;
        FOR r IN (SELECT tr, COUNT(*) nb, MIN(tx) tmin, MAX(tx) tmax FROM (
                    SELECT m.main_comp_rate tx,
                           CASE WHEN m.main_comp_rate IS NULL THEN '4. taux non renseigne'
                                WHEN m.main_comp_rate = 0 THEN '3. taux nul'
                                WHEN m.main_comp_rate < k_taux_dec THEN '1. inferieur a 1, saisie decimale probable'
                                ELSE '2. superieur ou egal a 1, saisie en pourcentage' END tr
                      FROM ldtb_contract_master m
                     WHERE m.module = k_mod
                       AND m.booking_date BETWEEN k_dt_deb AND k_dt_fin
                       AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                            WHERE v.contract_ref_no = m.contract_ref_no))
                   GROUP BY tr ORDER BY tr) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 40) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fpct(r.nb, v_nb_ctr), 14) || '|'
                || fpadl(ftx(r.tmin), 16) || '|' || fpadl(ftx(r.tmax), 16) || '|');
        END LOOP;
        tbl_line('4,40,16,14,16,16');

        -- -----------------------------------------------------
        p_test('STA-04', 'La concentration par emetteur reste dans les limites');
        p_obj('encours vivant par emetteur souverain, confronte a la limite fixee par');
        po('             le comite ALM (' || fmio(k_conc_lim) || '). Cette limite est un parametre du');
        po('             script : elle doit etre alignee sur la decision du comite avant');
        po('             conclusion.');
        tbl_line('4,14,34,16,26,26,16,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 14) || '|' || fpad('EMETTEUR', 34) || '|'
            || fpadl('NB CONTRATS', 16) || '|' || fpadl('ENCOURS VIVANT', 26) || '|'
            || fpadl('LIMITE ALM', 26) || '|' || fpadl('UTILISATION', 16) || '|'
            || fpadl('VERDICT', 14) || '|');
        tbl_line('4,14,34,16,26,26,16,14');
        v_row := 0;
        v_cnt := 0;
        v_mt  := 0;
        FOR r IN (SELECT m.counterparty cif,
                         MAX((SELECT MAX(c.customer_name1) FROM sttm_customer c
                               WHERE c.customer_no = m.counterparty)) nom,
                         COUNT(*) nb, SUM(m.lcy_amount) mt
                    FROM ldtb_contract_master m
                   WHERE m.module = k_mod
                     AND m.version_no = (SELECT MAX(v.version_no) FROM ldtb_contract_master v
                                          WHERE v.contract_ref_no = m.contract_ref_no)
                     AND m.maturity_date > k_arrete
                   GROUP BY m.counterparty
                   ORDER BY SUM(m.lcy_amount) DESC) LOOP
            v_row := v_row + 1;
            IF r.mt > k_conc_lim THEN
                v_cnt := v_cnt + 1;
                v_mt  := v_mt + (r.mt - k_conc_lim);
            END IF;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cif, 14) || '|' || fpad(r.nom, 34) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 26) || '|'
                || fpadl(fmio(k_conc_lim), 26) || '|' || fpadl(fpct(r.mt, k_conc_lim), 16) || '|'
                || fpadl(CASE WHEN r.mt > k_conc_lim THEN 'DEPASSEE' ELSE 'OK' END, 14) || '|');
        END LOOP;
        tbl_line('4,14,34,16,26,26,16,14');
        p_verdict('STA-04', 'Emetteur dont l''encours vivant depasse la limite ALM',
                  v_cnt, v_row, v_mt, 'ELEVE');

        -- -----------------------------------------------------
        p_test('STA-05', 'La nature d''une ecriture se lit sur AMOUNT_TAG');
        p_obj('un etat de controle ne doit jamais identifier la nature d''une ecriture');
        po('             par un libelle. Dans ACTB_HISTORY il n''existe d''ailleurs aucune');
        po('             colonne de libelle : la nature se lit sur AMOUNT_TAG, qui doit donc');
        po('             etre renseigne sur toutes les lignes. Le test mesure ce taux et liste');
        po('             les tags reellement utilises.');
        SELECT COUNT(*), SUM(CASE WHEN TRIM(h.amount_tag) IS NULL THEN 1 ELSE 0 END),
               COUNT(DISTINCT h.amount_tag)
          INTO v_tot, v_cnt, v_cnt2
          FROM actb_history h WHERE h.module = k_mod;
        print_kv('Ecritures du module',                 fnum(v_tot));
        print_kv('Dont sans tag de montant',            fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
        print_kv('Tags de montant distincts utilises',  fnum(v_cnt2));
        po('     Le present script indexe tous ses controles comptables sur');
        po('     AMOUNT_TAG et sur AC_NO, jamais sur un libelle.');
        p_verdict('STA-05', 'Ecriture sans tag de montant, donc non qualifiable',
                  v_cnt, v_tot, NULL, 'FAIBLE');
        tbl_line('4,22,16,16,26,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('TAG DE MONTANT', 22) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('NB CONTRATS', 16) || '|' || fpadl('MONTANT LCY', 26) || '|'
            || fpad('1ERE ECRITURE', 16) || '|' || fpad('DERNIERE', 16) || '|');
        tbl_line('4,22,16,16,26,16,16');
        v_row := 0;
        FOR r IN (SELECT h.amount_tag, COUNT(*) nb, COUNT(DISTINCT h.trn_ref_no) nbc,
                         SUM(NVL(h.lcy_amount, 0)) mt, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                    FROM actb_history h
                   WHERE h.module = k_mod
                   GROUP BY h.amount_tag
                   ORDER BY COUNT(*) DESC) LOOP
            v_row := v_row + 1;
            EXIT WHEN v_row > k_top;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.amount_tag, 22) || '|'
                || fpadl(fnum(r.nb), 16) || '|' || fpadl(fnum(r.nbc), 16) || '|'
                || fpadl(fmio(r.mt), 26) || '|' || fpad(fdt(r.d1), 16) || '|'
                || fpad(fdt(r.d2), 16) || '|');
        END LOOP;
        tbl_line('4,22,16,16,26,16,16');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- ########################################################################
    print_part('PARTIE 8 : SYNTHESE DE LA REVUE');
    -- ########################################################################

    -- =========================================================
    -- 16. SYNTHESE
    -- =========================================================
    print_section('27. SYNTHESE DE TOUS LES TESTS');
    BEGIN
        po('  Recapitulatif de l''ensemble des controles executes, dans l''ordre du');
        po('  rapport. La colonne CAS donne le nombre d''occurrences relevees, la colonne');
        po('  MONTANT l''enjeu financier associe lorsqu''il est chiffrable.');
        po('');

        tbl_line('4,10,62,12,12,10,20,12,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('CODE', 10) || '|' || fpad('CONTROLE', 62) || '|'
            || fpadl('CAS', 12) || '|' || fpadl('BASE', 12) || '|' || fpadl('%', 10) || '|'
            || fpadl('MONTANT', 20) || '|' || fpad('CRITICITE', 12) || '|' || fpadl('VERDICT', 14) || '|');
        tbl_line('4,10,62,12,12,10,20,12,14');
        FOR i IN 1 .. g_n LOOP
            po('  |' || fpadl(TO_CHAR(i), 4) || '|' || fpad(g_res(i).code, 10) || '|'
                || fpad(g_res(i).lib, 62) || '|' || fpadl(fnum(g_res(i).nb), 12) || '|'
                || fpadl(CASE WHEN g_res(i).base IS NULL THEN '-' ELSE fnum(g_res(i).base) END, 12) || '|'
                || fpadl(CASE WHEN g_res(i).base IS NULL OR g_res(i).base = 0 THEN '-'
                              ELSE fpct(g_res(i).nb, g_res(i).base) END, 10) || '|'
                || fpadl(CASE WHEN g_res(i).mt IS NULL THEN '-' ELSE fmio(g_res(i).mt) END, 20) || '|'
                || fpad(CASE WHEN g_res(i).nb = 0 THEN '-' ELSE g_res(i).crit END, 12) || '|'
                || fpadl(CASE WHEN g_res(i).nb = 0 THEN 'OK'
                              WHEN g_res(i).crit = 'INFO' THEN 'INFORMATION'
                              ELSE 'ANOMALIE' END, 14) || '|');
        END LOOP;
        tbl_line('4,10,62,12,12,10,20,12,14');

        print_sub('27.1 Comptage general');
        print_kv('Nombre de controles executes',            fnum(g_n));
        print_kv('Controles sans anomalie',                 fnum(g_n - g_anom));
        print_kv('Controles ayant releve au moins un cas',  fnum(g_anom));
        print_kv('Dont criticite CRITIQUE ou ELEVEE',       fnum(g_crit));

        print_sub('27.2 Repartition des anomalies par criticite');
        tbl_line('4,20,14,14,20');
        po('  |' || fpad('N#', 4) || '|' || fpad('CRITICITE', 20) || '|' || fpadl('NB CONTROLES', 14) || '|'
            || fpadl('NB CAS', 14) || '|' || fpadl('MONTANT CUMULE', 20) || '|');
        tbl_line('4,20,14,14,20');
        v_row := 0;
        FOR c IN (SELECT 'CRITIQUE' lib, 1 ord FROM DUAL UNION ALL
                  SELECT 'ELEVE',        2 FROM DUAL UNION ALL
                  SELECT 'MOYEN',        3 FROM DUAL UNION ALL
                  SELECT 'FAIBLE',       4 FROM DUAL UNION ALL
                  SELECT 'INFO',         5 FROM DUAL
                  ORDER BY 2) LOOP
            v_cnt := 0; v_cnt2 := 0; v_mt := 0;
            FOR i IN 1 .. g_n LOOP
                IF g_res(i).crit = c.lib AND g_res(i).nb > 0 THEN
                    v_cnt  := v_cnt + 1;
                    v_cnt2 := v_cnt2 + g_res(i).nb;
                    v_mt   := v_mt + NVL(g_res(i).mt, 0);
                END IF;
            END LOOP;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(c.lib, 20) || '|' || fpadl(fnum(v_cnt), 14) || '|'
                || fpadl(fnum(v_cnt2), 14) || '|' || fpadl(fmio(v_mt), 20) || '|');
        END LOOP;
        tbl_line('4,20,14,14,20');

        print_sub('27.3 Les dix constats a enjeu financier le plus eleve');
        tbl_line('4,10,62,12,20,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('CODE', 10) || '|' || fpad('CONTROLE', 62) || '|'
            || fpadl('CAS', 12) || '|' || fpadl('MONTANT', 20) || '|' || fpad('CRITICITE', 12) || '|');
        tbl_line('4,10,62,12,20,12');
        DECLARE
            v_used  VARCHAR2(4000) := ',';
            v_best  PLS_INTEGER;
            v_bestv NUMBER;
        BEGIN
            FOR n IN 1 .. 10 LOOP
                v_best  := 0;
                v_bestv := -1;
                FOR i IN 1 .. g_n LOOP
                    IF g_res(i).nb > 0
                       AND g_res(i).crit <> 'INFO'
                       AND NVL(g_res(i).mt, 0) > v_bestv
                       AND INSTR(v_used, ',' || TO_CHAR(i) || ',') = 0 THEN
                        v_best  := i;
                        v_bestv := NVL(g_res(i).mt, 0);
                    END IF;
                END LOOP;
                EXIT WHEN v_best = 0 OR v_bestv <= 0;
                v_used := v_used || TO_CHAR(v_best) || ',';
                po('  |' || fpadl(TO_CHAR(n), 4) || '|' || fpad(g_res(v_best).code, 10) || '|'
                    || fpad(g_res(v_best).lib, 62) || '|' || fpadl(fnum(g_res(v_best).nb), 12) || '|'
                    || fpadl(fmio(g_res(v_best).mt), 20) || '|' || fpad(g_res(v_best).crit, 12) || '|');
            END LOOP;
        END;
        tbl_line('4,10,62,12,20,12');

        print_sub('27.4 Rappel du perimetre revu');
        print_kv('Module audite',                     k_mod);
        print_kv('Periode auditee',                   fdt(k_dt_deb) || ' au ' || fdt(k_dt_fin));
        print_kv('Date d''arrete des controles',      fdt(k_arrete));
        print_kv('Contrats retenus',                  fnum(v_nb_ctr));
        print_kv('Encours nominal cumule',            famt(v_mt_ctr) || '  (' || fmio(v_mt_ctr) || ')');

        print_sub('27.5 Limites de la revue');
        po('  1. Les controles portent exclusivement sur les donnees enregistrees dans');
        po('     FLEXCUBE. Ils ne remplacent pas la verification sur piece des dossiers');
        po('     de souscription, des confirmations de contrepartie et des releves de titres.');
        po('  2. La convention de calcul des interets retenue au test MM-301 est deduite');
        po('     de la colonne ICCF_CALC_METHOD. Le tableau MM-301 a indique la convention');
        po('     qui reconcilie reellement les montants ; toute divergence doit etre');
        po('     confirmee aupres du parametrage produit avant conclusion.');
        po('  3. Les operations sont rattachees a leur derniere version de contrat. Les');
        po('     versions anterieures sont recensees au test MM-706 mais ne sont pas');
        po('     rejouees ligne a ligne.');
        po('  4. L''estimation des interets courus non provisionnes (test MM-316) est');
        po('     un ordre de grandeur calcule en base ' || TO_CHAR(k_base_jours) || ' jours. Elle ne se substitue pas');
        po('     au recalcul actuariel contractuel.');
        po('  5. La piste d''audit des contrats repose sur les ecritures comptables :');
        po('     LDTB_CONTRACT_MASTER ne conserve ni le saisisseur ni le validateur du');
        po('     contrat lui-meme.');
        po('  6. Douze controles candidats ont ete volontairement ecartes du decompte');
        po('     des tests, et quatre autres recalibres, parce qu''ils ne discriminaient');
        po('     rien sur ce portefeuille. La section 0.7 en donne la liste et le motif ;');
        po('     l''information correspondante reste imprimee sous forme descriptive.');
        po('  7. Huit controles de la partie 7 ne peuvent etre clos sans une piece');
        po('     exterieure a la base : releve de compte BEAC (CSH-01 a CSH-03),');
        po('     balance generale et etat de position titres (CUT-02 a CUT-05),');
        po('     politique comptable de valorisation (CLS-02). Le script en execute la');
        po('     part verifiable et imprime le terme a rapprocher ; la section 0.8 les');
        po('     recense. Tant que ces pieces ne sont pas obtenues, aucun de ces huit');
        po('     controles ne peut etre declare satisfait.');
        po('  8. La limite de concentration par emetteur utilisee au test STA-04 est un');
        po('     parametre du script (' || fmio(k_conc_lim) || '). Elle doit etre alignee sur la');
        po('     decision du comite ALM avant toute conclusion sur ce test.');

    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po('');
    po(v_sep);
    po('>>> REVUE TERMINEE - ' || fdth(SYSDATE));
    po('    ' || fnum(g_n) || ' controles executes, ' || fnum(g_anom) || ' avec anomalie, '
        || fnum(g_crit) || ' de criticite CRITIQUE ou ELEVEE.');
    po(v_sep);

EXCEPTION
    WHEN OTHERS THEN
        po('');
        po('!! ERREUR GENERALE : ' || SQLERRM);
        po('   ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/

-- SPOOL OFF
