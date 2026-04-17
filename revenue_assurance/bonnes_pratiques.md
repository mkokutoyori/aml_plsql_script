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
