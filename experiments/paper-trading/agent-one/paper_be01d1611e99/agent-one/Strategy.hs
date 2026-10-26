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
  writeFile manifest "{\"code_ref\":\"/workspace/paper_be01d1611e99/agent-one/Strategy.hs; preserved round-0 source and public bars in /workspace/paper_be01d1611e99/agent-one/round-0/\",\"approach\":\"Long-only trend heuristic: require positive trailing 20- and 40-bar log returns. Initially buy using cash divided by the latest close, buy slippage and fee factors, and an execution-price reserve of max(12%, four trailing-40-bar log-return standard deviations). Hold an existing long while both trends remain positive, otherwise liquidate. Unknown next-close execution means the reserve reduces but cannot eliminate infeasibility risk. Volume is not used because no reliable predictive relationship has been established.\",\"changes\":\"Initial round-0 strategy, using only supplied public history and stated cash/units. No prior strategy or settlement feedback used; no claim of validated predictive advantage or self-improvement. Code and observations preserved for review and subsequent round comparison.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
