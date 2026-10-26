module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Read
import Text.Printf
import Data.Char
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
number :: String -> IO Double
number s = case readMaybe s of Just x | not (isNaN x || isInfinite x) -> pure x; _ -> fail "Invalid numeric observation"
parseBar :: String -> IO (Double,Double,Double)
parseBar s = case split s of
  [a,b,c] -> do
    t <- number a; p <- number b; v <- number c
    unless (p > 0 && v >= 0) (fail "Invalid price or volume")
    pure (t,p,v)
  _ -> fail "Malformed bar"
mean :: [Double] -> Double
mean xs = sum xs / fromIntegral (length xs)
tailN :: Int -> [a] -> [a]
tailN n xs = drop (length xs - n) xs
down8 :: Double -> Double
down8 x = fromIntegral (floor (x * 1e8) :: Integer) / 1e8
main :: IO ()
main = do
  args <- getArgs
  hash <- case args of [h] | length h == 64 && all isHexDigit h -> pure h; _ -> fail "Missing source hash"
  let root = "/workspace/btc-paper/round-1"
      dest = "/shared/competition/daily_fade2130e2e5_m1/round-1/agent-two"
      cash = 254.3937364649581 :: Double
      units = 5.69166588 :: Double
  raw <- readFile (root ++ "/bars.csv")
  let rows = lines raw
  unless (not (null rows) && head rows == "t,close,volume") (fail "Invalid bar header")
  bars <- mapM parseBar (tail rows)
  unless (length bars >= 31 && and (zipWith (<) (map (\(t,_,_) -> t) bars) (drop 1 (map (\(t,_,_) -> t) bars)))) (fail "Insufficient or unordered observations")
  let ps = map (\(_,p,_) -> p) bars
      p = last ps
      momentum n = log (p / (ps !! (length ps - 1 - n)))
      rs = tailN 20 (zipWith (\a b -> log (b/a)) ps (tail ps))
      mu = mean rs
      sigma = sqrt (sum (map (\r -> (r-mu)^2) rs) / fromIntegral (length rs - 1))
      gate = momentum 10 > 0 && momentum 30 > 0 && p > mean (tailN 20 ps)
      exposure = if gate then min 0.75 (0.025 / max 0.000001 sigma) else 0
      equity = cash + units * p
      currentExposure = units * p / equity
      delta = exposure - currentExposure
      side | not gate && units > 0 = "sell"
           | delta > 0.02 = "buy"
           | delta < (-0.02) = "sell"
           | otherwise = "hold"
      quantity | not gate && units > 0 = units
               | side == "buy" = down8 (min (equity * delta) (cash * 0.80) / (p * 1.0005 * 1.001))
               | side == "sell" = min units (down8 ((-delta) * equity / p))
               | otherwise = 0
      orders = "side,quantity\n" ++ if quantity > 0 then printf "%s,%.8f\n" side quantity else ""
      code = root ++ "/Strategy.hs#sha256=" ++ hash
      approach = "Portfolio-aware long-only momentum with unchanged 10/30-bar positive log-momentum and close-above-SMA20 gates. Target exposure min(0.75,0.025/sample volatility of last 20 log returns). Two-percentage-point absolute exposure no-rebalance band; gate failure exits all held units. Buy sizing uses decision close with fee/slippage, floors units to eight decimals and limits cash spend estimate to 80 percent of available cash. Unknown next-close gaps can still affect feasibility; no fill forecast or guaranteed arbitrary-gap budget is claimed. Volume validated, not used. Only supplied public observations and authorized settled feedback; no real trading."
      changes = "Version btc-momentum-v2-portfolio; exact source SHA256=" ++ hash ++ "; parent=btc-momentum-v1 at /workspace/btc-paper/round-0/Strategy.hs SHA256=6f9bb9823fe23fd83278c03b84145385ed4ca663b00401330bc7a72b3f7aba17; effective round=1. Hypothesis: avoiding small target-exposure adjustments can reduce turnover costs without materially changing the parent momentum exposure. Actual edits: replace initial-capital entry sizing with supplied cash/units and marked decision-price equity; apply a 0.02 absolute exposure rebalance band, full gate-failure exit, portfolio-relative trimming and 80-percent available-cash cap on incremental buys. Momentum horizons 10/30, SMA20, sigma20, risk target 0.025 and exposure cap 0.75 unchanged. Adopt settled round-0 coaching and peer tips on causal timing, cost-aware accounting, exposure-aware comparisons and exact parent/version provenance. Adopt one-change-at-a-time evaluation as a future method, not a completed ablation; portfolio plumbing is required for carry-forward accounting. Reject interpreting the peer cash lead, our benchmark advantage or one settlement as validation of reversal, continuation or volatility sizing; available coaching explicitly lacks quantitative evidence. Do not add the peer extension/volume gates because their predictive value is unverified and simultaneous filter changes would confound attribution. No historical replay, independent comparison or tested improvement is claimed. Successful compilation, execution and file readback establish operational checks only. No automatic retry, repair or resubmission."
      manifest = "{\"code_ref\":" ++ show code ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  unless (equity > 0 && quantity >= 0 && not (isNaN quantity || isInfinite quantity)) (fail "Invalid sizing")
  when (quantity > 0 && side == "buy") $ unless (quantity * p * 1.0005 * 1.001 <= cash) (fail "Decision-price cash check failed")
  when (quantity > 0 && side == "sell") $ unless (quantity <= units) (fail "Sell exceeds held units")
  createDirectoryIfMissing True dest
  writeFile (root ++ "/signal.txt") (unlines ["momentum10=" ++ show (momentum 10),"momentum30=" ++ show (momentum 30),"sigma20=" ++ show sigma,"targetExposure=" ++ show exposure,"currentExposure=" ++ show currentExposure,"side=" ++ side,"quantity=" ++ show quantity])
  writeFile (dest ++ "/orders.csv") orders
  writeFile (dest ++ "/manifest.json") manifest
  actualOrders <- readFile (dest ++ "/orders.csv")
  actualManifest <- readFile (dest ++ "/manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (fail "Submission readback mismatch")
  case lines actualOrders of
    ["side,quantity"] -> pure ()
    ["side,quantity",line] -> case split line of
      [s,q] | s == "buy" || s == "sell" -> do
        x <- number q
        unless (x > 0 && if s == "sell" then x <= units else x * p * 1.0005 * 1.001 <= cash) (fail "Readback order validation failed")
      _ -> fail "Invalid order row"
    _ -> fail "Invalid orders"
  unless (all (\c -> ord c >= 32 && ord c < 127) (code ++ approach ++ changes)) (fail "Non-ASCII manifest string")
  writeFile (root ++ "/orders.csv") actualOrders
  writeFile (root ++ "/manifest.json") actualManifest
  putStrLn ("Submission written; orders.csv and manifest.json both readback-checked. Source SHA256=" ++ hash)
  putStrLn (if quantity == 0 then "Strategy execution succeeded: valid intentional hold, not a failed execution." else "Strategy execution succeeded: nonempty submission; routine validation and settlement remain authoritative.")
