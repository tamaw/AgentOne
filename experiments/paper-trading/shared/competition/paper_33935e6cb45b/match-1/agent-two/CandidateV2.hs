module Main where
import System.Directory
import System.Environment (getArgs)
import Control.Monad
import Text.Printf
import Text.Read (readMaybe)

version, parent, effectiveRound :: String
version = "agent-two-v2-offline-cash-total"
parent = "agent-two-v1"
effectiveRound = "0"

split :: String -> [String]
split s = case break (== ',') s of
  (a,[]) -> [a]
  (a,_:b) -> a : split b

main :: IO ()
main = do
  args <- getArgs
  root <- case args of
    ["--offline-root", r] -> pure r
    _ -> fail "Offline candidate only: --offline-root DIRECTORY required"
  let destination = root ++ "/agent-two"
      source = "/shared/competition/paper_33935e6cb45b/match-1/agent-two/CandidateV2.hs"
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
  when confirmedUptrend (putStrLn "Positive momentum observed; cash-only policy deliberately retains cash rather than aborting. No profitability claim.")
  let orders = "side,quantity\n"
      approach = "Offline cash-only baseline: compute momentum diagnostics without using them to forecast returns. Preserve initial cash and zero units for every valid public history. Positive momentum does not abort or authorize a trade. This robustness revision has no claimed economic alpha."
      changes = "agent-two-v2-offline-cash-total; parent agent-two-v1. Offline-only candidate: remove positive-momentum abort and require an explicit offline root. Keep zero exposure; no promotion, future orders, private future data, or profit claim. Historical tests are exploratory agent-reported reliability checks."
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
