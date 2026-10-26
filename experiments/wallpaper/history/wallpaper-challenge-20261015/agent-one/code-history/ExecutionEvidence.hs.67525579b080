{-# LANGUAGE BangPatterns #-}
module ExecutionEvidence (EvidenceFocus(..), summarizeLog, summarizeLogWith, LoggedResult(..), runLogged, checkAgentSource, checkAgentRuntime, checkStepSource, buildAgent, runScript) where

import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Char (toLower, isSpace, isDigit)
import Data.List (isInfixOf, isPrefixOf, stripPrefix, sortOn)
import Data.Maybe (mapMaybe)
import Control.Exception (bracket, try, IOException)
import System.Posix.Signals (signalProcessGroup, sigTERM, sigKILL)
import System.Exit (ExitCode(..))
import System.Process
import System.Timeout (timeout)
import System.IO
import StepLoader (loadStep)

import System.Posix.Process (getProcessID, getParentProcessID)
import System.IO.Error (ioeGetErrorString)

data EvidenceFocus = DiagnoseFailure | InspectOutcome | InspectText deriving (Eq,Show)

summarizeLog :: Int -> FilePath -> IO String
summarizeLog = summarizeLogWith DiagnoseFailure

summarizeLogWith :: EvidenceFocus -> Int -> FilePath -> IO String
summarizeLogWith focus limit path
  | limit < 256 = ioError (userError "Evidence budget must be at least 256 characters")
  | otherwise = summarizeWithin focus limit path

summarizeWithin :: EvidenceFocus -> Int -> FilePath -> IO String
summarizeWithin focus limit path = withBinaryFile path ReadMode $ \h -> do
      size <- hFileSize h
      let completeHeader = "Log bytes: " ++ show size ++ "; complete output\n"
      if size <= fromIntegral (limit - length completeHeader) then do
        raw <- B.hGet h (fromIntegral size)
        let decoded = T.unpack (TE.decodeUtf8With lenientDecode raw)
        pure (completeHeader ++ (if focus == InspectText then decoded else stripCSI decoded))
      else if focus == InspectText then compactText h size else compact h
  where
    compactText h size = do
      let header = "Log bytes: " ++ show size ++ "; focus: InspectText\nHEAD\n"
          marker n = "\n[omitted " ++ show n ++ " bytes]\nTAIL\n"
          reference = "\nFull content: " ++ path ++ "\n"
          includeReference = length header + length (marker size) + length reference + 16 <= limit
          location = if includeReference then reference else ""
          chunk = max 0 ((limit - length header - length (marker size) - length location) `div` 2)
      headBytes <- B.hGet h chunk
      hSeek h AbsoluteSeek (size - fromIntegral chunk)
      tailBytes <- B.hGet h chunk
      let omitted = size - fromIntegral (B.length headBytes + B.length tailBytes)
          decode = T.unpack . TE.decodeUtf8With lenientDecode
      pure $ take limit (header ++ decode headBytes ++ marker omitted ++ decode tailBytes ++ location)
    compact h = do
      (total, first, evidence, recent, warnings) <- scan h 0 "" [] "" (0 :: Int) ""
      let header = "Log bytes: " ++ show total ++ "; focus: " ++ show focus ++ "; GHC warning headers: " ++ show warnings ++ "\n"
          facts = packFacts (limit `div` 2) (map snd evidence)
          remaining = max 0 (limit - length header - length facts - 32)
      pure $ take limit (header ++ "EVIDENCE\n" ++ facts ++ "HEAD\n" ++ take (remaining `div` 2) first ++ "\nTAIL\n" ++ suffix (remaining - remaining `div` 2) recent)
    room = limit `div` 2
    scan h !total !first !evidence !recent !warnings !pending = do
      eof <- hIsEOF h
      if eof then pure (total,first,evidence,recent,warnings) else do
        raw <- B.hGetLine h
        consumed <- hTell h
        let text = stripCSI (T.unpack (TE.decodeUtf8With lenientDecode raw))
            warning = isGhcWarning text
            continuation = not (null pending) && not (null text) && isSpace (head text)
            grouped = if continuation then [(if "error: [GHC-" `isInfixOf` pending then 96 else 93, clipFact 240 (pending ++ " — " ++ dropWhile isSpace text))] else []
            contextual = if continuation then filter ((/= pending) . snd) evidence else evidence
            terminal = "runner exit:" `isPrefixOf` map toLower (dropWhile isSpace text)
            prior = if terminal then filter ((/= 110) . fst) contextual else contextual
            evidence' = take 12 $ sortOn (negate . fst) $ foldl insert prior (grouped ++ extract focus text)
            pending' = if warning || "error: [GHC-" `isInfixOf` text then clipFact 160 text else if null text then pending else ""
            first' = take room (first ++ text ++ "\n")
            recent' = suffix room (recent ++ suffix room text ++ "\n")
        scan h consumed first' evidence' recent' (warnings + if warning then 1 else 0) pending'

suffix :: Int -> String -> String
suffix n s = drop (max 0 (length s - n)) s

insert :: [(Int,String)] -> (Int,String) -> [(Int,String)]
insert rows row = if any ((== snd row) . snd) rows then rows else rows ++ [row]

extract :: EvidenceFocus -> String -> [(Int,String)]
extract InspectText _ = []
extract focus text = terminalStatus ++ roots ++ compilerErrors ++ compilerWarnings ++ generic
  where
    lower = map toLower text
    after needle = mapMaybe (stripPrefix needle) (tails text)
    roots = [(100,"Missing shared library: " ++ cleanLibrary name) | rest <- after "error while loading shared libraries:", name:_ <- [words rest], validLibrary name]
         ++ [(100,"Missing shared library: " ++ cleanLibrary name) | "=> not found" `isInfixOf` text, name:_ <- [words text], validLibrary name]
    failure = any (`isInfixOf` lower) ["error:","exitfailure","failed","timed out","not found"]
    normalized = dropWhile isSpace lower
    outcome = any (`isPrefixOf` normalized)
      ["runner exit:", "exitsuccess", "browser errors:", "pagination:", "dashboard http:",
       "paper http:", "http ", "http:", "mobile overflow:",
       "live rendered stories:", "typescript:", "live story:"]

    terminalStatus = [(110, clipFact 160 text) | "runner exit:" `isPrefixOf` normalized]
    compilerWarnings = [(92, clipFact 160 text) | isGhcWarning text]
    compilerErrors = [(95, clipFact 160 text) |
      ("error ts" `isPrefixOf` normalized && ':' `elem` normalized) ||
      ("error: [ghc-" `isInfixOf` normalized) ||
      any (`isPrefixOf` normalized)
        ["parse error on input", "couldn't match type", "could not find module",
         "not in scope:", "suggested fix:"]]

    generic = [(if focus == DiagnoseFailure then 70 else 40, clipFact 160 text) | failure && null roots && null terminalStatus && null compilerErrors]
           ++ [(if focus == InspectOutcome then 90 else 60, clipFact 160 text) | outcome && null terminalStatus]

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_:rest) = xs : tails rest

