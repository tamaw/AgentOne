{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module A2A (serve, callRPC, sendText, awaitTask, clientMain) where
import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.Aeson
import Data.Aeson.Types (Parser,parseEither)
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Encoding as TE
import Data.Char (toLower)
import Data.Maybe
import Data.Time
import Network.Socket
import System.IO
import System.Directory
import System.Environment
import System.Process
import System.Exit
import ExecutionRuntime (ModelConfig(..), message, trySync)
import A2AExecution
import A2ACompat
import Control.Concurrent.Async

root = ".runs/a2a/"
field k (Object o) = fromMaybe Null (K.lookup k o)
field _ _ = Null
txt (String t) = t
txt _ = ""
arr (Array a) = foldr (:) [] a
arr _ = []
set k v (Object o) = Object (K.insert k v o)
set _ _ v = v
str = String
fresh = T.strip <$> T.readFile "/proc/sys/kernel/random/uuid"
stamp = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" <$> getCurrentTime
state t = txt (field "state" (field "status" t))
terminal t = state t `elem` ["TASK_STATE_COMPLETED","TASK_STATE_FAILED","TASK_STATE_CANCELED","TASK_STATE_REJECTED"]
done t = terminal t || state t `elem` ["TASK_STATE_INPUT_REQUIRED","TASK_STATE_AUTH_REQUIRED"]
data DB = DB { tasks :: M.Map T.Text Value, contexts :: M.Map T.Text [Value] }
instance ToJSON DB where toJSON (DB ts cs) = object ["tasks" .= ts,"contexts" .= cs]
instance FromJSON DB where parseJSON = withObject "DB" $ \o -> DB <$> o .: "tasks" <*> o .: "contexts"
persist d = L.writeFile (root++"state.tmp") (encode d) >> renameFile (root++"state.tmp") (root++"state.json")
change db f = modifyMVar db $ \d -> do
  let (d',x)=f d
  persist d'
  pure (d',x)
agentMessage :: T.Text -> T.Text -> T.Text -> IO Value
agentMessage cid tid text = do
  mid <- fresh
  pure $ object ["messageId" .= mid,"contextId" .= cid,"taskId" .= tid,"role" .= ("ROLE_AGENT"::T.Text),"parts" .= [object ["text" .= text]]]
status :: T.Text -> Maybe Value -> T.Text -> Value
status s m tm = object (["state" .= (s::T.Text),"timestamp" .= tm] ++ ["message" .= x | Just x <- [m]])
limited Nothing t = t
limited (Just n) t = set "history" (toJSON (drop (max 0 (length hs-n)) hs)) t where hs=arr (field "history" t)
historyP o = do n <- o .:? "historyLength"; case n of Just x | (x < (0::Int) || toInteger x > 2147483647) -> fail "negative historyLength"; _ -> pure n
nonempty :: Object -> Key -> Parser T.Text
nonempty o k = do t <- o .: k; when (T.null t) (fail "empty identifier"); pure t
data Send = Send Value Bool (Maybe Int)
sendP = withObject "params" $ \o -> do
  m <- o .: "message"
  withObject "message" (\x -> do
    (_::T.Text) <- nonempty x "messageId"
    role <- x .: "role"; unless (role == ("ROLE_USER"::T.Text)) (fail "ROLE_USER required")
    ps <- x .: "parts" :: Parser [Value]; when (null ps) (fail "parts required")
    forM_ ps $ withObject "part" $ \p -> do
      unless (length (filter (`K.member` p) ["text","raw","url","data"]) == 1) (fail "one part content required")
      forM_ (K.lookup "text" p) $ \v -> void (parseJSON v :: Parser T.Text)
      when (K.member "kind" p) (fail "no kind in 1.0")
    forM_ ["contextId","taskId"] $ \k -> do (_::Maybe T.Text) <- x .:? k; pure ()
    when (K.member "kind" x) (fail "no kind in A2A 1.0")) m
  cfg <- o .:? "configuration" .!= object []
  (im,h) <- withObject "configuration" (\c -> do
    (_::Maybe [T.Text]) <- c .:? "acceptedOutputModes"
    (,) <$> c .:? "returnImmediately" .!= False <*> historyP c) cfg
  pure (Send m im h)
idP :: Value -> Parser (T.Text, Maybe Int)
idP = withObject "params" $ \o -> (,) <$> nonempty o "id" <*> historyP o
rpcP = withObject "rpc" $ \o -> do
  v <- o .: "jsonrpc"; unless (v == ("2.0"::T.Text)) (fail "jsonrpc")
  i <- o .: "id"; unless (case i of String _ -> True; Number _ -> True; Null -> True; _ -> False) (fail "id")
  m <- o .: "method"; p <- o .:? "params" .!= object []; pure (i,m::T.Text,p)
rpcError i code msg = object ["jsonrpc" .= ("2.0"::T.Text),"id" .= i,"error" .= object ["code" .= (code::Int),"message" .= (msg::T.Text)]]
rpcOK i v = object ["jsonrpc" .= ("2.0"::T.Text),"id" .= i,"result" .= v]
type Locks = MVar (M.Map T.Text (MVar ()))
contextLock ls cid = modifyMVar ls $ \m -> case M.lookup cid m of Just l -> pure (m,l); Nothing -> do l <- newMVar (); pure (M.insert cid l m,l)
type Running = MVar (M.Map T.Text (Async ()))
spawnTask db locks hub running model endpoint key tid = mask $ \restore -> do
  gate <- newEmptyMVar
  a <- async $ (takeMVar gate >> restore (runTask db locks hub model endpoint key tid)) `finally` modifyMVar_ running (pure . M.delete tid)
  modifyMVar_ running (pure . M.insert tid a)
  putMVar gate ()
runTask db locks hub model endpoint key tid = do
  mt <- M.lookup tid . tasks <$> readMVar db
  forM_ mt $ \t -> do
    let cid = txt (field "contextId" t)
    lock <- contextLock locks cid
    withMVar lock $ \_ -> do
      active <- change db $ \d -> case M.lookup tid (tasks d) of
        Just cur | not (terminal cur) ->
          let input=head (arr (field "history" cur)); prior=M.findWithDefault [] cid (contexts d)
              cur'=set "status" (set "state" (str "TASK_STATE_WORKING") (field "status" cur)) cur
          in (d {tasks=M.insert tid cur' (tasks d),contexts=M.insert cid (prior++[input]) (contexts d)},Just (input,prior))
        _ -> (d,Nothing)
      forM_ active $ \(input,prior) -> do
        instructionFile <- fromMaybe "SYSTEM.md" <$> lookupEnv "INSTRUCTIONS_FILE"
        let convert m=message (if txt (field "role" m)=="ROLE_AGENT" then "assistant" else "user") (T.intercalate "\n" [txt (field "text" p)|p<-arr (field "parts" m)])
            inbound=T.intercalate "\n" [txt (field "text" p)|p<-arr (field "parts" input)]
        result <- trySync (runExecution hub (ModelConfig endpoint key model instructionFile) cid tid (map convert prior) inbound)
        let (s,text)=case result of
              Right output -> ("TASK_STATE_COMPLETED",output)
              Left _ -> ("TASK_STATE_FAILED","Execution runtime failed. Worker reset if executing; files/effects may persist. Actual execution feedback is saved under this context's private .runs/a2a/execution directory.")
        msg <- agentMessage cid tid text; tm <- stamp; aid <- fresh
        change db (\d -> case M.lookup tid (tasks d) of
          Just cur | not (terminal cur) ->
            let cur'=set "status" (status s (Just msg) tm) $ set "history" (toJSON (arr (field "history" cur)++[msg])) $ set "artifacts" (toJSON [object ["artifactId" .= aid,"parts" .= [object ["text" .= text]]]]) cur
            in (d {tasks=M.insert tid cur' (tasks d),contexts=M.insertWith (\new old -> old++new) cid [msg] (contexts d)},())
          _ -> (d,()))
waitTask db tid = do
  t <- fromJust . M.lookup tid . tasks <$> readMVar db
  if done t then pure t else threadDelay 50000 >> waitTask db tid
handleRPC db locks hub running model endpoint key version raw = case eitherDecodeStrict' raw of
  Left _ -> pure (rpcError Null (-32700) "Parse error")
  Right request -> case parseEither rpcP request of
    Left _ -> pure (rpcError Null (-32600) "Invalid Request")
    Right (i,method,params) | (version /= Just "1.0") -> pure (rpcError i (-32009) "VersionNotSupportedError")
    Right (i,method,params) -> do
      let err c m = pure (rpcError i c m)
      case method of
        "SendMessage" | field "taskPushNotificationConfig" (field "configuration" params) /= Null -> err (-32003) "PushNotificationNotSupportedError"
        "SendMessage" | let modes=arr (field "acceptedOutputModes" (field "configuration" params)), not (null modes), not (String "text/plain" `elem` modes) -> err (-32005) "ContentTypeNotSupportedError"
        "SendMessage" -> case parseEither sendP params of
          Left _ -> err (-32602) "Invalid params"
          Right (Send m _ _) | any (\p -> case field "text" p of String _ -> False; _ -> True) (arr (field "parts" m)) -> err (-32005) "ContentTypeNotSupportedError"
          Right (Send m immediate h) -> do
            tid <- fresh; cidNew <- fresh; tm <- stamp
            created <- change db $ \d ->
              let ref = txt (field "taskId" m); provided = txt (field "contextId" m)
                  duplicate = [t | t <- M.elems (tasks d), any ((==field "messageId" m) . field "messageId") (take 1 (arr (field "history" t)))]
                  cid = if T.null provided then cidNew else provided
                  input = set "taskId" (str tid) (set "contextId" (str cid) m)
                  t = object ["id" .= tid,"contextId" .= cid,"status" .= status "TASK_STATE_SUBMITTED" Nothing tm,"history" .= [input],"artifacts" .= ([]::[Value])]
              in if not (T.null ref) then case M.lookup ref (tasks d) of
                   Nothing -> (d,Left (-32001,"TaskNotFoundError"))
                   Just old | not (T.null provided) && provided /= txt (field "contextId" old) -> (d,Left (-32602,"Context mismatch"))
                   Just _ -> (d,Left (-32004,"UnsupportedOperationError: task continuation is not supported; send a new task in the same context"))
                 else case duplicate of
                   old:_ -> (d,Right (old,False))
                   [] -> (d {tasks=M.insert tid t (tasks d)},Right (t,True))
            case created of
              Left (c,m) -> err c m
              Right (t,isNew) -> do
                when isNew $ spawnTask db locks hub running model endpoint key (txt (field "id" t))
                final <- if immediate then pure t else waitTask db (txt (field "id" t))
                pure $ rpcOK i (object ["task" .= limited h final])
        "GetTask" -> case parseEither idP params of
          Left _ -> err (-32602) "Invalid params"
          Right (tid,h) -> do
            mt <- M.lookup tid . tasks <$> readMVar db
            maybe (err (-32001) "TaskNotFoundError") (pure . rpcOK i . limited h) mt
        "CancelTask" -> case parseEither idP params of
          Left _ -> err (-32602) "Invalid params"
          Right (tid,_) -> do
            tm <- stamp
            mt <- M.lookup tid . tasks <$> readMVar db
            case mt of
              Nothing -> err (-32001) "TaskNotFoundError"
              Just old -> do
                msg <- agentMessage (txt (field "contextId" old)) tid "Task canceled."
                res <- change db $ \d -> case M.lookup tid (tasks d) of
                  Just cur | not (terminal cur) -> let t=set "status" (status "TASK_STATE_CANCELED" (Just msg) tm) $ set "history" (toJSON (arr (field "history" cur)++[msg])) cur in (d {tasks=M.insert tid t (tasks d)},Right t)
                  _ -> (d,Left ())
                case res of
                  Left () -> err (-32002) "TaskNotCancelableError"
                  Right canceled -> do
                    job <- M.lookup tid <$> readMVar running
                    forM_ job cancel
                    pure (rpcOK i canceled)
        _ -> err (-32601) "Method not found"
agentCard = object ["name" .= ("Agent One"::T.Text),"description" .= ("Haskell engineering agent with model-backed contextual text tasks"::T.Text),"version" .= ("1.0.0"::T.Text),"supportedInterfaces" .= [object ["url" .= ("http://agent-one:8080/rpc"::T.Text),"protocolBinding" .= ("JSONRPC"::T.Text),"protocolVersion" .= ("1.0"::T.Text)]],"capabilities" .= object ["streaming" .= False,"pushNotifications" .= False],"defaultInputModes" .= ["text/plain"::T.Text],"defaultOutputModes" .= ["text/plain"::T.Text],"skills" .= [object ["id" .= ("engineering"::T.Text),"name" .= ("Engineering review"::T.Text),"description" .= ("Contextual model-composed engineering analysis"::T.Text),"tags" .= ["haskell"::T.Text,"review"]]]]
serve = withSocketsDo $ do
  createDirectoryIfMissing True root
  exists <- doesFileExist (root++"state.json")
  d <- if exists then L.readFile (root++"state.json") >>= either (ioError . userError) pure . eitherDecode else pure (DB M.empty M.empty)
  db <- newMVar d; locks <- newMVar M.empty; logLock <- newMVar (); hub <- newHub; running <- newMVar M.empty
  endpoint <- fromMaybe "" <$> lookupEnv "LLM_ENDPOINT"; key <- fromMaybe "" <$> lookupEnv "LLM_API_KEY"; model <- getEnv "LLM_MODEL"
  sock <- socket AF_INET Stream defaultProtocol
  setSocketOption sock ReuseAddr 1; bind sock (SockAddrInet 8080 0); listen sock 128
  forM_ (M.toList (tasks d)) $ \(tid,t) -> unless (terminal t) $ do
    tm <- stamp
    msg <- agentMessage (txt (field "contextId" t)) tid "Server restarted during this task. Execution may have partially occurred; live worker memory/actions reset. Submit a new message after inspecting effects."
    change db $ \current -> (current {tasks=M.adjust (set "status" (status "TASK_STATE_FAILED" (Just msg) tm)) tid (tasks current)},())
  L.writeFile (root++"ready.json") (encode (object ["ready" .= True,"url" .= ("http://agent-one:8080/rpc"::T.Text)]))
  forever $ do
    (s,_) <- accept sock
    void $ forkIO $ (do
      h <- socketToHandle s ReadWriteMode; hSetBinaryMode h True; hSetBuffering h NoBuffering
      flip finally (hClose h) $ do
        line <- C.hGetLine h
        let headers acc = do l <- C.hGetLine h; if l=="\r" || B.null l then pure acc else let (k,v)=C.break (==':') l in headers ((map toLower (C.unpack k),T.strip (T.pack (C.unpack (C.drop 1 v)))):acc)
        hs <- headers []
        let parts=C.words line; method=if null parts then "" else head parts; path=if length parts<2 then "" else parts!!1
            n=fromMaybe 0 (lookup "content-length" hs >>= readMaybeInt . T.unpack)
            respond code body = do C.hPutStr h (C.pack ("HTTP/1.1 "++code++"\r\nContent-Type: application/json\r\nA2A-Version: 1.0\r\nConnection: close\r\nContent-Length: "++show (L.length body)++"\r\n\r\n")); L.hPut h body
        if method=="GET" && path=="/.well-known/agent-card.json" then respond "200 OK" (encode agentCard)
        else if method=="GET" && path=="/a2a/v0.3/.well-known/agent-card.json" then respond "200 OK" (encode (legacyCard agentCard))
        else if method=="GET" && path `elem` ["/health","/a2a/v0.3/health"] then respond "200 OK" (encode (object ["status" .= ("ok"::T.Text)]))
        else if method=="GET" && path=="/implementation" then do source <- T.readFile "src/A2A.hs"; runtime <- T.readFile "src/ExecutionRuntime.hs"; adapter <- T.readFile "src/A2AExecution.hs"; respond "200 OK" (encode (object ["source" .= source,"runtime" .= runtime,"adapter" .= adapter]))
        else if method=="POST" && path `elem` ["/rpc","/a2a/v0.3/rpc"] && n>=0 && n<=1048576 then do
          body <- B.hGet h n
          let legacy = path=="/a2a/v0.3/rpc"
          result <- handleRPC db locks hub running model endpoint key (if legacy then Just "1.0" else lookup "a2a-version" hs) (if legacy then legacyRequest body else body) `catch` \(_::SomeException) -> pure (rpcError (maybe Null (field "id") (decodeStrict' body)) (-32603) "Internal error")
          let answer = if legacy then legacyResponse result else result
          withMVar logLock $ \_ -> L.appendFile (root++"wire.jsonl") (encode (object ["direction" .= ("inbound"::T.Text),"request" .= fromMaybe Null (decodeStrict' body),"response" .= answer])<>"\n")
          respond "200 OK" (encode answer)
        else respond "404 Not Found" (encode (object ["error" .= ("Not found"::T.Text)]))) `catch` \(_::SomeException) -> pure ()
readMaybeInt s = case reads s of [(n,"")] -> Just (n::Int); _ -> Nothing
callRPC :: String -> T.Text -> Value -> IO Value
callRPC url method params = do
  mid <- fresh
  let request=object ["jsonrpc" .= ("2.0"::T.Text),"id" .= mid,"method" .= (method::T.Text),"params" .= params]
  createDirectoryIfMissing True root
  let reqFile=root++"client-"++T.unpack mid++".request.json"; resFile=root++"client-"++T.unpack mid++".response.json"
  L.writeFile reqFile (encode request)
  (code,_,_) <- readProcessWithExitCode "curl" ["--silent","--show-error","--max-time","600","-H","Content-Type: application/json","-H","A2A-Version: 1.0","--data-binary","@"++reqFile,"--output",resFile,url] ""
  unless (code==ExitSuccess) (ioError (userError "A2A transport failure"))
  response <- B.readFile resFile >>= either (ioError . userError) pure . eitherDecodeStrict'
  createDirectoryIfMissing True root
  L.appendFile (root++"client-wire.jsonl") (encode (object ["direction" .= ("outbound"::T.Text),"url" .= url,"request" .= request,"response" .= (response::Value)])<>"\n")
  pure response
clientMain url method raw = do
  p <- either (ioError . userError) pure (eitherDecodeStrict' (TE.encodeUtf8 (T.pack raw)))
  callRPC url (T.pack method) p >>= C.putStrLn . L.toStrict . encode

sendText :: String -> Maybe T.Text -> T.Text -> IO Value
sendText url cid text = do
  mid <- fresh
  let msg=object (["messageId" .= mid,"role" .= ("ROLE_USER"::T.Text),"parts" .= [object ["text" .= text]]]++["contextId" .= c | Just c <- [cid]])
  response <- callRPC url "SendMessage" (object ["message" .= msg,"configuration" .= object ["returnImmediately" .= True]])
  if field "error" response /= Null then ioError (userError (show (field "error" response))) else pure (field "task" (field "result" response))
awaitTask :: String -> T.Text -> IO Value
awaitTask url tid = do
  response <- callRPC url "GetTask" (object ["id" .= tid])
  let task=field "result" response
  if field "error" response /= Null then ioError (userError (show (field "error" response))) else if done task then pure task else threadDelay 1000000 >> awaitTask url tid
