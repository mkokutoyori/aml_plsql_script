-- ============================================================================
-- SCRIPT D'EXPLORATION - OPERATIONS DE CHANGE (FX)
-- Base : FLEXCUBE (FCUBS)
-- ============================================================================
-- OBJET
--   Ce script n'effectue AUCUN test de conformite. Il decrit la facon dont les
--   operations de change sont encodees dans la base, afin de pouvoir ensuite
--   rediger un script d'audit cible au regard du Reglement CEMAC n 02/18/
--   CEMAC/UMAC/CM du 21 decembre 2018 portant reglementation des changes.
--
--   Il est le pendant, pour le change, de explore_mm_operations.sql.
--
-- POURQUOI UNE EXPLORATION AVANT L'AUDIT
--   Le rapport d'exploration du marche monetaire a montre que le module FX
--   (Foreign Exchange) et le module FS (FX Settlements) sont declares installes
--   dans SMTB_MODULES, mais qu'AUCUNE ecriture d'ACTB_HISTORY ne porte le code
--   module FX ou FS. L'activite de change de la banque ne transite donc pas par
--   le module de deal FX. Ce script a pour premier objectif de determiner OU
--   elle est reellement enregistree, avant d'ecrire le moindre test.
--
--   Les gisements explores sont, dans l'ordre :
--     1. les tables du module FX / FS si elles existent et sont alimentees ;
--     2. le referentiel des cours (CYTB_RATES_HISTORY, CYTB_DERIVED_RATES_HISTORY) ;
--     3. les ecritures comptables en devises (ACTB_HISTORY, colonnes AC_CCY,
--        FCY_AMOUNT, EXCH_RATE, LCY_AMOUNT) ;
--     4. la reevaluation de change (RVTB_ACC_REVAL) ;
--     5. les soldes en devises (GLTB_GL_BAL.CCY_CODE, ACTB_ACCBAL_HISTORY.ACC_CCY,
--        STTM_CUST_ACCOUNT.CCY, STTB_ACCOUNT.AC_GL_CCY) ;
--     6. les comptes de correspondants (nostro / vostro) candidats ;
--     7. les transferts internationaux (module de transfert de fonds, messagerie
--        SWIFT, flux entrants et sortants), inclus dans le perimetre a la
--        demande du commanditaire.
--
-- CADRE REGLEMENTAIRE VISE (rappele en section 22)
--   Reglement n 02/18/CEMAC/UMAC/CM du 21/12/2018, en vigueur le 01/03/2019,
--   complete par les instructions du Gouverneur de la BEAC du 10 juin 2019.
--   Le script prepare le terrain pour les controles portant notamment sur :
--     - le cours applique et la parite officielle ;
--     - les seuils de justification et de domiciliation ;
--     - la detention d'avoirs en devises chez les correspondants ;
--     - les comptes en devises des residents et non-residents ;
--     - la position de change et son suivi.
--
-- LECTURE SEULE
--   Le script ne contient que des SELECT. Aucun INSERT, UPDATE, DELETE, aucun
--   ordre DDL, aucun COMMIT : il s'execute avec un simple droit de lecture.
--   Il interroge en plus les vues du dictionnaire Oracle ALL_TABLES et
--   ALL_TAB_COLUMNS, accessibles a tout utilisateur.
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
--   3. Lancer avec  F5  (Executer un script) et NON avec Ctrl+Entree :
--      Ctrl+Entree n'execute qu'une instruction et ignore les commandes SET.
--   4. Le rapport s'affiche dans l'onglet "Sortie de script".
--      Pour l'enregistrer dans un fichier, decommenter les lignes SPOOL.
--
-- UTILISATION SOUS SQLPLUS
--   sqlplus utilisateur/motdepasse@base
--   SQL> spool exploration_fx_report.txt
--   SQL> @explore_fx_operations.sql
--   SQL> spool off
--
-- PLAN DU RAPPORT
--   Partie 1 - sections  1 a  5 : contexte, decouverte du perimetre de change
--   Partie 2 - sections  6 a 10 : referentiel des devises et des cours
--   Partie 3 - sections 11 a 16 : empreinte du change dans la comptabilite
--   Partie 4 - sections 17 a 21 : comptes, clients et position de change
--   Partie 5 - sections 22 a 27 : les transferts internationaux
--   Partie 6 - sections 28 a 29 : cadre CEMAC et controles candidats
--
-- DUREE
--   Les parties 3, 4 et 5 lisent integralement ACTB_HISTORY (plusieurs millions
--   de lignes) : prevoir plusieurs minutes d'execution. La partie 5 en fait
--   plusieurs lectures filtrees sur le module de transfert.
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

-- SPOOL C:\temp\exploration_fx_report.txt

