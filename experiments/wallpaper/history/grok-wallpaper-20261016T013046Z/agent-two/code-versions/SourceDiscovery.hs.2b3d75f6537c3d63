module SourceDiscovery (findSource, readSourceLines) where
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Control.Exception (try, IOException)
import Data.List (isInfixOf)
sources :: [FilePath]
sources = ["app/Main.hs","StepLoader.hs","RequestGate.hs","ContextWindow.hs","IncumbentContext.hs","RemedyMemory.hs","SourceDiscovery.hs"]
load :: FilePath -> IO (Either String [T.Text])
load p | p `notElem` sources = pure (Left "Source not in runtime allowlist")
       | otherwise = do
           r <- try (T.readFile p) :: IO (Either IOException T.Text)
           pure $ either (const (Left "Source unavailable")) (Right . T.lines) r
render :: Int -> [(Int,T.Text)] -> String
render budget rows = go (max 0 (min 1800 budget)) rows
 where
  go _ [] = ""
  go n ((i,s):xs) = let row=show i ++ ": " ++ T.unpack s ++ "\n" in
    if length row <= n then row ++ go (n-length row) xs else ""
readSourceLines :: FilePath -> Int -> Int -> Int -> IO (Either String String)
readSourceLines p start count budget
 | start < 1 || count < 1 || count > 40 = pure (Left "Require start >= 1 and count in 1..40")
 | otherwise = fmap (fmap (render budget . take count . drop (start-1) . zip [1..])) (load p)
findSource :: String -> Int -> IO String
findSource query budget
 | null query || length query > 200 = pure "Invalid query"
 | otherwise = do
   rows <- mapM scan sources
   pure (take (max 0 (min 1800 budget)) (concat rows))
 where
  scan p = do
   r <- load p
   pure $ either (const "") (concatMap (\(i,s) -> p ++ ":" ++ show i ++ ": " ++ take 160 (T.unpack s) ++ "\n") . take 12 . filter (isInfixOf query . T.unpack . snd) . zip [1::Int ..]) r
