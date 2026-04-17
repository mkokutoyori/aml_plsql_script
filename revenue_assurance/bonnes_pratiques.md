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

---

## 6. Approche séquentielle & exploration préalable

### 6.1 Travail séquentiel, sans sous-agent

La rédaction des scripts d'audit se fait **strictement en séquentiel**, sans lancer d'agents parallèles (`Agent`, `subagent_type`, etc.). Plusieurs raisons :

- **Reproductibilité** : chaque étape doit être rejouable à l'identique à partir de l'historique Git. Un sous-agent introduit de l'incertitude et des décisions non-tracées.
- **Contexte partagé** : la rédaction d'une section d'audit dépend des décisions prises dans les sections précédentes (conventions de nommage, paramètres, helpers). Un sous-agent ignore ce contexte.
- **Responsabilité** : le développeur principal garde la main sur chaque décision d'architecture, et peut y revenir librement.
- **Lisibilité du Git log** : un commit = une décision attribuable.

**Règle** : toute la rédaction se fait dans le thread principal, via les outils Read/Edit/Write/Bash. Les agents spécialisés ne sont utilisés que pour des tâches annexes (revue indépendante, recherche documentaire large).

### 6.2 Un commit = une section

Chaque section rédigée — qu'il s'agisse d'un chapitre du BRD, d'une section du script d'audit, ou d'une partie du document de bonnes pratiques — donne lieu à :

1. Une écriture/édition de fichier isolée.
2. Un commit Git avec message préfixé du nom du livrable et du numéro de section (ex. `bonnes_pratiques §5: Verification du dictionnaire`).
3. Un push immédiat sur la branche de développement.

Cela permet au client de suivre l'avancement, de commenter section par section, et de revenir en arrière sans tout perdre en cas de désaccord.

### 6.3 Exploration préalable — workflow

Avant d'écrire un contrôle d'audit ambitieux, la donnée cible doit être comprise. Si une hypothèse n'est pas vérifiable par la seule lecture de `fcubs.csv` (distribution des valeurs, qualité des données, présence effective de patterns), alors :

**Workflow standard** :

1. **Je rédige un mini-script d'exploration** (`explore_<sujet>.sql`) — 30 à 100 lignes — qui répond à UNE question précise.
2. **Je livre ce script** au client avec une consigne claire sur ce qu'il doit faire tourner et où poster la sortie.
3. **Le client exécute** et me renvoie la sortie (fichier texte).
4. **J'analyse** la sortie, j'ajuste mes hypothèses.
5. **Je rédige le contrôle d'audit final** en connaissance de cause.

Exemple typique : avant d'auditer les taux anormaux sur les prêts, je ne sais pas si la colonne `NEGOTIATED_RATE` contient des valeurs décimales (0.12 = 12 %) ou en pourcentage (12). Plutôt que de deviner, je demande :

```sql
-- explore_negotiated_rate.sql
SELECT MIN(NEGOTIATED_RATE), MAX(NEGOTIATED_RATE),
       AVG(NEGOTIATED_RATE), MEDIAN(NEGOTIATED_RATE),
       COUNT(*), COUNT(NEGOTIATED_RATE)
FROM CLTB_ACCOUNT_COMPONENTS
WHERE NEGOTIATED_RATE IS NOT NULL;
```

Le client retourne la sortie, je vois `MIN=0.02, MAX=0.35`, je sais donc que les taux sont en **décimal**, et j'écris mon contrôle en conséquence (`> 0.25` pour « taux > 25 % »).

### 6.4 Mini-scripts d'exploration — conventions

Les mini-scripts d'exploration ad-hoc :

- Sont placés dans `revenue_assurance/exploration/` (créer le sous-répertoire si besoin).
- Sont nommés `explore_<sujet>.sql` (ex. `explore_negotiated_rate.sql`).
- Ne modifient **jamais** la base (pas de DML, pas de DDL).
- Tiennent sur un seul écran si possible.
- Imprimes les résultats avec `DBMS_OUTPUT` ou `SELECT ... FROM DUAL` pour lecture directe en SQL*Plus.
- Sont committés dans Git (traçabilité des questions posées).

Une fois la question résolue, le mini-script reste dans le repo comme documentation vivante.

### 6.5 Ne pas sur-anticiper

Pas d'abstractions prématurées. Pas de structures génériques sur-paramétrables en prévision de besoins futurs. Le script doit répondre au besoin **actuel** de façon claire et directe. Si une abstraction devient utile, elle sera introduite au moment où le besoin apparaît, pas avant.

### 6.6 Documenter les hypothèses non vérifiées

