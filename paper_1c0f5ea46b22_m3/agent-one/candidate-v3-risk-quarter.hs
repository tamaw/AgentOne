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
      units = 250 / (latest * 1.10 * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" units else ""
      approach = "Offline v3-risk-quarter: unchanged r10>0.006 and r5>0 with 21-close warmup; decision-close budget reduced from 500 to 250 dollars; same 1.10 buffer, 5bp slippage, 10bp fee and rounding. Long/cash, no leverage."
      changes = "Parent is exact preserved v2-match2 executable. Only algorithmic change: halve entry budget. Risk reduction selected for paired public development replay after match-2 loss; not independent evidence or guaranteed future superiority. No live submission. Later adaptation allowed with truthful provenance."
      manifest = "{\"code_ref\":" ++ json code ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n"
      decisions = "{\"stage\":\"offline_match2_improvement\",\"peer_tip_decisions\":[],\"rationale\":\"No new peer-tip adoption claims; general public tips are in improvement.json.\"}\n"
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
