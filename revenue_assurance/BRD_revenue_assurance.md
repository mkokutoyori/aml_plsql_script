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
