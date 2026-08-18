# BRD — Script PL/SQL d'audit du portefeuille de trésorerie et des opérations sur titres (module MM)

**Business Requirements Document**
**Système audité :** Oracle FLEXCUBE Universal Banking (FCUBS)
**Domaine :** Trésorerie / Portefeuille-titres — module `MM`
**Référentiel :** COBAC — CEMAC (BEAC), PCEC, normes prudentielles COBAC
**Livrable :** `audit_tresorerie_mm.sql` — script PL/SQL unique, exécutable en une seule passe
**Version du document :** 1.0
**Date :** 17/08/2026
**Statut :** Pour validation avant développement

---

## SOMMAIRE

| § | Titre |
|---|---|
| 1 | Contexte et enjeux |
| 2 | Objectifs de la mission et du script |
| 3 | Périmètre |
| 4 | Référentiel réglementaire COBAC / CEMAC |
| 5 | Modèle de données FLEXCUBE mobilisé |
| 6 | Hypothèses, dépendances et limites |
| 7 | Architecture technique du script |
| 8 | Bloc de paramétrage |
| 9 | Spécifications fonctionnelles détaillées (sections S0 à S13) |
| 10 | Catalogue consolidé des tests de contrôle |
| 11 | Spécifications de restitution |
| 12 | Exigences non fonctionnelles |
| 13 | Plan de recette |
| 14 | Gouvernance, livrables et planning |
| 15 | Annexes |

---

# 1. CONTEXTE ET ENJEUX

## 1.1 Contexte de la mission

L'établissement audité est une banque de la zone CEMAC, agréée et supervisée par la
Commission Bancaire de l'Afrique Centrale (COBAC), utilisant Oracle FLEXCUBE Universal
Banking comme progiciel bancaire cœur (core banking system).

La direction de l'audit interne conduit une mission d'audit des activités de la trésorerie.
Cette mission couvre notamment :

- la constitution et la structure du portefeuille de titres et des opérations de marché
  monétaire (placements et emprunts interbancaires, titres publics BTA/OTA, dépôts) ;
- le calcul et le rattachement des intérêts (charges et produits) ;
- la comptabilisation des opérations et son rapprochement avec la gestion ;
- le respect des normes prudentielles COBAC applicables ;
- la qualité du dispositif de contrôle interne entourant la chaîne de traitement.

## 1.2 Constat de départ

Dans l'instance FLEXCUBE de la banque, les opérations de trésorerie et sur titres sont
portées par le module **`MM`** (Money Market). Ce module partage le socle de tables
`LDTB_*` / `LDTM_*` avec le module `LD` (Loans & Deposits) : le discriminant est la colonne
`MODULE` de `LDTB_CONTRACT_MASTER` et de `ACTB_HISTORY`.

Les volumétries relevées lors de l'exploration préalable de la base sont les suivantes :

| Objet | Volumétrie constatée |
|---|---|
| `LDTB_CONTRACT_MASTER` (LD + MM confondus) | 604 contrats |
| `ACTB_HISTORY` — écritures comptables toutes origines | 5 788 417 lignes |
| `ACTB_HISTORY` — écritures `MODULE = 'MM'` | 80 820 lignes |
| Plage temporelle des écritures | 23/05/2022 → 09/04/2026 |
| Devises rencontrées | XAF (locale), USD, EUR, GBP, ZAR, CAD, JPY, XOF, CHF, SGD |
| Agences (`AC_BRANCH`) | 001, 003, 004, 005, 006, 007, 008, 099 |

La faible volumétrie contractuelle (604 contrats) au regard du volume d'écritures
comptables (80 820 écritures `MM`) est un premier point d'attention : elle suggère soit
une forte densité d'événements par contrat (accruals quotidiens), soit un archivage
partiel des contrats. Ce point est traité par le test **TRS-701**.

## 1.3 Enjeux d'audit

| Enjeu | Nature du risque | Impact potentiel |
|---|---|---|
| Exhaustivité du portefeuille | Opérations non enregistrées ou enregistrées hors module | Sous-évaluation des expositions, image infidèle |
| Exactitude des intérêts | Erreur de base de calcul, de taux, de nombre de jours | Résultat erroné, litiges contreparties |
| Séparation des exercices | Accruals non passés, arrêtés incomplets | Résultat mal rattaché, non-conformité PCEC |
| Réalité comptable | Écritures sans contrat sous-jacent, déséquilibres | Fraude, erreur de paramétrage produit |
| Respect des limites | Dépassement des normes de division des risques | Sanction COBAC, injonction |
| Contrôle interne | Absence de séparation maker/checker | Fraude interne, non-conformité R-2016/04 |
| Position de change | Non-couverture des positions en devises | Perte de change, non-conformité R-2003/02 |
| Qualité de données | Référentiels incomplets, dates aberrantes | Reporting réglementaire non fiable |

## 1.4 Positionnement du script dans la démarche d'audit

Le script constitue un **outil de test substantif automatisé, exhaustif et rejouable**. Il
ne se substitue pas au jugement professionnel de l'auditeur : il produit des **indicateurs
et des populations d'anomalies** qui doivent ensuite être :

1. **validées** (confirmation qu'il s'agit bien d'une anomalie et non d'un cas de gestion) ;
2. **quantifiées** (impact financier) ;
3. **remontées** (fiche de constat, recommandation, plan d'action).

Le script travaille **en lecture seule**. Il ne crée aucun objet, ne modifie aucune donnée,
ne pose aucun verrou applicatif.

---

# 2. OBJECTIFS DE LA MISSION ET DU SCRIPT

## 2.1 Objectif général

Fournir à l'auditeur, en **une exécution unique**, un rapport structuré et exploitable
présentant :

1. **la structure du portefeuille** de trésorerie / titres (cartographie complète) ;
2. **les composantes** des contrats (principal, intérêts, commissions, taxes, pénalités) ;
3. **le recalcul indépendant des intérêts** et la comparaison au calcul FLEXCUBE ;
4. **le contrôle de la comptabilisation** et son rapprochement gestion / comptabilité ;
5. **les défaillances constatées**, hiérarchisées par criticité, avec échantillons ;
6. **les indicateurs prudentiels** rapprochés des normes COBAC.

## 2.2 Objectifs opérationnels détaillés

| Réf. | Objectif | Section du script |
|---|---|---|
| OBJ-01 | Recenser et qualifier le paramétrage produit du module MM | S1 |
| OBJ-02 | Cartographier le portefeuille (encours, maturités, devises, contreparties) | S2 |
| OBJ-03 | Contrôler la cohérence des données contractuelles | S3 |
| OBJ-04 | Contrôler les composantes et les échéanciers | S4 |
| OBJ-05 | Recalculer les intérêts et détecter les écarts | S5 |
| OBJ-06 | Contrôler les accruals et la séparation des exercices | S6 |
| OBJ-07 | Contrôler la comptabilisation et le rapprochement gestion/compta | S7 |
| OBJ-08 | Contrôler les liquidations, remboursements et impayés | S8 |
| OBJ-09 | Contrôler les rollovers (renouvellements) | S9 |
| OBJ-10 | Produire les indicateurs prudentiels COBAC | S10 |
| OBJ-11 | Contrôler la séparation des tâches et les habilitations | S11 |
| OBJ-12 | Contrôler la qualité des données et des référentiels | S12 |
| OBJ-13 | Synthétiser les défaillances et produire un score de maîtrise | S13 |

## 2.3 Hors objectifs (out of scope) — version 1

Les éléments suivants sont explicitement **exclus** de la version 1 du script :

- valorisation « mark-to-market » des titres (absence de source de prix dans le périmètre
  de tables disponible) ;
- calcul du ratio de solvabilité / couverture des risques COBAC dans son intégralité
  (requiert la déclaration réglementaire complète, hors base FCUBS) ;
- contrôle des opérations de change au comptant et à terme (module `FX`) ;
- contrôle des dérivés (module `DV`) ;
- reconstitution du reporting CERBER destiné à la COBAC ;
- contrôle des titres détenus pour compte de tiers / conservation.

Ces points sont versés au **backlog v2** (§ 15.5).

---

# 3. PÉRIMÈTRE

## 3.1 Périmètre fonctionnel

Sont dans le périmètre toutes les opérations enregistrées dans FLEXCUBE avec :

- `LDTB_CONTRACT_MASTER.MODULE = 'MM'` ;
- et, en comptabilité, `ACTB_HISTORY.MODULE = 'MM'`.

Cela recouvre typiquement, selon le paramétrage FLEXCUBE :

| Nature d'opération | Sens | Type de produit attendu |
|---|---|---|
| Placement interbancaire / dépôt auprès d'un confrère | Emploi (actif) | Placement |
| Emprunt interbancaire / dépôt reçu d'un confrère | Ressource (passif) | Borrowing |
| Souscription de titres publics (BTA, OTA) | Emploi (actif) | Placement |
| Prise / mise en pension (repo / reverse repo) | Selon sens | Placement / Borrowing |
| Dépôts à terme institutionnels traités en trésorerie | Ressource | Borrowing |

> **Point à confirmer (PAC-01).** Le mapping exact « produit FLEXCUBE → nature d'opération
> COBAC » doit être obtenu auprès de la direction de la trésorerie et du paramétrage. Le
> script produit une **cartographie brute des produits rencontrés** (section S1) afin que
> ce mapping soit établi contradictoirement.

## 3.2 Périmètre temporel

- **Date d'arrêté** (`p_date_arrete`) : paramétrable, valeur par défaut = date la plus
  récente rencontrée dans `ACTB_HISTORY` pour `MODULE = 'MM'`.
- **Période d'analyse** (`p_date_debut` → `p_date_arrete`) : paramétrable, valeur par
  défaut = 24 mois glissants.
- Les tests d'encours (stock) portent sur la position à la date d'arrêté.
- Les tests de flux portent sur la période d'analyse.

## 3.3 Périmètre organisationnel

Toutes les agences (`BRANCH` / `AC_BRANCH`) sont incluses par défaut. Un paramètre
`p_branch_filter` permet de restreindre l'analyse à une agence (valeur `'*'` = toutes).

L'agence `099` concentre 2 567 017 écritures comptables toutes origines (soit 44 % du
total) : elle correspond vraisemblablement à une agence technique / centrale. Ce point est
à confirmer et fait l'objet du test **TRS-708**.

## 3.4 Périmètre technique

| Élément | Valeur |
|---|---|
| SGBD | Oracle Database (version cible ≥ 11gR2) |
| Schéma | Schéma applicatif FCUBS (à préciser au lancement) |
| Droits requis | `SELECT` sur les tables listées au § 5 |
| Mode d'exécution | SQL*Plus / SQLcl / SQL Developer, `SET SERVEROUTPUT ON` |
| Mode d'accès | **Lecture seule stricte** |
| Environnement cible | Copie de production ou environnement de restitution ; à défaut, production **en dehors des heures de traitement de masse (BOD/EOD)** |

---

# 4. RÉFÉRENTIEL RÉGLEMENTAIRE COBAC / CEMAC

## 4.1 Avertissement méthodologique

Les textes COBAC sont publiés par la BEAC. Lors de la rédaction du présent BRD,
**l'accès direct aux fichiers PDF des règlements sur le site de la BEAC n'a pas été
possible** depuis l'environnement de travail (blocage réseau sortant). Les références
ci-dessous sont établies à partir de recherches documentaires et de la connaissance du
corpus ; **elles doivent être confrontées aux textes officiels avant émission du rapport
d'audit définitif**. Chaque référence est assortie d'un niveau de confiance.

## 4.2 Corpus applicable au portefeuille de trésorerie et titres

| Réf. | Intitulé | Portée pour l'audit | Confiance |
|---|---|---|---|
| **COBAC R-2003/03** | Comptabilisation et traitement prudentiel des opérations sur titres effectuées par les établissements de crédit | **Texte pivot** : définition des titres, catégories comptables, règles d'évaluation et de comptabilisation, traitement prudentiel | Élevée (intitulé confirmé) |
| **COBAC R-2003/02** | Surveillance des positions de change | Limites de position de change par devise et globale, en % des fonds propres nets | Élevée (intitulé confirmé) |
| **COBAC R-2010/01** | Couverture des risques des établissements de crédit | Ratio de couverture des risques (solvabilité) ; les titres pondérés y entrent | Élevée |
| **COBAC R-2010/02** | Division des risques des établissements de crédit | Rapport max. 45 % FPN par bénéficiaire ; somme des grands risques ≤ 800 % FPN ; grand risque = exposition > 15 % FPN | Élevée |
| **COBAC R-2020/01** | Modification de R-2010/02 | Abaissement progressif du plafond par bénéficiaire : 40 % (2021), 35 % (2022), **25 % (à compter de 2023)** | Élevée |
| **COBAC R-2016/03** | Fonds propres nets des établissements de crédit | Définition et mode de calcul des FPN (dénominateur de toutes les normes) | Élevée |
| **COBAC R-2016/04** | Contrôle interne dans les établissements de crédit et les holdings financières (08/03/2016) | Séparation des fonctions, piste d'audit, contrôle des opérations de marché, limites internes | Élevée |
| **COBAC R-2018/01** | Classification, comptabilisation et provisionnement des créances | Créances en souffrance, déclassement, provisionnement — applicable aux créances interbancaires impayées | Élevée |
| **Rapport de liquidité COBAC** | Norme : ≥ 100 % (disponibilités à un mois / exigibilités à un mois) | Les placements MM ≤ 1 mois sont des disponibilités ; les emprunts MM ≤ 1 mois des exigibilités | Élevée |
| **Coefficient de transformation à long terme** | Norme : ≥ 50 % (emplois > 5 ans / ressources > 5 ans) | Contribution des titres longs (OTA) | Élevée |
| **PCEC — Plan Comptable des Établissements de Crédit (CEMAC/COBAC)** | Cadre comptable, nomenclature des comptes | Classe 1 (trésorerie et interbancaire), classe 3 (opérations sur titres et diverses), classes 6/7 (charges et produits) | Élevée |
| **Règlement du marché des titres publics CEMAC (BEAC), en vigueur depuis le 20/12/2019** | Organisation du marché, BTA / OTA, adjudications, SVT | Caractéristiques des titres publics détenus (BTA : 13/26/52 semaines, VN 1 MFCFA ; OTA : 2 à 10 ans) | Élevée |

## 4.3 Traduction des exigences réglementaires en règles de test

### 4.3.1 Classification et comptabilisation des titres (R-2003/03, PCEC)

Le règlement distingue classiquement les catégories suivantes de titres, chacune assortie
d'un régime d'évaluation propre :

| Catégorie | Intention de détention | Régime d'évaluation attendu | Traduction en test |
|---|---|---|---|
| Titres de transaction | Détention courte, marché liquide | Prix de marché ; variations en résultat | TRS-105, TRS-106 |
| Titres de placement | Détention non déterminée | Coût d'acquisition ; provision pour moins-value latente ; étalement décote/prime | TRS-107, TRS-505 |
| Titres d'investissement | Détention jusqu'à l'échéance | Coût amorti ; étalement de la décote/prime sur la durée résiduelle | TRS-108, TRS-506 |
| Titres de participation / activité de portefeuille | Détention durable | Hors périmètre MM (module `SE`/`GL`) | Exclu |

**Règles de test dérivées :**

- **RG-01** — Tout contrat MM assimilable à un titre doit être rattaché à une catégorie
  comptable identifiable via son produit (`LDTB_CONTRACT_MASTER.PRODUCT`) et son schéma
  comptable. Un produit non rattachable = **défaillance de paramétrage (MAJEUR)**.
- **RG-02** — Un transfert entre catégories (changement de produit sur un même sous-jacent)
  doit être exceptionnel et justifié. Toute occurrence est signalée.
- **RG-03** — L'étalement de la décote/prime doit produire un flux d'accrual régulier sur
  la durée résiduelle. Une absence d'accrual sur un contrat non échu porteur d'intérêt =
  **défaillance (CRITIQUE)**.
- **RG-04** — La comptabilisation doit être équilibrée par référence d'événement
  (`TRN_REF_NO` + `EVENT_SR_NO`) : ΣDébits = ΣCrédits en contre-valeur locale.

