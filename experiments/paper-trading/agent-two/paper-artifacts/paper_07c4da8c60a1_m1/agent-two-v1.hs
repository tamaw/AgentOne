module Main where
import System.Environment
import System.Directory
import System.FilePath
import Control.Monad
import Text.Printf
split s = case break (== ',') s of { (a,[]) -> [a]; (a,_:b) -> a:split b }
main :: IO ()
main = do
  [bars,dest,code] <- getArgs
  raw <- readFile bars
  let prices = map ((read :: String -> Double) . (!!1) . split) (tail (lines raw))
      p = last prices
      cash = 1000 :: Double
      factor = 1.0005 * 1.001
      reserveMultiplier = 1.15
      q = fromIntegral (floor (cash / (p * reserveMultiplier * factor) * 1000000) :: Integer) / 1000000 :: Double
      orders = "side,quantity\nbuy," ++ printf "%.6f" q ++ "\n"
      approach = "Public-close mean reversion, long only. Exploratory AR(1) fits on trailing 20/30/40/50 bars all forecast seven-step prices above the latest 79.30785898386068 close. Buy using a 15% next-close price reserve, including 5 bps slippage and 10 bps fees. This reserve does not guarantee feasibility for arbitrary next-close jumps. No future prices used."
      changes = "Initial own implementation, parent none, version agent-two-v1, effective round 0. Developed offline from this round's public bars and brief; no prior version, peer submission, or private judge data used. Brief did not instruct reading improvements or a handoff, and no handoff peer_tip_decisions were supplied. Chose mean reversion because all four exploratory window forecasts were positive; retained cash for uncertain next-close fills rather than spending all cash at the decision close. Exploratory agent-reported analysis only, not independent verification or settlement."
      fields = [("code_ref",code),("approach",approach),("changes",changes),("parent","none"),("version","agent-two-v1"),("effective_round","0")]
      json = "{" ++ concat [ (if i == 0 then "" else ",") ++ show k ++ ":" ++ show v | (i,(k,v)) <- zip [0::Int ..] fields ] ++ "}\n"
  unless (p > 0 && q > 0 && not (isNaN q || isInfinite q) && q*p*reserveMultiplier*factor <= cash) (fail "Invalid sizing")
  createDirectoryIfMissing True dest
  forM_ ["orders.csv","manifest.json"] $ \f -> do
    exists <- doesPathExist (dest </> f)
    when exists (fail ("Refusing to overwrite existing submission: " ++ f))
  writeFile (dest </> "manifest.json") json
  writeFile (dest </> "orders.csv") orders
  putStrLn ("Submitted paper buy quantity=" ++ printf "%.6f" q ++ "; version agent-two-v1; effective round 0.")
