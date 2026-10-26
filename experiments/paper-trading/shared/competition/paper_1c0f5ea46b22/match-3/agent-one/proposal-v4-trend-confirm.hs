module Main where
import System.Environment
import System.Directory
import Control.Monad
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  [bars,out,code] <- getArgs
  input <- readFile bars
  let prices=map (read . (!!1) . split) (drop 1 (lines input)) :: [Double]
      n=length prices
  unless (n>=21 && all (\p -> p>0 && not(isNaN p || isInfinite p)) prices) (fail "Invalid public history")
  let latest=last prices
      ret k=log(latest/(prices!!(n-1-k)))
      enter=ret 10>0.006 && ret 5>0 && ret 20>0
      units=250/(latest*1.10*1.0005*1.001)
      orders="side,quantity\n" ++ if enter then printf "buy,%.10f\n" units else ""
      manifest="{\"code_ref\":"++show code++",\"approach\":\"Offline v4 proposal: incumbent gate plus positive 20-bar log return; 21-close warmup, budget 250, heuristic 1.10 buffer, long-only, next-close fills.\",\"changes\":\"One signal-filter proposal against exact match-3 incumbent; evaluated only on reused public development observations. Not independent judge verification. No deployment or live orders.\"}\n"
  createDirectoryIfMissing True out
  writeFile (out++"/orders.csv") orders
  writeFile (out++"/manifest.json") manifest
  a<-readFile(out++"/orders.csv")
  b<-readFile(out++"/manifest.json")
  unless (a==orders && b==manifest) (fail "Readback mismatch")
