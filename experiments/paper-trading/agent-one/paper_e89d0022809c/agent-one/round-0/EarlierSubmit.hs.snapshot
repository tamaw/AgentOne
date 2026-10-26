module Main where
import StrategyV2
import System.Environment
import System.Directory
import System.Process
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
root = "/workspace/paper_05b62b926174/agent-one"
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
  hashes <- readProcess "sha256sum" [root++"/Submit.hs",root++"/StrategyV2.hs",root++"/PeerRevision.hs","/workspace/paper_be01d1611e99/agent-one/revision/StrategyV1.hs","/workspace/paper_be01d1611e99/agent-one/revision/v2/StrategyV2.hs","/workspace/paper_be01d1611e99/agent-one/revision/findings.json","/shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-two/findings-for-agent-one.json",dir++"/brief.md",dir++"/bars.csv"] ""
  let fields =
        [("code_ref",root++"/Submit.hs; "++root++"/StrategyV2.hs (PeerCostHysteresisV2); source SHA256 references:\n"++hashes)
        ,("approach","Frozen across both authorized new rounds: PeerCostHysteresisV2, long-only fixed-quantity orders, no topups. >=41 public observations required. Enter when 20/40-bar returns and close/SMA20-1 all >0.003; exit only when all < -0.003; otherwise retain position. Buy floor1e-10[cash/(decision_close*(1+max(0.12,4*sigma40))*(1.0005)*(1.001))]; sell held units. No future fill observation used. Reserve reduces but cannot guarantee cash feasibility at unknown next close; whole order may be rejected. Decision uses only supplied t,close,volume (volume unused); no external histories, private assets, judge state, or current peer orders used.")
        ,("changes","Completed own improvement artifacts located: /workspace/paper_be01d1611e99/agent-one/revision/findings.json, StrategyV1.hs, v2/StrategyV2.hs, v2/results.csv, final-peer-review.json; public shared counterparts /shared/competition/paper_be01d1611e99/collaboration/agent-one/findings.json and StrategyV1.hs. Original entry positive20/40 and immediate exit on either nonpositive replaced by fixed +/-0.003 triple-condition hysteresis. Original 12%-or-4sigma reserve and 1e-10 precision retained. Legitimately shared peer algorithm actively used: /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs RevisionV1, replicated in own v2/StrategyV2.hs using equivalent log momentum thresholds and own1e-10 vs peer1e-8 precision. Shared evidence: agent-two/findings-for-agent-one.json; own final-peer-review.json. Own ConsensusV1 is also a completed revision but needs121 bars; it is not shortened or spliced into this trial. V2 selected as already-reviewed executable shared revision with41-bar warmup, not demonstrated better forecasting, not fitted to new rounds. Prior evidence is explicitly negative/mixed: peer mean heldout revision6.20% vs own6.63% and buyhold25.81%; own V2 beat original2/6 and buyhold1/6 LTC/XRP annual transfer holdouts and lost to original on both continuous paths. Retrospective correlated-market research does not establish an anonymous-index edge. No raw external research price series consumed in this competition. Two new rounds cannot verify general self-improvement; only engine settlement and its matched round0-fill buy-and-hold count. No profit-alone improvement claim, no selection/promotion.")
        ,("decision","cash="++cashS++"; units="++unitsS++"; "++show f++"; signal="++show s++"; quantity="++show q)
        ,("evidence_limits","Round-specific authorized inputs: "++dir++"/brief.md and "++dir++"/bars.csv; account cash/units supplied by engine. Previous public evidence is read only when explicitly supplied. Local output is not settlement. Benchmark buys once at round0 next-close with same fee/slippage and holds; cannot infer its current equity without authorized settlement. Policy fixed for both rounds; no tuning on prior competition outcomes or new round0 settlement.")]
      json="{\n"++concat [ (if i==0 then "" else ",\n")++show k++":"++show v | (i,(k,v))<-zip [0::Int ..] fields]++"\n}\n"
      out=dir++"/agent-one"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") orders
  writeFile (out++"/manifest.json") json
  putStrLn (show f++"; "++show s++"; quantity="++show q)
  putStrLn orders
  putStrLn ("Submission ready: "++out++"/orders.csv and manifest.json. Await authoritative settlement; no performance claim.")
