module Main where
import System.Directory
import Control.Monad
import Text.Read (readMaybe)
import Text.Printf
split :: String -> [String]
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
mean xs = sum xs / fromIntegral (length xs)
finite x = not (isNaN x || isInfinite x)
main :: IO ()
main = do
  let dir = "/shared/competition/match_7b085c33c151/round-1/agent-two"
      code = "/workspace/competition/agent-two/MomentumV1.hs"
      cash = 1000 :: Double
  raw <- readFile "/shared/competition/match_7b085c33c151/round-1/bars.csv"
  let rows = map split (drop 1 (lines raw))
  unless (not (null rows) && all ((==3) . length) rows) (fail "Invalid public bars")
  ps <- mapM (\r -> maybe (fail "Invalid close") pure (readMaybe (r !! 1) :: Maybe Double)) rows
  unless (length ps >= 21 && all (\p -> finite p && p > 0) ps) (fail "Insufficient or invalid closes")
  let p = last ps
      sma = mean (drop (length ps - 20) ps)
      mom = p / (ps !! (length ps - 8)) - 1
      active = p > sma && mom > 0
      q = if active then 0.85 * cash / (p * 1.0005 * 1.001) else 0
      quantity = printf "%.10f" q :: String
      orders = "side,quantity\n" ++ if active then "buy," ++ quantity ++ "\n" else ""
      approach = "Long-only public-close momentum: close above 20-bar SMA and positive 7-bar return; allocate 85% of cash at decision price after estimated fees and slippage, retaining a next-close gap reserve. No leverage. Unknown fill can still make a buy infeasible."
      changes = "Independent competition-native momentum revision; no offline AAPL results used as evidence of improvement. Round 1 starts with cash 1000 and zero units."
      manifest = "{\n  \"code_ref\": " ++ show code ++ ",\n  \"approach\": " ++ show approach ++ ",\n  \"changes\": " ++ show changes ++ "\n}\n"
  createDirectoryIfMissing True dir
  writeFile (dir ++ "/orders.csv") orders
  writeFile (dir ++ "/manifest.json") manifest
  actualOrders <- readFile (dir ++ "/orders.csv")
  actualManifest <- readFile (dir ++ "/manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (fail "Submission readback mismatch")
  let parsed = map split (drop 1 (lines actualOrders))
  unless (head (lines actualOrders) == "side,quantity") (fail "Invalid orders header")
  forM_ parsed $ \r -> case r of
    ["buy",n] -> case readMaybe n :: Maybe Double of
      Just x | finite x && x > 0 && x * p * 1.0005 * 1.001 <= cash -> pure ()
      _ -> fail "Invalid quantity or decision-price affordability"
    _ -> fail "Invalid order row"
  unless (all (\s -> not (null s) && all (\c -> c >= ' ' && c <= '~') s) [code,approach,changes]) (fail "Invalid manifest strings")
  printf "Public signal: close %.6f, SMA20 %.6f, 7-bar return %.2f%%.\n" p sma (100*mom)
  putStrLn ("Submission ready: " ++ dir ++ "/orders.csv and manifest.json written and readback validated.")
  if active then do
    putStrLn ("Order: buy " ++ quantity ++ " units (simulated only).")
    printf "Buy fits cash if next close is at most %.6f; actual feasibility and equity are determined only by settlement.\n" (cash / ((read quantity :: Double) * 1.0005 * 1.001))
  else putStrLn "Order: hold (header-only)."
