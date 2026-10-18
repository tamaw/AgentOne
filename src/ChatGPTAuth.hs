{-# LANGUAGE DeriveGeneric #-}
module ChatGPTAuth (authCommand, chatGPT, chatGPTAccess) where

import Control.Exception
import Control.Monad
import Crypto.Hash (Digest, SHA256(..), hash)
import Crypto.Random (getRandomBytes)
import qualified Crypto.PubKey.RSA.PKCS15 as RSA
import Crypto.PubKey.RSA.Types (PublicKey(..))
import Data.Aeson hiding (json)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as K
import Data.Aeson.Types (parseMaybe)
import Data.Bits
import qualified Data.ByteArray as BA
import Data.ByteArray.Encoding
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L
import Data.Char (chr, isHexDigit, digitToInt)
import Data.List (find)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Text.Encoding.Error (lenientDecode)
import qualified Data.Text.IO as T
import Data.Time.Clock.POSIX
import GHC.Generics (Generic)
import Network.Socket
import qualified Network.Socket.ByteString as N
import Numeric (showHex)
import System.Directory hiding (isSymbolicLink)
import System.Environment
import System.Exit
import System.FilePath
import System.IO
import System.Posix.Files
import System.Posix.IO
import System.Process
import System.Timeout
import Text.Read (readMaybe)

data Account = Account
  { client_id :: T.Text, subject :: T.Text, email :: T.Text
  , access_token :: T.Text, refresh_token :: T.Text, id_token :: T.Text
  , scopes :: [T.Text], expires_at :: Integer, earliest_refresh_at :: Integer
  } deriving (Generic)
instance ToJSON Account
instance FromJSON Account

data Vault = Vault { active_account :: Maybe T.Text, accounts :: M.Map T.Text Account } deriving (Generic)
instance ToJSON Vault
instance FromJSON Vault

issuer, resource, consentScope :: T.Text
issuer = "https://auth.openai.com"
resource = "https://api.openai.com/v1"
consentScope = "chatgpt.tokens.use.direct"

reject :: String -> IO a
reject = ioError . userError

now :: IO Integer
now = floor <$> getPOSIXTime

textField :: T.Text -> Value -> T.Text
textField name value = fromMaybe "" $ parseMaybe (withObject "field" (.: Key.fromText name)) value

numberField :: T.Text -> Value -> Integer
numberField name value = fromMaybe 0 $ parseMaybe (withObject "field" (.: Key.fromText name)) value

json :: B.ByteString -> IO Value
json = either (const $ reject "Invalid JSON from authentication service") pure . eitherDecodeStrict'

encodeURL :: T.Text -> String
encodeURL = concatMap escape . B.unpack . T.encodeUtf8
  where
    escape n | n >= 65 && n <= 90 || n >= 97 && n <= 122 || n >= 48 && n <= 57 || n `elem` [45,46,95,126] = [chr (fromIntegral n)]
             | otherwise = '%' : (if n < 16 then "0" else "") ++ showHex n ""

form :: [(T.Text,T.Text)] -> String
form = concat . zipWith (++) ("" : repeat "&") . map (\(k,v) -> encodeURL k ++ "=" ++ encodeURL v)

http :: T.Text -> Maybe [(T.Text,T.Text)] -> [(T.Text,T.Text)] -> IO B.ByteString
http url body headers = do
  let config = unlines $ ["url = " ++ show (T.unpack url)] ++
        ["header = " ++ show (T.unpack k ++ ": " ++ T.unpack v) | (k,v) <- headers] ++
        maybe [] (\fields -> ["header = \"Content-Type: application/x-www-form-urlencoded\"", "data = " ++ show (form fields)]) body
  (code,out,_) <- readProcessWithExitCode "curl" ["--silent","--show-error","--fail-with-body","--proto","=https","--max-time","45","--max-filesize","1048576","--config","-"] config
  unless (code == ExitSuccess) $ reject "OpenAI authentication request failed; retry sign-in or check connectivity. Credentials were not changed."
  pure $ T.encodeUtf8 $ T.pack out

jsonHTTP :: T.Text -> Maybe [(T.Text,T.Text)] -> [(T.Text,T.Text)] -> IO Value
jsonHTTP url body headers = http url body headers >>= json

metadata :: IO Value
metadata = do
  value <- jsonHTTP (issuer <> "/.well-known/openid-configuration") Nothing []
  unless (textField "issuer" value == issuer) $ reject "Unexpected OpenAI issuer"
  forM_ ["authorization_endpoint","token_endpoint","jwks_uri","revocation_endpoint"] $ \k ->
    unless ((issuer <> "/") `T.isPrefixOf` textField k value) $ reject "Unexpected OpenAI authentication endpoint"
  pure value

authDirectory :: IO FilePath
authDirectory = do
  path <- lookupEnv "LLM_AUTH_DIR" >>= maybe (getXdgDirectory XdgConfig "agent-one") pure
  createDirectoryIfMissing True path
  status <- getSymbolicLinkStatus path
  unless (isDirectory status && not (isSymbolicLink status)) $ reject "Authentication directory must be a real directory"
  setFileMode path 0o700
  pure path

atomicPrivate :: FilePath -> B.ByteString -> IO ()
atomicPrivate path content = bracketOnError (openBinaryTempFile (takeDirectory path) ".auth-")
  (\(tmp,h) -> hClose h `finally` removeFile tmp) $ \(tmp,h) -> do
    setFileMode tmp 0o600
    B.hPut h content
    hClose h
    renameFile tmp path

withVault :: (FilePath -> Vault -> IO a) -> IO a
withVault action = do
  dir <- authDirectory
  bracket (openFd (dir </> "credentials.lock") ReadWrite defaultFileFlags { creat=Just 0o600, nofollow=True, cloexec=True }) closeFd $ \fd -> do
    waitToSetLock fd (WriteLock,AbsoluteSeek,0,0)
    let path = dir </> "credentials.json"
    exists <- doesFileExist path
    vault <- if not exists then pure (Vault Nothing M.empty) else do
      status <- getSymbolicLinkStatus path
      unless (isRegularFile status && not (isSymbolicLink status) && fileMode status .&. 0o077 == 0) $ reject "Credentials must be a regular owner-only file (chmod 600)"
      content <- B.readFile path
      either (const $ reject "Invalid saved ChatGPT credentials") pure (eitherDecodeStrict' content)
    action dir vault

saveVault :: FilePath -> Vault -> IO ()
saveVault dir = atomicPrivate (dir </> "credentials.json") . L.toStrict . encode

randomText :: Int -> IO T.Text
randomText size = T.decodeUtf8 . convertToBase Base64URLUnpadded <$> (getRandomBytes size :: IO B.ByteString)

hostID :: FilePath -> IO T.Text
hostID dir = do
  let path = dir </> "host-id"
  exists <- doesFileExist path
  if exists then do
    value <- T.strip <$> T.readFile path
    unless ("urn:uuid:" `T.isPrefixOf` value && T.length value == 45) $ reject "Invalid saved agent host ID"
    pure value
  else do
    bytes <- getRandomBytes 16 :: IO B.ByteString
    let fixed = B.pack [if i == 6 then n .&. 15 .|. 64 else if i == 8 then n .&. 63 .|. 128 else n | (i,n) <- zip [0::Int ..] (B.unpack bytes)]
        hex = T.decodeUtf8 $ convertToBase Base16 fixed
        value = "urn:uuid:" <> T.intercalate "-" [T.take 8 hex,T.take 4 (T.drop 8 hex),T.take 4 (T.drop 12 hex),T.take 4 (T.drop 16 hex),T.drop 20 hex]
    atomicPrivate path (T.encodeUtf8 value)
    pure value

selected :: Vault -> IO Account
selected vault = maybe (reject "No ChatGPT account selected. Run: agent-one auth login") pure $ active_account vault >>= (`M.lookup` accounts vault)

unbase64 :: T.Text -> IO B.ByteString
unbase64 = either (const $ reject "Invalid ID-token encoding") pure . convertFromBase Base64URLUnpadded . T.encodeUtf8

validateID :: Value -> T.Text -> Maybe T.Text -> T.Text -> IO Value
validateID discovery client expectedNonce token = do
  (encodedHeader,encodedClaims,signature) <- case T.splitOn "." token of
    [a,b,c] -> pure (a,b,c)
    _ -> reject "Invalid ID token"
  header <- unbase64 encodedHeader >>= json
  claims <- unbase64 encodedClaims >>= json
  unless (textField "alg" header == "RS256" && not (maybe False (K.member "crit") (parseMaybe (withObject "header" pure) header)) && not (T.null (textField "kid" header))) $ reject "Unsupported ID-token signature"
  keys <- jsonHTTP (textField "jwks_uri" discovery) Nothing []
  let candidates = fromMaybe [] $ parseMaybe (withObject "JWKS" (.: "keys")) keys :: [Value]
  key <- maybe (reject "ID-token signing key is absent from OpenAI JWKS") pure $ find (\k -> textField "kid" k == textField "kid" header && textField "kty" k == "RSA" && textField "use" k `elem` ["","sig"] && textField "alg" k `elem` ["","RS256"]) candidates
  modulus <- unbase64 (textField "n" key)
  exponent <- unbase64 (textField "e" key)
  sig <- unbase64 signature
  let integer = B.foldl' (\n x -> n*256+fromIntegral x) 0
      pub = PublicKey (B.length modulus) (integer modulus) (integer exponent)
  unless (B.length modulus >= 256 && RSA.verify (Just SHA256) pub (T.encodeUtf8 (encodedHeader <> "." <> encodedClaims)) sig) $ reject "Invalid ID-token signature"
  timestamp <- now
  let authorizedParty = textField "azp" claims
      audiences = fromMaybe [] (parseMaybe (withObject "claims" (.: "aud")) claims :: Maybe [T.Text])
      audience = textField "aud" claims == client || maybe False (client `elem`) (parseMaybe (withObject "claims" (.: "aud")) claims :: Maybe [T.Text])
  unless (textField "iss" claims == issuer && audience && (T.null authorizedParty || authorizedParty == client) && (length audiences <= 1 || authorizedParty == client) && numberField "exp" claims > timestamp && numberField "nbf" claims <= timestamp+30 && numberField "iat" claims <= timestamp+30 && not (T.null (textField "sub" claims))) $ reject "Invalid ID-token issuer, audience, identity, or lifetime"
  forM_ expectedNonce $ \nonce -> unless (BA.constEq (T.encodeUtf8 nonce) (T.encodeUtf8 (textField "nonce" claims))) $ reject "ID-token nonce mismatch"
  pure claims

makeAccount :: Value -> T.Text -> Value -> Maybe Account -> Maybe T.Text -> IO Account
makeAccount discovery client result previous nonce = do
  timestamp <- now
  let token = textField "id_token" result
      granted = if T.null (textField "scope" result) then maybe [] scopes previous else T.words (textField "scope" result)
      access = textField "access_token" result
      refresh = textField "refresh_token" result
      expiry = numberField "expires_in" result
  unless (consentScope `elem` granted && T.toCaseFold (textField "token_type" result) == "bearer" && expiry > 0 && not (T.null access || T.null refresh)) $ reject "ChatGPT plan permission or renewable credentials missing; sign in again and grant plan access"
  when (nonce /= Nothing && T.null token) $ reject "ID token missing from sign-in response"
  claims <- if T.null token then maybe (reject "ID token missing") (\old -> pure $ object ["sub" .= subject old,"email" .= email old]) previous else validateID discovery client nonce token
  forM_ previous $ \old -> unless (subject old == textField "sub" claims && client_id old == client) $ reject "ChatGPT account identity changed; add it as a separate account"
  pure $ Account client (textField "sub" claims) (textField "email" claims) access refresh
    (if T.null token then maybe "" id_token previous else token) granted (timestamp+expiry) (numberField "earliest_refresh_at" result)

chatGPT :: IO Bool
chatGPT = lookupEnv "LLM_AUTH" >>= \value -> case value of
  Nothing -> pure False
  Just "foundry" -> pure False
  Just "chatgpt" -> pure True
  _ -> reject "LLM_AUTH must be foundry or chatgpt"

chatGPTAccess :: IO (T.Text,T.Text)
chatGPTAccess = withVault $ \dir vault -> do
  account <- selected vault
  timestamp <- now
  current <- if expires_at account > timestamp+60 || earliest_refresh_at account > timestamp && expires_at account > timestamp then pure account else do
    when (T.null (refresh_token account)) $ reject "ChatGPT account is signed out; run agent-one auth login"
    when (earliest_refresh_at account > timestamp) $ reject "ChatGPT token cannot refresh yet; retry after its earliest refresh time"
    discovery <- metadata
    response <- jsonHTTP (textField "token_endpoint" discovery) (Just [("grant_type","refresh_token"),("client_id",client_id account),("refresh_token",refresh_token account),("resource",resource)]) []
    refreshed <- makeAccount discovery (client_id account) response (Just account) Nothing
    saveVault dir vault { accounts = M.insert (client_id refreshed) refreshed (accounts vault) }
    pure refreshed
  unless (consentScope `elem` scopes current && not (T.null (access_token current))) $ reject "ChatGPT plan use is not authorized; run agent-one auth login"
  T.putStrLn $ "[ChatGPT account: " <> email current <> " (" <> client_id current <> ")]"
  pure (access_token current,client_id current)

decodeQuery :: String -> [(T.Text,T.Text)]
decodeQuery = map field . split '&'
  where
    split c s = case break (==c) s of (a,[]) -> [a];(a,_:b) -> a:split c b
    field s = let (k,v)=break (=='=') s in (decode k,decode (drop 1 v))
    decode = T.decodeUtf8With lenientDecode . B.pack . bytes
    bytes []=[]
    bytes ('%':a:b:xs) | isHexDigit a && isHexDigit b = fromIntegral (16*digitToInt a+digitToInt b):bytes xs
    bytes ('+':xs)=32:bytes xs
    bytes (x:xs)=fromIntegral (fromEnum x):bytes xs

callback :: Socket -> T.Text -> IO [(T.Text,T.Text)]
callback listener expectedState = do
  fields <- bracket (accept listener) (close . fst) $ \(conn,_) -> do
    request <- timeout 5000000 (receive conn B.empty)
    let path = maybe "" (\raw -> case C.words (head (C.lines raw ++ [""])) of "GET":target:_ -> C.unpack target;_ -> "") request
        (route,query)=break (=='?') path
        fields=decodeQuery (drop 1 query)
        valid=length fields == M.size (M.fromList fields) && route=="/auth/callback" && maybe False (\s -> BA.constEq (T.encodeUtf8 expectedState) (T.encodeUtf8 s)) (lookup "state" fields)
    N.sendAll conn $ if valid then "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\n\r\nAuthorization received. Return to Agent One to check sign-in.\n" else "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nInvalid callback.\n"
    pure $ if valid then Just fields else Nothing
  maybe (callback listener expectedState) pure fields
  where receive conn acc | B.length acc > 16384 = pure B.empty
                         | "\r\n\r\n" `B.isInfixOf` acc = pure acc
                         | otherwise = do chunk <- N.recv conn 4096; if B.null chunk then pure acc else receive conn (acc<>chunk)

login :: Bool -> IO ()
login newAccount = do
  (host,previous,pending) <- withVault $ \dir vault -> do
    host <- hostID dir
    let previous=if newAccount then Nothing else active_account vault >>= (`M.lookup` accounts vault)
        path=dir </> "pending-client"
    exists <- doesFileExist path
    pending <- if maybe True (const False) previous && exists then do
      client <- T.strip <$> T.readFile path
      unless ("oaiapp_" `T.isPrefixOf` client) $ reject "Invalid pending client registration"
      pure (Just client)
      else pure Nothing
    pure (host,previous,pending)
  discovery <- metadata
  verifier <- randomText 48
  state <- randomText 32
  nonce <- randomText 32
  let challenge = T.decodeUtf8 $ convertToBase Base64URLUnpadded (hash (T.encodeUtf8 verifier) :: Digest SHA256)
      client = maybe (fromMaybe "dynamic_agent_client" pending) client_id previous
  port <- lookupEnv "LLM_OAUTH_PORT" >>= maybe (pure 1456) (maybe (reject "Invalid LLM_OAUTH_PORT") pure . readMaybe)
  unless (port >= 1 && port <= 65535) $ reject "LLM_OAUTH_PORT must be 1..65535"
  bindHost <- fromMaybe "127.0.0.1" <$> lookupEnv "LLM_OAUTH_BIND"
  unless (bindHost `elem` ["127.0.0.1","0.0.0.0"]) $ reject "LLM_OAUTH_BIND must be 127.0.0.1 or 0.0.0.0"
  withSocketsDo $ bracket (socket AF_INET Stream defaultProtocol) close $ \listener -> do
    setSocketOption listener ReuseAddr 1
    bind listener (SockAddrInet (fromIntegral (port::Int)) (if bindHost=="127.0.0.1" then tupleToHostAddress (127,0,0,1) else tupleToHostAddress (0,0,0,0)))
    listen listener 4
    let redirect = T.pack $ "http://127.0.0.1:" ++ show port ++ "/auth/callback"
        params = [("client_id",client),("ext_agent_host_id",host),("response_type","code"),("redirect_uri",redirect),("scope","openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),("resource",resource),("state",state),("nonce",nonce),("code_challenge_method","S256"),("code_challenge",challenge)] ++ (if client == "dynamic_agent_client" then [("agent_name_hint","AgentOne")] else maybe [] (\old -> [("login_hint",email old)]) previous)
        url = textField "authorization_endpoint" discovery <> "?" <> T.pack (form params)
    T.putStrLn $ "Continue with ChatGPT — open this URL in your browser:\n" <> url
    putStrLn "Waiting up to 10 minutes for browser consent. Callback must reach this host."
    fields <- timeout 600000000 (callback listener state) >>= maybe (reject "ChatGPT sign-in timed out") pure
    when (lookup "error" fields /= Nothing) $ reject "ChatGPT authorization declined; existing account unchanged"
    let issued = fromMaybe (if client == "dynamic_agent_client" then "" else client) (lookup "client_id" fields)
        code = fromMaybe "" (lookup "code" fields)
    unless ("oaiapp_" `T.isPrefixOf` issued && not (T.null code) && (client == "dynamic_agent_client" || issued == client)) $ reject "Invalid client registration callback"
    when (maybe True (const False) previous) $ withVault $ \dir _ -> atomicPrivate (dir </> "pending-client") (T.encodeUtf8 issued)
    response <- jsonHTTP (textField "token_endpoint" discovery) (Just [("grant_type","authorization_code"),("client_id",issued),("code",code),("code_verifier",verifier),("redirect_uri",redirect),("resource",resource)]) []
    account <- makeAccount discovery issued response previous (Just nonce)
    withVault $ \dir vault -> do
      forM_ (M.lookup issued (accounts vault)) $ \old -> unless (subject old == subject account) $ reject "Existing client identity mismatch"
      saveVault dir vault { active_account=Just issued, accounts=M.insert issued account (accounts vault) }
      let path=dir </> "pending-client"
      exists <- doesFileExist path
      when exists $ do saved<-T.strip <$> T.readFile path; when (saved==issued) (removeFile path)
    T.putStrLn $ "Signed in: " <> email account <> " (" <> issued <> ")"
    putStrLn "Usage and app access: https://chatgpt.com/settings/usage"

logout :: IO ()
logout = withVault $ \dir vault -> do
  account <- selected vault
  result <- tryJust (\e -> case fromException e :: Maybe SomeAsyncException of Just _ -> Nothing;_ -> Just e) $ do
    discovery <- metadata
    void $ http (textField "revocation_endpoint" discovery) (Just [("token",refresh_token account),("token_type_hint","refresh_token"),("client_id",client_id account)]) []
  let cleared=account { access_token="", refresh_token="", id_token="", expires_at=0 }
  saveVault dir vault { accounts=M.insert (client_id account) cleared (accounts vault) }
  case result of
    Left (_::SomeException) -> putStrLn "Signed out locally; remote revocation was not confirmed. Disconnect AgentOne in ChatGPT Settings."
    Right () -> putStrLn "Signed out and renewable session revoked."

authCommand :: [String] -> IO ()
authCommand args = case args of
  ["login"] -> login False
  ["add"] -> login True
  ["logout"] -> logout
  ["use",name] -> withVault $ \dir vault -> if M.member (T.pack name) (accounts vault) then saveVault dir vault { active_account=Just (T.pack name) } >> putStrLn ("Selected ChatGPT account: " ++ name) else reject "Unknown account client ID; run agent-one auth accounts"
  ["accounts"] -> withVault $ \_ vault -> forM_ (M.elems (accounts vault)) $ \a -> T.putStrLn $ (if active_account vault==Just (client_id a) then "* " else "  ") <> email a <> " (" <> client_id a <> ")"
  ["status"] -> withVault $ \_ vault -> do a<-selected vault; t<-now; T.putStrLn $ email a <> " (" <> client_id a <> ") " <> (if T.null (refresh_token a) then "signed out" else if expires_at a>t then "signed in" else "refresh required")
  ["models"] -> do
    (token,_) <- chatGPTAccess
    result <- jsonHTTP (resource <> "/models") Nothing [("Authorization","Bearer "<>token)]
    let models=fromMaybe [] $ parseMaybe (withObject "models" (.: "models")) result :: [Value]
    forM_ (filter ((=="list") . textField "visibility") models) $ \m -> T.putStrLn $ textField "slug" m <> "\t" <> textField "display_name" m
  _ -> reject "Usage: agent-one auth login|add|accounts|use CLIENT_ID|status|models|logout"
