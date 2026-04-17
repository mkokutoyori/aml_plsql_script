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
