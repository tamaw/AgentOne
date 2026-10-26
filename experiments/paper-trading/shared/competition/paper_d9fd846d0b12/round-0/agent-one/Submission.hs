module Main where
import StrategyV2
import System.Environment
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
main :: IO ()
main = do
  [bars,out,cashText,unitsText] <- getArgs
  rows <- fmap (map split . tail . lines) (readFile bars)
  let ps = reverse (map ((read :: String -> Double) . (!!1)) rows)
      f = features ps
      cash = read cashText :: Double
      units = read unitsText :: Double
      sig = signal Original f (units>0)
      q = buyQuantity Original f 0.001 0.0005 cash
      order = case sig of
        Buy | q>0 -> printf "buy,%.10f\n" q
        Sell | units>0 -> printf "sell,%.10f\n" units
        _ -> ""
  if null ps || any (\p -> isNaN p || isInfinite p || p<=0) ps || cash<0 || units<0 then error "invalid public input" else pure ()
  writeFile out ("side,quantity\n"++order)
  print f
  putStrLn ("mode=Original; signal="++show sig++"; reserve="++show (reserve Original f))
  putStr ("side,quantity\n"++order)
