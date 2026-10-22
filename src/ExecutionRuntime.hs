{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module ExecutionRuntime where
import Control.Concurrent
import Control.Concurrent.Async
import Control.Concurrent.STM
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

recordAt :: FilePath -> MVar Conversation -> Maybe Bool -> Value -> IO ()
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

startWorkerFor :: FilePath -> IO Worker
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

message :: T.Text -> T.Text -> Value
message role content = object ["role" .= role, "content" .= content]

ask :: String -> String -> String -> FilePath -> T.Text -> [Value] -> IO (T.Text, Value)
ask = askModel

execute :: MVar Worker -> FilePath -> T.Text -> IO ExecutionResult
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
  pure $ ExecutionResult (result <> "\n" <> TE.decodeUtf8With TE.lenientDecode bytes <> (if truncated then "\n[Output truncated at 16000 bytes.]" else "")) (result /= "WAIT") (result == "WAIT" || result == "CONTINUE") (TE.decodeUtf8With TE.lenientDecode bytes)

data ExecutionResult = ExecutionResult { executionFeedback :: T.Text, executionContinue :: Bool, executionSucceeded :: Bool, executionOutput :: T.Text }
data ModelConfig = ModelConfig String String String FilePath
systemInstructions :: T.Text -> T.Text -> T.Text
systemInstructions standing rules = standing <> "\nProject rules from AGENTS.md:\n" <> rules <>
  "\nOutput discipline: Follow supplied instructions silently. Unless explicitly requested, do not echo SYSTEM.md, AGENTS.md, full directory listings, or unchanged startup checks. Perform required checks and retain their artifacts; report required observations concisely. Keep stdout and A2A replies focused on useful results, actual errors, and materially relevant observations needed for execution feedback and reflection. Omit routine self-reflection paragraphs.\n"

modelStep :: ModelConfig -> MVar Worker -> [Value] -> FilePath -> FilePath -> IO () -> (Value -> IO ()) -> (Value -> IO ()) -> IO ExecutionResult
modelStep (ModelConfig endpoint key model instructionFile) workers history file requestFile beforeExecute saveAssistant saveFeedback = do
  standing <- T.readFile instructionFile
  when (T.null (T.strip standing)) $ ioError $ userError "Empty instructions"
  hasRules <- doesFileExist "AGENTS.md"
  rules <- if hasRules then T.readFile "AGENTS.md" else pure ""
  (source, assistant) <- ask endpoint key model requestFile (systemInstructions standing rules) (prepareContext history)
  beforeExecute
  saveAssistant assistant
  outcome <- execute workers file source
  saveFeedback $ message "user" $ "Execution feedback:\n" <> executionFeedback outcome <>
    (if executionContinue outcome then "\nThe step requested another model call to continue." else "\nThe step is waiting for new user input.")
  pure outcome
