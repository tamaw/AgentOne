module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Read
import Data.List
import Text.Printf
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
mean xs = sum xs / fromIntegral (length xs)
tailN n xs = drop (length xs - n) xs
main :: IO ()
main = do
  [hash] <- getArgs
  unless (length hash == 64) (fail "Missing source hash")
  let root = "/workspace/btc-paper/round-0"
      dest = "/shared/competition/daily_fade2130e2e5_m1/round-0/agent-two"
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
      quantity = fromIntegral (floor ((1000 * exposure / (p * 1.0005 * 1.001)) * 1e8) :: Integer) / 1e8 :: Double
      orders = "side,quantity\n" ++ if quantity > 0 then printf "buy,%.8f\n" quantity else ""
      code = root ++ "/Strategy.hs#sha256=" ++ hash
      approach = "Long-only 10/30-bar log-momentum consensus with close above 20-bar arithmetic mean. Exposure min(0.75,0.025/sample standard deviation of last 20 log returns); cash sizing uses decision close and stated fee/slippage, rounded down to 8 decimals. Unspent cash buffers unknown next-close gaps; feasibility is not guaranteed for arbitrary gaps. Volume is validated but not used. No real trading."
      changes = "Version btc-momentum-v1; exact source SHA256=" ++ hash ++ "; parent=none; effective round=0. Hypothesis: multi-horizon momentum may persist across the seven-bar mark after the observed breakout, while volatility scaling limits exposure. Initial implementation: 10/30-bar positive momentum gate, 20-bar mean gate, 20-return sample volatility, daily risk target 0.025, exposure cap 0.75. No prior public coaching or tips were supplied; none adopted or rejected. This is an untested baseline, not evidence of improvement; execution and readback validation are not performance testing."
      manifest = "{\"code_ref\":" ++ show code ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True dest
  writeFile (root ++ "/signal.txt") (unlines ["momentum10=" ++ show (momentum 10),"momentum30=" ++ show (momentum 30),"sigma20=" ++ show sigma,"exposure=" ++ show exposure,"quantity=" ++ show quantity])
  writeFile (dest ++ "/orders.csv") orders
  writeFile (dest ++ "/manifest.json") manifest
  actualOrders <- readFile (dest ++ "/orders.csv")
  actualManifest <- readFile (dest ++ "/manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (fail "Submission readback mismatch")
  case lines actualOrders of
    ["side,quantity"] -> pure ()
    ["side,quantity",line] -> case split line of
      ["buy",q] -> do
        x <- number q
        unless (x > 0 && x * p * 1.0005 * 1.001 <= 1000) (fail "Invalid decision-price sizing")
      _ -> fail "Invalid order format"
    _ -> fail "Invalid orders"
  writeFile (root ++ "/orders.csv") actualOrders
  writeFile (root ++ "/manifest.json") actualManifest
  putStrLn ("Submission written and both files readback-checked. Source SHA256=" ++ hash)
  putStrLn (if quantity == 0 then "Execution succeeded: valid intentional hold." else "Execution succeeded: nonempty submission; settlement remains authoritative.")
