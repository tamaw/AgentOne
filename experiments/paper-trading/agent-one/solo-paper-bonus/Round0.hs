module Main where
import System.Directory
import Control.Monad
import Text.Read (readMaybe)
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of
  (a,[]) -> [a]
  (a,_:b) -> a : split b
parse :: String -> (Int,Double,Double)
parse s = case split s of
  [a,b,c] | Just t <- readMaybe a, Just p <- readMaybe b, Just v <- readMaybe c, p > 0, v >= 0 -> (t,p,v)
  _ -> error "Invalid public bar"
main :: IO ()
main = do
  let base = "/shared/competition/bonus_ceac35656c41/round-0"
      destination = base ++ "/agent-one"
  raw <- readFile (base ++ "/bars.csv")
  let ls = lines raw
  unless (not (null ls) && head ls == "t,close,volume") $ error "Unexpected bars header"
  let bars = map parse (tail ls)
      prices = [p | (_,p,_) <- bars]
      n = length prices
  unless (n >= 21 && and [t == i | (i,(t,_,_)) <- zip [0..] bars]) $ error "Insufficient or nonsequential bars"
  let lastPrice = last prices
      trailing20 = drop (n-20) prices
      average20 = sum trailing20 / 20
      momentum20 = lastPrice / (prices !! (n-21)) - 1
      enter = momentum20 > 0 && lastPrice > average20
      buyCost = 1.0005 * 1.001
      quantity = fromIntegral (floor ((900 / (lastPrice * buyCost)) * 1000000) :: Integer) / 1000000 :: Double
      order = "side,quantity\n" ++ if enter && quantity > 0 then printf "buy,%.6f\n" quantity else ""
      approach = "Public-close trend filter: buy only when 20-bar return is positive and latest close exceeds its trailing 20-bar mean. Size using 90 percent of initial cash at latest close with multiplicative 5 bp slippage and 10 bp fee; six-decimal units rounded down. The remaining cash provides an approximately 11.1 percent next-close upward-gap buffer, not a guaranteed fill-price bound. Long only; seven-bar evaluation horizon and carried positions acknowledged."
      changes = "Initial round-0 offline strategy authored for this solo paper evaluation from the supplied public bars and rules. No prior strategy or feedback was available; no backtest, private data, peer submissions, baseline files, or infrastructure modifications used. Starting cash 1000 and units zero."
      manifest = "{\n  \"code_ref\": " ++ show "/workspace/solo-paper-bonus/Round0.hs" ++ ",\n  \"approach\": " ++ show approach ++ ",\n  \"changes\": " ++ show changes ++ "\n}\n"
  createDirectoryIfMissing True destination
  writeFile (destination ++ "/orders.csv") order
  writeFile (destination ++ "/manifest.json") manifest
  printf "Decision: last=%.6f mean20=%.6f return20=%.4f%% quantity=%.6f\n" lastPrice average20 (100*momentum20) (if enter then quantity else 0)
  forM_ ["orders.csv","manifest.json"] $ \name -> do
    actual <- readFile (destination ++ "/" ++ name)
    unless (actual == if name == "orders.csv" then order else manifest) $ error "Readback mismatch"
    putStrLn ("--- " ++ name ++ " readback ---")
    putStr actual
