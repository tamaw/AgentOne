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
  writeFile manifest "{\"code_ref\":\"/workspace/competition-paper_a6d369369e81/agent-one/OriginalSelected.hs; original source /shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs; selection evidence /shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/summary.txt; /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/completion.json and retained-lessons.json\",\"approach\":\"Select preserved OriginalStrategy: enter only with positive trailing 20- and 40-bar log returns, exit when either fails; reserve max(12%,4*sigma40) for next-close fixed-quantity buys including 5bps slippage and 10bps fee. Requires 41 closes; supplied 67 closes suffice. Index-only momentum and volatility require no dates or real prices. Volume unused. Unknown next fill cannot guarantee buy feasibility; no-trade is fully feasible with cash=1000, units=0.\",\"changes\":\"Trading logic and parameters unchanged from published OriginalStrategy.hs. Only isolated source/output paths and this manifest revised. Reviewed authorized StrategyV1.hs, v2/StrategyV2.hs and v2/summary.txt: no robust transferable improvement; ConsensusV1 needs 121 closes. Recent agent-two experiment completion.json and retained-lessons.json identify weekly-calendar/long-warmup and fill-time-sizing differences; not transplanted or claimed superior. Round-0 official evidence: cash=1000, units=0, equity=1000, zero trades/failures; benchmark=1015.6128279230027. One favorable benchmark interval does not justify forced entry or parameter fitting. Current 20-bar momentum is negative, so retain cash. No current peer orders or private assets inspected; no official rerun requested.\"}\n"
  printf "20-bar log return=%.6f; 40-bar log return=%.6f; daily log volatility=%.6f; next-close reserve=%.6f\n" (mom 20) (mom 40) vol buffer
  putStr ("Submitted orders:\nside,quantity\n" ++ order)
