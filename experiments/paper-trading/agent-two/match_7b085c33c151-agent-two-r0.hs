module Main where
import System.Directory
import Control.Monad
import Text.Read (readMaybe)
split :: String -> [String]
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  raw <- readFile "/shared/competition/match_7b085c33c151/round-0/bars.csv"
  let rows = map split (drop 1 (lines raw))
  unless (not (null rows) && all ((==3) . length) rows) (fail "Invalid public bars")
  prices <- mapM (\r -> maybe (fail "Invalid close") pure (readMaybe (r !! 1) :: Maybe Double)) rows
  unless (length prices >= 22 && all (\x -> x > 0 && not (isNaN x || isInfinite x)) prices) (fail "Insufficient or invalid prices")
  let rev = reverse prices
      r7 = head rev / (rev !! 7) - 1
      r21 = head rev / (rev !! 21) - 1
      sma20 = sum (take 20 rev) / 20
      dir = "/shared/competition/match_7b085c33c151/round-0/agent-two"
      orders = "side,quantity\n"
      approach = "Independent dual-horizon momentum filter carried from my available strategy: initiate longs only with positive 7-bar and 21-bar returns. Current 7-bar return=" ++ show (100*r7) ++ " percent; 21-bar return=" ++ show (100*r21) ++ " percent; latest close=" ++ show (head rev) ++ "; SMA20=" ++ show sma20 ++ ". Retain cash=1000 and units=0; no fees or unknown next-close buy-feasibility risk. No performance improvement claim."
      fields = [("code_ref","/workspace/match_7b085c33c151-agent-two-r0.hs"),("approach",approach),("changes","Adapted my existing dual-horizon cash filter to this match's public index bars and next-close execution. No offline AAPL results used as competition evidence; no peer submissions accessed.")]
      manifest = "{" ++ concat [ (if i == (0 :: Int) then "" else ",") ++ show k ++ ":" ++ show v | (i,(k,v)) <- zip [0..] fields] ++ "}\n"
  when (r7 > 0 && r21 > 0) (fail "Positive momentum: cash-only submission requires reconsideration")
  unless (all (all (\c -> fromEnum c >= 32 && fromEnum c < 127) . snd) fields) (fail "Manifest string encoding check failed")
  createDirectoryIfMissing True dir
  writeFile (dir ++ "/orders.csv") orders
  writeFile (dir ++ "/manifest.json") manifest
  checkedOrders <- readFile (dir ++ "/orders.csv")
  checkedManifest <- readFile (dir ++ "/manifest.json")
  unless (checkedOrders == orders && lines checkedOrders == ["side,quantity"]) (fail "Orders readback validation failed")
  unless (checkedManifest == manifest && map fst fields == ["code_ref","approach","changes"] && all (not . null . snd) fields) (fail "Manifest readback validation failed")
  putStrLn ("Round 0 ready: orders.csv and manifest.json written and readback validated. Hold 1000 cash, zero units. 7-bar momentum=" ++ show (100*r7) ++ "%, 21-bar momentum=" ++ show (100*r21) ++ "%. Only competition settlement determines results.")
