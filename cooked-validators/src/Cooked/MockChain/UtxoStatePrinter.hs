{-# LANGUAGE OverloadedStrings #-}

module Cooked.MockChain.UtxoStatePrinter (prettyUtxoState) where

import Cooked.MockChain.Base (UtxoState)
import qualified Data.Map as Map (toList)
import Data.Proxy (Proxy)
import qualified Ledger as Pl
import qualified Ledger.Value as Pl
import qualified Plutus.V2.Ledger.Api as Pl
import qualified PlutusTx.AssocMap as Pl
import Prettyprinter (Doc)
import qualified Prettyprinter

prettyTokenValue :: (Pl.CurrencySymbol, Pl.Map Pl.TokenName Integer) -> Doc ann
prettyTokenValue (symb, amountMap) =
  case (symb, Pl.toList amountMap) of
    ("", [("", adaAmount)]) ->
      "Ada" <> Prettyprinter.colon <> Prettyprinter.pretty adaAmount
    (_, tokenValueMap) ->
      Prettyprinter.pretty symb
        <> Prettyprinter.colon
        <> Prettyprinter.pretty tokenValueMap

-- Unsafe: address carries either pubkey or validator hash but
-- the API does not expose the constructors to pattern match.
prettyAddressTypeAndHash :: Pl.Address -> Doc ann
prettyAddressTypeAndHash a =
  case Pl.toPubKeyHash a of
    Nothing ->
      case Pl.toValidatorHash a of
        Nothing -> error "Printing address: Neither pubkey nor validator hash"
        Just hash ->
          "script" <> Prettyprinter.colon <> prettyCutHash hash
    Just hash ->
      "pubkey" <> Prettyprinter.colon <> prettyCutHash hash
  where
    prettyCutHash :: Show a => a -> Doc ann
    prettyCutHash = Prettyprinter.pretty . take 7 . show

prettyValue :: Pl.Value -> Doc ann
prettyValue =
  Prettyprinter.encloseSep "{" "}" "; "
    . map prettyTokenValue
    . Pl.toList
    . Pl.getValue

-- Unsafe
-- TODO Consider also using `prettyprinter` lib for datum
prettyDatum ::
  (Show a, Pl.UnsafeFromData a) =>
  -- | Proxy carrying the datum type
  Proxy a ->
  -- | Raw Plutus datum to show
  Pl.Datum ->
  Doc ann
prettyDatum proxy = Prettyprinter.pretty . show . convert proxy . Pl.getDatum
  where
    convert :: Pl.UnsafeFromData a => Proxy a -> Pl.BuiltinData -> a
    convert _proxy = Pl.unsafeFromBuiltinData

-- Unsafe
prettyPayload ::
  (Show a, Pl.UnsafeFromData a) =>
  -- | Proxy carrying the datum type
  Proxy a ->
  (Pl.Value, Maybe Pl.Datum) ->
  Doc ann
prettyPayload proxy (value, mDatum) =
  Prettyprinter.vsep
    [ prettyValue value,
      maybe
        Prettyprinter.emptyDoc
        (Prettyprinter.parens . prettyDatum proxy)
        mDatum
    ]

-- Unsafe
prettyAddress ::
  (Show a, Pl.UnsafeFromData a) =>
  -- | Proxy carrying the datum type
  Proxy a ->
  -- | Adress to show
  (Pl.Address, [(Pl.Value, Maybe Pl.Datum)]) ->
  Doc ann
prettyAddress proxy (address, payloads) =
  Prettyprinter.vsep
    [ prettyAddressTypeAndHash address,
      Prettyprinter.indent 2
        . Prettyprinter.vsep
        . map (("-" <>) . Prettyprinter.indent 1 . prettyPayload proxy)
        $ payloads
    ]

-- Unsafe
prettyUtxoState ::
  (Show a, Pl.UnsafeFromData a) =>
  -- | Proxy carrying the datum type
  Proxy a ->
  -- | UtxoState to show
  UtxoState ->
  Doc ann
prettyUtxoState proxy =
  Prettyprinter.vsep . map (prettyAddress proxy) . Map.toList
