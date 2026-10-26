{-# LANGUAGE OverloadedStrings #-}
module RemedyMemory (RemedyRecord(..), readRemedyRecords, selectRemedies, selectFromRecords) where
import Data.Aeson
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString as B
import qualified Data.Text as T
import Data.Char (isAlphaNum,toLower)
import Data.List (sortOn,nub)
import Control.Exception (try,IOException)
data RemedyRecord = RemedyRecord { recordId :: String, tags :: [String], scope :: String, observation :: String, remedy :: String, evidence :: [String], recheck :: String } deriving (Eq,Show)
instance FromJSON RemedyRecord where
 parseJSON = withObject "RemedyRecord" $ \o -> RemedyRecord <$> o .: "id" <*> o .: "tags" <*> o .: "scope" <*> o .: "observation" <*> o .: "remedy" <*> o .: "evidence" <*> o .: "recheck"
readRemedyRecords :: FilePath -> IO (Either String [RemedyRecord])
readRemedyRecords path = do
 raw <- try (B.readFile path) :: IO (Either IOException B.ByteString)
 pure $ case raw of
  Left _ -> Left "Remedy store unreadable"
  Right bytes | B.length bytes > 65536 -> Left "Remedy store exceeds 64KiB"
  Right bytes -> case eitherDecodeStrict' bytes of Left _ -> Left "Invalid remedy JSON"; Right value -> parseStore value
 where
  parseStore (Object o) = case (K.lookup "version" o,K.lookup "records" o) of
   (Just (Number 1),Just rs) -> case fromJSON rs of
    Error _ -> Left "Invalid remedy records"
    Success records | length records > 12 -> Left "Too many remedy records"
                    | any invalid records -> Left "Invalid or oversized remedy record"
                    | length (nub (map recordId records)) /= length records -> Left "Duplicate remedy IDs"
                    | otherwise -> Right records
   _ -> Left "Unsupported remedy store"
  parseStore _ = Left "Invalid remedy store"
  invalid r = null (recordId r) || null (tags r) || null (evidence r) || any null [scope r,observation r,remedy r,recheck r] || length (render r) > 1600
textOf :: Value -> String
textOf (Object o) = case K.lookup "content" o of Just (String t) -> T.unpack t; _ -> ""
textOf _ = ""
user :: Value -> Bool
user (Object o) = K.lookup "role" o == Just (String "user")
user _ = False
tokens :: String -> [String]
tokens = nub . words . map (\c -> if isAlphaNum c then toLower c else ' ')
feedback :: String -> Bool
feedback s = "Execution feedback:" `T.isPrefixOf` T.pack s
render :: RemedyRecord -> String
render r = "HISTORICAL REMEDY " ++ recordId r ++ " (advisory; recheck applicability)\nScope: " ++ scope r ++ "\nObserved: " ++ observation r ++ "\nRemedy: " ++ remedy r ++ "\nEvidence: " ++ unwords (evidence r) ++ "\nRecheck: " ++ recheck r
selectFromRecords :: Int -> [RemedyRecord] -> [Value] -> [Value]
selectFromRecords budget records context = pack (max 0 budget) ranked
 where
  us = map textOf (filter user context)
  latest p = take 1 (filter p (reverse us))
  query = tokens (unwords (latest (not . feedback) ++ latest feedback))
  score r = length (filter (`elem` query) (nub (concatMap tokens (tags r))))
  ranked = take 3 $ sortOn (\r -> (negate (score r),recordId r)) (filter ((>=2) . score) records)
  pack _ [] = []
  pack n (r:rs) | length (render r) <= n = object ["role" .= ("user" :: String),"content" .= render r] : pack (n-length (render r)) rs
                | otherwise = pack n rs
selectRemedies :: Int -> [Value] -> IO [Value]
selectRemedies budget context = do
 records <- readRemedyRecords "/workspace/remedy-memory.json"
 pure $ either (const []) (\rs -> selectFromRecords budget rs context) records
