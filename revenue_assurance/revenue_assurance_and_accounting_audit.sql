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
    p_fx_spread_bps             NUMBER := 10;    -- Tolerance FX spread (bps) S15.

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

    -- =================================================================
    -- SECTION S05 - CREDIT BALANCES WITHOUT INTEREST ACCRUAL
    -- -----------------------------------------------------------------
    -- [F-040] Comptes clientele a forte position crediteur (LCY) pour
    --         lesquels AUCUNE ecriture d'accrual d'interet n'existe
    --         dans ICTB_ACCRUALS_TEMP. Cas typique : produit d'epargne
    --         mal parametre, regle IC desactivee, ou compte CASA
    --         remuneré mais accrual absent (benefice client non verse
    --         OU produit non reconnu cote banque).
    --
    -- Sources : STTM_CUST_ACCOUNT, ICTB_ACCRUALS_TEMP.
    -- Severite : MEDIUM.
    -- Impact indicatif (en LCY) : bal * 0.02 * nb_jours / 365
    --   (2 % annuel = taux savings indicatif CEMAC, cf. BRD §7.A).
    -- =================================================================
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_ac_no     VARCHAR2(30);
        l_cust_no   VARCHAR2(20);
        l_branch    VARCHAR2(10);
        l_ccy       VARCHAR2(3);
        l_accl      VARCHAR2(10);
        l_bal       NUMBER;
        l_impact    NUMBER;
        l_days      NUMBER;
        l_n_040     PLS_INTEGER := 0;
        l_rate_sav  CONSTANT NUMBER := 0.02;
        l_base      CONSTANT NUMBER := 365;
        l_sql       VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S05') THEN
            log_info('Section S05 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S05',
                'Credit balances without interest accrual');

            l_days := GREATEST(1, (v_date_to - v_date_from) + 1);

            l_sql :=
                'SELECT a.CUST_AC_NO, a.CUST_NO, a.BRANCH_CODE, a.CCY, '
             || '       a.ACCOUNT_CLASS, NVL(a.LCY_CURR_BALANCE,0) AS BAL_LCY '
             || '  FROM STTM_CUST_ACCOUNT a '
             || '  LEFT JOIN ( '
             || '      SELECT ACCOUNT, SUM(NVL(ACCR_AMOUNT_LCY,0)) AS ACCR '
             || '        FROM ICTB_ACCRUALS_TEMP '
             || '       GROUP BY ACCOUNT '
             || '  ) i ON i.ACCOUNT = a.CUST_AC_NO '
             || ' WHERE NVL(a.LCY_CURR_BALANCE,0) >= :m '
             || '   AND NVL(a.AC_STAT_DORMANT,''N'') = ''N'' '
             || '   AND NVL(i.ACCR,0) = 0 '
             || '   AND (:p_branch IS NULL OR a.BRANCH_CODE = :p_branch) '
             || '   AND (:p_cust   IS NULL OR a.CUST_NO     = :p_cust) '
             || '   AND (:p_acc    IS NULL OR a.CUST_AC_NO  = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR a.CCY         = :p_ccy) '
             || ' ORDER BY NVL(a.LCY_CURR_BALANCE,0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_materiality_lcy,
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_cust_no, l_branch, l_ccy, l_accl, l_bal;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_040 >= NVL(p_top_n, 50);

                    l_impact := ROUND(l_bal * l_rate_sav * l_days / l_base, 2);

                    print_finding(
                        p_section    => 'S05',
                        p_code       => 'RA-S05-F040',
                        p_severity   => 'MEDIUM',
                        p_message    => 'Credit balance without accrual: bal='
                                     || f_fmt_lcy(l_bal)
                                     || ' class=' || NVL(l_accl,'?')
                                     || ' ccy=' || NVL(l_ccy,'?')
                                     || ' days=' || TO_CHAR(l_days),
                        p_entity     => l_ac_no,
                        p_impact_lcy => l_impact,
                        p_evidence   => 'BR=' || NVL(l_branch,'?')
                                     || ' CUST=' || NVL(f_mask_pii(l_cust_no),'?')
                                     || ' rate=' || TO_CHAR(l_rate_sav)
                                     || ' base=' || TO_CHAR(l_base)
                    );
                    l_n_040 := l_n_040 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S05',
                        'Query failed (likely ICTB_ACCRUALS_TEMP missing): '
                        || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-040 findings (no accrual)', TO_CHAR(l_n_040));
            print_kv('Savings rate (annual)',       TO_CHAR(l_rate_sav));
            print_kv('Day-count base',              TO_CHAR(l_base));

            print_section_footer('S05', l_n_040);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S05', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S05', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S06 - OVERDUE CL SCHEDULES NOT YET RECOVERED
    -- -----------------------------------------------------------------
    -- [F-050] Echeances PRINCIPAL en retard (AMOUNT_DUE > AMOUNT_SETTLED).
    -- [F-051] Echeances INTERET en retard.
    -- [F-052] Echeances FRAIS / COMMISSIONS en retard.
    --
    -- Source : CLTB_SCHEDULES_DETAILS (SCHEDULE_DUE_DATE, AMOUNT_DUE,
    -- AMOUNT_SETTLED, COMPONENT, ACCOUNT_NUMBER/AC_NO).
    --
    -- Methode : SCHEDULE_DUE_DATE < v_as_of_date - p_min_days_overdue
    -- ET AMOUNT_DUE > NVL(AMOUNT_SETTLED,0).
    --
    -- Severite : HIGH par defaut, CRITICAL si age > 90 jours OU impact
    -- >= p_materiality_critical_lcy. Promotion automatique par
    -- f_promote_severity en fonction de l'impact.
    -- =================================================================
    DECLARE
        l_cur      SYS_REFCURSOR;
        l_ac_no    VARCHAR2(30);
        l_comp     VARCHAR2(30);
        l_due_dt   DATE;
        l_due_amt  NUMBER;
        l_set_amt  NUMBER;
        l_open     NUMBER;
        l_age      NUMBER;
        l_sev      VARCHAR2(10);
        l_code     VARCHAR2(20);
        l_n_050    PLS_INTEGER := 0;
        l_n_051    PLS_INTEGER := 0;
        l_n_052    PLS_INTEGER := 0;
        l_sql      VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S06') THEN
            log_info('Section S06 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S06',
                'Overdue CL schedules not yet recovered');

            l_sql :=
                'SELECT s.ACCOUNT_NUMBER, s.COMPONENT, s.SCHEDULE_DUE_DATE, '
             || '       NVL(s.AMOUNT_DUE,0)      AS DUE_A, '
             || '       NVL(s.AMOUNT_SETTLED,0)  AS SET_A '
             || '  FROM CLTB_SCHEDULES_DETAILS s '
             || ' WHERE s.SCHEDULE_DUE_DATE < (:asof - :mindays) '
             || '   AND NVL(s.AMOUNT_DUE,0) > NVL(s.AMOUNT_SETTLED,0) '
             || '   AND (:p_acc IS NULL OR s.ACCOUNT_NUMBER = :p_acc) '
             || ' ORDER BY (NVL(s.AMOUNT_DUE,0) - NVL(s.AMOUNT_SETTLED,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_as_of_date, NVL(p_min_days_overdue, 30),
                    p_account_no, p_account_no;

                LOOP
                    FETCH l_cur INTO
                        l_ac_no, l_comp, l_due_dt, l_due_amt, l_set_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR (l_n_050 + l_n_051 + l_n_052)
                              >= NVL(p_top_n, 50);

                    l_open := l_due_amt - l_set_amt;
                    l_age  := GREATEST(0, v_as_of_date - l_due_dt);

                    -- Severite initiale : HIGH, CRITICAL si >90j.
                    l_sev := CASE WHEN l_age > 90 THEN 'CRITICAL' ELSE 'HIGH' END;

                    IF l_open < NVL(p_materiality_lcy, 0) THEN
                        CONTINUE;
                    END IF;

                    IF UPPER(NVL(l_comp,'?')) IN ('PRINCIPAL','PRN','PRN_INCR') THEN
                        l_code := 'RA-S06-F050';
                        l_n_050 := l_n_050 + 1;
                    ELSIF UPPER(NVL(l_comp,'?')) IN
                            ('MAIN_INT','INTEREST','PENAL_INT','PENALTY_INT') THEN
                        l_code := 'RA-S06-F051';
                        l_n_051 := l_n_051 + 1;
                    ELSE
                        l_code := 'RA-S06-F052';
                        l_n_052 := l_n_052 + 1;
                    END IF;

                    print_finding(
                        p_section    => 'S06',
                        p_code       => l_code,
                        p_severity   => l_sev,
                        p_message    => 'Overdue CL schedule comp=' || NVL(l_comp,'?')
                                     || ' due=' || f_fmt_ts(l_due_dt)
                                     || ' age=' || TO_CHAR(l_age) || 'd'
                                     || ' open=' || f_fmt_lcy(l_open),
                        p_entity     => l_ac_no,
                        p_impact_lcy => l_open,
                        p_evidence   => 'DUE_A=' || f_fmt_lcy(l_due_amt)
                                     || ' SET_A=' || f_fmt_lcy(l_set_amt)
                    );
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S06',
                        'Query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-050 findings (principal)', TO_CHAR(l_n_050));
            print_kv('F-051 findings (interest)',  TO_CHAR(l_n_051));
            print_kv('F-052 findings (fee/chg)',   TO_CHAR(l_n_052));
            print_kv('Min days overdue',           TO_CHAR(NVL(p_min_days_overdue, 30)));

            print_section_footer('S06', l_n_050 + l_n_051 + l_n_052);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S06', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S06', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S07 - FROZEN / ON-HOLD LOANS WITH OUTSTANDING BALANCE
    -- -----------------------------------------------------------------
    -- [F-060] Prets CL geles (USER_DEFINED_STATUS) ayant un principal
    --         > 0. Risque : solde pose sans traitement en douteux.
    -- [F-061] Accruals encore comptabilises sur des contrats geles.
    --         Risque majeur : produit reconnu alors que la creance
    --         n'est pas recouvrable -> violation du principe de
    --         prudence (BRD §14, COBAC R-2000/05).
    --
    -- Sources : CLTB_ACCOUNT_MASTER (USER_DEFINED_STATUS),
    --           CLTB_ACCOUNT_COMPONENTS (COMPONENT_VALUE),
    --           ICTB_ACCRUALS_TEMP (ACCR_AMOUNT_LCY) optionnel.
    -- =================================================================
    DECLARE
        l_cur      SYS_REFCURSOR;
        l_ac       VARCHAR2(30);
        l_cust     VARCHAR2(20);
        l_br       VARCHAR2(10);
        l_ccy      VARCHAR2(3);
        l_status   VARCHAR2(20);
        l_out      NUMBER;
        l_accr     NUMBER;
        l_n_060    PLS_INTEGER := 0;
        l_n_061    PLS_INTEGER := 0;
        l_sql      VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S07') THEN
            log_info('Section S07 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S07',
                'Frozen / on-hold loans with outstanding balance');

            -- [F-060] Prets geles avec principal > 0 ---------------
            l_sql :=
                'SELECT m.ACCOUNT_NUMBER, m.CUSTOMER_NO, m.BRANCH, m.CCY, '
             || '       m.USER_DEFINED_STATUS, '
             || '       NVL(SUM(NVL(c.COMPONENT_VALUE,0)),0) AS OUT_LCY '
             || '  FROM CLTB_ACCOUNT_MASTER m '
             || '  JOIN CLTB_ACCOUNT_COMPONENTS c '
             || '    ON c.ACCOUNT_NUMBER = m.ACCOUNT_NUMBER '
             || ' WHERE UPPER(NVL(m.USER_DEFINED_STATUS,'' '')) IN '
             || '       (''FROZEN'',''HOLD'',''ON_HOLD'',''FR'',''ONHOLD'') '
             || '   AND UPPER(NVL(c.COMPONENT,'' '')) = ''PRINCIPAL'' '
             || '   AND (:p_branch IS NULL OR m.BRANCH   = :p_branch) '
             || '   AND (:p_cust   IS NULL OR m.CUSTOMER_NO = :p_cust) '
             || '   AND (:p_acc    IS NULL OR m.ACCOUNT_NUMBER = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR m.CCY      = :p_ccy) '
             || ' GROUP BY m.ACCOUNT_NUMBER, m.CUSTOMER_NO, m.BRANCH, '
             || '          m.CCY, m.USER_DEFINED_STATUS '
             || ' HAVING NVL(SUM(NVL(c.COMPONENT_VALUE,0)),0) > 0 '
             || ' ORDER BY NVL(SUM(NVL(c.COMPONENT_VALUE,0)),0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO l_ac, l_cust, l_br, l_ccy, l_status, l_out;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_060 >= NVL(p_top_n, 50);

                    IF l_out >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S07',
                            p_code       => 'RA-S07-F060',
                            p_severity   => 'HIGH',
                            p_message    => 'Frozen loan with outstanding principal='
                                         || f_fmt_lcy(l_out)
                                         || ' status=' || NVL(l_status,'?'),
                            p_entity     => l_ac,
                            p_impact_lcy => l_out,
                            p_evidence   => 'BR=' || NVL(l_br,'?')
                                         || ' CUST=' || NVL(f_mask_pii(l_cust),'?')
                                         || ' CCY=' || NVL(l_ccy,'?')
                        );
                        l_n_060 := l_n_060 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S07',
                        'F-060 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-061] Accruals sur contrats geles -----------------
            l_sql :=
                'SELECT m.ACCOUNT_NUMBER, m.CUSTOMER_NO, m.BRANCH, m.CCY, '
             || '       m.USER_DEFINED_STATUS, '
             || '       NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) AS ACCR_LCY '
             || '  FROM CLTB_ACCOUNT_MASTER m '
             || '  JOIN ICTB_ACCRUALS_TEMP i '
             || '    ON i.CONTRACT_REF_NO = m.ACCOUNT_NUMBER '
             || ' WHERE UPPER(NVL(m.USER_DEFINED_STATUS,'' '')) IN '
             || '       (''FROZEN'',''HOLD'',''ON_HOLD'',''FR'',''ONHOLD'') '
             || '   AND (:p_branch IS NULL OR m.BRANCH   = :p_branch) '
             || '   AND (:p_cust   IS NULL OR m.CUSTOMER_NO = :p_cust) '
             || '   AND (:p_acc    IS NULL OR m.ACCOUNT_NUMBER = :p_acc) '
             || '   AND (:p_ccy    IS NULL OR m.CCY      = :p_ccy) '
             || ' GROUP BY m.ACCOUNT_NUMBER, m.CUSTOMER_NO, m.BRANCH, '
             || '          m.CCY, m.USER_DEFINED_STATUS '
             || ' HAVING NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) > 0 '
             || ' ORDER BY NVL(SUM(NVL(i.ACCR_AMOUNT_LCY,0)),0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    p_branch_code, p_branch_code,
                    p_customer_no, p_customer_no,
                    p_account_no,  p_account_no,
                    p_ccy,         p_ccy;

                LOOP
                    FETCH l_cur INTO l_ac, l_cust, l_br, l_ccy, l_status, l_accr;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_061 >= NVL(p_top_n, 50);

                    IF l_accr >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S07',
                            p_code       => 'RA-S07-F061',
                            p_severity   => 'CRITICAL',
                            p_message    => 'Accruals still running on frozen loan='
                                         || f_fmt_lcy(l_accr)
                                         || ' status=' || NVL(l_status,'?'),
                            p_entity     => l_ac,
                            p_impact_lcy => l_accr,
                            p_evidence   => 'BR=' || NVL(l_br,'?')
                                         || ' CUST=' || NVL(f_mask_pii(l_cust),'?')
                                         || ' CCY=' || NVL(l_ccy,'?')
                        );
                        l_n_061 := l_n_061 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S07 F-061 unavailable: ICTB_ACCRUALS_TEMP or '
                        || 'CONTRACT_REF_NO join failed ('
                        || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            print_kv('F-060 findings (outstanding)', TO_CHAR(l_n_060));
            print_kv('F-061 findings (accruals)',    TO_CHAR(l_n_061));

            print_section_footer('S07', l_n_060 + l_n_061);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S07', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S07', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S08 - LOAN COMPONENTS PENDING LIQUIDATION
    -- -----------------------------------------------------------------
    -- [F-070] Composantes CL avec montant du > 0 mais aucune
    --         liquidation (CLTB_LIQ) enregistree sur la periode.
    -- [F-071] Liquidations rejetees / non autorisees (AUTH_STAT <> 'A'
    --         ou LIQ_STATUS = 'R') avec montant residuel.
    --
    -- Sources : CLTB_ACCOUNT_COMPONENTS, CLTB_LIQ.
    -- Severite : MEDIUM, HIGH si impact >= p_materiality_impact_lcy.
    -- =================================================================
    DECLARE
        l_cur     SYS_REFCURSOR;
        l_ref     VARCHAR2(30);
        l_comp    VARCHAR2(30);
        l_amt     NUMBER;
        l_status  VARCHAR2(10);
        l_auth    VARCHAR2(10);
        l_n_070   PLS_INTEGER := 0;
        l_n_071   PLS_INTEGER := 0;
        l_sql     VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S08') THEN
            log_info('Section S08 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S08',
                'Loan components pending liquidation');

            -- [F-070] Composantes dues sans liquidation -------------
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.COMPONENT, '
             || '       NVL(c.AMOUNT_DUE,0) AS AMT '
             || '  FROM CLTB_ACCOUNT_COMPONENTS c '
             || ' WHERE NVL(c.AMOUNT_DUE,0) > 0 '
             || '   AND NOT EXISTS ( '
             || '       SELECT 1 FROM CLTB_LIQ l '
             || '        WHERE l.CONTRACT_REF_NO = c.CONTRACT_REF_NO '
             || '          AND l.COMPONENT = c.COMPONENT '
             || '          AND l.VALUE_DATE BETWEEN :d1 AND :d2 '
             || '       ) '
             || ' ORDER BY NVL(c.AMOUNT_DUE,0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_ref, l_comp, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_070 >= NVL(p_top_n, 50);

                    IF l_amt >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S08',
                            p_code       => 'RA-S08-F070',
                            p_severity   => 'MEDIUM',
                            p_message    => 'Component due without liquidation: comp='
                                         || NVL(l_comp,'?')
                                         || ' amt=' || f_fmt_lcy(l_amt),
                            p_entity     => l_ref,
                            p_impact_lcy => l_amt,
                            p_evidence   => 'period='
                                         || f_fmt_ts(v_date_from) || '..'
                                         || f_fmt_ts(v_date_to)
                        );
                        l_n_070 := l_n_070 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S08',
                        'F-070 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-071] Liquidations rejetees / non autorisees --------
            l_sql :=
                'SELECT l.CONTRACT_REF_NO, l.COMPONENT, '
             || '       NVL(l.LIQ_AMOUNT, l.AMOUNT_SETTLED) AS AMT, '
             || '       NVL(l.LIQ_STATUS, ''?'') AS ST, '
             || '       NVL(l.AUTH_STAT,  ''?'') AS AUTH '
             || '  FROM CLTB_LIQ l '
             || ' WHERE NVL(l.VALUE_DATE, l.EVENT_DATE) BETWEEN :d1 AND :d2 '
             || '   AND ( UPPER(NVL(l.LIQ_STATUS,'' '')) IN (''R'',''REJECTED'') '
             || '         OR UPPER(NVL(l.AUTH_STAT,'' '')) = ''U'' ) '
             || '   AND NVL(l.LIQ_AMOUNT, l.AMOUNT_SETTLED) > 0 '
             || ' ORDER BY NVL(l.LIQ_AMOUNT, l.AMOUNT_SETTLED) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_ref, l_comp, l_amt, l_status, l_auth;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_071 >= NVL(p_top_n, 50);

                    IF l_amt >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S08',
                            p_code       => 'RA-S08-F071',
                            p_severity   => 'HIGH',
                            p_message    => 'Rejected/unauthorized liquidation: comp='
                                         || NVL(l_comp,'?')
                                         || ' amt=' || f_fmt_lcy(l_amt)
                                         || ' status=' || l_status
                                         || ' auth=' || l_auth,
                            p_entity     => l_ref,
                            p_impact_lcy => l_amt,
                            p_evidence   => 'period='
                                         || f_fmt_ts(v_date_from) || '..'
                                         || f_fmt_ts(v_date_to)
                        );
                        l_n_071 := l_n_071 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S08 F-071 unavailable: CLTB_LIQ or '
                        || 'LIQ_STATUS/AUTH_STAT column missing ('
                        || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            print_kv('F-070 findings (no liquidation)', TO_CHAR(l_n_070));
            print_kv('F-071 findings (rejected)',       TO_CHAR(l_n_071));

            print_section_footer('S08', l_n_070 + l_n_071);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S08', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S08', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S09 - LD CONTRACTS RATE AND SCHEDULE ANOMALIES
    -- -----------------------------------------------------------------
    -- [F-080] Echeance LD depassee (LDTB_SCHEDULES.SCHEDULE_DATE <
    --         v_as_of_date) sur contrats actifs.
    -- [F-081] Taux d'interet hors grille produit (< MIN ou > MAX de
    --         LDTM_PRODUCT_MASTER).
    -- [F-082] Contrats LD expires (MATURITY_DATE < v_as_of_date) mais
    --         non clotures (AUTH_STAT = 'A', statut non terminal).
    --
    -- Severite : HIGH (taux anormal), MEDIUM (echeance manquee isolee),
    -- HIGH si contrat expire > 30 jours.
    -- =================================================================
    DECLARE
        l_cur      SYS_REFCURSOR;
        l_ref      VARCHAR2(30);
        l_prod     VARCHAR2(10);
        l_ccy      VARCHAR2(3);
        l_cpty     VARCHAR2(20);
        l_amt      NUMBER;
        l_rate     NUMBER;
        l_min      NUMBER;
        l_max      NUMBER;
        l_due_dt   DATE;
        l_mat_dt   DATE;
        l_days     NUMBER;
        l_n_080    PLS_INTEGER := 0;
        l_n_081    PLS_INTEGER := 0;
        l_n_082    PLS_INTEGER := 0;
        l_sql      VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S09') THEN
            log_info('Section S09 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S09',
                'LD contracts - rate and schedule anomalies');

            -- [F-080] Echeances LD depassees ------------------------
            l_sql :=
                'SELECT m.CONTRACT_REF_NO, m.PRODUCT, m.CCY, '
             || '       m.COUNTERPARTY, s.SCHEDULE_DATE, '
             || '       NVL(m.AMOUNT,0) AS NOTIONAL '
             || '  FROM LDTB_CONTRACT_MASTER m '
             || '  JOIN LDTB_SCHEDULES s '
             || '    ON s.CONTRACT_REF_NO = m.CONTRACT_REF_NO '
             || ' WHERE s.SCHEDULE_DATE < :asof '
             || '   AND NVL(s.SCHEDULE_FLAG, ''N'') <> ''L'' '
             || '   AND NVL(m.AUTH_STAT, ''?'') = ''A'' '
             || '   AND (:p_ccy IS NULL OR m.CCY = :p_ccy) '
             || ' ORDER BY s.SCHEDULE_DATE ASC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_as_of_date, p_ccy, p_ccy;

                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_ccy, l_cpty, l_due_dt, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_080 >= NVL(p_top_n, 50);

                    l_days := GREATEST(0, v_as_of_date - l_due_dt);

                    print_finding(
                        p_section    => 'S09',
                        p_code       => 'RA-S09-F080',
                        p_severity   => CASE WHEN l_days > 30
                                             THEN 'HIGH' ELSE 'MEDIUM' END,
                        p_message    => 'LD missed schedule: due='
                                     || f_fmt_ts(l_due_dt)
                                     || ' age=' || TO_CHAR(l_days) || 'd '
                                     || ' notional=' || f_fmt_lcy(l_amt),
                        p_entity     => l_ref,
                        p_impact_lcy => NULL,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CCY=' || NVL(l_ccy,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                    );
                    l_n_080 := l_n_080 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S09',
                        'F-080 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-081] Taux hors grille produit ----------------------
            l_sql :=
                'SELECT m.CONTRACT_REF_NO, m.PRODUCT, m.CCY, '
             || '       NVL(m.INT_RATE, m.FIXED_RATE) AS RATE, '
             || '       p.MIN_INT_RATE, p.MAX_INT_RATE, '
             || '       NVL(m.AMOUNT,0) AS NOTIONAL '
             || '  FROM LDTB_CONTRACT_MASTER m '
             || '  LEFT JOIN LDTM_PRODUCT_MASTER p '
             || '    ON p.PRODUCT = m.PRODUCT '
             || ' WHERE NVL(m.AUTH_STAT, ''?'') = ''A'' '
             || '   AND NVL(m.INT_RATE, m.FIXED_RATE) IS NOT NULL '
             || '   AND ( NVL(m.INT_RATE, m.FIXED_RATE) < NVL(p.MIN_INT_RATE, -1) '
             || '      OR NVL(m.INT_RATE, m.FIXED_RATE) > NVL(p.MAX_INT_RATE, 1e9) ) '
             || '   AND (:p_ccy IS NULL OR m.CCY = :p_ccy) '
             || ' ORDER BY ABS(NVL(m.AMOUNT,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING p_ccy, p_ccy;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_ccy, l_rate, l_min, l_max, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_081 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S09',
                        p_code       => 'RA-S09-F081',
                        p_severity   => 'HIGH',
                        p_message    => 'LD rate out of product range: rate='
                                     || NVL(TO_CHAR(l_rate,'FM990.0000',
                                          'NLS_NUMERIC_CHARACTERS=''.,'''),'?')
                                     || ' min=' || NVL(TO_CHAR(l_min,'FM990.0000',
                                          'NLS_NUMERIC_CHARACTERS=''.,'''),'?')
                                     || ' max=' || NVL(TO_CHAR(l_max,'FM990.0000',
                                          'NLS_NUMERIC_CHARACTERS=''.,'''),'?')
                                     || ' notional=' || f_fmt_lcy(l_amt),
                        p_entity     => l_ref,
                        p_impact_lcy => NULL,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CCY=' || NVL(l_ccy,'?')
                    );
                    l_n_081 := l_n_081 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S09 F-081 unavailable: LDTM_PRODUCT_MASTER or '
                        || 'rate bounds missing (' || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            -- [F-082] Contrats LD expires non clotures --------------
            l_sql :=
                'SELECT m.CONTRACT_REF_NO, m.PRODUCT, m.CCY, m.COUNTERPARTY, '
             || '       m.MATURITY_DATE, NVL(m.AMOUNT,0) AS NOTIONAL '
             || '  FROM LDTB_CONTRACT_MASTER m '
             || ' WHERE m.MATURITY_DATE IS NOT NULL '
             || '   AND m.MATURITY_DATE < :asof '
             || '   AND NVL(m.AUTH_STAT, ''?'') = ''A'' '
             || '   AND UPPER(NVL(m.CONTRACT_STATUS, ''ACTIVE'')) '
             || '       NOT IN (''L'', ''LIQUIDATED'', ''CLOSED'', ''C'') '
             || '   AND (:p_ccy IS NULL OR m.CCY = :p_ccy) '
             || ' ORDER BY m.MATURITY_DATE ASC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_as_of_date, p_ccy, p_ccy;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_ccy, l_cpty, l_mat_dt, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_082 >= NVL(p_top_n, 50);

                    l_days := GREATEST(0, v_as_of_date - l_mat_dt);

                    print_finding(
                        p_section    => 'S09',
                        p_code       => 'RA-S09-F082',
                        p_severity   => CASE WHEN l_days > 30
                                             THEN 'HIGH' ELSE 'MEDIUM' END,
                        p_message    => 'LD expired but still active: maturity='
                                     || f_fmt_ts(l_mat_dt)
                                     || ' age=' || TO_CHAR(l_days) || 'd'
                                     || ' notional=' || f_fmt_lcy(l_amt),
                        p_entity     => l_ref,
                        p_impact_lcy => ABS(l_amt),
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CCY=' || NVL(l_ccy,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                    );
                    l_n_082 := l_n_082 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S09',
                        'F-082 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-080 findings (missed schedule)', TO_CHAR(l_n_080));
            print_kv('F-081 findings (rate off range)',  TO_CHAR(l_n_081));
            print_kv('F-082 findings (expired active)',  TO_CHAR(l_n_082));

            print_section_footer('S09', l_n_080 + l_n_081 + l_n_082);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S09', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S09', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S10 - LOAN COMPONENT WAIVERS AND RATE OVERRIDES
    -- -----------------------------------------------------------------
    -- [F-090] Composantes CL avec WAIVE='Y' sur interet / frais
    --         (renonciation explicite du revenu banque).
    -- [F-091] Taux utilisateur sous le minimum produit
    --         (USER_DEFINED rate < CLTM_PRODUCT_MASTER.MIN_INT_RATE).
    --
    -- Impact [F-090] (indicatif) :
    --   notional * waived_rate * nb_jours / 365
    --   Le montant passe dans l'impact est AMOUNT_DUE (la perte
    --   deja materialisee pour la composante).
    -- =================================================================
    DECLARE
        l_cur     SYS_REFCURSOR;
        l_ref     VARCHAR2(30);
        l_prod    VARCHAR2(10);
        l_comp    VARCHAR2(30);
        l_cust    VARCHAR2(20);
        l_amt     NUMBER;
        l_rate    NUMBER;
        l_min     NUMBER;
        l_n_090   PLS_INTEGER := 0;
        l_n_091   PLS_INTEGER := 0;
        l_sql     VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S10') THEN
            log_info('Section S10 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S10',
                'Loan component waivers and manual rate overrides');

            -- [F-090] WAIVE='Y' sur composantes ------------------
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.COMPONENT, '
             || '       NVL(c.AMOUNT_DUE,0) AS AMT, '
             || '       m.CUSTOMER_NO, m.PRODUCT '
             || '  FROM CLTB_ACCOUNT_COMPONENTS c '
             || '  JOIN CLTB_ACCOUNT_MASTER m '
             || '    ON m.ACCOUNT_NUMBER = c.CONTRACT_REF_NO '
             || ' WHERE UPPER(NVL(c.WAIVE,''N'')) = ''Y'' '
             || '   AND NVL(c.AMOUNT_DUE,0) > 0 '
             || '   AND (:p_cust IS NULL OR m.CUSTOMER_NO = :p_cust) '
             || ' ORDER BY NVL(c.AMOUNT_DUE,0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING p_customer_no, p_customer_no;
                LOOP
                    FETCH l_cur INTO l_ref, l_comp, l_amt, l_cust, l_prod;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_090 >= NVL(p_top_n, 50);

                    IF l_amt >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S10',
                            p_code       => 'RA-S10-F090',
                            p_severity   => 'MEDIUM',
                            p_message    => 'Loan component waived: comp='
                                         || NVL(l_comp,'?')
                                         || ' amt_due=' || f_fmt_lcy(l_amt),
                            p_entity     => l_ref,
                            p_impact_lcy => l_amt,
                            p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                         || ' CUST=' || NVL(f_mask_pii(l_cust),'?')
                        );
                        l_n_090 := l_n_090 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S10',
                        'F-090 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-091] Taux < MIN produit -------------------------
            l_sql :=
                'SELECT m.ACCOUNT_NUMBER, m.PRODUCT, m.CUSTOMER_NO, '
             || '       NVL(c.INTEREST_RATE, c.USER_INT_RATE) AS R, '
             || '       p.MIN_INT_RATE, NVL(m.AMOUNT_FINANCED,0) AS AMT '
             || '  FROM CLTB_ACCOUNT_MASTER m '
             || '  JOIN CLTB_ACCOUNT_COMPONENTS c '
             || '    ON c.CONTRACT_REF_NO = m.ACCOUNT_NUMBER '
             || '  LEFT JOIN CLTM_PRODUCT_MASTER p '
             || '    ON p.PRODUCT = m.PRODUCT '
             || ' WHERE UPPER(NVL(c.COMPONENT,'' '')) IN '
             || '       (''MAIN_INT'', ''INTEREST'') '
             || '   AND NVL(c.INTEREST_RATE, c.USER_INT_RATE) IS NOT NULL '
             || '   AND NVL(c.INTEREST_RATE, c.USER_INT_RATE) '
             || '       < NVL(p.MIN_INT_RATE, 0) '
             || '   AND (:p_cust IS NULL OR m.CUSTOMER_NO = :p_cust) '
             || ' ORDER BY (NVL(p.MIN_INT_RATE,0) '
             || '           - NVL(c.INTEREST_RATE, c.USER_INT_RATE)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING p_customer_no, p_customer_no;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cust, l_rate, l_min, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_091 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S10',
                        p_code       => 'RA-S10-F091',
                        p_severity   => 'HIGH',
                        p_message    => 'User-defined rate below product minimum: rate='
                                     || NVL(TO_CHAR(l_rate,'FM990.0000',
                                          'NLS_NUMERIC_CHARACTERS=''.,'''),'?')
                                     || ' min=' || NVL(TO_CHAR(l_min,'FM990.0000',
                                          'NLS_NUMERIC_CHARACTERS=''.,'''),'?')
                                     || ' notional=' || f_fmt_lcy(l_amt),
                        p_entity     => l_ref,
                        p_impact_lcy => NULL,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CUST=' || NVL(f_mask_pii(l_cust),'?')
                    );
                    l_n_091 := l_n_091 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S10 F-091 unavailable: CLTM_PRODUCT_MASTER or '
                        || 'INTEREST_RATE column missing ('
                        || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            print_kv('F-090 findings (waivers)',  TO_CHAR(l_n_090));
            print_kv('F-091 findings (rate < min)', TO_CHAR(l_n_091));

            print_section_footer('S10', l_n_090 + l_n_091);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S10', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S10', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S11 - SI WITHOUT APPLY_CHG_* FLAGS SET
    -- -----------------------------------------------------------------
    -- [F-100] SI contracts dont au moins un flag APPLY_CHG_* est NULL
    --         ou 'N' -> frais non preleves a l'execution / au rejet.
    -- [F-101] SI configures pour facturer (APPLY_CHG_FLAG='Y') mais
    --         aucun evenement de charge cote ICTB_LIQ_DETAILS sur la
    --         periode -> frais parametre mais non realise.
    --
    -- Impact indicatif :
    --   [F-100] : nb_exec_non_chargees * 500 LCY (tarif standard SI).
    --   [F-101] : nb_exec * 500 LCY (idem).
    -- =================================================================
    DECLARE
        l_cur         SYS_REFCURSOR;
        l_ref         VARCHAR2(30);
        l_prod        VARCHAR2(10);
        l_cpty        VARCHAR2(20);
        l_n_exec      NUMBER;
        l_flag_flag   VARCHAR2(1);
        l_flag_rejt   VARCHAR2(1);
        l_flag_liq    VARCHAR2(1);
        l_n_100       PLS_INTEGER := 0;
        l_n_101       PLS_INTEGER := 0;
        l_si_fee_std  CONSTANT NUMBER := 500;
        l_impact      NUMBER;
        l_sql         VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S11') THEN
            log_info('Section S11 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S11',
                'Standing Instructions without APPLY_CHG_* flags');

            -- [F-100] Flags manquants / 'N' --------------------
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY, '
             || '       NVL(c.APPLY_CHG_FLAG,    ''N''), '
             || '       NVL(c.APPLY_CHG_REJT,    ''N''), '
             || '       NVL(c.APPLY_CHG_ON_LIQ,  ''N''), '
             || '       ( SELECT COUNT(*) FROM SITB_EXEC_LOG l '
             || '          WHERE l.CONTRACT_REF_NO = c.CONTRACT_REF_NO '
             || '            AND l.EXEC_DATE BETWEEN :d1 AND :d2 ) AS N_EXEC '
             || '  FROM SITB_CONTRACTS c '
             || ' WHERE ( NVL(c.APPLY_CHG_FLAG,    ''N'') = ''N'' '
             || '    OR  NVL(c.APPLY_CHG_REJT,    ''N'') = ''N'' '
             || '    OR  NVL(c.APPLY_CHG_ON_LIQ,  ''N'') = ''N'' ) '
             || '   AND NVL(c.AUTH_STAT,''?'') = ''A'' '
             || ' ORDER BY ( SELECT COUNT(*) FROM SITB_EXEC_LOG l '
             || '             WHERE l.CONTRACT_REF_NO = c.CONTRACT_REF_NO '
             || '               AND l.EXEC_DATE BETWEEN :d1b AND :d2b ) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_date_from, v_date_to,
                    v_date_from, v_date_to;

                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cpty,
                        l_flag_flag, l_flag_rejt, l_flag_liq, l_n_exec;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_100 >= NVL(p_top_n, 50);

                    l_impact := ROUND(NVL(l_n_exec, 0) * l_si_fee_std, 2);

                    print_finding(
                        p_section    => 'S11',
                        p_code       => 'RA-S11-F100',
                        p_severity   => CASE WHEN NVL(l_n_exec,0) > 12
                                             THEN 'HIGH' ELSE 'MEDIUM' END,
                        p_message    => 'SI with missing APPLY_CHG flags: FLAG='
                                     || l_flag_flag || ' REJT=' || l_flag_rejt
                                     || ' LIQ=' || l_flag_liq
                                     || ' n_exec=' || NVL(TO_CHAR(l_n_exec),'0'),
                        p_entity     => l_ref,
                        p_impact_lcy => l_impact,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                                     || ' std_fee_LCY=' || TO_CHAR(l_si_fee_std)
                    );
                    l_n_100 := l_n_100 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S11',
                        'F-100 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-101] SI chargeable mais aucun evenement charge ---
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY, '
             || '       ( SELECT COUNT(*) FROM SITB_EXEC_LOG l '
             || '          WHERE l.CONTRACT_REF_NO = c.CONTRACT_REF_NO '
             || '            AND l.EXEC_DATE BETWEEN :d1 AND :d2 ) AS N_EXEC '
             || '  FROM SITB_CONTRACTS c '
             || ' WHERE NVL(c.APPLY_CHG_FLAG, ''N'') = ''Y'' '
             || '   AND NVL(c.AUTH_STAT,''?'') = ''A'' '
             || '   AND NOT EXISTS ( '
             || '       SELECT 1 FROM ICTB_LIQ_DETAILS d '
             || '        WHERE d.CONTRACT_REF_NO = c.CONTRACT_REF_NO '
             || '          AND UPPER(NVL(d.COMPONENT,'' '')) LIKE ''CHG%'' '
             || '          AND NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) '
             || '              BETWEEN :d1b AND :d2b ) '
             || ' ORDER BY 4 DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_date_from, v_date_to,
                    v_date_from, v_date_to;

                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cpty, l_n_exec;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_101 >= NVL(p_top_n, 50);

                    IF NVL(l_n_exec, 0) > 0 THEN
                        l_impact := ROUND(l_n_exec * l_si_fee_std, 2);
                        print_finding(
                            p_section    => 'S11',
                            p_code       => 'RA-S11-F101',
                            p_severity   => 'HIGH',
                            p_message    => 'SI chargeable but no charge event: n_exec='
                                         || TO_CHAR(l_n_exec),
                            p_entity     => l_ref,
                            p_impact_lcy => l_impact,
                            p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                         || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                        );
                        l_n_101 := l_n_101 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S11 F-101 unavailable: ICTB_LIQ_DETAILS join '
                        || 'failed (' || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            print_kv('F-100 findings (missing flags)',  TO_CHAR(l_n_100));
            print_kv('F-101 findings (chargeable but 0)', TO_CHAR(l_n_101));
            print_kv('Std SI fee (LCY)',                 TO_CHAR(l_si_fee_std));

            print_section_footer('S11', l_n_100 + l_n_101);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S11', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S11', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S12 - EXPIRED OR STALLED STANDING INSTRUCTIONS
    -- -----------------------------------------------------------------
    -- [F-110] SI actives dont LAST_EXEC_DATE < v_as_of_date - 90j
    --         (instruction dormante - risque commission perdue).
    -- [F-111] SI en etat d'echec repete (EXEC_STATUS in F/E/X) sur
    --         la periode.
    -- [F-112] SI dont END_DATE < v_as_of_date mais toujours AUTH_STAT='A'
    --         (contrat expire, menage non fait).
    --
    -- Severite : MEDIUM par defaut, HIGH si impact indicatif depasse
    -- p_materiality_impact_lcy.
    -- =================================================================
    DECLARE
        l_cur         SYS_REFCURSOR;
        l_ref         VARCHAR2(30);
        l_prod        VARCHAR2(10);
        l_cpty        VARCHAR2(20);
        l_last_dt     DATE;
        l_end_dt      DATE;
        l_n_fail      NUMBER;
        l_days        NUMBER;
        l_n_110       PLS_INTEGER := 0;
        l_n_111       PLS_INTEGER := 0;
        l_n_112       PLS_INTEGER := 0;
        l_stall_th    CONSTANT NUMBER := 90;
        l_si_fee_std  CONSTANT NUMBER := 500;
        l_impact      NUMBER;
        l_sql         VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S12') THEN
            log_info('Section S12 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S12',
                'Expired or stalled Standing Instructions');

            -- [F-110] SI dormantes --------------------------------
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY, '
             || '       c.LAST_EXEC_DATE '
             || '  FROM SITB_CONTRACTS c '
             || ' WHERE NVL(c.AUTH_STAT,''?'') = ''A'' '
             || '   AND c.LAST_EXEC_DATE IS NOT NULL '
             || '   AND c.LAST_EXEC_DATE < :asof - :th '
             || '   AND (c.END_DATE IS NULL OR c.END_DATE >= :asof2) '
             || ' ORDER BY c.LAST_EXEC_DATE ASC';

            BEGIN
                OPEN l_cur FOR l_sql USING
                    v_as_of_date, l_stall_th, v_as_of_date;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cpty, l_last_dt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_110 >= NVL(p_top_n, 50);

                    l_days := GREATEST(0, v_as_of_date - l_last_dt);
                    l_impact := ROUND(l_days / 30 * l_si_fee_std, 2);

                    print_finding(
                        p_section    => 'S12',
                        p_code       => 'RA-S12-F110',
                        p_severity   => 'MEDIUM',
                        p_message    => 'Stalled SI: last_exec='
                                     || f_fmt_ts(l_last_dt)
                                     || ' age=' || TO_CHAR(l_days) || 'd',
                        p_entity     => l_ref,
                        p_impact_lcy => l_impact,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                    );
                    l_n_110 := l_n_110 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S12',
                        'F-110 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-111] SI en echec repete --------------------------
            l_sql :=
                'SELECT l.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY, '
             || '       COUNT(*) AS N_FAIL '
             || '  FROM SITB_EXEC_LOG l '
             || '  JOIN SITB_CONTRACTS c '
             || '    ON c.CONTRACT_REF_NO = l.CONTRACT_REF_NO '
             || ' WHERE l.EXEC_DATE BETWEEN :d1 AND :d2 '
             || '   AND UPPER(NVL(l.EXEC_STATUS,'' '')) IN '
             || '       (''F'', ''FAILED'', ''E'', ''ERROR'', ''X'') '
             || ' GROUP BY l.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY '
             || ' ORDER BY COUNT(*) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cpty, l_n_fail;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_111 >= NVL(p_top_n, 50);

                    l_impact := ROUND(l_n_fail * l_si_fee_std, 2);
                    print_finding(
                        p_section    => 'S12',
                        p_code       => 'RA-S12-F111',
                        p_severity   => CASE WHEN l_n_fail > 10
                                             THEN 'HIGH' ELSE 'MEDIUM' END,
                        p_message    => 'SI in repeated failure: n_fail='
                                     || TO_CHAR(l_n_fail),
                        p_entity     => l_ref,
                        p_impact_lcy => l_impact,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                    );
                    l_n_111 := l_n_111 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S12',
                        'F-111 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            -- [F-112] SI expirees non closes -----------------------
            l_sql :=
                'SELECT c.CONTRACT_REF_NO, c.PROD_CODE, c.COUNTERPARTY, c.END_DATE '
             || '  FROM SITB_CONTRACTS c '
             || ' WHERE NVL(c.AUTH_STAT,''?'') = ''A'' '
             || '   AND c.END_DATE IS NOT NULL '
             || '   AND c.END_DATE < :asof '
             || ' ORDER BY c.END_DATE ASC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_as_of_date;
                LOOP
                    FETCH l_cur INTO l_ref, l_prod, l_cpty, l_end_dt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_112 >= NVL(p_top_n, 50);

                    l_days := GREATEST(0, v_as_of_date - l_end_dt);
                    print_finding(
                        p_section    => 'S12',
                        p_code       => 'RA-S12-F112',
                        p_severity   => 'MEDIUM',
                        p_message    => 'SI expired but active: end='
                                     || f_fmt_ts(l_end_dt)
                                     || ' age=' || TO_CHAR(l_days) || 'd',
                        p_entity     => l_ref,
                        p_impact_lcy => NULL,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                                     || ' CPTY=' || NVL(f_mask_pii(l_cpty),'?')
                    );
                    l_n_112 := l_n_112 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_error('S12',
                        'F-112 query failed: ' || SUBSTR(SQLERRM, 1, 200));
            END;

            print_kv('F-110 findings (stalled)', TO_CHAR(l_n_110));
            print_kv('F-111 findings (failed)',  TO_CHAR(l_n_111));
            print_kv('F-112 findings (expired)', TO_CHAR(l_n_112));
            print_kv('Stall threshold (days)',   TO_CHAR(l_stall_th));

            print_section_footer('S12', l_n_110 + l_n_111 + l_n_112);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S12', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S12', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- SECTION S13 - CHARGES POSTED BUT UNLINKED / AT ZERO
    -- -----------------------------------------------------------------
    -- [F-120] Ecritures ACTB_HISTORY avec TRN_CODE de charge ne
    --         pouvant etre rattachees a un contrat CHTB_* ou a une
    --         ligne de liquidation ICTB_LIQ_DETAILS (ecart de
    --         parametrage).
    -- [F-121] Lignes ICTB_LIQ_DETAILS avec COMPONENT LIKE 'CHG%' et
    --         AMOUNT = 0 -> commission parametree mais non perçue.
    --
    -- NB : la liste exacte des TRN_CODE de frais depend de la
    -- configuration locale (cf. BRD §7.Z mini-scripts). En l'absence
    -- de mapping, F-120 utilise un filtre heuristique TRN_CODE LIKE
    -- '%CHG%' OR '%CHARGE%' et doit etre valide manuellement.
    -- =================================================================
    DECLARE
        l_cur     SYS_REFCURSOR;
        l_ref     VARCHAR2(30);
        l_comp    VARCHAR2(30);
        l_prod    VARCHAR2(10);
        l_trn     VARCHAR2(10);
        l_ac      VARCHAR2(30);
        l_amt     NUMBER;
        l_n       NUMBER;
        l_n_120   PLS_INTEGER := 0;
        l_n_121   PLS_INTEGER := 0;
        l_sql     VARCHAR2(4000);
    BEGIN
        IF NOT f_section_enabled('S13') THEN
            log_info('Section S13 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S13',
                'Charges posted but unlinked or at zero amount');

            -- [F-120] Ecritures de frais sans contrat rattache ----
            l_sql :=
                'SELECT h.AC_NO, h.TRN_CODE, COUNT(*) AS N, '
             || '       NVL(SUM(NVL(h.LCY_AMOUNT,0)),0) AS VOL_LCY '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE (UPPER(NVL(h.TRN_CODE,'' '')) LIKE ''%CHG%'' '
             || '     OR UPPER(NVL(h.TRN_CODE,'' '')) LIKE ''%CHARGE%'' '
             || '     OR UPPER(NVL(h.TRN_CODE,'' '')) LIKE ''%FEE%'') '
             || '   AND h.TRN_DT BETWEEN :d1 AND :d2 '
             || '   AND NOT EXISTS ( '
             || '       SELECT 1 FROM ICTB_LIQ_DETAILS d '
             || '        WHERE d.ACCOUNT = h.AC_NO '
             || '          AND UPPER(NVL(d.COMPONENT,'' '')) LIKE ''CHG%'' '
             || '          AND NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) = h.TRN_DT) '
             || ' GROUP BY h.AC_NO, h.TRN_CODE '
             || ' ORDER BY NVL(SUM(NVL(h.LCY_AMOUNT,0)),0) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_ac, l_trn, l_n, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_120 >= NVL(p_top_n, 50);

                    IF l_amt >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S13',
                            p_code       => 'RA-S13-F120',
                            p_severity   => 'MEDIUM',
                            p_message    => 'Charge entries unlinked to liquidation: trn='
                                         || NVL(l_trn,'?')
                                         || ' n=' || TO_CHAR(l_n)
                                         || ' vol=' || f_fmt_lcy(l_amt),
                            p_entity     => l_ac,
                            p_impact_lcy => l_amt,
                            p_evidence   => 'period='
                                         || f_fmt_ts(v_date_from) || '..'
                                         || f_fmt_ts(v_date_to)
                        );
                        l_n_120 := l_n_120 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S13 F-120 unavailable (ACTB/ICTB join): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-121] Commissions a zero ---------------------------
            l_sql :=
                'SELECT d.ACCOUNT, NVL(d.PRODUCT,''?'') AS PROD, '
             || '       d.COMPONENT, COUNT(*) AS N '
             || '  FROM ICTB_LIQ_DETAILS d '
             || ' WHERE UPPER(NVL(d.COMPONENT,'' '')) LIKE ''CHG%'' '
             || '   AND NVL(d.AMOUNT,0) = 0 '
             || '   AND NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) '
             || '       BETWEEN :d1 AND :d2 '
             || ' GROUP BY d.ACCOUNT, d.PRODUCT, d.COMPONENT '
             || ' ORDER BY COUNT(*) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_ac, l_prod, l_comp, l_n;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_121 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S13',
                        p_code       => 'RA-S13-F121',
                        p_severity   => CASE WHEN l_n > 20
                                             THEN 'HIGH' ELSE 'MEDIUM' END,
                        p_message    => 'Zero-amount charge liquidation: comp='
                                     || NVL(l_comp,'?') || ' n=' || TO_CHAR(l_n),
                        p_entity     => l_ac,
                        p_impact_lcy => NULL,
                        p_evidence   => 'PROD=' || NVL(l_prod,'?')
                    );
                    l_n_121 := l_n_121 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S13 F-121 unavailable: ICTB_LIQ_DETAILS not '
                        || 'queryable (' || SUBSTR(SQLERRM, 1, 120) || ').');
            END;

            print_kv('F-120 findings (unlinked)',    TO_CHAR(l_n_120));
            print_kv('F-121 findings (zero amount)', TO_CHAR(l_n_121));

            print_section_footer('S13', l_n_120 + l_n_121);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S13', 'Section aborted: ' || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S13', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S14 -- Interest accruals not liquidated within expected cycle
    -- =================================================================
    -- [F-130] accruals older than p_min_days_overdue still in
    --         ICTB_ACCRUALS_TEMP (impact = sum of accrued amount LCY).
    -- [F-131] discrepancies between accrued amount and sum of
    --         liquidations since period start (reconciliation).
    -- PCEC/38 (regularisation en attente), PCEC/702 / PCEC/602.
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_sql       VARCHAR2(4000);
        l_n_130     PLS_INTEGER := 0;
        l_n_131     PLS_INTEGER := 0;
        l_ac        VARCHAR2(30);
        l_comp      VARCHAR2(30);
        l_prod      VARCHAR2(30);
        l_oldest    DATE;
        l_age_d     NUMBER;
        l_amt_lcy   NUMBER;
        l_accr_sum  NUMBER;
        l_liq_sum   NUMBER;
        l_diff      NUMBER;
        l_sev       VARCHAR2(10);
        l_cutoff    DATE;
    BEGIN
        IF NOT f_section_enabled('S14') THEN
            log_info('Section S14 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S14',
                'Interest accruals not liquidated within expected cycle');

            l_cutoff := v_date_to - NVL(p_min_days_overdue, 30);

            -- [F-130] Accruals stale in ICTB_ACCRUALS_TEMP ------------
            l_sql :=
                'SELECT a.ACCOUNT, '
             || '       NVL(a.COMPONENT,''?'') AS COMP, '
             || '       MIN(NVL(a.VALUE_DATE, a.ACCRUAL_DATE)) AS OLDEST, '
             || '       SUM(NVL(a.AMOUNT,0)) AS AMT_LCY '
             || '  FROM ICTB_ACCRUALS_TEMP a '
             || ' WHERE NVL(a.VALUE_DATE, a.ACCRUAL_DATE) < :cutoff '
             || '   AND NVL(a.AMOUNT,0) <> 0 '
             || ' GROUP BY a.ACCOUNT, a.COMPONENT '
             || ' ORDER BY SUM(NVL(a.AMOUNT,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING l_cutoff;
                LOOP
                    FETCH l_cur
                     INTO l_ac, l_comp, l_oldest, l_amt_lcy;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_130 >= NVL(p_top_n, 50);

                    l_age_d := TRUNC(v_date_to) - TRUNC(l_oldest);

                    IF ABS(NVL(l_amt_lcy, 0))
                       < NVL(p_materiality_lcy, 0) THEN
                        NULL;
                    ELSE
                        l_sev := f_promote_severity('MEDIUM',
                                     ABS(NVL(l_amt_lcy, 0)));
                        IF ABS(NVL(l_amt_lcy, 0))
                           >= NVL(p_materiality_impact_lcy, 0) THEN
                            l_sev := f_promote_severity(l_sev,
                                         p_materiality_impact_lcy);
                            IF l_sev = 'MEDIUM' THEN l_sev := 'HIGH'; END IF;
                        END IF;

                        print_finding(
                            p_section    => 'S14',
                            p_code       => 'RA-S14-F130',
                            p_severity   => l_sev,
                            p_message    => 'Stale accrual: comp='
                                         || NVL(l_comp,'?')
                                         || ' age_days='
                                         || TO_CHAR(l_age_d)
                                         || ' oldest='
                                         || TO_CHAR(l_oldest,
                                                'YYYY-MM-DD'),
                            p_entity     => l_ac,
                            p_impact_lcy => ABS(NVL(l_amt_lcy, 0)),
                            p_evidence   => 'CUTOFF='
                                         || TO_CHAR(l_cutoff,
                                                'YYYY-MM-DD')
                                         || ' MIN_DAYS='
                                         || TO_CHAR(NVL(
                                                p_min_days_overdue, 30))
                        );
                        l_n_130 := l_n_130 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S14 F-130 unavailable: ICTB_ACCRUALS_TEMP '
                        || 'not queryable (' || SUBSTR(SQLERRM,1,120)
                        || ').');
            END;

            -- [F-131] Accrued vs liquidated reconciliation -----------
            l_sql :=
                'SELECT x.ACCOUNT, x.COMPONENT, '
             || '       x.ACCR_SUM, x.LIQ_SUM, '
             || '       (x.ACCR_SUM - x.LIQ_SUM) AS DIFF '
             || '  FROM ( '
             || '    SELECT a.ACCOUNT, NVL(a.COMPONENT,''?'') AS COMPONENT, '
             || '           SUM(NVL(a.AMOUNT,0)) AS ACCR_SUM, '
             || '           NVL(( '
             || '             SELECT SUM(NVL(l.AMOUNT,0)) '
             || '               FROM ICTB_LIQ_DETAILS l '
             || '              WHERE l.ACCOUNT = a.ACCOUNT '
             || '                AND NVL(l.COMPONENT,''?'') '
             || '                    = NVL(a.COMPONENT,''?'') '
             || '                AND NVL(l.LIQUIDATION_DATE, l.VALUE_DATE) '
             || '                    BETWEEN :d1 AND :d2 '
             || '           ),0) AS LIQ_SUM '
             || '      FROM ICTB_ACCRUALS_TEMP a '
             || '     WHERE NVL(a.VALUE_DATE, a.ACCRUAL_DATE) '
             || '           BETWEEN :d3 AND :d4 '
             || '     GROUP BY a.ACCOUNT, a.COMPONENT '
             || '  ) x '
             || ' WHERE ABS(x.ACCR_SUM - x.LIQ_SUM) >= :mat '
             || ' ORDER BY ABS(x.ACCR_SUM - x.LIQ_SUM) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      v_date_from, v_date_to,
                      NVL(p_materiality_lcy, 0);
                LOOP
                    FETCH l_cur
                     INTO l_ac, l_comp, l_accr_sum, l_liq_sum, l_diff;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_131 >= NVL(p_top_n, 50);

                    l_sev := f_promote_severity('MEDIUM', ABS(l_diff));
                    IF ABS(l_diff)
                       >= NVL(p_materiality_impact_lcy, 0) THEN
                        IF l_sev = 'MEDIUM' THEN l_sev := 'HIGH'; END IF;
                    END IF;

                    print_finding(
                        p_section    => 'S14',
                        p_code       => 'RA-S14-F131',
                        p_severity   => l_sev,
                        p_message    => 'Accrual vs liquidation mismatch: '
                                     || 'comp=' || NVL(l_comp,'?')
                                     || ' accr=' || f_fmt_lcy(l_accr_sum)
                                     || ' liq=' || f_fmt_lcy(l_liq_sum)
                                     || ' diff=' || f_fmt_lcy(l_diff),
                        p_entity     => l_ac,
                        p_impact_lcy => ABS(NVL(l_diff, 0)),
                        p_evidence   => 'PERIOD='
                                     || TO_CHAR(v_date_from,
                                            'YYYY-MM-DD')
                                     || '..'
                                     || TO_CHAR(v_date_to,
                                            'YYYY-MM-DD')
                    );
                    l_n_131 := l_n_131 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S14 F-131 unavailable (accrual/liq '
                        || 'reconciliation): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            print_kv('F-130 findings (stale accruals)',
                TO_CHAR(l_n_130));
            print_kv('F-131 findings (accr vs liq diff)',
                TO_CHAR(l_n_131));

            print_section_footer('S14', l_n_130 + l_n_131);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S14', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S14', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S15 -- FX trade / cash deal revenue leakage (spread not applied)
    -- =================================================================
    -- [F-140] FX contracts with DEAL_RATE within +/- p_fx_spread_bps
    --         bps of MID_RATE (spread nul ou insuffisant).
    --         Impact LCY ~= |DEAL_RATE - MID_RATE| * notional_LCY.
    -- [F-141] FX fees waived without justification (WAIVE flags on
    --         ICTB_LIQ_DETAILS linked to FX reference, or 0-amount
    --         charge components on FX contracts).
    -- PCEC/7 (produits de change), PCEC/706 (frais de change).
    DECLARE
        l_cur        SYS_REFCURSOR;
        l_sql        VARCHAR2(4000);
        l_n_140      PLS_INTEGER := 0;
        l_n_141      PLS_INTEGER := 0;
        l_ref        VARCHAR2(30);
        l_cpty       VARCHAR2(30);
        l_ccy1       VARCHAR2(10);
        l_ccy2       VARCHAR2(10);
        l_deal_rate  NUMBER;
        l_mid_rate   NUMBER;
        l_notional   NUMBER;
        l_impact     NUMBER;
        l_bps        NUMBER;
        l_user       VARCHAR2(30);
        l_fx_avail   BOOLEAN := TRUE;
        l_sev        VARCHAR2(10);
        l_bps_thr    NUMBER;
    BEGIN
        IF NOT f_section_enabled('S15') THEN
            log_info('Section S15 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S15',
                'FX trade / cash deal revenue leakage (spread control)');

            l_bps_thr := NVL(p_fx_spread_bps, 10);
            print_kv('FX spread tolerance (bps)', TO_CHAR(l_bps_thr));

            -- Probe FX module presence ---------------------------------
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT COUNT(*) FROM FXTB_CONTRACT_MASTER '
                 || ' WHERE ROWNUM <= 0'
                    INTO l_n_140;
                l_n_140 := 0;
            EXCEPTION
                WHEN OTHERS THEN
                    l_fx_avail := FALSE;
                    log_warn('S15 skipped: FXTB_CONTRACT_MASTER not '
                        || 'available (' || SUBSTR(SQLERRM,1,120)
                        || ').');
            END;

            IF l_fx_avail THEN
                -- [F-140] Deal rate vs mid-market rate -----------------
                l_sql :=
                    'SELECT f.CONTRACT_REF_NO AS REF, '
                 || '       NVL(f.COUNTERPARTY, ''?'') AS CPTY, '
                 || '       f.CCY1, f.CCY2, '
                 || '       f.EXCHANGE_RATE AS DEAL_RATE, '
                 || '       NVL(r.MID_RATE, f.EXCHANGE_RATE) AS MID_RATE, '
                 || '       NVL(f.AMOUNT_CCY1, f.BOUGHT_AMOUNT) AS NOTIONAL, '
                 || '       NVL(f.MAKER_ID, f.USER_ID) AS USR '
                 || '  FROM FXTB_CONTRACT_MASTER f '
                 || '  LEFT JOIN CYTB_RATES r '
                 || '    ON r.CCY1 = f.CCY1 '
                 || '   AND r.CCY2 = f.CCY2 '
                 || '   AND r.RATE_DATE = TRUNC(f.BOOKING_DATE) '
                 || ' WHERE TRUNC(f.BOOKING_DATE) BETWEEN :d1 AND :d2 '
                 || '   AND (:p_branch IS NULL '
                 || '        OR f.BRANCH_CODE = :p_branch) '
                 || '   AND f.EXCHANGE_RATE IS NOT NULL '
                 || '   AND NVL(r.MID_RATE, f.EXCHANGE_RATE) <> 0 '
                 || '   AND ABS(f.EXCHANGE_RATE - NVL(r.MID_RATE,0)) '
                 || '       * 10000 / NULLIF(NVL(r.MID_RATE,1),0) '
                 || '       <= :bps '
                 || ' ORDER BY NVL(f.AMOUNT_CCY1, f.BOUGHT_AMOUNT) DESC';

                BEGIN
                    OPEN l_cur FOR l_sql USING
                        v_date_from, v_date_to,
                        p_branch_code, p_branch_code,
                        l_bps_thr;
                    LOOP
                        FETCH l_cur
                         INTO l_ref, l_cpty, l_ccy1, l_ccy2,
                              l_deal_rate, l_mid_rate, l_notional,
                              l_user;
                        EXIT WHEN l_cur%NOTFOUND
                               OR l_n_140 >= NVL(p_top_n, 50);

                        IF NVL(l_mid_rate, 0) = 0 THEN
                            l_bps := 0;
                        ELSE
                            l_bps := ABS(l_deal_rate - l_mid_rate)
                                   * 10000 / l_mid_rate;
                        END IF;

                        l_impact := ABS(NVL(l_deal_rate, 0)
                                      - NVL(l_mid_rate, 0))
                                  * ABS(NVL(l_notional, 0));

                        IF l_impact < NVL(p_materiality_lcy, 0) THEN
                            NULL;
                        ELSE
                            l_sev := f_promote_severity('MEDIUM', l_impact);
                            IF l_impact
                               >= NVL(p_materiality_impact_lcy, 0) THEN
                                IF l_sev = 'MEDIUM' THEN
                                    l_sev := 'HIGH';
                                END IF;
                            END IF;

                            print_finding(
                                p_section    => 'S15',
                                p_code       => 'RA-S15-F140',
                                p_severity   => l_sev,
                                p_message    => 'FX spread below tolerance: '
                                             || l_ccy1 || '/' || l_ccy2
                                             || ' deal='
                                             || TO_CHAR(l_deal_rate,
                                                    'FM999999990.000000')
                                             || ' mid='
                                             || TO_CHAR(l_mid_rate,
                                                    'FM999999990.000000')
                                             || ' bps='
                                             || TO_CHAR(ROUND(l_bps, 2)),
                                p_entity     => l_ref,
                                p_impact_lcy => l_impact,
                                p_evidence   => 'CPTY='
                                             || f_mask_pii(l_cpty)
                                             || ' USR='
                                             || f_mask_pii(l_user)
                                             || ' NOTIONAL='
                                             || f_fmt_lcy(l_notional)
                            );
                            l_n_140 := l_n_140 + 1;
                        END IF;
                    END LOOP;
                    CLOSE l_cur;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF l_cur%ISOPEN THEN
                            CLOSE l_cur;
                        END IF;
                        log_warn('S15 F-140 unavailable (FXTB/CYTB): '
                            || SUBSTR(SQLERRM, 1, 120));
                END;

                -- [F-141] FX fees waived / zero on FX contracts ---------
                l_sql :=
                    'SELECT d.REFERENCE_NO AS REF, '
                 || '       NVL(d.COMPONENT,''?'') AS COMP, '
                 || '       NVL(d.USER_ID, ''?'') AS USR, '
                 || '       NVL(d.AMOUNT, 0) AS AMT '
                 || '  FROM ICTB_LIQ_DETAILS d '
                 || ' WHERE NVL(d.LIQUIDATION_DATE, d.VALUE_DATE) '
                 || '       BETWEEN :d1 AND :d2 '
                 || '   AND UPPER(NVL(d.MODULE, '''')) IN (''FX'',''FT'') '
                 || '   AND ( NVL(d.AMOUNT,0) = 0 '
                 || '         OR UPPER(NVL(d.WAIVE_FLAG, ''N'')) = ''Y'' ) '
                 || ' ORDER BY d.LIQUIDATION_DATE DESC';

                BEGIN
                    OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                    LOOP
                        FETCH l_cur
                         INTO l_ref, l_ccy1, l_user, l_impact;
                        EXIT WHEN l_cur%NOTFOUND
                               OR l_n_141 >= NVL(p_top_n, 50);

                        print_finding(
                            p_section    => 'S15',
                            p_code       => 'RA-S15-F141',
                            p_severity   => 'MEDIUM',
                            p_message    => 'FX fee waived or zero: comp='
                                         || l_ccy1
                                         || ' amt='
                                         || f_fmt_lcy(l_impact),
                            p_entity     => l_ref,
                            p_impact_lcy => NULL,
                            p_evidence   => 'USR=' || f_mask_pii(l_user)
                        );
                        l_n_141 := l_n_141 + 1;
                    END LOOP;
                    CLOSE l_cur;
                EXCEPTION
                    WHEN OTHERS THEN
                        IF l_cur%ISOPEN THEN
                            CLOSE l_cur;
                        END IF;
                        log_warn('S15 F-141 unavailable (FX fee scan): '
                            || SUBSTR(SQLERRM, 1, 120));
                END;
            END IF;

            print_kv('F-140 findings (spread nul)',  TO_CHAR(l_n_140));
            print_kv('F-141 findings (fees waived)', TO_CHAR(l_n_141));

            print_section_footer('S15', l_n_140 + l_n_141);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S15', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S15', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S16 -- GL balance vs movement history consistency
    -- =================================================================
    -- [F-150] GLs where SUM(ACTB_HISTORY net DR over period)
    --         != (GLTB_GL_BAL CLOSING_BAL - OPENING_BAL).
    -- [F-151] GLs with zero closing balance but active movements.
    -- [F-152] GLs flagged blocked/frozen but bearing movements.
    -- Severity HIGH, promoted CRITICAL on PCEC classes 6/7.
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_sql       VARCHAR2(4000);
        l_n_150     PLS_INTEGER := 0;
        l_n_151     PLS_INTEGER := 0;
        l_n_152     PLS_INTEGER := 0;
        l_gl        VARCHAR2(30);
        l_branch    VARCHAR2(10);
        l_opening   NUMBER;
        l_closing   NUMBER;
        l_net_dr    NUMBER;
        l_delta     NUMBER;
        l_discrep   NUMBER;
        l_movsum    NUMBER;
        l_movcnt    NUMBER;
        l_class     VARCHAR2(1);
        l_sev       VARCHAR2(10);
        l_blocked   VARCHAR2(1);
    BEGIN
        IF NOT f_section_enabled('S16') THEN
            log_info('Section S16 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S16',
                'GL balance vs movement history consistency');

            -- [F-150] Aggregate reconciliation --------------------------
            l_sql :=
                'SELECT h.GL_CODE, h.BRANCH_CODE, '
             || '       SUM(CASE WHEN h.DR_CR = ''D'' '
             || '                THEN NVL(h.LCY_AMOUNT,0) '
             || '                ELSE -NVL(h.LCY_AMOUNT,0) END) AS NET_DR, '
             || '       COUNT(*) AS CNT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND (:p_branch IS NULL '
             || '        OR h.BRANCH_CODE = :p_branch) '
             || ' GROUP BY h.GL_CODE, h.BRANCH_CODE '
             || ' ORDER BY ABS(SUM(CASE WHEN h.DR_CR = ''D'' '
             || '                       THEN NVL(h.LCY_AMOUNT,0) '
             || '                       ELSE -NVL(h.LCY_AMOUNT,0) END)) '
             || ' DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur
                     INTO l_gl, l_branch, l_net_dr, l_movcnt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_150 >= NVL(p_top_n, 50);

                    -- Try to fetch opening/closing balances for that GL
                    l_opening := NULL;
                    l_closing := NULL;
                    BEGIN
                        EXECUTE IMMEDIATE
                            'SELECT NVL(SUM(NVL(OPENING_BAL_LCY,0)),0), '
                         || '       NVL(SUM(NVL(CLOSING_BAL_LCY,0)),0) '
                         || '  FROM GLTB_GL_BAL '
                         || ' WHERE GL_CODE = :gl '
                         || '   AND BRANCH_CODE = :br '
                         || '   AND PERIOD_CODE = TO_CHAR(:d,''MON-YYYY'') '
                            INTO l_opening, l_closing
                            USING l_gl, l_branch, v_date_to;
                    EXCEPTION
                        WHEN OTHERS THEN
                            l_opening := NULL;
                            l_closing := NULL;
                    END;

                    IF l_opening IS NULL OR l_closing IS NULL THEN
                        -- Fallback: period-less scan
                        BEGIN
                            EXECUTE IMMEDIATE
                                'SELECT NVL(SUM(NVL(OPENING_BAL_LCY,0)),0), '
                             || '       NVL(SUM(NVL(CLOSING_BAL_LCY,0)),0) '
                             || '  FROM GLTB_GL_BAL '
                             || ' WHERE GL_CODE = :gl '
                             || '   AND BRANCH_CODE = :br '
                                INTO l_opening, l_closing
                                USING l_gl, l_branch;
                        EXCEPTION
                            WHEN OTHERS THEN
                                l_opening := 0;
                                l_closing := 0;
                        END;
                    END IF;

                    l_delta   := NVL(l_closing, 0) - NVL(l_opening, 0);
                    l_discrep := ABS(NVL(l_net_dr, 0) - l_delta);

                    l_class := SUBSTR(NVL(l_gl, ' '), 1, 1);

                    IF l_discrep < NVL(p_materiality_lcy, 0) THEN
                        NULL;
                    ELSE
                        l_sev := f_promote_severity('HIGH', l_discrep);
                        IF l_class IN ('6','7') THEN
                            l_sev := 'CRITICAL';
                        END IF;

                        print_finding(
                            p_section    => 'S16',
                            p_code       => 'RA-S16-F150',
                            p_severity   => l_sev,
                            p_message    => 'GL mvmt vs balance mismatch: '
                                         || 'net_DR=' || f_fmt_lcy(l_net_dr)
                                         || ' delta=' || f_fmt_lcy(l_delta)
                                         || ' discr=' || f_fmt_lcy(l_discrep),
                            p_entity     => l_gl,
                            p_impact_lcy => l_discrep,
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                                         || ' PCEC=' || l_class
                                         || ' CNT=' || TO_CHAR(l_movcnt)
                        );
                        l_n_150 := l_n_150 + 1;
                    END IF;

                    -- [F-151] Zero closing but movements present --------
                    IF NVL(l_closing, 0) = 0 AND NVL(l_movcnt, 0) > 0
                       AND ABS(NVL(l_net_dr, 0))
                           >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S16',
                            p_code       => 'RA-S16-F151',
                            p_severity   => 'MEDIUM',
                            p_message    => 'GL with zero closing bal but '
                                         || 'movements: net_DR='
                                         || f_fmt_lcy(l_net_dr)
                                         || ' cnt=' || TO_CHAR(l_movcnt),
                            p_entity     => l_gl,
                            p_impact_lcy => ABS(NVL(l_net_dr,0)),
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                        );
                        l_n_151 := l_n_151 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S16 F-150/F-151 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-152] Movements on blocked/frozen GL --------------------
            l_sql :=
                'SELECT m.GL_CODE, NVL(m.BLOCKED,''N'') AS BLK, '
             || '       ( SELECT COUNT(*) FROM ACTB_HISTORY h '
             || '          WHERE h.GL_CODE = m.GL_CODE '
             || '            AND TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '       ) AS CNT, '
             || '       ( SELECT NVL(SUM(NVL(h.LCY_AMOUNT,0)),0) '
             || '           FROM ACTB_HISTORY h '
             || '          WHERE h.GL_CODE = m.GL_CODE '
             || '            AND TRUNC(h.TRN_DT) BETWEEN :d3 AND :d4 '
             || '       ) AS AMT '
             || '  FROM GLTM_MASTER m '
             || ' WHERE UPPER(NVL(m.BLOCKED, ''N'')) = ''Y'' '
             || ' ORDER BY 4 DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      v_date_from, v_date_to;
                LOOP
                    FETCH l_cur
                     INTO l_gl, l_blocked, l_movcnt, l_movsum;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_152 >= NVL(p_top_n, 50);

                    IF NVL(l_movcnt, 0) = 0 THEN
                        EXIT;  -- remaining rows have 0 activity
                    END IF;

                    print_finding(
                        p_section    => 'S16',
                        p_code       => 'RA-S16-F152',
                        p_severity   => 'HIGH',
                        p_message    => 'Movements on blocked GL: cnt='
                                     || TO_CHAR(l_movcnt)
                                     || ' amt=' || f_fmt_lcy(l_movsum),
                        p_entity     => l_gl,
                        p_impact_lcy => ABS(NVL(l_movsum, 0)),
                        p_evidence   => 'BLOCKED=' || l_blocked
                    );
                    l_n_152 := l_n_152 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S16 F-152 unavailable '
                        || '(GLTM_MASTER.BLOCKED may not exist): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            print_kv('F-150 findings (mvmt/bal mismatch)',
                TO_CHAR(l_n_150));
            print_kv('F-151 findings (zero bal + mvmt)',
                TO_CHAR(l_n_151));
            print_kv('F-152 findings (blocked GL + mvmt)',
                TO_CHAR(l_n_152));

            print_section_footer('S16',
                l_n_150 + l_n_151 + l_n_152);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S16', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S16', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S17 -- Manual journal entries -- volume, concentration,
    --        sensitive GLs and off-hours posting
    -- =================================================================
    -- [F-160] Manual entries count / amount per user over period.
    -- [F-161] Manual entries on income/expense GLs (class 6/7).
    -- [F-162] Manual entries passed outside business hours (20h-06h)
    --         or on weekends.
    -- [F-163] Manual entries reversed within 24h (suspect window-
    --         dressing).
    -- PCEC focus /6 /7 /38 /5.
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_sql       VARCHAR2(4000);
        l_n_160     PLS_INTEGER := 0;
        l_n_161     PLS_INTEGER := 0;
        l_n_162     PLS_INTEGER := 0;
        l_n_163     PLS_INTEGER := 0;
        l_user      VARCHAR2(30);
        l_cnt       NUMBER;
        l_amt       NUMBER;
        l_gl        VARCHAR2(30);
        l_class     VARCHAR2(1);
        l_trn_ref   VARCHAR2(30);
        l_hour      NUMBER;
        l_dow       VARCHAR2(10);
        l_sev       VARCHAR2(10);
        l_branch    VARCHAR2(10);
        l_total_manual_cnt PLS_INTEGER := 0;
    BEGIN
        IF NOT f_section_enabled('S17') THEN
            log_info('Section S17 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S17',
                'Manual entries risk: volume, concentration, '
             || 'sensitive GLs, off-hours');

            -- Baseline: total manual entries in period ------------------
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT COUNT(*) FROM ACTB_HISTORY '
                 || ' WHERE TRUNC(TRN_DT) BETWEEN :d1 AND :d2 '
                 || '   AND (UPPER(NVL(MODULE,''  '')) = ''MO'' '
                 || '        OR UPPER(NVL(TRN_CODE,'''')) LIKE ''MAN%'' '
                 || '        OR UPPER(NVL(TRN_CODE,'''')) LIKE ''%MANUAL%'')'
                    INTO l_total_manual_cnt
                    USING v_date_from, v_date_to;
                print_kv('Manual entries total (period)',
                    TO_CHAR(l_total_manual_cnt));
            EXCEPTION
                WHEN OTHERS THEN
                    l_total_manual_cnt := 0;
                    log_warn('S17 baseline: ACTB_HISTORY.MODULE not '
                        || 'queryable (' || SUBSTR(SQLERRM,1,120)
                        || ').');
            END;

            -- [F-160] Concentration per user ----------------------------
            l_sql :=
                'SELECT NVL(h.MAKER_ID, h.AUTH_ID) AS USR, '
             || '       COUNT(*) AS CNT, '
             || '       SUM(NVL(h.LCY_AMOUNT,0)) AS AMT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND (UPPER(NVL(h.MODULE,''  '')) = ''MO'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''MAN%'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''%MANUAL%'') '
             || '   AND (:p_branch IS NULL '
             || '        OR h.BRANCH_CODE = :p_branch) '
             || ' GROUP BY NVL(h.MAKER_ID, h.AUTH_ID) '
             || ' ORDER BY COUNT(*) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur INTO l_user, l_cnt, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_160 >= NVL(p_top_n, 50);

                    -- Severity: HIGH if > 50% of total volume
                    l_sev := 'MEDIUM';
                    IF l_total_manual_cnt > 0
                       AND l_cnt * 2 > l_total_manual_cnt THEN
                        l_sev := 'HIGH';
                    END IF;
                    IF ABS(NVL(l_amt, 0))
                       >= NVL(p_materiality_impact_lcy, 0) THEN
                        l_sev := 'HIGH';
                    END IF;

                    print_finding(
                        p_section    => 'S17',
                        p_code       => 'RA-S17-F160',
                        p_severity   => l_sev,
                        p_message    => 'Manual-entry concentration: cnt='
                                     || TO_CHAR(l_cnt)
                                     || ' amt=' || f_fmt_lcy(l_amt),
                        p_entity     => f_mask_pii(l_user),
                        p_impact_lcy => ABS(NVL(l_amt, 0)),
                        p_evidence   => 'TOTAL_MANUAL='
                                     || TO_CHAR(l_total_manual_cnt)
                    );
                    l_n_160 := l_n_160 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S17 F-160 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-161] Manual entries on P&L GLs (class 6/7) -------------
            l_sql :=
                'SELECT h.GL_CODE, h.BRANCH_CODE, '
             || '       COUNT(*) AS CNT, '
             || '       SUM(NVL(h.LCY_AMOUNT,0)) AS AMT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND SUBSTR(NVL(h.GL_CODE,''0''),1,1) IN (''6'',''7'') '
             || '   AND (UPPER(NVL(h.MODULE,''  '')) = ''MO'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''MAN%'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''%MANUAL%'') '
             || ' GROUP BY h.GL_CODE, h.BRANCH_CODE '
             || ' ORDER BY SUM(NVL(h.LCY_AMOUNT,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_gl, l_branch, l_cnt, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_161 >= NVL(p_top_n, 50);

                    l_sev := f_promote_severity('HIGH', ABS(NVL(l_amt, 0)));

                    print_finding(
                        p_section    => 'S17',
                        p_code       => 'RA-S17-F161',
                        p_severity   => l_sev,
                        p_message    => 'Manual entry on P&L GL: cnt='
                                     || TO_CHAR(l_cnt)
                                     || ' amt=' || f_fmt_lcy(l_amt),
                        p_entity     => l_gl,
                        p_impact_lcy => ABS(NVL(l_amt, 0)),
                        p_evidence   => 'BR=' || NVL(l_branch,'?')
                                     || ' PCEC=' || SUBSTR(l_gl,1,1)
                    );
                    l_n_161 := l_n_161 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S17 F-161 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-162] Off-hours manual postings -------------------------
            l_sql :=
                'SELECT NVL(h.MAKER_ID, h.AUTH_ID) AS USR, '
             || '       TO_NUMBER(TO_CHAR(h.MAKER_DT_STAMP,''HH24'')) '
             || '                                  AS HR, '
             || '       TO_CHAR(h.MAKER_DT_STAMP,''DY'',' ||
                '''NLS_DATE_LANGUAGE=ENGLISH'') AS DOW, '
             || '       h.TRN_REF_NO, '
             || '       NVL(h.LCY_AMOUNT,0) AS AMT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND (UPPER(NVL(h.MODULE,''  '')) = ''MO'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''MAN%'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''%MANUAL%'') '
             || '   AND ( TO_NUMBER(TO_CHAR(h.MAKER_DT_STAMP,''HH24'')) '
             || '         NOT BETWEEN 6 AND 19 '
             || '      OR TO_CHAR(h.MAKER_DT_STAMP,''DY'',' ||
                '''NLS_DATE_LANGUAGE=ENGLISH'') IN (''SAT'',''SUN'') ) '
             || ' ORDER BY h.MAKER_DT_STAMP DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur
                     INTO l_user, l_hour, l_dow, l_trn_ref, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_162 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S17',
                        p_code       => 'RA-S17-F162',
                        p_severity   => 'MEDIUM',
                        p_message    => 'Off-hours manual posting: hr='
                                     || TO_CHAR(l_hour)
                                     || ' dow=' || l_dow
                                     || ' amt=' || f_fmt_lcy(l_amt),
                        p_entity     => l_trn_ref,
                        p_impact_lcy => ABS(NVL(l_amt, 0)),
                        p_evidence   => 'USR=' || f_mask_pii(l_user)
                    );
                    l_n_162 := l_n_162 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S17 F-162 unavailable (MAKER_DT_STAMP '
                        || 'may not exist): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-163] Manual entries reversed within 24h ---------------
            l_sql :=
                'SELECT h.TRN_REF_NO, '
             || '       NVL(h.MAKER_ID, h.AUTH_ID) AS USR, '
             || '       NVL(h.LCY_AMOUNT,0) AS AMT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND (UPPER(NVL(h.MODULE,''  '')) = ''MO'' '
             || '        OR UPPER(NVL(h.TRN_CODE,'''')) LIKE ''MAN%'') '
             || '   AND EXISTS ( '
             || '         SELECT 1 FROM ACTB_HISTORY r '
             || '          WHERE r.RELATED_REFERENCE = h.TRN_REF_NO '
             || '            AND UPPER(NVL(r.REVERSAL_MARKER,''N'')) = ''R'' '
             || '            AND r.TRN_DT <= h.TRN_DT + 1 '
             || '       ) '
             || ' ORDER BY h.TRN_DT DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING v_date_from, v_date_to;
                LOOP
                    FETCH l_cur INTO l_trn_ref, l_user, l_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_163 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S17',
                        p_code       => 'RA-S17-F163',
                        p_severity   => 'HIGH',
                        p_message    => 'Manual entry reversed <24h: amt='
                                     || f_fmt_lcy(l_amt),
                        p_entity     => l_trn_ref,
                        p_impact_lcy => ABS(NVL(l_amt, 0)),
                        p_evidence   => 'USR=' || f_mask_pii(l_user)
                    );
                    l_n_163 := l_n_163 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S17 F-163 unavailable (REVERSAL_MARKER / '
                        || 'RELATED_REFERENCE may not exist): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            print_kv('F-160 findings (user concentration)',
                TO_CHAR(l_n_160));
            print_kv('F-161 findings (P&L GL manual)',
                TO_CHAR(l_n_161));
            print_kv('F-162 findings (off-hours manual)',
                TO_CHAR(l_n_162));
            print_kv('F-163 findings (reversed <24h)',
                TO_CHAR(l_n_163));

            print_section_footer('S17',
                l_n_160 + l_n_161 + l_n_162 + l_n_163);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S17', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S17', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S18 -- Suspense accounts ageing (PCEC class 38)
    -- =================================================================
    -- [F-170] Suspense GL balances aged > 30/60/90/180 days.
    -- [F-171] Suspense GLs with only one-sided movements
    --         (DR without CR or CR without DR) over period.
    -- [F-172] Suspense GLs with balance on unexpected side.
    -- PCEC/38 (regularisation et attente).
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_sql       VARCHAR2(4000);
        l_n_170     PLS_INTEGER := 0;
        l_n_171     PLS_INTEGER := 0;
        l_n_172     PLS_INTEGER := 0;
        l_gl        VARCHAR2(30);
        l_branch    VARCHAR2(10);
        l_bal       NUMBER;
        l_oldest    DATE;
        l_age_d     NUMBER;
        l_dr_cnt    NUMBER;
        l_cr_cnt    NUMBER;
        l_dr_amt    NUMBER;
        l_cr_amt    NUMBER;
        l_sev       VARCHAR2(10);
    BEGIN
        IF NOT f_section_enabled('S18') THEN
            log_info('Section S18 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S18',
                'Suspense accounts ageing (PCEC/38)');

            -- Detection base: GL codes starting with ''38'' (COBAC PCEC)
            -- ou libelle contenant SUSPENSE / ATTENTE.

            -- [F-170] Suspense balances with ageing --------------------
            l_sql :=
                'SELECT b.GL_CODE, b.BRANCH_CODE, '
             || '       NVL(b.CLOSING_BAL_LCY,0) AS BAL, '
             || '       ( SELECT MIN(TRUNC(h.TRN_DT)) '
             || '           FROM ACTB_HISTORY h '
             || '          WHERE h.GL_CODE = b.GL_CODE '
             || '            AND h.BRANCH_CODE = b.BRANCH_CODE '
             || '            AND h.TRN_DT <= :d_to '
             || '       ) AS OLDEST '
             || '  FROM GLTB_GL_BAL b '
             || ' WHERE SUBSTR(NVL(b.GL_CODE,''0''),1,2) = ''38'' '
             || '   AND ABS(NVL(b.CLOSING_BAL_LCY,0)) > 0 '
             || '   AND (:p_branch IS NULL '
             || '        OR b.BRANCH_CODE = :p_branch) '
             || ' ORDER BY ABS(NVL(b.CLOSING_BAL_LCY,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_to, p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur INTO l_gl, l_branch, l_bal, l_oldest;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_170 >= NVL(p_top_n, 50);

                    IF l_oldest IS NULL THEN
                        l_age_d := NULL;
                    ELSE
                        l_age_d := TRUNC(v_date_to) - TRUNC(l_oldest);
                    END IF;

                    IF ABS(NVL(l_bal, 0))
                       < NVL(p_materiality_lcy, 0) THEN
                        NULL;
                    ELSE
                        l_sev := 'MEDIUM';
                        IF NVL(l_age_d, 0) > 180
                           OR ABS(NVL(l_bal, 0))
                              >= NVL(p_materiality_critical_lcy, 0) THEN
                            l_sev := 'CRITICAL';
                        ELSIF NVL(l_age_d, 0) > 90
                           OR ABS(NVL(l_bal, 0))
                              >= NVL(p_materiality_impact_lcy, 0) THEN
                            l_sev := 'HIGH';
                        ELSIF NVL(l_age_d, 0) > 60 THEN
                            l_sev := 'HIGH';
                        END IF;

                        print_finding(
                            p_section    => 'S18',
                            p_code       => 'RA-S18-F170',
                            p_severity   => l_sev,
                            p_message    => 'Suspense balance aged: bal='
                                         || f_fmt_lcy(l_bal)
                                         || ' age_days='
                                         || NVL(TO_CHAR(l_age_d), '?'),
                            p_entity     => l_gl,
                            p_impact_lcy => ABS(NVL(l_bal, 0)),
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                                         || ' OLDEST='
                                         || NVL(TO_CHAR(l_oldest,
                                                'YYYY-MM-DD'), '?')
                        );
                        l_n_170 := l_n_170 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S18 F-170 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-171] One-sided movements on suspense GLs --------------
            l_sql :=
                'SELECT h.GL_CODE, h.BRANCH_CODE, '
             || '       SUM(CASE WHEN h.DR_CR = ''D'' THEN 1 ELSE 0 END) '
             || '                                    AS DR_CNT, '
             || '       SUM(CASE WHEN h.DR_CR = ''C'' THEN 1 ELSE 0 END) '
             || '                                    AS CR_CNT, '
             || '       SUM(CASE WHEN h.DR_CR = ''D'' '
             || '                THEN NVL(h.LCY_AMOUNT,0) ELSE 0 END) '
             || '                                    AS DR_AMT, '
             || '       SUM(CASE WHEN h.DR_CR = ''C'' '
             || '                THEN NVL(h.LCY_AMOUNT,0) ELSE 0 END) '
             || '                                    AS CR_AMT '
             || '  FROM ACTB_HISTORY h '
             || ' WHERE SUBSTR(NVL(h.GL_CODE,''0''),1,2) = ''38'' '
             || '   AND TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '   AND (:p_branch IS NULL '
             || '        OR h.BRANCH_CODE = :p_branch) '
             || ' GROUP BY h.GL_CODE, h.BRANCH_CODE '
             || 'HAVING (SUM(CASE WHEN h.DR_CR = ''D'' THEN 1 ELSE 0 END) = 0 '
             || '     OR SUM(CASE WHEN h.DR_CR = ''C'' THEN 1 ELSE 0 END) = 0)'
             || ' ORDER BY ABS(SUM(NVL(h.LCY_AMOUNT,0))) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur
                     INTO l_gl, l_branch, l_dr_cnt, l_cr_cnt,
                          l_dr_amt, l_cr_amt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_171 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S18',
                        p_code       => 'RA-S18-F171',
                        p_severity   => 'HIGH',
                        p_message    => 'Suspense GL one-sided: DR_cnt='
                                     || TO_CHAR(l_dr_cnt)
                                     || ' CR_cnt=' || TO_CHAR(l_cr_cnt)
                                     || ' DR_amt=' || f_fmt_lcy(l_dr_amt)
                                     || ' CR_amt=' || f_fmt_lcy(l_cr_amt),
                        p_entity     => l_gl,
                        p_impact_lcy => ABS(NVL(l_dr_amt, 0)
                                         - NVL(l_cr_amt, 0)),
                        p_evidence   => 'BR=' || NVL(l_branch,'?')
                    );
                    l_n_171 := l_n_171 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S18 F-171 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-172] Suspense GL with balance on unexpected side ------
            -- Suspense accounts should normally carry a small balance.
            -- Flag GLs with |closing| > p_materiality_impact_lcy as
            -- unusual concentration that may indicate wrong side.
            l_sql :=
                'SELECT b.GL_CODE, b.BRANCH_CODE, '
             || '       NVL(b.CLOSING_BAL_LCY,0) AS BAL '
             || '  FROM GLTB_GL_BAL b '
             || ' WHERE SUBSTR(NVL(b.GL_CODE,''0''),1,2) = ''38'' '
             || '   AND ABS(NVL(b.CLOSING_BAL_LCY,0)) >= :mat '
             || '   AND (:p_branch IS NULL '
             || '        OR b.BRANCH_CODE = :p_branch) '
             || ' ORDER BY ABS(NVL(b.CLOSING_BAL_LCY,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING NVL(p_materiality_impact_lcy, 1000000),
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur INTO l_gl, l_branch, l_bal;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_172 >= NVL(p_top_n, 50);

                    print_finding(
                        p_section    => 'S18',
                        p_code       => 'RA-S18-F172',
                        p_severity   => 'HIGH',
                        p_message    => 'Suspense GL material balance '
                                     || '(side to review): bal='
                                     || f_fmt_lcy(l_bal),
                        p_entity     => l_gl,
                        p_impact_lcy => ABS(NVL(l_bal, 0)),
                        p_evidence   => 'BR=' || NVL(l_branch,'?')
                                     || ' SIDE='
                                     || CASE WHEN l_bal >= 0
                                             THEN 'DR' ELSE 'CR' END
                    );
                    l_n_172 := l_n_172 + 1;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S18 F-172 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            print_kv('F-170 findings (aged)',       TO_CHAR(l_n_170));
            print_kv('F-171 findings (one-sided)',  TO_CHAR(l_n_171));
            print_kv('F-172 findings (material)',   TO_CHAR(l_n_172));

            print_section_footer('S18',
                l_n_170 + l_n_171 + l_n_172);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S18', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S18', 0);
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
    END;

    -- =================================================================
    -- S19 -- FX revaluation anomalies
    -- =================================================================
    -- [F-180] FCY GL where FCY_BAL * closing_rate diverges from
    --         LCY_BAL beyond materiality (re-evaluation gap).
    -- [F-181] FCY GL with non-zero FCY balance but no reval posting
    --         over the period (batch reval skipped).
    -- [F-182] Position-currency imbalance: for a given CCY, sum of
    --         DR FCY positions ne SUM of CR FCY positions beyond
    --         tolerance.
    -- PCEC/3, PCEC/7.
    DECLARE
        l_cur       SYS_REFCURSOR;
        l_sql       VARCHAR2(4000);
        l_n_180     PLS_INTEGER := 0;
        l_n_181     PLS_INTEGER := 0;
        l_n_182     PLS_INTEGER := 0;
        l_gl        VARCHAR2(30);
        l_branch    VARCHAR2(10);
        l_ccy       VARCHAR2(10);
        l_fcy_bal   NUMBER;
        l_lcy_bal   NUMBER;
        l_rate      NUMBER;
        l_theo_lcy  NUMBER;
        l_gap       NUMBER;
        l_reval_cnt NUMBER;
        l_sum_pos   NUMBER;
        l_sum_neg   NUMBER;
        l_sev       VARCHAR2(10);
        l_local_ccy VARCHAR2(3);
    BEGIN
        IF NOT f_section_enabled('S19') THEN
            log_info('Section S19 skipped (p_sections_include/exclude).');
        ELSE
            print_section_header('S19',
                'FX revaluation anomalies');

            -- Resolve local currency (LCY) from SMTB_BANK_PARAMETERS.
            -- Fallback to 'XAF' per BRD assumption A-05.
            BEGIN
                EXECUTE IMMEDIATE
                    'SELECT LOCAL_CCY FROM SMTB_BANK_PARAMETERS '
                 || ' WHERE ROWNUM = 1'
                    INTO l_local_ccy;
            EXCEPTION
                WHEN OTHERS THEN
                    l_local_ccy := 'XAF';
                    log_warn('S19: LOCAL_CCY lookup failed, '
                        || 'fallback to XAF (' || SUBSTR(SQLERRM,1,80)
                        || ').');
            END;
            print_kv('Local currency (LCY)', NVL(l_local_ccy,'XAF'));

            -- [F-180] Reval gap per FCY GL ------------------------------
            l_sql :=
                'SELECT b.GL_CODE, b.BRANCH_CODE, b.CCY, '
             || '       NVL(b.FCY_CLOSING_BAL, 0) AS FCY_BAL, '
             || '       NVL(b.CLOSING_BAL_LCY, 0) AS LCY_BAL, '
             || '       NVL(r.BUY_RATE, r.MID_RATE) AS RATE '
             || '  FROM GLTB_GL_BAL b '
             || '  LEFT JOIN CYTB_RATES r '
             || '    ON r.CCY1 = b.CCY '
             || '   AND r.RATE_DATE = TRUNC(:d_to) '
             || ' WHERE NVL(b.CCY, '''') <> '''' '
             || '   AND NVL(b.CCY, '''') <> :lcy '
             || '   AND ABS(NVL(b.FCY_CLOSING_BAL,0)) > 0 '
             || '   AND (:p_branch IS NULL '
             || '        OR b.BRANCH_CODE = :p_branch) '
             || ' ORDER BY ABS(NVL(b.CLOSING_BAL_LCY,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_to, l_local_ccy,
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur
                     INTO l_gl, l_branch, l_ccy,
                          l_fcy_bal, l_lcy_bal, l_rate;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_180 >= NVL(p_top_n, 50);

                    IF NVL(l_rate, 0) = 0 THEN
                        -- cannot compute theoretical LCY without a rate
                        l_theo_lcy := NULL;
                        l_gap      := NULL;
                    ELSE
                        l_theo_lcy := NVL(l_fcy_bal, 0) * l_rate;
                        l_gap      := ABS(NVL(l_lcy_bal, 0) - l_theo_lcy);
                    END IF;

                    IF l_gap IS NULL
                       OR l_gap < NVL(p_materiality_lcy, 0) THEN
                        NULL;
                    ELSE
                        l_sev := f_promote_severity('HIGH', l_gap);
                        IF l_gap >= NVL(p_materiality_critical_lcy, 0) THEN
                            l_sev := 'CRITICAL';
                        END IF;

                        print_finding(
                            p_section    => 'S19',
                            p_code       => 'RA-S19-F180',
                            p_severity   => l_sev,
                            p_message    => 'FX reval gap: ccy='
                                         || l_ccy
                                         || ' fcy=' || f_fmt_lcy(l_fcy_bal)
                                         || ' lcy=' || f_fmt_lcy(l_lcy_bal)
                                         || ' rate='
                                         || TO_CHAR(l_rate,
                                                'FM999999990.000000')
                                         || ' theo_lcy='
                                         || f_fmt_lcy(l_theo_lcy)
                                         || ' gap='
                                         || f_fmt_lcy(l_gap),
                            p_entity     => l_gl,
                            p_impact_lcy => l_gap,
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                        );
                        l_n_180 := l_n_180 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S19 F-180 unavailable (GLTB_GL_BAL.FCY '
                        || 'or CYTB_RATES missing): '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-181] FCY GL with balance but no reval posting ----------
            l_sql :=
                'SELECT b.GL_CODE, b.BRANCH_CODE, b.CCY, '
             || '       NVL(b.FCY_CLOSING_BAL, 0) AS FCY_BAL, '
             || '       ( SELECT COUNT(*) '
             || '           FROM ACTB_HISTORY h '
             || '          WHERE h.GL_CODE = b.GL_CODE '
             || '            AND h.BRANCH_CODE = b.BRANCH_CODE '
             || '            AND TRUNC(h.TRN_DT) BETWEEN :d1 AND :d2 '
             || '            AND ( UPPER(NVL(h.TRN_CODE,'''')) '
             || '                  LIKE ''%REVAL%'' '
             || '               OR UPPER(NVL(h.MODULE,'''')) = ''EL'' ) '
             || '       ) AS REVAL_CNT '
             || '  FROM GLTB_GL_BAL b '
             || ' WHERE NVL(b.CCY,'''') <> '''' '
             || '   AND NVL(b.CCY,'''') <> :lcy '
             || '   AND ABS(NVL(b.FCY_CLOSING_BAL,0)) > 0 '
             || '   AND (:p_branch IS NULL '
             || '        OR b.BRANCH_CODE = :p_branch) '
             || ' ORDER BY ABS(NVL(b.CLOSING_BAL_LCY,0)) DESC';

            BEGIN
                OPEN l_cur FOR l_sql
                USING v_date_from, v_date_to,
                      l_local_ccy,
                      p_branch_code, p_branch_code;
                LOOP
                    FETCH l_cur
                     INTO l_gl, l_branch, l_ccy, l_fcy_bal, l_reval_cnt;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_181 >= NVL(p_top_n, 50);

                    IF NVL(l_reval_cnt, 0) = 0
                       AND ABS(NVL(l_fcy_bal, 0))
                           >= NVL(p_materiality_lcy, 0) THEN
                        print_finding(
                            p_section    => 'S19',
                            p_code       => 'RA-S19-F181',
                            p_severity   => 'HIGH',
                            p_message    => 'FCY GL without reval posting: '
                                         || 'ccy=' || l_ccy
                                         || ' fcy=' || f_fmt_lcy(l_fcy_bal),
                            p_entity     => l_gl,
                            p_impact_lcy => ABS(NVL(l_fcy_bal, 0)),
                            p_evidence   => 'BR=' || NVL(l_branch,'?')
                                         || ' REVAL_CNT=0'
                        );
                        l_n_181 := l_n_181 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S19 F-181 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            -- [F-182] Position imbalance per currency -------------------
            l_sql :=
                'SELECT b.CCY, '
             || '       SUM(CASE WHEN NVL(b.FCY_CLOSING_BAL,0) > 0 '
             || '                THEN NVL(b.FCY_CLOSING_BAL,0) ELSE 0 END) '
             || '                                     AS SUM_POS, '
             || '       SUM(CASE WHEN NVL(b.FCY_CLOSING_BAL,0) < 0 '
             || '                THEN NVL(b.FCY_CLOSING_BAL,0) ELSE 0 END) '
             || '                                     AS SUM_NEG, '
             || '       SUM(NVL(b.CLOSING_BAL_LCY,0)) AS TOTAL_LCY '
             || '  FROM GLTB_GL_BAL b '
             || ' WHERE NVL(b.CCY,'''') <> '''' '
             || '   AND NVL(b.CCY,'''') <> :lcy '
             || ' GROUP BY b.CCY '
             || 'HAVING ABS(SUM(NVL(b.FCY_CLOSING_BAL,0))) > 0 '
             || ' ORDER BY ABS(SUM(NVL(b.CLOSING_BAL_LCY,0))) DESC';

            BEGIN
                OPEN l_cur FOR l_sql USING l_local_ccy;
                LOOP
                    FETCH l_cur
                     INTO l_ccy, l_sum_pos, l_sum_neg, l_lcy_bal;
                    EXIT WHEN l_cur%NOTFOUND
                           OR l_n_182 >= NVL(p_top_n, 50);

                    IF ABS(NVL(l_lcy_bal, 0))
                       < NVL(p_materiality_impact_lcy, 0) THEN
                        NULL;
                    ELSE
                        print_finding(
                            p_section    => 'S19',
                            p_code       => 'RA-S19-F182',
                            p_severity   => 'HIGH',
                            p_message    => 'FX position imbalance: ccy='
                                         || l_ccy
                                         || ' sum_pos='
                                         || f_fmt_lcy(l_sum_pos)
                                         || ' sum_neg='
                                         || f_fmt_lcy(l_sum_neg)
                                         || ' net_lcy='
                                         || f_fmt_lcy(l_lcy_bal),
                            p_entity     => l_ccy,
                            p_impact_lcy => ABS(NVL(l_lcy_bal, 0)),
                            p_evidence   => 'LCY=' || l_local_ccy
                        );
                        l_n_182 := l_n_182 + 1;
                    END IF;
                END LOOP;
                CLOSE l_cur;
            EXCEPTION
                WHEN OTHERS THEN
                    IF l_cur%ISOPEN THEN
                        CLOSE l_cur;
                    END IF;
                    log_warn('S19 F-182 unavailable: '
                        || SUBSTR(SQLERRM, 1, 120));
            END;

            print_kv('F-180 findings (reval gap)',
                TO_CHAR(l_n_180));
            print_kv('F-181 findings (no reval posting)',
                TO_CHAR(l_n_181));
            print_kv('F-182 findings (ccy position imbalance)',
                TO_CHAR(l_n_182));

            print_section_footer('S19',
                l_n_180 + l_n_181 + l_n_182);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            log_error('S19', 'Section aborted: '
                || SUBSTR(SQLERRM, 1, 300));
            BEGIN
                print_section_footer('S19', 0);
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
