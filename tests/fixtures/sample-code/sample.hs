{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}

-- ============================================================================
-- Solarized Dark Showcase: Haskell (GHC 9.8 / Haskell2021 Pure Functional)
-- ============================================================================

module Core.Telemetry
  ( NodeId
  , Severity (..)
  , MetricSample (..)
  , Measurable (..)
  , clampScore
  , classifySample
  , summarizeBatch
  , ingestStream
  ) where

import qualified Data.Map.Strict as Map
import Data.List (foldl', filter)
import GHC.Generics (Generic)

type NodeId = String

newtype WindowMs = WindowMs Int
  deriving (Eq, Ord, Show)

data Severity
  = Info
  | Warn
  | Critical
  | Fatal
  deriving (Eq, Ord, Show, Generic)

data MetricSample = MetricSample
  { sampleNode  :: NodeId
  , sampleScore :: Double
  , sampleCount :: Integer
  , sampleValid :: Bool
  , sampleCode  :: Char
  } deriving (Eq, Show)

class Measurable a where
  measureScore :: a -> Double
  isHealthy    :: a -> Bool

instance Measurable MetricSample where
  measureScore sample = sampleScore sample
  isHealthy sample    = sampleValid sample && sampleScore sample < 85.0

clampScore :: forall a. (Ord a, Num a) => a -> a -> a -> a
clampScore lower upper val
  | val < lower = lower
  | val > upper = upper
  | otherwise   = val

classifySample :: MetricSample -> Maybe Severity
classifySample sample
  | not (sampleValid sample) = Nothing
  | score >= 95.0            = Just Fatal
  | score >= 80.0            = Just Critical
  | score >= 60.0            = Just Warn
  | otherwise                = Just Info
  where
    score = clampScore 0.0 100.0 (sampleScore sample)

summarizeBatch :: [MetricSample] -> Map.Map NodeId Double
summarizeBatch samples =
  let validSamples = filter isHealthy samples
      step acc item =
        case classifySample item of
          Nothing  -> acc
          Just sev ->
            let weight = if sev == Critical then 2.0 else 1.0
                delta  = measureScore item * weight
            in Map.insertWith (+) (sampleNode item) delta acc
  in foldl' step Map.empty validSamples

ingestStream :: NodeId -> [MetricSample] -> IO (Either String Double)
ingestStream primaryNode batch = do
  let summary = summarizeBatch batch
  case Map.lookup primaryNode summary of
    Nothing  -> pure (Left "missing primary node telemetry\n")
    Just val ->
      if val <= 0.0
        then pure (Left "empty telemetry batch\n")
        else pure (Right val)
