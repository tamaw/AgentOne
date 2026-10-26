module Main where
import System.Directory
import Control.Monad
import Text.Printf
import Text.Read (readMaybe)

version, parent, effectiveRound :: String
version = "agent-two-v1"
parent = "none; original public-bars-only strategy"
effectiveRound = "0"

split :: String -> [String]
split s = case break (== ',') s of
  (a,[]) -> [a]
  (a,_:b) -> a : split b

main :: IO ()
main = do
  let root = "/shared/competition/paper_33935e6cb45b_m1/round-0"
      destination = root ++ "/agent-two"
      source = "/workspace/paper_33935e6cb45b_m1-agent-two/StrategyV1.hs"
  raw <- readFile (root ++ "/bars.csv")
  let rows = lines raw
  unless (not (null rows) && head rows == "t,close,volume") (fail "Unexpected public bars header")
  prices <- forM (tail rows) $ \line -> case split line of
    [_,p,_] -> case readMaybe p :: Maybe Double of
      Just x | x > 0 && not (isNaN x || isInfinite x) -> pure x
      _ -> fail "Invalid public close"
    _ -> fail "Invalid public bar"
  unless (length prices >= 29) (fail "Insufficient public history")
  let current = last prices
      momentum n = current / (prices !! (length prices - 1 - n)) - 1
      m7 = momentum 7
      m14 = momentum 14
      m28 = momentum 28
      confirmedUptrend = m14 > 0 && m28 > 0
  printf "Public-close momentum: 7 bars %.4f%%; 14 bars %.4f%%; 28 bars %.4f%%.\n" (100*m7) (100*m14) (100*m28)
  when confirmedUptrend (fail "This cash-only version does not submit exposure in a confirmed uptrend; explicit adaptation required")
  let orders = "side,quantity\n"
      approach = "Cash-only defensive decision: require positive 14- and 28-bar close momentum before considering long exposure. Both are negative at the decision bar; the small 7-bar rebound is not confirmation. Preserve 1000 cash and zero units; no execution costs. This is a public-data heuristic, not a forecast or independently verified performance result."
      changes = "Original version agent-two-v1; parent: none; effective round: 0. Uses only the supplied public bars and brief. No prior improvements or own handoff were requested by this brief. No peer tips used and no peer submissions accessed. No offline performance claims or private future data. Cash-only submission selected because medium-term momentum is negative; no code promotion or freeze implied."
      manifest = "{\n  \"code_ref\": " ++ show source ++ ",\n  \"approach\": " ++ show approach ++ ",\n  \"changes\": " ++ show changes ++ "\n}\n"
  forM_ [destination ++ "/orders.csv", destination ++ "/manifest.json"] $ \p -> do
    exists <- doesPathExist p
    when exists (fail ("Refusing to overwrite existing submission: " ++ p))
  putStrLn "Confirmed both own submission files absent before writing."
  createDirectoryIfMissing True destination
  writeFile (destination ++ "/orders.csv") orders
  writeFile (destination ++ "/manifest.json") manifest
  actualOrders <- readFile (destination ++ "/orders.csv")
  actualManifest <- readFile (destination ++ "/manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (fail "Submission readback mismatch")
  sourceExists <- doesFileExist source
  unless sourceExists (fail "Executable source not preserved")
  putStrLn ("Preserved executable source: " ++ source)
  putStrLn ("Submitted and read back " ++ destination ++ "/orders.csv:")
  putStr actualOrders
  putStrLn ("Submitted and read back " ++ destination ++ "/manifest.json:")
  putStr actualManifest
  putStrLn "PAPER submission complete: no trades; cash 1000, units 0. Future settlement remains unknown."
