module Main where
import Data.List
import Text.Printf
split s=case break(==',') s of (a,[])->[a]; (a,_:b)->a:split b
main=do
 rs<-map split . tail . lines <$> readFile "results.csv"
 putStrLn "asset split cadence cost strategy | return% BH% excess_pp maxDD% BHDD% trades rejections"
 mapM_ (\r->printf "%s %s %s %s %s | %.2f %.2f %+.2f %.2f %.2f %s %s\n" (r!!0)(r!!1)(r!!2)(r!!3)(r!!4) (100*read(r!!7)::Double) (100*read(r!!8)::Double) (100*read(r!!9)::Double) (100*read(r!!10)::Double) (100*read(r!!11)::Double) (r!!12)(r!!13)) [r|r<-rs,r!!4 `elem` ["Original","ReserveOnly","ConsensusV1","PeerReconstructed"],(r!!2=="7" && r!!3=="1.0" && ("validation" `isInfixOf` (r!!1) || "holdout" `isInfixOf` (r!!1))) || "2023-2025-continuous"==r!!1]
 putStrLn "AGGREGATE annual fold win counts (all BTC+ETH 2023-25 holdouts; weekly base costs)"
 let held=[r|r<-rs,"holdout" `isInfixOf`(r!!1),r!!2=="7",r!!3=="1.0"]
 mapM_ (\mode->let zs=filter(\r->r!!4==mode)held; excess=map(\r->read(r!!9)::Double)zs in print(mode,"folds",length zs,"BH excess wins",length(filter(>0)excess),"mean excess",sum excess/fromIntegral(length excess))) ["Original","ReserveOnly","ConsensusV1","PeerReconstructed"]
