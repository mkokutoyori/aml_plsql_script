--------------------------------------------------------------------------------
-- LISTE DES CLIENTS DE LA BANQUE
--   avec MANDAT (mode de fonctionnement) / POUVOIR DE SIGNATURE / PROCURATION
--
-- SGBD        : Oracle (FLEXCUBE Universal Banking - FCUBS)
-- Type        : Requete SQL pure (aucun PL/SQL)
-- Granularite : 1 ligne par client (CUSTOMER_NO)
-- Convention  : chaque colonne de sortie reprend le nom REEL de la colonne
--               source, prefixe du nom de sa table -> TABLE_COLONNE.
--               Les colonnes multi-valuees (comptes, signataires) sont
--               agregees via LISTAGG mais conservent le nom reel de la colonne.
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
    -- IDENTITE DU CLIENT  (STTM_CUSTOMER)
    -- ----------------------------------------------------------------------
      c.customer_no                          AS sttm_customer_customer_no
    , c.customer_name1                       AS sttm_customer_customer_name1
    , c.short_name                           AS sttm_customer_short_name
    , c.customer_type                        AS sttm_customer_customer_type      -- I=Indiv, C=Corporate, B=Bank
    , c.customer_category                    AS sttm_customer_customer_category
    , c.kyc_ref_no                           AS sttm_customer_kyc_ref_no

    -- ----------------------------------------------------------------------
    -- MANDAT (mode de fonctionnement) - STTM_CUST_ACCOUNT (agrege par client)
    -- ----------------------------------------------------------------------
    , acc.mode_of_operation                  AS sttm_cust_account_mode_of_operation   -- S/J/E/F/A/M
    , acc.joint_ac_indicator                 AS sttm_cust_account_joint_ac_indicator  -- S=Single / J=Joint

    -- ----------------------------------------------------------------------
    -- POUVOIR DE SIGNATURE
    -- ----------------------------------------------------------------------
    , acc.repl_cust_sig                      AS sttm_cust_account_repl_cust_sig       -- Y/N (sur comptes)
    , sig.name                               AS sttm_kyc_corp_keypersons_name         -- signataires corporate
    , sig.relationship                       AS sttm_kyc_corp_keypersons_relationship
    , sig.position_or_title                  AS sttm_kyc_corp_keypersons_position_or_title

    -- ----------------------------------------------------------------------
    -- PROCURATION (Power of Attorney)
    -- ----------------------------------------------------------------------
    -- Particuliers (STTM_CUST_PERSONAL)
    , p.pa_issued                            AS sttm_cust_personal_pa_issued          -- Y/N
    , p.pa_holder_name                       AS sttm_cust_personal_pa_holder_name
    , p.pa_holder_nationalty                 AS sttm_cust_personal_pa_holder_nationalty
    -- KYC Retail (STTM_KYC_RETAIL)
    , kr.pa_given                            AS sttm_kyc_retail_pa_given              -- Y/N
    , kr.pa_holder_name                      AS sttm_kyc_retail_pa_holder_name

FROM            sttm_customer            c
    LEFT JOIN   sttm_cust_personal       p
           ON   p.customer_no  = c.customer_no
    LEFT JOIN   sttm_kyc_retail          kr
           ON   kr.kyc_ref_no  = c.kyc_ref_no

    -- ---- Agregation des COMPTES par client (STTM_CUST_ACCOUNT) ----
    -- NB: le DISTINCT est applique dans des sous-requetes imbriquees car
    --     LISTAGG(DISTINCT ...) n'est disponible qu'a partir d'Oracle 19c.
    LEFT JOIN (
        SELECT
              b.cust_no
            , b.repl_cust_sig
            , m.mode_of_operation
            , j.joint_ac_indicator
        FROM (
                 SELECT
                       a.cust_no
                     , MAX(a.repl_cust_sig)  AS repl_cust_sig
                 FROM   sttm_cust_account a
                 GROUP BY a.cust_no
             ) b
        LEFT JOIN (
                 SELECT
                       d.cust_no
                     , LISTAGG(d.mode_of_operation, ', ')
                           WITHIN GROUP (ORDER BY d.mode_of_operation)  AS mode_of_operation
                 FROM ( SELECT DISTINCT cust_no, mode_of_operation
                        FROM   sttm_cust_account ) d
                 GROUP BY d.cust_no
             ) m
               ON m.cust_no = b.cust_no
        LEFT JOIN (
                 SELECT
                       e.cust_no
                     , LISTAGG(e.joint_ac_indicator, ', ')
                           WITHIN GROUP (ORDER BY e.joint_ac_indicator) AS joint_ac_indicator
                 FROM ( SELECT DISTINCT cust_no, joint_ac_indicator
                        FROM   sttm_cust_account ) e
                 GROUP BY e.cust_no
             ) j
               ON j.cust_no = b.cust_no
    ) acc
           ON   acc.cust_no    = c.customer_no

    -- ---- Agregation des SIGNATAIRES corporate (STTM_KYC_CORP_KEYPERSONS) ----
    LEFT JOIN (
        SELECT
              k.kyc_ref_no
            , LISTAGG(k.name, ' | ')
                  WITHIN GROUP (ORDER BY k.name)              AS name
            , LISTAGG(k.relationship, ' | ')
                  WITHIN GROUP (ORDER BY k.name)              AS relationship
            , LISTAGG(k.position_or_title, ' | ')
                  WITHIN GROUP (ORDER BY k.name)              AS position_or_title
        FROM   sttm_kyc_corp_keypersons k
        GROUP BY k.kyc_ref_no
    ) sig
           ON   sig.kyc_ref_no = c.kyc_ref_no

ORDER BY c.customer_no;
