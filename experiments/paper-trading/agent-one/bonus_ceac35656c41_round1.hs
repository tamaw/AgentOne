module Main where
import Data.List (foldl')
import System.Process (readProcess)
import System.Directory (createDirectoryIfMissing)
import Text.Printf (printf)
split s = case break (== ',') s of { (a,[]) -> [a]; (a,_:b) -> a:split b }
main :: IO ()
main = do
  let root = "/shared/competition/bonus_ceac35656c41/round-1/"
      source = "/workspace/bonus_ceac35656c41_round1.hs"
      out = root ++ "agent-one/"
      held = 6.828306 :: Double
  rows <- tail . lines <$> readFile (root ++ "bars.csv")
  let prices = map ((read :: String -> Double) . (!! 1) . split) rows
      ema n = foldl' (\a p -> a + 2/(n+1)*(p-a)) (head prices) (tail prices)
      fast = ema 10
      slow = ema 20
      p = last prices
      retained = if p >= slow && fast >= slow then 1 else if fast >= slow then 0.5 else 0
      sell = held * (1-retained)
      orders = "side,quantity\n" ++ if sell > 0 then printf "sell,%.6f\n" sell else ""
  srcHash <- head . words <$> readProcess "sha256sum" [source] ""
  barsHash <- head . words <$> readProcess "sha256sum" [root ++ "bars.csv"] ""
  let codeRef = source ++ "#sha256=" ++ srcHash
      approach = "Offline long-only trend-risk overlay. EMA10 remains above EMA20, but the decision close is below both; retain half the carried units and sell the other half at the next close. No buys, leverage, or synthetic-baseline targeting. Uses public t=0..66 bars only; bars SHA256=" ++ barsHash
      changes = "New round-1 Haskell decision source; no claim of modifying or reproducing the round-0 source. Prior official feedback reports cash 86.37197770276859, units 6.828306 and equity 981.8613461707065. Adaptation reduces exposure after the latest downside move while retaining participation in the still-positive intermediate trend. Fixed EMA10/EMA20 overlay is a heuristic, not a fitted or validated forecast. No private or peer assets accessed; no infrastructure changes."
      manifest = "{\"code_ref\":" ++ show codeRef ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "orders.csv") orders
  writeFile (out ++ "manifest.json") manifest
  printf "Submitted sell %.6f units; remaining %.6f units before settlement. Close %.6f, EMA10 %.6f, EMA20 %.6f.\n" sell (held-sell) p fast slow
