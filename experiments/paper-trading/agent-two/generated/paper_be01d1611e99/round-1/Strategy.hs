module Main where
import System.Directory
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  let root = "/workspace/artifacts/paper_be01d1611e99/round-1"
      target = "/shared/competition/paper_be01d1611e99/round-1/agent-two"
      cash = 109.51688699881703 :: Double
      units = 7.43233156 :: Double
  raw <- readFile "/shared/competition/paper_be01d1611e99/round-1/bars.csv"
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
      prices = map (read . (!! 1)) rows :: [Double]
      n = length prices
  if n < 20 then fail "Insufficient public observations" else pure ()
  let lastPrice = last prices
      sma20 = sum (drop (n-20) prices) / 20
      momentum10 = lastPrice / (prices !! (n-11)) - 1
      momentum7 = lastPrice / (prices !! (n-8)) - 1
      bearish = lastPrice < sma20 && momentum10 < 0
      orders = "side,quantity\n" ++ if bearish then "sell," ++ printf "%.8f" units ++ "\n" else ""
      approach :: String
      approach = printf "Apply the prior 20-bar SMA / 10-bar momentum long-only filter to public closes only. At t=%s, close=%.10f, SMA20=%.10f, 10-bar return=%.6f%%, and 7-bar return=%.6f%%. Sell existing units only when close is below SMA20 and 10-bar momentum is negative; otherwise retain the position without adding exposure. Current cash=%.14f and units=%.8f. %s Avoiding a new buy also avoids infeasibility from an unknown next-close fill. No future prices or competitor submissions were used." (head (last rows)) lastPrice sma20 (100*momentum10) (100*momentum7) cash units (if bearish then "Both bearish conditions hold: liquidate all held units." else "The joint bearish condition does not hold: submit no trade and avoid turnover costs.")
      changes = "Reused the filter definition preserved in /workspace/pt-v3-dryrun-0ecd98594047-round0.hs; this is not the current competition's round-0 strategy artifact. Adapted its cash-only entry example into an exit/retain rule for this round's existing position, with no additional buying. Authoritative round-0 evidence reports equity 985.4536584780269 and a -1.454634152197309% round return. The new seven bars soften short-term momentum but one adverse settlement does not establish that a new strategy improves outcomes. No optimization, validated self-improvement, or performance guarantee is claimed."
      manifest = "{\"code_ref\":" ++ show (root ++ "/Strategy.hs") ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True root
  createDirectoryIfMissing True target
  writeFile (root ++ "/observations.csv") raw
  writeFile (root ++ "/orders.csv") orders
  writeFile (root ++ "/manifest.json") manifest
  writeFile (target ++ "/orders.csv") orders
  writeFile (target ++ "/manifest.json") manifest
  checkOrders <- readFile (target ++ "/orders.csv")
  checkManifest <- readFile (target ++ "/manifest.json")
  if checkOrders /= orders || checkManifest /= manifest then fail "Submission readback failed" else pure ()
  putStrLn (printf "Round 1 submission ready: %s Close %.6f; SMA20 %.6f; 10-bar return %.4f%%; 7-bar return %.4f%%." (if bearish then "sell 7.43233156 units." else "no trade; retain 7.43233156 units and cash 109.51688699881703.") lastPrice sma20 (100*momentum10) (100*momentum7))
  putStrLn ("Orders and required manifest written to " ++ target ++ ". Strategy and input snapshot preserved at " ++ root ++ ". Only routine settlement determines results.")
