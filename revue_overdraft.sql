-- ============================================================
-- SCRIPT DE REVUE DES OVERDRAFTS (DECOUVERTS BANCAIRES)
-- Base : FLEXCUBE (FCUBS) — Audit Interne / Risque de Credit
-- ============================================================
-- Ce script identifie les anomalies et zones de risque liees a
-- la gestion des decouverts (overdrafts) et des lignes de credit
-- rattachees aux comptes de la clientele.
--
-- PLAN DE LA REVUE
--   0.  Panorama du portefeuille overdraft (informatif)
--   1.  Overdrafts depassant leur limite
--   2.  Overdrafts expires mais toujours utilises
--   3.  Overdrafts sans approbation identifiable
--   4.  Overdrafts depasses pendant une longue periode
--   5.  Clients avec plusieurs overdrafts
--   6.  Augmentations de limites importantes
--   7.  Augmentations de limites juste avant un depassement
--   8.  Overdrafts proches ou superieurs aux seuils d'approbation
--   9.  Transactions manuelles sur comptes overdrawn
--   10. Overdrafts presentant des regularisations inhabituelles
--   11. Overdrafts dont les interets / frais n'ont pas ete appliques
--   12. Comptes presentant des depassements recurrents
--
-- TABLES UTILISEES
--   GETM_FACILITY             : lignes de credit / facilites (limites)
--   GETM_FACILITY_VD_DETAILS  : historique value-date des montants de limite
--   GETM_LIAB                 : liabilities (groupes de risque / clients)
--   STTM_CUST_ACCOUNT         : comptes clientele (soldes, TOD, dates OD)
--   STTM_CUSTOMER             : referentiel clients
--   STTM_ACCOUNT_CLASS        : classes de comptes (OVERDRAFT_FACILITY, IC)
--   ACTB_HISTORY              : ecritures comptables (module DE = saisie manuelle)
--   ACTB_ACCBAL_HISTORY       : soldes journaliers par compte (BKG_DATE)
--   ICTM_ACC_UDEVALS          : parametrage des taux au niveau du compte
--
-- CONVENTIONS
--   - Un solde debiteur (compte en overdraft) est NEGATIF dans FLEXCUBE
--     (ACY_CURR_BALANCE / LCY_CURR_BALANCE < 0).
--   - Les montants affiches "M" sont exprimes en MILLIONS de la devise
--     de reference (XAF sauf mention contraire).
--   - Les limites en devise etrangere sont ramenees au montant de
--     reporting (REPORTING_AMOUNT) lorsqu'il est renseigne ; la colonne
--     CCY est systematiquement affichee pour permettre le controle.
--   - Les seuils de la revue sont parametrables dans le bloc PARAMETRES
--     ci-dessous : ils DOIVENT etre alignes sur la grille de delegation
--     de pouvoirs en vigueur dans l'etablissement.
--
-- PERIMETRE DE LA REVUE
--   La revue porte exclusivement sur les COMPTES CLIENTELISES, c'est
--   a dire les comptes dont le GL naturel (STTB_ACCOUNT.AC_NATURAL_GL)
--   commence par le prefixe c_gl_client ('37'). Les comptes internes,
--   comptes de position, comptes de passage et GL techniques sont donc
--   exclus de tous les tests.
--   Le rattachement s'opere par la cle (AC_GL_NO, BRANCH_CODE) de
--   STTB_ACCOUNT vers (CUST_AC_NO, BRANCH_CODE) de STTM_CUST_ACCOUNT,
--   et vers (AC_NO, AC_BRANCH) pour les ecritures d'ACTB_HISTORY.
--   Une ligne de credit (GETM_FACILITY) entre dans le perimetre des
--   qu'elle est rattachee a au moins un compte clientelise.
--
-- PERFORMANCE
--   Le script a ete optimise pour limiter le cout des balayages sur les
--   tables volumineuses (ACTB_HISTORY ~5,8 M lignes,
--   ACTB_ACCBAL_HISTORY ~0,5 M lignes) :
--     - chaque test est execute en UNE SEULE passe : le comptage et le
--       detail sont obtenus par la meme requete (COUNT(*) OVER () et
--       ROW_NUMBER()), les lignes etant bufferisees avant affichage ;
--     - le perimetre clientelise est applique le plus tot possible,
--       avant toute jointure sur les historiques ;
--     - les jeux de travail partages par plusieurs tests d'une meme
--       section sont materialises une fois (WITH ... /*+ MATERIALIZE */) ;
--     - les sous-requetes correlees a predicat OR sur les cles de ligne
--       ont ete remplacees par des equi-jointures sur une cle normalisee.
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET LINESIZE 400
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_count         NUMBER;
    v_total         NUMBER;
    v_sep           VARCHAR2(80) := RPAD('=', 80, '=');
    v_test_no       NUMBER := 0;
    v_anomalies     NUMBER := 0;
    v_row_num       NUMBER := 0;
    v_montant       NUMBER;

    -- Buffer d'affichage : les lignes de detail d'un test sont
    -- accumulees ici pendant le parcours du curseur, puis affichees
    -- APRES la ligne [TEST nnn]. C'est ce buffer qui permet de ne
    -- lancer qu'UNE SEULE requete par test (le compteur est ramene
    -- par la requete de detail elle-meme) au lieu de deux.
    TYPE t_lines IS TABLE OF VARCHAR2(600) INDEX BY PLS_INTEGER;
    v_buf           t_lines;

    -- =========================================================
    -- PARAMETRES DE LA REVUE (a adapter au dispositif interne)
    -- =========================================================
    -- Perimetre : prefixe du GL naturel des comptes clientelises.
    -- Seuls les comptes dont STTB_ACCOUNT.AC_NATURAL_GL commence par ce
    -- prefixe sont retenus dans l'ensemble des tests de la revue.
    c_gl_client         CONSTANT VARCHAR2(10) := '37';
    c_gl_like           CONSTANT VARCHAR2(12) := c_gl_client || '%';

    -- Nombre maximum de lignes affichees par test
    c_max_rows          CONSTANT NUMBER := 30;

    -- Anciennete consideree comme "longue periode" de depassement
    c_jours_long        CONSTANT NUMBER := 90;    -- 3 mois
    c_jours_tres_long   CONSTANT NUMBER := 180;   -- 6 mois
    -- Duree maximale normale d'un TOD (decouvert temporaire)
    c_jours_tod_max     CONSTANT NUMBER := 30;

    -- Augmentation de limite consideree comme importante
    c_pct_augm          CONSTANT NUMBER := 25;            -- +25 %
    c_mnt_augm          CONSTANT NUMBER := 25000000;      -- ou +25 M
    -- Fenetre "augmentation juste avant un depassement"
    c_jours_avant       CONSTANT NUMBER := 30;

    -- Grille des seuils d'approbation (a aligner sur la delegation)
    c_seuil_1           CONSTANT NUMBER := 10000000;      -- 10 M
    c_seuil_2           CONSTANT NUMBER := 50000000;      -- 50 M
    c_seuil_3           CONSTANT NUMBER := 250000000;     -- 250 M
    c_seuil_4           CONSTANT NUMBER := 1000000000;    -- 1 000 M
    -- Bande "juste en dessous du seuil" (evitement du palier)
    c_pct_proche        CONSTANT NUMBER := 90;            -- 90 % du seuil

    -- Montant significatif d'ecriture / de decouvert
    c_mnt_signif        CONSTANT NUMBER := 5000000;       -- 5 M
    -- Profondeur d'analyse des historiques (en mois)
    c_mois_hist         CONSTANT NUMBER := 12;
    -- Profondeur d'analyse de l'historique des limites (en mois)
    c_mois_limit        CONSTANT NUMBER := 24;
    -- Nombre de jours en depassement au-dela duquel on parle de recurrence
    c_jours_recur       CONSTANT NUMBER := 60;
    -- Nombre d'episodes distincts d'overdraft caracterisant la recurrence
    c_nb_episodes       CONSTANT NUMBER := 4;
    -- Ecart maximum (en jours) d'un aller-retour credit/debit (habillage)
    c_jours_ar          CONSTANT NUMBER := 5;
    -- Taux d'interet debiteur annualise minimum attendu (%)
    c_taux_od_min       CONSTANT NUMBER := 5;

    PROCEDURE print_section(p_title VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE(v_sep);
        DBMS_OUTPUT.PUT_LINE('>>> ' || p_title);
        DBMS_OUTPUT.PUT_LINE(v_sep);
    END;

    PROCEDURE print_test(p_label VARCHAR2, p_count NUMBER, p_total NUMBER DEFAULT NULL) IS
    BEGIN
        v_test_no := v_test_no + 1;
        IF p_total IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 60, '.') || ' '
                || p_count || ' / ' || p_total
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        ELSE
            DBMS_OUTPUT.PUT_LINE('  [TEST ' || LPAD(v_test_no, 3, '0') || '] '
                || RPAD(p_label, 60, '.') || ' '
                || p_count
                || CASE WHEN p_count > 0 THEN '  *** ANOMALIE ***' ELSE '  OK' END);
        END IF;
        IF p_count > 0 THEN
            v_anomalies := v_anomalies + 1;
        END IF;
    END;

    -- Ligne informative (statistique de cadrage, non comptee comme test)
    PROCEDURE print_info(p_label VARCHAR2, p_value VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('    ' || RPAD(p_label, 55, '.') || ' ' || p_value);
    END;

    -- Dessine une ligne de separation parametrable
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
        DBMS_OUTPUT.PUT_LINE(v_line);
    END;

    -- Formatage d'un montant en millions
    FUNCTION fmt_m(p_amt NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_amt,0)/1000000, 'FM999G999G990D00') || ' M';
    END;

    -- Formatage d'un entier
    FUNCTION fmt_n(p_val NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_val,0), 'FM999G999G999G990');
    END;

    -- Formatage d'une date
    FUNCTION fmt_d(p_dt DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN NVL(TO_CHAR(p_dt, 'DD/MM/YYYY'), '-');
    END;

    -- =========================================================
    -- GESTION DU BUFFER DE DETAIL (execution en une seule passe)
    -- =========================================================
    -- Schema d'un test :
    --   buf_reset;
    --   FOR d IN (... COUNT(*) OVER () AS tot_cnt,
    --                 ROW_NUMBER() OVER (ORDER BY ...) AS rn
    --             ... WHERE rn <= c_max_rows ORDER BY rn) LOOP
    --       v_count := d.tot_cnt;
    --       buf_add('  |' || ...);
    --   END LOOP;
    --   print_test('libelle', v_count);
    --   buf_print('largeurs', 'entete');
    -- La requete n'est ainsi executee qu'une fois : elle rapporte a la
    -- fois le nombre total d'occurrences (tot_cnt, calcule avant la
    -- troncature a c_max_rows) et les lignes de detail a afficher.

    -- Reinitialise le buffer avant un test
    PROCEDURE buf_reset IS
    BEGIN
        v_buf.DELETE;
        v_row_num := 0;
        v_count   := 0;
    END;

    -- Ajoute une ligne de detail au buffer
    PROCEDURE buf_add(p_line VARCHAR2) IS
    BEGIN
        v_row_num := v_row_num + 1;
        v_buf(v_row_num) := p_line;
    END;

    -- Affiche le tableau bufferise (entete + lignes + pied)
    PROCEDURE buf_print(p_widths VARCHAR2, p_header VARCHAR2) IS
    BEGIN
        IF v_row_num = 0 THEN
            RETURN;
        END IF;
        tbl_line(p_widths);
        DBMS_OUTPUT.PUT_LINE(p_header);
        tbl_line(p_widths);
        FOR i IN 1 .. v_row_num LOOP
            DBMS_OUTPUT.PUT_LINE(v_buf(i));
        END LOOP;
        tbl_line(p_widths);
        IF NVL(v_count,0) > v_row_num THEN
            DBMS_OUTPUT.PUT_LINE('  (' || fmt_n(v_count - v_row_num)
                || ' ligne(s) supplementaire(s) non affichee(s) — limite c_max_rows = '
                || fmt_n(c_max_rows) || ')');
        END IF;
    END;