### 4.3.2 Division des risques (R-2010/02 modifié par R-2020/01)

- **RG-05** — Pour chaque contrepartie (`COUNTERPARTY`), l'exposition MM cumulée rapportée
  aux fonds propres nets ne doit pas excéder le plafond en vigueur (**25 %** depuis 2023).
- **RG-06** — Toute contrepartie dont l'exposition dépasse **15 % des FPN** est un
  « grand risque » et doit être identifiée comme telle.
- **RG-07** — La somme des grands risques ne doit pas excéder **800 % des FPN**.

> **Limite structurelle.** Les fonds propres nets ne sont pas disponibles dans les tables
> FCUBS du périmètre. Le script les reçoit en **paramètre d'entrée** (`p_fpn_xaf`), à
> renseigner à partir de la dernière déclaration COBAC validée. À défaut de valeur
> renseignée, le script produit les **expositions brutes et leur concentration relative**
> (part de chaque contrepartie dans l'encours total) et signale explicitement que les
> ratios réglementaires n'ont pas pu être calculés.

### 4.3.3 Positions de change (R-2003/02)

- **RG-08** — Le script produit la position nette par devise issue des opérations MM
  (emplois − ressources), en contre-valeur XAF, et la rapporte aux FPN si renseignés.
- **RG-09** — Les seuils par devise et global sont **paramétrables** (`p_seuil_change_devise`,
  `p_seuil_change_global`) et doivent être alignés sur le texte officiel avant émission
  du rapport.

### 4.3.4 Liquidité et transformation

- **RG-10** — Ventilation de l'encours MM par bandes de maturité résiduelle :
  ≤ 1 mois / 1-3 mois / 3-6 mois / 6-12 mois / 1-2 ans / 2-5 ans / > 5 ans.
- **RG-11** — Séparation emplois (placements) / ressources (emprunts) par bande, afin
  d'alimenter le rapport de liquidité (≥ 100 %) et le coefficient de transformation (≥ 50 %).

### 4.3.5 Créances en souffrance (R-2018/01)

- **RG-12** — Toute échéance MM échue et non réglée (`LDTB_CONTRACT_LIQ.AMOUNT_DUE >
  AMOUNT_PAID`) doit être identifiée, avec ancienneté (`OVERDUE_DAYS`).
- **RG-13** — Les seuils d'ancienneté de déclassement (30 / 90 / 180 / 360 jours) sont
  paramétrables et servent au classement en criticité.

### 4.3.6 Contrôle interne (R-2016/04)

- **RG-14** — Toute écriture comptable MM doit présenter un initiateur (`USER_ID`) et un
  valideur (`AUTH_ID`) **distincts**. `USER_ID = AUTH_ID` = **rupture de séparation des
  tâches (CRITIQUE)**, sauf comptes techniques automatiques identifiés.
- **RG-15** — Les utilisateurs techniques (`SYSTEM`, batch) doivent être recensés et leur
  usage circonscrit aux événements automatiques (accruals, EOD).
- **RG-16** — La piste d'audit doit être complète : tout contrat doit être traçable de
  l'événement de saisie jusqu'à l'écriture comptable.

---

# 5. MODÈLE DE DONNÉES FLEXCUBE MOBILISÉ

## 5.1 Vue d'ensemble de la chaîne de traitement

```
   PARAMÉTRAGE                CONTRAT                        COMPTABILITÉ
   -----------                -------                        ------------
LDTM_PRODUCT_MASTER  ──►  LDTB_CONTRACT_MASTER  ──────────►  ACTB_HISTORY
LDTM_PRODUCT_DFLT_          │  (MODULE='MM')                   (MODULE='MM')
  SCHEDULES                 │                                       │
LDTM_PRODUCT_LIQ_ORDER      ├─► LDTB_CONTRACT_PREFERENCE           │
LDTM_PRODUCT_ROLLOVER       ├─► LDTB_CONTRACT_SCHEDULES            │
LDTM_BRANCH_PARAMETERS      ├─► LDTB_CONTRACT_ICCF_DETAILS         │
                            ├─► LDTB_CONTRACT_ICCF_CALC   ─────────┤
                            ├─► LDTB_CONTRACT_ACCRUAL_HISTORY ─────┤
                            ├─► LDTB_CONTRACT_LIQ                  │
                            ├─► LDTB_CONTRACT_LIQ_SUMMARY          │
                            ├─► LDTB_CONTRACT_BALANCE              │
                            ├─► LDTB_CONTRACT_ROLLOVER             │
                            ├─► LDTB_CONTRACT_ROLL_INT_RATES       │
                            ├─► LDTB_CONTRACT_SWIFT_MESSAGE        │
                            └─► LDTB_CONTRACT_CONTROL              │
                                                                   ▼
   RÉFÉRENTIELS                                              GLTB_GL_BAL
   ------------                                              STTB_ACCOUNT
STTM_CUSTOMER (contrepartie)                                 RVTB_ACC_REVAL
STTM_CUSTOMER_CAT                                            CYTB_RATES_HISTORY
GETM_FACILITY (lignes)                                       CYTB_DERIVED_RATES_HISTORY
CSTM_PRODUCT / CSTB_AMOUNT_TAG
STTM_TRN_CODE
SMTB_USER / SMTB_USER_ROLE / SMTB_ROLE_*
```

## 5.2 Tables cœur — description et usage

### 5.2.1 `LDTB_CONTRACT_MASTER` — En-tête de contrat (604 lignes)

Table pivot du portefeuille. Un enregistrement par contrat et par version
(`CONTRACT_REF_NO`, `VERSION_NO`, `EVENT_SEQ_NO`).

| Colonne | Type | Usage dans l'audit |
|---|---|---|
| `CONTRACT_REF_NO` | VARCHAR2 | Identifiant du contrat — clé de rapprochement avec `ACTB_HISTORY.TRN_REF_NO` |
| `VERSION_NO`, `EVENT_SEQ_NO` | NUMBER | Versioning — **impose de ne retenir que la version courante** (max) |
| `MODULE` | VARCHAR2 | **Filtre du périmètre : `= 'MM'`** |
| `BRANCH` | VARCHAR2 | Agence de booking |
| `PRODUCT`, `PRODUCT_TYPE` | VARCHAR2/CHAR | Nature de l'opération (placement / emprunt), rattachement à la catégorie comptable |
| `COUNTERPARTY` | VARCHAR2 | Contrepartie — jointure `STTM_CUSTOMER.CUSTOMER_NO` — base de la division des risques |
| `CURRENCY` | VARCHAR2 | Devise du contrat — position de change |
| `AMOUNT`, `LCY_AMOUNT` | NUMBER | Nominal en devise / contre-valeur locale |
| `ORIGINAL_FACE_VALUE` | NUMBER | Valeur nominale d'origine (titres) — écart avec `AMOUNT` = décote/prime |
| `BOOKING_DATE`, `VALUE_DATE`, `TRADE_DATE` | DATE | Dates clés — contrôle d'antériorité et de séquencement |
| `ORIGINAL_START_DATE` | DATE | Date de départ d'origine (avant rollovers) |
| `MATURITY_TYPE`, `MATURITY_DATE`, `TENOR` | VARCHAR2/DATE/NUMBER | Échéance et durée — bandes de maturité, liquidité |
| `MAIN_COMP`, `MAIN_COMP_RATE`, `MAIN_COMP_AMOUNT`, `MAIN_COMP_SPREAD`, `MAIN_COMP_RATE_CODE` | — | Composante principale d'intérêt : taux, montant, spread |
| `BASE_INDEX_RATE` | NUMBER | Taux d'index de référence |
| `CONTRACT_STATUS`, `CONTRACT_DERIVED_STATUS`, `USER_DEFINED_STATUS` | — | Statut du contrat (actif, liquidé, en attente…) |
| `ICCF_STATUS`, `SETTLEMENT_STATUS`, `TAX_STATUS`, `BROKERAGE_STATUS`, `CHARGE_STATUS` | CHAR | Statuts des sous-systèmes — un statut non abouti est une anomalie de traitement |
| `ROLLOVER_ALLOWED`, `ROLLOVER_COUNT`, `ROLLOVER_INDICATOR`, `PARENT_CONTRACT_REF_NO` | — | Chaînage des renouvellements |
| `DEALER`, `DEALING_METHOD`, `BROKER_CODE` | VARCHAR2 | Opérateur de marché, canal, courtier — contrôle interne |
| `CREDIT_LINE` | VARCHAR2 | Ligne de crédit consommée — jointure `GETM_FACILITY` |
| `INT_PERIOD_BASIS` | CHAR | Base de la période d'intérêt (inclusion/exclusion des bornes) |
| `EXPOSURE_CATEGORY`, `RISK_FREE_EXP_AMOUNT` | — | Catégorisation risque |
| `AUTO_PROV_REQD`, `PROV_CCY_TYPE` | VARCHAR2 | Provisionnement automatique |
| `REJ_REASON` | VARCHAR2 | Motif de rejet éventuel |
| `INTERFACE_REF_NO`, `EXTERNAL_REF_NO` | VARCHAR2 | Origine externe (interface) — contrôle d'exhaustivité |

### 5.2.2 `LDTB_CONTRACT_MASTER_FCC` — Table miroir

Structure identique à `LDTB_CONTRACT_MASTER`.

> **Hypothèse H-01 (à valider).** Dans FCUBS, les tables suffixées `_FCC` hébergent une
> image de travail / non autorisée (work-in-progress) des contrats. Le script ne présume
> pas de la sémantique exacte : il **compare** les deux tables et signale :
> - les contrats présents dans `_FCC` et absents de la table principale (contrats en
>   instance, potentiellement non autorisés) ;
> - les contrats dont les montants, dates ou statuts diffèrent entre les deux tables.
>
> Le résultat de ce test (TRS-303) sert lui-même à **qualifier la sémantique** de la table
> miroir avec l'équipe applicative.

Tables miroir concernées : `LDTB_CONTRACT_MASTER_FCC`, `LDTB_CONTRACT_PREFERENCE_FCC`,
`LDTB_CONTRACT_SCHEDULES_FCC`, `LDTB_CONTRACT_ICCF_CALC_FCC`,
`LDTB_CONTRACT_ICCF_DETAILS_FCC`, `LDTB_CONTRACT_LIQ_FCC`,
`LDTB_CONTRACT_LIQ_SUMMARY_FCC`, `LDTB_CONTRACT_BALANCE_FCC`, `LDTM_PRODUCT_MASTER_FCC`.

### 5.2.3 `LDTB_CONTRACT_ICCF_CALC` — Détail du calcul d'intérêt

Table centrale pour le **recalcul indépendant des intérêts**.

| Colonne | Usage |
|---|---|
| `CONTRACT_REF_NO`, `COMPONENT` | Clé : contrat + composante (ex. `MAIN_INT`) |
| `START_DATE`, `END_DATE`, `SCHEDULE_DATE` | Période de calcul |
| `BASIS_AMOUNT` | Assiette de calcul |
| `RATE` | Taux appliqué (en %) |
| `NO_OF_DAYS` | Nombre de jours — **type VARCHAR2** ⇒ conversion sécurisée obligatoire |
| `CALCULATED_AMOUNT` | Montant calculé par FLEXCUBE — **valeur à challenger** |
| `ICCF_CALC_METHOD` | Méthode de calcul |
| `DAILY_AVERAGE_AMOUNT` | Encours moyen journalier (méthodes en moyenne) |
| `CURRENCY`, `PRODUCT` | Contexte |

**Formule de recalcul de référence :**

```
    Intérêt_recalculé = BASIS_AMOUNT × (RATE / 100) × (NO_OF_DAYS / DÉNOMINATEUR)
```

Le `DÉNOMINATEUR` dépend de la base de calcul (day count convention) : 360, 365 ou 366.
La base n'étant pas portée explicitement par `LDTB_CONTRACT_ICCF_CALC`, le script applique
une **détection empirique** :

1. calcul des trois montants candidats (base 360, 365, 366) ;
2. identification de la base qui minimise l'écart au `CALCULATED_AMOUNT` ;
3. si l'écart minimal reste supérieur à la tolérance (`p_tol_interet`), le contrat est
   classé en **écart de calcul** ;
4. la base retenue est comparée à `LDTB_CONTRACT_ROLL_INT_RATES.INT_BASIS` lorsque cette
   information est disponible, afin de détecter les **incohérences de base**.

Cette approche a une double vertu d'audit : elle valide le montant **et** documente la
convention effectivement appliquée par le système, contrat par contrat.

### 5.2.4 `LDTB_CONTRACT_ICCF_DETAILS` — Situation cumulée par composante

| Colonne | Usage |
|---|---|
| `COMPONENT`, `COMPONENT_CURRENCY` | Composante et devise |
| `ACCRUAL_REQUIRED` | Indique si la composante doit faire l'objet d'accruals |
| `PAYMENT_METHOD` | Méthode de paiement (bearing / discounted / true discounted) |
| `PREVIOUS_ACCRUAL_TO_DATE` | Date du dernier accrual — **contrôle de fraîcheur** |
| `TILL_DATE_ACCRUAL` | Cumul des accruals à date — **rapprochement avec l'historique** |
| `CURRENT_NET_ACCRUAL` | Accrual net courant |
| `LAST_LIQUIDATION_DATE`, `TOTAL_AMOUNT_LIQUIDATED`, `LATEST_LIQUIDATED_SCHEDULE` | Situation des liquidations |
| `UPFRONT_PROFIT_BOOKED` | Profit comptabilisé d'avance (titres décotés) |

### 5.2.5 `LDTB_CONTRACT_ACCRUAL_HISTORY` — Historique des accruals

| Colonne | Usage |
|---|---|
| `CONTRACT_REF_NO`, `COMPONENT`, `EVENT_SEQ_NO` | Clé |
| `TRANSACTION_DATE`, `VALUE_DATE`, `ACCRUAL_TO_DATE` | Dates — séparation des exercices |
| `NET_ACCRUAL`, `TILL_DATE_ACCRUAL`, `OUTSTANDING_ACCRUAL` | Montants |
| `TYPE_OF_ACCRUAL` | Type (normal, catch-up…) |
| `ACC_ENTRY_PASSED` | **Indicateur clé : l'écriture comptable a-t-elle été passée ?** |
| `ACCRUAL_REF_NO`, `PRODUCT_ACCRUAL_REF_NO` | Référence du traitement d'accrual |
| `OVERDUE_INTEREST`, `AMOUNT_PREPAID` | Intérêts de retard, remboursements anticipés |
| `USER_DEFINED_STATUS` | Statut du contrat au moment de l'accrual |

`ACC_ENTRY_PASSED ≠ 'Y'` sur un accrual comptabilisable est une **défaillance CRITIQUE**
(produit/charge constaté en gestion mais absent de la comptabilité).

### 5.2.6 `LDTB_CONTRACT_SCHEDULES` — Échéanciers

| Colonne | Usage |
|---|---|
| `COMPONENT`, `SCHEDULE_TYPE` | Composante et type d'échéance (P = principal, I = intérêt, R = révision…) |
| `START_DATE`, `NO_OF_SCHEDULES`, `FREQUENCY`, `FREQUENCY_UNIT` | Définition de la série |
| `AMOUNT` | Montant de l'échéance |
| `BASE_INDEX_RATE`, `LCY_EQVT_FOR_INDEX_LOANS` | Indexation |

### 5.2.7 `LDTB_CONTRACT_LIQ` et `LDTB_CONTRACT_LIQ_SUMMARY` — Liquidations

`LDTB_CONTRACT_LIQ` : `AMOUNT_DUE`, `AMOUNT_PAID`, `OVERDUE_DAYS`, `TAX_PAID`, `INT_PREPAY`
par composante et par événement → **détection des impayés**.

`LDTB_CONTRACT_LIQ_SUMMARY` : `VALUE_DATE`, `TOTAL_PAID`, `TOTAL_PREPAID`,
`PREPAYMENT_PENALTY_RATE`, `PREPAYMENT_PENALTY_AMOUNT`, `DISCOUNT_RATE`,
`LIQUIDATED_FACE_VALUE`, `PAYMENT_STATUS`, `OLD_MATURITY_DATE`, `NEW_MATURITY_DATE`,
`REJ_REASON` → **contrôle des remboursements anticipés, pénalités et prorogations**.

### 5.2.8 `LDTB_CONTRACT_BALANCE` — Encours

`PRINCIPAL_OUTSTANDING_BAL`, `CURRENT_FACE_VALUE` → encours de référence pour la
cartographie et le rapprochement avec la comptabilité.

### 5.2.9 `LDTB_CONTRACT_ROLLOVER` / `LDTB_CONTRACT_ROLL_INT_RATES` — Renouvellements

`ROLLOVER_AMT`, `ROLLOVER_TYPE`, `ROLLOVER_AMOUNT_TYPE`, `MATURITY_TYPE`, `MATURITY_DATE`,
`LIQUIDATE_OD_SCHEDULES`, `APPLY_TAX`, `ROLL_INST_STATUS`, `REF_RATE` ;
et pour les taux : `RATE`, `SPREAD`, `MARGIN`, `RATE_TYPE`, `RATE_CODE`, `INT_BASIS`,
`ROLL_RESET_TENOR`.

Enjeu d'audit : le rollover systématique peut masquer une **immobilisation durable** d'un
placement présenté comme court terme (impact liquidité et transformation).

### 5.2.10 `LDTB_CONTRACT_PREFERENCE` — Préférences contractuelles

Colonnes d'intérêt : `CONTRACT_SCHEDULE_TYPE`, `LIQ_BACK_VALUED_SCHEDULES`,
`PRINCIPAL_LIQUIDATION`, `HOLIDAY_CCY`, `IGNORE_HOLIDAYS`, `SCHEDULE_MOVEMENT`,
`MOVE_ACROSS_MONTH`, `AMORTISATION_TYPE`, `STATUS_CONTROL`, `ROUNDING_REQD`,
`CCY_ROUND_RULE`, `CCY_DECIMALS`, `CCY_ROUND_UNIT`, `MAX_INT_PAY_PERIOD`,
`MAX_RATE_REV_PERIOD`, `VERIFY_FUNDS*`, `TRACK_RECEIVABLE_*`.

Enjeu : les règles d'arrondi et de décalage de jours fériés expliquent une partie des
écarts de recalcul d'intérêt ; elles doivent être documentées avant conclusion.

### 5.2.11 `LDTB_CONTRACT_CONTROL` — Traçabilité

`CONTRACT_REF_NO`, `PROCESS_CODE`, `ENTRY_BY`, `ENTRY_TIME` → **piste d'audit** :
qui a agi, quand, sur quel processus.

### 5.2.12 `LDTB_CONTRACT_SWIFT_MESSAGE` — Confirmations

`SWIFT_COMPATIBILITY`, `CONFIRMATION_INDICATOR`, `VALUE_DATE`, `INTEREST_RATE`,
`NEXT_INTEREST_DATE`, `NEXT_INTEREST_AMOUNT`, `TOTAL_INTEREST_AMOUNT`,
`MATURITY_INTEREST_AMOUNT`, `CONTRACT_BALANCE`, `COMMON_REF_NO`.

Enjeu : rapprochement **confirmation de marché ↔ contrat enregistré** — contrôle clé du
back-office trésorerie (détection des deals fictifs ou non confirmés).

### 5.2.13 Tables de paramétrage produit

| Table | Usage |
|---|---|
| `LDTM_PRODUCT_MASTER` | Paramétrage produit : `ACCRUAL_FREQUENCY`, `CAPITALISE`, `MIN_TENOR`/`STD_TENOR`/`MAX_TENOR`/`TENOR_UNIT`, `LIQUIDATION_MODE`, `PAYMENT_METHOD`, `NORMAL_RATE_VARIANCE`, `MAXIMUM_RATE_VARIANCE`, `PREPAYMENT_PENALTY`, `TRACK_ACCRUED_INTEREST`, `FORWARD_DATING_ALLOWED`, `BLOCK_PRODUCT`, `INT_PERIOD_BASIS`, `DISC_ACCR_APPLICABLE`, `BOOK_UNEARNED_INTEREST`, `AUTO_PROV_REQUIRED`, `REVALUATION_*` |
| `LDTM_PRODUCT_DFLT_SCHEDULES` | Échéanciers par défaut |
| `LDTM_PRODUCT_LIQ_ORDER` | Ordre d'imputation des règlements — enjeu : imputation des impayés |
| `LDTM_PRODUCT_ROLLOVER` | Règles de renouvellement (`AUTO_MAN_ROLLOVER`, `ROLLOVER_WITH_INTEREST`, `DEDUCT_TAX_ON_ROLLOVER`) |
| `LDTM_BRANCH_PARAMETERS` | `PROCESS_TILL`, `ACCRUAL_LEVEL`, `TAX_COMPUTATION_BASIS`, `RESIDUAL_AMOUNT`, `REPORTING_CCY`, `APY_CALCULATION` + maker/checker du paramétrage |
| `CSTM_PRODUCT` | Description produit, dates de début/fin, statut d'autorisation, maker/checker |
| `CSTB_AMOUNT_TAG` | Sémantique des `AMOUNT_TAG` comptables |

### 5.2.14 Tables comptables

| Table | Usage |
|---|---|
| `ACTB_HISTORY` | Écritures comptables (5,79 M lignes ; 80 820 pour `MODULE='MM'`). Colonnes clés : `TRN_REF_NO`, `EVENT`, `EVENT_SR_NO`, `AC_BRANCH`, `AC_NO`, `AC_CCY`, `DRCR_IND`, `TRN_CODE`, `AMOUNT_TAG`, `FCY_AMOUNT`, `EXCH_RATE`, `LCY_AMOUNT`, `TRN_DT`, `VALUE_DT`, `MODULE`, `PRODUCT`, `USER_ID`, `AUTH_ID`, `RELATED_CUSTOMER`, `RELATED_ACCOUNT`, `RELATED_REFERENCE`, `FINANCIAL_CYCLE`, `PERIOD_CODE`, `CUST_GL`, `CATEGORY`, `TYPE`, `BATCH_NO`, `EXTERNAL_REF_NO` |
| `ACTB_ACCBAL_HISTORY` | Historique des soldes de comptes |
| `ACTB_VD_BAL` | Soldes en date de valeur |
| `GLTB_GL_BAL` | Balances GL par période : `DR_BAL_LCY`, `CR_BAL_LCY`, `DR_MOV_LCY`, `CR_MOV_LCY`, `OPEN_*` |
| `STTB_ACCOUNT` | Référentiel comptes/GL : `AC_GL_NO`, `AC_OR_GL`, `GL_CATEGORY`, `AC_GL_CCY`, `AC_STAT_DORMANT`, `AC_STAT_FROZEN`, `GL_STAT_BLOCKED`, `AC_GL_REC_STATUS` |
| `RVTB_ACC_REVAL` | Réévaluation de change : `ACCOUNT_BALANCE`, `OLD_LCY_EQUIVALENT`, `NEW_LCY_EQUIVALENT`, `NEW_RATE`, `PNL_ACCOUNT` |
| `CYTB_RATES_HISTORY` / `CYTB_DERIVED_RATES_HISTORY` | Historique des cours — contrôle des taux de conversion appliqués |
| `STTM_TRN_CODE` | Référentiel des codes transaction |

### 5.2.15 Tables de contrôle interne et habilitations

`SMTB_USER`, `SMTB_USER_ROLE`, `SMTB_ROLE_MASTER`, `SMTB_ROLE_DETAIL`,
`SMTB_ROLE_FUNC_LIMIT_DETAIL`, `SMTB_ROLE_FUNC_LIMIT_CUSTOM`, `SMTB_USER_DISABLE`,
`SMTB_SMS_LOG`, `SMTB_SMS_ACTION_LOG`, `SMTB_USERLOG_DETAILS`, `SMTB_FUNCTION_DESCRIPTION`.

### 5.2.16 Tables de traitement automatique (EOD/BOD)

`LDTB_AUTOMATIC_PROCESS_MASTER`, `LDTB_AUTOMATIC_PROCESS_QUEUE`,
`LDTB_AUTO_FUNCTION_DETAILS`, `LDTB_AUTO_FUNCTION_SETUP`, `LDTB_PERIODIC_ACCRUAL_DATE`,
`LDTB_COMPUTATION_HANDOFF`.

Enjeu : détecter les **traitements de fin de journée en échec ou incomplets**, cause
première des accruals manquants.

## 5.3 Clés de rapprochement

| Rapprochement | Clé |
|---|---|
| Contrat ↔ Comptabilité | `LDTB_CONTRACT_MASTER.CONTRACT_REF_NO` = `ACTB_HISTORY.TRN_REF_NO` |
| Contrat ↔ Contrepartie | `LDTB_CONTRACT_MASTER.COUNTERPARTY` = `STTM_CUSTOMER.CUSTOMER_NO` |
| Contrat ↔ Produit | `LDTB_CONTRACT_MASTER.PRODUCT` = `LDTM_PRODUCT_MASTER.PRODUCT` = `CSTM_PRODUCT.PRODUCT_CODE` |
| Contrat ↔ Ligne | `LDTB_CONTRACT_MASTER.CREDIT_LINE` ↔ `GETM_FACILITY.LINE_CODE` |
| Écriture ↔ Compte/GL | `ACTB_HISTORY.AC_NO` = `STTB_ACCOUNT.AC_GL_NO` |
| Accrual ↔ Écriture | `LDTB_CONTRACT_ACCRUAL_HISTORY` (`CONTRACT_REF_NO`, `EVENT_SEQ_NO`) ↔ `ACTB_HISTORY` (`TRN_REF_NO`, `EVENT_SR_NO`, `EVENT` ∈ accrual) |
| Rollover parent/enfant | `PARENT_CONTRACT_REF_NO` → `CONTRACT_REF_NO` |

## 5.4 Précaution majeure : le versioning

`LDTB_CONTRACT_MASTER` est versionnée (`VERSION_NO`, `EVENT_SEQ_NO`). **Tout comptage ou
sommation effectué sans réduction à la version courante produit un résultat faux.**

Le script matérialise systématiquement la vue « contrat courant » :

```sql
    WITH mm_courant AS (
      SELECT m.*
      FROM   LDTB_CONTRACT_MASTER m
      WHERE  m.MODULE = 'MM'
      AND    (m.CONTRACT_REF_NO, m.VERSION_NO, m.EVENT_SEQ_NO) IN (
               SELECT x.CONTRACT_REF_NO, MAX(x.VERSION_NO),
                      MAX(x.EVENT_SEQ_NO) KEEP (DENSE_RANK LAST ORDER BY x.VERSION_NO)
               FROM   LDTB_CONTRACT_MASTER x
               WHERE  x.MODULE = 'MM'
               GROUP  BY x.CONTRACT_REF_NO)
    )
```

Le test **TRS-301** contrôle par ailleurs la cohérence du versioning lui-même
(trous de séquence, versions multiples avec même `EVENT_SEQ_NO`).

---

# 6. HYPOTHÈSES, DÉPENDANCES ET LIMITES

## 6.1 Hypothèses

| Réf. | Hypothèse | Impact si fausse | Mode de validation |
|---|---|---|---|
| H-01 | Les tables `_FCC` sont des tables miroir (image de travail / non autorisée) | Interprétation erronée des écarts | Test TRS-303 + confirmation équipe applicative |
| H-02 | `MODULE = 'MM'` couvre l'intégralité des opérations sur titres | Périmètre incomplet | Test TRS-702 (recherche d'opérations titres hors MM par nature de GL) |
| H-03 | `PRODUCT_TYPE` distingue placement et emprunt | Sens des positions inversé | Test TRS-102 (croisement `PRODUCT_TYPE` × sens comptable dominant) |
| H-04 | La devise locale est XAF | Contre-valeurs erronées | Paramètre `p_ccy_locale`, contrôle par `LDTM_BRANCH_PARAMETERS.REPORTING_CCY` |
| H-05 | `CALCULATED_AMOUNT` est exprimé dans la devise de la composante | Écarts de recalcul massifs et faux | Analyse de la distribution des écarts par devise |
| H-06 | `ACTB_HISTORY.LCY_AMOUNT` est toujours renseigné et signé positivement, le sens étant porté par `DRCR_IND` | Déséquilibres factices | Test TRS-601 (contrôle de signe) |
| H-07 | Les écritures d'accrual portent un `EVENT` parmi `ACCR`, `IACR`, `MACR` | Rapprochement accrual/compta incomplet | Le script **découvre** dynamiquement les `EVENT` du module MM (TRS-602) |
| H-08 | Les fonds propres nets sont fournis en paramètre | Ratios prudentiels non calculables | Dégradation contrôlée : concentration relative uniquement |

