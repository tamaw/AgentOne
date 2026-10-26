{-# LANGUAGE OverloadedStrings, DeriveGeneric, ScopedTypeVariables #-}
module A2A (runServer, rpcCall, sendText, getTask, awaitTask) where
import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.Aeson
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L
import Data.Char (toLower)
import Data.List (find)
import qualified Data.Map.Strict as M
import Data.Maybe
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time
import GHC.Generics
import ExecutionRuntime (newExecutionContexts, runContext, trySync)
import A2ACompat
import Control.Concurrent.Async (race)
import Network.Socket
import qualified Network.Socket.ByteString as N
import System.Directory
import System.Environment
import System.Exit
import System.Process
import System.Timeout
import Text.Read (readMaybe)

data Store = Store { tasks :: M.Map T.Text Value, contexts :: M.Map T.Text [Value], pending :: [T.Text] } deriving (Generic, Eq)
instance ToJSON Store
instance FromJSON Store
data Fault = Fault Int T.Text deriving (Show)
instance Exception Fault
fault c s = throwIO (Fault c s)
field k (Object o) = fromMaybe Null (KM.lookup (K.fromText k) o)
field _ _ = Null
str (String s) = s
str _ = ""
arr (Array a) = foldr (:) [] a
arr _ = []
put k v (Object o) = Object (KM.insert (K.fromText k) v o)
put _ _ v = v
txt k = str . field k
state t = txt "state" (field "status" t)
terminal t = state t `elem` ["TASK_STATE_COMPLETED","TASK_STATE_FAILED","TASK_STATE_CANCELED","TASK_STATE_REJECTED"]
stopped t = terminal t || state t `elem` ["TASK_STATE_INPUT_REQUIRED","TASK_STATE_AUTH_REQUIRED"]
newId = T.strip . T.pack <$> readFile "/proc/sys/kernel/random/uuid"
stamp = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" <$> getCurrentTime
status :: T.Text -> Maybe Value -> IO Value
status s msg = do
  ts <- stamp
  pure $ object (["state" .= (s :: T.Text), "timestamp" .= ts] ++ ["message" .= m | Just m <- [msg]])
save st = L.writeFile ".runs/a2a/state.json.tmp" (encode st) >> renameFile ".runs/a2a/state.json.tmp" ".runs/a2a/state.json"
change ref f = modifyMVar ref $ \st -> do (st',v) <- f st; when (st' /= st) (save st'); pure (st',v)
parseP p v = either (const $ fault (-32602) "Invalid params") pure (parseEither p v)
nonempty = withText "nonempty string" $ \s -> if T.null s then fail "empty" else pure s
optionalId o k = do
  v <- o .:? k
  mapM (withText "id" $ \s -> if T.null s then fail "empty id" else pure s) v
histP o = do
  n <- o .:? "historyLength" :: Parser (Maybe Int)
  when (maybe False (\x -> x < 0 || toInteger x > 2147483647) n) $ fail "historyLength"
  pure n
trimHistory Nothing t = t
trimHistory (Just n) t = let hs = arr (field "history" t) in put "history" (toJSON (drop (max 0 (length hs-n)) hs)) t
lookupTask st i = maybe (fault (-32001) "Task not found") pure (M.lookup i (tasks st))
taskParams = withObject "params" $ \o -> do
  i <- o .: "id" >>= nonempty
  h <- histP o
  pure (i,h)
sendParams = withObject "params" $ \o -> do
  m <- o .: "message"
  _ <- withObject "message" (\x -> do
    _ <- x .: "messageId" >>= nonempty
    r <- x .: "role" :: Parser T.Text
    unless (r == "ROLE_USER") $ fail "role"
    ps <- x .: "parts" :: Parser [Value]
    when (null ps) $ fail "parts"
    forM_ ps $ withObject "part" $ \part -> do
      let contents = filter (`KM.member` part) ["text","raw","url","data"]
      unless (length contents == 1) $ fail "part content"
      forM_ (KM.lookup "text" part) $ \v -> void (parseJSON v :: Parser T.Text)
    _ <- optionalId x "contextId"
    _ <- optionalId x "taskId"
    pure ()) m
  co <- o .:? "configuration" .!= Object KM.empty
  (im,h,modes,push) <- withObject "configuration" (\c -> (,,,) <$> c .:? "returnImmediately" .!= False <*> histP c <*> c .:? "acceptedOutputModes" .!= ([] :: [T.Text]) <*> c .:? "taskPushNotificationConfig") co
  pure (m,im,h,modes,push :: Maybe Value)

dispatch ref method params = case method of
  "GetTask" -> do
    (i,h) <- parseP taskParams params
    readMVar ref >>= (\s -> trimHistory h <$> lookupTask s i)
  "CancelTask" -> do
    (i,_) <- parseP taskParams params
    change ref $ \s -> do
      t <- lookupTask s i
      when (terminal t) $ fault (-32002) "Task not cancelable"
      st <- status "TASK_STATE_CANCELED" Nothing
      let t' = put "status" st t
      pure (s { tasks = M.insert i t' (tasks s), pending = filter (/=i) (pending s) },t')
  "SendMessage" -> do
    (m,im,h,modes,push) <- parseP sendParams params
    when (isJust push) $ fault (-32003) "Push notifications not supported"
    unless (null modes || "text/plain" `elem` modes) $ fault (-32005) "Content type not supported"
    unless (all (\p -> case field "text" p of String _ -> True; _ -> False) (arr $ field "parts" m)) $ fault (-32005) "Only text parts supported"
    i0 <- newId
    c0 <- newId
    i <- change ref $ \s -> do
      let duplicate = find (\t -> any (\x -> txt "messageId" x == txt "messageId" m) (take 1 (arr (field "history" t)))) (M.elems (tasks s))
      case duplicate of
        Just t | T.null (txt "taskId" m) -> pure (s,txt "id" t)
        _ -> do
          old <- if T.null (txt "taskId" m) then pure Nothing else Just <$> lookupTask s (txt "taskId" m)
          forM_ old $ \t -> do
            when (terminal t) $ fault (-32004) "Task is terminal; create a new task in the same context"
            unless (state t `elem` ["TASK_STATE_INPUT_REQUIRED","TASK_STATE_AUTH_REQUIRED"]) $ fault (-32004) "Task is already processing"
            unless (T.null (txt "contextId" m) || txt "contextId" m == txt "contextId" t) $ fault (-32602) "Context does not match task"
          let i = maybe i0 (txt "id") old
              c = maybe (if T.null (txt "contextId" m) then c0 else txt "contextId" m) (txt "contextId") old
              msg = put "taskId" (String i) $ put "contextId" (String c) m
              hs = maybe [] (arr . field "history") old ++ [msg]
          st <- status "TASK_STATE_SUBMITTED" Nothing
          let t = object ["id" .= i,"contextId" .= c,"status" .= st,"history" .= hs,"artifacts" .= ([] :: [Value])]
          pure (s {tasks=M.insert i t (tasks s),pending=pending s ++ [i]},i)
    t <- if im then readMVar ref >>= (\s -> lookupTask s i) else waitLocal ref i
    pure $ object ["task" .= trimHistory h t]
  "SendStreamingMessage" -> fault (-32004) "Streaming not supported"
  "SubscribeToTask" -> fault (-32004) "Streaming not supported"
  "CreateTaskPushNotificationConfig" -> fault (-32003) "Push notifications not supported"
  "GetExtendedAgentCard" -> fault (-32007) "Extended agent card not configured"
  _ -> fault (-32601) "Method not found"
waitLocal ref i = do
  t <- readMVar ref >>= (\s -> lookupTask s i)
  if stopped t then pure t else threadDelay 100000 >> waitLocal ref i
rpc ref ver input = do
  let ident = case field "id" input of x@(String _) -> x; x@(Number _) -> x; _ -> Null
      err c m = object ["jsonrpc" .= ("2.0" :: T.Text),"id" .= ident,"error" .= object ["code" .= (c :: Int),"message" .= (m :: T.Text)]]
  (do
    case input of
      Object o | field "jsonrpc" input == String "2.0", String _ <- field "method" input, KM.member "id" o, field "id" input == ident -> pure ()
      _ -> fault (-32600) "Invalid Request"
    when (ver /= Just "1.0") $ fault (-32009) "Protocol version not supported"
    let p = case input of Object o | not (KM.member "params" o) -> Object KM.empty; _ -> field "params" input
    case p of Object _ -> pure (); _ -> fault (-32602) "Invalid params"
    result <- dispatch ref (txt "method" input) p
    pure $ object ["jsonrpc" .= ("2.0" :: T.Text),"id" .= ident,"result" .= result])
    `catch` (\(Fault c m) -> pure $ err c m)
    `catch` (\(_ :: SomeException) -> pure $ err (-32603) "Internal error")
modelHistory ms = [object ["role" .= (if txt "role" m == "ROLE_AGENT" then "assistant" else "user" :: T.Text),"content" .= T.intercalate "\n" [txt "text" p | p <- arr (field "parts" m)]] | m <- ms]
work ref runtimes = forever $ do
  next <- change ref $ \s -> case pending s of
    [] -> pure (s,Nothing)
    i:rest -> case M.lookup i (tasks s) of
      Just t | not (terminal t) -> do
        st <- status "TASK_STATE_WORKING" Nothing
        let c = txt "contextId" t
            m = last (arr (field "history" t))
            ms = M.findWithDefault [] c (contexts s)
            ms' = if any (\x -> txt "messageId" x == txt "messageId" m) ms then ms else ms ++ [m]
        pure (s {tasks=M.insert i (put "status" st t) (tasks s),contexts=M.insert c ms' (contexts s),pending=rest},Just (i,c,ms'))
      _ -> pure (s {pending=rest},Nothing)
  case next of
    Nothing -> threadDelay 200000
    Just (i,c,ms) -> do
      let active = do
            t <- readMVar ref >>= (\s -> lookupTask s i)
            when (terminal t) $ ioError $ userError "A2A task is terminal"
          canceled = do
            t <- readMVar ref >>= (\s -> lookupTask s i)
            if terminal t then pure () else threadDelay 50000 >> canceled
          inbound = T.intercalate "\n" [txt "text" p | p <- arr (field "parts" (last ms))]
      answer <- trySync $ race canceled (runContext runtimes c i (modelHistory (init ms)) inbound active)
      mid <- newId
      aid <- newId
      change ref $ \s -> do
        t <- lookupTask s i
        if terminal t then pure (s,()) else do
          let (ss,text) = case answer of Right (Right a) -> ("TASK_STATE_COMPLETED",a); _ -> ("TASK_STATE_FAILED","Execution failed; inspect private context conversation and execution artifacts." :: T.Text)
              msg = object ["messageId" .= mid,"contextId" .= c,"taskId" .= i,"role" .= ("ROLE_AGENT" :: T.Text),"parts" .= [object ["text" .= text]]]
              artifacts = [object ["artifactId" .= aid,"name" .= ("response" :: T.Text),"parts" .= [object ["text" .= text]]] | ss == "TASK_STATE_COMPLETED"]
          st <- status ss (Just msg)
          let t' = put "status" st $ put "artifacts" (toJSON artifacts) $ put "history" (toJSON (arr (field "history" t) ++ [msg])) t
          pure (s {tasks=M.insert i t' (tasks s),contexts=M.insertWith (flip (++)) c [msg] (contexts s)},())

card = object ["name" .= ("Agent Two" :: T.Text),"description" .= ("Haskell engineering agent with durable asynchronous A2A tasks and executable model-generated Haskell" :: T.Text),"version" .= ("1.0.0" :: T.Text),"supportedInterfaces" .= [object ["url" .= ("http://agent-two:8080/rpc" :: T.Text),"protocolBinding" .= ("JSONRPC" :: T.Text),"protocolVersion" .= ("1.0" :: T.Text)]],"capabilities" .= object ["streaming" .= False,"pushNotifications" .= False],"defaultInputModes" .= ["text/plain" :: T.Text],"defaultOutputModes" .= ["text/plain" :: T.Text],"skills" .= [object ["id" .= ("engineering" :: T.Text),"name" .= ("Engineering collaboration" :: T.Text),"description" .= ("Original executable Haskell agent with persistent per-context worker memory/actions" :: T.Text),"tags" .= ["haskell" :: T.Text,"review"]]]]
wire lock direction value = withMVar lock $ \_ -> do
  ts <- stamp
  L.appendFile ".runs/a2a/wire.jsonl" (encode (object ["time" .= ts,"direction" .= (direction :: T.Text),"body" .= value]) <> "\n")
readHTTP sock = headers B.empty where
  headers buf
    | B.length buf > 65536 = ioError $ userError "headers too big"
    | otherwise = let (h,rest) = C.breakSubstring "\r\n\r\n" buf in if B.null rest then do
        more <- N.recv sock 8192
        when (B.null more) $ ioError $ userError "closed"
        headers (buf <> more)
      else do
        let ls = C.lines h
            req = words (C.unpack (head ls))
            hs = [(map toLower $ C.unpack k, T.strip $ TE.decodeUtf8 $ C.drop 1 v) | l <- tail ls, let (k,v) = C.break (==':') l]
            n = fromMaybe 0 (lookup "content-length" hs >>= readMaybe . T.unpack) :: Int
        when (n < 0 || n > 2097152 || isJust (lookup "transfer-encoding" hs)) $ ioError $ userError "invalid length"
        body <- consume n (B.drop 4 rest)
        pure (req,hs,body)
  consume n buf | B.length buf >= n = pure (B.take n buf)
  consume n buf = do
    more <- N.recv sock (min 8192 (n-B.length buf))
    when (B.null more) $ ioError $ userError "short body"
    consume n (buf <> more)
respond sock code value = do
  let body = L.toStrict (encode value)
  N.sendAll sock (C.pack ("HTTP/1.1 " ++ code ++ "\r\nContent-Type: application/json\r\nA2A-Version: 1.0\r\nConnection: close\r\nContent-Length: " ++ show (B.length body) ++ "\r\n\r\n") <> body)
serve ref lock sock = do
  request <- timeout 15000000 (readHTTP sock)
  forM_ request $ \(line,hs,body) -> case line of
    ["GET","/.well-known/agent-card.json",_] -> respond sock "200 OK" card
    ["GET","/a2a/v0.3/.well-known/agent-card.json",_] -> respond sock "200 OK" (legacyCard card)
    ["GET",path,_] | path `elem` ["/health","/a2a/v0.3/health"] -> respond sock "200 OK" (object ["status" .= ("ok" :: T.Text)])
    ["GET","/implementation",_] -> do
      code <- readFile "src/A2A.hs"
      runtime <- readFile "src/ExecutionRuntime.hs"
      mainSource <- readFile "app/Main.hs"
      respond sock "200 OK" (object ["source" .= code,"runtime" .= runtime,"main" .= mainSource])
    ["POST",path,_] | path `elem` ["/rpc","/a2a/v0.3/rpc"] -> do
      let legacy = path=="/a2a/v0.3/rpc"
          parsed = eitherDecodeStrict' (if legacy then legacyRequest body else body)
      result <- case parsed of
        Left _ -> pure $ object ["jsonrpc" .= ("2.0" :: T.Text),"id" .= Null,"error" .= object ["code" .= (-32700 :: Int),"message" .= ("Parse error" :: T.Text)]]
        Right input -> do
          wire lock "inbound.request" input
          rpc ref (if legacy then Just "1.0" else case [v | (k,v) <- hs, k == "a2a-version"] of [v] -> Just v; _ -> Nothing) input
      wire lock "inbound.response" result
      respond sock "200 OK" (if legacy then legacyResponse result else result)
    _ -> respond sock "404 Not Found" (object ["error" .= ("Not found" :: T.Text)])
runServer = withSocketsDo $ do
  createDirectoryIfMissing True ".runs/a2a"
  exists <- doesFileExist ".runs/a2a/state.json"
  s <- if exists then L.readFile ".runs/a2a/state.json" >>= either (ioError . userError) pure . eitherDecode else pure (Store M.empty M.empty [])
  let lost = [i | (i,t) <- M.toList (tasks s),not (stopped t),i `notElem` pending s]
  ref <- newMVar s {pending=lost ++ pending s}
  lock <- newMVar ()
  runtimes <- newExecutionContexts
  bracket (socket AF_INET Stream defaultProtocol) close $ \sock -> do
    setSocketOption sock ReuseAddr 1
    bind sock (SockAddrInet 8080 0)
    listen sock 128
    _ <- forkIO $ work ref runtimes
    putStrLn "A2A 1.0 listening on 0.0.0.0:8080"
    forever $ do
      (conn,_) <- accept sock
      void $ forkFinally (serve ref lock conn) (\_ -> close conn)

rpcCall :: String -> T.Text -> Value -> IO Value
rpcCall url method params = do
  ident <- newId
  let input = object ["jsonrpc" .= ("2.0" :: T.Text),"id" .= ident,"method" .= method,"params" .= params]
  L.appendFile ".runs/a2a/client-wire.jsonl" (encode (object ["direction" .= ("outbound.request" :: T.Text),"url" .= url,"body" .= input]) <> "\n")
  (code,out,_) <- readProcessWithExitCode "curl" ["--silent","--show-error","--max-time","900","--header","Content-Type: application/json","--header","A2A-Version: 1.0","--data-binary","@-",url] (T.unpack (TE.decodeUtf8 (L.toStrict (encode input))))
  unless (code == ExitSuccess) $ ioError $ userError "A2A transport failed"
  result <- either (ioError . userError) pure (eitherDecodeStrict' (TE.encodeUtf8 (T.pack out)))
  L.appendFile ".runs/a2a/client-wire.jsonl" (encode (object ["direction" .= ("outbound.response" :: T.Text),"url" .= url,"body" .= (result :: Value)]) <> "\n")
  unless (field "id" result == String ident && field "jsonrpc" result == String "2.0") $ ioError $ userError "Invalid RPC response"
  case result of
    Object o -> unless (KM.member "result" o /= KM.member "error" o) $ ioError $ userError "Invalid result/error framing"
    _ -> ioError $ userError "Invalid RPC response object"
  when (field "error" result /= Null) $ ioError $ userError $ show (field "error" result)
  pure (field "result" result)
sendText :: String -> Maybe T.Text -> T.Text -> IO Value
sendText url context text = do
  mid <- newId
  rpcCall url "SendMessage" (object ["message" .= object (["messageId" .= mid,"role" .= ("ROLE_USER" :: T.Text),"parts" .= [object ["text" .= text]]] ++ ["contextId" .= c | Just c <- [context]]),"configuration" .= object ["returnImmediately" .= True]])
getTask :: String -> T.Text -> Maybe Int -> IO Value
getTask url i h = rpcCall url "GetTask" (object (["id" .= i] ++ ["historyLength" .= n | Just n <- [h]]))
awaitTask :: String -> T.Text -> IO Value
awaitTask url i = do
  t <- getTask url i Nothing
  if stopped t then pure t else threadDelay 1000000 >> awaitTask url i
