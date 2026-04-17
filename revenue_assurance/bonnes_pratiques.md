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
