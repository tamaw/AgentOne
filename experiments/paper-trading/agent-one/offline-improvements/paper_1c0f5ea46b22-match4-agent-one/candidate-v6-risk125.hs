module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  [bars,out,code] <- getArgs
  input <- readFile bars
  let prices = map (read . (!!1) . split) (drop 1 (lines input)) :: [Double]
      n = length prices
  unless (n>=21 && all (\p -> p>0 && not (isNaN p || isInfinite p)) prices) (fail "Invalid public close history")
  let latest = last prices
      ret k = log (latest / (prices !! (n-1-k)))
      r5 = ret 5
      r10 = ret 10
      enter = r10 > 0.006 && r5 > 0
      units = 125 / (latest * 1.10 * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" units else ""
      approach = "Offline risk-budget proposal v6-risk125: unchanged 21-close warmup, r10>0.006 and r5>0. Long only. Quantity=125/(latest_close*1.10*1.0005*1.001), ten decimal places. Reset capital=1000; next-close entry and seven-bar marking. Buffer is heuristic, not a gap guarantee."
      changes = "Offline-only proposal, parent v5-match4-metadata preserved byte-for-byte. Only trading parameter changed is nominal budget 250 to 125; signal, warmup, rounding, costs and fills unchanged. Motivated by public match-4 absolute loss despite positive benchmark gap and reused negative development results. Reused data are not held out; expected exposure scaling is not alpha or independent judge verification. Matched judge replay unavailable. No live deployment or current orders shared."
      manifest = "{\"code_ref\":" ++ show code ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  a <- readFile (out ++ "/orders.csv")
  b <- readFile (out ++ "/manifest.json")
  unless (a==orders && b==manifest) (fail "Output readback mismatch")
