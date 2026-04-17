# Business Requirements Document — Revenue Assurance & Accounting Audit

> **Projet** : Script unifié d'audit *Revenue Assurance* et de contrôle comptable sur le core banking **FCUBS** (Oracle Flexcube Universal Banking).
> **Livrable principal** : `revenue_assurance_and_accounting_audit.sql`
> **Référentiel comptable** : Plan Comptable des Établissements de Crédit de la CEMAC — **COBAC R-98/01** (1998).
> **Document complémentaire** : [`bonnes_pratiques.md`](./bonnes_pratiques.md) — normes de rédaction et d'exécution du script.
> **Version BRD** : 0.1 (rédaction en cours, section par section).

---

## 1. Contexte, portée et objectifs

### 1.1 Contexte métier

La banque opère sur **Oracle FCUBS** comme système d'information bancaire central (core banking). Les opérations y sont enregistrées en temps réel et déversent au bilan via le module GL (comptes généraux) et les tables de contrepartie (`ACTB_HISTORY`, `GLTB_GL_BAL`, `STTM_CUST_ACCOUNT`, modules CL — *Consumer Lending*, LD — *Loans & Deposits*, SI — *Standing Instructions*, IC — *Interest & Charges*, etc.).

Une **exploration technique préalable** a été conduite (cf. [`revenue_assurance_exploration_report.txt`](./revenue_assurance_exploration_report.txt), 2 769 lignes, 20 sections). Cette exploration a mis en évidence des **anomalies potentielles** et des **zones à risque** qui peuvent se traduire par :
- des **pertes de produits** (revenue leakage) : intérêts non perçus, frais non débités, commissions oubliées, découverts non facturés ;
- des **erreurs comptables** : comptes dormants avec intérêts courus non apurés, écritures manuelles sans justificatif, soldes GL anormaux, réconciliations en souffrance ;
- des **déviations de conformité** vis-à-vis du PCEC COBAC (regroupement de comptes, classes de charges/produits, hors-bilan).

