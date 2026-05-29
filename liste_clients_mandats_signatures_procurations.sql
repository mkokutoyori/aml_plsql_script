--------------------------------------------------------------------------------
-- LISTE DES CLIENTS DE LA BANQUE
--   avec MANDAT / POUVOIR DE SIGNATURE / PROCURATION
--
-- SGBD        : Oracle (FLEXCUBE Universal Banking - FCUBS)
-- Type        : Requete SQL pure (aucun PL/SQL)
-- Granularite : 1 ligne par (CLIENT x PERSONNE CLE corporate).
--               - Un client corporate ayant N personnes cles -> N lignes.
--               - Un client sans personne cle (particuliers, corporate sans
--                 keyperson) -> 1 ligne, colonnes KCKP_* a NULL.
--               => permet de filtrer directement sur KCKP_EST_SIGNATAIRE = 'Y'.
-- Convention  : chaque colonne de sortie reprend le nom REEL de la colonne
--               source, prefixe d'un code court de table (limite Oracle de
--               30 octets sur les identifiants en version < 12.2) :
--                 CUST_ = STTM_CUSTOMER             ACC_  = STTM_CUST_ACCOUNT
--                 PERS_ = STTM_CUST_PERSONAL        KYCR_ = STTM_KYC_RETAIL
--                 KCKP_ = STTM_KYC_CORP_KEYPERSONS  UDF_  = CSTM_FUNCTION_USERDEF_FIELDS (STDKYCMN)
--               Le mode de fonctionnement des comptes (par client) reste agrege
--               via LISTAGG en conservant le nom reel de la colonne.
--
-- Cartographie metier -> donnees FCUBS :
--   * MANDAT (mode de fonctionnement du compte)
--        -> STTM_CUST_ACCOUNT.JOINT_AC_INDICATOR
--           (MODE_OF_OPERATION non retenue : vide dans toute la base)
--   * POUVOIR DE SIGNATURE
--        -> STTM_KYC_CORP_KEYPERSONS  (1 ligne / personne cle, flag signataire)
--        -> STTM_CUST_ACCOUNT.REPL_CUST_SIG  (replication signature client)
--        -> CSTM_FUNCTION_USERDEF_FIELDS / STDKYCMN.field_val_7
--           (corp_ac_sign_or_director : signataire / directeur saisi en KYC)
--   * PROCURATION (Power of Attorney)
--        -> STTM_CUST_PERSONAL.PA_ISSUED / PA_HOLDER_NAME (particuliers)
--        -> STTM_KYC_RETAIL.PA_GIVEN / PA_HOLDER_NAME      (KYC retail)
--
-- Liaisons :
--   STTM_CUSTOMER.CUSTOMER_NO  = STTM_CUST_PERSONAL.CUSTOMER_NO
--   STTM_CUSTOMER.CUSTOMER_NO  = STTM_CUST_ACCOUNT.CUST_NO
--   STTM_CUSTOMER.KYC_REF_NO   = STTM_KYC_RETAIL.KYC_REF_NO
--   STTM_CUSTOMER.KYC_REF_NO   = STTM_KYC_CORP_KEYPERSONS.KYC_REF_NO
--   STTM_CUSTOMER.KYC_REF_NO   = SUBSTR(rec_key,1,LENGTH(rec_key)-1) (STDKYCMN)
--------------------------------------------------------------------------------

SELECT
    -- ----------------------------------------------------------------------
    -- IDENTITE DU CLIENT  (STTM_CUSTOMER)
    -- ----------------------------------------------------------------------
      c.customer_no                          AS cust_customer_no
    , c.customer_name1                       AS cust_customer_name1
    , c.short_name                           AS cust_short_name
    , c.customer_type                        AS cust_customer_type      -- I=Indiv, C=Corporate, B=Bank
    , c.customer_category                    AS cust_customer_category
    , c.kyc_ref_no                           AS cust_kyc_ref_no

    -- ----------------------------------------------------------------------
    -- MANDAT - STTM_CUST_ACCOUNT (agrege par client)
    -- NB: MODE_OF_OPERATION non retenue (colonne vide dans toute la base).
    -- ----------------------------------------------------------------------
    , acc.joint_ac_indicator                 AS acc_joint_ac_indicator  -- S=Single / J=Joint

    -- ----------------------------------------------------------------------
    -- POUVOIR DE SIGNATURE
    -- ----------------------------------------------------------------------
    , acc.repl_cust_sig                      AS acc_repl_cust_sig       -- Y/N (sur comptes)
    -- 1 ligne par personne cle (STTM_KYC_CORP_KEYPERSONS)
    , k.name                                 AS kckp_name
    , k.relationship                         AS kckp_relationship
    , k.position_or_title                    AS kckp_position_or_title
    , CASE WHEN UPPER(k.position_or_title) LIKE '%SIGNATORY%'
           THEN 'Y' ELSE 'N' END             AS kckp_est_signataire     -- Y/N (POSITION_OR_TITLE ~ SIGNATORY)
    -- Champ KYC utilisateur (STDKYCMN.field_val_7)
    , udf.corp_ac_sign_or_director           AS udf_corp_ac_sign_or_dir

    -- ----------------------------------------------------------------------
    -- PROCURATION (Power of Attorney)
    -- ----------------------------------------------------------------------
    -- Particuliers (STTM_CUST_PERSONAL)
    , p.pa_issued                            AS pers_pa_issued          -- Y/N
    , p.pa_holder_name                       AS pers_pa_holder_name
    , p.pa_holder_nationalty                 AS pers_pa_holder_nationalty
    -- KYC Retail (STTM_KYC_RETAIL)
    , kr.pa_given                            AS kycr_pa_given           -- Y/N
    , kr.pa_holder_name                      AS kycr_pa_holder_name

FROM            sttm_customer            c
    LEFT JOIN   sttm_cust_personal       p
           ON   p.customer_no  = c.customer_no
    LEFT JOIN   sttm_kyc_retail          kr
           ON   kr.kyc_ref_no  = c.kyc_ref_no

    -- ---- 1 ligne par PERSONNE CLE corporate (pouvoir de signature) ----
    LEFT JOIN   sttm_kyc_corp_keypersons k
           ON   k.kyc_ref_no   = c.kyc_ref_no

    -- ---- Champ utilisateur STDKYCMN : corp_ac_sign_or_director ----
    -- rec_key = KYC_REF_NO + 1 caractere technique -> on retire le dernier.
    -- MAX() pour garantir 1 ligne par KYC_REF_NO (pas de demultiplication).
    LEFT JOIN (
        SELECT
              SUBSTR(rec_key, 1, LENGTH(rec_key) - 1)  AS kyc_ref_no
            , MAX(field_val_7)                         AS corp_ac_sign_or_director
        FROM   cstm_function_userdef_fields
        WHERE  function_id = 'STDKYCMN'
        GROUP BY SUBSTR(rec_key, 1, LENGTH(rec_key) - 1)
    ) udf
           ON   udf.kyc_ref_no = c.kyc_ref_no

    -- ---- Agregation des COMPTES par client (STTM_CUST_ACCOUNT) ----
    -- NB: le DISTINCT est applique dans une sous-requete imbriquee car
    --     LISTAGG(DISTINCT ...) n'est disponible qu'a partir d'Oracle 19c.
    LEFT JOIN (
        SELECT
              b.cust_no
            , b.repl_cust_sig
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

ORDER BY c.customer_no, k.name;
