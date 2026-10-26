module Main where
import System.Environment
import Text.Read
import Text.Printf
import Control.Monad
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
num s = case readMaybe s :: Maybe Double of Just x | not (isNaN x || isInfinite x) -> x; _ -> error "Invalid number"
mean xs = sum xs / fromIntegral (length xs)
main = do
  [input,output,cashArg,unitsArg] <- getArgs
  raw <- readFile input
  let ls = lines raw
  unless (not (null ls) && head ls == "t,close,volume") (error "Invalid header")
  let rows = map split (tail ls)
  unless (all ((==3).length) rows) (error "Invalid row")
  let ps = map (num . (!!1)) rows
      vs = map (num . (!!2)) rows
      ts = map (read . head) rows :: [Int]
      n = length ps
      cash = num cashArg
      units = num unitsArg
  unless (n>=22 && ts==[0..n-1] && all (>0) ps && all (>0) vs && cash>=0 && units>=0) (error "Invalid public data or holdings")
  let p = last ps
      r7 = log (p/(ps!!(n-8)))
      r21 = log (p/(ps!!(n-22)))
      trailing = drop (n-21) ps
      rs = zipWith (\a b -> log (b/a)) trailing (tail trailing)
      mu = mean rs
      sigma = sqrt (mean (map (\x -> (x-mu)^2) rs))
      sma20 = mean (drop (n-20) ps)
      hurdle = 0.003+0.25*sigma*sqrt 6
      enter = r7>hurdle && r21>0 && p>sma20
      exit = p<sma20 && p/(ps!!(n-21))-1<0
      qty = min 250 (0.85*cash)/(p*1.0005*1.001)
      order | units>0 && exit = printf "sell,%.10f\n" (fromIntegral (floor (units*1e10)::Integer)/1e10::Double)
            | units==0 && enter && qty>0 = printf "buy,%.10f\n" qty
            | otherwise = ""
  writeFile output ("side,quantity\n"++order)
  check <- readFile output
  unless (check=="side,quantity\n"++order) (error "Orders readback mismatch")
  printf "t=%d close=%.10f r7=%.10f r21=%.10f sigma20=%.10f hurdle=%.10f sma20=%.10f entry=%s exit=%s\n" (n-1) p r7 r21 sigma hurdle sma20 (show enter) (show exit)
  putStr check
