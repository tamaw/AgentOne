{-# LANGUAGE OverloadedStrings #-}
module ContextWindow (prepareContext, contextCharacters, recoverHistoryMessage) where
import Data.Aeson
import qualified Data.ByteString.Lazy as B
import qualified Data.Vector as V
import Control.Exception (try, IOException)

import qualified Data.Aeson.KeyMap as K
import qualified Data.Text as T
content :: Value -> T.Text
content (Object o) = case K.lookup "content" o of Just (String s) -> s; _ -> ""
content _ = ""
contextCharacters :: [Value] -> Int
contextCharacters = sum . map (T.length . content)
prepareContext :: [Value] -> [Value]
prepareContext history
  | contextCharacters history <= 400000 = history
  | otherwise = zipWith elide [0 :: Int ..] history
  where
    cutoff = max 0 (length history - 24)
    elide i (Object o)
      | i < cutoff, K.lookup "role" o == Just (String "assistant"),
        Just (String s) <- K.lookup "content" o, T.length s > 512 =
          Object (K.insert "content" (String (T.concat
            ["[Archived generated Haskell module; conversation message index ",
             T.pack (show i), "; ",T.pack (show (T.length s)),
             " characters elided. Original source remains in /workspace/.runs/conversation.json messages at this index and execution history. Read the specific artifact if needed; do not replay completed work.] "])) o)
    elide i (Object o)
      | i < cutoff, K.lookup "role" o == Just (String "user"),
        Just (String s) <- K.lookup "content" o,
        "Execution feedback:\n" `T.isPrefixOf` s, T.length s > 2400 =
          Object (K.insert "content" (String (T.concat
            [T.take 900 s,
             "\n[Stale execution output elided; original conversation message index ",
             T.pack (show i), ". Use recoverHistoryMessage for exact original; full stored history is unchanged.]\n",
             T.takeEnd 900 s])) o)
    elide _ value = value

recoverHistoryMessage :: Int -> IO (Either String Value)
recoverHistoryMessage index
  | index < 0 = pure (Left "History index must be nonnegative")
  | otherwise = do
      loaded <- try $ do
        bytes <- B.readFile "/workspace/.runs/conversation.json"
        pure (eitherDecode bytes :: Either String Value)
      case loaded :: Either IOException (Either String Value) of
        Left _ -> pure (Left "Stored conversation could not be read")
        Right (Left _) -> pure (Left "Stored conversation is not valid JSON")
        Right (Right (Object o)) -> case K.lookup "messages" o of
          Just (Array messages) -> pure $ maybe (Left "History index out of range") Right (messages V.!? index)
          _ -> pure (Left "Stored conversation has no message array")
        Right (Right _) -> pure (Left "Stored conversation is not an object")
