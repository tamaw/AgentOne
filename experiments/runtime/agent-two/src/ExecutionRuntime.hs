module ExecutionRuntime where

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
import ModelConnection (askModel)
import ChatGPTAuth (authCommand)
import ContextWindow (prepareContext)
import System.Directory
import System.Environment
import System.Exit
import System.IO
import System.IO.Error (isEOFError)
import System.Posix.Signals
import System.Posix.Process (getParentProcessID, getProcessID)
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
record = recordAt ".runs/conversation.json"

recordAt path conversation pending entry = modifyMVarMasked_ conversation $ \(Conversation history executing) -> do
  let next = Conversation (history ++ [entry]) (fromMaybe executing pending)
  BL.writeFile (path ++ ".tmp") $ encode next
  renameFile (path ++ ".tmp") path
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
  parent <- getParentProcessID
  self <- getProcessID
  void $ forkIO $ forever $ do
    threadDelay 100000
    current <- getParentProcessID
    when (current /= parent) $ signalProcessGroup sigKILL self
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
startWorker = startWorkerFor ".runs/conversation.json"

startWorkerFor conversationPath = do
  executable <- getExecutablePath
  environment <- filter (\(name, _) -> not $ any (`isInfixOf` map toUpper name) ["KEY", "TOKEN", "SECRET", "PASSWORD", "LLM_"]) <$> getEnvironment
  (Just input, _, _, child) <- createProcess (proc executable ["--worker"])
    { std_in = CreatePipe, create_group = True, env = Just (("AGENT_CONVERSATION_FILE",conversationPath) : filter ((/= "AGENT_CONVERSATION_FILE") . fst) environment) }
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

ask :: String -> String -> String -> FilePath -> T.Text -> [Value] -> IO (T.Text, Value)
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
  truncated <- (> 16000) <$> getFileSize outputFile
  forM_ completed $ \offset -> B.hPut stdout $ B.drop offset bytes
  pure (result <> "\n" <> TE.decodeUtf8With TE.lenientDecode bytes <> (if truncated then "\n[Output truncated at 16000 bytes.]" else ""), result /= "WAIT")

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
          (feedback, again) <- stepEngine endpoint key model instructionFile (session ++ "/llm-" ++ show n ++ ".request.json") file workers
            (conversationMessages <$> readMVar conversation) (record conversation)
            (void $ atomically $ beginExecution paused generation requestGeneration executionStarted)
            (atomically $ finishExecution executionStarted)
          events $ object ["step" .= n, "output" .= feedback, "continue" .= again]
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


stepEngine endpoint key model instructionFile request file workers getHistory persist begin end = do
  standing <- T.readFile instructionFile
  when (T.null (T.strip standing)) $ ioError $ userError "Instructions file is empty"
  hasRules <- doesFileExist "AGENTS.md"
  rules <- if hasRules then T.readFile "AGENTS.md" else pure ""
  context <- getHistory
  (source, assistant) <- ask endpoint key model request (standing <> "\nProject rules from AGENTS.md:\n" <> rules <> "\nOutput discipline: Follow system/project instructions silently. Do not echo policy files, full directory listings, or unchanged startup checks into stdout or A2A replies. Report useful results, actual errors, and materially relevant observations concisely; omit routine self-reflection. Keep required startup checks and persisted observations, but report them only on startup or material change. Preserve conversation history and CONTINUE/WAIT semantics.\n") (prepareContext context)
  begin
  persist (Just True) assistant
  (feedback, again) <- execute workers file source
  persist (Just False) $ message "user" $ "Execution feedback:\n" <> feedback <>
    (if again then "\nThe step requested another model call to continue." else "\nThe step is waiting for new user input.")
  end
  pure (feedback, again)

data RuntimeContext = RuntimeContext FilePath (MVar Conversation) (MVar Worker) (MVar ())
type ExecutionContexts = MVar (M.Map T.Text RuntimeContext)
newExecutionContexts :: IO ExecutionContexts
newExecutionContexts = newMVar M.empty
contextDirectory c = ".runs/a2a/execution/context-" ++ concatMap hex (B.unpack (TE.encodeUtf8 c)) where
  hex b = let digits = "0123456789abcdef"; n = fromIntegral b in [digits !! (n `div` 16), digits !! (n `mod` 16)]
