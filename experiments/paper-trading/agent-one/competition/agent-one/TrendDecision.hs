module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Read (readMaybe)
import qualified Data.Map.Strict as M
import Text.ParserCombinators.ReadP
split [] = [""]
split (',':xs) = "" : split xs
split (x:xs) = let (y:ys) = split xs in (x:y):ys
finite x = not (isNaN x || isInfinite x)
jsonObject :: ReadP [(String,String)]
jsonObject = do
  skipSpaces; _ <- char '{'; skipSpaces
  fields <- sepBy field (skipSpaces >> char ',' >> skipSpaces)
  skipSpaces; _ <- char '}'; skipSpaces; eof; pure fields
  where field = do k <- readS_to_P reads; skipSpaces; _ <- char ':'; skipSpaces; v <- readS_to_P reads; pure (k,v)
main :: IO ()
main = do
  [barsPath,outDir,cashArg,unitsArg,roundArg] <- getArgs
  let cash = read cashArg :: Double; units = read unitsArg :: Double
  unless (all finite [cash,units] && cash >= 0 && units >= 0) (fail "Invalid public portfolio")
  raw <- readFile barsPath
  unless (take 1 (lines raw) == ["t,close,volume"]) (fail "Invalid public header")
  rows <- forM (tail (lines raw)) $ \line -> case split line of
    [t,p,v] -> case (readMaybe t :: Maybe Int,readMaybe p :: Maybe Double,readMaybe v :: Maybe Double) of
      (Just ti,Just pi,Just vi) | pi > 0 && vi >= 0 && finite pi && finite vi -> pure (ti,pi)
      _ -> fail "Invalid public bar"
    _ -> fail "Malformed public bar"
  unless (not (null rows) && map fst rows == [0..length rows-1]) (fail "Noncontiguous public bars")
  let prices = map snd rows
      recent n = take n (reverse prices)
      average xs = sum xs / fromIntegral (length xs)
      price = last prices
      ma10 = average (recent 10)
      ma20 = average (recent 20)
      bullish = length prices >= 20 && price > ma20 && ma10 > ma20
      equity = cash + units * price
      target = if bullish then 0.85 * equity else 0
      delta = target - units * price
      floorUnits x = fromIntegral (floor (max 0 x * 1000000) :: Integer) / 1000000 :: Double
      buyQty = floorUnits (min (0.85 * cash) delta / (price * 1.0005 * 1.001))
      sellQty = min units (floorUnits ((negate delta) / price))
      chosen | not bullish && units > 0 = [("sell",units)]
             | abs delta <= 0.05 * equity = []
             | delta > 0 && buyQty > 0 = [("buy",buyQty)]
             | delta < 0 && sellQty > 0 = [("sell",sellQty)]
             | otherwise = []
      orders = "side,quantity\n" ++ concat [side ++ "," ++ show q ++ "\n" | (side,q) <- chosen]
      fields = [("code_ref","/workspace/competition/agent-one/TrendDecision.hs"),("approach","Long-only public-close trend: last close above 20-bar mean and 10-bar mean above 20-bar mean. Target 85 percent marked equity when bullish, cash otherwise; a 5 percent equity no-rebalance band limits turnover. Buys retain at least 15 percent of cash as a next-close execution buffer, not a guarantee."),("changes","Round " ++ roundArg ++ ": retain the round-2 portfolio-aware trend strategy and turnover band unchanged; refresh signals from the current public bars and use supplied current cash and units. Uses only public bars and own holdings. No verified improvement claimed.")]
      manifest = "{" ++ concat [ (if i == 0 then "" else ",") ++ show k ++ ":" ++ show v | (i,(k,v)) <- zip [0::Int ..] fields] ++ "}\n"
  createDirectoryIfMissing True outDir
  writeFile (outDir ++ "/orders.csv") orders
  writeFile (outDir ++ "/manifest.json") manifest
  readOrders <- readFile (outDir ++ "/orders.csv")
  readManifest <- readFile (outDir ++ "/manifest.json")
  unless (readOrders == orders && readManifest == manifest) (fail "Submission readback mismatch")
  case readP_to_S jsonObject readManifest of
    [(parsed,"")] | M.fromList parsed == M.fromList fields && length parsed == 3 -> pure ()
    _ -> fail "Manifest readback invalid"
  unless (take 1 (lines readOrders) == ["side,quantity"]) (fail "Invalid order header")
  let validate [] _ _ = pure ()
      validate (row:rest) c u = case split row of
        [side,q] -> case readMaybe q :: Maybe Double of
          Just n | finite n && n > 0 -> case side of
            "buy" | n * price * 1.0005 * 1.001 <= c -> validate rest (c - n * price * 1.0005 * 1.001) (u+n)
            "sell" | n <= u -> validate rest (c + n * price * 0.9995 * 0.999) (u-n)
            _ -> fail "Infeasible order at public reference close"
          _ -> fail "Invalid quantity"
        _ -> fail "Malformed order"
  validate (drop 1 (lines readOrders)) cash units
  putStrLn ("Public close=" ++ show price ++ "; MA10=" ++ show ma10 ++ "; MA20=" ++ show ma20 ++ "; bullish=" ++ show bullish)
  putStrLn ("Current invested fraction=" ++ show (units * price / equity) ++ "; target=85% when bullish.")
  putStrLn ("Readback validated orders.csv and manifest.json; " ++ if null chosen then "HOLD: no orders submitted." else "orders=" ++ show chosen ++ "; next-close buy feasibility remains uncertain.")
