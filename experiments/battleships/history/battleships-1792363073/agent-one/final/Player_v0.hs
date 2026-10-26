{-# LANGUAGE OverloadedStrings #-}
module Main where
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as B
import Data.List
import Data.Bits
import System.IO
data S = S { scell :: Int, sresult :: String, ssunk :: [Int] }
data R = R { rphase :: String, rseed :: Int, rround :: Int, rshots :: [S] }
instance FromJSON S where
  parseJSON = withObject "S" $ \o -> S <$> o .: "cell" <*> o .: "result" <*> o .:? "sunk" .!= []
instance FromJSON R where
  parseJSON = withObject "R" $ \o -> R <$> o .: "phase" <*> o .: "seed" <*> o .: "round" <*> o .:? "shots" .!= []
next :: Int -> Int
next x = x * 1664525 + 1013904223
placements :: Int -> [[Int]]
placements n = [[r*8+c+i | i <- [0..n-1]] | r <- [0..7], c <- [0..8-n]] ++ [[(r+i)*8+c | i <- [0..n-1]] | c <- [0..7], r <- [0..8-n]]
shipsFor :: Int -> [[Int]]
shipsFor seed = go (seed `xor` 0x6d2b79f5) 0 [4,3,2] where
  go _ _ [] = []
  go x used (n:ns) = let y=next x; ps=placements n; p=ps !! (abs y `mod` length ps); m=foldl' setBit 0 p in if m .&. used == 0 then p:go y (used .|.m) ns else go y used (n:ns)
order :: Int -> [Int]
order seed = sortBy (\a b -> compare (key a) (key b)) [0..63] where key i = next (seed + i*1103515245)
choose :: R -> Int
choose r = head [x | x <- order (rseed r `xor` rround r), x `notElem` map scell (rshots r)]
run :: B.ByteString -> IO ()
run l = case eitherDecode l of
  Right r | rphase r == "place" -> B.putStrLn (encode (object ["ships" .= shipsFor (rseed r `xor` rround r)]))
  Right r | rphase r == "shoot" -> B.putStrLn (encode (object ["shot" .= choose r]))
  _ -> B.putStrLn (encode (object []))
main :: IO ()
main = hSetBuffering stdout NoBuffering >> B.getContents >>= mapM_ run . B.lines
