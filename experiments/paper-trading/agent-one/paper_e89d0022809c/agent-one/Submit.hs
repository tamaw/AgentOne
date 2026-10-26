module Main where
import StrategyV2
import System.Environment
import System.Directory
import System.Process
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
root = "/workspace/paper_e89d0022809c/agent-one"
main = do
  [dir,cashS,unitsS] <- getArgs
  raw <- readFile (dir++"/bars.csv")
  let ls=lines raw
  unless (not(null ls) && head ls=="t,close,volume") (fail "Invalid public bars header")
  rows <- forM (tail ls) $ \l -> case split l of
    [t,p,v] -> pure (read t::Int,read p::Double,read v::Double)
    _ -> fail "Malformed public bar"
  unless (not(null rows) && map (\(t,_,_)->t) rows == [0..length rows-1] && all (\(_,p,v)->p>0 && not(isInfinite p) && not(isNaN p) && v>=0 && not(isInfinite v) && not(isNaN v)) rows) (fail "Invalid public history")
  let cash=read cashS::Double; units=read unitsS::Double
      f=features(reverse(map (\(_,p,_)->p) rows))
      mode=PeerCostHysteresisV2
      s=signal mode f (units>0)
      q=case s of Buy->buyQuantity mode f 0.001 0.0005 cash; Sell->units; Hold->0
      orders="side,quantity\n" ++ case s of
        Buy | q>0 -> printf "buy,%.10f\n" q
        Sell | q>0 -> printf "sell,%.10f\n" q
        _ -> ""
  unless(cash>=0 && units>=0 && not(isInfinite cash || isNaN cash || isInfinite units || isNaN units) && q>=0 && not(isInfinite q || isNaN q)) (fail "Invalid account or quantity")
  hashes <- readProcess "sha256sum" [root++"/Submit.hs",root++"/StrategyV2.hs",root++"/PeerRevision.hs","/workspace/paper_05b62b926174/agent-one/Submit.hs","/workspace/paper_05b62b926174/agent-one/StrategyV2.hs","/workspace/paper_05b62b926174/agent-one/PeerRevision.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs","/workspace/paper_aef4ace3cdbf/agent-one/Submit.hs","/workspace/paper_aef4ace3cdbf/agent-one/StrategyV2.hs","/workspace/paper_aef4ace3cdbf/agent-one/PeerRevision.hs","/workspace/paper_be01d1611e99/agent-one/revision/v2/StrategyV2.hs","/workspace/paper_be01d1611e99/agent-one/revision/StrategyV1.hs","/workspace/paper_be01d1611e99/agent-one/revision/findings.json","/workspace/paper_be01d1611e99/agent-one/revision/final-peer-review.json",dir++"/brief.md",dir++"/bars.csv"] ""
  let fields =
        [("code_ref",root++"/Submit.hs; "++root++"/StrategyV2.hs mode PeerCostHysteresisV2; preserved peer artifact "++root++"/PeerRevision.hs. SHA256 provenance:\n"++hashes)
        ,("approach","Frozen reused strategy for both rounds: require 41 public bars. Enter flat only when 20- and 40-bar returns and close/SMA20-1 are all >0.003; exit held only when all three are < -0.003. Otherwise hold, no topups. Buy floor1e-10[cash/(decision_close*(1+max(0.12,4*sigma40))*(1.0005)*(1.001))], sell held quantity. Sigma40 is sample standard deviation of last 40 log returns. Only supplied public bars inform decisions; volume unused. Unknown next-close fill is not observed. Reserve cannot guarantee feasibility after an arbitrary gap. Long only, no leverage. Only routine settlement counts.")
        ,("changes","No new signal, thresholds, sizing, or claimed improvement. This runner is adapted directly from /workspace/paper_aef4ace3cdbf/agent-one/Submit.hs (SHA256 1377cb898e78ff4158ebe860c3a16f88c8e561f863bbf5185e2346451a593ae8), itself adapted from /workspace/paper_05b62b926174/agent-one/Submit.hs (SHA256 9b09773475c1c8a37e7f7fcbd4fb8ddf795322fa6d70e074a67307197b7bf0e1). Exact runner changes here: root path, provenance hash inputs, changes field replacement and added evidence_limits field; parsing, feature calculation, order decisions, quantity and output encoding unchanged. Both prior runners preserved locally as AefSubmit.hs.snapshot and EarlierSubmit.hs.snapshot. StrategyV2.hs and PeerRevision.hs copied byte-for-byte from paper_aef4ace3cdbf; identical to paper_05b62b926174 copies and original shared sources by SHA256. Actual own revised/shared source /workspace/paper_be01d1611e99/agent-one/revision/v2/StrategyV2.hs and /shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs: SHA256 668362a0ca843cb1775af713039db5681bbcac6b5db1e23f84d48f82880a405f, mode PeerCostHysteresisV2. Actual shared peer source /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs: SHA256 9d64d3f169de7770aeb7e5d061b55bf9ba0d3ff8e9b6c72b8ff0dd6ec6de5036, RevisionV1. Earlier legitimate two-way source exchange/review is recorded in /workspace/paper_be01d1611e99/agent-one/revision/findings.json and final-peer-review.json. Adaptation from peer RevisionV1 replaces original positive20/40 entry and exit-on-either-nonpositive with all-three +/-0.003 conditions including close/SMA20; own equivalent log thresholds and original 1e-10 precision retained versus peer arithmetic returns and 1e-8 precision. Both retain max(0.12,4*sigma40) reserve. Own ConsensusV1 revision exists in revision/StrategyV1.hs but needs121 bars and is not shortened or used. No current peer submissions accessed, no new collaboration in this run; sharing refers only to the actual historical artifacts.")
        ,("evidence_limits","All requested primary strategy sources located and hashed; no missing primary source. No independent original exchange transcript or point-in-time immutability verification performed; provenance relies on current files and retained review artifacts, not Git version claims. Prior research was mixed/negative: V2 beat original2/6 and buyhold1/6 annual LTC/XRP transfer holdouts and underperformed original on both continuous paths; no demonstrated anonymous-index edge. Decisions consume only this round's public bars and authorized account/settlement inputs, never archived price histories or current peer submissions. No window selection, engine/private-state access, real trades, financial transactions or infrastructure changes. Previous starts124,152,176 with60-bar lookback and14-bar competition are user-provided; current start is not published, so no disjoint/unseen claim. Freeze same strategy across exactly two authorized rounds with initial capital1000 carried by routine; no reset between rounds. Unknown next-close gaps can reject fixed-size buys despite reserve. Only routine settlement counts; local diagnostics are not P&L or evidence of improvement.")
        ,("decision","cash="++cashS++"; units="++unitsS++"; "++show f++"; signal="++show s++"; quantity="++show q)]
      json="{\n"++concat[(if i==0 then "" else ",\n")++show k++":"++show v | (i,(k,v))<-zip [0::Int ..] fields]++"\n}\n"
      out=dir++"/agent-one"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") orders
  writeFile (out++"/manifest.json") json
  putStrLn (show f++"; "++show s++"; quantity="++show q)
  putStr orders
  putStrLn ("Submission ready: "++out++"/orders.csv and manifest.json. Only routine settlement counts.")
