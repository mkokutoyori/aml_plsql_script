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
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('>>> EXPLORATION TERMINEE — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
