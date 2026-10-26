module Compare where
import qualified Main as P
import qualified Incumbent as I
import Data.List
import System.IO
import Data.Time.Clock
import Control.Exception
import System.Directory
play :: ([P.Shot] -> Int) -> [[Int]] -> Int
play choose fleet=go [] where
 go ss | length [()|P.Shot _ _ cs<-ss,not(null cs)]==3=length ss
 go ss | length ss>=64=error "did not finish"
 go ss=let c=choose ss; tried=c:[x|P.Shot x _ _<-ss]; ship=find (elem c) fleet; (res,cs)=case ship of Nothing->("miss",[]); Just xs->if all (`elem` tried) xs then ("sunk",xs) else ("hit",[]) in if c<0 || c>63 || c `elem` [x|P.Shot x _ _<-ss] then error "invalid shot" else go (ss++[P.Shot c res cs])
main=do
 hSetBuffering stdout LineBuffering
 t<-getCurrentTime
 rs<-mapM (\i->do
   let fleet=P.place (i*7919+104729) (i+1)
   a<-evaluate (play (I.choose True . map (\(P.Shot c r cs)->I.Shot c r cs)) fleet)
   b<-evaluate (play (P.choose True) fleet)
   print (i,a,b)
   pure (a,b)) [0..47]
 end<-getCurrentTime
 let avg xs=fromIntegral (sum xs)/fromIntegral (length xs)::Double
 let a=avg(map fst rs); b=avg(map snd rs); keep=b<=a
 writeFile "comparison-game2.json" ("{\"boards\":48,\"incumbent_mean\":"++show a++",\"candidate_mean\":"++show b++",\"candidate_retained\":"++(if keep then "true" else "false")++",\"seconds\":"++show(realToFrac(diffUTCTime end t)::Double)++",\"source\":\"same local generated fleets, not host hidden benchmark\"}\n")
 unlessKeep keep
unlessKeep True=pure ()
unlessKeep False=do copyFile "Player-before-game2.hs" "Player.hs"; copyFile "player-before-game2" "player"
