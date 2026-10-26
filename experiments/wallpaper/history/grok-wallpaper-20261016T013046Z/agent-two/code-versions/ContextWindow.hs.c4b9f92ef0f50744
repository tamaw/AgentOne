{-# LANGUAGE OverloadedStrings #-}
module ContextWindow (prepareContext, prepareContextWith, latestUserIntent, contextCharacters, recoverHistoryMessage) where
import Data.Aeson
import qualified Data.ByteString.Lazy as B
import qualified Data.Vector as V
import Control.Exception (try, IOException)
import qualified Data.Aeson.KeyMap as K
import qualified Data.Text as T
import Data.List (mapAccumL)
import qualified IncumbentContext
content :: Value -> T.Text
content (Object o) = case K.lookup "content" o of Just (String s) -> s; _ -> ""
content _ = ""
role (Object o) = K.lookup "role" o
role _ = Nothing
feedback v = "Execution feedback:\n" `T.isPrefixOf` content v
protected v = role v `elem` [Just (String "system"),Just (String "developer")] || (role v == Just (String "user") && not (feedback v))
metadata v = any (`T.isPrefixOf` content v) ["User paused or superseded work", "The step is waiting", "Worker timed out", "Conversation restored after supervisor restart", "Request or post-execution reporting failed", "[failure paused this request"]
latestUserIntent :: [Value] -> String
latestUserIntent h = case filter (\v -> role v == Just (String "user") && not (feedback v) && not (metadata v)) (reverse h) of v:_ -> T.unpack (content v); _ -> ""
contextCharacters :: [Value] -> Int
contextCharacters = sum . map costMessage
costMessage v@(Object o) = T.length (content v) + maybe 0 (fromIntegral . B.length . encode) (K.lookup "provider_output" o)
costMessage v = T.length (content v)
msg s = object ["role" .= String "user", "content" .= String s]
replace (Object o) s = Object (K.insert "content" (String s) o)
replace _ s = msg s
reference i = T.pack ("[History index " ++ show i ++ "; exact source/output: recoverHistoryMessage " ++ show i ++ " in ContextWindow; /workspace/.runs/conversation.json. Historical observation, not verified live state.]\n")
important l = any (`T.isInfixOf` T.toLower l) ["failed","error","refused","timed out","verified","audit","unresolved","exitfailure","exit success","exitsuccess","saved",".hs",".png","bind"]
packet i v@(Object o) | K.member "provider_output" o = v
packet i v = replace v (reference i <> body)
 where
  s = content v
  facts = T.unlines (take 16 (filter important (T.lines s)))
  body | T.length s <= 2400 = s
       | feedback v = T.take 600 s <> "\n[Selected observed lines; omitted text recoverable]\n" <> T.take 2400 facts <> "\n[Output tail]\n" <> T.takeEnd 900 s
       | otherwise = T.take 900 s <> "\n[Source fragment; recover complete module before reuse]\n" <> T.takeEnd 500 s
prepareContext :: [Value] -> [Value]
prepareContext h = prepareContextWith 64000 h []
prepareContextWith :: Int -> [Value] -> [Value] -> [Value]
prepareContextWith budget h remedies
 | overflow = overflowNotice : overflowRemedies ++ IncumbentContext.prepareContext h
 | otherwise = notice : supplement ++ chosen
 where
  floorSize = contextCharacters (filter protected h)
  overflow = floorSize + T.length (content notice) > max 0 budget
  overflowNotice = msg "[PROTECTED_FLOOR_OVERFLOW: requested character bound impossible without dropping user instructions. Incumbent context retained with bounded historical remedy supplement; actual size intentionally exceeds target. Full history unchanged.]"
  (_,overflowRemedies) = fit 1600 remedies
  notice = msg (T.pack ("[Bounded working context: original history preserved; " ++ show (length h) ++ " messages. All user intent/system/developer messages retained verbatim. Indexed fragments are historical evidence, not current truth. Exact recovery via ContextWindow.recoverHistoryMessage.]") )
  available = max 0 (budget - floorSize - T.length (content notice))
  (_,supplement) = fit (min 1600 available) remedies
  remaining = max 0 (available - contextCharacters supplement)
  (_,revChosen) = mapAccumL choose remaining (reverse (zip [0::Int ..] h))
  chosen = concat (reverse revChosen)
  choose n (i,v) | protected v = (n,[v])
                 | overflow = (n,[])
                 | otherwise = let p=packet i v; cost=costMessage p in if cost <= n then (n-cost,[p]) else (n,[])
  fit n [] = (n,[])
  fit n (v:vs) = let cost=T.length(content v); (r,rest)=fit (if cost<=n then n-cost else n) vs in (r, if cost<=n then v:rest else rest)

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
