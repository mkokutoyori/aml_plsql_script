/***********************************************************************
 * REVENUE ASSURANCE & ACCOUNTING AUDIT
 * ---------------------------------------------------------------------
 * Script   : revenue_assurance_and_accounting_audit.sql
 * Version  : 1.0.0
 * Purpose  : Detection and quantification of revenue leakage and
 *            accounting anomalies on an Oracle FCUBS (Flexcube
 *            Universal Banking) database, aligned with the CEMAC
 *            banking chart of accounts (COBAC R-98/01).
 * Scope    : Read-only PL/SQL anonymous block. No DML, no DDL.
 * Compat   : Oracle 11gR2 or higher.
 * Author   : Audit / Revenue Assurance team
 * Refs     : BRD_revenue_assurance.md, bonnes_pratiques.md
 * ---------------------------------------------------------------------
 * HOW TO RUN
 *   1. Log in to SQL*Plus / SQLcl / SQL Developer with a read-only
 *      account having SELECT privilege on the FCUBS schemas.
 *   2. Optional: edit the parameters in the DECLARE block below.
 *   3. Redirect output to a timestamped file:
 *         SPOOL reports/revenue_assurance_20260417.txt
 *         @revenue_assurance_and_accounting_audit.sql
 *         SPOOL OFF
 *   4. Archive the resulting text file for audit trail.
 * ---------------------------------------------------------------------
 * SECURITY NOTES
 *   - This script is strictly read-only. It does not create, modify or
 *     delete any row or object. Any deviation from this rule is
 *     considered a critical bug.
 *   - Personally identifiable information (account numbers, customer
 *     numbers) can be partially masked via p_mask_pii = 'Y' (default).
 *   - The output may contain sensitive findings (fraud, SoD). Restrict
 *     distribution according to the bank's information-security
 *     policy.
 **********************************************************************/

-- ---------------------------------------------------------------------
-- SQL*Plus environment settings (ignored on clients that do not support
-- them; the PL/SQL block itself remains portable).
-- ---------------------------------------------------------------------
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 200
SET PAGESIZE 0
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SET TERMOUT ON
SET ECHO OFF
WHENEVER SQLERROR CONTINUE

