module Main where
import System.Directory
import Control.Monad
import Text.Read
import Data.List
split s = case break (== ',') s of { (a,[]) -> [a]; (a,_:b) -> a:split b }
main :: IO ()
main = do
  let base = "/shared/competition/match_811fe8175c96/round-2/agent-one/"
      code = "/workspace/match_811fe8175c96/Round2.hs"
      approach = "Independent recovery-trend add: buy 2 units, increasing holdings from 10 to 12. Positive 5/10/20/30/40-bar momentum and a new 20-bar closing high support continued recovery; latest volume is 1.16 times its trailing-20-bar average. At the public decision close, estimated post-fee stock exposure is 96.92%, leaving approximately 31.47 cash. This is an intentional high long exposure to maximize expected final equity, not guaranteed outperformance. No leverage; the cash reserve tolerates approximately 19% next-close price appreciation before affordability becomes an issue. A reversal remains the principal risk."
      changes = "Increase exposure from 80.74% rather than retain the prior partial allocation: 30-bar momentum has turned positive and the close has advanced to 82.45280049. Historical positive 5/10-bar signals had negative mean forward returns, while positive 20/30-bar signals had positive means; only one joint positive-5/10/20 observation was eligible, so historical support is weak and overlapping. Broader recovery confirmation, not a fitted historical rule or copying an opponent, motivates this add. Only public bars, previous routine settlement and own previous manifest were inspected. Unknown next-close fill remains unverified. No bonus work authorized or executed."
      manifest = "{" ++ intercalate "," [show k ++ ":" ++ show v | (k,v) <- [("code_ref",code),("approach",approach),("changes",changes)]] ++ "}\n"
      orders = "side,quantity\nbuy,2\n"
  bars <- readFile "/shared/competition/match_811fe8175c96/round-2/bars.csv"
  let lastRow = split (last (lines bars))
      price = read (lastRow !! 1) :: Double
  unless (head lastRow == "73" && 2 * price * 1.0005 * 1.001 < 196.62661034529447) $ fail "Unexpected public input or insufficient indicative cash"
  unless (all (all (\c -> fromEnum c >= 32 && fromEnum c <= 126) . snd) [("code_ref",code),("approach",approach),("changes",changes)]) $ fail "Non-ASCII manifest value"
  createDirectoryIfMissing True base
  writeFile (base ++ "orders.csv") orders
  writeFile (base ++ "manifest.json") manifest
  actualOrders <- readFile (base ++ "orders.csv")
  actualManifest <- readFile (base ++ "manifest.json")
  unless (actualOrders == orders && actualManifest == manifest) $ fail "Submission readback mismatch"
  case lines actualOrders of
    ["side,quantity",r] -> case split r of
      ["buy",q] -> case (readMaybe q :: Maybe Double) of
        Just x | x > 0 && not (isInfinite x || isNaN x) -> pure ()
        _ -> fail "Invalid quantity"
      _ -> fail "Invalid order"
    _ -> fail "Invalid orders format"
  putStrLn "Submission written and read back; CSV validated and required string-only JSON manifest generated and verified."
  putStrLn ("orders.csv:\n" ++ actualOrders)
  putStrLn ("manifest.json:\n" ++ actualManifest)
  putStrLn "Round-2 submission ready. This is not confirmation of acceptance, fill, or settlement. Await existing routine feedback; final three-round verification and winner determination remain pending. No additional matches or bonus work executed."
