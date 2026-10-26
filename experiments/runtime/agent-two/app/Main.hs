module Main where
import ExecutionRuntime
import qualified A2A
import ChatGPTAuth (authCommand)
import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Environment
import System.IO

main :: IO ()
main = do
  mapM_ (`hSetBuffering` NoBuffering) [stdout, stderr]
  args <- getArgs
  case args of
    ["--worker"] -> worker
    ["--a2a"] -> loadEnv >> A2A.runServer
    ["--a2a-call",url,method,params] -> do
      value <- either (ioError . userError) pure (eitherDecodeStrict' (TE.encodeUtf8 (T.pack params)))
      result <- A2A.rpcCall url (T.pack method) value
      BL.putStr (encode result <> "\n")
    ["--a2a-send",url,context,text] -> do
      result <- A2A.sendText url (if context == "-" then Nothing else Just (T.pack context)) (T.pack text)
      BL.putStr (encode result <> "\n")
    ["--a2a-await",url,ident] -> A2A.awaitTask url (T.pack ident) >>= (\result -> BL.putStr (encode result <> "\n"))
    "auth":command -> loadEnv >> authCommand command
    [] -> supervisor
    _ -> ioError $ userError "Usage: agent-one [auth COMMAND]"
