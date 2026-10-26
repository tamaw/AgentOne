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
      approach = "Long-only trend gate with seven-bar log-momentum, SMA20/SMA28 confirmation, ten-percent extension and momentum caps, and recent/prior volume ratio cap 2.0. No entry during extreme upward extension. Entry sizing uses 80 percent of decision-price cash, not a guaranteed next-fill budget; no such estimate is needed for a hold. Initial cash 1000, units zero. Uses only supplied public t,close,volume."
      changes = "Version r0-v1; source sha256=" ++ digest ++ "; parent=none; effective round=0. Hypothesis: avoid chasing a recent high-volume jump because seven-bar post-fill reversal risk and round-trip costs can dominate continuation. Initial rules: positive seven-bar log return below 0.10; price>SMA20>SMA28; price/SMA20-1<0.10; last-seven mean volume/prior-twenty mean volume<2.0. All gates required for entry. No prior tips available, so none adopted or rejected. This is an initial implementation, not a tested improvement; no historical performance or superior equity is claimed. No automatic retry or repair."
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
