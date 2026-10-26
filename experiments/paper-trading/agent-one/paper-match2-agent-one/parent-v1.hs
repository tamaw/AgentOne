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
      enter = score > 0.006 && r5 > 0
      units = 500 / (latest * 1.10 * 1.0005 * 1.001)
      orders = "side,quantity\n" ++ if enter then printf "buy,%.10f\n" units else ""
      approach = "Public-close-only long/cash trend gate: enter only when mean 10/20-bar log return exceeds 0.006 and 5-bar log return is positive. Otherwise retain cash. Entry targets half of capital with a 10% next-close buffer, which is not a guaranteed bound. No leverage; next-close execution costs acknowledged. Volume not used. Seven-bar outcome is unknown."
      changes = "Initial own executable source v1; exact source SHA-256 in code_ref; parent=none; effective=match1 round0. Hypothesis: avoid paying costs for long exposure during negative intermediate momentum. Actual initial rules: equal-weight 10/20-bar log momentum >0.006 and positive 5-bar momentum; otherwise hold cash. No edits to a prior strategy and no tested improvement claimed. Both prior improvement documents: none supplied (Previous evidence: none), and no improvement documents found in public competition paths; there are no prior peer tips to adopt or reject. peer_tip_decisions records this first-match absence. No backtest or independent same-window replay performed."
      manifest = "{\"code_ref\":" ++ json code ++ ",\"approach\":" ++ json approach ++ ",\"changes\":" ++ json changes ++ "}\n"
      decisions = "{\"match\":1,\"round\":0,\"prior_improvement_documents\":[],\"peer_tip_decisions\":[],\"rationale\":\"First match; previous evidence is none and no prior public improvement documents were available. No peer tip exists to adopt or reject. Public general tips are due between matches, not during the current match.\"}\n"
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
