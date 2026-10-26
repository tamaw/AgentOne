{-# LANGUAGE BangPatterns #-}
module Main where
import Fleet
import Data.List
import System.CPUTime
import Control.Exception
simulate :: (Int -> [Shot] -> Int) -> Int -> Int
simulate policy seed=go [] where
 ships=fleet seed 17
 allCells=concat ships
 go ss | all (`elem` map (\(c,_,_)->c) ss) allCells = length ss
       | otherwise = let c=policy seed ss; fired=c:map (\(x,_,_)->x) ss; target=find (elem c) ships; (r,sk)=case target of Nothing -> ("miss",[]); Just cs -> if all (`elem` fired) cs then ("sunk",cs) else ("hit",[]) in if c `elem` tail fired then error "repeated shot" else go (ss++[(c,r,sk)])
baseline seed ss = head [c | c<-sortOn (\x->mix (fromIntegral seed+fromIntegral x*123456789)) [0..63],c `notElem` [a|(a,_,_)<-ss]]
main=do
 t0<-getCPUTime
 let seeds=[91001..91008]; bs=map (simulate baseline) seeds; cs=map (simulate (\s->choose s 1)) seeds
 evaluate (sum bs+sum cs)
 t1<-getCPUTime
 let mean xs=fromIntegral(sum xs)/fromIntegral(length xs)::Double
 putStrLn $ "{\"strategy\":\"Exact uniform posterior over all legal remaining nonoverlapping fleets, constrained by misses, unresolved hits and sunk ships; shoot maximum posterior occupancy. Seeded legal placement.\",\"reusable_tool\":\"Fleet.hs exact bitmask posterior and Evaluate.hs deterministic full-game simulator\",\"hypothesis\":\"Fleet-consistent posterior occupancy clears boards faster than seeded random untried-cell baseline\",\"measurement_scope\":\"8 locally generated deterministic fleets, not host hidden training fleets; CPU seconds cover both policies\",\"seeds\":"++show seeds++",\"baseline_shots\":"++show bs++",\"candidate_shots\":"++show cs++",\"baseline_mean\":"++show(mean bs)++",\"candidate_mean\":"++show(mean cs)++",\"cpu_seconds\":"++show(fromIntegral(t1-t0)/1e12::Double)++",\"protocol_checks\":\"persistent process: placement, empty history, miss and sunk history requests; measured separately in protocol-check.txt\",\"version\":\"versions/initial\"}"
