{-# LANGUAGE OverloadedStrings #-}
module LifecycleContext (loadLifecycle, applyLifecycle) where
import Data.Aeson
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString as B
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Control.Exception (try,IOException)
import Data.List (mapAccumL)
data Entry = Entry Int T.Text [T.Text] Int deriving Show
instance FromJSON Entry where
 parseJSON = withObject "lifecycle entry" $ \o -> Entry <$> o .: "index" <*> o .: "original" <*> o .: "retained" <*> o .: "completionWitness"
loadLifecycle :: FilePath -> IO (Either String [Entry])
loadLifecycle path = do
 r <- try (B.readFile path) :: IO (Either IOException B.ByteString)
 pure $ case r of
  Left _ -> Left "lifecycle file unreadable"
  Right b -> case eitherDecodeStrict' b of
   Left _ -> Left "lifecycle JSON invalid"
   Right (Object o) -> case K.lookup "entries" o of
    Just v -> case fromJSON v of
     Success es -> Right es
     Error _ -> Left "lifecycle entries invalid"
    Nothing -> Left "lifecycle entries absent"
   Right _ -> Left "lifecycle object absent"
isUser :: Value -> Bool
isUser (Object o) = K.lookup "role" o == Just (String "user")
isUser _ = False
text :: Value -> T.Text
text (Object o) = case K.lookup "content" o of Just (String s) -> s; _ -> ""
text _ = ""
applyLifecycle :: [Entry] -> [Value] -> [Value]
applyLifecycle es h = concat $ reverse outputs
 where
  indexed = M.fromList (zip [0::Int ..] h)
  valid (Entry i original _ witness) = i >= 0 && i < length h - 24 && witness > i && maybe False (\v -> isUser v && text v == original) (M.lookup i indexed) && maybe False (T.isInfixOf "The step is waiting for new user input." . text) (M.lookup witness indexed)
  table = M.fromList [(i,e) | e@(Entry i _ _ _) <- es, valid e]
  (_,outputs) = mapAccumL rewrite S.empty (reverse (zip [0::Int ..] h))
  rewrite seen (i,v) = case M.lookup i table of
   Nothing -> (seen,[v])
   Just (Entry _ _ clauses _) ->
    let unique = filter (`S.notMember` seen) clauses
        seen' = foldr S.insert seen clauses
        archived = object ["role" .= String "assistant", "content" .= T.pack ("[Completed reviewed paper request; original index " ++ show i ++ "; exact recovery: ContextWindow.recoverHistoryMessage " ++ show i ++ ". Task directives retired only; uncertain constraints preserved verbatim.]")]
    in (seen',[object ["role" .= String "user", "content" .= (T.unlines unique <> text archived)]])
