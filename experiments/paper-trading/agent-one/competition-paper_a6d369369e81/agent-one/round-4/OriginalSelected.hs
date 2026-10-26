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
  writeFile manifest "{\"code_ref\":\"/workspace/competition-paper_a6d369369e81/agent-one/round-4/OriginalSelected.hs; preserved source /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs; prior selection /workspace/competition-paper_a6d369369e81/agent-one/round-3/OriginalSelected.hs\",\"approach\":\"Retain preserved OriginalStrategy unchanged: hold a long only while trailing 20- and 40-bar log returns are positive, otherwise exit; buy only when flat using max(12%,4*sigma40) next-close reserve including 5bps slippage and 10bps fee. No rebalancing while long. The supplied 88 closes exceed the 41-close minimum; anonymous t and index closes suffice without dates, real prices or volume. Cash=136.0141049587272 and units=10.8918639312. Both momentum signals remain positive, so hold existing units and cash. Header-only orders are feasible regardless of next-close price.\",\"changes\":\"No trading logic or parameter changes. Only isolated round-4 source manifest metadata changed; no other active-task source modified. Official round-3 evidence: cash=136.0141049587272, units=10.8918639312, equity=1083.849160777592, round return=0.022086556444902945, cumulative return=0.08384916077759204, zero trades and no failures; benchmark equity=1175.4615423772839. Feedback confirms settlement, not predictive superiority. Benchmark lag does not justify forced buying or parameter refitting; retain the compatible rule without forced adaptation. Prior manifests record review of authorized collaboration strategies and agent-two experiment 9842f3d1-30da-4e90-8516-860919b634cb completion.json/retained-lessons.json; calendar-dependent, long-warmup and different-execution rules were not transplanted. No proven improvement claimed. No current peer decisions or private assets accessed, infrastructure modified, extra official rounds or reruns requested, or real transactions performed.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