## 6.2 Dépendances

| Réf. | Dépendance | Responsable | Échéance |
|---|---|---|---|
| D-01 | Fourniture des fonds propres nets à la date d'arrêté | Direction financière / Reporting réglementaire | Avant exécution |
| D-02 | Mapping produits MM → catégories comptables COBAC | Trésorerie + Comptabilité | Avant exécution |
| D-03 | Liste des utilisateurs techniques / batch légitimes | Production informatique | Avant exécution |
| D-04 | Textes officiels COBAC (R-2003/03, R-2003/02, R-2010/01, R-2010/02, R-2020/01) | Conformité | Avant émission du rapport |
| D-05 | Accès `SELECT` sur le schéma FCUBS | DBA | Avant exécution |
| D-06 | Limites internes de contrepartie et de dealer | Risques / Trésorerie | Avant exécution |
| D-07 | Confirmation de la sémantique des tables `_FCC` | Équipe applicative FLEXCUBE | Pendant l'exécution |

## 6.3 Limites reconnues

1. **Pas de valorisation de marché.** Aucune table de cours de titres n'est disponible dans
   le périmètre. Les tests d'évaluation (moins-values latentes, provisions) sont donc
   limités aux contrôles de cohérence interne.
2. **Pas de vue consolidée groupe.** L'analyse porte sur l'instance FLEXCUBE de
   l'établissement.
3. **Fonds propres nets exogènes.** Voir H-08.
4. **Tables d'événements détaillés non disponibles.** Le dictionnaire fourni ne comporte
   pas de table d'event log contractuel ; la piste d'audit est reconstituée à partir de
   `LDTB_CONTRACT_CONTROL` et de `ACTB_HISTORY` (`USER_ID`, `AUTH_ID`).
5. **Absence de colonnes `MAKER_ID` / `AUTH_STAT` sur `LDTB_CONTRACT_MASTER`.** Le contrôle
   maker/checker s'appuie donc sur la comptabilité (`ACTB_HISTORY`) et
   `LDTB_CONTRACT_CONTROL`, ce qui couvre l'acte comptable mais pas nécessairement l'acte
   de saisie contractuelle. Cette limite est explicitement mentionnée dans le rapport.

---

# 7. ARCHITECTURE TECHNIQUE DU SCRIPT

## 7.1 Principe directeur

**Un fichier, une exécution, aucun objet créé.**

Le livrable est un fichier `.sql` unique contenant :

1. un en-tête de directives SQL*Plus ;
2. un **bloc PL/SQL anonyme unique** ;
3. les procédures locales de mise en forme déclarées dans la partie déclarative du bloc ;
4. le corps du bloc, découpé en sections S0 à S13 ;
5. un bloc de synthèse final.

Cette architecture reprend celle déjà éprouvée dans le dépôt (`audit_aml_cft.sql`,
`test_coherence.sql`), garantissant l'homogénéité des livrables de la mission.

## 7.2 Squelette