data LoggedResult = LoggedResult { loggedExit :: Maybe ExitCode, loggedSummary :: String } deriving (Eq,Show)

runLogged :: EvidenceFocus -> Int -> Int -> FilePath -> FilePath -> FilePath -> [String] -> IO LoggedResult
runLogged focus budget seconds cwdPath logPath command args
  | seconds < 1 || seconds > 45 = ioError (userError "Command timeout must be 1..45 seconds")
  | budget < 256 = ioError (userError "Evidence budget must be at least 256 characters")
  | length logPath + 45 > budget - 128 = ioError (userError "Evidence budget cannot fit artifact path and summary; increase budget")
  | otherwise = do
      outcome <- try $ withFile logPath WriteMode $ \h ->
        bracket
          (do
            (_,_,_,child) <- createProcess (proc command args)
              { cwd = Just cwdPath, std_in = NoStream, std_out = UseHandle h, std_err = UseHandle h, create_group = True }
            pid <- getPid child
            pure (child,pid))
          (\(child,pid) -> do
            case pid of
              Just p -> do
                _ <- try (signalProcessGroup sigTERM p) :: IO (Either IOException ())
                _ <- timeout 250000 (waitForProcess child)
                _ <- try (signalProcessGroup sigKILL p) :: IO (Either IOException ())
                pure ()
              Nothing -> pure ()
            _ <- timeout 2000000 (waitForProcess child)
            pure ())
          (\(child,_) -> timeout (seconds * 1000000) (waitForProcess child))
      code <- case (outcome :: Either IOException (Maybe ExitCode)) of
        Right Nothing -> do
          appendFile logPath ("\nERROR: command timed out after " ++ show seconds ++ " seconds; cleanup attempted\n")
          pure Nothing
        Right (Just exit) -> do
          appendFile logPath ("\nRUNNER EXIT: " ++ show exit ++ "\n")
          pure (Just exit)
        Left err -> do
          let executable = reverse (takeWhile (/= '/') (reverse command))
          appendFile logPath ("\nERROR: command I/O failure for executable " ++ show executable ++ ": " ++ ioeGetErrorString err ++ "\n")
          pure (Just (ExitFailure 127))
      let effectiveFocus = case (focus,code) of

            (InspectOutcome,Just ExitSuccess) -> InspectOutcome
            (InspectOutcome,_) -> DiagnoseFailure
            _ -> focus
      let status = maybe "COMMAND TIMED OUT" (\c -> "COMMAND " ++ show c) code
      let reportHeader = status ++ "\nLog artifact: " ++ logPath ++ "\n"
      summary <- summarizeWithin effectiveFocus (budget - length reportHeader) logPath


      pure (LoggedResult code (take budget (reportHeader ++ summary)))

