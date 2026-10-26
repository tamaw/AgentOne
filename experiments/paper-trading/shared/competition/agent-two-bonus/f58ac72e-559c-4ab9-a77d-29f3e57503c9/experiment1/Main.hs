module Main where
import Engine
import System.Environment
-- Fixed hypothesis: +/-1% dual-momentum hysteresis reduces fee drag and whipsaw.
strategy s = Just $ if invested s
  then if r7 s <= -0.01 || r21 s <= -0.01 then 0 else 1
  else if r7 s > 0.01 && r21 s > 0.01 then 1 else 0
main = do [root] <- getArgs; run root "experiment1" strategy
