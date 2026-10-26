module Main where

import Control.Concurrent
import Control.Concurrent.Async
import Control.Concurrent.STM
import RequestGate (awaitSuperseded, resetIfStarted, beginExecution, finishExecution, failureFeedback, pauseIfCurrent, pauseFeedback)
import Control.Exception
import Control.Monad
import Data.Aeson
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.Char (isSpace, toUpper)
import Data.IORef
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TE
import qualified Data.Text.IO as T
import Data.Time.Clock.POSIX
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import ExecutionRuntime
import ModelConnection (askModel)
import qualified A2A
import ChatGPTAuth (authCommand)
import ContextWindow (prepareContext)
import System.Directory
import System.Environment
import System.Exit
import System.IO
import System.IO.Error (isEOFError)
import System.Posix.Signals
import System.Process
import System.Timeout
import Text.Read (readMaybe)

loadEnv :: IO ()
loadEnv = do
  exists <- doesFileExist ".env"
  when exists $ do
    content <- readFile ".env"
    forM_ (lines content) $ \line -> do
      let (name, rest) = break (== '=') $ dropWhile isSpace line
      unless (null rest || null name || head name == '#') $ do
        old <- lookupEnv name
        let raw = T.unpack $ T.strip $ T.pack $ tail rest
            value = maybe raw id (readMaybe raw :: Maybe String)
        when (old == Nothing) $ setEnv name value

record = recordAt ".runs/conversation.json"

supervisor :: IO ()
supervisor = do
  loadEnv
  endpoint <- fromMaybe "" <$> lookupEnv "LLM_ENDPOINT"
  key <- fromMaybe "" <$> lookupEnv "LLM_API_KEY"
  model <- getEnv "LLM_MODEL"
  session <- getPOSIXTime >>= makeAbsolute . (".runs/haskell-" ++) . show . (floor :: POSIXTime -> Integer) . (* 1000000)
  createDirectoryIfMissing True session
  instructionFile <- maybe "SYSTEM.md" id <$> lookupEnv "INSTRUCTIONS_FILE"
  automatic <- doesFileExist instructionFile
  exists <- doesFileExist ".runs/conversation.json"
  restored <- if exists then B.readFile ".runs/conversation.json" >>= either (ioError . userError) pure . eitherDecodeStrict'
    else pure $ Conversation [] False
  conversation <- newMVar restored
  let restoredCount = length $ conversationMessages restored
  when (restoredCount > 0) $ record conversation (Just False) $ message "user" $
    "Conversation restored after supervisor restart. Worker memory and actions were reset; files persist. " <>
    (if executionPending restored then "The previous step was interrupted and may have partially executed; inspect its artifacts before repeating effects. " else "") <>
    "Continue the current task from this conversation; do not repeat completed work."
  startPaused <- (== Just "1") <$> lookupEnv "AGENT_START_PAUSED"
  paused <- newTVarIO (startPaused || not automatic)
  generation <- newTVarIO (0 :: Int)
  when (automatic && restoredCount == 0) $ record conversation Nothing $ message "user" $ "Begin following " <> T.pack instructionFile <> "."
  let events value = BL.appendFile (session ++ "/events.jsonl") $ encode value <> "\n"
      terminal = do
        line <- T.strip <$> T.getLine
        case line of
          "/quit" -> pure ()
          "/pause" -> atomically (writeTVar paused True) >> putStrLn "[paused]" >> terminal
          "/resume" -> atomically (modifyTVar' generation (+ 1) >> writeTVar paused False) >> terminal
          "" -> terminal
          _ -> do
            record conversation Nothing $ message "user" line
            events $ object ["user" .= line]
            atomically $ modifyTVar' generation (+ 1) >> writeTVar paused False
            putStrLn "[message saved]"
            terminal
      loop workers n waiting = do
        requestGeneration <- atomically $ do
          readTVar paused >>= check . not
          current <- readTVar generation
          forM_ waiting $ \previous -> check (current /= previous)
          pure current
        context <- conversationMessages <$> readMVar conversation
        let file = session ++ "/Step" ++ show n ++ ".hs"
        executionStarted <- newTVarIO False
        outcome <- race (atomically $ awaitSuperseded paused generation requestGeneration) $ trySync $ do
          putStrLn $ "\n[step " ++ show n ++ "]"
          result <- modelStep (ModelConfig endpoint key model instructionFile) workers context file (session ++ "/llm-" ++ show n ++ ".request.json")
            (void $ atomically $ beginExecution paused generation requestGeneration executionStarted)
            (record conversation (Just True)) (record conversation (Just False))
          let feedback = executionFeedback result; again = executionContinue result
          atomically $ finishExecution executionStarted
          events $ object ["step" .= n, "source_file" .= file, "output" .= feedback, "continue" .= again]
          pure again
        case outcome of
          Left () -> do
            reset <- resetIfStarted executionStarted $ modifyMVar_ workers $ \w -> stopWorker w >> startWorker
            putStrLn $ if reset then "[worker restarted; live memory reset]" else "[request cancelled; worker memory preserved]"
            record conversation (Just False) $ message "user" $ if reset
              then "User paused or superseded execution. Worker memory and actions were reset; files remain and effects may be partial."
              else "User paused or superseded work with no execution awaiting feedback. Worker memory and actions were preserved; previously completed steps may have executed."
            loop workers (n + 1) Nothing
          Right (Left err) -> do
            let detail = (if null key then id else T.replace (T.pack key) "[redacted]") $ T.pack $ displayException err
            T.putStrLn $ "[error; recovering]\n" <> detail
            events $ object ["step" .= n, "error" .= detail]
            executing <- executionPending <$> readMVar conversation
            record conversation (Just False) $ message "user" $ T.pack $ failureFeedback executing (T.unpack detail)
            reset <- resetIfStarted executionStarted $ modifyMVar_ workers $ \w -> stopWorker w >> startWorker
            when reset $ record conversation (Just False) $ message "user" "Execution transport failed. Worker restarted; memory and actions were reset. Files persist and effects may be partial."
            didPause <- atomically $ pauseIfCurrent paused generation requestGeneration
            putStrLn $ pauseFeedback didPause
            record conversation Nothing $ message "user" $ T.pack $ pauseFeedback didPause
            loop workers (n + 1) Nothing
          Right (Right again) -> do
            unless again $ putStrLn "[waiting for input; no LLM calls scheduled]"
            loop workers (n + 1) (if again then Nothing else Just requestGeneration)
  putStrLn $ "Agent One (Haskell) — type a message. /pause /resume /quit. Ctrl+C exits.\nSession: " ++ session
  putStrLn $ "[conversation restored: " ++ show restoredCount ++ " messages; .runs/conversation.json]"
  bracket (newMVar =<< startWorker) (\workers -> withMVar workers stopWorker) $ \workers ->
    race_ (terminal `catch` \e -> unless (isEOFError e) $ throwIO e) (loop workers (1 :: Int) Nothing)

main :: IO ()
main = do
  mapM_ (`hSetBuffering` NoBuffering) [stdout, stderr]
  args <- getArgs
  case args of
    ["--worker"] -> worker
    ["--a2a"] -> loadEnv >> A2A.serve
    ["--a2a-call",url,method,params] -> A2A.clientMain url method params
    "auth":command -> loadEnv >> authCommand command
    [] -> supervisor
    _ -> ioError $ userError "Usage: agent-one [auth COMMAND]"
