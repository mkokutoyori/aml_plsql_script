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

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[FATAL] Unexpected error in main BEGIN: '
            || SUBSTR(SQLERRM, 1, 400));
END;
/
