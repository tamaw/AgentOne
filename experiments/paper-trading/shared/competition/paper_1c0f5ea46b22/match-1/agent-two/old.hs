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
      qty = 850 / (p*1.0005*1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" qty else ""
      approach = "v1 long-only multi-horizon momentum gate: enter only if trailing 7-bar log return exceeds 0.003+0.25*20-return population volatility*sqrt(6), trailing 21-bar return is positive, and latest close exceeds its 20-close mean. Otherwise retain cash. Entry uses 85% of decision-close cost-adjusted cash, reserving 15% for uncertain next-close fills; this buffer is not a guaranteed feasibility bound. No leverage or shorting."
      changes = "source_version=momentum-v1; sha256=" ++ hash ++ "; parent=none; effective=match1/round0; hypothesis=positive multi-horizon trends may persist over the six fill-to-mark intervals, while weak/downward trends do not justify fees and exposure. Initial rules: 7/21-bar momentum, 20-close mean, volatility-adjusted 0.003 hurdle, 85% entry budget. No prior improvement documents were supplied (previous evidence: none); there are no applicable prior peer tips to adopt or reject. These are untested initial rules, not demonstrated improvement. Only source execution and submission readback are checked; no independent same-window replay or settlement claim."
      manifest = "{\n\"code_ref\":" ++ show (source ++ "#sha256=" ++ hash) ++ ",\n\"approach\":" ++ show approach ++ ",\n\"changes\":" ++ show changes ++ ",\n\"peer_tip_decisions\":[],\n\"peer_tip_context\":\"First match; no previous improvement documents supplied and no peer tips available.\"\n}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  a <- readFile (out ++ "/orders.csv")
  b <- readFile (out ++ "/manifest.json")
  unless (a == orders && b == manifest) (error "Submission readback mismatch")
  printf "Public-data analysis: %d bars; 7-bar return %.4f; 21-bar return %.4f; daily volatility %.4f.\n" n r7 r21 sigma
  putStrLn "Submission written and exact-content readback verified. No settlement or performance claim."
