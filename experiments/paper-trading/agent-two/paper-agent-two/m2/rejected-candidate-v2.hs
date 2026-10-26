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
      enter = r7 > hurdle
      qty = 850 / (p*1.0005*1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" qty else ""
      approach = "v2-candidate long-only short-horizon momentum gate: enter only if trailing 7-bar log return exceeds 0.003+0.25*20-return population volatility*sqrt(6). Removes both long-trend confirmations; all other execution assumptions unchanged. Otherwise retain cash. Entry uses 85% of decision-close cost-adjusted cash, reserving 15% for uncertain next-close fills; this buffer is not a guaranteed feasibility bound. No leverage or shorting."
      changes = "source_version=momentum-v2-candidate; parent=momentum-v1; parent_sha256=a3f09a28bb1cbd4a25224422f4cff1541b1747002c675241174cf0c2d3194e04; evaluation_only=true; removes_21bar_positive_and_above_20close_mean_confirmations; retains_7bar_volatility_hurdle_and_85percent_budget; paired_public_history_replay_is_not_independent_judge_verification; no_live_orders_or_match_settlement_claim; candidate_sha256=" ++ hash
      manifest = "{\n\"code_ref\":" ++ show (source ++ "#sha256=" ++ hash) ++ ",\n\"approach\":" ++ show approach ++ ",\n\"changes\":" ++ show changes ++ ",\n\"peer_tip_decisions\":[],\n\"peer_tip_context\":\"First match; no previous improvement documents supplied and no peer tips available.\"\n}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  a <- readFile (out ++ "/orders.csv")
  b <- readFile (out ++ "/manifest.json")
  unless (a == orders && b == manifest) (error "Submission readback mismatch")
  printf "Public-data analysis: %d bars; 7-bar return %.4f; 21-bar return %.4f; daily volatility %.4f.\n" n r7 r21 sigma
  putStrLn "Submission written and exact-content readback verified. No settlement or performance claim."
