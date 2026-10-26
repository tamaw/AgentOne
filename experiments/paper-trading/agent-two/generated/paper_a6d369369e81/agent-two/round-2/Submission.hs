module Main where
import System.Directory
import Text.Printf
import Data.Char (isAscii,isControl)
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  let root = "/workspace/artifacts/paper_a6d369369e81/agent-two/round-2"
      target = "/shared/competition/paper_a6d369369e81/round-2/agent-two"
  raw <- readFile "/shared/competition/paper_a6d369369e81/round-2/bars.csv"
  let rows = map split (filter (not . null) (drop 1 (lines raw)))
  if take 1 (lines raw) /= ["t,close,volume"] || any ((/=3) . length) rows then fail "Invalid public CSV" else pure ()
  let ps = map (read . (!!1)) rows :: [Double]
      ts = map (read . head) rows :: [Int]
      n = length ps
  if n < 22 || any (\x -> x <= 0 || isNaN x || isInfinite x) ps || ts /= [0..73] then fail "Invalid public observations" else pure ()
  let p = last ps
      r7 = p / (ps !! (n-8)) - 1
      r21 = p / (ps !! (n-22)) - 1
      entry = r7 > 0 && r21 > 0
      costFactor = 1.0005 * 1.001 :: Double
      q = fromIntegral (floor (800 / (p * costFactor) * 1e8) :: Integer) / 1e8 :: Double
      limit = 1000 / (q * costFactor)
      orders = if entry then printf "side,quantity\nbuy,%.8f\n" q else "side,quantity\n"
  if not entry || q <= 0 || q*p*costFactor > 800 then fail "Reviewed entry or sizing inconsistent" else pure ()
  let approach = printf "Preserved dual-horizon momentum: require positive 7-bar and 21-bar completed-close returns. At t=73 close=%.12f, r7=%.6f%% and r21=%.6f%%; both gates pass. Buy %.8f units from current cash=1000, units=0. Quantity uses an 800 cash budget at the observed close including 5bps buy slippage and 10bps fee, rounded down to eight decimals. Fixed quantity costs fit 1000 if the unknown next close is at most %.12f (25%% above decision close, approximately); feasibility is conditional, not guaranteed. No future price accessed. Supplied 74 observations suffice for the 22-close rule; no dates or long warmup used." p (100*r7) (100*r21) q limit :: String
      changes = "Source references: /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/preserved/preserved-baseline-submission.hs; /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/retained-lessons.json; /workspace/artifacts/paper_a6d369369e81/agent-two/round-1/Submission.hs. Preserve the actual baseline's stated 7/21 entry gate, recalculated on current public bars. Previous executable only handled holds; this isolated round source adds fixed-unit buy sizing at 80% of observed-price cash capacity, leaving 20% cash at unchanged fill. This is an execution-risk buffer for delayed unknown-price fills, not a proven alpha improvement or a target-at-fill order. Round-1 routine feedback: no failures, cash=1000, units=0, equity=1000; benchmark equity=1105.6214724983752. The missed rebound does not justify retuning gates: entry now follows the unchanged signal, not forced benchmark chasing. Calendar weekly and 200-session experimental variants remain incompatible and unproven here; no transplant, backtest, parameter optimization, or superiority claim. No current peer orders, private assets, engine/state edits, real trades, extra rounds or official reruns. Only routine settlement counts."
      fields = [("code_ref",root ++ "/Submission.hs"),("approach",approach),("changes",changes)]
      manifest = "{" ++ foldr1 (\a b -> a ++ "," ++ b) [show k ++ ":" ++ show v | (k,v) <- fields] ++ "}\n"
  if not (all (all (\c -> isAscii c && not (isControl c)) . snd) fields) then fail "Manifest not JSON-safe" else pure ()
  createDirectoryIfMissing True target
  writeFile (root ++ "/observations.csv") raw
  writeFile (root ++ "/orders.csv") orders
  writeFile (root ++ "/manifest.json") manifest
  writeFile (target ++ "/orders.csv") orders
  writeFile (target ++ "/manifest.json") manifest
  a <- readFile (target ++ "/orders.csv")
  b <- readFile (target ++ "/manifest.json")
  if a /= orders || b /= manifest then fail "Readback mismatch" else pure ()
  putStrLn (printf "Round 2/5 signal: r7=%.6f%%, r21=%.6f%%. Submitted buy %.8f units. Cash suffices if next close <= %.12f; unknown fill feasibility is not guaranteed." (100*r7) (100*r21) q limit)
