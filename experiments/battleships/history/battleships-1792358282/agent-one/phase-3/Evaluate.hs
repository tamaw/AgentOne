module Evaluate where
import qualified Main as P
import Data.List
import System.IO
import Data.Time.Clock
import Control.Exception
play :: Bool -> [[Int]] -> Int
play improved fleet=go [] where
 go ss | length [()|P.Shot _ _ cs<-ss,not(null cs)]==3=length ss
 go ss | length ss>=64=64
 go ss=let c=P.choose improved ss; tried=c:[x|P.Shot x _ _<-ss]; ship=find (elem c) fleet; (res,cs)=case ship of Nothing->("miss",[]); Just xs->if all (`elem` tried) xs then ("sunk",xs) else ("hit",[]) in if c `elem` [x|P.Shot x _ _<-ss] then error "duplicate shot" else go (ss++[P.Shot c res cs])
main=do
 hSetBuffering stdout LineBuffering
 t<-getCurrentTime
 rs<-mapM (\i->do
   let fleet=P.place (i*7919+104729) (i+1)
   a<-evaluate (play False fleet)
   b<-evaluate (play True fleet)
   print (i,a,b)
   pure (a,b)) [0..47]
 end<-getCurrentTime
 let avg xs=fromIntegral (sum xs)/fromIntegral (length xs)::Double
 writeFile "measurements.json" ("{\"boards\":48,\"baseline_mean_shots\":"++show(avg(map fst rs))++",\"candidate_mean_shots\":"++show(avg(map snd rs))++",\"elapsed_seconds\":"++show(realToFrac(diffUTCTime end t)::Double)++",\"source\":\"local deterministic generated fleets, not host hidden benchmark\"}\n")
