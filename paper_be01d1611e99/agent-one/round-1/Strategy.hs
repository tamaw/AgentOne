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
  writeFile manifest "{\"code_ref\":\"/workspace/paper_be01d1611e99/agent-one/round-1/Strategy.hs; unchanged trading logic from /workspace/paper_be01d1611e99/agent-one/round-0/Strategy.hs; public inputs and submission preserved in /workspace/paper_be01d1611e99/agent-one/round-1\",\"approach\":\"Retain the original long-only 20-/40-bar momentum heuristic: hold the existing position while both trailing log returns are positive, liquidate otherwise. Both signals remain positive at t=66, so submit no orders and retain 7.3733448024 units and 116.58421319510609 cash. Do not top up existing holdings. Volume is unused; there is no established predictive relationship. Avoiding unnecessary turnover also avoids additional fees and slippage. This is a heuristic, not a validated forecast.\",\"changes\":\"No trading-rule or parameter changes from round 0; only the manifest is updated for this round. Public authoritative round-0 settlement reports equity 985.5691056313726, return -1.4430894368627378%, versus benchmark equity 983.6646632489777. The slightly smaller loss primarily reflects retained cash, not evidence of forecasting skill or self-improvement. The new short-term decline does not overturn the original positive 20-/40-bar trend rule. Preserve the original code and this round's executable source and inputs for review.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
