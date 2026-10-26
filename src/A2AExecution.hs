{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module A2AExecution (Hub, newHub, runExecution) where
import ExecutionRuntime
import Control.Concurrent
import Control.Exception
import Control.Monad
import Crypto.Hash (hash, Digest, SHA256)
import Data.Aeson
import qualified Data.ByteString as B
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Encoding as TE
import System.Directory
import Data.Time.Clock.POSIX
data Context = Context FilePath (MVar Conversation) (MVar Worker)
newtype Hub = Hub (MVar (M.Map T.Text Context))
newHub = Hub <$> newMVar M.empty
context (Hub hub) cid prior = modifyMVar hub $ \contexts -> case M.lookup cid contexts of
  Just c -> pure (contexts,c)
  Nothing -> do
    let dir=".runs/a2a/execution/"++show (hash (TE.encodeUtf8 cid)::Digest SHA256)
        path=dir++"/conversation.json"
    createDirectoryIfMissing True dir
    exists <- doesFileExist path
    restored <- if exists then B.readFile path >>= either (ioError . userError) pure . eitherDecodeStrict' else pure (Conversation prior False)
    conv <- newMVar restored
    when exists $ recordAt path conv (Just False) $ message "user" $
      "A2A context restored after server restart. Worker IORef memory/actions reset; full conversation and files persist. " <>
      (if executionPending restored then "Previous execution was interrupted; effects may be partial. Inspect files before repeating any effects." else "Do not repeat completed work.")
    w <- newMVar =<< startWorkerFor path
    let c=Context dir conv w
    pure (M.insert cid c contexts,c)
runExecution :: Hub -> ModelConfig -> T.Text -> T.Text -> [Value] -> T.Text -> IO T.Text
runExecution hub cfg cid tid prior inbound = do
  Context dir conv workers <- context hub cid prior
  attempt <- getPOSIXTime
  let path=dir++"/conversation.json"; taskDir=dir++"/"++T.unpack tid++"/attempt-"++show (floor (attempt*1000000)::Integer)
  createDirectoryIfMissing True taskDir
  executing <- newIORef False
  let interrupted = do
        active <- readIORef executing
        when active $ modifyMVar_ workers $ \w -> stopWorker w >> startWorkerFor path
        recordAt path conv (Just False) $ message "user" $ if active
          then "A2A task interrupted during execution. Worker terminated/reset: live memory/actions reset. Files persist and effects may be partial; no rollback is claimed."
          else "A2A task interrupted before further execution. Worker memory/actions preserved; completed file effects persist. No further calls for this task are scheduled."
      loop n failures outputs = do
        history <- conversationMessages <$> readMVar conv
        result <- modelStep cfg workers history (taskDir++"/Step"++show n++".hs") (taskDir++"/llm-"++show n++".request.json")
          (writeIORef executing True)
          (recordAt path conv (Just True))
          (\v -> recordAt path conv (Just False) v >> writeIORef executing False)
        let output=if executionSucceeded result then T.drop 1 (snd (T.breakOn "\n" (executionFeedback result))) else executionFeedback result
            errors=if executionSucceeded result then 0 else failures+1
            next=outputs++[output]
        when (errors >= 3) $ ioError $ userError "Three consecutive compilation/execution failures; task failed."
        if executionContinue result then loop (n+1) errors next else pure (T.intercalate "\n" next)
  (do
    recordAt path conv Nothing $ message "user" ("A2A inbound task "<>tid<>" in context "<>cid<>". Execute using the original Haskell Step capabilities; return False when THIS task is complete.\n"<>inbound)
    loop (1::Int) (0::Int) []) `onException` interrupted
