module Main where
import System.Environment
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
avg xs = sum xs / fromIntegral (length xs)
recent n xs = drop (max 0 (length xs - n)) xs
main :: IO ()
main = do
  [bars,orders,manifest,cashText,unitsText] <- getArgs
  rows <- fmap (map split . tail . lines) (readFile bars)
  let prices = map ((read :: String -> Double) . (!! 1)) rows
      returns = zipWith (\b a -> log (b/a)) (tail prices) prices
      vol = let rs = recent 40 returns; m = avg rs in sqrt (sum (map (\r -> (r-m)^2) rs) / fromIntegral (length rs-1))
      mom n = sum (recent n returns)
      bullish = mom 20 > 0 && mom 40 > 0
      cash = read cashText :: Double
      units = read unitsText :: Double
      buffer = max 0.12 (4*vol)
      quantity = cash / (last prices * (1+buffer) * 1.0005 * 1.001)
      order | bullish && units == 0 && cash > 0 = printf "buy,%.10f\n" (fromIntegral (floor (quantity*1e10) :: Integer)/1e10 :: Double)
            | not bullish && units > 0 = printf "sell,%.10f\n" units
            | otherwise = ""
  writeFile orders ("side,quantity\n" ++ order)
  writeFile manifest "{\"code_ref\":\"/workspace/competition-paper_a6d369369e81/agent-one/round-3/OriginalSelected.hs; preserved source /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs; prior selection /workspace/competition-paper_a6d369369e81/agent-one/round-2/OriginalSelected.hs\",\"approach\":\"Retain preserved OriginalStrategy unchanged: require positive trailing 20- and 40-bar log returns to hold a long, otherwise exit. Enter only when flat, with max(12%,4*sigma40) price reserve and stated fees/slippage. No rebalancing while long. The supplied 81 closes suffice for the 41-close minimum; anonymous indices require neither dates nor external prices. Volume unused. Current cash=136.0141049587272; units=10.8918639312. Both momentum signals remain positive, so hold existing units and cash; header-only orders require no next-close price assumption.\",\"changes\":\"No trading logic or parameter changes; isolated round-3 source changes only manifest metadata. Official round-2 evidence reports one trade, no failures, cash=136.0141049587272, units=10.8918639312, equity=1060.4279588095908, cumulative return=0.060427958809590794; benchmark equity=1146.4156424386579. This feedback verifies the prior entry settled, not future predictive superiority. Benchmark lag is not sufficient evidence for forced additional buying or parameter refitting. Retain the compatible strategy, without forced adaptation. Prior selection reviewed published collaboration strategies and agent-two experiment 9842f3d1-30da-4e90-8516-860919b634cb completion.json/retained-lessons.json; no calendar-dependent, long-warmup or different-execution variant transplanted. No proven improvement claimed. No current peer orders or private assets accessed; no engine changes, official reruns, extra rounds or real transactions.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
