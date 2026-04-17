-- ============================================================
-- SCRIPT D'EXPLORATION — GESTION DES ACCES & SECURITE DE L'INFORMATION
-- FLEXCUBE UNIVERSAL BANKING
-- Banque : Access Bank Cameroon
-- Objet : Cartographie exhaustive du dispositif d'habilitation
--         (utilisateurs, roles, privileges, mots de passe, journaux
--          d'audit applicatif, parametres de securite, acces
--          branche/till, rattachement comptable et hierarchique)
-- Usage : execution sqlplus > explore_access_management.sql > output.txt
-- ============================================================
-- Ce script produit un rapport d'exploration via DBMS_OUTPUT.
-- Chaque section est identifiee par un numero (A-xx) pour tracabilite.
-- Les resultats = volumetrie + distributions + echantillons.
-- Aucune modification de donnees. Lecture seule.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_count2        NUMBER;
    v_total         NUMBER;
    v_sep           VARCHAR2(120) := RPAD('=', 110, '=');
    v_subsep        VARCHAR2(120) := RPAD('-', 110, '-');

    -- Collections pour resultats dynamiques (EXECUTE IMMEDIATE BULK COLLECT)
    TYPE t_vc30_tab IS TABLE OF VARCHAR2(30);
    TYPE t_num_tab  IS TABLE OF NUMBER;
    v_maker_tab     t_vc30_tab;
    v_count_tab     t_num_tab;
    v_aux_tab       t_vc30_tab;

    -- -------------------------------------------------------
    -- Utilitaires d'affichage
    -- -------------------------------------------------------
    PROCEDURE p_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE p_sub(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('  [' || p_title || ']');
    END;

    PROCEDURE p_kv(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_label, 55, '.') || ' ' || NVL(p_value, 'NULL / NON RENSEIGNE'));
    END;

    PROCEDURE p_pct(p_label VARCHAR2, p_count NUMBER, p_total NUMBER) IS
    BEGIN
        IF p_total > 0 THEN
            p_kv(p_label, TO_CHAR(p_count) || ' / ' || TO_CHAR(p_total)
                || ' (' || TO_CHAR(ROUND(p_count * 100 / p_total, 1)) || '%)');
        ELSE
            p_kv(p_label, '0 / 0 (N/A)');
        END IF;
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION — GESTION DES ACCES & SECURITE DE L''INFORMATION');
    DBMS_OUTPUT.PUT_LINE('>>> Date execution : ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- A-01. VOLUMETRIE GENERALE — TABLES DE SECURITE
    -- =========================================================
    p_section('A-01. VOLUMETRIE GENERALE — TABLES DE SECURITE (SM*, FB*, UDF)');

    FOR t IN (
        SELECT table_name, categorie FROM (
            SELECT 'SMTB_USER'                   AS table_name, 'Utilisateurs'         AS categorie, 1  AS ord FROM DUAL UNION ALL
            SELECT 'SMTB_USER_ROLE',               'Affectation role',                  2  FROM DUAL UNION ALL
            SELECT 'SMTB_USER_CENTRAL_ROLES',      'Roles centralises',                 3  FROM DUAL UNION ALL
            SELECT 'SMTB_USER_TILLS',              'Affectation caisse',                4  FROM DUAL UNION ALL
            SELECT 'SMTB_USER_DISABLE',            'Comptes desactives',                5  FROM DUAL UNION ALL
            SELECT 'SMTB_USERLOG_DETAILS',         'Statistiques connexion',            6  FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_MASTER',             'Referentiel roles',                 7  FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_DETAIL',             'Privileges roles/fonctions',        8  FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_BRANCHES',           'Affectation role <-> agence',       9  FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_FUNC_LIMIT_CUSTOM',  'Limites custom par role',          10  FROM DUAL UNION ALL
            SELECT 'SMTB_ROLE_FUNC_LIMIT_DETAIL',  'Limites fonction/role (detail)',   11  FROM DUAL UNION ALL
            SELECT 'SMTB_PASSWORD_HISTORY',        'Historique mots de passe',         12  FROM DUAL UNION ALL
            SELECT 'SMTB_PARAMETERS',              'Parametres securite globaux',      13  FROM DUAL UNION ALL
            SELECT 'SMTB_SMS_LOG',                 'Journal sessions (login/logout)',  14  FROM DUAL UNION ALL
            SELECT 'SMTB_SMS_ACTION_LOG',          'Journal actions metier',           15  FROM DUAL UNION ALL
            SELECT 'SMTB_MENU',                    'Menus / fonctions',                16  FROM DUAL UNION ALL
            SELECT 'SMTB_FUNCTION_DESCRIPTION',    'Descriptions fonctions',           17  FROM DUAL UNION ALL
            SELECT 'SMTB_FUNC_GROUP',              'Groupes fonctions',                18  FROM DUAL UNION ALL
            SELECT 'SMTB_MODULES',                 'Modules applicatifs',              19  FROM DUAL UNION ALL
            SELECT 'SMTB_LANGUAGE',                'Langues',                          20  FROM DUAL UNION ALL
            SELECT 'SMTB_MSGS_RIGHTS',             'Droits messages SWIFT',            21  FROM DUAL UNION ALL
            SELECT 'SMTB_QUEUES',                  'Files d''attente',                 22  FROM DUAL UNION ALL
            SELECT 'SMTB_QUEUE_RIGHTS',            'Droits sur files',                 23  FROM DUAL UNION ALL
            SELECT 'SMTB_ACTION_CONTROLS',         'Controles sur actions',            24  FROM DUAL UNION ALL
            SELECT 'SMTB_STAGE_FIELD_VALUE',       'Valeurs de champs stage',          25  FROM DUAL UNION ALL
            SELECT 'FBTB_USER',                    'Utilisateurs FlexBranch',          26  FROM DUAL UNION ALL
            SELECT 'FBTM_BRANCH',                  'Agences FlexBranch',               27  FROM DUAL UNION ALL
            SELECT 'FBTM_BRANCH_INFO',             'Informations agence',              28  FROM DUAL UNION ALL
            SELECT 'CSTM_FUNCTION_USERDEF_FIELDS', 'Champs UDF (SMDROLDF/USRDF/...)',  29  FROM DUAL
            ORDER BY ord
        )
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || t.table_name INTO v_count;
            p_kv(RPAD(t.table_name, 32) || ' (' || t.categorie || ')', TO_CHAR(v_count) || ' lignes');
        EXCEPTION WHEN OTHERS THEN
            p_kv(RPAD(t.table_name, 32) || ' (' || t.categorie || ')', 'TABLE ABSENTE / NON LISIBLE');
        END;
    END LOOP;

    -- =========================================================
    -- A-02. SMTB_USER — REFERENTIEL UTILISATEURS
    -- =========================================================
    p_section('A-02. SMTB_USER — Referentiel des utilisateurs applicatifs');

    SELECT COUNT(*) INTO v_total FROM SMTB_USER;
    p_kv('Total utilisateurs enregistres', TO_CHAR(v_total));

    p_sub('Statut utilisateur (USER_STATUS : E=Enabled, D=Disabled, H=Hold, L=Locked)');
    FOR r IN (SELECT USER_STATUS, COUNT(*) nb FROM SMTB_USER GROUP BY USER_STATUS ORDER BY nb DESC) LOOP
        p_pct('  USER_STATUS = ' || NVL(r.USER_STATUS, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Statut d''autorisation (AUTH_STAT : A=Auth, U=Unauth)');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM SMTB_USER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        p_pct('  AUTH_STAT = ' || NVL(r.AUTH_STAT, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Statut enregistrement (RECORD_STAT : O=Open, C=Closed)');
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM SMTB_USER GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        p_pct('  RECORD_STAT = ' || NVL(r.RECORD_STAT, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Categorie utilisateur (USER_CATEGORY)');
    FOR r IN (SELECT USER_CATEGORY, COUNT(*) nb FROM SMTB_USER GROUP BY USER_CATEGORY ORDER BY nb DESC) LOOP
        p_pct('  Categorie = ' || NVL(r.USER_CATEGORY, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Langue (USER_LANGUAGE)');
    FOR r IN (SELECT USER_LANGUAGE, COUNT(*) nb FROM SMTB_USER GROUP BY USER_LANGUAGE ORDER BY nb DESC) LOOP
        p_pct('  Langue = ' || NVL(r.USER_LANGUAGE, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Module par defaut (DFLT_MODULE)');
    FOR r IN (
        SELECT DFLT_MODULE, nb FROM (
            SELECT DFLT_MODULE, COUNT(*) nb FROM SMTB_USER GROUP BY DFLT_MODULE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  Module = ' || NVL(r.DFLT_MODULE, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Top 15 agences de rattachement (HOME_BRANCH)');
    FOR r IN (
        SELECT HOME_BRANCH, nb FROM (
            SELECT HOME_BRANCH, COUNT(*) nb FROM SMTB_USER GROUP BY HOME_BRANCH ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  Agence = ' || NVL(r.HOME_BRANCH, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Authentification externe (LDAP_USER)');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE LDAP_USER = 'Y';
    p_pct('  Utilisateurs LDAP (LDAP_USER=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE LDAP_USER = 'N' OR LDAP_USER IS NULL;
    p_pct('  Utilisateurs locaux (non LDAP)', v_count, v_total);

    p_sub('Mot de passe : indicateurs');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_PASSWORD IS NULL OR USER_PASSWORD = ' ';
    p_pct('  Sans mot de passe stocke', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE SALT IS NULL OR SALT = ' ';
    p_pct('  Sans SALT (hash non sale)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE FORCE_PASSWD_CHANGE = 1;
    p_pct('  Changement mot de passe force (FORCE_PASSWD_CHANGE=1)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE PWD_CHANGED_ON IS NULL;
    p_pct('  Sans date de changement mot de passe', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE PWD_CHANGED_ON < ADD_MONTHS(SYSDATE, -6);
    p_pct('  Mot de passe inchange depuis > 6 mois', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE PWD_CHANGED_ON < ADD_MONTHS(SYSDATE, -12);
    p_pct('  Mot de passe inchange depuis > 12 mois', v_count, v_total);

    p_sub('Cycle de vie du compte (START_DATE / END_DATE)');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE END_DATE IS NOT NULL AND END_DATE < SYSDATE;
    p_pct('  Comptes avec END_DATE depassee', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE END_DATE IS NOT NULL AND END_DATE < SYSDATE AND USER_STATUS = 'E';
    p_pct('  Comptes ENABLES mais END_DATE depassee (anomalie)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE START_DATE IS NULL;
    p_pct('  Sans START_DATE', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE START_DATE > SYSDATE;
    p_pct('  START_DATE future', v_count, v_total);

    p_sub('Droits d''autorisation et limites');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE AUTO_AUTH = 'Y';
    p_pct('  Utilisateurs AUTO_AUTH=Y (auto-authorisation)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE ONCE_AUTH = 'Y';
    p_pct('  Utilisateurs ONCE_AUTH=Y', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MULTIBRANCH_ACCESS = 'Y';
    p_pct('  Acces multi-agences (MULTIBRANCH_ACCESS=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE STAFF_AC_RESTR = 'Y';
    p_pct('  Restriction compte staff (STAFF_AC_RESTR=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE OTHER_RM_CUST_RESTRICT = 'Y';
    p_pct('  Restriction clients autre RM (OTHER_RM_CUST_RESTRICT=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE TILL_ALLOWED = 'Y';
    p_pct('  Caisse autorisee (TILL_ALLOWED=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE GL_ALLOWED = 'Y';
    p_pct('  Acces GL autorise (GL_ALLOWED=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE BRANCHES_ALLOWED = 'Y';
    p_pct('  Acces toutes agences (BRANCHES_ALLOWED=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE ACCLASS_ALLOWED = 'Y';
    p_pct('  Toutes classes de compte autorisees (ACCLASS_ALLOWED=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE PRODUCTS_ALLOWED = 'Y';
    p_pct('  Tous produits autorises (PRODUCTS_ALLOWED=Y)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE GROUP_CODE_ALLOWED = 'Y';
    p_pct('  Tous groupes autorises (GROUP_CODE_ALLOWED=Y)', v_count, v_total);

    p_sub('Montants plafonds (devise LIMITS_CCY)');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MAX_TXN_AMT IS NULL OR MAX_TXN_AMT = 0;
    p_pct('  MAX_TXN_AMT non defini (0 ou NULL)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MAX_AUTH_AMT IS NULL OR MAX_AUTH_AMT = 0;
    p_pct('  MAX_AUTH_AMT non defini (0 ou NULL)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MAX_OVERRIDE_AMT IS NULL OR MAX_OVERRIDE_AMT = 0;
    p_pct('  MAX_OVERRIDE_AMT non defini (0 ou NULL)', v_count, v_total);

    p_sub('Statistiques plafonds transaction (LIMITS_CCY)');
    FOR r IN (
        SELECT LIMITS_CCY,
               COUNT(*) nb,
               ROUND(AVG(MAX_TXN_AMT)) moy_txn,
               MAX(MAX_TXN_AMT) max_txn,
               MAX(MAX_AUTH_AMT) max_auth,
               MAX(MAX_OVERRIDE_AMT) max_ovr
        FROM SMTB_USER
        WHERE MAX_TXN_AMT > 0
        GROUP BY LIMITS_CCY
        ORDER BY nb DESC
    ) LOOP
        p_kv('  CCY=' || NVL(r.LIMITS_CCY,'(NULL)') || ' | nb=' || r.nb
             || ' | max_txn=' || r.max_txn || ' | max_auth=' || r.max_auth
             || ' | max_override=' || r.max_ovr, 'moy_txn=' || r.moy_txn);
    END LOOP;

    p_sub('Parametres ergonomie / securite session');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE SCREEN_SAVER_TIMEOUT IS NULL OR SCREEN_SAVER_TIMEOUT = 0;
    p_pct('  Sans timeout ecran (SCREEN_SAVER_TIMEOUT=0/NULL)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE SCREEN_SAVER_TIMEOUT > 30;
    p_pct('  Timeout ecran > 30 minutes', v_count, v_total);
    p_sub('Distribution SCREEN_SAVER_TIMEOUT (minutes)');
    FOR r IN (SELECT SCREEN_SAVER_TIMEOUT, COUNT(*) nb FROM SMTB_USER
              GROUP BY SCREEN_SAVER_TIMEOUT ORDER BY nb DESC) LOOP
        p_pct('  Timeout = ' || NVL(TO_CHAR(r.SCREEN_SAVER_TIMEOUT), '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Identite et coordonnees');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_EMAIL IS NULL OR USER_EMAIL = ' ';
    p_pct('  Sans email', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE TELEPHONE_NUMBER IS NULL OR TELEPHONE_NUMBER = ' ';
    p_pct('  Sans telephone bureau', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_MOBILE IS NULL OR USER_MOBILE = ' ';
    p_pct('  Sans mobile', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_MANAGER IS NULL OR USER_MANAGER = ' ';
    p_pct('  Sans manager hierarchique renseigne', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE DEPT_CODE IS NULL OR DEPT_CODE = ' ';
    p_pct('  Sans code departement', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE EXT_USER_REF IS NULL OR EXT_USER_REF = ' ';
    p_pct('  Sans reference externe (EXT_USER_REF)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE CUSTOMER_NO IS NOT NULL AND CUSTOMER_NO <> ' ';
    p_pct('  Lie a un CIF (CUSTOMER_NO renseigne)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MFI_USER = 'Y';
    p_pct('  Utilisateurs MFI (microfinance)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE DASHBOARD_REQD = 'Y';
    p_pct('  Dashboard active', v_count, v_total);

    p_sub('Traces maker/checker');
    SELECT COUNT(DISTINCT MAKER_ID) INTO v_count FROM SMTB_USER;
    p_kv('  Nombre distinct de MAKER_ID', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CHECKER_ID) INTO v_count FROM SMTB_USER;
    p_kv('  Nombre distinct de CHECKER_ID', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_pct('  MAKER_ID = CHECKER_ID (auto-validation)', v_count, v_total);

    p_sub('Top 10 createurs de comptes utilisateurs (MAKER_ID)');
    FOR r IN (
        SELECT MAKER_ID, nb FROM (
            SELECT MAKER_ID, COUNT(*) nb FROM SMTB_USER
            GROUP BY MAKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_pct('  MAKER_ID = ' || NVL(r.MAKER_ID, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Top 10 valideurs de comptes utilisateurs (CHECKER_ID)');
    FOR r IN (
        SELECT CHECKER_ID, nb FROM (
            SELECT CHECKER_ID, COUNT(*) nb FROM SMTB_USER
            GROUP BY CHECKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_pct('  CHECKER_ID = ' || NVL(r.CHECKER_ID, '(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Echantillon 10 utilisateurs — vue synthetique');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, USER_NAME, USER_STATUS, AUTH_STAT, RECORD_STAT,
                   HOME_BRANCH, DFLT_MODULE, LDAP_USER,
                   TO_CHAR(START_DATE,'DD/MM/YYYY') sdate,
                   TO_CHAR(END_DATE,'DD/MM/YYYY') edate,
                   TO_CHAR(PWD_CHANGED_ON,'DD/MM/YYYY') pwd_chg
            FROM SMTB_USER
            ORDER BY USER_ID
        ) WHERE ROWNUM <= 10
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  --- USER_ID=' || r.USER_ID || ' | ' || r.USER_NAME || ' ---');
        p_kv('    Status/Auth/Record', r.USER_STATUS||' / '||r.AUTH_STAT||' / '||r.RECORD_STAT);
        p_kv('    Home branch / Module', NVL(r.HOME_BRANCH,'-')||' / '||NVL(r.DFLT_MODULE,'-'));
        p_kv('    LDAP', NVL(r.LDAP_USER,'-'));
        p_kv('    Start / End / Pwd changed', NVL(r.sdate,'-')||' / '||NVL(r.edate,'-')||' / '||NVL(r.pwd_chg,'-'));
    END LOOP;

    -- =========================================================
    -- A-03. SMTB_USER_DISABLE & SMTB_USERLOG_DETAILS
    --        — Desactivations et historique de connexion
    -- =========================================================
    p_section('A-03. SMTB_USER_DISABLE & SMTB_USERLOG_DETAILS — Desactivations et connexions');

    -- ---------- SMTB_USER_DISABLE ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_USER_DISABLE;
    p_kv('Total evenements de desactivation (SMTB_USER_DISABLE)', TO_CHAR(v_total));

    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_DISABLE;
    p_kv('Nombre d''utilisateurs distincts concernes', TO_CHAR(v_count));

    p_sub('Repartition par motif (MESSAGE)');
    FOR r IN (
        SELECT MESSAGE, nb FROM (
            SELECT SUBSTR(MESSAGE, 1, 60) AS MESSAGE, COUNT(*) nb
            FROM SMTB_USER_DISABLE GROUP BY SUBSTR(MESSAGE, 1, 60) ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_pct('  ' || NVL(r.MESSAGE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Terminal de desactivation (TERMINAL_ID) — Top 10');
    FOR r IN (
        SELECT TERMINAL_ID, nb FROM (
            SELECT TERMINAL_ID, COUNT(*) nb FROM SMTB_USER_DISABLE
            GROUP BY TERMINAL_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_pct('  TERMINAL = ' || NVL(r.TERMINAL_ID,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Distribution temporelle (derniers 12 mois)');
    FOR r IN (
        SELECT TO_CHAR(START_TIME, 'YYYY-MM') AS mois, COUNT(*) nb
        FROM SMTB_USER_DISABLE
        WHERE START_TIME >= ADD_MONTHS(SYSDATE, -12)
        GROUP BY TO_CHAR(START_TIME, 'YYYY-MM')
        ORDER BY mois
    ) LOOP
        p_kv('  ' || r.mois, TO_CHAR(r.nb) || ' desactivation(s)');
    END LOOP;

    p_sub('Top 10 utilisateurs les plus souvent desactives');
    FOR r IN (
        SELECT USER_ID, nb FROM (
            SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_DISABLE
            GROUP BY USER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  USER_ID = ' || NVL(r.USER_ID,'(NULL)'), TO_CHAR(r.nb) || ' desactivation(s)');
    END LOOP;

    p_sub('Echantillon 10 evenements recents');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, TERMINAL_ID,
                   TO_CHAR(START_TIME,'DD/MM/YYYY HH24:MI') dt,
                   SUBSTR(MESSAGE, 1, 80) msg
            FROM SMTB_USER_DISABLE
            ORDER BY START_TIME DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  ' || r.dt || ' | USER=' || r.USER_ID || ' | TERM=' || NVL(r.TERMINAL_ID,'-'),
             NVL(r.msg,'-'));
    END LOOP;

    -- ---------- SMTB_USERLOG_DETAILS ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_USERLOG_DETAILS;
    p_kv('Total lignes SMTB_USERLOG_DETAILS (stats de connexion)', TO_CHAR(v_total));

    p_sub('Couverture : utilisateurs avec stats connexion');
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USERLOG_DETAILS;
    p_kv('  Utilisateurs distincts traces', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER u
        WHERE NOT EXISTS (SELECT 1 FROM SMTB_USERLOG_DETAILS l WHERE l.USER_ID = u.USER_ID);
    p_kv('  Utilisateurs SMTB_USER SANS trace de login', TO_CHAR(v_count));

    p_sub('Derniere connexion (LAST_SIGNED_ON) — anciennete');
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON IS NULL;
    p_pct('  LAST_SIGNED_ON = NULL (jamais connecte)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON >= SYSDATE - 7;
    p_pct('  Connecte dans les 7 derniers jours', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON >= SYSDATE - 30;
    p_pct('  Connecte dans les 30 derniers jours', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON < SYSDATE - 90 AND LAST_SIGNED_ON IS NOT NULL;
    p_pct('  Inactif > 90 jours', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON < SYSDATE - 180 AND LAST_SIGNED_ON IS NOT NULL;
    p_pct('  Inactif > 180 jours (dormant candidat)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE LAST_SIGNED_ON < SYSDATE - 365 AND LAST_SIGNED_ON IS NOT NULL;
    p_pct('  Inactif > 365 jours (dormant avere)', v_count, v_total);

    p_sub('Compteurs de logins');
    FOR r IN (
        SELECT ROUND(AVG(NO_CUMULATIVE_LOGINS)) avg_cum,
               MAX(NO_CUMULATIVE_LOGINS) max_cum,
               ROUND(AVG(NO_SUCCESSIVE_LOGINS)) avg_suc,
               MAX(NO_SUCCESSIVE_LOGINS) max_suc
        FROM SMTB_USERLOG_DETAILS
    ) LOOP
        p_kv('  NO_CUMULATIVE_LOGINS (moyenne)', TO_CHAR(r.avg_cum));
        p_kv('  NO_CUMULATIVE_LOGINS (max)', TO_CHAR(r.max_cum));
        p_kv('  NO_SUCCESSIVE_LOGINS (moyenne)', TO_CHAR(r.avg_suc));
        p_kv('  NO_SUCCESSIVE_LOGINS (max)', TO_CHAR(r.max_suc));
    END LOOP;

    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE NO_SUCCESSIVE_LOGINS >= 3;
    p_pct('  Utilisateurs avec NO_SUCCESSIVE_LOGINS >= 3 (tentatives echouees consecutives)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS WHERE NO_SUCCESSIVE_LOGINS >= 5;
    p_pct('  Utilisateurs avec NO_SUCCESSIVE_LOGINS >= 5', v_count, v_total);

    p_sub('Top 10 utilisateurs les plus anciens par inactivite');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID,
                   TO_CHAR(LAST_SIGNED_ON,'DD/MM/YYYY HH24:MI') last_sign,
                   NO_CUMULATIVE_LOGINS, NO_SUCCESSIVE_LOGINS
            FROM SMTB_USERLOG_DETAILS
            WHERE LAST_SIGNED_ON IS NOT NULL
            ORDER BY LAST_SIGNED_ON ASC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  USER=' || r.USER_ID || ' | last=' || r.last_sign,
             'cum=' || r.NO_CUMULATIVE_LOGINS || ' / suc=' || r.NO_SUCCESSIVE_LOGINS);
    END LOOP;

    p_sub('Top 10 utilisateurs les plus actifs (NO_CUMULATIVE_LOGINS)');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, NO_CUMULATIVE_LOGINS, NO_SUCCESSIVE_LOGINS,
                   TO_CHAR(LAST_SIGNED_ON,'DD/MM/YYYY HH24:MI') last_sign
            FROM SMTB_USERLOG_DETAILS
            ORDER BY NO_CUMULATIVE_LOGINS DESC NULLS LAST
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  USER=' || r.USER_ID || ' | cum=' || r.NO_CUMULATIVE_LOGINS,
             'last=' || NVL(r.last_sign,'-') || ' / suc=' || r.NO_SUCCESSIVE_LOGINS);
    END LOOP;

    -- =========================================================
    -- A-04. SMTB_ROLE_MASTER & SMTB_ROLE_BRANCHES — Referentiel des roles
    -- =========================================================
    p_section('A-04. SMTB_ROLE_MASTER & SMTB_ROLE_BRANCHES — Referentiel des roles');

    -- ---------- SMTB_ROLE_MASTER ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_MASTER;
    p_kv('Total roles definis', TO_CHAR(v_total));

    p_sub('Statut d''enregistrement (RECORD_STAT)');
    FOR r IN (SELECT RECORD_STAT, COUNT(*) nb FROM SMTB_ROLE_MASTER GROUP BY RECORD_STAT ORDER BY nb DESC) LOOP
        p_pct('  RECORD_STAT = ' || NVL(r.RECORD_STAT,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Statut d''autorisation (AUTH_STAT)');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM SMTB_ROLE_MASTER GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        p_pct('  AUTH_STAT = ' || NVL(r.AUTH_STAT,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Once auth (ONCE_AUTH)');
    FOR r IN (SELECT ONCE_AUTH, COUNT(*) nb FROM SMTB_ROLE_MASTER GROUP BY ONCE_AUTH ORDER BY nb DESC) LOOP
        p_pct('  ONCE_AUTH = ' || NVL(r.ONCE_AUTH,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Perimetre ouvert (tous/all)');
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE BRANCHES_ALLOWED = 'Y';
    p_pct('  Roles avec BRANCHES_ALLOWED=Y (toutes agences)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE ACCCLASS_ALLOWED = 'Y';
    p_pct('  Roles avec ACCCLASS_ALLOWED=Y (toutes classes)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE BRANCH_VLT_ROLE = 'Y';
    p_pct('  Roles cles coffre-fort (BRANCH_VLT_ROLE=Y)', v_count, v_total);

    p_sub('Categorie de role (BRANCH_ROLE_CAT)');
    FOR r IN (SELECT BRANCH_ROLE_CAT, COUNT(*) nb FROM SMTB_ROLE_MASTER
              GROUP BY BRANCH_ROLE_CAT ORDER BY nb DESC) LOOP
        p_pct('  CAT = ' || NVL(r.BRANCH_ROLE_CAT,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Niveau hierarchique du role (BRANCH_ROLE_LEVEL)');
    FOR r IN (SELECT BRANCH_ROLE_LEVEL, COUNT(*) nb FROM SMTB_ROLE_MASTER
              GROUP BY BRANCH_ROLE_LEVEL ORDER BY BRANCH_ROLE_LEVEL NULLS FIRST) LOOP
        p_pct('  LEVEL = ' || NVL(TO_CHAR(r.BRANCH_ROLE_LEVEL),'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Role centralisation / authorisation');
    FOR r IN (SELECT CENTRALISATION_ROLE, COUNT(*) nb FROM SMTB_ROLE_MASTER
              GROUP BY CENTRALISATION_ROLE ORDER BY nb DESC) LOOP
        p_pct('  CENTRALISATION_ROLE = ' || NVL(r.CENTRALISATION_ROLE,'(NULL)'), r.nb, v_total);
    END LOOP;
    FOR r IN (SELECT BRANCH_AUTH_ROLE, COUNT(*) nb FROM SMTB_ROLE_MASTER
              GROUP BY BRANCH_AUTH_ROLE ORDER BY nb DESC) LOOP
        p_pct('  BRANCH_AUTH_ROLE = ' || NVL(r.BRANCH_AUTH_ROLE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Frequence reset mot de passe branche (BRANCH_PWD_RESET_FREQ, jours)');
    FOR r IN (SELECT BRANCH_PWD_RESET_FREQ, COUNT(*) nb FROM SMTB_ROLE_MASTER
              GROUP BY BRANCH_PWD_RESET_FREQ ORDER BY BRANCH_PWD_RESET_FREQ NULLS FIRST) LOOP
        p_pct('  FREQ = ' || NVL(TO_CHAR(r.BRANCH_PWD_RESET_FREQ),'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Traces maker/checker des roles');
    SELECT COUNT(DISTINCT MAKER_ID) INTO v_count FROM SMTB_ROLE_MASTER;
    p_kv('  Nombre distinct de MAKER_ID', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT CHECKER_ID) INTO v_count FROM SMTB_ROLE_MASTER;
    p_kv('  Nombre distinct de CHECKER_ID', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_pct('  MAKER_ID = CHECKER_ID (auto-validation)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE CHECKER_ID IS NULL OR CHECKER_ID = ' ';
    p_pct('  Roles sans CHECKER_ID', v_count, v_total);

    p_sub('Top 10 makers de roles');
    FOR r IN (
        SELECT MAKER_ID, nb FROM (
            SELECT MAKER_ID, COUNT(*) nb FROM SMTB_ROLE_MASTER
            GROUP BY MAKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_pct('  MAKER_ID = ' || NVL(r.MAKER_ID,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Echantillon 15 roles');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_ID,
                   SUBSTR(ROLE_DESCRIPTION, 1, 55) descr,
                   RECORD_STAT, AUTH_STAT,
                   BRANCHES_ALLOWED, ACCCLASS_ALLOWED,
                   BRANCH_VLT_ROLE, BRANCH_ROLE_CAT, BRANCH_ROLE_LEVEL
            FROM SMTB_ROLE_MASTER
            ORDER BY ROLE_ID
        ) WHERE ROWNUM <= 15
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  --- ROLE=' || r.ROLE_ID || ' | ' || NVL(r.descr,'-') || ' ---');
        p_kv('    Record/Auth', r.RECORD_STAT||' / '||r.AUTH_STAT);
        p_kv('    Branches / AcClass allowed', NVL(r.BRANCHES_ALLOWED,'-')||' / '||NVL(r.ACCCLASS_ALLOWED,'-'));
        p_kv('    Coffre / Cat / Level',
             NVL(r.BRANCH_VLT_ROLE,'-')||' / '||NVL(r.BRANCH_ROLE_CAT,'-')||' / '||NVL(TO_CHAR(r.BRANCH_ROLE_LEVEL),'-'));
    END LOOP;

    -- ---------- SMTB_ROLE_BRANCHES ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_BRANCHES;
    p_kv('Total affectations role <-> agence (SMTB_ROLE_BRANCHES)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Top 15 agences avec plus de roles attribues');
        FOR r IN (
            SELECT BRANCH, nb FROM (
                SELECT BRANCH, COUNT(*) nb FROM SMTB_ROLE_BRANCHES
                GROUP BY BRANCH ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  BRANCH = ' || NVL(r.BRANCH,'(NULL)'), TO_CHAR(r.nb) || ' role(s)');
        END LOOP;

        p_sub('Top 15 roles avec le plus d''agences');
        FOR r IN (
            SELECT ROLE_ID, nb FROM (
                SELECT ROLE_ID, COUNT(*) nb FROM SMTB_ROLE_BRANCHES
                GROUP BY ROLE_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  ROLE = ' || NVL(r.ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' agence(s)');
        END LOOP;

        p_sub('Echantillon 10 affectations');
        FOR r IN (
            SELECT * FROM (
                SELECT ROLE_ID, BRANCH FROM SMTB_ROLE_BRANCHES ORDER BY ROLE_ID, BRANCH
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  ROLE=' || r.ROLE_ID, 'BRANCH=' || r.BRANCH);
        END LOOP;
    END IF;

    -- =========================================================
    -- A-05. SMTB_ROLE_DETAIL — Privileges role/fonction (matrice fine)
    -- =========================================================
    p_section('A-05. SMTB_ROLE_DETAIL — Privileges role/fonction (23K+ lignes attendues)');

    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_DETAIL;
    p_kv('Total lignes de privileges role/fonction', TO_CHAR(v_total));

    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL;
    p_kv('Nombre de roles distincts avec privileges', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT ROLE_FUNCTION) INTO v_count FROM SMTB_ROLE_DETAIL;
    p_kv('Nombre de fonctions distinctes accessibles', TO_CHAR(v_count));

    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM SMTB_ROLE_DETAIL;
    p_kv('Nombre d''agences distinctes (BRANCH_CODE)', TO_CHAR(v_count));

    p_sub('Statut d''autorisation (AUTH_STAT)');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM SMTB_ROLE_DETAIL
              GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        p_pct('  AUTH_STAT = ' || NVL(r.AUTH_STAT,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Distribution par BRANCH_CODE (top 15)');
    FOR r IN (
        SELECT BRANCH_CODE, nb FROM (
            SELECT BRANCH_CODE, COUNT(*) nb FROM SMTB_ROLE_DETAIL
            GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  BRANCH = ' || NVL(r.BRANCH_CODE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Top 20 roles avec le plus de privileges (nb de lignes role/fonction)');
    FOR r IN (
        SELECT ROLE_ID, nb FROM (
            SELECT ROLE_ID, COUNT(*) nb FROM SMTB_ROLE_DETAIL
            GROUP BY ROLE_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_kv('  ROLE = ' || NVL(r.ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' fonctions');
    END LOOP;

    p_sub('Top 20 fonctions les plus attribuees (ROLE_FUNCTION)');
    FOR r IN (
        SELECT ROLE_FUNCTION, nb FROM (
            SELECT ROLE_FUNCTION, COUNT(*) nb FROM SMTB_ROLE_DETAIL
            GROUP BY ROLE_FUNCTION ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_kv('  FUNC = ' || NVL(r.ROLE_FUNCTION,'(NULL)'), TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('Top 20 fonctions RAD (RAD_FUNCTION_ID) les plus attribuees');
    FOR r IN (
        SELECT RAD_FUNCTION_ID, nb FROM (
            SELECT RAD_FUNCTION_ID, COUNT(*) nb FROM SMTB_ROLE_DETAIL
            WHERE RAD_FUNCTION_ID IS NOT NULL
            GROUP BY RAD_FUNCTION_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_kv('  RAD = ' || NVL(r.RAD_FUNCTION_ID,'(NULL)'), TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('Fonctions SENSIBLES — focus gestion des acces / parametres');
    FOR f IN (
        SELECT func FROM (
            SELECT 'SMDUSRDF' AS func, 1 ord FROM DUAL UNION ALL
            SELECT 'SMDROLDF',        2 FROM DUAL UNION ALL
            SELECT 'SMDCHPWD',        3 FROM DUAL UNION ALL
            SELECT 'SMDBRGRT',        4 FROM DUAL UNION ALL
            SELECT 'SMDAUTH',         5 FROM DUAL UNION ALL
            SELECT 'SMSPARAM',        6 FROM DUAL UNION ALL
            SELECT 'SMDPARAM',        7 FROM DUAL UNION ALL
            SELECT 'SMDCHKDT',        8 FROM DUAL UNION ALL
            SELECT 'SMDUSRHL',        9 FROM DUAL UNION ALL
            SELECT 'SMDCLRUS',       10 FROM DUAL UNION ALL
            SELECT 'STDCIF',         11 FROM DUAL UNION ALL
            SELECT 'STDCUSAC',       12 FROM DUAL UNION ALL
            SELECT 'STDACCLS',       13 FROM DUAL UNION ALL
            SELECT 'STDBRANC',       14 FROM DUAL UNION ALL
            SELECT 'KYDKYCMN',       15 FROM DUAL UNION ALL
            SELECT 'STDKYCMN',       16 FROM DUAL UNION ALL
            SELECT 'STDCUSTF',       17 FROM DUAL ORDER BY ord
        )
    ) LOOP
        SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL
            WHERE UPPER(ROLE_FUNCTION) = f.func OR UPPER(RAD_FUNCTION_ID) = f.func;
        p_kv('  Fonction ' || f.func, TO_CHAR(v_count) || ' role(s) l''ont dans le scope');
    END LOOP;

    p_sub('Distribution CONTROL_STRING (pattern de droits) — Top 20');
    FOR r IN (
        SELECT CONTROL_STRING, nb FROM (
            SELECT SUBSTR(CONTROL_STRING, 1, 32) AS CONTROL_STRING, COUNT(*) nb
            FROM SMTB_ROLE_DETAIL
            GROUP BY SUBSTR(CONTROL_STRING, 1, 32) ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_pct('  CTRL = ' || NVL(r.CONTROL_STRING,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Volume CONTROL_1..CONTROL_16 actifs (NULL / non nul)');
    FOR c IN (
        SELECT LEVEL AS n FROM DUAL CONNECT BY LEVEL <= 16
    ) LOOP
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM SMTB_ROLE_DETAIL WHERE CONTROL_' || c.n || ' IS NOT NULL AND CONTROL_' || c.n || ' > 0' INTO v_count;
        p_pct('  CONTROL_' || c.n || ' actif (>0)', v_count, v_total);
    END LOOP;

    p_sub('Roles ayant acces a TOUTES les agences (heuristique : > 1 BRANCH_CODE)');
    FOR r IN (
        SELECT ROLE_ID, nb_branches FROM (
            SELECT ROLE_ID, COUNT(DISTINCT BRANCH_CODE) nb_branches
            FROM SMTB_ROLE_DETAIL
            GROUP BY ROLE_ID
            HAVING COUNT(DISTINCT BRANCH_CODE) > 1
            ORDER BY nb_branches DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ROLE = ' || r.ROLE_ID, TO_CHAR(r.nb_branches) || ' agence(s)');
    END LOOP;

    p_sub('Echantillon 10 lignes');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_ID, ROLE_FUNCTION, BRANCH_CODE, AUTH_STAT,
                   SUBSTR(CONTROL_STRING, 1, 40) AS ctrl, RAD_FUNCTION_ID
            FROM SMTB_ROLE_DETAIL
            ORDER BY ROLE_ID, ROLE_FUNCTION
        ) WHERE ROWNUM <= 10
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  --- ROLE=' || r.ROLE_ID || ' | FUNC=' || r.ROLE_FUNCTION
            || ' | BRN=' || NVL(r.BRANCH_CODE,'-') || ' | AUTH=' || NVL(r.AUTH_STAT,'-') || ' ---');
        p_kv('    CONTROL_STRING', r.ctrl);
        p_kv('    RAD_FUNCTION_ID', NVL(r.RAD_FUNCTION_ID,'-'));
    END LOOP;

    -- =========================================================
    -- A-06. SMTB_USER_ROLE & SMTB_USER_CENTRAL_ROLES
    --        — Affectation utilisateur <-> role (locale & centralisee)
    -- =========================================================
    p_section('A-06. SMTB_USER_ROLE & SMTB_USER_CENTRAL_ROLES — Affectation user<->role');

    -- ---------- SMTB_USER_ROLE ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_USER_ROLE;
    p_kv('Total affectations user-role (SMTB_USER_ROLE)', TO_CHAR(v_total));

    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_ROLE;
    p_kv('Utilisateurs distincts avec au moins 1 role', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_USER_ROLE;
    p_kv('Roles distincts effectivement attribues', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM SMTB_USER_ROLE;
    p_kv('Agences distinctes (BRANCH_CODE)', TO_CHAR(v_count));

    p_sub('Statut d''autorisation (AUTH_STAT)');
    FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM SMTB_USER_ROLE
              GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
        p_pct('  AUTH_STAT = ' || NVL(r.AUTH_STAT,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Distribution par BRANCH_CODE (top 15)');
    FOR r IN (
        SELECT BRANCH_CODE, nb FROM (
            SELECT BRANCH_CODE, COUNT(*) nb FROM SMTB_USER_ROLE
            GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  BRANCH = ' || NVL(r.BRANCH_CODE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Nombre de roles par utilisateur — statistiques');
    FOR r IN (
        SELECT ROUND(AVG(nb),2) moy, MIN(nb) mini, MAX(nb) maxi
        FROM (SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_ROLE GROUP BY USER_ID)
    ) LOOP
        p_kv('  Roles/user : moyenne', TO_CHAR(r.moy));
        p_kv('  Roles/user : min', TO_CHAR(r.mini));
        p_kv('  Roles/user : max', TO_CHAR(r.maxi));
    END LOOP;

    p_sub('Top 15 utilisateurs les plus dotes en roles');
    FOR r IN (
        SELECT USER_ID, nb FROM (
            SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_ROLE
            GROUP BY USER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  USER = ' || NVL(r.USER_ID,'(NULL)'), TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('Top 15 roles les plus attribues');
    FOR r IN (
        SELECT ROLE_ID, nb FROM (
            SELECT ROLE_ID, COUNT(*) nb FROM SMTB_USER_ROLE
            GROUP BY ROLE_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ROLE = ' || NVL(r.ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' utilisateur(s)');
    END LOOP;

    p_sub('Utilisateurs actifs SANS role (AUTH_STAT = A et USER_STATUS actif)');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER u
        WHERE NOT EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.USER_ID = u.USER_ID)
          AND NOT EXISTS (SELECT 1 FROM SMTB_USER_CENTRAL_ROLES c WHERE c.USER_ID = u.USER_ID);
    p_kv('  SMTB_USER sans AUCUNE affectation role', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER u
        WHERE u.USER_STATUS = 'E' AND u.AUTH_STAT = 'A'
          AND NOT EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.USER_ID = u.USER_ID)
          AND NOT EXISTS (SELECT 1 FROM SMTB_USER_CENTRAL_ROLES c WHERE c.USER_ID = u.USER_ID);
    p_kv('  Dont actifs et autorises (ENABLED/Authorised)', TO_CHAR(v_count));

    p_sub('Roles definis MAIS non attribues (orphelins)');
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER m
        WHERE NOT EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.ROLE_ID = m.ROLE_ID)
          AND NOT EXISTS (SELECT 1 FROM SMTB_USER_CENTRAL_ROLES c WHERE c.ROLE_ID = m.ROLE_ID);
    p_kv('  Nombre de roles orphelins', TO_CHAR(v_count));

    p_sub('Roles attribues mais absents de SMTB_ROLE_MASTER (fantomes)');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT ROLE_ID FROM SMTB_USER_ROLE
        WHERE ROLE_ID NOT IN (SELECT ROLE_ID FROM SMTB_ROLE_MASTER)
    );
    p_kv('  Roles fantomes (SMTB_USER_ROLE)', TO_CHAR(v_count));

    p_sub('Utilisateurs attribues mais absents de SMTB_USER');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT USER_ID FROM SMTB_USER_ROLE
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER)
    );
    p_kv('  Utilisateurs fantomes (SMTB_USER_ROLE)', TO_CHAR(v_count));

    p_sub('Echantillon 10 affectations');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, ROLE_ID, BRANCH_CODE, AUTH_STAT
            FROM SMTB_USER_ROLE ORDER BY USER_ID, ROLE_ID
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  USER=' || r.USER_ID, 'ROLE=' || r.ROLE_ID || ' | BRN=' || NVL(r.BRANCH_CODE,'-') || ' | AUTH=' || NVL(r.AUTH_STAT,'-'));
    END LOOP;

    -- ---------- SMTB_USER_CENTRAL_ROLES ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_USER_CENTRAL_ROLES;
    p_kv('Total affectations centralisees (SMTB_USER_CENTRAL_ROLES)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_CENTRAL_ROLES;
        p_kv('  Utilisateurs distincts avec role centralise', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_USER_CENTRAL_ROLES;
        p_kv('  Roles centralises distincts', TO_CHAR(v_count));

        p_sub('Statut d''autorisation (AUTH_STAT)');
        FOR r IN (SELECT AUTH_STAT, COUNT(*) nb FROM SMTB_USER_CENTRAL_ROLES
                  GROUP BY AUTH_STAT ORDER BY nb DESC) LOOP
            p_pct('  AUTH_STAT = ' || NVL(r.AUTH_STAT,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Top 15 utilisateurs les plus dotes en roles centralises');
        FOR r IN (
            SELECT USER_ID, nb FROM (
                SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_CENTRAL_ROLES
                GROUP BY USER_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  USER = ' || NVL(r.USER_ID,'(NULL)'), TO_CHAR(r.nb) || ' role(s)');
        END LOOP;

        p_sub('Top 15 roles centralises les plus attribues');
        FOR r IN (
            SELECT ROLE_ID, nb FROM (
                SELECT ROLE_ID, COUNT(*) nb FROM SMTB_USER_CENTRAL_ROLES
                GROUP BY ROLE_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  ROLE = ' || NVL(r.ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' utilisateur(s)');
        END LOOP;

        p_sub('Cumul total des roles par utilisateur (locaux + centralises) — Top 15');
        FOR r IN (
            SELECT USER_ID, nb FROM (
                SELECT USER_ID, SUM(nb) nb FROM (
                    SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_ROLE GROUP BY USER_ID
                    UNION ALL
                    SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_CENTRAL_ROLES GROUP BY USER_ID
                ) GROUP BY USER_ID
                ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  USER = ' || r.USER_ID, TO_CHAR(r.nb) || ' role(s) cumules');
        END LOOP;
    END IF;

    -- =========================================================
    -- A-07. SMTB_ROLE_FUNC_LIMIT_CUSTOM & SMTB_ROLE_FUNC_LIMIT_DETAIL
    --        — Limites transactionnelles par role/fonction
    -- =========================================================
    p_section('A-07. SMTB_ROLE_FUNC_LIMIT_* — Limites transactionnelles role/fonction');

    -- ---------- SMTB_ROLE_FUNC_LIMIT_CUSTOM ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM;
    p_kv('Total entetes CUSTOM (SMTB_ROLE_FUNC_LIMIT_CUSTOM)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Statut des entetes CUSTOM');
        FOR r IN (SELECT RECORD_STAT, AUTH_STAT, COUNT(*) nb FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM
                  GROUP BY RECORD_STAT, AUTH_STAT ORDER BY nb DESC) LOOP
            p_pct('  Rec=' || NVL(r.RECORD_STAT,'(NULL)') || ' / Auth=' || NVL(r.AUTH_STAT,'(NULL)'),
                  r.nb, v_total);
        END LOOP;

        p_sub('Liste des roles concernes (CUSTOM)');
        FOR r IN (
            SELECT ROLE_ID,
                   SUBSTR(ROLE_DESCRIPTION,1,50) descr,
                   MAKER_ID, CHECKER_ID,
                   TO_CHAR(MAKER_DT_STAMP,'DD/MM/YYYY') mk_dt,
                   TO_CHAR(CHECKER_DT_STAMP,'DD/MM/YYYY') ck_dt,
                   RECORD_STAT, AUTH_STAT, ONCE_AUTH, MOD_NO
            FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM
            ORDER BY ROLE_ID
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  --- ROLE=' || r.ROLE_ID || ' | ' || NVL(r.descr,'-') || ' ---');
            p_kv('    Maker / Date', NVL(r.MAKER_ID,'-') || ' / ' || NVL(r.mk_dt,'-'));
            p_kv('    Checker / Date', NVL(r.CHECKER_ID,'-') || ' / ' || NVL(r.ck_dt,'-'));
            p_kv('    Record/Auth/Once/Mod',
                 r.RECORD_STAT||' / '||r.AUTH_STAT||' / '||NVL(r.ONCE_AUTH,'-')||' / '||r.MOD_NO);
        END LOOP;
    END IF;

    -- ---------- SMTB_ROLE_FUNC_LIMIT_DETAIL ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_FUNC_LIMIT_DETAIL;
    p_kv('Total lignes DETAIL (SMTB_ROLE_FUNC_LIMIT_DETAIL)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL;
        p_kv('  Roles distincts avec limite fonction', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT FUNCTION_ID) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL;
        p_kv('  Fonctions distinctes avec limite', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT LIMIT_CCY) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL;
        p_kv('  Devises distinctes (LIMIT_CCY)', TO_CHAR(v_count));

        p_sub('Repartition par LIMIT_CCY');
        FOR r IN (SELECT LIMIT_CCY, COUNT(*) nb,
                         MIN(INPUT_LIMIT_AMOUNT) mini,
                         ROUND(AVG(INPUT_LIMIT_AMOUNT)) moy,
                         MAX(INPUT_LIMIT_AMOUNT) maxi
                  FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
                  GROUP BY LIMIT_CCY ORDER BY nb DESC) LOOP
            p_kv('  CCY=' || NVL(r.LIMIT_CCY,'(NULL)') || ' | nb=' || r.nb
                 || ' | min=' || r.mini || ' | moy=' || r.moy || ' | max=' || r.maxi,
                 ' ');
        END LOOP;

        p_sub('Repartition par FUNCTION_ID');
        FOR r IN (
            SELECT FUNCTION_ID, nb FROM (
                SELECT FUNCTION_ID, COUNT(*) nb FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
                GROUP BY FUNCTION_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            p_pct('  FUNC = ' || NVL(r.FUNCTION_ID,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Top 20 roles avec le plus de limites configurees');
        FOR r IN (
            SELECT ROLE_ID, nb FROM (
                SELECT ROLE_ID, COUNT(*) nb FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
                GROUP BY ROLE_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 20
        ) LOOP
            p_kv('  ROLE = ' || NVL(r.ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' fonction(s)');
        END LOOP;

        p_sub('Montants plafonds extremes (INPUT_LIMIT_AMOUNT)');
        FOR r IN (
            SELECT * FROM (
                SELECT ROLE_ID, FUNCTION_ID, LIMIT_CCY, INPUT_LIMIT_AMOUNT,
                       SUBSTR(FUNCTION_DESCRIPTION, 1, 50) fd
                FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
                ORDER BY INPUT_LIMIT_AMOUNT DESC NULLS LAST
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  ROLE=' || r.ROLE_ID || ' | FUNC=' || r.FUNCTION_ID || ' | CCY=' || r.LIMIT_CCY,
                 'LIMIT=' || r.INPUT_LIMIT_AMOUNT || ' | ' || NVL(r.fd,'-'));
        END LOOP;

        p_sub('Limites nulles ou zero (anomalies potentielles)');
        SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
            WHERE INPUT_LIMIT_AMOUNT IS NULL OR INPUT_LIMIT_AMOUNT = 0;
        p_pct('  INPUT_LIMIT_AMOUNT NULL ou 0', v_count, v_total);
        SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
            WHERE LIMIT_CCY IS NULL OR LIMIT_CCY = ' ';
        p_pct('  LIMIT_CCY NULL', v_count, v_total);

        p_sub('Coherence DETAIL <-> CUSTOM');
        SELECT COUNT(DISTINCT d.ROLE_ID) INTO v_count
            FROM SMTB_ROLE_FUNC_LIMIT_DETAIL d
            WHERE NOT EXISTS (SELECT 1 FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM c WHERE c.ROLE_ID = d.ROLE_ID);
        p_kv('  Roles presents dans DETAIL absents de CUSTOM', TO_CHAR(v_count));
        SELECT COUNT(*) INTO v_count
            FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM c
            WHERE NOT EXISTS (SELECT 1 FROM SMTB_ROLE_FUNC_LIMIT_DETAIL d WHERE d.ROLE_ID = c.ROLE_ID);
        p_kv('  Roles CUSTOM sans lignes DETAIL', TO_CHAR(v_count));

        p_sub('Echantillon 15 lignes DETAIL');
        FOR r IN (
            SELECT * FROM (
                SELECT ROLE_ID, FUNCTION_ID, LIMIT_CCY, INPUT_LIMIT_AMOUNT,
                       SUBSTR(FUNCTION_DESCRIPTION, 1, 40) fd,
                       SUBSTR(ROLE_DESCRIPTION, 1, 30) rd
                FROM SMTB_ROLE_FUNC_LIMIT_DETAIL
                ORDER BY ROLE_ID, FUNCTION_ID
            ) WHERE ROWNUM <= 15
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  --- ROLE=' || r.ROLE_ID || ' (' || NVL(r.rd,'-') || ')'
                || ' | FUNC=' || r.FUNCTION_ID || ' ---');
            p_kv('    LIMIT / CCY', NVL(TO_CHAR(r.INPUT_LIMIT_AMOUNT),'-') || ' / ' || NVL(r.LIMIT_CCY,'-'));
            p_kv('    Fonction', NVL(r.fd,'-'));
        END LOOP;
    END IF;

    -- =========================================================
    -- A-08. SMTB_PARAMETERS & SMTB_PASSWORD_HISTORY
    --        — Parametres de securite + historique des mots de passe
    -- =========================================================
    p_section('A-08. SMTB_PARAMETERS & SMTB_PASSWORD_HISTORY — Politique MDP & historique');

    -- ---------- SMTB_PARAMETERS ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_PARAMETERS;
    p_kv('Lignes SMTB_PARAMETERS (doit etre 1 — singleton)', TO_CHAR(v_total));

    IF v_total >= 1 THEN
        p_sub('Politique de mot de passe');
        FOR r IN (SELECT * FROM SMTB_PARAMETERS WHERE ROWNUM = 1) LOOP
            p_kv('  Application (APPLICATION_NAME)', NVL(r.APPLICATION_NAME,'-'));
            p_kv('  Site (SITE_CODE)', NVL(r.SITE_CODE,'-'));
            p_kv('  Head office (HEAD_OFFICE)', NVL(r.HEAD_OFFICE,'-'));
            p_kv('  Activation key', NVL(r.ACTIVATION_KEY,'-'));
            p_kv('  Release type', NVL(r.RELEASE_TYPE,'-'));
            DBMS_OUTPUT.PUT_LINE('  -- Politique MDP --');
            p_kv('  MIN_PWD_LENGTH', TO_CHAR(r.MIN_PWD_LENGTH));
            p_kv('  MAX_PWD_LENGTH', TO_CHAR(r.MAX_PWD_LENGTH));
            p_kv('  MIN_PWD_ALPHA_LENGTH', TO_CHAR(r.MIN_PWD_ALPHA_LENGTH));
            p_kv('  MAX_PWD_ALPHA_LENGTH', TO_CHAR(r.MAX_PWD_ALPHA_LENGTH));
            p_kv('  MIN_PWD_NUMERIC_LENGTH', TO_CHAR(r.MIN_PWD_NUMERIC_LENGTH));
            p_kv('  MAX_PWD_NUMERIC_LENGTH', TO_CHAR(r.MAX_PWD_NUMERIC_LENGTH));
            p_kv('  MIN_SPECIALCHAR_LENGTH', NVL(r.MIN_SPECIALCHAR_LENGTH,'-'));
            p_kv('  MAX_SPECIALCHAR_LENGTH', NVL(r.MAX_SPECIALCHAR_LENGTH,'-'));
            p_kv('  MIN_UPPERCASE_CHAR', TO_CHAR(r.MIN_UPPERCASE_CHAR));
            p_kv('  MIN_LOWERCASE_CHAR', TO_CHAR(r.MIN_LOWERCASE_CHAR));
            p_kv('  PWD_HAS_CAPS (majuscules obligatoires ?)', NVL(r.PWD_HAS_CAPS,'-'));
            p_kv('  CONCHAR_PWD_NUM (chars consecutifs interdits)', TO_CHAR(r.CONCHAR_PWD_NUM));
            p_kv('  PWD_CHANGE_AFTER (jours apres creation)', TO_CHAR(r.PWD_CHANGE_AFTER));
            p_kv('  FREQ_PWD_CHG (frequence changement, jours)', TO_CHAR(r.FREQ_PWD_CHG));
            p_kv('  PWD_EXPIRY_MSG_DAYS (alerte avant expiration)', TO_CHAR(r.PWD_EXPIRY_MSG_DAYS));
            p_kv('  PWD_PREVENT_REUSE (historique reuse)', TO_CHAR(r.PWD_PREVENT_REUSE));
            p_kv('  ALWAYS_FOR_PWD_CHANGE', NVL(r.ALWAYS_FOR_PWD_CHANGE,'-'));
            p_kv('  PASSWORD_EXTERNAL (LDAP global)', NVL(r.PASSWORD_EXTERNAL,'-'));
            DBMS_OUTPUT.PUT_LINE('  -- Politique connexion --');
            p_kv('  INVALID_LOGINS_CUM (seuil cumulatif)', TO_CHAR(r.INVALID_LOGINS_CUM));
            p_kv('  INVALID_LOGINS_SUC (seuil successif)', TO_CHAR(r.INVALID_LOGINS_SUC));
            p_kv('  DORMANCY_DAYS (jours avant dormance)', TO_CHAR(r.DORMANCY_DAYS));
            p_kv('  SCREEN_SAVER_REQ', NVL(r.SCREEN_SAVER_REQ,'-'));
            p_kv('  SCREEN_SAVER_TIMEOUT (min)', TO_CHAR(r.SCREEN_SAVER_TIMEOUT));
            p_kv('  SCREEN_SAVER_MODIFIABLE_FLAG', NVL(r.SCREEN_SAVER_MODIFIABLE_FLAG,'-'));
            DBMS_OUTPUT.PUT_LINE('  -- Politique autres --');
            p_kv('  ARCHIVAL_PERIOD (jours conservation)', TO_CHAR(r.ARCHIVAL_PERIOD));
            p_kv('  DISPLAY_LEGAL_NOTICE', NVL(r.DISPLAY_LEGAL_NOTICE,'-'));
            IF r.LEGAL_NOTICE IS NOT NULL THEN
                p_kv('  LEGAL_NOTICE (60 premiers caracteres)', SUBSTR(r.LEGAL_NOTICE, 1, 60));
            ELSE
                p_kv('  LEGAL_NOTICE', 'NON CONFIGURE');
            END IF;
            DBMS_OUTPUT.PUT_LINE('  -- Maker/Checker --');
            p_kv('  Record / Auth / Once', r.RECORD_STAT||' / '||r.AUTH_STAT||' / '||NVL(r.ONCE_AUTH,'-'));
            p_kv('  MAKER_ID', NVL(r.MAKER_ID,'-'));
            p_kv('  CHECKER_ID', NVL(r.CHECKER_ID,'-'));
            p_kv('  MAKER_DT_STAMP', TO_CHAR(r.MAKER_DT_STAMP,'DD/MM/YYYY HH24:MI'));
            p_kv('  CHECKER_DT_STAMP', TO_CHAR(r.CHECKER_DT_STAMP,'DD/MM/YYYY HH24:MI'));
            p_kv('  MOD_NO', TO_CHAR(r.MOD_NO));
        END LOOP;

        p_sub('Evaluation rapide vs bonnes pratiques (COBAC / CIS) — reperes');
        FOR r IN (SELECT * FROM SMTB_PARAMETERS WHERE ROWNUM = 1) LOOP
            IF r.MIN_PWD_LENGTH IS NULL OR r.MIN_PWD_LENGTH < 8 THEN
                p_kv('  Longueur mini mot de passe (attendu >= 8)', 'FAIBLE : ' || NVL(TO_CHAR(r.MIN_PWD_LENGTH),'NULL'));
            ELSE
                p_kv('  Longueur mini mot de passe', 'OK : ' || r.MIN_PWD_LENGTH);
            END IF;
            IF r.FREQ_PWD_CHG IS NULL OR r.FREQ_PWD_CHG > 90 OR r.FREQ_PWD_CHG = 0 THEN
                p_kv('  Rotation mot de passe (attendu <= 90 j)', 'A REVOIR : ' || NVL(TO_CHAR(r.FREQ_PWD_CHG),'NULL'));
            ELSE
                p_kv('  Rotation mot de passe', 'OK : ' || r.FREQ_PWD_CHG || ' j');
            END IF;
            IF r.PWD_PREVENT_REUSE IS NULL OR r.PWD_PREVENT_REUSE < 3 THEN
                p_kv('  Historique reuse (attendu >= 3)', 'A REVOIR : ' || NVL(TO_CHAR(r.PWD_PREVENT_REUSE),'NULL'));
            ELSE
                p_kv('  Historique reuse', 'OK : ' || r.PWD_PREVENT_REUSE);
            END IF;
            IF r.INVALID_LOGINS_SUC IS NULL OR r.INVALID_LOGINS_SUC = 0 OR r.INVALID_LOGINS_SUC > 5 THEN
                p_kv('  Seuil tentatives successives (attendu <= 5)', 'A REVOIR : ' || NVL(TO_CHAR(r.INVALID_LOGINS_SUC),'NULL'));
            ELSE
                p_kv('  Seuil tentatives successives', 'OK : ' || r.INVALID_LOGINS_SUC);
            END IF;
            IF r.DORMANCY_DAYS IS NULL OR r.DORMANCY_DAYS = 0 OR r.DORMANCY_DAYS > 90 THEN
                p_kv('  Delai dormance (attendu <= 90 j)', 'A REVOIR : ' || NVL(TO_CHAR(r.DORMANCY_DAYS),'NULL'));
            ELSE
                p_kv('  Delai dormance', 'OK : ' || r.DORMANCY_DAYS || ' j');
            END IF;
            IF r.SCREEN_SAVER_TIMEOUT IS NULL OR r.SCREEN_SAVER_TIMEOUT = 0 OR r.SCREEN_SAVER_TIMEOUT > 15 THEN
                p_kv('  Timeout ecran (attendu <= 15 min)', 'A REVOIR : ' || NVL(TO_CHAR(r.SCREEN_SAVER_TIMEOUT),'NULL'));
            ELSE
                p_kv('  Timeout ecran', 'OK : ' || r.SCREEN_SAVER_TIMEOUT || ' min');
            END IF;
        END LOOP;
    END IF;

    -- ---------- SMTB_PASSWORD_HISTORY ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_PASSWORD_HISTORY;
    p_kv('Total lignes SMTB_PASSWORD_HISTORY', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_PASSWORD_HISTORY;
        p_kv('  Utilisateurs distincts avec historique', TO_CHAR(v_count));

        SELECT COUNT(*) INTO v_count FROM SMTB_USER u
            WHERE NOT EXISTS (SELECT 1 FROM SMTB_PASSWORD_HISTORY p WHERE p.USER_ID = u.USER_ID);
        p_kv('  SMTB_USER sans historique MDP', TO_CHAR(v_count));

        p_sub('Distribution du nombre d''occurrences par utilisateur');
        FOR r IN (
            SELECT nb_occ, COUNT(*) nb_users FROM (
                SELECT USER_ID, COUNT(*) nb_occ FROM SMTB_PASSWORD_HISTORY GROUP BY USER_ID
            ) GROUP BY nb_occ ORDER BY nb_occ
        ) LOOP
            p_kv('  Nb_rotations = ' || r.nb_occ, TO_CHAR(r.nb_users) || ' utilisateur(s)');
        END LOOP;

        p_sub('Top 15 utilisateurs — plus grand historique MDP');
        FOR r IN (
            SELECT USER_ID, nb FROM (
                SELECT USER_ID, COUNT(*) nb FROM SMTB_PASSWORD_HISTORY
                GROUP BY USER_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  USER = ' || r.USER_ID, TO_CHAR(r.nb) || ' MDP historises');
        END LOOP;

        p_sub('Couverture SALT (hash sale ?)');
        SELECT COUNT(*) INTO v_count FROM SMTB_PASSWORD_HISTORY WHERE SALT IS NULL OR SALT = ' ';
        p_pct('  Lignes SANS SALT', v_count, v_total);
        SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_PASSWORD_HISTORY
            WHERE SALT IS NULL OR SALT = ' ';
        p_kv('  Utilisateurs impactes par SALT manquant', TO_CHAR(v_count));

        p_sub('Detection doublons HASH MDP (signe de reuse ou absence de SALT)');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT PASSWORD_USED, COUNT(DISTINCT USER_ID) nu
            FROM SMTB_PASSWORD_HISTORY
            WHERE PASSWORD_USED IS NOT NULL
            GROUP BY PASSWORD_USED HAVING COUNT(DISTINCT USER_ID) > 1
        );
        p_kv('  Hash partages par >1 utilisateur (signal faible)', TO_CHAR(v_count));

        p_sub('Top 10 hash partages (exhaustif, anonymise)');
        FOR r IN (
            SELECT * FROM (
                SELECT SUBSTR(PASSWORD_USED, 1, 20) hpref, COUNT(DISTINCT USER_ID) nu
                FROM SMTB_PASSWORD_HISTORY
                WHERE PASSWORD_USED IS NOT NULL
                GROUP BY SUBSTR(PASSWORD_USED, 1, 20)
                HAVING COUNT(DISTINCT USER_ID) > 1
                ORDER BY nu DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  Hash prefixe=' || r.hpref, TO_CHAR(r.nu) || ' user(s)');
        END LOOP;
    END IF;

    -- =========================================================
    -- A-09. SMTB_SMS_LOG — Journal des sessions (login/logout, navigation)
    -- =========================================================
    p_section('A-09. SMTB_SMS_LOG — Journal des sessions (volume important)');

    SELECT COUNT(*) INTO v_total FROM SMTB_SMS_LOG;
    p_kv('Total evenements de session', TO_CHAR(v_total));

    p_sub('Bornes temporelles');
    FOR r IN (
        SELECT MIN(START_TIME) mn, MAX(START_TIME) mx FROM SMTB_SMS_LOG
    ) LOOP
        p_kv('  Plus ancien START_TIME', TO_CHAR(r.mn,'DD/MM/YYYY HH24:MI'));
        p_kv('  Plus recent START_TIME', TO_CHAR(r.mx,'DD/MM/YYYY HH24:MI'));
    END LOOP;
    FOR r IN (
        SELECT MIN(SYSTEM_START_TIME) mn, MAX(SYSTEM_START_TIME) mx FROM SMTB_SMS_LOG
    ) LOOP
        p_kv('  Plus ancien SYSTEM_START_TIME', TO_CHAR(r.mn,'DD/MM/YYYY HH24:MI'));
        p_kv('  Plus recent SYSTEM_START_TIME', TO_CHAR(r.mx,'DD/MM/YYYY HH24:MI'));
    END LOOP;

    p_sub('Repartition LOG_TYPE (L=Login, T=Transaction, etc.)');
    FOR r IN (SELECT LOG_TYPE, COUNT(*) nb FROM SMTB_SMS_LOG
              GROUP BY LOG_TYPE ORDER BY nb DESC) LOOP
        p_pct('  LOG_TYPE = ' || NVL(r.LOG_TYPE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Repartition EXIT_FLAG (0=ok / 1=abnormal, convention Flexcube)');
    FOR r IN (SELECT EXIT_FLAG, COUNT(*) nb FROM SMTB_SMS_LOG
              GROUP BY EXIT_FLAG ORDER BY nb DESC) LOOP
        p_pct('  EXIT_FLAG = ' || NVL(TO_CHAR(r.EXIT_FLAG),'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Repartition par MODULE_CODE (top 20)');
    FOR r IN (
        SELECT MODULE_CODE, nb FROM (
            SELECT MODULE_CODE, COUNT(*) nb FROM SMTB_SMS_LOG
            GROUP BY MODULE_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_pct('  MODULE = ' || NVL(r.MODULE_CODE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Repartition par BRANCH_CODE (top 15)');
    FOR r IN (
        SELECT BRANCH_CODE, nb FROM (
            SELECT BRANCH_CODE, COUNT(*) nb FROM SMTB_SMS_LOG
            GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  BRANCH = ' || NVL(r.BRANCH_CODE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Volumetrie par mois (12 derniers mois)');
    FOR r IN (
        SELECT TO_CHAR(SYSTEM_START_TIME,'YYYY-MM') mois, COUNT(*) nb
        FROM SMTB_SMS_LOG
        WHERE SYSTEM_START_TIME >= ADD_MONTHS(SYSDATE, -12)
        GROUP BY TO_CHAR(SYSTEM_START_TIME,'YYYY-MM')
        ORDER BY mois
    ) LOOP
        p_kv('  ' || r.mois, TO_CHAR(r.nb) || ' evenement(s)');
    END LOOP;

    p_sub('Volumetrie par heure de la journee (hotspots)');
    FOR r IN (
        SELECT TO_CHAR(SYSTEM_START_TIME,'HH24') heure, COUNT(*) nb
        FROM SMTB_SMS_LOG
        WHERE SYSTEM_START_TIME >= SYSDATE - 90
        GROUP BY TO_CHAR(SYSTEM_START_TIME,'HH24')
        ORDER BY heure
    ) LOOP
        p_kv('  Heure ' || r.heure || 'h', TO_CHAR(r.nb));
    END LOOP;

    p_sub('Focus LOGIN uniquement (LOG_TYPE=L) — volumetrie 30 j');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
        WHERE LOG_TYPE = 'L' AND SYSTEM_START_TIME >= SYSDATE - 30;
    p_kv('  Login/logout sur 30 derniers jours', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_SMS_LOG
        WHERE LOG_TYPE = 'L' AND SYSTEM_START_TIME >= SYSDATE - 30;
    p_kv('  Utilisateurs uniques connectes sur 30 j', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_SMS_LOG
        WHERE LOG_TYPE = 'L' AND SYSTEM_START_TIME >= SYSDATE - 7;
    p_kv('  Utilisateurs uniques connectes sur 7 j', TO_CHAR(v_count));

    p_sub('Top 15 utilisateurs — volume evenements (tous types, 90 j)');
    FOR r IN (
        SELECT USER_ID, nb FROM (
            SELECT USER_ID, COUNT(*) nb FROM SMTB_SMS_LOG
            WHERE SYSTEM_START_TIME >= SYSDATE - 90
            GROUP BY USER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  USER = ' || NVL(r.USER_ID,'(NULL)'), TO_CHAR(r.nb) || ' evenement(s) / 90j');
    END LOOP;

    p_sub('Top 15 fonctions les plus accedees (FUNCTION_ID, 90 j)');
    FOR r IN (
        SELECT FUNCTION_ID, nb FROM (
            SELECT FUNCTION_ID, COUNT(*) nb FROM SMTB_SMS_LOG
            WHERE SYSTEM_START_TIME >= SYSDATE - 90
            GROUP BY FUNCTION_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  FUNC = ' || NVL(r.FUNCTION_ID,'(NULL)'), TO_CHAR(r.nb));
    END LOOP;

    p_sub('Top 15 terminaux (TERMINAL_ID) - 90 j');
    FOR r IN (
        SELECT TERMINAL_ID, nb FROM (
            SELECT TERMINAL_ID, COUNT(*) nb FROM SMTB_SMS_LOG
            WHERE SYSTEM_START_TIME >= SYSDATE - 90
            GROUP BY TERMINAL_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  TERM = ' || NVL(r.TERMINAL_ID,'(NULL)'), TO_CHAR(r.nb));
    END LOOP;

    p_sub('Connexions multi-terminaux par utilisateur (90 j)');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT USER_ID FROM SMTB_SMS_LOG
        WHERE SYSTEM_START_TIME >= SYSDATE - 90 AND LOG_TYPE = 'L'
        GROUP BY USER_ID HAVING COUNT(DISTINCT TERMINAL_ID) > 1
    );
    p_kv('  Utilisateurs connectes depuis > 1 terminal / 90 j', TO_CHAR(v_count));

    p_sub('Top 10 utilisateurs connectes depuis le plus de terminaux (90 j)');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, COUNT(DISTINCT TERMINAL_ID) nt
            FROM SMTB_SMS_LOG
            WHERE SYSTEM_START_TIME >= SYSDATE - 90 AND LOG_TYPE = 'L'
            GROUP BY USER_ID ORDER BY nt DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  USER = ' || r.USER_ID, TO_CHAR(r.nt) || ' terminaux distincts / 90 j');
    END LOOP;

    p_sub('Connexions hors heures ouvrees (19h-6h) — 90 j');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
        WHERE LOG_TYPE = 'L' AND SYSTEM_START_TIME >= SYSDATE - 90
          AND (TO_NUMBER(TO_CHAR(SYSTEM_START_TIME,'HH24')) < 6
               OR TO_NUMBER(TO_CHAR(SYSTEM_START_TIME,'HH24')) >= 19);
    p_kv('  Connexions nocturnes (<6h ou >=19h) sur 90 j', TO_CHAR(v_count));

    p_sub('Connexions week-end (samedi/dimanche) — 90 j');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
        WHERE LOG_TYPE = 'L' AND SYSTEM_START_TIME >= SYSDATE - 90
          AND TO_CHAR(SYSTEM_START_TIME,'D','NLS_DATE_LANGUAGE=ENGLISH') IN ('6','7');
    p_kv('  Connexions week-end sur 90 j', TO_CHAR(v_count));

    p_sub('Top 10 descriptions d''evenements (DESCRIPTION)');
    FOR r IN (
        SELECT DESCRIPTION, nb FROM (
            SELECT SUBSTR(DESCRIPTION, 1, 60) AS DESCRIPTION, COUNT(*) nb
            FROM SMTB_SMS_LOG
            WHERE DESCRIPTION IS NOT NULL
            GROUP BY SUBSTR(DESCRIPTION, 1, 60) ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_pct('  ' || NVL(r.DESCRIPTION,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Echantillon 10 evenements LOGIN recents');
    FOR r IN (
        SELECT * FROM (
            SELECT USER_ID, BRANCH_CODE, TERMINAL_ID, FUNCTION_ID,
                   TO_CHAR(SYSTEM_START_TIME,'DD/MM/YYYY HH24:MI:SS') dt,
                   EXIT_FLAG,
                   SUBSTR(DESCRIPTION, 1, 50) descr
            FROM SMTB_SMS_LOG
            WHERE LOG_TYPE = 'L'
            ORDER BY SYSTEM_START_TIME DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  ' || r.dt || ' | USER=' || r.USER_ID || ' | BRN=' || NVL(r.BRANCH_CODE,'-'),
             'TERM=' || NVL(r.TERMINAL_ID,'-') || ' | FUNC=' || NVL(r.FUNCTION_ID,'-')
             || ' | EXIT=' || NVL(TO_CHAR(r.EXIT_FLAG),'-'));
    END LOOP;

    -- =========================================================
    -- A-10. SMTB_SMS_ACTION_LOG — Journal des actions metier
    --        (piste d'audit applicatif : creation, modification, autorisation)
    -- =========================================================
    p_section('A-10. SMTB_SMS_ACTION_LOG — Journal des actions metier (piste d''audit)');

    SELECT COUNT(*) INTO v_total FROM SMTB_SMS_ACTION_LOG;
    p_kv('Total actions enregistrees', TO_CHAR(v_total));

    p_sub('Bornes temporelles');
    FOR r IN (SELECT MIN(REQ_TIME) mn, MAX(REQ_TIME) mx FROM SMTB_SMS_ACTION_LOG) LOOP
        p_kv('  Plus ancien REQ_TIME', TO_CHAR(r.mn,'DD/MM/YYYY HH24:MI'));
        p_kv('  Plus recent REQ_TIME', TO_CHAR(r.mx,'DD/MM/YYYY HH24:MI'));
    END LOOP;

    p_sub('Distribution des ACTION (top 25)');
    FOR r IN (
        SELECT ACTION, nb FROM (
            SELECT ACTION, COUNT(*) nb FROM SMTB_SMS_ACTION_LOG
            GROUP BY ACTION ORDER BY nb DESC
        ) WHERE ROWNUM <= 25
    ) LOOP
        p_pct('  ACTION = ' || NVL(r.ACTION,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Distribution EXITFLAG (0=ok / 1=abnormal, convention Flexcube)');
    FOR r IN (SELECT EXITFLAG, COUNT(*) nb FROM SMTB_SMS_ACTION_LOG
              GROUP BY EXITFLAG ORDER BY nb DESC) LOOP
        p_pct('  EXITFLAG = ' || NVL(TO_CHAR(r.EXITFLAG),'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Actions d''ECHEC (EXITFLAG != 0) — focus ACTION');
    FOR r IN (
        SELECT ACTION, nb FROM (
            SELECT ACTION, COUNT(*) nb FROM SMTB_SMS_ACTION_LOG
            WHERE EXITFLAG IS NOT NULL AND EXITFLAG <> 0
            GROUP BY ACTION ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ACTION = ' || NVL(r.ACTION,'(NULL)'), TO_CHAR(r.nb) || ' echec(s)');
    END LOOP;

    p_sub('Actions sensibles — focus securite / parametres');
    FOR a IN (
        SELECT action FROM (
            SELECT 'NEW' AS action, 1 ord FROM DUAL UNION ALL
            SELECT 'MODIFY',         2 FROM DUAL UNION ALL
            SELECT 'DELETE',         3 FROM DUAL UNION ALL
            SELECT 'CLOSE',          4 FROM DUAL UNION ALL
            SELECT 'REOPEN',         5 FROM DUAL UNION ALL
            SELECT 'AUTH',           6 FROM DUAL UNION ALL
            SELECT 'AUTHORIZE',      7 FROM DUAL UNION ALL
            SELECT 'REVERSE',        8 FROM DUAL UNION ALL
            SELECT 'UNLOCK',         9 FROM DUAL UNION ALL
            SELECT 'HOLD',          10 FROM DUAL UNION ALL
            SELECT 'LIQUIDATE',     11 FROM DUAL UNION ALL
            SELECT 'AMEND',         12 FROM DUAL UNION ALL
            SELECT 'ROLLOVER',      13 FROM DUAL UNION ALL
            SELECT 'DELETEALL',     14 FROM DUAL UNION ALL
            SELECT 'COPY',          15 FROM DUAL UNION ALL
            SELECT 'PRINT',         16 FROM DUAL UNION ALL
            SELECT 'REJECT',        17 FROM DUAL ORDER BY ord
        )
    ) LOOP
        EXECUTE IMMEDIATE
            'SELECT COUNT(*) FROM SMTB_SMS_ACTION_LOG WHERE UPPER(ACTION) = :1'
            INTO v_count USING a.action;
        p_kv('  ACTION = ' || a.action, TO_CHAR(v_count));
    END LOOP;

    p_sub('Repartition par CURR_BRANCH (top 15)');
    FOR r IN (
        SELECT CURR_BRANCH, nb FROM (
            SELECT CURR_BRANCH, COUNT(*) nb FROM SMTB_SMS_ACTION_LOG
            GROUP BY CURR_BRANCH ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  CURR_BRANCH = ' || NVL(r.CURR_BRANCH,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Divergence CURR_BRANCH <> HOME_BRANCH (multi-agence)');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_ACTION_LOG
        WHERE CURR_BRANCH IS NOT NULL AND HOME_BRANCH IS NOT NULL
          AND CURR_BRANCH <> HOME_BRANCH;
    p_pct('  Nb actions CURR_BRANCH <> HOME_BRANCH', v_count, v_total);

    p_sub('Volumetrie par mois (12 derniers mois)');
    FOR r IN (
        SELECT TO_CHAR(REQ_TIME,'YYYY-MM') mois, COUNT(*) nb
        FROM SMTB_SMS_ACTION_LOG
        WHERE REQ_TIME >= ADD_MONTHS(SYSDATE, -12)
        GROUP BY TO_CHAR(REQ_TIME,'YYYY-MM') ORDER BY mois
    ) LOOP
        p_kv('  ' || r.mois, TO_CHAR(r.nb) || ' action(s)');
    END LOOP;

    p_sub('Duree moyenne requete (REQ_TIME -> RESP_TIME) en secondes');
    FOR r IN (
        SELECT ROUND(AVG(EXTRACT(DAY FROM (RESP_TIME - REQ_TIME)) * 86400 +
                         EXTRACT(HOUR FROM (RESP_TIME - REQ_TIME)) * 3600 +
                         EXTRACT(MINUTE FROM (RESP_TIME - REQ_TIME)) * 60 +
                         EXTRACT(SECOND FROM (RESP_TIME - REQ_TIME))), 2) secs
        FROM SMTB_SMS_ACTION_LOG
        WHERE RESP_TIME IS NOT NULL AND REQ_TIME IS NOT NULL
          AND REQ_TIME >= SYSDATE - 90
    ) LOOP
        p_kv('  Duree moyenne action sur 90 j (sec)', TO_CHAR(r.secs));
    END LOOP;

    p_sub('Actions en erreur (DESCRIPTION non nulle + EXITFLAG!=0) — top 15');
    FOR r IN (
        SELECT DESCRIPTION, nb FROM (
            SELECT SUBSTR(DESCRIPTION, 1, 80) AS DESCRIPTION, COUNT(*) nb
            FROM SMTB_SMS_ACTION_LOG
            WHERE EXITFLAG IS NOT NULL AND EXITFLAG <> 0
              AND DESCRIPTION IS NOT NULL
            GROUP BY SUBSTR(DESCRIPTION, 1, 80) ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ' || NVL(r.DESCRIPTION,'(NULL)'), TO_CHAR(r.nb));
    END LOOP;

    p_sub('Echantillon 10 actions recentes');
    FOR r IN (
        SELECT * FROM (
            SELECT SEQUENCE_NO, ACTION_SEQUENCE_NO, ACTION,
                   TO_CHAR(REQ_TIME,'DD/MM/YYYY HH24:MI:SS') dt,
                   CURR_BRANCH, HOME_BRANCH, TXN_BRANCH, EXITFLAG,
                   SUBSTR(DESCRIPTION, 1, 60) descr,
                   SUBSTR(PKVALS, 1, 40) pk
            FROM SMTB_SMS_ACTION_LOG
            ORDER BY REQ_TIME DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  --- ' || r.dt || ' | SEQ=' || r.SEQUENCE_NO
            || '/' || r.ACTION_SEQUENCE_NO || ' | ACTION=' || r.ACTION || ' ---');
        p_kv('    Branches (CURR/HOME/TXN)', NVL(r.CURR_BRANCH,'-')||' / '||NVL(r.HOME_BRANCH,'-')
              ||' / '||NVL(r.TXN_BRANCH,'-'));
        p_kv('    EXITFLAG / PKVALS', NVL(TO_CHAR(r.EXITFLAG),'-')||' / '||NVL(r.pk,'-'));
        p_kv('    Description', NVL(r.descr,'-'));
    END LOOP;

    p_sub('Correlation avec SMTB_SMS_LOG : actions sans session loguee');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_ACTION_LOG a
        WHERE a.REQ_TIME >= SYSDATE - 30
          AND NOT EXISTS (
              SELECT 1 FROM SMTB_SMS_LOG l
              WHERE l.SEQUENCE_NO = a.SEQUENCE_NO
          );
    p_kv('  Actions 30 j sans entete session correspondante', TO_CHAR(v_count));

    -- =========================================================
    -- A-11. SMTB_MENU, SMTB_FUNCTION_DESCRIPTION, SMTB_MODULES,
    --        SMTB_LANGUAGE, SMTB_FUNC_GROUP — Catalogue fonctionnel
    -- =========================================================
    p_section('A-11. Catalogue fonctionnel (MENU / FUNCTION_DESCRIPTION / MODULES / LANGUAGE / FUNC_GROUP)');

    -- ---------- SMTB_MENU ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_MENU;
    p_kv('Total fonctions declarees (SMTB_MENU)', TO_CHAR(v_total));

    p_sub('Disponibilite (AVAILABLE : 1=oui / 0=non)');
    FOR r IN (SELECT AVAILABLE, COUNT(*) nb FROM SMTB_MENU
              GROUP BY AVAILABLE ORDER BY nb DESC) LOOP
        p_pct('  AVAILABLE = ' || NVL(TO_CHAR(r.AVAILABLE),'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Flags de securite par fonction');
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE LOG_EVENT = 1;
    p_pct('  LOG_EVENT=1 (evenement journalise)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE LOGGING_REQD = 'Y';
    p_pct('  LOGGING_REQD=Y (logging explicite requis)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE DUAL_AUTH_REQD = 'Y';
    p_pct('  DUAL_AUTH_REQD=Y (double autorisation)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE AUTO_AUTH = 'Y';
    p_pct('  AUTO_AUTH=Y (auto-authorisation autorisee)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE REMARKS_REQD = 'Y';
    p_pct('  REMARKS_REQD=Y (justification obligatoire)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE FIELD_LOG_REQD = 'Y';
    p_pct('  FIELD_LOG_REQD=Y (log par champ)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE TANK_MODIFICATIONS = 'Y';
    p_pct('  TANK_MODIFICATIONS=Y (modifs stockees en tank)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE HO_FUNCTION = 'Y';
    p_pct('  HO_FUNCTION=Y (fonction head-office uniquement)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE CUST_ACCESS = 1;
    p_pct('  CUST_ACCESS=1 (fonction personnalisable)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE EOD_FUNCTION = 'Y';
    p_pct('  EOD_FUNCTION=Y (fonction End-of-Day)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE EXPORT_REQD = 'Y';
    p_pct('  EXPORT_REQD=Y (export donnees)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE MULTIBRANCH_ACCESS = 'Y';
    p_pct('  MULTIBRANCH_ACCESS=Y (acces multi-agences)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE DUPLICATE_TASK_CHK = 'Y';
    p_pct('  DUPLICATE_TASK_CHK=Y (controle doublon)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE ALLOW_ONLY_IN_NORMAL = 'Y';
    p_pct('  ALLOW_ONLY_IN_NORMAL=Y (hors demo uniquement)', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE ALLOW_IN_DEMO = 'Y';
    p_pct('  ALLOW_IN_DEMO=Y (autorise en demo)', v_count, v_total);

    p_sub('Timeout session par fonction (SESSION_INTERVAL)');
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE SESSION_INTERVAL IS NULL OR SESSION_INTERVAL = 0;
    p_pct('  Fonctions sans SESSION_INTERVAL', v_count, v_total);
    FOR r IN (
        SELECT ROUND(AVG(SESSION_INTERVAL),2) moy, MIN(SESSION_INTERVAL) mini, MAX(SESSION_INTERVAL) maxi
        FROM SMTB_MENU WHERE SESSION_INTERVAL > 0
    ) LOOP
        p_kv('  Moy / Min / Max SESSION_INTERVAL', NVL(TO_CHAR(r.moy),'-')||' / '||NVL(TO_CHAR(r.mini),'-')||' / '||NVL(TO_CHAR(r.maxi),'-'));
    END LOOP;

    p_sub('MAX_RES_ROWS (plafond lignes retour) — stats');
    FOR r IN (
        SELECT ROUND(AVG(MAX_RES_ROWS),2) moy, MIN(MAX_RES_ROWS) mini, MAX(MAX_RES_ROWS) maxi
        FROM SMTB_MENU WHERE MAX_RES_ROWS > 0
    ) LOOP
        p_kv('  Moy / Min / Max MAX_RES_ROWS', NVL(TO_CHAR(r.moy),'-')||' / '||NVL(TO_CHAR(r.mini),'-')||' / '||NVL(TO_CHAR(r.maxi),'-'));
    END LOOP;

    p_sub('Distribution MODULE (top 15)');
    FOR r IN (
        SELECT MODULE, nb FROM (
            SELECT MODULE, COUNT(*) nb FROM SMTB_MENU
            GROUP BY MODULE ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_pct('  MODULE = ' || NVL(r.MODULE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Type de fonction (EXECUTABLE_TYPE)');
    FOR r IN (SELECT EXECUTABLE_TYPE, COUNT(*) nb FROM SMTB_MENU
              GROUP BY EXECUTABLE_TYPE ORDER BY nb DESC) LOOP
        p_pct('  EXECUTABLE_TYPE = ' || NVL(r.EXECUTABLE_TYPE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Origine (FUNCTION_ORIGIN) — standard vs custom');
    FOR r IN (SELECT FUNCTION_ORIGIN, COUNT(*) nb FROM SMTB_MENU
              GROUP BY FUNCTION_ORIGIN ORDER BY nb DESC) LOOP
        p_pct('  ORIGIN = ' || NVL(r.FUNCTION_ORIGIN,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Fonctions customisees (CUSTOM_MODIFIED / CLUSTER_MODIFIED)');
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE CUSTOM_MODIFIED = 'Y';
    p_pct('  CUSTOM_MODIFIED=Y', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_MENU WHERE CLUSTER_MODIFIED = 'Y';
    p_pct('  CLUSTER_MODIFIED=Y', v_count, v_total);

    p_sub('Echantillon 10 fonctions sensibles (SM*) — focus gestion des acces');
    FOR r IN (
        SELECT * FROM (
            SELECT FUNCTION_ID, MODULE, AVAILABLE, LOG_EVENT, DUAL_AUTH_REQD,
                   AUTO_AUTH, REMARKS_REQD, FIELD_LOG_REQD
            FROM SMTB_MENU
            WHERE FUNCTION_ID LIKE 'SM%'
            ORDER BY FUNCTION_ID
        ) WHERE ROWNUM <= 15
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  --- FUNC=' || r.FUNCTION_ID || ' | MOD=' || NVL(r.MODULE,'-') || ' ---');
        p_kv('    Available / LogEvent',
             NVL(TO_CHAR(r.AVAILABLE),'-') || ' / ' || NVL(TO_CHAR(r.LOG_EVENT),'-'));
        p_kv('    DualAuth / AutoAuth / Remarks / FieldLog',
             NVL(r.DUAL_AUTH_REQD,'-') || ' / ' || NVL(r.AUTO_AUTH,'-')
             || ' / ' || NVL(r.REMARKS_REQD,'-') || ' / ' || NVL(r.FIELD_LOG_REQD,'-'));
    END LOOP;

    -- ---------- SMTB_FUNCTION_DESCRIPTION ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_FUNCTION_DESCRIPTION;
    p_kv('Total descriptions fonctions (SMTB_FUNCTION_DESCRIPTION)', TO_CHAR(v_total));

    p_sub('Distribution par langue (LANG_CODE)');
    FOR r IN (SELECT LANG_CODE, COUNT(*) nb FROM SMTB_FUNCTION_DESCRIPTION
              GROUP BY LANG_CODE ORDER BY nb DESC) LOOP
        p_pct('  LANG = ' || NVL(r.LANG_CODE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Distribution par MAIN_MENU (top 15)');
    FOR r IN (
        SELECT MAIN_MENU, nb FROM (
            SELECT MAIN_MENU, COUNT(*) nb FROM SMTB_FUNCTION_DESCRIPTION
            WHERE LANG_CODE IN ('ENG','FRN')
            GROUP BY MAIN_MENU ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  MAIN_MENU = ' || NVL(r.MAIN_MENU,'(NULL)'), TO_CHAR(r.nb));
    END LOOP;

    -- ---------- SMTB_MODULES ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_MODULES;
    p_kv('Total modules applicatifs (SMTB_MODULES)', TO_CHAR(v_total));

    p_sub('Statut d''installation (INSTALLED)');
    FOR r IN (SELECT INSTALLED, COUNT(*) nb FROM SMTB_MODULES
              GROUP BY INSTALLED ORDER BY nb DESC) LOOP
        p_pct('  INSTALLED = ' || NVL(r.INSTALLED,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Licence (LICENSE)');
    FOR r IN (SELECT LICENSE, COUNT(*) nb FROM SMTB_MODULES
              GROUP BY LICENSE ORDER BY nb DESC) LOOP
        p_pct('  LICENSE = ' || NVL(r.LICENSE,'(NULL)'), r.nb, v_total);
    END LOOP;

    p_sub('Statut enregistrement (RECORD_STAT / AUTH_STAT)');
    FOR r IN (SELECT RECORD_STAT, AUTH_STAT, COUNT(*) nb FROM SMTB_MODULES
              GROUP BY RECORD_STAT, AUTH_STAT ORDER BY nb DESC) LOOP
        p_pct('  Rec/Auth = ' || NVL(r.RECORD_STAT,'-') || '/' || NVL(r.AUTH_STAT,'-'), r.nb, v_total);
    END LOOP;

    p_sub('Liste des modules installes (INSTALLED=Y)');
    FOR r IN (
        SELECT MODULE_ID, SUBSTR(MODULE_DESC,1,50) mdesc, LICENSE
        FROM SMTB_MODULES
        WHERE INSTALLED = 'Y'
        ORDER BY MODULE_ID
    ) LOOP
        p_kv('  ' || RPAD(r.MODULE_ID,8), NVL(r.mdesc,'-') || ' | LIC=' || NVL(r.LICENSE,'-'));
    END LOOP;

    -- ---------- SMTB_LANGUAGE ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_LANGUAGE;
    p_kv('Total langues (SMTB_LANGUAGE)', TO_CHAR(v_total));
    FOR r IN (
        SELECT LANG_CODE, LANG_NAME, LANG_ISO_CODE, DISPLAY_DIRECTION,
               RECORD_STAT, AUTH_STAT
        FROM SMTB_LANGUAGE ORDER BY LANG_CODE
    ) LOOP
        p_kv('  ' || r.LANG_CODE || ' (' || NVL(r.LANG_ISO_CODE,'-') || ')',
             NVL(r.LANG_NAME,'-') || ' | dir=' || NVL(r.DISPLAY_DIRECTION,'-')
             || ' | rec/auth=' || NVL(r.RECORD_STAT,'-') || '/' || NVL(r.AUTH_STAT,'-'));
    END LOOP;

    -- ---------- SMTB_FUNC_GROUP ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_FUNC_GROUP;
    p_kv('Total SMTB_FUNC_GROUP (groupes transactionnels)', TO_CHAR(v_total));

    p_sub('Distribution par TRANSACTION_TYPE');
    FOR r IN (SELECT TRANSACTION_TYPE, COUNT(*) nb FROM SMTB_FUNC_GROUP
              GROUP BY TRANSACTION_TYPE ORDER BY nb DESC) LOOP
        p_pct('  TYPE = ' || NVL(r.TRANSACTION_TYPE,'(NULL)'), r.nb, v_total);
    END LOOP;

    -- =========================================================
    -- A-12. SMTB_MSGS_RIGHTS / SMTB_QUEUES / SMTB_QUEUE_RIGHTS /
    --        SMTB_ACTION_CONTROLS / SMTB_STAGE_FIELD_VALUE
    --        — Droits sur messages SWIFT, files et actions controlees
    -- =========================================================
    p_section('A-12. Droits messages SWIFT / files / actions / stages');

    -- ---------- SMTB_MSGS_RIGHTS ----------
    SELECT COUNT(*) INTO v_total FROM SMTB_MSGS_RIGHTS;
    p_kv('Total droits messagerie (SMTB_MSGS_RIGHTS)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT USER_ROLE_ID) INTO v_count FROM SMTB_MSGS_RIGHTS;
        p_kv('  Beneficiaires distincts (user/role)', TO_CHAR(v_count));

        p_sub('Type de beneficiaire (USER_ROLE_FLAG : U=User, R=Role)');
        FOR r IN (SELECT USER_ROLE_FLAG, COUNT(*) nb FROM SMTB_MSGS_RIGHTS
                  GROUP BY USER_ROLE_FLAG ORDER BY nb DESC) LOOP
            p_pct('  FLAG = ' || NVL(r.USER_ROLE_FLAG,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Decompte des droits accordes (Y) par action');
        FOR a IN (
            SELECT col FROM (
                SELECT 'GENERATE' col, 1 ord FROM DUAL UNION ALL
                SELECT 'HOLD',             2 FROM DUAL UNION ALL
                SELECT 'CANCEL',           3 FROM DUAL UNION ALL
                SELECT 'TEST_INPUT',       4 FROM DUAL UNION ALL
                SELECT 'CHANGE_NODE',      5 FROM DUAL UNION ALL
                SELECT 'CHANGE_ADDR',      6 FROM DUAL UNION ALL
                SELECT 'RELEASE',          7 FROM DUAL UNION ALL
                SELECT 'REINSTATE',        8 FROM DUAL UNION ALL
                SELECT 'CHANGE_MEDIA',     9 FROM DUAL UNION ALL
                SELECT 'CHANGE_PRIOR',    10 FROM DUAL UNION ALL
                SELECT 'BRANCH_MOVE',     11 FROM DUAL UNION ALL
                SELECT 'PRINT',           12 FROM DUAL UNION ALL
                SELECT 'TEST_CHECK',      13 FROM DUAL UNION ALL
                SELECT 'HOLD_AUTH',       14 FROM DUAL UNION ALL
                SELECT 'CANCEL_AUTH',     15 FROM DUAL UNION ALL
                SELECT 'RELEASE_AUTH',    16 FROM DUAL UNION ALL
                SELECT 'REINSTATE_AUTH',  17 FROM DUAL UNION ALL
                SELECT 'FT_UPLOAD',       18 FROM DUAL UNION ALL
                SELECT 'LINK_CONTRACT',   19 FROM DUAL UNION ALL
                SELECT 'MOVE_QUEUE',      20 FROM DUAL UNION ALL
                SELECT 'CHANGE_MSG',      21 FROM DUAL UNION ALL
                SELECT 'SUPPRESS',        22 FROM DUAL UNION ALL
                SELECT 'DELETE_MSG',      23 FROM DUAL UNION ALL
                SELECT 'AUTH_RIGHTS',     24 FROM DUAL ORDER BY ord
            )
        ) LOOP
            EXECUTE IMMEDIATE
                'SELECT COUNT(*) FROM SMTB_MSGS_RIGHTS WHERE ' || a.col || ' = ''Y'''
                INTO v_count;
            p_pct('  ' || RPAD(a.col, 20), v_count, v_total);
        END LOOP;

        p_sub('Top 10 beneficiaires avec le plus de droits cumulables');
        FOR r IN (
            SELECT * FROM (
                SELECT USER_ROLE_ID,
                       (CASE WHEN GENERATE='Y' THEN 1 ELSE 0 END
                      + CASE WHEN HOLD='Y'     THEN 1 ELSE 0 END
                      + CASE WHEN CANCEL='Y'   THEN 1 ELSE 0 END
                      + CASE WHEN RELEASE='Y'  THEN 1 ELSE 0 END
                      + CASE WHEN REINSTATE='Y' THEN 1 ELSE 0 END
                      + CASE WHEN CHANGE_MSG='Y' THEN 1 ELSE 0 END
                      + CASE WHEN SUPPRESS='Y' THEN 1 ELSE 0 END
                      + CASE WHEN DELETE_MSG='Y' THEN 1 ELSE 0 END
                      + CASE WHEN AUTH_RIGHTS='Y' THEN 1 ELSE 0 END) AS score
                FROM SMTB_MSGS_RIGHTS
                ORDER BY score DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  Beneficiaire = ' || r.USER_ROLE_ID, 'score=' || r.score || ' droit(s) sensibles');
        END LOOP;
    END IF;

    -- ---------- SMTB_QUEUES ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_QUEUES;
    p_kv('Total files d''attente (SMTB_QUEUES)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Liste des files declarees');
        FOR r IN (
            SELECT QUEUE, SUBSTR(DESCRIPTION,1,50) descr,
                   RECORD_STAT, AUTH_STAT, COLLECTION_QUEUE
            FROM SMTB_QUEUES ORDER BY QUEUE
        ) LOOP
            p_kv('  ' || RPAD(r.QUEUE,20), NVL(r.descr,'-') || ' | RS/AS='||NVL(r.RECORD_STAT,'-')
                 ||'/'||NVL(r.AUTH_STAT,'-')||' | COL='||NVL(r.COLLECTION_QUEUE,'-'));
        END LOOP;
    END IF;

    -- ---------- SMTB_QUEUE_RIGHTS ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_QUEUE_RIGHTS;
    p_kv('Total droits sur files (SMTB_QUEUE_RIGHTS)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Repartition par file (QUEUE) et type beneficiaire');
        FOR r IN (SELECT QUEUE, USER_ROLE_FLAG, COUNT(*) nb
                  FROM SMTB_QUEUE_RIGHTS
                  GROUP BY QUEUE, USER_ROLE_FLAG
                  ORDER BY QUEUE, nb DESC) LOOP
            p_kv('  QUEUE=' || r.QUEUE || ' | FLAG=' || NVL(r.USER_ROLE_FLAG,'-'),
                 TO_CHAR(r.nb) || ' beneficiaire(s)');
        END LOOP;

        p_sub('Top 15 beneficiaires (USER_ROLE_ID)');
        FOR r IN (
            SELECT USER_ROLE_ID, nb FROM (
                SELECT USER_ROLE_ID, COUNT(*) nb FROM SMTB_QUEUE_RIGHTS
                GROUP BY USER_ROLE_ID ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  Beneficiaire = ' || NVL(r.USER_ROLE_ID,'(NULL)'), TO_CHAR(r.nb) || ' file(s)');
        END LOOP;
    END IF;

    -- ---------- SMTB_ACTION_CONTROLS ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_ACTION_CONTROLS;
    p_kv('Total controles d''actions (SMTB_ACTION_CONTROLS)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Liste des actions controlees');
        FOR r IN (
            SELECT SERIAL_NO, ACTION_NAME, ACTION_PARENT,
                   SUBSTR(CONTROL_STRING, 1, 30) cs,
                   SUBSTR(TYPE_STRING, 1, 20) ts
            FROM SMTB_ACTION_CONTROLS ORDER BY SERIAL_NO
        ) LOOP
            p_kv('  SN=' || r.SERIAL_NO || ' | ACTION=' || RPAD(NVL(r.ACTION_NAME,'-'),18)
                 || ' | PARENT=' || NVL(r.ACTION_PARENT,'-'),
                 'CTRL=' || NVL(r.cs,'-') || ' | TYPE=' || NVL(r.ts,'-'));
        END LOOP;
    END IF;

    -- ---------- SMTB_STAGE_FIELD_VALUE ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_STAGE_FIELD_VALUE;
    p_kv('Total valeurs stage (SMTB_STAGE_FIELD_VALUE)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Distribution par PROCESS_CODE / STAGE');
        FOR r IN (SELECT PROCESS_CODE, COUNT(DISTINCT STAGE) nst, COUNT(*) nb
                  FROM SMTB_STAGE_FIELD_VALUE
                  GROUP BY PROCESS_CODE ORDER BY nb DESC) LOOP
            p_kv('  PROC=' || NVL(r.PROCESS_CODE,'(NULL)'),
                 TO_CHAR(r.nst) || ' stage(s) / ' || TO_CHAR(r.nb) || ' lignes');
        END LOOP;

        p_sub('Echantillon 10 lignes');
        FOR r IN (
            SELECT * FROM (
                SELECT PROCESS_CODE, STAGE, PAYLOAD_FIELD,
                       SUBSTR(XPATH_EXPRESSION, 1, 60) xp
                FROM SMTB_STAGE_FIELD_VALUE
                ORDER BY PROCESS_CODE, STAGE
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  PROC=' || r.PROCESS_CODE || ' | STAGE=' || r.STAGE,
                 'FIELD=' || NVL(r.PAYLOAD_FIELD,'-') || ' | XPATH=' || NVL(r.xp,'-'));
        END LOOP;
    END IF;

    -- =========================================================
    -- A-13. FBTB_USER / FBTM_BRANCH / FBTM_BRANCH_INFO / SMTB_USER_TILLS
    --        — Comptes FlexBranch, agences et rattachement caisses
    -- =========================================================
    p_section('A-13. FlexBranch users / branches / tills');

    -- ---------- FBTB_USER ----------
    SELECT COUNT(*) INTO v_total FROM FBTB_USER;
    p_kv('Total utilisateurs FlexBranch (FBTB_USER)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT USERID) INTO v_count FROM FBTB_USER;
        p_kv('  USERID distincts', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT BRANCHCODE) INTO v_count FROM FBTB_USER;
        p_kv('  BRANCHCODE distincts', TO_CHAR(v_count));

        p_sub('Statut utilisateur (USER_STATUS)');
        FOR r IN (SELECT USER_STATUS, COUNT(*) nb FROM FBTB_USER
                  GROUP BY USER_STATUS ORDER BY nb DESC) LOOP
            p_pct('  USER_STATUS = ' || NVL(r.USER_STATUS,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Statut login (LOGINSTATUS)');
        FOR r IN (SELECT LOGINSTATUS, COUNT(*) nb FROM FBTB_USER
                  GROUP BY LOGINSTATUS ORDER BY nb DESC) LOOP
            p_pct('  LOGINSTATUS = ' || NVL(r.LOGINSTATUS,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Mode connexion (ONLINE_TXN)');
        FOR r IN (SELECT ONLINE_TXN, COUNT(*) nb FROM FBTB_USER
                  GROUP BY ONLINE_TXN ORDER BY nb DESC) LOOP
            p_pct('  ONLINE_TXN = ' || NVL(r.ONLINE_TXN,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('LDAP (LDAPUSER)');
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE LDAPUSER = 'Y';
        p_pct('  LDAPUSER=Y', v_count, v_total);

        p_sub('Acces multi-agences (MULTIBRANCH_ACCESS)');
        FOR r IN (SELECT MULTIBRANCH_ACCESS, COUNT(*) nb FROM FBTB_USER
                  GROUP BY MULTIBRANCH_ACCESS ORDER BY nb DESC) LOOP
            p_pct('  MULTIBRANCH_ACCESS = ' || NVL(r.MULTIBRANCH_ACCESS,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Couverture mot de passe / SALT');
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE PASSWORD IS NULL OR PASSWORD = ' ';
        p_pct('  Sans PASSWORD', v_count, v_total);
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE SALT IS NULL OR SALT = ' ';
        p_pct('  Sans SALT', v_count, v_total);

        p_sub('Tentatives echouees (FAILURE_LOGINS)');
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE FAILURE_LOGINS >= 3;
        p_pct('  >= 3 echecs consecutifs', v_count, v_total);
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE FAILURE_LOGINS >= 5;
        p_pct('  >= 5 echecs consecutifs', v_count, v_total);

        p_sub('Anciennete de connexion');
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE LAST_ONLINE_LOGIN IS NULL;
        p_pct('  Jamais connecte ONLINE', v_count, v_total);
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE LAST_ONLINE_LOGIN < SYSDATE - 90;
        p_pct('  LAST_ONLINE_LOGIN > 90 j', v_count, v_total);
        SELECT COUNT(*) INTO v_count FROM FBTB_USER WHERE LAST_OFFLINE_LOGIN IS NOT NULL;
        p_pct('  Avec login OFFLINE au moins une fois', v_count, v_total);

        p_sub('Plafonds transaction (MAXTXNAMT / MAXAUTHAMT) par LIMITCCY');
        FOR r IN (
            SELECT LIMITCCY, COUNT(*) nb,
                   MAX(MAXTXNAMT) maxt, MAX(MAXAUTHAMT) maxa
            FROM FBTB_USER
            WHERE MAXTXNAMT > 0 OR MAXAUTHAMT > 0
            GROUP BY LIMITCCY ORDER BY nb DESC
        ) LOOP
            p_kv('  CCY=' || NVL(r.LIMITCCY,'(NULL)') || ' | nb=' || r.nb,
                 'maxTxn=' || r.maxt || ' | maxAuth=' || r.maxa);
        END LOOP;

        p_sub('Coherence FBTB_USER <-> SMTB_USER');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT DISTINCT USERID FROM FBTB_USER
            WHERE USERID NOT IN (SELECT USER_ID FROM SMTB_USER)
        );
        p_kv('  Users FBTB absents de SMTB_USER', TO_CHAR(v_count));

        p_sub('Top 15 agences avec le plus d''utilisateurs FlexBranch');
        FOR r IN (
            SELECT BRANCHCODE, nb FROM (
                SELECT BRANCHCODE, COUNT(*) nb FROM FBTB_USER
                GROUP BY BRANCHCODE ORDER BY nb DESC
            ) WHERE ROWNUM <= 15
        ) LOOP
            p_kv('  BRANCH = ' || NVL(r.BRANCHCODE,'(NULL)'), TO_CHAR(r.nb) || ' user(s)');
        END LOOP;
    END IF;

    -- ---------- FBTM_BRANCH ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM FBTM_BRANCH;
    p_kv('Total agences FlexBranch (FBTM_BRANCH)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Etat EOD par agence (END_OF_INPUT)');
        FOR r IN (SELECT END_OF_INPUT, COUNT(*) nb FROM FBTM_BRANCH
                  GROUP BY END_OF_INPUT ORDER BY nb DESC) LOOP
            p_pct('  END_OF_INPUT = ' || NVL(r.END_OF_INPUT,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Liste des agences');
        FOR r IN (SELECT BRANCH_CODE, BRANCH_NAME, END_OF_INPUT
                  FROM FBTM_BRANCH ORDER BY BRANCH_CODE) LOOP
            p_kv('  ' || RPAD(r.BRANCH_CODE,6), NVL(r.BRANCH_NAME,'-') || ' | EOD=' || NVL(r.END_OF_INPUT,'-'));
        END LOOP;
    END IF;

    -- ---------- FBTM_BRANCH_INFO ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM FBTM_BRANCH_INFO;
    p_kv('Total lignes FBTM_BRANCH_INFO', TO_CHAR(v_total));

    IF v_total > 0 THEN
        p_sub('Detail agences (posting date / LCY / week-end)');
        FOR r IN (SELECT BRANCH_CODE, BRANCH_NAME,
                         BANKCODE, BANKNAME,
                         BRANCH_LCY,
                         TO_CHAR(CURRENTPOSTINGDATE,'DD/MM/YYYY') cpd,
                         TO_CHAR(NEXTPOSTINGDATE,'DD/MM/YYYY') npd,
                         WEEKLYHOLIDAY1, WEEKLYHOLIDAY2, UNTANKINGINTERVAL
                  FROM FBTM_BRANCH_INFO ORDER BY BRANCH_CODE) LOOP
            DBMS_OUTPUT.PUT_LINE('  --- BRANCH=' || r.BRANCH_CODE || ' | ' || NVL(r.BRANCH_NAME,'-')
                || ' (bank ' || NVL(r.BANKCODE,'-') || ') ---');
            p_kv('    LCY / Posting (cur/next)', NVL(r.BRANCH_LCY,'-') || ' | ' || NVL(r.cpd,'-') || ' / ' || NVL(r.npd,'-'));
            p_kv('    Holidays / Untank interval',
                 NVL(r.WEEKLYHOLIDAY1,'-') || ' + ' || NVL(r.WEEKLYHOLIDAY2,'-')
                 || ' | ' || NVL(TO_CHAR(r.UNTANKINGINTERVAL),'-'));
        END LOOP;
    END IF;

    -- ---------- SMTB_USER_TILLS ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_total FROM SMTB_USER_TILLS;
    p_kv('Total affectations caisse (SMTB_USER_TILLS)', TO_CHAR(v_total));

    IF v_total > 0 THEN
        SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_TILLS;
        p_kv('  Utilisateurs distincts avec caisse', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT TILL_ID) INTO v_count FROM SMTB_USER_TILLS;
        p_kv('  Caisses distinctes', TO_CHAR(v_count));
        SELECT COUNT(DISTINCT BRANCH_CODE) INTO v_count FROM SMTB_USER_TILLS;
        p_kv('  Agences distinctes (BRANCH_CODE)', TO_CHAR(v_count));

        p_sub('Repartition par BRANCH_CODE');
        FOR r IN (
            SELECT BRANCH_CODE, COUNT(*) nb FROM SMTB_USER_TILLS
            GROUP BY BRANCH_CODE ORDER BY nb DESC
        ) LOOP
            p_pct('  BRANCH = ' || NVL(r.BRANCH_CODE,'(NULL)'), r.nb, v_total);
        END LOOP;

        p_sub('Caisses partagees par plusieurs utilisateurs (RISK : multi-user/till)');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT TILL_ID, BRANCH_CODE, COUNT(DISTINCT USER_ID) nu
            FROM SMTB_USER_TILLS
            GROUP BY TILL_ID, BRANCH_CODE
            HAVING COUNT(DISTINCT USER_ID) > 1
        );
        p_kv('  Caisses assignees a > 1 user', TO_CHAR(v_count));

        p_sub('Utilisateurs affectes a plusieurs caisses');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT USER_ID FROM SMTB_USER_TILLS
            GROUP BY USER_ID HAVING COUNT(DISTINCT TILL_ID) > 1
        );
        p_kv('  Users avec > 1 caisse', TO_CHAR(v_count));

        p_sub('Echantillon 10 affectations');
        FOR r IN (
            SELECT * FROM (
                SELECT USER_ID, TILL_ID, BRANCH_CODE
                FROM SMTB_USER_TILLS ORDER BY BRANCH_CODE, TILL_ID, USER_ID
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  USER=' || r.USER_ID, 'TILL=' || r.TILL_ID || ' | BRN=' || r.BRANCH_CODE);
        END LOOP;

        p_sub('Coherence SMTB_USER_TILLS <-> SMTB_USER (TILL_ALLOWED=Y)');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT DISTINCT t.USER_ID FROM SMTB_USER_TILLS t
            JOIN SMTB_USER u ON u.USER_ID = t.USER_ID
            WHERE NVL(u.TILL_ALLOWED,'N') <> 'Y'
        );
        p_kv('  Users avec caisse mais TILL_ALLOWED != Y', TO_CHAR(v_count));
    END IF;

    -- =========================================================
    -- A-14. CSTM_FUNCTION_USERDEF_FIELDS — UDF securite
    --        Focus : SMDROLDF (privileges roles), SMDUSRDF (identite users),
    --                STDBRANC (agences), STDACCLS (classes de comptes)
    -- =========================================================
    p_section('A-14. CSTM_FUNCTION_USERDEF_FIELDS — UDF dediees securite/acces');

    SELECT COUNT(*) INTO v_total FROM CSTM_FUNCTION_USERDEF_FIELDS;
    p_kv('Total lignes CSTM_FUNCTION_USERDEF_FIELDS', TO_CHAR(v_total));

    p_sub('Distribution par FUNCTION_ID (focus securite/acces)');
    FOR r IN (
        SELECT FUNCTION_ID, COUNT(*) nb FROM CSTM_FUNCTION_USERDEF_FIELDS
        WHERE FUNCTION_ID IN ('SMDROLDF','SMDUSRDF','STDBRANC','STDACCLS',
                              'SMDCHPWD','SMDCHKDT','SMDAUTH','SMDPARAM',
                              'SMDUSRHL','SMSPARAM','SMDUSRDF','STDCIF','STDCUSAC')
        GROUP BY FUNCTION_ID ORDER BY nb DESC
    ) LOOP
        p_kv('  ' || RPAD(r.FUNCTION_ID,12), TO_CHAR(r.nb) || ' UDF');
    END LOOP;

    -- ---------- SMDROLDF — privileges roles (UDF) ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS WHERE FUNCTION_ID = 'SMDROLDF';
    p_kv('SMDROLDF — lignes', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_sub('SMDROLDF : distribution FIELD_VAL_1 (PRIVILEGE_ACCLASS_LIST)');
        FOR r IN (
            SELECT FIELD_VAL_1, COUNT(*) nb FROM (
                SELECT FIELD_VAL_1, COUNT(*) nb
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'SMDROLDF'
                GROUP BY FIELD_VAL_1 ORDER BY COUNT(*) DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  PRIV_ACCLASS = ' || NVL(r.FIELD_VAL_1,'(NULL)'), TO_CHAR(r.nb));
        END LOOP;

        p_sub('SMDROLDF : distribution FIELD_VAL_2 (PRIVILEGE_ROLE)');
        FOR r IN (
            SELECT FIELD_VAL_2, COUNT(*) nb FROM (
                SELECT FIELD_VAL_2, COUNT(*) nb
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'SMDROLDF'
                GROUP BY FIELD_VAL_2 ORDER BY COUNT(*) DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  PRIV_ROLE = ' || NVL(r.FIELD_VAL_2,'(NULL)'), TO_CHAR(r.nb));
        END LOOP;

        p_sub('SMDROLDF : echantillon 10 entrees');
        FOR r IN (
            SELECT * FROM (
                SELECT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) role_id,
                       FIELD_VAL_1 priv_acclass, FIELD_VAL_2 priv_role
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'SMDROLDF'
                ORDER BY REC_KEY
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  ROLE=' || NVL(r.role_id,'(NULL)'),
                 'PRIV_ACCLASS=' || NVL(r.priv_acclass,'-')
                 || ' | PRIV_ROLE=' || NVL(r.priv_role,'-'));
        END LOOP;

        p_sub('SMDROLDF : coherence avec SMTB_ROLE_MASTER');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT DISTINCT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) AS role_id
            FROM CSTM_FUNCTION_USERDEF_FIELDS
            WHERE FUNCTION_ID = 'SMDROLDF'
        ) WHERE role_id NOT IN (SELECT ROLE_ID FROM SMTB_ROLE_MASTER);
        p_kv('  Roles UDF absents de SMTB_ROLE_MASTER', TO_CHAR(v_count));
    END IF;

    -- ---------- SMDUSRDF — identite user (UDF) ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS WHERE FUNCTION_ID = 'SMDUSRDF';
    p_kv('SMDUSRDF — lignes', TO_CHAR(v_count));

    IF v_count > 0 THEN
        SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS
            WHERE FUNCTION_ID = 'SMDUSRDF' AND (FIELD_VAL_1 IS NULL OR FIELD_VAL_1 = ' ');
        p_kv('  SMDUSRDF : sans email (FIELD_VAL_1)', TO_CHAR(v_count));
        SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS
            WHERE FUNCTION_ID = 'SMDUSRDF' AND (FIELD_VAL_2 IS NULL OR FIELD_VAL_2 = ' ');
        p_kv('  SMDUSRDF : sans staff_id (FIELD_VAL_2)', TO_CHAR(v_count));

        p_sub('SMDUSRDF : echantillon 10 entrees');
        FOR r IN (
            SELECT * FROM (
                SELECT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) user_id,
                       FIELD_VAL_1 email, FIELD_VAL_2 staff_id
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'SMDUSRDF'
                ORDER BY REC_KEY
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  USER=' || NVL(r.user_id,'(NULL)'),
                 'EMAIL=' || NVL(r.email,'-') || ' | STAFF=' || NVL(r.staff_id,'-'));
        END LOOP;

        p_sub('SMDUSRDF : coherence avec SMTB_USER');
        SELECT COUNT(*) INTO v_count FROM (
            SELECT DISTINCT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) AS user_id
            FROM CSTM_FUNCTION_USERDEF_FIELDS
            WHERE FUNCTION_ID = 'SMDUSRDF'
        ) WHERE user_id NOT IN (SELECT USER_ID FROM SMTB_USER);
        p_kv('  Users UDF absents de SMTB_USER', TO_CHAR(v_count));
    END IF;

    -- ---------- STDBRANC — agences (UDF) ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS WHERE FUNCTION_ID = 'STDBRANC';
    p_kv('STDBRANC — lignes', TO_CHAR(v_count));

    IF v_count > 0 THEN
        SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS
            WHERE FUNCTION_ID = 'STDBRANC' AND (FIELD_VAL_1 IS NULL OR FIELD_VAL_1 = ' ');
        p_kv('  STDBRANC sans telephone agence (FIELD_VAL_1)', TO_CHAR(v_count));

        p_sub('STDBRANC : echantillon 10 entrees (code agence / telephone)');
        FOR r IN (
            SELECT * FROM (
                SELECT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) branch_code,
                       FIELD_VAL_1 phone
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'STDBRANC'
                ORDER BY REC_KEY
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  BRANCH=' || NVL(r.branch_code,'(NULL)'), 'TEL=' || NVL(r.phone,'-'));
        END LOOP;
    END IF;

    -- ---------- STDACCLS — classes de comptes / privilege (UDF) ----------
    DBMS_OUTPUT.PUT_LINE('');
    SELECT COUNT(*) INTO v_count FROM CSTM_FUNCTION_USERDEF_FIELDS WHERE FUNCTION_ID = 'STDACCLS';
    p_kv('STDACCLS — lignes', TO_CHAR(v_count));

    IF v_count > 0 THEN
        p_sub('STDACCLS : distribution FIELD_VAL_1 (privilege)');
        FOR r IN (
            SELECT FIELD_VAL_1, COUNT(*) nb FROM (
                SELECT FIELD_VAL_1, COUNT(*) nb FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'STDACCLS'
                GROUP BY FIELD_VAL_1 ORDER BY COUNT(*) DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  PRIV = ' || NVL(r.FIELD_VAL_1,'(NULL)'), TO_CHAR(r.nb));
        END LOOP;

        p_sub('STDACCLS : echantillon 10 entrees');
        FOR r IN (
            SELECT * FROM (
                SELECT SUBSTR(REC_KEY, 1, INSTR(REC_KEY,'~',1,1)-1) acclass,
                       FIELD_VAL_1 priv
                FROM CSTM_FUNCTION_USERDEF_FIELDS
                WHERE FUNCTION_ID = 'STDACCLS' ORDER BY REC_KEY
            ) WHERE ROWNUM <= 10
        ) LOOP
            p_kv('  ACCLASS=' || NVL(r.acclass,'(NULL)'), 'PRIVILEGE=' || NVL(r.priv,'-'));
        END LOOP;
    END IF;

    -- ---------- Fonctions UDF supplementaires (si presentes) ----------
    DBMS_OUTPUT.PUT_LINE('');
    p_sub('Autres FUNCTION_ID UDF potentiellement lies a la securite');
    FOR f IN (
        SELECT func FROM (
            SELECT 'SMDCHPWD' func FROM DUAL UNION ALL
            SELECT 'SMDCHKDT'       FROM DUAL UNION ALL
            SELECT 'SMDAUTH'        FROM DUAL UNION ALL
            SELECT 'SMDPARAM'       FROM DUAL UNION ALL
            SELECT 'SMDUSRHL'       FROM DUAL UNION ALL
            SELECT 'SMSPARAM'       FROM DUAL UNION ALL
            SELECT 'STDSTCHN'       FROM DUAL
        )
    ) LOOP
        EXECUTE IMMEDIATE
            'SELECT COUNT(*) FROM CSTM_FUNCTION_USERDEF_FIELDS WHERE FUNCTION_ID = :1'
            INTO v_count USING f.func;
        p_kv('  ' || RPAD(f.func,10), TO_CHAR(v_count) || ' UDF');
    END LOOP;

    -- =========================================================
    -- A-15. COHERENCE INTER-TABLES & SEPARATION DES TACHES (SoD)
    --        — Anomalies, orphelins, doublons, conflits d'acces
    -- =========================================================
    p_section('A-15. COHERENCE, ANOMALIES, SEPARATION DES TACHES (SoD)');

    -- ---- Integrite user ----
    p_sub('A-15.1 Integrite des comptes SMTB_USER');
    SELECT COUNT(*) INTO v_total FROM SMTB_USER;

    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_ID IS NULL OR USER_ID = ' ';
    p_pct('  USER_ID NULL/blanc', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_NAME IS NULL OR USER_NAME = ' ';
    p_pct('  USER_NAME NULL/blanc', v_count, v_total);
    SELECT COUNT(*) INTO v_count FROM (
        SELECT USER_ID, COUNT(*) nb FROM SMTB_USER
        GROUP BY USER_ID HAVING COUNT(*) > 1
    );
    p_kv('  Doublons USER_ID', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM (
        SELECT UPPER(USER_NAME) nm, COUNT(*) nb FROM SMTB_USER
        WHERE USER_NAME IS NOT NULL
        GROUP BY UPPER(USER_NAME) HAVING COUNT(*) > 1
    );
    p_kv('  Doublons USER_NAME (nom homonyme, sans casse)', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE CUSTOMER_NO IS NOT NULL AND CUSTOMER_NO <> ' '
          AND CUSTOMER_NO NOT IN (SELECT CUSTOMER_NO FROM STTM_CUSTOMER);
    p_kv('  CUSTOMER_NO renseigne mais absent de STTM_CUSTOMER', TO_CHAR(v_count));

    -- ---- Incoherence statut ----
    p_sub('A-15.2 Statut incoherent');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE USER_STATUS = 'E' AND (RECORD_STAT = 'C' OR AUTH_STAT = 'U');
    p_kv('  ENABLED mais Record=Closed ou Auth=Unauth', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE USER_STATUS = 'E' AND END_DATE IS NOT NULL AND END_DATE < SYSDATE;
    p_kv('  ENABLED et END_DATE depassee', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE USER_STATUS = 'D' AND AUTH_STAT = 'U';
    p_kv('  DISABLED et Unauthorised (suspect)', TO_CHAR(v_count));

    -- ---- Users actifs mais dormants ----
    p_sub('A-15.3 Users enabled ET dormants > 90 jours (croisement)');
    SELECT COUNT(*) INTO v_count
    FROM SMTB_USER u
    LEFT JOIN SMTB_USERLOG_DETAILS l ON l.USER_ID = u.USER_ID
    WHERE u.USER_STATUS = 'E'
      AND (l.LAST_SIGNED_ON IS NULL OR l.LAST_SIGNED_ON < SYSDATE - 90);
    p_kv('  Users ENABLED dormants > 90 j', TO_CHAR(v_count));

    SELECT COUNT(*) INTO v_count
    FROM SMTB_USER u
    LEFT JOIN SMTB_USERLOG_DETAILS l ON l.USER_ID = u.USER_ID
    WHERE u.USER_STATUS = 'E' AND u.AUTH_STAT = 'A'
      AND (l.LAST_SIGNED_ON IS NULL OR l.LAST_SIGNED_ON < SYSDATE - 180);
    p_kv('  Users ENABLED/Auth et dormants > 180 j', TO_CHAR(v_count));

    p_sub('A-15.4 Users jamais connectes mais disposant de roles');
    SELECT COUNT(*) INTO v_count
    FROM SMTB_USER u
    LEFT JOIN SMTB_USERLOG_DETAILS l ON l.USER_ID = u.USER_ID
    WHERE l.LAST_SIGNED_ON IS NULL
      AND EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.USER_ID = u.USER_ID);
    p_kv('  Jamais connectes MAIS avec roles actifs', TO_CHAR(v_count));

    -- ---- Segregation of duties (SoD) ----
    p_sub('A-15.5 SoD : MAKER = CHECKER (auto-validation)');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_kv('  SMTB_USER : MAKER=CHECKER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER
        WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_kv('  SMTB_ROLE_MASTER : MAKER=CHECKER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_FUNC_LIMIT_CUSTOM
        WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_kv('  SMTB_ROLE_FUNC_LIMIT_CUSTOM : MAKER=CHECKER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_PARAMETERS
        WHERE MAKER_ID = CHECKER_ID AND MAKER_ID IS NOT NULL;
    p_kv('  SMTB_PARAMETERS : MAKER=CHECKER', TO_CHAR(v_count));

    p_sub('A-15.6 SoD : action SMTB_SMS_ACTION_LOG — auto-autorisation recente (180 j)');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_ACTION_LOG a
    WHERE a.REQ_TIME >= SYSDATE - 180
      AND UPPER(a.ACTION) IN ('AUTH','AUTHORIZE')
      AND EXISTS (
          SELECT 1 FROM SMTB_SMS_ACTION_LOG b
          WHERE b.PKVALS = a.PKVALS
            AND UPPER(b.ACTION) IN ('NEW','MODIFY')
            AND b.SEQUENCE_NO = a.SEQUENCE_NO
      );
    p_kv('  Paires NEW/MODIFY puis AUTH meme SEQUENCE_NO sur 180 j', TO_CHAR(v_count));

    -- ---- Privileges excessifs ----
    p_sub('A-15.7 Privileges excessifs potentiels');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE BRANCHES_ALLOWED = 'Y' AND ACCLASS_ALLOWED = 'Y'
          AND PRODUCTS_ALLOWED = 'Y' AND GL_ALLOWED = 'Y';
    p_kv('  Users avec ALL allowed (branches + acclass + products + GL)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM (
        SELECT USER_ID FROM (
            SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_ROLE GROUP BY USER_ID
            UNION ALL
            SELECT USER_ID, COUNT(*) nb FROM SMTB_USER_CENTRAL_ROLES GROUP BY USER_ID
        ) GROUP BY USER_ID HAVING SUM(nb) >= 10
    );
    p_kv('  Users avec >= 10 roles cumules', TO_CHAR(v_count));

    p_sub('A-15.8 Roles a perimetre universel (toutes agences + classes)');
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER
        WHERE BRANCHES_ALLOWED = 'Y' AND ACCCLASS_ALLOWED = 'Y';
    p_kv('  Roles Branches=Y ET Acclass=Y', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER WHERE BRANCH_VLT_ROLE = 'Y';
    p_kv('  Roles coffre-fort (BRANCH_VLT_ROLE=Y)', TO_CHAR(v_count));

    -- ---- LDAP ----
    p_sub('A-15.9 Coherence LDAP / mot de passe local');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE LDAP_USER = 'Y' AND USER_PASSWORD IS NOT NULL AND USER_PASSWORD <> ' ';
    p_kv('  LDAP=Y mais USER_PASSWORD stocke localement', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER
        WHERE (LDAP_USER IS NULL OR LDAP_USER <> 'Y')
          AND (USER_PASSWORD IS NULL OR USER_PASSWORD = ' ');
    p_kv('  Local (non LDAP) mais sans USER_PASSWORD', TO_CHAR(v_count));

    -- ---- Password policy ----
    p_sub('A-15.10 Politique MDP : utilisateurs non conformes');
    FOR p IN (SELECT * FROM SMTB_PARAMETERS WHERE ROWNUM = 1) LOOP
        IF p.FREQ_PWD_CHG IS NOT NULL AND p.FREQ_PWD_CHG > 0 THEN
            SELECT COUNT(*) INTO v_count FROM SMTB_USER
                WHERE PWD_CHANGED_ON IS NOT NULL
                  AND PWD_CHANGED_ON < SYSDATE - p.FREQ_PWD_CHG
                  AND USER_STATUS = 'E';
            p_kv('  Users ENABLED depassant FREQ_PWD_CHG (' || p.FREQ_PWD_CHG || 'j)',
                 TO_CHAR(v_count));
        END IF;
        IF p.DORMANCY_DAYS IS NOT NULL AND p.DORMANCY_DAYS > 0 THEN
            SELECT COUNT(*) INTO v_count
            FROM SMTB_USER u
            LEFT JOIN SMTB_USERLOG_DETAILS l ON l.USER_ID = u.USER_ID
            WHERE u.USER_STATUS = 'E'
              AND (l.LAST_SIGNED_ON IS NULL OR l.LAST_SIGNED_ON < SYSDATE - p.DORMANCY_DAYS);
            p_kv('  Users ENABLED depassant DORMANCY_DAYS (' || p.DORMANCY_DAYS || 'j)',
                 TO_CHAR(v_count));
        END IF;
    END LOOP;

    -- ---- Orphelins ----
    p_sub('A-15.11 Orphelins / fantomes');
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE ROLE_ID NOT IN (SELECT ROLE_ID FROM SMTB_ROLE_MASTER);
    p_kv('  SMTB_ROLE_DETAIL.ROLE_ID absent de SMTB_ROLE_MASTER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_ROLE
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER);
    p_kv('  SMTB_USER_ROLE.USER_ID absent de SMTB_USER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_ROLE
        WHERE ROLE_ID NOT IN (SELECT ROLE_ID FROM SMTB_ROLE_MASTER);
    p_kv('  SMTB_USER_ROLE.ROLE_ID absent de SMTB_ROLE_MASTER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_CENTRAL_ROLES
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER);
    p_kv('  SMTB_USER_CENTRAL_ROLES.USER_ID absent de SMTB_USER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_TILLS
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER);
    p_kv('  SMTB_USER_TILLS.USER_ID absent de SMTB_USER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_PASSWORD_HISTORY
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER);
    p_kv('  SMTB_PASSWORD_HISTORY.USER_ID absent de SMTB_USER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USERLOG_DETAILS
        WHERE USER_ID NOT IN (SELECT USER_ID FROM SMTB_USER);
    p_kv('  SMTB_USERLOG_DETAILS.USER_ID absent de SMTB_USER', TO_CHAR(v_count));

    -- ---- Cumul users actifs vs volumetrie ----
    p_sub('A-15.12 Profil global des acces actifs');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_STATUS = 'E' AND AUTH_STAT = 'A';
    p_kv('  Users ENABLED + Authorised', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_USER_ROLE WHERE AUTH_STAT = 'A';
    p_kv('  Users avec au moins 1 role AUTH_STAT=A', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER u
        WHERE u.USER_STATUS = 'E' AND u.AUTH_STAT = 'A'
          AND EXISTS (SELECT 1 FROM SMTB_USER_ROLE r WHERE r.USER_ID = u.USER_ID AND r.AUTH_STAT = 'A');
    p_kv('  Users actifs ET role attribue actif', TO_CHAR(v_count));

    -- ---- Tills multi-user ----
    p_sub('A-15.13 Risque partage caisse / agence');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT TILL_ID, BRANCH_CODE FROM SMTB_USER_TILLS
        GROUP BY TILL_ID, BRANCH_CODE HAVING COUNT(DISTINCT USER_ID) > 1
    );
    p_kv('  Caisses (TILL_ID) partagees par > 1 user', TO_CHAR(v_count));

    -- ---- Session anormale ----
    p_sub('A-15.14 Sessions anormales SMTB_SMS_LOG (30 j)');
    SELECT COUNT(*) INTO v_count FROM SMTB_SMS_LOG
        WHERE SYSTEM_START_TIME >= SYSDATE - 30 AND EXIT_FLAG <> 0;
    p_kv('  Events EXIT_FLAG != 0 sur 30 j', TO_CHAR(v_count));
    SELECT COUNT(DISTINCT USER_ID) INTO v_count FROM SMTB_SMS_LOG
        WHERE SYSTEM_START_TIME >= SYSDATE - 30 AND EXIT_FLAG <> 0;
    p_kv('  Users distincts impactes', TO_CHAR(v_count));

    p_sub('A-15.15 Recap executif');
    SELECT COUNT(*) INTO v_count FROM SMTB_USER;
    p_kv('  Nombre total de comptes', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER WHERE USER_STATUS = 'E';
    p_kv('  Dont ENABLED', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_MASTER;
    p_kv('  Nombre total de roles', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_ROLE;
    p_kv('  Affectations user-role (locales)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_USER_CENTRAL_ROLES;
    p_kv('  Affectations user-role (centralisees)', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_DETAIL;
    p_kv('  Lignes privileges role/fonction', TO_CHAR(v_count));

    -- =========================================================
    -- A-17. CARTOGRAPHIE DES ADMINISTRATEURS
    --        — Qui a acces aux fonctions de securite (SM*) ?
    -- =========================================================
    p_section('A-17. CARTOGRAPHIE ADMINISTRATEURS — acces aux fonctions SM* / parametrage');

    p_sub('A-17.1 Volume de privileges admin par fonction cible');
    FOR f IN (
        SELECT func, label FROM (
            SELECT 'SMDUSRDF' func, 'Creation/modif utilisateurs' label, 1 ord FROM DUAL UNION ALL
            SELECT 'SMDROLDF',       'Creation/modif roles',               2 FROM DUAL UNION ALL
            SELECT 'SMDCHPWD',       'Reset mot de passe',                 3 FROM DUAL UNION ALL
            SELECT 'SMDCHKDT',       'Autorisation creation user',         4 FROM DUAL UNION ALL
            SELECT 'SMDPARAM',       'Parametres globaux SMS',             5 FROM DUAL UNION ALL
            SELECT 'SMSPARAM',       'Parametres SMS bis',                 6 FROM DUAL UNION ALL
            SELECT 'SMDUSRHL',       'Historique utilisateurs',            7 FROM DUAL UNION ALL
            SELECT 'SMDCLRUS',       'Clear users',                        8 FROM DUAL UNION ALL
            SELECT 'SMDAUTH',        'Autorisation generique',             9 FROM DUAL UNION ALL
            SELECT 'CSDUDFMT',       'UDF maintenance',                   10 FROM DUAL UNION ALL
            SELECT 'CSDXTCTL',       'Controle des executions',           11 FROM DUAL UNION ALL
            SELECT 'CSDXTFSR',       'Fonction reserve',                  12 FROM DUAL UNION ALL
            SELECT 'STDEODST',       'Statut End-of-day',                 13 FROM DUAL UNION ALL
            SELECT 'EIDMANOP',       'Operations manuelles EOD',          14 FROM DUAL ORDER BY ord
        )
    ) LOOP
        SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL
            WHERE UPPER(ROLE_FUNCTION) = f.func OR UPPER(RAD_FUNCTION_ID) = f.func;
        SELECT COUNT(DISTINCT ur.USER_ID) INTO v_count2 FROM SMTB_USER_ROLE ur
            JOIN SMTB_ROLE_DETAIL rd ON rd.ROLE_ID = ur.ROLE_ID
            WHERE UPPER(rd.ROLE_FUNCTION) = f.func OR UPPER(rd.RAD_FUNCTION_ID) = f.func;
        p_kv('  ' || RPAD(f.func,10) || ' (' || f.label || ')',
             TO_CHAR(v_count) || ' role(s) / ' || TO_CHAR(v_count2) || ' user(s)');
    END LOOP;

    p_sub('A-17.2 Top 15 utilisateurs "superadmin" (acces >=3 fonctions SM*)');
    FOR r IN (
        SELECT * FROM (
            SELECT ur.USER_ID, COUNT(DISTINCT rd.ROLE_FUNCTION) nb_func
            FROM SMTB_USER_ROLE ur
            JOIN SMTB_ROLE_DETAIL rd ON rd.ROLE_ID = ur.ROLE_ID
            WHERE rd.ROLE_FUNCTION LIKE 'SM%' OR rd.RAD_FUNCTION_ID LIKE 'SM%'
            GROUP BY ur.USER_ID
            HAVING COUNT(DISTINCT rd.ROLE_FUNCTION) >= 3
            ORDER BY nb_func DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  USER=' || r.USER_ID, TO_CHAR(r.nb_func) || ' fonction(s) SM* distinctes');
    END LOOP;

    p_sub('A-17.3 Top 15 roles "admin" (nombre de fonctions SM* couvertes)');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_ID, COUNT(DISTINCT ROLE_FUNCTION) nb
            FROM SMTB_ROLE_DETAIL
            WHERE ROLE_FUNCTION LIKE 'SM%' OR RAD_FUNCTION_ID LIKE 'SM%'
            GROUP BY ROLE_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ROLE=' || r.ROLE_ID, TO_CHAR(r.nb) || ' fonction(s) SM*');
    END LOOP;

    p_sub('A-17.4 Admins historiques : MAKER_ID de SMTB_USER (qui a cree les comptes)');
    SELECT COUNT(DISTINCT MAKER_ID) INTO v_count FROM SMTB_USER WHERE MAKER_ID IS NOT NULL;
    p_kv('  Nombre de createurs distincts', TO_CHAR(v_count));
    FOR r IN (
        SELECT * FROM (
            SELECT MAKER_ID, COUNT(*) nb,
                   MIN(MAKER_DT_STAMP) premiere,
                   MAX(MAKER_DT_STAMP) derniere
            FROM SMTB_USER
            WHERE MAKER_ID IS NOT NULL
            GROUP BY MAKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  MAKER=' || r.MAKER_ID || ' | ' || r.nb || ' comptes',
             TO_CHAR(r.premiere,'DD/MM/YYYY') || ' -> ' || TO_CHAR(r.derniere,'DD/MM/YYYY'));
    END LOOP;

    p_sub('A-17.5 Admins historiques : CHECKER_ID de SMTB_USER');
    FOR r IN (
        SELECT * FROM (
            SELECT CHECKER_ID, COUNT(*) nb,
                   MAX(CHECKER_DT_STAMP) derniere
            FROM SMTB_USER
            WHERE CHECKER_ID IS NOT NULL
            GROUP BY CHECKER_ID ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  CHECKER=' || r.CHECKER_ID || ' | ' || r.nb || ' autorisations',
             'derniere=' || TO_CHAR(r.derniere,'DD/MM/YYYY'));
    END LOOP;

    p_sub('A-17.6 MAKER_ID / CHECKER_ID absents de SMTB_USER (traces orphelines)');
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT MAKER_ID FROM SMTB_USER WHERE MAKER_ID IS NOT NULL
        AND MAKER_ID NOT IN (SELECT USER_ID FROM SMTB_USER)
    );
    p_kv('  MAKER_ID fantomes dans SMTB_USER', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM (
        SELECT DISTINCT CHECKER_ID FROM SMTB_USER WHERE CHECKER_ID IS NOT NULL
        AND CHECKER_ID NOT IN (SELECT USER_ID FROM SMTB_USER)
    );
    p_kv('  CHECKER_ID fantomes dans SMTB_USER', TO_CHAR(v_count));

    p_sub('A-17.7 Cumul d''activite admin recente (SMTB_SMS_ACTION_LOG 90 j)');
    FOR r IN (
        SELECT * FROM (
            SELECT SUBSTR(PKVALS, 1, 20) user_cible, COUNT(*) nb
            FROM SMTB_SMS_ACTION_LOG
            WHERE REQ_TIME >= SYSDATE - 90
              AND UPPER(ACTION) IN ('NEW','MODIFY','DELETE','AUTH','AUTHORIZE','CLOSE','REOPEN','UNLOCK')
              AND PKVALS IS NOT NULL
            GROUP BY SUBSTR(PKVALS, 1, 20) ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  PK_prefix=' || NVL(r.user_cible,'(NULL)'), TO_CHAR(r.nb) || ' action(s) admin / 90 j');
    END LOOP;

    -- =========================================================
    -- A-18. DECODAGE CONTROL_STRING
    --        — Matrice fine des droits N/C/D/A/Q/M/U/P/R/L/H/X/I/E/B/T
    --          (Convention Flexcube : chaque position = un droit unitaire)
    -- =========================================================
    p_section('A-18. DECODAGE CONTROL_STRING — matrice fine des droits unitaires');

    SELECT COUNT(*) INTO v_total FROM SMTB_ROLE_DETAIL;
    p_kv('Total lignes SMTB_ROLE_DETAIL analysees', TO_CHAR(v_total));

    p_sub('A-18.1 Longueur des CONTROL_STRING rencontrees');
    FOR r IN (
        SELECT LENGTH(CONTROL_STRING) ln, COUNT(*) nb
        FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
        GROUP BY LENGTH(CONTROL_STRING)
        ORDER BY ln
    ) LOOP
        p_kv('  Longueur = ' || NVL(TO_CHAR(r.ln),'NULL'), TO_CHAR(r.nb));
    END LOOP;

    p_sub('A-18.2 Comptage des droits Y par position (1->16)');
    FOR p IN (SELECT LEVEL pos FROM DUAL CONNECT BY LEVEL <= 16) LOOP
        EXECUTE IMMEDIATE
            'SELECT COUNT(*) FROM SMTB_ROLE_DETAIL '
            || 'WHERE CONTROL_STRING IS NOT NULL '
            || 'AND LENGTH(CONTROL_STRING) >= :1 '
            || 'AND SUBSTR(CONTROL_STRING, :2, 1) = ''Y'''
            INTO v_count USING p.pos, p.pos;
        p_pct('  Position ' || LPAD(TO_CHAR(p.pos),2) || ' (CONTROL_' || p.pos || ')',
              v_count, v_total);
    END LOOP;

    p_sub('A-18.3 Mappage conventionnel des positions (observation)');
    DBMS_OUTPUT.PUT_LINE('  Position 1  = NEW (creation)');
    DBMS_OUTPUT.PUT_LINE('  Position 2  = COPY');
    DBMS_OUTPUT.PUT_LINE('  Position 3  = DELETE');
    DBMS_OUTPUT.PUT_LINE('  Position 4  = CLOSE');
    DBMS_OUTPUT.PUT_LINE('  Position 5  = UNLOCK / AMEND');
    DBMS_OUTPUT.PUT_LINE('  Position 6  = REOPEN');
    DBMS_OUTPUT.PUT_LINE('  Position 7  = PRINT');
    DBMS_OUTPUT.PUT_LINE('  Position 8  = AUTHORIZE');
    DBMS_OUTPUT.PUT_LINE('  Position 9  = QUERY');
    DBMS_OUTPUT.PUT_LINE('  Position 10 = REVERSE / ROLLOVER');
    DBMS_OUTPUT.PUT_LINE('  Position 11 = LIQUIDATE / HOLD');
    DBMS_OUTPUT.PUT_LINE('  Position 12 = EXECUTE');
    DBMS_OUTPUT.PUT_LINE('  Position 13 = REJECT / CONFIRM');
    DBMS_OUTPUT.PUT_LINE('  Position 14 = UPLOAD / IMPORT');
    DBMS_OUTPUT.PUT_LINE('  Position 15 = EXPORT');
    DBMS_OUTPUT.PUT_LINE('  Position 16 = AUDIT / HISTORY');

    p_sub('A-18.4 Roles avec droit NEW + AUTH simultanes (SoD : auto-autorisation possible)');
    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
          AND LENGTH(CONTROL_STRING) >= 8
          AND SUBSTR(CONTROL_STRING,1,1) = 'Y'
          AND SUBSTR(CONTROL_STRING,8,1) = 'Y';
    p_kv('  Roles distincts avec NEW + AUTH', TO_CHAR(v_count));
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
          AND LENGTH(CONTROL_STRING) >= 8
          AND SUBSTR(CONTROL_STRING,1,1) = 'Y'
          AND SUBSTR(CONTROL_STRING,8,1) = 'Y';
    p_pct('  Lignes role/fonction avec NEW + AUTH', v_count, v_total);

    p_sub('A-18.5 Roles avec droit DELETE + AUTH (suppression auto-autorisee)');
    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
          AND LENGTH(CONTROL_STRING) >= 8
          AND SUBSTR(CONTROL_STRING,3,1) = 'Y'
          AND SUBSTR(CONTROL_STRING,8,1) = 'Y';
    p_kv('  Roles distincts DELETE + AUTH', TO_CHAR(v_count));

    p_sub('A-18.6 Roles avec droits FULL (>= 12 positions a Y)');
    SELECT COUNT(DISTINCT ROLE_ID) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
          AND (LENGTH(REPLACE(CONTROL_STRING,'Y','')) <= LENGTH(CONTROL_STRING) - 12);
    p_kv('  Roles distincts avec >= 12 droits actifs', TO_CHAR(v_count));

    p_sub('A-18.7 Top 15 roles/fonctions les plus "permissifs" (plus de Y dans CONTROL_STRING)');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_ID, ROLE_FUNCTION,
                   (LENGTH(CONTROL_STRING) - LENGTH(REPLACE(CONTROL_STRING,'Y',''))) nb_y,
                   CONTROL_STRING
            FROM SMTB_ROLE_DETAIL
            WHERE CONTROL_STRING IS NOT NULL
            ORDER BY (LENGTH(CONTROL_STRING) - LENGTH(REPLACE(CONTROL_STRING,'Y',''))) DESC
        ) WHERE ROWNUM <= 15
    ) LOOP
        p_kv('  ROLE=' || RPAD(r.ROLE_ID,15) || ' FUNC=' || RPAD(r.ROLE_FUNCTION,12),
             TO_CHAR(r.nb_y) || ' droits | CTRL=' || SUBSTR(r.CONTROL_STRING,1,20));
    END LOOP;

    p_sub('A-18.8 Roles/fonctions en QUERY seule (lecture pure)');
    SELECT COUNT(*) INTO v_count FROM SMTB_ROLE_DETAIL
        WHERE CONTROL_STRING IS NOT NULL
          AND LENGTH(CONTROL_STRING) >= 9
          AND SUBSTR(CONTROL_STRING,9,1) = 'Y'
          AND SUBSTR(CONTROL_STRING,1,1) = 'N'
          AND SUBSTR(CONTROL_STRING,3,1) = 'N'
          AND SUBSTR(CONTROL_STRING,8,1) = 'N';
    p_pct('  Lignes QUERY seule (saine separation)', v_count, v_total);

    p_sub('A-18.9 Matrice N+AUTH par fonction sensible (Top 10 fonctions concernees)');
    FOR r IN (
        SELECT * FROM (
            SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
            FROM SMTB_ROLE_DETAIL
            WHERE CONTROL_STRING IS NOT NULL
              AND LENGTH(CONTROL_STRING) >= 8
              AND SUBSTR(CONTROL_STRING,1,1) = 'Y'
              AND SUBSTR(CONTROL_STRING,8,1) = 'Y'
            GROUP BY ROLE_FUNCTION ORDER BY nb DESC
        ) WHERE ROWNUM <= 10
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s) NEW+AUTH');
    END LOOP;

    -- =========================================================
    -- A-19. ACCES AUX DONNEES SENSIBLES (CLIENT / KYC / COMPTES / AML)
    -- =========================================================
    p_section('A-19. ACCES AUX DONNEES SENSIBLES — perimetre CIF/KYC/Comptes/AML');

    p_sub('A-19.1 Roles ayant acces aux fonctions CIF (STDCIF, STDCUMNT, STDCUSAC)');
    FOR r IN (
        SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
        FROM SMTB_ROLE_DETAIL
        WHERE ROLE_FUNCTION IN ('STDCIF','STDCUMNT','STDCUSAC','STDCIFAD','STDCIFMT')
        GROUP BY ROLE_FUNCTION
        ORDER BY nb DESC
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('A-19.2 Roles ayant acces aux fonctions KYC (STDKYCMN, STDKYCRT, STDKYCCR)');
    FOR r IN (
        SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
        FROM SMTB_ROLE_DETAIL
        WHERE ROLE_FUNCTION LIKE 'ST%KYC%'
           OR ROLE_FUNCTION LIKE '%KYC%'
           OR ROLE_FUNCTION LIKE '%PEP%'
        GROUP BY ROLE_FUNCTION
        ORDER BY nb DESC
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('A-19.3 Roles ayant acces aux fonctions comptes (STDCUSAC, STDACCLS, STDACBRP)');
    FOR r IN (
        SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
        FROM SMTB_ROLE_DETAIL
        WHERE ROLE_FUNCTION LIKE 'STDAC%'
           OR ROLE_FUNCTION LIKE 'STDCUSAC%'
           OR ROLE_FUNCTION LIKE 'STDACCLS%'
        GROUP BY ROLE_FUNCTION
        ORDER BY nb DESC
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('A-19.4 Fonctions STATUT COMPTE / GEL / DORMANCE (dormancy, freeze, block, close)');
    FOR r IN (
        SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
        FROM SMTB_ROLE_DETAIL
        WHERE UPPER(ROLE_FUNCTION) LIKE '%DORM%'
           OR UPPER(ROLE_FUNCTION) LIKE '%FRZ%'
           OR UPPER(ROLE_FUNCTION) LIKE '%BLOCK%'
           OR UPPER(ROLE_FUNCTION) LIKE '%CLOS%'
           OR UPPER(ROLE_FUNCTION) LIKE '%FREEZ%'
        GROUP BY ROLE_FUNCTION
        ORDER BY nb DESC
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('A-19.5 Fonctions AML / fraude / ecritures manuelles (AM*, FP*, DE*, XP*)');
    FOR r IN (
        SELECT ROLE_FUNCTION, COUNT(DISTINCT ROLE_ID) nb
        FROM SMTB_ROLE_DETAIL
        WHERE SUBSTR(ROLE_FUNCTION,1,2) IN ('AM','AL','FP','DE','XP','IB','JE')
           OR UPPER(ROLE_FUNCTION) LIKE '%AML%'
           OR UPPER(ROLE_FUNCTION) LIKE '%FRAUD%'
           OR UPPER(ROLE_FUNCTION) LIKE '%JRNL%'
        GROUP BY ROLE_FUNCTION
        ORDER BY nb DESC
    ) LOOP
        p_kv('  FUNC=' || r.ROLE_FUNCTION, TO_CHAR(r.nb) || ' role(s)');
    END LOOP;

    p_sub('A-19.6 Top 20 utilisateurs avec acces combines CIF + KYC + Compte (risque consolide)');
    FOR r IN (
        SELECT * FROM (
            SELECT ur.USER_ID,
                   COUNT(DISTINCT rd.ROLE_FUNCTION) nb_func_sens
            FROM SMTB_USER_ROLE ur, SMTB_ROLE_DETAIL rd
            WHERE ur.ROLE_ID = rd.ROLE_ID
              AND (rd.ROLE_FUNCTION LIKE 'STDCIF%'
                OR rd.ROLE_FUNCTION LIKE 'STDKYC%'
                OR rd.ROLE_FUNCTION LIKE 'STDCUSAC%'
                OR rd.ROLE_FUNCTION LIKE 'STDACCLS%')
            GROUP BY ur.USER_ID
            ORDER BY nb_func_sens DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p_kv('  USER=' || r.USER_ID, TO_CHAR(r.nb_func_sens) || ' fonctions sensibles');
    END LOOP;

    p_sub('A-19.7 Makers/Checkers historiques de STTM_CUSTOMER (creation/modif CIF)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAKER_ID, COUNT(*) nb
            FROM STTM_CUSTOMER
            WHERE MAKER_ID IS NOT NULL
            GROUP BY MAKER_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 15) LOOP
            p_kv('  MAKER_CIF=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' CIF crees');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_CUSTOMER', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-19.8 Makers/Checkers historiques de STTB_ACCOUNT (ouverture/modif compte)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAKER_ID, COUNT(*) nb
            FROM STTB_ACCOUNT
            WHERE MAKER_ID IS NOT NULL
            GROUP BY MAKER_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 15) LOOP
            p_kv('  MAKER_ACC=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' comptes crees/modif');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTB_ACCOUNT', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-19.9 Makers orphelins sur STTM_CUSTOMER (CIF cree par user supprime de SMTB_USER)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(DISTINCT c.MAKER_ID)
            FROM STTM_CUSTOMER c
            WHERE c.MAKER_ID IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = c.MAKER_ID)'
        INTO v_count;
        p_kv('  MAKER_ID CIF absents de SMTB_USER', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_CUSTOMER-SMTB_USER jointure', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-19.10 Poids des makers sur STTM_KYC_MASTER');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAKER_ID, COUNT(*) nb
            FROM STTM_KYC_MASTER
            WHERE MAKER_ID IS NOT NULL
            GROUP BY MAKER_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 15) LOOP
            p_kv('  MAKER_KYC=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' KYC maj');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_KYC_MASTER', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-19.11 SMTB_SMS_LOG — acces recents aux ecrans sensibles (90 jours)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT USER_ID, COUNT(*) nb
            FROM SMTB_SMS_LOG
            WHERE UPPER(NVL(OPERATION,''''))  LIKE ''%CIF%''
              AND TRUNC(OPERATION_DATE) >= TRUNC(SYSDATE)-90
            GROUP BY USER_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 10) LOOP
            p_kv('  USER=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' acces CIF 90j');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  SMTB_SMS_LOG/CIF 90j', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-19.12 Ratio de concentration — Top 1 maker STTM_CUSTOMER / total');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAX(nb), SUM(nb) FROM (
                SELECT COUNT(*) nb FROM STTM_CUSTOMER
                WHERE MAKER_ID IS NOT NULL
                GROUP BY MAKER_ID
            )' INTO v_count, v_total;
        p_pct('  Poids du maker dominant CIF', v_count, v_total);
    EXCEPTION WHEN OTHERS THEN
        p_kv('  Concentration CIF', 'inaccessible - ' || SQLERRM);
    END;

    -- =========================================================
    -- A-20. TRACABILITE MAKER/CHECKER SUR LES TABLES METIER
    -- =========================================================
    p_section('A-20. TRACABILITE MAKER/CHECKER — double signature sur operations metier');

    p_sub('A-20.1 STTM_CUSTOMER — repartition AUTH_STATUS (A=Authorise, U=Unauth)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT NVL(AUTH_STATUS,''?''), COUNT(*) nb
            FROM STTM_CUSTOMER
            GROUP BY AUTH_STATUS
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. v_maker_tab.COUNT LOOP
            p_kv('  STTM_CUSTOMER AUTH_STATUS=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)));
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_CUSTOMER AUTH_STATUS', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.2 STTM_CUSTOMER — CIF en statut unauthorized (risque non-authorise)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(*) FROM STTM_CUSTOMER
            WHERE NVL(AUTH_STATUS,''U'') <> ''A''' INTO v_count;
        p_kv('  CIF non authorises', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  CIF non authorises', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.3 STTM_CUSTOMER — violations SoD (MAKER_ID = CHECKER_ID)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(*) FROM STTM_CUSTOMER
            WHERE MAKER_ID IS NOT NULL
              AND CHECKER_ID IS NOT NULL
              AND UPPER(MAKER_ID) = UPPER(CHECKER_ID)' INTO v_count;
        p_kv('  CIF auto-authorises (MAKER=CHECKER)', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_CUSTOMER SoD', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.4 STTB_ACCOUNT — repartition AUTH_STATUS');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT NVL(AUTH_STATUS,''?''), COUNT(*) nb
            FROM STTB_ACCOUNT
            GROUP BY AUTH_STATUS
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. v_maker_tab.COUNT LOOP
            p_kv('  STTB_ACCOUNT AUTH_STATUS=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)));
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTB_ACCOUNT AUTH_STATUS', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.5 STTB_ACCOUNT — violations SoD (MAKER=CHECKER sur compte)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(*) FROM STTB_ACCOUNT
            WHERE MAKER_ID IS NOT NULL
              AND CHECKER_ID IS NOT NULL
              AND UPPER(MAKER_ID) = UPPER(CHECKER_ID)' INTO v_count;
        p_kv('  Comptes auto-authorises', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTB_ACCOUNT SoD', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.6 STTM_KYC_MASTER — repartition AUTH_STATUS');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT NVL(AUTH_STATUS,''?''), COUNT(*) nb
            FROM STTM_KYC_MASTER
            GROUP BY AUTH_STATUS
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. v_maker_tab.COUNT LOOP
            p_kv('  STTM_KYC_MASTER AUTH_STATUS=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)));
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_KYC_MASTER AUTH_STATUS', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.7 STTM_KYC_MASTER — violations SoD');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(*) FROM STTM_KYC_MASTER
            WHERE MAKER_ID IS NOT NULL
              AND CHECKER_ID IS NOT NULL
              AND UPPER(MAKER_ID) = UPPER(CHECKER_ID)' INTO v_count;
        p_kv('  KYC auto-authorises', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  STTM_KYC_MASTER SoD', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.8 ACTB_HISTORY — violations SoD sur ecritures comptables (MAKER_ID=AUTH_ID)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(*) FROM ACTB_HISTORY
            WHERE MAKER_ID IS NOT NULL
              AND AUTH_ID IS NOT NULL
              AND UPPER(MAKER_ID) = UPPER(AUTH_ID)' INTO v_count;
        p_kv('  Ecritures auto-authorisees', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  ACTB_HISTORY SoD', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.9 ACTB_HISTORY — Top 15 makers ecritures (365 j)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAKER_ID, COUNT(*) nb FROM ACTB_HISTORY
            WHERE MAKER_ID IS NOT NULL
              AND TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -12)
            GROUP BY MAKER_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 15) LOOP
            p_kv('  MAKER=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' ecritures 12m');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  ACTB_HISTORY top makers', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.10 ACTB_HISTORY — Top 15 authorizers ecritures (365 j)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT AUTH_ID, COUNT(*) nb FROM ACTB_HISTORY
            WHERE AUTH_ID IS NOT NULL
              AND TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -12)
            GROUP BY AUTH_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 15) LOOP
            p_kv('  AUTH=' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' autorisations 12m');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  ACTB_HISTORY top auths', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.11 ACTB_HISTORY — paires MAKER-AUTH les plus frequentes (Top 10, 90 j)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT MAKER_ID || '' >> '' || AUTH_ID paire, COUNT(*) nb
            FROM ACTB_HISTORY
            WHERE MAKER_ID IS NOT NULL AND AUTH_ID IS NOT NULL
              AND TRN_DT >= TRUNC(SYSDATE) - 90
            GROUP BY MAKER_ID || '' >> '' || AUTH_ID
            ORDER BY nb DESC'
        BULK COLLECT INTO v_maker_tab, v_count_tab;
        FOR i IN 1 .. LEAST(v_maker_tab.COUNT, 10) LOOP
            p_kv('  ' || v_maker_tab(i), TO_CHAR(v_count_tab(i)) || ' operations 90j');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p_kv('  ACTB_HISTORY paires', 'inaccessible - ' || SQLERRM);
    END;

    p_sub('A-20.12 Orphelins maker/checker (identifiants absents de SMTB_USER)');
    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(DISTINCT MAKER_ID)
            FROM STTM_CUSTOMER c
            WHERE c.MAKER_ID IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = c.MAKER_ID)'
        INTO v_count;
        p_kv('  Makers CIF absents du referentiel', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  Makers CIF orphelins', 'inaccessible - ' || SQLERRM);
    END;

    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(DISTINCT MAKER_ID)
            FROM STTB_ACCOUNT a
            WHERE a.MAKER_ID IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = a.MAKER_ID)'
        INTO v_count;
        p_kv('  Makers comptes absents du referentiel', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  Makers comptes orphelins', 'inaccessible - ' || SQLERRM);
    END;

    BEGIN
        EXECUTE IMMEDIATE '
            SELECT COUNT(DISTINCT MAKER_ID)
            FROM ACTB_HISTORY h
            WHERE h.MAKER_ID IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM SMTB_USER u WHERE u.USER_ID = h.MAKER_ID)'
        INTO v_count;
        p_kv('  Makers ecritures absents du referentiel', TO_CHAR(v_count));
    EXCEPTION WHEN OTHERS THEN
        p_kv('  Makers ecritures orphelins', 'inaccessible - ' || SQLERRM);
    END;

    -- =========================================================
    -- A-16. SYNTHESE FINALE & REFERENCES
    -- =========================================================
    p_section('A-16. SYNTHESE FINALE — perimetre couvert par ce script');

    DBMS_OUTPUT.PUT_LINE('  Perimetre explore (24 tables + UDF) :');
    DBMS_OUTPUT.PUT_LINE('    - Comptes & identite       : SMTB_USER, FBTB_USER, SMDUSRDF (UDF)');
    DBMS_OUTPUT.PUT_LINE('    - Cycle de vie & inactivite: SMTB_USER_DISABLE, SMTB_USERLOG_DETAILS');
    DBMS_OUTPUT.PUT_LINE('    - Roles & privileges       : SMTB_ROLE_MASTER, SMTB_ROLE_DETAIL,');
    DBMS_OUTPUT.PUT_LINE('                                  SMTB_ROLE_BRANCHES, SMDROLDF (UDF)');
    DBMS_OUTPUT.PUT_LINE('    - Affectations             : SMTB_USER_ROLE, SMTB_USER_CENTRAL_ROLES,');
    DBMS_OUTPUT.PUT_LINE('                                  SMTB_USER_TILLS');
    DBMS_OUTPUT.PUT_LINE('    - Limites transactionnelles: SMTB_ROLE_FUNC_LIMIT_CUSTOM/DETAIL');
    DBMS_OUTPUT.PUT_LINE('    - Politique MDP & params   : SMTB_PARAMETERS, SMTB_PASSWORD_HISTORY');
    DBMS_OUTPUT.PUT_LINE('    - Piste d''audit            : SMTB_SMS_LOG, SMTB_SMS_ACTION_LOG');
    DBMS_OUTPUT.PUT_LINE('    - Catalogue fonctionnel    : SMTB_MENU, SMTB_FUNCTION_DESCRIPTION,');
    DBMS_OUTPUT.PUT_LINE('                                  SMTB_MODULES, SMTB_LANGUAGE, SMTB_FUNC_GROUP');
    DBMS_OUTPUT.PUT_LINE('    - Droits peripheriques     : SMTB_MSGS_RIGHTS, SMTB_QUEUES,');
    DBMS_OUTPUT.PUT_LINE('                                  SMTB_QUEUE_RIGHTS, SMTB_ACTION_CONTROLS,');
    DBMS_OUTPUT.PUT_LINE('                                  SMTB_STAGE_FIELD_VALUE');
    DBMS_OUTPUT.PUT_LINE('    - Topologie agences        : FBTM_BRANCH, FBTM_BRANCH_INFO, STDBRANC (UDF)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Prochaines etapes suggerees :');
    DBMS_OUTPUT.PUT_LINE('    1. Rediger un rapport d''exploration (exploration_access_report.txt)');
    DBMS_OUTPUT.PUT_LINE('    2. Etablir le dictionnaire de donnees securite / referentiels');
    DBMS_OUTPUT.PUT_LINE('    3. Concevoir un script d''audit IAM (controles automatises COBAC / CIS)');
    DBMS_OUTPUT.PUT_LINE('    4. Definir KRI : taux dormance, SoD, roles universels, MDP non tournes');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  Referentiels applicables :');
    DBMS_OUTPUT.PUT_LINE('    - COBAC R-2016/01 (controle interne etablissements de credit CEMAC)');
    DBMS_OUTPUT.PUT_LINE('    - ISO/IEC 27001 A.9 (Access Control) & A.12.4 (Logging)');
    DBMS_OUTPUT.PUT_LINE('    - PCI-DSS v4 8.x (gestion des identites et authentification)');
    DBMS_OUTPUT.PUT_LINE('    - CIS Controls v8 # 5 (Account Management) & # 6 (Access Control)');

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('>>> 16 sections - perimetre IAM/SECURITE FLEXCUBE');
    DBMS_OUTPUT.PUT_LINE(v_sep);

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ERREUR PL/SQL : ' || SQLCODE || ' - ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('>>> ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        DBMS_OUTPUT.PUT_LINE(v_sep);
        RAISE;
END;
/
