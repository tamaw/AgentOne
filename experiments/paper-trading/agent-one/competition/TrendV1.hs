module Main where
import System.Environment
import System.Directory
import System.FilePath
import Control.Monad
split :: String -> [String]
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
mean xs = sum xs / fromIntegral (length xs)
main :: IO ()
main = do
  [bars,out,cashArg,unitsArg] <- getArgs
  raw <- readFile bars
  let rows = map split (tail (lines raw))
      prices = [read p :: Double | [_,p,_] <- rows]
      cash = read cashArg :: Double
      units = read unitsArg :: Double
      recent n = drop (length prices - n) prices
      p = last prices
      m10 = mean (recent 10)
      m20 = mean (recent 20)
      momentum = p / (prices !! (length prices - 11)) - 1
      bullish = p > m20 && m10 > m20 && momentum > 0
      bearish = p < m20 && m10 < m20 && momentum < 0
      buyUnits = 0.75 * cash / (p * 1.15 * 1.0015005)
      orders = if bearish && units > 0 then [("sell",units)] else if bullish && units == 0 && cash > 0 then [("buy",buyUnits)] else []
      csv = "side,quantity\n" ++ concat [s ++ "," ++ show q ++ "\n" | (s,q) <- orders]
      approach = "Long-only trend filter using public trailing 10/20-bar means and 10-bar momentum; hold cash when trend is negative. Next-close execution is uncertain; no performance improvement asserted."
      changes = "Independent initial strategy. Orders determined solely from public bars and own current cash/units."
      manifest = "{\"code_ref\":\"/workspace/competition/TrendV1.hs\",\"approach\":" ++ show approach ++ ",\"changes\":" ++ show changes ++ "}\n"
  unless (length prices >= 20 && length prices == length rows && all (>0) prices) (fail "Invalid public bars")
  createDirectoryIfMissing True out
  writeFile (out </> "orders.csv") csv
  writeFile (out </> "manifest.json") manifest
  actualOrders <- readFile (out </> "orders.csv")
  actualManifest <- readFile (out </> "manifest.json")
  unless (actualOrders == csv && actualManifest == manifest) (fail "Readback mismatch")
  unless (all (\(s,q) -> (s == "buy" || s == "sell") && q > 0 && not (isNaN q || isInfinite q)) orders) (fail "Invalid order")
  putStrLn ("Public signals: last=" ++ show p ++ ", mean10=" ++ show m10 ++ ", mean20=" ++ show m20 ++ ", momentum10=" ++ show momentum)
  putStrLn ("Validated submission readback: " ++ show (length orders) ++ " orders; all required manifest fields are strings.")
  putStr actualOrders
  putStr actualManifest
