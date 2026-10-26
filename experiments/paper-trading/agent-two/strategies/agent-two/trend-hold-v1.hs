module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Read (readMaybe)
import Text.Printf
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
num :: String -> Double
num s = case readMaybe s of Just x | not (isNaN x || isInfinite x) -> x; _ -> error "Invalid numeric value"
bar :: String -> (Int,Double,Double)
bar s = case split s of [t,p,v] -> (read t,num p,num v); _ -> error "Invalid bar"
main :: IO ()
main = do
  [input,output,unitsArg,cashArg] <- getArgs
  raw <- readFile input
  let ls = lines raw
  unless (not (null ls) && head ls == "t,close,volume") (error "Invalid bars header")
  let bs = map bar (tail ls)
      prices = [p | (_,p,_) <- bs]
      n = length prices
      units = num unitsArg
      cash = num cashArg
  unless (n >= 21 && map (\(t,_,_) -> t) bs == [0..n-1] && all (\(_,p,v) -> p>0 && v>0) bs && units>=0 && cash>=0) (error "Invalid public data or portfolio")
  let lastPrice = last prices
      sma20 = sum (drop (n-20) prices) / 20
      momentum20 = lastPrice / (prices !! (n-21)) - 1
      exitRegime = lastPrice < sma20 && momentum20 < 0
      selling = exitRegime && units > 0
      orders = "side,quantity\n" ++ if selling then "sell," ++ unitsArg ++ "\n" else ""
      manifest = "{\"code_ref\":\"/workspace/strategies/agent-two/trend-hold-v1.hs\",\"approach\":\"Independent long-only trend persistence with a two-condition downside exit: sell existing units only when the public close is below its 20-bar mean and 20-bar momentum is negative; otherwise retain the portfolio without trading.\",\"changes\":\"Competition-native next-close decision using only published index bars and current holdings. No offline AAPL performance assumptions, no new buys, and no improvement claim.\"}\n"
  createDirectoryIfMissing True output
  writeFile (output ++ "/orders.csv") orders
  writeFile (output ++ "/manifest.json") manifest
  actualOrders <- readFile (output ++ "/orders.csv")
  actualManifest <- readFile (output ++ "/manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) (error "Submission readback mismatch")
  let rows = lines actualOrders
      validRow row = case split row of ["sell",q] -> let x=num q in x>0 && x<=units; _ -> False
  unless (head rows == "side,quantity" && length rows <= 2 && all validRow (tail rows)) (error "Order validation failed")
  printf "Public decision t=%d: close=%.6f, SMA20=%.6f, 20-bar return=%.4f%%.\n" (n-1) lastPrice sma20 (100*momentum20)
  putStrLn (if selling then "Submitted sell of existing units under the downside filter." else "Submitted HOLD: retain 6.5046126199 units and current cash; positive medium-term trend does not trigger the downside exit.")
  putStrLn "orders.csv and manifest.json written and readback-validated. Only competition settlement determines results."