packFacts :: Int -> [String] -> String
packFacts budget = go budget
  where
    go _ [] = ""
    go remaining (fact:rest)
      | length fact + 1 <= remaining = fact ++ "\n" ++ go (remaining - length fact - 1) rest
      | " — " `isInfixOf` fact && length header + 1 <= remaining =
          header ++ "\n" ++ go (remaining - length header - 1) rest
      | otherwise = go remaining rest
      where header = reverse (dropWhile isSpace (reverse (takeWhile (/= '—') fact)))

stripCSI :: String -> String
stripCSI [] = []
stripCSI ('\ESC':'[':rest) =
  let (parameters, final) = span (\c -> c >= '\x20' && c <= '\x3f') rest
  in case final of
    c:xs | c >= '\x40' && c <= '\x7e' -> stripCSI xs
    _ -> '\ESC':'[':parameters ++ stripCSI final
stripCSI (c:rest) = c : stripCSI rest

clipFact :: Int -> String -> String
clipFact budget text
  | length (take (budget + 1) text) <= budget = text
  | otherwise =
      let available = budget - length marker
          front = available `div` 2
      in take front text ++ marker ++ suffix (available - front) text
  where marker = " [truncated]"

checkAgentSource :: FilePath -> IO LoggedResult
checkAgentSource logPath =
  runScript InspectOutcome 2400 45 "/workspace" logPath $ unlines
      [ "before=$(sha256sum app/Main.hs RequestGate.hs StepLoader.hs ContextWindow.hs ExecutionEvidence.hs NativePreflight.hs agent-one.cabal stack.yaml stack.yaml.lock)"
      , "printf 'SOURCE SNAPSHOT (SHA-256):\\n%s\\n' \"$before\""
      , "compile_status=0"
      , "stack --allow-different-user exec -- sh -c 'set -eu; printf \"Compiler GHC: \"; ghc --numeric-version; printf \"Compiler target: \"; ghc --print-target-platform; exec ghc -fno-code -Wall -iapp -i. -XOverloadedStrings -XScopedTypeVariables app/Main.hs ExecutionEvidence.hs NativePreflight.hs' || compile_status=$?"
      , "after=$(sha256sum app/Main.hs RequestGate.hs StepLoader.hs ContextWindow.hs ExecutionEvidence.hs NativePreflight.hs agent-one.cabal stack.yaml stack.yaml.lock)"
      , "if [ \"$before\" != \"$after\" ]; then printf 'ERROR: source changed during diagnosis\\n'; exit 1; fi"
      , "printf 'Source snapshot unchanged during diagnosis\\n'"
      , "exit \"$compile_status\""
      ]

