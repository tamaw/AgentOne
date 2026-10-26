module Main where
import System.Environment
import System.FilePath
import System.Process
import System.Exit
import Control.Monad
import Numeric
import Text.Read
split s = case break (==',') s of (a,[]) -> [a]; (a,_:r) -> a:split r
avg xs = sum xs / fromIntegral (length xs)
clamp lo hi x = max lo (min hi x)
finite x = not (isNaN x || isInfinite x)
num x = showFFloat (Just 10) x ""
down x = fromInteger (floor (x*1e10)) / 1e10 :: Double
main = do
  [input,out,src,archive,parentHash] <- getArgs
  raw <- readFile input
  unless (take 1 (lines raw) == ["t,close,volume"]) (fail "Invalid bars header")
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
  unless (length rows >= 25 && all ((==3) . length) rows) (fail "Invalid bars shape")
  let ts = map (read . head) rows :: [Int]
      closes = map (read . (!!1)) rows :: [Double]
      volumes = map (read . (!!2)) rows :: [Double]
  unless (and (zipWith (<) ts (tail ts)) && all (\x -> x>0 && finite x) closes && all (\x -> x>=0 && finite x) volumes) (fail "Invalid observations")
  let cash = 315.5724201417289
      held = 7.2358441286
      logs = map log closes
      xs = init logs
      ys = tail logs
      mx = avg xs
      my = avg ys
      sxx = sum [(x-mx)^2 | x<-xs]
      sxy = sum (zipWith (\x y -> (x-mx)*(y-my)) xs ys)
      prior = 10 * sxx / fromIntegral (length xs)
      beta = if sxx > 0 then clamp 0 0.98 ((sxy+prior*0.9)/(sxx+prior)) else 0.9
      alpha = my-beta*mx
      residuals = zipWith (\x y -> y-alpha-beta*x) xs ys
      noise = max 1e-8 (sum (map (^2) residuals)/fromIntegral (length residuals-2))
      predictions = iterate (\x -> alpha+beta*x) (last logs)
      variance = noise * sum [beta^(2*k) | k<-[0..5::Int]]
      buyCost = 1.0005*1.001
      sellFactor = 0.9995*0.999
      grossEdge = predictions!!7-predictions!!1
      edge = grossEdge-log buyCost
      allocation = clamp 0 0.95 (edge/(3*variance))
      equity = cash+held*last closes
      desired = equity*allocation/(last closes*buyCost)
      stressPrice = maximum closes*1.35*buyCost
      buyQty = down (min (max 0 (desired-held)) (cash/stressPrice))
      sellQty = down (min held (max 0 (held-desired)))
      order = if desired>held && grossEdge>log buyCost && buyQty>=1e-8 then Just ("buy",buyQty) else if desired<held && grossEdge<log sellFactor && sellQty>=1e-8 then Just ("sell",sellQty) else Nothing
      orders = "side,quantity\n" ++ maybe "" (\(side,q)->side++","++num q++"\n") order
  unless (all finite [beta,alpha,noise,variance,grossEdge,allocation,desired,buyQty,sellQty]) (fail "Nonfinite model result")
  (hc,ho,he) <- readProcessWithExitCode "sha256sum" [src] ""
  unless (hc==ExitSuccess) (fail ("Hash failed: "++he))
  let hash = head (words ho)
      approach = "Public-close-only regularized log-price AR(1), unchanged prior and risk parameters; predict decision+7 versus decision+1. Inventory-aware target rebalancing with asymmetric transaction-cost no-trade band; long-only. Buys are cash-capped at 1.35 times maximum observed close with fees/slippage; this stress is not a guaranteed future-price bound. No external data or current peer input."
      changes = "source=sha256:"++hash++"; parent=/workspace/btc-paper/daily_491a334aba93_m1/round-0/Strategy.hs#sha256:"++parentHash++" (v1); version=v2-inventory; effective_round=1. Hypothesis: retain the original bounded mean-reversion forecast without selecting parameters from one favorable settlement; avoid unnecessary turnover by requiring forecast edge to exceed directional execution cost. Actual edits: replace fixed initial 1000 equity and buy-only orders with supplied cash/units, marked-equity target, sell support capped at holdings, incremental buys capped by current cash under the existing 1.35-max-price stress; buy gross-log-edge threshold log(1.0005*1.001), sell threshold log(0.9995*0.999), otherwise hold. Preserve slope prior 0.90, 10 pseudo-observations, slope clip [0,0.98], six fill-to-mark variance intervals, variance penalty 3, exposure ceiling 0.95. Add zero-variance safeguard and finite-volume validation. Adopt settled round-0 coaching on fill-to-mark alignment (already implemented), truthful version provenance, cash/passive comparison and exposure confounding as interpretation constraints, not signal changes. Reject copying peer momentum parameters or treating its directional hypothesis as evidence: one settlement and the coaching packet provide no validated comparative edge. Chronological walk-forward comparison remains an unperformed research suggestion, not an adopted tested improvement. Source edits and execution/readback validation only; no backtest, parameter search, independent replay or demonstrated improvement. Single build/run, no retry or repair/resubmission."
      manifest = "{\n  \"code_ref\": "++show (src++"#sha256:"++hash)++",\n  \"approach\": "++show approach++",\n  \"changes\": "++show changes++"\n}\n"
  writeFile (archive </> "model-output.txt") (unlines ["beta="++show beta,"alpha="++show alpha,"variance="++show variance,"forecast_gross_log_edge="++show grossEdge,"allocation="++show allocation,"planned_order="++show order,"source_sha256="++hash])
  writeFile (out </> "orders.csv") orders
  writeFile (out </> "manifest.json") manifest
  ro <- readFile (out </> "orders.csv")
  rm <- readFile (out </> "manifest.json")
  unless (ro==orders && rm==manifest) (fail "Readback mismatch; not repaired")
  let valid r = case split r of
        [side,q] -> case (readMaybe q :: Maybe Double) of
          Just n -> finite n && n>0 && ((side=="sell" && n<=held) || (side=="buy" && n*stressPrice<=cash))
          _ -> False
        _ -> False
  unless (take 1 (lines ro)==["side,quantity"] && all valid (drop 1 (lines ro))) (fail "Order validation failed; not repaired")
  (jc,jo,je) <- readProcessWithExitCode "python3" ["-c","import json,sys; d=json.load(open(sys.argv[1])); assert all(isinstance(d.get(k),str) and d[k] for k in ('code_ref','approach','changes')); print('Manifest JSON and required string fields verified.')",out </> "manifest.json"] ""
  unless (jc==ExitSuccess) (fail ("Manifest invalid; not repaired: "++je))
  writeFile (archive </> "orders.csv") ro
  writeFile (archive </> "manifest.json") rm
  putStr jo
  putStrLn "Submission files written once and both readback-checked. Model execution succeeded; intentional holds, if any, are distinct from failures."
  putStrLn ("Executable source SHA256: "++hash)
