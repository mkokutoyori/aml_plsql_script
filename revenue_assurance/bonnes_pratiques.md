# Bonnes pratiques — Scripts d'audit PL/SQL FCUBS

Document normatif régissant la rédaction des scripts d'audit Revenue Assurance & Accounting sur la base de données FCUBS (Flexcube Universal Banking, Oracle). À appliquer à tout script du répertoire `revenue_assurance/`.

---

## 1. Introduction & objectifs

### 1.1 Contexte

La banque opère sur Flexcube Universal Banking (FCUBS), dont le schéma Oracle contient plusieurs centaines de tables. Le répertoire `revenue_assurance/` héberge les scripts qui extraient, agrègent et testent la cohérence des données comptables et des flux de revenus. Ces scripts servent deux audiences :

- **La direction financière et le contrôle interne** : ils doivent pouvoir mesurer le niveau de fuites de revenus (« revenue leakage »), suivre les indicateurs de qualité comptable, et piloter les actions correctives.
- **Les auditeurs externes et la COBAC** : ils attendent des pistes d'audit traçables, reproductibles, documentées, et alignées sur le Plan Comptable des Établissements de Crédit de la CEMAC (PCEC, Règlement COBAC R-98/01).

### 1.2 Objectifs des scripts d'audit

Chaque script d'audit livré dans ce répertoire doit répondre à **cinq objectifs non négociables** :

1. **Détection d'anomalies** — identifier les écarts, manques à gagner, incohérences entre référentiels et mouvements, ruptures d'intégrité référentielle, et dérogations non justifiées.
2. **Quantification financière** — chiffrer l'impact monétaire (en devise locale) de chaque anomalie, ne pas se limiter à un dénombrement.
3. **Aide à la décision** — livrer un rapport exploitable par un décideur non-technique, avec indicateurs consolidés, priorités et recommandations.
4. **Traçabilité d'audit** — horodater l'exécution, lister les paramètres utilisés, nommer les tables et colonnes interrogées, afin qu'un tiers puisse rejouer l'audit à l'identique.
5. **Alignement réglementaire** — rapprocher systématiquement les GL FCUBS des classes PCEC (1 à 9) et signaler toute entrée comptable incohérente avec le cadre COBAC.

### 1.3 Distinction exploration / audit

Deux types de scripts coexistent dans ce répertoire et ne doivent **jamais être confondus** :

| Type | Objectif | Sortie attendue | Ton |
|---|---|---|---|
| **Exploration** (`explore_*.sql`) | Cartographier le contenu des tables, connaître les volumétries, découvrir les patterns de données | Statistiques descriptives, top-N, plages temporelles | Neutre, inventaire |
| **Audit** (`audit_*.sql` / `*_audit.sql`) | Tester des hypothèses de contrôle, mesurer des anomalies, produire des findings | Findings qualifiés (sévérité, impact LCY, recommandation) | Assertif, conclusif |

Un script d'exploration **décrit** ; un script d'audit **conclut**. Un audit qui se contente de lister des volumes est un audit raté.

### 1.4 Portée du présent document

Les sections suivantes couvrent :

- **§2** Paramétrage du script (paramètres optionnels, conventions de nommage)
- **§3** Défensivité & robustesse PL/SQL
- **§4** Compatibilité Oracle & conventions SQL
- **§5** Vérification du dictionnaire de données
- **§6** Approche séquentielle & exploration préalable
- **§7** Structure & format du rapport de sortie
- **§8** Workflow Git & livraisons
- **§9** Performance & scalabilité
- **§10** Traçabilité & reproductibilité
- **§11** Gestion des erreurs & logging
- **§12** Checklist de validation avant livraison

Chaque section pose des **règles** (impératives) et des **recommandations** (conseillées). Toute dérogation doit être justifiée en commentaire du script concerné.

---

## 2. Paramétrage du script

### 2.1 Principe général

Tout script d'audit **doit** être paramétrable. Un script figé sur des valeurs en dur (date, agence, compte) n'est utilisable qu'une fois et perd sa valeur d'outil récurrent d'audit. Cependant, **tous les paramètres doivent être optionnels** : le script doit tourner sans aucun argument et produire un rapport intelligible sur l'intégralité des données, avec des valeurs par défaut documentées.