getRuntime registry c initial = modifyMVar registry $ \rs -> case M.lookup c rs of
  Just r -> pure (rs,r)
  Nothing -> do
    dir <- makeAbsolute (contextDirectory c)
    createDirectoryIfMissing True dir
    let path = dir ++ "/conversation.json"
    exists <- doesFileExist path
    restored <- if exists then B.readFile path >>= either (ioError . userError) pure . eitherDecodeStrict' else pure (Conversation initial False)
    conv <- newMVar restored
    when exists $ recordAt path conv (Just False) $ message "user" $ "Conversation restored after supervisor restart. Worker memory and actions were reset; files persist. " <>
      (if executionPending restored then "Previous execution may have partially run; inspect private step artifacts before repeating effects. " else "") <> "Continue existing work, not completed effects."
    workers <- newMVar =<< startWorkerFor path
    serial <- newMVar ()
    let r = RuntimeContext dir conv workers serial
    pure (M.insert c r rs,r)

runContext :: ExecutionContexts -> T.Text -> T.Text -> [Value] -> T.Text -> IO () -> IO T.Text
runContext registry c task initial inbound active = do
  active
  RuntimeContext dir conv workers serial <- getRuntime registry c initial
  withMVar serial $ \_ -> do
    let path = dir ++ "/conversation.json"
        persist = recordAt path conv
        recover = mask_ $ do
          modifyMVar_ workers $ \w -> stopWorker w >> startWorkerFor path
          persist (Just False) $ message "user" "Task execution interrupted or failed. Worker memory/actions reset; files persist and effects may be partial. No rollback is claimed."
    (do
      active
      persist Nothing $ message "user" ("Incoming A2A request. ContextId=" <> c <> "; taskId=" <> task <> ". Full private execution history: " <> T.pack path <> ". Use this history, not /workspace/.runs/conversation.json. Execute Haskell Step modules using the ORIGINAL runtime; communicate actual results using putStrLn. Return True only for necessary continuation, False to complete this task and wait.\n\n" <> inbound)
      endpoint <- fromMaybe "" <$> lookupEnv "LLM_ENDPOINT"
      key <- fromMaybe "" <$> lookupEnv "LLM_API_KEY"
      model <- getEnv "LLM_MODEL"
      instruction <- fromMaybe "SYSTEM.md" <$> lookupEnv "INSTRUCTIONS_FILE"
      attempt <- getPOSIXTime
      let taskDir = dir ++ "/tasks/" ++ T.unpack task ++ "/attempt-" ++ show (floor (attempt*1000000) :: Integer)
      createDirectoryIfMissing True taskDir
      let loop n failures outputs = do
            active
            let base = taskDir ++ "/Step" ++ show n
            (feedback,again) <- stepEngine endpoint key model instruction (base ++ ".request.json") (base ++ ".hs") workers
              (conversationMessages <$> readMVar conv) persist active (pure ())
            let successful = "CONTINUE\n" `T.isPrefixOf` feedback || "WAIT\n" `T.isPrefixOf` feedback
                compileError = "WontCompile" `T.isInfixOf` feedback || "compilation exceeded" `T.isInfixOf` feedback
                failures' = if successful then 0 else failures + 1
                outputs' = outputs ++ [if successful then T.drop 1 (snd (T.breakOn "\n" feedback)) else feedback]
            BL.appendFile (taskDir ++ "/events.jsonl") (encode (object ["step" .= n,"output" .= feedback,"continue" .= again]) <> "\n")
            unless (successful || (compileError && failures' < 3)) $ ioError $ userError "Haskell execution failed; actual feedback is preserved in the private context conversation and step artifacts."
            active
            if again then loop (n+1) failures' outputs' else pure (T.intercalate "\n" outputs')
      loop (1 :: Int) (0 :: Int) []) `onException` recover
