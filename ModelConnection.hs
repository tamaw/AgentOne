{-# LANGUAGE OverloadedStrings #-}
module ModelConnection (askModel) where

import Control.Exception
import Control.Monad
import Data.Aeson
import Data.Aeson.Types (Parser, parseEither, parseMaybe)
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString.Lazy as B
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as T
import Data.Time.Clock.POSIX
import System.Directory
import System.Environment
import System.Exit
import System.IO.Error
import System.Process

askModel :: String -> String -> String -> FilePath -> T.Text -> [Value] -> IO (T.Text, Value)
askModel endpoint key model file instructions history = do
  when (null key) $ ioError $ userError "LLM_API_KEY is empty"
  started <- getPOSIXTime
  effort <- maybe "high" id <$> lookupEnv "LLM_REASONING_EFFORT"
  requestTimeout <- maybe "900" id <$> lookupEnv "LLM_TIMEOUT_SECONDS"
  createDirectoryIfMissing True ".runs"
  let sessionPath = ".runs/model-session-id"
  exists <- doesFileExist sessionPath
  unless exists $ do
    host <- maybe "agent" id <$> lookupEnv "HOSTNAME"
    writeFile sessionPath (host ++ "-" ++ show (floor (started * 1000000) :: Integer))
  session <- T.strip <$> T.readFile sessionPath
  let base = T.dropWhileEnd (== '/') (T.pack endpoint)
      root = if "/api/projects/" `T.isInfixOf` base then fst (T.breakOn "/api/projects/" base) else base
      url | "/responses" `T.isSuffixOf` root = root
          | "/v1" `T.isSuffixOf` root = root <> "/responses"
          | otherwise = root <> "/openai/v1/responses"
      payload = object ["model" .= model, "instructions" .= instructions, "input" .= concatMap (wire model) history, "store" .= False,
          "include" .= ["reasoning.encrypted_content" :: T.Text], "reasoning" .= object ["effort" .= effort], "prompt_cache_key" .= session]
      redact = T.replace (T.pack key) "[redacted]"
      emit = T.putStrLn . redact . T.decodeUtf8 . B.toStrict . encode
      elapsed = (round :: POSIXTime -> Integer) . (* 1000) . subtract started <$> getPOSIXTime
      header s = "header = " ++ show s
      config = unlines ["url = " ++ show (T.unpack url), header ("api-key: " ++ key),
        header "Content-Type: application/json", header "User-Agent: AgentOne-Haskell/1.0",
        "data-binary = " ++ show ('@' : file)]
  B.writeFile file (encode payload)
  emit $ object ["event" .= ("llm.request" :: T.Text), "time" .= started, "model" .= model,
    "endpoint" .= url, "session" .= session, "messages" .= length history,
    "latest_message" .= (if null history then Null else last history), "request_file" .= file]
  outcome <- tryJust synchronous $ do
    (code, output, err) <- readProcessWithExitCode "curl"
      ["--silent", "--show-error", "--fail-with-body", "--max-time", requestTimeout, "--config", "-"] config
    unless (code == ExitSuccess) $ ioError $ userError $ take 2000 (err ++ output)
    value <- either (ioError . userError) pure (eitherDecodeStrict' (T.encodeUtf8 (T.pack output)))
    B.writeFile (file ++ ".response.json") (encode value)
    source <- either (ioError . userError) pure (parseEither parseResponse value)
    let source' = stripFence source
    when (T.null source') $ ioError $ userError "Model returned no Haskell source"
    duration <- elapsed
    let field name = parseMaybe (withObject "response" (.: name)) value :: Maybe Value
        output = maybe [] id (parseMaybe (withObject "response" (.: "output")) value :: Maybe [Value])
        reasoningItems = length [() | Object o <- output, K.lookup "type" o == Just (String "reasoning")]
    emit $ object ["event" .= ("llm.response" :: T.Text), "duration_ms" .= duration,
      "id" .= field "id", "status" .= field "status", "usage" .= field "usage", "reasoning_items" .= reasoningItems]
    T.putStrLn ("[llm code]\n" <> redact source' <> "\n[llm code end]")
    let assistant = object ["role" .= ("assistant" :: T.Text), "content" .= source',
          "provider_model" .= model, "provider_source" .= source', "provider_output" .= output]
    pure (source', assistant)
  case outcome of
    Right source -> pure source
    Left err -> do
      duration <- elapsed
      let problem = redact (T.pack (displayException err))
      emit $ object ["event" .= ("llm.error" :: T.Text), "duration_ms" .= duration, "error" .= problem]
      ioError $ userError $ T.unpack problem
  where
    clean (Object o) = Object $ K.filterWithKey (\k _ -> k `elem` ["role", "content"]) o
    clean v = v
    wire name v@(Object o)
      | K.lookup "provider_model" o == Just (String (T.pack name)),
        K.lookup "provider_source" o == K.lookup "content" o,
        Just (Array outputs) <- K.lookup "provider_output" o = foldr (:) [] outputs
      | otherwise = [clean v]
    wire _ v = [clean v]
    synchronous e = case fromException e :: Maybe SomeAsyncException of Just _ -> Nothing; Nothing -> Just e
    stripFence raw = let s = T.strip raw; ls = T.lines s in
      if length ls >= 2 && "```" `T.isPrefixOf` head ls && T.strip (last ls) == "```"
      then T.strip (T.unlines (init (tail ls))) else s
    parseResponse = withObject "response" $ \o -> do
      status <- o .:? "status" .!= ("completed" :: T.Text)
      when (status /= "completed") $ fail $ T.unpack status
      items <- o .: "output" :: Parser [Value]
      chunks <- forM items $ withObject "output" $ \item -> do
        kind <- item .: "type" :: Parser T.Text
        if kind /= "message" then pure [] else do
          parts <- item .: "content"
          forM parts $ withObject "content" $ \part -> do
            kind' <- part .: "type" :: Parser T.Text
            if kind' == "output_text" then part .: "text" else pure ""
      pure $ T.strip $ T.concat $ concat chunks
