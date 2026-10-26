module Main where
import qualified Revision as R
import System.Environment
import Text.Printf
import Data.List
import Control.Monad
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
json s = '"' : concatMap esc s ++ "\"" where
 esc '"' = "\\\""
 esc '\\' = "\\\\"
 esc '\n' = "\\n"
 esc '\r' = "\\r"
 esc '\t' = "\\t"
 esc c = [c]
main = do
 [bars,out,manifest,cashS,unitsS] <- getArgs
 txt <- readFile bars
 let rows = map split (tail (lines txt))
     prices = map (read . (!!1)) rows :: [Double]
     cash = read cashS :: Double
     units = read unitsS :: Double
 unless (length prices >= 41 && all (\p -> p>0 && not (isNaN p || isInfinite p)) prices && cash>=0 && units>=0) (fail "Invalid public data or account")
 let result = R.order R.RevisionV1 0.0005 prices cash units (units==0)
     body = case result of R.Hold -> ""; R.Buy q -> printf "buy,%.8f\n" q; R.Sell q -> "sell," ++ show q ++ "\n"
     rev = reverse prices
     p = head rev
     r k = p/(rev!!k)-1
     dist = p/(sum(take 20 rev)/20)-1
     rs = zipWith (\a b -> log(a/b)) (take 41 rev) (tail(take 41 rev))
     mu = sum rs/40
     sd = sqrt(sum(map (\x -> (x-mu)^2) rs)/39)
     features = printf "decision t=%s; close=%.12f; return20=%.9f; return40=%.9f; SMA20-distance=%.9f; sigma40=%.9f; cash=%.12f; units=%.12f; order=%s" (head(last rows)) p (r 20) (r 40) dist sd cash units (show result)
     approach = "Experimental frozen RevisionV1: require 41 closes. When flat, buy only if arithmetic 20/40-bar returns and close/SMA20-1 all exceed 0.003. When long, sell all only if all three are below -0.003; otherwise hold, without topups. Buy units floor to 1e-8 of cash/[decisionClose*(1+max(0.12,4*sampleSD40logreturns))*1.0005*1.001]. Reserve reduces but cannot guarantee next-close feasibility. Only supplied public t,close,volume data and stated account are inputs; volume unused. " ++ features
     changes = "Frozen RevisionV1 reused, not a newly improved algorithm. Actual source chain verified this task: /workspace/strategies/paper_be01d1611e99/agent-two/Round0.hs SHA256 6fa9df3fbfcf4f1f34795762bf677a423a6572b14ce106a83d41a68e7d8eb45c originally used positive arithmetic 10/20-bar entry and 90% cash sizing. Actual revision /workspace/strategies/paper_be01d1611e99/agent-two/offline-v1/Revision.hs SHA256 9d64d3f169de7770aeb7e5d061b55bf9ba0d3ff8e9b6c72b8ff0dd6ec6de5036 is byte-identical to legitimately shared /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs and both later own /workspace/strategies/paper_05b62b926174/agent-two/Revision.hs and /workspace/strategies/paper_aef4ace3cdbf/agent-two/Revision.hs. All located; no required strategy source missing. Actual shared peer source /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs SHA256 b4d9690941b3842d4e1738a536a5748cc61ccd15806759496815dad8a0dfc3aa is also preserved at /workspace/strategies/paper_aef4ace3cdbf/agent-two/OriginalPeerStrategy.hs. Sharing and actual-source review recorded in /shared/competition/paper_be01d1611e99/collaboration/agent-two/peer-review.json. RevisionV1 adopted peer 20/40 confirmation and max(12%,4*sampleSD40logreturns) price reserve; changed own initial 10/20 rule and 90% allocation to arithmetic 20/40 returns plus SMA20-distance all >0.003 for entry, all <-0.003 for exit, no topups; peer used positive 20/40 summed log returns and liquidation if either nonpositive, with 1e-10 units precision, while RevisionV1 floors buys to 1e-8. These adaptations predate this task. Later own harness /workspace/strategies/paper_05b62b926174/agent-two/Strategy.hs SHA256 4271ae8a726cc1181ea6b494c8c9bbf9e0231e4020102f4b8c4c5aee3d5a8ede and /workspace/strategies/paper_aef4ace3cdbf/agent-two/Strategy.hs SHA256 22f8f78ae5b303dd8235f391526e1bcd9f9d99f6d9f21a0907e0059a429a2d6f use the same frozen RevisionV1. Current Strategy.hs is copied from the latter with ONLY changes and code_ref manifest strings replaced; Revision.hs copied byte-for-byte. No signal, parameters, sizing, parsing, validation or execution logic changed; no new peer exchange. Source hashes recorded alongside current source in round-0.sha256. Old retrospective proxy results cited in prior harnesses did not establish improvement; no old market dataset or old bars loaded for decisions, no new tuning or performance claim. Decisions use only this round public bars and authorized account. Unknown next close means reserve cannot guarantee affordability. Historical start selected by routine; supplied previous starts 124/152/176 with lookback60/competition14 do not verify disjointness or unseen data here; no such claim. Exactly two decision rounds intended, round1 awaits routine feedback and public bars, with cash/units carried forward as routine states, not reset by agent. No current peer submissions, private judge assets or engine state accessed or modified. Only authoritative settlement counts; no version promotion or fabricated improvement."
     ref = "/workspace/strategies/paper_e89d0022809c/agent-two/Strategy.hs; frozen dependency /workspace/strategies/paper_e89d0022809c/agent-two/Revision.hs SHA256 9d64d3f169de7770aeb7e5d061b55bf9ba0d3ff8e9b6c72b8ff0dd6ec6de5036; source chain and hashes in changes and /workspace/strategies/paper_e89d0022809c/agent-two/round-0.sha256"
 writeFile out ("side,quantity\n" ++ body)
 writeFile manifest ("{\"code_ref\":" ++ json ref ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n")
 putStrLn features
 putStrLn ("Orders ready: " ++ out)
