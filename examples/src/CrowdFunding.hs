{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-specialise #-}

-- A smart contract to model a crowd funding project with a deadline
module CrowdFunding where

-- Plutus related imports
import Ledger.Contexts
import qualified PlutusTx as PlTx
import PlutusTx.Builtins.Internal hiding (snd)
import qualified Ledger.Typed.Scripts as Scripts
import Ledger.Address
import Ledger.Credential
import Ledger.Crypto
import Ledger
import Ledger.Time
import PlutusTx.Prelude (traceIfFalse)

-- Some basic types
import Data.String
import Data.Bool
import Data.Aeson hiding (Value)
import GHC.Generics
import Prelude
import Schema

{-
The datum for the CrowdFunding smart contract. A peer can either :
* propose a project with its address, an id, a goal and a time range
* contribute to a project with its address and an id
-}
data CrowdFundingDatum =
  ProjectProposal PubKeyHash String Integer POSIXTimeRange |
  Funding         PubKeyHash String
  deriving stock    (Eq    , Show    , Generic)
  deriving anyclass (ToJSON, FromJSON)

{-
The redeemer for the CrowdFunding smart contract. The project can either be :
* launched, with the following parameters :
  - an AssetClass : the nature of the tokens to give to contributors
  - a power of 10 : the number of parts in which the project shall be split among contributors
  - the time at which this transaction is launched
* cancelled
-}
data CrowdFundingRedeemer =
  Launch AssetClass Integer POSIXTime |
  Cancel
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)  

-- Retrieves the value for the current input
getCurrentValue :: ScriptContext -> Maybe Value
getCurrentValue = (fmap (txOutValue . txInInfoResolved)) . findOwnInput

-- Retrieves the current time and compares it to a time range
validateTimeRange :: POSIXTime -> POSIXTimeRange -> Bool
validateTimeRange time range = True

-- Compares the sum of all inputs, with the threshold
validateTotalSum :: ScriptContext -> Integer -> Bool
validateTotalSum ctx threshold =
  (_>= threshold) $
  (get "") $
  (get "") $
  getValue $
  (mconcat (fmap (txOutValue . txInInfoResolved))) $
  txInfoInput $ ctx

-- Checks if the given Datum corresponds to a project proposal
isProjectProposal :: CrowdFundingDatum -> Bool
isProjectProposal (ProjectProposal _ _ _ _) = True
isProjectProposal _ = False

-- Check that the context only contains a single instance of a project proposal
validateSingleProposal :: ScriptContext -> Bool
validateSingleProposal =
  (== 1) .
  length .
  (filter isProjectProposal) .
  (fmap (fromJSON . toJSON . snd)) .
  txInfoData .
  scriptContextTxInfo

--  1 == length (filter isProjectProposal (fmap snd (txInfoData (scriptContextTxInfo ctx))))

validateCrowdFunding :: CrowdFundingDatum -> CrowdFundingRedeemer -> ScriptContext -> Bool
-- We can always cancel the project regarding the project proposal
validateCrowdFunding (ProjectProposal _    _  _      _       ) Cancel _   = True
-- To launch the project, we need to check if the total amount of money is enough
-- We also need to check whether the current time is part of the time range
-- Finally, we need to check if there is a single instance of a project proposal
validateCrowdFunding (ProjectProposal _    id threshold range) (Launch _ _ time) ctx =
  traceIfFalse "Current time not in the time range." (validateTimeRange time range) &&
  traceIfFalse "The project has not reach its funding threshold." (validateTotalSum ctx threshold) &&
  traceIfFalse "There are multiple project proposals." (validateSingleProposal ctx)
validateCrowdFunding (Funding hash id) (Launch _ _ _) ctx = True
validateCrowdFunding (Funding hash id) Cancel ctx = True

-- data CrowdFunding

-- PlTx.makeLift ''CrowdFundingDatum
-- PlTx.unstableMakeIsData ''CrowdFundingDatum

-- instance Scripts.ValidatorTypes CrowdFunding where
--   type RedeemerType CrowdFunding = CrowdFundingRedeemer
--   type DatumType CrowdFunding = CrowdFundingDatum

-- crowdFundingValidator :: Scripts.TypedValidator CrowdFunding
-- crowdFundingValidator =
--   Scripts.mkTypedValidator @CrowdFunding
--     $$(PlTx.compile [||validateCrowdFunding||])
--     $$(PlTx.compile [||wrap||])
--   where
--     wrap = Scripts.wrapValidator @CrowdFundingDatum @CrowdFundingRedeemer







