{-# LANGUAGE OverloadedStrings #-}
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson
import qualified Data.HashMap.Strict as HM
import Data.Bits
import Data.List
import Data.Ord
import Data.Word
import System.IO

data Req = Req { phase :: String, seed :: Int, roundN :: Int, shots :: [(Int,String,[Int])] }
instance FromJSON Req where
 parseJSON = withObject "Req" $ \o -> do
  p <- o .: "phase"; s <- o .: "seed"; r <- o .: "round"
  xs <- o .:? "shots" .!= []
  q <- mapM (withObject "shot" $ \x -> (,,) <$> x .: "cell" <*> x .: "result" <*> x .:? "sunk" .!= []) xs
  pure (Req p s r q)

placements :: Int -> [Word64]
placements n = [foldl' setBit 0 [r*8+c+i | i<-[0..n-1]] | r<-[0..7],c<-[0..8-n]] ++
               [foldl' setBit 0 [(r+i)*8+c | i<-[0..n-1]] | r<-[0..8-n],c<-[0..7]]

rng :: Int -> [Int]
rng x = let y = (1103515245*x+12345) `mod` 2147483647 in y : rng y
place :: Int -> Int -> [[Int]]
place sd rd = go (rng (sd `xor` (rd*7919))) [4,3,2] 0 where
 go _ [] _ = []
 go (x:xs) (n:ns) used = let ps=filter (\m->m .&. used==0) (placements n); m=ps!!(x `mod` length ps)
                          in bits m : go xs ns (used .|. m)
 go _ _ _=[]
bits :: Word64 -> [Int]
bits m=[i|i<-[0..63],testBit m i]
mask :: [Int] -> Word64
mask=foldl' setBit 0

bestShot :: Req -> Int
bestShot q =
 let ss=shots q
     tried=mask [c|(c,_,_)<-ss]
     sunkCells=concat [z|(_,_,z)<-ss]
     sunkM=mask sunkCells
     sunkLens=map length $ filter (not.null) [z|(_,_,z)<-ss]
     rems=foldl' (flip delete) [4,3,2] sunkLens
     hitM=mask [c|(c,res,z)<-ss,res=="hit",null z]
     bad=mask [c|(c,res,_ )<-ss,res=="miss"] .|. sunkM
     ps=concatMap placements rems
     ok p=p .&. bad==0 && (hitM==0 || p .&. hitM/=0)
     score=foldl' (\a p->if ok p then add (p .&. complement tried) a else a) (replicate 64 0) ps
     avail=[i|i<-[0..63],not(testBit tried i)]
     mx=maximum (map (score!!) avail)
 in head [i|i<-avail,score!!i==mx]

main=do hSetBuffering stdout NoBuffering; mapM_ run . lines =<< getContents where
 run l=case eitherDecode (BL.pack l) of
  Right q | phase q=="place" -> BL.putStrLn (encode (object ["ships" .= place (seed q) (roundN q)]))
          | phase q=="shoot" -> BL.putStrLn (encode (object ["shot" .= bestShot q]))
  _ -> BL.putStrLn (encode (object ["shot" .= (0::Int)]))