Si, faute de temps ou d'accès à la base, une hypothèse n'est pas vérifiée empiriquement, elle doit apparaître en **commentaire explicite** dans le script, précédée du mot-clé `-- ASSUMPTION:` :

```sql
-- ASSUMPTION: NEGOTIATED_RATE est exprimé en décimal (0.12 = 12 %).
--   À confirmer avec le métier si les seuils de détection paraissent incohérents.
WHERE NEGOTIATED_RATE > 0.25
```

Cela signale à la relecture qu'un point reste ouvert, sans bloquer la livraison.

### 6.7 Livraisons incrémentales

Un script d'audit complet peut compter 3 000+ lignes et couvrir 20+ sections. **Ne jamais le rédiger d'un seul jet**. Procéder par incréments :

1. Une section / un thème par itération.
2. Le client valide la logique sur un échantillon.
3. On passe à la section suivante.

Cette discipline permet de détecter très tôt les désalignements métier et évite de refondre un gros livrable à la dernière minute.

---

## 7. Structure & format du rapport de sortie

### 7.1 Langue

Le rapport de sortie du script d'audit est **rédigé en anglais**. Public cible : direction financière, comité d'audit, auditeurs externes (dont COBAC), régulateurs. L'anglais est la langue de travail standard pour ces audiences.

Les commentaires dans le code source du script peuvent rester en français pour l'équipe de développement, mais tout texte imprimé via `DBMS_OUTPUT.PUT_LINE` **doit** être en anglais.

### 7.2 Structure hiérarchique obligatoire

Chaque rapport suit la structure fixe suivante :

```
================================================================
HEADER BLOCK
  - Title, execution timestamp, database instance, script version
----------------------------------------------------------------
AUDIT PARAMETERS
  - All parameters actually used (cf. §2.4)
================================================================
EXECUTIVE SUMMARY
  - Top 10 findings ranked by LCY impact
  - Overall risk rating (LOW / MEDIUM / HIGH / CRITICAL)
  - Comparison vs previous run (if available)
================================================================
SECTION 1 — <AUDIT THEME 1>
  1.1 <sub-test>
    Finding [F-001] <severity> ....... <LCY impact>
      Description : ...
      Evidence    : ...
      Population  : N records
      Recommendation : ...
  1.2 <sub-test>
    ...
================================================================
SECTION 2 — <AUDIT THEME 2>
  ...
================================================================
APPENDICES
  - Detailed top-N listings referenced in findings
  - Data dictionary cross-reference
  - Glossary
================================================================
FOOTER
  - End-of-run timestamp, total findings count, execution duration
```

### 7.3 Executive summary

Le bloc `EXECUTIVE SUMMARY` est **obligatoire**. Il agrège les findings les plus matériels et permet à un directeur non-technique de saisir l'essentiel en 30 secondes. Il doit contenir :

- **Overall risk rating** — un seul mot : `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`.
- **Total estimated revenue leakage** — somme des impacts LCY quantifiables.
- **Top 10 findings** — tableau formaté : référence du finding, sévérité, impact LCY, description courte.
- **Key ratios** — par ex. ratio de waivers sur encours, ratio de comptes dormants avec matière, couverture du GL income vs ACTB accrued.
- **Trend indicator** (si exécutions antérieures stockées) — évolution depuis la dernière exécution.

### 7.4 Format d'un finding

Chaque finding suit un format standardisé :

```
  Finding [F-042] ........... SEVERITY: HIGH .... IMPACT: 52,916,870 XAF
  ------------------------------------------------------------
  Title       : Accrued debit interest on dormant accounts
  Description : 179 dormant accounts hold positive ACY_ACCRUED_DR_IC,
                creating frozen receivables that should be booked as
                interest income but remain off-balance-sheet.
  Population  : 179 accounts
  LCY impact  : 6,392,829.25 XAF
  Evidence    : STTM_CUST_ACCOUNT where AC_STAT_DORMANT='Y'
                AND ACY_ACCRUED_DR_IC > 0
  Root cause  : Dormancy flag frozen IC accrual posting but not
                reversed the accrued balance.
  Recommendation :
    1. Run dormant account review for accrued IC > 1,000 LCY.
    2. Either book to income or reverse the accrual.
    3. Update dormancy procedure to handle residual accrued balance.
  Owner       : Finance — Revenue Assurance
  Target date : +30d
  ------------------------------------------------------------
```

### 7.5 Référencement des findings

Chaque finding reçoit un identifiant **stable** : `[F-NNN]` où `NNN` est une numérotation séquentielle maintenue entre exécutions. Cela permet au management de suivre la résolution d'un finding spécifique sur plusieurs audits successifs.

