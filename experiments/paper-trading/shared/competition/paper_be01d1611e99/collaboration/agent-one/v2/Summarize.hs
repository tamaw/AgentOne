module Main where
import Data.List
import Text.Printf
split s=case break(==',')s of (a,[])->[a];(a,_:b)->a:split b
num r i=read(r!!i)::Double
main=do
 rs<-map split . tail . lines <$> readFile "results.csv"
 putStrLn "asset split cadence cost strategy | return% BH% excess_pp maxDD% BHDD% trades rejections"
 let wanted r = (r!!1=="2023-2025-continuous" && r!!4 `elem` ["Original","ConsensusV1","PeerCostHysteresisV2","DecisionSizedHold"]) || (r!!0 `elem` ["LTCUSD","XRPUSD"] && any (`isInfixOf` (r!!1)) ["validation","holdout"] && r!!2=="7" && r!!3=="1.0" && r!!4 `elem` ["Original","PeerCostHysteresisV2"])
 mapM_ (\r->printf "%s %s %s %s %s | %.2f %.2f %+.2f %.2f %.2f %s %s\n" (r!!0)(r!!1)(r!!2)(r!!3)(r!!4) (100*num r 7)(100*num r 8)(100*num r 9)(100*num r 10)(100*num r 11)(r!!12)(r!!13)) (filter wanted rs)
 putStrLn "TRANSFER ANNUAL HOLDOUT SUMMARY (LTC/XRP 2023-25, weekly base costs)"
 let held=[r|r<-rs,r!!0 `elem` ["LTCUSD","XRPUSD"],"holdout" `isInfixOf`(r!!1),r!!2=="7",r!!3=="1.0"]
 mapM_ (\mode->let zs=filter(\r->r!!4==mode)held; excess=map(\r->num r 9)zs; original r=head[z|z<-held,z!!0==r!!0,z!!1==r!!1,z!!4=="Original"] in print(mode,"folds",length zs,"BH wins",length(filter(>0)excess),"original wins",length(filter(\r->num r 7>num(original r)7)zs),"mean excess",sum excess/fromIntegral(length excess))) ["Original","ConsensusV1","PeerCostHysteresisV2","DecisionSizedHold"]
