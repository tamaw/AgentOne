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
  let cash = 1014.3520899517492
      held = 0
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
      changes = "source=sha256:"++hash++"; parent=/workspace/btc-paper/daily_491a334aba93_m1/round-1/Strategy.hs#sha256:"++parentHash++" (v2-inventory); version=v3-round2-state; effective_round=2. Hypothesis: retain the existing regularized mean-reversion and inventory-aware policy without tuning on two sparse settlements; no performance improvement is established. Actual edits: supplied starting cash updated from 315.5724201417289 to 1014.3520899517492 and held units from 7.2358441286 to 0; provenance updated. All signal, allocation, no-trade and cash-stress rules unchanged: AR slope prior 0.90 with 10 pseudo-observations, clip [0,0.98], decision+7 versus decision+1 horizon, six variance intervals, variance penalty 3, allocation cap 0.95, buy threshold log(1.0005*1.001), sell threshold log(0.9995*0.999), buy feasibility stress 1.35 times maximum observed close, downward quantity rounding at 1e-10. Adopt settled round-1 coaching and peer tips on separating operational validity from performance, fill-to-mark alignment, cash/passive and exposure confounding, and exact parent/effective-round provenance as interpretation and artifact-check principles; existing alignment and readbacks already implement the relevant operational rules. Reject copying peer parameters or retuning on sparse outcomes because coaching supplies no independent comparative evidence. Defer matched chronological version/exposure/turnover comparisons as unperformed research, not a tested improvement. The last settled round lost value and trailed passive; neither this source edit nor successful execution demonstrates improvement. No backtest, parameter search, independent replay, extra match, retry, repair or resubmission."
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