Si un finding disparaît entre deux exécutions (problème résolu), son numéro **n'est pas réattribué**. Un nouveau finding reçoit le prochain numéro libre.

### 7.6 Niveaux de sévérité

Normaliser strictement :

| Sévérité | Critère (indicatif) |
|---|---|
| `CRITICAL` | Impact > 1 % du PNB annuel OU risque réglementaire direct |
| `HIGH` | Impact > 10 000 000 XAF OU > 100 comptes concernés |
| `MEDIUM` | Impact > 1 000 000 XAF OU > 10 comptes |
| `LOW` | En dessous des seuils ci-dessus, mais anomalie avérée |
| `INFO` | Observation sans impact immédiat, à surveiller |

Les seuils sont paramétrables (cf. §2.2 `p_materiality_lcy`) et doivent être rappelés dans l'en-tête du rapport.

### 7.7 Formatage des nombres

- Séparateurs de milliers : virgule en anglais (`52,916,870`).
- Deux décimales pour les montants monétaires (`6,392,829.25 XAF`).
- Pourcentages : `12.35 %` (espace avant le %).
- Dates : ISO `YYYY-MM-DD` ; timestamps : `YYYY-MM-DD HH24:MI:SS`.
- Padding à droite avec `.` ou ` ` pour aligner les valeurs (`RPAD(label, 55, '.')`).
- Largeur de ligne maximale : 100 caractères pour tenir dans une console standard.

### 7.8 Tableaux

Pour les listes (top-N), utiliser un format de colonnes fixes avec en-tête et séparateur :

```
  Rank  Branch   Product   LCY Amount       Count
  ----  -------  --------  ---------------  -------
     1  001      LD01      12,345,678.90      4,521
     2  055      CL05       9,876,543.21      3,210
```

