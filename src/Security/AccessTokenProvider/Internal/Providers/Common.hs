{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Security.AccessTokenProvider.Internal.Providers.Common
  ( tryNewProvider
  , tryEnvDeserialization
  ) where

import           Control.Exception.Safe
import           Control.Lens
import           Control.Monad.IO.Class
import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Maybe
import           Data.Aeson
import           Data.Aeson.Lens
import           Data.Format
import           Data.List.NonEmpty                                   (NonEmpty)
import qualified Data.List.NonEmpty                                   as NonEmpty
import           Data.Text                                            (Text)
import qualified Data.Text.Encoding                                   as Text

import           Security.AccessTokenProvider.Internal.Types
import qualified Security.AccessTokenProvider.Internal.Types.Severity as Severity
import           Security.AccessTokenProvider.Internal.Util

tryNewProvider
  :: (MonadIO m, MonadThrow m)
  => AccessTokenName
  -> m (Maybe envConf)
  -> (envConf -> m conf)
  -> (AccessTokenName -> conf -> m (Maybe (AccessTokenProvider m t)))
  -> m (Maybe (AccessTokenProvider m t))
tryNewProvider tokenName makeEnvConf makeConf providerBuilder = do
  maybeEnvConf <- makeEnvConf
  case maybeEnvConf of
    Just envConf -> do
      conf <- makeConf envConf
      providerBuilder tokenName conf
    Nothing ->
      pure Nothing

atpConfVarName :: Text
atpConfVarName = "ATP_CONF"

tryEnvDeserialization
  :: ( MonadThrow m
     , FromJSON a )
  => Backend m
  -> NonEmpty Text
  -> m (Maybe a)
tryEnvDeserialization backend providers = do
  let BackendEnv { .. } = backendEnv backend
      BackendLog { .. } = backendLog backend
  maybeConf <- runMaybeT $ do
    envVal <- MaybeT $ envLookup atpConfVarName
    jsonVal :: Value <- lift $ throwDecode (Text.encodeUtf8 envVal)
    provider <- MaybeT . pure $ jsonVal ^? key "provider" . _String
    lift $ logMsg Severity.Debug [fmt|ATP_CONF requests AccessTokenProvider '${provider}'|]
    if provider `elem` providers
      then do lift $ logMsg Severity.Info [fmt|Using AccessTokenProvider '${NonEmpty.head providers}'|]
              pure jsonVal
      else MaybeT (pure Nothing)
  case maybeConf of
    Just conf ->
      Just <$> throwDecodeValue conf
    Nothing ->
      pure Nothing
