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
     changes = "Located completed improvement candidate, not invented: /workspace/strategies/paper_be01d1611e99/agent-two/offline-v1/Revision.hs (SHA256 9d64d3f169de7770aeb7e5d061b55bf9ba0d3ff8e9b6c72b8ff0dd6ec6de5036), identical to legitimately shared /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs. Exact local copy retained alongside this harness as Revision.hs; RevisionV1 branch unchanged for both new rounds. Relative to own prior round0 10/20 positive entry and round1 SMA20/10 exit, candidate unifies state machine, slows to 20/40 plus SMA20 consensus, adds symmetric 0.30% hysteresis, changes 90% cash allocation to peer volatility reserve. Shared algorithm source: /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs (SHA256 b4d9690941b3842d4e1738a536a5748cc61ccd15806759496815dad8a0dfc3aa); directly uses its 20/40 confirmation and max(12%,4*sigma40) execution reserve; not its disjunctive exit or 1e-10 precision. Actual-source review: /shared/competition/paper_be01d1611e99/collaboration/agent-two/peer-review.json. Peer StrategyV1.hs consensus120 is not adopted; peer transfer-plan.json independently attributes PeerCostHysteresisV2 to our RevisionV1, not new independent evidence. Completed-task evidence: /workspace/strategies/paper_be01d1611e99/agent-two/offline-v1/results-summary.json, evaluation.csv and fallback-plan.json. Summary explicitly says do not promote: primary retrospective equity-proxy heldout mean revision return 6.203737806% versus own generalized 6.633107558% and buyhold 25.808277224%, not authoritative settlement. These old results document provenance/limitations only: no external series loaded or new fitting in this competition. Historical survivorship, dependence, uncertain price adjustments and retrospective splits limit transfer to anonymous index. Prior contest observed history is not unseen validation. No parameter changes from either observed contest or old performance. Experimental use requested here is not promotion or verified improvement. New-round orders use only the supplied public bars and authorized account/feedback; no private judge/market assets or current peer orders accessed. Unknown next close precludes unconditional buy-feasibility guarantee. Only authoritative settlement and matched buy-and-hold count; no realized result claimed before settlement."
     ref = "/workspace/strategies/paper_05b62b926174/agent-two/Strategy.hs; frozen dependency /workspace/strategies/paper_05b62b926174/agent-two/Revision.hs"
 writeFile out ("side,quantity\n" ++ body)
 writeFile manifest ("{\"code_ref\":" ++ json ref ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n")
 putStrLn features
 putStrLn ("Orders ready: " ++ out)
