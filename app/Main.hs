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
import StepLoader (loadStep)
import LifecycleContext (loadLifecycle, applyLifecycle)
import ModelConnection (askModel)
import ContextWindow (prepareContextWith, latestUserIntent)
import RemedyMemory (readRemedyRecords, selectFromRecords)
import System.Directory
import System.Environment
import System.Exit
import System.IO
import System.IO.Error (isEOFError)
import System.Posix.Signals
import System.Process
import System.Timeout
import Text.Read (readMaybe)

type Worker = (Handle, ProcessHandle)
type Memory = IORef (M.Map String String)
type Actions = IORef (M.Map String (IO ()))

data Conversation = Conversation { conversationMessages :: [Value], executionPending :: Bool }
instance ToJSON Conversation where
  toJSON (Conversation history pending) = object ["messages" .= history, "execution_pending" .= pending]
instance FromJSON Conversation where
  parseJSON = withObject "conversation" $ \o -> Conversation <$> o .: "messages" <*> o .:? "execution_pending" .!= False

record :: MVar Conversation -> Maybe Bool -> Value -> IO ()
record conversation pending entry = modifyMVarMasked_ conversation $ \(Conversation history executing) -> do
  let next = Conversation (history ++ [entry]) (fromMaybe executing pending)
  BL.writeFile ".runs/conversation.json.tmp" $ encode next
  renameFile ".runs/conversation.json.tmp" ".runs/conversation.json"
  pure next

trySync :: IO a -> IO (Either SomeException a)
trySync = tryJust (\e -> case fromException e :: Maybe SomeAsyncException of Just _ -> Nothing; Nothing -> Just e)

capture :: FilePath -> IO a -> IO a
capture file action = bracket ((,) <$> hDuplicate stdout <*> hDuplicate stderr)
  (\(out, err) -> hDuplicateTo out stdout >> hDuplicateTo err stderr >> hClose out >> hClose err) $ \_ ->
    withFile file WriteMode $ \h -> do
      hSetBuffering h NoBuffering
      hDuplicateTo h stdout
      hDuplicateTo h stderr
      action `finally` (hFlush stdout >> hFlush stderr)

worker :: IO ()
worker = do
  memory <- newIORef M.empty :: IO Memory
  actions <- newIORef M.empty :: IO Actions
  forever $ do
    file <- getLine
    outcome <- trySync $ capture (file ++ ".output") $ do
      compiled <- loadStep file
      case compiled of
        Left err -> ioError $ userError $ show err
        Right action -> do
          finished <- timeout 60000000 (action memory actions)
          maybe (ioError $ userError "Execution timed out after 60 seconds.") pure finished
    writeFile (file ++ ".result.tmp") $ either displayException (\again -> if again then "CONTINUE" else "WAIT") outcome
    renameFile (file ++ ".result.tmp") (file ++ ".result")

startWorker :: IO Worker
startWorker = do
  executable <- getExecutablePath
  environment <- filter (\(name, _) -> not $ any (`isInfixOf` map toUpper name) ["KEY", "TOKEN", "SECRET", "PASSWORD", "LLM_"]) <$> getEnvironment
  (Just input, _, _, child) <- createProcess (proc executable ["--worker"])
    { std_in = CreatePipe, create_group = True, env = Just environment }
  hSetBuffering input LineBuffering
  pure (input, child)

stopWorker :: Worker -> IO ()
stopWorker (input, child) = do
  pid <- getPid child
  forM_ pid $ \p -> void $ trySync $ signalProcessGroup sigKILL p
  _ <- trySync $ hClose input
  void $ waitForProcess child

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

message :: T.Text -> T.Text -> Value
message role content = object ["role" .= role, "content" .= content]

ask :: String -> String -> String -> FilePath -> T.Text -> [Value] -> IO T.Text
ask = askModel

execute :: MVar Worker -> FilePath -> T.Text -> IO (T.Text, Bool)
execute workers file source = withMVar workers $ \(input, child) -> do
  status <- getProcessExitCode child
  when (status /= Nothing) $ ioError $ userError "Worker exited; /pause then /resume to restart it."
  T.writeFile file source
  hPutStrLn input file
  let outputFile = file ++ ".output"
      resultFile = file ++ ".result"
      stream offset = do
        exists <- doesFileExist outputFile
        next <- if not exists || offset >= 16000 then pure offset else withBinaryFile outputFile ReadMode $ \h -> do
          hSeek h AbsoluteSeek (fromIntegral offset)
          bytes <- B.hGetSome h (16000 - offset)
          B.hPut stdout bytes
          pure $ offset + B.length bytes
        ready <- doesFileExist resultFile
        if ready then pure next else do
          exit <- getProcessExitCode child
          when (exit /= Nothing) $ ioError $ userError "Worker crashed; pause/resume to restart."
          threadDelay 50000
          stream next
  completed <- timeout 90000000 $ stream 0
  when (completed == Nothing) $ ioError $ userError "Worker timed out; pause/resume to restart."
  result <- T.readFile resultFile
  when (result /= "CONTINUE" && result /= "WAIT") $ T.putStrLn $ "[execution error] " <> result
  bytes <- withBinaryFile outputFile ReadMode $ \h -> B.hGet h 16000
  forM_ completed $ \offset -> B.hPut stdout $ B.drop offset bytes
  pure (result <> "\n" <> TE.decodeUtf8With TE.lenientDecode bytes <> "\n[Output capped at 16000 bytes.]", result /= "WAIT")

supervisor :: IO ()
supervisor = do
  loadEnv
  [endpoint, key, model] <- mapM getEnv ["LLM_ENDPOINT", "LLM_API_KEY", "LLM_MODEL"]
  session <- (".runs/haskell-" ++) . show . (floor :: POSIXTime -> Integer) . (* 1000000) <$> getPOSIXTime
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
          standing <- T.readFile instructionFile
          when (T.null (T.strip standing)) $ ioError $ userError $ "Instructions file is empty: " ++ instructionFile
          hasRules <- doesFileExist "AGENTS.md"
          rules <- if hasRules then T.readFile "AGENTS.md" else pure ""
          remedyStore <- readRemedyRecords "/workspace/remedy-memory.json"
          let intent = message "user" (T.pack (latestUserIntent context))
              memories = either (const []) (\rs -> selectFromRecords 1600 rs [intent]) remedyStore
          case remedyStore of
            Left category -> events $ object ["remedy_memory_error" .= category]
            Right _ -> pure ()
          lifecycle <- loadLifecycle "/workspace/context-lifecycle.json"
          case lifecycle of
            Left category -> events $ object ["context_lifecycle_error" .= category]
            Right _ -> pure ()
          let scopedContext = either (const context) (\entries -> applyLifecycle entries context) lifecycle
              workingContext = prepareContextWith 64000 scopedContext memories
          source <- ask endpoint key model (session ++ "/llm-" ++ show n ++ ".request.json")
            (standing <> "\nProject rules from AGENTS.md:\n" <> rules) workingContext
          _ <- atomically $ beginExecution paused generation requestGeneration executionStarted
          record conversation (Just True) $ message "assistant" source
          (feedback, again) <- execute workers file source
          record conversation (Just False) $ message "user" $ "Execution feedback:\n" <> feedback <>
            (if again then "\nThe step requested another model call to continue." else "\nThe step is waiting for new user input.")
          atomically $ finishExecution executionStarted
          events $ object ["step" .= n, "source" .= source, "output" .= feedback, "continue" .= again]
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
            let detail = T.replace (T.pack key) "[redacted]" $ T.pack $ displayException err
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
  if args == ["--worker"] then worker else supervisor
