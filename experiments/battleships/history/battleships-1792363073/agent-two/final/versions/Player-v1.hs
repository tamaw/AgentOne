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
     opts n=filter (\p->p .&. bad==0) (placements n)
     score = case rems of
      [4,3,2] -> eval3 (opts 4) (opts 3) (opts 2) hitM tried
      [4,3] -> eval2 (opts 4) (opts 3) hitM tried
      [4,2] -> eval2 (opts 4) (opts 2) hitM tried
      [3,2] -> eval2 (opts 3) (opts 2) hitM tried
      [4] -> eval1 (opts 4) hitM tried
      [3] -> eval1 (opts 3) hitM tried
      [2] -> eval1 (opts 2) hitM tried
      _ -> replicate 64 0
     avail=[i|i<-[0..63],not(testBit tried i)]
     mx=maximum (map (score!!) avail)
 in head [i|i<-avail,score!!i==mx]
add m a = foldl' (\v i->take i v++[v!!i+1]++drop(i+1)v) a (bits m)
eval1 ps h t=foldl' (\a p->if (p .&. h)==h then add (p .&. complement t) a else a) (replicate 64 0) ps
eval2 as bs h t=foldl' f (replicate 64 0) [(a,b)|a<-as,b<-bs,a .&. b==0] where f z (a,b)=let u=a.|.b in if u .&.h==h then add (u .&.complement t) z else z
eval3 as bs cs h t=foldl' f (replicate 64 0) [(a,b,c)|a<-as,b<-bs,c<-cs,a .&.b==0,a .&.c==0,b .&.c==0] where f z (a,b,c)=let u=a.|.b.|.c in if u .&.h==h then add (u .&.complement t) z else z
main=do hSetBuffering stdout NoBuffering; mapM_ run . lines =<< getContents where
 run l=case eitherDecode (BL.pack l) of
  Right q | phase q=="place" -> BL.putStrLn (encode (object ["ships" .= place (seed q) (roundN q)]))
          | phase q=="shoot" -> BL.putStrLn (encode (object ["shot" .= bestShot q]))
  _ -> BL.putStrLn (encode (object ["shot" .= (0::Int)]))