BEGIN

    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   REVUE DES OVERDRAFTS — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

    -- =========================================================
    -- SECTION 0 : PANORAMA DU PORTEFEUILLE OVERDRAFT (INFORMATIF)
    -- =========================================================
    -- Cadrage de la revue. Chaque bloc d'indicateurs est obtenu par UNE
    -- SEULE requete a agregation conditionnelle, au lieu d'une requete
    -- par indicateur : le portefeuille n'est balaye qu'une fois.
    -- =========================================================
    print_section('0. PANORAMA DU PORTEFEUILLE OVERDRAFT');

    -- 0.1 Rappel des parametres de la revue
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Parametres de la revue]');
    print_info('Perimetre : prefixe GL naturel clientelise', c_gl_client || ' (LIKE ''' || c_gl_like || ''')');
    print_info('Longue periode de depassement (jours)', fmt_n(c_jours_long));
    print_info('Tres longue periode de depassement (jours)', fmt_n(c_jours_tres_long));
    print_info('Duree maximale normale d''un TOD (jours)', fmt_n(c_jours_tod_max));
    print_info('Augmentation de limite importante (%)', fmt_n(c_pct_augm) || ' %');
    print_info('Augmentation de limite importante (montant)', fmt_m(c_mnt_augm));
    print_info('Fenetre augmentation / depassement (jours)', fmt_n(c_jours_avant));
    print_info('Seuil d''approbation 1', fmt_m(c_seuil_1));
    print_info('Seuil d''approbation 2', fmt_m(c_seuil_2));
    print_info('Seuil d''approbation 3', fmt_m(c_seuil_3));
    print_info('Seuil d''approbation 4', fmt_m(c_seuil_4));
    print_info('Bande "juste en dessous du seuil" (%)', fmt_n(c_pct_proche) || ' %');
    print_info('Profondeur d''analyse des historiques (mois)', fmt_n(c_mois_hist));

    -- 0.2 Cadrage du perimetre clientelise
    --     Un compte est "clientelise" lorsque son GL naturel
    --     (STTB_ACCOUNT.AC_NATURAL_GL) commence par c_gl_client.
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Perimetre — comptes clientelises (AC_NATURAL_GL LIKE ''' || c_gl_like || ''')]');
    FOR s IN (
        SELECT COUNT(*)                                              AS nb_tot,
               COUNT(CASE WHEN g.AC_GL_NO IS NOT NULL THEN 1 END)    AS nb_per,
               COUNT(CASE WHEN g.AC_GL_NO IS NOT NULL
                           AND a.RECORD_STAT = 'O' THEN 1 END)       AS nb_per_ouv,
               COUNT(CASE WHEN g.AC_GL_NO IS NOT NULL
                           AND a.RECORD_STAT = 'O'
                           AND NVL(a.ACY_CURR_BALANCE,0) < 0 THEN 1 END) AS nb_per_deb
        FROM STTM_CUST_ACCOUNT a
        LEFT JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                                AND g.BRANCH_CODE = a.BRANCH_CODE
                                AND g.AC_NATURAL_GL LIKE c_gl_like
    ) LOOP
        print_info('Comptes STTM_CUST_ACCOUNT (toutes natures)', fmt_n(s.nb_tot));
        print_info('dont comptes CLIENTELISES (perimetre revue)', fmt_n(s.nb_per));
        print_info('dont clientelises et ouverts', fmt_n(s.nb_per_ouv));
        print_info('dont clientelises, ouverts et debiteurs', fmt_n(s.nb_per_deb));
        print_info('Comptes hors perimetre (exclus de la revue)', fmt_n(s.nb_tot - s.nb_per));
    END LOOP;

    -- 0.3 Portefeuille des lignes de credit du perimetre (GETM_FACILITY)
    --     Une ligne entre dans le perimetre des qu'elle est rattachee a
    --     au moins un compte clientelise (LINE_ID = LINE_CODE ou = ID).
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Lignes de credit du perimetre — GETM_FACILITY]');
    FOR s IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT COUNT(*)                                                        AS nb_tot,
               COUNT(CASE WHEN f.RECORD_STAT = 'O' THEN 1 END)                 AS nb_open,
               COUNT(CASE WHEN f.AUTH_STAT = 'A' THEN 1 END)                   AS nb_auth,
               COUNT(CASE WHEN NVL(f.AUTH_STAT,'U') != 'A' THEN 1 END)         AS nb_nauth,
               COUNT(CASE WHEN NVL(f.UTILISATION,0) > 0 THEN 1 END)            AS nb_util,
               COUNT(CASE WHEN f.LINE_EXPIRY_DATE < TRUNC(SYSDATE) THEN 1 END) AS nb_exp,
               COUNT(CASE WHEN f.LINE_EXPIRY_DATE IS NULL THEN 1 END)          AS nb_sans_exp,
               NVL(SUM(CASE WHEN f.RECORD_STAT = 'O'
                            THEN f.LIMIT_AMOUNT END),0)                        AS mnt_limite,
               NVL(SUM(CASE WHEN f.RECORD_STAT = 'O'
                            THEN f.UTILISATION END),0)                         AS mnt_util
        FROM GETM_FACILITY f
        WHERE f.ID IN (SELECT line_id FROM per_line)
    ) LOOP
        print_info('Nombre total de lignes du perimetre', fmt_n(s.nb_tot));
        print_info('Lignes ouvertes (RECORD_STAT = O)', fmt_n(s.nb_open));
        print_info('Lignes autorisees (AUTH_STAT = A)', fmt_n(s.nb_auth));
        print_info('Lignes NON autorisees', fmt_n(s.nb_nauth));
        print_info('Lignes avec utilisation > 0', fmt_n(s.nb_util));
        print_info('Lignes expirees', fmt_n(s.nb_exp));
        print_info('Lignes sans date d''expiration', fmt_n(s.nb_sans_exp));
        print_info('Total des limites accordees (lignes ouvertes)', fmt_m(s.mnt_limite));
        print_info('Total des utilisations (lignes ouvertes)', fmt_m(s.mnt_util));
    END LOOP;

    -- Repartition par devise de ligne (perimetre)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Repartition des lignes du perimetre par devise]');
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT NVL(f.LINE_CURRENCY,'-') AS ccy, COUNT(*) AS nb,
               NVL(SUM(f.LIMIT_AMOUNT),0) AS mnt
        FROM GETM_FACILITY f
        WHERE f.ID IN (SELECT line_id FROM per_line)
        GROUP BY NVL(f.LINE_CURRENCY,'-')
        ORDER BY COUNT(*) DESC
    ) LOOP
        print_info('Devise ' || d.ccy, fmt_n(d.nb) || ' ligne(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 0.4 Comptes clientelises : rattachement et position debitrice
    --     (un seul balayage du perimetre pour tous les indicateurs)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptes clientelises — rattachement et position]');
    FOR s IN (
        SELECT COUNT(*)                                                       AS nb_ouv,
               COUNT(CASE WHEN TRIM(a.LINE_ID) IS NOT NULL THEN 1 END)        AS nb_ligne,
               COUNT(CASE WHEN NVL(a.ACY_CURR_BALANCE,0) < 0 THEN 1 END)      AS nb_deb,
               NVL(SUM(CASE WHEN NVL(a.ACY_CURR_BALANCE,0) < 0
                            THEN ABS(a.LCY_CURR_BALANCE) END),0)              AS mnt_deb,
               COUNT(CASE WHEN a.OVERDRAFT_SINCE IS NOT NULL THEN 1 END)      AS nb_od_since,
               COUNT(CASE WHEN a.OVERLINE_OD_SINCE IS NOT NULL THEN 1 END)    AS nb_overline,
               COUNT(CASE WHEN NVL(a.TOD_LIMIT,0) > 0 THEN 1 END)             AS nb_tod,
               COUNT(CASE WHEN a.TOD_SINCE IS NOT NULL THEN 1 END)            AS nb_tod_since,
               COUNT(CASE WHEN NVL(a.ACY_CURR_BALANCE,0) < 0
                           AND TRIM(a.LINE_ID) IS NULL
                           AND NVL(a.TOD_LIMIT,0) = 0 THEN 1 END)             AS nb_deb_nu
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        WHERE a.RECORD_STAT = 'O'
    ) LOOP
        v_total := s.nb_ouv;
        print_info('Comptes clientelises ouverts', fmt_n(s.nb_ouv));
        print_info('Comptes portant une LINE_ID', fmt_n(s.nb_ligne));
        print_info('Comptes en solde debiteur', fmt_n(s.nb_deb));
        print_info('Encours debiteur total (contre-valeur)', fmt_m(s.mnt_deb));
        print_info('Comptes avec OVERDRAFT_SINCE renseigne', fmt_n(s.nb_od_since));
        print_info('Comptes en depassement de ligne (OVERLINE)', fmt_n(s.nb_overline));
        print_info('Comptes avec un TOD (decouvert temporaire)', fmt_n(s.nb_tod));
        print_info('Comptes avec TOD_SINCE renseigne', fmt_n(s.nb_tod_since));
        print_info('Comptes debiteurs sans ligne ni TOD', fmt_n(s.nb_deb_nu));
    END LOOP;

    -- 0.5 Top 15 des encours debiteurs du perimetre
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top 15 des encours debiteurs — perimetre clientelise]');
    buf_reset;
    FOR d IN (
        SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO,
                   NVL(a.CCY,'-') AS ccy, NVL(a.BRANCH_CODE,'-') AS brn,
                   a.LCY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
                   ROW_NUMBER() OVER (ORDER BY a.LCY_CURR_BALANCE ASC) AS rn
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
                               AND g.AC_NATURAL_GL LIKE c_gl_like
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
        ) WHERE rn <= 15 ORDER BY rn
    ) LOOP
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,13) || '|' || RPAD(' ' || SUBSTR(d.nom,1,28),30) || '|'
            || RPAD(' ' || d.CUST_AC_NO,22) || '|' || RPAD(' ' || d.ccy,6) || '|'
            || RPAD(' ' || d.brn,14) || '|'
            || LPAD(fmt_m(d.solde),17) || ' |'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),14) || '|');
    END LOOP;
    v_count := v_row_num;
    IF v_row_num = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  (aucun compte clientelise en position debitrice)');
    ELSE
        buf_print('4,13,30,22,6,14,18,14',
            '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',13) || '|' || RPAD(' NOM CLIENT',30) || '|'
            || RPAD(' COMPTE',22) || '|' || RPAD(' CCY',6) || '|' || RPAD(' AGENCE',14) || '|'
            || RPAD(' SOLDE (M)',18) || '|' || RPAD(' OD DEPUIS',14) || '|');
    END IF;

    -- =========================================================
    -- SECTION 1 : OVERDRAFTS DEPASSANT LEUR LIMITE
    -- =========================================================
    -- Un depassement de limite doit faire l'objet d'une autorisation
    -- prealable (delegation de pouvoirs) et d'un suivi rapproche.
    -- NB : le montant effectif d'une ligne FLEXCUBE correspond a
    --      LIMIT_AMOUNT + COLLATERAL_CONTRIBUTION.
    -- PERIMETRE : seules les lignes rattachees a au moins un compte
    --      clientelise (per_line) et les comptes clientelises (jointure
    --      STTB_ACCOUNT) sont examines.
    -- =========================================================
    print_section('1. OVERDRAFTS DEPASSANT LEUR LIMITE');

    -- 1.1 Lignes dont l'utilisation depasse la limite nominale
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, f.LINE_SERIAL, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) AS depass,
                   f.LINE_EXPIRY_DATE,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0)
              AND NVL(f.UTILISATION,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || LPAD(NVL(d.LINE_SERIAL,0),4) || ' |'
            || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || LPAD(fmt_m(d.depass),14) || ' |'
            || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),12) || '|');
    END LOOP;
    print_test('Lignes : utilisation > limite nominale', v_count);
    buf_print('4,12,24,16,5,5,15,15,15,12',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' SER',5) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|'
        || RPAD(' EXPIRE LE',12) || '|');

    -- 1.2 Lignes dont l'utilisation depasse le montant effectif
    --     (limite + contribution du collateral) => depassement non couvert
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.COLLATERAL_CONTRIBUTION,0) AS collat,
                   NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0) - NVL(f.COLLATERAL_CONTRIBUTION,0) AS ecart,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) - NVL(f.LIMIT_AMOUNT,0)
                                               - NVL(f.COLLATERAL_CONTRIBUTION,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0) + NVL(f.COLLATERAL_CONTRIBUTION,0)
              AND NVL(f.UTILISATION,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.collat),14) || ' |'
            || LPAD(fmt_m(d.util),14) || ' |' || LPAD(fmt_m(d.ecart),14) || ' |');
    END LOOP;
    print_test('Lignes : utilisation > limite + collateral', v_count);
    buf_print('4,12,24,16,5,15,15,15,15',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' COLLATERAL',15) || '|' || RPAD(' UTILISE',15) || '|'
        || RPAD(' NON COUVERT',15) || '|');

    -- 1.3 Lignes dont le disponible calcule par FLEXCUBE est negatif
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.AVAILABLE_AMOUNT,0) AS dispo,
                   NVL(f.USER_DEFINE_STATUS,'-') AS statut,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.AVAILABLE_AMOUNT,0) ASC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.AVAILABLE_AMOUNT,0) < 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || LPAD(fmt_m(d.dispo),14) || ' |'
            || RPAD(' ' || SUBSTR(d.statut,1,10),12) || '|');
    END LOOP;
    print_test('Lignes avec AVAILABLE_AMOUNT negatif', v_count);
    buf_print('4,12,24,16,5,15,15,15,12',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DISPONIBLE',15) || '|'
        || RPAD(' STATUT',12) || '|');

    -- 1.4 Comptes dont le solde debiteur excede l'autorisation
    --     (limite de la ligne rattachee + TOD accorde)
    --     NB : le TOD est pris en compte quelle que soit sa validite ;
    --          les TOD expires sont traites en section 2.
    --     La sous-requete correlee a predicat OR sur GETM_FACILITY a ete
    --     remplacee par une equi-jointure sur une cle de ligne normalisee
    --     (fac_lim), calculee une seule fois pour toute la requete.
    buf_reset;
    FOR d IN (
        WITH fac_lim AS (
            SELECT /*+ MATERIALIZE */ line_key, MAX(LIMIT_AMOUNT) AS limite
            FROM (
                SELECT f.LINE_CODE AS line_key, f.LIMIT_AMOUNT
                FROM GETM_FACILITY f WHERE f.RECORD_STAT = 'O'
                UNION ALL
                SELECT TO_CHAR(f.ID), f.LIMIT_AMOUNT
                FROM GETM_FACILITY f WHERE f.RECORD_STAT = 'O'
            )
            GROUP BY line_key
        )
        SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   ABS(a.ACY_CURR_BALANCE) AS solde_deb,
                   NVL(fl.limite,0) + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0) AS autorise,
                   ABS(a.ACY_CURR_BALANCE)
                     - (NVL(fl.limite,0) + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)) AS depass,
                   a.OVERDRAFT_SINCE,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY ABS(a.ACY_CURR_BALANCE)
                       - (NVL(fl.limite,0) + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)) DESC) AS rn
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
                               AND g.AC_NATURAL_GL LIKE c_gl_like
            LEFT JOIN fac_lim fl ON fl.line_key = a.LINE_ID
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND ABS(a.ACY_CURR_BALANCE) >
                  NVL(fl.limite,0) + NVL(a.TOD_LIMIT,0) + NVL(a.SUBLIMIT,0)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde_deb),14) || ' |' || LPAD(fmt_m(d.autorise),14) || ' |'
            || LPAD(fmt_m(d.depass),14) || ' |'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),15) || '|');
    END LOOP;
    print_test('Comptes : solde debiteur > autorisation (ligne+TOD)', v_count);
    buf_print('4,12,24,20,5,15,15,15,15',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE DEB.',15) || '|' || RPAD(' AUTORISE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|'
        || RPAD(' OD DEPUIS',15) || '|');

    -- 1.5 Comptes marques en depassement de ligne par FLEXCUBE (OVERLINE)
    buf_reset;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               a.ACY_CURR_BALANCE AS solde, a.OVERLINE_OD_SINCE, a.OVERDRAFT_SINCE,
               TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) AS nb_jours,
               COUNT(*) OVER () AS tot_cnt,
               ROW_NUMBER() OVER (ORDER BY a.OVERLINE_OD_SINCE ASC) AS rn
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O' AND a.OVERLINE_OD_SINCE IS NOT NULL
    ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || fmt_d(d.OVERLINE_OD_SINCE),14) || '|'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),14) || '|'
            || LPAD(fmt_n(d.nb_jours),9) || ' |');
    END LOOP;
    print_test('Comptes en depassement de ligne (OVERLINE_OD_SINCE)', v_count);
    buf_print('4,12,24,20,5,15,14,14,10',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' OVERLINE LE',14) || '|' || RPAD(' OD DEPUIS',14) || '|'
        || RPAD(' JOURS',10) || '|');

    -- 1.6 Lignes portant un depassement exceptionnel enregistre
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.EXCEP_TXN_AMT,0) AS mnt_exc,
                   NVL(f.EXCEP_BREACH,0) AS nb_breach, f.DATE_OF_LAST_OD,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.EXCEP_TXN_AMT,0) DESC,
                                               NVL(f.EXCEP_BREACH,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE (NVL(f.EXCEP_BREACH,0) > 0 OR NVL(f.EXCEP_TXN_AMT,0) > 0)
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.mnt_exc),14) || ' |'
            || LPAD(fmt_n(d.nb_breach),13) || ' |'
            || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),14) || '|');
    END LOOP;
    print_test('Lignes avec depassement exceptionnel (EXCEP_BREACH)', v_count);
    buf_print('4,12,24,16,5,15,15,14,14',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' MNT EXCEPT.',15) || '|' || RPAD(' NB BREACH',14) || '|'
        || RPAD(' DERNIER OD',14) || '|');

    -- 1.7 Lignes dont l'utilisation depasse le montant approuve
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.APPROVED_AMT,0) AS approuve, NVL(f.LIMIT_AMOUNT,0) AS limite,
                   NVL(f.UTILISATION,0) AS util,
                   NVL(f.UTILISATION,0) - NVL(f.APPROVED_AMT,0) AS ecart,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) - NVL(f.APPROVED_AMT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.APPROVED_AMT,0) > 0
              AND NVL(f.UTILISATION,0) > NVL(f.APPROVED_AMT,0)
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.approuve),14) || ' |' || LPAD(fmt_m(d.limite),14) || ' |'
            || LPAD(fmt_m(d.util),14) || ' |' || LPAD(fmt_m(d.ecart),14) || ' |');
    END LOOP;
    print_test('Lignes : utilisation > montant approuve (APPROVED_AMT)', v_count);
    buf_print('4,12,24,16,5,15,15,15,15',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' APPROUVE',15) || '|' || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|'
        || RPAD(' ECART',15) || '|');

    -- 1.8 Sous-lignes dont l'utilisation cumulee depasse la ligne mere
    --     (la ligne mere doit appartenir au perimetre clientelise)
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT liab, nom, ligne_mere, nb_sous, limite_mere, util_cum, depass,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY depass DESC) AS rn
            FROM (
                SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                       p.LINE_CODE AS ligne_mere, COUNT(*) AS nb_sous,
                       NVL(p.LIMIT_AMOUNT,0) AS limite_mere,
                       NVL(SUM(f.UTILISATION),0) AS util_cum,
                       NVL(SUM(f.UTILISATION),0) - NVL(p.LIMIT_AMOUNT,0) AS depass
                FROM GETM_FACILITY f
                JOIN GETM_FACILITY p ON p.ID = f.MAIN_LINE_ID
                LEFT JOIN GETM_LIAB l ON l.ID = p.LIAB_ID
                WHERE f.MAIN_LINE_ID IS NOT NULL AND f.MAIN_LINE_ID != f.ID
                  AND p.ID IN (SELECT line_id FROM per_line)
                GROUP BY p.ID, l.LIAB_NO, l.LIAB_NAME, p.LINE_CODE, p.LIMIT_AMOUNT
                HAVING NVL(SUM(f.UTILISATION),0) > NVL(p.LIMIT_AMOUNT,0)
            )
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.ligne_mere,1,14),16) || '|' || LPAD(fmt_n(d.nb_sous),7) || ' |'
            || LPAD(fmt_m(d.limite_mere),14) || ' |' || LPAD(fmt_m(d.util_cum),14) || ' |'
            || LPAD(fmt_m(d.depass),14) || ' |');
    END LOOP;
    print_test('Sous-lignes : utilisation cumulee > ligne mere', v_count);
    buf_print('4,12,24,16,8,15,15,15',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE MERE',16) || '|' || RPAD(' NB SOUS',8) || '|'
        || RPAD(' LIMITE MERE',15) || '|' || RPAD(' UTIL. CUMULEE',15) || '|' || RPAD(' DEPASSEMENT',15) || '|');

    -- =========================================================
    -- SECTION 2 : OVERDRAFTS EXPIRES MAIS TOUJOURS UTILISES
    -- =========================================================
    -- Une ligne echue doit etre soit renouvelee formellement, soit
    -- apuree. Le maintien d'une utilisation apres l'echeance revient
    -- a accorder un concours sans decision de credit valide.
    -- PERIMETRE : lignes rattachees a un compte clientelise, comptes
    --      clientelises uniquement.
    -- =========================================================
    print_section('2. OVERDRAFTS EXPIRES MAIS TOUJOURS UTILISES');

    -- 2.1 Lignes expirees dont l'utilisation reste positive
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.LINE_EXPIRY_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_EXPIRY_DATE) AS nb_jours,
                   NVL(f.AVAILABILITY_FLAG,'-') AS dispo,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
              AND NVL(f.UTILISATION,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
            || LPAD(fmt_n(d.nb_jours),9) || ' |'
            || RPAD(' ' || d.dispo,6) || '|');
    END LOOP;
    print_test('Lignes expirees avec utilisation > 0', v_count);
    buf_print('4,12,24,16,5,15,15,13,10,6',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' EXPIRE LE',13) || '|'
        || RPAD(' J.RETARD',10) || '|' || RPAD(' DISPO',6) || '|');

    -- 2.2 Lignes expirees mais toujours declarees disponibles
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.AVAILABLE_AMOUNT,0) AS dispo,
                   f.LINE_EXPIRY_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_EXPIRY_DATE) AS nb_jours,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
              AND NVL(f.AVAILABILITY_FLAG,'N') = 'Y'
              AND f.RECORD_STAT = 'O'
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.dispo),14) || ' |'
            || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
            || LPAD(fmt_n(d.nb_jours),9) || ' |');
    END LOOP;
    print_test('Lignes expirees encore disponibles (AVAILABILITY=Y)', v_count);
    buf_print('4,12,24,16,5,15,15,13,10',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' DISPONIBLE',15) || '|' || RPAD(' EXPIRE LE',13) || '|'
        || RPAD(' J.RETARD',10) || '|');

    -- 2.3 Comptes debiteurs rattaches a une (ou des) ligne(s) toutes expirees
    --     La jointure a predicat OR sur la cle de ligne est remplacee par
    --     une equi-jointure sur fac_key (cle normalisee LINE_CODE / ID).
    buf_reset;
    FOR d IN (
        WITH fac_key AS (
            SELECT /*+ MATERIALIZE */ f.LINE_CODE AS line_key, f.LINE_EXPIRY_DATE
            FROM GETM_FACILITY f
            WHERE f.LINE_CODE IS NOT NULL
            UNION ALL
            SELECT TO_CHAR(f.ID), f.LINE_EXPIRY_DATE
            FROM GETM_FACILITY f
            WHERE f.LINE_CODE IS NULL OR TO_CHAR(f.ID) != f.LINE_CODE
        )
        SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   MIN(a.ACY_CURR_BALANCE) AS solde,
                   MAX(a.LINE_ID) AS ligne,
                   MAX(k.LINE_EXPIRY_DATE) AS expiry,
                   TRUNC(SYSDATE) - TRUNC(MAX(k.LINE_EXPIRY_DATE)) AS nb_jours,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY MIN(a.ACY_CURR_BALANCE) ASC) AS rn
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
                               AND g.AC_NATURAL_GL LIKE c_gl_like
            JOIN fac_key k ON k.line_key = a.LINE_ID
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
            GROUP BY a.CUST_NO, c.CUSTOMER_NAME1, a.CUST_AC_NO, a.CCY
            HAVING MAX(k.LINE_EXPIRY_DATE) < TRUNC(SYSDATE)
               AND COUNT(CASE WHEN k.LINE_EXPIRY_DATE IS NULL THEN 1 END) = 0
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.expiry),13) || '|'
            || LPAD(fmt_n(d.nb_jours),9) || ' |');
    END LOOP;
    print_test('Comptes debiteurs sur ligne(s) toutes expirees', v_count);
    buf_print('4,12,24,20,5,15,16,13,10',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' DERN. LIGNE',16) || '|' || RPAD(' EXPIREE LE',13) || '|'
        || RPAD(' J.RETARD',10) || '|');

    -- 2.4 TOD (decouverts temporaires) expires et compte toujours debiteur
    buf_reset;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               a.ACY_CURR_BALANCE AS solde, NVL(a.TOD_LIMIT,0) AS tod,
               a.TOD_LIMIT_START_DATE, a.TOD_LIMIT_END_DATE,
               TRUNC(SYSDATE) - TRUNC(a.TOD_LIMIT_END_DATE) AS nb_jours,
               COUNT(*) OVER () AS tot_cnt,
               ROW_NUMBER() OVER (ORDER BY a.TOD_LIMIT_END_DATE ASC) AS rn
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O'
          AND NVL(a.ACY_CURR_BALANCE,0) < 0
          AND NVL(a.TOD_LIMIT,0) > 0
          AND a.TOD_LIMIT_END_DATE IS NOT NULL
          AND a.TOD_LIMIT_END_DATE < TRUNC(SYSDATE)
    ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |' || LPAD(fmt_m(d.tod),14) || ' |'
            || RPAD(' ' || fmt_d(d.TOD_LIMIT_START_DATE),13) || '|'
            || RPAD(' ' || fmt_d(d.TOD_LIMIT_END_DATE),13) || '|'
            || LPAD(fmt_n(d.nb_jours),8) || ' |');
    END LOOP;
    print_test('TOD expires avec compte encore debiteur', v_count);
    buf_print('4,12,24,20,5,15,15,13,13,9',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' TOD',15) || '|' || RPAD(' DEBUT TOD',13) || '|'
        || RPAD(' FIN TOD',13) || '|' || RPAD(' J.RETARD',9) || '|');

    -- 2.5 Mouvements debiteurs enregistres APRES l'expiration de la ligne
    --     Le perimetre clientelise est applique AVANT la jointure sur
    --     ACTB_HISTORY, ce qui reduit fortement le volume a parcourir.
    buf_reset;
    FOR d IN (
        WITH fac_key AS (
            SELECT /*+ MATERIALIZE */ f.LINE_CODE AS line_key, f.LINE_EXPIRY_DATE
            FROM GETM_FACILITY f
            WHERE f.LINE_CODE IS NOT NULL
              AND f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
            UNION ALL
            SELECT TO_CHAR(f.ID), f.LINE_EXPIRY_DATE
            FROM GETM_FACILITY f
            WHERE (f.LINE_CODE IS NULL OR TO_CHAR(f.ID) != f.LINE_CODE)
              AND f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE)
        ),
        per_ac AS (
            SELECT /*+ MATERIALIZE */ a.CUST_AC_NO, a.CUST_NO, a.LINE_ID,
                   k.LINE_EXPIRY_DATE
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
                               AND g.AC_NATURAL_GL LIKE c_gl_like
            JOIN fac_key k ON k.line_key = a.LINE_ID
            WHERE a.RECORD_STAT = 'O'
        )
        SELECT * FROM (
            SELECT p.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, p.CUST_AC_NO,
                   MAX(p.LINE_ID) AS ligne, MAX(p.LINE_EXPIRY_DATE) AS expiry,
                   COUNT(*) AS nb_deb, SUM(h.LCY_AMOUNT) AS total_deb,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY SUM(h.LCY_AMOUNT) DESC) AS rn
            FROM per_ac p
            JOIN ACTB_HISTORY h ON h.AC_NO = p.CUST_AC_NO
                 AND h.DRCR_IND = 'D'
                 AND h.TRN_DT > p.LINE_EXPIRY_DATE
                 AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = p.CUST_NO
            GROUP BY p.CUST_NO, c.CUSTOMER_NAME1, p.CUST_AC_NO
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|'
            || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.expiry),13) || '|'
            || LPAD(fmt_n(d.nb_deb),8) || ' |'
            || LPAD(fmt_m(d.total_deb),16) || ' |');
    END LOOP;
    print_test('Comptes : debits posterieurs a l''expiration de la ligne', v_count);
    buf_print('4,12,24,20,16,13,9,17',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' LIGNE',16) || '|' || RPAD(' EXPIREE LE',13) || '|'
        || RPAD(' NB DEBITS',9) || '|' || RPAD(' TOTAL DEBITS',17) || '|');

    -- 2.6 Lignes utilisees sans date d'expiration (concours perpetuel)
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.LINE_START_DATE,
                   TRUNC(SYSDATE) - TRUNC(f.LINE_START_DATE) AS anciennete,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_EXPIRY_DATE IS NULL
              AND NVL(f.UTILISATION,0) > 0
              AND f.RECORD_STAT = 'O'
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || fmt_d(d.LINE_START_DATE),13) || '|'
            || LPAD(fmt_n(d.anciennete) || ' j',10) || ' |');
    END LOOP;
    print_test('Lignes utilisees sans date d''expiration', v_count);
    buf_print('4,12,24,16,5,15,15,13,11',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' DEBUT LE',13) || '|'
        || RPAD(' ANCIENNETE',11) || '|');

    -- 2.7 Incoherences de dates sur les lignes (expiration <= debut)
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, f.LINE_START_DATE, f.LINE_EXPIRY_DATE,
                   NVL(f.UTILISATION,0) AS util,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.LINE_START_DATE IS NOT NULL AND f.LINE_EXPIRY_DATE IS NOT NULL
              AND f.LINE_EXPIRY_DATE <= f.LINE_START_DATE
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |'
            || RPAD(' ' || fmt_d(d.LINE_START_DATE),13) || '|'
            || RPAD(' ' || fmt_d(d.LINE_EXPIRY_DATE),13) || '|'
            || LPAD(fmt_m(d.util),14) || ' |');
    END LOOP;
    print_test('Lignes : date d''expiration <= date de debut', v_count);
    buf_print('4,12,24,16,5,15,13,13,15',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' DEBUT',13) || '|' || RPAD(' EXPIRATION',13) || '|'
        || RPAD(' UTILISE',15) || '|');

    -- =========================================================
    -- SECTION 3 : OVERDRAFTS SANS APPROBATION IDENTIFIABLE
    -- =========================================================
    -- Tout concours doit etre rattachable a une decision de credit
    -- formalisee et a un valideur distinct de l'initiateur
    -- (principe des quatre yeux / separation des taches).
    -- PERIMETRE : lignes rattachees a un compte clientelise, comptes
    --      clientelises uniquement.
    -- =========================================================
    print_section('3. OVERDRAFTS SANS APPROBATION IDENTIFIABLE');

    -- 3.1 Lignes non autorisees dans le systeme mais deja utilisees
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.AUTH_STAT,'-') AS auth, NVL(f.MAKER_ID,'-') AS maker, f.MAKER_DT_STAMP,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.UTILISATION,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.AUTH_STAT,'U') != 'A'
              AND NVL(f.UTILISATION,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || d.auth,6) || '|' || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
    END LOOP;
    print_test('Lignes non autorisees (AUTH_STAT != A) et utilisees', v_count);
    buf_print('4,12,24,16,5,15,15,6,16,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' AUTH',6) || '|'
        || RPAD(' MAKER',16) || '|' || RPAD(' SAISIE LE',13) || '|');

    -- 3.2 Lignes ouvertes sans valideur identifie (CHECKER_ID absent)
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.MAKER_ID,'-') AS maker, f.MAKER_DT_STAMP,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O'
              AND TRIM(f.CHECKER_ID) IS NULL
              AND NVL(f.LIMIT_AMOUNT,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
    END LOOP;
    print_test('Lignes sans valideur identifie (CHECKER_ID absent)', v_count);
    buf_print('4,12,24,16,5,15,15,16,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' MAKER',16) || '|'
        || RPAD(' SAISIE LE',13) || '|');

    -- 3.3 Lignes auto-approuvees (initiateur = valideur)
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.MAKER_ID AS usr, f.CHECKER_DT_STAMP,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.MAKER_ID IS NOT NULL AND f.CHECKER_ID IS NOT NULL
              AND UPPER(TRIM(f.MAKER_ID)) = UPPER(TRIM(f.CHECKER_ID))
              AND NVL(f.LIMIT_AMOUNT,0) > 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
    END LOOP;
    print_test('Lignes auto-approuvees (MAKER_ID = CHECKER_ID)', v_count);
    buf_print('4,12,24,16,5,15,15,16,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' UTILISATEUR',16) || '|'
        || RPAD(' VALIDE LE',13) || '|');

    -- 3.4 Lignes accordees sans montant approuve renseigne
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   f.LINE_CODE, NVL(f.LINE_CURRENCY,'-') AS ccy,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   NVL(f.CHECKER_ID,'-') AS checker, f.CHECKER_DT_STAMP,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY NVL(f.LIMIT_AMOUNT,0) DESC) AS rn
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O'
              AND NVL(f.LIMIT_AMOUNT,0) > 0
              AND NVL(f.APPROVED_AMT,0) = 0
              AND f.ID IN (SELECT line_id FROM per_line)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
            || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|'
            || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
    END LOOP;
    print_test('Lignes avec limite > 0 mais APPROVED_AMT absent', v_count);
    buf_print('4,12,24,16,5,15,15,16,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
        || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|' || RPAD(' CHECKER',16) || '|'
        || RPAD(' VALIDE LE',13) || '|');

    -- 3.5 Comptes debiteurs sans aucune autorisation (ni ligne, ni TOD)
    --     => decouvert de fait, accorde hors dispositif
    buf_reset;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
               NVL(a.ACCOUNT_CLASS,'-') AS cl, NVL(a.BRANCH_CODE,'-') AS brn,
               COUNT(*) OVER () AS tot_cnt,
               ROW_NUMBER() OVER (ORDER BY a.LCY_CURR_BALANCE ASC) AS rn
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O'
          AND NVL(a.ACY_CURR_BALANCE,0) < 0
          AND TRIM(a.LINE_ID) IS NULL
          AND NVL(a.TOD_LIMIT,0) = 0
          AND NVL(a.SUBLIMIT,0) = 0
    ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
            || RPAD(' ' || SUBSTR(d.cl,1,11),13) || '|'
            || RPAD(' ' || d.brn,14) || '|');
    END LOOP;
    print_test('Comptes debiteurs sans ligne ni TOD (decouvert de fait)', v_count);
    buf_print('4,12,24,20,5,15,13,13,14',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' OD DEPUIS',13) || '|' || RPAD(' CL. COMPTE',13) || '|'
        || RPAD(' AGENCE',14) || '|');

    -- 3.6 TOD accordes sans periode de validite renseignee
    buf_reset;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               NVL(a.TOD_LIMIT,0) AS tod, a.ACY_CURR_BALANCE AS solde,
               a.TOD_LIMIT_START_DATE, a.TOD_LIMIT_END_DATE,
               COUNT(*) OVER () AS tot_cnt,
               ROW_NUMBER() OVER (ORDER BY NVL(a.TOD_LIMIT,0) DESC) AS rn
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O'
          AND NVL(a.TOD_LIMIT,0) > 0
          AND (a.TOD_LIMIT_START_DATE IS NULL OR a.TOD_LIMIT_END_DATE IS NULL)
    ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.tod),14) || ' |' || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || fmt_d(d.TOD_LIMIT_START_DATE),13) || '|'
            || RPAD(' ' || fmt_d(d.TOD_LIMIT_END_DATE),13) || '|');
    END LOOP;
    print_test('TOD sans periode de validite (dates absentes)', v_count);
    buf_print('4,12,24,20,5,15,15,13,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' TOD',15) || '|' || RPAD(' SOLDE',15) || '|' || RPAD(' DEBUT TOD',13) || '|'
        || RPAD(' FIN TOD',13) || '|');

    -- 3.7 Comptes debiteurs sur une classe n'autorisant pas le decouvert
    buf_reset;
    FOR d IN (SELECT * FROM (
        SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
               a.ACY_CURR_BALANCE AS solde, a.ACCOUNT_CLASS AS cl,
               NVL(ac.DESCRIPTION,'-') AS cl_lib, NVL(ac.OVERDRAFT_FACILITY,'-') AS od_fac,
               COUNT(*) OVER () AS tot_cnt,
               ROW_NUMBER() OVER (ORDER BY a.LCY_CURR_BALANCE ASC) AS rn
        FROM STTM_CUST_ACCOUNT a
        JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                           AND g.BRANCH_CODE = a.BRANCH_CODE
                           AND g.AC_NATURAL_GL LIKE c_gl_like
        JOIN STTM_ACCOUNT_CLASS ac ON ac.ACCOUNT_CLASS = a.ACCOUNT_CLASS
        LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
        WHERE a.RECORD_STAT = 'O'
          AND NVL(a.ACY_CURR_BALANCE,0) < 0
          AND NVL(ac.OVERDRAFT_FACILITY,'N') != 'Y'
    ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || SUBSTR(d.cl,1,10),12) || '|'
            || RPAD(' ' || SUBSTR(d.cl_lib,1,24),26) || '|'
            || RPAD(' ' || d.od_fac,7) || '|');
    END LOOP;
    print_test('Comptes debiteurs sur classe sans OVERDRAFT_FACILITY', v_count);
    buf_print('4,12,24,20,5,15,12,26,7',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' CLASSE',12) || '|' || RPAD(' LIBELLE CLASSE',26) || '|'
        || RPAD(' OD FAC.',7) || '|');

    -- 3.8 Comptes rattaches a une LINE_ID inexistante dans GETM_FACILITY
    --     Le NOT EXISTS correle a predicat OR (balayage complet de
    --     GETM_FACILITY par compte) est remplace par un anti-join sur la
    --     cle de ligne normalisee fac_key, materialisee une seule fois.
    buf_reset;
    FOR d IN (
        WITH fac_key AS (
            SELECT /*+ MATERIALIZE */ f.LINE_CODE AS line_key
            FROM GETM_FACILITY f
            WHERE f.LINE_CODE IS NOT NULL
            UNION
            SELECT TO_CHAR(f.ID)
            FROM GETM_FACILITY f
        )
        SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.LINE_ID, a.OVERDRAFT_SINCE,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY a.LCY_CURR_BALANCE ASC) AS rn
            FROM STTM_CUST_ACCOUNT a
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO    = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
                               AND g.AC_NATURAL_GL LIKE c_gl_like
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND TRIM(a.LINE_ID) IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM fac_key k WHERE k.line_key = a.LINE_ID)
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
            || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
            || LPAD(fmt_m(d.solde),14) || ' |'
            || RPAD(' ' || SUBSTR(d.LINE_ID,1,16),18) || '|'
            || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|');
    END LOOP;
    print_test('Comptes rattaches a une ligne inexistante (LINE_ID orpheline)', v_count);
    buf_print('4,12,24,20,5,15,18,13',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
        || RPAD(' SOLDE',15) || '|' || RPAD(' LINE_ID INCONNUE',18) || '|' || RPAD(' OD DEPUIS',13) || '|');

    -- 3.9 Liabilities non autorisees portant des lignes utilisees
    buf_reset;
    FOR d IN (
        WITH per_line AS (
            SELECT /*+ MATERIALIZE */ f.ID AS line_id
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = f.LINE_CODE
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
            UNION
            SELECT f.ID
            FROM GETM_FACILITY f
            JOIN STTM_CUST_ACCOUNT a ON a.LINE_ID = TO_CHAR(f.ID)
            JOIN STTB_ACCOUNT g ON g.AC_GL_NO = a.CUST_AC_NO
                               AND g.BRANCH_CODE = a.BRANCH_CODE
            WHERE g.AC_NATURAL_GL LIKE c_gl_like
        )
        SELECT * FROM (
            SELECT liab, nom, auth, lim_glob, util, nb_lignes, maker,
                   COUNT(*) OVER () AS tot_cnt,
                   ROW_NUMBER() OVER (ORDER BY util DESC) AS rn
            FROM (
                SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                       NVL(l.AUTH_STAT,'-') AS auth, NVL(l.OVERALL_LIMIT,0) AS lim_glob,
                       NVL(SUM(f.UTILISATION),0) AS util, COUNT(*) AS nb_lignes,
                       NVL(MAX(l.MAKER_ID),'-') AS maker
                FROM GETM_LIAB l
                JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
                WHERE NVL(l.AUTH_STAT,'U') != 'A'
                  AND NVL(f.UTILISATION,0) > 0
                  AND f.ID IN (SELECT line_id FROM per_line)
                GROUP BY l.ID, l.LIAB_NO, l.LIAB_NAME, l.AUTH_STAT, l.OVERALL_LIMIT
            )
        ) WHERE rn <= c_max_rows ORDER BY rn) LOOP
        v_count := d.tot_cnt;
        buf_add('  |' || LPAD(d.rn,3) || ' |'
            || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
            || RPAD(' ' || d.auth,8) || '|'
            || LPAD(fmt_m(d.lim_glob),15) || ' |' || LPAD(fmt_m(d.util),15) || ' |'
            || LPAD(fmt_n(d.nb_lignes),7) || ' |'
            || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|');
    END LOOP;
    print_test('Liabilities non autorisees avec lignes utilisees', v_count);
    buf_print('4,12,26,8,16,16,8,16',
        '  |' || RPAD(' N#',4) || '|' || RPAD(' LIAB_NO',12) || '|' || RPAD(' NOM',26) || '|'
        || RPAD(' AUTH',8) || '|' || RPAD(' LIMITE GLOB.',16) || '|' || RPAD(' UTIL. CUMULEE',16) || '|'
        || RPAD(' NB LIGNES',8) || '|' || RPAD(' MAKER',16) || '|');

    -- =========================================================
    -- SECTION 4 : OVERDRAFTS DEPASSES PENDANT UNE LONGUE PERIODE
    -- =========================================================
    -- Un decouvert durablement immobilise n'est plus une facilite de
    -- tresorerie mais un credit de fait : il doit etre consolide,
    -- provisionne et declasse selon les regles prudentielles.
    -- =========================================================
    print_section('4. OVERDRAFTS DEPASSES PENDANT UNE LONGUE PERIODE');

    -- Ventilation de l'anciennete des positions debitrices (informatif)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Anciennete des positions debitrices — OVERDRAFT_SINCE]');
    FOR d IN (SELECT tranche, COUNT(*) AS nb, NVL(SUM(ABS(solde)),0) AS mnt
              FROM (SELECT CASE
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 30  THEN '1. 0 a 30 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 90  THEN '2. 31 a 90 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 180 THEN '3. 91 a 180 jours'
                             WHEN TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) <= 365 THEN '4. 181 a 365 jours'
                             ELSE '5. plus de 365 jours'
                           END AS tranche,
                           a.LCY_CURR_BALANCE AS solde
                    FROM STTM_CUST_ACCOUNT a
                    WHERE a.RECORD_STAT = 'O'
                      AND NVL(a.ACY_CURR_BALANCE,0) < 0
                      AND a.OVERDRAFT_SINCE IS NOT NULL)
              GROUP BY tranche
              ORDER BY tranche) LOOP
        print_info(d.tranche, fmt_n(d.nb) || ' compte(s) — ' || fmt_m(d.mnt));
    END LOOP;

    -- 4.1 Comptes en position debitrice depuis plus de c_jours_long
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND a.OVERDRAFT_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_long;
    print_test('Comptes debiteurs depuis plus de ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,13,9,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OD DEPUIS',13) || '|' || RPAD(' JOURS',9) || '|'
            || RPAD(' INT. DUS',15) || '|');
        tbl_line('4,12,24,20,5,15,13,9,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) AS nb_jours,
                   NVL(a.DR_INT_DUE,0) AS int_dus
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND a.OVERDRAFT_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_long
            ORDER BY a.OVERDRAFT_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || LPAD(fmt_m(d.int_dus),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,13,9,15');
    END IF;

    -- 4.2 Comptes en depassement de ligne depuis plus de c_jours_long
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.OVERLINE_OD_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) > c_jours_long;
    print_test('Comptes en depassement de ligne > ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,14,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' OVERLINE LE',14) || '|' || RPAD(' JOURS',9) || '|'
            || RPAD(' LIGNE',16) || '|');
        tbl_line('4,12,24,20,5,15,14,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERLINE_OD_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) AS nb_jours,
                   NVL(a.LINE_ID,'-') AS ligne
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.OVERLINE_OD_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.OVERLINE_OD_SINCE) > c_jours_long
            ORDER BY a.OVERLINE_OD_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |'
                || RPAD(' ' || fmt_d(d.OVERLINE_OD_SINCE),14) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,15,14,9,16');
    END IF;

    -- 4.3 TOD utilises au-dela de la duree normale d'un decouvert temporaire
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.TOD_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) > c_jours_tod_max;
    print_test('TOD en cours depuis plus de ' || c_jours_tod_max || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,15,15,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',15) || '|' || RPAD(' TOD',15) || '|' || RPAD(' TOD DEPUIS',13) || '|'
            || RPAD(' JOURS',9) || '|');
        tbl_line('4,12,24,20,5,15,15,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, NVL(a.TOD_LIMIT,0) AS tod, a.TOD_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) AS nb_jours
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.TOD_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.TOD_SINCE) > c_jours_tod_max
            ORDER BY a.TOD_SINCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),14) || ' |' || LPAD(fmt_m(d.tod),14) || ' |'
                || RPAD(' ' || fmt_d(d.TOD_SINCE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,5,15,15,13,9');
    END IF;

    -- 4.4 Lignes en depassement dont le premier decouvert est ancien
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE f.DATE_OF_FIRST_OD IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) > c_jours_tres_long
      AND NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0);
    print_test('Lignes en depassement depuis plus de ' || c_jours_tres_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,15,15,13,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' LIMITE',15) || '|' || RPAD(' UTILISE',15) || '|'
            || RPAD(' 1er OD LE',13) || '|' || RPAD(' DERN. OD LE',13) || '|' || RPAD(' JOURS',9) || '|');
        tbl_line('4,12,24,16,15,15,13,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, f.LINE_CODE,
                   NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                   f.DATE_OF_FIRST_OD, f.DATE_OF_LAST_OD,
                   TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) AS nb_jours
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.DATE_OF_FIRST_OD IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(f.DATE_OF_FIRST_OD) > c_jours_tres_long
              AND NVL(f.UTILISATION,0) > NVL(f.LIMIT_AMOUNT,0)
            ORDER BY f.DATE_OF_FIRST_OD ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|'
                || LPAD(fmt_m(d.limite),14) || ' |' || LPAD(fmt_m(d.util),14) || ' |'
                || RPAD(' ' || fmt_d(d.DATE_OF_FIRST_OD),13) || '|'
                || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |');
        END LOOP;
        tbl_line('4,12,24,16,15,15,13,13,9');
    END IF;

    -- 4.5 Plus longue periode CONTINUE de solde debiteur sur la periode
    --     (reconstituee a partir des soldes journaliers ACTB_ACCBAL_HISTORY)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT ACCOUNT
        FROM (
            SELECT ACCOUNT, grp, MAX(BKG_DATE) - MIN(BKG_DATE) + 1 AS duree
            FROM (
                SELECT ACCOUNT, BKG_DATE,
                       SUM(top_dep) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS grp
                FROM (
                    SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                           CASE WHEN NVL(LAG(ACY_CLOSING_BAL)
                                OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE),0) < 0
                                THEN 0 ELSE 1 END AS top_dep
                    FROM ACTB_ACCBAL_HISTORY
                    WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                )
                WHERE ACY_CLOSING_BAL < 0
            )
            GROUP BY ACCOUNT, grp
        )
        GROUP BY ACCOUNT
        HAVING MAX(duree) > c_jours_long
    );
    print_test('Comptes : periode continue debitrice > ' || c_jours_long || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,13,13,9,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' DEBUT',13) || '|' || RPAD(' FIN',13) || '|'
            || RPAD(' DUREE(j)',9) || '|' || RPAD(' PIRE SOLDE',16) || '|');
        tbl_line('4,12,24,20,13,13,9,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT x.ACCOUNT, NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   x.deb, x.fin, x.duree, x.pire
            FROM (
                SELECT ACCOUNT, deb, fin, duree, pire,
                       ROW_NUMBER() OVER (PARTITION BY ACCOUNT ORDER BY duree DESC) AS rn
                FROM (
                    SELECT ACCOUNT, grp, MIN(BKG_DATE) AS deb, MAX(BKG_DATE) AS fin,
                           MAX(BKG_DATE) - MIN(BKG_DATE) + 1 AS duree,
                           MIN(ACY_CLOSING_BAL) AS pire
                    FROM (
                        SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                               SUM(top_dep) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS grp
                        FROM (
                            SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                                   CASE WHEN NVL(LAG(ACY_CLOSING_BAL)
                                        OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE),0) < 0
                                        THEN 0 ELSE 1 END AS top_dep
                            FROM ACTB_ACCBAL_HISTORY
                            WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                        )
                        WHERE ACY_CLOSING_BAL < 0
                    )
                    GROUP BY ACCOUNT, grp
                )
            ) x
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = x.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE x.rn = 1 AND x.duree > c_jours_long
            ORDER BY x.duree DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || RPAD(' ' || fmt_d(d.deb),13) || '|' || RPAD(' ' || fmt_d(d.fin),13) || '|'
                || LPAD(fmt_n(d.duree),8) || ' |'
                || LPAD(fmt_m(d.pire),15) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,13,13,9,16');
    END IF;

    -- 4.6 Comptes jamais revenus en position creditrice sur la periode
    --     => decouvert structurel (credit deguise)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT h.ACCOUNT
        FROM ACTB_ACCBAL_HISTORY h
        WHERE h.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        GROUP BY h.ACCOUNT
        HAVING MAX(h.ACY_CLOSING_BAL) < 0
           AND COUNT(*) >= c_jours_long
    );
    print_test('Comptes constamment debiteurs sur ' || c_mois_hist || ' mois', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,9,16,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' NB JOURS',9) || '|'
            || RPAD(' SOLDE MOYEN',16) || '|' || RPAD(' PIRE SOLDE',16) || '|' || RPAD(' SOLDE FINAL',16) || '|');
        tbl_line('4,12,24,20,9,16,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT x.ACCOUNT, NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom,
                   x.nb_jours, x.moyen, x.pire, x.dernier
            FROM (
                SELECT h.ACCOUNT, COUNT(*) AS nb_jours, AVG(h.ACY_CLOSING_BAL) AS moyen,
                       MIN(h.ACY_CLOSING_BAL) AS pire,
                       MAX(h.ACY_CLOSING_BAL) KEEP (DENSE_RANK LAST ORDER BY h.BKG_DATE) AS dernier
                FROM ACTB_ACCBAL_HISTORY h
                WHERE h.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                GROUP BY h.ACCOUNT
                HAVING MAX(h.ACY_CLOSING_BAL) < 0
                   AND COUNT(*) >= c_jours_long
            ) x
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = x.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            ORDER BY x.pire ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || LPAD(fmt_m(d.moyen),15) || ' |' || LPAD(fmt_m(d.pire),15) || ' |'
                || LPAD(fmt_m(d.dernier),15) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,9,16,16,16');
    END IF;

    -- =========================================================
    -- SECTION 5 : CLIENTS AVEC PLUSIEURS OVERDRAFTS
    -- =========================================================
    -- Le fractionnement des concours sur plusieurs lignes, comptes ou
    -- agences masque l'exposition reelle sur un meme risque et peut
    -- servir a contourner la grille de delegation.
    -- =========================================================
    print_section('5. CLIENTS AVEC PLUSIEURS OVERDRAFTS');

    -- 5.1 Clients (liabilities) portant plusieurs lignes utilisees
    SELECT COUNT(*) INTO v_count FROM (
        SELECT f.LIAB_ID
        FROM GETM_FACILITY f
        WHERE NVL(f.UTILISATION,0) > 0 AND f.RECORD_STAT = 'O'
        GROUP BY f.LIAB_ID
        HAVING COUNT(*) > 1
    );
    print_test('Clients avec plusieurs lignes utilisees simultanement', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,9,16,16,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',26) || '|'
            || RPAD(' NB LIGNES',9) || '|' || RPAD(' LIMITES CUM.',16) || '|' || RPAD(' UTIL. CUMULEE',16) || '|'
            || RPAD(' DISPO CUM.',16) || '|' || RPAD(' 1re EXPIR.',13) || '|');
        tbl_line('4,12,26,9,16,16,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   COUNT(*) AS nb_lignes, NVL(SUM(f.LIMIT_AMOUNT),0) AS lim_cum,
                   NVL(SUM(f.UTILISATION),0) AS util_cum, NVL(SUM(f.AVAILABLE_AMOUNT),0) AS dispo_cum,
                   MIN(f.LINE_EXPIRY_DATE) AS exp_min
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.UTILISATION,0) > 0 AND f.RECORD_STAT = 'O'
            GROUP BY f.LIAB_ID, l.LIAB_NO, l.LIAB_NAME
            HAVING COUNT(*) > 1
            ORDER BY NVL(SUM(f.UTILISATION),0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || LPAD(fmt_n(d.nb_lignes),8) || ' |'
                || LPAD(fmt_m(d.lim_cum),15) || ' |' || LPAD(fmt_m(d.util_cum),15) || ' |'
                || LPAD(fmt_m(d.dispo_cum),15) || ' |'
                || RPAD(' ' || fmt_d(d.exp_min),13) || '|');
        END LOOP;
        tbl_line('4,12,26,9,16,16,16,13');
    END IF;

    -- 5.2 Clients avec plusieurs comptes en position debitrice
    SELECT COUNT(*) INTO v_count FROM (
        SELECT a.CUST_NO
        FROM STTM_CUST_ACCOUNT a
        WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
        GROUP BY a.CUST_NO
        HAVING COUNT(*) > 1
    );
    print_test('Clients avec plusieurs comptes debiteurs', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,10,17,17,13,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',26) || '|'
            || RPAD(' NB CPTES',10) || '|' || RPAD(' ENCOURS DEB.',17) || '|' || RPAD(' PIRE COMPTE',17) || '|'
            || RPAD(' + ANCIEN OD',13) || '|' || RPAD(' NB AG.',9) || '|');
        tbl_line('4,12,26,10,17,17,13,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(MAX(c.CUSTOMER_NAME1),'-') AS nom, COUNT(*) AS nb_cptes,
                   SUM(a.LCY_CURR_BALANCE) AS encours, MIN(a.LCY_CURR_BALANCE) AS pire,
                   MIN(a.OVERDRAFT_SINCE) AS od_depuis,
                   COUNT(DISTINCT a.BRANCH_CODE) AS nb_ag
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
            GROUP BY a.CUST_NO
            HAVING COUNT(*) > 1
            ORDER BY SUM(a.LCY_CURR_BALANCE) ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || LPAD(fmt_n(d.nb_cptes),9) || ' |'
                || LPAD(fmt_m(d.encours),16) || ' |' || LPAD(fmt_m(d.pire),16) || ' |'
                || RPAD(' ' || fmt_d(d.od_depuis),13) || '|'
                || LPAD(fmt_n(d.nb_ag),8) || ' |');
        END LOOP;
        tbl_line('4,12,26,10,17,17,13,9');
    END IF;

    -- 5.3 Clients dont les lignes sont portees par plusieurs agences
    SELECT COUNT(*) INTO v_count FROM (
        SELECT f.LIAB_ID
        FROM GETM_FACILITY f
        WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
        GROUP BY f.LIAB_ID
        HAVING COUNT(DISTINCT f.BRN) > 1
    );
    print_test('Clients avec des lignes dans plusieurs agences', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,9,8,16,16,20');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',26) || '|'
            || RPAD(' NB LIGNES',9) || '|' || RPAD(' NB AG.',8) || '|'
            || RPAD(' LIMITES CUM.',16) || '|' || RPAD(' UTIL. CUMULEE',16) || '|' || RPAD(' AGENCES',20) || '|');
        tbl_line('4,12,26,9,8,16,16,20');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT liab, nom, COUNT(*) AS nb_lignes, COUNT(DISTINCT brn) AS nb_ag,
                   NVL(SUM(limite),0) AS lim_cum, NVL(SUM(util),0) AS util_cum,
                   LISTAGG(CASE WHEN rn_brn = 1 THEN brn END, ',')
                       WITHIN GROUP (ORDER BY brn) AS agences
            FROM (
                SELECT f.LIAB_ID AS liab_id, NVL(l.LIAB_NO,'-') AS liab,
                       NVL(l.LIAB_NAME,'-') AS nom, NVL(f.BRN,'-') AS brn,
                       NVL(f.LIMIT_AMOUNT,0) AS limite, NVL(f.UTILISATION,0) AS util,
                       ROW_NUMBER() OVER (PARTITION BY f.LIAB_ID, f.BRN ORDER BY f.ID) AS rn_brn
                FROM GETM_FACILITY f
                LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
                WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
            )
            GROUP BY liab_id, liab, nom
            HAVING COUNT(DISTINCT brn) > 1
            ORDER BY NVL(SUM(limite),0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || LPAD(fmt_n(d.nb_lignes),8) || ' |' || LPAD(fmt_n(d.nb_ag),7) || ' |'
                || LPAD(fmt_m(d.lim_cum),15) || ' |' || LPAD(fmt_m(d.util_cum),15) || ' |'
                || RPAD(' ' || SUBSTR(d.agences,1,18),20) || '|');
        END LOOP;
        tbl_line('4,12,26,9,8,16,16,20');
    END IF;

    -- 5.4 Clients dont l'utilisation cumulee depasse la limite globale
    SELECT COUNT(*) INTO v_count FROM (
        SELECT l.ID
        FROM GETM_LIAB l
        JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
        WHERE NVL(l.OVERALL_LIMIT,0) > 0
        GROUP BY l.ID, l.OVERALL_LIMIT
        HAVING NVL(SUM(f.UTILISATION),0) > NVL(l.OVERALL_LIMIT,0)
    );
    print_test('Clients : utilisation cumulee > limite globale (LIAB)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,9,17,17,17,7');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',26) || '|'
            || RPAD(' NB LIGNES',9) || '|' || RPAD(' LIMITE GLOB.',17) || '|' || RPAD(' UTIL. CUMULEE',17) || '|'
            || RPAD(' DEPASSEMENT',17) || '|' || RPAD(' RATING',7) || '|');
        tbl_line('4,12,26,9,17,17,17,7');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, COUNT(*) AS nb_lignes,
                   NVL(l.OVERALL_LIMIT,0) AS lim_glob, NVL(SUM(f.UTILISATION),0) AS util_cum,
                   NVL(SUM(f.UTILISATION),0) - NVL(l.OVERALL_LIMIT,0) AS depass,
                   NVL(MAX(l.CREDIT_RATING),'-') AS rating
            FROM GETM_LIAB l
            JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
            WHERE NVL(l.OVERALL_LIMIT,0) > 0
            GROUP BY l.ID, l.LIAB_NO, l.LIAB_NAME, l.OVERALL_LIMIT
            HAVING NVL(SUM(f.UTILISATION),0) > NVL(l.OVERALL_LIMIT,0)
            ORDER BY NVL(SUM(f.UTILISATION),0) - NVL(l.OVERALL_LIMIT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || LPAD(fmt_n(d.nb_lignes),8) || ' |'
                || LPAD(fmt_m(d.lim_glob),16) || ' |' || LPAD(fmt_m(d.util_cum),16) || ' |'
                || LPAD(fmt_m(d.depass),16) || ' |'
                || RPAD(' ' || SUBSTR(d.rating,1,5),7) || '|');
        END LOOP;
        tbl_line('4,12,26,9,17,17,17,7');
    END IF;

    -- 5.5 Comptes cumulant une ligne de credit ET un TOD
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.LINE_ID IS NOT NULL AND TRIM(a.LINE_ID) IS NOT NULL
      AND NVL(a.TOD_LIMIT,0) > 0
      AND EXISTS (SELECT 1 FROM GETM_FACILITY f
                  WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                    AND NVL(f.LIMIT_AMOUNT,0) > 0);
    print_test('Comptes cumulant une ligne de credit et un TOD', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,16,15,15,15');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' LIGNE',16) || '|'
            || RPAD(' LIMITE LIGNE',15) || '|' || RPAD(' TOD',15) || '|' || RPAD(' SOLDE',15) || '|');
        tbl_line('4,12,24,20,16,15,15,15');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, a.LINE_ID,
                   NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                        WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)),0) AS lim_ligne,
                   NVL(a.TOD_LIMIT,0) AS tod, a.ACY_CURR_BALANCE AS solde
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.LINE_ID IS NOT NULL AND TRIM(a.LINE_ID) IS NOT NULL
              AND NVL(a.TOD_LIMIT,0) > 0
              AND EXISTS (SELECT 1 FROM GETM_FACILITY f
                          WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                            AND NVL(f.LIMIT_AMOUNT,0) > 0)
            ORDER BY NVL(a.TOD_LIMIT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || SUBSTR(d.LINE_ID,1,14),16) || '|'
                || LPAD(fmt_m(d.lim_ligne),14) || ' |' || LPAD(fmt_m(d.tod),14) || ' |'
                || LPAD(fmt_m(d.solde),14) || ' |');
        END LOOP;
        tbl_line('4,12,24,20,16,15,15,15');
    END IF;

    -- 5.6 Groupes de risque regroupant plusieurs liabilities utilisatrices
    SELECT COUNT(*) INTO v_count FROM (
        SELECT l.MAIN_LIAB_ID
        FROM GETM_LIAB l
        JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
        WHERE l.MAIN_LIAB_ID IS NOT NULL
          AND NVL(f.UTILISATION,0) > 0
        GROUP BY l.MAIN_LIAB_ID
        HAVING COUNT(DISTINCT l.ID) > 1
    );
    print_test('Groupes de risque avec plusieurs liabilities utilisatrices', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,26,9,9,17,17,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' GROUPE',12) || '|' || RPAD(' NOM GROUPE',26) || '|'
            || RPAD(' NB LIAB',9) || '|' || RPAD(' NB LIGNES',9) || '|'
            || RPAD(' LIMITES CUM.',17) || '|' || RPAD(' UTIL. CUMULEE',17) || '|' || RPAD(' LIMITE GROUPE',17) || '|');
        tbl_line('4,12,26,9,9,17,17,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(m.LIAB_NO, TO_CHAR(l.MAIN_LIAB_ID)) AS groupe,
                   NVL(m.LIAB_NAME,'-') AS nom,
                   COUNT(DISTINCT l.ID) AS nb_liab, COUNT(*) AS nb_lignes,
                   NVL(SUM(f.LIMIT_AMOUNT),0) AS lim_cum, NVL(SUM(f.UTILISATION),0) AS util_cum,
                   NVL(MAX(m.OVERALL_LIMIT),0) AS lim_groupe
            FROM GETM_LIAB l
            JOIN GETM_FACILITY f ON f.LIAB_ID = l.ID
            LEFT JOIN GETM_LIAB m ON m.ID = l.MAIN_LIAB_ID
            WHERE l.MAIN_LIAB_ID IS NOT NULL
              AND NVL(f.UTILISATION,0) > 0
            GROUP BY l.MAIN_LIAB_ID, m.LIAB_NO, m.LIAB_NAME
            HAVING COUNT(DISTINCT l.ID) > 1
            ORDER BY NVL(SUM(f.UTILISATION),0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || SUBSTR(d.groupe,1,10),12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
                || LPAD(fmt_n(d.nb_liab),8) || ' |' || LPAD(fmt_n(d.nb_lignes),8) || ' |'
                || LPAD(fmt_m(d.lim_cum),16) || ' |' || LPAD(fmt_m(d.util_cum),16) || ' |'
                || LPAD(fmt_m(d.lim_groupe),16) || ' |');
        END LOOP;
        tbl_line('4,12,26,9,9,17,17,17');
    END IF;

    -- =========================================================
    -- SECTION 6 : AUGMENTATIONS DE LIMITES IMPORTANTES
    -- =========================================================
    -- L'historique value-date des limites (GETM_FACILITY_VD_DETAILS)
    -- permet de reconstituer les revisions successives d'une ligne et
    -- d'identifier les hausses qui auraient du relever d'un niveau de
    -- delegation superieur ou d'une nouvelle decision de credit.
    -- =========================================================
    print_section('6. AUGMENTATIONS DE LIMITES IMPORTANTES');

    -- Volumetrie des revisions de limites (informatif)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Revisions de limites par annee — GETM_FACILITY_VD_DETAILS]');
    FOR d IN (SELECT TO_CHAR(VALUE_DATE,'YYYY') AS annee, COUNT(*) AS nb,
                     COUNT(DISTINCT FACILITY_ID) AS nb_lignes
              FROM GETM_FACILITY_VD_DETAILS
              WHERE VALUE_DATE IS NOT NULL
              GROUP BY TO_CHAR(VALUE_DATE,'YYYY')
              ORDER BY 1 DESC) LOOP
        print_info('Annee ' || d.annee, fmt_n(d.nb) || ' revision(s) sur '
            || fmt_n(d.nb_lignes) || ' ligne(s)');
    END LOOP;

    -- 6.1 Augmentations de limite superieures a c_pct_augm %
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE, vd.MOD_NO,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE NVL(v.lim_prec,0) > 0
          AND v.LIMIT_AMOUNT > v.lim_prec
          AND (v.LIMIT_AMOUNT - v.lim_prec) * 100 / v.lim_prec >= c_pct_augm
    );
    print_test('Augmentations de limite >= ' || c_pct_augm || ' %', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,16,8,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' ANCIENNE LIM.',16) || '|' || RPAD(' NOUVELLE LIM.',16) || '|'
            || RPAD(' HAUSSE',16) || '|' || RPAD(' %',8) || '|' || RPAD(' EFFET LE',12) || '|');
        tbl_line('4,12,22,16,16,16,16,8,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   v.LIMIT_AMOUNT - v.lim_prec AS hausse,
                   ROUND((v.LIMIT_AMOUNT - v.lim_prec) * 100 / v.lim_prec, 1) AS pct,
                   v.VALUE_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(v.lim_prec,0) > 0
              AND v.LIMIT_AMOUNT > v.lim_prec
              AND (v.LIMIT_AMOUNT - v.lim_prec) * 100 / v.lim_prec >= c_pct_augm
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.ancienne),15) || ' |' || LPAD(fmt_m(d.nouvelle),15) || ' |'
                || LPAD(fmt_m(d.hausse),15) || ' |'
                || LPAD(TO_CHAR(d.pct,'FM999G990D0'),7) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,22,16,16,16,16,8,12');
    END IF;

    -- 6.2 Augmentations de limite superieures a c_mnt_augm en valeur
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE v.lim_prec IS NOT NULL
          AND v.LIMIT_AMOUNT - v.lim_prec >= c_mnt_augm
    );
    print_test('Augmentations de limite >= ' || fmt_m(c_mnt_augm), v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,16,12,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' ANCIENNE LIM.',16) || '|' || RPAD(' NOUVELLE LIM.',16) || '|'
            || RPAD(' HAUSSE',16) || '|' || RPAD(' EFFET LE',12) || '|' || RPAD(' SAISI LE',12) || '|');
        tbl_line('4,12,22,16,16,16,16,12,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   v.LIMIT_AMOUNT - v.lim_prec AS hausse, v.VALUE_DATE, v.BOOK_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL
              AND v.LIMIT_AMOUNT - v.lim_prec >= c_mnt_augm
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.ancienne),15) || ' |' || LPAD(fmt_m(d.nouvelle),15) || ' |'
                || LPAD(fmt_m(d.hausse),15) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,22,16,16,16,16,12,12');
    END IF;

    -- 6.3 Limites au moins doublees en une seule revision
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE NVL(v.lim_prec,0) > 0
          AND v.LIMIT_AMOUNT >= 2 * v.lim_prec
    );
    print_test('Limites au moins doublees en une revision', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,10,12,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' ANCIENNE LIM.',16) || '|' || RPAD(' NOUVELLE LIM.',16) || '|'
            || RPAD(' COEFF.',10) || '|' || RPAD(' EFFET LE',12) || '|' || RPAD(' UTILISE AUJ.',16) || '|');
        tbl_line('4,12,22,16,16,16,10,12,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   ROUND(v.LIMIT_AMOUNT / v.lim_prec, 1) AS coeff,
                   v.VALUE_DATE, NVL(f.UTILISATION,0) AS util
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(v.lim_prec,0) > 0
              AND v.LIMIT_AMOUNT >= 2 * v.lim_prec
            ORDER BY v.LIMIT_AMOUNT / v.lim_prec DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.ancienne),15) || ' |' || LPAD(fmt_m(d.nouvelle),15) || ' |'
                || LPAD('x ' || TO_CHAR(d.coeff,'FM999G990D0'),9) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|'
                || LPAD(fmt_m(d.util),15) || ' |');
        END LOOP;
        tbl_line('4,12,22,16,16,16,10,12,16');
    END IF;

    -- 6.4 Lignes ayant subi plusieurs augmentations sur la periode
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.FACILITY_ID
        FROM (
            SELECT vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
        GROUP BY v.FACILITY_ID
        HAVING COUNT(*) >= 3
    );
    print_test('Lignes avec au moins 3 augmentations sur ' || c_mois_limit || ' mois', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,10,16,16,16,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' NB HAUSSES',10) || '|' || RPAD(' LIM. INITIALE',16) || '|'
            || RPAD(' LIM. FINALE',16) || '|' || RPAD(' HAUSSE TOT.',16) || '|' || RPAD(' DERNIERE',12) || '|');
        tbl_line('4,12,22,16,10,16,16,16,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   COUNT(*) AS nb_hausses,
                   MIN(v.lim_prec) KEEP (DENSE_RANK FIRST ORDER BY v.VALUE_DATE) AS lim_init,
                   MAX(v.LIMIT_AMOUNT) KEEP (DENSE_RANK LAST ORDER BY v.VALUE_DATE) AS lim_fin,
                   MAX(v.LIMIT_AMOUNT) KEEP (DENSE_RANK LAST ORDER BY v.VALUE_DATE)
                   - MIN(v.lim_prec) KEEP (DENSE_RANK FIRST ORDER BY v.VALUE_DATE) AS hausse_tot,
                   MAX(v.VALUE_DATE) AS derniere
            FROM (
                SELECT vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
            GROUP BY v.FACILITY_ID, l.LIAB_NO, l.LIAB_NAME, f.LINE_CODE
            HAVING COUNT(*) >= 3
            ORDER BY COUNT(*) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_n(d.nb_hausses),9) || ' |'
                || LPAD(fmt_m(d.lim_init),15) || ' |' || LPAD(fmt_m(d.lim_fin),15) || ' |'
                || LPAD(fmt_m(d.hausse_tot),15) || ' |'
                || RPAD(' ' || fmt_d(d.derniere),12) || '|');
        END LOOP;
        tbl_line('4,12,22,16,10,16,16,16,12');
    END IF;

    -- 6.5 Augmentations importantes suivies d'une utilisation marginale
    --     (limite gonflee sans besoin economique demontre)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
        WHERE v.lim_prec IS NOT NULL
          AND v.LIMIT_AMOUNT - v.lim_prec >= c_mnt_augm
          AND NVL(f.LIMIT_AMOUNT,0) > 0
          AND NVL(f.UTILISATION,0) < 0.25 * NVL(f.LIMIT_AMOUNT,0)
    );
    print_test('Fortes hausses de limite peu utilisees (< 25 %)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,16,9,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' HAUSSE',16) || '|' || RPAD(' LIM. ACTUELLE',16) || '|'
            || RPAD(' UTILISE',16) || '|' || RPAD(' TAUX UTIL',9) || '|' || RPAD(' EFFET LE',12) || '|');
        tbl_line('4,12,22,16,16,16,16,9,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.LIMIT_AMOUNT - v.lim_prec AS hausse,
                   NVL(f.LIMIT_AMOUNT,0) AS lim_act, NVL(f.UTILISATION,0) AS util,
                   ROUND(NVL(f.UTILISATION,0) * 100 / NULLIF(f.LIMIT_AMOUNT,0), 1) AS taux,
                   v.VALUE_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL
              AND v.LIMIT_AMOUNT - v.lim_prec >= c_mnt_augm
              AND NVL(f.LIMIT_AMOUNT,0) > 0
              AND NVL(f.UTILISATION,0) < 0.25 * NVL(f.LIMIT_AMOUNT,0)
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.hausse),15) || ' |' || LPAD(fmt_m(d.lim_act),15) || ' |'
                || LPAD(fmt_m(d.util),15) || ' |'
                || LPAD(TO_CHAR(NVL(d.taux,0),'FM990D0') || ' %',8) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,22,16,16,16,16,9,12');
    END IF;

    -- 6.6 Lignes ayant fait l'objet d'un nombre eleve de modifications
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.MOD_NO,0) >= 10;
    print_test('Lignes avec 10 modifications ou plus (MOD_NO)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,8,16,16,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' MOD_NO',8) || '|' || RPAD(' LIMITE',16) || '|'
            || RPAD(' UTILISE',16) || '|' || RPAD(' DERN. MAKER',16) || '|' || RPAD(' MODIFIE LE',13) || '|');
        tbl_line('4,12,24,16,8,16,16,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, f.LINE_CODE,
                   NVL(f.MOD_NO,0) AS mod_no, NVL(f.LIMIT_AMOUNT,0) AS limite,
                   NVL(f.UTILISATION,0) AS util, NVL(f.MAKER_ID,'-') AS maker, f.MAKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.MOD_NO,0) >= 10
            ORDER BY NVL(f.MOD_NO,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|'
                || LPAD(fmt_n(d.mod_no),7) || ' |'
                || LPAD(fmt_m(d.limite),15) || ' |' || LPAD(fmt_m(d.util),15) || ' |'
                || RPAD(' ' || SUBSTR(d.maker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.MAKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,8,16,16,16,13');
    END IF;

    -- =========================================================
    -- SECTION 7 : AUGMENTATIONS DE LIMITES JUSTE AVANT UN DEPASSEMENT
    -- =========================================================
    -- Une hausse de limite decidee a la veille (ou au lendemain) d'un
    -- depassement traduit souvent une regularisation a posteriori :
    -- la limite est alignee sur l'utilisation constatee au lieu que
    -- l'utilisation soit contenue dans la limite autorisee.
    -- =========================================================
    print_section('7. AUGMENTATIONS DE LIMITES JUSTE AVANT UN DEPASSEMENT');

    -- 7.1 Hausse de limite dans les jours precedant le dernier decouvert
    --     enregistre sur la ligne (DATE_OF_LAST_OD)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
          AND f.DATE_OF_LAST_OD IS NOT NULL
          AND f.DATE_OF_LAST_OD BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
    );
    print_test('Hausses de limite dans les ' || c_jours_avant || ' j precedant un OD', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,12,12,8');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' ANCIENNE LIM.',16) || '|' || RPAD(' NOUVELLE LIM.',16) || '|'
            || RPAD(' HAUSSE LE',12) || '|' || RPAD(' OD LE',12) || '|' || RPAD(' DELAI',8) || '|');
        tbl_line('4,12,22,16,16,16,12,12,8');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   v.VALUE_DATE, f.DATE_OF_LAST_OD,
                   TRUNC(f.DATE_OF_LAST_OD) - TRUNC(v.VALUE_DATE) AS delai
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
              AND f.DATE_OF_LAST_OD IS NOT NULL
              AND f.DATE_OF_LAST_OD BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.ancienne),15) || ' |' || LPAD(fmt_m(d.nouvelle),15) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|'
                || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),12) || '|'
                || LPAD(fmt_n(d.delai) || ' j',7) || ' |');
        END LOOP;
        tbl_line('4,12,22,16,16,16,12,12,8');
    END IF;

    -- 7.2 Hausses de limite a effet RETROACTIF (VALUE_DATE < BOOK_DATE)
    --     => la limite est datee avant sa saisie effective
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
          AND v.BOOK_DATE IS NOT NULL AND v.VALUE_DATE < v.BOOK_DATE
    );
    print_test('Hausses de limite a effet retroactif (VD < BOOK)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,12,12,9');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' ANCIENNE LIM.',16) || '|' || RPAD(' NOUVELLE LIM.',16) || '|'
            || RPAD(' EFFET LE',12) || '|' || RPAD(' SAISI LE',12) || '|' || RPAD(' RETRO(j)',9) || '|');
        tbl_line('4,12,22,16,16,16,12,12,9');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   v.VALUE_DATE, v.BOOK_DATE,
                   TRUNC(v.BOOK_DATE) - TRUNC(v.VALUE_DATE) AS retro
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE, vd.BOOK_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
              AND v.BOOK_DATE IS NOT NULL AND v.VALUE_DATE < v.BOOK_DATE
            ORDER BY TRUNC(v.BOOK_DATE) - TRUNC(v.VALUE_DATE) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.ancienne),15) || ' |' || LPAD(fmt_m(d.nouvelle),15) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|'
                || RPAD(' ' || fmt_d(d.BOOK_DATE),12) || '|'
                || LPAD(fmt_n(d.retro),8) || ' |');
        END LOOP;
        tbl_line('4,12,22,16,16,16,12,12,9');
    END IF;

    -- 7.3 Hausse accordee alors que le compte lie depassait DEJA l'ancienne
    --     limite dans les jours precedents (regularisation d'un depassement)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID, a.CUST_AC_NO
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
        JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
          AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY h
                      WHERE h.ACCOUNT = a.CUST_AC_NO
                        AND h.BKG_DATE BETWEEN v.VALUE_DATE - c_jours_avant AND v.VALUE_DATE
                        AND h.ACY_CLOSING_BAL < -v.lim_prec)
    );
    print_test('Hausses regularisant un depassement deja constate', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,20,15,15,15,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',20) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' ANCIENNE LIM.',15) || '|' || RPAD(' NOUVELLE LIM.',15) || '|'
            || RPAD(' PIRE SOLDE',15) || '|' || RPAD(' HAUSSE LE',12) || '|');
        tbl_line('4,12,20,20,15,15,15,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, a.CUST_AC_NO,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   (SELECT MIN(h.ACY_CLOSING_BAL) FROM ACTB_ACCBAL_HISTORY h
                     WHERE h.ACCOUNT = a.CUST_AC_NO
                       AND h.BKG_DATE BETWEEN v.VALUE_DATE - c_jours_avant AND v.VALUE_DATE) AS pire,
                   v.VALUE_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
              AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY h
                          WHERE h.ACCOUNT = a.CUST_AC_NO
                            AND h.BKG_DATE BETWEEN v.VALUE_DATE - c_jours_avant AND v.VALUE_DATE
                            AND h.ACY_CLOSING_BAL < -v.lim_prec)
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,18),20) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || LPAD(fmt_m(d.ancienne),14) || ' |' || LPAD(fmt_m(d.nouvelle),14) || ' |'
                || LPAD(fmt_m(d.pire),14) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,20,20,15,15,15,12');
    END IF;

    -- 7.4 Hausse immediatement consommee (>= 90 % de la nouvelle limite
    --     utilises dans les jours qui suivent)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID, a.CUST_AC_NO
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
        JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
          AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY h
                      WHERE h.ACCOUNT = a.CUST_AC_NO
                        AND h.BKG_DATE BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
                        AND h.ACY_CLOSING_BAL <= -0.9 * v.LIMIT_AMOUNT)
    );
    print_test('Hausses consommees a plus de 90 % dans les ' || c_jours_avant || ' j', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,20,15,15,15,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',20) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' ANCIENNE LIM.',15) || '|' || RPAD(' NOUVELLE LIM.',15) || '|'
            || RPAD(' PIRE SOLDE',15) || '|' || RPAD(' HAUSSE LE',12) || '|');
        tbl_line('4,12,20,20,15,15,15,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, a.CUST_AC_NO,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   (SELECT MIN(h.ACY_CLOSING_BAL) FROM ACTB_ACCBAL_HISTORY h
                     WHERE h.ACCOUNT = a.CUST_AC_NO
                       AND h.BKG_DATE BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant) AS pire,
                   v.VALUE_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
              AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY h
                          WHERE h.ACCOUNT = a.CUST_AC_NO
                            AND h.BKG_DATE BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
                            AND h.ACY_CLOSING_BAL <= -0.9 * v.LIMIT_AMOUNT)
            ORDER BY v.LIMIT_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,18),20) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || LPAD(fmt_m(d.ancienne),14) || ' |' || LPAD(fmt_m(d.nouvelle),14) || ' |'
                || LPAD(fmt_m(d.pire),14) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,20,20,15,15,15,12');
    END IF;

    -- 7.5 Hausse de limite suivie d'une ecriture debitrice significative
    --     sur le compte lie dans les jours qui suivent
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.ID, a.CUST_AC_NO
        FROM (
            SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
        JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
          AND EXISTS (SELECT 1 FROM ACTB_HISTORY h
                      WHERE h.AC_NO = a.CUST_AC_NO AND h.DRCR_IND = 'D'
                        AND h.TRN_DT BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
                        AND h.LCY_AMOUNT >= c_mnt_signif)
    );
    print_test('Hausses suivies d''un gros debit sur le compte lie', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,20,15,15,9,15,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',20) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' ANCIENNE LIM.',15) || '|' || RPAD(' NOUVELLE LIM.',15) || '|'
            || RPAD(' NB DEBITS',9) || '|' || RPAD(' + GROS DEBIT',15) || '|' || RPAD(' HAUSSE LE',12) || '|');
        tbl_line('4,12,20,20,15,15,9,15,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, a.CUST_AC_NO,
                   v.lim_prec AS ancienne, v.LIMIT_AMOUNT AS nouvelle,
                   (SELECT COUNT(*) FROM ACTB_HISTORY h
                     WHERE h.AC_NO = a.CUST_AC_NO AND h.DRCR_IND = 'D'
                       AND h.TRN_DT BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
                       AND h.LCY_AMOUNT >= c_mnt_signif) AS nb_deb,
                   (SELECT MAX(h.LCY_AMOUNT) FROM ACTB_HISTORY h
                     WHERE h.AC_NO = a.CUST_AC_NO AND h.DRCR_IND = 'D'
                       AND h.TRN_DT BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant) AS gros_deb,
                   v.VALUE_DATE
            FROM (
                SELECT vd.ID, vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            JOIN STTM_CUST_ACCOUNT a ON (a.LINE_ID = f.LINE_CODE OR a.LINE_ID = TO_CHAR(f.ID))
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
              AND EXISTS (SELECT 1 FROM ACTB_HISTORY h
                          WHERE h.AC_NO = a.CUST_AC_NO AND h.DRCR_IND = 'D'
                            AND h.TRN_DT BETWEEN v.VALUE_DATE AND v.VALUE_DATE + c_jours_avant
                            AND h.LCY_AMOUNT >= c_mnt_signif)
            ORDER BY (v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,18),20) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || LPAD(fmt_m(d.ancienne),14) || ' |' || LPAD(fmt_m(d.nouvelle),14) || ' |'
                || LPAD(fmt_n(d.nb_deb),8) || ' |'
                || LPAD(fmt_m(d.gros_deb),14) || ' |'
                || RPAD(' ' || fmt_d(d.VALUE_DATE),12) || '|');
        END LOOP;
        tbl_line('4,12,20,20,15,15,9,15,12');
    END IF;

    -- =========================================================
    -- SECTION 8 : OVERDRAFTS PROCHES OU SUPERIEURS AUX SEUILS
    --             D'APPROBATION
    -- =========================================================
    -- Les montants qui se logent juste sous un palier de delegation
    -- (bande c_pct_proche, par defaut 90 %) sont un indicateur classique
    -- de contournement du niveau d'approbation requis. Le cumul de
    -- plusieurs concours sous le seuil produit le meme effet.
    -- NB : pour les lignes en devise, le montant de reference retenu est
    --      REPORTING_AMOUNT lorsqu'il est renseigne, sinon LIMIT_AMOUNT.
    -- =========================================================
    print_section('8. OVERDRAFTS PROCHES OU SUPERIEURS AUX SEUILS D''APPROBATION');

    -- Ventilation des limites par palier de delegation (informatif)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Ventilation des lignes par palier de delegation]');
    FOR d IN (SELECT palier, COUNT(*) AS nb, NVL(SUM(mnt),0) AS total,
                     NVL(SUM(util),0) AS util
              FROM (SELECT CASE
                             WHEN mnt >= c_seuil_4 THEN '5. >= seuil 4'
                             WHEN mnt >= c_seuil_3 THEN '4. seuil 3 a seuil 4'
                             WHEN mnt >= c_seuil_2 THEN '3. seuil 2 a seuil 3'
                             WHEN mnt >= c_seuil_1 THEN '2. seuil 1 a seuil 2'
                             ELSE '1. < seuil 1'
                           END AS palier, mnt, util
                    FROM (SELECT CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                                      THEN NVL(f.LIMIT_AMOUNT,0)
                                      ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                                 END AS mnt,
                                 NVL(f.UTILISATION,0) AS util
                          FROM GETM_FACILITY f
                          WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0))
              GROUP BY palier
              ORDER BY palier) LOOP
        print_info(d.palier, fmt_n(d.nb) || ' ligne(s) — limites ' || fmt_m(d.total)
            || ' — utilise ' || fmt_m(d.util));
    END LOOP;

    -- 8.1 Lignes dont la limite se situe juste en dessous d'un seuil
    SELECT COUNT(*) INTO v_count FROM (
        SELECT x.ID FROM (
            SELECT f.ID,
                   CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                        THEN NVL(f.LIMIT_AMOUNT,0)
                        ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                   END AS mnt
            FROM GETM_FACILITY f
            WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
        ) x
        WHERE (x.mnt >= c_seuil_1 * c_pct_proche / 100 AND x.mnt < c_seuil_1)
           OR (x.mnt >= c_seuil_2 * c_pct_proche / 100 AND x.mnt < c_seuil_2)
           OR (x.mnt >= c_seuil_3 * c_pct_proche / 100 AND x.mnt < c_seuil_3)
           OR (x.mnt >= c_seuil_4 * c_pct_proche / 100 AND x.mnt < c_seuil_4)
    );
    print_test('Limites logees juste sous un seuil (bande ' || c_pct_proche || ' %)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,5,16,16,10,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' LIMITE',16) || '|' || RPAD(' SEUIL VISE',16) || '|' || RPAD(' % SEUIL',10) || '|'
            || RPAD(' UTILISE',16) || '|');
        tbl_line('4,12,22,16,5,16,16,10,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT liab, nom, ligne, ccy, mnt, seuil,
                   ROUND(mnt * 100 / seuil, 1) AS pct, util
            FROM (
                SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                       f.LINE_CODE AS ligne, NVL(f.LINE_CURRENCY,'-') AS ccy,
                       NVL(f.UTILISATION,0) AS util,
                       CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                            THEN NVL(f.LIMIT_AMOUNT,0)
                            ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                       END AS mnt,
                       CASE
                         WHEN NVL(f.LIMIT_AMOUNT,0) >= c_seuil_4 * c_pct_proche / 100
                              AND NVL(f.LIMIT_AMOUNT,0) < c_seuil_4 THEN c_seuil_4
                         WHEN NVL(f.LIMIT_AMOUNT,0) >= c_seuil_3 * c_pct_proche / 100
                              AND NVL(f.LIMIT_AMOUNT,0) < c_seuil_3 THEN c_seuil_3
                         WHEN NVL(f.LIMIT_AMOUNT,0) >= c_seuil_2 * c_pct_proche / 100
                              AND NVL(f.LIMIT_AMOUNT,0) < c_seuil_2 THEN c_seuil_2
                         WHEN NVL(f.LIMIT_AMOUNT,0) >= c_seuil_1 * c_pct_proche / 100
                              AND NVL(f.LIMIT_AMOUNT,0) < c_seuil_1 THEN c_seuil_1
                       END AS seuil
                FROM GETM_FACILITY f
                LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
                WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
            )
            WHERE seuil IS NOT NULL
            ORDER BY mnt DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.mnt),15) || ' |' || LPAD(fmt_m(d.seuil),15) || ' |'
                || LPAD(TO_CHAR(d.pct,'FM990D0') || ' %',9) || ' |'
                || LPAD(fmt_m(d.util),15) || ' |');
        END LOOP;
        tbl_line('4,12,22,16,5,16,16,10,16');
    END IF;

    -- 8.2 Lignes atteignant ou depassant le seuil du comite de credit
    SELECT COUNT(*) INTO v_count FROM (
        SELECT x.ID FROM (
            SELECT f.ID,
                   CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                        THEN NVL(f.LIMIT_AMOUNT,0)
                        ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                   END AS mnt
            FROM GETM_FACILITY f
            WHERE f.RECORD_STAT = 'O'
        ) x
        WHERE x.mnt >= c_seuil_3
    );
    print_test('Lignes >= seuil 3 (' || fmt_m(c_seuil_3) || ') a rapprocher des PV', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,16,16,16,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' LIMITE',16) || '|' || RPAD(' APPROUVE',16) || '|'
            || RPAD(' UTILISE',16) || '|' || RPAD(' CHECKER',16) || '|' || RPAD(' VALIDE LE',13) || '|');
        tbl_line('4,12,22,16,16,16,16,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, f.LINE_CODE AS ligne,
                   CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                        THEN NVL(f.LIMIT_AMOUNT,0)
                        ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                   END AS mnt,
                   NVL(f.APPROVED_AMT,0) AS approuve, NVL(f.UTILISATION,0) AS util,
                   NVL(f.CHECKER_ID,'-') AS checker, f.CHECKER_DT_STAMP
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O'
              AND CASE WHEN NVL(f.LINE_CURRENCY,'XAF') = 'XAF'
                       THEN NVL(f.LIMIT_AMOUNT,0)
                       ELSE NVL(NULLIF(f.REPORTING_AMOUNT,0), NVL(f.LIMIT_AMOUNT,0))
                  END >= c_seuil_3
            ORDER BY mnt DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_m(d.mnt),15) || ' |' || LPAD(fmt_m(d.approuve),15) || ' |'
                || LPAD(fmt_m(d.util),15) || ' |'
                || RPAD(' ' || SUBSTR(d.checker,1,14),16) || '|'
                || RPAD(' ' || fmt_d(d.CHECKER_DT_STAMP),13) || '|');
        END LOOP;
        tbl_line('4,12,22,16,16,16,16,16,13');
    END IF;

    -- 8.3 Clients dont le CUMUL des lignes franchit un seuil alors que
    --     chaque ligne prise isolement reste en dessous (fractionnement)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT f.LIAB_ID
        FROM GETM_FACILITY f
        WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
        GROUP BY f.LIAB_ID
        HAVING COUNT(*) > 1
           AND SUM(NVL(f.LIMIT_AMOUNT,0)) >= c_seuil_2
           AND MAX(NVL(f.LIMIT_AMOUNT,0)) < c_seuil_2
    );
    print_test('Cumul de lignes >= seuil 2 avec chaque ligne en dessous', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,10,17,17,17,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' NB LIGNES',10) || '|' || RPAD(' CUMUL LIMITES',17) || '|' || RPAD(' + GROSSE LIGNE',17) || '|'
            || RPAD(' SEUIL 2',17) || '|' || RPAD(' UTIL. CUMULEE',17) || '|');
        tbl_line('4,12,24,10,17,17,17,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, COUNT(*) AS nb_lignes,
                   SUM(NVL(f.LIMIT_AMOUNT,0)) AS cumul, MAX(NVL(f.LIMIT_AMOUNT,0)) AS plus_grosse,
                   NVL(SUM(f.UTILISATION),0) AS util_cum
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE f.RECORD_STAT = 'O' AND NVL(f.LIMIT_AMOUNT,0) > 0
            GROUP BY f.LIAB_ID, l.LIAB_NO, l.LIAB_NAME
            HAVING COUNT(*) > 1
               AND SUM(NVL(f.LIMIT_AMOUNT,0)) >= c_seuil_2
               AND MAX(NVL(f.LIMIT_AMOUNT,0)) < c_seuil_2
            ORDER BY SUM(NVL(f.LIMIT_AMOUNT,0)) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || LPAD(fmt_n(d.nb_lignes),9) || ' |'
                || LPAD(fmt_m(d.cumul),16) || ' |' || LPAD(fmt_m(d.plus_grosse),16) || ' |'
                || LPAD(fmt_m(c_seuil_2),16) || ' |' || LPAD(fmt_m(d.util_cum),16) || ' |');
        END LOOP;
        tbl_line('4,12,24,10,17,17,17,17');
    END IF;

    -- 8.4 Hausses successives sous le seuil mais cumulees au-dessus
    --     (saucissonnage dans le temps)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT v.FACILITY_ID
        FROM (
            SELECT vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                   LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                        ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
            FROM GETM_FACILITY_VD_DETAILS vd
            WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
        ) v
        WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
        GROUP BY v.FACILITY_ID
        HAVING COUNT(*) > 1
           AND SUM(v.LIMIT_AMOUNT - v.lim_prec) >= c_seuil_1
           AND MAX(v.LIMIT_AMOUNT - v.lim_prec) < c_seuil_1
    );
    print_test('Hausses cumulees >= seuil 1, chacune en dessous', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,16,10,16,16,16,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',22) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' NB HAUSSES',10) || '|' || RPAD(' CUMUL HAUSSES',16) || '|'
            || RPAD(' + GROSSE',16) || '|' || RPAD(' LIM. FINALE',16) || '|' || RPAD(' DERNIERE',12) || '|');
        tbl_line('4,12,22,16,10,16,16,16,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom,
                   NVL(f.LINE_CODE, TO_CHAR(v.FACILITY_ID)) AS ligne,
                   COUNT(*) AS nb_hausses,
                   SUM(v.LIMIT_AMOUNT - v.lim_prec) AS cumul,
                   MAX(v.LIMIT_AMOUNT - v.lim_prec) AS plus_grosse,
                   MAX(v.LIMIT_AMOUNT) KEEP (DENSE_RANK LAST ORDER BY v.VALUE_DATE) AS lim_fin,
                   MAX(v.VALUE_DATE) AS derniere
            FROM (
                SELECT vd.FACILITY_ID, vd.LIMIT_AMOUNT, vd.VALUE_DATE,
                       LAG(vd.LIMIT_AMOUNT) OVER (PARTITION BY vd.FACILITY_ID
                            ORDER BY vd.VALUE_DATE, vd.BOOK_DATE, vd.ID) AS lim_prec
                FROM GETM_FACILITY_VD_DETAILS vd
                WHERE vd.VALUE_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ) v
            LEFT JOIN GETM_FACILITY f ON f.ID = v.FACILITY_ID
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE v.lim_prec IS NOT NULL AND v.LIMIT_AMOUNT > v.lim_prec
            GROUP BY v.FACILITY_ID, l.LIAB_NO, l.LIAB_NAME, f.LINE_CODE
            HAVING COUNT(*) > 1
               AND SUM(v.LIMIT_AMOUNT - v.lim_prec) >= c_seuil_1
               AND MAX(v.LIMIT_AMOUNT - v.lim_prec) < c_seuil_1
            ORDER BY SUM(v.LIMIT_AMOUNT - v.lim_prec) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || SUBSTR(d.ligne,1,14),16) || '|'
                || LPAD(fmt_n(d.nb_hausses),9) || ' |'
                || LPAD(fmt_m(d.cumul),15) || ' |' || LPAD(fmt_m(d.plus_grosse),15) || ' |'
                || LPAD(fmt_m(d.lim_fin),15) || ' |'
                || RPAD(' ' || fmt_d(d.derniere),12) || '|');
        END LOOP;
        tbl_line('4,12,22,16,10,16,16,16,12');
    END IF;

    -- 8.5 TOD atteignant ou approchant le premier seuil de delegation
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.TOD_LIMIT,0) >= c_seuil_1 * c_pct_proche / 100;
    print_test('TOD atteignant ' || c_pct_proche || ' % du seuil 1 ou plus', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,20,5,16,16,10,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',24) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' TOD',16) || '|' || RPAD(' SOLDE',16) || '|' || RPAD(' % SEUIL 1',10) || '|'
            || RPAD(' FIN TOD',13) || '|');
        tbl_line('4,12,24,20,5,16,16,10,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   NVL(a.TOD_LIMIT,0) AS tod, a.ACY_CURR_BALANCE AS solde,
                   ROUND(NVL(a.TOD_LIMIT,0) * 100 / c_seuil_1, 1) AS pct,
                   a.TOD_LIMIT_END_DATE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.TOD_LIMIT,0) >= c_seuil_1 * c_pct_proche / 100
            ORDER BY NVL(a.TOD_LIMIT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.tod),15) || ' |' || LPAD(fmt_m(d.solde),15) || ' |'
                || LPAD(TO_CHAR(d.pct,'FM99990D0') || ' %',9) || ' |'
                || RPAD(' ' || fmt_d(d.TOD_LIMIT_END_DATE),13) || '|');
        END LOOP;
        tbl_line('4,12,24,20,5,16,16,10,13');
    END IF;

    -- =========================================================
    -- SECTION 9 : TRANSACTIONS MANUELLES SUR COMPTES OVERDRAWN
    -- =========================================================
    -- Les ecritures du module DE (Data Entry / saisie manuelle) ne
    -- proviennent d'aucun flux client automatise : sur un compte deja
    -- debiteur, elles doivent etre justifiees, autorisees par un tiers
    -- et rattachees a une piece. Le compte est considere comme
    -- "overdrawn" lorsque son solde de cloture du jour de l'ecriture
    -- (ACTB_ACCBAL_HISTORY) est negatif.
    -- =========================================================
    print_section('9. TRANSACTIONS MANUELLES SUR COMPTES OVERDRAWN');

    -- 9.1 Synthese par compte des ecritures manuelles passees en position
    --     debitrice
    SELECT COUNT(*) INTO v_count FROM (
        SELECT h.AC_NO
        FROM ACTB_HISTORY h
        JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
             AND b.BKG_DATE = TRUNC(h.TRN_DT)
             AND b.ACY_CLOSING_BAL < 0
        WHERE h.MODULE = 'DE'
          AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        GROUP BY h.AC_NO
    );
    print_test('Comptes debiteurs mouvementes par ecritures manuelles (DE)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,8,16,16,9,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' NB ECR.',8) || '|'
            || RPAD(' TOTAL DEBITS',16) || '|' || RPAD(' TOTAL CREDITS',16) || '|' || RPAD(' NB USERS',9) || '|'
            || RPAD(' DERNIERE',13) || '|');
        tbl_line('4,12,22,20,8,16,16,9,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.AC_NO, NVL(MAX(a.CUST_NO),'-') AS cif, NVL(MAX(c.CUSTOMER_NAME1),'-') AS nom,
                   COUNT(*) AS nb_ecr,
                   SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) AS tot_deb,
                   SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) AS tot_cred,
                   COUNT(DISTINCT h.USER_ID) AS nb_users, MAX(h.TRN_DT) AS derniere
            FROM ACTB_HISTORY h
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
                 AND b.ACY_CLOSING_BAL < 0
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE h.MODULE = 'DE'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
            GROUP BY h.AC_NO
            ORDER BY SUM(h.LCY_AMOUNT) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.AC_NO,20) || '|'
                || LPAD(fmt_n(d.nb_ecr),7) || ' |'
                || LPAD(fmt_m(d.tot_deb),15) || ' |' || LPAD(fmt_m(d.tot_cred),15) || ' |'
                || LPAD(fmt_n(d.nb_users),8) || ' |'
                || RPAD(' ' || fmt_d(d.derniere),13) || '|');
        END LOOP;
        tbl_line('4,12,22,20,8,16,16,9,13');
    END IF;

    -- 9.2 Ecritures manuelles significatives, detail
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT)
         AND b.ACY_CLOSING_BAL < 0
    WHERE h.MODULE = 'DE'
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND h.LCY_AMOUNT >= c_mnt_signif;
    print_test('Ecritures manuelles >= ' || fmt_m(c_mnt_signif) || ' sur compte debiteur', v_count);
    IF v_count > 0 THEN
        tbl_line('4,20,12,4,7,16,12,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' REFERENCE',12) || '|'
            || RPAD(' S',4) || '|' || RPAD(' CODE',7) || '|' || RPAD(' MONTANT',16) || '|'
            || RPAD(' DATE',12) || '|' || RPAD(' UTILISATEUR',16) || '|' || RPAD(' SOLDE DU JOUR',16) || '|');
        tbl_line('4,20,12,4,7,16,12,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.AC_NO, h.TRN_REF_NO, h.DRCR_IND, NVL(h.TRN_CODE,'-') AS trn_code,
                   h.LCY_AMOUNT, h.TRN_DT, NVL(h.USER_ID,'-') AS usr, b.ACY_CLOSING_BAL AS solde
            FROM ACTB_HISTORY h
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
                 AND b.ACY_CLOSING_BAL < 0
            WHERE h.MODULE = 'DE'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND h.LCY_AMOUNT >= c_mnt_signif
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.AC_NO,20) || '|' || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|'
                || RPAD(' ' || d.DRCR_IND,4) || '|' || RPAD(' ' || SUBSTR(d.trn_code,1,5),7) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |'
                || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |');
        END LOOP;
        tbl_line('4,20,12,4,7,16,12,16,16');
    END IF;

    -- 9.3 Ecritures manuelles saisies et autorisees par le meme utilisateur
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT)
         AND b.ACY_CLOSING_BAL < 0
    WHERE h.MODULE = 'DE'
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND h.USER_ID IS NOT NULL AND h.AUTH_ID IS NOT NULL
      AND UPPER(TRIM(h.USER_ID)) = UPPER(TRIM(h.AUTH_ID));
    print_test('Ecritures manuelles auto-autorisees (USER_ID = AUTH_ID)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,20,12,4,16,12,18,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' REFERENCE',12) || '|'
            || RPAD(' S',4) || '|' || RPAD(' MONTANT',16) || '|' || RPAD(' DATE',12) || '|'
            || RPAD(' UTILISATEUR',18) || '|' || RPAD(' SOLDE DU JOUR',16) || '|');
        tbl_line('4,20,12,4,16,12,18,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.AC_NO, h.TRN_REF_NO, h.DRCR_IND, h.LCY_AMOUNT, h.TRN_DT,
                   h.USER_ID AS usr, b.ACY_CLOSING_BAL AS solde
            FROM ACTB_HISTORY h
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
                 AND b.ACY_CLOSING_BAL < 0
            WHERE h.MODULE = 'DE'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND h.USER_ID IS NOT NULL AND h.AUTH_ID IS NOT NULL
              AND UPPER(TRIM(h.USER_ID)) = UPPER(TRIM(h.AUTH_ID))
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.AC_NO,20) || '|' || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|'
                || RPAD(' ' || d.DRCR_IND,4) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |'
                || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || RPAD(' ' || SUBSTR(d.usr,1,16),18) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |');
        END LOOP;
        tbl_line('4,20,12,4,16,12,18,16');
    END IF;

    -- 9.4 Ecritures manuelles antidatees sur comptes debiteurs
    --     (date de valeur anterieure a la date comptable)
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT)
         AND b.ACY_CLOSING_BAL < 0
    WHERE h.MODULE = 'DE'
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND h.VALUE_DT IS NOT NULL
      AND TRUNC(h.VALUE_DT) < TRUNC(h.TRN_DT);
    print_test('Ecritures manuelles antidatees sur compte debiteur', v_count);
    IF v_count > 0 THEN
        tbl_line('4,20,12,4,16,12,12,8,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' REFERENCE',12) || '|'
            || RPAD(' S',4) || '|' || RPAD(' MONTANT',16) || '|' || RPAD(' DATE COMPT.',12) || '|'
            || RPAD(' DATE VALEUR',12) || '|' || RPAD(' ECART',8) || '|' || RPAD(' UTILISATEUR',16) || '|');
        tbl_line('4,20,12,4,16,12,12,8,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.AC_NO, h.TRN_REF_NO, h.DRCR_IND, h.LCY_AMOUNT, h.TRN_DT, h.VALUE_DT,
                   TRUNC(h.TRN_DT) - TRUNC(h.VALUE_DT) AS ecart, NVL(h.USER_ID,'-') AS usr
            FROM ACTB_HISTORY h
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
                 AND b.ACY_CLOSING_BAL < 0
            WHERE h.MODULE = 'DE'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND h.VALUE_DT IS NOT NULL
              AND TRUNC(h.VALUE_DT) < TRUNC(h.TRN_DT)
            ORDER BY TRUNC(h.TRN_DT) - TRUNC(h.VALUE_DT) DESC, h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.AC_NO,20) || '|' || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|'
                || RPAD(' ' || d.DRCR_IND,4) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |'
                || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|' || RPAD(' ' || fmt_d(d.VALUE_DT),12) || '|'
                || LPAD(fmt_n(d.ecart) || ' j',7) || ' |'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|');
        END LOOP;
        tbl_line('4,20,12,4,16,12,12,8,16');
    END IF;

    -- 9.5 Ecritures manuelles debitrices sur comptes deja au-dela de leur
    --     autorisation (ligne + TOD) : aggravation d'un depassement
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT)
    WHERE h.MODULE = 'DE' AND h.DRCR_IND = 'D'
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND b.ACY_CLOSING_BAL < - (NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                                      WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)),0)
                                 + NVL(a.TOD_LIMIT,0));
    print_test('Debits manuels sur comptes deja au-dela de l''autorisation', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,12,16,12,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' COMPTE',20) || '|'
            || RPAD(' REFERENCE',12) || '|' || RPAD(' MONTANT DEBIT',16) || '|' || RPAD(' DATE',12) || '|'
            || RPAD(' SOLDE DU JOUR',16) || '|' || RPAD(' UTILISATEUR',16) || '|');
        tbl_line('4,12,20,12,16,12,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, h.AC_NO, h.TRN_REF_NO, h.LCY_AMOUNT, h.TRN_DT,
                   b.ACY_CLOSING_BAL AS solde, NVL(h.USER_ID,'-') AS usr
            FROM ACTB_HISTORY h
            JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
            WHERE h.MODULE = 'DE' AND h.DRCR_IND = 'D'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND b.ACY_CLOSING_BAL < - (NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                                              WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)),0)
                                         + NVL(a.TOD_LIMIT,0))
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || d.AC_NO,20) || '|'
                || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |'
                || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|');
        END LOOP;
        tbl_line('4,12,20,12,16,12,16,16');
    END IF;

    -- 9.6 Utilisateurs les plus actifs en saisie manuelle sur comptes
    --     debiteurs (cartographie des intervenants)
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Top utilisateurs — ecritures manuelles sur comptes debiteurs]');
    tbl_line('4,18,26,9,9,17,17');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' USER_ID',18) || '|' || RPAD(' NOM UTILISATEUR',26) || '|'
        || RPAD(' NB ECR.',9) || '|' || RPAD(' NB CPTES',9) || '|'
        || RPAD(' TOTAL DEBITS',17) || '|' || RPAD(' TOTAL CREDITS',17) || '|');
    tbl_line('4,18,26,9,9,17,17');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT NVL(h.USER_ID,'-') AS usr, NVL(MAX(u.USER_NAME),'-') AS nom,
               COUNT(*) AS nb_ecr, COUNT(DISTINCT h.AC_NO) AS nb_cptes,
               SUM(CASE WHEN h.DRCR_IND = 'D' THEN h.LCY_AMOUNT ELSE 0 END) AS tot_deb,
               SUM(CASE WHEN h.DRCR_IND = 'C' THEN h.LCY_AMOUNT ELSE 0 END) AS tot_cred
        FROM ACTB_HISTORY h
        JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
             AND b.BKG_DATE = TRUNC(h.TRN_DT)
             AND b.ACY_CLOSING_BAL < 0
        LEFT JOIN SMTB_USER u ON u.USER_ID = h.USER_ID
        WHERE h.MODULE = 'DE'
          AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        GROUP BY h.USER_ID
        ORDER BY COUNT(*) DESC
    ) WHERE ROWNUM <= 20) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || SUBSTR(d.usr,1,16),18) || '|' || RPAD(' ' || SUBSTR(d.nom,1,24),26) || '|'
            || LPAD(fmt_n(d.nb_ecr),8) || ' |' || LPAD(fmt_n(d.nb_cptes),8) || ' |'
            || LPAD(fmt_m(d.tot_deb),16) || ' |' || LPAD(fmt_m(d.tot_cred),16) || ' |');
    END LOOP;
    tbl_line('4,18,26,9,9,17,17');
    IF v_row_num = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  (aucune ecriture manuelle sur compte debiteur)');
    END IF;

    -- =========================================================
    -- SECTION 10 : OVERDRAFTS PRESENTANT DES REGULARISATIONS
    --              INHABITUELLES
    -- =========================================================
    -- Une regularisation "de facade" consiste a ramener artificiellement
    -- le compte a l'equilibre a une date d'arrete (fin de mois, fin
    -- d'exercice) puis a le laisser repartir en position debitrice.
    -- Elle fausse le declassement, le provisionnement et le reporting
    -- prudentiel.
    -- =========================================================
    print_section('10. OVERDRAFTS PRESENTANT DES REGULARISATIONS INHABITUELLES');

    -- 10.1 Habillage d'arrete mensuel : retour a l'equilibre en fin de
    --      mois encadre par deux positions debitrices
    SELECT COUNT(*) INTO v_count FROM (
        SELECT x.ACCOUNT, x.BKG_DATE
        FROM (
            SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                   LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec,
                   LEAD(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_suiv,
                   LEAD(BKG_DATE) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS dt_suiv
            FROM ACTB_ACCBAL_HISTORY
            WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        ) x
        WHERE x.ACY_CLOSING_BAL >= 0
          AND x.bal_prec < -c_mnt_signif
          AND x.bal_suiv < -c_mnt_signif
          AND x.BKG_DATE >= LAST_DAY(x.BKG_DATE) - 3
          AND x.dt_suiv <= x.BKG_DATE + 7
    );
    print_test('Retours a l''equilibre en fin de mois puis redebit', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,12,16,16,16,12');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' COMPTE',20) || '|'
            || RPAD(' ARRETE LE',12) || '|' || RPAD(' SOLDE VEILLE',16) || '|' || RPAD(' SOLDE ARRETE',16) || '|'
            || RPAD(' SOLDE SUIVANT',16) || '|' || RPAD(' REDEBIT LE',12) || '|');
        tbl_line('4,12,20,12,16,16,16,12');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(a.CUST_NO,'-') AS cif, x.ACCOUNT, x.BKG_DATE, x.bal_prec,
                   x.ACY_CLOSING_BAL AS bal_arrete, x.bal_suiv, x.dt_suiv
            FROM (
                SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                       LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec,
                       LEAD(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_suiv,
                       LEAD(BKG_DATE) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS dt_suiv
                FROM ACTB_ACCBAL_HISTORY
                WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
            ) x
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = x.ACCOUNT
            WHERE x.ACY_CLOSING_BAL >= 0
              AND x.bal_prec < -c_mnt_signif
              AND x.bal_suiv < -c_mnt_signif
              AND x.BKG_DATE >= LAST_DAY(x.BKG_DATE) - 3
              AND x.dt_suiv <= x.BKG_DATE + 7
            ORDER BY x.bal_prec ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || d.ACCOUNT,20) || '|'
                || RPAD(' ' || fmt_d(d.BKG_DATE),12) || '|'
                || LPAD(fmt_m(d.bal_prec),15) || ' |' || LPAD(fmt_m(d.bal_arrete),15) || ' |'
                || LPAD(fmt_m(d.bal_suiv),15) || ' |'
                || RPAD(' ' || fmt_d(d.dt_suiv),12) || '|');
        END LOOP;
        tbl_line('4,12,20,12,16,16,16,12');
    END IF;

    -- 10.2 Aller-retour : credit significatif suivi d'un debit de montant
    --      quasi identique dans les jours qui suivent
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY hc
    JOIN ACTB_HISTORY hd ON hd.AC_NO = hc.AC_NO AND hd.DRCR_IND = 'D'
         AND hd.TRN_DT > hc.TRN_DT AND hd.TRN_DT <= hc.TRN_DT + c_jours_ar
         AND ABS(hd.LCY_AMOUNT - hc.LCY_AMOUNT) <= 0.05 * hc.LCY_AMOUNT
    WHERE hc.DRCR_IND = 'C'
      AND hc.LCY_AMOUNT >= c_mnt_signif
      AND hc.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY b
                  WHERE b.ACCOUNT = hc.AC_NO
                    AND b.BKG_DATE BETWEEN TRUNC(hc.TRN_DT) - 5 AND TRUNC(hc.TRN_DT)
                    AND b.ACY_CLOSING_BAL < 0);
    print_test('Regularisations en aller-retour sous ' || c_jours_ar || ' jours', v_count);
    IF v_count > 0 THEN
        tbl_line('4,20,16,12,16,12,7,7');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' CREDIT',16) || '|'
            || RPAD(' LE',12) || '|' || RPAD(' DEBIT RETOUR',16) || '|' || RPAD(' LE',12) || '|'
            || RPAD(' MOD.C',7) || '|' || RPAD(' MOD.D',7) || '|');
        tbl_line('4,20,16,12,16,12,7,7');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT hc.AC_NO, hc.LCY_AMOUNT AS mnt_cred, hc.TRN_DT AS dt_cred,
                   hd.LCY_AMOUNT AS mnt_deb, hd.TRN_DT AS dt_deb,
                   NVL(hc.MODULE,'-') AS mod_c, NVL(hd.MODULE,'-') AS mod_d
            FROM ACTB_HISTORY hc
            JOIN ACTB_HISTORY hd ON hd.AC_NO = hc.AC_NO AND hd.DRCR_IND = 'D'
                 AND hd.TRN_DT > hc.TRN_DT AND hd.TRN_DT <= hc.TRN_DT + c_jours_ar
                 AND ABS(hd.LCY_AMOUNT - hc.LCY_AMOUNT) <= 0.05 * hc.LCY_AMOUNT
            WHERE hc.DRCR_IND = 'C'
              AND hc.LCY_AMOUNT >= c_mnt_signif
              AND hc.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND EXISTS (SELECT 1 FROM ACTB_ACCBAL_HISTORY b
                          WHERE b.ACCOUNT = hc.AC_NO
                            AND b.BKG_DATE BETWEEN TRUNC(hc.TRN_DT) - 5 AND TRUNC(hc.TRN_DT)
                            AND b.ACY_CLOSING_BAL < 0)
            ORDER BY hc.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.AC_NO,20) || '|'
                || LPAD(fmt_m(d.mnt_cred),15) || ' |' || RPAD(' ' || fmt_d(d.dt_cred),12) || '|'
                || LPAD(fmt_m(d.mnt_deb),15) || ' |' || RPAD(' ' || fmt_d(d.dt_deb),12) || '|'
                || RPAD(' ' || d.mod_c,7) || '|' || RPAD(' ' || d.mod_d,7) || '|');
        END LOOP;
        tbl_line('4,20,16,12,16,12,7,7');
    END IF;

    -- 10.3 Regularisation obtenue par ecriture interne (DE / GL) et non
    --      par un flux client
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN (
        SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
               LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec
        FROM ACTB_ACCBAL_HISTORY
        WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
    ) x ON x.ACCOUNT = h.AC_NO AND x.BKG_DATE = TRUNC(h.TRN_DT)
    WHERE h.MODULE IN ('DE','GL')
      AND h.DRCR_IND = 'C'
      AND h.LCY_AMOUNT >= c_mnt_signif
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND x.bal_prec < 0
      AND x.ACY_CLOSING_BAL >= 0;
    print_test('Regularisations par ecriture interne (module DE / GL)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,20,12,7,16,12,16,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' COMPTE',20) || '|' || RPAD(' REFERENCE',12) || '|'
            || RPAD(' MODULE',7) || '|' || RPAD(' CREDIT',16) || '|' || RPAD(' LE',12) || '|'
            || RPAD(' SOLDE VEILLE',16) || '|' || RPAD(' UTILISATEUR',16) || '|');
        tbl_line('4,20,12,7,16,12,16,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT h.AC_NO, h.TRN_REF_NO, h.MODULE, h.LCY_AMOUNT, h.TRN_DT,
                   x.bal_prec, NVL(h.USER_ID,'-') AS usr
            FROM ACTB_HISTORY h
            JOIN (
                SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                       LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec
                FROM ACTB_ACCBAL_HISTORY
                WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
            ) x ON x.ACCOUNT = h.AC_NO AND x.BKG_DATE = TRUNC(h.TRN_DT)
            WHERE h.MODULE IN ('DE','GL')
              AND h.DRCR_IND = 'C'
              AND h.LCY_AMOUNT >= c_mnt_signif
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND x.bal_prec < 0
              AND x.ACY_CLOSING_BAL >= 0
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.AC_NO,20) || '|' || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|'
                || RPAD(' ' || d.MODULE,7) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |' || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || LPAD(fmt_m(d.bal_prec),15) || ' |'
                || RPAD(' ' || SUBSTR(d.usr,1,14),16) || '|');
        END LOOP;
        tbl_line('4,20,12,7,16,12,16,16');
    END IF;

    -- 10.4 Regularisations concentrees sur la periode d'arrete annuel
    --      (derniers jours de decembre)
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT) - 1
         AND b.ACY_CLOSING_BAL < 0
    WHERE h.DRCR_IND = 'C'
      AND h.LCY_AMOUNT >= c_mnt_signif
      AND TO_CHAR(h.TRN_DT,'MMDD') BETWEEN '1226' AND '1231'
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit);
    print_test('Credits significatifs sur comptes debiteurs fin decembre', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,12,7,16,12,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' COMPTE',20) || '|'
            || RPAD(' REFERENCE',12) || '|' || RPAD(' MODULE',7) || '|' || RPAD(' CREDIT',16) || '|'
            || RPAD(' LE',12) || '|' || RPAD(' SOLDE VEILLE',16) || '|');
        tbl_line('4,12,20,12,7,16,12,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(a.CUST_NO,'-') AS cif, h.AC_NO, h.TRN_REF_NO, NVL(h.MODULE,'-') AS mdl,
                   h.LCY_AMOUNT, h.TRN_DT, b.ACY_CLOSING_BAL AS bal_veille
            FROM ACTB_HISTORY h
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT) - 1
                 AND b.ACY_CLOSING_BAL < 0
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
            WHERE h.DRCR_IND = 'C'
              AND h.LCY_AMOUNT >= c_mnt_signif
              AND TO_CHAR(h.TRN_DT,'MMDD') BETWEEN '1226' AND '1231'
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_limit)
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || d.AC_NO,20) || '|'
                || RPAD(' ' || SUBSTR(d.TRN_REF_NO,1,10),12) || '|' || RPAD(' ' || d.mdl,7) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |' || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || LPAD(fmt_m(d.bal_veille),15) || ' |');
        END LOOP;
        tbl_line('4,12,20,12,7,16,12,16');
    END IF;

    -- 10.5 Regularisation alimentee par un autre compte du MEME client
    --      (transfert interne de tresorerie, cavalerie)
    SELECT COUNT(*) INTO v_count
    FROM ACTB_HISTORY h
    JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
    JOIN STTM_CUST_ACCOUNT a2 ON a2.CUST_AC_NO = h.RELATED_ACCOUNT
    JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
         AND b.BKG_DATE = TRUNC(h.TRN_DT)
    WHERE h.DRCR_IND = 'C'
      AND h.LCY_AMOUNT >= c_mnt_signif
      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
      AND h.RELATED_ACCOUNT IS NOT NULL
      AND a2.CUST_NO = a.CUST_NO
      AND a2.CUST_AC_NO != a.CUST_AC_NO
      AND b.ACY_OPENING_BAL < 0;
    print_test('Regularisations par un autre compte du meme client', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,20,16,12,7,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' COMPTE CREDITE',20) || '|'
            || RPAD(' COMPTE SOURCE',20) || '|' || RPAD(' MONTANT',16) || '|' || RPAD(' LE',12) || '|'
            || RPAD(' MODULE',7) || '|' || RPAD(' SOLDE OUVERT.',16) || '|');
        tbl_line('4,12,20,20,16,12,7,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, h.AC_NO, h.RELATED_ACCOUNT, h.LCY_AMOUNT, h.TRN_DT,
                   NVL(h.MODULE,'-') AS mdl, b.ACY_OPENING_BAL AS bal_ouv
            FROM ACTB_HISTORY h
            JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = h.AC_NO
            JOIN STTM_CUST_ACCOUNT a2 ON a2.CUST_AC_NO = h.RELATED_ACCOUNT
            JOIN ACTB_ACCBAL_HISTORY b ON b.ACCOUNT = h.AC_NO
                 AND b.BKG_DATE = TRUNC(h.TRN_DT)
            WHERE h.DRCR_IND = 'C'
              AND h.LCY_AMOUNT >= c_mnt_signif
              AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND h.RELATED_ACCOUNT IS NOT NULL
              AND a2.CUST_NO = a.CUST_NO
              AND a2.CUST_AC_NO != a.CUST_AC_NO
              AND b.ACY_OPENING_BAL < 0
            ORDER BY h.LCY_AMOUNT DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || d.AC_NO,20) || '|'
                || RPAD(' ' || SUBSTR(d.RELATED_ACCOUNT,1,18),20) || '|'
                || LPAD(fmt_m(d.LCY_AMOUNT),15) || ' |' || RPAD(' ' || fmt_d(d.TRN_DT),12) || '|'
                || RPAD(' ' || d.mdl,7) || '|'
                || LPAD(fmt_m(d.bal_ouv),15) || ' |');
        END LOOP;
        tbl_line('4,12,20,20,16,12,7,16');
    END IF;

    -- =========================================================
    -- SECTION 11 : OVERDRAFTS DONT LES INTERETS / FRAIS N'ONT PAS
    --              ETE APPLIQUES
    -- =========================================================
    -- L'absence de perception des agios sur un compte durablement
    -- debiteur constitue une perte de produit net bancaire, une rupture
    -- d'egalite de traitement entre clients et, le cas echeant, un
    -- avantage consenti hors delegation.
    -- =========================================================
    print_section('11. OVERDRAFTS DONT LES INTERETS / FRAIS N''ONT PAS ETE APPLIQUES');

    -- 11.1 Comptes debiteurs de longue duree sans aucune ecriture
    --      d'interet debiteur (module IC) sur la periode
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND a.OVERDRAFT_SINCE IS NOT NULL
      AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_tod_max
      AND NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                      WHERE h.AC_NO = a.CUST_AC_NO
                        AND h.MODULE = 'IC' AND h.DRCR_IND = 'D'
                        AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist));
    print_test('Comptes debiteurs > ' || c_jours_tod_max || ' j sans interets debiteurs', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,5,16,13,9,14');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',16) || '|' || RPAD(' OD DEPUIS',13) || '|' || RPAD(' JOURS',9) || '|'
            || RPAD(' CLASSE',14) || '|');
        tbl_line('4,12,22,20,5,16,13,9,14');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE,
                   TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) AS nb_jours,
                   NVL(a.ACCOUNT_CLASS,'-') AS cl
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND a.OVERDRAFT_SINCE IS NOT NULL
              AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_tod_max
              AND NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                              WHERE h.AC_NO = a.CUST_AC_NO
                                AND h.MODULE = 'IC' AND h.DRCR_IND = 'D'
                                AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist))
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || LPAD(fmt_n(d.nb_jours),8) || ' |'
                || RPAD(' ' || SUBSTR(d.cl,1,12),14) || '|');
        END LOOP;
        tbl_line('4,12,22,20,5,16,13,9,14');
    END IF;

    -- 11.2 Comptes debiteurs significatifs sans interets courus
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.LCY_CURR_BALANCE < -c_mnt_signif
      AND NVL(a.ACY_ACCRUED_DR_IC,0) = 0;
    print_test('Comptes debiteurs significatifs sans interets courus', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,5,16,16,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',16) || '|' || RPAD(' INT. COURUS',16) || '|' || RPAD(' INT. DUS',16) || '|'
            || RPAD(' OD DEPUIS',13) || '|');
        tbl_line('4,12,22,20,5,16,16,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, NVL(a.ACY_ACCRUED_DR_IC,0) AS courus,
                   NVL(a.DR_INT_DUE,0) AS dus, a.OVERDRAFT_SINCE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.LCY_CURR_BALANCE < -c_mnt_signif
              AND NVL(a.ACY_ACCRUED_DR_IC,0) = 0
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |' || LPAD(fmt_m(d.courus),15) || ' |'
                || LPAD(fmt_m(d.dus),15) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|');
        END LOOP;
        tbl_line('4,12,22,20,5,16,16,16,13');
    END IF;

    -- 11.3 Interets debiteurs dus et non liquides
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.DR_INT_DUE,0) > 0;
    print_test('Comptes avec interets debiteurs dus non liquides', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,5,16,16,16,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' INT. DUS',16) || '|' || RPAD(' FRAIS DUS',16) || '|' || RPAD(' SOLDE',16) || '|'
            || RPAD(' OD DEPUIS',13) || '|');
        tbl_line('4,12,22,20,5,16,16,16,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   NVL(a.DR_INT_DUE,0) AS dus, NVL(a.CHG_DUE,0) AS frais,
                   a.ACY_CURR_BALANCE AS solde, a.OVERDRAFT_SINCE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.DR_INT_DUE,0) > 0
            ORDER BY NVL(a.DR_INT_DUE,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.dus),15) || ' |' || LPAD(fmt_m(d.frais),15) || ' |'
                || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|');
        END LOOP;
        tbl_line('4,12,22,20,5,16,16,16,13');
    END IF;

    -- 11.4 Frais dus non preleves sur comptes debiteurs
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.CHG_DUE,0) > 0
      AND NVL(a.ACY_CURR_BALANCE,0) < 0;
    print_test('Comptes debiteurs avec frais dus non preleves', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,5,16,16,13,14');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' FRAIS DUS',16) || '|' || RPAD(' SOLDE',16) || '|' || RPAD(' OD DEPUIS',13) || '|'
            || RPAD(' AGENCE',14) || '|');
        tbl_line('4,12,22,20,5,16,16,13,14');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   NVL(a.CHG_DUE,0) AS frais, a.ACY_CURR_BALANCE AS solde,
                   a.OVERDRAFT_SINCE, NVL(a.BRANCH_CODE,'-') AS brn
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.CHG_DUE,0) > 0
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
            ORDER BY NVL(a.CHG_DUE,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.frais),15) || ' |' || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || RPAD(' ' || d.brn,14) || '|');
        END LOOP;
        tbl_line('4,12,22,20,5,16,16,13,14');
    END IF;

    -- 11.5 Comptes debiteurs rattaches a une classe qui n'inclut pas le
    --      calcul / suivi des interets
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    JOIN STTM_ACCOUNT_CLASS ac ON ac.ACCOUNT_CLASS = a.ACCOUNT_CLASS
    WHERE a.RECORD_STAT = 'O'
      AND NVL(a.ACY_CURR_BALANCE,0) < 0
      AND (NVL(ac.IC_INCLUSION,'N') != 'Y' OR NVL(ac.TRACK_ACCRUED_IC,'N') != 'Y');
    print_test('Comptes debiteurs sur classe sans suivi des interets', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,16,12,24,7,7');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' SOLDE',16) || '|' || RPAD(' CLASSE',12) || '|'
            || RPAD(' LIBELLE CLASSE',24) || '|' || RPAD(' IC_IN',7) || '|' || RPAD(' TRACK',7) || '|');
        tbl_line('4,12,22,20,16,12,24,7,7');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO,
                   a.ACY_CURR_BALANCE AS solde, a.ACCOUNT_CLASS AS cl,
                   NVL(ac.DESCRIPTION,'-') AS cl_lib,
                   NVL(ac.IC_INCLUSION,'-') AS ic_in, NVL(ac.TRACK_ACCRUED_IC,'-') AS track
            FROM STTM_CUST_ACCOUNT a
            JOIN STTM_ACCOUNT_CLASS ac ON ac.ACCOUNT_CLASS = a.ACCOUNT_CLASS
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND NVL(a.ACY_CURR_BALANCE,0) < 0
              AND (NVL(ac.IC_INCLUSION,'N') != 'Y' OR NVL(ac.TRACK_ACCRUED_IC,'N') != 'Y')
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || SUBSTR(d.cl,1,10),12) || '|' || RPAD(' ' || SUBSTR(d.cl_lib,1,22),24) || '|'
                || RPAD(' ' || d.ic_in,7) || '|' || RPAD(' ' || d.track,7) || '|');
        END LOOP;
        tbl_line('4,12,22,20,16,12,24,7,7');
    END IF;

    -- 11.6 Taux d'interet debiteur effectif annualise anormalement bas
    --      taux = interets debites / (encours debiteur moyen x jours / 365)
    SELECT COUNT(*) INTO v_count FROM (
        SELECT s.ACCOUNT
        FROM (
            SELECT b.ACCOUNT, AVG(ABS(b.ACY_CLOSING_BAL)) AS enc_moy, COUNT(*) AS nb_j
            FROM ACTB_ACCBAL_HISTORY b
            WHERE b.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
              AND b.ACY_CLOSING_BAL < 0
            GROUP BY b.ACCOUNT
            HAVING COUNT(*) >= c_jours_tod_max
               AND AVG(ABS(b.ACY_CLOSING_BAL)) >= c_mnt_signif
        ) s
        WHERE NVL((SELECT SUM(h.LCY_AMOUNT) FROM ACTB_HISTORY h
                    WHERE h.AC_NO = s.ACCOUNT AND h.MODULE = 'IC' AND h.DRCR_IND = 'D'
                      AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)),0)
              < c_taux_od_min / 100 * s.enc_moy * s.nb_j / 365
    );
    print_test('Comptes : taux debiteur effectif < ' || c_taux_od_min || ' %', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,20,9,17,16,10,16');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' COMPTE',20) || '|'
            || RPAD(' NB JOURS',9) || '|' || RPAD(' ENCOURS MOYEN',17) || '|' || RPAD(' INT. DEBITES',16) || '|'
            || RPAD(' TAUX EFF.',10) || '|' || RPAD(' INT. ATTENDUS',16) || '|');
        tbl_line('4,12,20,9,17,16,10,16');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(a.CUST_NO,'-') AS cif, s.ACCOUNT, s.nb_j, s.enc_moy, s.interets,
                   ROUND(s.interets * 365 * 100 / NULLIF(s.enc_moy * s.nb_j, 0), 2) AS taux,
                   c_taux_od_min / 100 * s.enc_moy * s.nb_j / 365 AS attendus
            FROM (
                SELECT b.ACCOUNT, AVG(ABS(b.ACY_CLOSING_BAL)) AS enc_moy, COUNT(*) AS nb_j,
                       NVL((SELECT SUM(h.LCY_AMOUNT) FROM ACTB_HISTORY h
                             WHERE h.AC_NO = b.ACCOUNT AND h.MODULE = 'IC' AND h.DRCR_IND = 'D'
                               AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)),0) AS interets
                FROM ACTB_ACCBAL_HISTORY b
                WHERE b.BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                  AND b.ACY_CLOSING_BAL < 0
                GROUP BY b.ACCOUNT
                HAVING COUNT(*) >= c_jours_tod_max
                   AND AVG(ABS(b.ACY_CLOSING_BAL)) >= c_mnt_signif
            ) s
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = s.ACCOUNT
            WHERE s.interets < c_taux_od_min / 100 * s.enc_moy * s.nb_j / 365
            ORDER BY s.enc_moy DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || d.ACCOUNT,20) || '|'
                || LPAD(fmt_n(d.nb_j),8) || ' |'
                || LPAD(fmt_m(d.enc_moy),16) || ' |' || LPAD(fmt_m(d.interets),15) || ' |'
                || LPAD(TO_CHAR(NVL(d.taux,0),'FM990D00') || ' %',9) || ' |'
                || LPAD(fmt_m(d.attendus),15) || ' |');
        END LOOP;
        tbl_line('4,12,20,9,17,16,10,16');
    END IF;

    -- =========================================================
    -- SECTION 12 : COMPTES PRESENTANT DES DEPASSEMENTS RECURRENTS
    -- =========================================================
    -- La recurrence se mesure en episodes distincts de position
    -- debitrice, reconstitues a partir des soldes journaliers : un
    -- nouvel episode commence des que le solde repasse sous zero apres
    -- un retour a l'equilibre. Un compte qui alterne sans cesse traduit
    -- soit un besoin de financement structurel non formalise, soit un
    -- pilotage du compte pour eviter le declassement.
    -- =========================================================
    print_section('12. COMPTES PRESENTANT DES DEPASSEMENTS RECURRENTS');

    -- 12.1 Comptes cumulant plusieurs episodes distincts de decouvert
    SELECT COUNT(*) INTO v_count FROM (
        SELECT ACCOUNT
        FROM (
            SELECT ACCOUNT, ACY_CLOSING_BAL,
                   LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec
            FROM ACTB_ACCBAL_HISTORY
            WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
        )
        WHERE ACY_CLOSING_BAL < 0
        GROUP BY ACCOUNT
        HAVING SUM(CASE WHEN NVL(bal_prec,0) >= 0 THEN 1 ELSE 0 END) >= c_nb_episodes
    );
    print_test('Comptes avec au moins ' || c_nb_episodes || ' episodes de decouvert', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,10,10,17,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' NB EPIS.',10) || '|' || RPAD(' NB JOURS',10) || '|'
            || RPAD(' PIRE SOLDE',17) || '|' || RPAD(' SOLDE ACTUEL',17) || '|');
        tbl_line('4,12,22,20,10,10,17,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, ep.ACCOUNT,
                   ep.nb_ep, ep.nb_j, ep.pire, NVL(a.ACY_CURR_BALANCE,0) AS solde
            FROM (
                SELECT ACCOUNT,
                       SUM(CASE WHEN NVL(bal_prec,0) >= 0 THEN 1 ELSE 0 END) AS nb_ep,
                       COUNT(*) AS nb_j, MIN(ACY_CLOSING_BAL) AS pire
                FROM (
                    SELECT ACCOUNT, BKG_DATE, ACY_CLOSING_BAL,
                           LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec
                    FROM ACTB_ACCBAL_HISTORY
                    WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                )
                WHERE ACY_CLOSING_BAL < 0
                GROUP BY ACCOUNT
                HAVING SUM(CASE WHEN NVL(bal_prec,0) >= 0 THEN 1 ELSE 0 END) >= c_nb_episodes
            ) ep
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = ep.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            ORDER BY ep.nb_ep DESC, ep.nb_j DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || LPAD(fmt_n(d.nb_ep),9) || ' |' || LPAD(fmt_n(d.nb_j),9) || ' |'
                || LPAD(fmt_m(d.pire),16) || ' |' || LPAD(fmt_m(d.solde),16) || ' |');
        END LOOP;
        tbl_line('4,12,22,20,10,10,17,17');
    END IF;

    -- 12.2 Comptes passant une part importante de l'annee en position
    --      debitrice
    SELECT COUNT(*) INTO v_count FROM (
        SELECT ACCOUNT
        FROM ACTB_ACCBAL_HISTORY
        WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
          AND ACY_CLOSING_BAL < 0
        GROUP BY ACCOUNT
        HAVING COUNT(*) > c_jours_recur
    );
    print_test('Comptes debiteurs plus de ' || c_jours_recur || ' jours sur la periode', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,10,17,17,17');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' NB JOURS',10) || '|'
            || RPAD(' ENCOURS MOYEN',17) || '|' || RPAD(' PIRE SOLDE',17) || '|' || RPAD(' SOLDE ACTUEL',17) || '|');
        tbl_line('4,12,22,20,10,17,17,17');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(a.CUST_NO,'-') AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, s.ACCOUNT,
                   s.nb_j, s.moyen, s.pire, NVL(a.ACY_CURR_BALANCE,0) AS solde
            FROM (
                SELECT ACCOUNT, COUNT(*) AS nb_j, AVG(ACY_CLOSING_BAL) AS moyen,
                       MIN(ACY_CLOSING_BAL) AS pire
                FROM ACTB_ACCBAL_HISTORY
                WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                  AND ACY_CLOSING_BAL < 0
                GROUP BY ACCOUNT
                HAVING COUNT(*) > c_jours_recur
            ) s
            LEFT JOIN STTM_CUST_ACCOUNT a ON a.CUST_AC_NO = s.ACCOUNT
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            ORDER BY s.nb_j DESC, s.pire ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.ACCOUNT,20) || '|'
                || LPAD(fmt_n(d.nb_j),9) || ' |'
                || LPAD(fmt_m(d.moyen),16) || ' |' || LPAD(fmt_m(d.pire),16) || ' |'
                || LPAD(fmt_m(d.solde),16) || ' |');
        END LOOP;
        tbl_line('4,12,22,20,10,17,17,17');
    END IF;

    -- 12.3 Comptes en recidive selon FLEXCUBE (decouvert precedent
    --      documente ET nouveau decouvert en cours)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.PREV_OVD_DATE IS NOT NULL
      AND a.OVERDRAFT_SINCE IS NOT NULL;
    print_test('Comptes en recidive (PREV_OVD_DATE et OVERDRAFT_SINCE)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,5,16,13,13,10');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' CCY',5) || '|'
            || RPAD(' SOLDE',16) || '|' || RPAD(' OD PRECEDENT',13) || '|' || RPAD(' OD ACTUEL',13) || '|'
            || RPAD(' ECART(j)',10) || '|');
        tbl_line('4,12,22,20,5,16,13,13,10');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO, NVL(a.CCY,'-') AS ccy,
                   a.ACY_CURR_BALANCE AS solde, a.PREV_OVD_DATE, a.OVERDRAFT_SINCE,
                   TRUNC(a.OVERDRAFT_SINCE) - TRUNC(a.PREV_OVD_DATE) AS ecart
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.PREV_OVD_DATE IS NOT NULL
              AND a.OVERDRAFT_SINCE IS NOT NULL
            ORDER BY a.LCY_CURR_BALANCE ASC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|' || RPAD(' ' || d.ccy,5) || '|'
                || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || fmt_d(d.PREV_OVD_DATE),13) || '|'
                || RPAD(' ' || fmt_d(d.OVERDRAFT_SINCE),13) || '|'
                || LPAD(fmt_n(d.ecart),9) || ' |');
        END LOOP;
        tbl_line('4,12,22,20,5,16,13,13,10');
    END IF;

    -- 12.4 Comptes a decouverts temporaires repetes (TOD precedent
    --      documente)
    SELECT COUNT(*) INTO v_count
    FROM STTM_CUST_ACCOUNT a
    WHERE a.RECORD_STAT = 'O'
      AND a.PREV_TOD_SINCE IS NOT NULL;
    print_test('Comptes a TOD repetes (PREV_TOD_SINCE renseigne)', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,22,20,16,16,13,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
            || RPAD(' COMPTE',20) || '|' || RPAD(' TOD',16) || '|' || RPAD(' SOLDE',16) || '|'
            || RPAD(' TOD PRECED.',13) || '|' || RPAD(' TOD ACTUEL',13) || '|');
        tbl_line('4,12,22,20,16,16,13,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT a.CUST_NO, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO,
                   NVL(a.TOD_LIMIT,0) AS tod, a.ACY_CURR_BALANCE AS solde,
                   a.PREV_TOD_SINCE, a.TOD_SINCE
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            WHERE a.RECORD_STAT = 'O'
              AND a.PREV_TOD_SINCE IS NOT NULL
            ORDER BY NVL(a.TOD_LIMIT,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.CUST_NO,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
                || RPAD(' ' || d.CUST_AC_NO,20) || '|'
                || LPAD(fmt_m(d.tod),15) || ' |' || LPAD(fmt_m(d.solde),15) || ' |'
                || RPAD(' ' || fmt_d(d.PREV_TOD_SINCE),13) || '|'
                || RPAD(' ' || fmt_d(d.TOD_SINCE),13) || '|');
        END LOOP;
        tbl_line('4,12,22,20,16,16,13,13');
    END IF;

    -- 12.5 Lignes ayant connu plusieurs depassements exceptionnels
    SELECT COUNT(*) INTO v_count
    FROM GETM_FACILITY f
    WHERE NVL(f.EXCEP_BREACH,0) >= 2;
    print_test('Lignes avec au moins 2 depassements exceptionnels', v_count);
    IF v_count > 0 THEN
        tbl_line('4,12,24,16,10,16,16,13,13');
        DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF/LIAB',12) || '|' || RPAD(' NOM',24) || '|'
            || RPAD(' LIGNE',16) || '|' || RPAD(' NB BREACH',10) || '|' || RPAD(' LIMITE',16) || '|'
            || RPAD(' UTILISE',16) || '|' || RPAD(' 1er OD',13) || '|' || RPAD(' DERNIER OD',13) || '|');
        tbl_line('4,12,24,16,10,16,16,13,13');
        v_row_num := 0;
        FOR d IN (SELECT * FROM (
            SELECT NVL(l.LIAB_NO,'-') AS liab, NVL(l.LIAB_NAME,'-') AS nom, f.LINE_CODE,
                   NVL(f.EXCEP_BREACH,0) AS nb_breach, NVL(f.LIMIT_AMOUNT,0) AS limite,
                   NVL(f.UTILISATION,0) AS util, f.DATE_OF_FIRST_OD, f.DATE_OF_LAST_OD
            FROM GETM_FACILITY f
            LEFT JOIN GETM_LIAB l ON l.ID = f.LIAB_ID
            WHERE NVL(f.EXCEP_BREACH,0) >= 2
            ORDER BY NVL(f.EXCEP_BREACH,0) DESC
        ) WHERE ROWNUM <= c_max_rows) LOOP
            v_row_num := v_row_num + 1;
            DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
                || RPAD(' ' || d.liab,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,22),24) || '|'
                || RPAD(' ' || SUBSTR(d.LINE_CODE,1,14),16) || '|'
                || LPAD(fmt_n(d.nb_breach),9) || ' |'
                || LPAD(fmt_m(d.limite),15) || ' |' || LPAD(fmt_m(d.util),15) || ' |'
                || RPAD(' ' || fmt_d(d.DATE_OF_FIRST_OD),13) || '|'
                || RPAD(' ' || fmt_d(d.DATE_OF_LAST_OD),13) || '|');
        END LOOP;
        tbl_line('4,12,24,16,10,16,16,13,13');
    END IF;

    -- 12.6 Synthese : comptes cumulant plusieurs facteurs de risque
    --      (1 point par critere) — support de priorisation des controles
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('  [Comptes cumulant au moins 3 facteurs de risque overdraft]');
    DBMS_OUTPUT.PUT_LINE('   Criteres : A=depassement autorisation  B=OD > ' || c_jours_long || ' j'
        || '  C=' || c_nb_episodes || ' episodes ou +  D=aucun interet debiteur'
        || '  E=ecritures manuelles  F=ligne expiree');
    tbl_line('4,12,22,20,17,7,7,7,7,7,7,7');
    DBMS_OUTPUT.PUT_LINE('  |' || RPAD(' N#',4) || '|' || RPAD(' CIF',12) || '|' || RPAD(' NOM CLIENT',22) || '|'
        || RPAD(' COMPTE',20) || '|' || RPAD(' SOLDE',17) || '|'
        || RPAD(' A',7) || '|' || RPAD(' B',7) || '|' || RPAD(' C',7) || '|' || RPAD(' D',7) || '|'
        || RPAD(' E',7) || '|' || RPAD(' F',7) || '|' || RPAD(' SCORE',7) || '|');
    tbl_line('4,12,22,20,17,7,7,7,7,7,7,7');
    v_row_num := 0;
    FOR d IN (SELECT * FROM (
        SELECT cif, nom, compte, solde, fa, fb, fc, fd, fe, ff,
               fa + fb + fc + fd + fe + ff AS score
        FROM (
            SELECT a.CUST_NO AS cif, NVL(c.CUSTOMER_NAME1,'-') AS nom, a.CUST_AC_NO AS compte,
                   a.ACY_CURR_BALANCE AS solde,
                   CASE WHEN ABS(a.ACY_CURR_BALANCE) >
                             NVL((SELECT MAX(f.LIMIT_AMOUNT) FROM GETM_FACILITY f
                                  WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                                    AND f.RECORD_STAT = 'O'),0) + NVL(a.TOD_LIMIT,0)
                        THEN 1 ELSE 0 END AS fa,
                   CASE WHEN a.OVERDRAFT_SINCE IS NOT NULL
                         AND TRUNC(SYSDATE) - TRUNC(a.OVERDRAFT_SINCE) > c_jours_long
                        THEN 1 ELSE 0 END AS fb,
                   CASE WHEN NVL(ep.nb_ep,0) >= c_nb_episodes THEN 1 ELSE 0 END AS fc,
                   CASE WHEN NOT EXISTS (SELECT 1 FROM ACTB_HISTORY h
                                         WHERE h.AC_NO = a.CUST_AC_NO
                                           AND h.MODULE = 'IC' AND h.DRCR_IND = 'D'
                                           AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist))
                        THEN 1 ELSE 0 END AS fd,
                   CASE WHEN EXISTS (SELECT 1 FROM ACTB_HISTORY h
                                     WHERE h.AC_NO = a.CUST_AC_NO AND h.MODULE = 'DE'
                                       AND h.TRN_DT >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist))
                        THEN 1 ELSE 0 END AS fe,
                   CASE WHEN EXISTS (SELECT 1 FROM GETM_FACILITY f
                                     WHERE (f.LINE_CODE = a.LINE_ID OR TO_CHAR(f.ID) = a.LINE_ID)
                                       AND f.LINE_EXPIRY_DATE IS NOT NULL
                                       AND f.LINE_EXPIRY_DATE < TRUNC(SYSDATE))
                        THEN 1 ELSE 0 END AS ff
            FROM STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
            LEFT JOIN (
                SELECT ACCOUNT, SUM(CASE WHEN NVL(bal_prec,0) >= 0 THEN 1 ELSE 0 END) AS nb_ep
                FROM (
                    SELECT ACCOUNT, ACY_CLOSING_BAL,
                           LAG(ACY_CLOSING_BAL) OVER (PARTITION BY ACCOUNT ORDER BY BKG_DATE) AS bal_prec
                    FROM ACTB_ACCBAL_HISTORY
                    WHERE BKG_DATE >= ADD_MONTHS(TRUNC(SYSDATE), -c_mois_hist)
                )
                WHERE ACY_CLOSING_BAL < 0
                GROUP BY ACCOUNT
            ) ep ON ep.ACCOUNT = a.CUST_AC_NO
            WHERE a.RECORD_STAT = 'O' AND NVL(a.ACY_CURR_BALANCE,0) < 0
        )
        WHERE fa + fb + fc + fd + fe + ff >= 3
        ORDER BY fa + fb + fc + fd + fe + ff DESC, solde ASC
    ) WHERE ROWNUM <= c_max_rows) LOOP
        v_row_num := v_row_num + 1;
        DBMS_OUTPUT.PUT_LINE('  |' || LPAD(v_row_num,3) || ' |'
            || RPAD(' ' || d.cif,12) || '|' || RPAD(' ' || SUBSTR(d.nom,1,20),22) || '|'
            || RPAD(' ' || d.compte,20) || '|'
            || LPAD(fmt_m(d.solde),16) || ' |'
            || LPAD(d.fa,6) || ' |' || LPAD(d.fb,6) || ' |' || LPAD(d.fc,6) || ' |'
            || LPAD(d.fd,6) || ' |' || LPAD(d.fe,6) || ' |' || LPAD(d.ff,6) || ' |'
            || LPAD(d.score,6) || ' |');
    END LOOP;
    tbl_line('4,12,22,20,17,7,7,7,7,7,7,7');
    IF v_row_num = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  (aucun compte ne cumule 3 facteurs de risque ou plus)');
    END IF;

    -- =========================================================
    -- FIN
    -- =========================================================
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE(v_sep);
    DBMS_OUTPUT.PUT_LINE('   TOTAL TESTS EXECUTES : ' || v_test_no);
    DBMS_OUTPUT.PUT_LINE('   TESTS AVEC ANOMALIES : ' || v_anomalies);
    DBMS_OUTPUT.PUT_LINE('   FIN — ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE(v_sep);

END;
/
