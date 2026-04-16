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
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