Pas de tableaux exotiques (pas d'ASCII art, pas de barres de progression). Un lecteur doit pouvoir copier-coller le rapport dans Excel en un seul clic.

### 7.9 Cross-référencement

- Chaque finding référence les tables FCUBS interrogées (cf. §5.5).
- Chaque finding à dimension réglementaire cite le compte PCEC concerné (ex. `PCEC 70 — Produits sur opérations de trésorerie`).
- Les recommandations pointent vers les sections du script qui pourraient servir à vérifier la correction après remédiation.

### 7.10 Footer & métriques d'exécution

En clôture du rapport :

```
================================================================
END OF AUDIT RUN
  Started at  : 2026-04-17 11:27:45
  Ended at    : 2026-04-17 11:34:12
  Duration    : 00:06:27
  Sections    : 20 / 20 executed
  Findings    : 42 raised (5 CRITICAL, 12 HIGH, 18 MEDIUM, 7 LOW)
  Errors      : 0 blocking, 2 non-blocking (logged inline)
  Report hash : <optional SHA-256 of the report body for integrity>
================================================================
```

Les métriques d'exécution permettent au client de suivre la dérive de performance dans le temps et d'identifier les sections qui ralentissent.

---

## 8. Workflow Git & livraisons

### 8.1 Branche de travail

Tout le développement se fait sur **une branche dédiée** nommée selon le contexte de la tâche (exemple actuel : `claude/continue-revenue-assurance-script-RIaih`). Ne jamais pousser directement sur `main` ou `master`.

### 8.2 Granularité des commits

**Règle d'or** : un commit = une section logique terminée. Pas plusieurs sections dans un seul commit, pas une section coupée en plusieurs commits (sauf correctif de bug).

Avantages :

- Le reviewer lit le diff section par section.
- `git revert` ou `git bisect` isole une régression à la section près.
- Le `git log` devient un plan de livraison lisible.

### 8.3 Message de commit

Format imposé :

```
<livrable> <numéro de section>: <résumé impératif concis>
```

Exemples :

- `bonnes_pratiques §5: Verification du dictionnaire de donnees`
- `audit_script §12: Overdraft tacite sans TOD_LIMIT`
- `explore_revenue_assurance.sql Section 15: LDTB ICCF detaille`
- `Fix ORA-01722: EXITFLAG (NUMBER) needs TO_CHAR in NVL`

Règles :

- Pas d'accents ni caractères spéciaux dans le titre (portabilité terminal).
- Mode impératif : « Fix », « Add », « Refactor », pas « Fixed » ni « Adding ».
- Titre en 72 caractères maximum.
- Si le commit mérite une explication, un corps de message suit le titre après une ligne blanche.

### 8.4 Push après chaque commit

Push **systématique après chaque commit** :

```bash
git push -u origin <branch>
```

Pas de batching local. Le client doit pouvoir consulter la progression sur GitHub en temps réel.

### 8.5 Retry en cas d'échec réseau

Si `git push` échoue pour cause réseau, retry jusqu'à 4 fois avec backoff exponentiel (2 s, 4 s, 8 s, 16 s). Si l'échec persiste, signaler au client, ne pas tenter de forcer le push.

### 8.6 Ne jamais forcer le push

**Interdits absolus** sauf demande explicite écrite du client :

- `git push --force`
- `git push --force-with-lease`
- `git reset --hard` suivi d'un push
- `git commit --amend` sur un commit déjà poussé

Si un commit est erroné, créer un **nouveau commit** qui annule ou corrige. L'historique doit rester linéaire et traçable.

### 8.7 Pull / fetch réguliers

Avant toute nouvelle session de travail :

```bash
git fetch origin <branch>
git pull origin <branch>
```

Pour récupérer les éventuels ajouts du client (rapports d'exécution, nouveaux scripts, données complémentaires). Cas typique : le client a exécuté le script d'exploration et poussé le rapport de sortie dans le repo.

### 8.8 Structure du répertoire `revenue_assurance/`

Convention de structure cible :

```
revenue_assurance/
├── bonnes_pratiques.md               # Ce document
├── BRD_revenue_assurance.md          # Business Requirements Document
├── revenue_assurance_and_accounting_audit.sql   # Script d'audit principal
├── plan_comptable_cobac.txt          # Référence PCEC
├── explore_revenue_assurance.sql     # Script d'exploration (pré-audit)
├── revenue_assurance_exploration_report.txt      # Sortie d'exploration
├── exploration/                      # Mini-scripts d'exploration ad-hoc
│   ├── explore_negotiated_rate.sql
│   └── ...
├── reports/                          # Sorties d'exécution de l'audit
│   ├── audit_report_2026-04-17.txt
│   └── ...
└── doc/                              # Documentation annexe
    ├── data_dictionary_ra.md
    └── changelog.md
```

Ne pas polluer la racine du repo avec des fichiers transitoires.

### 8.9 Jamais d'écriture hors du répertoire du projet

Les scripts d'audit et la documentation restent confinés dans `revenue_assurance/`. Ne jamais créer de fichiers dans `/tmp`, `/home/user/`, ou tout autre chemin hors repo, sauf pour les sorties de spool explicitement documentées (dans ce cas le chemin est un paramètre du script).

### 8.10 Secrets & données sensibles

- **Jamais** de credentials dans les fichiers committés (pas de mot de passe Oracle, pas de token GitHub).
- Pas de données personnelles client en clair dans les rapports d'exemple committés. Si un rapport réel est committé pour archive, anonymiser les CIF / numéros de compte.
- Utiliser `.gitignore` pour exclure les fichiers de config local (`wallet/`, `.env`, `sqlnet.ora`).

### 8.11 Pull requests & revues

Une fois la branche prête pour livraison :

- Créer une Pull Request vers `main` **uniquement sur demande explicite** du client.
- La PR reprend dans sa description :
  - Liste des livrables
  - Sections principales ajoutées
  - Instructions de test (comment lancer le script, paramètres conseillés)
  - Références aux rapports d'exécution

Le client procède à la revue section par section, et demande les ajustements via commentaires GitHub.

### 8.12 Tag de version

Après validation et merge, taguer la livraison :

```
git tag -a ra-v1.0 -m "Revenue Assurance audit — v1.0 production release"
git push origin ra-v1.0
```

Ce tag fige une version reproductible du livrable pour archivage et audit.

---

## 9. Performance & scalabilité

### 9.1 Hypothèses de volumétrie

FCUBS en production contient typiquement :

- `ACTB_HISTORY` : plusieurs millions de lignes (observé : 5,8 M).
- `CLTB_ACCOUNT_SCHEDULES` : centaines de milliers de lignes.
- `STTM_CUST_ACCOUNT` : dizaines de milliers.
- `SMTB_SMS_LOG`, `SMTB_SMS_ACTION_LOG` : millions de lignes (observé : 1,8 M).

Un script qui tombe en timeout à 30 minutes sur `ACTB_HISTORY` est inutilisable. La performance n'est pas un raffinement : c'est un **critère de mise en production**.

### 9.2 Cibles de temps d'exécution

| Mode | Cible | Si dépassé |
|---|---|---|
| `SUMMARY` | < 2 min | refactor obligatoire |
| `FULL` | < 15 min | acceptable pour une exécution de nuit |
| `DEEP` | < 60 min | toléré pour audit trimestriel |

Mesurer systématiquement via `SET TIMING ON` et imprimer la durée de chaque section dans le rapport.

### 9.3 Filtrage précoce

Appliquer les paramètres de filtre (§2) **au plus tôt** dans la requête. Éviter :

```sql
-- MAUVAIS : agrège toute la table puis filtre
SELECT * FROM (
    SELECT BRANCH_CODE, SUM(LCY_AMOUNT) sm
    FROM ACTB_HISTORY
    GROUP BY BRANCH_CODE
) WHERE BRANCH_CODE = p_branch_code;
```

Préférer :

```sql
-- BIEN : filtre avant le GROUP BY
SELECT BRANCH_CODE, SUM(LCY_AMOUNT) sm
FROM ACTB_HISTORY
WHERE (p_branch_code IS NULL OR BRANCH_CODE = p_branch_code)
  AND (p_date_from IS NULL OR TRN_DT >= p_date_from)
GROUP BY BRANCH_CODE;
```

### 9.4 Index présumés

FCUBS crée des index sur les clés métier standard (`TRN_REF_NO`, `BRANCH_CODE + TRN_DT`, `AC_NO`). Privilégier les filtres sur ces colonnes quand plusieurs options sont possibles.

Ne pas présumer d'index sur des colonnes secondaires (`AML_EXCEPTION`, `DONT_SHOWIN_STMT`) : un filtre sur une seule de ces colonnes sans filtre temporel associé peut provoquer un full scan.

### 9.5 Full scan volontaire — bannière d'avertissement

Certains contrôles imposent un full scan (comptage global sur `ACTB_HISTORY` sans filtre temporel, par exemple). Dans ce cas :

- Imprimer une bannière dans le rapport : `Note: Full table scan on ACTB_HISTORY (~5.8M rows), expect ~45s`.
- Mettre ce contrôle en mode `DEEP` uniquement si possible.
- Justifier en commentaire dans le code pourquoi le full scan est nécessaire.

### 9.6 HINTs Oracle — à éviter par défaut

Ne pas sprinkler de `/*+ INDEX(...) */` sans nécessité. L'optimiseur Oracle gère généralement bien les plans de requêtes. Un hint mal choisi fige un plan qui devient sous-optimal après évolution statistique des tables.

Exceptions tolérées :

- `/*+ PARALLEL(8) */` sur les agrégats lourds en mode `DEEP`.
- `/*+ FIRST_ROWS(25) */` pour les top-N quand `ORDER BY` est sur une colonne indexée.

Toujours commenter l'intention du hint.

### 9.7 Sampling pour explorations visuelles

Pour un aperçu (pas pour un audit complet), utiliser l'échantillonnage natif Oracle :

```sql
SELECT *
FROM ACTB_HISTORY SAMPLE (0.1)    -- 0.1 % de l'échantillon
WHERE LCY_AMOUNT > 1000000;
```

Plus rapide qu'un full scan et suffisant pour valider la forme des données. À **ne pas** utiliser pour les chiffres de reporting final : le sampling fausse les agrégats.

### 9.8 Matérialisation intermédiaire

Pour les audits complexes qui réutilisent un même sous-ensemble plusieurs fois, envisager une table temporaire de travail :

```sql
-- En tête du script (si droits disponibles)
CREATE GLOBAL TEMPORARY TABLE t_ra_recent_movements ON COMMIT PRESERVE ROWS AS
SELECT * FROM ACTB_HISTORY WHERE 1=0;

-- Dans le script
INSERT INTO t_ra_recent_movements
SELECT * FROM ACTB_HISTORY
WHERE TRN_DT BETWEEN p_date_from AND p_date_to
  AND (p_branch_code IS NULL OR BRANCH_CODE = p_branch_code);
```

Les requêtes ultérieures tournent sur la temp table (quelques milliers de lignes au lieu de millions). Attention : les droits `CREATE TABLE` ne sont pas toujours accordés au schéma d'audit. Prévoir un fallback.

### 9.9 Évitement des N+1

**Interdit** : ouvrir un curseur sur une table, puis pour chaque ligne exécuter un `SELECT` sur une autre table.

```sql
-- TRÈS MAUVAIS
FOR r IN (SELECT CONTRACT_REF_NO FROM LDTB_CONTRACT_MASTER WHERE ...) LOOP
    SELECT SUM(AMOUNT) INTO v_sum
    FROM LDTB_CONTRACT_LIQ
    WHERE CONTRACT_REF_NO = r.CONTRACT_REF_NO;
    print_kv('  Contract ' || r.CONTRACT_REF_NO, TO_CHAR(v_sum));
END LOOP;
```

Remplacer par une seule jointure agrégée :

```sql
FOR r IN (
    SELECT m.CONTRACT_REF_NO, NVL(SUM(l.AMOUNT), 0) sm
    FROM LDTB_CONTRACT_MASTER m
    LEFT JOIN LDTB_CONTRACT_LIQ l ON l.CONTRACT_REF_NO = m.CONTRACT_REF_NO
    WHERE m.CONTRACT_STATUS = 'A'
    GROUP BY m.CONTRACT_REF_NO
) LOOP
    print_kv('  Contract ' || r.CONTRACT_REF_NO, TO_CHAR(r.sm));
END LOOP;
```

### 9.10 Limiter DBMS_OUTPUT

Le buffer `DBMS_OUTPUT` est mémoire. Imprimer des millions de lignes est :

1. Lent (chaque ligne transite par le buffer puis l'affichage).
2. Illisible (rapport inexploitable).
3. Potentiellement tronqué malgré `SIZE UNLIMITED`.

**Règle** : les top-N se limitent à `p_top_n` (défaut 25, max 100). Ne jamais imprimer une liste non bornée. Pour les drill-downs massifs, prévoir un export CSV via `UTL_FILE`.

### 9.11 Chronométrage par section

Instrumenter chaque section avec un chronométrage :

```sql
DECLARE
    v_t0 TIMESTAMP;
BEGIN
    v_t0 := SYSTIMESTAMP;
    -- corps de la section
    print_kv('  Section duration',
             TO_CHAR(EXTRACT(SECOND FROM (SYSTIMESTAMP - v_t0))) || 's');
END;
```

Les sections > 60 s deviennent candidates au refactor ou au mode `DEEP` uniquement.

---

## 10. Traçabilité & reproductibilité

### 10.1 Principe

Un audit qui ne peut pas être rejoué à l'identique n'a pas de valeur probante. Le rapport livré aux régulateurs doit pouvoir être reconstitué intégralement à partir :

1. De la version taguée du script.
2. De la plage temporelle fixée par les paramètres.
3. D'un état figé de la base (snapshot ou sauvegarde).

### 10.2 Horodatage

Chaque rapport imprime **deux horodatages** :

- `Execution timestamp` — moment de lancement du script (`SYSTIMESTAMP` au démarrage).
- `Data cut-off` — borne haute des données incluses (`p_date_to` ou `SYSDATE`).

Les deux peuvent diverger si l'audit est lancé à t=J pour une période arrêtée au J-1. Les distinguer évite toute ambiguïté.

### 10.3 Version du script dans le rapport

En tête de chaque rapport, imprimer :

```
Script version  : revenue_assurance_and_accounting_audit.sql v1.3.2
Git commit      : 7e50e58 (2026-04-17)
Script checksum : SHA-256: <hash>
```

La version se met à jour manuellement dans une constante en tête du script (`C_SCRIPT_VERSION CONSTANT VARCHAR2(20) := '1.3.2';`). Le commit Git peut être imprimé si l'environnement le permet.

### 10.4 Rappel systématique des paramètres

Tout paramètre utilisé est **imprimé** dans la section `AUDIT PARAMETERS` (cf. §2.4). Aucune valeur par défaut masquée. Si un paramètre n'a pas été fourni, imprimer explicitement `(default) <valeur>`.

### 10.5 Déterminisme

Chaque requête doit produire **le même résultat** à données constantes. Vigilance sur :

- **ORDER BY incomplets** : dans un top-N, deux lignes à égalité sur la colonne de tri peuvent permuter entre exécutions. Toujours ajouter une clé de départage stable (`ORDER BY sm DESC, CONTRACT_REF_NO`).
- **SYSDATE** : si le script utilise `SYSDATE` dans plusieurs endroits, deux évaluations à quelques secondes d'intervalle peuvent produire des bornes légèrement différentes. Fixer une variable `v_run_ts := SYSDATE` au début et la réutiliser.
- **ROWID** : jamais utiliser `ROWID` comme tri ou référence. Non stable entre réorganisations.
- **Fonctions non déterministes** : éviter `DBMS_RANDOM`, `SYS_GUID()` dans un audit.

### 10.6 Logs d'exécution séparés

Outre le rapport d'audit principal (output fonctionnel), produire un **log technique** parallèle contenant :

- Chaque erreur non-bloquante (`SQLERRM`).
- Chaque table ignorée pour cause d'absence.
- Chaque paramètre ajusté (ex. `p_materiality_lcy < 0 -> abs value applied`).
- Chaque chronométrage par section.

Ces deux flux peuvent partager le même fichier de sortie en les distinguant par préfixe :

```
[AUDIT ] Finding [F-042] ...
[LOG   ] Table LDTM_XYZ ignored: ORA-00942
[PERF  ] Section 12 duration: 4.2s
```

### 10.7 Archivage des rapports

Chaque rapport d'exécution est archivé dans `revenue_assurance/reports/` sous la forme :

```
reports/audit_report_<env>_<YYYYMMDD>_<HHMM>.txt
```

Exemple : `reports/audit_report_PROD_20260417_1127.txt`.

Ne pas écraser un rapport précédent : l'historique permet de tracer l'évolution des indicateurs dans le temps.

### 10.8 Comparaison avec l'exécution précédente

Si un rapport précédent existe dans `reports/`, le script peut en extraire les compteurs des findings clés et afficher l'évolution :

```
  [F-042] Accrued DR on dormant accounts
    Current run  : 179 records / 6,392,829 XAF
    Previous run : 203 records / 7,840,112 XAF  (-24 records, -18.5%)
```

Cela transforme un audit statique en outil de suivi dynamique. Comparaison mécanique sur les `[F-NNN]`.

### 10.9 Documentation du schéma FCUBS utilisé

Maintenir un fichier `doc/data_dictionary_ra.md` qui liste **toutes les tables et colonnes** effectivement utilisées par le script d'audit, avec :

- Le nom de la table.
- Les colonnes lues.
- La sémantique métier de chaque colonne.
- Le finding / la section qui l'utilise.

Ce document est mis à jour à chaque ajout de section. Il sert d'annexe à la documentation d'audit et facilite la vérification de la portée par le client.

### 10.10 Pas de mutation de la base

**Interdit absolu** : `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE`, `CREATE`, `ALTER`, `DROP`, `GRANT` sur les tables FCUBS.

Exception : `CREATE GLOBAL TEMPORARY TABLE` pour des besoins internes (§9.8), et seulement dans un schéma d'audit dédié. Même dans ce cas, nettoyage systématique en fin de script.

Le script d'audit est en **lecture seule**. Toute tentative d'écriture doit faire échouer le script en erreur explicite.

### 10.11 Annonce de fin claire

Le rapport se termine par une ligne sans ambiguïté :

```
>>> END OF AUDIT — no runtime errors
```

ou

```
>>> END OF AUDIT — with 2 non-blocking warnings (see [LOG] entries)
```

Le client doit savoir en un coup d'œil si l'audit s'est terminé normalement, même si des erreurs non-bloquantes sont survenues.

---

## 11. Gestion des erreurs & logging

### 11.1 Taxonomie des erreurs

Trois niveaux à distinguer :

| Niveau | Exemple | Réaction |
|---|---|---|
| **Fatal** | Paramètre incohérent, base indisponible, pas de droit SELECT | Stopper l'audit, sortie `-20001..-20099` |
| **Bloquant local** | Colonne obsolète dans une requête SECTION critique | Logger, marquer le finding comme `[ERROR]`, continuer |
| **Non-bloquant** | Table optionnelle absente, sample vide | Logger en `[LOG ]`, imprimer `N/A`, continuer |

### 11.2 Erreurs fatales — validation préalable

Dans le tout premier bloc `BEGIN` du script, valider :

```sql
-- Sanity checks
IF p_date_from IS NOT NULL AND p_date_to IS NOT NULL
   AND p_date_from > p_date_to THEN
    RAISE_APPLICATION_ERROR(-20001,
        'p_date_from (' || TO_CHAR(p_date_from, 'YYYY-MM-DD') ||
        ') > p_date_to (' || TO_CHAR(p_date_to, 'YYYY-MM-DD') || ')');
END IF;

IF p_materiality_lcy < 0 THEN
    print_warning('p_materiality_lcy < 0 — absolute value applied');
    p_materiality_lcy := ABS(p_materiality_lcy);
END IF;

-- Check database connectivity and expected schema
BEGIN
    SELECT COUNT(*) INTO v_count FROM ACTB_HISTORY WHERE ROWNUM = 1;
EXCEPTION
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20002,
            'ACTB_HISTORY not readable: ' || SQLERRM);
END;
```

### 11.3 Plage -20001 à -20099 réservée

Réserver :

- `-20001` à `-20019` : erreurs de paramètres
- `-20020` à `-20039` : erreurs de schéma / connectivité
- `-20040` à `-20059` : erreurs de logique d'audit (assertion violée)
- `-20060` à `-20099` : erreurs diverses

Maintenir un tableau des codes utilisés dans `doc/error_codes.md`.

### 11.4 Handler WHEN OTHERS — obligations

Tout `WHEN OTHERS` doit :

1. Capturer `SQLCODE` et `SQLERRM`.
2. Logger dans le rapport avec préfixe `[LOG ]` ou `[ERROR]`.
3. **Jamais** `NULL;` silencieux (cf. §3.2).
4. Préserver l'information d'origine : `SUBSTR(SQLERRM, 1, 200)` pour éviter les lignes trop longues, mais conserver le message.

```sql
EXCEPTION
    WHEN OTHERS THEN
        log_error(
            p_section => 'SECTION 12',
            p_subtest => '12.13 ACTB_ACCBAL_HISTORY',
            p_sqlcode => SQLCODE,
            p_sqlerrm => SUBSTR(SQLERRM, 1, 400)
        );
        print_kv('  ACTB_ACCBAL_HISTORY stats', 'N/A (see [ERROR] log)');
```

### 11.5 Helper `log_error`

Procédure standard :

```sql
PROCEDURE log_error(
    p_section VARCHAR2,
    p_subtest VARCHAR2,
    p_sqlcode NUMBER,
    p_sqlerrm VARCHAR2
) IS
BEGIN
    DBMS_OUTPUT.PUT_LINE('[ERROR] ' ||
        TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3') || ' | ' ||
        p_section || ' / ' || p_subtest || ' | ' ||
        'SQLCODE=' || TO_CHAR(p_sqlcode) || ' | ' ||
        p_sqlerrm);
    g_error_count := g_error_count + 1;
END;
```

Le compteur global `g_error_count` est incrémenté pour alimenter la ligne finale du rapport (§10.11).

### 11.6 Nesting des blocs

Préférer un grand nombre de petits blocs `BEGIN/EXCEPTION/END;` bien délimités à un seul gros `WHEN OTHERS` qui catch toute une section.

Raison : un seul `WHEN OTHERS` masque la localisation de l'erreur. Dix petits blocs isolent précisément la sous-requête défaillante et permettent au reste de la section de tourner normalement.

### 11.7 Messages de log — format

Chaque log ligne imprime :

```
[LEVEL] YYYY-MM-DD HH24:MI:SS.FF3 | SECTION N.m | SQLCODE=... | message
```

Avec `LEVEL` ∈ {`INFO `, `WARN `, `ERROR`, `PERF `, `AUDIT`}. Le padding à 5 caractères maintient l'alignement visuel dans le rapport.

### 11.8 Erreurs silencieuses — interdiction

**Les comportements suivants sont interdits** :

- `EXCEPTION WHEN OTHERS THEN NULL;`
- Ignorer le retour d'une procédure sans vérifier qu'elle a fonctionné.
- Dire « la requête a retourné 0 » sans distinguer « 0 parce qu'il n'y a rien » de « 0 parce que la requête a échoué ».

Cette distinction est cruciale pour un audit : un finding à 0 enregistrements doit être une **absence confirmée**, pas une défaillance masquée.

### 11.9 Cas spécifique : table partiellement absente

Certaines installations FCUBS n'ont pas toutes les tables (modules non licenciés). Pour ces cas, utiliser le pattern :

```sql
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM GETM_FACILITY WHERE ROWNUM=1';
    -- table exists, run the actual audit
    BEGIN
        SELECT COUNT(*) INTO v_count FROM GETM_FACILITY WHERE ...;
        print_kv('  Facility audit', TO_CHAR(v_count));
    EXCEPTION
        WHEN OTHERS THEN log_error(...);
    END;
EXCEPTION
    WHEN OTHERS THEN
        print_kv('  Facility audit', 'SKIPPED (table GETM_FACILITY unavailable)');
END;
```

Le premier `EXECUTE IMMEDIATE` teste l'existence sans faire planter le parse.

### 11.10 Résumé d'erreurs en tête de rapport

Si des erreurs non-bloquantes sont survenues, un bloc `KNOWN LIMITATIONS` résume en tête (après le summary) :

```
---------------------------------------------------------------
KNOWN LIMITATIONS — 2 sections ran with reduced scope
---------------------------------------------------------------
  [SECTION 18.5] SMTB_PASSWORD_HISTORY not accessible
    -> audit of password rotation policy SKIPPED
  [SECTION 20.7] LDTB_COMPUTATION_HANDOFF empty
    -> EOD handoff monitoring returned no data
---------------------------------------------------------------
```

Le lecteur sait immédiatement que l'audit n'a pas eu 100 % de couverture, et où se situent les zones aveugles.
