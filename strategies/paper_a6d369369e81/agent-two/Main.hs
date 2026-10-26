module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
import Text.Read (readMaybe)
import Text.ParserCombinators.ReadP
import Data.Char
import qualified Data.Map.Strict as M
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
finite x = not (isNaN x || isInfinite x)
jsonString = readS_to_P (reads :: ReadS String)
jsonObject = between (char '{') (char '}') (sepBy ((,) <$> jsonString <* char ':' <*> jsonString) (char ',')) <* skipSpaces <* eof
main :: IO ()
main = do
 [dir,cs,us] <- getArgs
 let cash = read cs :: Double; units = read us :: Double
 when (not (all finite [cash,units]) || cash<0 || units<0) $ fail "Invalid supplied account"
 raw <- readFile (dir++"/bars.csv")
 let ls = lines raw
 when (null ls || head ls/="t,close,volume") $ fail "Invalid bars header"
 rows <- forM (tail ls) $ \l -> case split l of
   [a,b,c] -> case (readMaybe a :: Maybe Int,readMaybe b :: Maybe Double,readMaybe c :: Maybe Double) of
     (Just t,Just p,Just v) | finite p && p>0 && finite v && v>=0 -> pure (t,p,v)
     _ -> fail "Invalid public bar values"
   _ -> fail "Invalid public bar row"
 let ps = [p|(_,p,_)<-rows]; ts = [t|(t,_,_)<-rows]; n=length ps
 when (n<41 || not (and (zipWith (<) ts (tail ts)))) $ fail "Insufficient or unordered history"
 let p=last ps; mom k=p/(ps!!(n-1-k))-1; sma=sum (drop (n-20) ps)/20
     buySignal=mom 10>0 && mom 20>0
     sellSignal=p<sma && mom 10<0
     q=fromIntegral (floor (0.90*cash/(p*1.0005*1.001)*1e8)::Integer)/1e8 :: Double
     orders=if units>0 && sellSignal then [("sell",units)] else if units==0 && buySignal && q>0 then [("buy",q)] else []
     csv="side,quantity\n"++concat [s++","++show v++"\n"|(s,v)<-orders]
     fields=[("code_ref","/workspace/strategies/paper_a6d369369e81/agent-two/Main.hs"),
       ("approach","Preserve OwnGeneralized dual-horizon momentum: when flat buy only if both 10-bar and 20-bar close returns are positive; when invested sell all only if close is below its 20-bar mean and 10-bar return is negative; otherwise hold. Entry spends at most 90% of decision-close cash including 5bp slippage and 10bp fee, units rounded down to 8 decimals. Uses only anonymous public closes, at least 41 bars, and supplied own account. No calendar, volume signal, long warmup or peer decisions. Unknown next-close buy feasibility cannot be guaranteed: reserve accommodates an approximately 11.11% rise, not larger. Sales use supplied held units; header-only holds require no fill."),
       ("changes","Selection sources: /shared/competition/paper_be01d1611e99/collaboration/agent-two/OriginalRound0.hs and Revision.hs (OwnGeneralized). Signal thresholds, sell rule and 90% sizing preserved, not optimized. Actual changes are isolated competition paths, public-input/account validation, general round/account arguments, manifest and order readback validation. Reviewed /shared/competition/agent-two-experiments/9842f3d1-30da-4e90-8516-860919b634cb/retained-lessons.json and cycle3/Main.hs: calendar-week variant requires dates and different execution semantics; 200-session filter is infeasible with 60 bars; rejected pullback variant not adopted. No claimed improvement or independent predictive validation. Round-0 has no prior routine feedback. Subsequent decisions use supplied routine feedback; no automatic strategy change. Only official routine settlement counts.")]
     manifest="{"++concat (zipWith (\i (k,v)->(if i==0 then "" else ",")++show k++":"++show v) [0::Int ..] fields)++"}\n"
     out=dir++"/agent-two/"
 createDirectoryIfMissing True out
 writeFile (out++"orders.csv.tmp") csv
 writeFile (out++"manifest.json.tmp") manifest
 renameFile (out++"orders.csv.tmp") (out++"orders.csv")
 renameFile (out++"manifest.json.tmp") (out++"manifest.json")
 oc <- readFile (out++"orders.csv")
 mc <- readFile (out++"manifest.json")
 unless (oc==csv && mc==manifest) $ fail "Readback mismatch"
 case readP_to_S jsonObject mc of
   [(fs,"")] | M.fromList fs==M.fromList fields && length fs==3 -> pure ()
   _ -> fail "Invalid manifest readback"
 unless (head (lines oc)=="side,quantity") $ fail "Invalid orders header"
 forM_ (tail (lines oc)) $ \l -> case split l of
   [s,v] | s=="buy" || s=="sell" -> case readMaybe v :: Maybe Double of
     Just x | finite x && x>0 && (if s=="sell" then x<=units else x*p*1.0005*1.001<=cash) -> pure ()
     _ -> fail "Invalid or decision-close-infeasible quantity"
   _ -> fail "Invalid orders row"
 printf "Public observations: %d bars through t=%d; close=%.8f; r10=%.4f%%; r20=%.4f%%; SMA20=%.8f.\n" n (last ts) p (100*mom 10) (100*mom 20) sma
 putStr oc
 putStrLn "Both orders.csv and manifest.json written and readback validated. This is a submission, not settlement or proof of improvement."
