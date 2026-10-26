module Main where
import System.Directory
import System.Process
import Control.Monad
import Text.Printf
import Text.Read (readMaybe)
split :: Char -> String -> [String]
split c s = case break (==c) s of
  (a,[]) -> [a]
  (a,_:b) -> a:split c b
main :: IO ()
main = do
  let src = "/workspace/paper_3f23b0730060_agent_two/strategy-v1.hs"
      root = "/shared/competition/paper_3f23b0730060_m1/round-0"
      out = root ++ "/agent-two"
  csv <- readFile (root ++ "/bars.csv")
  let rows = map (split ',') (drop 1 (lines csv))
  unless (length rows == 60 && all ((==3) . length) rows) (fail "Unexpected public bar format")
  let prices = map (read . (!!1)) rows :: [Double]
      recent = drop (length prices - 30) prices
      lastPrice = last prices
      avg = sum recent / 30
      sd = sqrt (sum (map (\x -> (x-avg)^2) recent) / 29)
      z = if sd > 0 then (lastPrice-avg)/sd else 0
      trend = lastPrice / head recent - 1
      enter = z <= (-0.5) && trend >= (-0.05)
      quantity = if enter then 900 / (lastPrice * 1.0005 * 1.001) else 0
      orders = "side,quantity\n" ++ if enter then printf "buy,%.8f\n" quantity else ""
  hashOutput <- readProcess "sha256sum" [src] ""
  let hash = head (words hashOutput)
      code = "strategy-v1; sha256=" ++ hash ++ "; source=" ++ src
      approach = "Long-only 30-close mean reversion: buy when last close is at least 0.5 sample standard deviations below its 30-close mean and the 29-interval return is no worse than -5%; otherwise hold cash. Buy quantity uses 90% of cash at decision-close cost including 5 bps slippage and 10 bps fee; remaining cash buffers unknown next-close execution. No guaranteed fill-price bound is assumed."
      changes = "Version strategy-v1; source sha256=" ++ hash ++ "; parent=none; effective_round=0. Initial implementation: window=30, entry_z=-0.5, minimum_window_return=-0.05, decision_cost_allocation=0.90. Hypothesis: moderate short-horizon weakness within a non-collapsing range may mean-revert over the seven-bar scoring horizon. No prior version, backtest, parameter search, or tested improvement is claimed. Uses only supplied public closes; volume unused."
      manifest = "{\"code_ref\":" ++ show code ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  gotOrders <- readFile (out ++ "/orders.csv")
  gotManifest <- readFile (out ++ "/manifest.json")
  unless (gotOrders == orders && gotManifest == manifest) (fail "Submission readback mismatch")
  let orderLines = lines gotOrders
  unless (head orderLines == "side,quantity") (fail "Invalid order header")
  forM_ (tail orderLines) $ \row -> case split ',' row of
    ["buy",q] -> case readMaybe q :: Maybe Double of
      Just n | n > 0 && not (isNaN n || isInfinite n) && n * lastPrice * 1.0005 * 1.001 <= 1000 -> pure ()
      _ -> fail "Invalid buy quantity"
    _ -> fail "Invalid order row"
  writeFile "/workspace/paper_3f23b0730060_agent_two/submission-record.txt" (printf "last_close=%.10f mean30=%.10f sd30=%.10f z=%.6f window_return=%.6f\n" lastPrice avg sd z trend ++ orders ++ manifest)
  putStrLn (printf "Public-data signal: last=%.6f, mean30=%.6f, sample_sd=%.6f, z=%.4f, window_return=%.4f%%." lastPrice avg sd z (100*trend))
  putStrLn ("Source SHA-256: " ++ hash ++ "; parent=none; effective round=0.")
  putStrLn ("Submission readback verified: " ++ out ++ "/orders.csv and manifest.json.")
  putStr orders
  putStrLn "Initial mean-reversion rule, not a demonstrated improvement. Unknown next-close execution remains subject to routine feasibility validation; only routine settlement establishes performance."
