module Main where
import System.Directory
import Text.Printf
import Data.Char (isAscii, isControl)
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  let root = "/workspace/artifacts/paper_a6d369369e81/agent-two/round-1"
      target = "/shared/competition/paper_a6d369369e81/round-1/agent-two"
      baseline = "/shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/preserved/preserved-baseline-submission.hs"
      lessons = "/shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/retained-lessons.json"
  raw <- readFile "/shared/competition/paper_a6d369369e81/round-1/bars.csv"
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
      ps = map (read . (!!1)) rows :: [Double]
      n = length ps
  if n < 22 || any (\x -> x <= 0 || isNaN x || isInfinite x) ps then fail "Invalid or insufficient public observations" else pure ()
  let p = last ps
      r7 = p / (ps !! (n-8)) - 1
      r21 = p / (ps !! (n-22)) - 1
      entry = r7 > 0 && r21 > 0
  if entry then fail "Expected hold condition changed; do not submit an unreviewed buy" else pure ()
  let orders = "side,quantity\n"
      approach = printf "Preserved dual-horizon momentum entry: initiate long only if both completed-close 7-bar and 21-bar returns are positive. At t=%s close=%.12f, r7=%.6f%% and r21=%.6f%%. Entry condition fails; retain cash=1000 and units=0. Header-only order is deliberate and feasible at every next-close fill, with no fee or slippage incurred. Uses only supplied t,close,volume; 22 observations suffice, no dates or long warmup required." (head (last rows)) p (100*r7) (100*r21) :: String
      changes = "Selected actual preserved baseline source " ++ baseline ++ "; limitations from " ++ lessons ++ ". No signal changes, optimization, or improvement claim. Isolated implementation recalculates 7/21 returns from this routine's public observations instead of copying historical manifest numbers. Weekly calendar and 200-session variants not adopted: no dates, insufficient warmup, incompatible sizing/execution and no established superiority. Round-0 public evidence reports cash=1000, units=0, equity=1000, versus benchmark equity=1015.6128279230027; one missed positive interval does not justify forcing a trade or replacing the rule. No peer current orders or private assets used. Exactly one five-round paper competition; no extra rounds or reruns."
      fields = [("code_ref",root ++ "/Submission.hs"),("approach",approach),("changes",changes)]
      pair (k,v) = show k ++ ":" ++ show v
      manifest = "{" ++ foldr1 (\a b -> a ++ "," ++ b) (map pair fields) ++ "}\n"
  if not (all (all (\c -> isAscii c && not (isControl c)) . snd) fields) then fail "Manifest strings not JSON-safe ASCII" else pure ()
  createDirectoryIfMissing True target
  writeFile (root ++ "/observations.csv") raw
  writeFile (root ++ "/orders.csv") orders
  writeFile (root ++ "/manifest.json") manifest
  writeFile (target ++ "/orders.csv") orders
  writeFile (target ++ "/manifest.json") manifest
  a <- readFile (target ++ "/orders.csv")
  b <- readFile (target ++ "/manifest.json")
  if a /= orders || lines a /= ["side,quantity"] || b /= manifest || map fst fields /= ["code_ref","approach","changes"] then fail "Submission readback validation failed" else pure ()
  putStrLn (printf "Round 1/5 ready: hold cash 1000, units 0. Public t=%s; 7-bar return %.6f%%; 21-bar return %.6f%%." (head (last rows)) (100*r7) (100*r21))
  putStrLn ("Both orders.csv and manifest.json written and readback validated in " ++ target ++ ". Preserved baseline retained without signal changes; only routine settlement counts.")
