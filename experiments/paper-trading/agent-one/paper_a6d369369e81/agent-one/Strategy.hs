module Main where
import System.Environment
import System.Directory
import Text.Printf
import Control.Monad
import Data.Char
import Data.List
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
recent n xs = drop (max 0 (length xs-n)) xs
avg xs = sum xs / fromIntegral (length xs)
finite x = not (isNaN x || isInfinite x)
quote s = "\"" ++ concatMap esc s ++ "\"" where
 esc '\"' = "\\\""
 esc '\\' = "\\\\"
 esc '\n' = "\\n"
 esc '\r' = "\\r"
 esc '\t' = "\\t"
 esc c | ord c < 32 = printf "\\u%04x" (ord c)
       | otherwise = [c]
object fs = "{" ++ intercalate "," [quote k ++ ":" ++ quote v | (k,v)<-fs] ++ "}\n"
main = do
 [bars,out,cashText,unitsText,roundText,feedback] <- getArgs
 raw <- readFile bars
 let ls = lines raw
 unless (not (null ls) && head ls == "t,close,volume") $ error "Unexpected bars header"
 let parse l = case split l of [t,p,v] -> (read t::Int,read p::Double,read v::Double); _ -> error "Malformed bar"
     rows = map parse (tail ls)
     prices = [p | (_,p,_)<-rows]
     ts = [t | (t,_,_)<-rows]
     cash = read cashText :: Double
     units = read unitsText :: Double
 unless (length rows>=41 && and (zipWith (<) ts (tail ts)) && all (\(_,p,v)->finite p && p>0 && finite v && v>=0) rows && finite cash && finite units && cash>=0 && units>=0) $ error "Invalid public inputs"
 let returns = zipWith (\b a -> log (b/a)) (tail prices) prices
     rs = recent 40 returns
     mu = avg rs
     vol = sqrt (sum [(r-mu)^2 | r<-rs] / fromIntegral (length rs-1))
     mom n = sum (recent n returns)
     bullish = mom 20>0 && mom 40>0
     reserve = max 0.12 (4*vol)
     q = fromIntegral (floor (cash/(last prices*(1+reserve)*1.0005*1.001)*1e10)::Integer)/1e10 :: Double
     trade | bullish && units==0 && cash>0 && q>0 = [("buy",q)]
           | not bullish && units>0 = [("sell",units)]
           | otherwise = []
     orders = "side,quantity\n" ++ concat [s ++ "," ++ show x ++ "\n" | (s,x)<-trade]
     approach = "Preserved OriginalStrategy.hs: long only when trailing 20- and 40-bar log returns are both positive; otherwise cash. Hold existing long while both remain positive, otherwise sell all held units. Fixed buy units use latest public close, 5bps slippage, 10bps fee and max(12%,4*sigma40) next-close reserve. At least 41 closes required, so anonymous 60-bar history suffices; no calendars, real prices or volume signal. Reserve reduces but cannot eliminate unknown-next-close infeasibility. No verified predictive superiority claimed."
     changes = "Selected original agent-one trend heuristic rather than unproven transfer. Signal and sizing unchanged from authorized preserved OriginalStrategy.hs; added public-input checks, structured manifests, exact sell serialization and submission readback validation in isolated competition source. StrategyV1 consensus needs 121 bars and is incompatible. Agent-two experiment hypothesis-and-policy.json identifies weekly calendar-dependent cadence, 200-bar filter and different fill-price sizing: none transplanted. Round " ++ roundText ++ ". Feedback: " ++ feedback
     manifest = object [("code_ref","/workspace/paper_a6d369369e81/agent-one/Strategy.hs; original=/shared/competition/paper_be01d1611e99/collaboration/agent-one/OriginalStrategy.hs; reviewed=/shared/competition/paper_be01d1611e99/collaboration/agent-one/StrategyV1.hs,/shared/competition/paper_be01d1611e99/collaboration/agent-one/v2/StrategyV2.hs,/shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/cycle3/hypothesis-and-policy.json"),("approach",approach),("changes",changes)]
 createDirectoryIfMissing True out
 writeFile (out++"/orders.csv") orders
 writeFile (out++"/manifest.json") manifest
 actualOrders <- readFile (out++"/orders.csv")
 actualManifest <- readFile (out++"/manifest.json")
 unless (actualOrders==orders && actualManifest==manifest) $ error "Readback mismatch"
 let parsed = map split (tail (lines actualOrders))
 forM_ parsed $ \r -> case r of
   [s,x] -> do
     let n = read x :: Double
     unless (s `elem` ["buy","sell"] && finite n && n>0 && (if s=="sell" then n<=units else n*last prices*1.0005*1.001<=cash)) $ error "Invalid order"
   _ -> error "Malformed order"
 let metrics = printf "round=%s bars=%d last=%.10f momentum20=%.8f momentum40=%.8f sigma40=%.8f reserve=%.8f" roundText (length prices) (last prices) (mom 20) (mom 40) vol reserve
 writeFile (out++"/selection-report.json") (object [("metrics",metrics),("feedback",feedback),("decision",if null trade then "hold" else fst (head trade)),("validation","orders.csv and manifest.json written and read back; exact public schema constructed; quantities checked; actual next-close feasibility and P&L determined only by routine")])
 putStrLn metrics
 putStrLn ("Readback validated orders.csv and manifest.json in "++out)
 putStr actualOrders
