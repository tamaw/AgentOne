module Main where
import System.Environment
import System.Directory
import System.FilePath
import Control.Monad
import Text.Read (readMaybe)
import Text.Printf
import Data.List (intercalate)
split :: String -> [String]
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
parse :: String -> (Int,Double,Double)
parse s = case split s of
 [a,b,c] -> case (readMaybe a,readMaybe b,readMaybe c) of
  (Just t,Just p,Just v) | p>0 && v>=0 && not (isNaN p || isInfinite p || isNaN v || isInfinite v) -> (t,p,v)
  _ -> error "Invalid public observation"
 _ -> error "Invalid CSV row"
mean xs = sum xs / fromIntegral (length xs)
json :: String -> String
json s = "\"" ++ concatMap esc s ++ "\"" where
 esc '"' = "\\\""
 esc '\\' = "\\\\"
 esc '\n' = "\\n"
 esc c = [c]
main :: IO ()
main = do
 [bars,dest,ref] <- getArgs
 raw <- readFile bars
 let ls = lines raw
 unless (not (null ls) && head ls == "t,close,volume") (fail "Unexpected header")
 let obs = map parse (tail ls)
     ps = [p | (_,p,_) <- obs]
     ts = [t | (t,_,_) <- obs]
     n = length ps
 unless (n>=21 && and (zipWith (<) ts (tail ts))) (fail "Insufficient or unordered observations")
 let recent = drop (n-21) ps
     rs = zipWith (\a b -> log (b/a)) recent (tail recent)
     mu = mean rs
     sigma = sqrt (sum [(r-mu)^2 | r<-rs] / 19)
     lastP = last ps
     ma20 = mean (drop (n-20) ps)
     mom20 = log (lastP / (ps !! (n-21)))
     mom7 = log (lastP / (ps !! (n-8)))
     score = if sigma>0 then mom20 / (sigma * sqrt 20) else 0
     eligible = score>0.5 && lastP>ma20 && mom7>0
     exposure = if eligible then min 0.5 (0.01 / max 0.000001 sigma) else 0
     qty = 1000 * exposure / (lastP * 1.0005 * 1.001)
     orders = "side,quantity\n" ++ if qty>0 then printf "buy,%.10f\n" (qty::Double) else ""
     approach = "Public-close-only long/cash trend filter: 20-bar log momentum divided by 20-return sample volatility times sqrt(20) must exceed 0.5; close must exceed SMA20; 7-bar log momentum must be positive. Eligible exposure=min(0.5,0.01/daily volatility); otherwise intentional cash hold. Orders reference last observed close with stated fee and slippage; no future fill is observed. No empirical performance claim."
     changes = "Initial source version v1; parent=none; effective round=0; exact SHA256 is in code_ref. Hypothesis: positive multi-horizon trends may persist, while noisy/negative trends do not justify round-trip costs. Actual initial parameters: lookbacks 20 and 7, score threshold 0.5, volatility budget 0.01, exposure cap 0.5. No prior settled-round tips supplied, so none adopted or rejected. This is initial implementation, not a tested improvement; no optimization or backtest performed."
     manifest = "{\n" ++ intercalate ",\n" ["  " ++ json k ++ ": " ++ json v | (k,v)<-[("code_ref",ref),("approach",approach),("changes",changes)]] ++ "\n}\n"
 createDirectoryIfMissing True dest
 let op=dest </> "orders.csv"; mp=dest </> "manifest.json"
 oe <- doesFileExist op
 me <- doesFileExist mp
 when (oe || me) (fail "Submission already exists; refusing repair or resubmission")
 writeFile op orders
 writeFile mp manifest
 actualO <- readFile op
 actualM <- readFile mp
 unless (actualO==orders && actualM==manifest) (fail "Readback mismatch; no repair attempted")
 printf "observations=%d close=%.8f SMA20=%.8f momentum20=%.8f momentum7=%.8f daily_volatility=%.8f trend_score=%.8f\n" n lastP ma20 mom20 mom7 sigma score
 putStrLn "Submission written once; both files read back and matched exactly. Execution successful."
