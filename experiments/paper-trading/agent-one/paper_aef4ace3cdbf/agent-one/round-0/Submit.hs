module Main where
import StrategyV2
import System.Environment
import System.Directory
import System.Process
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
root = "/workspace/paper_aef4ace3cdbf/agent-one"
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
  hashes <- readProcess "sha256sum" [root++"/Submit.hs",root++"/StrategyV2.hs",root++"/PeerRevision.hs","/workspace/paper_05b62b926174/agent-one/Submit.hs","/workspace/paper_05b62b926174/agent-one/StrategyV2.hs","/workspace/paper_05b62b926174/agent-one/PeerRevision.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs",dir++"/brief.md",dir++"/bars.csv"] ""
  let fields =
        [("code_ref",root++"/Submit.hs; "++root++"/StrategyV2.hs mode PeerCostHysteresisV2; preserved peer artifact "++root++"/PeerRevision.hs. SHA256 provenance:\n"++hashes)
        ,("approach","Frozen reused strategy for both rounds: require 41 public bars. Enter flat only when 20- and 40-bar returns and close/SMA20-1 are all >0.003; exit held only when all three are < -0.003. Otherwise hold, no topups. Buy floor1e-10[cash/(decision_close*(1+max(0.12,4*sigma40))*(1.0005)*(1.001))], sell held quantity. Sigma40 is sample standard deviation of last 40 log returns. Only supplied public bars inform decisions; volume unused. Unknown next-close fill is not observed. Reserve cannot guarantee feasibility after an arbitrary gap. Long only, no leverage. Only routine settlement counts.")
        ,("changes","No new signal, parameter, sizing, or algorithm revision in this task. Reuse actual own sources /workspace/paper_05b62b926174/agent-one/StrategyV2.hs and Submit.hs; copy StrategyV2.hs and PeerRevision.hs byte-for-byte. Submit.hs retains prior parsing, feature generation, signal and sizing code; changes only artifact root, provenance hashes and manifest text. Preserve prior runner as PriorSubmit.hs.snapshot. Legitimate algorithm sharing previously occurred in paper_be01d1611e99: /shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs RevisionV1 contributed the +/-0.003 triple-condition hysteresis; the reviewed own implementation is /shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs PeerCostHysteresisV2. Own implementation retains original max(0.12,4*sigma40) reserve and 1e-10 quantity precision (peer uses 1e-8). This revision was already present in paper_05b62b926174; it is not a new improvement here. No new peer communication or current peer submissions inspected. No external research price histories or private engine assets consumed. Policy frozen for both new rounds, not tuned to known outcomes. Prior research was mixed/negative and does not demonstrate an anonymous-index forecasting edge; no self-improvement, selection, promotion, or performance claim.")
        ,("decision","cash="++cashS++"; units="++unitsS++"; "++show f++"; signal="++show s++"; quantity="++show q)]
      json="{\n"++concat[(if i==0 then "" else ",\n")++show k++":"++show v | (i,(k,v))<-zip [0::Int ..] fields]++"\n}\n"
      out=dir++"/agent-one"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") orders
  writeFile (out++"/manifest.json") json
  putStrLn (show f++"; "++show s++"; quantity="++show q)
  putStr orders
  putStrLn ("Submission ready: "++out++"/orders.csv and manifest.json. Only routine settlement counts.")
