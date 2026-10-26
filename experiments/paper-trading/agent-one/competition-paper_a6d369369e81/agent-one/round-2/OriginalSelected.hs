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
  writeFile manifest "{\"code_ref\":\"/workspace/competition-paper_a6d369369e81/agent-one/round-2/OriginalSelected.hs; preserved source /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs; prior selection /workspace/competition-paper_a6d369369e81/agent-one/round-1-submission.json\",\"approach\":\"Retain preserved OriginalStrategy unchanged: long only when both trailing 20- and 40-bar log returns are positive; exit otherwise. Fixed-unit buys reserve max(12%,4*sigma40), with 5bps slippage and 10bps fee included. Supplied 74 closes suffice for its 41-close minimum; anonymous indices require neither dates nor external prices. Volume unused. Cash=1000 and units=0. Unknown next-close prices prevent guaranteed buy feasibility; reserve limits but does not eliminate rejection risk.\",\"changes\":\"No trading logic or parameter changes. Isolated round-2 source differs only in manifest metadata; no other task source modified. Official round-1 evidence: cash=1000, units=0, equity=1000, no trades or failures; benchmark equity=1105.6214724983752. Benchmark outperformance is observed opportunity cost, not sufficient evidence to force entry or refit parameters. Both current 20- and 40-bar momentum are now positive, so the unchanged rule enters with its existing execution reserve. Prior review of published collaboration strategies and agent-two experiment 9842f3d1-30da-4e90-8516-860919b634cb completion.json/retained-lessons.json found calendar/long-warmup/execution incompatibilities; none transplanted. No proven improvement claimed, no peer current orders or private assets accessed, and no official rerun or additional competition requested.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
