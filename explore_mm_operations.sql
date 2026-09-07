-- ============================================================================
-- SCRIPT D'EXPLORATION — OPERATIONS DE MARCHE MONETAIRE (MODULE MM)
-- Base : FLEXCUBE (FCUBS)
-- ============================================================================
-- OBJET
--   Ce script n'effectue AUCUN test de conformite. Il decrit la facon dont les
--   operations de marche monetaire sont encodees dans la base, afin de pouvoir
--   ensuite rediger un script d'audit cible (sur le modele de test_coherence.sql
--   et audit_aml_cft.sql).
--
--   Deux angles sont couverts :
--     1. les contrats du module 'MM' (table LDTB_CONTRACT_MASTER, partagee avec
--        le module LD) et toutes leurs tables satellites ;
--     2. l'utilisateur applicatif CALYPSOUSR, par lequel l'outil de gestion des
--        titres et des placements deverse ses operations dans FLEXCUBE.
--
-- STRUCTURE
--   Le script est decoupe en QUATRE blocs PL/SQL independants. Si un bloc echoue
--   (objet absent, droits insuffisants), les autres s'executent quand meme.
--     Bloc 1 : contexte et cartographie du schema        (sections 1 a 5)
--     Bloc 2 : contrats du module MM                     (sections 6 a 16)
--     Bloc 3 : ecritures comptables ACTB_HISTORY         (sections 17 a 22)
--     Bloc 4 : CALYPSOUSR, utilisateurs et controles     (sections 23 a 30)
--
-- UTILISATION
--   sqlplus utilisateur/motdepasse@base
--   SQL> spool exploration_mm_report.txt
--   SQL> @explore_mm_operations.sql
--   SQL> spool off
--
--   Puis transmettre exploration_mm_report.txt pour la redaction du script final.
--
-- DUREE
--   Les blocs 3 et 4 lisent integralement ACTB_HISTORY (plusieurs millions de
--   lignes) et SMTB_SMS_LOG : prevoir plusieurs minutes d'execution.
-- ============================================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SET LINESIZE 250
SET PAGESIZE 0
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    -- ---------- Variables de travail ----------
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_row     NUMBER;
    v_dim     VARCHAR2(60);

    -- Motif de recherche de l'application CALYPSO (utilisateur applicatif)
    k_pat     VARCHAR2(30) := '%CALYPSO%';
    -- Module des operations de marche monetaire
    k_mod     VARCHAR2(4)  := 'MM';

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
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990D00');
    END;

    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G990D00') || ' M';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
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
    po('   BLOC 1/4 : CONTEXTE ET CARTOGRAPHIE DU SCHEMA');
    po(v_sep);

    -- =========================================================
    -- 1. CONTEXTE D'EXECUTION
    -- =========================================================
    print_section('1. CONTEXTE D''EXECUTION');

    print_kv('Date / heure du rapport',   TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    print_kv('Utilisateur connecte',      SYS_CONTEXT('USERENV', 'SESSION_USER'));
    print_kv('Schema courant',            SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
    print_kv('Base de donnees',           SYS_CONTEXT('USERENV', 'DB_NAME'));
    print_kv('Instance',                  SYS_CONTEXT('USERENV', 'INSTANCE_NAME'));
    print_kv('Module explore',            k_mod || ' (operations de marche monetaire)');
    print_kv('Motif application externe', k_pat);

    -- Agences (utile pour lire les references de contrat : les 3 premiers
    -- caracteres d'un CONTRACT_REF_NO sont le code agence)
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

    -- =========================================================
    -- 2. MODULES FLEXCUBE INSTALLES
    -- =========================================================
    print_section('2. MODULES FLEXCUBE DECLARES (SMTB_MODULES)');
    po('  Objectif : identifier le code exact du module marche monetaire et les');
    po('  modules connexes (titres, change, placements) reellement installes.');
    po('');

    BEGIN
        tbl_line('4,10,50,12,12,12');
        po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpad('LIBELLE', 50) || '|'
            || fpad('INSTALLE', 12) || '|' || fpad('RECORD_STAT', 12) || '|' || fpad('AUTH_STAT', 12) || '|');
        tbl_line('4,10,50,12,12,12');
        v_row := 0;
        FOR r IN (SELECT module_id, module_desc, installed, record_stat, auth_stat
                  FROM smtb_modules ORDER BY module_id) LOOP
            v_row := v_row + 1;
            po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module_id, 10) || '|'
                || fpad(r.module_desc, 50) || '|' || fpad(r.installed, 12) || '|'
                || fpad(r.record_stat, 12) || '|' || fpad(r.auth_stat, 12) || '|');
        END LOOP;
        tbl_line('4,10,50,12,12,12');
    EXCEPTION
        WHEN OTHERS THEN po('    !! ' || SQLERRM);
    END;

    -- =========================================================
    -- 3. DECOUVERTE DES OBJETS DU SCHEMA
    -- =========================================================
    print_section('3. DECOUVERTE DES OBJETS DU SCHEMA (dictionnaire Oracle)');
    po('  Le dictionnaire de donnees dont nous disposons est partiel. Cette section');
    po('  interroge ALL_TABLES / ALL_VIEWS pour lister ce qui existe reellement');
    po('  autour du marche monetaire, des titres et de l''application externe.');

    -- 3.1 Nombre d'objets par famille de prefixe
    print_sub('3.1 Nombre de tables par famille de prefixe');
    FOR r IN (
        SELECT fam, pat FROM (
            SELECT 'LD (Loans & Deposits = support du module MM)' fam, 'LD%'        pat, 1 ord FROM DUAL UNION ALL
            SELECT 'MM (tables propres au marche monetaire)',        'MM%',            2 FROM DUAL UNION ALL
            SELECT 'SE (Securities / titres)',                       'SE%',            3 FROM DUAL UNION ALL
            SELECT 'DV (Derivatives)',                               'DV%',            4 FROM DUAL UNION ALL
            SELECT 'FX (operations de change)',                      'FX%',            5 FROM DUAL UNION ALL
            SELECT 'CD (Corporate Deposits)',                        'CD%',            6 FROM DUAL UNION ALL
            SELECT 'ETD / futures et options',                       'ET%',            7 FROM DUAL UNION ALL
            SELECT 'SI (Standing Instructions)',                     'SI%',            8 FROM DUAL UNION ALL
            SELECT 'AC (comptabilite)',                              'ACTB%',          9 FROM DUAL UNION ALL
            SELECT 'Objets contenant CALYPSO',                       '%CALYPSO%',     10 FROM DUAL UNION ALL
            SELECT 'Objets contenant DEAL',                          '%DEAL%',        11 FROM DUAL UNION ALL
            SELECT 'Objets contenant TREASURY',                      '%TREASUR%',     12 FROM DUAL UNION ALL
            SELECT 'Objets contenant PLACEMENT',                     '%PLACEMENT%',   13 FROM DUAL UNION ALL
            SELECT 'Objets contenant INTERFACE / UPLOAD',            '%UPLOAD%',      14 FROM DUAL
        ) ORDER BY ord
    ) LOOP
        SELECT COUNT(*) INTO v_cnt FROM all_tables WHERE table_name LIKE r.pat;
        SELECT COUNT(*) INTO v_cnt2 FROM all_views WHERE view_name LIKE r.pat;
        print_kv('  ' || r.fam, fnum(v_cnt) || ' tables / ' || fnum(v_cnt2) || ' vues');
    END LOOP;

    -- 3.2 Tables du perimetre contenant des donnees (statistiques Oracle)
    print_sub('3.2 Tables du perimetre porteuses de donnees (NUM_ROWS des statistiques)');
    po('  Attention : NUM_ROWS provient des statistiques Oracle, il peut etre perime.');
    po('');
    tbl_line('4,12,36,16,14');
    po('  |' || fpad('N#', 4) || '|' || fpad('PROPRIETAIRE', 12) || '|' || fpad('TABLE', 36) || '|'
        || fpadl('NUM_ROWS', 16) || '|' || fpad('ANALYSEE LE', 14) || '|');
    tbl_line('4,12,36,16,14');
    v_row := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT owner, table_name, num_rows, last_analyzed
            FROM all_tables
            WHERE (   table_name LIKE 'LD%'  OR table_name LIKE 'MM%'
                   OR table_name LIKE 'SE%'  OR table_name LIKE 'DV%'
                   OR table_name LIKE 'CD%'  OR table_name LIKE 'ET%'
                   OR table_name LIKE '%CALYPSO%' OR table_name LIKE '%TREASUR%')
              AND NVL(num_rows, 0) > 0
            ORDER BY num_rows DESC
        ) WHERE ROWNUM <= 120
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.owner, 12) || '|' || fpad(r.table_name, 36) || '|'
            || fpadl(fnum(r.num_rows), 16) || '|' || fpad(fdt(r.last_analyzed), 14) || '|');
    END LOOP;
    tbl_line('4,12,36,16,14');
    IF v_row = 0 THEN
        po('    (aucune table du perimetre avec des statistiques exploitables)');
    END IF;

    -- 3.3 Tous les objets dont le nom evoque CALYPSO
    print_sub('3.3 Objets dont le nom contient CALYPSO');
    v_row := 0;
    FOR r IN (SELECT owner, object_name, object_type, created, last_ddl_time
              FROM all_objects WHERE object_name LIKE '%CALYPSO%' ORDER BY object_type, object_name) LOOP
        v_row := v_row + 1;
        print_kv('  ' || r.object_type || ' : ' || r.owner || '.' || r.object_name,
                 'cree le ' || fdt(r.created) || ', modifie le ' || fdt(r.last_ddl_time));
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucun objet nomme CALYPSO : l''application n''expose donc qu''un');
        po('     utilisateur applicatif, pas de table dediee dans FLEXCUBE)');
    END IF;

    -- 3.4 Vues clientele utilisees par les requetes metier
    print_sub('3.4 Vues STTM_CUSTOMER* / CSTM_PRODUCT* disponibles');
    v_row := 0;
    FOR r IN (SELECT owner, view_name FROM all_views
              WHERE view_name LIKE 'STTM_CUSTOMER%' OR view_name LIKE 'CSTM_PRODUCT%'
              ORDER BY view_name) LOOP
        v_row := v_row + 1;
        print_kv('  VUE ' || r.owner || '.' || r.view_name, 'disponible');
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucune vue trouvee : utiliser directement les tables STTM_CUSTOMER / CSTM_PRODUCT)');
    END IF;

    -- =========================================================
    -- 4. VOLUMETRIE REELLE DES TABLES DU PERIMETRE
    -- =========================================================
    print_section('4. VOLUMETRIE REELLE DES TABLES DU PERIMETRE (COUNT(*))');

    FOR t IN (
        SELECT tab, lib FROM (
            SELECT 'LDTB_CONTRACT_MASTER'          tab, 'Contrats LD/MM - en-tete'                lib,  1 ord FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_MASTER_FCC',     'Contrats LD/MM - version courante',                 2 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_PREFERENCE',     'Preferences du contrat',                            3 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_BALANCE',        'Encours principal',                                 4 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_DETAILS',   'Composantes interets/commissions',                  5 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_CALC',      'Calcul des interets',                               6 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SCHEDULES',      'Echeanciers',                                       7 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_LIQ',            'Liquidations - detail',                             8 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_LIQ_SUMMARY',    'Liquidations - synthese',                           9 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ROLLOVER',       'Renouvellements (rollover)',                       10 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ROLL_INT_RATES', 'Taux appliques au renouvellement',                 11 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ACCRUAL_HISTORY','Historique des provisions d''interets',            12 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SWIFT_MESSAGE',  'Confirmations SWIFT du contrat',                   13 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_CONTROL',        'Verrous / controle de saisie',                     14 FROM DUAL UNION ALL
            SELECT 'LDTM_PRODUCT_MASTER',          'Parametrage produit LD/MM',                        15 FROM DUAL UNION ALL
            SELECT 'LDTM_PRODUCT_ROLLOVER',        'Parametrage rollover produit',                     16 FROM DUAL UNION ALL
            SELECT 'LDTM_PRODUCT_DFLT_SCHEDULES',  'Echeanciers par defaut produit',                   17 FROM DUAL UNION ALL
            SELECT 'LDTM_BRANCH_PARAMETERS',       'Parametres agence du module',                      18 FROM DUAL UNION ALL
            SELECT 'CSTM_PRODUCT',                 'Referentiel produits (libelles)',                  19 FROM DUAL UNION ALL
            SELECT 'CSTB_AMOUNT_TAG',              'Referentiel des tags de montant',                  20 FROM DUAL UNION ALL
            SELECT 'STTM_TRN_CODE',                'Referentiel des codes transaction',                21 FROM DUAL UNION ALL
            SELECT 'ACTB_HISTORY',                 'Ecritures comptables historisees',                 22 FROM DUAL UNION ALL
            SELECT 'STTM_CUSTOMER',                'Fiches clients / contreparties',                   23 FROM DUAL UNION ALL
            SELECT 'STTM_CUST_ACCOUNT',            'Comptes clients',                                  24 FROM DUAL UNION ALL
            SELECT 'STTM_KYC_MASTER',              'Referentiel KYC',                                  25 FROM DUAL UNION ALL
            SELECT 'STTB_ACCOUNT',                 'Comptes GL',                                       26 FROM DUAL UNION ALL
            SELECT 'SMTB_USER',                    'Utilisateurs FLEXCUBE',                            27 FROM DUAL UNION ALL
            SELECT 'SMTB_USER_ROLE',               'Affectation des roles',                            28 FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_MASTER',             'Referentiel des roles',                            29 FROM DUAL UNION ALL
            SELECT 'SMTB_SMS_LOG',                 'Journal des sessions applicatives',                30 FROM DUAL UNION ALL
            SELECT 'SMTB_SMS_ACTION_LOG',          'Journal des actions (XML requete/reponse)',        31 FROM DUAL UNION ALL
            SELECT 'SMTB_USERLOG_DETAILS',         'Dernieres connexions par utilisateur',             32 FROM DUAL UNION ALL
            SELECT 'GETM_FACILITY',                'Lignes de credit / limites',                       33 FROM DUAL UNION ALL
            SELECT 'CSTM_FUNCTION_USERDEF_FIELDS', 'Champs personnalises (UDF)',                       34 FROM DUAL
        ) ORDER BY ord
    ) LOOP
        v_cnt := f_count(t.tab);
        print_kv(t.tab, RPAD(f_lbl(v_cnt), 22) || '  ' || t.lib);
    END LOOP;

    -- =========================================================
    -- 5. PERIMETRE MM : PREMIER CADRAGE
    -- =========================================================
    print_section('5. PREMIER CADRAGE DU PERIMETRE MM');

    print_kv('Contrats toutes natures (LDTB_CONTRACT_MASTER)', f_lbl(f_count('LDTB_CONTRACT_MASTER')));
    print_kv('Contrats MODULE = ''MM''',        f_lbl(f_count('LDTB_CONTRACT_MASTER', 'MODULE = ''MM''')));
    print_kv('Contrats MODULE = ''LD''',        f_lbl(f_count('LDTB_CONTRACT_MASTER', 'MODULE = ''LD''')));
    print_kv('Ecritures comptables MODULE = ''MM''',
             f_lbl(f_count('ACTB_HISTORY', 'MODULE = ''MM''')));
    print_kv('Ecritures comptables saisies par ' || k_pat,
             f_lbl(f_count('ACTB_HISTORY', 'USER_ID LIKE ''' || k_pat || '''')));
    print_kv('Ecritures comptables autorisees par ' || k_pat,
             f_lbl(f_count('ACTB_HISTORY', 'AUTH_ID LIKE ''' || k_pat || '''')));
    print_kv('Sessions applicatives de ' || k_pat || ' (SMTB_SMS_LOG)',
             f_lbl(f_count('SMTB_SMS_LOG', 'USER_ID LIKE ''' || k_pat || '''')));
    print_kv('Utilisateurs FLEXCUBE correspondant a ' || k_pat,
             f_lbl(f_count('SMTB_USER', 'USER_ID LIKE ''' || k_pat || ''' OR USER_NAME LIKE ''' || k_pat || '''')));

    po('');
    po('  >>> FIN DU BLOC 1');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!! ERREUR BLOC 1 : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/


DECLARE
    -- ---------- Variables de travail ----------
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_row     NUMBER;
    v_dim     VARCHAR2(60);

    -- Motif de recherche de l'application CALYPSO (utilisateur applicatif)
    k_pat     VARCHAR2(30) := '%CALYPSO%';
    -- Module des operations de marche monetaire
    k_mod     VARCHAR2(4)  := 'MM';

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
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990D00');
    END;

    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G990D00') || ' M';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
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
    po('   BLOC 2/4 : LES CONTRATS DU MODULE MM (LDTB_CONTRACT_MASTER)');
    po(v_sep);

    -- =========================================================
    -- 6. REPARTITION DES CONTRATS PAR MODULE
    -- =========================================================
    print_section('6. LDTB_CONTRACT_MASTER : REPARTITION PAR MODULE');
    po('  Le module MM (marche monetaire) partage la table des contrats avec le');
    po('  module LD (prets et depots). La colonne MODULE est donc le premier filtre.');
    po('');

    tbl_line('4,10,12,12,12,14,14,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpadl('CONTRATS', 12) || '|'
        || fpadl('CONTREPART.', 12) || '|' || fpadl('PRODUITS', 12) || '|' || fpad('1ER BOOKING', 14) || '|'
        || fpad('DER. BOOKING', 14) || '|' || fpadl('TOTAL LCY', 20) || '|');
    tbl_line('4,10,12,12,12,14,14,20');
    v_row := 0;
    FOR r IN (
        SELECT module,
               COUNT(*) nb,
               COUNT(DISTINCT counterparty) nb_cp,
               COUNT(DISTINCT product) nb_pr,
               MIN(booking_date) d1,
               MAX(booking_date) d2,
               SUM(lcy_amount) tot
        FROM ldtb_contract_master
        GROUP BY module
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module, 10) || '|' || fpadl(fnum(r.nb), 12) || '|'
            || fpadl(fnum(r.nb_cp), 12) || '|' || fpadl(fnum(r.nb_pr), 12) || '|' || fpad(fdt(r.d1), 14) || '|'
            || fpad(fdt(r.d2), 14) || '|' || fpadl(fmio(r.tot), 20) || '|');
    END LOOP;
    tbl_line('4,10,12,12,12,14,14,20');

    -- Unicite : une ligne par contrat ou une ligne par version ?
    print_sub('6.1 Granularite de la table : une ligne = un contrat ou une version ?');
    SELECT COUNT(*), COUNT(DISTINCT contract_ref_no)
      INTO v_cnt, v_cnt2
      FROM ldtb_contract_master WHERE module = k_mod;
    print_kv('Lignes MM', fnum(v_cnt));
    print_kv('References de contrat distinctes MM', fnum(v_cnt2));
    print_kv('=> granularite',
             CASE WHEN v_cnt = v_cnt2 THEN 'UNE LIGNE PAR CONTRAT (derniere version)'
                  ELSE 'PLUSIEURS LIGNES PAR CONTRAT : filtrer sur la version' END);
    show_dist('6.2 Repartition VERSION_NO (MM)',   'ldtb_contract_master', 'VERSION_NO',   'MODULE = ''MM''', 20, 'V');
    show_dist('6.3 Repartition EVENT_SEQ_NO (MM)', 'ldtb_contract_master', 'EVENT_SEQ_NO', 'MODULE = ''MM''', 20, 'V');

    -- =========================================================
    -- 7. PROFIL COMPLET DES COLONNES SUR LE PERIMETRE MM
    -- =========================================================
    print_section('7. PROFIL COLONNE PAR COLONNE DE LDTB_CONTRACT_MASTER (MODULE = MM)');
    po('  Section la plus importante de l''exploration : elle montre, pour CHAQUE');
    po('  colonne, le taux de remplissage reel, le nombre de valeurs distinctes,');
    po('  les bornes et les valeurs les plus frequentes. C''est ce qui permettra de');
    po('  savoir sur quelles colonnes le script d''audit final peut s''appuyer.');

    profile_table('LDTB_CONTRACT_MASTER', 'MODULE = ''MM''');

    print_section('7 BIS. MEME PROFIL SUR LE MODULE LD (POUR COMPARAISON)');
    po('  Permet de distinguer ce qui est propre aux operations de marche monetaire');
    po('  de ce qui releve du parametrage general du module Loans & Deposits.');

    profile_table('LDTB_CONTRACT_MASTER', 'MODULE = ''LD''');

    -- =========================================================
    -- 8. DISTRIBUTIONS CLES DU PERIMETRE MM
    -- =========================================================
    print_section('8. DISTRIBUTIONS CLES DES CONTRATS MM');

    show_dist('8.01 PRODUCT (code produit)',              'ldtb_contract_master', 'PRODUCT',                 'MODULE = ''MM''', 40);
    show_dist('8.02 PRODUCT_TYPE',                        'ldtb_contract_master', 'PRODUCT_TYPE',            'MODULE = ''MM''');
    show_dist('8.03 BRANCH (agence)',                     'ldtb_contract_master', 'BRANCH',                  'MODULE = ''MM''');
    show_dist('8.04 CURRENCY (devise)',                   'ldtb_contract_master', 'CURRENCY',                'MODULE = ''MM''');
    show_dist('8.05 CONTRACT_STATUS',                     'ldtb_contract_master', 'CONTRACT_STATUS',         'MODULE = ''MM''');
    show_dist('8.06 CONTRACT_DERIVED_STATUS',             'ldtb_contract_master', 'CONTRACT_DERIVED_STATUS', 'MODULE = ''MM''');
    show_dist('8.07 USER_DEFINED_STATUS',                 'ldtb_contract_master', 'USER_DEFINED_STATUS',     'MODULE = ''MM''');
    show_dist('8.08 MATURITY_TYPE',                       'ldtb_contract_master', 'MATURITY_TYPE',           'MODULE = ''MM''');
    show_dist('8.09 PAYMENT_METHOD',                      'ldtb_contract_master', 'PAYMENT_METHOD',          'MODULE = ''MM''');
    show_dist('8.10 ROLLOVER_ALLOWED',                    'ldtb_contract_master', 'ROLLOVER_ALLOWED',        'MODULE = ''MM''');
    show_dist('8.11 ROLLOVER_COUNT',                      'ldtb_contract_master', 'ROLLOVER_COUNT',          'MODULE = ''MM''', 25, 'V');
    show_dist('8.12 DEALER (operateur de marche)',        'ldtb_contract_master', 'DEALER',                  'MODULE = ''MM''', 40);
    show_dist('8.13 DEALING_METHOD (canal de negoce)',    'ldtb_contract_master', 'DEALING_METHOD',          'MODULE = ''MM''');
    show_dist('8.14 MAIN_COMP (composante principale)',   'ldtb_contract_master', 'MAIN_COMP',               'MODULE = ''MM''');
    show_dist('8.15 MAIN_COMP_RATE_CODE',                 'ldtb_contract_master', 'MAIN_COMP_RATE_CODE',     'MODULE = ''MM''');
    show_dist('8.16 CREDIT_LINE (ligne de credit)',       'ldtb_contract_master', 'CREDIT_LINE',             'MODULE = ''MM''', 30);
    show_dist('8.17 BROKER_CODE (courtier)',              'ldtb_contract_master', 'BROKER_CODE',             'MODULE = ''MM''', 30);
    show_dist('8.18 TAX_SCHEME (schema fiscal)',          'ldtb_contract_master', 'TAX_SCHEME',              'MODULE = ''MM''');
    show_dist('8.19 ICCF_STATUS',                         'ldtb_contract_master', 'ICCF_STATUS',             'MODULE = ''MM''');
    show_dist('8.20 SETTLEMENT_STATUS',                   'ldtb_contract_master', 'SETTLEMENT_STATUS',       'MODULE = ''MM''');
    show_dist('8.21 TAX_STATUS',                          'ldtb_contract_master', 'TAX_STATUS',              'MODULE = ''MM''');
    show_dist('8.22 BROKERAGE_STATUS',                    'ldtb_contract_master', 'BROKERAGE_STATUS',        'MODULE = ''MM''');
    show_dist('8.23 CHARGE_STATUS',                       'ldtb_contract_master', 'CHARGE_STATUS',           'MODULE = ''MM''');
    show_dist('8.24 CPARTY_CONFIRM_STATUS',               'ldtb_contract_master', 'CPARTY_CONFIRM_STATUS',   'MODULE = ''MM''');
    show_dist('8.25 BROKER_CONFIRM_STATUS',               'ldtb_contract_master', 'BROKER_CONFIRM_STATUS',   'MODULE = ''MM''');
    show_dist('8.26 EXPOSURE_CATEGORY',                   'ldtb_contract_master', 'EXPOSURE_CATEGORY',       'MODULE = ''MM''');
    show_dist('8.27 INT_PERIOD_BASIS',                    'ldtb_contract_master', 'INT_PERIOD_BASIS',        'MODULE = ''MM''');
    show_dist('8.28 CLUSTER_ID',                          'ldtb_contract_master', 'CLUSTER_ID',              'MODULE = ''MM''');
    show_dist('8.29 SUBSYSTEM_STAT',                      'ldtb_contract_master', 'SUBSYSTEM_STAT',          'MODULE = ''MM''');
    show_dist('8.30 Annee de BOOKING_DATE',               'ldtb_contract_master', 'TO_CHAR(BOOKING_DATE, ''YYYY'')',      'MODULE = ''MM''', 30, 'V');
    show_dist('8.31 Mois de BOOKING_DATE (24 derniers)',  'ldtb_contract_master', 'TO_CHAR(BOOKING_DATE, ''YYYY-MM'')',   'MODULE = ''MM''', 36, 'V');
    show_dist('8.32 Annee de VALUE_DATE',                 'ldtb_contract_master', 'TO_CHAR(VALUE_DATE, ''YYYY'')',        'MODULE = ''MM''', 30, 'V');
    show_dist('8.33 Annee de MATURITY_DATE',              'ldtb_contract_master', 'TO_CHAR(MATURITY_DATE, ''YYYY'')',     'MODULE = ''MM''', 30, 'V');
    show_dist('8.34 Jour de la semaine du BOOKING_DATE',  'ldtb_contract_master', 'TO_CHAR(BOOKING_DATE, ''D'')',         'MODULE = ''MM''', 10, 'V');

    -- =========================================================
    -- 9. STRUCTURE DES REFERENCES
    -- =========================================================
    print_section('9. STRUCTURE DES REFERENCES DE CONTRAT MM');
    po('  Dans FLEXCUBE la reference de contrat est composee : 3 caracteres d''agence,');
    po('  4 caracteres de produit, puis une date julienne et un numero de sequence.');
    po('  On verifie ici que cette regle est respectee pour les operations MM.');

    show_dist('9.1 Longueur de CONTRACT_REF_NO',            'ldtb_contract_master', 'LENGTH(CONTRACT_REF_NO)',    'MODULE = ''MM''', 20, 'V');
    show_dist('9.2 Prefixe agence  (positions 1 a 3)',      'ldtb_contract_master', 'SUBSTR(CONTRACT_REF_NO,1,3)', 'MODULE = ''MM''', 30);
    show_dist('9.3 Prefixe produit (positions 4 a 7)',      'ldtb_contract_master', 'SUBSTR(CONTRACT_REF_NO,4,4)', 'MODULE = ''MM''', 40);
    show_dist('9.4 Segment date    (positions 8 a 10)',     'ldtb_contract_master', 'SUBSTR(CONTRACT_REF_NO,8,3)', 'MODULE = ''MM''', 20);
    show_dist('9.5 USER_REF_NO : renseigne ?',              'ldtb_contract_master',
              'CASE WHEN TRIM(USER_REF_NO) IS NULL THEN ''NON RENSEIGNE'' WHEN USER_REF_NO = CONTRACT_REF_NO THEN ''IDENTIQUE A LA REFERENCE'' ELSE ''REFERENCE EXTERNE PROPRE'' END',
              'MODULE = ''MM''');
    show_dist('9.6 INTERFACE_REF_NO : renseigne ?',         'ldtb_contract_master',
              'CASE WHEN TRIM(INTERFACE_REF_NO) IS NULL THEN ''NON RENSEIGNE'' ELSE ''RENSEIGNE'' END',
              'MODULE = ''MM''');
    show_dist('9.7 REL_REFERENCE : renseigne ?',            'ldtb_contract_master',
              'CASE WHEN TRIM(REL_REFERENCE) IS NULL THEN ''NON RENSEIGNE'' WHEN REL_REFERENCE = CONTRACT_REF_NO THEN ''IDENTIQUE A LA REFERENCE'' ELSE ''AUTRE REFERENCE'' END',
              'MODULE = ''MM''');
    show_dist('9.8 PARENT_CONTRACT_REF_NO : renseigne ?',   'ldtb_contract_master',
              'CASE WHEN TRIM(PARENT_CONTRACT_REF_NO) IS NULL THEN ''NON RENSEIGNE'' ELSE ''RENSEIGNE (contrat issu d''''un rollover)'' END',
              'MODULE = ''MM''');

    print_sub('9.9 Decomposition de 15 references MM (echantillon)');
    tbl_line('4,22,10,10,10,16,22,22');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 22) || '|' || fpad('AGENCE', 10) || '|'
        || fpad('PRODUIT', 10) || '|' || fpad('SEQ', 10) || '|' || fpad('BOOKING', 16) || '|'
        || fpad('USER_REF_NO', 22) || '|' || fpad('REL_REFERENCE', 22) || '|');
    tbl_line('4,22,10,10,10,16,22,22');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT contract_ref_no, booking_date, user_ref_no, rel_reference
                FROM ldtb_contract_master WHERE module = 'MM' ORDER BY booking_date DESC, contract_ref_no
              ) WHERE ROWNUM <= 15) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 22) || '|'
            || fpad(SUBSTR(r.contract_ref_no, 1, 3), 10) || '|' || fpad(SUBSTR(r.contract_ref_no, 4, 4), 10) || '|'
            || fpad(SUBSTR(r.contract_ref_no, 11), 10) || '|' || fpad(fdt(r.booking_date), 16) || '|'
            || fpad(r.user_ref_no, 22) || '|' || fpad(r.rel_reference, 22) || '|');
    END LOOP;
    tbl_line('4,22,10,10,10,16,22,22');

    -- =========================================================
    -- 10. STATISTIQUES MONTANTS, TAUX ET DUREES
    -- =========================================================
    print_section('10. MONTANTS, TAUX ET DUREES DES OPERATIONS MM');

    print_sub('10.1 Statistiques generales');
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master WHERE module = k_mod;
    print_kv('Nombre de contrats MM', fnum(v_cnt));
    FOR r IN (
        SELECT SUM(lcy_amount) s_lcy, AVG(lcy_amount) a_lcy, MIN(lcy_amount) mn_lcy, MAX(lcy_amount) mx_lcy,
               MEDIAN(lcy_amount) me_lcy,
               MIN(main_comp_rate) mn_r, MAX(main_comp_rate) mx_r, AVG(main_comp_rate) a_r,
               MIN(tenor) mn_t, MAX(tenor) mx_t, AVG(tenor) a_t,
               COUNT(main_comp_rate) nb_r, COUNT(tenor) nb_t
        FROM ldtb_contract_master WHERE module = 'MM'
    ) LOOP
        print_kv('Encours cumule LCY_AMOUNT',        famt(r.s_lcy) || '  (' || fmio(r.s_lcy) || ')');
        print_kv('Montant moyen (LCY)',              famt(r.a_lcy));
        print_kv('Montant median (LCY)',             famt(r.me_lcy));
        print_kv('Montant minimum (LCY)',            famt(r.mn_lcy));
        print_kv('Montant maximum (LCY)',            famt(r.mx_lcy));
        print_kv('Taux MAIN_COMP_RATE renseigne',    fnum(r.nb_r) || ' contrats');
        print_kv('Taux minimum / moyen / maximum',
                 TO_CHAR(r.mn_r, 'FM990D0000') || '  /  ' || TO_CHAR(r.a_r, 'FM990D0000') || '  /  ' || TO_CHAR(r.mx_r, 'FM990D0000'));
        print_kv('TENOR renseigne',                  fnum(r.nb_t) || ' contrats');
        print_kv('TENOR minimum / moyen / maximum',
                 fnum(r.mn_t) || '  /  ' || TO_CHAR(r.a_t, 'FM99990D0') || '  /  ' || fnum(r.mx_t));
    END LOOP;

    print_sub('10.2 Repartition par tranche de montant (LCY_AMOUNT)');
    tbl_line('26,12,12,22,10');
    po('  |' || fpad('TRANCHE', 26) || '|' || fpadl('NB', 12) || '|' || fpadl('% NB', 12) || '|'
        || fpadl('TOTAL LCY', 22) || '|' || fpadl('% MT', 10) || '|');
    tbl_line('26,12,12,22,10');
    SELECT COUNT(*), SUM(lcy_amount) INTO v_cnt, v_tot FROM ldtb_contract_master WHERE module = 'MM';
    FOR r IN (
        SELECT tranche, COUNT(*) nb, SUM(lcy_amount) tot FROM (
            SELECT CASE
                     WHEN lcy_amount IS NULL      THEN '0. non renseigne'
                     WHEN lcy_amount < 10000000   THEN '1. moins de 10 M'
                     WHEN lcy_amount < 50000000   THEN '2. 10 a 50 M'
                     WHEN lcy_amount < 100000000  THEN '3. 50 a 100 M'
                     WHEN lcy_amount < 500000000  THEN '4. 100 a 500 M'
                     WHEN lcy_amount < 1000000000 THEN '5. 500 M a 1 Md'
                     WHEN lcy_amount < 5000000000 THEN '6. 1 a 5 Md'
                     ELSE                              '7. 5 Md et plus'
                   END AS tranche
            FROM ldtb_contract_master WHERE module = 'MM')
        GROUP BY tranche ORDER BY tranche
    ) LOOP
        po('  |' || fpad(r.tranche, 26) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fpct(r.nb, v_cnt), 12) || '|'
            || fpadl(fmio(r.tot), 22) || '|' || fpadl(fpct(r.tot, v_tot), 10) || '|');
    END LOOP;
    tbl_line('26,12,12,22,10');

    print_sub('10.3 Repartition par tranche de taux (MAIN_COMP_RATE)');
    tbl_line('26,12,22,22');
    po('  |' || fpad('TRANCHE DE TAUX', 26) || '|' || fpadl('NB', 12) || '|' || fpadl('TOTAL LCY', 22) || '|'
        || fpadl('MONTANT MOYEN', 22) || '|');
    tbl_line('26,12,22,22');
    FOR r IN (
        SELECT tranche, COUNT(*) nb, SUM(lcy_amount) tot, AVG(lcy_amount) moy FROM (
            SELECT CASE
                     WHEN main_comp_rate IS NULL THEN '0. non renseigne'
                     WHEN main_comp_rate = 0     THEN '1. taux nul'
                     WHEN main_comp_rate < 2     THEN '2. moins de 2 %'
                     WHEN main_comp_rate < 4     THEN '3. 2 a 4 %'
                     WHEN main_comp_rate < 6     THEN '4. 4 a 6 %'
                     WHEN main_comp_rate < 8     THEN '5. 6 a 8 %'
                     WHEN main_comp_rate < 12    THEN '6. 8 a 12 %'
                     ELSE                             '7. 12 % et plus'
                   END AS tranche, lcy_amount
            FROM ldtb_contract_master WHERE module = 'MM')
        GROUP BY tranche ORDER BY tranche
    ) LOOP
        po('  |' || fpad(r.tranche, 26) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.tot), 22) || '|'
            || fpadl(famt(r.moy), 22) || '|');
    END LOOP;
    tbl_line('26,12,22,22');

    print_sub('10.4 Repartition par duree reelle (MATURITY_DATE - VALUE_DATE)');
    tbl_line('26,12,22,16,16');
    po('  |' || fpad('DUREE', 26) || '|' || fpadl('NB', 12) || '|' || fpadl('TOTAL LCY', 22) || '|'
        || fpadl('TAUX MOYEN', 16) || '|' || fpadl('JOURS MOYENS', 16) || '|');
    tbl_line('26,12,22,16,16');
    FOR r IN (
        SELECT tranche, COUNT(*) nb, SUM(lcy_amount) tot, AVG(main_comp_rate) tx, AVG(jours) jm FROM (
            SELECT CASE
                     WHEN maturity_date IS NULL OR value_date IS NULL THEN '0. dates incompletes'
                     WHEN maturity_date - value_date <= 1   THEN '1. au jour le jour'
                     WHEN maturity_date - value_date <= 7   THEN '2. 2 a 7 jours'
                     WHEN maturity_date - value_date <= 31  THEN '3. 8 a 31 jours'
                     WHEN maturity_date - value_date <= 92  THEN '4. 1 a 3 mois'
                     WHEN maturity_date - value_date <= 183 THEN '5. 3 a 6 mois'
                     WHEN maturity_date - value_date <= 366 THEN '6. 6 a 12 mois'
                     ELSE                                        '7. plus de 12 mois'
                   END AS tranche,
                   lcy_amount, main_comp_rate, (maturity_date - value_date) AS jours
            FROM ldtb_contract_master WHERE module = 'MM')
        GROUP BY tranche ORDER BY tranche
    ) LOOP
        po('  |' || fpad(r.tranche, 26) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.tot), 22) || '|'
            || fpadl(TO_CHAR(r.tx, 'FM990D0000'), 16) || '|' || fpadl(TO_CHAR(r.jm, 'FM99990D0'), 16) || '|');
    END LOOP;
    tbl_line('26,12,22,16,16');

    print_sub('10.5 Coherence TENOR declare / duree calculee');
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master
     WHERE module = 'MM' AND tenor IS NOT NULL AND maturity_date IS NOT NULL AND value_date IS NOT NULL
       AND tenor != (maturity_date - value_date);
    print_kv('Contrats ou TENOR <> MATURITY_DATE - VALUE_DATE', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master
     WHERE module = 'MM' AND maturity_date IS NOT NULL AND value_date IS NOT NULL AND maturity_date < value_date;
    print_kv('Contrats ou MATURITY_DATE < VALUE_DATE', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master
     WHERE module = 'MM' AND value_date IS NOT NULL AND booking_date IS NOT NULL AND value_date < booking_date;
    print_kv('Contrats ou VALUE_DATE < BOOKING_DATE (valeur retroactive)', fnum(v_cnt));

    -- =========================================================
    -- 11. LISTE DETAILLEE DES CONTRATS MM
    -- =========================================================
    print_section('11. LISTE DETAILLEE DES CONTRATS MM (100 PLUS RECENTS)');

    print_sub('11.1 Vue metier : contrepartie, montant, taux, echeance');
    tbl_line('4,20,7,12,26,5,18,8,11,11,6,4,11');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 20) || '|' || fpad('PROD', 7) || '|'
        || fpad('CIF', 12) || '|' || fpad('CONTREPARTIE', 26) || '|' || fpad('CCY', 5) || '|'
        || fpadl('MONTANT LCY', 18) || '|' || fpadl('TAUX', 8) || '|' || fpad('BOOKING', 11) || '|'
        || fpad('ECHEANCE', 11) || '|' || fpadl('JOURS', 6) || '|' || fpad('ST', 4) || '|' || fpad('DEALER', 11) || '|');
    tbl_line('4,20,7,12,26,5,18,8,11,11,6,4,11');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT m.contract_ref_no, m.product, m.counterparty, c.customer_name1, m.currency,
                       m.lcy_amount, m.main_comp_rate, m.booking_date, m.maturity_date,
                       (m.maturity_date - m.value_date) AS jours, m.contract_status, m.dealer
                FROM ldtb_contract_master m
                LEFT JOIN sttm_customer c ON c.customer_no = m.counterparty
                WHERE m.module = 'MM'
                ORDER BY m.booking_date DESC, m.contract_ref_no
              ) WHERE ROWNUM <= 100) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 20) || '|' || fpad(r.product, 7) || '|'
            || fpad(r.counterparty, 12) || '|' || fpad(r.customer_name1, 26) || '|' || fpad(r.currency, 5) || '|'
            || fpadl(famt(r.lcy_amount), 18) || '|' || fpadl(TO_CHAR(r.main_comp_rate, 'FM990D0000'), 8) || '|'
            || fpad(fdt(r.booking_date), 11) || '|' || fpad(fdt(r.maturity_date), 11) || '|'
            || fpadl(fnum(r.jours), 6) || '|' || fpad(r.contract_status, 4) || '|' || fpad(r.dealer, 11) || '|');
    END LOOP;
    tbl_line('4,20,7,12,26,5,18,8,11,11,6,4,11');

    print_sub('11.2 Vue technique : references croisees et commentaires');
    tbl_line('4,22,22,22,22,22,38');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 22) || '|' || fpad('USER_REF_NO', 22) || '|'
        || fpad('REL_REFERENCE', 22) || '|' || fpad('INTERFACE_REF_NO', 22) || '|'
        || fpad('PARENT_CONTRACT', 22) || '|' || fpad('REMARKS', 38) || '|');
    tbl_line('4,22,22,22,22,22,38');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT contract_ref_no, user_ref_no, rel_reference, interface_ref_no,
                       parent_contract_ref_no, remarks, booking_date
                FROM ldtb_contract_master WHERE module = 'MM'
                ORDER BY booking_date DESC, contract_ref_no
              ) WHERE ROWNUM <= 60) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 22) || '|' || fpad(r.user_ref_no, 22) || '|'
            || fpad(r.rel_reference, 22) || '|' || fpad(r.interface_ref_no, 22) || '|'
            || fpad(r.parent_contract_ref_no, 22) || '|' || fpad(r.remarks, 38) || '|');
    END LOOP;
    tbl_line('4,22,22,22,22,22,38');

    -- =========================================================
    -- 12. LES CONTREPARTIES DES OPERATIONS MM
    -- =========================================================
    print_section('12. LES CONTREPARTIES DES OPERATIONS MM');

    print_sub('12.1 Rapprochement avec le referentiel clients');
    SELECT COUNT(DISTINCT counterparty) INTO v_cnt FROM ldtb_contract_master WHERE module = k_mod;
    print_kv('Contreparties distinctes sur les contrats MM', fnum(v_cnt));
    SELECT COUNT(DISTINCT m.counterparty) INTO v_cnt2
      FROM ldtb_contract_master m
      JOIN sttm_customer c ON c.customer_no = m.counterparty
     WHERE m.module = 'MM';
    print_kv('Contreparties retrouvees dans STTM_CUSTOMER', fnum(v_cnt2));
    print_kv('Contreparties INCONNUES du referentiel', fnum(v_cnt - v_cnt2));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master m
     WHERE m.module = 'MM' AND (m.counterparty IS NULL OR TRIM(m.counterparty) IS NULL);
    print_kv('Contrats MM sans contrepartie renseignee', fnum(v_cnt));

    show_dist('12.2 Type de contrepartie (CUSTOMER_TYPE)',
              '(SELECT c.customer_type ct FROM ldtb_contract_master m JOIN sttm_customer c ON c.customer_no = m.counterparty WHERE m.module = ''MM'') x',
              'ct');
    show_dist('12.3 Categorie de contrepartie (CUSTOMER_CATEGORY)',
              '(SELECT c.customer_category cc FROM ldtb_contract_master m JOIN sttm_customer c ON c.customer_no = m.counterparty WHERE m.module = ''MM'') x',
              'cc', NULL, 30);
    show_dist('12.4 Pays de la contrepartie (COUNTRY)',
              '(SELECT c.country co FROM ldtb_contract_master m JOIN sttm_customer c ON c.customer_no = m.counterparty WHERE m.module = ''MM'') x',
              'co', NULL, 30);
    show_dist('12.5 Nationalite de la contrepartie',
              '(SELECT c.nationality na FROM ldtb_contract_master m JOIN sttm_customer c ON c.customer_no = m.counterparty WHERE m.module = ''MM'') x',
              'na', NULL, 30);
    show_dist('12.6 Niveau de risque KYC de la contrepartie',
              '(SELECT NVL(k.risk_level, ''SANS KYC'') rl FROM ldtb_contract_master m JOIN sttm_customer c ON c.customer_no = m.counterparty LEFT JOIN sttm_kyc_master k ON k.kyc_ref_no = c.kyc_ref_no WHERE m.module = ''MM'') x',
              'rl');

    print_sub('12.7 Top 40 des contreparties par encours MM');
    tbl_line('4,13,34,6,10,10,10,12,20,12');
    po('  |' || fpad('N#', 4) || '|' || fpad('CIF', 13) || '|' || fpad('CONTREPARTIE', 34) || '|'
        || fpad('TYPE', 6) || '|' || fpad('PAYS', 10) || '|' || fpad('NATION.', 10) || '|'
        || fpad('RISQUE', 10) || '|' || fpadl('NB CONTRATS', 12) || '|' || fpadl('TOTAL LCY', 20) || '|'
        || fpadl('TAUX MOYEN', 12) || '|');
    tbl_line('4,13,34,6,10,10,10,12,20,12');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT m.counterparty, NVL(c.customer_name1, '(inconnu du referentiel)') nom,
                       c.customer_type, c.country, c.nationality, NVL(k.risk_level, '-') risk,
                       COUNT(*) nb, SUM(m.lcy_amount) tot, AVG(m.main_comp_rate) tx
                FROM ldtb_contract_master m
                LEFT JOIN sttm_customer c   ON c.customer_no = m.counterparty
                LEFT JOIN sttm_kyc_master k ON k.kyc_ref_no  = c.kyc_ref_no
                WHERE m.module = 'MM'
                GROUP BY m.counterparty, c.customer_name1, c.customer_type, c.country, c.nationality, k.risk_level
                ORDER BY SUM(m.lcy_amount) DESC NULLS LAST
              ) WHERE ROWNUM <= 40) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.counterparty, 13) || '|' || fpad(r.nom, 34) || '|'
            || fpad(r.customer_type, 6) || '|' || fpad(r.country, 10) || '|' || fpad(r.nationality, 10) || '|'
            || fpad(r.risk, 10) || '|' || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.tot), 20) || '|'
            || fpadl(TO_CHAR(r.tx, 'FM990D0000'), 12) || '|');
    END LOOP;
    tbl_line('4,13,34,6,10,10,10,12,20,12');

    -- =========================================================
    -- 13. REFERENTIEL PRODUITS
    -- =========================================================
    print_section('13. REFERENTIEL DES PRODUITS MM / LD');

    print_sub('13.1 Produits declares dans CSTM_PRODUCT pour les modules MM et LD');
    tbl_line('4,10,44,8,14,12,10,10');
    po('  |' || fpad('N#', 4) || '|' || fpad('CODE', 10) || '|' || fpad('LIBELLE', 44) || '|'
        || fpad('MODULE', 8) || '|' || fpad('GROUPE', 14) || '|' || fpad('OUVERTURE', 12) || '|'
        || fpad('REC_STAT', 10) || '|' || fpad('AUTH', 10) || '|');
    tbl_line('4,10,44,8,14,12,10,10');
    v_row := 0;
    FOR r IN (SELECT product_code, product_description, module, product_group,
                     product_start_date, record_stat, auth_stat
              FROM cstm_product WHERE module IN ('MM', 'LD') ORDER BY module, product_code) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product_code, 10) || '|'
            || fpad(r.product_description, 44) || '|' || fpad(r.module, 8) || '|' || fpad(r.product_group, 14) || '|'
            || fpad(fdt(r.product_start_date), 12) || '|' || fpad(r.record_stat, 10) || '|' || fpad(r.auth_stat, 10) || '|');
    END LOOP;
    tbl_line('4,10,44,8,14,12,10,10');
    IF v_row = 0 THEN
        po('    (aucun produit CSTM_PRODUCT sur les modules MM / LD)');
    END IF;

    print_sub('13.2 Produits effectivement utilises par les contrats MM');
    tbl_line('4,10,40,12,20,12,10,10,10,10');
    po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('LIBELLE', 40) || '|'
        || fpadl('NB CONTRATS', 12) || '|' || fpadl('TOTAL LCY', 20) || '|' || fpadl('TAUX MOY', 12) || '|'
        || fpad('TYPE', 10) || '|' || fpad('ROLLOVER', 10) || '|' || fpad('CD', 10) || '|' || fpad('NEGOC.', 10) || '|');
    tbl_line('4,10,40,12,20,12,10,10,10,10');
    v_row := 0;
    FOR r IN (
        SELECT m.product, NVL(p.product_description, '(absent de CSTM_PRODUCT)') lib,
               COUNT(*) nb, SUM(m.lcy_amount) tot, AVG(m.main_comp_rate) tx,
               MAX(lp.product_type) ptype, MAX(lp.rollover_allowed) roll,
               MAX(lp.certificate_of_deposit) cd, MAX(lp.negotiable) nego
        FROM ldtb_contract_master m
        LEFT JOIN cstm_product p        ON p.product_code = m.product
        LEFT JOIN ldtm_product_master lp ON lp.product   = m.product
        WHERE m.module = 'MM'
        GROUP BY m.product, p.product_description
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 10) || '|' || fpad(r.lib, 40) || '|'
            || fpadl(fnum(r.nb), 12) || '|' || fpadl(fmio(r.tot), 20) || '|'
            || fpadl(TO_CHAR(r.tx, 'FM990D0000'), 12) || '|' || fpad(r.ptype, 10) || '|' || fpad(r.roll, 10) || '|'
            || fpad(r.cd, 10) || '|' || fpad(r.nego, 10) || '|');
    END LOOP;
    tbl_line('4,10,40,12,20,12,10,10,10,10');

    print_sub('13.3 Parametrage LDTM_PRODUCT_MASTER des produits utilises en MM');
    tbl_line('4,10,8,10,10,10,10,10,12,12,12');
    po('  |' || fpad('N#', 4) || '|' || fpad('PRODUIT', 10) || '|' || fpad('TYPE', 8) || '|'
        || fpadl('TEN.MIN', 10) || '|' || fpadl('TEN.STD', 10) || '|' || fpadl('TEN.MAX', 10) || '|'
        || fpad('UNITE', 10) || '|' || fpad('LIQUID.', 10) || '|' || fpadl('VAR.NORM', 12) || '|'
        || fpadl('VAR.MAX', 12) || '|' || fpad('INTRADAY', 12) || '|');
    tbl_line('4,10,8,10,10,10,10,10,12,12,12');
    v_row := 0;
    FOR r IN (
        SELECT lp.product, lp.product_type, lp.min_tenor, lp.std_tenor, lp.max_tenor, lp.tenor_unit,
               lp.liquidation_mode, lp.normal_rate_variance, lp.maximum_rate_variance, lp.intra_day_deal
        FROM ldtm_product_master lp
        WHERE lp.product IN (SELECT DISTINCT product FROM ldtb_contract_master WHERE module = 'MM')
        ORDER BY lp.product
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.product, 10) || '|' || fpad(r.product_type, 8) || '|'
            || fpadl(fnum(r.min_tenor), 10) || '|' || fpadl(fnum(r.std_tenor), 10) || '|'
            || fpadl(fnum(r.max_tenor), 10) || '|' || fpad(r.tenor_unit, 10) || '|'
            || fpad(r.liquidation_mode, 10) || '|' || fpadl(TO_CHAR(r.normal_rate_variance, 'FM990D00'), 12) || '|'
            || fpadl(TO_CHAR(r.maximum_rate_variance, 'FM990D00'), 12) || '|' || fpad(r.intra_day_deal, 12) || '|');
    END LOOP;
    tbl_line('4,10,8,10,10,10,10,10,12,12,12');

    -- =========================================================
    -- 14. LDTB_CONTRACT_MASTER vs LDTB_CONTRACT_MASTER_FCC
    -- =========================================================
    print_section('14. LDTB_CONTRACT_MASTER vs LDTB_CONTRACT_MASTER_FCC');
    po('  FLEXCUBE tient deux tables d''en-tete de contrat. Il faut determiner');
    po('  laquelle fait foi pour un audit des operations de marche monetaire.');

    print_kv('LDTB_CONTRACT_MASTER     - total',      f_lbl(f_count('LDTB_CONTRACT_MASTER')));
    print_kv('LDTB_CONTRACT_MASTER     - MM',         f_lbl(f_count('LDTB_CONTRACT_MASTER', 'MODULE = ''MM''')));
    print_kv('LDTB_CONTRACT_MASTER_FCC - total',      f_lbl(f_count('LDTB_CONTRACT_MASTER_FCC')));
    print_kv('LDTB_CONTRACT_MASTER_FCC - MM',         f_lbl(f_count('LDTB_CONTRACT_MASTER_FCC', 'MODULE = ''MM''')));

    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master m
     WHERE m.module = 'MM'
       AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master_fcc f WHERE f.contract_ref_no = m.contract_ref_no);
    print_kv('Contrats MM presents dans MASTER et absents de _FCC', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master_fcc f
     WHERE f.module = 'MM'
       AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m WHERE m.contract_ref_no = f.contract_ref_no);
    print_kv('Contrats MM presents dans _FCC et absents de MASTER', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master m
     JOIN ldtb_contract_master_fcc f ON f.contract_ref_no = m.contract_ref_no
     WHERE m.module = 'MM' AND NVL(m.lcy_amount, -1) != NVL(f.lcy_amount, -1);
    print_kv('Contrats MM avec un LCY_AMOUNT different entre les deux tables', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master m
     JOIN ldtb_contract_master_fcc f ON f.contract_ref_no = m.contract_ref_no
     WHERE m.module = 'MM' AND NVL(m.version_no, -1) != NVL(f.version_no, -1);
    print_kv('Contrats MM avec un VERSION_NO different entre les deux tables', fnum(v_cnt));

    profile_table('LDTB_CONTRACT_MASTER_FCC', 'MODULE = ''MM''',
                  'PROFIL DES COLONNES : LDTB_CONTRACT_MASTER_FCC  [MODULE = MM]');

    -- =========================================================
    -- 15. TABLES SATELLITES DU CONTRAT
    -- =========================================================
    print_section('15. TABLES SATELLITES DU CONTRAT SUR LE PERIMETRE MM');
    po('  Pour chaque table liee au contrat : volumetrie totale, volumetrie sur les');
    po('  seuls contrats MM et nombre de contrats MM concernes.');
    po('');

    tbl_line('4,36,16,16,16');
    po('  |' || fpad('N#', 4) || '|' || fpad('TABLE', 36) || '|' || fpadl('LIGNES TOTAL', 16) || '|'
        || fpadl('LIGNES MM', 16) || '|' || fpadl('CONTRATS MM', 16) || '|');
    tbl_line('4,36,16,16,16');
    v_row := 0;
    FOR t IN (
        SELECT tab FROM (
            SELECT 'LDTB_CONTRACT_PREFERENCE'       tab, 1 ord FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_BALANCE',            2 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_DETAILS',       3 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_CALC',          4 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SCHEDULES',          5 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_LIQ',                6 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_LIQ_SUMMARY',        7 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ROLLOVER',           8 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ROLL_INT_RATES',     9 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ACCRUAL_HISTORY',   10 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SWIFT_MESSAGE',     11 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_CONTROL',           12 FROM DUAL UNION ALL
            SELECT 'LDTB_HOLIDAY_CURRENCIES',         13 FROM DUAL UNION ALL
            SELECT 'LDTB_ACCRUAL_FOR_LIMITS',         14 FROM DUAL UNION ALL
            SELECT 'LDTB_COMPUTATION_HANDOFF',        15 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_BALANCE_FCC',       16 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_ICCF_DETAILS_FCC',  17 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_LIQ_SUMMARY_FCC',   18 FROM DUAL UNION ALL
            SELECT 'LDTB_CONTRACT_SCHEDULES_FCC',     19 FROM DUAL
        ) ORDER BY ord
    ) LOOP
        v_row := v_row + 1;
        v_cnt  := f_count(t.tab);
        v_cnt2 := f_count(t.tab,
                    'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')');
        v_cnt3 := -1;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(DISTINCT CONTRACT_REF_NO) FROM ' || t.tab
                || ' WHERE CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')'
                INTO v_cnt3;
        EXCEPTION
            WHEN OTHERS THEN v_cnt3 := -1;
        END;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(t.tab, 36) || '|'
            || fpadl(CASE WHEN v_cnt  < 0 THEN 'ABSENTE' ELSE fnum(v_cnt)  END, 16) || '|'
            || fpadl(CASE WHEN v_cnt2 < 0 THEN 'N/A'     ELSE fnum(v_cnt2) END, 16) || '|'
            || fpadl(CASE WHEN v_cnt3 < 0 THEN 'N/A'     ELSE fnum(v_cnt3) END, 16) || '|');
    END LOOP;
    tbl_line('4,36,16,16,16');

    -- Profils detailles des satellites les plus utiles
    profile_table('LDTB_CONTRACT_BALANCE',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_BALANCE (contrats MM) - encours');
    profile_table('LDTB_CONTRACT_ICCF_DETAILS',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_ICCF_DETAILS (contrats MM) - composantes d''interet');
    profile_table('LDTB_CONTRACT_ICCF_CALC',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_ICCF_CALC (contrats MM) - calcul des interets');
    profile_table('LDTB_CONTRACT_SCHEDULES',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_SCHEDULES (contrats MM) - echeanciers');
    profile_table('LDTB_CONTRACT_LIQ_SUMMARY',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_LIQ_SUMMARY (contrats MM) - liquidations');
    profile_table('LDTB_CONTRACT_ROLLOVER',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_ROLLOVER (contrats MM) - renouvellements');
    profile_table('LDTB_CONTRACT_SWIFT_MESSAGE',
                  'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')',
                  'PROFIL : LDTB_CONTRACT_SWIFT_MESSAGE (contrats MM) - confirmations');
    profile_table('LDTB_CONTRACT_ACCRUAL_HISTORY', 'MODULE = ''MM''',
                  'PROFIL : LDTB_CONTRACT_ACCRUAL_HISTORY [MODULE = MM] - provisions d''interets');

    print_sub('15.1 Contenu integral de LDTB_CONTRACT_CONTROL (verrous de saisie)');
    tbl_line('4,24,20,26,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 24) || '|' || fpad('PROCESS_CODE', 20) || '|'
        || fpad('ENTRY_BY', 26) || '|' || fpad('ENTRY_TIME', 20) || '|');
    tbl_line('4,24,20,26,20');
    v_row := 0;
    FOR r IN (SELECT contract_ref_no, process_code, entry_by, entry_time
              FROM ldtb_contract_control ORDER BY entry_time DESC) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 24) || '|'
            || fpad(r.process_code, 20) || '|' || fpad(r.entry_by, 26) || '|'
            || fpad(TO_CHAR(r.entry_time, 'DD/MM/YYYY HH24:MI'), 20) || '|');
    END LOOP;
    tbl_line('4,24,20,26,20');
    IF v_row = 0 THEN
        po('    (table vide)');
    END IF;

    -- =========================================================
    -- 16. CYCLE DE VIE DES OPERATIONS MM
    -- =========================================================
    print_section('16. CYCLE DE VIE DES OPERATIONS MM');

    print_sub('16.1 Etat du portefeuille a la date du rapport');
    SELECT COUNT(*) INTO v_tot FROM ldtb_contract_master WHERE module = k_mod;
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master
     WHERE module = 'MM' AND maturity_date IS NOT NULL AND maturity_date >= TRUNC(SYSDATE);
    print_kv('Contrats MM en cours (echeance a venir)', fnum(v_cnt) || '  ' || fpct(v_cnt, v_tot));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master
     WHERE module = 'MM' AND maturity_date IS NOT NULL AND maturity_date < TRUNC(SYSDATE);
    print_kv('Contrats MM echus', fnum(v_cnt) || '  ' || fpct(v_cnt, v_tot));
    SELECT NVL(SUM(lcy_amount), 0) INTO v_tot FROM ldtb_contract_master
     WHERE module = 'MM' AND maturity_date IS NOT NULL AND maturity_date >= TRUNC(SYSDATE);
    print_kv('Encours nominal des contrats MM en cours', famt(v_tot) || '  (' || fmio(v_tot) || ')');
    SELECT NVL(SUM(b.principal_outstanding_bal), 0) INTO v_tot
      FROM ldtb_contract_balance b
      JOIN ldtb_contract_master m ON m.contract_ref_no = b.contract_ref_no
     WHERE m.module = 'MM';
    print_kv('Somme PRINCIPAL_OUTSTANDING_BAL des contrats MM', famt(v_tot) || '  (' || fmio(v_tot) || ')');
    SELECT COUNT(*) INTO v_cnt
      FROM ldtb_contract_master m
      JOIN ldtb_contract_balance b ON b.contract_ref_no = m.contract_ref_no
     WHERE m.module = 'MM' AND m.maturity_date < TRUNC(SYSDATE) AND NVL(b.principal_outstanding_bal, 0) > 0;
    print_kv('Contrats MM echus avec un encours residuel > 0', fnum(v_cnt));

    print_sub('16.2 Renouvellements (rollover)');
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master WHERE module = 'MM' AND NVL(rollover_count, 0) > 0;
    print_kv('Contrats MM ayant ete renouveles au moins une fois', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM ldtb_contract_master WHERE module = 'MM' AND TRIM(parent_contract_ref_no) IS NOT NULL;
    print_kv('Contrats MM issus d''un contrat parent', fnum(v_cnt));
    show_dist('16.3 ROLLOVER_INDICATOR', 'ldtb_contract_master', 'ROLLOVER_INDICATOR', 'MODULE = ''MM''');
    show_dist('16.4 ROLLOVER_MECHANISM', 'ldtb_contract_master', 'ROLLOVER_MECHANISM', 'MODULE = ''MM''');
    show_dist('16.5 ROLLOVER_METHOD',    'ldtb_contract_master', 'ROLLOVER_METHOD',    'MODULE = ''MM''');

    show_dist('16.6 Statut de paiement des liquidations MM (LDTB_CONTRACT_LIQ_SUMMARY)',
              'ldtb_contract_liq_summary', 'PAYMENT_STATUS',
              'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')');
    show_dist('16.7 Composantes liquidees MM (LDTB_CONTRACT_LIQ)',
              'ldtb_contract_liq', 'COMPONENT',
              'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')');
    show_dist('16.8 Composantes d''interet MM (LDTB_CONTRACT_ICCF_DETAILS)',
              'ldtb_contract_iccf_details', 'COMPONENT',
              'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')');
    show_dist('16.9 Types d''echeance MM (LDTB_CONTRACT_SCHEDULES)',
              'ldtb_contract_schedules', 'SCHEDULE_TYPE',
              'CONTRACT_REF_NO IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE MODULE = ''MM'')');

    print_sub('16.10 Echantillon : interets calcules sur 25 contrats MM');
    tbl_line('4,22,12,12,12,20,10,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 22) || '|' || fpad('COMPOSANTE', 12) || '|'
        || fpad('DEBUT', 12) || '|' || fpad('FIN', 12) || '|' || fpadl('BASE', 20) || '|'
        || fpadl('TAUX', 10) || '|' || fpadl('INTERETS', 20) || '|');
    tbl_line('4,22,12,12,12,20,10,20');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT i.contract_ref_no, i.component, i.start_date, i.end_date,
                       i.basis_amount, i.rate, i.calculated_amount
                FROM ldtb_contract_iccf_calc i
                JOIN ldtb_contract_master m ON m.contract_ref_no = i.contract_ref_no
                WHERE m.module = 'MM'
                ORDER BY i.start_date DESC, i.contract_ref_no
              ) WHERE ROWNUM <= 25) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 22) || '|' || fpad(r.component, 12) || '|'
            || fpad(fdt(r.start_date), 12) || '|' || fpad(fdt(r.end_date), 12) || '|'
            || fpadl(famt(r.basis_amount), 20) || '|' || fpadl(TO_CHAR(r.rate, 'FM990D0000'), 10) || '|'
            || fpadl(famt(r.calculated_amount), 20) || '|');
    END LOOP;
    tbl_line('4,22,12,12,12,20,10,20');

    po('');
    po('  >>> FIN DU BLOC 2');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!! ERREUR BLOC 2 : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/


