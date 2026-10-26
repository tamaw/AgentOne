module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
json :: String -> String
json s = "\"" ++ concatMap esc s ++ "\"" where
  esc '\"' = "\\\""
  esc '\\' = "\\\\"
  esc '\n' = "\\n"
  esc c = [c]
main :: IO ()
main = do
  [bars,out,code] <- getArgs
  input <- readFile bars
  let rows = map split (drop 1 (lines input))
      prices = map (read . (!! 1)) rows :: [Double]
      n = length prices
  unless (n >= 21 && all (>0) prices) (fail "Invalid public close history")
  let latest = last prices
      ret k = log (latest / (prices !! (n-1-k)))
      r5 = ret 5
      r10 = ret 10
      r20 = ret 20
      score = 0.5*r10 + 0.5*r20
      enter = r10 > 0.006 && r5 > 0
      units = 500 / (latest * 1.10 * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" units else ""
      approach = "Candidate v2: long/cash fast trend gate r10>0.006 and r5>0; unchanged half-capital sizing, 10% uncertain-fill buffer, fees and slippage. Public closes only."
      changes = "Offline candidate v2 derived from preserved v1: replace mean 10/20-bar return gate with 10-bar return gate at the same 0.006 threshold; all sizing and input validation unchanged. Effective only if selected after public-prefix comparison; no judge verification or guaranteed next-fill feasibility."
      manifest = "{\"code_ref\":" ++ json code ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n"
      decisions = "{\"stage\":\"offline_candidate_evaluation\",\"peer_tip_decisions\":[],\"rationale\":\"Candidate snapshot; no current orders shared. Revisit peer tips before later submission.\"}\n"
  createDirectoryIfMissing True out
  writeFile (out ++ "/orders.csv") orders
  writeFile (out ++ "/manifest.json") manifest
  writeFile (out ++ "/peer_tip_decisions.json") decisions
  ordersRead <- readFile (out ++ "/orders.csv")
  manifestRead <- readFile (out ++ "/manifest.json")
  decisionsRead <- readFile (out ++ "/peer_tip_decisions.json")
  unless (ordersRead == orders && manifestRead == manifest && decisionsRead == decisions) (fail "Readback mismatch")
  unless (take 1 (lines ordersRead) == ["side,quantity"]) (fail "Incorrect orders header")
  printf "Public observations: n=%d; close=%.8f; log returns 5/10/20=%.6f/%.6f/%.6f; score=%.6f.\n" n latest r5 r10 r20 score
  putStrLn (if enter then "Buy generated; unknown next-close feasibility remains a risk." else "Header-only hold verified: no fill-feasibility risk; cash remains 1000 and units 0 before settlement.")
  putStrLn "Manifest and peer-tip decisions written and exact-readback checked. No performance test claimed."