```sql
-- ============================================================
-- SCRIPT D'AUDIT TRÉSORERIE / PORTEFEUILLE-TITRES (MODULE MM)
-- FLEXCUBE Universal Banking
-- Référentiel : COBAC / CEMAC — PCEC
-- ============================================================

SET ECHO OFF
SET DEFINE OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 200
SET PAGESIZE 0
SET TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    -- ---------- PARAMÈTRES (§ 8) ----------
    p_module            CONSTANT VARCHAR2(3)  := 'MM';
    p_ccy_locale        CONSTANT VARCHAR2(3)  := 'XAF';
    p_date_arrete       DATE;
    p_date_debut        DATE;
    p_fpn_xaf           CONSTANT NUMBER       := NULL;   -- à renseigner
    p_tol_interet       CONSTANT NUMBER       := 1;      -- unité de devise
    p_tol_interet_pct   CONSTANT NUMBER       := 0.01;   -- 1 %
    p_seuil_grand_risq  CONSTANT NUMBER       := 15;     -- % FPN
    p_seuil_benef_max   CONSTANT NUMBER       := 25;     -- % FPN (depuis 2023)
    p_seuil_gr_cumul    CONSTANT NUMBER       := 800;    -- % FPN
    p_echantillon_max   CONSTANT NUMBER       := 25;
    -- ...

    -- ---------- VARIABLES DE TRAVAIL ----------
    v_count             NUMBER;
    v_total             NUMBER;
    ...

    -- ---------- COLLECTIONS DE PRÉ-AGRÉGATION ----------
    TYPE t_compta_rec IS RECORD (
        nb_ecritures    NUMBER,
        tot_debit_lcy   NUMBER,
        tot_credit_lcy  NUMBER,
        premiere_dt     DATE,
        derniere_dt     DATE);
    TYPE t_compta_tab IS TABLE OF t_compta_rec INDEX BY VARCHAR2(50);
    g_compta            t_compta_tab;   -- indexé par TRN_REF_NO

    -- ---------- REGISTRE DES DÉFAILLANCES ----------
    TYPE t_finding_rec IS RECORD (
        code            VARCHAR2(20),
        section         VARCHAR2(60),
        criticite       VARCHAR2(10),
        libelle         VARCHAR2(300),
        nb_cas          NUMBER,
        montant_impact  NUMBER,
        ref_cobac       VARCHAR2(60));
    TYPE t_finding_tab IS TABLE OF t_finding_rec INDEX BY PLS_INTEGER;
    g_findings          t_finding_tab;
    g_nf                PLS_INTEGER := 0;

    -- ---------- PROCÉDURES D'AFFICHAGE ----------
    PROCEDURE p_section(...);
    PROCEDURE p_test(...);
    PROCEDURE p_kv(...);
    PROCEDURE p_pct(...);
    PROCEDURE p_finding(...);       -- alimente g_findings ET affiche
    PROCEDURE p_tbl_line(...);
    PROCEDURE p_tbl_header(...);
    PROCEDURE p_tbl_row(...);
    FUNCTION  f_num(p_txt VARCHAR2) RETURN NUMBER;   -- conversion sécurisée
    FUNCTION  f_fmt(p_n NUMBER) RETURN VARCHAR2;     -- format monétaire

BEGIN
    -- S0  : Initialisation, garde-fous, périmètre
    -- S1  : Référentiel produits
    -- S2  : Structure du portefeuille
    -- S3  : Cohérence des données contractuelles
    -- S4  : Composantes et échéanciers
    -- S5  : Recalcul des intérêts
    -- S6  : Accruals et séparation des exercices
    -- S7  : Comptabilisation et rapprochement
    -- S8  : Liquidations, impayés, remboursements anticipés
    -- S9  : Rollovers
    -- S10 : Indicateurs prudentiels COBAC
    -- S11 : Contrôle interne et habilitations
    -- S12 : Qualité de données et référentiels
    -- S13 : Synthèse des défaillances
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('*** ERREUR : ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        RAISE;
END;
/
```

## 7.3 Stratégie de performance

`ACTB_HISTORY` compte 5,79 M de lignes. Une exécution naïve (une requête agrégée par test)
provoquerait des dizaines de balayages complets.

**Règle d'architecture ARCH-01 — une seule passe sur `ACTB_HISTORY`.**
Au démarrage (section S0), le script effectue **un unique parcours** de
`ACTB_HISTORY` filtré sur `MODULE = 'MM'` et sur la période, et alimente des collections
associatives PL/SQL indexées par `TRN_REF_NO`, par `EVENT`, par `AMOUNT_TAG`, par
`AC_NO` et par `USER_ID`. Tous les tests des sections S6, S7 et S11 consomment ensuite ces
collections en mémoire.

Ordre de grandeur : 80 820 lignes MM → empreinte mémoire de quelques dizaines de Mo, ce qui
est parfaitement soutenable en PGA.

**Règle ARCH-02 — pas de requête corrélée ligne à ligne.** Les rapprochements
contrat ↔ comptabilité se font par jointure ensembliste ou par lookup en collection.

**Règle ARCH-03 — échantillonnage borné.** Chaque test qui liste des cas se limite à
`p_echantillon_max` lignes (défaut 25), triées par matérialité décroissante (montant), afin
de conserver un rapport lisible. Le **comptage reste exhaustif**.

**Règle ARCH-04 — pas de DDL, pas de DML, pas de table temporaire.** Le script est
exécutable par un compte en lecture seule.

**Règle ARCH-05 — robustesse.** Chaque section est encadrée par un bloc
`BEGIN ... EXCEPTION WHEN OTHERS THEN` local qui journalise l'erreur et **poursuit** à la
section suivante, afin qu'une table absente ou un droit manquant n'interrompe pas
l'intégralité du diagnostic.

## 7.4 Conventions de codage