### 2.2 Paramètres standards attendus

Chaque script d'audit doit exposer, au minimum, les paramètres optionnels suivants, déclarés dans le bloc `DECLARE` en tête du script :

| Paramètre | Type | Défaut | Sémantique |
|---|---|---|---|
| `p_date_from` | `DATE` | `NULL` (= pas de borne basse) | Borne basse de la période auditée (inclusive) |
| `p_date_to` | `DATE` | `SYSDATE` | Borne haute de la période (inclusive) |
| `p_branch_code` | `VARCHAR2(10)` | `NULL` (= toutes agences) | Agence unique à auditer |
| `p_branch_list` | `VARCHAR2(4000)` | `NULL` | Liste d'agences séparées par virgule (ex. `'001,002,055'`) |
| `p_account_no` | `VARCHAR2(20)` | `NULL` | Compte client unique |
| `p_account_list` | `VARCHAR2(4000)` | `NULL` | Liste de comptes séparés par virgule |
| `p_customer_no` | `VARCHAR2(9)` | `NULL` | CIF client unique |
| `p_currency` | `VARCHAR2(3)` | `NULL` | Devise à auditer (ex. `'XAF'`) |
| `p_product_code` | `VARCHAR2(4)` | `NULL` | Produit FCUBS unique (LD, CL, IC, ...) |
| `p_module` | `VARCHAR2(2)` | `NULL` | Module FCUBS (`LD`, `CL`, `IC`, `CH`, `GL`, ...) |
| `p_materiality_lcy` | `NUMBER` | `1000` | Seuil de matérialité en devise locale pour filtrer le bruit |
| `p_top_n` | `NUMBER` | `25` | Cardinalité des palmarès (top-N) |
| `p_include_closed` | `CHAR(1)` | `'N'` | `Y` pour inclure les comptes/contrats clôturés |

### 2.3 Règles de déclaration

- **Un seul bloc de paramètres** en tête du script, encadré par un en-tête visible (`-- =====  PARAMETRES D'AUDIT  =====`).
- Chaque paramètre est commenté : sémantique, type attendu, exemple d'utilisation, valeur par défaut.
- Les paramètres **NULL** signifient « pas de filtre » ; le WHERE doit utiliser le pattern standard :
  ```sql
  AND (p_branch_code IS NULL OR t.BRANCH_CODE = p_branch_code)
  AND (p_date_from   IS NULL OR t.TRN_DT >= p_date_from)
  AND (p_date_to     IS NULL OR t.TRN_DT <= p_date_to)
  ```
