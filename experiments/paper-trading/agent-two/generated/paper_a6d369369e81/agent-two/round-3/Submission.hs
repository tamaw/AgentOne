module Main where
import System.Directory
import Text.Printf
import Data.Char (isAscii,isControl)
import Data.List (intercalate)
import Text.ParserCombinators.ReadP
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
jsonString :: ReadP String
jsonString = char '"' *> munch (\c -> isAscii c && not (isControl c) && c /= '"' && c /= '\\') <* char '"'
jsonObject :: ReadP [(String,String)]
jsonObject = between (char '{') (char '}') (sepBy ((,) <$> jsonString <* char ':' <*> jsonString) (char ',')) <* skipSpaces <* eof
main :: IO ()
main = do
  let root = "/workspace/artifacts/paper_a6d369369e81/agent-two/round-3"
      target = "/shared/competition/paper_a6d369369e81/round-3/agent-two"
      cash = 225.8686382298434 :: Double
      units = 9.75911008 :: Double
  raw <- readFile "/shared/competition/paper_a6d369369e81/round-3/bars.csv"
  let rows = map split (drop 1 (lines raw))
  if take 1 (lines raw) /= ["t,close,volume"] || any ((/=3) . length) rows then fail "Invalid public CSV" else pure ()
  let ps = map (read . (!!1)) rows :: [Double]
      ts = map (read . head) rows :: [Int]
      n = length ps
  if n < 22 || ts /= [0..80] || any (\p -> p <= 0 || isNaN p || isInfinite p) ps then fail "Invalid public observations" else pure ()
  let p = last ps
      r7 = p / (ps !! (n-8)) - 1
      r21 = p / (ps !! (n-22)) - 1
  if not (r7 > 0 && r21 > 0 && units > 0 && cash >= 0) then fail "Reviewed hold signal inconsistent" else pure ()
  let approach = printf "Preserved dual-horizon momentum entry gate: positive 7-bar and 21-bar completed-close returns. At t=80 close=%.12f, r7=%.6f%% and r21=%.6f%%; both remain positive. Already long 9.75911008 units following the round-2 entry: retain existing position and cash=225.8686382298434, without pyramiding or repeatedly deploying the execution buffer. Submit header-only no-trade orders. No cash or unit feasibility risk from this hold; no future fill price required. All 81 supplied anonymous index observations are sufficient for the 22-close calculation; no calendar or long-warmup rule used." p (100*r7) (100*r21) :: String
      changes = "Source references: /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/preserved/preserved-baseline-submission.hs; /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/retained-lessons.json; /workspace/artifacts/paper_a6d369369e81/agent-two/round-2/Submission.hs; /shared/competition/paper_a6d369369e81/round-2/evidence.md. No signal thresholds changed. Isolated round-3 source recalculates the preserved entry gate and handles an already-held position with a hold, not a fresh entry or cash top-up. Round-2 routine settlement accepted one buy with no failures and reports own cash=225.8686382298434, units=9.75911008, equity=1054.1434510803267; benchmark equity=1146.4156424386579. The benchmark shortfall and reported trailing standing do not establish a better rule and do not justify forced trades or parameter retuning. The previous 20% observed-price entry buffer remains cash; it was a delayed-fill affordability precaution, not a recurring deployment instruction or proven alpha. No calendar-weekly or 200-session experimental transplant, optimization, backtest, or claim of improvement. No current peer orders inspected, decision coordination, private asset access, infrastructure/state edits, real trades, extra rounds, or official reruns. Only routine settlement counts."
      fields = [("code_ref",root ++ "/Submission.hs"),("approach",approach),("changes",changes)]
      safe c = isAscii c && not (isControl c) && c /= '"' && c /= '\\'
      orders = "side,quantity\n"
      manifest = "{" ++ intercalate "," ["\"" ++ k ++ "\":\"" ++ v ++ "\"" | (k,v) <- fields] ++ "}\n"
  if not (all (all safe . snd) fields) then fail "Unsafe JSON field" else pure ()
  createDirectoryIfMissing True target
  writeFile (root ++ "/observations.csv") raw
  writeFile (root ++ "/orders.csv") orders
  writeFile (root ++ "/manifest.json") manifest
  writeFile (target ++ "/orders.csv") orders
  writeFile (target ++ "/manifest.json") manifest
  a <- readFile (target ++ "/orders.csv")
  b <- readFile (target ++ "/manifest.json")
  if a /= orders || lines a /= ["side,quantity"] then fail "Invalid orders readback" else pure ()
  case readP_to_S jsonObject b of
    [(parsed,"")] | parsed == fields && b == manifest -> pure ()
    _ -> fail "Invalid manifest readback"
  putStrLn (printf "Round 3/5 submission ready: HOLD 9.75911008 units; cash 225.8686382298434. Public t=80 momentum: r7=%.6f%%, r21=%.6f%%. No strategy retuning or top-up. Both orders.csv (header-only) and manifest.json were written and readback validated. Only routine settlement counts." (100*r7) (100*r21))
