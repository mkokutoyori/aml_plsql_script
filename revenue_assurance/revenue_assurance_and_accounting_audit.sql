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
    -- Corps du rapport construit dans les sections suivantes du
    -- script. A ce stade, on imprime uniquement l'empreinte de
    -- version et on arrete proprement.
    DBMS_OUTPUT.PUT_LINE('Revenue Assurance audit - ' || C_SCRIPT_NAME || ' v' || C_SCRIPT_VERSION);
    DBMS_OUTPUT.PUT_LINE('Regulation: ' || C_REGULATION);
    DBMS_OUTPUT.PUT_LINE('Report format version: ' || C_REPORT_FORMAT_VERSION);
    DBMS_OUTPUT.PUT_LINE('Build stage: parameters declared (section 1).');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[FATAL] Unexpected error during section-1 build: ' || SQLERRM);
END;
/