DECLARE
    -- ---------- Variables de travail ----------
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_row     NUMBER;
    v_dim     VARCHAR2(60);
    v_mt      NUMBER;
    v_d1      DATE;
    v_d2      DATE;

    -- Devise de tenue de compte (monnaie locale). Elle est verifiee en
    -- section 1 : le script affiche la devise la plus frequente des ecritures
    -- pour confirmer que la valeur ci-dessous est la bonne.
    k_lcy     VARCHAR2(3)  := 'XAF';

    -- Parite fixe de rattachement du franc CFA a l'euro (1 EUR = 655,957 XAF).
    -- Sert de repere pour lire les cours EUR de la section 9.
    k_par_eur NUMBER       := 655.957;
    k_ccy_eur VARCHAR2(3)  := 'EUR';

    -- Seuils de la reglementation des changes CEMAC, en monnaie locale.
    -- Ils ne servent ici qu'a DIMENSIONNER les futurs tests (section 23).
    k_s_justif NUMBER := 5000000;    -- seuil de justification / domiciliation
    k_s_carte  NUMBER := 1000000;    -- plafond mensuel des paiements a distance
    k_j_rapat  NUMBER := 150;        -- delai de rapatriement des recettes d'export

    -- Module portant les transferts de fonds. La section 23 affiche la
    -- repartition de toutes les ecritures par module : si les transferts
    -- internationaux de cette banque sont ailleurs, corriger cette constante.
    k_mod_ft   VARCHAR2(4) := 'FT';
    -- Largeur de la bande examinee sous le seuil de justification, pour
    -- detecter un eventuel fractionnement des operations.
    k_bande    NUMBER := 0.20;       -- 20 pourcent sous le seuil

    -- ---------- Helpers d'affichage ----------
    PROCEDURE po(t VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(t);
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
        po('  ' || RPAD(SUBSTR(l, 1, 66), 68, '.') || ' ' || NVL(v, 'NULL / NON RENSEIGNE'));
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

    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G999G990D00') || ' M';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
    END;

    -- Horodatage SANS deux-points : sous SQL Developer, un deux-points suivi
    -- de MI serait pris pour une variable de liaison et ouvrirait une fenetre
    -- de saisie au lancement du script.
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

    -- ---------- Helpers dynamiques (tolerants aux objets absents) ----------
    -- Compte les lignes d'une table ; renvoie -1 si la table est absente/inaccessible
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

    FUNCTION f_lbl(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN x < 0 THEN '>>> OBJET ABSENT OU INACCESSIBLE' ELSE fnum(x) || ' lignes' END;
    END;

    -- Meme chose, sans le suffixe : pour les colonnes "nombre de cas"
    FUNCTION f_cas(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN CASE WHEN x < 0 THEN 'OBJET ABSENT' ELSE fnum(x) END;
    END;

    -- Distribution des valeurs d'une colonne (ou d'une expression) d'une table.
    -- p_order : 'K' = tri par effectif decroissant, 'V' = tri par valeur croissante
    PROCEDURE show_dist(p_label VARCHAR2,
                        p_tab   VARCHAR2,
                        p_col   VARCHAR2,
                        p_where VARCHAR2 DEFAULT NULL,
                        p_top   NUMBER   DEFAULT 25,
                        p_order VARCHAR2 DEFAULT 'K') IS
        TYPE t_cur IS REF CURSOR;
        c    t_cur;
        v_v  VARCHAR2(200);
        v_k  NUMBER;
        v_j  NUMBER := 0;
        v_s  VARCHAR2(4000);
    BEGIN
        print_sub(p_label);
        v_s := 'SELECT * FROM (SELECT NVL(TRIM(SUBSTR(TO_CHAR(' || p_col || '), 1, 60)), ''(vide / NULL)'') v,'
            || ' COUNT(*) k FROM ' || p_tab
            || CASE WHEN p_where IS NOT NULL THEN ' WHERE ' || p_where END
            || ' GROUP BY ' || p_col
            || CASE WHEN p_order = 'V' THEN ' ORDER BY 1' ELSE ' ORDER BY COUNT(*) DESC' END
            || ') WHERE ROWNUM <= ' || p_top;
        OPEN c FOR v_s;
        LOOP
            FETCH c INTO v_v, v_k;
            EXIT WHEN c%NOTFOUND;
            v_j := v_j + 1;
            print_kv('  ' || v_v, fnum(v_k));
        END LOOP;
        CLOSE c;
        IF v_j = 0 THEN
            po('    (aucune ligne dans le perimetre)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF c%ISOPEN THEN
                CLOSE c;
            END IF;
            po('    !! ERREUR : ' || SQLERRM);
    END;

    -- Profil colonne par colonne d'une table (taux de remplissage, cardinalite,
    -- min/max et valeurs les plus frequentes) sur un perimetre donne.
    -- C'est le coeur de l'exploration : il montre ce qui est REELLEMENT alimente.
    PROCEDURE profile_table(p_tab   VARCHAR2,
                            p_where VARCHAR2 DEFAULT NULL,
                            p_title VARCHAR2 DEFAULT NULL) IS
        v_w    VARCHAR2(2000) := CASE WHEN p_where IS NOT NULL THEN ' WHERE ' || p_where END;
        v_lig  NUMBER;
        v_nn   NUMBER;
        v_di   NUMBER;
        v_mn   VARCHAR2(200);
        v_mx   VARCHAR2(200);
        v_top  VARCHAR2(500);
        v_expr VARCHAR2(500);
        v_mne  VARCHAR2(500);
        v_mxe  VARCHAR2(500);
        v_nbc  NUMBER := 0;
    BEGIN
        print_sub(NVL(p_title, 'PROFIL DES COLONNES : ' || p_tab
                  || CASE WHEN p_where IS NOT NULL THEN '  [' || p_where || ']' END));
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_tab || v_w INTO v_lig;
        EXCEPTION
            WHEN OTHERS THEN
                po('    !! table absente ou inaccessible : ' || SQLERRM);
                RETURN;
        END;
        po('    Lignes dans le perimetre : ' || fnum(v_lig));
        IF v_lig = 0 THEN
            po('    (perimetre vide : profil non calcule)');
            RETURN;
        END IF;

        tbl_line('32,14,12,11,20,20,40');
        po('  |' || fpad('COLONNE', 32) || '|' || fpad('TYPE', 14) || '|' || fpadl('REMPLI', 12) || '|'
            || fpadl('DISTINCT', 11) || '|' || fpad('MIN', 20) || '|' || fpad('MAX', 20) || '|'
            || fpad('VALEURS LES PLUS FREQUENTES', 40) || '|');
        tbl_line('32,14,12,11,20,20,40');

        FOR c IN (
            SELECT column_name, data_type
            FROM all_tab_columns
            WHERE table_name = UPPER(p_tab)
              AND column_name NOT LIKE 'SYS\_NC%' ESCAPE '\'
              AND data_type NOT IN ('CLOB','BLOB','NCLOB','LONG','RAW','LONG RAW','BFILE','XMLTYPE')
              AND owner = (SELECT owner FROM (
                              SELECT owner FROM all_tab_columns
                              WHERE table_name = UPPER(p_tab)
                              ORDER BY DECODE(owner, SYS_CONTEXT('USERENV','CURRENT_SCHEMA'), 0, 1), owner
                           ) WHERE ROWNUM = 1)
            ORDER BY column_id
        ) LOOP
            v_nbc := v_nbc + 1;
            IF c.data_type LIKE 'DATE%' OR c.data_type LIKE 'TIMESTAMP%' THEN
                v_expr := 'TO_CHAR(' || c.column_name || ', ''DD/MM/YYYY'')';
                v_mne  := 'TO_CHAR(MIN(' || c.column_name || '), ''DD/MM/YYYY'')';
                v_mxe  := 'TO_CHAR(MAX(' || c.column_name || '), ''DD/MM/YYYY'')';
            ELSIF c.data_type IN ('NUMBER','FLOAT','BINARY_FLOAT','BINARY_DOUBLE') THEN
                v_expr := 'TO_CHAR(' || c.column_name || ')';
                v_mne  := 'TO_CHAR(MIN(' || c.column_name || '))';
                v_mxe  := 'TO_CHAR(MAX(' || c.column_name || '))';
            ELSE
                v_expr := 'TO_CHAR(' || c.column_name || ')';
                v_mne  := 'SUBSTR(MIN(' || c.column_name || '), 1, 18)';
                v_mxe  := 'SUBSTR(MAX(' || c.column_name || '), 1, 18)';
            END IF;

            BEGIN
                EXECUTE IMMEDIATE 'SELECT COUNT(' || c.column_name || '), COUNT(DISTINCT ' || c.column_name
                    || '), ' || v_mne || ', ' || v_mxe || ' FROM ' || p_tab || v_w
                    INTO v_nn, v_di, v_mn, v_mx;
            EXCEPTION
                WHEN OTHERS THEN
                    v_nn := -1; v_di := -1; v_mn := NULL; v_mx := NULL;
            END;

            v_top := NULL;
            IF v_nn > 0 AND v_di BETWEEN 1 AND 500 THEN
                BEGIN
                    EXECUTE IMMEDIATE
                        'SELECT LISTAGG(v, '' | '') WITHIN GROUP (ORDER BY k DESC) FROM ('
                     || ' SELECT v, k FROM ('
                     || '   SELECT NVL(TRIM(SUBSTR(' || v_expr || ', 1, 16)), ''(vide)'') v, COUNT(*) k'
                     || '   FROM ' || p_tab || v_w
                     || '   GROUP BY ' || c.column_name
                     || '   ORDER BY COUNT(*) DESC) WHERE ROWNUM <= 3)'
                        INTO v_top;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_top := NULL;
                END;
            END IF;

            po('  |' || fpad(c.column_name, 32) || '|' || fpad(c.data_type, 14) || '|'
                || fpadl(CASE WHEN v_nn < 0 THEN 'ERR' ELSE fnum(v_nn) END, 12) || '|'
                || fpadl(CASE WHEN v_di < 0 THEN 'ERR' ELSE fnum(v_di) END, 11) || '|'
                || fpad(v_mn, 20) || '|' || fpad(v_mx, 20) || '|' || fpad(v_top, 40) || '|');
        END LOOP;
        tbl_line('32,14,12,11,20,20,40');
        IF v_nbc = 0 THEN
            po('    (aucune colonne trouvee dans ALL_TAB_COLUMNS pour ' || UPPER(p_tab) || ')');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('    !! ERREUR profil : ' || SQLERRM);
    END;

BEGIN

    po(v_sep);
    po('   PARTIE 1/6 : CONTEXTE ET DECOUVERTE DU PERIMETRE DE CHANGE');
    po(v_sep);

    -- =========================================================
    -- 1. CONTEXTE D'EXECUTION
    -- =========================================================
    print_section('1. CONTEXTE D''EXECUTION');
    BEGIN
        print_kv('Date / heure du rapport',   fdth(SYSDATE));
        print_kv('Utilisateur connecte',      SYS_CONTEXT('USERENV', 'SESSION_USER'));
        print_kv('Schema courant',            SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
        print_kv('Base de donnees',           SYS_CONTEXT('USERENV', 'DB_NAME'));
        print_kv('Instance',                  SYS_CONTEXT('USERENV', 'INSTANCE_NAME'));
        print_kv('Devise locale presumee',    k_lcy || '  (verifiee en section 1.2)');
        print_kv('Parite de rattachement retenue',
                 '1 ' || k_ccy_eur || ' = ' || TO_CHAR(k_par_eur) || ' ' || k_lcy);

        print_sub('1.1 Agences (FBTM_BRANCH)');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT branch_code, branch_name FROM fbtm_branch ORDER BY branch_code) LOOP
                v_row := v_row + 1;
                print_kv('  Agence ' || r.branch_code, r.branch_name);
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        IF v_row = 0 THEN
            po('    (table FBTM_BRANCH vide ou absente)');
        END IF;

        print_sub('1.2 Confirmation de la devise locale');
        po('  En comptabilite FLEXCUBE, une ecriture en monnaie locale porte un cours');
        po('  de change egal a 1 et un montant en devise egal au montant en local.');
        po('  La devise la plus frequente dans ce cas est la monnaie de tenue de compte.');
        po('');
        tbl_line('4,10,18,22,22,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB ECRITURES', 18) || '|'
            || fpadl('DONT COURS = 1', 22) || '|' || fpadl('DONT FCY = LCY', 22) || '|'
            || fpadl('% DU TOTAL', 14) || '|');
        tbl_line('4,10,18,22,22,14');
        v_row := 0;
        BEGIN
            SELECT COUNT(*) INTO v_tot FROM actb_history;
            FOR r IN (SELECT * FROM (
                        SELECT h.ac_ccy ccy, COUNT(*) nb,
                               SUM(CASE WHEN NVL(h.exch_rate, 1) = 1 THEN 1 ELSE 0 END) nb1,
                               SUM(CASE WHEN NVL(h.fcy_amount, 0) = NVL(h.lcy_amount, 0)
                                        THEN 1 ELSE 0 END) nbe
                          FROM actb_history h
                         GROUP BY h.ac_ccy
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 10) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nb1), 22) || '|'
                    || fpadl(fnum(r.nbe), 22) || '|' || fpadl(fpct(r.nb, v_tot), 14) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,18,22,22,14');
        po('  Si la premiere ligne n''est pas ' || k_lcy || ', corriger la constante k_lcy');
        po('  en tete du script avant toute exploitation du rapport.');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 2. MODULES FLEXCUBE LIES AU CHANGE
    -- =========================================================
    print_section('2. MODULES FLEXCUBE LIES AU CHANGE (SMTB_MODULES)');
    BEGIN
        po('  Objectif : verifier quels modules de change sont declares installes,');
        po('  avant de constater en section 5 lesquels sont reellement alimentes.');
        po('  FX = Foreign Exchange (deals de change), FS = FX Settlements,');
        po('  CY = referentiel des devises, DV = Derivatives, RE = Revaluation.');
        po('');
        BEGIN
            tbl_line('4,10,50,12,12,12');
            po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpad('LIBELLE', 50) || '|'
                || fpad('INSTALLE', 12) || '|' || fpad('RECORD_STAT', 12) || '|' || fpad('AUTH_STAT', 12) || '|');
            tbl_line('4,10,50,12,12,12');
            v_row := 0;
            FOR r IN (SELECT module_id, module_desc, installed, record_stat, auth_stat
                        FROM smtb_modules
                       WHERE module_id IN ('FX', 'FS', 'CY', 'DV', 'RE', 'FT', 'MM', 'LC', 'BC', 'DE')
                          OR UPPER(module_desc) LIKE '%EXCHANGE%'
                          OR UPPER(module_desc) LIKE '%CURRENC%'
                       ORDER BY module_id) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module_id, 10) || '|'
                    || fpad(r.module_desc, 50) || '|' || fpad(r.installed, 12) || '|'
                    || fpad(r.record_stat, 12) || '|' || fpad(r.auth_stat, 12) || '|');
            END LOOP;
            tbl_line('4,10,50,12,12,12');
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 3. DECOUVERTE DES OBJETS DE CHANGE DANS LE DICTIONNAIRE
    -- =========================================================
    print_section('3. DECOUVERTE DES OBJETS DE CHANGE (dictionnaire Oracle)');
    BEGIN
        po('  Le dictionnaire de donnees fourni pour ce dossier ne couvre pas le module');
        po('  FX. Cette section interroge donc directement ALL_TABLES pour recenser');
        po('  tout objet dont le nom evoque le change, la devise ou le cours.');

        print_sub('3.1 Tables par famille de prefixe liee au change');
        tbl_line('4,14,50,14,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('PREFIXE', 14) || '|' || fpad('FAMILLE', 50) || '|'
            || fpadl('NB TABLES', 14) || '|' || fpadl('LIGNES (STATS)', 18) || '|');
        tbl_line('4,14,50,14,18');
        v_row := 0;
        FOR p IN (
            SELECT 'FXT' pfx, 'Module Foreign Exchange (deals de change)' lib, 1 ord FROM DUAL UNION ALL
            SELECT 'FST',      'Module FX Settlements (reglement des deals)',    2 FROM DUAL UNION ALL
            SELECT 'CYT',      'Referentiel des devises et des cours',           3 FROM DUAL UNION ALL
            SELECT 'RVT',      'Reevaluation de change',                         4 FROM DUAL UNION ALL
            SELECT 'DVT',      'Produits derives',                               5 FROM DUAL UNION ALL
            SELECT 'ACT',      'Comptabilite',                                   6 FROM DUAL UNION ALL
            SELECT 'GLT',      'Grand livre',                                    7 FROM DUAL
            ORDER BY 3
        ) LOOP
            BEGIN
                SELECT COUNT(*), NVL(SUM(num_rows), 0) INTO v_cnt, v_tot
                  FROM all_tables
                 WHERE table_name LIKE p.pfx || '%'
                   AND owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
            EXCEPTION
                WHEN OTHERS THEN v_cnt := -1; v_tot := 0;
            END;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(p.pfx || '%', 14) || '|' || fpad(p.lib, 50) || '|'
                || fpadl(CASE WHEN v_cnt < 0 THEN 'ERR' ELSE fnum(v_cnt) END, 14) || '|'
                || fpadl(fnum(v_tot), 18) || '|');
        END LOOP;
        tbl_line('4,14,50,14,18');

        print_sub('3.2 Tables du module FX / FS porteuses de donnees (NUM_ROWS > 0)');
        tbl_line('4,42,18,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('TABLE', 42) || '|' || fpadl('LIGNES (STATS)', 18) || '|'
            || fpadl('DERNIERE ANALYSE', 18) || '|');
        tbl_line('4,42,18,18');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT table_name, num_rows, last_analyzed
                        FROM all_tables
                       WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                         AND (table_name LIKE 'FXT%' OR table_name LIKE 'FST%')
                         AND NVL(num_rows, 0) > 0
                       ORDER BY num_rows DESC) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.table_name, 42) || '|'
                    || fpadl(fnum(r.num_rows), 18) || '|' || fpadl(fdt(r.last_analyzed), 18) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,42,18,18');
        IF v_row = 0 THEN
            po('    >>> AUCUNE table FX / FS alimentee selon les statistiques.');
            po('        Le module de deal de change n''est pas utilise : l''activite de');
            po('        change doit etre cherchee dans la comptabilite (partie 3).');
        END IF;

        print_sub('3.3 Tables dont le nom evoque la devise, le cours ou le correspondant');
        tbl_line('4,42,18,42');
        po('  |' || fpad('N#', 4) || '|' || fpad('TABLE', 42) || '|' || fpadl('LIGNES (STATS)', 18) || '|'
            || fpad('MOTIF DE SELECTION', 42) || '|');
        tbl_line('4,42,18,42');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT table_name, num_rows,
                             CASE
                               WHEN table_name LIKE '%NOSTRO%' THEN 'compte de correspondant (nostro)'
                               WHEN table_name LIKE '%VOSTRO%' THEN 'compte de correspondant (vostro)'
                               WHEN table_name LIKE '%FOREX%' THEN 'change'
                               WHEN table_name LIKE '%EXCH%'  THEN 'change / cours'
                               WHEN table_name LIKE '%RATE%'  THEN 'cours ou taux'
                               WHEN table_name LIKE '%CCY%'   THEN 'devise'
                               WHEN table_name LIKE '%CURRENC%' THEN 'devise'
                               WHEN table_name LIKE '%REVAL%' THEN 'reevaluation'
                               ELSE 'autre'
                             END motif
                        FROM all_tables
                       WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                         AND (table_name LIKE '%NOSTRO%' OR table_name LIKE '%VOSTRO%'
                              OR table_name LIKE '%FOREX%' OR table_name LIKE '%EXCH%'
                              OR table_name LIKE '%RATE%'  OR table_name LIKE '%CCY%'
                              OR table_name LIKE '%CURRENC%' OR table_name LIKE '%REVAL%')
                         AND NVL(num_rows, 0) > 0
                       ORDER BY num_rows DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 60;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.table_name, 42) || '|'
                    || fpadl(fnum(r.num_rows), 18) || '|' || fpad(r.motif, 42) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,42,18,42');
        IF v_row = 0 THEN
            po('    (aucune table correspondante, ou statistiques absentes)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 4. VOLUMETRIE REELLE DES TABLES DU PERIMETRE
    -- =========================================================
    print_section('4. VOLUMETRIE REELLE DES TABLES DU PERIMETRE (COUNT(*))');
    BEGIN
        po('  Les statistiques Oracle peuvent etre perimees. Cette section compte');
        po('  reellement les lignes des tables utiles a l''audit du change.');
        po('');
        FOR r IN (
            SELECT tab, lib, ord FROM (
                SELECT 'CYTB_RATES_HISTORY' tab,
                       'Historique des cours de change saisis' lib, 1 ord FROM DUAL UNION ALL
                SELECT 'CYTB_DERIVED_RATES_HISTORY',
                       'Historique des cours croises derives',        2 FROM DUAL UNION ALL
                SELECT 'RVTB_ACC_REVAL',
                       'Reevaluation de change des comptes',          3 FROM DUAL UNION ALL
                SELECT 'ACTB_HISTORY',
                       'Ecritures comptables historisees',            4 FROM DUAL UNION ALL
                SELECT 'ACTB_ACCBAL_HISTORY',
                       'Soldes quotidiens par compte et devise',      5 FROM DUAL UNION ALL
                SELECT 'GLTB_GL_BAL',
                       'Soldes du grand livre par devise',            6 FROM DUAL UNION ALL
                SELECT 'STTM_CUST_ACCOUNT',
                       'Comptes clients (colonne CCY)',               7 FROM DUAL UNION ALL
                SELECT 'STTB_ACCOUNT',
                       'Comptes et generaux (colonne AC_GL_CCY)',     8 FROM DUAL UNION ALL
                SELECT 'STTM_CUSTOMER',
                       'Fiches clients (pays, nationalite)',          9 FROM DUAL UNION ALL
                SELECT 'STTM_TRN_CODE',
                       'Referentiel des codes transaction',          10 FROM DUAL UNION ALL
                SELECT 'CSTB_AMOUNT_TAG',
                       'Referentiel des tags de montant',            11 FROM DUAL UNION ALL
                SELECT 'CSTM_PRODUCT',
                       'Referentiel des produits',                   12 FROM DUAL UNION ALL
                SELECT 'SITB_CONTRACT_MASTER',
                       'Instructions permanentes (devises)',         13 FROM DUAL UNION ALL
                SELECT 'FXTB_CONTRACT_MASTER',
                       'Deals de change - en-tete (si present)',      14 FROM DUAL UNION ALL
                SELECT 'FXTB_CONTRACT_EVENT_LOG',
                       'Deals de change - evenements (si present)',   15 FROM DUAL UNION ALL
                SELECT 'FSTB_CONTRACT_MASTER',
                       'Reglements de change (si present)',           16 FROM DUAL
            ) ORDER BY ord
        ) LOOP
            print_kv(r.tab, f_lbl(f_count(r.tab)) || '   ' || r.lib);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 5. PREMIER CADRAGE : OU VIT L'ACTIVITE DE CHANGE
    -- =========================================================
    print_section('5. PREMIER CADRAGE : OU VIT REELLEMENT L''ACTIVITE DE CHANGE');
    BEGIN
        po('  Section decisive pour la suite : elle etablit si le change passe par un');
        po('  module de deal ou seulement par des ecritures en devises.');

        print_sub('5.1 Ecritures comptables portant un code module de change');
        print_kv('Ecritures MODULE = ''FX''', f_lbl(f_count('ACTB_HISTORY', 'MODULE = ''FX''')));
        print_kv('Ecritures MODULE = ''FS''', f_lbl(f_count('ACTB_HISTORY', 'MODULE = ''FS''')));
        print_kv('Ecritures MODULE = ''DV''', f_lbl(f_count('ACTB_HISTORY', 'MODULE = ''DV''')));
        print_kv('Ecritures MODULE = ''RE'' (reevaluation)',
                 f_lbl(f_count('ACTB_HISTORY', 'MODULE = ''RE''')));

        print_sub('5.2 Ecritures en devises, tous modules confondus');
        BEGIN
            SELECT COUNT(*),
                   SUM(CASE WHEN h.ac_ccy <> k_lcy THEN 1 ELSE 0 END),
                   COUNT(DISTINCT h.ac_ccy),
                   COUNT(DISTINCT CASE WHEN h.ac_ccy <> k_lcy THEN h.ac_ccy END),
                   SUM(CASE WHEN h.ac_ccy <> k_lcy THEN NVL(h.lcy_amount, 0) ELSE 0 END),
                   MIN(CASE WHEN h.ac_ccy <> k_lcy THEN h.trn_dt END),
                   MAX(CASE WHEN h.ac_ccy <> k_lcy THEN h.trn_dt END)
              INTO v_tot, v_cnt, v_cnt2, v_cnt3, v_mt, v_d1, v_d2
              FROM actb_history h;
            print_kv('Ecritures comptables au total',        fnum(v_tot));
            print_kv('Ecritures en devise etrangere',        fnum(v_cnt) || '   ' || fpct(v_cnt, v_tot));
            print_kv('Devises distinctes rencontrees',       fnum(v_cnt2));
            print_kv('Dont devises etrangeres',              fnum(v_cnt3));
            print_kv('Contre-valeur cumulee en ' || k_lcy,   famt(v_mt) || '  (' || fmio(v_mt) || ')');
            print_kv('Premiere ecriture en devise',          fdt(v_d1));
            print_kv('Derniere ecriture en devise',          fdt(v_d2));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;

        print_sub('5.3 Modules porteurs des ecritures en devises');
        tbl_line('4,10,18,14,22,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpadl('NB ECRITURES', 18) || '|'
            || fpadl('NB DEVISES', 14) || '|' || fpadl('CONTRE-VALEUR', 22) || '|'
            || fpad('1ERE ECRIT.', 16) || '|' || fpad('DER. ECRIT.', 16) || '|');
        tbl_line('4,10,18,14,22,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.module, COUNT(*) nb, COUNT(DISTINCT h.ac_ccy) nbc,
                             SUM(NVL(h.lcy_amount, 0)) mt, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                        FROM actb_history h
                       WHERE h.ac_ccy <> k_lcy
                       GROUP BY h.module
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module, 10) || '|'
                    || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nbc), 14) || '|'
                    || fpadl(fmio(r.mt), 22) || '|' || fpad(fdt(r.d1), 16) || '|'
                    || fpad(fdt(r.d2), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,18,14,22,16,16');
        IF v_row = 0 THEN
            po('    (aucune ecriture en devise etrangere)');
        END IF;

        print_sub('5.4 Autres gisements de donnees de change');
        print_kv('Comptes clients en devise etrangere',
                 f_lbl(f_count('STTM_CUST_ACCOUNT', 'CCY <> ''' || k_lcy || '''')));
        print_kv('Comptes et generaux en devise etrangere',
                 f_lbl(f_count('STTB_ACCOUNT', 'AC_GL_CCY <> ''' || k_lcy || '''')));
        print_kv('Soldes de grand livre en devise etrangere',
                 f_lbl(f_count('GLTB_GL_BAL', 'CCY_CODE <> ''' || k_lcy || '''')));
        print_kv('Lignes de reevaluation de change',
                 f_lbl(f_count('RVTB_ACC_REVAL')));
        print_kv('Cours de change historises',
                 f_lbl(f_count('CYTB_RATES_HISTORY')));
        print_kv('Cours croises derives historises',
                 f_lbl(f_count('CYTB_DERIVED_RATES_HISTORY')));

        po('');
        po('  >>> FIN DE LA PARTIE 1');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po(v_sep);
    po('   PARTIE 2/6 : LE REFERENTIEL DES DEVISES ET DES COURS');
    po(v_sep);

    -- =========================================================
    -- 6. INVENTAIRE DES DEVISES
    -- =========================================================
    print_section('6. INVENTAIRE DES DEVISES PRESENTES DANS LA BASE');
    BEGIN
        po('  Croisement des quatre gisements : comptes clients, comptes et generaux,');
        po('  ecritures comptables et cotations. Une devise cotee mais sans compte ni');
        po('  ecriture est un parametrage dormant ; une devise mouvementee mais jamais');
        po('  cotee est un risque de valorisation.');
        po('');
        tbl_line('4,10,14,12,18,22,16,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('CPTES CLIENTS', 14) || '|'
            || fpadl('CPTES / GL', 12) || '|' || fpadl('NB ECRITURES', 18) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|' || fpadl('COTATIONS', 16) || '|'
            || fpadl('STATUT', 14) || '|');
        tbl_line('4,10,14,12,18,22,16,14');
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT ccy, SUM(nb_cpt) nb_cpt, SUM(nb_gl) nb_gl, SUM(nb_ecr) nb_ecr,
                       SUM(mt) mt, SUM(nb_cot) nb_cot
                  FROM (
                    SELECT a.ccy ccy, COUNT(*) nb_cpt, 0 nb_gl, 0 nb_ecr, 0 mt, 0 nb_cot
                      FROM sttm_cust_account a GROUP BY a.ccy
                    UNION ALL
                    SELECT g.ac_gl_ccy, 0, COUNT(*), 0, 0, 0
                      FROM sttb_account g GROUP BY g.ac_gl_ccy
                    UNION ALL
                    SELECT h.ac_ccy, 0, 0, COUNT(*), SUM(NVL(h.lcy_amount, 0)), 0
                      FROM actb_history h GROUP BY h.ac_ccy
                    UNION ALL
                    SELECT c.ccy1, 0, 0, 0, 0, COUNT(*)
                      FROM cytb_rates_history c GROUP BY c.ccy1
                    UNION ALL
                    SELECT c.ccy2, 0, 0, 0, 0, COUNT(*)
                      FROM cytb_rates_history c GROUP BY c.ccy2
                  )
                 GROUP BY ccy
                 ORDER BY SUM(nb_ecr) DESC, SUM(nb_cot) DESC
            ) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 40;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb_cpt), 14) || '|' || fpadl(fnum(r.nb_gl), 12) || '|'
                    || fpadl(fnum(r.nb_ecr), 18) || '|' || fpadl(fmio(r.mt), 22) || '|'
                    || fpadl(fnum(r.nb_cot), 16) || '|'
                    || fpadl(CASE
                               WHEN r.ccy = k_lcy                        THEN 'LOCALE'
                               WHEN r.nb_ecr = 0 AND r.nb_cot > 0        THEN 'cotee non util.'
                               WHEN r.nb_ecr > 0 AND r.nb_cot = 0        THEN 'UTIL. NON COTEE'
                               WHEN r.nb_ecr > 0                         THEN 'active'
                               ELSE                                           'dormante'
                             END, 14) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,14,12,18,22,16,14');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 7. CYTB_RATES_HISTORY
    -- =========================================================
    print_section('7. CYTB_RATES_HISTORY : LES COURS DE CHANGE SAISIS');
    BEGIN
        po('  Table centrale pour tout controle de change : elle porte, par agence, par');
        po('  couple de devises et par type de cours, le cours acheteur, le cours moyen');
        po('  et le cours vendeur, avec leur date d''application.');

        profile_table('CYTB_RATES_HISTORY', NULL,
                      'PROFIL DES COLONNES : CYTB_RATES_HISTORY');

        show_dist('7.1 Types de cours (RATE_TYPE)',        'cytb_rates_history', 'RATE_TYPE',   NULL, 25);
        show_dist('7.2 Devise 1 du couple (CCY1)',         'cytb_rates_history', 'CCY1',        NULL, 25);
        show_dist('7.3 Devise 2 du couple (CCY2)',         'cytb_rates_history', 'CCY2',        NULL, 25);
        show_dist('7.4 Agence de cotation (BRANCH_CODE)',  'cytb_rates_history', 'BRANCH_CODE', NULL, 25);
        show_dist('7.5 Annee de cotation',                 'cytb_rates_history',
                  'TO_CHAR(RATE_DATE, ''YYYY'')', NULL, 30, 'V');

        print_sub('7.6 Couples de devises cotes');
        tbl_line('4,10,10,12,14,16,16,16,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CCY1', 10) || '|' || fpad('CCY2', 10) || '|'
            || fpad('TYPE', 12) || '|' || fpadl('NB COTATIONS', 14) || '|' || fpad('1ERE DATE', 16) || '|'
            || fpad('DER. DATE', 16) || '|' || fpadl('COURS MIN', 16) || '|' || fpadl('COURS MOYEN', 16) || '|'
            || fpadl('COURS MAX', 16) || '|');
        tbl_line('4,10,10,12,14,16,16,16,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT c.ccy1, c.ccy2, c.rate_type, COUNT(*) nb,
                               MIN(c.rate_date) d1, MAX(c.rate_date) d2,
                               MIN(c.mid_rate) mn, AVG(c.mid_rate) mo, MAX(c.mid_rate) mx
                          FROM cytb_rates_history c
                         GROUP BY c.ccy1, c.ccy2, c.rate_type
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy1, 10) || '|' || fpad(r.ccy2, 10) || '|'
                    || fpad(r.rate_type, 12) || '|' || fpadl(fnum(r.nb), 14) || '|' || fpad(fdt(r.d1), 16) || '|'
                    || fpad(fdt(r.d2), 16) || '|' || fpadl(TO_CHAR(ROUND(r.mn, 6)), 16) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mo, 6)), 16) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mx, 6)), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,12,14,16,16,16,16,16');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 8. CYTB_DERIVED_RATES_HISTORY
    -- =========================================================
    print_section('8. CYTB_DERIVED_RATES_HISTORY : LES COURS CROISES DERIVES');
    BEGIN
        po('  FLEXCUBE derive des cours croises a partir des cours saisis. Il faut');
        po('  savoir lequel des deux referentiels sert effectivement a valoriser les');
        po('  ecritures : c''est l''objet du rapprochement de la section 14.');

        profile_table('CYTB_DERIVED_RATES_HISTORY', NULL,
                      'PROFIL DES COLONNES : CYTB_DERIVED_RATES_HISTORY');

        show_dist('8.1 Types de cours (RATE_TYPE)',       'cytb_derived_rates_history', 'RATE_TYPE', NULL, 25);
        show_dist('8.2 Indicateur de cours (RATE_FLAG)',  'cytb_derived_rates_history', 'RATE_FLAG', NULL, 25);
        show_dist('8.3 Facteur multiplicateur (MULT_FACTOR)',
                  'cytb_derived_rates_history', 'MULT_FACTOR', NULL, 25);
        show_dist('8.4 Facteur de puissance (POWER_FACTOR)',
                  'cytb_derived_rates_history', 'POWER_FACTOR', NULL, 25);
        show_dist('8.5 Annee de cotation',                'cytb_derived_rates_history',
                  'TO_CHAR(RATE_DATE, ''YYYY'')', NULL, 30, 'V');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 9. ANALYSE DES COURS
    -- =========================================================
    print_section('9. ANALYSE DES COURS : PARITE FIXE, SPREADS ET DISPERSION');
    BEGIN
        po('  Le franc CFA est rattache a l''euro par une parite fixe. Toute cotation');
        po('  EUR qui s''en ecarte doit etre expliquee. Pour les autres devises, le');
        po('  spread entre cours acheteur et cours vendeur mesure la marge de change.');

        print_sub('9.1 Cotations impliquant l''euro, confrontees a la parite de rattachement');
        print_kv('Parite de reference retenue',
                 '1 ' || k_ccy_eur || ' = ' || TO_CHAR(k_par_eur) || ' ' || k_lcy);
        po('');
        tbl_line('4,10,10,12,14,16,16,18,18,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CCY1', 10) || '|' || fpad('CCY2', 10) || '|'
            || fpad('TYPE', 12) || '|' || fpadl('NB COTATIONS', 14) || '|' || fpadl('COURS MIN', 16) || '|'
            || fpadl('COURS MAX', 16) || '|' || fpadl('ECARTS / PARITE', 18) || '|'
            || fpadl('ECART MAX', 18) || '|' || fpad('DERNIERE DATE', 16) || '|');
        tbl_line('4,10,10,12,14,16,16,18,18,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT c.ccy1, c.ccy2, c.rate_type, COUNT(*) nb,
                             MIN(c.mid_rate) mn, MAX(c.mid_rate) mx,
                             SUM(CASE WHEN ABS(NVL(c.mid_rate, 0) - k_par_eur) > 0.001
                                       AND ABS(NVL(c.mid_rate, 0) - 1 / k_par_eur) > 0.0000001
                                      THEN 1 ELSE 0 END) nb_ec,
                             MAX(LEAST(ABS(NVL(c.mid_rate, 0) - k_par_eur),
                                       ABS(NVL(c.mid_rate, 0) - 1 / k_par_eur))) ec_mx,
                             MAX(c.rate_date) d2
                        FROM cytb_rates_history c
                       WHERE c.ccy1 = k_ccy_eur OR c.ccy2 = k_ccy_eur
                       GROUP BY c.ccy1, c.ccy2, c.rate_type
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 25;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy1, 10) || '|' || fpad(r.ccy2, 10) || '|'
                    || fpad(r.rate_type, 12) || '|' || fpadl(fnum(r.nb), 14) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mn, 6)), 16) || '|' || fpadl(TO_CHAR(ROUND(r.mx, 6)), 16) || '|'
                    || fpadl(fnum(r.nb_ec), 18) || '|' || fpadl(TO_CHAR(ROUND(r.ec_mx, 6)), 18) || '|'
                    || fpad(fdt(r.d2), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,12,14,16,16,18,18,16');
        IF v_row = 0 THEN
            po('    (aucune cotation impliquant ' || k_ccy_eur || ')');
        END IF;

        print_sub('9.2 Spread entre cours acheteur et cours vendeur, par couple');
        po('  Le spread est exprime en pourcentage du cours moyen. Un spread nul');
        po('  signale une cotation unique ; un spread eleve, une marge de change large.');
        po('');
        tbl_line('4,10,10,12,14,16,16,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CCY1', 10) || '|' || fpad('CCY2', 10) || '|'
            || fpad('TYPE', 12) || '|' || fpadl('NB COTATIONS', 14) || '|' || fpadl('SPREAD MOYEN', 16) || '|'
            || fpadl('SPREAD MIN', 16) || '|' || fpadl('SPREAD MAX', 16) || '|'
            || fpadl('NB SPREAD NUL', 16) || '|');
        tbl_line('4,10,10,12,14,16,16,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT c.ccy1, c.ccy2, c.rate_type, COUNT(*) nb,
                               AVG(100 * (c.sale_rate - c.buy_rate) / NULLIF(c.mid_rate, 0)) sp_mo,
                               MIN(100 * (c.sale_rate - c.buy_rate) / NULLIF(c.mid_rate, 0)) sp_mn,
                               MAX(100 * (c.sale_rate - c.buy_rate) / NULLIF(c.mid_rate, 0)) sp_mx,
                               SUM(CASE WHEN NVL(c.sale_rate, 0) = NVL(c.buy_rate, 0)
                                        THEN 1 ELSE 0 END) nb0
                          FROM cytb_rates_history c
                         WHERE c.mid_rate IS NOT NULL AND c.mid_rate <> 0
                         GROUP BY c.ccy1, c.ccy2, c.rate_type
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 30) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy1, 10) || '|' || fpad(r.ccy2, 10) || '|'
                    || fpad(r.rate_type, 12) || '|' || fpadl(fnum(r.nb), 14) || '|'
                    || fpadl(TO_CHAR(ROUND(r.sp_mo, 4)) || ' %', 16) || '|'
                    || fpadl(TO_CHAR(ROUND(r.sp_mn, 4)) || ' %', 16) || '|'
                    || fpadl(TO_CHAR(ROUND(r.sp_mx, 4)) || ' %', 16) || '|'
                    || fpadl(fnum(r.nb0), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,12,14,16,16,16,16');

        print_sub('9.3 Coherence interne des cours (acheteur, moyen, vendeur)');
        po('  Regle attendue : cours acheteur inferieur ou egal au cours moyen,');
        po('  lui-meme inferieur ou egal au cours vendeur, et aucun cours nul.');
        po('');
        BEGIN
            SELECT COUNT(*),
                   SUM(CASE WHEN c.buy_rate > c.mid_rate THEN 1 ELSE 0 END),
                   SUM(CASE WHEN c.mid_rate > c.sale_rate THEN 1 ELSE 0 END),
                   SUM(CASE WHEN NVL(c.mid_rate, 0) <= 0 THEN 1 ELSE 0 END)
              INTO v_tot, v_cnt, v_cnt2, v_cnt3
              FROM cytb_rates_history c;
            print_kv('Cotations au total',                       fnum(v_tot));
            print_kv('Cours acheteur superieur au cours moyen',  fnum(v_cnt));
            print_kv('Cours moyen superieur au cours vendeur',   fnum(v_cnt2));
            print_kv('Cours moyen nul ou negatif',               fnum(v_cnt3));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 10. CONTINUITE DE L'HISTORIQUE DES COURS
    -- =========================================================
    print_section('10. CONTINUITE DE L''HISTORIQUE DES COURS');
    BEGIN
        po('  Une valorisation fiable suppose une cotation disponible a chaque date');
        po('  ouvree. Cette section mesure la profondeur et les trous de l''historique,');
        po('  couple par couple.');
        po('');
        tbl_line('4,10,10,16,16,14,16,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CCY1', 10) || '|' || fpad('CCY2', 10) || '|'
            || fpad('1ERE COTATION', 16) || '|' || fpad('DER. COTATION', 16) || '|'
            || fpadl('NB DATES', 14) || '|' || fpadl('ETENDUE (J)', 16) || '|'
            || fpadl('PLUS LONG TROU', 16) || '|' || fpadl('SILENCE (J)', 16) || '|');
        tbl_line('4,10,10,16,16,14,16,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT ccy1, ccy2, MIN(rate_date) d1, MAX(rate_date) d2,
                               COUNT(*) nbd, MAX(rate_date) - MIN(rate_date) etendue,
                               MAX(gap) trou
                          FROM (SELECT ccy1, ccy2, rate_date,
                                       rate_date - LAG(rate_date)
                                         OVER (PARTITION BY ccy1, ccy2 ORDER BY rate_date) gap
                                  FROM (SELECT DISTINCT ccy1, ccy2, rate_date
                                          FROM cytb_rates_history))
                         GROUP BY ccy1, ccy2
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 30) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy1, 10) || '|' || fpad(r.ccy2, 10) || '|'
                    || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|' || fpadl(fnum(r.nbd), 14) || '|'
                    || fpadl(fnum(r.etendue), 16) || '|' || fpadl(fnum(r.trou), 16) || '|'
                    || fpadl(fnum(TRUNC(SYSDATE) - TRUNC(r.d2)), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,16,16,14,16,16,16');

        po('');
        po('  >>> FIN DE LA PARTIE 2');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po(v_sep);
    po('   PARTIE 3/6 : L''EMPREINTE DU CHANGE DANS LA COMPTABILITE');
    po(v_sep);
    po('  ATTENTION : ACTB_HISTORY est volumineuse. Cette partie peut demander');
    po('  plusieurs minutes d''execution.');

    -- =========================================================
    -- 11. CARTOGRAPHIE DES ECRITURES EN DEVISES
    -- =========================================================
    print_section('11. ACTB_HISTORY : CARTOGRAPHIE DES ECRITURES EN DEVISES');
    BEGIN
        print_sub('11.1 Par devise');
        tbl_line('4,10,18,14,22,22,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB ECRITURES', 18) || '|'
            || fpadl('NB COMPTES', 14) || '|' || fpadl('MONTANT DEVISE', 22) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|' || fpad('1ERE ECRIT.', 16) || '|'
            || fpad('DER. ECRIT.', 16) || '|');
        tbl_line('4,10,18,14,22,22,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.ac_ccy ccy, COUNT(*) nb, COUNT(DISTINCT h.ac_no) nbc,
                             SUM(NVL(h.fcy_amount, 0)) fcy, SUM(NVL(h.lcy_amount, 0)) lcy,
                             MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                        FROM actb_history h
                       WHERE h.ac_ccy <> k_lcy
                       GROUP BY h.ac_ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nbc), 14) || '|'
                    || fpadl(famt(r.fcy), 22) || '|' || fpadl(fmio(r.lcy), 22) || '|'
                    || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,18,14,22,22,16,16');
        IF v_row = 0 THEN
            po('    (aucune ecriture en devise etrangere)');
        END IF;

        print_sub('11.2 Par devise et par annee');
        tbl_line('4,10,10,18,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpad('ANNEE', 10) || '|'
            || fpadl('NB ECRITURES', 18) || '|' || fpadl('MONTANT DEVISE', 22) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|');
        tbl_line('4,10,10,18,22,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.ac_ccy ccy, TO_CHAR(h.trn_dt, 'YYYY') an, COUNT(*) nb,
                             SUM(NVL(h.fcy_amount, 0)) fcy, SUM(NVL(h.lcy_amount, 0)) lcy
                        FROM actb_history h
                       WHERE h.ac_ccy <> k_lcy
                       GROUP BY h.ac_ccy, TO_CHAR(h.trn_dt, 'YYYY')
                       ORDER BY h.ac_ccy, 2) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 80;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpad(r.an, 10) || '|'
                    || fpadl(fnum(r.nb), 18) || '|' || fpadl(famt(r.fcy), 22) || '|'
                    || fpadl(fmio(r.lcy), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,18,22,22');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 12. PROFIL DES COLONNES DE CHANGE D'ACTB_HISTORY
    -- =========================================================
    print_section('12. PROFIL DES COLONNES D''ACTB_HISTORY SUR LE PERIMETRE DEVISES');
    BEGIN
        po('  Le profil est calcule sur les seules ecritures en devise etrangere : il');
        po('  montre quelles colonnes sont reellement alimentees pour ces operations.');
        profile_table('ACTB_HISTORY', 'AC_CCY <> ''' || k_lcy || '''',
                      'PROFIL DES COLONNES : ACTB_HISTORY  [ecritures en devise etrangere]');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 13. ANALYSE MULTI-AXES DES ECRITURES EN DEVISES
    -- =========================================================
    print_section('13. ANALYSE MULTI-AXES DES ECRITURES EN DEVISES');
    BEGIN
        po('  Une seule lecture de la table, declinee sur douze axes d''analyse.');
        po('  C''est la photographie complete de la facon dont le change est');
        po('  comptabilise dans cette banque.');

        v_dim := '~';
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT ord, dim, val, k, tot FROM (
                    SELECT dd.ord AS ord,
                           dd.dim AS dim,
                           NVL(TRIM(CASE dd.dim
                                WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                                WHEN 'MODULE'         THEN h.module
                                WHEN 'EVENT'          THEN h.event
                                WHEN 'TRN_CODE'       THEN h.trn_code
                                WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                                WHEN 'SENS'           THEN h.drcr_ind
                                WHEN 'PRODUIT'        THEN h.product
                                WHEN 'AGENCE'         THEN h.ac_branch
                                WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                                WHEN 'SAISI_PAR'      THEN h.user_id
                                WHEN 'AUTORISE_PAR'   THEN h.auth_id
                                WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL
                                                                THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                           END), '(vide)') AS val,
                           COUNT(*) AS k,
                           SUM(NVL(h.lcy_amount, 0)) AS tot,
                           ROW_NUMBER() OVER (PARTITION BY dd.dim ORDER BY COUNT(*) DESC) AS rn
                    FROM actb_history h
                    CROSS JOIN (
                        SELECT 'ANNEE' dim, 1 ord FROM DUAL UNION ALL
                        SELECT 'MODULE',       2 FROM DUAL UNION ALL
                        SELECT 'EVENT',        3 FROM DUAL UNION ALL
                        SELECT 'TRN_CODE',     4 FROM DUAL UNION ALL
                        SELECT 'AMOUNT_TAG',   5 FROM DUAL UNION ALL
                        SELECT 'SENS',         6 FROM DUAL UNION ALL
                        SELECT 'PRODUIT',      7 FROM DUAL UNION ALL
                        SELECT 'AGENCE',       8 FROM DUAL UNION ALL
                        SELECT 'CLIENT_OU_GL', 9 FROM DUAL UNION ALL
                        SELECT 'SAISI_PAR',   10 FROM DUAL UNION ALL
                        SELECT 'AUTORISE_PAR',11 FROM DUAL UNION ALL
                        SELECT 'REF_EXTERNE', 12 FROM DUAL
                    ) dd
                    WHERE h.ac_ccy <> k_lcy
                    GROUP BY dd.ord, dd.dim,
                             CASE dd.dim
                                WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                                WHEN 'MODULE'         THEN h.module
                                WHEN 'EVENT'          THEN h.event
                                WHEN 'TRN_CODE'       THEN h.trn_code
                                WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                                WHEN 'SENS'           THEN h.drcr_ind
                                WHEN 'PRODUIT'        THEN h.product
                                WHEN 'AGENCE'         THEN h.ac_branch
                                WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                                WHEN 'SAISI_PAR'      THEN h.user_id
                                WHEN 'AUTORISE_PAR'   THEN h.auth_id
                                WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL
                                                                THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                             END
                ) WHERE rn <= 15
                ORDER BY ord, k DESC
            ) LOOP
                IF v_dim <> r.dim THEN
                    v_dim := r.dim;
                    print_sub('13.' || TO_CHAR(r.ord) || ' Axe . ' || r.dim);
                    tbl_line('34,16,22');
                    po('  |' || fpad('VALEUR', 34) || '|' || fpadl('NB ECRITURES', 16) || '|'
                        || fpadl('CONTRE-VALEUR', 22) || '|');
                    tbl_line('34,16,22');
                END IF;
                po('  |' || fpad(r.val, 34) || '|' || fpadl(fnum(r.k), 16) || '|'
                    || fpadl(fmio(r.tot), 22) || '|');
                v_row := v_row + 1;
            END LOOP;
            IF v_row > 0 THEN
                tbl_line('34,16,22');
            ELSE
                po('    (aucune ecriture en devise etrangere)');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 14. RELATION ENTRE MONTANT EN DEVISE, COURS ET CONTRE-VALEUR
    -- =========================================================
    print_section('14. RELATION ENTRE MONTANT EN DEVISE, COURS ET CONTRE-VALEUR');
    BEGIN
        po('  Question centrale du futur script d''audit : selon quelle convention');
        po('  FLEXCUBE convertit-il le montant en devise en contre-valeur locale ?');
        po('  Deux conventions sont possibles, la multiplication ou la division par le');
        po('  cours. Le script teste les deux et indique laquelle reconcilie.');
        po('');
        po('    convention MULTIPLICATION . contre-valeur = montant devise x cours');
        po('    convention DIVISION ....... contre-valeur = montant devise / cours');
        po('');
        po('  Tolerance appliquee : 1 unite de monnaie locale, ou 0,01 pourcent.');

        print_sub('14.1 Convention qui reconcilie la contre-valeur, par devise');
        tbl_line('4,10,16,18,18,18,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB TESTEES', 16) || '|'
            || fpadl('MULTIPLICATION', 18) || '|' || fpadl('DIVISION', 18) || '|'
            || fpadl('AUCUNE', 18) || '|' || fpadl('% RECONCILIE', 18) || '|');
        tbl_line('4,10,16,18,18,18,18');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT ccy, COUNT(*) nb,
                             SUM(ok_mult) n_mult, SUM(ok_div) n_div,
                             SUM(CASE WHEN ok_mult + ok_div = 0 THEN 1 ELSE 0 END) n_non
                        FROM (SELECT h.ac_ccy ccy,
                                     CASE WHEN ABS(NVL(h.lcy_amount, 0)
                                                   - NVL(h.fcy_amount, 0) * NVL(h.exch_rate, 0))
                                               <= GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                                          THEN 1 ELSE 0 END ok_mult,
                                     CASE WHEN ABS(NVL(h.lcy_amount, 0)
                                                   - NVL(h.fcy_amount, 0) / NULLIF(h.exch_rate, 0))
                                               <= GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                                          THEN 1 ELSE 0 END ok_div
                                FROM actb_history h
                               WHERE h.ac_ccy <> k_lcy
                                 AND NVL(h.fcy_amount, 0) <> 0
                                 AND NVL(h.exch_rate, 0) <> 0)
                       GROUP BY ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fnum(r.n_mult), 18) || '|'
                    || fpadl(fnum(r.n_div), 18) || '|' || fpadl(fnum(r.n_non), 18) || '|'
                    || fpadl(fpct(r.nb - r.n_non, r.nb), 18) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,18,18,18,18');
        IF v_row = 0 THEN
            po('    (aucune ecriture en devise avec montant et cours renseignes)');
        END IF;

        print_sub('14.2 Distribution des cours de change appliques, par devise');
        tbl_line('4,10,16,18,18,18,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('COURS MIN', 18) || '|' || fpadl('COURS MOYEN', 18) || '|'
            || fpadl('COURS MAX', 18) || '|' || fpadl('NB COURS DISTINCTS', 18) || '|');
        tbl_line('4,10,16,18,18,18,18');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.ac_ccy ccy, COUNT(*) nb, MIN(h.exch_rate) mn,
                             AVG(h.exch_rate) mo, MAX(h.exch_rate) mx,
                             COUNT(DISTINCT h.exch_rate) nbd
                        FROM actb_history h
                       WHERE h.ac_ccy <> k_lcy AND NVL(h.exch_rate, 0) <> 0
                       GROUP BY h.ac_ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(TO_CHAR(ROUND(r.mn, 6)), 18) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mo, 6)), 18) || '|'
                    || fpadl(TO_CHAR(ROUND(r.mx, 6)), 18) || '|' || fpadl(fnum(r.nbd), 18) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,18,18,18,18');

        print_sub('14.3 Ecritures en devise sans cours de change renseigne');
        BEGIN
            SELECT COUNT(*), SUM(NVL(lcy_amount, 0)) INTO v_cnt, v_mt
              FROM actb_history
             WHERE ac_ccy <> k_lcy AND NVL(exch_rate, 0) = 0;
            print_kv('Ecritures en devise sans cours', fnum(v_cnt));
            print_kv('Contre-valeur correspondante',   famt(v_mt) || '  (' || fmio(v_mt) || ')');
            SELECT COUNT(*), SUM(NVL(lcy_amount, 0)) INTO v_cnt, v_mt
              FROM actb_history
             WHERE ac_ccy <> k_lcy AND NVL(fcy_amount, 0) = 0;
            print_kv('Ecritures en devise sans montant en devise', fnum(v_cnt));
            print_kv('Contre-valeur correspondante',   famt(v_mt) || '  (' || fmio(v_mt) || ')');
            SELECT COUNT(*) INTO v_cnt
              FROM actb_history
             WHERE ac_ccy = k_lcy AND NVL(exch_rate, 1) <> 1;
            print_kv('Ecritures en monnaie locale avec un cours different de 1', fnum(v_cnt));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 15. COMPTES ET GENERAUX MOUVEMENTES EN DEVISES
    -- =========================================================
    print_section('15. COMPTES ET GENERAUX MOUVEMENTES EN DEVISES');
    BEGIN
        po('  Les comptes de correspondants (nostro) apparaissent ici : ce sont les');
        po('  generaux en devise etrangere les plus mouvementes. La reglementation');
        po('  CEMAC encadre la detention d''avoirs en devises chez les correspondants.');
        po('');
        tbl_line('4,22,38,8,8,16,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE / GENERAL', 22) || '|' || fpad('LIBELLE', 38) || '|'
            || fpad('CCY', 8) || '|' || fpad('C/GL', 8) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('TOTAL DEBIT', 22) || '|' || fpadl('TOTAL CREDIT', 22) || '|');
        tbl_line('4,22,38,8,8,16,22,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT h.ac_no, MAX(h.ac_ccy) ccy, MAX(h.cust_gl) cgl, COUNT(*) nb,
                               (SELECT MAX(a.ac_gl_desc) FROM sttb_account a
                                 WHERE a.ac_gl_no = h.ac_no) lib,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                          FROM actb_history h
                         WHERE h.ac_ccy <> k_lcy
                         GROUP BY h.ac_no
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 38) || '|'
                    || fpad(r.ccy, 8) || '|' || fpad(r.cgl, 8) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fmio(r.deb), 22) || '|' || fpadl(fmio(r.cre), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,22,38,8,8,16,22,22');
        IF v_row = 0 THEN
            po('    (aucun compte mouvemente en devise etrangere)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 16. ECHANTILLON D'ECRITURES EN DEVISES
    -- =========================================================
    print_section('16. ECHANTILLON DES 40 DERNIERES ECRITURES EN DEVISES');
    BEGIN
        tbl_line('4,22,8,8,10,22,6,6,20,16,20,12,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('TRN_REF_NO', 22) || '|' || fpad('MODULE', 8) || '|'
            || fpad('EVENT', 8) || '|' || fpad('TRN_CODE', 10) || '|' || fpad('AC_NO', 22) || '|'
            || fpad('CCY', 6) || '|' || fpad('D/C', 6) || '|' || fpadl('MONTANT DEVISE', 20) || '|'
            || fpadl('COURS', 16) || '|' || fpadl('CONTRE-VALEUR', 20) || '|' || fpad('DATE', 12) || '|'
            || fpad('SAISI PAR', 16) || '|');
        tbl_line('4,22,8,8,10,22,6,6,20,16,20,12,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT h.trn_ref_no, h.module, h.event, h.trn_code, h.ac_no, h.ac_ccy,
                               h.drcr_ind, h.fcy_amount, h.exch_rate, h.lcy_amount, h.trn_dt, h.user_id
                          FROM actb_history h
                         WHERE h.ac_ccy <> k_lcy
                         ORDER BY h.trn_dt DESC, h.trn_ref_no, h.ac_entry_sr_no
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_ref_no, 22) || '|'
                    || fpad(r.module, 8) || '|' || fpad(r.event, 8) || '|' || fpad(r.trn_code, 10) || '|'
                    || fpad(r.ac_no, 22) || '|' || fpad(r.ac_ccy, 6) || '|' || fpad(r.drcr_ind, 6) || '|'
                    || fpadl(famt(r.fcy_amount), 20) || '|' || fpadl(TO_CHAR(ROUND(r.exch_rate, 6)), 16) || '|'
                    || fpadl(famt(r.lcy_amount), 20) || '|' || fpad(fdt(r.trn_dt), 12) || '|'
                    || fpad(r.user_id, 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,22,8,8,10,22,6,6,20,16,20,12,16');
        IF v_row = 0 THEN
            po('    (aucune ecriture en devise etrangere)');
        END IF;

        po('');
        po('  >>> FIN DE LA PARTIE 3');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po(v_sep);
    po('   PARTIE 4/6 : COMPTES, CLIENTS ET POSITION DE CHANGE');
    po(v_sep);

    -- =========================================================
    -- 17. COMPTES CLIENTS EN DEVISES
    -- =========================================================
    print_section('17. LES COMPTES CLIENTS EN DEVISES');
    BEGIN
        po('  L''ouverture et le fonctionnement des comptes en devises par les residents');
        po('  et les non-residents sont encadres par la reglementation des changes');
        po('  (instruction du Gouverneur de la BEAC n 005 du 10 juin 2019).');

        print_sub('17.1 Comptes clients par devise');
        tbl_line('4,10,14,14,14,22,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB COMPTES', 14) || '|'
            || fpadl('NB CLIENTS', 14) || '|' || fpadl('DONT OUVERTS', 14) || '|'
            || fpadl('SOLDE DEVISE', 22) || '|' || fpadl('CONTRE-VALEUR', 22) || '|'
            || fpad('1ERE OUVERT.', 16) || '|');
        tbl_line('4,10,14,14,14,22,22,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT a.ccy, COUNT(*) nb, COUNT(DISTINCT a.cust_no) nbc,
                             SUM(CASE WHEN NVL(TRIM(a.record_stat), 'O') = 'O' THEN 1 ELSE 0 END) nbo,
                             SUM(NVL(a.acy_curr_balance, 0)) sacy,
                             SUM(NVL(a.lcy_curr_balance, 0)) slcy,
                             MIN(a.ac_open_date) d1
                        FROM sttm_cust_account a
                       GROUP BY a.ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(fnum(r.nbc), 14) || '|'
                    || fpadl(fnum(r.nbo), 14) || '|' || fpadl(famt(r.sacy), 22) || '|'
                    || fpadl(fmio(r.slcy), 22) || '|' || fpad(fdt(r.d1), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,14,14,14,22,22,16');

        print_sub('17.2 Comptes en devises par classe de compte');
        tbl_line('4,10,16,40,14,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpad('CLASSE', 16) || '|'
            || fpad('LIBELLE DE LA CLASSE', 40) || '|' || fpadl('NB COMPTES', 14) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|' || fpadl('NB CLIENTS', 16) || '|');
        tbl_line('4,10,16,40,14,22,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT a.ccy, a.account_class cls, COUNT(*) nb,
                               COUNT(DISTINCT a.cust_no) nbc,
                               SUM(NVL(a.lcy_curr_balance, 0)) mt,
                               (SELECT MAX(c.description) FROM sttm_account_class c
                                 WHERE c.account_class = a.account_class) lib
                          FROM sttm_cust_account a
                         WHERE a.ccy <> k_lcy
                         GROUP BY a.ccy, a.account_class
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 30) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpad(r.cls, 16) || '|'
                    || fpad(r.lib, 40) || '|' || fpadl(fnum(r.nb), 14) || '|' || fpadl(fmio(r.mt), 22) || '|'
                    || fpadl(fnum(r.nbc), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,40,14,22,16');
        IF v_row = 0 THEN
            po('    (aucun compte client en devise etrangere, ou classe indisponible)');
        END IF;

        print_sub('17.3 Statuts des comptes en devises');
        show_dist('Statut d''enregistrement (RECORD_STAT)', 'sttm_cust_account', 'RECORD_STAT',
                  'CCY <> ''' || k_lcy || '''', 10);
        show_dist('Compte dormant (AC_STAT_DORMANT)',       'sttm_cust_account', 'AC_STAT_DORMANT',
                  'CCY <> ''' || k_lcy || '''', 10);
        show_dist('Compte gele (AC_STAT_FROZEN)',           'sttm_cust_account', 'AC_STAT_FROZEN',
                  'CCY <> ''' || k_lcy || '''', 10);
        show_dist('Compte bloque (AC_STAT_BLOCK)',          'sttm_cust_account', 'AC_STAT_BLOCK',
                  'CCY <> ''' || k_lcy || '''', 10);
        show_dist('Annee d''ouverture',                     'sttm_cust_account',
                  'TO_CHAR(AC_OPEN_DATE, ''YYYY'')', 'CCY <> ''' || k_lcy || '''', 30, 'V');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 18. LES TITULAIRES DE COMPTES EN DEVISES
    -- =========================================================
    print_section('18. LES TITULAIRES DE COMPTES EN DEVISES');
    BEGIN
        po('  La reglementation distingue residents et non-residents. FLEXCUBE ne porte');
        po('  pas d''indicateur de residence explicite : le pays et la nationalite du');
        po('  client en sont les meilleurs substituts disponibles.');

        print_sub('18.1 Repartition par pays du titulaire');
        tbl_line('4,12,10,16,16,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PAYS', 12) || '|' || fpad('DEVISE', 10) || '|'
            || fpadl('NB COMPTES', 16) || '|' || fpadl('NB CLIENTS', 16) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|' || fpadl('% COMPTES', 16) || '|');
        tbl_line('4,12,10,16,16,22,16');
        v_row := 0;
        BEGIN
            SELECT COUNT(*) INTO v_tot FROM sttm_cust_account WHERE ccy <> k_lcy;
            FOR r IN (SELECT * FROM (
                        SELECT c.country pays, a.ccy, COUNT(*) nb,
                               COUNT(DISTINCT a.cust_no) nbc,
                               SUM(NVL(a.lcy_curr_balance, 0)) mt
                          FROM sttm_cust_account a
                          JOIN sttm_customer c ON c.customer_no = a.cust_no
                         WHERE a.ccy <> k_lcy
                         GROUP BY c.country, a.ccy
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.pays, 12) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fnum(r.nbc), 16) || '|'
                    || fpadl(fmio(r.mt), 22) || '|' || fpadl(fpct(r.nb, v_tot), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,12,10,16,16,22,16');
        IF v_row = 0 THEN
            po('    (aucun compte client en devise etrangere)');
        END IF;

        print_sub('18.2 Repartition par type et categorie de client');
        show_dist('Type de client (CUSTOMER_TYPE)',
                  'sttm_customer c', 'c.CUSTOMER_TYPE',
                  'EXISTS (SELECT 1 FROM sttm_cust_account a WHERE a.cust_no = c.customer_no '
                  || 'AND a.ccy <> ''' || k_lcy || ''')', 15);
        show_dist('Categorie de client (CUSTOMER_CATEGORY)',
                  'sttm_customer c', 'c.CUSTOMER_CATEGORY',
                  'EXISTS (SELECT 1 FROM sttm_cust_account a WHERE a.cust_no = c.customer_no '
                  || 'AND a.ccy <> ''' || k_lcy || ''')', 25);
        show_dist('Nationalite (NATIONALITY)',
                  'sttm_customer c', 'c.NATIONALITY',
                  'EXISTS (SELECT 1 FROM sttm_cust_account a WHERE a.cust_no = c.customer_no '
                  || 'AND a.ccy <> ''' || k_lcy || ''')', 25);

        print_sub('18.3 Les 30 titulaires de comptes en devises les plus importants');
        tbl_line('4,14,34,8,8,10,14,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 14) || '|' || fpad('CLIENT', 34) || '|'
            || fpad('TYPE', 8) || '|' || fpad('PAYS', 8) || '|' || fpad('DEVISE', 10) || '|'
            || fpadl('NB COMPTES', 14) || '|' || fpadl('CONTRE-VALEUR', 22) || '|');
        tbl_line('4,14,34,8,8,10,14,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT a.cust_no, MAX(c.customer_name1) nom, MAX(c.customer_type) typ,
                               MAX(c.country) pays, MAX(a.ccy) ccy, COUNT(*) nb,
                               SUM(NVL(a.lcy_curr_balance, 0)) mt
                          FROM sttm_cust_account a
                          JOIN sttm_customer c ON c.customer_no = a.cust_no
                         WHERE a.ccy <> k_lcy
                         GROUP BY a.cust_no
                         ORDER BY SUM(ABS(NVL(a.lcy_curr_balance, 0))) DESC
                      ) WHERE ROWNUM <= 30) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cust_no, 14) || '|' || fpad(r.nom, 34) || '|'
                    || fpad(r.typ, 8) || '|' || fpad(r.pays, 8) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(famt(r.mt), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,14,34,8,8,10,14,22');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 19. COMPTES ET GENERAUX EN DEVISES, CORRESPONDANTS
    -- =========================================================
    print_section('19. COMPTES ET GENERAUX EN DEVISES (CORRESPONDANTS)');
    BEGIN
        po('  STTB_ACCOUNT recense a la fois les comptes clients et les generaux. Les');
        po('  generaux en devise etrangere sont les supports des avoirs detenus chez les');
        po('  correspondants, dont la reglementation encadre la detention.');

        print_sub('19.1 Comptes et generaux par devise');
        tbl_line('4,10,14,14,14,40');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB LIGNES', 14) || '|'
            || fpadl('DONT GENERAUX', 14) || '|' || fpadl('DONT COMPTES', 14) || '|'
            || fpad('EXEMPLE DE LIBELLE', 40) || '|');
        tbl_line('4,10,14,14,14,40');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT a.ac_gl_ccy ccy, COUNT(*) nb,
                             SUM(CASE WHEN a.ac_or_gl = 'G' THEN 1 ELSE 0 END) nbg,
                             SUM(CASE WHEN a.ac_or_gl = 'A' THEN 1 ELSE 0 END) nba,
                             MAX(a.ac_gl_desc) lib
                        FROM sttb_account a
                       GROUP BY a.ac_gl_ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpadl(fnum(r.nb), 14) || '|'
                    || fpadl(fnum(r.nbg), 14) || '|' || fpadl(fnum(r.nba), 14) || '|' || fpad(r.lib, 40) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,14,14,14,40');

        print_sub('19.2 Generaux en devise etrangere : candidats comptes de correspondants');
        tbl_line('4,22,44,10,10,14,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('GENERAL', 22) || '|' || fpad('LIBELLE', 44) || '|'
            || fpad('DEVISE', 10) || '|' || fpad('CATEG.', 10) || '|' || fpad('AGENCE', 14) || '|'
            || fpadl('NB ECRITURES', 16) || '|');
        tbl_line('4,22,44,10,10,14,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT a.ac_gl_no, a.ac_gl_desc, a.ac_gl_ccy, a.gl_category, a.branch_code,
                               NVL(x.nb, 0) nb
                          FROM sttb_account a
                          LEFT JOIN (SELECT h.ac_no, COUNT(*) nb
                                       FROM actb_history h
                                      WHERE h.ac_ccy <> k_lcy
                                      GROUP BY h.ac_no) x ON x.ac_no = a.ac_gl_no
                         WHERE a.ac_gl_ccy <> k_lcy
                           AND a.ac_or_gl = 'G'
                         ORDER BY NVL(x.nb, 0) DESC, a.ac_gl_ccy, a.ac_gl_no
                      ) WHERE ROWNUM <= 60) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_gl_no, 22) || '|'
                    || fpad(r.ac_gl_desc, 44) || '|' || fpad(r.ac_gl_ccy, 10) || '|'
                    || fpad(r.gl_category, 10) || '|' || fpad(r.branch_code, 14) || '|'
                    || fpadl(fnum(r.nb), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,22,44,10,10,14,16');
        IF v_row = 0 THEN
            po('    (aucun general en devise etrangere)');
        END IF;

        print_sub('19.3 Generaux dont le libelle evoque un correspondant');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT a.ac_gl_no, a.ac_gl_desc, a.ac_gl_ccy
                        FROM sttb_account a
                       WHERE UPPER(a.ac_gl_desc) LIKE '%NOSTRO%'
                          OR UPPER(a.ac_gl_desc) LIKE '%VOSTRO%'
                          OR UPPER(a.ac_gl_desc) LIKE '%CORRESPOND%'
                          OR UPPER(a.ac_gl_desc) LIKE '%BEAC%'
                          OR UPPER(a.ac_gl_desc) LIKE '%BANQUE CENTRALE%'
                       ORDER BY a.ac_gl_ccy, a.ac_gl_no) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 60;
                print_kv('  ' || RPAD(r.ac_gl_no, 18) || ' ' || RPAD(NVL(r.ac_gl_ccy, '-'), 5), r.ac_gl_desc);
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        IF v_row = 0 THEN
            po('    (aucun libelle correspondant aux motifs recherches)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 20. POSITION DE CHANGE
    -- =========================================================
    print_section('20. POSITION DE CHANGE PAR DEVISE');
    BEGIN
        po('  La reglementation impose aux etablissements de credit de communiquer');
        po('  periodiquement a la Banque Centrale leurs positions globales de change.');
        po('  Cette section reconstitue la position telle qu''elle ressort des soldes du');
        po('  grand livre, devise par devise.');

        print_sub('20.1 Exercices et periodes disponibles dans GLTB_GL_BAL');
        show_dist('Exercice (FIN_YEAR)',    'gltb_gl_bal', 'FIN_YEAR',    NULL, 20, 'V');
        show_dist('Periode (PERIOD_CODE)',  'gltb_gl_bal', 'PERIOD_CODE', NULL, 20, 'V');

        print_sub('20.2 Position par devise et par exercice');
        tbl_line('4,10,10,14,22,22,24,24');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpad('EXERCICE', 10) || '|'
            || fpadl('NB LIGNES', 14) || '|' || fpadl('SOLDE DEBIT', 22) || '|'
            || fpadl('SOLDE CREDIT', 22) || '|' || fpadl('POSITION NETTE DEVISE', 24) || '|'
            || fpadl('POSITION NETTE LOCALE', 24) || '|');
        tbl_line('4,10,10,14,22,22,24,24');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT g.ccy_code ccy, g.fin_year an, COUNT(*) nb,
                             SUM(NVL(g.dr_bal, 0)) db, SUM(NVL(g.cr_bal, 0)) cb,
                             SUM(NVL(g.dr_bal, 0)) - SUM(NVL(g.cr_bal, 0)) net,
                             SUM(NVL(g.dr_bal_lcy, 0)) - SUM(NVL(g.cr_bal_lcy, 0)) net_lcy
                        FROM gltb_gl_bal g
                       WHERE g.ccy_code <> k_lcy
                       GROUP BY g.ccy_code, g.fin_year
                       ORDER BY g.ccy_code, g.fin_year) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 60;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpad(r.an, 10) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(famt(r.db), 22) || '|'
                    || fpadl(famt(r.cb), 22) || '|' || fpadl(famt(r.net), 24) || '|'
                    || fpadl(famt(r.net_lcy), 24) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,14,22,22,24,24');
        IF v_row = 0 THEN
            po('    (aucun solde de grand livre en devise etrangere)');
        END IF;

        print_sub('20.3 Contribution des comptes clients a la position');
        tbl_line('4,10,16,24,24,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB COMPTES', 16) || '|'
            || fpadl('SOLDE EN DEVISE', 24) || '|' || fpadl('CONTRE-VALEUR LOCALE', 24) || '|'
            || fpadl('COURS IMPLICITE', 16) || '|');
        tbl_line('4,10,16,24,24,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT a.ccy, COUNT(*) nb,
                             SUM(NVL(a.acy_curr_balance, 0)) sacy,
                             SUM(NVL(a.lcy_curr_balance, 0)) slcy
                        FROM sttm_cust_account a
                       WHERE a.ccy <> k_lcy
                       GROUP BY a.ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(famt(r.sacy), 24) || '|' || fpadl(famt(r.slcy), 24) || '|'
                    || fpadl(CASE WHEN NVL(r.sacy, 0) = 0 THEN '-'
                                  ELSE TO_CHAR(ROUND(r.slcy / r.sacy, 4)) END, 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,24,24,16');
        po('  Le cours implicite est le rapport entre la contre-valeur locale et le');
        po('  solde en devise. Il doit rester proche du cours de cloture de la devise.');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 21. REEVALUATION DE CHANGE
    -- =========================================================
    print_section('21. REEVALUATION DE CHANGE (RVTB_ACC_REVAL)');
    BEGIN
        po('  La reevaluation periodique des positions en devises degage un resultat de');
        po('  change. C''est le point de rencontre entre le referentiel des cours et la');
        po('  comptabilite : le futur script d''audit y recalculera le gain ou la perte.');

        profile_table('RVTB_ACC_REVAL', NULL, 'PROFIL DES COLONNES : RVTB_ACC_REVAL');

        show_dist('21.1 Devise reevaluee (CCY)',            'rvtb_acc_reval', 'CCY',        NULL, 25);
        show_dist('21.2 Indicateur de reevaluation (REVAL_IND)',
                  'rvtb_acc_reval', 'REVAL_IND', NULL, 25);
        show_dist('21.3 Agence (BRANCH_CODE)',              'rvtb_acc_reval', 'BRANCH_CODE', NULL, 25);
        show_dist('21.4 Annee de reevaluation',             'rvtb_acc_reval',
                  'TO_CHAR(REVAL_DATE, ''YYYY'')', NULL, 30, 'V');
        show_dist('21.5 Indicateur de resultat de negoce (TRADING_PL_INDICATOR)',
                  'rvtb_acc_reval', 'TRADING_PL_INDICATOR', NULL, 25);

        print_sub('21.6 Resultat de reevaluation par devise et par annee');
        po('  Le resultat est la difference entre la nouvelle et l''ancienne');
        po('  contre-valeur locale de la position reevaluee.');
        po('');
        tbl_line('4,10,10,14,24,24,24,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpad('ANNEE', 10) || '|'
            || fpadl('NB LIGNES', 14) || '|' || fpadl('ANCIENNE C-VALEUR', 24) || '|'
            || fpadl('NOUVELLE C-VALEUR', 24) || '|' || fpadl('RESULTAT DE CHANGE', 24) || '|'
            || fpadl('COURS MOYEN', 16) || '|');
        tbl_line('4,10,10,14,24,24,24,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT v.ccy, TO_CHAR(v.reval_date, 'YYYY') an, COUNT(*) nb,
                             SUM(NVL(v.old_lcy_equivalent, 0)) anc,
                             SUM(NVL(v.new_lcy_equivalent, 0)) nouv,
                             SUM(NVL(v.new_lcy_equivalent, 0) - NVL(v.old_lcy_equivalent, 0)) res,
                             AVG(v.new_rate) tx
                        FROM rvtb_acc_reval v
                       GROUP BY v.ccy, TO_CHAR(v.reval_date, 'YYYY')
                       ORDER BY v.ccy, 2) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 60;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpad(r.an, 10) || '|'
                    || fpadl(fnum(r.nb), 14) || '|' || fpadl(famt(r.anc), 24) || '|'
                    || fpadl(famt(r.nouv), 24) || '|' || fpadl(famt(r.res), 24) || '|'
                    || fpadl(TO_CHAR(ROUND(r.tx, 6)), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,14,24,24,24,16');
        IF v_row = 0 THEN
            po('    (aucune ligne de reevaluation)');
        END IF;

        print_sub('21.7 Coherence entre position reevaluee, cours et contre-valeur');
        po('  Regle attendue : nouvelle contre-valeur = solde du compte x nouveau cours');
        po('  (ou solde divise par le cours selon la convention de cotation).');
        po('');
        BEGIN
            SELECT COUNT(*),
                   SUM(CASE WHEN ABS(NVL(v.new_lcy_equivalent, 0)
                                     - NVL(v.account_balance, 0) * NVL(v.new_rate, 0))
                                 <= GREATEST(1, ABS(NVL(v.new_lcy_equivalent, 0)) * 0.0001)
                            THEN 1 ELSE 0 END),
                   SUM(CASE WHEN ABS(NVL(v.new_lcy_equivalent, 0)
                                     - NVL(v.account_balance, 0) / NULLIF(v.new_rate, 0))
                                 <= GREATEST(1, ABS(NVL(v.new_lcy_equivalent, 0)) * 0.0001)
                            THEN 1 ELSE 0 END)
              INTO v_tot, v_cnt, v_cnt2
              FROM rvtb_acc_reval v
             WHERE NVL(v.new_rate, 0) <> 0;
            print_kv('Lignes de reevaluation testees',                fnum(v_tot));
            print_kv('Reconciliees par multiplication du cours',      fnum(v_cnt)  || '   ' || fpct(v_cnt, v_tot));
            print_kv('Reconciliees par division par le cours',        fnum(v_cnt2) || '   ' || fpct(v_cnt2, v_tot));
            print_kv('Non reconciliees',                              fnum(v_tot - GREATEST(v_cnt, v_cnt2)));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;

        po('');
        po('  >>> FIN DE LA PARTIE 4');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po(v_sep);
    po('   PARTIE 5/6 : LES TRANSFERTS INTERNATIONAUX');
    po(v_sep);
    po('  Les transferts avec l''etranger sont inclus dans le perimetre de la revue.');
    po('  Ils sont le principal vecteur des obligations de domiciliation, de');
    po('  justification et de rapatriement posees par la reglementation des changes.');
    po('  Cette partie lit le sous-ensemble des ecritures du module de transfert :');
    po('  prevoir plusieurs minutes d''execution.');

    -- =========================================================
    -- 22. DECOUVERTE DU MODULE DES TRANSFERTS ET DE LA MESSAGERIE
    -- =========================================================
    print_section('22. DECOUVERTE DU MODULE DES TRANSFERTS ET DE LA MESSAGERIE');
    BEGIN
        po('  Le dictionnaire fourni ne couvre ni le module de transfert de fonds ni la');
        po('  messagerie SWIFT. Comme pour le change, la decouverte passe par le');
        po('  dictionnaire Oracle.');

        print_sub('22.1 Familles de tables candidates');
        tbl_line('4,14,54,14,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('PREFIXE', 14) || '|' || fpad('FAMILLE', 54) || '|'
            || fpadl('NB TABLES', 14) || '|' || fpadl('LIGNES (STATS)', 18) || '|');
        tbl_line('4,14,54,14,18');
        v_row := 0;
        FOR p IN (
            SELECT 'FTT' pfx, 'Module Funds Transfer (transferts de fonds)' lib, 1 ord FROM DUAL UNION ALL
            SELECT 'MST',      'Messagerie SWIFT (messages entrants et sortants)',  2 FROM DUAL UNION ALL
            SELECT 'IST',      'Instructions de reglement (settlement)',            3 FROM DUAL UNION ALL
            SELECT 'PCT',      'Paiements et compensation',                         4 FROM DUAL UNION ALL
            SELECT 'PMT',      'Paiements',                                         5 FROM DUAL UNION ALL
            SELECT 'DET',      'Data Entry (saisies comptables directes)',          6 FROM DUAL UNION ALL
            SELECT 'RTT',      'Retail Teller (operations de guichet)',             7 FROM DUAL
            ORDER BY 3
        ) LOOP
            BEGIN
                SELECT COUNT(*), NVL(SUM(num_rows), 0) INTO v_cnt, v_tot
                  FROM all_tables
                 WHERE table_name LIKE p.pfx || '%'
                   AND owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA');
            EXCEPTION
                WHEN OTHERS THEN v_cnt := -1; v_tot := 0;
            END;
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(p.pfx || '%', 14) || '|' || fpad(p.lib, 54) || '|'
                || fpadl(CASE WHEN v_cnt < 0 THEN 'ERR' ELSE fnum(v_cnt) END, 14) || '|'
                || fpadl(fnum(v_tot), 18) || '|');
        END LOOP;
        tbl_line('4,14,54,14,18');

        print_sub('22.2 Tables de transfert et de messagerie porteuses de donnees');
        tbl_line('4,42,18,18');
        po('  |' || fpad('N#', 4) || '|' || fpad('TABLE', 42) || '|' || fpadl('LIGNES (STATS)', 18) || '|'
            || fpadl('DERNIERE ANALYSE', 18) || '|');
        tbl_line('4,42,18,18');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT table_name, num_rows, last_analyzed
                        FROM all_tables
                       WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                         AND (table_name LIKE 'FTT%' OR table_name LIKE 'MST%'
                              OR table_name LIKE 'IST%' OR table_name LIKE 'PCT%'
                              OR table_name LIKE 'PMT%')
                         AND NVL(num_rows, 0) > 0
                       ORDER BY num_rows DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 60;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.table_name, 42) || '|'
                    || fpadl(fnum(r.num_rows), 18) || '|' || fpadl(fdt(r.last_analyzed), 18) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,42,18,18');
        IF v_row = 0 THEN
            po('    (aucune table de transfert ou de messagerie alimentee selon les statistiques)');
        END IF;

        print_sub('22.3 Tables dont le nom evoque le transfert, le message ou le beneficiaire');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT table_name, num_rows
                        FROM all_tables
                       WHERE owner = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
                         AND (table_name LIKE '%SWIFT%' OR table_name LIKE '%MSG%'
                              OR table_name LIKE '%TRANSFER%' OR table_name LIKE '%BENEF%'
                              OR table_name LIKE '%REMIT%' OR table_name LIKE '%SETTLE%')
                         AND NVL(num_rows, 0) > 0
                       ORDER BY num_rows DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 40;
                print_kv('  ' || r.table_name, fnum(r.num_rows) || ' lignes');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        IF v_row = 0 THEN
            po('    (aucune table correspondante, ou statistiques absentes)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 23. CARTOGRAPHIE DES ECRITURES DU MODULE DE TRANSFERT
    -- =========================================================
    print_section('23. CARTOGRAPHIE DES ECRITURES DU MODULE DE TRANSFERT');
    BEGIN
        print_kv('Module de transfert retenu', k_mod_ft);
        po('  Le tableau ci-dessous rappelle la repartition de TOUTES les ecritures par');
        po('  module. Si les transferts internationaux de cette banque ne sont pas dans');
        po('  le module retenu, corriger la constante k_mod_ft en tete du script.');
        po('');
        tbl_line('4,10,18,14,22,16,16,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpadl('NB ECRITURES', 18) || '|'
            || fpadl('NB DEVISES', 14) || '|' || fpadl('TOTAL LCY', 22) || '|'
            || fpad('1ERE ECRIT.', 16) || '|' || fpad('DER. ECRIT.', 16) || '|'
            || fpadl('% NB', 12) || '|');
        tbl_line('4,10,18,14,22,16,16,12');
        v_row := 0;
        BEGIN
            SELECT COUNT(*) INTO v_tot FROM actb_history;
            FOR r IN (SELECT h.module, COUNT(*) nb, COUNT(DISTINCT h.ac_ccy) nbc,
                             SUM(NVL(h.lcy_amount, 0)) mt, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                        FROM actb_history h
                       GROUP BY h.module
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module, 10) || '|'
                    || fpadl(fnum(r.nb), 18) || '|' || fpadl(fnum(r.nbc), 14) || '|'
                    || fpadl(fmio(r.mt), 22) || '|' || fpad(fdt(r.d1), 16) || '|'
                    || fpad(fdt(r.d2), 16) || '|' || fpadl(fpct(r.nb, v_tot), 12) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,18,14,22,16,16,12');

        print_sub('23.1 Profil des colonnes sur le perimetre des transferts');
        profile_table('ACTB_HISTORY', 'MODULE = ''' || k_mod_ft || '''',
                      'PROFIL DES COLONNES : ACTB_HISTORY  [module ' || k_mod_ft || ']');

        print_sub('23.2 Analyse multi-axes des ecritures de transfert');
        v_dim := '~';
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT ord, dim, val, k, tot FROM (
                    SELECT dd.ord AS ord,
                           dd.dim AS dim,
                           NVL(TRIM(CASE dd.dim
                                WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                                WHEN 'DEVISE'         THEN h.ac_ccy
                                WHEN 'EVENT'          THEN h.event
                                WHEN 'TRN_CODE'       THEN h.trn_code
                                WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                                WHEN 'SENS'           THEN h.drcr_ind
                                WHEN 'PRODUIT'        THEN h.product
                                WHEN 'AGENCE'         THEN h.ac_branch
                                WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                                WHEN 'SAISI_PAR'      THEN h.user_id
                                WHEN 'AUTORISE_PAR'   THEN h.auth_id
                                WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL
                                                                THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                           END), '(vide)') AS val,
                           COUNT(*) AS k,
                           SUM(NVL(h.lcy_amount, 0)) AS tot,
                           ROW_NUMBER() OVER (PARTITION BY dd.dim ORDER BY COUNT(*) DESC) AS rn
                    FROM actb_history h
                    CROSS JOIN (
                        SELECT 'ANNEE' dim, 1 ord FROM DUAL UNION ALL
                        SELECT 'DEVISE',       2 FROM DUAL UNION ALL
                        SELECT 'EVENT',        3 FROM DUAL UNION ALL
                        SELECT 'TRN_CODE',     4 FROM DUAL UNION ALL
                        SELECT 'AMOUNT_TAG',   5 FROM DUAL UNION ALL
                        SELECT 'SENS',         6 FROM DUAL UNION ALL
                        SELECT 'PRODUIT',      7 FROM DUAL UNION ALL
                        SELECT 'AGENCE',       8 FROM DUAL UNION ALL
                        SELECT 'CLIENT_OU_GL', 9 FROM DUAL UNION ALL
                        SELECT 'SAISI_PAR',   10 FROM DUAL UNION ALL
                        SELECT 'AUTORISE_PAR',11 FROM DUAL UNION ALL
                        SELECT 'REF_EXTERNE', 12 FROM DUAL
                    ) dd
                    WHERE h.module = k_mod_ft
                    GROUP BY dd.ord, dd.dim,
                             CASE dd.dim
                                WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                                WHEN 'DEVISE'         THEN h.ac_ccy
                                WHEN 'EVENT'          THEN h.event
                                WHEN 'TRN_CODE'       THEN h.trn_code
                                WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                                WHEN 'SENS'           THEN h.drcr_ind
                                WHEN 'PRODUIT'        THEN h.product
                                WHEN 'AGENCE'         THEN h.ac_branch
                                WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                                WHEN 'SAISI_PAR'      THEN h.user_id
                                WHEN 'AUTORISE_PAR'   THEN h.auth_id
                                WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL
                                                                THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                             END
                ) WHERE rn <= 15
                ORDER BY ord, k DESC
            ) LOOP
                IF v_dim <> r.dim THEN
                    v_dim := r.dim;
                    print_sub('23.2.' || TO_CHAR(r.ord) || ' Axe . ' || r.dim);
                    tbl_line('34,16,22');
                    po('  |' || fpad('VALEUR', 34) || '|' || fpadl('NB ECRITURES', 16) || '|'
                        || fpadl('TOTAL LCY', 22) || '|');
                    tbl_line('34,16,22');
                END IF;
                po('  |' || fpad(r.val, 34) || '|' || fpadl(fnum(r.k), 16) || '|'
                    || fpadl(fmio(r.tot), 22) || '|');
                v_row := v_row + 1;
            END LOOP;
            IF v_row > 0 THEN
                tbl_line('34,16,22');
            ELSE
                po('    (aucune ecriture dans le module ' || k_mod_ft || ')');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 24. QUALIFICATION DES TRANSFERTS INTERNATIONAUX
    -- =========================================================
    print_section('24. QUALIFICATION DES TRANSFERTS INTERNATIONAUX');
    BEGIN
        po('  FLEXCUBE ne porte pas d''indicateur "transfert international". Il faut le');
        po('  reconstituer. Trois indices sont disponibles dans la comptabilite :');
        po('    - l''operation est libellee en devise etrangere ;');
        po('    - elle mouvemente un general en devise etrangere (correspondant) ;');
        po('    - elle porte une reference externe (message recu ou emis).');
        po('  Le tableau croise ces indices au niveau de l''operation, pas de l''ecriture.');

        print_sub('24.1 Croisement des indices, au niveau de l''operation');
        tbl_line('4,20,20,20,16,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 20) || '|' || fpad('CORRESPONDANT', 20) || '|'
            || fpad('REF. EXTERNE', 20) || '|' || fpadl('NB OPERATIONS', 16) || '|'
            || fpadl('TOTAL LCY', 22) || '|' || fpadl('% OPERATIONS', 16) || '|');
        tbl_line('4,20,20,20,16,22,16');
        v_row := 0;
        BEGIN
            SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_tot
              FROM actb_history h WHERE h.module = k_mod_ft;
            FOR r IN (
                SELECT CASE WHEN n_fx > 0 THEN 'devise etrangere' ELSE 'monnaie locale' END dev,
                       CASE WHEN n_corr > 0 THEN 'general en devise' ELSE 'aucun' END corr,
                       CASE WHEN n_ext > 0 THEN 'renseignee' ELSE 'absente' END ext,
                       COUNT(*) nb, SUM(mt) mt
                  FROM (SELECT h.trn_ref_no,
                               SUM(CASE WHEN h.ac_ccy <> k_lcy THEN 1 ELSE 0 END) n_fx,
                               SUM(CASE WHEN h.cust_gl = 'G' AND h.ac_ccy <> k_lcy
                                        THEN 1 ELSE 0 END) n_corr,
                               SUM(CASE WHEN TRIM(h.external_ref_no) IS NOT NULL
                                        THEN 1 ELSE 0 END) n_ext,
                               MAX(NVL(h.lcy_amount, 0)) mt
                          FROM actb_history h
                         WHERE h.module = k_mod_ft
                         GROUP BY h.trn_ref_no)
                 GROUP BY CASE WHEN n_fx > 0 THEN 'devise etrangere' ELSE 'monnaie locale' END,
                          CASE WHEN n_corr > 0 THEN 'general en devise' ELSE 'aucun' END,
                          CASE WHEN n_ext > 0 THEN 'renseignee' ELSE 'absente' END
                 ORDER BY COUNT(*) DESC
            ) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.dev, 20) || '|' || fpad(r.corr, 20) || '|'
                    || fpad(r.ext, 20) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 22) || '|'
                    || fpadl(fpct(r.nb, v_tot), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,20,20,20,16,22,16');
        po('  Une operation cumulant devise etrangere et general en devise est un');
        po('  transfert international quasi certain. Une operation en monnaie locale');
        po('  sans correspondant est un virement domestique.');

        print_sub('24.2 Transferts par devise');
        tbl_line('4,10,16,22,22,16,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpadl('NB OPERATIONS', 16) || '|'
            || fpadl('MONTANT DEVISE', 22) || '|' || fpadl('CONTRE-VALEUR', 22) || '|'
            || fpad('1ERE OPER.', 16) || '|' || fpad('DER. OPER.', 16) || '|');
        tbl_line('4,10,16,22,22,16,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.ac_ccy ccy, COUNT(DISTINCT h.trn_ref_no) nb,
                             SUM(NVL(h.fcy_amount, 0)) fcy, SUM(NVL(h.lcy_amount, 0)) lcy,
                             MIN(h.trn_dt) d1, MAX(h.trn_dt) d2
                        FROM actb_history h
                       WHERE h.module = k_mod_ft
                       GROUP BY h.ac_ccy
                       ORDER BY COUNT(*) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 30;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(famt(r.fcy), 22) || '|' || fpadl(fmio(r.lcy), 22) || '|'
                    || fpad(fdt(r.d1), 16) || '|' || fpad(fdt(r.d2), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,22,22,16,16');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;


    -- =========================================================
    -- 25. FLUX ENTRANTS ET SORTANTS
    -- =========================================================
    print_section('25. FLUX ENTRANTS ET SORTANTS');
    BEGIN
        po('  Le sens du flux se lit sur le compte du client : un debit du compte client');
        po('  correspond a un transfert emis, un credit a un transfert recu. La');
        po('  distinction porte l''obligation de rapatriement pour les flux entrants et');
        po('  l''obligation de justification pour les flux sortants.');

        print_sub('25.1 Sens des flux par devise, sur les comptes clients');
        tbl_line('4,10,16,16,22,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('DEVISE', 10) || '|' || fpad('SENS', 16) || '|'
            || fpadl('NB ECRITURES', 16) || '|' || fpadl('MONTANT DEVISE', 22) || '|'
            || fpadl('CONTRE-VALEUR', 22) || '|' || fpadl('NB COMPTES', 16) || '|');
        tbl_line('4,10,16,16,22,22,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT h.ac_ccy ccy,
                             CASE h.drcr_ind WHEN 'D' THEN 'EMIS (debit)'
                                             WHEN 'C' THEN 'RECU (credit)'
                                             ELSE h.drcr_ind END sens,
                             COUNT(*) nb, SUM(NVL(h.fcy_amount, 0)) fcy,
                             SUM(NVL(h.lcy_amount, 0)) lcy, COUNT(DISTINCT h.ac_no) nbc
                        FROM actb_history h
                       WHERE h.module = k_mod_ft
                         AND h.cust_gl = 'A'
                       GROUP BY h.ac_ccy, h.drcr_ind
                       ORDER BY SUM(NVL(h.lcy_amount, 0)) DESC) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 40;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ccy, 10) || '|' || fpad(r.sens, 16) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(famt(r.fcy), 22) || '|'
                    || fpadl(fmio(r.lcy), 22) || '|' || fpadl(fnum(r.nbc), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,16,16,22,22,16');

        print_sub('25.2 Evolution annuelle des flux en devises');
        tbl_line('4,10,10,16,22,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('ANNEE', 10) || '|' || fpad('DEVISE', 10) || '|'
            || fpadl('NB ECRITURES', 16) || '|' || fpadl('EMIS (DEBIT)', 22) || '|'
            || fpadl('RECU (CREDIT)', 22) || '|' || fpadl('SOLDE NET', 22) || '|');
        tbl_line('4,10,10,16,22,22,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT TO_CHAR(h.trn_dt, 'YYYY') an, h.ac_ccy ccy, COUNT(*) nb,
                             SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                             SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                        FROM actb_history h
                       WHERE h.module = k_mod_ft
                         AND h.cust_gl = 'A'
                         AND h.ac_ccy <> k_lcy
                       GROUP BY TO_CHAR(h.trn_dt, 'YYYY'), h.ac_ccy
                       ORDER BY 1, 2) LOOP
                v_row := v_row + 1;
                EXIT WHEN v_row > 80;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.an, 10) || '|' || fpad(r.ccy, 10) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.deb), 22) || '|'
                    || fpadl(fmio(r.cre), 22) || '|' || fpadl(fmio(r.cre - r.deb), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,10,10,16,22,22,22');
        IF v_row = 0 THEN
            po('    (aucun flux en devise etrangere sur les comptes clients)');
        END IF;

        print_sub('25.3 Generaux mouvementes par les transferts');
        tbl_line('4,22,40,10,16,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('GENERAL', 22) || '|' || fpad('LIBELLE', 40) || '|'
            || fpad('DEVISE', 10) || '|' || fpadl('NB ECRITURES', 16) || '|'
            || fpadl('TOTAL DEBIT', 22) || '|' || fpadl('TOTAL CREDIT', 22) || '|');
        tbl_line('4,22,40,10,16,22,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT h.ac_no, MAX(h.ac_ccy) ccy, COUNT(*) nb,
                               (SELECT MAX(a.ac_gl_desc) FROM sttb_account a
                                 WHERE a.ac_gl_no = h.ac_no) lib,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                          FROM actb_history h
                         WHERE h.module = k_mod_ft
                           AND h.cust_gl = 'G'
                         GROUP BY h.ac_no
                         ORDER BY COUNT(*) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 40) || '|'
                    || fpad(r.ccy, 10) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.deb), 22) || '|'
                    || fpadl(fmio(r.cre), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,22,40,10,16,22,22');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 26. SEUILS REGLEMENTAIRES ET FRACTIONNEMENT
    -- =========================================================
    print_section('26. SEUILS REGLEMENTAIRES ET FRACTIONNEMENT DES OPERATIONS');
    BEGIN
        print_kv('Seuil de justification et de domiciliation',
                 TO_CHAR(k_s_justif, 'FM999G999G999') || ' ' || k_lcy);
        print_kv('Bande examinee sous le seuil',
                 TO_CHAR(ROUND(k_bande * 100)) || ' pourcent, soit a partir de '
                 || TO_CHAR(ROUND(k_s_justif * (1 - k_bande)), 'FM999G999G999') || ' ' || k_lcy);
        po('  Le montant d''une operation est pris egal au plus grand montant en');
        po('  contre-valeur locale parmi ses ecritures.');

        print_sub('26.1 Distribution des operations de transfert par tranche de montant');
        tbl_line('4,34,16,14,22,14');
        po('  |' || fpad('N#', 4) || '|' || fpad('TRANCHE DE MONTANT', 34) || '|'
            || fpadl('NB OPERATIONS', 16) || '|' || fpadl('% NB', 14) || '|'
            || fpadl('TOTAL LCY', 22) || '|' || fpadl('% MONTANT', 14) || '|');
        tbl_line('4,34,16,14,22,14');
        v_row := 0;
        BEGIN
            SELECT COUNT(*), SUM(mt) INTO v_tot, v_mt
              FROM (SELECT MAX(NVL(h.lcy_amount, 0)) mt
                      FROM actb_history h
                     WHERE h.module = k_mod_ft
                     GROUP BY h.trn_ref_no);
            FOR r IN (
                SELECT tr, COUNT(*) nb, SUM(mt) somme
                  FROM (SELECT CASE
                                 WHEN mt <  k_s_justif * (1 - k_bande) THEN '1. sous la bande'
                                 WHEN mt <  k_s_justif                 THEN '2. dans la bande sous le seuil'
                                 WHEN mt =  k_s_justif                 THEN '3. exactement au seuil'
                                 WHEN mt <  k_s_justif * 2             THEN '4. de 1 a 2 fois le seuil'
                                 WHEN mt <  k_s_justif * 10            THEN '5. de 2 a 10 fois le seuil'
                                 ELSE                                       '6. plus de 10 fois le seuil'
                               END tr, mt
                          FROM (SELECT MAX(NVL(h.lcy_amount, 0)) mt
                                  FROM actb_history h
                                 WHERE h.module = k_mod_ft
                                 GROUP BY h.trn_ref_no))
                 GROUP BY tr ORDER BY tr
            ) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.tr, 34) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fpct(r.nb, v_tot), 14) || '|' || fpadl(fmio(r.somme), 22) || '|'
                    || fpadl(fpct(r.somme, v_mt), 14) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,34,16,14,22,14');
        po('  Une concentration anormale dans la tranche 2 est l''indice d''un');
        po('  fractionnement destine a rester sous le seuil de justification.');

        print_sub('26.2 Repartition fine des operations autour du seuil');
        tbl_line('4,34,16,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('PALIER (en % du seuil)', 34) || '|'
            || fpadl('NB OPERATIONS', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
        tbl_line('4,34,16,22');
        v_row := 0;
        BEGIN
            FOR r IN (
                SELECT pal, COUNT(*) nb, SUM(mt) somme
                  FROM (SELECT LEAST(FLOOR(mt / (k_s_justif / 20)) * 5, 200) pal, mt
                          FROM (SELECT MAX(NVL(h.lcy_amount, 0)) mt
                                  FROM actb_history h
                                 WHERE h.module = k_mod_ft
                                 GROUP BY h.trn_ref_no)
                         WHERE mt BETWEEN k_s_justif * 0.5 AND k_s_justif * 2)
                 GROUP BY pal ORDER BY pal
            ) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
                    || fpad('de ' || TO_CHAR(r.pal) || ' a ' || TO_CHAR(r.pal + 5) || ' %', 34) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.somme), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,34,16,22');
        IF v_row = 0 THEN
            po('    (aucune operation dans la plage examinee)');
        END IF;

        print_sub('26.3 Comptes cumulant plusieurs operations sous le seuil le meme mois');
        tbl_line('4,22,10,12,16,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('COMPTE', 22) || '|' || fpad('DEVISE', 10) || '|'
            || fpad('MOIS', 12) || '|' || fpadl('NB OPERATIONS', 16) || '|'
            || fpadl('TOTAL LCY', 22) || '|' || fpadl('MOYENNE', 16) || '|');
        tbl_line('4,22,10,12,16,22,16');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT ac_no, ccy, mois, COUNT(*) nb, SUM(mt) somme, AVG(mt) moy
                          FROM (SELECT h.ac_no, MAX(h.ac_ccy) ccy,
                                       TO_CHAR(MIN(h.trn_dt), 'YYYY-MM') mois,
                                       MAX(NVL(h.lcy_amount, 0)) mt
                                  FROM actb_history h
                                 WHERE h.module = k_mod_ft
                                   AND h.cust_gl = 'A'
                                 GROUP BY h.ac_no, h.trn_ref_no)
                         WHERE mt BETWEEN k_s_justif * (1 - k_bande) AND k_s_justif
                         GROUP BY ac_no, ccy, mois
                        HAVING COUNT(*) >= 3
                         ORDER BY COUNT(*) DESC, SUM(mt) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.ccy, 10) || '|'
                    || fpad(r.mois, 12) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(famt(r.somme), 22) || '|'
                    || fpadl(famt(r.moy), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,22,10,12,16,22,16');
        IF v_row = 0 THEN
            po('    (aucun compte ne cumule trois operations ou plus dans la bande le meme mois)');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 27. DONNEURS D'ORDRE ET BENEFICIAIRES
    -- =========================================================
    print_section('27. DONNEURS D''ORDRE ET BENEFICIAIRES DES TRANSFERTS');
    BEGIN
        po('  Le rattachement des transferts aux clients passe par le compte mouvemente.');
        po('  Il permet de relier la revue des changes au dispositif de connaissance du');
        po('  client deja audite par ailleurs.');

        print_sub('27.1 Les 30 clients les plus actifs en transfert');
        tbl_line('4,14,32,8,8,16,22,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 14) || '|' || fpad('CLIENT', 32) || '|'
            || fpad('TYPE', 8) || '|' || fpad('PAYS', 8) || '|' || fpadl('NB OPERATIONS', 16) || '|'
            || fpadl('EMIS (DEBIT)', 22) || '|' || fpadl('RECU (CREDIT)', 22) || '|');
        tbl_line('4,14,32,8,8,16,22,22');
        v_row := 0;
        BEGIN
            FOR r IN (SELECT * FROM (
                        SELECT a.cust_no,
                               MAX(c.customer_name1) nom, MAX(c.customer_type) typ,
                               MAX(c.country) pays,
                               COUNT(DISTINCT h.trn_ref_no) nb,
                               SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                               SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                          FROM actb_history h
                          JOIN sttm_cust_account a ON a.cust_ac_no = h.ac_no
                          JOIN sttm_customer c ON c.customer_no = a.cust_no
                         WHERE h.module = k_mod_ft
                           AND h.cust_gl = 'A'
                         GROUP BY a.cust_no
                         ORDER BY SUM(NVL(h.lcy_amount, 0)) DESC
                      ) WHERE ROWNUM <= 30) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.cust_no, 14) || '|' || fpad(r.nom, 32) || '|'
                    || fpad(r.typ, 8) || '|' || fpad(r.pays, 8) || '|' || fpadl(fnum(r.nb), 16) || '|'
                    || fpadl(fmio(r.deb), 22) || '|' || fpadl(fmio(r.cre), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,14,32,8,8,16,22,22');

        print_sub('27.2 Transferts par pays du client');
        tbl_line('4,12,16,16,22,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('PAYS', 12) || '|' || fpadl('NB CLIENTS', 16) || '|'
            || fpadl('NB OPERATIONS', 16) || '|' || fpadl('TOTAL LCY', 22) || '|'
            || fpadl('% OPERATIONS', 16) || '|');
        tbl_line('4,12,16,16,22,16');
        v_row := 0;
        BEGIN
            SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_tot
              FROM actb_history h WHERE h.module = k_mod_ft AND h.cust_gl = 'A';
            FOR r IN (SELECT * FROM (
                        SELECT c.country pays, COUNT(DISTINCT a.cust_no) nbc,
                               COUNT(DISTINCT h.trn_ref_no) nb,
                               SUM(NVL(h.lcy_amount, 0)) mt
                          FROM actb_history h
                          JOIN sttm_cust_account a ON a.cust_ac_no = h.ac_no
                          JOIN sttm_customer c ON c.customer_no = a.cust_no
                         WHERE h.module = k_mod_ft
                           AND h.cust_gl = 'A'
                         GROUP BY c.country
                         ORDER BY COUNT(DISTINCT h.trn_ref_no) DESC
                      ) WHERE ROWNUM <= 40) LOOP
                v_row := v_row + 1;
                po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.pays, 12) || '|' || fpadl(fnum(r.nbc), 16) || '|'
                    || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.mt), 22) || '|'
                    || fpadl(fpct(r.nb, v_tot), 16) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,12,16,16,22,16');

        print_sub('27.3 Couverture KYC des clients transferant');
        BEGIN
            SELECT COUNT(DISTINCT a.cust_no),
                   COUNT(DISTINCT CASE WHEN TRIM(c.kyc_ref_no) IS NULL THEN a.cust_no END),
                   COUNT(DISTINCT CASE WHEN TRIM(c.country) IS NULL THEN a.cust_no END),
                   COUNT(DISTINCT CASE WHEN NVL(TRIM(c.frozen), 'N') = 'Y' THEN a.cust_no END)
              INTO v_cnt, v_cnt2, v_cnt3, v_row
              FROM actb_history h
              JOIN sttm_cust_account a ON a.cust_ac_no = h.ac_no
              JOIN sttm_customer c ON c.customer_no = a.cust_no
             WHERE h.module = k_mod_ft
               AND h.cust_gl = 'A';
            print_kv('Clients ayant emis ou recu un transfert', fnum(v_cnt));
            print_kv('Dont sans dossier KYC',                   fnum(v_cnt2) || '   ' || fpct(v_cnt2, v_cnt));
            print_kv('Dont sans pays renseigne',                fnum(v_cnt3) || '   ' || fpct(v_cnt3, v_cnt));
            print_kv('Dont geles',                              fnum(v_row)  || '   ' || fpct(v_row, v_cnt));
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;

        po('');
        po('  >>> FIN DE LA PARTIE 5');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po(v_sep);
    po('   PARTIE 6/6 : CADRE CEMAC ET CONTROLES CANDIDATS');
    po(v_sep);

    -- =========================================================
    -- 28. RAPPEL DU CADRE REGLEMENTAIRE
    -- =========================================================
    print_section('28. CADRE REGLEMENTAIRE DE REFERENCE');
    BEGIN
        po('  AVERTISSEMENT');
        po('    Ce rappel a ete etabli a partir de sources secondaires. Le texte officiel');
        po('    n''a pas pu etre consulte depuis l''environnement de redaction du script.');
        po('    Les numeros d''articles et les montants doivent etre confirmes sur le');
        po('    Journal Officiel de la CEMAC avant toute citation dans un rapport d''audit.');
        po('');
        po('  TEXTE PRINCIPAL');
        po('    Reglement n 02/18/CEMAC/UMAC/CM du 21 decembre 2018 portant reglementation');
        po('    des changes dans la CEMAC. Adopte a Yaounde en session extraordinaire du');
        po('    Comite Ministeriel de l''UMAC. Entree en vigueur le 1er mars 2019, avec un');
        po('    delai de mise en conformite de six mois expirant le 30 aout 2019.');
        po('    Il remplace le reglement de 2000.');
        po('');
        po('  TEXTES D''APPLICATION');
        po('    Instructions du Gouverneur de la BEAC du 10 juin 2019, dont notamment .');
        po('      Instruction n 001  importation de billets de banque par les');
        po('                         etablissements de credit');
        po('      Instruction n 002  tarification des operations de transfert');
        po('      Instruction n 003  retrocession des devises a la BEAC par les');
        po('                         etablissements de credit');
        po('      Instruction n 004  conditions de detention d''avoirs en devises chez');
        po('                         les correspondants etrangers');
        po('      Instruction n 005  ouverture et fonctionnement des comptes en devises');
        po('                         des residents et des non-residents');
        po('      Instruction n 006  declaration et domiciliation des exportations de');
        po('                         biens et services, rapatriement des recettes');
        po('      Instruction n 007  declaration, domiciliation et reglement des');
        po('                         importations de biens et services');
        po('    Deux instructions complementaires portent sur le change manuel et sur le');
        po('    statut des etablissements sous-delegues en change manuel.');
        po('');
        po('  PRINCIPES STRUCTURANTS RETENUS POUR LA CONSTRUCTION DES TESTS');
        po('    1. Monopole de la Banque Centrale sur les reserves de change et');
        po('       obligation de retrocession des devises a la BEAC.');
        po('    2. Obligation de rapatriement des recettes d''exportation dans un delai');
        po('       maximal de ' || TO_CHAR(k_j_rapat) || ' jours a compter de l''exportation effective.');
        po('    3. Domiciliation obligatoire aupres d''un etablissement de credit de la');
        po('       CEMAC des operations d''importation et d''exportation de biens et de');
        po('       services d''un montant egal ou superieur a '
            || TO_CHAR(k_s_justif, 'FM999G999G999') || ' ' || k_lcy || '.');
        po('    4. Obligation de justification des reglements avec l''etranger au dela du');
        po('       meme seuil, et exigence de facture ou document equivalent en deca.');
        po('    5. Encadrement de la detention d''avoirs en devises chez les');
        po('       correspondants etrangers.');
        po('    6. Encadrement de l''ouverture et du fonctionnement des comptes en devises');
        po('       des residents et des non-residents.');
        po('    7. Communication periodique a la Banque Centrale des releves de comptes');
        po('       de correspondants et des positions globales de change. La position');
        po('       exterieure des banques fait l''objet d''une remontee decadaire.');
        po('    8. Plafonnement des paiements et retraits par carte hors zone CEMAC a');
        po('       ' || TO_CHAR(k_s_justif, 'FM999G999G999') || ' ' || k_lcy
            || ' par personne et par voyage, et des paiements a distance');
        po('       a ' || TO_CHAR(k_s_carte, 'FM999G999G999') || ' ' || k_lcy || ' par personne et par mois.');
        po('    9. Declaration en douane des sommes en especes egales ou superieures a');
        po('       ' || TO_CHAR(k_s_justif, 'FM999G999G999') || ' ' || k_lcy || ' ou de leur equivalent en devises.');
        po('   10. Controle des intermediaires agrees confie a la Commission Bancaire de');
        po('       l''Afrique Centrale, par delegation de la Banque Centrale ; sanctions');
        po('       administratives relevant de la seule BEAC.');
        po('');
        po('  OBLIGATIONS PROPRES AUX TRANSFERTS INTERNATIONAUX');
        po('    Les transferts avec l''etranger etant inclus dans le perimetre de la');
        po('    revue, les obligations suivantes structurent la partie 5 du rapport.');
        po('    a. Les reglements des transactions avec l''etranger au dela du seuil de');
        po('       ' || TO_CHAR(k_s_justif, 'FM999G999G999') || ' ' || k_lcy
            || ' doivent transiter par un intermediaire agree.');
        po('    b. Tout transfert doit etre appuye des justificatifs requis. L''execution');
        po('       d''un transfert au profit d''un agent economique n''ayant pas apure');
        po('       l''ensemble de ses dossiers de domiciliation d''importation est');
        po('       assimilee a un transfert sans justificatifs, sanctionnee par');
        po('       l''article 164 du Reglement.');
        po('    c. Les depenses d''importation de services d''un montant egal ou superieur');
        po('       au seuil doivent etre domiciliees aupres d''un etablissement de credit');
        po('       de la CEMAC et declarees a la Banque Centrale.');
        po('    d. Les recettes d''exportation doivent etre rapatriees dans le delai de');
        po('       ' || TO_CHAR(k_j_rapat) || ' jours et cedees selon les quotites en vigueur.');
        po('    e. L''instruction n 002 encadre la tarification des operations de');
        po('       transfert au sein de la CEMAC.');
        po('    f. Les sanctions administratives applicables aux prestataires de services');
        po('       de paiement sont prevues aux articles 167, 171 et 172 du Reglement.');
        po('');
        po('  CE QUE LA BASE PEUT ET NE PEUT PAS PROUVER SUR LES TRANSFERTS');
        po('    FLEXCUBE porte le flux comptable, la devise, le cours, le compte');
        po('    mouvemente, l''horodatage et l''identite des operateurs. Il ne porte ni le');
        po('    dossier de domiciliation, ni la facture, ni la declaration a la BEAC.');
        po('    Les tests de la partie 5 mesurent donc la COHERENCE et la TRACABILITE du');
        po('    flux, et identifient les operations a rapprocher des dossiers papier :');
        po('    ils ne concluent pas seuls a la conformite documentaire.');
        po('');
        po('  PORTEE POUR L''AUDIT DES DONNEES');
        po('    Une partie de ces obligations ne se verifie pas dans FLEXCUBE (dossiers');
        po('    de domiciliation, declarations douanieres, etats decadaires transmis a la');
        po('    BEAC). Le script d''audit se concentrera sur ce que la base peut prouver :');
        po('    le cours applique, la coherence des contre-valeurs, la tenue des comptes');
        po('    en devises, les avoirs chez les correspondants, la position de change et');
        po('    la piste d''audit des operations.');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    -- =========================================================
    -- 29. CONTROLES CANDIDATS
    -- =========================================================
    print_section('29. CONTROLES PREPARATOIRES : DIMENSIONNEMENT DES FUTURS TESTS');
    BEGIN
        po('  Chaque ligne est un test candidat du futur script d''audit du change.');
        po('  Le chiffre indique le nombre de cas concernes ; il permettra de retenir');
        po('  les tests pertinents et de calibrer les seuils.');

        print_sub('23.1 Sur les ecritures comptables (une seule lecture de la table)');
        tbl_line('4,72,16,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 72) || '|' || fpadl('NB CAS', 16) || '|'
            || fpadl('MONTANT LCY', 22) || '|');
        tbl_line('4,72,16,22');
        BEGIN
            FOR r IN (
                SELECT
                  SUM(CASE WHEN h.ac_ccy <> k_lcy THEN 1 ELSE 0 END) n0,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy THEN NVL(h.lcy_amount, 0) ELSE 0 END) m0,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.exch_rate, 0) = 0
                           THEN 1 ELSE 0 END) n1,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.exch_rate, 0) = 0
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m1,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.fcy_amount, 0) = 0
                           THEN 1 ELSE 0 END) n2,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.fcy_amount, 0) = 0
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m2,
                  SUM(CASE WHEN h.ac_ccy = k_lcy AND NVL(h.exch_rate, 1) <> 1
                           THEN 1 ELSE 0 END) n3,
                  SUM(CASE WHEN h.ac_ccy = k_lcy AND NVL(h.exch_rate, 1) <> 1
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m3,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.fcy_amount, 0) <> 0
                             AND NVL(h.exch_rate, 0) <> 0
                             AND ABS(NVL(h.lcy_amount, 0) - NVL(h.fcy_amount, 0) * NVL(h.exch_rate, 0))
                                 > GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                             AND ABS(NVL(h.lcy_amount, 0) - NVL(h.fcy_amount, 0) / NULLIF(h.exch_rate, 0))
                                 > GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                           THEN 1 ELSE 0 END) n4,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.fcy_amount, 0) <> 0
                             AND NVL(h.exch_rate, 0) <> 0
                             AND ABS(NVL(h.lcy_amount, 0) - NVL(h.fcy_amount, 0) * NVL(h.exch_rate, 0))
                                 > GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                             AND ABS(NVL(h.lcy_amount, 0) - NVL(h.fcy_amount, 0) / NULLIF(h.exch_rate, 0))
                                 > GREATEST(1, ABS(NVL(h.lcy_amount, 0)) * 0.0001)
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m4,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.lcy_amount, 0) >= k_s_justif
                           THEN 1 ELSE 0 END) n5,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.lcy_amount, 0) >= k_s_justif
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m5,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.lcy_amount, 0) >= k_s_justif
                             AND TRIM(h.external_ref_no) IS NULL
                           THEN 1 ELSE 0 END) n6,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.lcy_amount, 0) >= k_s_justif
                             AND TRIM(h.external_ref_no) IS NULL
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m6,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND h.user_id = h.auth_id
                             AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM'
                           THEN 1 ELSE 0 END) n7,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND h.user_id = h.auth_id
                             AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM'
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m7,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy
                             AND (TRUNC(h.trn_dt) - TRUNC(h.trn_dt, 'IW') + 1) IN (6, 7)
                           THEN 1 ELSE 0 END) n8,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy
                             AND (TRUNC(h.trn_dt) - TRUNC(h.trn_dt, 'IW') + 1) IN (6, 7)
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m8,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND TRUNC(h.value_dt) < TRUNC(h.trn_dt)
                           THEN 1 ELSE 0 END) n9,
                  SUM(CASE WHEN h.ac_ccy <> k_lcy AND TRUNC(h.value_dt) < TRUNC(h.trn_dt)
                           THEN NVL(h.lcy_amount, 0) ELSE 0 END) m9
                FROM actb_history h
            ) LOOP
                po('  |' || fpadl('1', 4) || '|'
                    || fpad('Ecritures en devise etrangere (population de reference)', 72) || '|'
                    || fpadl(fnum(r.n0), 16) || '|' || fpadl(fmio(r.m0), 22) || '|');
                po('  |' || fpadl('2', 4) || '|'
                    || fpad('Ecriture en devise sans cours de change renseigne', 72) || '|'
                    || fpadl(fnum(r.n1), 16) || '|' || fpadl(fmio(r.m1), 22) || '|');
                po('  |' || fpadl('3', 4) || '|'
                    || fpad('Ecriture en devise sans montant en devise', 72) || '|'
                    || fpadl(fnum(r.n2), 16) || '|' || fpadl(fmio(r.m2), 22) || '|');
                po('  |' || fpadl('4', 4) || '|'
                    || fpad('Ecriture en monnaie locale avec un cours different de 1', 72) || '|'
                    || fpadl(fnum(r.n3), 16) || '|' || fpadl(fmio(r.m3), 22) || '|');
                po('  |' || fpadl('5', 4) || '|'
                    || fpad('Contre-valeur non reconciliee par le cours applique', 72) || '|'
                    || fpadl(fnum(r.n4), 16) || '|' || fpadl(fmio(r.m4), 22) || '|');
                po('  |' || fpadl('6', 4) || '|'
                    || fpad('Operation en devise au dela du seuil de justification', 72) || '|'
                    || fpadl(fnum(r.n5), 16) || '|' || fpadl(fmio(r.m5), 22) || '|');
                po('  |' || fpadl('7', 4) || '|'
                    || fpad('Operation au dela du seuil sans reference externe', 72) || '|'
                    || fpadl(fnum(r.n6), 16) || '|' || fpadl(fmio(r.m6), 22) || '|');
                po('  |' || fpadl('8', 4) || '|'
                    || fpad('Ecriture en devise saisie et autorisee par le meme agent', 72) || '|'
                    || fpadl(fnum(r.n7), 16) || '|' || fpadl(fmio(r.m7), 22) || '|');
                po('  |' || fpadl('9', 4) || '|'
                    || fpad('Ecriture en devise passee un samedi ou un dimanche', 72) || '|'
                    || fpadl(fnum(r.n8), 16) || '|' || fpadl(fmio(r.m8), 22) || '|');
                po('  |' || fpadl('10', 4) || '|'
                    || fpad('Ecriture en devise a date de valeur retroactive', 72) || '|'
                    || fpadl(fnum(r.n9), 16) || '|' || fpadl(fmio(r.m9), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        tbl_line('4,72,16,22');

        print_sub('29.2 Sur le referentiel des cours');
        tbl_line('4,72,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 72) || '|' || fpadl('NB CAS', 16) || '|');
        tbl_line('4,72,16');
        v_row := 10;
        FOR r IN (
            SELECT lib, tab, whr, ord FROM (
                SELECT 'Cotation a cours moyen nul ou negatif' lib,
                       'CYTB_RATES_HISTORY' tab, 'NVL(MID_RATE, 0) <= 0' whr, 1 ord FROM DUAL UNION ALL
                SELECT 'Cotation dont le cours acheteur depasse le cours vendeur',
                       'CYTB_RATES_HISTORY', 'BUY_RATE > SALE_RATE', 2 FROM DUAL UNION ALL
                SELECT 'Cotation dont le cours moyen sort de la fourchette acheteur-vendeur',
                       'CYTB_RATES_HISTORY', 'MID_RATE < BUY_RATE OR MID_RATE > SALE_RATE', 3 FROM DUAL UNION ALL
                SELECT 'Cotation sans ecart entre cours acheteur et cours vendeur',
                       'CYTB_RATES_HISTORY', 'NVL(BUY_RATE, 0) = NVL(SALE_RATE, 0)', 4 FROM DUAL UNION ALL
                SELECT 'Cotation portant une date posterieure a la date du jour',
                       'CYTB_RATES_HISTORY', 'RATE_DATE > SYSDATE', 5 FROM DUAL UNION ALL
                SELECT 'Cotation derivee a cours moyen nul ou negatif',
                       'CYTB_DERIVED_RATES_HISTORY', 'NVL(MID_RATE, 0) <= 0', 6 FROM DUAL
            ) ORDER BY ord
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 72) || '|'
                || fpadl(f_cas(f_count(r.tab, r.whr)), 16) || '|');
        END LOOP;
        -- Cotations euro s'ecartant de la parite de rattachement
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM cytb_rates_history c
             WHERE (c.ccy1 = k_ccy_eur OR c.ccy2 = k_ccy_eur)
               AND ABS(NVL(c.mid_rate, 0) - k_par_eur) > 0.001
               AND ABS(NVL(c.mid_rate, 0) - 1 / k_par_eur) > 0.0000001;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Cotation ' || k_ccy_eur || ' s''ecartant de la parite de rattachement', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        -- Devises mouvementees jamais cotees
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM (SELECT DISTINCT h.ac_ccy ccy FROM actb_history h WHERE h.ac_ccy <> k_lcy) x
             WHERE NOT EXISTS (SELECT 1 FROM cytb_rates_history c
                                WHERE c.ccy1 = x.ccy OR c.ccy2 = x.ccy);
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Devise mouvementee en comptabilite mais jamais cotee', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        -- Couples dont l'historique presente un trou de plus de 7 jours
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM (SELECT ccy1, ccy2, MAX(gap) trou
                      FROM (SELECT ccy1, ccy2,
                                   rate_date - LAG(rate_date)
                                     OVER (PARTITION BY ccy1, ccy2 ORDER BY rate_date) gap
                              FROM (SELECT DISTINCT ccy1, ccy2, rate_date FROM cytb_rates_history))
                     GROUP BY ccy1, ccy2)
             WHERE trou > 7;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Couple de devises presentant un trou de cotation de plus de 7 jours', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        tbl_line('4,72,16');

        print_sub('29.3 Sur les comptes et les clients');
        tbl_line('4,72,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 72) || '|' || fpadl('NB CAS', 16) || '|');
        tbl_line('4,72,16');
        FOR r IN (
            SELECT lib, tab, whr, ord FROM (
                SELECT 'Compte client en devise etrangere (population de reference)' lib,
                       'STTM_CUST_ACCOUNT' tab, 'CCY <> ''@LCY@''' whr, 1 ord FROM DUAL UNION ALL
                SELECT 'Compte en devise dormant avec un solde non nul',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(TRIM(AC_STAT_DORMANT), ''N'') = ''Y'' '
                       || 'AND NVL(ACY_CURR_BALANCE, 0) <> 0', 2 FROM DUAL UNION ALL
                SELECT 'Compte en devise gele avec un solde non nul',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(TRIM(AC_STAT_FROZEN), ''N'') = ''Y'' '
                       || 'AND NVL(ACY_CURR_BALANCE, 0) <> 0', 3 FROM DUAL UNION ALL
                SELECT 'Compte en devise bloque avec un solde non nul',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(TRIM(AC_STAT_BLOCK), ''N'') = ''Y'' '
                       || 'AND NVL(ACY_CURR_BALANCE, 0) <> 0', 4 FROM DUAL UNION ALL
                SELECT 'Compte en devise ferme avec un solde non nul',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(TRIM(RECORD_STAT), ''O'') <> ''O'' '
                       || 'AND NVL(ACY_CURR_BALANCE, 0) <> 0', 5 FROM DUAL UNION ALL
                SELECT 'Compte en devise non autorise (AUTH_STAT different de A)',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(TRIM(AUTH_STAT), ''A'') <> ''A''', 6 FROM DUAL UNION ALL
                SELECT 'Compte en devise dont la contre-valeur locale est nulle malgre un solde',
                       'STTM_CUST_ACCOUNT',
                       'CCY <> ''@LCY@'' AND NVL(ACY_CURR_BALANCE, 0) <> 0 '
                       || 'AND NVL(LCY_CURR_BALANCE, 0) = 0', 7 FROM DUAL UNION ALL
                SELECT 'General en devise etrangere (population de reference)',
                       'STTB_ACCOUNT', 'AC_GL_CCY <> ''@LCY@'' AND AC_OR_GL = ''G''', 8 FROM DUAL
            ) ORDER BY ord
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 72) || '|'
                || fpadl(f_cas(f_count(r.tab, REPLACE(r.whr, '@LCY@', k_lcy))), 16) || '|');
        END LOOP;
        -- Titulaire de compte en devise sans dossier KYC
        BEGIN
            SELECT COUNT(DISTINCT a.cust_no) INTO v_cnt
              FROM sttm_cust_account a
              JOIN sttm_customer c ON c.customer_no = a.cust_no
             WHERE a.ccy <> k_lcy AND TRIM(c.kyc_ref_no) IS NULL;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Titulaire de compte en devise sans dossier KYC', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        -- Titulaire de compte en devise sans pays renseigne
        BEGIN
            SELECT COUNT(DISTINCT a.cust_no) INTO v_cnt
              FROM sttm_cust_account a
              JOIN sttm_customer c ON c.customer_no = a.cust_no
             WHERE a.ccy <> k_lcy AND TRIM(c.country) IS NULL;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Titulaire de compte en devise sans pays renseigne', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        -- Client detenant des comptes dans plus de deux devises
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM (SELECT a.cust_no FROM sttm_cust_account a
                     GROUP BY a.cust_no
                    HAVING COUNT(DISTINCT a.ccy) > 2);
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Client detenant des comptes dans plus de deux devises', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        tbl_line('4,72,16');

        print_sub('29.4 Sur la position de change et la reevaluation');
        tbl_line('4,72,16');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 72) || '|' || fpadl('NB CAS', 16) || '|');
        tbl_line('4,72,16');
        FOR r IN (
            SELECT lib, tab, whr, ord FROM (
                SELECT 'Ligne de reevaluation sans cours applique' lib,
                       'RVTB_ACC_REVAL' tab, 'NVL(NEW_RATE, 0) = 0' whr, 1 ord FROM DUAL UNION ALL
                SELECT 'Ligne de reevaluation a resultat nul',
                       'RVTB_ACC_REVAL',
                       'NVL(NEW_LCY_EQUIVALENT, 0) = NVL(OLD_LCY_EQUIVALENT, 0)', 2 FROM DUAL UNION ALL
                SELECT 'Ligne de reevaluation portant sur la monnaie locale',
                       'RVTB_ACC_REVAL', 'CCY = ''@LCY@''', 3 FROM DUAL UNION ALL
                SELECT 'Ligne de reevaluation sans compte de contrepartie de resultat',
                       'RVTB_ACC_REVAL', 'TRIM(PNL_ACCOUNT) IS NULL', 4 FROM DUAL UNION ALL
                SELECT 'Solde de grand livre en devise sans contre-valeur locale',
                       'GLTB_GL_BAL',
                       'CCY_CODE <> ''@LCY@'' AND (NVL(DR_BAL, 0) <> 0 OR NVL(CR_BAL, 0) <> 0) '
                       || 'AND NVL(DR_BAL_LCY, 0) = 0 AND NVL(CR_BAL_LCY, 0) = 0', 5 FROM DUAL
            ) ORDER BY ord
        ) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.lib, 72) || '|'
                || fpadl(f_cas(f_count(r.tab, REPLACE(r.whr, '@LCY@', k_lcy))), 16) || '|');
        END LOOP;
        -- Reevaluation non reconciliee par le cours
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM rvtb_acc_reval v
             WHERE NVL(v.new_rate, 0) <> 0
               AND ABS(NVL(v.new_lcy_equivalent, 0) - NVL(v.account_balance, 0) * NVL(v.new_rate, 0))
                   > GREATEST(1, ABS(NVL(v.new_lcy_equivalent, 0)) * 0.0001)
               AND ABS(NVL(v.new_lcy_equivalent, 0) - NVL(v.account_balance, 0) / NULLIF(v.new_rate, 0))
                   > GREATEST(1, ABS(NVL(v.new_lcy_equivalent, 0)) * 0.0001);
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Reevaluation non reconciliee par le cours applique', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        -- Devise en position mais jamais reevaluee
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM (SELECT DISTINCT a.ccy ccy FROM sttm_cust_account a
                     WHERE a.ccy <> k_lcy AND NVL(a.acy_curr_balance, 0) <> 0) x
             WHERE NOT EXISTS (SELECT 1 FROM rvtb_acc_reval v WHERE v.ccy = x.ccy);
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|'
            || fpad('Devise portant une position mais jamais reevaluee', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|');
        tbl_line('4,72,16');


        print_sub('29.5 Sur les transferts internationaux');
        po('  Les compteurs ci-dessous sont calcules au niveau de l''operation, en une');
        po('  seule lecture du perimetre du module ' || k_mod_ft || '.');
        po('');
        tbl_line('4,72,16,22');
        po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 72) || '|' || fpadl('NB CAS', 16) || '|'
            || fpadl('MONTANT LCY', 22) || '|');
        tbl_line('4,72,16,22');
        BEGIN
            FOR r IN (
                SELECT
                  COUNT(*) n0, SUM(mt) m0,
                  SUM(CASE WHEN n_fx > 0 THEN 1 ELSE 0 END) n1,
                  SUM(CASE WHEN n_fx > 0 THEN mt ELSE 0 END) m1,
                  SUM(CASE WHEN n_fx > 0 AND n_ext = 0 THEN 1 ELSE 0 END) n2,
                  SUM(CASE WHEN n_fx > 0 AND n_ext = 0 THEN mt ELSE 0 END) m2,
                  SUM(CASE WHEN mt >= k_s_justif THEN 1 ELSE 0 END) n3,
                  SUM(CASE WHEN mt >= k_s_justif THEN mt ELSE 0 END) m3,
                  SUM(CASE WHEN mt >= k_s_justif AND n_ext = 0 THEN 1 ELSE 0 END) n4,
                  SUM(CASE WHEN mt >= k_s_justif AND n_ext = 0 THEN mt ELSE 0 END) m4,
                  SUM(CASE WHEN mt >= k_s_justif * (1 - k_bande) AND mt < k_s_justif
                           THEN 1 ELSE 0 END) n5,
                  SUM(CASE WHEN mt >= k_s_justif * (1 - k_bande) AND mt < k_s_justif
                           THEN mt ELSE 0 END) m5,
                  SUM(CASE WHEN n_fx > 0 AND n_corr = 0 THEN 1 ELSE 0 END) n6,
                  SUM(CASE WHEN n_fx > 0 AND n_corr = 0 THEN mt ELSE 0 END) m6,
                  SUM(CASE WHEN n_auto > 0 THEN 1 ELSE 0 END) n7,
                  SUM(CASE WHEN n_auto > 0 THEN mt ELSE 0 END) m7,
                  SUM(CASE WHEN n_wk > 0 THEN 1 ELSE 0 END) n8,
                  SUM(CASE WHEN n_wk > 0 THEN mt ELSE 0 END) m8,
                  SUM(CASE WHEN n_fx > 0 AND n_norate > 0 THEN 1 ELSE 0 END) n9,
                  SUM(CASE WHEN n_fx > 0 AND n_norate > 0 THEN mt ELSE 0 END) m9,
                  SUM(CASE WHEN n_cli = 0 THEN 1 ELSE 0 END) n10,
                  SUM(CASE WHEN n_cli = 0 THEN mt ELSE 0 END) m10
                FROM (SELECT h.trn_ref_no,
                             MAX(NVL(h.lcy_amount, 0)) mt,
                             SUM(CASE WHEN h.ac_ccy <> k_lcy THEN 1 ELSE 0 END) n_fx,
                             SUM(CASE WHEN h.cust_gl = 'G' AND h.ac_ccy <> k_lcy
                                      THEN 1 ELSE 0 END) n_corr,
                             SUM(CASE WHEN TRIM(h.external_ref_no) IS NOT NULL
                                      THEN 1 ELSE 0 END) n_ext,
                             SUM(CASE WHEN h.user_id = h.auth_id
                                        AND UPPER(NVL(TRIM(h.user_id), 'X')) <> 'SYSTEM'
                                      THEN 1 ELSE 0 END) n_auto,
                             SUM(CASE WHEN (TRUNC(h.trn_dt) - TRUNC(h.trn_dt, 'IW') + 1) IN (6, 7)
                                      THEN 1 ELSE 0 END) n_wk,
                             SUM(CASE WHEN h.ac_ccy <> k_lcy AND NVL(h.exch_rate, 0) = 0
                                      THEN 1 ELSE 0 END) n_norate,
                             SUM(CASE WHEN h.cust_gl = 'A' THEN 1 ELSE 0 END) n_cli
                        FROM actb_history h
                       WHERE h.module = k_mod_ft
                       GROUP BY h.trn_ref_no)
            ) LOOP
                po('  |' || fpadl('1', 4) || '|'
                    || fpad('Operations de transfert (population de reference)', 72) || '|'
                    || fpadl(fnum(r.n0), 16) || '|' || fpadl(fmio(r.m0), 22) || '|');
                po('  |' || fpadl('2', 4) || '|'
                    || fpad('Transfert comportant au moins une ecriture en devise', 72) || '|'
                    || fpadl(fnum(r.n1), 16) || '|' || fpadl(fmio(r.m1), 22) || '|');
                po('  |' || fpadl('3', 4) || '|'
                    || fpad('Transfert en devise sans reference externe (message absent)', 72) || '|'
                    || fpadl(fnum(r.n2), 16) || '|' || fpadl(fmio(r.m2), 22) || '|');
                po('  |' || fpadl('4', 4) || '|'
                    || fpad('Transfert au dela du seuil de justification', 72) || '|'
                    || fpadl(fnum(r.n3), 16) || '|' || fpadl(fmio(r.m3), 22) || '|');
                po('  |' || fpadl('5', 4) || '|'
                    || fpad('Transfert au dela du seuil sans reference externe', 72) || '|'
                    || fpadl(fnum(r.n4), 16) || '|' || fpadl(fmio(r.m4), 22) || '|');
                po('  |' || fpadl('6', 4) || '|'
                    || fpad('Transfert dans la bande immediatement sous le seuil', 72) || '|'
                    || fpadl(fnum(r.n5), 16) || '|' || fpadl(fmio(r.m5), 22) || '|');
                po('  |' || fpadl('7', 4) || '|'
                    || fpad('Transfert en devise ne mouvementant aucun general en devise', 72) || '|'
                    || fpadl(fnum(r.n6), 16) || '|' || fpadl(fmio(r.m6), 22) || '|');
                po('  |' || fpadl('8', 4) || '|'
                    || fpad('Transfert saisi et autorise par le meme agent', 72) || '|'
                    || fpadl(fnum(r.n7), 16) || '|' || fpadl(fmio(r.m7), 22) || '|');
                po('  |' || fpadl('9', 4) || '|'
                    || fpad('Transfert passe un samedi ou un dimanche', 72) || '|'
                    || fpadl(fnum(r.n8), 16) || '|' || fpadl(fmio(r.m8), 22) || '|');
                po('  |' || fpadl('10', 4) || '|'
                    || fpad('Transfert en devise sans cours de change sur au moins une ecriture', 72) || '|'
                    || fpadl(fnum(r.n9), 16) || '|' || fpadl(fmio(r.m9), 22) || '|');
                po('  |' || fpadl('11', 4) || '|'
                    || fpad('Transfert ne mouvementant aucun compte client (general a general)', 72) || '|'
                    || fpadl(fnum(r.n10), 16) || '|' || fpadl(fmio(r.m10), 22) || '|');
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN po('    !! ' || SQLERRM);
        END;
        -- Comptes cumulant des operations dans la bande sous le seuil
        BEGIN
            SELECT COUNT(*) INTO v_cnt
              FROM (SELECT ac_no
                      FROM (SELECT h.ac_no, h.trn_ref_no,
                                   TO_CHAR(MIN(h.trn_dt), 'YYYY-MM') mois,
                                   MAX(NVL(h.lcy_amount, 0)) mt
                              FROM actb_history h
                             WHERE h.module = k_mod_ft
                               AND h.cust_gl = 'A'
                             GROUP BY h.ac_no, h.trn_ref_no)
                     WHERE mt BETWEEN k_s_justif * (1 - k_bande) AND k_s_justif
                     GROUP BY ac_no, mois
                    HAVING COUNT(*) >= 3);
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        po('  |' || fpadl('12', 4) || '|'
            || fpad('Compte cumulant au moins trois transferts sous le seuil le meme mois', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|' || fpadl('-', 22) || '|');
        -- Clients transferant sans dossier KYC
        BEGIN
            SELECT COUNT(DISTINCT a.cust_no) INTO v_cnt
              FROM actb_history h
              JOIN sttm_cust_account a ON a.cust_ac_no = h.ac_no
              JOIN sttm_customer c ON c.customer_no = a.cust_no
             WHERE h.module = k_mod_ft
               AND h.cust_gl = 'A'
               AND TRIM(c.kyc_ref_no) IS NULL;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        po('  |' || fpadl('13', 4) || '|'
            || fpad('Client transferant sans dossier KYC rattache', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|' || fpadl('-', 22) || '|');
        -- Transferts portes par un client gele
        BEGIN
            SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_cnt
              FROM actb_history h
              JOIN sttm_cust_account a ON a.cust_ac_no = h.ac_no
              JOIN sttm_customer c ON c.customer_no = a.cust_no
             WHERE h.module = k_mod_ft
               AND h.cust_gl = 'A'
               AND NVL(TRIM(c.frozen), 'N') = 'Y';
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1;
        END;
        po('  |' || fpadl('14', 4) || '|'
            || fpad('Transfert porte par un client gele', 72) || '|'
            || fpadl(f_cas(v_cnt), 16) || '|' || fpadl('-', 22) || '|');
        tbl_line('4,72,16,22');
        po('  Les controles 3, 5 et 6 sont des indices de defaut de justification ou de');
        po('  fractionnement : ils designent les operations a rapprocher des dossiers de');
        po('  domiciliation, ils ne constatent pas a eux seuls une infraction.');
        po('');
        po('  LECTURE DU TABLEAU');
        po('    Un compte a zero valide le controle et permet de l''ecarter du script');
        po('    final ou de le conserver comme test de non-regression. Un compte eleve');
        po('    signale soit une anomalie de masse, soit un controle mal calibre : dans');
        po('    les deux cas il faut l''instruire avant de le retenir.');
        po('    La mention OBJET ABSENT OU INACCESSIBLE indique que la table n''existe pas');
        po('    dans ce schema ou que les droits de lecture manquent.');
    EXCEPTION
        WHEN OTHERS THEN
            po('');
            po('    !! SECTION INTERROMPUE : ' || SQLERRM);
            po('       ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END;

    po('');
    po(v_sep);
    po('>>> EXPLORATION TERMINEE - ' || fdth(SYSDATE));
    po(v_sep);

EXCEPTION
    WHEN OTHERS THEN
        po('');
        po('!! ERREUR GENERALE : ' || SQLERRM);
        po('   ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/

-- SPOOL OFF
