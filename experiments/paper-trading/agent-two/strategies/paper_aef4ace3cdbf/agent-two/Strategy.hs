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
     changes = "Reused frozen RevisionV1 without signal, sizing or parameter changes from own /workspace/strategies/paper_05b62b926174/agent-two/Strategy.hs and Revision.hs. Original harness SHA256 4271ae8a726cc1181ea6b494c8c9bbf9e0231e4020102f4b8c4c5aee3d5a8ede. Current harness changes only code_ref and manifest provenance for this authorized two-round simulation. Exact original harness and peer source preserved beside current harness as OriginalHarness.hs and OriginalPeerStrategy.hs. Revision.hs is identical to shared /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs, SHA256 9d64d3f169de7770aeb7e5d061b55bf9ba0d3ff8e9b6c72b8ff0dd6ec6de5036. Actual prior algorithm sharing occurred: shared peer /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs SHA256 b4d9690941b3842d4e1738a536a5748cc61ccd15806759496815dad8a0dfc3aa supplied 20/40 confirmation and max(12%,4*sigma40) reserve; RevisionV1 adds SMA20 consensus and symmetric 0.30% hysteresis, floors units to 1e-8, and does not adopt peer disjunctive exit. No new peer exchange or algorithm revision occurred in this task; old shared source was reviewed and reused. Prior baseline own entry was 10/20 with 90% allocation and exit SMA20/10; these were already revised before paper_05b62b926174. Prior controlled retrospective proxy evidence at /shared/competition/paper_be01d1611e99/collaboration/agent-two/results-summary.json did not establish improvement: heldout mean RevisionV1 return 6.203737806%, own generalized 6.633107558%, buyhold 25.808277224%; historical dependence, survivorship and uncertain adjustments limit transfer. No promotion or self-improvement claimed. No tuning to observed outcomes, no external market data loaded, and no current peer submission or private judge assets accessed. Decisions use only current supplied public bars and authorized cash/units. Reserve cannot guarantee unknown next-close affordability. Only routine settlement counts; no P&L claimed."
     ref = "/workspace/strategies/paper_aef4ace3cdbf/agent-two/Strategy.hs; dependency /workspace/strategies/paper_aef4ace3cdbf/agent-two/Revision.hs; preserved originals /workspace/strategies/paper_aef4ace3cdbf/agent-two/OriginalHarness.hs and /workspace/strategies/paper_aef4ace3cdbf/agent-two/OriginalPeerStrategy.hs"
 writeFile out ("side,quantity\n" ++ body)
 writeFile manifest ("{\"code_ref\":" ++ json ref ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n")
 putStrLn features
 putStrLn ("Orders ready: " ++ out)
