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
      approach = "Unchanged parent long-only trend gate: positive seven-bar log momentum below 0.10, price>SMA20>SMA28, price/SMA20-1<0.10, and last-seven/prior-twenty mean volume ratio<2.0. All gates required. Entry budget remains 800 index-cash including buy fee and slippage estimated at decision close; arbitrary next-close gaps can still cause infeasibility. Current cash=1000 and units=0. Uses only supplied public observations and settled-round feedback. No real trading."
      changes = "Version r1-v1; source sha256=" ++ digest ++ "; parent=r0-v1, source /workspace/btc-daily-fade2130e2e5/Strategy-r0-v1.hs#sha256=095d4809cdb05b195aaf694f0f6362e64858d3cbac953e9484c1dcbcfccd1c6e; effective round=1. Hypothesis remains that avoiding unusually extended high-volume jumps may reduce reversal exposure over the delayed mark horizon. Actual rule/parameter changes: none; preserve seven-bar momentum 0..0.10, SMA20/SMA28, extension cap 0.10, volume ratio cap 2.0, and 800 decision-price cash budget. Edits update provenance and settled-feedback attribution only. Adopt settled coaching and both agents' tips on causal decision/fill/mark separation, net-versus-gross accounting, cash and cost-matched benchmarks, exposure awareness, and exact parent/version retention as evaluation principles. Reject using one settled outcome to retune gates or claim filter skill; decline adopting peer multi-horizon momentum and volatility sizing because no matched independent evidence supports replacing existing gates. Chronological one-change ablations remain a proposed later authorized analysis, not performed here. No performance test or independent matched replay was run; this source edit is not a tested improvement. Initial orchestration module compilation failed before strategy execution; archived separately. This strategy is built and executed once, without automatic retry, repair, or resubmission."
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
