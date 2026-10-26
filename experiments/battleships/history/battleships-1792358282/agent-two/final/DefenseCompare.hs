{-# LANGUAGE BangPatterns #-}
module Main where
import Fleet
import qualified FleetOld as O
import Data.List
import System.CPUTime
import Control.Exception
simulate :: (Int -> Int -> [[Int]]) -> (Int -> [Shot] -> Int) -> Int -> Int
simulate layout policy seed=go [] where
 ships=layout seed 17
 allCells=concat ships
 go ss | all (`elem` map (\(c,_,_)->c) ss) allCells = length ss
       | otherwise = let c=policy seed ss; fired=c:map (\(x,_,_)->x) ss; target=find (elem c) ships; (r,sk)=case target of Nothing -> ("miss",[]); Just cs -> if all (`elem` fired) cs then ("sunk",cs) else ("hit",[]) in if c `elem` tail fired then error "repeated shot" else go (ss++[(c,r,sk)])
baseline seed ss = head [c | c<-sortOn (\x->mix (fromIntegral seed+fromIntegral x*123456789)) [0..63],c `notElem` [a|(a,_,_)<-ss]]
main=do
 t0<-getCPUTime
 let seeds=[92001..92048]; baseline=map (simulate O.fleet (\s->O.choose s 1)) seeds; candidates=[map (simulate (edgeFleet n) (\s->O.choose s 1)) seeds | n<-[4,16,64]]
 evaluate (sum baseline+sum (map sum candidates))
 t1<-getCPUTime
 print (baseline,candidates,fromIntegral(t1-t0)/1e12::Double)
