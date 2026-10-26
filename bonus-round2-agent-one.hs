module Main where
import System.Process
import System.Directory
import Control.Monad
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of
  (a,[]) -> [a]
  (a,_:b) -> a : split b
main :: IO ()
main = do
  let root = "/shared/competition/bonus_ceac35656c41/round-2/"
      dest = root ++ "agent-one/"
      source = "/workspace/bonus-round2-agent-one.hs"
  raw <- readFile (root ++ "bars.csv")
  let rows = map split (filter (not . null) (tail (lines raw)))
      prices = map (\r -> read (r !! 1) :: Double) rows
      n = length prices
      lastPrice = last prices
      momentum k = lastPrice / (prices !! (n - 1 - k)) - 1
      horizons = [7,14,21]
      signals = map momentum horizons
      exit = all (< 0) signals
      orders = "side,quantity\n" ++ if exit then "sell,3.414153\n" else ""
  unless (n > 21 && all (> 0) prices) (fail "Invalid public price history")
  digest <- readProcess "sha256sum" [source] ""
  let codeRef = source ++ " sha256:" ++ head (words digest)
      approach = "Long-only multi-horizon momentum filter using only public closes. Sell all carried units when 7-, 14-, and 21-bar returns are negative; otherwise hold. No purchases, leverage, or assumptions about the unknown next-close fill. Cash-hold slot is synthetic and not another participant."
      changes = "Round-2 offline adaptation: use agreement across three horizons rather than react to a single bar; exit the remaining 3.414153 units on the current jointly negative signal. Prior official evidence reports cash 524.8767974760563 and equity 963.5980418164309; no claims about prior strategy source or future performance. Existing engine, repositories, and infrastructure unchanged."
      manifest = "{\n  \"code_ref\": " ++ show codeRef ++ ",\n  \"approach\": " ++ show approach ++ ",\n  \"changes\": " ++ show changes ++ "\n}\n"
  createDirectoryIfMissing True dest
  writeFile (dest ++ "orders.csv") orders
  writeFile (dest ++ "manifest.json") manifest
  actualOrders <- readFile (dest ++ "orders.csv")
  actualManifest <- readFile (dest ++ "manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (fail "Submission readback mismatch")
  forM_ (zip horizons signals) $ \(k,r) -> printf "%d-bar close return: %.6f%%\n" k (100*r)
  putStrLn "--- orders.csv readback ---"
  putStr actualOrders
  putStrLn "--- manifest.json readback ---"
  putStr actualManifest
