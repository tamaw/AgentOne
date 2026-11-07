{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module A2AExecution (Hub, newHub, runExecution) where
import ExecutionRuntime
import Control.Concurrent
import Control.Exception
import Control.Monad
import Crypto.Hash (hash, Digest, SHA256)
import Data.Aeson
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory
import System.Environment
import Data.Time.Clock.POSIX
import Text.Read (readMaybe)

data Context = Context FilePath (MVar Conversation)
data Hub = Hub (MVar (M.Map T.Text Context)) (MVar Worker) Int FilePath (MVar ())

bootstrapConversation :: FilePath
bootstrapConversation = ".runs/a2a/application-bootstrap/conversation.json"

startupReceipt :: FilePath
startupReceipt = ".runs/a2a/application-worker-startup.json"

writeStartupReceipt :: T.Text -> Maybe FilePath -> Maybe T.Text -> IO ()
writeStartupReceipt state bootstrap problem = do
  now <- getPOSIXTime
  BL.writeFile (startupReceipt ++ ".tmp") $ encode $ object
    [ "state" .= state
    , "bootstrap" .= maybe Null (String . T.pack) bootstrap
    , "error" .= maybe Null String problem
    , "time" .= now
    ]
  renameFile (startupReceipt ++ ".tmp") startupReceipt

applicationWorker :: FilePath -> IO Worker
applicationWorker conversation = mask $ \restore -> do
  bootstrap <- lookupEnv "AGENT_BOOTSTRAP_STEP"
  writeStartupReceipt "starting" bootstrap Nothing
  outcome <- trySync $ startWorkerFor conversation
  case outcome of
    Left err -> do
      writeStartupReceipt "failed" bootstrap (Just $ T.pack $ displayException err)
      throwIO err
    Right started -> do
      restore (writeStartupReceipt "ready" bootstrap Nothing) `onException` stopWorker started
      pure started

maxSteps :: IO Int
maxSteps = do
  configured <- lookupEnv "A2A_MAX_STEPS"
  case configured of
    Nothing -> pure 8
    Just value -> case readMaybe value :: Maybe Int of
      Just limit | limit > 0 -> pure limit
      _ -> ioError $ userError "A2A_MAX_STEPS must be a positive integer."

newHub :: IO Hub
newHub = do
  createDirectoryIfMissing True ".runs/a2a/application-bootstrap"
  exists <- doesFileExist bootstrapConversation
  unless exists $ do
    BL.writeFile (bootstrapConversation ++ ".tmp") $ encode $ Conversation [] False
    renameFile (bootstrapConversation ++ ".tmp") bootstrapConversation
  limit <- maxSteps
  started <- applicationWorker bootstrapConversation
  Hub <$> newMVar M.empty <*> newMVar started <*> pure limit <*> pure bootstrapConversation <*> newMVar ()

restartWorker :: Hub -> IO ()
restartWorker (Hub _ workers _ conversation _) =
  modifyMVar_ workers $ \old -> stopWorker old >> applicationWorker conversation

context :: Hub -> T.Text -> [Value] -> IO Context
context (Hub contexts _ _ _ _) cid prior = modifyMVar contexts $ \known -> case M.lookup cid known of
  Just current -> pure (known, current)
  Nothing -> do
    let dir = ".runs/a2a/execution/" ++ show (hash (TE.encodeUtf8 cid) :: Digest SHA256)
        path = dir ++ "/conversation.json"
    createDirectoryIfMissing True dir
    exists <- doesFileExist path
    restored <- if exists then B.readFile path >>= either (ioError . userError) pure . eitherDecodeStrict' else pure (Conversation prior False)
    conversation <- newMVar restored
    when exists $ recordAt path conversation (Just False) $ message "user" $
      "A2A context restored after server restart. The shared application worker has bootstrapped from persistent files; do not assume old request-local memory survived. " <>
      (if executionPending restored
        then "Previous execution was interrupted and effects may be partial. Inspect the application/journal before repeating any effects."
        else "Do not repeat completed work.")
    let current = Context dir conversation
    pure (M.insert cid current known, current)

runExecution :: Hub -> ModelConfig -> T.Text -> T.Text -> [Value] -> T.Text -> IO T.Text
runExecution hub@(Hub _ workers limit _ lease) cfg cid tid prior inbound = withMVar lease $ \_ -> do
  Context dir conversation <- context hub cid prior
  attempt <- getPOSIXTime
  let path = dir ++ "/conversation.json"
      taskDir = dir ++ "/" ++ T.unpack tid ++ "/attempt-" ++ show (floor (attempt * 1000000) :: Integer)
  createDirectoryIfMissing True taskDir
  executing <- newIORef False
  let interrupted = do
        active <- readIORef executing
        when active $ restartWorker hub
        recordAt path conversation (Just False) $ message "user" $ if active
          then "A2A task interrupted during execution. The shared application worker terminated and restarted after its old process group exited; bootstrap recovery ran before later requests. Files persist and effects may be partial; no rollback is claimed."
          else "A2A task ended with no active worker execution. Shared application memory/actions were preserved; completed file effects persist."
      loop n failures = do
        history <- conversationMessages <$> readMVar conversation
        result <- modelStep cfg workers path history (taskDir ++ "/Step" ++ show n ++ ".hs") (taskDir ++ "/llm-" ++ show n ++ ".request.json")
          (writeIORef executing True)
          (recordAt path conversation (Just True))
          (\entry -> recordAt path conversation (Just False) entry >> writeIORef executing False)
        let errors = if executionSucceeded result then 0 else failures + 1
        when (errors >= 3) $ ioError $ userError "Three consecutive compilation/execution failures; task failed."
        if executionContinue result
          then if n >= limit
            then ioError $ userError "A2A_MAX_STEPS exhausted before the step returned False."
            else loop (n + 1) errors
          else if executionSucceeded result
            then pure $ executionOutput result
            else ioError $ userError "Step failed without requesting another model call."
  (do
    recordAt path conversation Nothing $ message "user" ("A2A inbound task " <> tid <> " in context " <> cid <> ". Execute using the original Haskell Step capabilities; return False when THIS task is complete.\n" <> inbound)
    loop (1 :: Int) 0) `onException` interrupted
