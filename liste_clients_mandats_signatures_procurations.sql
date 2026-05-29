--------------------------------------------------------------------------------
-- LISTE DES CLIENTS DE LA BANQUE
--   avec MANDAT (mode de fonctionnement) / POUVOIR DE SIGNATURE / PROCURATION
--
-- SGBD        : Oracle (FLEXCUBE Universal Banking - FCUBS)
-- Type        : Requete SQL pure (aucun PL/SQL)
-- Granularite : 1 ligne par client (CUSTOMER_NO)
--
-- Cartographie metier -> donnees FCUBS :
--   * MANDAT (mode de fonctionnement du compte)
--        -> STTM_CUST_ACCOUNT.MODE_OF_OPERATION  (+ JOINT_AC_INDICATOR)
--   * POUVOIR DE SIGNATURE
--        -> STTM_KYC_CORP_KEYPERSONS  (signataires / directeurs des dossiers corporate)
--        -> STTM_CUST_ACCOUNT.REPL_CUST_SIG  (replication signature client)
--   * PROCURATION (Power of Attorney)
--        -> STTM_CUST_PERSONAL.PA_ISSUED / PA_HOLDER_NAME (particuliers)
--        -> STTM_KYC_RETAIL.PA_GIVEN / PA_HOLDER_NAME      (KYC retail)
--
-- Liaisons :
--   STTM_CUSTOMER.CUSTOMER_NO  = STTM_CUST_PERSONAL.CUSTOMER_NO
--   STTM_CUSTOMER.CUSTOMER_NO  = STTM_CUST_ACCOUNT.CUST_NO
--   STTM_CUSTOMER.KYC_REF_NO   = STTM_KYC_RETAIL.KYC_REF_NO
--   STTM_CUSTOMER.KYC_REF_NO   = STTM_KYC_CORP_KEYPERSONS.KYC_REF_NO
--------------------------------------------------------------------------------

SELECT
    -- ----------------------------------------------------------------------
    -- IDENTITE DU CLIENT
    -- ----------------------------------------------------------------------
      c.customer_no                                          AS customer_no
    , c.customer_name1                                       AS customer_name
    , c.short_name                                           AS short_name
    , c.customer_type                                        AS customer_type      -- I=Indiv, C=Corporate, B=Bank
    , CASE c.customer_type
          WHEN 'I' THEN 'Particulier'
          WHEN 'C' THEN 'Entreprise'
          WHEN 'B' THEN 'Banque'
          ELSE c.customer_type
      END                                                    AS customer_type_lib
    , c.customer_category                                    AS customer_category
    , c.kyc_ref_no                                           AS kyc_ref_no

    -- ----------------------------------------------------------------------
    -- MANDAT (mode de fonctionnement) - agrege sur l'ensemble des comptes
    -- ----------------------------------------------------------------------
    , NVL(acc.nb_comptes, 0)                                 AS nb_comptes
    , acc.modes_fonctionnement                               AS mandat_mode_operation     -- codes bruts agreges
    , acc.modes_fonctionnement_lib                           AS mandat_mode_operation_lib -- libelles
    , acc.indicateurs_jointure                               AS mandat_compte_joint       -- S=Single / J=Joint

    -- ----------------------------------------------------------------------
    -- POUVOIR DE SIGNATURE
    -- ----------------------------------------------------------------------
    , NVL(sig.nb_signataires, 0)                             AS nb_signataires_corp
    , sig.signataires                                        AS pouvoir_signature_corp    -- Nom (Relation - Poste)
    , acc.repl_signature_client                              AS pouvoir_signature_repl    -- REPL_CUST_SIG (Y/N) sur comptes

    -- ----------------------------------------------------------------------
    -- PROCURATION (Power of Attorney)
    -- ----------------------------------------------------------------------
    -- Particuliers (STTM_CUST_PERSONAL)
    , p.pa_issued                                            AS procuration_emise_indiv   -- Y/N
    , p.pa_holder_name                                       AS procuration_mandataire_indiv
    , p.pa_holder_nationalty                                 AS procuration_nationalite_indiv
    -- KYC Retail (STTM_KYC_RETAIL)
    , kr.pa_given                                            AS procuration_donnee_retail -- Y/N
    , kr.pa_holder_name                                      AS procuration_mandataire_retail
    -- Synthese : une procuration existe-t-elle ?
    , CASE
          WHEN NVL(p.pa_issued, 'N') = 'Y'
            OR NVL(kr.pa_given,  'N') = 'Y' THEN 'OUI'
          ELSE 'NON'
      END                                                    AS procuration_existe

FROM            sttm_customer            c
    LEFT JOIN   sttm_cust_personal       p
           ON   p.customer_no  = c.customer_no
    LEFT JOIN   sttm_kyc_retail          kr
           ON   kr.kyc_ref_no  = c.kyc_ref_no

    -- ---- Agregation des COMPTES par client (mandat + signature repliquee) ----
    LEFT JOIN (
        SELECT
              a.cust_no
            , COUNT(*)                                          AS nb_comptes
            , LISTAGG(DISTINCT a.mode_of_operation, ', ')
                  WITHIN GROUP (ORDER BY a.mode_of_operation)   AS modes_fonctionnement
            , LISTAGG(DISTINCT
                  CASE a.mode_of_operation
                      WHEN 'S' THEN 'Signature unique'
                      WHEN 'J' THEN 'Conjointe (Jointly)'
                      WHEN 'E' THEN 'Indifferente (Either)'
                      WHEN 'F' THEN 'Premier ou survivant'
                      WHEN 'A' THEN 'Quiconque ou survivant'
                      WHEN 'M' THEN 'Titulaire de mandat'
                      ELSE a.mode_of_operation
                  END, ', ')
                  WITHIN GROUP (ORDER BY a.mode_of_operation)   AS modes_fonctionnement_lib
            , LISTAGG(DISTINCT a.joint_ac_indicator, ', ')
                  WITHIN GROUP (ORDER BY a.joint_ac_indicator)  AS indicateurs_jointure
            , MAX(a.repl_cust_sig)                              AS repl_signature_client
        FROM   sttm_cust_account a
        GROUP BY a.cust_no
    ) acc
           ON   acc.cust_no    = c.customer_no

    -- ---- Agregation des SIGNATAIRES corporate (pouvoir de signature) ----
    LEFT JOIN (
        SELECT
              k.kyc_ref_no
            , COUNT(*)                                          AS nb_signataires
            , LISTAGG(
                  k.name
                  || CASE WHEN k.relationship      IS NOT NULL
                          THEN ' (' || k.relationship || ')' END
                  || CASE WHEN k.position_or_title IS NOT NULL
                          THEN ' - ' || k.position_or_title END
                  , ' | ')
                  WITHIN GROUP (ORDER BY k.name)                AS signataires
        FROM   sttm_kyc_corp_keypersons k
        GROUP BY k.kyc_ref_no
    ) sig
           ON   sig.kyc_ref_no = c.kyc_ref_no

ORDER BY c.customer_no;
