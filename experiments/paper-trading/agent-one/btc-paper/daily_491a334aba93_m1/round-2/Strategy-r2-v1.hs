module Main where
import System.Environment
import System.Directory
import System.Process
import Control.Monad
import Text.Read (readMaybe)
import Text.Printf
import Data.List (intercalate)
data Bar = Bar Int Double Double deriving Show
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
parse s = case split s of
  [a,b,c] -> case (readMaybe a, readMaybe b, readMaybe c) of
    (Just t,Just p,Just v) | p>0 && v>=0 && not (isInfinite p || isNaN p || isInfinite v || isNaN v) -> pure (Bar t p v)
    _ -> fail "invalid observation"
  _ -> fail "invalid CSV row"
price (Bar _ p _) = p
volume (Bar _ _ v) = v
time (Bar t _ _) = t
mean xs = sum xs / fromIntegral (length xs)
lastN n = reverse . take n . reverse
main = do
  [barsPath,outDir,sourcePath,auditDir] <- getArgs
  raw <- readFile barsPath
  let rows = lines raw
  unless (not (null rows) && head rows == "t,close,volume") $ fail "invalid header"
  bars <- mapM parse (tail rows)
  unless (length bars >= 28 && and (zipWith (<) (map time bars) (drop 1 (map time bars)))) $ fail "insufficient or unordered observations"
  let ps = map price bars
      vs = map volume bars
      p = last ps
      sma20 = mean (lastN 20 ps)
      sma28 = mean (lastN 28 ps)
      momentum7 = log (p / (ps !! (length ps - 8)))
      extension = p / sma20 - 1
      priorVolume = mean (take 20 (drop (length vs - 27) vs))
      volumeRatio = if priorVolume>0 then mean (lastN 7 vs)/priorVolume else 1/0
      enter = p>sma20 && sma20>sma28 && momentum7>0 && momentum7<0.10 && extension<0.10 && volumeRatio<2.0
      quantity = 800 / (p * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" quantity else ""
  hashOutput <- readProcess "sha256sum" [sourcePath] ""
  let digest = head (words hashOutput)
      codeRef = sourcePath ++ "#sha256=" ++ digest
      approach = "Unchanged local-parent long-only trend gates: price>SMA20>SMA28; seven-bar log momentum in (0,0.10); price/SMA20-1<0.10; last-seven/prior-twenty average volume ratio<2.0. Buy budget is 800 index-cash at decision-close estimated all-in cost, leaving a 20% cash reserve; a next-close upward gap exceeding 25% can still cause rejection. Supplied current cash=1000, units=0. Public observations only; next-close execution and decision+7 mark. No real trading."
      changes = "version=r2-v1; source=sha256:" ++ digest ++ "; parent=local candidate /workspace/btc-round1/Strategy-r1-v1.hs#sha256:1e5339146c9c3f235f10e925218654cf872b56fd98ef157f68bf137d4c7b7758; effective_round=2. Parent is a retained local source, not an accepted current-run submission; round-1 authoritative feedback reports missing artifacts, not a valid hold. Hypothesis: preserve bounded trend gates while fixing submission completeness, rather than infer signal failure from rejection. Actual signal/risk parameter changes: none; retain SMA20/28, seven-bar log momentum bounds 0 and 0.10, extension cap 0.10, volume ratio cap 2.0, and 800 decision-close budget. Actual edits: current-round provenance and manifest attribution; single build/run at the required round-2 destination with exact readback of both required files and preserved source/logs. Adopt settled coaching and both agents' shared tips on artifact completeness and acceptance-versus-performance separation; file readback is not authoritative acceptance. Adopt causal fill-to-mark alignment, cash/cost-matched passive references and exposure/turnover controls as evaluation principles, not new signal evidence. Reject copying peer AR parameters, retuning from the sparse scoreboard, and treating either edits or benchmark gaps as demonstrated improvement. Matched chronological comparisons and ablations remain unperformed suggestions. No backtest, parameter search, independent replay, or tested improvement claimed. One compile and one execution only, no automatic retry, repair, or resubmission."
      manifest = "{\n" ++ intercalate ",\n" ["  " ++ show k ++ ": " ++ show v | (k,v)<-[("code_ref",codeRef),("approach",approach),("changes",changes)]] ++ "\n}\n"
  createDirectoryIfMissing True outDir
  existsOrders <- doesFileExist (outDir ++ "/orders.csv")
  existsManifest <- doesFileExist (outDir ++ "/manifest.json")
  when (existsOrders || existsManifest) $ fail "existing submission; refusing overwrite"
  writeFile (auditDir ++ "/features.txt") (unlines ["source_sha256="++digest,"bars="++show (length bars),"last_close="++show p,"momentum7_log="++show momentum7,"sma20="++show sma20,"sma28="++show sma28,"extension="++show extension,"volume_ratio="++show volumeRatio,"entry_gate="++show enter,"performance_test=none"] )
  writeFile (outDir ++ "/orders.csv") orders
  writeFile (outDir ++ "/manifest.json") manifest
  ordersBack <- readFile (outDir ++ "/orders.csv")
  manifestBack <- readFile (outDir ++ "/manifest.json")
  unless (ordersBack==orders && manifestBack==manifest) $ fail "submission readback mismatch"
  writeFile (auditDir ++ "/orders.readback.csv") ordersBack
  writeFile (auditDir ++ "/manifest.readback.json") manifestBack
  putStrLn "Strategy completed; both submission files written and exact readback verified. No performance claim."
