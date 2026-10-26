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
      enter = r7 > hurdle && p > mean (drop (n-20) ps)
      qty = 500 / (p*1.0005*1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" qty else ""
      approach = "Offline candidate: same 22-close warmup, 500-dollar budget, 7-bar volatility-adjusted momentum and above-20-close-mean gate as parent; remove only positive 21-bar momentum gate. Fixed sizing reserve is heuristic, no leverage."
      changes = "momentum-v2-no-r21-m3-offline; direct parent is preserved old.hs, exact match3 submitted source. Single proposed signal change removes r21>0. Candidate under offline evaluation only; no judge verification. Hypothesis: At fixed 500-dollar entry budget, removing only the positive 21-bar momentum confirmation will improve mean seven-bar marked return by at least 0.0005 (5 basis points of initial capital), while maximum episode marked drawdown stays at or below 0.025 and rejected fills do not increase, on identical public origins 21..52. Otherwise retain the parent."
      manifest = "{\"code_ref\":" ++ show (source ++ "#sha256=" ++ hash) ++ ",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  a <- readFile (out ++ "/orders.csv")
  b <- readFile (out ++ "/manifest.json")
  unless (a == orders && b == manifest) (error "Submission readback mismatch")
  printf "Public-data analysis: %d bars; 7-bar return %.4f; 21-bar return %.4f; daily volatility %.4f.\n" n r7 r21 sigma
  putStrLn "Submission written and exact-content readback verified. No settlement or performance claim."