Dans un contexte CEMAC où la **COBAC** (Commission Bancaire de l'Afrique Centrale) exige un reporting prudentiel rigoureux, et où les marges d'intermédiation sont structurellement comprimées, la **Revenue Assurance** devient un levier direct de résultat net et un garde-fou de conformité.

### 1.2 Portée fonctionnelle (*scope*)

Le script couvre **trois dimensions** auditables à partir des données FCUBS :

| Dimension | Contenu | Source FCUBS |
|---|---|---|
| **Revenue Assurance** | Détection et quantification de fuites de revenus sur : intérêts (prêts, découverts, comptes courants créditeurs), commissions, frais de tenue de compte, standing instructions, pénalités de retard, frais de change. | Modules IC, CL, LD, SI, CH, FX + `ACTB_HISTORY` |
| **Contrôle comptable** | Cohérence `ACTB_HISTORY` ↔ `GLTB_GL_BAL`, écritures manuelles, comptes d'attente / suspense, FX revaluation, accruals non apurés, comptes sans mouvement avec solde, mapping PCEC. | GL, MO (Manual Operations), FT (Funds Transfer) |
| **Cartographie PCEC** | Rapprochement des soldes agrégés aux rubriques normatives des classes **1 à 9** de la COBAC (bilan, charges, produits, hors-bilan). | `GLTB_GL_MASTER`, `GLTB_GL_BAL`, PCEC COBAC R-98/01 |

### 1.3 Hors portée

Ne sont **pas** couverts dans ce BRD / ce script :
- La **lutte anti-blanchiment (AML/CFT)** — objet d'un module dédié distinct.
- Le **contrôle prudentiel** (ratios de solvabilité, liquidité, grands risques) — couvert par le reporting COBAC dédié.
- Les **contrôles opérationnels temps réel** (workflows, maker/checker) — relèvent de la configuration applicative.
- Les **systèmes périphériques** non FCUBS (monétique, mobile money, trésorerie hors FCUBS) — audits séparés.
- La **remédiation automatique** : le script **détecte et rapporte**, il ne **modifie jamais** les données.

### 1.4 Objectifs stratégiques

L'audit vise **cinq objectifs principaux**, ordonnés par valeur métier décroissante :

1. **Identifier et chiffrer les pertes de revenus** (revenue leakage) en devises locales et de bilan, par agence, par produit, par contrepartie, afin de prioriser les actions de recouvrement.
2. **Détecter les anomalies comptables** susceptibles de fausser le résultat ou les états financiers (accruals dormants, écritures manuelles non justifiées, FX reval incohérents, comptes d'attente vieillissants).
3. **Produire un rapport exploitable par la Direction Financière, l'Audit Interne et la COBAC**, en anglais, structuré, avec sévérité, impact monétaire estimé et recommandation par constat.
4. **Fournir une base de preuves auditable** (traçable, reproductible, paramétrée) — chaque constat doit être ré-exécutable et rattaché à une requête de référence.
5. **Aligner les constats sur le PCEC COBAC R-98/01** pour faciliter la lecture par les superviseurs et le contrôle de gestion réglementaire.

### 1.5 Objectifs SMART

| # | Objectif | Indicateur | Cible |
|---|---|---|---|
| O1 | Couvrir les principaux points de fuite identifiés à l'exploration | Nombre de sections d'audit | ≥ 20 thèmes |
| O2 | Chiffrer l'impact financier estimé | % de constats avec impact LCY | ≥ 80 % |
| O3 | Exécuter en mode FULL sur une photo mensuelle | Temps d'exécution cible | < 15 minutes |
| O4 | Paramétrage optionnel complet | Paramètres supportés | ≥ 10 (période, agences, comptes, devises, seuils, mode) |
| O5 | Conformité COBAC | % de sections référant une classe PCEC | 100 % |

### 1.6 Parties prenantes

| Rôle | Responsabilité vis-à-vis du livrable |
|---|---|
| **Direction Financière** | Utilisateur principal du rapport ; priorisation des recouvrements ; arbitrages. |
| **Audit Interne** | Recette métier ; utilisation des constats pour les missions ; archivage. |
| **Contrôle de Gestion / Reporting COBAC** | Rapprochement PCEC ; reporting prudentiel. |
| **DSI / Equipe FCUBS** | Accès à la base, exécution planifiée, maintenance du script, gestion des droits lecture seule. |
| **Risk & Compliance** | Revue des constats à caractère réglementaire ; escalade COBAC le cas échéant. |
| **Direction Générale** | Décision stratégique sur les actions correctives majeures. |

### 1.7 Hypothèses structurantes

- **H1** — L'exécution se fait sur un **environnement de lecture** (standby, réplique, ou instance DWH) ou en mode read-only sur PROD en dehors des heures ouvrables.
- **H2** — Le compte d'exécution dispose d'un accès **SELECT uniquement** sur les schémas FCUBS pertinents, sans privilège de modification.
- **H3** — La version cible est **Oracle 11gR2 ou supérieure**. Toute syntaxe plus récente (FETCH FIRST, JSON_OBJECT, etc.) est proscrite.
- **H4** — Le paramétrage par défaut (`NULL` → tout inclus) doit donner un rapport **complet exhaustif** ; l'utilisateur peut restreindre a posteriori.
- **H5** — Le script **ne modifie aucune donnée** (pas d'INSERT/UPDATE/DELETE/DDL/DCL). Toute violation de cette règle est bloquante en revue.
- **H6** — La source de vérité des colonnes est `fcubs.csv` (dictionnaire extrait des vues système). Aucune colonne ne doit être inventée.

### 1.8 Résultats attendus

Le projet livre :
1. `bonnes_pratiques.md` — normes de rédaction (déjà livré).
2. `BRD_revenue_assurance.md` — présent document.
3. `revenue_assurance_and_accounting_audit.sql` — script paramétrable produisant un rapport texte horodaté en anglais.
4. Un **rapport d'exemple** anonymisé (à défaut, la capture du premier run contrôlé).

---

## 2. Glossaire, définitions et cadre de référence

### 2.1 Glossaire des termes métier

| Terme | Définition retenue pour ce document |
|---|---|
| **Revenue Assurance (RA)** | Ensemble des contrôles détectifs visant à s'assurer que tout revenu contractuellement dû à la banque a bien été calculé, facturé, comptabilisé et encaissé. |
| **Revenue leakage** | Perte de revenu non facturé ou non encaissé, imputable à une défaillance de paramétrage, de processus, de données ou de contrôle. |
| **Accrual** | Charge ou produit à recevoir / à payer couru mais non encore liquidé (ex. intérêts courus non échus — ICNE). |
| **Dormant account** | Compte client sans mouvement de clientèle sur une période définie par la politique interne (typiquement 6 à 12 mois). |
| **Overdraft autorisé (TOD limit)** | Autorisation formelle de découvert matérialisée par un paramétrage `TOD_LIMIT` sur `STTM_CUST_ACCOUNT`. |
| **Overdraft non autorisé** | Solde débiteur d'un compte sans `TOD_LIMIT`, ou dépassant la limite accordée. |
| **Standing Instruction (SI)** | Instruction permanente (prélèvement automatique) — module SI FCUBS. |
| **Waiver** | Remise ou annulation d'un frais ou d'un intérêt, matérialisée dans FCUBS par des flags `WAIVE*` ou `WAIVER_*` selon la table. |
| **Materiality (LCY)** | Seuil de matérialité exprimé en devise locale, en deçà duquel un écart est jugé non significatif. |
| **Finding** | Constat d'audit unitaire, identifié par `[F-NNN]`, doté d'une sévérité, d'un impact, d'une recommandation. |
| **Severity** | Niveau de gravité du constat : `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `INFO`. |
| **Mode d'exécution** | `SUMMARY` (indicateurs agrégés), `FULL` (rapport complet), `DEEP` (avec top-N par dimension). |
| **Photo comptable** | Instantané des soldes à une date donnée (fin de mois généralement), utilisé comme périmètre d'audit. |
| **LCY / FCY** | Local Currency / Foreign Currency — convention FCUBS. |
| **Branch** | Agence comptable au sens FCUBS (`BRANCH_CODE`). |

### 2.2 Glossaire technique FCUBS (tables et modules clés)

| Module / Table | Rôle fonctionnel |
|---|---|
| `ACTB_HISTORY` | Historique des écritures comptables (mouvements par compte / GL). |
| `GLTB_GL_BAL` / `GLTB_GL_MASTER` | Soldes et paramétrage des comptes généraux (GL). |
| `STTM_CUST_ACCOUNT` / `STTM_CUSTOMER` | Comptes clients et référentiel clientèle. |
| `STDTB_BRANCH` | Référentiel des agences. |
| **Module CL** — `CLTB_ACCOUNT_MASTER`, `CLTB_ACCOUNT_COMPONENTS`, `CLTB_LIQ`, `CLTB_SCHEDULES_DETAILS` | Consumer Lending (crédits à la clientèle) : principal, composantes (INT, PRINCIPAL, FEES), liquidations, échéanciers. |
| **Module LD** — `LDTB_CONTRACT_MASTER`, `LDTM_PRODUCT_MASTER`, `LDTB_SCHEDULES` | Loans & Deposits (crédits/dépôts interbancaires et grands comptes). |
| **Module SI** — `SITB_CONTRACTS`, `SITB_EXEC_LOG` | Standing Instructions (prélèvements/virements permanents). |
| **Module IC** — `ICTB_ACCRUALS_TEMP`, `ICTB_LIQ_DETAILS` | Interest & Charges (moteur de calcul intérêts et frais). |
| **Module MO** — `MOTB_CONTRACT_MASTER` | Manual Operations (écritures manuelles). |
| **Module FT** — `FTTB_CONTRACT_MASTER` | Funds Transfer (virements). |
| **Module FX** — `FXTB_CONTRACT_MASTER` | Foreign Exchange (contrats de change). |
| `SMTB_USER`, `SMTB_ROLE` | Référentiel utilisateurs / droits applicatifs. |

> La liste exhaustive des colonnes auditables est tirée de `fcubs.csv` (dictionnaire), seule source de vérité ; aucun champ ne doit être inventé (cf. `bonnes_pratiques.md` §5).

### 2.3 Cadre comptable de référence — PCEC COBAC R-98/01

Le **Plan Comptable des Établissements de Crédit de la CEMAC** (Règlement COBAC **R-98/01**, 1998) structure la comptabilité bancaire en **neuf classes** :

| Classe | Nature | Pertinence pour l'audit RA / comptable |
|---|---|---|
| **1** | Opérations de trésorerie et opérations avec les établissements de crédit | Réconciliations interbancaires, NOSTRO/VOSTRO, accruals interbancaires. |
| **2** | Opérations avec la clientèle | Crédits clientèle, découverts, dépôts ; **foyer principal** de fuite de revenus (intérêts, commissions, pénalités). |
| **3** | Opérations sur titres et opérations diverses | Portefeuille titres, comptes de régularisation, **comptes d'attente / suspense** (38x). |
| **4** | Valeurs immobilisées | Immobilisations, amortissements, participations — moins exposé à la RA quotidienne. |
| **5** | Capitaux permanents | Fonds propres, réserves, résultat — contrôle d'intégrité du résultat net. |
| **6** | Charges | **Charges d'exploitation bancaire** (intérêts versés), charges générales. |
| **7** | Produits | **Produits d'exploitation bancaire** (intérêts reçus, commissions) — foyer des manques à gagner. |
| **8** | Soldes caractéristiques de gestion | Produit net bancaire, résultat brut d'exploitation — indicateurs dérivés. |
| **9** | Engagements hors bilan | Garanties données/reçues, engagements de financement — exposition non bilantielle. |

Chaque **classe** se décline hiérarchiquement en :
- **comptes principaux** (2 chiffres) ;
- **comptes divisionnaires** (3 chiffres) ;
- **sous-comptes** (4 chiffres et plus).

L'audit doit, autant que possible, **rattacher chaque constat à la rubrique PCEC correspondante** (classe voire compte divisionnaire) pour faciliter la lecture par le contrôle de gestion et le reporting prudentiel.

### 2.4 Références normatives et réglementaires

- **COBAC R-98/01** (1998) — Plan Comptable des Établissements de Crédit de la CEMAC.
- **COBAC R-2009/02** — dispositif de contrôle interne des établissements de crédit.
- **Oracle Flexcube Universal Banking** — *Core Functional Guide* et *Data Model Reference* de la version en exploitation.
- **ISO 20022** — pour les conventions de libellés et codes devises / pays (où pertinent).
- **Normes IFRS / OHADA-SYSCOHADA** — cadre comptable supplétif ; le PCEC COBAC prime en matière bancaire CEMAC.
- Documents internes : politique de tarification, grille des frais, circulaire de provisionnement, procédure dormance.

### 2.5 Conventions de notation dans ce BRD

- **MUST** / **DOIT** = exigence ferme, non négociable.
- **SHOULD** / **DEVRAIT** = recommandation forte, toute dérogation doit être justifiée et tracée.
- **MAY** / **PEUT** = option admise.
- Les identifiants de constat d'audit sont formatés `[F-NNN]` (numéro séquentiel à trois chiffres, stable dans le temps).
- Les références d'exigence métier sont formatées `[BR-NN]` (Business Requirement) et `[FR-NN]` (Functional Requirement) dans les sections suivantes.
- Les libellés de rubriques PCEC sont notés `PCEC/<classe>` ou `PCEC/<compte>` (ex. `PCEC/2`, `PCEC/702`).

---

## 3. Exigences métier (Business Requirements)

Les exigences métier expriment, du point de vue des **parties prenantes**, les besoins que le livrable doit satisfaire. Elles sont déclinées en exigences fonctionnelles au §4 et en contrôles détaillés au §7.

### 3.1 Besoins de la Direction Financière

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-01** | Chiffrer en LCY les pertes de revenus potentielles détectées sur la période auditée, par **agence**, **produit**, **client** et **rubrique PCEC**. | MUST | Prioriser le recouvrement et le cadrage budgétaire. |
| **BR-02** | Fournir un **Executive Summary** en tête de rapport, limité à 1 page équivalente, listant les 10 à 20 constats les plus matériels. | MUST | Lecture rapide par la Direction. |
| **BR-03** | Permettre la **simulation** de l'effet P&L d'une correction (intérêts manqués sur découvert, SI non facturées) via des agrégats par compte / contrepartie. | SHOULD | Aide à la négociation client et aux arbitrages commerciaux. |
| **BR-04** | Exposer la **volumétrie** des cas (nombre de comptes, contrats, écritures) en regard de chaque impact monétaire. | MUST | Éviter les faux positifs à fort impact unitaire mais isolés. |
| **BR-05** | Présenter l'évolution des indicateurs clés entre **deux runs** (comparatif mensuel). | MAY | Cible à terme ; peut être traité hors script dans un premier temps. |

### 3.2 Besoins de l'Audit Interne

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-10** | Produire des constats **ré-exécutables** : chaque `[F-NNN]` doit être rattaché à une requête de référence documentée dans le script. | MUST | Piste d'audit, revue par des pairs, contre-audit externe. |
| **BR-11** | **Ne modifier aucune donnée** : script strictement en lecture (SELECT uniquement). | MUST | Règle d'or audit ; toute déviation est bloquante. |
| **BR-12** | Horodater le rapport (date de génération, photo comptable auditée, version du script) et identifier l'exécutant. | MUST | Traçabilité et archivage. |
| **BR-13** | Détailler chaque constat par : **description**, **volume**, **impact**, **sévérité**, **rubrique PCEC**, **recommandation**, **requête d'appui**. | MUST | Exploitable tel quel dans un rapport de mission. |
| **BR-14** | Documenter les **limitations connues** (KNOWN LIMITATIONS) en fin de rapport. | MUST | Transparence sur le périmètre effectivement couvert. |

### 3.3 Besoins du Contrôle de Gestion / Reporting COBAC

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-20** | Rattacher chaque section d'audit à au moins **une classe** PCEC COBAC R-98/01. | MUST | Lecture prudentielle et réglementaire. |
| **BR-21** | Identifier les comptes GL non mappés ou mal mappés au PCEC. | SHOULD | Qualité du reporting COBAC. |
| **BR-22** | Détecter les **écritures manuelles** massives, récurrentes ou sur comptes sensibles (charges, produits, suspense). | MUST | Risque de manipulation de résultat. |
| **BR-23** | Identifier les **comptes d'attente / suspense** (classe 38x) à ancienneté anormale. | MUST | Risque de résultat latent ou de masquage. |
| **BR-24** | Vérifier la cohérence **ACTB_HISTORY ↔ GLTB_GL_BAL** sur un sous-ensemble de GL critiques. | SHOULD | Intégrité comptable. |

### 3.4 Besoins de la DSI / Équipe FCUBS

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-30** | Compatibilité **Oracle 11gR2 minimum** sans dépendance à des objets applicatifs (packages métier) autres que le dictionnaire. | MUST | Exécution possible sur standby, DWH ou PROD. |
| **BR-31** | Exécution en **bloc PL/SQL anonyme** unique, sans création d'objets (procédures, tables, types). | MUST | Pas d'installation ; zéro empreinte persistante. |
| **BR-32** | **Paramétrage** par variables de tête : période, agence(s), compte(s), devise(s), seuils, mode, top-N, etc., tous optionnels (NULL = pas de filtre). | MUST | Flexibilité d'usage. |
| **BR-33** | Borne de **temps d'exécution** : `SUMMARY` < 2 min, `FULL` < 15 min, `DEEP` < 60 min sur photo mensuelle. | SHOULD | Compatibilité fenêtre d'exploitation. |
| **BR-34** | **Robustesse** : chaque section encadrée par `BEGIN ... EXCEPTION WHEN OTHERS` afin qu'une erreur locale n'interrompe pas le rapport global. | MUST | Production de rapport même partiellement dégradé. |
| **BR-35** | **Log d'erreurs** en pied de rapport (codes, sections, horodatage). | MUST | Diagnostic rapide. |

### 3.5 Besoins de Risk & Compliance

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-40** | Détecter les **waivers** (remises) non conformes à la politique (hors seuils / hors grille / sans approbation). | MUST | Risque de pertes non maîtrisées et de fraude interne. |
| **BR-41** | Détecter les **comptes dormants** porteurs d'accruals non apurés ou de mouvements inhabituels. | MUST | Risque opérationnel et conformité. |
| **BR-42** | Identifier les **standing instructions** en échec ou expirées, et les SI de frais non exécutées. | MUST | Revenue leakage direct. |
| **BR-43** | Identifier les **crédits** avec échéances impayées, gelés, ou avec composantes en attente de liquidation. | MUST | Risque de crédit et manque à gagner sur pénalités / intérêts. |
| **BR-44** | Lister les **utilisateurs** à fort volume d'écritures manuelles ou d'annulations. | SHOULD | Piste d'audit SoD (*Segregation of Duties*). |

### 3.6 Besoins de la Direction Générale

| Id | Exigence | Priorité | Justification |
|---|---|---|---|
| **BR-50** | Disposer d'un **indicateur unique** agrégé d'exposition en LCY (somme des impacts estimés, bornés par un plafond de prudence). | SHOULD | Décision stratégique et arbitrage des chantiers correctifs. |
| **BR-51** | Connaître les **3 à 5 grandes causes racines** (root causes) les plus fréquentes. | SHOULD | Orientation des plans d'action. |

### 3.7 Matrice de traçabilité (extrait)

Chaque exigence métier doit être couverte par au moins une exigence fonctionnelle (§4) et/ou un contrôle (§7). Cette matrice sera maintenue dans la §4 une fois celle-ci rédigée.

| Exigence métier | Couverture prévue |
|---|---|
| BR-01, BR-04 | FR-10 (agrégation multidimensionnelle), §7 Audits 1-20 |
| BR-02 | §8 Executive Summary |
| BR-10, BR-11, BR-12, BR-13 | FR-30 (traçabilité), `bonnes_pratiques.md` §10 |
| BR-20, BR-21 | §9 Mapping PCEC |
| BR-30 à BR-35 | §5 Exigences non-fonctionnelles |
| BR-40 à BR-44 | §7 Catalogue de contrôles |

### 3.8 Critères d'acceptation métier

L'ouvrage est réputé **acceptable métier** si :
1. Tous les `MUST` de la §3 sont couverts par au moins un `FR` et un contrôle.
2. Un run `FULL` sur une photo mensuelle produit un rapport **lisible de bout en bout** (pas d'interruption, pas de sortie tronquée).
3. L'Executive Summary tient en ≤ 60 lignes.
4. 100 % des sections citent leur rattachement PCEC.
5. Un reviewer indépendant peut **ré-exécuter** n'importe quel `[F-NNN]` à partir des requêtes d'appui documentées.

---

## 4. Exigences fonctionnelles (Functional Requirements)

Les exigences fonctionnelles décrivent **ce que le script doit faire** pour satisfaire les besoins métier du §3. Elles seront déclinées en contrôles opérationnels au §7, et en paramètres au §6.

### 4.1 Vue d'ensemble des capacités

Le script DOIT offrir les capacités suivantes, dans cet ordre d'exécution logique :

1. **Initialisation** — lecture des paramètres, calcul du périmètre effectif, horodatage, ouverture du rapport.
2. **Vérification d'environnement** — version Oracle, droits, présence des tables critiques, métadonnées de la photo comptable.
3. **Calcul des indicateurs transverses** (KPIs) — totaux balance, volumes, nombre de comptes, couverture PCEC.
4. **Exécution des audits thématiques** — une section par thème (20+ thèmes, cf. §7), chacune encadrée, horodatée, chiffrée.
5. **Agrégation et synthèse** — Executive Summary, top-N par dimension, indicateur agrégé (BR-50).
6. **Rendu final** — pied de rapport, journal d'erreurs, limitations connues, versioning.

### 4.2 FR — Initialisation et cadrage

| Id | Exigence | Couvre |
|---|---|---|
| **FR-01** | Déclarer en tête du script **tous les paramètres optionnels** (cf. §6) avec valeurs par défaut `NULL` sauf exceptions documentées. | BR-32 |
| **FR-02** | Calculer un **périmètre effectif** : `v_date_from_eff := NVL(p_date_from, TRUNC(ADD_MONTHS(SYSDATE,-1),'MM'))` ; `v_date_to_eff := NVL(p_date_to, SYSDATE)`. | BR-32 |
| **FR-03** | Produire un **bloc d'écho des paramètres** en début de rapport (valeurs appliquées, y compris valeurs par défaut calculées). | BR-12 |
| **FR-04** | Initialiser une **constante de version** `C_SCRIPT_VERSION` et un identifiant de run `v_run_id` (ex. `TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS')`). | BR-12 |
| **FR-05** | Ouvrir le rapport avec une **bannière** (nom du script, version, date d'exécution, utilisateur `USER`, instance `SYS_CONTEXT('USERENV','INSTANCE_NAME')`). | BR-12 |

### 4.3 FR — Vérification d'environnement

| Id | Exigence | Couvre |
|---|---|---|
| **FR-06** | Détecter la version Oracle (`v$version` / `product_component_version`) et consigner un **warning** si < 11gR2. | BR-30 |
| **FR-07** | Vérifier l'existence des tables critiques (liste blanche) via `ALL_TABLES` ; continuer avec un warning si une table n'est pas présente, sans interrompre le run. | BR-34 |
| **FR-08** | Afficher le **nombre de lignes estimé** (`NUM_ROWS` ALL_TABLES) des tables principales pour dimensionner la photo. | BR-33 |
| **FR-09** | Déterminer la **date métier de la photo** (`STTB_CURRENT_BUSINESS_DATE` si disponible, sinon `MAX(TRN_DT)` de `ACTB_HISTORY`) et la consigner. | BR-12 |

### 4.4 FR — Calculs transverses (KPIs globaux)

| Id | Exigence | Couvre |
|---|---|---|
| **FR-10** | Pour chaque thème auditable, pouvoir **agréger** les résultats selon les dimensions : agence, produit, devise, segment client, classe PCEC, tranche d'ancienneté. | BR-01, BR-04 |
| **FR-11** | Calculer un **total d'exposition LCY** borné (cf. BR-50) en sommant les impacts estimés, après déduplication logique (un même compte compté une fois par type de fuite). | BR-50 |
| **FR-12** | Calculer les **volumétries de référence** : nombre de comptes actifs, nombre de contrats CL/LD actifs, nombre de SI actives, nombre d'écritures sur période, nombre de GL. | BR-04 |
| **FR-13** | Calculer le **taux de couverture PCEC** : % de GL rattachés à une rubrique PCEC identifiable. | BR-20, BR-21 |

### 4.5 FR — Exécution des audits thématiques

| Id | Exigence | Couvre |
|---|---|---|
| **FR-20** | Chaque thème (§7) DOIT être implémenté dans un **bloc PL/SQL encadré** : `BEGIN ... EXCEPTION WHEN OTHERS THEN log_error(...) END;`. | BR-34, BR-35 |
| **FR-21** | Chaque thème DOIT imprimer un **en-tête normé** (id de section, titre, objectif, classe PCEC, période effective). | BR-13 |
| **FR-22** | Chaque constat émis DOIT être matérialisé par un appel au helper `print_finding(p_id, p_severity, p_title, p_count, p_impact_lcy, p_recommendation, p_pcec)`. | BR-13, BR-20 |
| **FR-23** | Chaque thème DOIT exposer un **mini résumé** en fin de section : nombre de findings, total impact LCY, top 3 dimensions. | BR-01, BR-02 |
| **FR-24** | Les requêtes de détail doivent être **bornées** par `ROWNUM <= p_top_n` (défaut 50) pour éviter les sorties géantes. | BR-33 |
| **FR-25** | Les montants doivent être affichés avec **séparateur de milliers** et avec la devise (`FM999G999G999G990D00`). | BR-13 |

### 4.6 FR — Synthèse et agrégation

| Id | Exigence | Couvre |
|---|---|---|
| **FR-30** | Produire un **Executive Summary** listant, par ordre décroissant d'impact, les findings de sévérité `CRITICAL` et `HIGH` (jusqu'à 20 max). | BR-02 |
| **FR-31** | Produire un **Top-N par dimension** (agence, produit, client) en mode `DEEP` uniquement. | BR-01 |
| **FR-32** | Produire une **matrice sévérité × classe PCEC** : nombre de findings et total impact par cellule. | BR-20 |
| **FR-33** | Produire une ligne **Total RA Exposure (LCY, capped)** conforme à BR-50. | BR-50 |
| **FR-34** | Produire une section **Root Causes Top 5** : agrégation libre des causes les plus fréquentes sur l'ensemble des findings. | BR-51 |

### 4.7 FR — Traçabilité, sécurité, clôture

| Id | Exigence | Couvre |
|---|---|---|
| **FR-40** | **Refuser** toute exécution en mode écriture : le script DOIT être un bloc anonyme sans DML/DDL. Toute requête doit être un SELECT. | BR-11 |
| **FR-41** | Tenir un **journal `[LOG]`** séparé du rapport (INFO/WARN/ERROR) horodaté. | BR-35 |
| **FR-42** | Tenir un **journal `[PERF]`** optionnel mesurant la durée de chaque section (`DBMS_UTILITY.GET_TIME`). | BR-33 |
| **FR-43** | Clôturer par une section **KNOWN LIMITATIONS** listant toute section dégradée ou inexécutable. | BR-14 |
| **FR-44** | Clôturer par un **pied de page** répétant l'identifiant de run, la version et un hash simple (ex. `DBMS_UTILITY.GET_HASH_VALUE` sur la bannière) pour détecter l'altération. | BR-12 |

### 4.8 FR — Extensibilité

| Id | Exigence | Couvre |
|---|---|---|
| **FR-50** | L'ajout d'un nouveau thème DOIT se faire par insertion d'un bloc structuré (en-tête + body + résumé) sans refonte du script. | BR-30 |
| **FR-51** | Les seuils de matérialité DOIVENT être **centralisés** en tête (un paramètre par type d'impact au maximum). | BR-32 |
| **FR-52** | Les libellés (textes, titres, severity labels) DOIVENT être **en anglais** dans le rapport ; les commentaires internes peuvent être en français. | §7 et §8 |

### 4.9 Interactions avec l'utilisateur

Le script n'est **pas interactif** : il ne consomme aucune entrée utilisateur à l'exécution. Toute entrée se fait via :
- les **variables PL/SQL** déclarées en tête (édition directe du script) ;
- OU des variables de **session SQL\*Plus** (`DEFINE`, `&var`) si l'environnement le supporte (optionnel).

### 4.10 Sorties

Le script produit **une sortie unique** via `DBMS_OUTPUT.PUT_LINE`. L'appelant redirige vers un fichier (`spool`) :
```
SPOOL reports/revenue_assurance_<RUN_ID>.txt
@revenue_assurance_and_accounting_audit.sql
SPOOL OFF
```
Le nommage conseillé du fichier de sortie est `revenue_assurance_<YYYYMMDD>_<HH24MISS>.txt` pour faciliter l'archivage et la comparaison.

### 4.11 Matrice BR ↔ FR (synthèse)

| Business Req | Functional Reqs associées |
|---|---|
| BR-01 | FR-10, FR-23, FR-31 |
| BR-02 | FR-30 |
| BR-04 | FR-10, FR-12, FR-23 |
| BR-10 à BR-14 | FR-04, FR-05, FR-20 à FR-22, FR-40 à FR-44 |
| BR-20, BR-21 | FR-13, FR-21, FR-32 |
| BR-30 à BR-35 | FR-06 à FR-09, FR-20, FR-34, FR-41, FR-42 |
| BR-32 | FR-01 à FR-03, FR-51 |
| BR-33 | FR-08, FR-24, FR-42 |
| BR-50 | FR-11, FR-33 |
| BR-51 | FR-34 |

---

## 5. Exigences non-fonctionnelles (NFR)

Les exigences non-fonctionnelles décrivent **comment** le script doit se comporter (performance, robustesse, sécurité, maintenabilité, portabilité) indépendamment des fonctions qu'il réalise.

### 5.1 Performance et scalabilité

| Id | Exigence | Cible | Mesure |
|---|---|---|---|
| **NFR-01** | Temps d'exécution — mode `SUMMARY` | < **2 minutes** | Photo mensuelle standard (volumétries `fcubs.csv`). |
| **NFR-02** | Temps d'exécution — mode `FULL` | < **15 minutes** | Photo mensuelle standard. |
| **NFR-03** | Temps d'exécution — mode `DEEP` | < **60 minutes** | Photo mensuelle standard. |
| **NFR-04** | Consommation mémoire PL/SQL | < **100 Mo** par session | Pas d'accumulation de collections massives. |
| **NFR-05** | Buffer `DBMS_OUTPUT` | **ILLIMITÉ** | `SET SERVEROUTPUT ON SIZE UNLIMITED`. |
| **NFR-06** | Pas de boucle **N+1** (une requête par ligne) | 0 | Toute extraction TOP-N fait une seule requête agrégée. |
| **NFR-07** | Filtrage précoce par période | 100 % des sections temporelles | Aucune lecture full-scan non bornée. |
| **NFR-08** | Volumétrie de sortie (rapport texte) | < **20 Mo** en `FULL`, < 80 Mo en `DEEP` | Borne par `p_top_n`. |

> En cas de dépassement, le script DOIT **tronquer** proprement la section concernée et émettre un warning `[LOG]`, plutôt que d'échouer silencieusement.

### 5.2 Robustesse et disponibilité

| Id | Exigence |
|---|---|
| **NFR-10** | Aucune erreur non interceptée : chaque section est encadrée par `BEGIN ... EXCEPTION WHEN OTHERS ... END;`. |
| **NFR-11** | Une erreur dans une section **n'interrompt pas** le rapport global : la section est marquée `SKIPPED — see error log` et les suivantes s'exécutent. |
| **NFR-12** | Reprise après interruption : le script étant idempotent et sans état persistant, un simple re-run suffit. |
| **NFR-13** | Défensivité des conversions : tout `NVL` sur colonne numérique/date utilise `TO_CHAR`, toute division utilise `NULLIF`, toute somme est enveloppée `NVL(SUM(...),0)`. |

### 5.3 Sécurité et conformité technique

| Id | Exigence |
|---|---|
| **NFR-20** | **Lecture seule stricte** : aucun `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `TRUNCATE`, `DROP`, `ALTER`, `CREATE`, `GRANT`, `REVOKE`, `COMMIT`, `ROLLBACK`, `SAVEPOINT` dans le script. |
| **NFR-21** | Aucune **donnée personnelle sensible** (identifiants pièces, numéros complets) ne doit être affichée en clair au-delà de ce qui est nécessaire au constat ; les numéros de compte sont partiellement masqués en mode `SUMMARY`. |
| **NFR-22** | Le script ne crée **aucun objet persistant** : pas de `CREATE TABLE`, pas de `CREATE PROCEDURE`, pas de fichier écrit via `UTL_FILE` (sauf demande explicite documentée). |
| **NFR-23** | Pas d'appel à `DBMS_EXECUTE_IMMEDIATE`, `DBMS_SQL`, ni aucun package permettant l'exécution dynamique arbitraire. Exception admise : `DBMS_UTILITY.GET_TIME`, `DBMS_UTILITY.GET_HASH_VALUE`, `DBMS_OUTPUT`. |
| **NFR-24** | Compte d'exécution doté uniquement de `SELECT ANY TABLE` ou de `SELECT` granulaires sur les schémas FCUBS concernés. |

### 5.4 Portabilité et compatibilité

| Id | Exigence |
|---|---|
| **NFR-30** | Exécutable en **Oracle 11gR2** minimum, compatible 12c/19c/21c sans modification. |
| **NFR-31** | Syntaxe proscrite : `FETCH FIRST N ROWS`, `WITHIN GROUP (ORDER BY)` postérieures à 11g, `JSON_OBJECT`, *PIVOT* moderne, *IDENTITY columns*, *Invisible columns*. |
| **NFR-32** | ANSI JOIN **obligatoire** (pas de jointures `table1, table2 WHERE ...`). |
| **NFR-33** | Compatible SQL\*Plus et SQLcl ; testé sur SQL Developer (exécution interactive). |
| **NFR-34** | Encodage fichier : **UTF-8 sans BOM** ; pas de caractères latin-1 dépendant de l'environnement serveur. |

### 5.5 Maintenabilité et lisibilité

| Id | Exigence |
|---|---|
| **NFR-40** | Chaque section du script ≤ **300 lignes** ; au-delà, sous-sectionner. |
| **NFR-41** | Nommage : variables `v_`, paramètres `p_`, constantes `C_`, curseurs `cur_`. |
| **NFR-42** | Commentaires en **français** dans le code, libellés du rapport en **anglais**. |
| **NFR-43** | Format : indentation 4 espaces, pas de tabulations ; lignes ≤ 200 caractères. |
| **NFR-44** | Helpers réutilisés : `print_kv`, `safe_count`, `print_finding`, `log_error`, `print_section_header`, `print_section_footer`, déclarés une seule fois en tête. |
| **NFR-45** | Le script DOIT passer une **compilation à blanc** (`SET AUTOPRINT OFF` + compile implicite du bloc anonyme) sans warning autre que `PLW-*` mineurs documentés. |

### 5.6 Traçabilité et auditabilité

| Id | Exigence |
|---|---|
| **NFR-50** | Horodatage en tête et en pied du rapport au format `YYYY-MM-DD HH24:MI:SS TZR`. |
| **NFR-51** | Versioning : `C_SCRIPT_VERSION` mis à jour à chaque livraison, suivant le schéma `MAJOR.MINOR.PATCH`. |
| **NFR-52** | Archivage du rapport : convention de nommage `revenue_assurance_<YYYYMMDD>_<HH24MISS>.txt`, répertoire `reports/` (hors Git). |
| **NFR-53** | Les logs `[LOG]` et `[PERF]` DOIVENT être en fin de rapport, séparés du corps, pour extraction automatique possible. |

### 5.7 Internationalisation (I18N)

| Id | Exigence |
|---|---|
| **NFR-60** | Rapport en **anglais** uniquement (BR-02). Pas de localisation multi-langue dans cette version. |
| **NFR-61** | Formats date ISO (`YYYY-MM-DD`), séparateur de décimales `.` (point), séparateur de milliers `,` (virgule) dans le rapport. |
| **NFR-62** | Les devises sont explicitées par leur code ISO 4217 (ex. `XAF`, `USD`, `EUR`). Les montants LCY sont étiquetés « LCY (<ISO>) » lorsque la devise locale est connue. |

### 5.8 Configuration et exploitation

| Id | Exigence |
|---|---|
| **NFR-70** | Pré-requis d'exécution documentés en tête du script (version Oracle, commandes SQL\*Plus recommandées, droits requis). |
| **NFR-71** | Le script DOIT être utilisable tel quel sans variable d'environnement autre que celles liées au compte Oracle (TNS). |
| **NFR-72** | Le SPOOL conseillé est documenté dans un bloc `-- HOW TO RUN` en tête du fichier. |

### 5.9 Dépendances externes

| Id | Exigence |
|---|---|
| **NFR-80** | Aucune dépendance à un package PL/SQL applicatif FCUBS non standard (Flexcube Open Development Toolkit, etc.). |
| **NFR-81** | Seules dépendances admises : dictionnaire Oracle (`ALL_*`, `USER_*`, `V$*`), `DBMS_OUTPUT`, `DBMS_UTILITY`. |

### 5.10 Tests et qualité (cadrage ; détail en §11)

| Id | Exigence |
|---|---|
| **NFR-90** | Un jeu de tests minimal : exécution à vide (périmètre nul), sur une agence, sur une période courte (1 jour), sur une période longue (1 mois), avec seuils restrictifs. |
| **NFR-91** | Vérification de la **reproductibilité** : deux runs successifs sans changement de données doivent produire des rapports identiques à l'horodatage près. |
| **NFR-92** | Tous les constats `CRITICAL`/`HIGH` d'un run de référence DOIVENT être ré-obtenus sur un run suivant, sauf changement documenté. |

### 5.11 Synthèse des cibles chiffrées

| Dimension | Cible | Seuil d'alerte |
|---|---|---|
| Durée `SUMMARY` | < 2 min | > 5 min |
| Durée `FULL` | < 15 min | > 30 min |
| Durée `DEEP` | < 60 min | > 120 min |
| Taille rapport `FULL` | < 20 Mo | > 50 Mo |
| Nb findings affichés | selon `p_top_n` (défaut 50) | > 500 par section |
| Taux couverture PCEC | ≥ 95 % | < 80 % |
| Taux d'erreurs interceptées | 100 % | toute exception non catch = bug |

---

## 6. Paramétrage et interfaces

Le script DOIT être **paramétrable** mais **utilisable sans paramètre** (tous optionnels). L'utilisateur édite les valeurs en tête du bloc, sans toucher au corps.

### 6.1 Principe général

- Chaque paramètre est déclaré comme **variable PL/SQL** en tête du bloc avec une **valeur par défaut** (le plus souvent `NULL`).
- `NULL` ⇒ **pas de filtrage** sur la dimension correspondante (inclusion totale).
- Le pattern SQL générique est : `AND (p_xxx IS NULL OR colonne = p_xxx)` pour conserver la planification d'index quand la valeur est `NULL`.
- Pour une liste, on utilise un type `SYS.ODCIVARCHAR2LIST` (ou équivalent) rempli en tête : `AND (p_list IS NULL OR colonne IN (SELECT column_value FROM TABLE(p_list)))`.

### 6.2 Catalogue des paramètres standard

#### 6.2.1 Périmètre temporel

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_date_from` | `DATE` | `NULL` | Borne inférieure de la période auditée (inclusive). Par défaut, début du mois précédent si `NULL` et utilisé dans un thème temporel. |
| `p_date_to` | `DATE` | `NULL` | Borne supérieure (inclusive). Par défaut, date métier courante. |
| `p_as_of_date` | `DATE` | `NULL` | Date de photo pour les soldes (défaut : `SYSDATE`). |

#### 6.2.2 Périmètre géographique / organisationnel

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_branch_code` | `VARCHAR2` | `NULL` | Agence unique. |
| `p_branch_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste d'agences. Si renseignée, prime sur `p_branch_code`. |
| `p_department` | `VARCHAR2` | `NULL` | Département / région bancaire (si taxonomie interne). |

#### 6.2.3 Périmètre client / compte

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_customer_no` | `VARCHAR2` | `NULL` | Client unique. |
| `p_customer_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste de clients. |
| `p_account_no` | `VARCHAR2` | `NULL` | Compte unique. |
| `p_account_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste de comptes. |
| `p_customer_segment` | `VARCHAR2` | `NULL` | Segment (CORPORATE, SME, RETAIL, etc.). |

#### 6.2.4 Produits et contrats

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_module` | `VARCHAR2` | `NULL` | Module à restreindre (CL, LD, SI, IC, MO, FT, FX, GL). |
| `p_product_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Codes produits concernés. |
| `p_account_class_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Classes de compte (CASA, OD, LOAN, etc.). |

#### 6.2.5 Devises

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_ccy` | `VARCHAR2` | `NULL` | Devise unique (ISO 4217). |
| `p_ccy_list` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste de devises. |
| `p_include_fcy_only` | `CHAR(1)` | `'N'` | Si `'Y'`, n'inclure que les comptes FCY. |

#### 6.2.6 Seuils de matérialité

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_materiality_lcy` | `NUMBER` | `100000` | Seuil global de matérialité en LCY ; tout montant absolu en deçà est relégué en `INFO`. |
| `p_materiality_impact_lcy` | `NUMBER` | `1000000` | Seuil au-dessus duquel un constat est automatiquement `HIGH` au minimum. |
| `p_materiality_critical_lcy` | `NUMBER` | `10000000` | Seuil au-dessus duquel un constat est `CRITICAL`. |
| `p_min_days_overdue` | `NUMBER` | `30` | Ancienneté minimale pour qualifier un impayé / overdue. |
| `p_min_days_dormant` | `NUMBER` | `180` | Ancienneté minimale pour qualifier un compte dormant. |

#### 6.2.7 Mode d'exécution et verbosité

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_mode` | `VARCHAR2` | `'FULL'` | `SUMMARY`, `FULL` ou `DEEP`. |
| `p_top_n` | `NUMBER` | `50` | Nombre de lignes max par extraction TOP-N. |
| `p_verbose` | `CHAR(1)` | `'N'` | Si `'Y'`, ajoute les requêtes d'appui en pied de section. |
| `p_include_perf_log` | `CHAR(1)` | `'Y'` | Inclut le bloc `[PERF]` en fin de rapport. |
| `p_mask_pii` | `CHAR(1)` | `'Y'` | Masquage partiel des numéros de comptes / clients. |
| `p_language` | `VARCHAR2` | `'EN'` | Langue du rapport (verrouillé à `EN` dans v1, cf. NFR-60). |

#### 6.2.8 Contrôle des thèmes

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_sections_include` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste blanche d'identifiants de sections à exécuter (ex. `{'S01','S05'}`). |
| `p_sections_exclude` | `SYS.ODCIVARCHAR2LIST` | `NULL` | Liste noire de sections à ignorer. Priorité sur `p_sections_include`. |

### 6.3 Bloc d'écho des paramètres (exigence FR-03)

Le rapport DOIT rappeler, dans les 30 premières lignes, **toutes** les valeurs appliquées (y compris les défauts calculés). Exemple de rendu attendu :

```
===============================================================================
 REVENUE ASSURANCE & ACCOUNTING AUDIT — PARAMETERS IN EFFECT
===============================================================================
 Date from .............. 2026-03-01
 Date to ................ 2026-03-31
 As-of date ............. 2026-04-17
 Branch(es) ............. (ALL)
 Customer(s) ............ (ALL)
 Account(s) ............. (ALL)
 Module ................. (ALL)
 Currency(ies) .......... (ALL)
 Materiality (LCY) ...... 100,000
 Mode ................... FULL
 Top-N .................. 50
 Mask PII ............... Y
 Language ............... EN
-------------------------------------------------------------------------------
 Sections include ....... (ALL)
 Sections exclude ....... (NONE)
===============================================================================
```

### 6.4 Règles de validation des paramètres

| Règle | Effet si violée |
|---|---|
| `p_date_from <= p_date_to` (si les deux renseignés) | Erreur FATAL, arrêt du script avec `ORA-20001`. |
| `p_mode IN ('SUMMARY','FULL','DEEP')` | Erreur FATAL, `ORA-20002`. |
| `p_top_n BETWEEN 1 AND 1000` | Valeur écrêtée + warning. |
| `p_materiality_* >= 0` | Valeur écrêtée à 0 + warning. |
| `p_language = 'EN'` | Autres valeurs refusées (v1), warning. |
| `p_sections_include` et `p_sections_exclude` cohérents | Si une section est dans les deux, elle est **exclue** (priorité sûreté). |

### 6.5 Interfaces d'entrée

| Interface | Description |
|---|---|
| **Variables PL/SQL de tête** | Interface unique et obligatoire (édition directe du script). |
| **SQL\*Plus `DEFINE`** | Optionnel : substitution `&p_xxx` possible mais **non requise**. À documenter uniquement si utilisée. |
| **Fichier externe de configuration** | NON supporté en v1 (reporté). |

### 6.6 Interfaces de sortie

| Interface | Description |
|---|---|
| **`DBMS_OUTPUT.PUT_LINE`** | Canal principal du rapport. |
| **SPOOL SQL\*Plus** | Redirection recommandée vers `reports/revenue_assurance_<RUN_ID>.txt`. |
| **Table de persistance** | NON supportée en v1 ; pourra être ajoutée en v2 (table de findings). |

### 6.7 Compatibilité avec l'exploration existante

Les paramètres déclarés DOIVENT être **cohérents** avec les hypothèses prises par `explore_revenue_assurance.sql` afin de permettre une **comparaison** exploration/audit sur le même périmètre. Toute divergence de convention DOIT être explicitée en §10.

### 6.8 Extensibilité du paramétrage

Tout nouveau paramètre ajouté en v1.x DOIT :
1. Conserver une **valeur par défaut rétro-compatible** (ne pas modifier le comportement d'un run déjà validé) ;
2. Être déclaré dans le bloc d'écho (§6.3) ;
3. Être documenté dans `bonnes_pratiques.md` §2 ;
4. Incrémenter `C_SCRIPT_VERSION` en `MINOR`.

---

## 7. Catalogue détaillé des contrôles

Chaque contrôle ci-dessous correspond à **une section** du script final. Un contrôle peut produire **plusieurs constats** (`[F-NNN]`), chacun avec sa sévérité et son impact. Cinq familles sont distinguées :

- **A — Revenue Assurance : comptes & découverts** (§7.A, sections S01–S05)
- **B — Revenue Assurance : crédits CL / LD** (§7.B, sections S06–S10)
- **C — Revenue Assurance : SI, IC, commissions, frais** (§7.C, sections S11–S15)
- **D — Contrôle comptable : GL, écritures manuelles, FX, suspense** (§7.D, sections S16–S20)
- **E — Contrôle interne & SoD** (§7.E, sections S21–S23)

### 7.0 Grille de description (applicable à chaque contrôle)

Chaque contrôle est décrit par :
- **ID** : identifiant de section (`S01`…`S23`) et identifiants de findings `[F-NNN]`.
- **Titre** — libellé court en anglais (utilisé dans le rapport).
- **Objectif** — ce que le contrôle détecte et pourquoi.
- **Sources FCUBS** — tables et colonnes.
- **Méthode** — logique métier et règle de qualification.
- **Sévérité par défaut** — ajustable par montant via les seuils `p_materiality_*`.
- **Impact monétaire estimé** — formule de chiffrage.
- **Dimensions d'agrégation** — agence, produit, client, devise, ancienneté.
- **Recommandation type** — action suggérée au management.
- **Rattachement PCEC** — classe(s) et, si possible, comptes divisionnaires.
- **Paramètres applicables** — liste des `p_*` qui influencent le contrôle.
- **Fondement exploration** — renvoi au(x) constat(s) du rapport d'exploration qui motive(nt) le contrôle.

### 7.A — Revenue Assurance : comptes et découverts

#### S01 — Unauthorized overdrafts without TOD limit

- **Findings** : `[F-001]` accounts with debit balance and no TOD limit ; `[F-002]` accounts in persistent overdraft beyond `p_min_days_overdue`.
- **Objectif** — Identifier les comptes en **solde débiteur** sans autorisation de découvert paramétrée, et a fortiori ceux en overdraft **persistant**, source de fuite d'intérêts débiteurs et de risque de crédit non facturé.
- **Sources** — `STTM_CUST_ACCOUNT` (`AC_STAT_DR_BAL`, `AC_STAT_CR_BAL`, `TOD_LIMIT`, `TOD_START_DATE`, `TOD_END_DATE`, `ACY_CURR_BALANCE`, `LCY_CURR_BALANCE`, `BRANCH_CODE`, `CUST_NO`, `CCY`), `GLTB_GL_BAL` pour contrôle de cohérence.
- **Méthode** — `ACY_CURR_BALANCE < 0` AND (`TOD_LIMIT` IS NULL OR `TOD_LIMIT` = 0 OR `SYSDATE` NOT BETWEEN `TOD_START_DATE` AND `TOD_END_DATE`).
- **Sévérité** — HIGH (par défaut) ; CRITICAL si nombre > 100 ou impact > `p_materiality_critical_lcy`.
- **Impact LCY** — `SUM(ABS(LCY_CURR_BALANCE)) × taux_interet_OD_standard × (jours_overdraft/365)`. Le taux OD standard est un paramètre dérivé ou, à défaut, consigné en hypothèse.
- **Dimensions** — agence, devise, segment client.
- **Recommandation** — Régulariser le paramétrage TOD ou facturer le découvert non autorisé ; alerter Commercial.
- **PCEC** — `PCEC/2` (Opérations avec la clientèle) — comptes 201/208 et correspondants produits d'intérêts en `PCEC/702`.
- **Paramètres** — `p_date_to`, `p_branch_*`, `p_account_*`, `p_min_days_overdue`, `p_materiality_*`.
- **Fondement exploration** — rapport d'exploration : **950 comptes** en overdraft sans TOD_LIMIT (section 14).

#### S02 — TOD limits overrun / expired without renewal

- **Findings** : `[F-010]` accounts where `ABS(debit balance) > TOD_LIMIT` ; `[F-011]` TOD expired (`TOD_END_DATE < SYSDATE`) while balance still debit.
- **Objectif** — Détecter les **dépassements** de limite de découvert et les **TOD périmées** encore utilisées.
- **Sources** — `STTM_CUST_ACCOUNT`.
- **Méthode** — Comparaison `ABS(ACY_CURR_BALANCE)` vs `TOD_LIMIT`, avec filtre `TOD_END_DATE < SYSDATE` pour `[F-011]`.
- **Sévérité** — HIGH, CRITICAL si dépassement > 200 % de la limite.
- **Impact LCY** — Surintérêts : `(solde − TOD_LIMIT) × (taux_penal − taux_OD) × jours/365`.
- **Dimensions** — agence, produit (account class), segment.
- **Recommandation** — Renouveler, écrêter ou facturer au taux pénal.
- **PCEC** — `PCEC/2` côté actif (`PCEC/201`), `PCEC/702` côté produits.
- **Paramètres** — `p_date_to`, `p_branch_*`, `p_materiality_*`.
- **Fondement exploration** — confirmé par volumétrie TOD_LIMIT de la section 8 du rapport.

#### S03 — Accounts dormant with accrued balances or unexpected activity

- **Findings** : `[F-020]` dormant accounts with non-zero accrued interest/charges ; `[F-021]` dormant accounts with movements on period.
- **Objectif** — Mettre en évidence les comptes dormants (`AC_STAT_DORMANT = 'Y'` ou équivalent) pour lesquels des **accruals** subsistent ou des **mouvements** ont été observés sur la période.
- **Sources** — `STTM_CUST_ACCOUNT` (`AC_STAT_DORMANT`, `DORMANT_SINCE` si présent), `ACTB_HISTORY` (mouvements période), `ICTB_ACCRUALS_TEMP` (accruals).
- **Méthode** — Compte dormant + existence d'un accrual non nul ou d'au moins une écriture `ACTB_HISTORY` sur `[p_date_from, p_date_to]`.
- **Sévérité** — MEDIUM par défaut, HIGH si mouvements clientèle sur compte dormant (suspicion AML/fraude — à référer au module dédié).
- **Impact LCY** — Pour `[F-020]` : `SUM(accrual_amount_lcy)`. Pour `[F-021]` : indicateur de risque, impact non chiffré.
- **Dimensions** — agence, type de mouvement, ancienneté dormance.
- **Recommandation** — Apurer accruals, reclasser le compte, vérifier authenticité des mouvements.
- **PCEC** — `PCEC/2` (clientèle), potentiellement `PCEC/38` (comptes de régularisation).
- **Paramètres** — `p_min_days_dormant`, `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — **179 comptes dormants** avec accruals (section 14).

#### S04 — Account charges waived beyond policy thresholds

- **Findings** : `[F-030]` recurring waivers on charge components ; `[F-031]` waivers without documented approver; `[F-032]` waiver concentration by user.
- **Objectif** — Quantifier l'impact des **remises** (waivers) appliquées aux frais de tenue de compte et commissions.
- **Sources** — `ICTB_LIQ_DETAILS` (composante `CHG_*`, colonne `WAIVER_AMOUNT` ou équivalent), `CHTB_*` si activé, `SMTB_USER` pour identifier l'utilisateur.
- **Méthode** — Somme des montants waivés par compte / utilisateur / période ; ratio `waived / (waived + collected)` ; top utilisateurs.
- **Sévérité** — MEDIUM, HIGH si ratio > 30 % ou concentration utilisateur > 50 % des waivers.
- **Impact LCY** — Somme waived LCY sur la période.
- **Dimensions** — agence, utilisateur, composante, produit.
- **Recommandation** — Revue SoD, revalidation politique de waivers, plafonds par grade.
- **PCEC** — `PCEC/7` — produits non perçus (classes 702/706 selon composante).
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — à confirmer via mini-script d'exploration (cf. §7.Z hypothèse à valider) sur les tables de composantes et champs WAIVE réellement présents.

#### S05 — Credit balances on accounts without interest accrual

- **Findings** : `[F-040]` high-balance CASA accounts with no interest accrual generated over period.
- **Objectif** — S'assurer que tout compte d'épargne / courant rémunéré génère effectivement ses accruals. Inversement, détecter des comptes non rémunérés qui devraient l'être selon le produit.
- **Sources** — `STTM_CUST_ACCOUNT` (account class), `ICTB_ACCRUALS_TEMP` (existence d'accruals), paramétrage produit `ICTM_PRODUCT_DEFINITION` si nécessaire.
- **Méthode** — Jointure `STTM_CUST_ACCOUNT LEFT JOIN ICTB_ACCRUALS_TEMP` sur période, filtre absence + solde créditeur > `p_materiality_lcy`.
- **Sévérité** — MEDIUM.
- **Impact LCY** — Estimatif, potentiel bénéfice client indûment non versé ou produit indûment reconnu.
- **Dimensions** — agence, classe de compte, devise.
- **Recommandation** — Vérifier mapping produit IC, lancer un run IC correctif si applicable.
- **PCEC** — `PCEC/2` (clientèle), `PCEC/6` (charges d'intérêts) et/ou `PCEC/7`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — à confirmer : sections IC du rapport indiquent la présence d'accruals mais pas leur complétude fonctionnelle.

---

> La suite du catalogue (§7.B à §7.E) est décrite ci-dessous.

### 7.B — Revenue Assurance : crédits CL et LD

#### S06 — Overdue loan schedules (CL) not yet recovered

- **Findings** : `[F-050]` overdue principal schedules ; `[F-051]` overdue interest schedules ; `[F-052]` overdue fee/charge schedules.
- **Objectif** — Identifier toutes les **échéances** CL restant dues au-delà de `p_min_days_overdue` et quantifier les **intérêts de retard / pénalités** non facturés.
- **Sources** — `CLTB_SCHEDULES_DETAILS` (`SCHEDULE_DUE_DATE`, `AMOUNT_DUE`, `AMOUNT_SETTLED`, `COMPONENT`, `ACCOUNT_NUMBER`), `CLTB_ACCOUNT_MASTER` (statut contrat), `CLTB_ACCOUNT_COMPONENTS` (paramétrage pénalités).
- **Méthode** — `SCHEDULE_DUE_DATE < p_as_of_date - p_min_days_overdue` AND `AMOUNT_DUE > NVL(AMOUNT_SETTLED,0)` ; regroupement par composante (`PRINCIPAL` / `MAIN_INT` / `PENAL_INT` / `FEE`).
- **Sévérité** — HIGH ; CRITICAL au-delà de 90 jours ou `p_materiality_critical_lcy`.
- **Impact LCY** — Somme des `AMOUNT_DUE - AMOUNT_SETTLED` par composante + estimation d'intérêts de retard non comptabilisés (`solde × taux_penal × jours_retard/365`).
- **Dimensions** — agence, produit CL (LDTM_PRODUCT_MASTER), segment client, tranches d'ancienneté (30/60/90/>90).
- **Recommandation** — Relance / provisionnement / activation du module de pénalités.
- **PCEC** — `PCEC/2` (clientèle), `PCEC/29` (créances douteuses / impayées), `PCEC/702` (intérêts perçus).
- **Paramètres** — `p_min_days_overdue`, `p_date_from`, `p_date_to`, `p_branch_*`, `p_product_list`.
- **Fondement exploration** — **1 620 échéances** en retard (section 14 du rapport).

#### S07 — Frozen / on-hold loans with outstanding balance

- **Findings** : `[F-060]` frozen CL loans (`USER_DEFINED_STATUS` / `FROZEN` flag) carrying outstanding principal ; `[F-061]` accruals still running on frozen contracts.
- **Objectif** — Détecter les crédits **gelés** (frozen) qui conservent un solde restant dû et, pire, sur lesquels des accruals continuent à être comptabilisés.
- **Sources** — `CLTB_ACCOUNT_MASTER` (`USER_DEFINED_STATUS`, colonnes de statut technique), `CLTB_ACCOUNT_COMPONENTS` (component balances), `ICTB_ACCRUALS_TEMP`.
- **Méthode** — Filtre statut gelé + solde principal ≠ 0 + éventuelle existence d'accruals sur la période.
- **Sévérité** — HIGH. CRITICAL si accruals toujours en cours (risque comptable).
- **Impact LCY** — Solde gelé + accruals indûment comptabilisés.
- **Dimensions** — agence, produit, ancienneté du gel.
- **Recommandation** — Arrêter les accruals, statuer sur reprise ou provision intégrale.
- **PCEC** — `PCEC/29` (douteux/litigieux), `PCEC/70`/`PCEC/60` pour les accruals inappropriés.
- **Paramètres** — `p_date_to`, `p_branch_*`, `p_materiality_*`.
- **Fondement exploration** — **662 prêts CL gelés** (section 14).

#### S08 — Loan components pending liquidation

- **Findings** : `[F-070]` CL components with amount due and no matching `CLTB_LIQ` row within expected window ; `[F-071]` components with rejected liquidation.
- **Objectif** — Vérifier que toutes les **composantes** liquidables (intérêts dus, frais, principal) ont bien été **liquidées** et que les échecs sont traités.
- **Sources** — `CLTB_ACCOUNT_COMPONENTS`, `CLTB_LIQ` (`VALUE_DATE`, `LIQ_AMOUNT`, `LIQ_STATUS`/`AUTH_STAT`).
- **Méthode** — `LEFT JOIN` CL composantes vs `CLTB_LIQ` sur contrat + composante + date, détection d'absence et de rejets.
- **Sévérité** — MEDIUM ; HIGH si impact > `p_materiality_impact_lcy`.
- **Impact LCY** — Somme des `AMOUNT_DUE` non liquidés.
- **Dimensions** — agence, composante, produit.
- **Recommandation** — Relancer liquidation batch / déboguer le paramétrage IC.
- **PCEC** — `PCEC/2`, `PCEC/702`, `PCEC/706`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — section CL indique des composantes actives ; à confirmer sur la colonne de statut exacte.

#### S09 — Interbank / corporate loans (LD) — rate and schedule anomalies

- **Findings** : `[F-080]` LD contracts with next schedule date passed ; `[F-081]` LD contracts with interest rate deviating from product range ; `[F-082]` LD expired but still active.
- **Objectif** — Contrôler la bonne tenue du portefeuille **LD** (prêts/dépôts interbancaires, grands comptes) : échéances manquées, taux hors grille, contrats expirés non clôturés.
- **Sources** — `LDTB_CONTRACT_MASTER` (`VALUE_DATE`, `MATURITY_DATE`, `PRODUCT`, `INT_RATE`/`FIXED_RATE`), `LDTM_PRODUCT_MASTER` (`PRODUCT`, paramétrage), `LDTB_SCHEDULES`.
- **Méthode** — Comparaisons de dates vs `p_as_of_date` ; bornes de taux via paramétrage produit (ou seuils empiriques si paramétrage indisponible).
- **Sévérité** — HIGH (taux anormal), MEDIUM (échéance manquée isolée).
- **Impact LCY** — Écart de taux × notional × durée restante ; intérêts non courus.
- **Dimensions** — produit, contrepartie, devise.
- **Recommandation** — Corriger paramétrage, reclasser ou clôturer.
- **PCEC** — `PCEC/1` (trésorerie / EC) si interbancaire, `PCEC/2` si clientèle corporate, `PCEC/70`/`PCEC/60` pour les intérêts.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_product_list`, `p_materiality_*`.
- **Fondement exploration** — sections LD et LDTM dans le rapport (présence vérifiée des tables et colonnes).

#### S10 — Loan component waivers and manual rate overrides

- **Findings** : `[F-090]` loan components with `WAIVE='Y'` on interest/fee ; `[F-091]` user-defined interest rates below product minimum.
- **Objectif** — Quantifier les **renonciations** (waivers) et **remises de taux** appliquées aux crédits, par utilisateur et par contrepartie.
- **Sources** — `CLTB_ACCOUNT_COMPONENTS` (`WAIVE`, `USER_DEFINED_SPREAD` si présent), `CLTB_ACCOUNT_MASTER`, `SMTB_USER`.
- **Méthode** — Filtre `WAIVE='Y'` + extraction top utilisateurs / top contreparties ; détection taux < seuil produit.
- **Sévérité** — MEDIUM, HIGH si récurrent par utilisateur ou impact > `p_materiality_impact_lcy`.
- **Impact LCY** — Somme estimée des intérêts/frais non perçus (`notional × spread_waive × durée`).
- **Dimensions** — utilisateur, produit, client.
- **Recommandation** — Revue politique crédit, contrôle SoD, plafonds de waiver par grade.
- **PCEC** — `PCEC/7` produits non perçus, `PCEC/702` / `PCEC/706`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — colonne `WAIVE` confirmée sur `CLTB_ACCOUNT_COMPONENTS` (correction d'erreur passée lors du debug).

---

### 7.C — Revenue Assurance : SI, IC, commissions et frais

#### S11 — Standing Instructions without `APPLY_CHG_*` flags set

- **Findings** : `[F-100]` SI contracts without `APPLY_CHG_FLAG`/`APPLY_CHG_ON_REJECT`/`APPLY_CHG_ON_LIQ` properly set ; `[F-101]` SI products configured to apply charges but executions not generating any charge event.
- **Objectif** — S'assurer que toutes les SI qui **devraient** facturer des frais (en exécution ou en cas de rejet) sont bien paramétrées pour le faire.
- **Sources** — `SITB_CONTRACTS` (`APPLY_CHG_FLAG`, `APPLY_CHG_REJT`, `APPLY_CHG_ON_LIQ`, `PROD_CODE`, `EXEC_STATUS`), `SITB_EXEC_LOG`.
- **Méthode** — Filtres sur flags NULL / `'N'` ; jointure aux logs d'exécution pour confirmer l'absence d'événement de charge.
- **Sévérité** — HIGH si volume significatif, MEDIUM sinon.
- **Impact LCY** — `nb_exécutions × frais_standard_par_SI` (frais par défaut à paramétrer en hypothèse ou par produit).
- **Dimensions** — agence, produit SI, contrepartie.
- **Recommandation** — Activer les flags, régulariser par facturation rétroactive si politique le permet.
- **PCEC** — `PCEC/702` / `PCEC/706` (commissions / frais).
- **Paramètres** — `p_date_from`, `p_date_to`, `p_branch_*`, `p_product_list`.
- **Fondement exploration** — **51 SI sans APPLY_CHG_\*** + **782 SI en échec avec `APPLY_CHG_REJT='N'`** (section 14).

#### S12 — Expired or stalled Standing Instructions

- **Findings** : `[F-110]` SI contracts with `LAST_EXEC_DATE < p_as_of_date - N days` while still active ; `[F-111]` SI with `EXEC_STATUS` in failure state over period ; `[F-112]` SI with `END_DATE < p_as_of_date` still active.
- **Objectif** — Mettre en évidence les SI dormantes ou en échec répété, source de perte de commissions et de risque client.
- **Sources** — `SITB_CONTRACTS`, `SITB_EXEC_LOG`.
- **Méthode** — Comparaison dates + comptage des échecs par SI sur la période.
- **Sévérité** — MEDIUM, HIGH si SI génère des frais potentiels > `p_materiality_impact_lcy`.
- **Impact LCY** — Frais non perçus + risque d'avoir à justifier auprès du client final.
- **Dimensions** — agence, produit, ancienneté du dernier échec.
- **Recommandation** — Relance client / reparamétrage / clôture propre.
- **PCEC** — `PCEC/702` / `PCEC/706`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_*`.
- **Fondement exploration** — **281 SI expirées** (section 14).

#### S13 — Charges posted but unlinked to expected account / product

- **Findings** : `[F-120]` charge transactions without a corresponding product-rule match ; `[F-121]` charges with `CHARGE_AMT = 0` on products that should charge.
- **Objectif** — Détecter les commissions **paramétrées mais non perçues** (ligne créée avec montant 0) ou **comptabilisées sans règle** (écart de paramétrage produit).
- **Sources** — `CHTB_CONTRACT_MASTER` (si module CH utilisé), `ACTB_HISTORY` filtré par `TRN_CODE` de charge, paramétrage produit IC/CH.
- **Méthode** — Jointure comptable ↔ paramétrage produit ; détection de montants nuls inattendus.
- **Sévérité** — MEDIUM, HIGH si concentration sur un produit.
- **Impact LCY** — Estimation sur base tarif officiel.
- **Dimensions** — produit, agence, composante.
- **Recommandation** — Vérifier politique tarifaire et batch IC.
- **PCEC** — `PCEC/706` (commissions et frais divers).
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — à confirmer via mini-script d'exploration (tables CH / IC non systématiquement détaillées dans le rapport initial).

#### S14 — Interest accruals not liquidated within expected cycle

- **Findings** : `[F-130]` accruals older than `p_min_days_overdue` still in `ICTB_ACCRUALS_TEMP` ; `[F-131]` discrepancies between accrued amount and sum of liquidations since last reset.
- **Objectif** — S'assurer que le moteur IC **liquide** ses accruals selon la périodicité attendue et qu'aucun écart d'arrondi significatif ne s'accumule.
- **Sources** — `ICTB_ACCRUALS_TEMP`, `ICTB_LIQ_DETAILS`, paramétrage produit IC.
- **Méthode** — Pour chaque couple compte/composante, comparer la date du plus ancien accrual non liquidé à la date attendue de liquidation ; sommer les écarts par agence.
- **Sévérité** — HIGH si écart cumulé > `p_materiality_impact_lcy`.
- **Impact LCY** — Somme des accruals non liquidés LCY.
- **Dimensions** — agence, composante, produit.
- **Recommandation** — Lancer une liquidation corrective, investiguer paramétrage produit.
- **PCEC** — `PCEC/38` (régularisation) en attente, `PCEC/702`/`PCEC/602` à la liquidation.
- **Paramètres** — `p_date_to`, `p_min_days_overdue`, `p_materiality_impact_lcy`.
- **Fondement exploration** — accruals présents dans le rapport ; complétude à vérifier.

#### S15 — FX trade / cash deal revenue leakage (spread not applied)

- **Findings** : `[F-140]` FX contracts with rate within ±X bps of mid-market (spread nul) ; `[F-141]` FX fees waived without justification.
- **Objectif** — Détecter les opérations de change clientèle pour lesquelles la **marge** (spread) n'a pas été appliquée conformément à la politique de pricing, ou pour lesquelles les frais ont été annulés.
- **Sources** — `FXTB_CONTRACT_MASTER` (`DEAL_RATE`, `MID_RATE` si disponible), table de taux mid (`CYTB_RATES` ou équivalent).
- **Méthode** — Comparaison `DEAL_RATE` vs `MID_RATE` ; tolérance en bps paramétrable.
- **Sévérité** — HIGH pour contreparties corporate / FX volume > `p_materiality_impact_lcy`.
- **Impact LCY** — `|DEAL_RATE − MID_RATE| × notional_converti_LCY`.
- **Dimensions** — utilisateur, contrepartie, devise.
- **Recommandation** — Revue grille de pricing, contrôles maker/checker.
- **PCEC** — `PCEC/7` produits de change.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`, `p_ccy_list`.
- **Fondement exploration** — à confirmer via mini-script d'exploration dédié FX si le module FX est effectivement utilisé.

---

### 7.D — Contrôle comptable : GL, écritures manuelles, FX reval, suspense

#### S16 — GL balance vs movement history consistency

- **Findings** : `[F-150]` GLs where `SUM(ACTB_HISTORY movements over period) ≠ (GLTB_GL_BAL closing − opening)` beyond tolerance ; `[F-151]` GLs with zero balance but active movements ; `[F-152]` GLs with movements but frozen status.
- **Objectif** — Vérifier la **cohérence** entre l'historique comptable (`ACTB_HISTORY`) et les soldes GL (`GLTB_GL_BAL`) pour un sous-ensemble de GL critiques (produits, charges, suspense, clientèle).
- **Sources** — `ACTB_HISTORY` (`TRN_DT`, `AC_NO`, `DR_CR`, `LCY_AMOUNT`, `FCY_AMOUNT`, `BRANCH_CODE`), `GLTB_GL_BAL` (`OPENING_BAL_LCY`, `CLOSING_BAL_LCY`, `PERIOD_CODE`), `GLTB_GL_MASTER`.
- **Méthode** — Agrégation `SUM(CASE DR_CR WHEN 'D' THEN -LCY_AMOUNT ELSE LCY_AMOUNT END)` sur période vs `CLOSING_BAL_LCY − OPENING_BAL_LCY` ; tolérance absolue `p_materiality_lcy`.
- **Sévérité** — HIGH au-delà du seuil, CRITICAL si GL de résultat (classes 6/7).
- **Impact LCY** — Valeur absolue de l'écart.
- **Dimensions** — classe PCEC, agence, période.
- **Recommandation** — Ouvrir un ticket de réconciliation, purger / rejouer les batchs concernés.
- **PCEC** — Toutes classes, focus sur `PCEC/6`, `PCEC/7`, `PCEC/38`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`, `p_branch_*`.
- **Fondement exploration** — présence confirmée de `ACTB_HISTORY` et `GLTB_GL_BAL`, schéma mappé lors de l'exploration.

#### S17 — Manual journal entries — volume, concentration, sensitive GLs

- **Findings** : `[F-160]` manual entries count / amount per user over period ; `[F-161]` manual entries on income/expense GLs (classes 6/7) ; `[F-162]` manual entries passed outside business hours ; `[F-163]` manual entries reversed within 24h.
- **Objectif** — Détecter les **écritures manuelles** à risque (SoD, manipulation de résultat, opérations de dernière minute).
- **Sources** — `MOTB_CONTRACT_MASTER` (si module MO), `ACTB_HISTORY` filtré par `TRN_CODE` manuel, `SMTB_USER`.
- **Méthode** — Agrégation par utilisateur, par GL sensible, par plage horaire (`TO_CHAR(CREATION_DATE,'HH24')`), détection des renversements (`REVERSAL_MARKER` / amount négation).
- **Sévérité** — MEDIUM par défaut, HIGH en cas de concentration (> 50 % des écritures manuelles sur un utilisateur) ou sur GL sensible.
- **Impact LCY** — Somme des montants LCY concernés.
- **Dimensions** — utilisateur, GL, agence, tranche horaire.
- **Recommandation** — Revue maker/checker, analyse SoD, justification écrite requise.
- **PCEC** — Focus sur `PCEC/6`, `PCEC/7`, `PCEC/38`, `PCEC/5`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_top_n`, `p_materiality_lcy`.
- **Fondement exploration** — tables MO et ACTB_HISTORY confirmées.

#### S18 — Suspense accounts ageing (PCEC/38)

- **Findings** : `[F-170]` suspense account balances > 30/60/90/180 days old ; `[F-171]` suspense accounts with only one-sided movements ; `[F-172]` suspense accounts with balance opposite to expected side.
- **Objectif** — Surveiller les **comptes d'attente / suspense** (classe PCEC 38x) pour éviter l'accumulation et le risque de résultat latent.
- **Sources** — `GLTB_GL_MASTER` (filtre sur GL de la famille suspense), `ACTB_HISTORY`, `GLTB_GL_BAL`.
- **Méthode** — Pour chaque GL suspense, ancienneté du solde courant = `p_as_of_date − date du premier mouvement non soldé` ; agrégation par tranches.
- **Sévérité** — HIGH au-delà de 90 jours, CRITICAL au-delà de 180 jours ou montant > `p_materiality_critical_lcy`.
- **Impact LCY** — Solde absolu par tranche.
- **Dimensions** — agence, GL, ancienneté.
- **Recommandation** — Apurement mensuel obligatoire, escalade par ancienneté, provisionnement.
- **PCEC** — `PCEC/38` (comptes de régularisation et d'attente).
- **Paramètres** — `p_as_of_date`, `p_materiality_lcy`, `p_branch_*`.
- **Fondement exploration** — mapping GL à compléter par un mini-script d'exploration pour identifier la liste réelle des GL suspense à la banque.

#### S19 — FX revaluation anomalies

- **Findings** : `[F-180]` FX revaluation GL with abnormal swings (> X % mean daily) ; `[F-181]` FCY GL balance without matching reval posting over period ; `[F-182]` position-currency imbalance (actif ≠ passif FCY).
- **Objectif** — Contrôler la **revalorisation FX** : tous les soldes FCY doivent être réévalués à la bonne date et la position bilantielle par devise doit être équilibrée.
- **Sources** — `GLTB_GL_BAL` (`FCY_BALANCE`, `LCY_BALANCE`, `CCY`), `ACTB_HISTORY` pour postings de reval, table de taux de clôture.
- **Méthode** — Recalcul théorique `FCY_BALANCE × taux_clôture` vs `LCY_BALANCE` ; détection d'écart > tolérance.
- **Sévérité** — HIGH, CRITICAL si écart > `p_materiality_critical_lcy`.
- **Impact LCY** — Somme absolue des écarts.
- **Dimensions** — devise, agence, classe PCEC.
- **Recommandation** — Rejouer le batch de reval, corriger la table de taux.
- **PCEC** — Toutes classes, focus `PCEC/3` (opérations diverses) et `PCEC/7`.
- **Paramètres** — `p_as_of_date`, `p_ccy_list`, `p_materiality_lcy`.
- **Fondement exploration** — à confirmer : présence de GL FCY identifiée, mais le détail du batch de reval requiert un mini-script d'exploration.

#### S20 — GL mapping gaps vs PCEC COBAC

- **Findings** : `[F-190]` GL accounts without PCEC class assignable ; `[F-191]` GLs whose first-digit class is inconsistent with nature (e.g., a product GL in class 1) ; `[F-192]` significant volumes routed to an `OTHER / MISC` bucket.
- **Objectif** — Garantir la **couverture PCEC** pour le reporting COBAC ; aucune fuite d'activité vers un GL non classé ne doit subsister.
- **Sources** — `GLTB_GL_MASTER` (code GL, description, classe éventuelle), `GLTB_GL_BAL`.
- **Méthode** — Dérivation de la classe PCEC à partir du préfixe du code GL (convention interne) + comparaison à un mapping de référence (fichier externe ou convention documentée).
- **Sévérité** — MEDIUM, HIGH si GL à volume significatif non mappé.
- **Impact LCY** — Volume total des mouvements sur GL non mappés.
- **Dimensions** — classe PCEC, agence.
- **Recommandation** — Compléter le mapping, republier le reporting COBAC rétroactivement si nécessaire.
- **PCEC** — Transverse, objectif de couverture ≥ 95 %.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — nécessaire mini-script d'exploration pour établir la convention de préfixe GL→PCEC propre à cette banque.

---

### 7.E — Contrôles internes et Segregation of Duties (SoD)

#### S21 — Maker/Checker violations and self-authorization patterns

- **Findings** : `[F-200]` transactions where `MAKER_ID = CHECKER_ID` (self-authorized) ; `[F-201]` users with recurring maker/checker pairing above threshold ; `[F-202]` maker/checker cycles completed in < N seconds (auto-approval suspect).
- **Objectif** — Détecter les violations du principe **maker/checker** et les paires suspectes de collusion potentielle.
- **Sources** — `ACTB_HISTORY` (`MAKER_ID`, `CHECKER_ID`, `MAKER_DT_STAMP`, `CHECKER_DT_STAMP`), `MOTB_CONTRACT_MASTER`, `SMTB_USER`, `SMTB_ROLE`.
- **Méthode** — Filtre `MAKER_ID = CHECKER_ID` ; pour les paires récurrentes, agrégation `(MAKER, CHECKER) → count` et classement ; délais (`CHECKER_DT_STAMP − MAKER_DT_STAMP`) < `p_min_maker_checker_seconds` (param dérivé).
- **Sévérité** — CRITICAL pour `[F-200]` s'agissant de GL sensibles, HIGH sinon.
- **Impact LCY** — Somme des montants LCY concernés.
- **Dimensions** — utilisateur, rôle, GL/produit, agence.
- **Recommandation** — Revue urgente des droits, retrait de cumuls, rappel de politique.
- **PCEC** — Transverse.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_top_n`, `p_materiality_lcy`.
- **Fondement exploration** — colonnes `MAKER_ID`/`CHECKER_ID` confirmées sur `ACTB_HISTORY`.

#### S22 — Inactive / dormant user accounts with recent activity

- **Findings** : `[F-210]` users with `EXITFLAG = 'Y'` (or disabled status) still showing `ACTB_HISTORY` activity over period ; `[F-211]` users with no login since N days but present in transactions.
- **Objectif** — Vérifier que les comptes utilisateurs **inactifs** ou **sortis** ne réalisent plus d'opérations (risque de compte orphelin, usurpation, ghost user).
- **Sources** — `SMTB_USER` (`USER_ID`, `EXITFLAG`, `LAST_LOGIN_DATE`, `START_DATE`, `END_DATE`), `ACTB_HISTORY`.
- **Méthode** — Jointure `SMTB_USER` ↔ `ACTB_HISTORY.MAKER_ID / CHECKER_ID` sur période ; filtre sur flag sortie ou `LAST_LOGIN_DATE < p_as_of_date - N`.
- **Sévérité** — CRITICAL (risque de fraude / usurpation).
- **Impact LCY** — Somme des montants des opérations concernées.
- **Dimensions** — utilisateur, rôle, agence.
- **Recommandation** — Blocage immédiat, enquête, revue des accès.
- **PCEC** — Transverse (contrôle interne).
- **Paramètres** — `p_date_from`, `p_date_to`, `p_as_of_date`.
- **Fondement exploration** — champ `EXITFLAG` confirmé (type NUMBER) ; requiert `TO_CHAR` pour afficher.

#### S23 — Role and privilege anomalies — toxic combinations

- **Findings** : `[F-220]` users with concurrent roles enabling end-to-end transaction handling (maker + checker + authoriser) ; `[F-221]` roles granting access to sensitive GLs to non-accounting users ; `[F-222]` role concentration (one role covers > N % of sensitive privileges).
- **Objectif** — Identifier les **combinaisons toxiques** de rôles et privilèges non conformes à la SoD.
- **Sources** — `SMTB_USER_ROLE`, `SMTB_ROLE`, `SMTB_ROLE_FUNCTION`, tables de privilèges applicatifs.
- **Méthode** — Matrice de couverture rôle ↔ fonction ; détection des cumuls interdits via une liste noire documentée (liste à figer par le Responsable Sécurité / Compliance).
- **Sévérité** — HIGH, CRITICAL si combinaison présente sur > N utilisateurs.
- **Impact LCY** — Non chiffré directement ; exposé en risque.
- **Dimensions** — rôle, utilisateur, agence.
- **Recommandation** — Réattribution des rôles, refonte de la matrice, validation DRH / Compliance.
- **PCEC** — Transverse.
- **Paramètres** — `p_as_of_date`, `p_branch_*`.
- **Fondement exploration** — tables SM confirmées dans le rapport d'exploration.

### 7.F — Conformité PCEC et méthodes comptables

Cette famille vérifie que les écritures FCUBS respectent le **référentiel comptable** COBAC R-98/01 (PCEC) et les **principes comptables** applicables (cf. §14). Elle complète §7.D (cohérence technique GL↔historique) par une lecture **normative**.

#### S24 — Accounting scheme compliance (transaction vs expected DR/CR pattern)

- **Findings** : `[F-230]` product transactions whose debit/credit scheme deviates from the standard pattern (cf. §13.3) ; `[F-231]` one-sided postings (débit sans crédit de contrepartie attendu) ; `[F-232]` contrepartie inscrite sur un GL hors famille attendue.
- **Objectif** — Garantir que chaque opération suit le **schéma comptable standard** documenté en §13 (ex. octroi de prêt : DR `PCEC/201` ↔ CR `PCEC/251/252` client ; facturation de frais : DR compte client ↔ CR `PCEC/706`).
- **Sources** — `ACTB_HISTORY` (paire d'écritures par `TRN_REF_NO`), `GLTB_GL_MASTER`, mapping interne `TRN_CODE` → schéma attendu (§13.3).
- **Méthode** — Pour chaque `TRN_REF_NO` sur la période, reconstituer la paire DR/CR et comparer le couple (GL débit, GL crédit) au schéma autorisé pour le `TRN_CODE`.
- **Sévérité** — HIGH ; CRITICAL sur GL de classes 6/7/5.
- **Impact LCY** — Montant LCY des écritures non conformes.
- **Dimensions** — `TRN_CODE`, produit, agence, utilisateur.
- **Recommandation** — Corriger le paramétrage produit ou l'écriture manuelle ; valider le registre des schémas (§13.3).
- **PCEC** — Transverse (focus classes 6/7/2/38).
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — à confirmer via mini-script `describe_accounting_schemes.sql` (§7.Z).

#### S25 — Offsetting / compensation breaches (non-compensation principle)

- **Findings** : `[F-240]` accounts where a debit position and a credit position on the same client/family are netted into one GL ; `[F-241]` GL whose balance comprises offsetting asset/liability in violation du principe de non-compensation.
- **Objectif** — Appliquer le **principe de non-compensation** (§14.2) : un actif et un passif ne peuvent être nets sauf exceptions prévues ; les produits et charges ne se compensent pas.
- **Sources** — `STTM_CUST_ACCOUNT`, `GLTB_GL_BAL`, `GLTB_GL_MASTER` (nature actif/passif/produit/charge dérivée du code).
- **Méthode** — Détection des configurations où des positions opposées du même client ou de la même classe PCEC sont comptabilisées sur un GL unique au lieu de GL séparés actif/passif.
- **Sévérité** — HIGH ; CRITICAL si impact > `p_materiality_critical_lcy`.
- **Impact LCY** — Somme brute des positions compensées (les deux jambes).
- **Dimensions** — classe PCEC, client, produit.
- **Recommandation** — Scinder les écritures, ouvrir GL dédiés, documenter les exceptions autorisées.
- **PCEC** — Classes 1, 2, 6, 7.
- **Paramètres** — `p_as_of_date`, `p_materiality_lcy`.
- **Fondement exploration** — mini-script `describe_accounting_schemes.sql` + règle de classification actif/passif.

#### S26 — Cut-off / specialisation des exercices

- **Findings** : `[F-250]` transactions dated in period N posted in period N+1 ; `[F-251]` accruals not reversed / not extended across period boundary ; `[F-252]` backdated entries (`TRN_DT < BKG_DATE − tolerance`).
- **Objectif** — Appliquer la **spécialisation des exercices** : chaque charge/produit est rattaché à la période à laquelle il se rapporte.
- **Sources** — `ACTB_HISTORY` (`TRN_DT`, `BKG_DATE`, `VALUE_DATE`), `ICTB_ACCRUALS_TEMP`.
- **Méthode** — Ecart `BKG_DATE − TRN_DT` > tolérance ; vérification de la présence d'accruals en fin de mois sur GL produits/charges ; détection d'écritures antidatées.
- **Sévérité** — HIGH sur GL de résultat, MEDIUM sinon.
- **Impact LCY** — Somme LCY des écritures mal rattachées.
- **Dimensions** — période, agence, utilisateur.
- **Recommandation** — Revue batch de clôture, contrôles maker/checker renforcés en fin de période.
- **PCEC** — Classes 6, 7 en priorité.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_tol_days_backdate` (dérivé, défaut 3).
- **Fondement exploration** — confirmé : `BKG_DATE` et `TRN_DT` présents sur `ACTB_HISTORY`.

#### S27 — Permanence des méthodes / rate & parameter changes

- **Findings** : `[F-260]` product interest rate changes applied retroactively (affecting prior periods) ; `[F-261]` fee grid updates without documented effective date ; `[F-262]` unusual spikes in income/expense accruals following a parameter change.
- **Objectif** — Appliquer la **permanence des méthodes** : les règles de calcul (taux, méthodes d'amortissement, grilles) ne changent pas arbitrairement en cours d'exercice.
- **Sources** — `ICTM_PRODUCT_DEFINITION`, `CSTB_CONTRACT_EVENT_LOG` (si disponible), `ACTB_HISTORY`, tables de grille des frais.
- **Méthode** — Comparaison des versions de paramétrage dans le temps ; détection de changements rétroactifs ou sans date effective ; corrélation avec des pics d'accruals.
- **Sévérité** — HIGH.
- **Impact LCY** — Différentiel estimé (nouvelle méthode − ancienne méthode) sur la période.
- **Dimensions** — produit, utilisateur, période.
- **Recommandation** — Geler les paramètres en cours d'exercice, documenter toute dérogation.
- **PCEC** — Classes 6, 7.
- **Paramètres** — `p_date_from`, `p_date_to`.
- **Fondement exploration** — mini-script `describe_parameter_history.sql` (§7.Z).

#### S28 — GL nature consistency (asset/liability/income/expense)

- **Findings** : `[F-270]` asset GLs with persistent credit balance ; `[F-271]` liability GLs with persistent debit balance ; `[F-272]` income/expense GLs reset to zero mid-period without explicit closing entry.
- **Objectif** — Vérifier que chaque GL conserve un **sens de solde** cohérent avec sa nature comptable PCEC.
- **Sources** — `GLTB_GL_MASTER` (nature), `GLTB_GL_BAL` (solde par période).
- **Méthode** — Contrôle du sens normal : les comptes d'actif (classes 1, 2 côté emplois, 3 côté emplois, 4) doivent être normalement débiteurs ; passifs normalement créditeurs ; produits créditeurs ; charges débitrices. Tolérance paramétrable.
- **Sévérité** — HIGH ; CRITICAL pour classes 6/7 avec inversion de sens.
- **Impact LCY** — Valeur absolue du solde anormal.
- **Dimensions** — classe PCEC, agence.
- **Recommandation** — Investiguer l'inversion de sens, corriger, éventuellement reclasser le GL.
- **PCEC** — Toutes classes.
- **Paramètres** — `p_as_of_date`, `p_materiality_lcy`.
- **Fondement exploration** — la nature des GL est exposée par `GLTB_GL_MASTER` (à confirmer par mini-script `describe_gl_nature.sql`).

---

### 7.G — Détection de fraudes et typologies à risque

Cette famille couvre les **schémas de fraude** internes et externes détectables par analyse des données comptables FCUBS. Elle agit en **complément** (et non en remplacement) du module AML/CFT dédié : l'angle retenu ici est la **fraude comptable / opérationnelle**, pas le blanchiment.

> Les constats de cette famille sont par nature sensibles : ils doivent faire l'objet d'une **investigation contradictoire** avant toute conclusion (cf. §10.5 et §15.4).

#### S29 — Circular / structured transactions between related accounts

- **Findings** : `[F-280]` funds cycling between a small set of related accounts over a short window (A→B→C→A) ; `[F-281]` transactions just below reporting / authorisation thresholds (structuring) ; `[F-282]` round-trip transactions reversed within N hours with no business justification.
- **Objectif** — Détecter les **transactions circulaires** et les **structuring** (fragmentation pour rester sous un seuil) qui sont des indicateurs classiques de fraude et de manipulation de soldes.
- **Sources** — `ACTB_HISTORY` (`AC_NO`, `TRN_REF_NO`, `OFFSET_AC_NO` si présent, `LCY_AMOUNT`, `TRN_DT`), `FTTB_CONTRACT_MASTER`.
- **Méthode** — Graphe orienté comptes × comptes sur la période ; détection de cycles de longueur 2–5 ; détection de montants clusterisés juste sous les seuils paramétrables (ex. 9 999 999 répétés).
- **Sévérité** — HIGH, CRITICAL si impliquant un compte sensible (§13).
- **Impact LCY** — Volume total des flux cycliques / structurés.
- **Dimensions** — compte, utilisateur, agence, tranche de montant.
- **Recommandation** — Saisir Audit Interne et Compliance ; investigation dédiée ; blocage des comptes le cas échéant.
- **PCEC** — Transverse, foyer `PCEC/2`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_structuring_threshold_lcy` (dérivé).
- **Fondement exploration** — structure `ACTB_HISTORY` confirmée ; présence d'un `OFFSET_AC_NO` à vérifier via mini-script.

#### S30 — Suspicious reversals (contre-passations)

- **Findings** : `[F-290]` entries reversed within < 24h on sensitive GLs (classes 6/7/38) ; `[F-291]` reversals passed by a different user than the maker of the original, but repeatedly by the same pair ; `[F-292]` round-trip (posting + reversal) straddling a period boundary (fin de mois).
- **Objectif** — Détecter les **contre-passations suspectes** : écritures passées pour gonfler/amoindrir un solde puis annulées, ou pour tester des contrôles.
- **Sources** — `ACTB_HISTORY` (`TRN_REF_NO`, `REVERSAL_MARKER` / `TRN_CODE` d'annulation, `MAKER_ID`, `CHECKER_ID`, `TRN_DT`).
- **Méthode** — Appariement par `TRN_REF_NO` ou par somme algébrique nulle sur fenêtre courte ; classification des cas à risque selon GL cible.
- **Sévérité** — HIGH, CRITICAL pour contournements fin de période.
- **Impact LCY** — Montant LCY du couple original/annulation.
- **Dimensions** — GL cible, maker/checker, horodatage, période.
- **Recommandation** — Revue maker/checker, revalidation SoD, alerte Compliance.
- **PCEC** — Focus `PCEC/6`, `PCEC/7`, `PCEC/38`, `PCEC/5`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_reversal_window_hours` (défaut 24).
- **Fondement exploration** — présence de flags de renversement confirmée sur `ACTB_HISTORY`.

#### S31 — Off-hours / weekend / holiday postings

- **Findings** : `[F-300]` postings with `CREATION_DATE` in weekend or outside `p_business_hours_window` ; `[F-301]` postings on official holidays (si calendrier disponible) ; `[F-302]` concentration par utilisateur/agence d'écritures hors heures.
- **Objectif** — Détecter les écritures passées en **dehors des heures d'exploitation** normales, indicateur classique de fraude interne.
- **Sources** — `ACTB_HISTORY` (`CREATION_DATE`, `MAKER_DT_STAMP`), calendrier interne si disponible.
- **Méthode** — Filtre horaire + jour de la semaine ; rapprochement calendrier férié ; comptage par utilisateur/agence.
- **Sévérité** — MEDIUM, HIGH si concentration + GL sensible.
- **Impact LCY** — Somme LCY des écritures concernées.
- **Dimensions** — utilisateur, agence, créneau horaire.
- **Recommandation** — Revue SoD, revalidation des accès hors heures.
- **PCEC** — Transverse.
- **Paramètres** — `p_business_hours_from`, `p_business_hours_to` (ex. 07:00–19:00), `p_exclude_technical_users`.
- **Fondement exploration** — colonnes confirmées.

#### S32 — Inter-account kiting / timing fraud

- **Findings** : `[F-310]` accounts with repeated offsetting credit/debit patterns aligning with cut-off batches ; `[F-311]` overdraft positions temporarily eliminated on run dates (fin de mois / fin de trimestre) then re-appearing.
- **Objectif** — Détecter le **kiting** : utilisation des décalages de traitement pour masquer artificiellement un découvert ou gonfler un solde à une date d'arrêté.
- **Sources** — `ACTB_HISTORY`, `STTM_CUST_ACCOUNT` (variations de solde autour des arrêtés).
- **Méthode** — Comparaison solde veille d'arrêté vs solde jour d'arrêté vs solde lendemain ; détection des « pics » non persistants.
- **Sévérité** — HIGH, CRITICAL si récurrent.
- **Impact LCY** — Valeur du pic masqué.
- **Dimensions** — compte, client, agence.
- **Recommandation** — Investigation ciblée ; revue des limites de découvert ; alerte Compliance.
- **PCEC** — `PCEC/2`.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_materiality_lcy`.
- **Fondement exploration** — nécessite un mini-script `describe_cutoff_dates.sql` pour identifier les dates d'arrêté internes.

#### S33 — Employee / internal actor red flags

- **Findings** : `[F-320]` postings by employees **on their own client account** or on accounts of first-degree related parties ; `[F-321]` employees with waivers granted to their own accounts ; `[F-322]` large transfers between employee accounts and external beneficiaries recently created ; `[F-323]` ghost/suspense accounts opened and closed within a short window by the same user.
- **Objectif** — Mettre en lumière les **conflits d'intérêts** et schémas d'**enrichissement interne** à partir des rapprochements utilisateur/client.
- **Sources** — `SMTB_USER` (association USER_ID ↔ CUSTOMER_NO interne si existe), `STTM_CUSTOMER`, `ACTB_HISTORY`, `CSTB_CONTRACT_EVENT_LOG`.
- **Méthode** — Jointure `MAKER_ID`/`CHECKER_ID` ↔ `CUSTOMER_NO` interne ; détection de waivers auto-appliqués ; détection de comptes de courte durée de vie par utilisateur.
- **Sévérité** — CRITICAL (risque éthique et fraude).
- **Impact LCY** — Somme des montants concernés.
- **Dimensions** — utilisateur, lien familial (si renseigné), agence.
- **Recommandation** — Blocage immédiat, enquête contradictoire, saisine RH + Compliance.
- **PCEC** — Transverse.
- **Paramètres** — `p_date_from`, `p_date_to`.
- **Fondement exploration** — mini-script `describe_user_customer_link.sql` requis.

#### S34 — Reference data tampering preceding debits

- **Findings** : `[F-330]` beneficiary / RIB changes on a customer account within N hours before a large outgoing transfer ; `[F-331]` interest rate or fee waiver granted minutes before a liquidation ; `[F-332]` account re-opened (un-dormant) then immediately debited ; `[F-333]` address / contact change just before a sensitive operation.
- **Objectif** — Détecter les **modifications de référentiel** suspectes qui **précèdent** une opération financière, schéma typique de fraude ciblée (siphonage de compte dormant, détournement par changement de bénéficiaire).
- **Sources** — `CSTB_CONTRACT_EVENT_LOG` (événements applicatifs), `STTM_CUST_ACCOUNT` (audit trail s'il existe), `CLTB_ACCOUNT_COMPONENTS` pour les waivers, `ACTB_HISTORY` pour le débit consécutif.
- **Méthode** — Fenêtre temporelle courte (`p_tamper_window_hours`, défaut 24h) entre la modification et l'opération ; classement par impact.
- **Sévérité** — CRITICAL.
- **Impact LCY** — Montant de l'opération subséquente.
- **Dimensions** — utilisateur, type de modification, client.
- **Recommandation** — Geler l'opération si possible, investigation Audit + Compliance, saisine éventuelle autorités.
- **PCEC** — Transverse.
- **Paramètres** — `p_date_from`, `p_date_to`, `p_tamper_window_hours`.
- **Fondement exploration** — dépend de la disponibilité d'un journal d'événements applicatif (mini-script `describe_event_log.sql`).

---

### 7.Z — Hypothèses à valider par mini-scripts d'exploration

Les contrôles suivants requièrent, **avant** rédaction du corps du script, des mini-scripts d'exploration dédiés afin de ne pas inventer de structures :

| Section | Objet à clarifier | Mini-script attendu |
|---|---|---|
| S04 | Colonnes réelles `WAIVE*` sur `ICTB_LIQ_DETAILS`/`ACTB_HISTORY` | `describe_waiver_columns.sql` |
| S13 | Présence effective du module CH (`CHTB_*`) | `describe_module_ch.sql` |
| S14 | Convention de liquidation IC (fréquence produit) | `describe_ic_accrual_cycle.sql` |
| S15 | Usage réel du module FX et des taux mid | `describe_fx_module.sql` |
| S18 | Liste des GL suspense (plage de codes) | `list_suspense_gls.sql` |
| S20 | Convention de préfixe GL → PCEC | `gl_prefix_to_pcec.sql` |
| S23 | Mapping `SMTB_ROLE_FUNCTION` complet | `describe_role_function.sql` |
| S24 / S25 / S28 | Cartographie `TRN_CODE` → schéma comptable attendu ; nature des GL | `describe_accounting_schemes.sql`, `describe_gl_nature.sql` |
| S27 | Historique de paramétrage produit (taux, grilles) | `describe_parameter_history.sql` |
| S29 | Présence de `OFFSET_AC_NO` sur `ACTB_HISTORY` | `describe_offset_account.sql` |
| S32 | Dates d'arrêté internes / calendrier batch | `describe_cutoff_dates.sql` |
| S33 | Lien `SMTB_USER.USER_ID` ↔ `STTM_CUSTOMER.CUSTOMER_NO` | `describe_user_customer_link.sql` |
| S34 | Journal d'événements applicatifs (référentiel) | `describe_event_log.sql` |

> Un mini-script est rédigé à la demande, exécuté par le côté banque, et son résultat déclenche la rédaction de la section concernée. Voir `bonnes_pratiques.md` §6 pour le protocole.

### 7.99 — Tableau récapitulatif des contrôles

| Section | Titre | Sévérité max | Classe PCEC principale | Fondement exploration |
|---|---|---|---|---|
| S01 | Unauthorized overdrafts | CRITICAL | PCEC/2, PCEC/702 | 950 comptes |
| S02 | TOD overrun / expired | HIGH | PCEC/2, PCEC/702 | Confirmé |
| S03 | Dormant with accruals | HIGH | PCEC/2, PCEC/38 | 179 comptes |
| S04 | Charge waivers | HIGH | PCEC/7 | À confirmer |
| S05 | Credit balances w/o accrual | MEDIUM | PCEC/2, PCEC/6/7 | À confirmer |
| S06 | Overdue CL schedules | CRITICAL | PCEC/2, PCEC/29, PCEC/702 | 1 620 échéances |
| S07 | Frozen CL | CRITICAL | PCEC/29 | 662 prêts |
| S08 | CL pending liquidation | HIGH | PCEC/2, PCEC/702 | À confirmer |
| S09 | LD anomalies | HIGH | PCEC/1, PCEC/2 | Tables confirmées |
| S10 | CL waivers / overrides | HIGH | PCEC/7 | Colonne `WAIVE` confirmée |
| S11 | SI without charge flags | HIGH | PCEC/706 | 51 + 782 |
| S12 | Expired/stalled SI | HIGH | PCEC/706 | 281 |
| S13 | Unbilled / zero charges | HIGH | PCEC/706 | À confirmer |
| S14 | IC accruals not liquidated | HIGH | PCEC/38, PCEC/702 | À confirmer |
| S15 | FX spread leakage | HIGH | PCEC/7 | À confirmer |
| S16 | GL vs history consistency | CRITICAL | Toutes | Schéma confirmé |
| S17 | Manual entries risk | HIGH | PCEC/6, PCEC/7, PCEC/38 | MO/ACTB confirmés |
| S18 | Suspense ageing | CRITICAL | PCEC/38 | À confirmer |
| S19 | FX revaluation | CRITICAL | PCEC/3, PCEC/7 | À confirmer |
| S20 | GL–PCEC mapping gaps | HIGH | Transverse | À confirmer |
| S21 | Maker/checker violations | CRITICAL | Transverse | Colonnes confirmées |
| S22 | Inactive users active | CRITICAL | Transverse | `EXITFLAG` confirmé |
| S23 | Toxic role combinations | CRITICAL | Transverse | SM confirmés |
| S24 | Accounting scheme compliance | CRITICAL | Transverse (6/7/2/38) | À confirmer |
| S25 | Offsetting breaches | CRITICAL | 1/2/6/7 | À confirmer |
| S26 | Cut-off / spécialisation | HIGH | 6/7 | Confirmé |
| S27 | Permanence des méthodes | HIGH | 6/7 | À confirmer |
| S28 | GL nature consistency | CRITICAL | Toutes | À confirmer |
| S29 | Circular / structured txns | CRITICAL | PCEC/2 | À confirmer |
| S30 | Suspicious reversals | CRITICAL | 5/6/7/38 | Confirmé |
| S31 | Off-hours postings | HIGH | Transverse | Confirmé |
| S32 | Kiting / timing fraud | CRITICAL | PCEC/2 | À confirmer |
| S33 | Employee red flags | CRITICAL | Transverse | À confirmer |
| S34 | Reference data tampering | CRITICAL | Transverse | À confirmer |

Ce catalogue peut être enrichi au fil des runs sans rupture de compatibilité (numérotation stable, sections ajoutées à la suite).

---

## 8. Structure du rapport de sortie

Le rapport doit être **en anglais**, en **texte brut monospacé**, largeur ≤ 200 colonnes, lisible à la fois par un humain et par un outil d'extraction textuelle. Il est généré intégralement via `DBMS_OUTPUT.PUT_LINE` et redirigé par SPOOL vers un fichier horodaté.

### 8.1 Hiérarchie du rapport

```
REPORT
├── HEADER                   — bannière, version, horodatage
├── PARAMETERS               — écho des paramètres effectifs
├── ENVIRONMENT              — version Oracle, photo comptable, volumes de référence
├── EXECUTIVE SUMMARY        — synthèse condensée (≤ 60 lignes)
├── GLOBAL INDICATORS        — KPIs (total exposure, findings by severity, PCEC coverage)
├── SECTIONS
│   ├── S01 ... S23          — une sous-arborescence par contrôle
│   │   ├── Header           — id, titre, objectif, PCEC
│   │   ├── Findings [F-NNN] — chacun structuré (cf. 8.4)
│   │   └── Summary          — mini-résumé de section
├── CROSS-CUTTING VIEWS      — top-N, matrice sévérité×PCEC, root causes
├── APPENDICES               — queries used, reference tables, glossary abbreviations
├── KNOWN LIMITATIONS        — sections dégradées/inexécutées et raisons
├── LOGS [LOG]               — horodatage info/warn/error
├── PERFORMANCE [PERF]       — durée par section (opt.)
└── FOOTER                   — run-id, hash, version, signature
```

### 8.2 HEADER (exemple)

```
===============================================================================
  REVENUE ASSURANCE & ACCOUNTING AUDIT
  Bank          : <BANK_NAME>
  Environment   : <INSTANCE_NAME>
  Script version: 1.0.0
  Run ID        : 20260417231502
  Executed by   : <DB_USER>
  Executed at   : 2026-04-17 23:15:02 UTC
===============================================================================
```

### 8.3 EXECUTIVE SUMMARY (exemple)

```
===============================================================================
  EXECUTIVE SUMMARY
===============================================================================
 Audit period ................ 2026-03-01 → 2026-03-31
 As-of date .................. 2026-04-17
 Total findings .............. 137 (C:14  H:42  M:61  L:15  I:5)
 Total RA exposure (LCY) ..... 1,842,500,000 XAF  [capped @ p_materiality_cap]
 PCEC coverage ............... 98.2%
-------------------------------------------------------------------------------
 TOP 10 FINDINGS BY IMPACT
 #   SEV        ID        TITLE                                  IMPACT (LCY)
 01  CRITICAL   F-006     Overdue CL schedules > 90 days       312,400,000
 02  CRITICAL   F-050     Unauthorised overdrafts              287,900,000
 ...
===============================================================================
```

### 8.4 Format d'un Finding

Chaque constat est émis au format normalisé :

```
-------------------------------------------------------------------------------
 [F-050]  SEVERITY: CRITICAL    PCEC: 2 / 702
 Title   : Unauthorized overdrafts without TOD limit
 Period  : 2026-03-01 → 2026-03-31   As-of: 2026-04-17
 Scope   : Branch=ALL  Customer=ALL  Product=CASA
 Count   : 950 accounts
 Impact  : 287,900,000 LCY (XAF)  (estimated unbilled OD interest)
 Rule    : ACY_CURR_BALANCE < 0 AND (TOD_LIMIT IS NULL OR TOD_LIMIT = 0)
 Top dim : by Branch — Douala 42%, Yaoundé 31%, Bafoussam 12%
 Reco    : Enforce TOD paramétering, bill unauthorized OD at penal rate
 Ref-qry : APPENDIX A1.S01.Q01
-------------------------------------------------------------------------------
```

Champs **obligatoires** : `[F-NNN]`, Severity, Title, Count, Impact (ou N/A), Rule, Recommendation, PCEC.
Champs **recommandés** : Period, Scope, Top dim, Ref-qry.

### 8.5 Sévérités — définition et règles de promotion

| Severity | Définition courte | Règle de promotion automatique |
|---|---|---|
| `CRITICAL` | Risque immédiat sur le résultat, la conformité ou la SoD ; à traiter sous 7 jours. | Impact > `p_materiality_critical_lcy` OU section marquée critical. |
| `HIGH` | Perte / risque significatif ; plan d'action sous 30 jours. | Impact > `p_materiality_impact_lcy`. |
| `MEDIUM` | À investiguer ; corriger dans le cycle trimestriel. | Par défaut pour la plupart des findings. |
| `LOW` | À tracer ; revue annuelle. | Impact < `p_materiality_lcy`. |
| `INFO` | Observation / volumétrie ; pas d'action requise. | Agrégats de contexte. |

La promotion s'applique **automatiquement** au moment de `print_finding` en fonction des seuils.

### 8.6 GLOBAL INDICATORS (exemple)

```
===============================================================================
  GLOBAL INDICATORS
===============================================================================
 FINDINGS BY SEVERITY
   CRITICAL .............. 14
   HIGH .................. 42
   MEDIUM ................ 61
   LOW ................... 15
   INFO .................. 5

 EXPOSURE BY PCEC CLASS (LCY)
   Class 1 (Treasury/EC)         ......     84,000,000
   Class 2 (Customers)           ......  1,423,100,000
   Class 3 (Securities/Diverse)  ......     12,700,000
   Class 6 (Expenses)            ......     28,300,000
   Class 7 (Income)              ......    294,400,000

 VOLUMETRY
   Accounts audited ........ 312,478
   Transactions scanned .... 18,492,105
   GL accounts ............. 12,417
```

### 8.7 CROSS-CUTTING VIEWS

- **Severity × PCEC matrix** : nombre de findings et somme d'impact LCY par cellule.
- **Top-N by branch / product / customer** (mode `DEEP` uniquement).
- **Root causes Top 5** — identifiants textuels (ex. "Product param missing", "User SoD breach", "Batch skipped", "TOD not renewed"), agrégés sur tous les findings.

### 8.8 APPENDICES

- **A1 — Queries** : pour chaque `[F-NNN]`, la requête SQL utilisée (ou sa version anonymisée) est listée, préfixée de son identifiant `Ref-qry` (`A1.SNN.Qnn`). Imprimée **uniquement** si `p_verbose = 'Y'`.
- **A2 — Reference tables** : tables de seuils, liste des GL critiques, mapping PCEC utilisé.
- **A3 — Glossary & abbreviations** : rappel des acronymes utilisés.

### 8.9 KNOWN LIMITATIONS

```
===============================================================================
  KNOWN LIMITATIONS
===============================================================================
 - Section S15 (FX leakage): skipped — table CYTB_RATES not accessible.
 - Section S18 (Suspense ageing): partial — suspense GL list based on
   convention <30* ; banque to confirm complete list.
 - Mapping GL→PCEC: automatic derivation from GL code prefix; manual
   validation pending.
```

### 8.10 LOGS `[LOG]` et `[PERF]`

- **[LOG]** : chaque ligne au format `YYYY-MM-DD HH24:MI:SS | LEVEL | SECTION | MESSAGE` avec LEVEL ∈ {`INFO`, `WARN`, `ERROR`, `FATAL`}.
- **[PERF]** : `SECTION | DURATION_MS | ROWS_RETURNED | STATUS` — une ligne par section exécutée.

Ces blocs DOIVENT être placés en **fin** de rapport pour ne pas polluer la lecture métier.

### 8.11 FOOTER

```
===============================================================================
  END OF REPORT
  Run ID        : 20260417231502
  Script version: 1.0.0
  Integrity hash: 7f3c-91a8-bb2d (DBMS_UTILITY.GET_HASH_VALUE on banner)
  Duration      : 00:11:42
  Status        : COMPLETED (3 sections degraded, see KNOWN LIMITATIONS)
===============================================================================
```

### 8.12 Règles de mise en forme

- Largeur cible : **120 colonnes** (stricte) pour blocs centraux, max 200.
- Séparateurs : `===` pour grandes sections, `---` pour sous-sections.
- Numérotation monétaire : virgule comme séparateur de milliers, point décimal.
- Alignement des montants : **à droite** avec largeur fixe.
- Dates : ISO `YYYY-MM-DD` (jamais locale).
- Caractères : ASCII pur ; pas de caractère non-ASCII (emoji, accents) pour garantir la portabilité du spool.
- Pas de couleur ni d'escape ANSI.

### 8.13 Principes d'ergonomie

- L'Executive Summary DOIT tenir en **une page terminale** (≤ 60 lignes).
- Chaque section DOIT être **auto-suffisante** : un lecteur peut lire une section sans relire le début du rapport.
- Les montants majeurs DOIVENT être répétés en pied de section.
- Chaque finding DOIT citer sa règle (`Rule`) en une ligne lisible.

### 8.14 Versionnement du format de rapport

La version du format de rapport est distincte de la version du script : `REPORT_FORMAT_VERSION = 1.0`. Toute évolution impactant l'extraction automatique (ajout/suppression de champ) DOIT incrémenter cette version et être documentée dans `KNOWN LIMITATIONS` pendant au moins un run de transition.

---

## 9. Mapping PCEC COBAC par constat

Cette section formalise le **rattachement** de chaque contrôle §7 à une ou plusieurs rubriques du PCEC COBAC R-98/01 et précise la logique d'affectation en rapport.

### 9.1 Principes de rattachement

- **P1** — Chaque contrôle DOIT être rattaché à **au moins une classe** PCEC (exigence BR-20).
- **P2** — Lorsque l'information GL est disponible, le rattachement DOIT descendre au **compte principal** (2 chiffres) voire **divisionnaire** (3 chiffres).
- **P3** — Un constat peut être rattaché à **plusieurs rubriques** (double entrée bilan/résultat).
- **P4** — Si un constat porte sur un GL **non mappé**, il est classé en `PCEC/?` et remonté dans S20 (BR-21).
- **P5** — Les rubriques utilisées DOIVENT être citées **textuellement** dans le rapport (ex. `PCEC/2 — Opérations avec la clientèle`).

### 9.2 Rappel synthétique des classes PCEC (COBAC R-98/01)

| Classe | Intitulé officiel | Portée RA / audit |
|---|---|---|
| **1** | Opérations de trésorerie et opérations avec les établissements de crédit | Interbank, NOSTRO/VOSTRO, BCEAO/BEAC. |
| **2** | Opérations avec la clientèle | **Foyer principal RA** : crédits, dépôts, découverts. |
| **3** | Opérations sur titres et opérations diverses | Titres, 38x comptes d'attente / régularisation. |
| **4** | Valeurs immobilisées | Immobilisations, participations. |
| **5** | Capitaux permanents | Fonds propres, résultat. |
| **6** | Charges | Charges d'exploitation bancaire (intérêts versés, frais). |
| **7** | Produits | **Foyer clé** : intérêts perçus, commissions, frais. |
| **8** | Soldes caractéristiques de gestion | PNB, RBE (indicateurs). |
| **9** | Engagements hors bilan | Garanties, engagements de financement. |

### 9.3 Matrice Section × Classe PCEC

> Une croix indique que la section produit des findings rattachables à la classe ; une double croix (`XX`) indique un rattachement **principal**.

| Section | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| S01 — Unauthorized overdrafts |   | XX |   |   |   |   | X  |   |   |
| S02 — TOD overrun / expired   |   | XX |   |   |   |   | X  |   |   |
| S03 — Dormant with accruals   |   | XX | X  |   |   | X  | X  |   |   |
| S04 — Charge waivers          |   | X  |   |   |   |   | XX |   |   |
| S05 — No accrual on CASA      |   | X  |   |   |   | X  | X  |   |   |
| S06 — Overdue CL schedules    |   | XX |   |   |   |   | X  |   |   |
| S07 — Frozen CL               |   | XX |   |   |   | X  | X  |   |   |
| S08 — CL pending liquidation  |   | XX |   |   |   | X  | X  |   |   |
| S09 — LD anomalies            | X | X  |   |   |   | X  | X  |   |   |
| S10 — CL waivers / overrides  |   | X  |   |   |   |   | XX |   |   |
| S11 — SI without charge flags |   | X  |   |   |   |   | XX |   |   |
| S12 — Expired/stalled SI      |   | X  |   |   |   |   | XX |   |   |
| S13 — Unbilled / zero charges |   | X  |   |   |   |   | XX |   |   |
| S14 — IC accruals unliquidated|   | X  | X  |   |   | X  | XX |   |   |
| S15 — FX spread leakage       |   | X  | X  |   |   |   | XX |   |   |
| S16 — GL vs history           | X | X  | X  | X  | X  | X  | X  |   |   |
| S17 — Manual entries risk     |   | X  | XX |   | X  | X  | X  |   |   |
| S18 — Suspense ageing         |   |    | XX |   |   |   |   |   |   |
| S19 — FX revaluation          |   | X  | XX |   |   | X  | X  |   |   |
| S20 — GL–PCEC mapping gaps    | X | X  | X  | X  | X  | X  | X  | X  | X |
| S21 — Maker/checker           | X | X  | X  |   |   | X  | X  |   | X |
| S22 — Inactive users active   | X | X  | X  |   |   | X  | X  |   | X |
| S23 — Toxic role combinations | X | X  | X  | X  | X  | X  | X  |   | X |

### 9.4 Tableau détaillé — rubriques divisionnaires recommandées

| Section | Rubrique(s) COBAC ciblée(s) (recommandation) |
|---|---|
| S01 | `PCEC/201` (crédits clientèle ordinaires), `PCEC/208` (créances diverses), `PCEC/702` (intérêts sur opérations avec clientèle). |
| S02 | Idem S01, avec focus `PCEC/28` (créances en souffrance) si TOD persistante. |
| S03 | `PCEC/251`/`PCEC/252` (comptes à vue, comptes d'épargne), `PCEC/38` (régularisation) pour accruals. |
| S04 | `PCEC/706` (commissions) et `PCEC/702` côté intérêts manqués. |
| S05 | `PCEC/25`/`PCEC/251` côté dépôt, `PCEC/60`/`PCEC/602` côté intérêts versés, `PCEC/702` côté produits. |
| S06 | `PCEC/201` → `PCEC/28`/`PCEC/29` (impayés, douteux), `PCEC/702`. |
| S07 | `PCEC/29` (créances litigieuses), `PCEC/60` si accruals indus. |
| S08 | `PCEC/201`, `PCEC/702`, `PCEC/706`. |
| S09 | `PCEC/1` (interbancaire), `PCEC/201` (corporate), `PCEC/702`. |
| S10 | `PCEC/706`, `PCEC/702`. |
| S11 / S12 / S13 | `PCEC/706` (commissions/frais). |
| S14 | `PCEC/38` (accruals en attente), `PCEC/702`/`PCEC/602` à la liquidation. |
| S15 | `PCEC/706` frais de change, `PCEC/702` produits de change, `PCEC/33` position FX si classe 3 interne. |
| S16 | Toutes classes, focus `PCEC/6`/`PCEC/7`/`PCEC/38`. |
| S17 | `PCEC/6`/`PCEC/7`/`PCEC/38`/`PCEC/5`. |
| S18 | `PCEC/38` (comptes de régularisation / d'attente). |
| S19 | `PCEC/33` (position de change), `PCEC/7`, `PCEC/6`. |
| S20 | Transverse — objet même de la section. |
| S21 / S22 / S23 | Transverse contrôle interne — citation PCEC à titre informatif. |

### 9.5 Dérivation automatique GL → PCEC

Deux stratégies sont admises, **dans l'ordre de préférence** :

1. **Convention de préfixe** — si la banque applique une convention documentée (ex. GL commençant par `1xxxx` ⇒ PCEC/1), l'audit en tire la classe directement. Documentée en §7.Z et à valider via mini-script d'exploration.
2. **Table de correspondance interne** — si une table interne `PCEC_MAPPING` existe (nom à déterminer), elle est utilisée en priorité absolue.

À défaut, la section S20 remonte le problème sans empêcher la production du rapport (BR-34).

### 9.6 Taux de couverture PCEC

L'indicateur `PCEC Coverage` DOIT être calculé et publié dans `GLOBAL INDICATORS` (§8.6) :

```
PCEC Coverage = (Volume LCY mouvementé sur GL mappés)
              / (Volume LCY mouvementé total)  × 100
```

Cible : ≥ 95 % (NFR-13 indirect, BR-21).

### 9.7 Ouverture hors-bilan (classe 9)

Les contrôles sur les engagements hors bilan (garanties données, engagements de financement, etc.) sont **hors scope v1** mais pré-cadrés via S23 (contrôles internes). Une v2 pourra ajouter :
- `S24 — Guarantees expired but active`
- `S25 — Commitment fees not billed`

Ces sections suivront strictement la même grille §7.0.

### 9.8 Limites du mapping

- Le PCEC est **normatif** mais certains comptes spécifiques (ex. auxiliaires techniques FCUBS) n'ont pas d'équivalent strict. Dans ce cas, le script consigne `PCEC/?` et le mappe via `S20`.
- Les fusions / éclatements de classes entre versions du PCEC ne sont pas gérés automatiquement : la version COBAC R-98/01 (1998) fait foi jusqu'à décision contraire documentée.

---

## 10. Risques, hypothèses et limites

### 10.1 Cartographie des risques du livrable

| Id | Risque | Probabilité | Impact | Mitigation |
|---|---|:-:|:-:|---|
| **R-01** | Script qui écrit en base par erreur | Faible | Critique | NFR-20 (interdiction SQL), revue de code systématique, compte SELECT-only. |
| **R-02** | Temps d'exécution > fenêtre d'exploitation | Moyenne | Élevé | Modes `SUMMARY`/`FULL`/`DEEP`, `p_top_n`, filtrage précoce, exécution sur standby/DWH. |
| **R-03** | Faux positifs massifs (mauvaise interprétation d'un flag) | Moyenne | Élevé | Validation par exemple sur périmètre restreint, cross-check avec l'exploration, seuil de matérialité. |
| **R-04** | Faux négatifs (contrôle qui ne détecte pas son cas cible) | Moyenne | Élevé | Tests `§11` sur jeux de données connus, revue par Audit Interne. |
| **R-05** | Divergence de schéma entre environnements (DEV/UAT/PROD) | Moyenne | Moyen | Vérification FR-07 des tables/colonnes critiques au démarrage, warning non bloquant. |
| **R-06** | Fuite d'information PII dans le rapport | Faible | Élevé | `p_mask_pii = 'Y'` par défaut, règles de diffusion du rapport, archivage sécurisé. |
| **R-07** | Interprétation erronée du mapping PCEC | Moyenne | Moyen | Publication de la convention en §9.5, validation par Contrôle de Gestion. |
| **R-08** | Évolution des tables FCUBS (upgrade patch) qui casse le script | Faible | Moyen | Bannière de version Oracle/FCUBS, revue après chaque upgrade majeur. |
| **R-09** | Dépendance à un tarif / taux de référence non documenté | Élevée | Moyen | Hypothèses explicitement déclarées en tête et en `KNOWN LIMITATIONS`. |
| **R-10** | Exécution simultanée perturbant l'intégrité de la photo | Faible | Moyen | Lancement recommandé en dehors des batchs de nuit / après la clôture métier. |
| **R-11** | Surcharge I/O sur instance PROD | Moyenne | Moyen | Privilégier une réplique ; sinon lancer en heures creuses, mode `SUMMARY` d'abord. |
| **R-12** | Version Oracle obsolète non supportée | Faible | Élevé | NFR-30 : vérification explicite ; warning si < 11gR2. |

### 10.2 Hypothèses structurantes

Toutes les hypothèses DOIVENT être **listées** en tête de rapport (`ASSUMPTIONS` dans le bloc PARAMETERS ou dédié).

| Id | Hypothèse | Source |
|---|---|---|
| **A-01** | Oracle 11gR2 ou supérieur. | NFR-30 |
| **A-02** | Droits SELECT sur tous les schémas FCUBS nécessaires. | BR-11 |
| **A-03** | `fcubs.csv` est la **source de vérité** des colonnes. | `bonnes_pratiques.md` §5 |
| **A-04** | La photo comptable est stable pendant l'exécution (pas de DML concurrent massif sur la période). | R-10 |
| **A-05** | La devise locale est `XAF` (zone CEMAC) sauf paramétrage contraire. | §2 |
| **A-06** | Le taux d'intérêt « overdraft standard » utilisé pour l'estimation S01/S02 est un paramètre dérivé ou une valeur hypothèse documentée. | S01 |
| **A-07** | Les accruals IC sont liquidés périodiquement selon un cycle paramétré produit par produit. | S14 |
| **A-08** | Le mapping GL → PCEC utilise la convention de préfixe en `STDTB_BRANCH_PARAMETERS` ou équivalent, à défaut dérivation par premier chiffre du code. | §9.5 |
| **A-09** | Les utilisateurs techniques (`SYSTEM`, `SYS_BATCH_USER`, etc.) sont **exclus** des contrôles SoD (S21–S23). | Convention |
| **A-10** | Les seuils de matérialité par défaut (`100k`, `1M`, `10M` LCY) sont provisoires et seront calibrés avec la Direction Financière. | §6.2.6 |

### 10.3 Limites connues du périmètre v1

- **L-01** — **Pas** de contrôle temps réel : le script opère sur une photo. Les opérations intraday non encore déversées ne sont pas auditées.
- **L-02** — **Pas** de persistance des findings : la comparaison inter-runs est manuelle (`diff` sur rapports). Une v2 pourrait créer une table `RA_FINDINGS_HISTORY`.
- **L-03** — **Pas** d'audit de configuration applicative (paramétrage produit, grille des frais) en profondeur : seuls les effets (données) sont contrôlés.
- **L-04** — **Pas** de contrôle hors bilan (classe 9 PCEC) en v1.
- **L-05** — **Pas** d'audit du module monétique / mobile money / trésorerie non FCUBS.
- **L-06** — Les **impacts monétaires** sont des **estimations** ; elles dépendent d'hypothèses (taux, durée, etc.) explicitées dans chaque contrôle.
- **L-07** — Les **libellés** COBAC officiels sont rattachés par classe/compte principal ; la lecture ultra-fine (sous-compte 5-6 chiffres) reste à la charge de l'utilisateur.
- **L-08** — La **localisation** est verrouillée à `EN` en v1 (NFR-60).
- **L-09** — Le script ne fait **pas** de provisionnement théorique (IFRS 9 / OHADA) ; cela relève d'un autre livrable.
- **L-10** — Les **exceptions de la politique interne** (waivers approuvés par instance) ne sont pas détectables sans une table de référence des approbations, qui sera adressée en §7.Z si présente.

### 10.4 Dépendances externes (organisationnelles et techniques)

| Dépendance | Responsable | Criticité |
|---|---|---|
| Accès lecture sur les schémas FCUBS PROD ou réplique | DSI / DBA | Bloquant |
| Validation des seuils de matérialité | Direction Financière | Bloquant pour interprétation |
| Convention de mapping GL → PCEC | Contrôle de Gestion | Bloquant pour §9 |
| Liste des GL sensibles et GL suspense | Comptabilité / Audit | Bloquant pour S17, S18 |
| Politique de waiver et grille des frais | Commercial / Risk | Souhaitable pour S04, S10, S11 |
| Liste des utilisateurs techniques à exclure | Sécurité SI | Souhaitable pour S21–S23 |
| Taux d'intérêt de pénalité standard | Direction Financière | Souhaitable pour S01, S02, S06 |

Une **check-list de pré-exécution** reprend ces dépendances et est validée avant chaque run officiel (voir §12).

### 10.5 Contraintes réglementaires et éthiques

- Le rapport peut contenir des **données à caractère personnel** (numéros de compte, identifiants client) ; il DOIT être diffusé selon la politique interne de sécurité de l'information et selon les règles CEMAC applicables à la protection des données.
- Les **constats** portés à la connaissance du management doivent être traités **sans diffusion externe** avant analyse : les findings sont des **hypothèses à investiguer**, pas des conclusions définitives.
- Tout usage à des fins disciplinaires d'un constat DOIT faire l'objet d'une **validation contradictoire** avec les parties concernées (utilisateur listé dans un finding SoD, par exemple).

### 10.6 Plan de maîtrise des risques (synthèse)

| Niveau de risque | Actions-clés |
|---|---|
| **R-01 / R-12 (critiques)** | Revue de code systématique, CI manuelle par pair, run contrôlé sur UAT avant PROD. |
| **R-02 / R-04 (élevés)** | Tests (§11), mesure de durée `[PERF]`, mode `SUMMARY` en priorité. |
| **R-03 / R-09 (élevés)** | Calibration progressive des seuils, dialogue Direction Financière. |
| **R-05 / R-08 / R-11 (moyens)** | Vérifications dictionnaire (FR-07), fenêtre d'exécution, observation des temps. |
| **R-06 (élevé mais peu probable)** | Masquage PII activé par défaut, archivage contrôlé. |
| **R-07 / R-10 (moyens)** | Revue Contrôle de Gestion ; exécution hors heures sensibles. |

### 10.7 Registre des exceptions acceptées

Toute **dérogation** à une règle du §5 (NFR) ou §7 (contrôles) DOIT être consignée dans un registre tenu en annexe du présent BRD (section future, ou fichier séparé `exceptions_register.md`), avec :
- date ;
- objet ;
- justification ;
- porteur ;
- durée d'applicabilité ;
- validation (visa).

Aucune exception n'est admise pour :
- NFR-20 (lecture seule),
- NFR-23 (pas de SQL dynamique non borné),
- BR-11 (zéro modification de données).

---

## 11. Plan de test et recette

Le plan de test couvre **quatre niveaux** : compilation, tests fonctionnels, tests non-fonctionnels et recette métier. Chaque niveau DOIT être validé avant passage au suivant.

### 11.1 Niveau 1 — Tests techniques (pré-recette)

| Id | Test | Objectif | Critère de succès |
|---|---|---|---|
| **T1-01** | Compilation du bloc anonyme | Vérifier la syntaxe PL/SQL sur Oracle 11gR2. | Pas d'erreur de compilation, pas de `PLS-*` hors `PLW-05005` admis. |
| **T1-02** | Exécution à vide (périmètre impossible) | `p_date_from := SYSDATE + 1` (aucune donnée). | Rapport généré, toutes sections à 0 finding, status `COMPLETED`. |
| **T1-03** | Exécution sur 1 jour | Borne très courte. | Durée < 30 s, rapport complet, aucune exception non catch. |
| **T1-04** | Exécution sur 1 agence isolée | `p_branch_code := '<BR1>'`. | Seule l'agence ciblée apparaît dans le rapport. |
| **T1-05** | Exécution mode `SUMMARY` | Vérifier la cible NFR-01. | Durée < 2 min ; sortie ≤ 2 Mo. |
| **T1-06** | Exécution mode `FULL` | Photo mensuelle standard. | Durée < 15 min, rapport ≤ 20 Mo. |
| **T1-07** | Exécution mode `DEEP` | Avec top-N élargi. | Durée < 60 min, rapport ≤ 80 Mo. |
| **T1-08** | Lecture seule | Scan statique : aucun `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `COMMIT`, `ROLLBACK`, `CREATE`, `ALTER`, `DROP`. | Zéro occurrence (hors commentaires). |
| **T1-09** | Robustesse : table inexistante forcée | Renommer temporairement une table non critique en UAT. | Warning émis, rapport complet sur les autres sections. |
| **T1-10** | Paramètres invalides | `p_mode := 'BOGUS'`, `p_date_from > p_date_to`. | Erreur `ORA-20001/20002` **en début** de script, message clair. |

### 11.2 Niveau 2 — Tests fonctionnels par contrôle

Pour chaque section `S01..S23`, le test fonctionnel DOIT :
1. **Créer / identifier** un jeu de données (fixture) contenant au moins un cas de chaque type de finding attendu.
2. **Exécuter** le script sur ce jeu.
3. **Vérifier** la présence, la sévérité, le compte et l'impact attendus.

| Id | Contrôle | Cas à tester (au minimum) |
|---|---|---|
| **T2-01** | S01 | 1 compte OD sans TOD (attendu HIGH) ; 1 compte créditeur (attendu absent). |
| **T2-02** | S02 | 1 compte dépassant TOD de 200 % (attendu CRITICAL). |
| **T2-03** | S03 | 1 compte dormant avec accrual ; 1 sans accrual (absent). |
| **T2-04** | S04 | 1 compte avec waiver massif sur composante charge. |
| **T2-05** | S06 | 1 échéance CL en retard de 45 jours (HIGH) ; 1 en retard de 100 jours (CRITICAL). |
| **T2-06** | S07 | 1 prêt CL gelé avec encours. |
| **T2-07** | S11 | 1 SI avec `APPLY_CHG_FLAG = 'N'`. |
| **T2-08** | S12 | 1 SI expirée active. |
| **T2-09** | S16 | 1 GL artificiellement déséquilibré sur un compte temporaire UAT. |
| **T2-10** | S17 | 1 écriture manuelle sur GL de classe 7 hors heures. |
| **T2-11** | S18 | 1 solde suspense > 180 jours. |
| **T2-12** | S21 | 1 transaction `MAKER_ID = CHECKER_ID`. |
| **T2-13** | S22 | 1 utilisateur `EXITFLAG=1` ayant bougé une écriture. |
| **T2-14** | S23 | 1 utilisateur avec combinaison maker+checker+authoriser. |

> Les fixtures sont idéalement préparées sur un environnement **UAT** distinct, avec données masquées. À défaut, identification manuelle de cas réels dans la photo PROD.

### 11.3 Niveau 3 — Tests non-fonctionnels

| Id | Test | Cible |
|---|---|---|
| **T3-01** | Durée mode `SUMMARY` | < 2 min (NFR-01). |
| **T3-02** | Durée mode `FULL` | < 15 min (NFR-02). |
| **T3-03** | Durée mode `DEEP` | < 60 min (NFR-03). |
| **T3-04** | Taille de rapport | < 20 Mo en `FULL`, < 80 Mo en `DEEP` (NFR-08). |
| **T3-05** | Utilisation PGA/SGA | < 100 Mo côté session (NFR-04). |
| **T3-06** | Reproductibilité | Deux runs identiques : rapports identiques hors horodatage / hash. |
| **T3-07** | Portabilité | Exécution OK sur 11gR2, 12c, 19c (si disponibles). |
| **T3-08** | Lisibilité | Validation manuelle : Executive Summary ≤ 60 lignes, findings conformes au §8.4. |
| **T3-09** | Compatibilité clients | Exécution en SQL\*Plus, SQLcl et SQL Developer. |
| **T3-10** | Impact I/O | Pic I/O lu via `v$sesstat` < seuil convenu DBA. |

### 11.4 Niveau 4 — Recette métier

| Id | Test | Responsable | Critère |
|---|---|---|---|
| **T4-01** | Revue Executive Summary | Direction Financière | Compréhensible sans relecture du reste du rapport. |
| **T4-02** | Revue des findings `CRITICAL`/`HIGH` | Audit Interne | 100 % explicables, actionnables, avec recommandation utile. |
| **T4-03** | Validation mapping PCEC | Contrôle de Gestion | Toutes les sections rattachées ; `PCEC Coverage` ≥ 95 %. |
| **T4-04** | Estimation des impacts LCY | Direction Financière | Vraisemblance des montants, pas d'ordres de grandeur aberrants. |
| **T4-05** | Revue des recommandations | Compliance + Risque | Alignées avec la politique interne. |
| **T4-06** | Revue des sections SoD | Sécurité SI + Compliance | Aucun faux positif connu non expliqué. |
| **T4-07** | Comparaison vs exploration | Auteurs du rapport d'exploration | Les indicateurs clés (950, 1620, 662, 179, 281, 51, 782) sont retrouvés. |
| **T4-08** | Ergonomie | Utilisateur final | Lecture fluide, pas d'ambiguïté sur les abréviations. |

### 11.5 Procédure de recette

1. **Dry run** en UAT sur 1 journée.
2. **Full run** en UAT sur 1 mois.
3. **Revue des écarts** avec les parties prenantes.
4. **Calibration des seuils** en fonction des retours.
5. **Run de référence** en PROD (lecture seule, hors heures batch).
6. **Approbation formelle** (§12).
7. **Passage en production récurrente** (planification mensuelle recommandée).

### 11.6 Critères d'acceptation globaux (Go / No-Go)

Go conditionné à la réunion **cumulative** des critères suivants :

- T1-01, T1-02, T1-08, T1-10 : **100 %** OK (non négociable).
- T2-01..T2-14 : **≥ 90 %** OK, avec justification des tests manqués.
- T3-02, T3-04 : dans les cibles ou sous dérogation documentée.
- T4-01, T4-02, T4-03, T4-07 : validés par leurs responsables.
- `KNOWN LIMITATIONS` publié et **revu** avec le management.

Tout No-Go DOIT être accompagné d'une **remediation list** avec échéance et porteur.

### 11.7 Livrables de recette

- **Rapport de recette** — synthèse des tests T1/T2/T3/T4, verdict, signataires.
- **Rapport de run de référence** — le premier rapport validé, archivé comme baseline.
- **Registre des exceptions** — §10.7.
- **Version figée** — `C_SCRIPT_VERSION = 1.0.0` (ou `RC` en attendant l'approbation finale).

### 11.8 Non-régression

Après toute évolution (ajout de section, correction de bug, changement de seuil), un **run comparatif** contre le dernier run de référence DOIT être effectué :
- Les findings `CRITICAL`/`HIGH` doivent rester **stables** sauf changement explicite.
- Les nouveaux findings doivent être **documentés** dans les release notes.
- Les findings disparus doivent être **justifiés** (correction acceptée, bug, changement de seuil).

### 11.9 Outillage recommandé

- **SPOOL** SQL\*Plus avec horodatage nommant le fichier.
- **`diff`** système pour comparer deux rapports (exclure l'en-tête horodaté).
- **Extraction** automatique possible des findings via regex sur `[F-NNN]` et `SEVERITY:`.
- **Archivage** : répertoire `reports/` hors Git, rétention ≥ 24 mois recommandée.

---

## 12. Gouvernance, planning et approbation

### 12.1 Gouvernance

| Rôle | Titulaire (à compléter) | Responsabilités |
|---|---|---|
| **Sponsor** | Direction Financière | Arbitrages stratégiques, priorisation, validation finale du livrable. |
| **Product Owner** | Audit Interne | Porteur fonctionnel du BRD, validation des contrôles et des sévérités. |
| **Tech Lead** | DSI / équipe FCUBS | Revue de code, performance, compatibilité, sécurité technique. |
| **Business Analyst** | Contrôle de Gestion | Mapping PCEC, cohérence COBAC, seuils de matérialité. |
| **Security Officer** | RSSI / Sécurité SI | Validation des sections SoD (S21–S23) et de la gestion PII. |
| **Risk & Compliance** | Risk Manager | Validation recommandations, risque opérationnel, reporting réglementaire. |
| **Développeur** | Équipe projet | Rédaction du script, exécution des tests, correction des anomalies. |
| **Testeur / Recetteur** | Audit Interne + métiers concernés | Exécution des tests T1–T4, verdict Go/No-Go. |

### 12.2 Comitologie

| Instance | Fréquence | Objet |
|---|---|---|
| **Comité de pilotage (COPIL)** | Mensuel pendant le projet, trimestriel ensuite | Avancement, arbitrages, validation jalons. |
| **Comité technique** | Hebdomadaire pendant la rédaction | Revue de code, anomalies, paramétrages. |
| **Revue métier** | Ponctuelle à chaque section §7 finalisée | Validation fonctionnelle des contrôles. |
| **Revue SoD dédiée** | Avant run officiel PROD | Validation S21–S23 avec Sécurité SI et RH. |

### 12.3 Planning indicatif (jalons)

> Les durées sont exprimées en semaines calendaires. Le planning est ajustable selon les disponibilités des parties prenantes.

| Jalon | Livrable | Durée | Dépendance |
|---|---|---|---|
| **J0** | Validation du présent BRD | 1 sem | Revue par toutes parties |
| **J1** | Squelette du script + en-tête + paramètres + helpers + logs | 1 sem | J0 |
| **J2** | Sections S01–S05 (RA comptes & découverts) | 1 sem | J1 |
| **J3** | Sections S06–S10 (crédits CL/LD) | 1 sem | J2 |
| **J4** | Sections S11–S15 (SI, IC, charges, FX) | 1 sem | J3 + mini-scripts §7.Z |
| **J5** | Sections S16–S20 (contrôle comptable + PCEC) | 1 sem | J4 + mini-scripts §7.Z |
| **J6** | Sections S21–S23 (contrôles internes & SoD) | 0,5 sem | J5 |
| **J7** | Agrégations, Executive Summary, KNOWN LIMITATIONS, FOOTER | 0,5 sem | J6 |
| **J8** | Tests T1 + T2 en UAT | 1 sem | J7 |
| **J9** | Tests T3 + T4 + recette | 1 sem | J8 |
| **J10** | Run de référence PROD + approbation formelle | 0,5 sem | J9 |
| **J11** | Mise en production récurrente (run mensuel planifié) | continu | J10 |

Durée cumulée indicative : **~9 semaines**.

### 12.4 Procédure de livraison

1. Rédaction **section par section**, push unitaire (cf. `bonnes_pratiques.md` §8).
2. Ouverture d'une **pull request** sur la branche `claude/continue-revenue-assurance-script-RIaih` (ou équivalente).
3. Revue de code **obligatoire** par le Tech Lead et le Product Owner.
4. Passage des **tests T1** (compilation, lecture seule, bornes d'exécution).
5. Passage des **tests T2** fonctionnels en UAT.
6. Validation COPIL du passage en PROD.
7. Merge sur `main`, tag `v1.0.0`.
8. Exécution **de référence** en PROD ; archivage du rapport dans `reports/` hors Git.
9. Communication du rapport aux destinataires prévus.

### 12.5 Gestion des évolutions (change management)

- Toute évolution DOIT passer par un **ticket** (issue) référencé par son id dans le commit.
- Une **version `MINOR`** est publiée pour l'ajout d'un contrôle.
- Une **version `PATCH`** est publiée pour la correction d'un bug ou l'ajustement d'un seuil documenté.
- Une **version `MAJOR`** est publiée en cas de rupture du format de rapport ou du contrat de paramétrage.
- Chaque livraison s'accompagne de **release notes** succinctes (résumé des findings ajoutés, seuils modifiés, bugs corrigés).

### 12.6 Indicateurs de suivi post-production

| Indicateur | Cible | Fréquence |
|---|---|---|
| Nombre de findings `CRITICAL` par run | ↓ mois après mois | Mensuelle |
| Impact LCY total | ↓ mois après mois | Mensuelle |
| Durée d'exécution `FULL` | ≤ 15 min | Chaque run |
| Nombre d'exceptions catch `[LOG]` | 0 en nominal | Chaque run |
| Taux de couverture PCEC | ≥ 95 % | Chaque run |
| Écarts non résolus > 60 jours | 0 pour `CRITICAL` | Trimestrielle |

### 12.7 Maintenance et support

- **Runbook** : documentation d'exploitation (comment lancer, où récupérer le rapport, qui contacter).
- **Canal support** : référer les anomalies à la DSI / équipe FCUBS.
- **Revue annuelle** : relecture du BRD une fois par an pour cadrer avec l'évolution de FCUBS, du PCEC et de la politique interne.

### 12.8 Critères de retrait / remplacement

Le script peut être **retiré** ou **remplacé** si :
- la banque migre hors de FCUBS ;
- le PCEC COBAC est remplacé par un nouveau référentiel ;
- un outil RA standard (GRC) couvrant équivalemment les §7 est adopté ;
- les besoins métier évoluent au-delà de la capacité du bloc PL/SQL monolithique (nécessitant une refonte en package ou en job ETL).

Dans tous les cas, une **archive** du dernier run de référence DOIT être conservée.

### 12.9 Approbation formelle

Le présent BRD entre en vigueur après signature ou validation documentée des parties suivantes :

| Rôle | Nom / Titulaire | Date | Visa |
|---|---|---|---|
| Sponsor (Direction Financière) | _à compléter_ |   |   |
| Product Owner (Audit Interne) | _à compléter_ |   |   |
| Tech Lead (DSI / FCUBS) | _à compléter_ |   |   |
| Business Analyst (Contrôle de Gestion) | _à compléter_ |   |   |
| RSSI / Sécurité SI | _à compléter_ |   |   |
| Risk & Compliance | _à compléter_ |   |   |

### 12.10 Historique des versions du BRD

| Version | Date | Auteur(s) | Changements |
|---|---|---|---|
| 0.1 | 2026-04-17 | Claude (assistant) | Rédaction initiale section par section, alignée sur le rapport d'exploration et le PCEC COBAC R-98/01. |
| 1.0 | _à venir_ | _après approbation_ | Version validée, figée avant démarrage de la rédaction du script. |

---

## 13. Comptes sensibles et schémas comptables de référence

### 13.1 Définition des « comptes sensibles »

Un **compte sensible** est un compte (client ou GL) dont une anomalie a un impact **disproportionné** au regard de la matérialité habituelle — soit par sa nature comptable (charges/produits, résultat, fonds propres), soit par son usage fonctionnel (suspense, comptes internes, comptes dirigeants), soit par son profil de risque (utilisateurs techniques, mandats spéciaux).

Tout contrôle des §7 DOIT **flagger** tout finding portant sur un compte sensible avec un **bonus de sévérité** (promotion automatique vers la sévérité supérieure).

### 13.2 Registre des comptes sensibles

| Catégorie | Exemples FCUBS / PCEC | Règle d'identification | Niveau |
|---|---|---|---|
| **Comptes de résultat** | GL de classes 6 et 7 | `GL code first digit IN ('6','7')` | HIGH+ |
| **Suspense / attente** | GL PCEC/38, comptes `SUSPENSE_*` | Préfixe GL `38*` ou libellé contenant `SUSP`/`WAIT`/`PENDING`/`CLEARING` | CRITICAL |
| **Comptes internes / bureau** | Comptes internal office, GL internes | `STTM_CUST_ACCOUNT.INTERNAL_FLAG = 'Y'` ou famille dédiée | CRITICAL |
| **Fonds propres / réserves** | PCEC/5 | `GL code first digit = '5'` | CRITICAL |
| **Comptes dirigeants / employés** | Comptes clients dont `CUSTOMER_NO` lié à un `USER_ID` | Jointure référentielle (§7.Z) | CRITICAL |
| **Comptes « exceptionnels »** | Charges/produits exceptionnels, abandons | GL PCEC/67/77 ou libellés `EXCEPT` | HIGH+ |
| **Comptes d'écart / régularisation** | PCEC/38, comptes `DIFF_*`, `ADJ_*` | Préfixe ou libellé | HIGH+ |
| **Comptes de change interne** | Position FX, `PCEC/33`/équivalent interne | Famille GL dédiée | HIGH |
| **Comptes NOSTRO / VOSTRO** | PCEC/1 (interbancaire) | Famille GL dédiée | HIGH |
| **Comptes nouveaux ouverts récemment** | Tout compte ouvert < 30 jours | `STTM_CUST_ACCOUNT.BOOK_DATE > SYSDATE − 30` | MEDIUM+ |
| **Comptes dormants puis réactivés** | Réactivation récente | Événement `DORMANCY_REMOVED` puis activité | HIGH+ |
| **Comptes blocklist/watchlist** | Comptes désignés par Compliance | Liste externe (si fournie) | CRITICAL |

> La **liste exhaustive** des GL sensibles propres à la banque (code exacts et libellés) DOIT être validée avec la Comptabilité, l'Audit Interne et le Contrôle de Gestion, puis documentée dans un fichier de référence `sensitive_accounts_register.md` (à produire). En attendant cette liste figée, le script applique les **règles d'identification heuristiques** ci-dessus.

### 13.3 Schémas comptables de référence (accounting schemas)

Un **schéma comptable** décrit la paire (ou le n-uplet) d'écritures attendues pour une opération donnée. Le script S24 compare les écritures réelles à ces schémas.

> Convention d'écriture ci-dessous : `DR <GL ou famille>` / `CR <GL ou famille>` ; les montants sont en LCY sauf mention contraire.

| Opération | Schéma attendu | Source FCUBS |
|---|---|---|
| **Octroi de crédit** (décaissement) | DR `PCEC/201` (créance client) / CR `PCEC/251` ou `PCEC/252` (compte client) | `CLTB_ACCOUNT_MASTER`, `ACTB_HISTORY` |
| **Remboursement principal** | DR compte client / CR créance client | `CLTB_LIQ`, `ACTB_HISTORY` |
| **Paiement intérêts débiteurs (loan)** | DR compte client / CR `PCEC/702` | `CLTB_LIQ`, `ICTB_LIQ_DETAILS` |
| **Intérêts créditeurs (dépôt rémunéré)** | DR `PCEC/602` / CR compte client | `ICTB_LIQ_DETAILS` |
| **Accrual intérêts perçus (ICNE actif)** | DR `PCEC/38` (régularisation) / CR `PCEC/702` | `ICTB_ACCRUALS_TEMP` |
| **Accrual intérêts versés (ICNE passif)** | DR `PCEC/602` / CR `PCEC/38` | `ICTB_ACCRUALS_TEMP` |
| **Facturation frais tenue de compte** | DR compte client / CR `PCEC/706` | `ICTB_LIQ_DETAILS` |
| **Commission virement** | DR compte client / CR `PCEC/706` | `FTTB_CONTRACT_MASTER`, `ACTB_HISTORY` |
| **SI exécution (transfert)** | DR compte émetteur / CR compte bénéficiaire | `SITB_EXEC_LOG`, `ACTB_HISTORY` |
| **SI frais d'exécution** | DR compte émetteur / CR `PCEC/706` | `SITB_EXEC_LOG` |
| **Change (FX deal clientèle)** | DR compte client devise 1 / CR compte client devise 2 + DR/CR `PCEC/706`/`PCEC/702` pour la marge | `FXTB_CONTRACT_MASTER` |
| **Revalorisation FX** | DR/CR GL FCY / CR/DR `PCEC/7` ou `PCEC/6` (gain/perte de reval) | Batch EOD |
| **Écriture manuelle de régularisation** | Toute combinaison documentée par `TRN_CODE` manuel | `MOTB_CONTRACT_MASTER` |
| **Passage en douteux / provisionnement** | DR `PCEC/29` / CR `PCEC/201` puis DR `PCEC/6` (dotation) / CR `PCEC/29` (provision) | Selon circulaire provisionnement |
| **Apurement compte suspense** | DR/CR `PCEC/38` / CR/DR GL cible final (classe 1/2/6/7) | Écritures d'apurement |

### 13.4 Formalisation du registre des schémas

Pour être exploitable par S24, chaque schéma DOIT être formalisé selon la structure suivante (fichier interne `accounting_schemes_register.md`) :

```
SCHEMA_ID        : LOAN_DISBURSE
TRN_CODE(S)      : LOAN, DISB, CL01
LEG_1  DR_CR=DR  GL_FAMILY=PCEC/201     SIGN=POS
LEG_2  DR_CR=CR  GL_FAMILY=PCEC/251|252 SIGN=POS
AMOUNT_RULE      : LEG_1.LCY = LEG_2.LCY
BRANCH_RULE      : LEG_1.BRANCH = LEG_2.BRANCH
VALUE_DATE_RULE  : LEG_1.VALUE_DATE = LEG_2.VALUE_DATE
```

Le script S24 lit (en mémoire / hard-codé en première itération) l'ensemble de ces schémas et flagge toute écriture qui **ne matche aucun** schéma connu, ou qui **matche un schéma mais viole une règle** (montant, agence, value date).

### 13.5 Méthode de contrôle de conformité des schémas

1. **Énumération** des `TRN_REF_NO` sur la période `[p_date_from, p_date_to]`.
2. **Groupement** des jambes d'un même `TRN_REF_NO` (DR + CR).
3. **Identification** du schéma attendu via `TRN_CODE` + produit.
4. **Vérification** des GL (via préfixe PCEC) et des règles (montants, dates, agences).
5. **Émission** d'un finding par violation (`[F-230/231/232]`).

> En l'absence de schéma formalisé pour un `TRN_CODE` donné, le script **n'émet pas** de violation arbitraire : il émet un finding `INFO` signalant l'absence de schéma référencé, à traiter en v1.x.

### 13.6 Gouvernance du registre

- Le **registre des comptes sensibles** (§13.2) est maintenu par Comptabilité + Audit Interne + Contrôle de Gestion ; il DOIT être revu **trimestriellement**.
- Le **registre des schémas comptables** (§13.3) est maintenu par Comptabilité + équipe FCUBS ; il DOIT être revu **après chaque upgrade** ou changement de paramétrage produit.
- Toute **modification** des registres DOIT être horodatée, versionnée et justifiée.

### 13.7 Articulation avec les contrôles §7

| Registre | Sections §7 directement concernées |
|---|---|
| Comptes sensibles | S01, S04, S10, S11, S17, S18, S20, S21, S22, S23, S29, S30, S31, S32, S33, S34 (promotion automatique de sévérité) |
| Schémas comptables | S24 (principal), S16 (cohérence), S25 (non-compensation), S28 (nature GL) |

---


### Annexe A — Références

- **COBAC R-98/01** — Plan Comptable des Établissements de Crédit de la CEMAC (1998).
- **COBAC R-2009/02** — Dispositif de contrôle interne.
- **Oracle Flexcube Universal Banking** — Core Functional Guide, Data Model Reference.
- **Oracle Database 11gR2** — PL/SQL Language Reference.
- **ISO 20022** — Messaging standard (pour codes devises, pays).
- Documents internes (politique de tarification, grille des frais, politique de dormance, circulaire de provisionnement) — à annexer.

### Annexe B — Artefacts associés

- `bonnes_pratiques.md` — Normes de rédaction du script.
- `explore_revenue_assurance.sql` — Script d'exploration initial.
- `revenue_assurance_exploration_report.txt` — Rapport d'exploration exécuté en base.
- `plan_comptable_cobac.txt` — Référentiel PCEC utilisé.
- `fcubs.csv` — Dictionnaire des tables/colonnes FCUBS (source de vérité).
- `revenue_assurance_and_accounting_audit.sql` — Script final (à produire).

### Annexe C — Glossaire des identifiants

- `BR-NN` — Business Requirement (§3).
- `FR-NN` — Functional Requirement (§4).
- `NFR-NN` — Non-Functional Requirement (§5).
- `SNN` — Section d'audit (§7, S01..S23).
- `F-NNN` — Finding (constat individuel, numérotation séquentielle par section).
- `R-NN` — Risque projet (§10).
- `A-NN` — Hypothèse (§10).
- `L-NN` — Limite connue (§10).
- `T1-NN / T2-NN / T3-NN / T4-NN` — Tests (§11).

---

*Fin du document BRD.*
