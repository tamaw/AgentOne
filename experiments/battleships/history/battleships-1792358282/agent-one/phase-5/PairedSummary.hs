{-# LANGUAGE OverloadedStrings #-}
module Main where
import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as B
import Data.List
import Text.Read
import System.Environment
import Control.Monad
summary :: FilePath -> IO Value
summary path=do
 txt<-readFile path
 rows<-mapM (\s->maybe (fail ("invalid measurement row in "++path)) pure (readMaybe s :: Maybe (Int,Int,Int))) (filter (not.null) (lines txt))
 let n=length rows; ids=[i|(i,_,_)<-rows]
 unless (n>=2 && length(nub ids)==n && all (\(_,a,b)->a>=9 && a<=64 && b>=9 && b<=64) rows) (fail "invalid paired measurements")
 let ds=[fromIntegral(b-a)::Double|(_,a,b)<-rows]; nf=fromIntegral n; mean xs=sum xs/nf; d=mean ds
 let se=sqrt (sum [(x-d)^2|x<-ds]/(nf*(nf-1)))
 pure $ object ["file" .= path,"boards" .= n,"incumbent_mean" .= mean [fromIntegral a|(_,a,_)<-rows],"candidate_mean" .= mean [fromIntegral b|(_,_,b)<-rows],"paired_delta_candidate_minus_incumbent" .= d,"paired_standard_error" .= se,"approximate_95pct_interval" .= [d-1.96*se,d+1.96*se],"candidate_wins" .= length(filter (<0) ds),"ties" .= length(filter (==0) ds),"candidate_losses" .= length(filter (>0) ds),"caveat" .= ("Normal approximation on reused local boards; descriptive, not proof of generalization or match strength."::String)]
load :: FilePath -> IO Value
load p=B.readFile p >>= either fail pure . eitherDecode
main=do
 args<-getArgs
 reports<-mapM summary args
 B.writeFile "paired-summary.json" (encode reports)
 host<-load "selection.json"
 prior<-load "evidence-before-prize.json"
 local<-load "comparison-game2.json"
 rejected<-load "comparison-game3.json"
 let final=object ["phase" .= ("post-match capability preservation"::String),"match" .= object ["result" .= ("won 3 to 1, reported by referee"::String),"interpretation" .= ("Small series; outcome combines policy, placement, board difficulty and luck. It does not establish causal improvement."::String)],"host_latest_selection" .= host,"host_interpretation" .= ("Latest saved selection compares identical 48-board score arrays at mean 26.333333333333332. Acceptance on equality demonstrates no improvement in that submission, not evidence of stronger play."::String),"local_ship_length_weighting_measurement" .= local,"local_stronger_targeting_measurement" .= rejected,"paired_analysis" .= reports,"retained_policy" .= ("Game-2 actual-length inverse weighting; game-3 stronger targeting reverted on local regression. Player executable unchanged in prize phase."::String),"reusable_improvement" .= object ["source" .= ("PairedSummary.hs"::String),"executable" .= ("paired-summary"::String),"capability" .= ("Reusable arbitrary paired-log analysis: validates integer rows, unique board IDs and legal shot counts; computes paired mean difference, standard error, approximate interval and win/tie/loss counts. Takes log paths as arguments and saves paired-summary.json."::String),"observed_execution" .= ("Ran on actual game-2 and game-3 48-board comparison logs; results embedded above."::String)],"prior_evidence" .= prior,"limitations" .= ("Local boards reused for tuning, not an independent holdout. Confidence intervals are descriptive only. No new matches, hidden-fleet reads, or claims of harness self-improvement."::String)]
 B.writeFile "evidence.json" (encode final)
 mapM_ (B.putStrLn . encode) reports