checkAgentRuntime :: FilePath -> IO LoggedResult
checkAgentRuntime logPath = do
  pid <- getProcessID
  parent <- getParentProcessID
  runLogged InspectText 2400 20 "/workspace" logPath "sh"
    ["-c", unlines
      [ "set -eu"
      , "installed=$(stack --allow-different-user path --local-install-root)/bin/agent-one"
      , "b=$(sha256sum \"$installed\" | cut -d ' ' -f1)"
      , "printf 'Installed SHA-256: %s\\n' \"$b\""
      , "inspect() { role=$1; pid=$2; live=/proc/$pid/exe; printf '%s PID: %s\\n' \"$role\" \"$pid\"; printf '%s executable: ' \"$role\"; readlink \"$live\"; a=$(sha256sum \"$live\" | cut -d ' ' -f1); printf '%s SHA-256: %s\\n' \"$role\" \"$a\"; if [ \"$a\" = \"$b\" ]; then printf '%s matches installed binary\\n' \"$role\"; else printf '%s differs from installed binary\\n' \"$role\"; fi; }"
      , "inspect Worker " ++ show pid
      , "inspect Parent " ++ show parent
      ]]

isGhcWarning :: String -> Bool
isGhcWarning text = case words (map toLower (dropWhile isSpace text)) of
  location:"warning:":code:_ -> "[ghc-" `isPrefixOf` code && located location
  "<no":"location":"info>:":"warning:":code:_ -> "[ghc-" `isPrefixOf` code
  _ -> False
  where
    located location = case reverse (splitColon location) of
      "":column:line:fileParts -> numeric column && numeric line && not (null fileParts)
      _ -> False
    numeric s = not (null s) && all isDigit s
    splitColon s = case break (== ':') s of
      (piece,[]) -> [piece]
      (piece,_:rest) -> piece : splitColon rest

cleanLibrary :: String -> String
cleanLibrary = reverse . dropWhile (== ':') . reverse

validLibrary :: String -> Bool
validLibrary raw =
  let name = cleanLibrary raw
  in ".so" `isInfixOf` name && not (null name) &&
     all (\c -> c `elem` ['a'..'z'] || c `elem` ['A'..'Z'] ||
                c `elem` ['0'..'9'] || c `elem` ("._+-/" :: String)) name

checkStepSource :: FilePath -> IO (Either String ())
checkStepSource path = do
  checked <- loadStep path
  pure $ either (Left . show) (const (Right ())) checked

buildAgent :: FilePath -> IO LoggedResult
buildAgent logPath = runLogged InspectOutcome 2400 45 "/workspace" logPath
  "stack" ["--allow-different-user", "build"]

runScript :: EvidenceFocus -> Int -> Int -> FilePath -> FilePath -> String -> IO LoggedResult
runScript focus budget seconds cwdPath logPath script =
  runLogged focus budget seconds cwdPath logPath "bash"
    ["-o", "pipefail", "-e", "-u", "-c", "trap 'printf \"ERROR: script line %s exited %s\\n\" \"$((LINENO - 1))\" \"$?\" >&2' ERR\n" ++ script]
