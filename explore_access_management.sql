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
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
