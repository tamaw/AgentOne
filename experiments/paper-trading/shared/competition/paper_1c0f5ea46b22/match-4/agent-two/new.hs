module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
mean xs = sum xs / fromIntegral (length xs)
main :: IO ()
main = do
  [bars,out,source,hash] <- getArgs
  raw <- readFile bars
  let rows = map split (drop 1 (lines raw))
      ps = [read (r !! 1) :: Double | r <- rows]
      n = length ps
  unless (n >= 22 && all (>0) ps) (error "Insufficient or invalid public prices")
  let p = last ps
      r7 = log (p / (ps !! (n-8)))
      r21 = log (p / (ps !! (n-22)))
      trailing = drop (n-21) ps
      rs = zipWith (\a b -> log (b/a)) trailing (tail trailing)
      mu = mean rs
      sigma = sqrt (mean (map (\x -> (x-mu)^2) rs))
      hurdle = 0.003 + 0.25*sigma*sqrt 6
      enter = r7 > hurdle && r21 > 0 && p > mean (drop (n-20) ps)
      qty = 250 / (p*1.0005*1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" qty else ""
      approach = "Long-only multi-horizon momentum; r7 > 0.003+0.25*sigma20*sqrt(6), r21>0, latest close above trailing 20-close mean. Warmup 22 closes. Quantity 250/(latest_close*1.0005*1.001), ten decimals; otherwise cash. Risk reduction via smaller exposure, not a new alpha signal. Reserve is not a bound on unknown next-close gaps."
      changes = "Offline match4 risk-sizing proposal momentum-v1-budget250-m4-offline. Parent momentum-v1-budget500-m4-metadata. Only quantity budget changes from 500 to 250; signal, 22-close warmup, ten-decimal rounding and next-close execution conventions unchanged. Metadata updated to describe this proposal; testing and selection are recorded separately in improvement.json. No live trading, matched judge replay, independent judge verification or future-performance guarantee."
      manifest = "{\"code_ref\":" ++ show (source ++ "#sha256=" ++ hash) ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  a <- readFile (out ++ "/orders.csv")
  b <- readFile (out ++ "/manifest.json")
  unless (a == orders && b == manifest) (error "Offline readback mismatch")
