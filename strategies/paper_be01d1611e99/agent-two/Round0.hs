module Main where
import System.Directory (renameFile)
import Text.Printf (printf)
split :: String -> [String]
split s = case break (== ',') s of
  (a,[]) -> [a]
  (a,_:b) -> a:split b
main :: IO ()
main = do
  raw <- readFile "/shared/competition/paper_be01d1611e99/round-0/bars.csv"
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
      prices = map (read . (!! 1)) rows :: [Double]
      n = length prices
      p = last prices
      momentum k = p / (prices !! (n-1-k)) - 1
      r10 = momentum 10
      r20 = momentum 20
      returns = zipWith (\a b -> log (b/a)) prices (tail prices)
      avg = sum returns / fromIntegral (length returns)
      vol = sqrt (sum (map (\x -> (x-avg)^2) returns) / fromIntegral (length returns-1))
      allocation = if r10 > 0 && r20 > 0 then 0.90 else 0
      quantity = fromIntegral (floor (allocation * 1000 / (p * 1.0005 * 1.001) * 1e8) :: Integer) / 1e8 :: Double
      out = "/shared/competition/paper_be01d1611e99/round-0/agent-two/"
      orders = "side,quantity\n" ++ if quantity > 0 then printf "buy,%.8f\n" quantity else ""
      fields =
        [("code_ref", "/workspace/strategies/paper_be01d1611e99/agent-two/Round0.hs")
        ,("approach", "Initial long-only trend rule using only supplied public bars: buy when both 10-bar and 20-bar close returns are positive. Size to 90% of cash at the decision close including 5bp buy slippage and 10bp fee, rounding units downward. Leave cash to accommodate an unknown next-close fill; feasibility is not guaranteed if the next close rises more than approximately 11.11%. No leverage. Signals are descriptive, not evidence of predictive performance. Only authoritative settlement determines results.")
        ,("changes", "Round-0 initial implementation for this rerun; no prior-round feedback or prior strategy performance used. No self-improvement claim. Preserve this source as the reviewable submission artifact.")]
      manifest = "{" ++ concat (zipWith (\i (k,v) -> (if i == (0::Int) then "" else ",") ++ show k ++ ":" ++ show v) [0..] fields) ++ "}\n"
  writeFile (out ++ "orders.csv.tmp") orders
  writeFile (out ++ "manifest.json.tmp") manifest
  renameFile (out ++ "orders.csv.tmp") (out ++ "orders.csv")
  renameFile (out ++ "manifest.json.tmp") (out ++ "manifest.json")
  printf "Public-bar analysis: %d bars; last close %.6f; 10-bar return %.2f%%; 20-bar return %.2f%%; log-return volatility %.2f%%.\n" n p (100*r10) (100*r20) (100*vol)
  putStrLn orders
  putStrLn "Agent-two round-0 orders.csv and manifest.json are ready. Strategy source preserved at /workspace/strategies/paper_be01d1611e99/agent-two/Round0.hs. This is a submission, not a settlement result."
