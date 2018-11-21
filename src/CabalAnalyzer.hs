module CabalAnalyzer (analyzeCabalFileDefaultTarget) where

import Distribution.Types.GenericPackageDescription
import Distribution.PackageDescription.Parsec
import Distribution.Verbosity
import Distribution.Version
import Distribution.Types.CondTree
import Distribution.Types.UnqualComponentName
import Distribution.Types.Dependency
import Distribution.Types.VersionRange
import Distribution.Types.PackageName

import System.Environment
import Data.List (find, intercalate)
import Data.Maybe (isJust)
import Data.Bits (xor)

import VabalError


baseToGHCMap :: [(Version, Version)]
baseToGHCMap = reverse
    [ (mkVersion [4,0,0,0], mkVersion [6,10,1])
    , (mkVersion [4,1,0,0], mkVersion [6,10,2])
    , (mkVersion [4,2,0,0], mkVersion [6,12,1])
    , (mkVersion [4,2,0,1], mkVersion [6,12,2])
    , (mkVersion [4,2,0,2], mkVersion [6,12,3])
    , (mkVersion [4,3,0,0], mkVersion [7,0,1])
    , (mkVersion [4,3,1,0], mkVersion [7,0,2])
    , (mkVersion [4,4,0,0], mkVersion [7,2,1])
    , (mkVersion [4,4,1,0], mkVersion [7,2,2])
    , (mkVersion [4,5,0,0], mkVersion [7,4,1])
    , (mkVersion [4,5,1,0], mkVersion [7,4,2])
    , (mkVersion [4,6,0,0], mkVersion [7,6,1])
    , (mkVersion [4,6,0,1], mkVersion [7,6,2])
    , (mkVersion [4,7,0,0], mkVersion [7,8,1])
    , (mkVersion [4,7,0,1], mkVersion [7,8,3])
    , (mkVersion [4,7,0,2], mkVersion [7,8,4])
    , (mkVersion [4,8,0,0], mkVersion [7,10,1])
    , (mkVersion [4,8,1,0], mkVersion [7,10,2])
    , (mkVersion [4,8,2,0], mkVersion [7,10,3])
    , (mkVersion [4,9,0,0], mkVersion [8,0,1])
    , (mkVersion [4,9,1,0], mkVersion [8,0,2])
    , (mkVersion [4,10,0,0], mkVersion [8,2,1])
    , (mkVersion [4,10,1,0], mkVersion [8,2,2])
    , (mkVersion [4,11,0,0], mkVersion [8,4,1])
    , (mkVersion [4,11,1,0], mkVersion [8,4,2])
    , (mkVersion [4,11,1,0], mkVersion [8,4,3])
    , (mkVersion [4,12,0,0], mkVersion [8,6,1])
    , (mkVersion [4,12,0,0], mkVersion [8,6,2])
    ]

-- TODO: Use binary search
getNewestGHCFromVersionRange :: VersionRange -> Maybe Version
getNewestGHCFromVersionRange vr = snd <$> find (versionInRange vr . fst) baseToGHCMap
    where versionInRange :: VersionRange -> Version -> Bool
          versionInRange = flip withinRange


prettyPrintVersion :: Version -> String
prettyPrintVersion ver = intercalate "." $ map show (versionNumbers ver)

analyzeCabalFileDefaultTarget :: FilePath -> IO String
analyzeCabalFileDefaultTarget filepath = do
    res <- readGenericPackageDescription normal filepath
    let canDetermineDefaultTarget = isJust (condLibrary res) `xor` (not . null $ condExecutables res)

    if not canDetermineDefaultTarget then
        throwVabalError "Can't determine default target"
    else do
        let baseVersion = case condLibrary res of
                            Just lib -> analyzeTarget lib
                            Nothing  -> analyzeTarget (snd . head $ condExecutables res)

        case baseVersion of
            Nothing -> throwVabalError "Error, no base package found"
            Just baseVersion -> do
                case getNewestGHCFromVersionRange baseVersion of
                    Nothing -> throwVabalError "Error, could not satisfy constraints"
                    Just version -> return $ prettyPrintVersion version


analyzeTarget :: CondTree ConfVar [Dependency] a -> Maybe VersionRange
analyzeTarget deps = simplifyVersionRange <$> getBaseConstraint (condTreeConstraints deps)

getBaseConstraint :: [Dependency] -> Maybe VersionRange
getBaseConstraint deps = depVerRange <$> find isBase deps
    where isBase (Dependency packageName _) = unPackageName packageName == "base"
