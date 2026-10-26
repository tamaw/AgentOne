module Main where
import StrategyV2
import System.Environment
import System.Directory
import System.FilePath
import System.Process
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
root = "/workspace/paper_63d59f6ee3e5/agent-one"
finite x = not (isInfinite x || isNaN x)
main = do
  [dir,cashS,unitsS,feedback] <- getArgs
  brief <- readFile (dir++"/brief.md")
  unless (all (`elem` words brief) ["code_ref,","approach,","changes."]) (fail "Review manifest schema in brief")
  raw <- readFile (dir++"/bars.csv")
  let ls=lines raw
  unless (not(null ls) && head ls=="t,close,volume") (fail "Invalid bars header")
  rows <- forM (tail ls) $ \l -> case split l of
    [t,p,v] -> pure (read t::Int,read p::Double,read v::Double)
    _ -> fail "Malformed public bar"
  unless (not(null rows) && map (\(t,_,_)->t) rows == [0..length rows-1] && all (\(_,p,v)->p>0 && finite p && v>=0 && finite v) rows) (fail "Invalid public history")
  let cash=read cashS::Double; units=read unitsS::Double
      f=features(reverse(map (\(_,p,_)->p) rows))
      mode=PeerCostHysteresisV2
      s=signal mode f (units>0)
      q=case s of Buy->buyQuantity mode f 0.001 0.0005 cash; Sell->units; Hold->0
      orders="side,quantity\n" ++ case s of
        Buy | q>0 -> printf "buy,%.10f\n" q
        Sell | q>0 -> printf "sell,%.10f\n" q
        _ -> ""
  unless (cash>=0 && units>=0 && finite cash && finite units && q>=0 && finite q) (fail "Invalid account or quantity")
  let snap=root++"/"++takeFileName dir
  createDirectoryIfMissing True snap
  forM_ ["Submit.hs","StrategyV2.hs","PeerRevision.hs"] $ \p -> copyFile (root++"/"++p) (snap++"/"++p)
  hashes <- readProcess "sha256sum" [snap++"/Submit.hs",snap++"/StrategyV2.hs",snap++"/PeerRevision.hs","/workspace/paper_e89d0022809c/agent-one/StrategyV2.hs","/workspace/paper_be01d1611e99/agent-one/revision/v2/StrategyV2.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs","/shared/competition/paper_be01d1611e99/collaboration/agent-two/Revision.hs",dir++"/brief.md",dir++"/bars.csv"] ""
  let fields =
        [("code_ref",snap++"/Submit.hs; "++snap++"/StrategyV2.hs mode PeerCostHysteresisV2; "++snap++"/PeerRevision.hs retained provenance, not executed. SHA256 verified artifacts:\n"++hashes)
        ,("approach","Reused frozen long-only hysteresis strategy: minimum41 bars; enter flat when log20 and log40 returns exceed log1.003 and close/SMA20-1>0.003; exit held only when log20 and log40 <log0.997 and distance<-0.003; otherwise deliberate HOLD, no topups. Buys floor1e-10[cash/(decision_close*(1+max(0.12,4*sigma40))*1.0005*1.001)]. Sigma40 sample log-return volatility. Reserve reduces but cannot guarantee against next-close infeasibility. Volume unused. Decision: "++show f++"; signal="++show s++"; quantity="++show q++"; cash="++cashS++"; units="++unitsS++". Five-round independent run; capital starts1000 once and routine cash/units carry. Only routine settlement counts.")
        ,("changes","No changes to signal, thresholds or sizing. Independently read actual original/revised/local and shared source, matched SHA256 of StrategyV2 across preserved later-run and original shared sources, and peer Revision.hs to preserved PeerRevision.hs. Historical review reports successful collaboration and mixed/negative transfer results; original exchange transcript not independently verified, no proven improvement or predictive advantage claimed. New runner adapts prior Submit.hs parsing/order logic but replaces stale two-round narrative with five-round scope, current paths, round snapshots and mandatory post-write existence/readback/schema validation for BOTH own files, including HOLD. Own snapshots hashed each round. No peer current submissions read or modified. Window overlap/unseen status not verified. Public feedback use: "++feedback)]
      json="{\n"++concat[(if i==0 then "" else ",\n")++show k++":"++show v | (i,(k,v))<-zip [0::Int ..] fields]++"\n}\n"
      out=dir++"/agent-one"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") orders
  writeFile (out++"/manifest.json") json
  forM_ [out++"/orders.csv",out++"/manifest.json"] $ \p -> do
    exists <- doesFileExist p
    unless exists (fail ("Missing submission: "++p))
    text <- readFile p
    unless (text == if takeFileName p=="orders.csv" then orders else json) (fail "Readback mismatch")
  checked <- readProcess "python3" ["-c","import csv,json,sys,decimal; from pathlib import Path; p=Path(sys.argv[1]); m=json.loads((p/'manifest.json').read_text()); assert set(m)=={'code_ref','approach','changes'}; assert all(isinstance(v,str) and v for v in m.values()); r=list(csv.reader((p/'orders.csv').open())); assert r and r[0]==['side','quantity']; assert all(len(x)==2 and x[0] in ('buy','sell') and decimal.Decimal(x[1]).is_finite() and decimal.Decimal(x[1])>0 for x in r[1:]); print('Existence, full readback and public-schema validation PASSED for both own files.'); print((p/'orders.csv').read_text()); print('Manifest readback fields: '+', '.join(m)); print('Manifest approach: '+m['approach'])",out] ""
  putStr checked
  putStrLn ("Own submission verified: "++out++"/{orders.csv,manifest.json}. Peer current files were not accessed; cannot certify peer submission. No simulated profit claim before routine settlement.")