DECLARE
    -- ---------- Variables de travail ----------
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_row     NUMBER;
    v_dim     VARCHAR2(60);

    -- Motif de recherche de l'application CALYPSO (utilisateur applicatif)
    k_pat     VARCHAR2(30) := '%CALYPSO%';
    -- Module des operations de marche monetaire
    k_mod     VARCHAR2(4)  := 'MM';

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
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990D00');
    END;

    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G990D00') || ' M';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
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
    po('   BLOC 3/4 : LES ECRITURES COMPTABLES (ACTB_HISTORY)');
    po(v_sep);
    po('  ATTENTION : ACTB_HISTORY est volumineuse. Ce bloc peut demander');
    po('  plusieurs minutes d''execution.');

    -- =========================================================
    -- 17. CARTOGRAPHIE DE TOUS LES MODULES
    -- =========================================================
    print_section('17. ACTB_HISTORY : CARTOGRAPHIE PAR MODULE');
    po('  Permet de situer le poids du marche monetaire dans l''ensemble des');
    po('  ecritures et d''identifier les autres modules a surveiller.');
    po('');

    tbl_line('4,10,16,12,14,14,22,12');
    po('  |' || fpad('N#', 4) || '|' || fpad('MODULE', 10) || '|' || fpadl('NB ECRITURES', 16) || '|'
        || fpadl('% NB', 12) || '|' || fpad('1ERE ECRIT.', 14) || '|' || fpad('DER. ECRIT.', 14) || '|'
        || fpadl('TOTAL LCY', 22) || '|' || fpadl('NB USERS', 12) || '|');
    tbl_line('4,10,16,12,14,14,22,12');
    SELECT COUNT(*) INTO v_tot FROM actb_history;
    v_row := 0;
    FOR r IN (
        SELECT module, COUNT(*) nb, MIN(trn_dt) d1, MAX(trn_dt) d2,
               SUM(NVL(lcy_amount, 0)) tot, COUNT(DISTINCT user_id) nbu
        FROM actb_history
        GROUP BY module
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.module, 10) || '|' || fpadl(fnum(r.nb), 16) || '|'
            || fpadl(fpct(r.nb, v_tot), 12) || '|' || fpad(fdt(r.d1), 14) || '|' || fpad(fdt(r.d2), 14) || '|'
            || fpadl(fmio(r.tot), 22) || '|' || fpadl(fnum(r.nbu), 12) || '|');
    END LOOP;
    tbl_line('4,10,16,12,14,14,22,12');

    -- =========================================================
    -- 18. DETAIL DES ECRITURES DU MODULE MM
    -- =========================================================
    print_section('18. ACTB_HISTORY : ANALYSE MULTI-AXES DES ECRITURES DU MODULE MM');
    po('  Une seule lecture de la table, declinee sur onze axes d''analyse.');
    po('  C''est la photographie complete de la facon dont les operations de');
    po('  marche monetaire sont comptabilisees.');

    v_dim := '~';
    v_row := 0;
    FOR r IN (
        SELECT ord, dim, val, k, tot FROM (
            SELECT dd.ord AS ord,
                   dd.dim AS dim,
                   NVL(TRIM(CASE dd.dim
                        WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                        WHEN 'EVENT'          THEN h.event
                        WHEN 'TRN_CODE'       THEN h.trn_code
                        WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                        WHEN 'SENS'           THEN h.drcr_ind
                        WHEN 'PRODUIT'        THEN h.product
                        WHEN 'AGENCE'         THEN h.ac_branch
                        WHEN 'DEVISE'         THEN h.ac_ccy
                        WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                        WHEN 'SAISI_PAR'      THEN h.user_id
                        WHEN 'AUTORISE_PAR'   THEN h.auth_id
                        WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                   END), '(vide)') AS val,
                   COUNT(*) AS k,
                   SUM(NVL(h.lcy_amount, 0)) AS tot,
                   ROW_NUMBER() OVER (PARTITION BY dd.dim ORDER BY COUNT(*) DESC) AS rn
            FROM actb_history h
            CROSS JOIN (
                SELECT 'ANNEE' dim, 1 ord FROM DUAL UNION ALL
                SELECT 'EVENT',        2 FROM DUAL UNION ALL
                SELECT 'TRN_CODE',     3 FROM DUAL UNION ALL
                SELECT 'AMOUNT_TAG',   4 FROM DUAL UNION ALL
                SELECT 'SENS',         5 FROM DUAL UNION ALL
                SELECT 'PRODUIT',      6 FROM DUAL UNION ALL
                SELECT 'AGENCE',       7 FROM DUAL UNION ALL
                SELECT 'DEVISE',       8 FROM DUAL UNION ALL
                SELECT 'CLIENT_OU_GL', 9 FROM DUAL UNION ALL
                SELECT 'SAISI_PAR',   10 FROM DUAL UNION ALL
                SELECT 'AUTORISE_PAR',11 FROM DUAL UNION ALL
                SELECT 'REF_EXTERNE', 12 FROM DUAL
            ) dd
            WHERE h.module = 'MM'
            GROUP BY dd.ord, dd.dim,
                     NVL(TRIM(CASE dd.dim
                          WHEN 'ANNEE'          THEN TO_CHAR(h.trn_dt, 'YYYY')
                          WHEN 'EVENT'          THEN h.event
                          WHEN 'TRN_CODE'       THEN h.trn_code
                          WHEN 'AMOUNT_TAG'     THEN h.amount_tag
                          WHEN 'SENS'           THEN h.drcr_ind
                          WHEN 'PRODUIT'        THEN h.product
                          WHEN 'AGENCE'         THEN h.ac_branch
                          WHEN 'DEVISE'         THEN h.ac_ccy
                          WHEN 'CLIENT_OU_GL'   THEN h.cust_gl
                          WHEN 'SAISI_PAR'      THEN h.user_id
                          WHEN 'AUTORISE_PAR'   THEN h.auth_id
                          WHEN 'REF_EXTERNE'    THEN CASE WHEN TRIM(h.external_ref_no) IS NULL THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                     END), '(vide)')
        ) WHERE rn <= 25
        ORDER BY ord, DECODE(dim, 'ANNEE', val), k DESC
    ) LOOP
        IF r.dim != v_dim THEN
            v_dim := r.dim;
            print_sub('18.' || r.ord || ' Axe : ' || r.dim);
            tbl_line('34,16,22');
            po('  |' || fpad('VALEUR', 34) || '|' || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
            tbl_line('34,16,22');
        END IF;
        po('  |' || fpad(r.val, 34) || '|' || fpadl(fnum(r.k), 16) || '|' || fpadl(fmio(r.tot), 22) || '|');
        v_row := v_row + 1;
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucune ecriture comptable sur le module MM)');
    ELSE
        tbl_line('34,16,22');
    END IF;

    -- =========================================================
    -- 19. LIBELLES DES CODES UTILISES PAR LE MODULE MM
    -- =========================================================
    print_section('19. LIBELLES DES CODES TRANSACTION ET TAGS DE MONTANT DU MODULE MM');

    print_sub('19.1 Codes transaction (STTM_TRN_CODE)');
    tbl_line('4,10,50,14,16,22');
    po('  |' || fpad('N#', 4) || '|' || fpad('TRN_CODE', 10) || '|' || fpad('LIBELLE', 50) || '|'
        || fpad('SUIVI AML', 14) || '|' || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
    tbl_line('4,10,50,14,16,22');
    v_row := 0;
    FOR r IN (
        SELECT h.trn_code,
               (SELECT MAX(t.trn_desc)       FROM sttm_trn_code t WHERE t.trn_code = h.trn_code) lib,
               (SELECT MAX(t.aml_monitoring) FROM sttm_trn_code t WHERE t.trn_code = h.trn_code) aml,
               COUNT(*) nb, SUM(NVL(h.lcy_amount, 0)) tot
        FROM actb_history h
        WHERE h.module = 'MM'
        GROUP BY h.trn_code
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_code, 10) || '|' || fpad(r.lib, 50) || '|'
            || fpad(r.aml, 14) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.tot), 22) || '|');
    END LOOP;
    tbl_line('4,10,50,14,16,22');

    print_sub('19.2 Tags de montant (CSTB_AMOUNT_TAG)');
    tbl_line('4,24,46,16,22');
    po('  |' || fpad('N#', 4) || '|' || fpad('AMOUNT_TAG', 24) || '|' || fpad('LIBELLE', 46) || '|'
        || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
    tbl_line('4,24,46,16,22');
    v_row := 0;
    FOR r IN (
        SELECT h.amount_tag,
               (SELECT MAX(a.description) FROM cstb_amount_tag a
                 WHERE a.amount_tag = h.amount_tag AND a.module = 'MM') lib,
               COUNT(*) nb, SUM(NVL(h.lcy_amount, 0)) tot
        FROM actb_history h
        WHERE h.module = 'MM'
        GROUP BY h.amount_tag
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.amount_tag, 24) || '|' || fpad(r.lib, 46) || '|'
            || fpadl(fnum(r.nb), 16) || '|' || fpadl(fmio(r.tot), 22) || '|');
    END LOOP;
    tbl_line('4,24,46,16,22');

    -- =========================================================
    -- 20. RAPPROCHEMENT ECRITURES <-> CONTRATS MM
    -- =========================================================
    print_section('20. RAPPROCHEMENT ECRITURES COMPTABLES <-> CONTRATS MM');
    po('  Objectif : verifier que TRN_REF_NO d''ACTB_HISTORY correspond bien au');
    po('  CONTRACT_REF_NO du contrat. C''est la cle de jointure du script final.');

    SELECT COUNT(*), COUNT(DISTINCT trn_ref_no) INTO v_cnt, v_cnt2
      FROM actb_history WHERE module = k_mod;
    print_kv('Ecritures du module MM', fnum(v_cnt));
    print_kv('References de transaction distinctes', fnum(v_cnt2));

    SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_cnt
      FROM actb_history h
     WHERE h.module = 'MM'
       AND EXISTS (SELECT 1 FROM ldtb_contract_master m WHERE m.contract_ref_no = h.trn_ref_no);
    print_kv('Dont rattachees a un contrat LDTB_CONTRACT_MASTER', fnum(v_cnt));

    SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_cnt
      FROM actb_history h
     WHERE h.module = 'MM'
       AND NOT EXISTS (SELECT 1 FROM ldtb_contract_master m WHERE m.contract_ref_no = h.trn_ref_no);
    print_kv('Ecritures MM SANS contrat correspondant', fnum(v_cnt));

    SELECT COUNT(*) INTO v_cnt
      FROM ldtb_contract_master m
     WHERE m.module = 'MM'
       AND NOT EXISTS (SELECT 1 FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no);
    print_kv('Contrats MM SANS aucune ecriture comptable', fnum(v_cnt));

    print_sub('20.1 Ecritures MM par contrat : 30 contrats les plus mouvementes');
    tbl_line('4,22,12,14,14,20,20,26');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 22) || '|' || fpad('CIF', 12) || '|'
        || fpadl('NB ECRIT.', 14) || '|' || fpadl('NB EVENTS', 14) || '|' || fpadl('TOTAL DEBIT', 20) || '|'
        || fpadl('TOTAL CREDIT', 20) || '|' || fpad('SAISI PAR', 26) || '|');
    tbl_line('4,22,12,14,14,20,20,26');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT h.trn_ref_no,
                       (SELECT MAX(m.counterparty) FROM ldtb_contract_master m
                         WHERE m.contract_ref_no = h.trn_ref_no) cif,
                       COUNT(*) nb,
                       COUNT(DISTINCT h.event) nbe,
                       SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                       SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre,
                       MAX(h.user_id) usr
                FROM actb_history h
                WHERE h.module = 'MM'
                GROUP BY h.trn_ref_no
                ORDER BY COUNT(*) DESC
              ) WHERE ROWNUM <= 30) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_ref_no, 22) || '|' || fpad(r.cif, 12) || '|'
            || fpadl(fnum(r.nb), 14) || '|' || fpadl(fnum(r.nbe), 14) || '|' || fpadl(fmio(r.deb), 20) || '|'
            || fpadl(fmio(r.cre), 20) || '|' || fpad(r.usr, 26) || '|');
    END LOOP;
    tbl_line('4,22,12,14,14,20,20,26');

    -- =========================================================
    -- 21. COMPTES MOUVEMENTES PAR LE MODULE MM
    -- =========================================================
    print_section('21. COMPTES ET GENERAUX MOUVEMENTES PAR LE MODULE MM');

    print_sub('21.1 Top 40 des comptes mouvementes');
    tbl_line('4,22,32,8,8,14,20,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('AC_NO', 22) || '|' || fpad('LIBELLE COMPTE', 32) || '|'
        || fpad('CCY', 8) || '|' || fpad('C/GL', 8) || '|' || fpadl('NB ECRIT.', 14) || '|'
        || fpadl('TOTAL DEBIT', 20) || '|' || fpadl('TOTAL CREDIT', 20) || '|');
    tbl_line('4,22,32,8,8,14,20,20');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT h.ac_no,
                       (SELECT MAX(a.ac_desc) FROM sttm_cust_account a WHERE a.cust_ac_no = h.ac_no) lib,
                       MAX(h.ac_ccy) ccy, MAX(h.cust_gl) cgl, COUNT(*) nb,
                       SUM(CASE WHEN h.drcr_ind = 'D' THEN NVL(h.lcy_amount, 0) ELSE 0 END) deb,
                       SUM(CASE WHEN h.drcr_ind = 'C' THEN NVL(h.lcy_amount, 0) ELSE 0 END) cre
                FROM actb_history h
                WHERE h.module = 'MM'
                GROUP BY h.ac_no
                ORDER BY COUNT(*) DESC
              ) WHERE ROWNUM <= 40) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.lib, 32) || '|'
            || fpad(r.ccy, 8) || '|' || fpad(r.cgl, 8) || '|' || fpadl(fnum(r.nb), 14) || '|'
            || fpadl(fmio(r.deb), 20) || '|' || fpadl(fmio(r.cre), 20) || '|');
    END LOOP;
    tbl_line('4,22,32,8,8,14,20,20');

    -- =========================================================
    -- 22. ECHANTILLON D'ECRITURES MM
    -- =========================================================
    print_section('22. ECHANTILLON DES 40 DERNIERES ECRITURES DU MODULE MM');

    tbl_line('4,22,8,10,22,6,6,18,12,12,16,16');
    po('  |' || fpad('N#', 4) || '|' || fpad('TRN_REF_NO', 22) || '|' || fpad('EVENT', 8) || '|'
        || fpad('TRN_CODE', 10) || '|' || fpad('AC_NO', 22) || '|' || fpad('D/C', 6) || '|'
        || fpad('CCY', 6) || '|' || fpadl('MONTANT LCY', 18) || '|' || fpad('TRN_DT', 12) || '|'
        || fpad('VALUE_DT', 12) || '|' || fpad('SAISI PAR', 16) || '|' || fpad('AUTORISE PAR', 16) || '|');
    tbl_line('4,22,8,10,22,6,6,18,12,12,16,16');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT h.trn_ref_no, h.event, h.trn_code, h.ac_no, h.drcr_ind, h.ac_ccy,
                       h.lcy_amount, h.trn_dt, h.value_dt, h.user_id, h.auth_id
                FROM actb_history h
                WHERE h.module = 'MM'
                ORDER BY h.trn_dt DESC, h.trn_ref_no, h.ac_entry_sr_no
              ) WHERE ROWNUM <= 40) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.trn_ref_no, 22) || '|' || fpad(r.event, 8) || '|'
            || fpad(r.trn_code, 10) || '|' || fpad(r.ac_no, 22) || '|' || fpad(r.drcr_ind, 6) || '|'
            || fpad(r.ac_ccy, 6) || '|' || fpadl(famt(r.lcy_amount), 18) || '|' || fpad(fdt(r.trn_dt), 12) || '|'
            || fpad(fdt(r.value_dt), 12) || '|' || fpad(r.user_id, 16) || '|' || fpad(r.auth_id, 16) || '|');
    END LOOP;
    tbl_line('4,22,8,10,22,6,6,18,12,12,16,16');

    po('');
    po('  >>> FIN DU BLOC 3');

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!! ERREUR BLOC 3 : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/


