module NativePreflight (NativeReport(..), checkSharedLibraries, summarizeNativeReport) where

import Control.Exception (IOException, try)
import Data.List (isInfixOf, nub)
import System.Directory (doesFileExist)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)

data NativeReport = NativeReady FilePath | NativeMissing FilePath [String] | NativeUnavailable FilePath String deriving (Eq, Show)

checkSharedLibraries :: FilePath -> IO NativeReport
checkSharedLibraries executable = do
  exists <- doesFileExist executable
  if not exists then pure (NativeUnavailable executable "executable not installed") else do
    outcome <- try (readProcessWithExitCode "ldd" [executable] "") :: IO (Either IOException (ExitCode, String, String))
    pure $ case outcome of
      Left _ -> NativeUnavailable executable "could not execute ldd"
      Right (code, out, err) ->
        let missing = nub [name | line <- lines out, "=> not found" `isInfixOf` line, name:_ <- [words line]]
        in if not (null missing) then NativeMissing executable missing
           else if code == ExitSuccess then NativeReady executable
           else NativeUnavailable executable (take 240 (unwords (words (out ++ " " ++ err))))

summarizeNativeReport :: NativeReport -> String
summarizeNativeReport report = case report of
  NativeReady path -> path ++ ": native dependencies resolved"
  NativeMissing path names -> path ++ ": missing native libraries: " ++ unwords names
  NativeUnavailable path reason -> path ++ ": preflight unavailable: " ++ reason
