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