DECLARE
    -- ---------- Variables de travail ----------
    v_sep     VARCHAR2(200) := RPAD('=', 120, '=');
    v_cnt     NUMBER;
    v_cnt2    NUMBER;
    v_cnt3    NUMBER;
    v_tot     NUMBER;
    v_row     NUMBER;
    v_dim     VARCHAR2(60);

    -- Motif de recherche de l'application CALYPSO (utilisateur applicatif)
    k_pat     VARCHAR2(30) := '%CALYPSO%';
    -- Module des operations de marche monetaire
    k_mod     VARCHAR2(4)  := 'MM';

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
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990');
    END;

    FUNCTION famt(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0), 'FM999G999G999G990D00');
    END;

    FUNCTION fmio(x NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(x, 0) / 1000000, 'FM999G999G990D00') || ' M';
    END;

    FUNCTION fdt(d DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(d, 'DD/MM/YYYY');
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
    po('   BLOC 4/4 : L''APPLICATION CALYPSOUSR, LES UTILISATEURS ET LES CONTROLES');
    po(v_sep);

    -- =========================================================
    -- 23. FICHE DES UTILISATEURS "CALYPSO"
    -- =========================================================
    print_section('23. FICHE DES UTILISATEURS CORRESPONDANT A ' || k_pat);
    po('  CALYPSOUSR est l''utilisateur applicatif par lequel l''outil de gestion');
    po('  des titres et des placements deverse ses operations dans FLEXCUBE.');
    po('  Sa fiche de securite dit tout de son niveau de privilege.');

    v_row := 0;
    FOR u IN (
        SELECT * FROM smtb_user
        WHERE user_id LIKE k_pat OR UPPER(NVL(user_name, ' ')) LIKE k_pat
        ORDER BY user_id
    ) LOOP
        v_row := v_row + 1;
        po('');
        po('  --- UTILISATEUR : ' || u.user_id || ' ---');
        print_kv('  Nom complet',                    u.user_name);
        print_kv('  Statut (USER_STATUS)',           u.user_status);
        print_kv('  Categorie (USER_CATEGORY)',      u.user_category);
        print_kv('  Date de debut',                  fdt(u.start_date));
        print_kv('  Date de fin',                    fdt(u.end_date));
        print_kv('  Statut change le',               fdt(u.status_changed_on));
        print_kv('  Mot de passe change le',         fdt(u.pwd_changed_on));
        print_kv('  Agence de rattachement',         u.home_branch);
        print_kv('  Module par defaut',              u.dflt_module);
        print_kv('  Fonction de demarrage',          u.startup_function);
        print_kv('  AUTO_AUTH (auto-autorisation)',  u.auto_auth);
        print_kv('  Utilisateur LDAP',               u.ldap_user);
        print_kv('  Reference externe (EXT_USER_REF)', u.ext_user_ref);
        print_kv('  Client rattache (CUSTOMER_NO)',  u.customer_no);
        print_kv('  Montant max de transaction',     famt(u.max_txn_amt));
        print_kv('  Montant max d''autorisation',    famt(u.max_auth_amt));
        print_kv('  Montant max de derogation',      famt(u.max_override_amt));
        print_kv('  Limite de transaction',          famt(u.user_txn_limit) || ' ' || NVL(u.limits_ccy, ''));
        print_kv('  Agences autorisees',             u.branches_allowed);
        print_kv('  Produits autorises',             u.products_allowed);
        print_kv('  Acces multi-agences',            u.multibranch_access);
        print_kv('  Email',                          u.user_email);
        print_kv('  Departement',                    u.dept_code);
        print_kv('  Cree par / le',                  u.maker_id || '  le  ' || fdt(u.maker_dt_stamp));
        print_kv('  Autorise par / le',              u.checker_id || '  le  ' || fdt(u.checker_dt_stamp));
        print_kv('  RECORD_STAT / AUTH_STAT',        u.record_stat || ' / ' || u.auth_stat);
        print_kv('  Nombre de modifications',        fnum(u.mod_no));

        -- Roles
        po('    Roles affectes :');
        v_cnt := 0;
        FOR rr IN (SELECT ur.role_id, ur.branch_code, ur.auth_stat, rm.role_description
                   FROM smtb_user_role ur
                   LEFT JOIN smtb_role_master rm ON rm.role_id = ur.role_id
                   WHERE ur.user_id = u.user_id
                   ORDER BY ur.role_id) LOOP
            v_cnt := v_cnt + 1;
            print_kv('      ' || rr.role_id || ' (agence ' || rr.branch_code || ')',
                     NVL(rr.role_description, '(sans libelle)') || '  [auth ' || rr.auth_stat || ']');
        END LOOP;
        IF v_cnt = 0 THEN
            po('      (aucun role affecte)');
        END IF;

        -- Connexions
        FOR lg IN (SELECT last_signed_on, no_cumulative_logins, no_successive_logins
                   FROM smtb_userlog_details WHERE user_id = u.user_id) LOOP
            print_kv('  Derniere connexion',         TO_CHAR(lg.last_signed_on, 'DD/MM/YYYY HH24:MI:SS'));
            print_kv('  Connexions cumulees',        fnum(lg.no_cumulative_logins));
            print_kv('  Connexions successives',     fnum(lg.no_successive_logins));
        END LOOP;

        -- Volumetrie de son activite
        print_kv('  Ecritures comptables saisies',
                 f_lbl(f_count('ACTB_HISTORY', 'USER_ID = ''' || u.user_id || '''')));
        print_kv('  Ecritures comptables autorisees',
                 f_lbl(f_count('ACTB_HISTORY', 'AUTH_ID = ''' || u.user_id || '''')));
        print_kv('  Sessions applicatives (SMTB_SMS_LOG)',
                 f_lbl(f_count('SMTB_SMS_LOG', 'USER_ID = ''' || u.user_id || '''')));
    END LOOP;
    IF v_row = 0 THEN
        po('');
        po('  !! AUCUN utilisateur ne correspond au motif ' || k_pat);
        po('     Voir la section 24 pour identifier le bon identifiant applicatif.');
    END IF;

    -- =========================================================
    -- 24. PANORAMA DES UTILISATEURS FLEXCUBE
    -- =========================================================
    print_section('24. PANORAMA DES UTILISATEURS FLEXCUBE');

    show_dist('24.1 USER_CATEGORY',       'smtb_user', 'USER_CATEGORY');
    show_dist('24.2 USER_STATUS',         'smtb_user', 'USER_STATUS');
    show_dist('24.3 AUTO_AUTH',           'smtb_user', 'AUTO_AUTH');
    show_dist('24.4 LDAP_USER',           'smtb_user', 'LDAP_USER');
    show_dist('24.5 DFLT_MODULE',         'smtb_user', 'DFLT_MODULE', NULL, 40);
    show_dist('24.6 HOME_BRANCH',         'smtb_user', 'HOME_BRANCH', NULL, 30);
    show_dist('24.7 RECORD_STAT',         'smtb_user', 'RECORD_STAT');

    print_sub('24.8 Utilisateurs a auto-autorisation (AUTO_AUTH = Y) : profils de type interface');
    tbl_line('4,18,34,12,12,12,12,20,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('USER_ID', 18) || '|' || fpad('NOM', 34) || '|'
        || fpad('CATEG.', 12) || '|' || fpad('STATUT', 12) || '|' || fpad('AGENCE', 12) || '|'
        || fpad('MODULE', 12) || '|' || fpadl('MAX TXN', 20) || '|' || fpadl('MAX AUTH', 20) || '|');
    tbl_line('4,18,34,12,12,12,12,20,20');
    v_row := 0;
    FOR r IN (SELECT user_id, user_name, user_category, user_status, home_branch, dflt_module,
                     max_txn_amt, max_auth_amt
              FROM smtb_user WHERE auto_auth = 'Y' ORDER BY user_id) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 18) || '|' || fpad(r.user_name, 34) || '|'
            || fpad(r.user_category, 12) || '|' || fpad(r.user_status, 12) || '|' || fpad(r.home_branch, 12) || '|'
            || fpad(r.dflt_module, 12) || '|' || fpadl(famt(r.max_txn_amt), 20) || '|'
            || fpadl(famt(r.max_auth_amt), 20) || '|');
    END LOOP;
    tbl_line('4,18,34,12,12,12,12,20,20');
    IF v_row = 0 THEN
        po('    (aucun utilisateur en auto-autorisation)');
    END IF;

    print_sub('24.9 Utilisateurs dont le module par defaut est MM ou LD');
    tbl_line('4,18,34,12,12,12,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('USER_ID', 18) || '|' || fpad('NOM', 34) || '|'
        || fpad('MODULE', 12) || '|' || fpad('STATUT', 12) || '|' || fpad('AGENCE', 12) || '|'
        || fpad('DERNIERE CONNEXION', 20) || '|');
    tbl_line('4,18,34,12,12,12,20');
    v_row := 0;
    FOR r IN (SELECT u.user_id, u.user_name, u.dflt_module, u.user_status, u.home_branch, l.last_signed_on
              FROM smtb_user u
              LEFT JOIN smtb_userlog_details l ON l.user_id = u.user_id
              WHERE u.dflt_module IN ('MM', 'LD') ORDER BY u.user_id) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 18) || '|' || fpad(r.user_name, 34) || '|'
            || fpad(r.dflt_module, 12) || '|' || fpad(r.user_status, 12) || '|' || fpad(r.home_branch, 12) || '|'
            || fpad(fdt(r.last_signed_on), 20) || '|');
    END LOOP;
    tbl_line('4,18,34,12,12,12,20');
    IF v_row = 0 THEN
        po('    (aucun utilisateur rattache par defaut aux modules MM / LD)');
    END IF;

    print_sub('24.10 Roles dont le nom evoque la tresorerie ou CALYPSO');
    v_row := 0;
    FOR r IN (SELECT role_id, role_description, record_stat, auth_stat,
                     (SELECT COUNT(*) FROM smtb_user_role ur WHERE ur.role_id = rm.role_id) nbu
              FROM smtb_role_master rm
              WHERE UPPER(role_id) LIKE '%CALYPSO%' OR UPPER(role_id) LIKE '%TRESO%'
                 OR UPPER(role_id) LIKE '%TREASUR%' OR UPPER(role_id) LIKE '%DEAL%'
                 OR UPPER(NVL(role_description, ' ')) LIKE '%TREASUR%'
                 OR UPPER(NVL(role_description, ' ')) LIKE '%MONEY MARKET%'
              ORDER BY role_id) LOOP
        v_row := v_row + 1;
        print_kv('  ' || r.role_id, NVL(r.role_description, '(sans libelle)')
                 || '  [' || r.record_stat || '/' || r.auth_stat || ']  '
                 || fnum(r.nbu) || ' utilisateur(s)');
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucun role correspondant)');
    END IF;

    -- =========================================================
    -- 25. ECRANS FLEXCUBE DES MODULES MM ET LD
    -- =========================================================
    print_section('25. ECRANS (FONCTIONS) DES MODULES MM ET LD');
    po('  Les FUNCTION_ID identifient les ecrans utilises. Ils servent a lire le');
    po('  journal SMTB_SMS_LOG et les champs personnalises (UDF).');
    po('');

    tbl_line('4,14,10,50,12,12');
    po('  |' || fpad('N#', 4) || '|' || fpad('FUNCTION_ID', 14) || '|' || fpad('MODULE', 10) || '|'
        || fpad('DESCRIPTION', 50) || '|' || fpad('AUTO_AUTH', 12) || '|' || fpad('DISPONIBLE', 12) || '|');
    tbl_line('4,14,10,50,12,12');
    v_row := 0;
    FOR r IN (SELECT m.function_id, m.module, m.auto_auth, m.available,
                     (SELECT MAX(d.description) FROM smtb_function_description d
                       WHERE d.function_id = m.function_id) descr
              FROM smtb_menu m
              WHERE m.module IN ('MM', 'LD')
              ORDER BY m.module, m.function_id) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.function_id, 14) || '|' || fpad(r.module, 10) || '|'
            || fpad(r.descr, 50) || '|' || fpad(r.auto_auth, 12) || '|' || fpad(r.available, 12) || '|');
    END LOOP;
    tbl_line('4,14,10,50,12,12');
    IF v_row = 0 THEN
        po('    (aucun ecran declare sur les modules MM / LD)');
    END IF;

    -- =========================================================
    -- 26. ACTIVITE DE CALYPSO DANS LES ECRITURES COMPTABLES
    -- =========================================================
    print_section('26. ACTIVITE DE ' || k_pat || ' DANS ACTB_HISTORY (TOUS MODULES)');
    po('  Meme principe qu''en section 18 : une seule lecture, plusieurs axes.');
    po('  Objectif : savoir quels modules et quels types d''operations transitent');
    po('  reellement par l''application externe.');

    v_dim := '~';
    v_row := 0;
    FOR r IN (
        SELECT ord, dim, val, k, tot FROM (
            SELECT dd.ord AS ord,
                   dd.dim AS dim,
                   NVL(TRIM(CASE dd.dim
                        WHEN 'MODULE'        THEN h.module
                        WHEN 'ANNEE'         THEN TO_CHAR(h.trn_dt, 'YYYY')
                        WHEN 'EVENT'         THEN h.event
                        WHEN 'TRN_CODE'      THEN h.trn_code
                        WHEN 'AMOUNT_TAG'    THEN h.amount_tag
                        WHEN 'PRODUIT'       THEN h.product
                        WHEN 'AGENCE'        THEN h.ac_branch
                        WHEN 'DEVISE'        THEN h.ac_ccy
                        WHEN 'SENS'          THEN h.drcr_ind
                        WHEN 'SAISI_PAR'     THEN h.user_id
                        WHEN 'AUTORISE_PAR'  THEN h.auth_id
                        WHEN 'REF_EXTERNE'   THEN CASE WHEN TRIM(h.external_ref_no) IS NULL THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                   END), '(vide)') AS val,
                   COUNT(*) AS k,
                   SUM(NVL(h.lcy_amount, 0)) AS tot,
                   ROW_NUMBER() OVER (PARTITION BY dd.dim ORDER BY COUNT(*) DESC) AS rn
            FROM actb_history h
            CROSS JOIN (
                SELECT 'MODULE' dim, 1 ord FROM DUAL UNION ALL
                SELECT 'ANNEE',        2 FROM DUAL UNION ALL
                SELECT 'EVENT',        3 FROM DUAL UNION ALL
                SELECT 'TRN_CODE',     4 FROM DUAL UNION ALL
                SELECT 'AMOUNT_TAG',   5 FROM DUAL UNION ALL
                SELECT 'PRODUIT',      6 FROM DUAL UNION ALL
                SELECT 'AGENCE',       7 FROM DUAL UNION ALL
                SELECT 'DEVISE',       8 FROM DUAL UNION ALL
                SELECT 'SENS',         9 FROM DUAL UNION ALL
                SELECT 'SAISI_PAR',   10 FROM DUAL UNION ALL
                SELECT 'AUTORISE_PAR',11 FROM DUAL UNION ALL
                SELECT 'REF_EXTERNE', 12 FROM DUAL
            ) dd
            WHERE h.user_id LIKE k_pat OR h.auth_id LIKE k_pat
            GROUP BY dd.ord, dd.dim,
                     NVL(TRIM(CASE dd.dim
                          WHEN 'MODULE'        THEN h.module
                          WHEN 'ANNEE'         THEN TO_CHAR(h.trn_dt, 'YYYY')
                          WHEN 'EVENT'         THEN h.event
                          WHEN 'TRN_CODE'      THEN h.trn_code
                          WHEN 'AMOUNT_TAG'    THEN h.amount_tag
                          WHEN 'PRODUIT'       THEN h.product
                          WHEN 'AGENCE'        THEN h.ac_branch
                          WHEN 'DEVISE'        THEN h.ac_ccy
                          WHEN 'SENS'          THEN h.drcr_ind
                          WHEN 'SAISI_PAR'     THEN h.user_id
                          WHEN 'AUTORISE_PAR'  THEN h.auth_id
                          WHEN 'REF_EXTERNE'   THEN CASE WHEN TRIM(h.external_ref_no) IS NULL THEN 'NON RENSEIGNEE' ELSE 'RENSEIGNEE' END
                     END), '(vide)')
        ) WHERE rn <= 25
        ORDER BY ord, DECODE(dim, 'ANNEE', val), k DESC
    ) LOOP
        IF r.dim != v_dim THEN
            v_dim := r.dim;
            print_sub('26.' || r.ord || ' Axe : ' || r.dim);
            tbl_line('34,16,22');
            po('  |' || fpad('VALEUR', 34) || '|' || fpadl('NB ECRITURES', 16) || '|' || fpadl('TOTAL LCY', 22) || '|');
            tbl_line('34,16,22');
        END IF;
        po('  |' || fpad(r.val, 34) || '|' || fpadl(fnum(r.k), 16) || '|' || fpadl(fmio(r.tot), 22) || '|');
        v_row := v_row + 1;
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucune ecriture comptable pour ce motif d''utilisateur)');
    ELSE
        tbl_line('34,16,22');
    END IF;

    print_sub('26.13 Top 30 des utilisateurs par nombre d''ecritures (tous modules)');
    po('  Sert a situer le poids de l''application externe par rapport aux agents.');
    po('');
    tbl_line('4,20,16,12,14,14,22,26');
    po('  |' || fpad('N#', 4) || '|' || fpad('USER_ID', 20) || '|' || fpadl('NB ECRITURES', 16) || '|'
        || fpadl('% TOTAL', 12) || '|' || fpad('1ERE', 14) || '|' || fpad('DERNIERE', 14) || '|'
        || fpadl('TOTAL LCY', 22) || '|' || fpad('MODULES TOUCHES', 26) || '|');
    tbl_line('4,20,16,12,14,14,22,26');
    SELECT COUNT(*) INTO v_tot FROM actb_history;
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT user_id, SUM(nb) nb, MIN(d1) d1, MAX(d2) d2, SUM(tot) tot,
                       LISTAGG(module, ',') WITHIN GROUP (ORDER BY module) mods
                FROM (
                    SELECT h.user_id, h.module, COUNT(*) nb, MIN(h.trn_dt) d1, MAX(h.trn_dt) d2,
                           SUM(NVL(h.lcy_amount, 0)) tot
                    FROM actb_history h
                    GROUP BY h.user_id, h.module
                )
                GROUP BY user_id
                ORDER BY SUM(nb) DESC
              ) WHERE ROWNUM <= 30) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.user_id, 20) || '|' || fpadl(fnum(r.nb), 16) || '|'
            || fpadl(fpct(r.nb, v_tot), 12) || '|' || fpad(fdt(r.d1), 14) || '|' || fpad(fdt(r.d2), 14) || '|'
            || fpadl(fmio(r.tot), 22) || '|' || fpad(r.mods, 26) || '|');
    END LOOP;
    tbl_line('4,20,16,12,14,14,22,26');

    -- =========================================================
    -- 27. JOURNAL DES SESSIONS APPLICATIVES
    -- =========================================================
    print_section('27. JOURNAL SMTB_SMS_LOG : SESSIONS ET FONCTIONS UTILISEES');

    print_sub('27.1 Volumetrie generale du journal');
    print_kv('Total des lignes de journal',       f_lbl(f_count('SMTB_SMS_LOG')));
    print_kv('Lignes de ' || k_pat,               f_lbl(f_count('SMTB_SMS_LOG', 'USER_ID LIKE ''' || k_pat || '''')));

    v_dim := '~';
    v_row := 0;
    FOR r IN (
        SELECT ord, dim, val, k FROM (
            SELECT dd.ord AS ord,
                   dd.dim AS dim,
                   NVL(TRIM(CASE dd.dim
                        WHEN 'UTILISATEUR' THEN s.user_id
                        WHEN 'ANNEE'       THEN TO_CHAR(s.start_time, 'YYYY')
                        WHEN 'FUNCTION_ID' THEN s.function_id
                        WHEN 'MODULE_CODE' THEN s.module_code
                        WHEN 'AGENCE'      THEN s.branch_code
                        WHEN 'TERMINAL'    THEN s.terminal_id
                        WHEN 'LOG_TYPE'    THEN s.log_type
                   END), '(vide)') AS val,
                   COUNT(*) AS k,
                   ROW_NUMBER() OVER (PARTITION BY dd.dim ORDER BY COUNT(*) DESC) AS rn
            FROM smtb_sms_log s
            CROSS JOIN (
                SELECT 'UTILISATEUR' dim, 1 ord FROM DUAL UNION ALL
                SELECT 'ANNEE',            2 FROM DUAL UNION ALL
                SELECT 'FUNCTION_ID',      3 FROM DUAL UNION ALL
                SELECT 'MODULE_CODE',      4 FROM DUAL UNION ALL
                SELECT 'AGENCE',           5 FROM DUAL UNION ALL
                SELECT 'TERMINAL',         6 FROM DUAL UNION ALL
                SELECT 'LOG_TYPE',         7 FROM DUAL
            ) dd
            WHERE s.user_id LIKE k_pat
            GROUP BY dd.ord, dd.dim,
                     NVL(TRIM(CASE dd.dim
                          WHEN 'UTILISATEUR' THEN s.user_id
                          WHEN 'ANNEE'       THEN TO_CHAR(s.start_time, 'YYYY')
                          WHEN 'FUNCTION_ID' THEN s.function_id
                          WHEN 'MODULE_CODE' THEN s.module_code
                          WHEN 'AGENCE'      THEN s.branch_code
                          WHEN 'TERMINAL'    THEN s.terminal_id
                          WHEN 'LOG_TYPE'    THEN s.log_type
                     END), '(vide)')
        ) WHERE rn <= 25
        ORDER BY ord, DECODE(dim, 'ANNEE', val), k DESC
    ) LOOP
        IF r.dim != v_dim THEN
            v_dim := r.dim;
            print_sub('27.' || (r.ord + 1) || ' Axe : ' || r.dim);
            tbl_line('40,16');
            po('  |' || fpad('VALEUR', 40) || '|' || fpadl('NB LIGNES', 16) || '|');
            tbl_line('40,16');
        END IF;
        po('  |' || fpad(r.val, 40) || '|' || fpadl(fnum(r.k), 16) || '|');
        v_row := v_row + 1;
    END LOOP;
    IF v_row = 0 THEN
        po('    (aucune ligne de journal pour ce motif d''utilisateur)');
    ELSE
        tbl_line('40,16');
    END IF;

    print_sub('27.9 Ecrans les plus utilises sur les modules MM et LD (tous utilisateurs)');
    tbl_line('4,14,12,44,16,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('FUNCTION_ID', 14) || '|' || fpad('MODULE', 12) || '|'
        || fpad('DESCRIPTION', 44) || '|' || fpadl('NB ACCES', 16) || '|' || fpadl('NB USERS', 20) || '|');
    tbl_line('4,14,12,44,16,20');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT s.function_id, MAX(s.module_code) mc, COUNT(*) nb, COUNT(DISTINCT s.user_id) nbu,
                       (SELECT MAX(d.description) FROM smtb_function_description d
                         WHERE d.function_id = s.function_id) descr
                FROM smtb_sms_log s
                WHERE s.module_code IN ('MM', 'LD')
                GROUP BY s.function_id
                ORDER BY COUNT(*) DESC
              ) WHERE ROWNUM <= 30) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.function_id, 14) || '|' || fpad(r.mc, 12) || '|'
            || fpad(r.descr, 44) || '|' || fpadl(fnum(r.nb), 16) || '|' || fpadl(fnum(r.nbu), 20) || '|');
    END LOOP;
    tbl_line('4,14,12,44,16,20');
    IF v_row = 0 THEN
        po('    (aucune trace de journal sur les modules MM / LD)');
    END IF;

    -- =========================================================
    -- 28. CROISEMENT MARCHE MONETAIRE x APPLICATION EXTERNE
    -- =========================================================
    print_section('28. CROISEMENT : QUI SAISIT LES OPERATIONS DE MARCHE MONETAIRE ?');

    print_sub('28.1 Contrats MM selon l''utilisateur des ecritures comptables');
    tbl_line('4,22,18,18,14,14,22');
    po('  |' || fpad('N#', 4) || '|' || fpad('SAISI PAR', 22) || '|' || fpad('AUTORISE PAR', 18) || '|'
        || fpadl('NB CONTRATS', 18) || '|' || fpadl('NB ECRITURES', 14) || '|' || fpad('DERNIERE', 14) || '|'
        || fpadl('TOTAL LCY', 22) || '|');
    tbl_line('4,22,18,18,14,14,22');
    v_row := 0;
    FOR r IN (
        SELECT NVL(TRIM(h.user_id), '(vide)') usr, NVL(TRIM(h.auth_id), '(vide)') aut,
               COUNT(DISTINCT h.trn_ref_no) nbc, COUNT(*) nb, MAX(h.trn_dt) d2,
               SUM(NVL(h.lcy_amount, 0)) tot
        FROM actb_history h
        WHERE h.module = 'MM'
        GROUP BY NVL(TRIM(h.user_id), '(vide)'), NVL(TRIM(h.auth_id), '(vide)')
        ORDER BY COUNT(*) DESC
    ) LOOP
        v_row := v_row + 1;
        EXIT WHEN v_row > 40;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.usr, 22) || '|' || fpad(r.aut, 18) || '|'
            || fpadl(fnum(r.nbc), 18) || '|' || fpadl(fnum(r.nb), 14) || '|' || fpad(fdt(r.d2), 14) || '|'
            || fpadl(fmio(r.tot), 22) || '|');
    END LOOP;
    tbl_line('4,22,18,18,14,14,22');
    IF v_row = 0 THEN
        po('    (aucune ecriture comptable sur le module MM)');
    END IF;

    print_sub('28.2 Volumetrie croisee module x application externe');
    SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_cnt
      FROM actb_history h WHERE h.module = 'MM' AND (h.user_id LIKE k_pat OR h.auth_id LIKE k_pat);
    print_kv('Contrats MM touches par ' || k_pat, fnum(v_cnt));
    SELECT COUNT(DISTINCT h.trn_ref_no) INTO v_cnt
      FROM actb_history h WHERE h.module = 'MM' AND h.user_id NOT LIKE k_pat AND NVL(h.auth_id, 'X') NOT LIKE k_pat;
    print_kv('Contrats MM touches uniquement par d''autres utilisateurs', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM actb_history h
     WHERE h.module = 'MM' AND h.user_id = h.auth_id;
    print_kv('Ecritures MM ou le saisisseur est aussi l''autorisateur', fnum(v_cnt));
    SELECT COUNT(*) INTO v_cnt FROM actb_history h
     WHERE (h.user_id LIKE k_pat OR h.auth_id LIKE k_pat) AND h.user_id = h.auth_id;
    print_kv('Ecritures ' || k_pat || ' auto-autorisees', fnum(v_cnt));

    print_sub('28.3 Contrats MM et utilisateur d''origine (30 plus recents)');
    tbl_line('4,22,12,26,18,18,12,18');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTRACT_REF_NO', 22) || '|' || fpad('CIF', 12) || '|'
        || fpad('CONTREPARTIE', 26) || '|' || fpad('SAISI PAR', 18) || '|' || fpad('AUTORISE PAR', 18) || '|'
        || fpad('BOOKING', 12) || '|' || fpadl('MONTANT LCY', 18) || '|');
    tbl_line('4,22,12,26,18,18,12,18');
    v_row := 0;
    FOR r IN (SELECT * FROM (
                SELECT m.contract_ref_no, m.counterparty, c.customer_name1, m.booking_date, m.lcy_amount,
                       (SELECT MIN(h.user_id) FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no) usr,
                       (SELECT MIN(h.auth_id) FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no) aut
                FROM ldtb_contract_master m
                LEFT JOIN sttm_customer c ON c.customer_no = m.counterparty
                WHERE m.module = 'MM'
                ORDER BY m.booking_date DESC, m.contract_ref_no
              ) WHERE ROWNUM <= 30) LOOP
        v_row := v_row + 1;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(r.contract_ref_no, 22) || '|' || fpad(r.counterparty, 12) || '|'
            || fpad(r.customer_name1, 26) || '|' || fpad(r.usr, 18) || '|' || fpad(r.aut, 18) || '|'
            || fpad(fdt(r.booking_date), 12) || '|' || fpadl(famt(r.lcy_amount), 18) || '|');
    END LOOP;
    tbl_line('4,22,12,26,18,18,12,18');

    -- =========================================================
    -- 29. CHAMPS PERSONNALISES (UDF) DES ECRANS MM / LD
    -- =========================================================
    print_section('29. CHAMPS PERSONNALISES (UDF) DES ECRANS MM ET LD');
    po('  La banque personnalise souvent FLEXCUBE via des champs libres stockes');
    po('  dans CSTM_FUNCTION_USERDEF_FIELDS. On regarde ici s''il en existe pour');
    po('  les operations de marche monetaire.');

    v_cnt := f_count('CSTM_FUNCTION_USERDEF_FIELDS');
    print_kv('CSTM_FUNCTION_USERDEF_FIELDS', f_lbl(v_cnt));
    IF v_cnt > 0 THEN
        show_dist('29.1 FUNCTION_ID commencant par LD, MM, CS ou SE',
                  'cstm_function_userdef_fields', 'FUNCTION_ID',
                  'FUNCTION_ID LIKE ''LD%'' OR FUNCTION_ID LIKE ''MM%'' OR FUNCTION_ID LIKE ''SE%''', 40);
        show_dist('29.2 Tous les FUNCTION_ID presents (top 60)',
                  'cstm_function_userdef_fields', 'FUNCTION_ID', NULL, 60);

        print_sub('29.3 Echantillon des UDF rattaches aux ecrans LD / MM');
        DECLARE
            TYPE t_cur IS REF CURSOR;
            c    t_cur;
            v_fi VARCHAR2(100);
            v_rk VARCHAR2(400);
            v_f1 VARCHAR2(400);
            v_f2 VARCHAR2(400);
            v_f3 VARCHAR2(400);
            v_f4 VARCHAR2(400);
        BEGIN
            v_row := 0;
            OPEN c FOR
                'SELECT * FROM ('
             || '  SELECT function_id, rec_key, field_val_1, field_val_2, field_val_3, field_val_4'
             || '  FROM cstm_function_userdef_fields'
             || '  WHERE function_id LIKE ''LD%'' OR function_id LIKE ''MM%'''
             || '  ORDER BY function_id, rec_key) WHERE ROWNUM <= 20';
            LOOP
                FETCH c INTO v_fi, v_rk, v_f1, v_f2, v_f3, v_f4;
                EXIT WHEN c%NOTFOUND;
                v_row := v_row + 1;
                po('    --- ' || v_fi || ' | ' || v_rk || ' ---');
                print_kv('      FIELD_VAL_1', v_f1);
                print_kv('      FIELD_VAL_2', v_f2);
                print_kv('      FIELD_VAL_3', v_f3);
                print_kv('      FIELD_VAL_4', v_f4);
            END LOOP;
            CLOSE c;
            IF v_row = 0 THEN
                po('    (aucun UDF rattache aux ecrans LD / MM)');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF c%ISOPEN THEN
                    CLOSE c;
                END IF;
                po('    !! ' || SQLERRM);
        END;
    END IF;

    -- =========================================================
    -- 30. CONTROLES PREPARATOIRES POUR LE SCRIPT D'AUDIT FINAL
    -- =========================================================
    print_section('30. CONTROLES PREPARATOIRES : DIMENSIONNEMENT DES FUTURS TESTS');
    po('  Chaque ligne est un test candidat du futur script d''audit des operations');
    po('  de marche monetaire. Le chiffre indique le nombre de cas concernes ;');
    po('  il permettra de retenir les tests pertinents et de calibrer les seuils.');
    po('');

    tbl_line('4,74,14,20');
    po('  |' || fpad('N#', 4) || '|' || fpad('CONTROLE CANDIDAT', 74) || '|' || fpadl('NB CAS', 14) || '|'
        || fpadl('MONTANT LCY', 20) || '|');
    tbl_line('4,74,14,20');
    v_row := 0;
    FOR t IN (
        SELECT lib, cond FROM (
            SELECT 'Contrepartie absente du referentiel clients' lib,
                   'NOT EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty)' cond, 1 ord FROM DUAL UNION ALL
            SELECT 'Contrepartie non renseignee',
                   'TRIM(m.counterparty) IS NULL', 2 FROM DUAL UNION ALL
            SELECT 'Contrepartie sans reference KYC',
                   'EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty AND TRIM(c.kyc_ref_no) IS NULL)', 3 FROM DUAL UNION ALL
            SELECT 'Contrepartie gelee, decedee ou introuvable',
                   'EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty AND (c.frozen = ''Y'' OR c.deceased = ''Y'' OR c.whereabouts_unknown = ''Y''))', 4 FROM DUAL UNION ALL
            SELECT 'Contrepartie non autorisee (AUTH_STAT <> A)',
                   'EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty AND c.auth_stat != ''A'')', 5 FROM DUAL UNION ALL
            SELECT 'Contrepartie a risque KYC eleve (RISK_LEVEL)',
                   'EXISTS (SELECT 1 FROM sttm_customer c JOIN sttm_kyc_master k ON k.kyc_ref_no = c.kyc_ref_no WHERE c.customer_no = m.counterparty AND UPPER(k.risk_level) LIKE ''%HIGH%'')', 6 FROM DUAL UNION ALL
            SELECT 'Contrepartie qui n''est pas un etablissement bancaire (CUSTOMER_TYPE <> B)',
                   'EXISTS (SELECT 1 FROM sttm_customer c WHERE c.customer_no = m.counterparty AND c.customer_type != ''B'')', 7 FROM DUAL UNION ALL
            SELECT 'Taux MAIN_COMP_RATE non renseigne',
                   'm.main_comp_rate IS NULL', 8 FROM DUAL UNION ALL
            SELECT 'Taux MAIN_COMP_RATE egal a zero',
                   'm.main_comp_rate = 0', 9 FROM DUAL UNION ALL
            SELECT 'Taux superieur a 15 pourcent',
                   'm.main_comp_rate > 15', 10 FROM DUAL UNION ALL
            SELECT 'Montant du contrat nul ou negatif',
                   'NVL(m.lcy_amount, 0) <= 0', 11 FROM DUAL UNION ALL
            SELECT 'Montant superieur a 1 milliard',
                   'm.lcy_amount > 1000000000', 12 FROM DUAL UNION ALL
            SELECT 'Montant rond au million (possible operation forfaitaire)',
                   'MOD(NVL(m.lcy_amount, 1), 1000000) = 0 AND NVL(m.lcy_amount, 0) > 0', 13 FROM DUAL UNION ALL
            SELECT 'Echeance anterieure a la date de valeur',
                   'm.maturity_date < m.value_date', 14 FROM DUAL UNION ALL
            SELECT 'Date de valeur anterieure a la date de booking',
                   'm.value_date < m.booking_date', 15 FROM DUAL UNION ALL
            SELECT 'Contrat echu depuis plus de 90 jours',
                   'm.maturity_date < SYSDATE - 90', 16 FROM DUAL UNION ALL
            SELECT 'Contrat echu avec encours residuel non nul',
                   'm.maturity_date < TRUNC(SYSDATE) AND EXISTS (SELECT 1 FROM ldtb_contract_balance b WHERE b.contract_ref_no = m.contract_ref_no AND NVL(b.principal_outstanding_bal, 0) > 0)', 17 FROM DUAL UNION ALL
            SELECT 'Contrat sans aucune ecriture comptable',
                   'NOT EXISTS (SELECT 1 FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no)', 18 FROM DUAL UNION ALL
            SELECT 'Contrat sans composante d''interet (ICCF)',
                   'NOT EXISTS (SELECT 1 FROM ldtb_contract_iccf_details i WHERE i.contract_ref_no = m.contract_ref_no)', 19 FROM DUAL UNION ALL
            SELECT 'Contrat sans echeancier',
                   'NOT EXISTS (SELECT 1 FROM ldtb_contract_schedules s WHERE s.contract_ref_no = m.contract_ref_no)', 20 FROM DUAL UNION ALL
            SELECT 'Contrat sans confirmation SWIFT',
                   'NOT EXISTS (SELECT 1 FROM ldtb_contract_swift_message w WHERE w.contract_ref_no = m.contract_ref_no)', 21 FROM DUAL UNION ALL
            SELECT 'Produit absent du referentiel CSTM_PRODUCT',
                   'NOT EXISTS (SELECT 1 FROM cstm_product p WHERE p.product_code = m.product)', 22 FROM DUAL UNION ALL
            SELECT 'Produit absent du parametrage LDTM_PRODUCT_MASTER',
                   'NOT EXISTS (SELECT 1 FROM ldtm_product_master lp WHERE lp.product = m.product)', 23 FROM DUAL UNION ALL
            SELECT 'Duree hors bornes du produit (TENOR < MIN ou > MAX)',
                   'EXISTS (SELECT 1 FROM ldtm_product_master lp WHERE lp.product = m.product AND ((lp.min_tenor IS NOT NULL AND m.tenor < lp.min_tenor) OR (lp.max_tenor IS NOT NULL AND m.tenor > lp.max_tenor)))', 24 FROM DUAL UNION ALL
            SELECT 'Contrat renouvele au moins une fois',
                   'NVL(m.rollover_count, 0) > 0', 25 FROM DUAL UNION ALL
            SELECT 'Contrat renouvele plus de trois fois',
                   'NVL(m.rollover_count, 0) > 3', 26 FROM DUAL UNION ALL
            SELECT 'Contrat sans DEALER identifie',
                   'TRIM(m.dealer) IS NULL', 27 FROM DUAL UNION ALL
            SELECT 'Contrat sans compte de reglement par defaut',
                   'TRIM(m.dflt_settle_ac) IS NULL', 28 FROM DUAL UNION ALL
            SELECT 'Contrat sans ligne de credit rattachee',
                   'TRIM(m.credit_line) IS NULL', 29 FROM DUAL UNION ALL
            SELECT 'Contrat sans remarque / justification',
                   'TRIM(m.remarks) IS NULL', 30 FROM DUAL UNION ALL
            SELECT 'Contrat booke un samedi ou un dimanche',
                   'TO_CHAR(m.booking_date, ''DY'', ''NLS_DATE_LANGUAGE=ENGLISH'') IN (''SAT'', ''SUN'')', 31 FROM DUAL UNION ALL
            SELECT 'Contrat dont la reference ne commence pas par le code agence',
                   'SUBSTR(m.contract_ref_no, 1, 3) != m.branch', 32 FROM DUAL UNION ALL
            SELECT 'Contrat non confirme par la contrepartie',
                   'NVL(m.cparty_confirm_status, ''N'') != ''Y''', 33 FROM DUAL UNION ALL
            SELECT 'Contrat dont les ecritures sont saisies par l''application externe',
                   'EXISTS (SELECT 1 FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no AND h.user_id LIKE ''%CALYPSO%'')', 34 FROM DUAL UNION ALL
            SELECT 'Contrat dont les ecritures sont auto-autorisees (saisie = autorisation)',
                   'EXISTS (SELECT 1 FROM actb_history h WHERE h.trn_ref_no = m.contract_ref_no AND h.user_id = h.auth_id)', 35 FROM DUAL
        ) ORDER BY ord
    ) LOOP
        v_row := v_row + 1;
        v_cnt := -1;
        v_tot := 0;
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*), NVL(SUM(m.lcy_amount), 0) FROM ldtb_contract_master m'
                || ' WHERE m.module = ''MM'' AND (' || t.cond || ')'
                INTO v_cnt, v_tot;
        EXCEPTION
            WHEN OTHERS THEN v_cnt := -1; v_tot := 0;
        END;
        po('  |' || fpadl(TO_CHAR(v_row), 4) || '|' || fpad(t.lib, 74) || '|'
            || fpadl(CASE WHEN v_cnt < 0 THEN 'NON CALCULE' ELSE fnum(v_cnt) END, 14) || '|'
            || fpadl(CASE WHEN v_cnt < 0 THEN '-' ELSE fmio(v_tot) END, 20) || '|');
    END LOOP;
    tbl_line('4,74,14,20');

    po('');
    po(v_sep);
    po('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    po(v_sep);

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('!! ERREUR BLOC 4 : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