- **Jamais** de concaténation dynamique pour construire le WHERE (risque d'injection SQL et illisibilité). Préférer le pattern `IS NULL OR …` ci-dessus.
- Pour les listes (`p_branch_list`), utiliser la fonction native :
  ```sql
  AND (p_branch_list IS NULL
       OR INSTR(',' || p_branch_list || ',', ',' || t.BRANCH_CODE || ',') > 0)
  ```

### 2.4 Rappel des paramètres dans le rapport

Avant toute section de résultats, le script **doit** imprimer un bloc récapitulatif des paramètres actifs. Cela garantit la reproductibilité et la traçabilité :

```
===============================================================
AUDIT PARAMETERS (as applied for this run)
---------------------------------------------------------------
  Execution timestamp ... 2026-04-17 11:45:03
  Database instance ..... FCUBS_PROD
  Period from ........... 2025-01-01
  Period to ............. 2026-04-17
  Branches .............. ALL
  Materiality (LCY) ..... 1,000
  Top-N ................. 25
  Include closed ........ N
===============================================================
```

Si un paramètre est à `NULL`, imprimer explicitement `ALL` ou `NO FILTER`, jamais une ligne vide.

### 2.5 Validation des paramètres

Avant toute requête :

- Si `p_date_from > p_date_to`, lever une erreur explicite et arrêter (`RAISE_APPLICATION_ERROR(-20001, 'p_date_from > p_date_to')`).
- Si un code agence est fourni, vérifier son existence dans `FBTM_BRANCH` et imprimer un warning si inconnu (sans arrêter).
- Si `p_materiality_lcy < 0`, utiliser la valeur absolue avec un warning.

### 2.6 Extension multi-modes

Pour les scripts complexes, prévoir un paramètre de mode d'exécution :

| Mode | Effet |
|---|---|
| `SUMMARY` | Indicateurs consolidés uniquement (rapide, < 1 min) |
| `FULL` | Rapport complet (défaut) |
| `DEEP` | Inclut les investigations détaillées (listes nominatives top-100, drill-down) |

Ce paramètre (`p_mode VARCHAR2(10) := 'FULL'`) permet au management d'obtenir rapidement un tableau de bord sans relancer l'intégralité de l'audit.

---

## 3. Défensivité & robustesse PL/SQL

### 3.1 Philosophie

Un audit ne doit **jamais s'arrêter sur une erreur isolée**. Si une requête sur une table marginale échoue (table absente, colonne renommée, donnée corrompue), l'audit doit logger l'incident et continuer. Un rapport partiel avec 95 % d'indicateurs vaut mille fois mieux qu'une exécution interrompue au bout de 10 minutes sur une table anecdotique.

Règle fondamentale : **chaque contrôle d'audit est un îlot isolé**. Il ne partage pas son sort avec le contrôle suivant.

### 3.2 Bloc BEGIN/EXCEPTION systématique

Chaque requête `SELECT INTO` et chaque `FOR r IN (…) LOOP` interrogeant une table non critique **doit** être encadré :

```sql
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM CLTB_ACCOUNT_COMPONENTS
    WHERE WAIVE = 'Y';
    print_kv('  Composants prêt WAIVE=Y', TO_CHAR(v_count));
EXCEPTION
    WHEN OTHERS THEN
        print_kv('  Composants prêt WAIVE=Y', 'N/A (' || SQLERRM || ')');
END;
```

Ne pas mettre de `EXCEPTION WHEN OTHERS THEN NULL;` silencieux : **toujours** remonter le `SQLERRM` dans le rapport pour que l'auditeur sache quel contrôle n'a pas abouti.

### 3.3 Helpers obligatoires

Chaque script définit en préambule un jeu minimal de procédures réutilisables :

| Helper | Rôle |
|---|---|
| `print_section(p_title)` | Imprime une en-tête de section avec séparateur visuel |
| `print_subsection(p_title)` | Imprime un sous-titre indenté |
| `print_kv(p_label, p_value)` | Imprime une paire `label...........value` avec padding |
| `print_finding(p_ref, p_severity, p_msg, p_lcy_impact)` | Imprime un finding formaté pour le rapport |
| `safe_count(p_table, p_label)` | `COUNT(*)` d'une table avec gestion d'absence |
| `safe_sum(p_table, p_col, p_label)` | Somme d'une colonne avec gestion d'absence |
| `print_warning(p_msg)` | Imprime un avertissement non-bloquant |

Chaque helper doit gérer lui-même les exceptions. Le corps principal du script doit rester lisible, focalisé sur la logique d'audit.

### 3.4 Typage strict — NVL et conversions

**Règle** : dans un `NVL(expr1, expr2)`, les deux opérandes doivent être du même type. Si `expr1` est NUMBER ou DATE et `expr2` une chaîne (ex. `'(NULL)'`), Oracle tente une conversion implicite qui plante à la première valeur incompatible (ORA-01722, ORA-01858).

Pattern correct pour imprimer une valeur optionnelle non-VARCHAR :

```sql
-- Colonne NUMBER
SELECT NVL(TO_CHAR(FREQUENCY_UNIT), '(NULL)') FROM ...

-- Colonne DATE
SELECT NVL(TO_CHAR(LAST_DT, 'YYYY-MM-DD'), '(NULL)') FROM ...
```

Jamais :

```sql
-- FAUX si FREQUENCY_UNIT est NUMBER
SELECT NVL(FREQUENCY_UNIT, '(NULL)') FROM ...
```

Avant d'utiliser `NVL(COL, 'string_default')`, vérifier le type de `COL` dans `fcubs.csv`.

### 3.5 Division par zéro

Tout ratio doit être protégé par `NULLIF` ou `GREATEST` :

```sql
-- Taux d'utilisation d'une facilité
ROUND(100 * UTILIZED / NULLIF(APPROVED, 0), 2) AS pct_util

-- Protection par GREATEST (choix personnel selon la sémantique)
ROUND(100 * UTILIZED / GREATEST(APPROVED, 1), 2) AS pct_util
```

### 3.6 Sémantique des agrégats sur ensembles vides

`SUM(x)` sur un ensemble vide retourne `NULL`, pas 0. Toujours envelopper : `NVL(SUM(x), 0)`. Même règle pour `MIN`, `MAX`, `AVG` si le résultat doit être imprimé ou concaténé.

### 3.7 Valeurs extrêmes & overflow

Les données comptables peuvent contenir des valeurs aberrantes (ex. `209 041 988 673 235 797 936 015 431 909 324 978 823 600 000 000 000 …`, vu lors de l'exploration). Un `SUM` ou une conversion peut alors dépasser la précision NUMBER d'Oracle.

Règles :

- Pour afficher un grand nombre : utiliser `TO_CHAR(v_num, 'FM999G999G999G999G999G999G999G990D00')` avec séparateurs.
- Avant toute somme sensible, filtrer les valeurs aberrantes : `WHERE ABS(AMOUNT_DUE) < 1E15` et logger le nombre de lignes écartées.
- Ne jamais faire de `SUM` d'une colonne VARCHAR2 sans vérifier son type (cf. cas `CALC_SI_AMT`).

### 3.8 Scalar subquery dans un appel procédural

**Interdit** : placer une `(SELECT ...)` scalaire directement dans un argument de procédure PL/SQL. Cause l'erreur PLS-00122.

```sql
-- FAUX
print_kv('Label', TO_CHAR((SELECT SUM(x) FROM t)));

-- CORRECT
SELECT SUM(x) INTO v_num FROM t;
print_kv('Label', TO_CHAR(v_num));
```

### 3.9 Variables locales typées selon l'usage

Déclarer :

- `v_count NUMBER` pour les dénombrements
- `v_num NUMBER` pour les montants monétaires
- `v_pct NUMBER` pour les pourcentages
- `v_dt DATE` pour les dates
- `v_txt VARCHAR2(4000)` pour les chaînes concaténées
- `v_sep VARCHAR2(80) := RPAD('=', 79, '=')` pour les séparateurs

Ne jamais réutiliser `v_count` pour stocker un montant : cela rend le code illisible à la relecture.

### 3.10 Gestion défensive des jointures

Toute jointure croisant deux tables dont au moins une est marginale doit être encapsulée dans `BEGIN/EXCEPTION`. Pattern typique :

```sql
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM LDTB_CONTRACT_MASTER c
    JOIN LDTM_PRODUCT_MASTER p ON p.PRODUCT = c.PRODUCT
    WHERE p.BLOCK_PRODUCT = 'Y';
    print_kv('  Contrats actifs sur produits bloqués', TO_CHAR(v_count));
EXCEPTION
    WHEN OTHERS THEN
        print_kv('  Contrats actifs sur produits bloqués',
                 'N/A (' || SUBSTR(SQLERRM, 1, 200) || ')');
END;
```

---

## 4. Compatibilité Oracle & conventions SQL

### 4.1 Version cible

La base FCUBS du client tourne sur un moteur Oracle qui n'accepte pas toutes les syntaxes modernes (retours d'erreurs observés pendant la phase d'exploration). Il faut **écrire en ciblant Oracle 11gR2** comme dénominateur commun. Toute fonctionnalité postérieure doit être évitée ou feature-detected.

### 4.2 Pagination / Top-N

**Interdit** : `FETCH FIRST n ROWS ONLY` et `OFFSET n ROWS` (syntaxe 12c+).

**Correct** : utiliser `ROWNUM` dans une sous-requête, après l'ORDER BY :

```sql
SELECT * FROM (
    SELECT col1, col2, SUM(amount) sm
    FROM t
    GROUP BY col1, col2
    ORDER BY sm DESC
) WHERE ROWNUM <= p_top_n;
```

Ne pas appliquer `ROWNUM <= N` au même niveau que `ORDER BY` : Oracle applique le filtre avant le tri et le résultat est non-déterministe.

### 4.3 ANSI JOIN vs jointure WHERE

Préférer la syntaxe ANSI `JOIN … ON …` à la jointure implicite par `WHERE`. Elle est plus lisible et détache clairement la logique de jointure de la logique de filtre :

```sql
-- BIEN
FROM STTM_CUST_ACCOUNT a
JOIN STTM_CUSTOMER c ON c.CUSTOMER_NO = a.CUST_NO
WHERE a.AC_STAT_DORMANT = 'Y'

-- TOLÉRÉ mais moins bien
FROM STTM_CUST_ACCOUNT a, STTM_CUSTOMER c
WHERE c.CUSTOMER_NO = a.CUST_NO
  AND a.AC_STAT_DORMANT = 'Y'
```

### 4.4 Alias systématiques

Toute table dans une jointure doit avoir un alias court et mnémotechnique (`a` pour `STTM_CUST_ACCOUNT`, `c` pour `STTM_CUSTOMER`, `h` pour `ACTB_HISTORY`, `g` pour `GLTB_GL_BAL`, etc.). Chaque colonne référencée dans un `SELECT` ou un `WHERE` sur plus d'une table doit être préfixée par son alias. Cela évite les ambiguïtés et facilite la lecture.

### 4.5 Scalar subquery — seulement en contexte SQL

Les `(SELECT ...)` scalaires sont autorisés **uniquement** dans un `SELECT` ou un `WHERE` (contexte SQL), jamais dans un appel de procédure PL/SQL (cf. §3.8).

### 4.6 Dates — comparaisons et formats

- Utiliser `TRUNC(SYSDATE)` pour éliminer la composante horaire quand on compare à une `DATE` tronquée.
- Éviter `SYSDATE - 30` ; préférer `ADD_MONTHS(SYSDATE, -1)` pour la lisibilité métier.
- Les comparaisons `d >= DATE '2025-01-01'` sont préférables à `d >= TO_DATE('01-01-2025', 'DD-MM-YYYY')` (format ISO, pas de dépendance au NLS).
- Pour borner une période inclusive, utiliser `>= p_date_from AND < p_date_to + 1` si on veut couvrir la journée entière du `p_date_to`.

### 4.7 NULL-safe comparisons

Les comparaisons `=` et `<>` renvoient `UNKNOWN` (non `TRUE`) sur un opérande NULL. Pour filtrer les valeurs différentes d'une valeur donnée en incluant les NULL, utiliser :

```sql
WHERE NVL(STATUS, 'X') <> 'LIQD'
```

Ou, pour les comparaisons NULL-safe :

```sql
WHERE LNNVL(STATUS = 'LIQD')  -- vrai si STATUS <> 'LIQD' OU STATUS IS NULL
```

### 4.8 Conversions explicites

- `TO_CHAR(num)` pour concaténer un NUMBER à une VARCHAR2.
- `TO_CHAR(d, 'YYYY-MM-DD')` pour imprimer une DATE (format ISO toujours).
- `TO_CHAR(d, 'YYYY-MM-DD HH24:MI:SS')` pour les timestamps.
- `TO_NUMBER(txt DEFAULT NULL ON CONVERSION ERROR)` est 12c+ : l'éviter. Utiliser `REGEXP_LIKE(txt, '^-?[0-9]+(\.[0-9]+)?$')` comme garde.

### 4.9 Regex — pattern de guard

Pour convertir une colonne VARCHAR2 qui contient parfois des valeurs non numériques :

```sql
SELECT NVL(SUM(
           TO_NUMBER(REGEXP_SUBSTR(CALC_SI_AMT, '^-?[0-9]+(\.[0-9]+)?$'))
       ), 0)
INTO v_num
FROM SITB_CONTRACT_MASTER
WHERE REGEXP_LIKE(CALC_SI_AMT, '^-?[0-9]+(\.[0-9]+)?$');
```

Ce pattern isole les seules valeurs numériques avant conversion, évitant ORA-01722.

### 4.10 Commentaires SQL / PL/SQL

- `--` en début de ligne pour un commentaire de section (lisible dans les diff Git).
- `/* ... */` pour un commentaire bloc en en-tête de fichier ou de procédure.
- **Jamais** de `--` en fin de ligne exécutable (risque de confusion lors de la copie vers SQL*Plus).
- Les commentaires doivent expliquer le **pourquoi** (l'intention d'audit), pas le **quoi** (le SQL se lit).

### 4.11 SET SERVEROUTPUT & tailles de buffer

En tête de script, toujours :

```sql
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 200
SET PAGESIZE 0
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING ON
```

Sans `SIZE UNLIMITED`, le buffer `DBMS_OUTPUT` sature vers 20 000 lignes et le script se tait silencieusement.

### 4.12 Spool vers fichier

Pour livrer le rapport au client, prévoir un bloc `SPOOL` commenté qu'il suffit de décommenter :

```sql
-- SPOOL /tmp/revenue_assurance_audit_YYYYMMDD.txt
-- (corps du script)
-- SPOOL OFF
```

Documenter la convention de nommage du fichier de sortie (avec date d'exécution).

---

## 5. Vérification du dictionnaire de données

### 5.1 Pourquoi c'est critique

FCUBS hérite d'un schéma volumineux (plusieurs centaines de tables, plusieurs milliers de colonnes) souvent mal documenté. Plusieurs patterns observés induisent des erreurs fréquentes :

- Même nom de colonne, type différent selon la table (ex. `FREQUENCY_UNIT` est NUMBER dans `LDTM_PRODUCT_DFLT_SCHEDULES` mais VARCHAR2 dans `CLTB_ACCOUNT_APPS_MASTER`).
- Colonnes quasi-synonymes (`WAIVER` vs `WAIVE`, `WAIVER_FLAG` vs `DEFAULT_WAIVER`) qui n'existent pas dans les mêmes tables.
- Tables au nom proche (`CLTB_LIQ` vs `CLTB_AMOUNT_LIQ`) dont une seule existe réellement.
- Colonnes `PRODUCT` vs `PRODUCT_CODE` selon la table.

Un script qui référence une colonne inexistante ou un mauvais type plante au compile (PLS-00904) ou au runtime (ORA-01722, ORA-00942). **Le seul antidote : vérifier systématiquement avant d'écrire.**

### 5.2 Source de vérité : `fcubs.csv`

Le fichier `/home/user/aml_plsql_script/fcubs.csv` à la racine du projet contient le dictionnaire de données extrait de la base cible, au format :

```
"TABLE_NAME","COLUMN_NAME","DATA_TYPE",NUM_ROWS
"ACTB_HISTORY","AC_NO","VARCHAR2",5788417
"ACTB_HISTORY","LCY_AMOUNT","NUMBER",5788417
```

Ce fichier est **la référence unique** avant d'écrire une requête. Si une colonne n'y figure pas, elle n'existe pas dans la base du client (ou elle appartient à une version FCUBS différente).

### 5.3 Règle de vérification avant écriture

Avant toute nouvelle requête dans un script d'audit, **vérifier** :

1. **La table existe** dans `fcubs.csv` (recherche exacte `"NOM_TABLE"`).
2. **Les colonnes référencées existent** dans cette table (recherche `"NOM_TABLE","NOM_COL"`).
3. **Les types sont compatibles** avec les opérations prévues (SUM sur NUMBER, comparaison dates, etc.).
4. **La cardinalité** (`NUM_ROWS`) est raisonnable : si une table a 50 millions de lignes, prévoir `ROWNUM <= p_top_n` ou un filtre agressif.

Commandes type pour interroger le dictionnaire :

```bash
# Lister toutes les colonnes d'une table
grep '"LDTB_CONTRACT_MASTER"' fcubs.csv

# Vérifier qu'une colonne existe
grep '"STTM_CUST_ACCOUNT","DEFAULT_WAIVER"' fcubs.csv

# Trouver toutes les colonnes contenant "WAIV" dans un table
grep '"CLTB_ACCOUNT_COMPONENTS"' fcubs.csv | grep -i WAIV
```

### 5.4 Mise à jour de fcubs.csv

Si le client ajoute/modifie le schéma FCUBS, il doit régénérer `fcubs.csv`. Requête Oracle pour régénération :

```sql
SELECT '"' || OWNER || '.' || TABLE_NAME || '","' || COLUMN_NAME || '","' ||
       DATA_TYPE || '",' || NUM_ROWS
FROM ALL_TAB_COLUMNS c
JOIN ALL_TABLES t USING (OWNER, TABLE_NAME)
WHERE OWNER = 'FCUBS'
ORDER BY TABLE_NAME, COLUMN_ID;
```

Après régénération, relancer tous les scripts d'audit pour valider la compatibilité.

### 5.5 Annotation des requêtes

Lorsqu'une requête croise plusieurs tables, commenter en tête la liste des colonnes utilisées :

```sql
-- Sources :
--   LDTB_CONTRACT_MASTER (CONTRACT_REF_NO, PRODUCT, CONTRACT_STATUS)
--   LDTM_PRODUCT_MASTER  (PRODUCT, BLOCK_PRODUCT)
-- Test : contrats actifs adossés à des produits bloqués
SELECT COUNT(DISTINCT c.CONTRACT_REF_NO) ...
```

Cela rend les dépendances schéma lisibles et facilite la maintenance après refonte FCUBS.

### 5.6 Cas des colonnes absentes mais attendues

Si la logique d'audit suppose une colonne qui n'existe pas dans `fcubs.csv`, deux options :

1. **Rédiger un mini-script d'exploration** (cf. §6.3) demandant au client de confirmer la colonne/table.
2. **Encapsuler la requête dans un BEGIN/EXCEPTION** et logger `N/A` si la colonne manque, pour ne pas bloquer l'audit.

**Ne jamais** inventer le nom d'une colonne en espérant qu'elle existe. Les coûts de debug sont démesurés.

### 5.7 Colonnes FCUBS récurrentes à connaître

Quelques invariants qui reviennent partout :

| Pattern | Sémantique |
|---|---|
| `BRANCH_CODE`, `AC_BRANCH` | Code agence (FBTM_BRANCH) |
| `CUST_NO`, `CUSTOMER_NO`, `CUSTOMER` | CIF client (STTM_CUSTOMER) |
| `CUST_AC_NO`, `ACCOUNT_NUMBER`, `AC_NO` | Compte client (STTM_CUST_ACCOUNT) |
| `LCY_*` | Montant en devise locale (Local Currency) |
| `FCY_*`, `ACY_*` | Montant en devise de l'opération (Foreign / Account Currency) |
| `AUTH_STAT` (`A`/`U`) | Authorized / Unauthorized |
| `RECORD_STAT` (`O`/`C`) | Open / Closed |
| `MAKER_ID` / `CHECKER_ID` | Four-eyes principle (saisie / validation) |
| `*_DT_STAMP` | Horodatage technique |
| `TRN_DT`, `VALUE_DT` | Date de transaction / date valeur |
| `CCY`, `CCY_CODE`, `AC_CCY` | Code devise ISO |
| `EVENT`, `EVENT_SR_NO`, `EVENT_SEQ_NO` | Ordre chronologique des événements sur un contrat |
| `PRODUCT`, `PRODUCT_CODE` | Code produit FCUBS (attention : pas toujours le même nom de colonne) |
| `MODULE` | Module d'origine (`LD`, `CL`, `IC`, `CH`, `GL`, `MM`, `FX`, ...) |

Ces patterns, bien maîtrisés, permettent d'anticiper les colonnes présentes sans avoir à systématiquement interroger `fcubs.csv`.