-- =====================================================================
--  REVENUE ASSURANCE & ACCOUNTING AUDIT - MAIN ANONYMOUS BLOCK
-- =====================================================================
DECLARE
    -- =================================================================
    -- SECTION 1 - CONSTANTS AND OPTIONAL PARAMETERS
    -- -----------------------------------------------------------------
    -- Toutes les valeurs par defaut sont NULL ou des valeurs neutres :
    -- NULL sur un parametre signifie "pas de filtre" (portee maximale).
    -- Les utilisateurs peuvent editer les valeurs ci-dessous pour
    -- restreindre le perimetre d'audit. Le rapport affiche un echo
    -- complet des parametres effectifs en tete.
    -- =================================================================

    -- --------------------------------------------------------------
    -- 1.1 Identite du script (constantes figees, ne pas editer)
    -- --------------------------------------------------------------
    C_SCRIPT_NAME            CONSTANT VARCHAR2(80)  := 'revenue_assurance_and_accounting_audit.sql';
    C_SCRIPT_VERSION         CONSTANT VARCHAR2(20)  := '1.0.0';
    C_REPORT_FORMAT_VERSION  CONSTANT VARCHAR2(10)  := '1.0';
    C_REGULATION             CONSTANT VARCHAR2(80)  := 'COBAC R-98/01 (PCEC CEMAC)';

    -- --------------------------------------------------------------
    -- 1.2 Perimetre temporel
    -- --------------------------------------------------------------
    p_date_from              DATE   := NULL;     -- Debut de periode (inclusif). NULL = debut du mois precedent.
    p_date_to                DATE   := NULL;     -- Fin de periode (inclusif).   NULL = date metier courante.
    p_as_of_date             DATE   := NULL;     -- Date de photo des soldes.    NULL = SYSDATE.

    -- --------------------------------------------------------------
    -- 1.3 Perimetre organisationnel / agence
    -- --------------------------------------------------------------
    p_branch_code            VARCHAR2(10)  := NULL;   -- Agence unique.
    p_branch_list            SYS.ODCIVARCHAR2LIST := NULL;  -- Liste d'agences (prime sur p_branch_code).
    p_department             VARCHAR2(40)  := NULL;   -- Departement / region interne.

    -- --------------------------------------------------------------
    -- 1.4 Perimetre client / compte
    -- --------------------------------------------------------------
    p_customer_no            VARCHAR2(20)  := NULL;
    p_customer_list          SYS.ODCIVARCHAR2LIST := NULL;
    p_account_no             VARCHAR2(30)  := NULL;
    p_account_list           SYS.ODCIVARCHAR2LIST := NULL;
    p_customer_segment       VARCHAR2(20)  := NULL;   -- CORPORATE / SME / RETAIL / ...

    -- --------------------------------------------------------------
    -- 1.5 Produits et modules
    -- --------------------------------------------------------------
    p_module                 VARCHAR2(10)  := NULL;   -- CL / LD / SI / IC / MO / FT / FX / GL (NULL = tous).
    p_product_list           SYS.ODCIVARCHAR2LIST := NULL;
    p_account_class_list     SYS.ODCIVARCHAR2LIST := NULL;

    -- --------------------------------------------------------------
    -- 1.6 Devises
    -- --------------------------------------------------------------
    p_ccy                    VARCHAR2(3)   := NULL;   -- ISO 4217 (ex. XAF, USD, EUR).
    p_ccy_list               SYS.ODCIVARCHAR2LIST := NULL;
    p_include_fcy_only       CHAR(1)       := 'N';    -- 'Y' = restreindre aux comptes en devise etrangere.

    -- --------------------------------------------------------------
    -- 1.7 Seuils de materialite (en devise locale)
    -- --------------------------------------------------------------
    p_materiality_lcy           NUMBER := 100000;       -- Seuil global de materialite.
    p_materiality_impact_lcy    NUMBER := 1000000;      -- Promotion automatique en HIGH.
    p_materiality_critical_lcy  NUMBER := 10000000;     -- Promotion automatique en CRITICAL.
    p_min_days_overdue          NUMBER := 30;
    p_min_days_dormant          NUMBER := 180;

    -- --------------------------------------------------------------
    -- 1.8 Mode d'execution et verbosite
    -- --------------------------------------------------------------
    p_mode                   VARCHAR2(10)  := 'FULL';   -- SUMMARY / FULL / DEEP
    p_top_n                  NUMBER        := 50;       -- Lignes max par extraction TOP-N.
    p_verbose                CHAR(1)       := 'N';      -- 'Y' = imprimer les requetes d'appui.
    p_include_perf_log       CHAR(1)       := 'Y';      -- 'Y' = bloc [PERF] en pied de rapport.
    p_mask_pii               CHAR(1)       := 'Y';      -- 'Y' = masquer les numeros PII.
    p_language               VARCHAR2(2)   := 'EN';     -- Verrouille a EN en v1.

    -- --------------------------------------------------------------
    -- 1.9 Controle des sections
    -- --------------------------------------------------------------
    p_sections_include       SYS.ODCIVARCHAR2LIST := NULL; -- Liste blanche ('S01','S05',...). NULL = tout.
    p_sections_exclude       SYS.ODCIVARCHAR2LIST := NULL; -- Liste noire. Prime sur include.

    -- --------------------------------------------------------------
    -- 1.10 Parametres anti-fraude (BRD §15.6)
    -- --------------------------------------------------------------
    p_structuring_threshold_lcy NUMBER       := 10000000;  -- Seuil de detection du structuring.
    p_reversal_window_hours     NUMBER       := 24;        -- Fenetre des contre-passations suspectes.
    p_business_hours_from       VARCHAR2(5)  := '07:00';
    p_business_hours_to         VARCHAR2(5)  := '19:00';
    p_weekend_days              VARCHAR2(20) := 'SAT,SUN';
    p_holiday_list              SYS.ODCIVARCHAR2LIST := NULL;
    p_tamper_window_hours       NUMBER       := 24;        -- Fenetre modification referentiel -> debit.
    p_cycle_max_length          NUMBER       := 5;
    p_exclude_technical_users   SYS.ODCIVARCHAR2LIST := NULL; -- USER_ID techniques a ignorer.
    p_tol_days_backdate         NUMBER       := 3;         -- Tolerance BKG_DATE vs TRN_DT.

    -- --------------------------------------------------------------
    -- 1.11 Valeurs effectives (calculees a l'initialisation)
    -- --------------------------------------------------------------
    v_date_from      DATE;
    v_date_to        DATE;
    v_as_of_date     DATE;
    v_run_id         VARCHAR2(20);
    v_db_user        VARCHAR2(60);
    v_instance_name  VARCHAR2(60);
    v_business_date  DATE;

    -- --------------------------------------------------------------
    -- 1.12 Compteurs globaux (alimentes par chaque section)
    -- --------------------------------------------------------------
    g_findings_total     PLS_INTEGER := 0;
    g_findings_critical  PLS_INTEGER := 0;
    g_findings_high      PLS_INTEGER := 0;
    g_findings_medium    PLS_INTEGER := 0;
    g_findings_low       PLS_INTEGER := 0;
    g_findings_info      PLS_INTEGER := 0;
    g_total_exposure_lcy NUMBER      := 0;
    g_section_errors     PLS_INTEGER := 0;
    g_limitations        PLS_INTEGER := 0;

    -- --------------------------------------------------------------
    -- 1.13 Chronometrage [PERF]
    -- --------------------------------------------------------------
    g_t_start            PLS_INTEGER;
    g_t_section_start    PLS_INTEGER;

    -- =================================================================
    -- SECTION 2 - PROCEDURES HELPERS (PRINT, LOG, FINDING)
    -- -----------------------------------------------------------------
    -- Helpers locaux reutilises par toutes les sections d'audit.
    -- - Tous declares AVANT le BEGIN principal (bonnes_pratiques.md).
    -- - Aucun ne realise de DML.
    -- - Chaque helper capture WHEN OTHERS afin de ne jamais interrompre
    --   un rapport pour une erreur d'impression ou de journalisation.
    -- - Ordre de declaration respecte les dependances (forward refs
    --   interdits en PL/SQL local).
    -- =================================================================

    -----------------------------------------------------------------
    -- 2.1 f_mask_pii : masquage optionnel des numeros PII.
    --     Garde les 4 premiers caracteres, remplace le reste par '*'.
    --     Si p_mask_pii <> 'Y', la valeur est rendue telle quelle.
    -----------------------------------------------------------------
    FUNCTION f_mask_pii(p_val IN VARCHAR2) RETURN VARCHAR2 IS
        l_len  PLS_INTEGER;
        l_keep CONSTANT PLS_INTEGER := 4;
    BEGIN
        IF p_val IS NULL THEN
            RETURN NULL;
        END IF;
        IF NVL(p_mask_pii,'N') <> 'Y' THEN
            RETURN p_val;
        END IF;
        l_len := LENGTH(p_val);
        IF l_len <= l_keep THEN
            RETURN RPAD('*', l_len, '*');
        END IF;
        RETURN SUBSTR(p_val, 1, l_keep) || RPAD('*', l_len - l_keep, '*');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN '***';
    END f_mask_pii;

    -----------------------------------------------------------------
    -- 2.2 f_fmt_lcy : formatage numerique stable, insensible a la NLS.
    -----------------------------------------------------------------
    FUNCTION f_fmt_lcy(p_amt IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF p_amt IS NULL THEN
            RETURN 'N/A';
        END IF;
        RETURN TO_CHAR(p_amt, 'FM999,999,999,999,990.00',
                       'NLS_NUMERIC_CHARACTERS=''.,''');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TO_CHAR(p_amt);
    END f_fmt_lcy;

    -----------------------------------------------------------------
    -- 2.3 f_fmt_ts : horodatage stable YYYY-MM-DD HH24:MI:SS.
    -----------------------------------------------------------------
    FUNCTION f_fmt_ts(p_d IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_d IS NULL THEN
            RETURN 'N/A';
        END IF;
        RETURN TO_CHAR(p_d, 'YYYY-MM-DD HH24:MI:SS');
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END f_fmt_ts;

    -----------------------------------------------------------------
    -- 2.4 f_elapsed_ms : temps ecoule en ms depuis DBMS_UTILITY.GET_TIME.
    --     GET_TIME rend des centisecondes : *10 pour passer en ms.
    -----------------------------------------------------------------
    FUNCTION f_elapsed_ms(p_t_start IN PLS_INTEGER) RETURN PLS_INTEGER IS
    BEGIN
        IF p_t_start IS NULL THEN
            RETURN NULL;
        END IF;
        RETURN (DBMS_UTILITY.GET_TIME - p_t_start) * 10;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END f_elapsed_ms;

    -----------------------------------------------------------------
    -- 2.5 print_line : impression brute d'une ligne.
    -----------------------------------------------------------------
    PROCEDURE print_line(p_txt IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(NVL(p_txt, ''));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END print_line;

    -----------------------------------------------------------------
    -- 2.6 print_kv : impression cle-valeur alignee.
    -----------------------------------------------------------------
    PROCEDURE print_kv(
        p_key   IN VARCHAR2,
        p_val   IN VARCHAR2,
        p_width IN PLS_INTEGER DEFAULT 32
    ) IS
        l_w PLS_INTEGER := NVL(p_width, 32);
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD(NVL(p_key,''), l_w, ' ') || ': ' || NVL(p_val,''));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END print_kv;

    -----------------------------------------------------------------
    -- 2.7 print_section_header : banniere d'ouverture + chrono section.
    -----------------------------------------------------------------
    PROCEDURE print_section_header(
        p_code  IN VARCHAR2,
        p_title IN VARCHAR2
    ) IS
    BEGIN
        g_t_section_start := DBMS_UTILITY.GET_TIME;
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 78, '='));
        DBMS_OUTPUT.PUT_LINE('[' || NVL(p_code,'SXX') || '] ' || NVL(p_title,''));
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 78, '='));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END print_section_header;

    -----------------------------------------------------------------
    -- 2.8 print_section_footer : cloture + nombre de findings + ms.
    -----------------------------------------------------------------
    PROCEDURE print_section_footer(
        p_code       IN VARCHAR2,
        p_n_findings IN PLS_INTEGER DEFAULT NULL
    ) IS
        l_ms PLS_INTEGER;
    BEGIN
        l_ms := f_elapsed_ms(g_t_section_start);
        DBMS_OUTPUT.PUT_LINE('[' || NVL(p_code,'SXX') || '] END'
            || ' findings=' || NVL(TO_CHAR(p_n_findings), '0')
            || ' elapsed_ms=' || NVL(TO_CHAR(l_ms), 'N/A'));
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 78, '-'));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END print_section_footer;

    -----------------------------------------------------------------
    -- 2.9 log_info / log_warn / log_error : journalisation technique.
    --     log_warn incremente g_limitations ; log_error incremente
    --     g_section_errors. Les deux sont exploites par [LOG] final.
    -----------------------------------------------------------------
    PROCEDURE log_info(p_msg IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('[LOG][INFO ] '
            || f_fmt_ts(SYSDATE) || ' ' || NVL(p_msg,''));
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END log_info;

    PROCEDURE log_warn(p_msg IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('[LOG][WARN ] '
            || f_fmt_ts(SYSDATE) || ' ' || NVL(p_msg,''));
        g_limitations := NVL(g_limitations, 0) + 1;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END log_warn;

    PROCEDURE log_error(p_section IN VARCHAR2, p_msg IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('[LOG][ERROR] '
            || f_fmt_ts(SYSDATE)
            || ' SEC=' || NVL(p_section,'?')
            || ' ' || NVL(p_msg,''));
        g_section_errors := NVL(g_section_errors, 0) + 1;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END log_error;

    -----------------------------------------------------------------
    -- 2.10 f_promote_severity : promotion automatique selon l'impact.
    --      - impact >= p_materiality_critical_lcy => CRITICAL
    --      - impact >= p_materiality_impact_lcy   => HIGH
    --      Une severite n'est jamais retrogradee.
    -----------------------------------------------------------------
    FUNCTION f_promote_severity(
        p_severity   IN VARCHAR2,
        p_impact_lcy IN NUMBER
    ) RETURN VARCHAR2 IS
        l_sev  VARCHAR2(10) := UPPER(NVL(p_severity,'INFO'));
        l_rank PLS_INTEGER;
        l_new  VARCHAR2(10);
    BEGIN
        l_rank := CASE l_sev
                      WHEN 'CRITICAL' THEN 5
                      WHEN 'HIGH'     THEN 4
                      WHEN 'MEDIUM'   THEN 3
                      WHEN 'LOW'      THEN 2
                      WHEN 'INFO'     THEN 1
                      ELSE 1
                  END;
        IF p_impact_lcy IS NOT NULL THEN
            IF p_materiality_critical_lcy IS NOT NULL
               AND p_impact_lcy >= p_materiality_critical_lcy THEN
                l_new := 'CRITICAL';
            ELSIF p_materiality_impact_lcy IS NOT NULL
              AND p_impact_lcy >= p_materiality_impact_lcy THEN
                l_new := 'HIGH';
            END IF;
            IF l_new = 'CRITICAL' AND l_rank < 5 THEN
                RETURN 'CRITICAL';
            ELSIF l_new = 'HIGH' AND l_rank < 4 THEN
                RETURN 'HIGH';
            END IF;
        END IF;
        RETURN l_sev;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NVL(p_severity,'INFO');
    END f_promote_severity;

    -----------------------------------------------------------------
    -- 2.11 print_finding : emet une ligne [FND] + met a jour les
    --      compteurs globaux g_findings_* et g_total_exposure_lcy.
    --      Aucune exception ne remonte.
    -----------------------------------------------------------------
    PROCEDURE print_finding(
        p_section    IN VARCHAR2,
        p_code       IN VARCHAR2,
        p_severity   IN VARCHAR2,
        p_message    IN VARCHAR2,
        p_entity     IN VARCHAR2 DEFAULT NULL,
        p_impact_lcy IN NUMBER   DEFAULT NULL,
        p_evidence   IN VARCHAR2 DEFAULT NULL
    ) IS
        l_sev    VARCHAR2(10);
        l_entity VARCHAR2(400);
        l_impact VARCHAR2(40);
    BEGIN
        l_sev    := f_promote_severity(p_severity, p_impact_lcy);
        l_entity := f_mask_pii(p_entity);
        l_impact := f_fmt_lcy(p_impact_lcy);

        DBMS_OUTPUT.PUT_LINE(
            '[FND] SEC=' || NVL(p_section,'SXX')
            || ' SEV=' || RPAD(l_sev, 8, ' ')
            || ' CODE=' || RPAD(NVL(p_code,'---'), 14, ' ')
            || ' IMPACT_LCY=' || l_impact
            || ' ENT=' || NVL(l_entity,'-')
            || ' | ' || NVL(p_message,'')
            || CASE WHEN p_evidence IS NOT NULL
                    THEN ' | EV=' || p_evidence
                    ELSE NULL
               END
        );

        g_findings_total := NVL(g_findings_total, 0) + 1;
        CASE l_sev
            WHEN 'CRITICAL' THEN g_findings_critical := NVL(g_findings_critical,0) + 1;
            WHEN 'HIGH'     THEN g_findings_high     := NVL(g_findings_high,0)     + 1;
            WHEN 'MEDIUM'   THEN g_findings_medium   := NVL(g_findings_medium,0)   + 1;
            WHEN 'LOW'      THEN g_findings_low      := NVL(g_findings_low,0)      + 1;
            WHEN 'INFO'     THEN g_findings_info     := NVL(g_findings_info,0)     + 1;
            ELSE                  g_findings_info     := NVL(g_findings_info,0)     + 1;
        END CASE;

        IF p_impact_lcy IS NOT NULL THEN
            g_total_exposure_lcy := NVL(g_total_exposure_lcy, 0) + p_impact_lcy;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                DBMS_OUTPUT.PUT_LINE('[LOG][WARN ] print_finding failed for '
                    || NVL(p_section,'SXX') || '/' || NVL(p_code,'---')
                    || ' : ' || SUBSTR(SQLERRM, 1, 200));
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END print_finding;

    -----------------------------------------------------------------
    -- 2.12 safe_count : execute un SELECT COUNT scalaire en dynamique.
    --      - Renvoie 0 si le SQL est vide.
    --      - Renvoie NULL et journalise une erreur si l'execution echoue
    --        (table absente, privileges, etc.). Ce contrat est utilise
    --        par les sections d'audit pour ne jamais interrompre le
    --        rapport face a une vue FCUBS non provisionnee.
    -----------------------------------------------------------------
    FUNCTION safe_count(
        p_section IN VARCHAR2,
        p_sql     IN VARCHAR2
    ) RETURN NUMBER IS
        l_n NUMBER;
    BEGIN
        IF p_sql IS NULL THEN
            RETURN 0;
        END IF;
        EXECUTE IMMEDIATE p_sql INTO l_n;
        RETURN NVL(l_n, 0);
    EXCEPTION
        WHEN OTHERS THEN
            log_error(p_section,
                'safe_count failed: ' || SUBSTR(SQLERRM, 1, 200));
            RETURN NULL;
    END safe_count;

    -----------------------------------------------------------------
    -- 2.13 safe_scalar_varchar2 : idem safe_count mais rend VARCHAR2.
    --      Utilise pour les metadonnees (version DB, business_date...).
    -----------------------------------------------------------------
    FUNCTION safe_scalar_varchar2(
        p_section IN VARCHAR2,
        p_sql     IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_v VARCHAR2(4000);
    BEGIN
        IF p_sql IS NULL THEN
            RETURN NULL;
        END IF;
        EXECUTE IMMEDIATE p_sql INTO l_v;
        RETURN l_v;
    EXCEPTION
        WHEN OTHERS THEN
            log_error(p_section,
                'safe_scalar_varchar2 failed: ' || SUBSTR(SQLERRM, 1, 200));
            RETURN NULL;
    END safe_scalar_varchar2;

    -----------------------------------------------------------------
    -- 2.14 safe_scalar_date : idem safe_count mais rend DATE.
    -----------------------------------------------------------------
    FUNCTION safe_scalar_date(
        p_section IN VARCHAR2,
        p_sql     IN VARCHAR2
    ) RETURN DATE IS
        l_d DATE;
    BEGIN
        IF p_sql IS NULL THEN
            RETURN NULL;
        END IF;
        EXECUTE IMMEDIATE p_sql INTO l_d;
        RETURN l_d;
    EXCEPTION
        WHEN OTHERS THEN
            log_error(p_section,
                'safe_scalar_date failed: ' || SUBSTR(SQLERRM, 1, 200));
            RETURN NULL;
    END safe_scalar_date;

    -----------------------------------------------------------------
    -- 2.15 f_section_enabled : filtre inclusion/exclusion de sections.
    --      p_sections_exclude prime sur p_sections_include (BRD §6).
    -----------------------------------------------------------------
    FUNCTION f_section_enabled(p_code IN VARCHAR2) RETURN BOOLEAN IS
        l_in_inc BOOLEAN := TRUE;
        l_in_exc BOOLEAN := FALSE;
    BEGIN
        IF p_code IS NULL THEN
            RETURN TRUE;
        END IF;
        IF p_sections_exclude IS NOT NULL AND p_sections_exclude.COUNT > 0 THEN
            FOR i IN 1 .. p_sections_exclude.COUNT LOOP
                IF UPPER(p_sections_exclude(i)) = UPPER(p_code) THEN
                    l_in_exc := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        END IF;
        IF l_in_exc THEN
            RETURN FALSE;
        END IF;
        IF p_sections_include IS NOT NULL AND p_sections_include.COUNT > 0 THEN
            l_in_inc := FALSE;
            FOR i IN 1 .. p_sections_include.COUNT LOOP
                IF UPPER(p_sections_include(i)) = UPPER(p_code) THEN
                    l_in_inc := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        END IF;
        RETURN l_in_inc;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TRUE; -- En cas de doute, on execute la section.
    END f_section_enabled;

BEGIN
    -- =================================================================
    -- SECTION 3 - INITIALISATION DES VALEURS EFFECTIVES ET ECHO
    -- -----------------------------------------------------------------
    -- 3.1 Demarre le chrono global [PERF].
    -- 3.2 Collecte les metadonnees d'environnement (user, instance,
    --     run_id) via SYS_CONTEXT. Repli silencieux sur USER si l'acces
    --     au contexte est refuse.
    -- 3.3 Resolve la date metier FCUBS a partir de SMTB_BANK_PARAMETERS.
    --     Repli sur TRUNC(SYSDATE) avec journal [WARN] si la table n'est
    --     pas accessible.
    -- 3.4 Calcule le perimetre temporel effectif :
    --       v_date_to    = p_date_to    ou date metier
    --       v_date_from  = p_date_from  ou 1er du mois precedent
    --       v_as_of_date = p_as_of_date ou date metier
    --     Journalise un [WARN] si les bornes sont inversees.
    -- 3.5 Imprime la banniere du rapport (identite du script).
    -- 3.6 Echo integral des parametres effectifs (BRD §6.3) - aucune
    --     donnee sensible n'est imprimee en clair : p_customer_no et
    --     p_account_no passent par f_mask_pii ; pour les collections
    --     seule la cardinalite est publiee.
    -- =================================================================

    -- 3.1 Chrono global -------------------------------------------------
    g_t_start := DBMS_UTILITY.GET_TIME;

    -- 3.2 Metadonnees d'environnement -----------------------------------
    BEGIN
        SELECT SYS_CONTEXT('USERENV','SESSION_USER'),
               SYS_CONTEXT('USERENV','INSTANCE_NAME')
          INTO v_db_user, v_instance_name
          FROM DUAL;
    EXCEPTION
        WHEN OTHERS THEN
            v_db_user       := USER;
            v_instance_name := NULL;
    END;

    v_run_id := TO_CHAR(SYSDATE, 'YYYYMMDD-HH24MISS')
                || '-' || NVL(SYS_CONTEXT('USERENV','SESSIONID'), '0');

    -- 3.3 Date metier FCUBS --------------------------------------------
    v_business_date := safe_scalar_date(
        'INIT',
        'SELECT MIN(TODAY) FROM SMTB_BANK_PARAMETERS'
    );
    IF v_business_date IS NULL THEN
        log_warn('FCUBS business date unavailable; fallback to TRUNC(SYSDATE).');
        v_business_date := TRUNC(SYSDATE);
    END IF;

    -- 3.4 Perimetre temporel effectif ----------------------------------
    v_as_of_date := NVL(p_as_of_date, v_business_date);
    v_date_to    := NVL(p_date_to,    v_business_date);
    v_date_from  := NVL(p_date_from,
                        ADD_MONTHS(TRUNC(v_business_date, 'MM'), -1));

    IF v_date_from > v_date_to THEN
        log_warn('p_date_from > p_date_to : bornes inversees, rapport potentiellement vide.');
    END IF;

    -- 3.5 Banniere ------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE(RPAD('=', 78, '='));
    DBMS_OUTPUT.PUT_LINE('REVENUE ASSURANCE & ACCOUNTING AUDIT');
    DBMS_OUTPUT.PUT_LINE(RPAD('=', 78, '='));
    print_kv('Script',          C_SCRIPT_NAME || ' v' || C_SCRIPT_VERSION);
    print_kv('Report format',   C_REPORT_FORMAT_VERSION);
    print_kv('Regulation',      C_REGULATION);
    print_kv('Run id',          v_run_id);
    print_kv('Run timestamp',   f_fmt_ts(SYSDATE));
    print_kv('DB user',         NVL(v_db_user, '?'));
    print_kv('DB instance',     NVL(v_instance_name, '?'));
    print_kv('Business date',   f_fmt_ts(v_business_date));
    DBMS_OUTPUT.PUT_LINE(RPAD('=', 78, '='));

    -- 3.6 Echo des parametres effectifs (BRD §6.3) ---------------------
    print_section_header('PARAMS', 'Effective parameters (echo)');

    -- 3.6.a Perimetre temporel
    print_kv('p_date_from',                 f_fmt_ts(v_date_from));
    print_kv('p_date_to',                   f_fmt_ts(v_date_to));
    print_kv('p_as_of_date',                f_fmt_ts(v_as_of_date));

    -- 3.6.b Organisation / agence
    print_kv('p_branch_code',               NVL(p_branch_code, '<ALL>'));
    print_kv('p_branch_list.count',         TO_CHAR(
        CASE WHEN p_branch_list IS NULL THEN 0 ELSE p_branch_list.COUNT END));
    print_kv('p_department',                NVL(p_department, '<ALL>'));

    -- 3.6.c Client / compte (PII masque)
    print_kv('p_customer_no',               NVL(f_mask_pii(p_customer_no), '<ALL>'));
    print_kv('p_customer_list.count',       TO_CHAR(
        CASE WHEN p_customer_list IS NULL THEN 0 ELSE p_customer_list.COUNT END));
    print_kv('p_account_no',                NVL(f_mask_pii(p_account_no), '<ALL>'));
    print_kv('p_account_list.count',        TO_CHAR(
        CASE WHEN p_account_list IS NULL THEN 0 ELSE p_account_list.COUNT END));
    print_kv('p_customer_segment',          NVL(p_customer_segment, '<ALL>'));

    -- 3.6.d Produits / modules
    print_kv('p_module',                    NVL(p_module, '<ALL>'));
    print_kv('p_product_list.count',        TO_CHAR(
        CASE WHEN p_product_list IS NULL THEN 0 ELSE p_product_list.COUNT END));
    print_kv('p_account_class_list.count',  TO_CHAR(
        CASE WHEN p_account_class_list IS NULL THEN 0 ELSE p_account_class_list.COUNT END));

    -- 3.6.e Devises
    print_kv('p_ccy',                       NVL(p_ccy, '<ALL>'));
    print_kv('p_ccy_list.count',            TO_CHAR(
        CASE WHEN p_ccy_list IS NULL THEN 0 ELSE p_ccy_list.COUNT END));
    print_kv('p_include_fcy_only',          p_include_fcy_only);

    -- 3.6.f Seuils de materialite
    print_kv('p_materiality_lcy',           f_fmt_lcy(p_materiality_lcy));
    print_kv('p_materiality_impact_lcy',    f_fmt_lcy(p_materiality_impact_lcy));
    print_kv('p_materiality_critical_lcy',  f_fmt_lcy(p_materiality_critical_lcy));
    print_kv('p_min_days_overdue',          TO_CHAR(p_min_days_overdue));
    print_kv('p_min_days_dormant',          TO_CHAR(p_min_days_dormant));

    -- 3.6.g Mode et verbosite
    print_kv('p_mode',                      p_mode);
    print_kv('p_top_n',                     TO_CHAR(p_top_n));
    print_kv('p_verbose',                   p_verbose);
    print_kv('p_include_perf_log',          p_include_perf_log);
    print_kv('p_mask_pii',                  p_mask_pii);
    print_kv('p_language',                  p_language);

    -- 3.6.h Filtrage de sections
    print_kv('p_sections_include.count',    TO_CHAR(
        CASE WHEN p_sections_include IS NULL THEN 0 ELSE p_sections_include.COUNT END));
    print_kv('p_sections_exclude.count',    TO_CHAR(
        CASE WHEN p_sections_exclude IS NULL THEN 0 ELSE p_sections_exclude.COUNT END));

    -- 3.6.i Parametres anti-fraude (BRD §15.6)
    print_kv('p_structuring_threshold_lcy', f_fmt_lcy(p_structuring_threshold_lcy));
    print_kv('p_reversal_window_hours',     TO_CHAR(p_reversal_window_hours));
    print_kv('p_business_hours_from',       p_business_hours_from);
    print_kv('p_business_hours_to',         p_business_hours_to);
    print_kv('p_weekend_days',              p_weekend_days);
    print_kv('p_holiday_list.count',        TO_CHAR(
        CASE WHEN p_holiday_list IS NULL THEN 0 ELSE p_holiday_list.COUNT END));
    print_kv('p_tamper_window_hours',       TO_CHAR(p_tamper_window_hours));
    print_kv('p_cycle_max_length',          TO_CHAR(p_cycle_max_length));
    print_kv('p_tol_days_backdate',         TO_CHAR(p_tol_days_backdate));
    print_kv('p_exclude_technical_users.count', TO_CHAR(
        CASE WHEN p_exclude_technical_users IS NULL THEN 0
             ELSE p_exclude_technical_users.COUNT END));

    print_section_footer('PARAMS', 0);

    log_info('Section 3 (init & echo) completed. run_id=' || v_run_id);

    -- =================================================================
    -- SECTION 4 - VERIFICATION DE L'ENVIRONNEMENT
    -- -----------------------------------------------------------------
    -- 4.1 Version Oracle : imprime la banniere V$VERSION. L'absence
    --     d'acces est degradee en [WARN] (le script continue).
    -- 4.2 Presence / privileges SELECT sur les tables FCUBS attendues.
    --     - Liste "requise"   : manquant => [WARN] + couverture reduite.
    --     - Liste "optionnelle" : manquant => [INFO] (les sections
    --       concernees seront automatiquement neutralisees).
    -- 4.3 Resume de couverture (nb tables OK/miss) + origine de la
    --     date metier.
    -- NB : sonde = 'SELECT COUNT(*) FROM <t> WHERE ROWNUM <= 0'. Cette
    -- sonde ne ramene jamais de ligne de donnees (ROWNUM <= 0) et reste
    -- instantanee, ce qui la rend safe pour un audit read-only.
    -- =================================================================
    DECLARE
        l_tab_req     SYS.ODCIVARCHAR2LIST;
        l_tab_opt     SYS.ODCIVARCHAR2LIST;
        l_status      VARCHAR2(30);
        l_n_req_ok    PLS_INTEGER := 0;
        l_n_req_miss  PLS_INTEGER := 0;
        l_n_opt_ok    PLS_INTEGER := 0;
        l_n_opt_miss  PLS_INTEGER := 0;
        l_banner      VARCHAR2(200);

        -- f_probe : execute une sonde SELECT COUNT(*) sur une table.
        -- Renvoie 'OK' si accessible, 'MISSING' / 'NO_PRIV' /
        -- 'STALE_LINK' / 'ERR<code>' sinon.
        FUNCTION f_probe(p_tab IN VARCHAR2) RETURN VARCHAR2 IS
            l_x PLS_INTEGER;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT COUNT(*) FROM ' || p_tab || ' WHERE ROWNUM <= 0'
                INTO l_x;
            RETURN 'OK';
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -942 THEN
                    RETURN 'MISSING';
                ELSIF SQLCODE = -1031 THEN
                    RETURN 'NO_PRIV';
                ELSIF SQLCODE = -980 THEN
                    RETURN 'STALE_LINK';
                ELSE
                    RETURN 'ERR' || TO_CHAR(SQLCODE);
                END IF;
        END f_probe;
    BEGIN
        IF NOT f_section_enabled('ENV') THEN
            log_info('Section ENV skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('ENV', 'Environment verification');

            -- 4.1 Version Oracle ---------------------------------------
            l_banner := safe_scalar_varchar2('ENV',
                'SELECT BANNER FROM V$VERSION WHERE BANNER LIKE ''Oracle%'' AND ROWNUM = 1');
            IF l_banner IS NULL THEN
                l_banner := safe_scalar_varchar2('ENV',
                    'SELECT PRODUCT || '' '' || VERSION '
                    || ' FROM PRODUCT_COMPONENT_VERSION '
                    || ' WHERE PRODUCT LIKE ''Oracle%'' AND ROWNUM = 1');
            END IF;
            print_kv('Oracle banner', NVL(l_banner, '<unknown>'));
            IF l_banner IS NULL THEN
                log_warn('Oracle version banner unavailable (V$VERSION privilege missing?).');
            END IF;

            -- 4.2.a Tables FCUBS REQUISES ------------------------------
            l_tab_req := SYS.ODCIVARCHAR2LIST(
                'SMTB_BANK_PARAMETERS',        -- date metier
                'STTM_CUST_ACCOUNT',           -- comptes (detail)
                'STTM_CUST_ACCOUNT_MASTER',    -- comptes (master)
                'STTM_CUSTOMER',               -- clients
                'STTM_CURRENCY',               -- devises
                'STTM_BRANCH',                 -- agences
                'GLTM_MASTER',                 -- referentiel GL
                'GLTB_GL_BAL',                 -- soldes GL
                'ACTB_HISTORY'                 -- lignes comptables
            );
            FOR i IN 1 .. l_tab_req.COUNT LOOP
                l_status := f_probe(l_tab_req(i));
                IF l_status = 'OK' THEN
                    l_n_req_ok := l_n_req_ok + 1;
                    print_kv('REQ ' || l_tab_req(i), 'OK');
                ELSE
                    l_n_req_miss := l_n_req_miss + 1;
                    print_kv('REQ ' || l_tab_req(i), l_status);
                    log_warn('Required FCUBS object not accessible: '
                        || l_tab_req(i) || ' status=' || l_status);
                END IF;
            END LOOP;

            -- 4.2.b Tables FCUBS OPTIONNELLES --------------------------
            l_tab_opt := SYS.ODCIVARCHAR2LIST(
                'STTM_ACCOUNT_CLASS',
                'STTM_PRODUCT',
                'CLTB_CONTRACT_MASTER',
                'CLTB_SCHEDULE',
                'CLTB_SCHEDULES_HIST',
                'LDTB_CONTRACT_MASTER',
                'LDTB_SCHEDULE',
                'SITB_CONTRACTS_MASTER',
                'SITB_EXECUTION_LOG',
                'ICTB_ACC_LIQ_DETAILS',
                'ICTB_LIQUIDATION',
                'ICTB_ACCOUNTS',
                'MOTB_CONTRACT_MASTER',
                'FXTB_CONTRACT_MASTER',
                'SMTB_USER',
                'SMTB_USER_ROLE',
                'SMTB_ROLE_DETAIL',
                'ACVW_ALL_AC_ENTRIES'
            );
            FOR i IN 1 .. l_tab_opt.COUNT LOOP
                l_status := f_probe(l_tab_opt(i));
                IF l_status = 'OK' THEN
                    l_n_opt_ok := l_n_opt_ok + 1;
                ELSE
                    l_n_opt_miss := l_n_opt_miss + 1;
                    log_info('Optional FCUBS object not accessible: '
                        || l_tab_opt(i) || ' status=' || l_status);
                END IF;
            END LOOP;

            -- 4.3 Synthese ---------------------------------------------
            print_kv('Required tables OK',
                TO_CHAR(l_n_req_ok) || '/' || TO_CHAR(l_tab_req.COUNT));
            print_kv('Required tables missing', TO_CHAR(l_n_req_miss));
            print_kv('Optional tables OK',
                TO_CHAR(l_n_opt_ok) || '/' || TO_CHAR(l_tab_opt.COUNT));
            print_kv('Optional tables missing', TO_CHAR(l_n_opt_miss));
            print_kv('Business date source',
                CASE WHEN p_as_of_date IS NOT NULL THEN 'p_as_of_date (override)'
                     ELSE 'SMTB_BANK_PARAMETERS or SYSDATE fallback'
                END);

            IF l_n_req_miss > 0 THEN
                log_warn('Required FCUBS tables are missing; audit coverage is reduced.');
            END IF;

            print_section_footer('ENV', 0);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('ENV', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('ENV', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION 5 - KPIs GLOBAUX ET COUVERTURE PCEC
    -- -----------------------------------------------------------------
    -- 5.1 Volumetrie referentielle : nombre de clients, de comptes
    --     client, de GL, d'agences et de devises actives.
    -- 5.2 Activite comptable sur la fenetre [v_date_from ; v_date_to] :
    --     nombre de lignes, somme des debits / credits en LCY, ecart
    --     partie-double a titre indicatif (doit etre nul sur un
    --     systeme sain - toute divergence est reprise dans le finding
    --     principal de S16/S17).
    -- 5.3 Couverture PCEC (COBAC R-98/01) : part des GL dont la
    --     premiere decimale correspond a une classe CEMAC valide
    --     (1 a 9). Un taux < 95 % declenche un [WARN] global.
    -- 5.4 Breakdown par classe PCEC (1..9).
    -- =================================================================
    DECLARE
        l_n_customer  NUMBER;
        l_n_cust_acc  NUMBER;
        l_n_gl        NUMBER;
        l_n_branch    NUMBER;
        l_n_ccy       NUMBER;
        l_n_lines     NUMBER;
        l_sum_dr      NUMBER;
        l_sum_cr      NUMBER;
        l_pcec_total  NUMBER;
        l_pcec_valid  NUMBER;
        l_coverage    NUMBER;
        l_cur         SYS_REFCURSOR;
        l_class       VARCHAR2(1);
        l_class_n     NUMBER;
    BEGIN
        IF NOT f_section_enabled('KPI') THEN
            log_info('Section KPI skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('KPI', 'Global KPIs & PCEC coverage');

            -- 5.1 Volumetrie referentielle -----------------------------
            l_n_customer := safe_count('KPI', 'SELECT COUNT(*) FROM STTM_CUSTOMER');
            l_n_cust_acc := safe_count('KPI', 'SELECT COUNT(*) FROM STTM_CUST_ACCOUNT');
            l_n_gl       := safe_count('KPI', 'SELECT COUNT(*) FROM GLTM_MASTER');
            l_n_branch   := safe_count('KPI', 'SELECT COUNT(*) FROM STTM_BRANCH');
            l_n_ccy      := safe_count('KPI', 'SELECT COUNT(*) FROM STTM_CURRENCY');

            print_kv('Customers #',         NVL(TO_CHAR(l_n_customer), 'N/A'));
            print_kv('Customer accounts #', NVL(TO_CHAR(l_n_cust_acc), 'N/A'));
            print_kv('GL accounts #',       NVL(TO_CHAR(l_n_gl),       'N/A'));
            print_kv('Branches #',          NVL(TO_CHAR(l_n_branch),   'N/A'));
            print_kv('Currencies #',        NVL(TO_CHAR(l_n_ccy),      'N/A'));

            -- 5.2 Activite comptable sur la periode --------------------
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT COUNT(*), '
                    || ' NVL(SUM(DR_AMOUNT_LCY),0), '
                    || ' NVL(SUM(CR_AMOUNT_LCY),0) '
                    || ' FROM ACTB_HISTORY '
                    || ' WHERE TRN_DT BETWEEN :1 AND :2'
                    INTO l_n_lines, l_sum_dr, l_sum_cr
                    USING v_date_from, v_date_to;
            EXCEPTION
                WHEN OTHERS THEN
                    log_error('KPI', 'Journal scan failed: ' || SUBSTR(SQLERRM, 1, 200));
                    l_n_lines := NULL; l_sum_dr := NULL; l_sum_cr := NULL;
            END;

            print_kv('Journal period',  f_fmt_ts(v_date_from) || ' -> ' || f_fmt_ts(v_date_to));
            print_kv('Journal lines #', NVL(TO_CHAR(l_n_lines), 'N/A'));
            print_kv('Sum DR LCY',      f_fmt_lcy(l_sum_dr));
            print_kv('Sum CR LCY',      f_fmt_lcy(l_sum_cr));
            print_kv('Partie double DR-CR',
                CASE
                    WHEN l_sum_dr IS NULL OR l_sum_cr IS NULL THEN 'N/A'
                    ELSE f_fmt_lcy(l_sum_dr - l_sum_cr)
                END);

            IF l_sum_dr IS NOT NULL AND l_sum_cr IS NOT NULL
               AND ABS(l_sum_dr - l_sum_cr) > NVL(p_materiality_lcy, 0) THEN
                log_warn('Global DR vs CR mismatch on period : '
                    || f_fmt_lcy(l_sum_dr - l_sum_cr) || ' LCY (see S16).');
            END IF;

            -- 5.3 Couverture PCEC --------------------------------------
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT COUNT(*), '
                    || ' SUM(CASE WHEN SUBSTR(GL_CODE,1,1) '
                    || '         IN (''1'',''2'',''3'',''4'',''5'',''6'',''7'',''8'',''9'') '
                    || '    THEN 1 ELSE 0 END) '
                    || ' FROM GLTM_MASTER'
                    INTO l_pcec_total, l_pcec_valid;
            EXCEPTION
                WHEN OTHERS THEN
                    log_error('KPI', 'PCEC coverage scan failed: ' || SUBSTR(SQLERRM, 1, 200));
                    l_pcec_total := NULL; l_pcec_valid := NULL;
            END;

            IF NVL(l_pcec_total, 0) > 0 THEN
                l_coverage := ROUND(100 * NVL(l_pcec_valid, 0) / NULLIF(l_pcec_total, 0), 2);
            ELSE
                l_coverage := NULL;
            END IF;

            print_kv('PCEC GL total',      NVL(TO_CHAR(l_pcec_total), 'N/A'));
            print_kv('PCEC GL CEMAC-like', NVL(TO_CHAR(l_pcec_valid), 'N/A'));
            print_kv('PCEC coverage %',
                CASE WHEN l_coverage IS NULL THEN 'N/A'
                     ELSE TO_CHAR(l_coverage, 'FM990.00',
                                  'NLS_NUMERIC_CHARACTERS=''.,''')
                END);

            IF l_coverage IS NOT NULL AND l_coverage < 95 THEN
                log_warn('PCEC coverage below 95% ('
                    || TO_CHAR(l_coverage, 'FM990.00',
                               'NLS_NUMERIC_CHARACTERS=''.,''')
                    || '%) - some GL codes do not follow COBAC R-98/01.');
            END IF;

            -- 5.4 Breakdown par classe PCEC ----------------------------
            print_line('PCEC class breakdown (COBAC R-98/01 classes 1..9):');
            BEGIN
                OPEN l_cur FOR
                    'SELECT SUBSTR(GL_CODE,1,1) AS CLASS_ID, COUNT(*) AS N '
                    || ' FROM GLTM_MASTER '
                    || ' WHERE SUBSTR(GL_CODE,1,1) BETWEEN ''1'' AND ''9'' '
                    || ' GROUP BY SUBSTR(GL_CODE,1,1) '
                    || ' ORDER BY 1';
                LOOP
                    FETCH l_cur INTO l_class, l_class_n;
                    EXIT WHEN l_cur%NOTFOUND;
                    print_kv('  Class ' || l_class,
                        TO_CHAR(l_class_n) || ' GL accounts');
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('KPI', 'PCEC breakdown failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_section_footer('KPI', 0);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('KPI', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('KPI', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S01 - DECOUVERTS NON CAPTURES (overdraft leakage)
    -- -----------------------------------------------------------------
    -- Objectif :
    --   Detecte les comptes clients presentant un solde debiteur (en
    --   LCY) a la date d'arrete, dont la classe de compte n'est pas
    --   configuree comme "decouvert autorise". Ce sont des positions
    --   ou la banque devrait percevoir un interet debiteur mais ou la
    --   configuration produit l'empeche (leakage).
    --
    -- Impact indicatif (en LCY) :
    --   approx_leakage = ABS(BAL_LCY) * 0.05 * (nb_jours_periode / 360)
    --
    --   0.05   : taux annuel indicatif (cf. BRD §7.A).
    --   360    : base jours standard marche CEMAC.
    --   L'impact reel depend du produit IC effectivement configure ;
    --   les findings sont a confronter aux extractions ICTB_*.
    -- =================================================================
    DECLARE
        l_cur        SYS_REFCURSOR;
        l_ac_no      VARCHAR2(30);
        l_cust_no    VARCHAR2(20);
        l_branch     VARCHAR2(10);
        l_ccy        VARCHAR2(3);
        l_accl       VARCHAR2(10);
        l_bal_lcy    NUMBER;
        l_n_findings PLS_INTEGER := 0;
        l_days       NUMBER;
        l_impact     NUMBER;
        l_rate_ind   CONSTANT NUMBER := 0.05;
        l_base       CONSTANT NUMBER := 360;
        l_sql        VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S01') THEN
            log_info('Section S01 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S01',
                'Overdraft leakage (uncaptured debit balances)');

            l_days := GREATEST(1, (v_date_to - v_date_from) + 1);

            -- Requete dynamique : evite la resolution de STTM_CUST_ACCOUNT
            -- au PARSE du bloc (defensif - cf. §4 ENV).
            l_sql :=
                'SELECT CUST_AC_NO, CUST_NO, BRANCH_CODE, CCY, ACCOUNT_CLASS, '
             || '       NVL(LCY_CURR_BALANCE,0) AS BAL_LCY '
             || '  FROM STTM_CUST_ACCOUNT '
             || ' WHERE NVL(LCY_CURR_BALANCE,0) < 0 '
             || '   AND UPPER(NVL(ACCOUNT_CLASS,''?'')) NOT IN '
             || '       (''OD'',''OVDFT'',''TOD'',''ODRA'',''ODCORP'',''ODSME'') '
             || '   AND (:p_branch IS NULL OR BRANCH_CODE = :p_branch) '
             || '   AND (:p_cust   IS NULL OR CUST_NO     = :p_cust) '
             || '   AND (:p_acc    IS NULL OR CUST_AC_NO  = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR CCY         = :p_ccy) '
             || ' ORDER BY ABS(NVL(LCY_CURR_BALANCE,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_cust_no, l_branch, l_ccy, l_accl, l_bal_lcy;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_findings >= NVL(p_top_n, 50);

                    l_impact := ROUND(
                        ABS(l_bal_lcy) * l_rate_ind * l_days / l_base, 2);

                    IF l_impact >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S01',
                            p_code       => 'RA-S01-01',
                            p_severity   => 'MEDIUM',
                            p_message    => 'Negative LCY balance on non-overdraft '
                                         || 'account_class=' || NVL(l_accl, '?')
                                         || ' ccy=' || NVL(l_ccy, '?')
                                         || ' bal=' || f_fmt_lcy(l_bal_lcy)
                                         || ' days=' || TO_CHAR(l_days),
                            p_entity     => l_ac_no,
                            p_impact_lcy => l_impact,
                            p_evidence   => 'BR=' || NVL(l_branch, '?')
                                         || ' CUST=' || NVL(f_mask_pii(l_cust_no), '?')
                        );
                        l_n_findings := l_n_findings + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S01',
                        'Main query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('Indicative rate',       TO_CHAR(l_rate_ind));
            print_kv('Day-count base',        TO_CHAR(l_base));
            print_kv('Period length (days)',  TO_CHAR(l_days));
            print_kv('Top-N cap',             TO_CHAR(NVL(p_top_n, 50)));

            print_section_footer('S01', l_n_findings);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S01', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S01', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S02 - TOD OVERRUN / EXPIRED WITHOUT RENEWAL
    -- -----------------------------------------------------------------
    -- [F-010] ABS(solde debiteur) > TOD_LIMIT (depassement autorise)
    -- [F-011] TOD_END_DATE < v_as_of_date mais solde toujours debiteur
    --
    -- Sources : STTM_CUST_ACCOUNT (TOD_LIMIT, TOD_START_DATE, TOD_END_DATE,
    -- LCY_CURR_BALANCE, ACY_CURR_BALANCE).
    -- Impact indicatif [F-010] : (|bal| - TOD_LIMIT) * taux_penal
    --                            * nb_jours / 365
    -- Taux penal indicatif : 10 % annuel (BRD §7.A S02).
    -- Severite : HIGH par defaut, CRITICAL si depassement > 200 %.
    -- =================================================================
    DECLARE
        l_cur        SYS_REFCURSOR;
        l_ac_no      VARCHAR2(30);
        l_cust_no    VARCHAR2(20);
        l_branch     VARCHAR2(10);
        l_ccy        VARCHAR2(3);
        l_accl       VARCHAR2(10);
        l_bal_lcy    NUMBER;
        l_tod_limit  NUMBER;
        l_tod_start  DATE;
        l_tod_end    DATE;
        l_excess     NUMBER;
        l_ratio      NUMBER;
        l_days       NUMBER;
        l_impact     NUMBER;
        l_sev        VARCHAR2(10);
        l_n_010      PLS_INTEGER := 0;
        l_n_011      PLS_INTEGER := 0;
        l_rate_pen   CONSTANT NUMBER := 0.10;
        l_base       CONSTANT NUMBER := 365;
        l_sql        VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S02') THEN
            log_info('Section S02 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S02',
                'TOD limits overrun or expired without renewal');

            l_days := GREATEST(1, (v_date_to - v_date_from) + 1);

            l_sql :=
                'SELECT CUST_AC_NO, CUST_NO, BRANCH_CODE, CCY, ACCOUNT_CLASS, '
             || '       NVL(LCY_CURR_BALANCE,0)            AS BAL_LCY, '
             || '       NVL(TOD_LIMIT,0)                   AS TOD_LIM, '
             || '       TOD_START_DATE, TOD_END_DATE '
             || '  FROM STTM_CUST_ACCOUNT '
             || ' WHERE NVL(LCY_CURR_BALANCE,0) < 0 '
             || '   AND (NVL(TOD_LIMIT,0) > 0 OR TOD_END_DATE IS NOT NULL) '
             || '   AND (:p_branch IS NULL OR BRANCH_CODE = :p_branch) '
             || '   AND (:p_cust   IS NULL OR CUST_NO     = :p_cust) '
             || '   AND (:p_acc    IS NULL OR CUST_AC_NO  = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR CCY         = :p_ccy) '
             || ' ORDER BY ABS(NVL(LCY_CURR_BALANCE,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_cust_no, l_branch, l_ccy, l_accl,
                        l_bal_lcy, l_tod_limit, l_tod_start, l_tod_end;
                    EXIT WHEN l_cur%NOTFOUND
                           OR (l_n_010 + l_n_011) >= NVL(p_top_n, 50);

                    -- [F-010] Overrun de TOD
                    IF l_tod_limit > 0
                       AND ABS(l_bal_lcy) > l_tod_limit THEN
                        l_excess := ABS(l_bal_lcy) - l_tod_limit;
                        l_ratio  := ROUND(100 * l_excess
                                          / NULLIF(l_tod_limit, 0), 2);
                        l_impact := ROUND(l_excess * l_rate_pen
                                          * l_days / l_base, 2);
                        l_sev    := CASE WHEN l_ratio > 200 THEN 'CRITICAL'
                                         ELSE 'HIGH' END;

                        IF l_impact >= NVL(p_materiality_lcy, 0) THEN
                            print_finding(
                                p_section    => 'S02',
                                p_code       => 'RA-S02-F010',
                                p_severity   => l_sev,
                                p_message    => 'TOD overrun: bal=' || f_fmt_lcy(l_bal_lcy)
                                             || ' limit=' || f_fmt_lcy(l_tod_limit)
                                             || ' excess=' || f_fmt_lcy(l_excess)
                                             || ' ratio=' || NVL(TO_CHAR(l_ratio,'FM9990.00',
                                                  'NLS_NUMERIC_CHARACTERS=''.,'''),'N/A')
                                             || '%',
                                p_entity     => l_ac_no,
                                p_impact_lcy => l_impact,
                                p_evidence   => 'BR=' || NVL(l_branch,'?')
                                             || ' CUST=' || NVL(f_mask_pii(l_cust_no),'?')
                                             || ' CCY=' || NVL(l_ccy,'?')
                                             || ' ACCL=' || NVL(l_accl,'?')
                            );
                            l_n_010 := l_n_010 + 1;
                        END IF;
                    END IF;

                    -- [F-011] TOD expiree mais solde debiteur
                    IF l_tod_end IS NOT NULL
                       AND l_tod_end < v_as_of_date THEN
                        l_impact := ROUND(ABS(l_bal_lcy) * l_rate_pen
                                          * l_days / l_base, 2);
                        IF l_impact >= NVL(p_materiality_lcy, 0) THEN
                            print_finding(
                                p_section    => 'S02',
                                p_code       => 'RA-S02-F011',
                                p_severity   => 'HIGH',
                                p_message    => 'Expired TOD still used: tod_end='
                                             || f_fmt_ts(l_tod_end)
                                             || ' bal=' || f_fmt_lcy(l_bal_lcy)
                                             || ' limit=' || f_fmt_lcy(l_tod_limit),
                                p_entity     => l_ac_no,
                                p_impact_lcy => l_impact,
                                p_evidence   => 'BR=' || NVL(l_branch,'?')
                                             || ' CUST=' || NVL(f_mask_pii(l_cust_no),'?')
                                             || ' CCY=' || NVL(l_ccy,'?')
                            );
                            l_n_011 := l_n_011 + 1;
                        END IF;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S02',
                        'Main query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-010 findings (overrun)', TO_CHAR(l_n_010));
            print_kv('F-011 findings (expired)', TO_CHAR(l_n_011));
            print_kv('Penal rate (annual)',      TO_CHAR(l_rate_pen));
            print_kv('Day-count base',           TO_CHAR(l_base));

            print_section_footer('S02', l_n_010 + l_n_011);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S02', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S02', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S03 - DORMANT ACCOUNTS WITH ACCRUALS OR ACTIVITY
    -- -----------------------------------------------------------------
    -- [F-020] Comptes dormants avec interets/charges accrues non nulles
    --         -> risque de revenu/charge non apure (PCEC 2 / 38).
    -- [F-021] Comptes dormants avec mouvements sur la periode
    --         -> suspicion AML/fraude (a referer au module dedie).
    --
    -- Sources :
    --   - STTM_CUST_ACCOUNT : AC_STAT_DORMANT ('Y' = dormant)
    --   - ACTB_HISTORY       : mouvements sur [v_date_from; v_date_to]
    --   - ICTB_ACCRUALS_TEMP : accruals (optionnel, peut etre absent)
    --
    -- En l'absence de ICTB_ACCRUALS_TEMP, [F-020] est journalise comme
    -- limitation et la detection se restreint a [F-021].
    -- =================================================================
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_ac_no     VARCHAR2(30);
        l_cust_no   VARCHAR2(20);
        l_branch    VARCHAR2(10);
        l_ccy       VARCHAR2(3);
        l_val_n     NUMBER;
        l_val_lcy   NUMBER;
        l_n_020     PLS_INTEGER := 0;
        l_n_021     PLS_INTEGER := 0;
        l_sql       VARCHAR2(4000);
        l_days      NUMBER;
    BEGIN
        IF NOT f_section_enabled('S03') THEN
            log_info('Section S03 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S03',
                'Dormant accounts with accruals or unexpected activity');

            l_days := GREATEST(1, (v_date_to - v_date_from) + 1);

            -- [F-020] Dormants + accruals non nuls ------------------
            l_sql :=
                'SELECT a.CUST_AC_NO, a.CUST_NO, a.BRANCH_CODE, a.CCY, '
             || '       NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) AS ACCR_LCY '
             || '  FROM STTM_CUST_ACCOUNT a '
             || '  JOIN ICTB_ACCRUALS_TEMP i '
             || '    ON i.ACCOUNT = a.CUST_AC_NO '
             || ' WHERE NVL(a.AC_STAT_DORMANT,''N'') = ''Y'' '
             || '   AND (:p_branch IS NULL OR a.BRANCH_CODE = :p_branch) '
             || '   AND (:p_cust   IS NULL OR a.CUST_NO     = :p_cust) '
             || '   AND (:p_acc    IS NULL OR a.CUST_AC_NO  = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR a.CCY         = :p_ccy) '
             || ' GROUP BY a.CUST_AC_NO, a.CUST_NO, a.BRANCH_CODE, a.CCY '
             || ' HAVING NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) > 0 '
             || ' ORDER BY NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_cust_no, l_branch, l_ccy, l_val_lcy;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_020 >= NVL(p_top_n, 50);

                    IF l_val_lcy >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S03',
                            p_code       => 'RA-S03-F020',
                            p_severity   => 'MEDIUM',
                            p_message    => 'Dormant account with non-zero accrual sum='
                                         || f_fmt_lcy(l_val_lcy),
                            p_entity     => l_ac_no,
                            p_impact_lcy => l_val_lcy,
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                                         || ' CUST=' || NVL(f_mask_pii(l_cust_no),'?')
                                         || ' CCY=' || NVL(l_ccy,'?')
                        );
                        l_n_020 := l_n_020 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S03 F-020 unavailable: ICTB_ACCRUALS_TEMP '
                        || 'not queryable (' || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            -- [F-021] Dormants + mouvements sur periode -------------
            l_sql :=
                'SELECT a.CUST_AC_NO, a.CUST_NO, a.BRANCH_CODE, a.CCY, '
             || '       COUNT(*) AS N_MOV, '
             || '       NVL(SUM(ABS(NVL(h.LCY_AMOUNT,0))),0) AS VOL_LCY '
             || '  FROM STTM_CUST_ACCOUNT a '
             || '  JOIN ACTB_HISTORY h '
             || '    ON h.AC_NO = a.CUST_AC_NO '
             || ' WHERE NVL(a.AC_STAT_DORMANT,''N'') = ''Y'' '
             || '   AND h.TRN_DT BETWEEN :d1 AND :d2 '
             || '   AND (:p_branch IS NULL OR a.BRANCH_CODE = :p_branch) '
             || '   AND (:p_cust   IS NULL OR a.CUST_NO     = :p_cust) '
             || '   AND (:p_acc    IS NULL OR a.CUST_AC_NO  = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR a.CCY         = :p_ccy) '
             || ' GROUP BY a.CUST_AC_NO, a.CUST_NO, a.BRANCH_CODE, a.CCY '
             || ' ORDER BY NVL(SUM(ABS(NVL(h.LCY_AMOUNT,0))),0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_date_from, v_date_to,
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_cust_no, l_branch, l_ccy, l_val_n, l_val_lcy;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_021 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S03',
                        p_code       => 'RA-S03-F021',
                        p_severity   => 'HIGH',
                        p_message    => 'Dormant account with activity on period : '
                                     || TO_CHAR(l_val_n) || ' moves, vol='
                                     || f_fmt_lcy(l_val_lcy)
                                     || ' (refer AML module)',
                        p_entity     => l_ac_no,
                        p_impact_lcy => l_val_lcy,
                        p_evidence   => 'BR=' || NVL(l_branch,'?')
                                     || ' CUST=' || NVL(f_mask_pii(l_cust_no),'?')
                                     || ' CCY=' || NVL(l_ccy,'?')
                                     || ' DAYS=' || TO_CHAR(l_days)
                    );
                    l_n_021 := l_n_021 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S03',
                        'Movements query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-020 findings (accruals)',  TO_CHAR(l_n_020));
            print_kv('F-021 findings (activity)',  TO_CHAR(l_n_021));

            print_section_footer('S03', l_n_020 + l_n_021);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S03', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S03', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S04 - ACCOUNT CHARGES WAIVED BEYOND POLICY THRESHOLDS
    -- -----------------------------------------------------------------
    -- [F-030] Waivers recurrents par compte (volume de remise).
    -- [F-032] Concentration de waivers par utilisateur (top N).
    --
    -- Sources :
    --   - ICTB_LIQ_DETAILS : colonne waiver (nom variable selon version
    --                        FCUBS ; on essaie WAIVED_AMOUNT puis
    --                        WAIVER_AMOUNT ; log_warn si aucune ne
    --                        repond).
    --   - Periode : LIQUIDATION_DATE / VALUE_DATE dans [date_from; date_to].
    --
    -- Impact LCY : somme waived.
    -- Severite : MEDIUM, HIGH si ratio waived / total > 30 % ou
    -- concentration utilisateur > 50 %.
    -- =================================================================
    DECLARE
        l_cur        SYS_REFCURSOR;
        l_col_waiver VARCHAR2(30) := NULL;
        l_sql        VARCHAR2(4000);
        l_key        VARCHAR2(200);
        l_sum_w      NUMBER;
        l_sum_t      NUMBER;
        l_ratio      NUMBER;
        l_n          NUMBER;
        l_n_030      PLS_INTEGER := 0;
        l_n_032      PLS_INTEGER := 0;
        l_sev        VARCHAR2(10);

        -- f_col_exists : detecte l'existence d'une colonne sur une
        -- table accessible. Utilise ALL_TAB_COLUMNS.
        FUNCTION f_col_exists(p_tab IN VARCHAR2, p_col IN VARCHAR2)
            RETURN BOOLEAN IS
            l_x PLS_INTEGER;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT COUNT(*) FROM ALL_TAB_COLUMNS '
                || ' WHERE TABLE_NAME = :1 AND COLUMN_NAME = :2'
                INTO l_x USING UPPER(p_tab), UPPER(p_col);
            RETURN (NVL(l_x, 0) > 0);
        EXCEPTION
            WHEN OTHERS THEN
                RETURN FALSE;
        END f_col_exists;
    BEGIN
        IF NOT f_section_enabled('S04') THEN
            log_info('Section S04 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S04',
                'Charge waivers beyond policy thresholds');

            -- Detection du nom de colonne waiver reel.
            IF f_col_exists('ICTB_LIQ_DETAILS', 'WAIVED_AMOUNT') THEN
                l_col_waiver := 'WAIVED_AMOUNT';
            ELSIF f_col_exists('ICTB_LIQ_DETAILS', 'WAIVER_AMOUNT') THEN
                l_col_waiver := 'WAIVER_AMOUNT';
            ELSIF f_col_exists('ICTB_LIQ_DETAILS', 'WAIVED_AMT') THEN
                l_col_waiver := 'WAIVED_AMT';
            END IF;

            IF l_col_waiver IS NULL THEN
                log_warn('S04 F-030/F-032: no waiver column on ICTB_LIQ_DETAILS'
                    || ' (try WAIVED_AMOUNT / WAIVER_AMOUNT / WAIVED_AMT).');
            ELSE
                print_kv('Waiver column detected', l_col_waiver);

                -- [F-030] Top waivers par compte ----------------------
                l_sql :=
                    'SELECT d.ACCOUNT, SUM(NVL(d.' || l_col_waiver || ',0)) AS W_LCY, '
                 || '       SUM(NVL(d.AMOUNT,0)) AS T_LCY, COUNT(*) AS N '
                 || '  FROM ICTB_LIQ_DETAILS d '
                 || ' WHERE NVL(d.' || l_col_waiver || ',0) > 0 '
                 || '   AND NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) '
                 || '       BETWEEN :d1 AND :d2 '
                 || '   AND (:p_acc IS NULL OR d.ACCOUNT = :p_acc) '
                 || ' GROUP BY d.ACCOUNT '
                 || ' ORDER BY SUM(NVL(d.' || l_col_waiver || ',0)) DESC';

                BEGIN
                    OPEN l_cur FOR l_sql USING
                        v_date_from, v_date_to,
                        p_account_no, p_account_no;

                    LOOP
                        FETCH l_cur INTO l_key, l_sum_w, l_sum_t, l_n;
                        EXIT WHEN l_cur%NOTFOUND
                               OR l_n_030 >= NVL(p_top_n, 50);

                        l_ratio := CASE WHEN NVL(l_sum_t,0) = 0 THEN NULL
                                        ELSE ROUND(100 * l_sum_w
                                                   / NULLIF(l_sum_t, 0), 2)
                                   END;
                        l_sev := CASE WHEN NVL(l_ratio, 0) > 30 THEN 'HIGH'
                                      ELSE 'MEDIUM' END;

                        IF l_sum_w >= NVL(p_materiality_lcy, 0) THEN
                            print_finding(
                                p_section    => 'S04',
                                p_code       => 'RA-S04-F030',
                                p_severity   => l_sev,
                                p_message    => 'Recurring waivers on charges: waived='
                                             || f_fmt_lcy(l_sum_w)
                                             || ' total=' || f_fmt_lcy(l_sum_t)
                                             || ' ratio=' || NVL(TO_CHAR(l_ratio,
                                                  'FM990.00','NLS_NUMERIC_CHARACTERS=''.,'''),
                                                  'N/A') || '%'
                                             || ' n=' || TO_CHAR(l_n),
                                p_entity     => l_key,
                                p_impact_lcy => l_sum_w,
                                p_evidence   => 'col=' || l_col_waiver
                            );
                            l_n_030 := l_n_030 + 1;
                        END IF;
                    END LOOP;
                    CLOSE l_cur;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF l_cur%ISOPEN THEN
                            CLOSE l_cur;
                        END IF;
                        log_error('S04',
                            'F-030 query failed: ' || SUBSTR(SQLERRM, 1, 200));
                END;

                -- [F-032] Concentration par utilisateur ---------------
                l_sql :=
                    'SELECT d.MAKER_ID, SUM(NVL(d.' || l_col_waiver || ',0)) AS W_LCY, '
                 || '       COUNT(*) AS N '
                 || '  FROM ICTB_LIQ_DETAILS d '
                 || ' WHERE NVL(d.' || l_col_waiver || ',0) > 0 '
                 || '   AND NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) '
                 || '       BETWEEN :d1 AND :d2 '
                 || ' GROUP BY d.MAKER_ID '
                 || ' ORDER BY SUM(NVL(d.' || l_col_waiver || ',0)) DESC';

                BEGIN
                    OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                    LOOP
                        FETCH l_cur INTO l_key, l_sum_w, l_n;
                        EXIT WHEN l_cur%NOTFOUND
                               OR l_n_032 >= NVL(p_top_n, 50);

                        IF l_sum_w >= NVL(p_materiality_lcy, 0) THEN
                            print_finding(
                                p_section    => 'S04',
                                p_code       => 'RA-S04-F032',
                                p_severity   => 'MEDIUM',
                                p_message    => 'Waiver concentration by user: waived='
                                             || f_fmt_lcy(l_sum_w)
                                             || ' n=' || TO_CHAR(l_n),
                                p_entity     => l_key,
                                p_impact_lcy => l_sum_w,
                                p_evidence   => 'col=' || l_col_waiver
                            );
                            l_n_032 := l_n_032 + 1;
                        END IF;
                    END LOOP;
                    CLOSE l_cur;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF l_cur%ISOPEN THEN
                            CLOSE l_cur;
                        END IF;
                        log_error('S04',
                            'F-032 query failed: ' || SUBSTR(SQLERRM, 1, 200));
                END;
            END IF;

            print_kv('F-030 findings (per account)', TO_CHAR(l_n_030));
            print_kv('F-032 findings (per user)',    TO_CHAR(l_n_032));

            print_section_footer('S04', l_n_030 + l_n_032);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S04', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S04', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[FATAL] Unexpected error in main BEGIN: '
            || SUBSTR(SQLERRM, 1, 400));
END;
/