| Convention | Règle |
|---|---|
| Nommage des tests | `TRS-nnn` (TRS = Trésorerie), numérotation par centaine = section |
| Criticité | `CRITIQUE`, `MAJEUR`, `MINEUR`, `INFO` |
| Conversion numérique | Fonction `f_num` avec `TO_NUMBER(... DEFAULT NULL ON CONVERSION ERROR)` ou bloc `EXCEPTION` selon la version Oracle — **obligatoire pour `NO_OF_DAYS` (VARCHAR2)** |
| Comparaison de montants | Toujours avec tolérance (`ABS(a-b) > p_tol`) — jamais d'égalité stricte sur des `NUMBER` |
| Dates | Format d'affichage `DD/MM/YYYY` |
| Montants | Format `FM999G999G999G990D00`, séparateurs adaptés ; **ne jamais utiliser `.` comme séparateur de groupe avec `G`** (cause d'`ORA-01481` déjà rencontrée dans le dépôt) |
| Chaînes | `SET DEFINE OFF` obligatoire (présence de `&` dans les libellés) |
| Largeur | 110 à 200 caractères, cohérente avec les scripts existants |

## 7.5 Gestion des valeurs « blanc » FLEXCUBE

FLEXCUBE stocke fréquemment un **espace** (`' '`) plutôt qu'un `NULL`. Tous les tests de
complétude doivent donc s'écrire :

```sql
    WHERE colonne IS NULL OR TRIM(colonne) IS NULL
```

et non `WHERE colonne IS NULL`. Cette règle est **impérative** — elle a un impact direct sur
la fiabilité des taux de complétude annoncés dans le rapport d'audit.

---

# 8. BLOC DE PARAMÉTRAGE

Le script expose en tête de partie déclarative un bloc de paramètres unique et documenté.

| Paramètre | Type | Défaut | Description |
|---|---|---|---|
| `p_module` | VARCHAR2(3) | `'MM'` | Module audité |
| `p_ccy_locale` | VARCHAR2(3) | `'XAF'` | Devise locale (contre-valeur) |
| `p_date_arrete` | DATE | max(`TRN_DT`) MM | Date d'arrêté de l'audit |
| `p_date_debut` | DATE | `p_date_arrete` − 24 mois | Début de la période de flux |
| `p_branch_filter` | VARCHAR2 | `'*'` | Agence ou `'*'` pour toutes |
| `p_fpn_xaf` | NUMBER | `NULL` | Fonds propres nets à la date d'arrêté |
| `p_tol_interet` | NUMBER | `1` | Tolérance absolue de recalcul (unité de devise) |
| `p_tol_interet_pct` | NUMBER | `0.01` | Tolérance relative de recalcul (1 %) |
| `p_tol_compta` | NUMBER | `1` | Tolérance d'équilibrage comptable (XAF) |
| `p_seuil_grand_risq` | NUMBER | `15` | Seuil « grand risque » en % FPN (R-2010/02) |
| `p_seuil_benef_max` | NUMBER | `25` | Plafond par bénéficiaire en % FPN (R-2020/01, depuis 2023) |
| `p_seuil_gr_cumul` | NUMBER | `800` | Plafond cumulé des grands risques en % FPN |
| `p_seuil_change_devise` | NUMBER | `15` | Limite de position de change par devise en % FPN — **à aligner sur R-2003/02** |
| `p_seuil_change_global` | NUMBER | `45` | Limite de position de change globale en % FPN — **à aligner sur R-2003/02** |
| `p_jours_retard_1` | NUMBER | `30` | 1er palier d'ancienneté d'impayé |
| `p_jours_retard_2` | NUMBER | `90` | 2e palier (seuil usuel de déclassement) |
| `p_jours_retard_3` | NUMBER | `180` | 3e palier |
| `p_jours_retard_4` | NUMBER | `360` | 4e palier |
| `p_jours_accrual_max` | NUMBER | `5` | Retard maximal admis d'accrual (jours ouvrés) |
| `p_echantillon_max` | NUMBER | `25` | Nombre de lignes détaillées par test |
| `p_users_techniques` | VARCHAR2 | `'SYSTEM,SYSTEMUSER,BATCH'` | Liste des comptes automatiques exemptés du test maker/checker |
| `p_seuil_concentration` | NUMBER | `10` | Seuil d'alerte de concentration en % de l'encours MM total |
| `p_afficher_ok` | BOOLEAN | `TRUE` | Afficher aussi les tests sans anomalie |

> **Exigence EXI-01.** Tout seuil réglementaire doit être **isolé dans ce bloc**, jamais
> codé en dur dans le corps du script, afin que l'auditeur puisse rejouer l'analyse avec
> les valeurs officielles sans intervention de développement.

---

# 9. SPÉCIFICATIONS FONCTIONNELLES DÉTAILLÉES

## S0 — Initialisation, garde-fous et cadrage

### S0.1 En-tête du rapport

Affiche : titre, établissement, module audité, date d'exécution, date d'arrêté, période
d'analyse, devise locale, valeur des FPN (ou mention « NON RENSEIGNÉS »), liste des seuils
appliqués avec leur référence réglementaire.

### S0.2 Garde-fous

| Réf. | Contrôle | Comportement si échec |
|---|---|---|
| TRS-001 | Existence et accessibilité des tables du périmètre | Liste des tables inaccessibles ; les sections dépendantes sont neutralisées avec mention explicite |
| TRS-002 | Présence d'au moins un contrat `MODULE='MM'` | Arrêt propre avec message ; le module n'est pas utilisé |
| TRS-003 | Présence d'écritures `ACTB_HISTORY` `MODULE='MM'` | Poursuite dégradée, section S7 neutralisée |
| TRS-004 | Cohérence de la devise locale déclarée vs `LDTM_BRANCH_PARAMETERS.REPORTING_CCY` | Avertissement |
| TRS-005 | Bornes de dates cohérentes (`p_date_debut < p_date_arrete`) | Correction automatique + avertissement |

### S0.3 Pré-agrégation comptable (ARCH-01)

Parcours unique de `ACTB_HISTORY` où `MODULE='MM'` et `TRN_DT` dans la période, alimentant :

- `g_compta(TRN_REF_NO)` : nb écritures, total débit LCY, total crédit LCY, min/max date ;
- `g_event(EVENT)` : nb écritures, total LCY, nb contrats distincts ;
- `g_tag(AMOUNT_TAG)` : nb, total débit, total crédit ;
- `g_user(USER_ID)` : nb écritures, nb écritures auto-validées (`USER_ID = AUTH_ID`) ;
- `g_gl(AC_NO)` : nb, solde net LCY ;
- `g_ccy(AC_CCY)` : nb, débit, crédit en devise et en LCY.

### S0.4 Cadrage volumétrique (TRS-006)

Tableau de cadrage affiché en tête :

| Indicateur | Valeur |
|---|---|
| Contrats MM (toutes versions) | … |
| Contrats MM (version courante) | … |
| Contrats MM actifs à la date d'arrêté | … |
| Contrats MM liquidés | … |
| Encours principal total (LCY) | … |
| Écritures comptables MM sur la période | … |
| Total débits / crédits LCY | … |
| Nombre de produits MM distincts | … |
| Nombre de contreparties distinctes | … |
| Nombre de devises | … |

---

## S1 — Référentiel produits et paramétrage

**Objectif.** Documenter le paramétrage et détecter les défauts de configuration à la
source, qui expliquent la majorité des anomalies de traitement.

| Test | Objet | Règle | Criticité |
|---|---|---|---|
| TRS-101 | Inventaire des produits MM | Liste `LDTM_PRODUCT_MASTER` × produits effectivement utilisés dans `LDTB_CONTRACT_MASTER` (MM) : code, description, `PRODUCT_TYPE`, `PAYMENT_METHOD`, `ACCRUAL_FREQUENCY`, `TENOR_UNIT`, min/std/max tenor, nb contrats, encours | INFO |
| TRS-102 | Sens des produits | Croisement `PRODUCT_TYPE` × sens comptable dominant (`DRCR_IND`) sur le premier événement (`INIT`). Détecte un produit paramétré « placement » comptabilisé comme ressource | MAJEUR |
| TRS-103 | Produits utilisés mais absents du référentiel | Produit présent dans `LDTB_CONTRACT_MASTER` sans ligne dans `LDTM_PRODUCT_MASTER` | CRITIQUE |
| TRS-104 | Produits bloqués mais utilisés | `LDTM_PRODUCT_MASTER.BLOCK_PRODUCT = 'Y'` avec contrats postérieurs au blocage | MAJEUR |
| TRS-105 | Produits sans accrual | `ACCRUAL_FREQUENCY` non renseignée ou `TRACK_ACCRUED_INTEREST` ≠ Y sur un produit porteur d'intérêt | CRITIQUE |
| TRS-106 | Fréquence d'accrual non quotidienne | `ACCRUAL_FREQUENCY` ≠ D : évaluer l'impact sur la séparation des exercices | MAJEUR |
| TRS-107 | Traitement de la décote | `DISC_ACCR_APPLICABLE` / `BOOK_UNEARNED_INTEREST` sur les produits titres — cohérence avec le régime attendu (R-2003/03) | MAJEUR |
| TRS-108 | Provisionnement automatique | `AUTO_PROV_REQUIRED` / `PROV_FREQUENCY` renseignés ? Absence de provisionnement automatique sur un portefeuille comportant des impayés | MAJEUR |
| TRS-109 | Tolérances de taux | `NORMAL_RATE_VARIANCE` / `MAXIMUM_RATE_VARIANCE` : valeurs nulles ou très élevées = absence de garde-fou sur les taux saisis | MAJEUR |
| TRS-110 | Bornes de durée | `MIN_TENOR` / `MAX_TENOR` non renseignés ou incohérents (min > max) | MINEUR |
| TRS-111 | Dates de vie produit | `CSTM_PRODUCT.PRODUCT_START_DATE` / `PRODUCT_END_DATE` : contrats bookés hors période de validité du produit | MAJEUR |
| TRS-112 | Autorisation du paramétrage | `CSTM_PRODUCT.AUTH_STAT` ≠ 'A' ou `MAKER_ID = CHECKER_ID` sur un produit MM | CRITIQUE |
| TRS-113 | Paramètres d'agence | `LDTM_BRANCH_PARAMETERS` : `ACCRUAL_LEVEL`, `PROCESS_TILL`, `RESIDUAL_AMOUNT`, `REPORTING_CCY` ; maker = checker | MAJEUR |
| TRS-114 | Ordre de liquidation | `LDTM_PRODUCT_LIQ_ORDER` : produits sans ordre défini (imputation des règlements non maîtrisée) | MINEUR |
| TRS-115 | Règles de rollover produit | `LDTM_PRODUCT_ROLLOVER.AUTO_MAN_ROLLOVER = 'A'` : rollover automatique — recensement et exposition concernée | MAJEUR |
| TRS-116 | Échéanciers par défaut | `LDTM_PRODUCT_DFLT_SCHEDULES` absent pour un produit avec échéancier | MINEUR |
| TRS-117 | Écarts référentiel produit / miroir | `LDTM_PRODUCT_MASTER` vs `LDTM_PRODUCT_MASTER_FCC` | MINEUR |
| TRS-118 | Cartographie des `AMOUNT_TAG` MM | Liste des tags rencontrés en comptabilité MM, croisés à `CSTB_AMOUNT_TAG` ; tags inconnus du référentiel | MAJEUR |
| TRS-119 | Codes transaction MM | `ACTB_HISTORY.TRN_CODE` (MM) × `STTM_TRN_CODE` : codes inexistants au référentiel, codes non autorisés | MAJEUR |

---

## S2 — Structure du portefeuille

**Objectif.** Produire la cartographie qui constitue le socle descriptif du rapport
d'audit — l'auditeur doit pouvoir répondre à « de quoi est fait ce portefeuille ? ».

| Test | Objet | Restitution |
|---|---|---|
| TRS-201 | Répartition par produit | Tableau : produit, libellé, nb contrats, encours LCY, % du total, encours moyen, taux moyen pondéré, durée moyenne |
| TRS-202 | Répartition emplois / ressources | Placements vs emprunts : nb, encours, taux moyen, duration approchée ; **position nette** |
| TRS-203 | Répartition par devise | Devise, nb contrats, montant en devise, contre-valeur LCY, % du total |
| TRS-204 | Répartition par contrepartie | Top N contreparties : code, nom (`STTM_CUSTOMER.CUSTOMER_NAME1`), catégorie, nb contrats, encours, % du total |
| TRS-205 | Répartition par catégorie de contrepartie | Croisement `STTM_CUSTOMER.CUSTOMER_CATEGORY` (BANK, FIN_INT, OFI, GOVT, CORP…) — distinction interbancaire / souverain / clientèle |
| TRS-206 | Répartition par agence | `BRANCH` : nb contrats, encours ; identification des agences de booking atypiques |
| TRS-207 | Répartition par bande de maturité résiduelle | ≤ 1 M / 1-3 M / 3-6 M / 6-12 M / 1-2 A / 2-5 A / > 5 A ; séparément pour emplois et ressources |
| TRS-208 | Répartition par durée initiale | Bandes de `TENOR` — identification des placements « courts renouvelés » |
| TRS-209 | Distribution des taux | Min, Q1, médiane, Q3, max, moyenne pondérée par produit et par devise ; détection des taux extrêmes |
| TRS-210 | Contrats à taux nul ou négatif | `MAIN_COMP_RATE ≤ 0` sur un contrat porteur d'intérêt |
| TRS-211 | Répartition par statut | `CONTRACT_STATUS`, `CONTRACT_DERIVED_STATUS`, `USER_DEFINED_STATUS` : effectifs et encours |
| TRS-212 | Répartition par dealer et méthode de négociation | `DEALER`, `DEALING_METHOD`, `BROKER_CODE` : concentration de l'activité sur un opérateur |
| TRS-213 | Évolution temporelle | Nb contrats et encours bookés par mois sur la période — détection de pics et de creux anormaux |
| TRS-214 | Ticket moyen et dispersion | Par produit : montant min, max, moyen, médian ; identification des opérations hors normes |
| TRS-215 | Concentration (Herfindahl) | Indice de concentration par contrepartie et par produit ; alerte si part d'une contrepartie > `p_seuil_concentration` |
| TRS-216 | Titres publics identifiés | Contrats dont la contrepartie est un État / Trésor de la CEMAC ou dont le produit est identifié « titre public » : ventilation BTA (≤ 52 semaines) / OTA (> 1 an) selon la maturité initiale |
| TRS-217 | Nominal vs valeur d'acquisition | Écart `ORIGINAL_FACE_VALUE` − `AMOUNT` : décote (émission au-dessous du pair) ou prime ; recensement et montant global |

---

## S3 — Cohérence des données contractuelles

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-301 | Versioning : contrats avec versions dupliquées, `EVENT_SEQ_NO` non strictement croissant, ou trous de séquence | MAJEUR |
| TRS-302 | Contrats orphelins : présents dans `LDTB_CONTRACT_MASTER` sans ligne dans `LDTB_CONTRACT_PREFERENCE`, `LDTB_CONTRACT_ICCF_DETAILS` ou `LDTB_CONTRACT_BALANCE` | MAJEUR |
| TRS-303 | Écarts table principale / table miroir `_FCC` (montant, dates, statut, contrats présents d'un seul côté) | MAJEUR |
| TRS-304 | Chronologie des dates : `TRADE_DATE > BOOKING_DATE`, `BOOKING_DATE > VALUE_DATE`, `VALUE_DATE ≥ MATURITY_DATE`, `ORIGINAL_START_DATE > VALUE_DATE` | CRITIQUE |
| TRS-305 | Dates aberrantes : dates antérieures à 1990, postérieures à la date d'arrêté + 30 ans, ou nulles sur champ obligatoire | MAJEUR |
| TRS-306 | Contrats à valeur postdatée (`VALUE_DATE > p_date_arrete`) mais avec écritures comptables déjà passées | CRITIQUE |
| TRS-307 | Cohérence `TENOR` / (`MATURITY_DATE` − `VALUE_DATE`) : écart supérieur à la tolérance | MAJEUR |
| TRS-308 | Contrats sans contrepartie (`COUNTERPARTY` nul ou blanc) | CRITIQUE |
| TRS-309 | Contrepartie inexistante dans `STTM_CUSTOMER` | CRITIQUE |
| TRS-310 | Contrepartie existante mais gelée (`FROZEN='Y'`), décédée, ou avec statut d'enregistrement fermé | CRITIQUE |
| TRS-311 | Contrats sans devise ou avec devise inconnue du référentiel | CRITIQUE |
| TRS-312 | Montant nul, négatif ou nul en contre-valeur (`AMOUNT ≤ 0` ou `LCY_AMOUNT ≤ 0`) | CRITIQUE |
| TRS-313 | Cohérence `AMOUNT` × taux de change ≈ `LCY_AMOUNT` : rapprochement avec `CYTB_RATES_HISTORY` à la date de valeur, écart > tolérance | MAJEUR |
| TRS-314 | Contrats en devise avec `LCY_AMOUNT = AMOUNT` (taux implicite = 1) alors que la devise ≠ devise locale | MAJEUR |
| TRS-315 | Statuts de sous-système non aboutis : `ICCF_STATUS`, `SETTLEMENT_STATUS`, `TAX_STATUS`, `BROKERAGE_STATUS`, `CHARGE_STATUS` en attente sur un contrat actif | MAJEUR |
| TRS-316 | Contrats rejetés (`REJ_REASON` renseigné) mais toujours actifs / comptabilisés | CRITIQUE |
| TRS-317 | Contrats sans `DEALER` renseigné | MAJEUR |
| TRS-318 | Contrats sans `DFLT_SETTLE_AC` (compte de règlement) alors que le produit exige un règlement | MAJEUR |
| TRS-319 | Contrats avec `CREDIT_LINE` renseignée mais ligne inexistante ou expirée dans `GETM_FACILITY` (`LINE_EXPIRY_DATE < VALUE_DATE`) | MAJEUR |
| TRS-320 | Contrats consommant une ligne au-delà de `LIMIT_AMOUNT` | CRITIQUE |
| TRS-321 | Contrats issus d'une interface (`INTERFACE_REF_NO` renseigné) : recensement et contrôle de complétude des attributs | MINEUR |
| TRS-322 | Doublons potentiels : même contrepartie, même devise, même montant, même date de valeur, même échéance, références différentes | MAJEUR |
| TRS-323 | Contrats sans message SWIFT de confirmation (`LDTB_CONTRACT_SWIFT_MESSAGE` absent) alors que la contrepartie est une banque | MAJEUR |
| TRS-324 | Écart entre le taux du contrat (`MAIN_COMP_RATE`) et le taux de la confirmation SWIFT (`INTEREST_RATE`) | CRITIQUE |
| TRS-325 | Écart entre l'encours du contrat et `LDTB_CONTRACT_SWIFT_MESSAGE.CONTRACT_BALANCE` | MAJEUR |
| TRS-326 | Contrats avec `MULTIPLE_CIF = 'Y'` : traitement particulier à documenter | INFO |
| TRS-327 | Contrats intra-day (`INTRA_DAY_DEAL`) : recensement | INFO |
| TRS-328 | Contrats sans `USER_REF_NO` (référence utilisateur) — traçabilité front/back dégradée | MINEUR |

---

## S4 — Composantes et échéanciers

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-401 | Inventaire des composantes rencontrées (`LDTB_CONTRACT_ICCF_DETAILS.COMPONENT`) : effectifs, devises, méthodes de paiement | INFO |
| TRS-402 | Contrats sans composante d'intérêt alors que `MAIN_COMP_RATE > 0` | CRITIQUE |
| TRS-403 | Composante d'intérêt dont la devise diffère de la devise du contrat | MAJEUR |
| TRS-404 | `ACCRUAL_REQUIRED ≠ 'Y'` sur une composante d'intérêt d'un contrat non échu | CRITIQUE |
| TRS-405 | Contrats actifs sans échéancier (`LDTB_CONTRACT_SCHEDULES` absent) | CRITIQUE |
| TRS-406 | Échéancier dont la somme des montants principal ≠ montant du contrat (tolérance d'arrondi) | CRITIQUE |
| TRS-407 | Échéances postérieures à la date d'échéance du contrat | MAJEUR |
| TRS-408 | Échéances antérieures à la date de valeur | MAJEUR |
| TRS-409 | Échéances à montant nul ou négatif | MAJEUR |
| TRS-410 | Fréquence d'échéance incohérente (`FREQUENCY` / `FREQUENCY_UNIT` nuls ou aberrants) | MINEUR |
| TRS-411 | Écart entre l'échéancier contractuel et l'échéancier par défaut du produit | MINEUR |
| TRS-412 | Contrats à échéancier utilisateur (`USER_DEFINED_SCHED = 'Y'`) : recensement, encours, justification à demander | MAJEUR |
| TRS-413 | Cohérence `LDTB_CONTRACT_SCHEDULES` vs `LDTB_CONTRACT_SCHEDULES_FCC` | MINEUR |
| TRS-414 | Contrats amortissables (`AMORTISATION_TYPE`) : cohérence type d'amortissement / profil d'échéancier | MAJEUR |
| TRS-415 | Règles de jours fériés : `IGNORE_HOLIDAYS = 'Y'` sur des contrats significatifs — impact potentiel sur le calcul d'intérêt | MAJEUR |
| TRS-416 | Paramètres d'arrondi : `ROUNDING_REQD`, `CCY_ROUND_RULE`, `CCY_DECIMALS`, `CCY_ROUND_UNIT` incohérents avec la devise | MINEUR |
| TRS-417 | Période maximale d'intérêt / de révision (`MAX_INT_PAY_PERIOD`, `MAX_RATE_REV_PERIOD`) dépassée | MINEUR |
| TRS-418 | Contrats à taux révisable : présence d'échéances de révision (`SCHEDULE_TYPE` de révision) et de `RATE_CODE` | MAJEUR |
| TRS-419 | Contrats à taux révisable sans révision effective depuis plus d'une période | MAJEUR |
| TRS-420 | Encours de `LDTB_CONTRACT_BALANCE` incohérent avec `AMOUNT` − principal remboursé | CRITIQUE |

---

## S5 — Recalcul indépendant des intérêts

**Objectif.** C'est le cœur substantif de l'audit : **ne pas croire le système sur parole**.

### S5.1 Méthode

Pour chaque ligne de `LDTB_CONTRACT_ICCF_CALC` rattachée à un contrat MM :

1. Conversion sécurisée de `NO_OF_DAYS` (VARCHAR2 → NUMBER) via `f_num`.
2. Contrôle de cohérence : `NO_OF_DAYS` ≈ `END_DATE` − `START_DATE` (selon
   `INT_PERIOD_BASIS` : bornes incluses ou exclues).
3. Calcul des trois montants candidats :
   - `I360 = BASIS_AMOUNT × RATE/100 × NDAYS/360`
   - `I365 = BASIS_AMOUNT × RATE/100 × NDAYS/365`
   - `I366 = BASIS_AMOUNT × RATE/100 × NDAYS/366`
4. Détermination de la base retenue = celle minimisant `ABS(candidat − CALCULATED_AMOUNT)`.
5. Écart absolu et écart relatif.
6. Classement :
   - **conforme** si écart ≤ MAX(`p_tol_interet`, `p_tol_interet_pct` × `CALCULATED_AMOUNT`) ;
   - **écart mineur** si écart relatif ≤ 5 % ;
   - **écart majeur** au-delà.

### S5.2 Tests

| Test | Objet | Criticité |
|---|---|---|
| TRS-501 | Distribution des bases de calcul détectées (360 / 365 / 366 / indéterminée) par produit et par devise | INFO |
| TRS-502 | Contrats dont la base détectée est **hétérogène** d'une période à l'autre | CRITIQUE |
| TRS-503 | Lignes de calcul dont aucune base ne reproduit `CALCULATED_AMOUNT` dans la tolérance | CRITIQUE |
| TRS-504 | Synthèse des écarts : nb lignes, nb contrats, écart total en valeur absolue, écart net (sur/sous-évaluation), top 25 écarts par montant | CRITIQUE |
| TRS-505 | Écart entre la base détectée et `LDTB_CONTRACT_ROLL_INT_RATES.INT_BASIS` | MAJEUR |
| TRS-506 | `NO_OF_DAYS` non numérique ou nul | MAJEUR |
| TRS-507 | `NO_OF_DAYS` incohérent avec (`END_DATE` − `START_DATE`) au-delà de 1 jour | MAJEUR |
| TRS-508 | `BASIS_AMOUNT` ≠ encours de principal à la période considérée | CRITIQUE |
| TRS-509 | `RATE` différent de `MAIN_COMP_RATE` du contrat (hors contrats à taux révisable) | CRITIQUE |
| TRS-510 | `RATE` hors bornes de variance du produit (`NORMAL_RATE_VARIANCE` / `MAXIMUM_RATE_VARIANCE`) par rapport au taux standard | MAJEUR |
| TRS-511 | Périodes de calcul se chevauchant sur une même composante | CRITIQUE |
| TRS-512 | Trous dans les périodes de calcul (discontinuité entre `END_DATE` d'une période et `START_DATE` de la suivante) | CRITIQUE |
| TRS-513 | Périodes de calcul postérieures à la date d'échéance du contrat | MAJEUR |
| TRS-514 | Cohérence Σ`CALCULATED_AMOUNT` par contrat vs `TILL_DATE_ACCRUAL` de `LDTB_CONTRACT_ICCF_DETAILS` | CRITIQUE |
| TRS-515 | Écart `LDTB_CONTRACT_ICCF_CALC` vs `LDTB_CONTRACT_ICCF_CALC_FCC` | MINEUR |
| TRS-516 | Taux atypiques : taux > percentile 99 ou < percentile 1 du produit — analyse de la justification | MAJEUR |
| TRS-517 | Contrats dont le taux est significativement hors marché : comparaison au taux moyen pondéré des contrats de même produit / devise / bande de maturité / trimestre, écart > 200 bps | CRITIQUE |
| TRS-518 | Intérêts calculés sur un contrat de montant nul | MAJEUR |
| TRS-519 | Méthode de calcul (`ICCF_CALC_METHOD`) hétérogène au sein d'un même produit | MAJEUR |
| TRS-520 | Contrats « discounted » : cohérence entre `UPFRONT_PROFIT_BOOKED`, la décote (`ORIGINAL_FACE_VALUE` − `AMOUNT`) et les intérêts calculés | CRITIQUE |

### S5.3 Restitution attendue

Tableau de synthèse par produit :

```
  +------+--------------------+--------+-------------+-------------+---------+--------+
  | PROD | LIBELLE            | NB LIG | MT CALCULÉ  | MT RECALCULÉ| ÉCART   | % ÉCART|
  +------+--------------------+--------+-------------+-------------+---------+--------+
```

puis liste détaillée des N plus gros écarts avec : contrat, contrepartie, composante,
période, assiette, taux, jours, base détectée, montant FLEXCUBE, montant recalculé, écart.

---

## S6 — Accruals et séparation des exercices

**Objectif.** Vérifier que les charges et produits d'intérêt sont rattachés au bon exercice
et effectivement comptabilisés — exigence centrale du PCEC.

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-601 | Contrats actifs porteurs d'intérêt **sans aucun accrual** dans `LDTB_CONTRACT_ACCRUAL_HISTORY` | CRITIQUE |
| TRS-602 | Accruals dont `ACC_ENTRY_PASSED ≠ 'Y'` : produit/charge constaté sans écriture comptable | CRITIQUE |
| TRS-603 | Fraîcheur des accruals : `PREVIOUS_ACCRUAL_TO_DATE` antérieure à la date d'arrêté de plus de `p_jours_accrual_max` jours sur un contrat actif | CRITIQUE |
| TRS-604 | Trous dans la chronologie des accruals : jours ouvrés sans accrual sur un contrat actif à fréquence quotidienne | CRITIQUE |
| TRS-605 | Cohérence Σ`NET_ACCRUAL` (historique) vs `TILL_DATE_ACCRUAL` (ICCF details) — écart > tolérance | CRITIQUE |
| TRS-606 | Accruals postérieurs à la date de liquidation du contrat | MAJEUR |
| TRS-607 | Accruals à montant négatif (reprises) : recensement, volumétrie, justification | MAJEUR |
| TRS-608 | Accruals de rattrapage (`TYPE_OF_ACCRUAL` de catch-up) : volumétrie et montants — indicateur de défaillance du batch | MAJEUR |
| TRS-609 | Accruals dont `ACCRUAL_TO_DATE > TRANSACTION_DATE` (anticipation) | MAJEUR |
| TRS-610 | Accruals chevauchant deux exercices comptables sans coupure à la clôture | CRITIQUE |
| TRS-611 | Séparation des exercices : accruals passés en exercice N pour une période relevant de N−1 | CRITIQUE |
| TRS-612 | Rapprochement accrual ↔ comptabilité : Σ`NET_ACCRUAL` par contrat vs Σ écritures `ACTB_HISTORY` d'événement d'accrual | CRITIQUE |
| TRS-613 | Écritures d'accrual en comptabilité sans ligne correspondante dans l'historique des accruals | CRITIQUE |
| TRS-614 | `OUTSTANDING_ACCRUAL` non nul sur un contrat entièrement liquidé | MAJEUR |
| TRS-615 | Intérêts courus non échus (ICNE) à la date d'arrêté : montant total par produit, devise et contrepartie — **rapprochement attendu avec le compte de créances rattachées du PCEC** | CRITIQUE |
| TRS-616 | Contrats dont l'ICNE dépasse le montant du principal | CRITIQUE |
| TRS-617 | État des traitements automatiques : `LDTB_AUTOMATIC_PROCESS_QUEUE.PROCESS_STATUS` ≠ statut de succès sur la période ; dates de traitement manquantes | CRITIQUE |
| TRS-618 | `LDTB_AUTO_FUNCTION_DETAILS.WORK_IN_PROGRESS` resté positionné : traitement interrompu | CRITIQUE |
| TRS-619 | `LDTB_PERIODIC_ACCRUAL_DATE` : dates de dernier accrual par produit/agence — produits en retard | MAJEUR |
| TRS-620 | `LDTB_COMPUTATION_HANDOFF` : lignes en attente de transfert | MAJEUR |
| TRS-621 | Écart `LDTB_CONTRACT_ICCF_DETAILS` vs `LDTB_CONTRACT_ICCF_DETAILS_FCC` | MINEUR |
| TRS-622 | `LDTB_ACCRUAL_FOR_LIMITS` : cohérence du cumul d'accrual pris en compte pour les limites | MINEUR |

---

## S7 — Comptabilisation et rapprochement gestion / comptabilité

**Objectif.** Vérifier que tout ce qui est en gestion est en comptabilité, que tout ce qui
est en comptabilité est justifié par la gestion, et que les écritures sont équilibrées.

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-701 | **Contrats sans écriture comptable** : contrat MM actif sans aucune ligne `ACTB_HISTORY` avec `TRN_REF_NO = CONTRACT_REF_NO` | CRITIQUE |
| TRS-702 | **Écritures sans contrat** : lignes `ACTB_HISTORY` `MODULE='MM'` dont le `TRN_REF_NO` n'existe pas dans `LDTB_CONTRACT_MASTER` | CRITIQUE |
| TRS-703 | **Déséquilibre par événement** : pour chaque (`TRN_REF_NO`, `EVENT_SR_NO`), ΣDébits LCY ≠ ΣCrédits LCY au-delà de `p_tol_compta` | CRITIQUE |
| TRS-704 | **Déséquilibre global** du module MM sur la période | CRITIQUE |
| TRS-705 | Écritures MM avec `LCY_AMOUNT` nul ou négatif | MAJEUR |
| TRS-706 | Écritures en devise avec `FCY_AMOUNT` renseigné mais `EXCH_RATE` nul, ou `FCY_AMOUNT × EXCH_RATE ≠ LCY_AMOUNT` au-delà de la tolérance | CRITIQUE |
| TRS-707 | Taux de change appliqué incohérent avec `CYTB_RATES_HISTORY` / `CYTB_DERIVED_RATES_HISTORY` à la date de l'écriture (écart > 1 %) | CRITIQUE |
| TRS-708 | Ventilation des écritures MM par agence comptable : concentration sur une agence technique (ex. 099) — cohérence avec l'agence de booking du contrat | MAJEUR |
| TRS-709 | Écritures dont l'agence comptable diffère de l'agence de booking du contrat | MAJEUR |
| TRS-710 | Écritures MM imputées sur des comptes clients (`CUST_GL = 'A'`) plutôt que sur des GL techniques — cohérence par `AMOUNT_TAG` | MAJEUR |
| TRS-711 | Écritures imputées sur un compte/GL inexistant dans `STTB_ACCOUNT` | CRITIQUE |
| TRS-712 | Écritures imputées sur un compte dormant, gelé ou bloqué (`AC_STAT_DORMANT`, `AC_STAT_FROZEN`, `GL_STAT_BLOCKED`) | CRITIQUE |
| TRS-713 | Écritures imputées sur un compte de devise différente de la devise de l'écriture | MAJEUR |
| TRS-714 | Écritures avec `VALUE_DT` antérieure à `TRN_DT` de plus de N jours (back-value) | MAJEUR |
| TRS-715 | Écritures avec `VALUE_DT` postérieure à `TRN_DT` (forward-value) | MAJEUR |
| TRS-716 | Écritures antérieures à la date de valeur du contrat ou postérieures à sa liquidation | CRITIQUE |
| TRS-717 | Rapprochement encours gestion / soldes comptables : Σ`PRINCIPAL_OUTSTANDING_BAL` (contrats actifs) vs solde net des comptes GL de principal MM | CRITIQUE |
| TRS-718 | Rapprochement ICNE gestion / comptabilité : Σ`TILL_DATE_ACCRUAL` non liquidé vs solde des comptes de créances/dettes rattachées | CRITIQUE |
| TRS-719 | Rapprochement produits/charges d'intérêt : Σ écritures MM sur comptes de classe 6/7 vs Σ accruals et liquidations d'intérêt de la période | CRITIQUE |
| TRS-720 | Cartographie des couples (`EVENT`, `AMOUNT_TAG`, `DRCR_IND`, nature du compte) : détection des schémas comptables atypiques ou non répétables | MAJEUR |
| TRS-721 | Événements comptables inattendus pour le module MM (liste dynamique des `EVENT` rencontrés, avec volumétrie et montants) | INFO |
| TRS-722 | Écritures d'extourne / contre-passation : identification par événement de reversal ; volumétrie, montants, contrats concernés, délai entre écriture et extourne | CRITIQUE |
| TRS-723 | Contrats présentant plusieurs cycles booking / extourne / rebooking — indicateur de manipulation | CRITIQUE |
| TRS-724 | Écritures MM hors période comptable ouverte (`FINANCIAL_CYCLE` / `PERIOD_CODE` incohérents avec `TRN_DT`) | CRITIQUE |
| TRS-725 | Écritures MM avec `BATCH_NO` renseigné : ventilation batch vs saisie manuelle | MAJEUR |
| TRS-726 | Écritures MM dont `PRODUCT` diffère du produit du contrat | MAJEUR |
| TRS-727 | Réévaluation de change : contrôle de `RVTB_ACC_REVAL` sur les comptes MM en devises — comptes en devise non réévalués à la date d'arrêté | CRITIQUE |
| TRS-728 | Cohérence `NEW_LCY_EQUIVALENT` = `ACCOUNT_BALANCE` × `NEW_RATE` dans `RVTB_ACC_REVAL` | MAJEUR |
| TRS-729 | Écarts entre les mouvements calculés depuis `ACTB_HISTORY` (MM) et les mouvements de `GLTB_GL_BAL` sur les GL concernés, par période | CRITIQUE |
| TRS-730 | Écritures MM sans `AMOUNT_TAG` ou avec tag non référencé | MAJEUR |

---

## S8 — Liquidations, impayés et remboursements anticipés

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-801 | **Impayés** : `LDTB_CONTRACT_LIQ` avec `AMOUNT_DUE > AMOUNT_PAID` — nb, montant, ancienneté | CRITIQUE |
| TRS-802 | Ventilation des impayés par palier d'ancienneté (`OVERDUE_DAYS` : ≤ 30 / 31-90 / 91-180 / 181-360 / > 360) — **rattachement au régime R-2018/01** | CRITIQUE |
| TRS-803 | Impayés sur contrepartie bancaire : risque de contrepartie interbancaire avéré | CRITIQUE |
| TRS-804 | Contrats échus (`MATURITY_DATE < p_date_arrete`) toujours au statut actif | CRITIQUE |
| TRS-805 | Contrats échus avec encours de principal non nul | CRITIQUE |
| TRS-806 | Contrats liquidés avec encours de principal non nul dans `LDTB_CONTRACT_BALANCE` | CRITIQUE |
| TRS-807 | Contrats liquidés avec des échéances restant dues | CRITIQUE |
| TRS-808 | Liquidations sans écriture comptable correspondante | CRITIQUE |
| TRS-809 | Écritures de liquidation sans ligne dans `LDTB_CONTRACT_LIQ` | CRITIQUE |
| TRS-810 | Cohérence Σ`AMOUNT_PAID` vs `LDTB_CONTRACT_LIQ_SUMMARY.TOTAL_PAID` | MAJEUR |
| TRS-811 | Remboursements anticipés (`TOTAL_PREPAID > 0`) : recensement, montants, contreparties | MAJEUR |
| TRS-812 | Remboursements anticipés **sans pénalité** alors que le produit prévoit `PREPAYMENT_PENALTY = 'Y'` | CRITIQUE |
| TRS-813 | Recalcul de la pénalité de remboursement anticipé : `PREPAYMENT_PENALTY_AMOUNT` vs assiette × `PREPAYMENT_PENALTY_RATE` | MAJEUR |
| TRS-814 | Prorogations d'échéance : `OLD_MATURITY_DATE` ≠ `NEW_MATURITY_DATE` — recensement, ancienneté, contreparties concernées ; **une prorogation répétée peut masquer un impayé** | CRITIQUE |
| TRS-815 | Liquidations rejetées (`REJ_REASON` renseigné) restées sans reprise | MAJEUR |
| TRS-816 | `PAYMENT_STATUS` en anomalie ou non abouti | MAJEUR |
| TRS-817 | Liquidations en date de valeur antérieure (back-valued) : `LIQ_BACK_VALUED_SCHEDULES` et impact intérêts | MAJEUR |
| TRS-818 | Écart `LIQUIDATED_FACE_VALUE` vs valeur nominale du contrat pour les titres | MAJEUR |
| TRS-819 | Liquidations partielles inférieures au minimum du produit (`MIN_AMT_PARTIAL_LIQ`) | MINEUR |
| TRS-820 | Ordre d'imputation des règlements : contrôle que l'imputation respecte `LDTM_PRODUCT_LIQ_ORDER` (intérêts avant principal, pénalités en premier…) | MAJEUR |
| TRS-821 | Taxes prélevées (`TAX_PAID`) : cohérence avec le `TAX_SCHEME` du contrat ; contrats taxables sans taxe prélevée | MAJEUR |
| TRS-822 | Écart `LDTB_CONTRACT_LIQ` vs `LDTB_CONTRACT_LIQ_FCC` et `LIQ_SUMMARY` vs `LIQ_SUMMARY_FCC` | MINEUR |
| TRS-823 | Provisionnement : contrats en impayé > 90 jours sans provision constatée (recherche d'écritures de provision sur le contrat) | CRITIQUE |

---

## S9 — Rollovers (renouvellements)

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-901 | Inventaire des rollovers : nb contrats, nb renouvellements (`ROLLOVER_COUNT`), montants, contreparties | INFO |
| TRS-902 | Contrats à `ROLLOVER_COUNT` élevé (> seuil paramétrable, défaut 6) : **placement court affiché mais durablement immobilisé** — impact liquidité/transformation | CRITIQUE |
| TRS-903 | Durée cumulée effective : (`MATURITY_DATE` − `ORIGINAL_START_DATE`) vs `TENOR` affiché — reclassement en bande de maturité réelle | CRITIQUE |
| TRS-904 | Rollovers automatiques (`AUTO_MAN_ROLLOVER = 'A'`) : recensement et encours ; absence de décision humaine documentée | MAJEUR |
| TRS-905 | Chaînage parent/enfant rompu : `PARENT_CONTRACT_REF_NO` renseigné mais contrat parent inexistant | MAJEUR |
| TRS-906 | Rollover avec capitalisation des intérêts (`ROLLOVER_WITH_INTEREST = 'Y'`) : montant renouvelé ≠ principal + intérêts capitalisés | MAJEUR |
| TRS-907 | Rollover avec modification de taux non justifiée : écart de taux parent/enfant > 200 bps | MAJEUR |
| TRS-908 | Rollover exécuté sur un contrat présentant des échéances impayées, sans liquidation préalable (`LIQUIDATE_OD_SCHEDULES ≠ 'Y'`) | CRITIQUE |
| TRS-909 | Rollover postérieur à la date d'échéance de plus de N jours | MAJEUR |
| TRS-910 | Rollover sans écriture comptable de l'événement correspondant | CRITIQUE |
| TRS-911 | Contrats avec instruction de rollover en attente (`ROLL_INST_STATUS`) non exécutée | MAJEUR |
| TRS-912 | Taxes sur rollover : `APPLY_TAX` / `DEDUCT_TAX_ON_ROLLOVER` incohérents entre produit et contrat | MINEUR |
| TRS-913 | Taux de rollover (`LDTB_CONTRACT_ROLL_INT_RATES.RATE`) hors marché par rapport aux contrats comparables | MAJEUR |
| TRS-914 | Rollovers concentrés sur une même contrepartie ou un même dealer | MAJEUR |

---

## S10 — Indicateurs prudentiels COBAC

**Objectif.** Alimenter la partie « conformité prudentielle » du rapport d'audit.

### S10.1 Division des risques (R-2010/02 modifié par R-2020/01)

| Test | Objet | Criticité |
|---|---|---|
| TRS-1001 | Exposition MM par contrepartie à la date d'arrêté (principal + ICNE), en LCY | INFO |
| TRS-1002 | Exposition rapportée aux FPN : contreparties dépassant `p_seuil_benef_max` (25 %) | CRITIQUE |
| TRS-1003 | Identification des grands risques (> `p_seuil_grand_risq`, soit 15 % FPN) | CRITIQUE |
| TRS-1004 | Somme des grands risques rapportée aux FPN vs plafond de 800 % | CRITIQUE |
| TRS-1005 | Concentration relative : part de la 1re, des 5 et des 10 premières contreparties dans l'encours MM total (calculable sans FPN) | MAJEUR |
| TRS-1006 | Exposition sur contreparties du groupe / apparentées (à identifier via `STTM_CUSTOMER` : catégorie, groupe, personnel) | CRITIQUE |
| TRS-1007 | Exposition souveraine (États CEMAC, Trésors publics) : montant, part, ventilation par émetteur | MAJEUR |

### S10.2 Liquidité et transformation

| Test | Objet | Criticité |
|---|---|---|
| TRS-1010 | Échéancier de liquidité MM : emplois et ressources par bande de maturité résiduelle, en LCY | INFO |
| TRS-1011 | Gap de liquidité par bande (emplois − ressources) et gap cumulé | MAJEUR |
| TRS-1012 | Contribution MM au rapport de liquidité (bande ≤ 1 mois) : disponibilités MM / exigibilités MM | MAJEUR |
| TRS-1013 | Contribution MM au coefficient de transformation (bande > 5 ans) | MAJEUR |
| TRS-1014 | Ressources MM très concentrées sur une échéance unique — risque de refinancement | MAJEUR |
| TRS-1015 | Impact du rollover systématique sur la maturité réelle (croisement TRS-903) : échéancier de liquidité **retraité** | CRITIQUE |

### S10.3 Position de change (R-2003/02)

| Test | Objet | Criticité |
|---|---|---|
| TRS-1020 | Position nette MM par devise (emplois − ressources) en devise et en contre-valeur XAF | INFO |
| TRS-1021 | Position par devise rapportée aux FPN vs `p_seuil_change_devise` | CRITIQUE |
| TRS-1022 | Position globale (somme des positions longues, somme des positions courtes) rapportée aux FPN vs `p_seuil_change_global` | CRITIQUE |
| TRS-1023 | Devises en position sans réévaluation constatée dans `RVTB_ACC_REVAL` | CRITIQUE |
| TRS-1024 | Ancienneté du dernier cours utilisé par devise (`CYTB_RATES_HISTORY`) : cours périmés | MAJEUR |

### S10.4 Couverture des risques et classement

| Test | Objet | Criticité |
|---|---|---|
| TRS-1030 | Ventilation de l'encours MM par nature de contrepartie et pondération indicative (souverain / banque CEMAC / banque hors zone / autre) — **éléments d'alimentation du ratio de couverture des risques, sans conclusion sur le ratio lui-même** | INFO |
| TRS-1031 | Créances MM en souffrance selon R-2018/01 : montant, ancienneté, provisions constatées, insuffisance de provision estimée | CRITIQUE |
| TRS-1032 | Contrats sans `EXPOSURE_CATEGORY` renseignée | MAJEUR |

---

## S11 — Contrôle interne et habilitations

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-1101 | **Auto-validation** : écritures MM avec `USER_ID = AUTH_ID`, hors comptes techniques listés dans `p_users_techniques` — **violation de la séparation des tâches (R-2016/04)** | CRITIQUE |
| TRS-1102 | Écritures MM sans `AUTH_ID` renseigné | CRITIQUE |
| TRS-1103 | Concentration de l'activité : top opérateurs MM par nb d'écritures et par montant ; part du 1er opérateur | MAJEUR |
| TRS-1104 | Utilisateurs actifs sur MM absents de `SMTB_USER` ou désactivés (`SMTB_USER_DISABLE`) à la date d'opération | CRITIQUE |
| TRS-1105 | Utilisateurs opérant sur MM dont le profil (`SMTB_USER_ROLE` / `SMTB_ROLE_MASTER`) ne comporte pas de rôle trésorerie identifié | CRITIQUE |
| TRS-1106 | Limites fonctionnelles : `SMTB_ROLE_FUNC_LIMIT_DETAIL` / `_CUSTOM` — opérations dont le montant dépasse la limite du rôle de l'opérateur | CRITIQUE |
| TRS-1107 | Opérations MM réalisées hors plage horaire ouvrable (analyse de `ENTRY_TIME` de `LDTB_CONTRACT_CONTROL` et des horodatages disponibles) | MAJEUR |
| TRS-1108 | Opérations MM en week-end ou jour férié | MAJEUR |
| TRS-1109 | `LDTB_CONTRACT_CONTROL` : contrats sans trace de contrôle ; processus (`PROCESS_CODE`) inattendus | MAJEUR |
| TRS-1110 | Cumul des fonctions : utilisateur ayant à la fois initié un contrat et validé son écriture comptable | CRITIQUE |
| TRS-1111 | Dealers non recensés dans le référentiel utilisateurs | MAJEUR |
| TRS-1112 | Contrats dont le `DEALER` et l'initiateur de l'écriture (`USER_ID`) sont identiques — front/back non séparés | CRITIQUE |
| TRS-1113 | Activité de connexion : `SMTB_SMS_LOG` / `SMTB_USERLOG_DETAILS` — sessions des opérateurs MM à des horaires atypiques | MINEUR |
| TRS-1114 | Modifications de paramétrage produit MM sur la période (`MOD_NO`, `CHECKER_DT_STAMP`) : recensement et validation | MAJEUR |
| TRS-1115 | Paramétrage MM modifié par un maker = checker | CRITIQUE |

---

## S12 — Qualité de données et référentiels

| Test | Règle de contrôle | Criticité |
|---|---|---|
| TRS-1201 | Taux de complétude des colonnes clés de `LDTB_CONTRACT_MASTER` (avec traitement des blancs FLEXCUBE) | INFO |
| TRS-1202 | Colonnes uniformément vides sur l'ensemble du portefeuille — champs non alimentés par le paramétrage | MAJEUR |
| TRS-1203 | Contreparties MM sans KYC valide (`STTM_CUSTOMER.KYC_DETAILS ≠ 'V'` ou `KYC_REF_NO` absent) — **jonction avec l'audit AML/CFT déjà réalisé** | CRITIQUE |
| TRS-1204 | Contreparties MM avec profil de risque non renseigné (`RISK_PROFILE`) | MAJEUR |
| TRS-1205 | Contreparties MM domiciliées hors CEMAC : ventilation par pays, montants | MAJEUR |
| TRS-1206 | Contreparties MM catégorisées PEP | CRITIQUE |
| TRS-1207 | Références contractuelles non conformes au format attendu (longueur, préfixe agence/module) | MINEUR |
| TRS-1208 | Doublons de `USER_REF_NO` | MINEUR |
| TRS-1209 | Caractères de contrôle / non imprimables dans les libellés et remarques | MINEUR |
| TRS-1210 | Cohérence des devises entre contrat, composante, échéancier, écriture comptable et compte de règlement | MAJEUR |
| TRS-1211 | Contrats dont le `REMARKS` ou `INTERNAL_REMARKS` contient des mots-clés d'alerte (à paramétrer : « régularisation », « exception », « dérogation », « à corriger ») | MAJEUR |
| TRS-1212 | Cohérence des effectifs entre tables liées (contrat / préférence / balance / ICCF details) | MAJEUR |

---

## S13 — Synthèse des défaillances

### S13.1 Registre des défaillances

Le script alimente au fil de l'eau la collection `g_findings`. La section S13 la restitue :

**Tableau 1 — Synthèse par criticité**

| Criticité | Nb de tests en anomalie | Nb de cas | Impact financier identifié (LCY) |
|---|---|---|---|
| CRITIQUE | … | … | … |
| MAJEUR | … | … | … |
| MINEUR | … | … | … |

**Tableau 2 — Synthèse par section**

| Section | Tests exécutés | Tests conformes | Tests en anomalie | Taux de conformité |
|---|---|---|---|---|

**Tableau 3 — Détail des défaillances (trié par criticité puis impact décroissant)**

| Code | Section | Criticité | Libellé | Nb cas | Impact LCY | Réf. COBAC |
|---|---|---|---|---|---|---|

### S13.2 Score de maîtrise

Un indicateur synthétique est calculé :

```
    Score = 100 − (10 × nb_CRITIQUES_en_anomalie
                 +  4 × nb_MAJEURS_en_anomalie
                 +  1 × nb_MINEURS_en_anomalie)   , borné à [0 ; 100]
```

| Score | Appréciation |
|---|---|
| 85 – 100 | Dispositif maîtrisé |
| 70 – 84 | Maîtrise satisfaisante avec réserves |
| 50 – 69 | Maîtrise insuffisante |
| < 50 | Dispositif défaillant |

> Cette pondération est **conventionnelle** et doit être validée par le responsable de
> mission. Elle sert à hiérarchiser, non à conclure : la conclusion d'audit reste fondée sur
> le jugement professionnel.

### S13.3 Top 10 des points d'attention

Liste des 10 défaillances les plus significatives (croisement criticité × impact financier
× volumétrie), formulées de façon directement réutilisable en fiche de constat.

### S13.4 Pied de rapport

- durée d'exécution du script ;
- nombre de tests exécutés / neutralisés ;
- liste des tests neutralisés avec le motif (table inaccessible, paramètre manquant) ;
- rappel des paramètres utilisés ;
- rappel des hypothèses non levées.

---

# 10. CATALOGUE CONSOLIDÉ DES TESTS

## 10.1 Récapitulatif par section

| Section | Intitulé | Plage de codes | Nb de tests |
|---|---|---|---|
| S0 | Initialisation et cadrage | TRS-001 à TRS-006 | 6 |
| S1 | Référentiel produits et paramétrage | TRS-101 à TRS-119 | 19 |
| S2 | Structure du portefeuille | TRS-201 à TRS-217 | 17 |
| S3 | Cohérence des données contractuelles | TRS-301 à TRS-328 | 28 |
| S4 | Composantes et échéanciers | TRS-401 à TRS-420 | 20 |
| S5 | Recalcul des intérêts | TRS-501 à TRS-520 | 20 |
| S6 | Accruals et séparation des exercices | TRS-601 à TRS-622 | 22 |
| S7 | Comptabilisation et rapprochement | TRS-701 à TRS-730 | 30 |
| S8 | Liquidations et impayés | TRS-801 à TRS-823 | 23 |
| S9 | Rollovers | TRS-901 à TRS-914 | 14 |
| S10 | Indicateurs prudentiels COBAC | TRS-1001 à TRS-1032 | 21 |
| S11 | Contrôle interne et habilitations | TRS-1101 à TRS-1115 | 15 |
| S12 | Qualité de données | TRS-1201 à TRS-1212 | 12 |
| S13 | Synthèse | — | — |
| **TOTAL** | | | **247** |

## 10.2 Répartition par criticité cible

| Criticité | Nb de tests | Part |
|---|---|---|
| CRITIQUE | ~ 75 | 30 % |
| MAJEUR | ~ 105 | 43 % |
| MINEUR | ~ 30 | 12 % |
| INFO | ~ 37 | 15 % |

## 10.3 Matrice de couverture des assertions d'audit

| Assertion | Sections couvrantes | Tests emblématiques |
|---|---|---|
| **Existence / Réalité** | S3, S7, S11 | TRS-702, TRS-322, TRS-323, TRS-1101 |
| **Exhaustivité** | S6, S7 | TRS-601, TRS-701, TRS-717 |
| **Exactitude / Évaluation** | S5, S6, S8 | TRS-503, TRS-504, TRS-605, TRS-813 |
| **Séparation des exercices** | S6 | TRS-603, TRS-610, TRS-611, TRS-615 |
| **Droits et obligations** | S3, S10 | TRS-319, TRS-320, TRS-1002 |
| **Présentation et information** | S1, S2, S10 | TRS-101, TRS-207, TRS-1010 |
| **Conformité réglementaire** | S10 | TRS-1002, TRS-1004, TRS-1021, TRS-1031 |
| **Contrôle interne** | S11 | TRS-1101, TRS-1106, TRS-1110, TRS-1112 |

## 10.4 Matrice de traçabilité réglementaire

| Référence COBAC | Tests rattachés |
|---|---|
| R-2003/03 (opérations sur titres) | TRS-107, TRS-108, TRS-216, TRS-217, TRS-505, TRS-506, TRS-520 |
| R-2003/02 (positions de change) | TRS-1020 à TRS-1024, TRS-707, TRS-727 |
| R-2010/01 (couverture des risques) | TRS-1030 |
| R-2010/02 + R-2020/01 (division des risques) | TRS-1001 à TRS-1007 |
| R-2016/03 (fonds propres nets) | Paramètre `p_fpn_xaf`, base de S10 |
| R-2016/04 (contrôle interne) | TRS-1101 à TRS-1115, TRS-317, TRS-323 |
| R-2018/01 (créances en souffrance) | TRS-801 à TRS-803, TRS-823, TRS-1031 |
| Liquidité / transformation | TRS-1010 à TRS-1015, TRS-207, TRS-902, TRS-903 |
| PCEC (cadre comptable) | S7 dans son ensemble, TRS-615, TRS-718, TRS-719 |
| Marché des titres publics CEMAC | TRS-216, TRS-1007 |

---

# 11. SPÉCIFICATIONS DE RESTITUTION

## 11.1 Canal

Sortie `DBMS_OUTPUT`, destinée à être capturée par `SPOOL` :

```sql
    SPOOL rapport_audit_tresorerie_mm_YYYYMMDD.txt
    @audit_tresorerie_mm.sql
    SPOOL OFF
```

## 11.2 Charte de présentation

Reprise stricte de la charte des scripts existants du dépôt :

```
================================================================================
>>> SECTION 5 : RECALCUL INDÉPENDANT DES INTÉRÊTS
================================================================================

--------------------------------------------------------------------------------
  TEST TRS-504 : Synthèse des écarts de recalcul d'intérêt
--------------------------------------------------------------------------------
  Lignes de calcul analysées........................ 12 480
  Lignes conformes (tolérance 1 XAF / 1%)........... 11 902 / 12 480 (95.4%)
  Lignes en écart................................... 578 / 12 480 (4.6%)
  Écart absolu cumulé............................... 4 812 337 XAF
  Écart net (sur-évaluation)........................ 1 204 991 XAF
  [CRITIQUE] 578 lignes de calcul d'intérêt ne sont pas reproductibles.

  Détail des 25 écarts les plus significatifs :
  +----+-------------------+------------------+----------+--------+------+-----+------------+------------+-----------+
  | N# | CONTRAT           | CONTREPARTIE     | COMPOSANT| ASSIETTE| TAUX|JOURS| FLEXCUBE   | RECALCULÉ  | ÉCART     |
  +----+-------------------+------------------+----------+--------+------+-----+------------+------------+-----------+
```

## 11.3 Règles de mise en forme

| Élément | Règle |
|---|---|
| Séparateur de section | 80 à 110 caractères `=` |
| Séparateur de test | 80 à 110 caractères `-` |
| Ligne indicateur | `RPAD(libellé, 50, '.') || ' ' || valeur` |
| Marqueur de constat | `[CRITIQUE]`, `[MAJEUR]`, `[MINEUR]`, `[INFO]`, `[OK]` |
| Tableaux | Bordures ASCII `+`, `-`, `|` ; largeur totale ≤ 200 |
| Montants | Séparateur de milliers, sans décimale pour les montants XAF, 2 décimales pour les devises |
| Troncature | `SUBSTR` sur les libellés longs, avec largeur de colonne fixe |
| Tests conformes | Affichés avec `[OK]` si `p_afficher_ok = TRUE` |

## 11.4 Structure du fichier de sortie

1. Page de garde (établissement, module, dates, paramètres)
2. Cadrage volumétrique
3. Sections S1 à S12 dans l'ordre
4. Section S13 — synthèse et score
5. Pied de rapport

Volume estimé de la sortie : 2 500 à 5 000 lignes selon le nombre d'anomalies.

## 11.5 Exploitation en aval

Le rapport texte est destiné à être :

- annexé au dossier de travail de la mission (section « tests substantifs ») ;
- découpé par test pour alimenter les feuilles de travail Excel de la mission ;
- utilisé comme base de discussion contradictoire avec la direction de la trésorerie.

Une **variante CSV** (sortie tabulée mono-format, une ligne par anomalie) peut être produite
en v1.1 pour faciliter l'import dans l'outil de gestion des constats. Cette variante n'est
pas incluse dans la v1.

---

# 12. EXIGENCES NON FONCTIONNELLES

| Réf. | Exigence | Critère d'acceptation |
|---|---|---|
| ENF-01 | Exécution en une seule commande | Le script s'exécute intégralement par `@audit_tresorerie_mm.sql` sans intervention |
| ENF-02 | Lecture seule | Aucun `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `CREATE`, `DROP`, `ALTER`, `COMMIT` |
| ENF-03 | Durée d'exécution | ≤ 15 minutes sur environnement de restitution |
| ENF-04 | Empreinte mémoire | PGA ≤ 512 Mo |
| ENF-05 | Robustesse | Une erreur sur une section n'interrompt pas les autres ; message explicite |
| ENF-06 | Idempotence | Deux exécutions consécutives produisent le même résultat (à données constantes) |
| ENF-07 | Portabilité | Compatible Oracle 11gR2 et supérieur ; pas de fonctionnalité 21c+ obligatoire |
| ENF-08 | Traçabilité | Chaque anomalie renvoie à un code test et à une référence réglementaire |
| ENF-09 | Paramétrabilité | Tous les seuils en tête de script (§ 8) |
| ENF-10 | Lisibilité du code | Commentaires en français, un bandeau par test, indentation homogène |
| ENF-11 | Absence d'impact production | Pas de verrou, pas de `FOR UPDATE`, pas de hint parallèle agressif |
| ENF-12 | Confidentialité | Aucune donnée nominative superflue ; les libellés sont tronqués ; le rapport reste classé « confidentiel — audit interne » |

---

# 13. PLAN DE RECETTE

## 13.1 Recette technique

| Réf. | Cas de test | Attendu |
|---|---|---|
| REC-T01 | Exécution complète sur environnement de restitution | Aucune erreur Oracle, sortie complète |
| REC-T02 | Exécution avec un compte en lecture seule | Succès |
| REC-T03 | Exécution avec `p_fpn_xaf = NULL` | Section S10 en mode dégradé, message explicite, pas d'erreur |
| REC-T04 | Exécution avec une table du périmètre inaccessible | Section neutralisée, message, poursuite |
| REC-T05 | Exécution avec `p_branch_filter` sur une agence | Résultats cohérents et restreints |
| REC-T06 | Mesure de la durée | ≤ 15 minutes |
| REC-T07 | Contrôle d'absence de DML | Revue de code + `EXPLAIN` |
| REC-T08 | Encodage et caractères accentués | Sortie lisible, pas de caractère parasite |
| REC-T09 | Format des montants | Pas d'`ORA-01481`, séparateurs corrects |
| REC-T10 | `NO_OF_DAYS` non numérique | Pas d'`ORA-01722`, ligne classée en anomalie TRS-506 |

## 13.2 Recette fonctionnelle

| Réf. | Cas de test | Méthode de validation |
|---|---|---|
| REC-F01 | Cadrage volumétrique | Rapprochement manuel avec des comptages SQL indépendants |
| REC-F02 | Recalcul d'intérêt | Vérification manuelle sur 10 contrats choisis (calcul sur tableur) |
| REC-F03 | Équilibre comptable | Vérification manuelle sur 5 événements |
| REC-F04 | Rapprochement gestion/compta | Rapprochement avec la balance comptable officielle à la date d'arrêté |
| REC-F05 | Bandes de maturité | Contrôle de la somme des bandes = encours total |
| REC-F06 | Division des risques | Recalcul manuel sur les 3 premières contreparties |
| REC-F07 | Position de change | Rapprochement avec l'état de position de change de la trésorerie |
| REC-F08 | Impayés | Rapprochement avec l'état des impayés du back-office |
| REC-F09 | Séparation des tâches | Vérification de 10 cas d'auto-validation auprès de la production informatique |
| REC-F10 | Absence de faux positifs massifs | Revue contradictoire des 20 premiers cas de chaque test CRITIQUE |

## 13.3 Critère de sortie de recette

Le script est réputé recetté lorsque :

- 100 % des cas REC-T sont passants ;
- 100 % des cas REC-F ont fait l'objet d'une validation contradictoire ;
- le taux de faux positifs constaté sur les tests CRITIQUES est inférieur à 10 %, ou les
  règles concernées ont été ajustées ;
- le responsable de mission a validé la restitution.

---

# 14. GOUVERNANCE, LIVRABLES ET PLANNING

## 14.1 Livrables

| Réf. | Livrable | Format | Destinataire |
|---|---|---|---|
| L-01 | Le présent BRD | Markdown | Responsable de mission |
| L-02 | Script `audit_tresorerie_mm.sql` | SQL | Auditeur, DBA |
| L-03 | Rapport d'exécution | Texte (spool) | Dossier de travail |
| L-04 | Note de synthèse des défaillances | Document | Direction de l'audit |
| L-05 | Journal des faux positifs et ajustements | Tableur | Dossier de travail |

## 14.2 Rôles

| Rôle | Responsabilité |
|---|---|
| Responsable de mission | Valide le BRD, les seuils, la conclusion |
| Auditeur en charge | Exécute, analyse, documente |
| Référent conformité | Valide les références réglementaires COBAC |
| DBA / Production | Fournit l'accès, valide l'absence d'impact |
| Référent applicatif FLEXCUBE | Confirme la sémantique des tables et du paramétrage |
| Direction de la trésorerie | Contradictoire sur les constats |

## 14.3 Séquencement proposé

| Étape | Contenu | Durée indicative |
|---|---|---|
| E1 | Validation du BRD et des seuils | 2 j |
| E2 | Développement du script (sections S0 à S5) | 3 j |
| E3 | Développement du script (sections S6 à S9) | 3 j |
| E4 | Développement du script (sections S10 à S13) | 2 j |
| E5 | Recette technique | 1 j |
| E6 | Première exécution et recette fonctionnelle | 2 j |
| E7 | Ajustement des règles (faux positifs) | 2 j |
| E8 | Exécution définitive et rédaction des constats | 3 j |

## 14.4 Gestion des versions

Le script et le BRD sont versionnés dans le dépôt Git de la mission, sur la branche
`claude/treasury-audit-cemac-cobac-w9fucc`, aux côtés des livrables existants
(`audit_aml_cft.sql`, `test_coherence.sql`, `explore_database.sql`).

---

# 15. ANNEXES

## 15.1 Glossaire

| Terme | Définition |
|---|---|
| **Accrual** | Rattachement périodique (souvent quotidien) des intérêts courus non échus à l'exercice |
| **AMOUNT_TAG** | Étiquette FLEXCUBE identifiant la nature d'un montant dans un schéma comptable |
| **BTA** | Bon du Trésor Assimilable — titre public court terme CEMAC (13, 26 ou 52 semaines ; valeur nominale 1 000 000 FCFA) |
| **COBAC** | Commission Bancaire de l'Afrique Centrale — superviseur bancaire de la CEMAC |
| **Composante** | Élément financier d'un contrat (principal, intérêt, commission, taxe, pénalité) |
| **Day count convention** | Convention de décompte des jours (ACT/360, ACT/365, 30/360…) |
| **EOD / BOD** | End Of Day / Begin Of Day — traitements automatiques de fin et de début de journée |
| **FPN** | Fonds propres nets au sens du règlement COBAC R-2016/03 |
| **Grand risque** | Exposition sur un même bénéficiaire excédant 15 % des FPN |
| **ICCF** | Interest, Commission, Charges and Fees — sous-système FLEXCUBE de calcul |
| **ICNE** | Intérêts courus non échus |
| **LCY / FCY** | Local Currency / Foreign Currency |
| **Liquidation (FLEXCUBE)** | Règlement d'une échéance (et non liquidation au sens juridique) |
| **Maker / Checker** | Initiateur / valideur — principe de séparation des tâches |
| **MM** | Money Market — module FLEXCUBE des opérations de marché monétaire et de trésorerie |
| **OTA** | Obligation du Trésor Assimilable — titre public moyen/long terme CEMAC (2 à 10 ans) |
| **PCEC** | Plan Comptable des Établissements de Crédit |
| **Rollover** | Renouvellement d'un contrat à son échéance |
| **SVT** | Spécialiste en Valeurs du Trésor |
| **Tenor** | Durée du contrat |

## 15.2 Correspondance test ↔ table principale

| Section | Tables principalement sollicitées |
|---|---|
| S1 | `LDTM_PRODUCT_MASTER`, `LDTM_PRODUCT_*`, `CSTM_PRODUCT`, `CSTB_AMOUNT_TAG`, `STTM_TRN_CODE`, `LDTM_BRANCH_PARAMETERS` |
| S2 | `LDTB_CONTRACT_MASTER`, `LDTB_CONTRACT_BALANCE`, `STTM_CUSTOMER`, `STTM_CUSTOMER_CAT` |
| S3 | `LDTB_CONTRACT_MASTER`, `_FCC`, `STTM_CUSTOMER`, `GETM_FACILITY`, `LDTB_CONTRACT_SWIFT_MESSAGE`, `CYTB_RATES_HISTORY` |
| S4 | `LDTB_CONTRACT_SCHEDULES`, `LDTB_CONTRACT_ICCF_DETAILS`, `LDTB_CONTRACT_PREFERENCE`, `LDTB_CONTRACT_BALANCE` |
| S5 | `LDTB_CONTRACT_ICCF_CALC`, `LDTB_CONTRACT_ICCF_DETAILS`, `LDTB_CONTRACT_ROLL_INT_RATES` |
| S6 | `LDTB_CONTRACT_ACCRUAL_HISTORY`, `LDTB_CONTRACT_ICCF_DETAILS`, `ACTB_HISTORY`, `LDTB_AUTOMATIC_PROCESS_QUEUE`, `LDTB_PERIODIC_ACCRUAL_DATE` |
| S7 | `ACTB_HISTORY`, `GLTB_GL_BAL`, `STTB_ACCOUNT`, `RVTB_ACC_REVAL`, `CYTB_*` |
| S8 | `LDTB_CONTRACT_LIQ`, `LDTB_CONTRACT_LIQ_SUMMARY`, `LDTM_PRODUCT_LIQ_ORDER` |
| S9 | `LDTB_CONTRACT_ROLLOVER`, `LDTB_CONTRACT_ROLL_INT_RATES`, `LDTM_PRODUCT_ROLLOVER` |
| S10 | `LDTB_CONTRACT_MASTER`, `LDTB_CONTRACT_BALANCE`, `LDTB_CONTRACT_ICCF_DETAILS`, `STTM_CUSTOMER` |
| S11 | `ACTB_HISTORY`, `SMTB_*`, `LDTB_CONTRACT_CONTROL` |
| S12 | Toutes |

## 15.3 Points à confirmer (PAC)

| Réf. | Point | Interlocuteur |
|---|---|---|
| PAC-01 | Mapping produits MM → catégories comptables COBAC (transaction / placement / investissement) | Trésorerie + Comptabilité |
| PAC-02 | Sémantique exacte des tables `_FCC` | Référent applicatif FLEXCUBE |
| PAC-03 | Valeurs de `PRODUCT_TYPE` et `CONTRACT_STATUS` en usage | Référent applicatif |
| PAC-04 | Comptes GL du PCEC utilisés pour le principal, les ICNE, les produits et charges d'intérêt MM | Comptabilité |
| PAC-05 | Fonds propres nets à la date d'arrêté | Reporting réglementaire |
| PAC-06 | Limites internes de contrepartie, de dealer et de position | Risques |
| PAC-07 | Liste des utilisateurs techniques / batch | Production informatique |
| PAC-08 | Seuils exacts de position de change (R-2003/02) | Conformité |
| PAC-09 | Nature de l'agence 099 | Organisation |
| PAC-10 | Horaires ouvrables de la salle des marchés | Trésorerie |

## 15.4 Risques du projet

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| Faux positifs massifs sur le recalcul d'intérêt (règles d'arrondi, jours fériés) | Élevée | Moyen | Détection empirique de la base ; tolérance paramétrable ; revue contradictoire avant conclusion |
| Indisponibilité des FPN | Moyenne | Élevé | Mode dégradé documenté (concentration relative) |
| Volumétrie `ACTB_HISTORY` pénalisante | Moyenne | Moyen | Pré-agrégation en une passe (ARCH-01) |
| Sémantique `_FCC` mal comprise | Moyenne | Moyen | Test descriptif TRS-303 avant interprétation |
| Références COBAC non vérifiées sur texte officiel | Élevée | Élevé | Blocage de l'émission du rapport tant que D-04 n'est pas levée |
| Exécution en production perturbant les traitements | Faible | Élevé | Exécution hors EOD/BOD, environnement de restitution privilégié |

## 15.5 Backlog version 2

| Réf. | Évolution |
|---|---|
| V2-01 | Sortie CSV structurée (une ligne par anomalie) pour import dans l'outil de constats |
| V2-02 | Valorisation mark-to-market si une source de prix est mise à disposition |
| V2-03 | Extension au module `FX` (change au comptant et à terme) |
| V2-04 | Extension aux dérivés (module `DV`) |
| V2-05 | Reconstitution des états CERBER relatifs aux titres |
| V2-06 | Analyse de tendance multi-arrêtés (comparaison de deux exécutions) |
| V2-07 | Détection d'anomalies par écart-type glissant sur les taux (approche statistique) |
| V2-08 | Contrôle des titres en conservation pour compte de tiers |
| V2-09 | Intégration du calcul complet du ratio de couverture des risques |
| V2-10 | Rapprochement automatique avec les confirmations SWIFT brutes (MT320/MT330/MT350) |

## 15.6 Sources documentaires consultées

- [Règlements de la COBAC — BEAC](https://www.beac.int/supervision-bancaire/reglements-de-cobac/)
- [Règlement COBAC R-2003/03 relatif à la comptabilisation et au traitement prudentiel des opérations sur titres effectuées par les établissements de crédit](https://www.beac.int/wp-content/uploads/2016/10/cbR-2003-03.pdf)
- [Règlement COBAC R-2003/02 relatif à la surveillance des positions de change](https://www.beac.int/wp-content/uploads/2016/10/Re%CC%80glement-COBAC-R-200302-relatif-a%CC%80-la-surveillance-des-positions-de-change.pdf)
- [Règlement COBAC R-2010/01 relatif à la couverture des risques](https://www.beac.int/wp-content/uploads/2016/10/RgltCOBAC_-R_2010_01_couvrisq.pdf)
- [Règlement COBAC R-2010/02 relatif à la division des risques](https://www.beac.int/wp-content/uploads/2016/10/Reglement-_COBAC-_R_2010_02_divrisq.pdf)
- [Règlement COBAC R-2020/01 modifiant la division des risques](https://www.kalieu-elongo.com/wp-content/uploads/2021/02/reglement_cobac_r-2020_01-dovision-des-risques.pdf)
- [Règlement COBAC R-2016/03 relatif aux fonds propres nets des établissements de crédit](http://kalieu-elongo.com/wp-content/uploads/2017/02/reglement_cobac_r-2016_03_relatif_aux_fonds_propres_nets_des_etablissements_de_credit.pdf)
- [Règlement COBAC R-2016/04 relatif au contrôle interne](https://www.beac.int/wp-content/uploads/2016/10/reglement_cobac_r-2016_04_relatif_au_controle_interne.pdf)
- [Règlement COBAC R-2018/01 relatif à la classification, à la comptabilisation et au provisionnement des créances](https://www.beac.int/wp-content/uploads/2016/10/reglement_cobac_r_2018-01_relatif_a_la_classification_a_la_comptabilisation_et_au_provisionnement_des_creances.pdf)
- [Plan Comptable des Établissements de Crédit — COBAC](https://planeteexpertises.com/telechargement/plan-comptable-etablissements-credits-cobac.pdf)
- [Présentation générale du Marché des Titres Publics — BEAC](https://www.beac.int/m-des-titres-publics/presentation-generale/)
- [CEMAC/COBAC : ce qui change pour la division des risques bancaires](https://droitmediasfinance.com/index.php/actualites/droit-bancaire/287-cemac-cobac-ce-qui-change-pour-la-division-des-risques-bancaires)
- [Rapport annuel 2024 de la Commission Bancaire de l'Afrique Centrale](https://www.beac.int/wp-content/uploads/2016/10/Rapport-annuel-de-la-COBAC-2024-PDF-14.8-Mo_compressed-1.pdf)
- [Oracle FLEXCUBE Universal Banking — Money Market User Manual](https://docs.oracle.com/cd/E51523_01/PDF/MM/MM.pdf)

> **Rappel.** L'accès direct au contenu de ces documents n'ayant pas été possible depuis
> l'environnement de rédaction (blocage du réseau sortant), les règles chiffrées reprises
> dans ce BRD doivent être confrontées aux textes officiels avant l'émission du rapport
> d'audit (dépendance D-04).

---

**FIN DU DOCUMENT**
