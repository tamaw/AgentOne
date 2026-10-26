module Main where
import Engine
import System.Environment
-- Fixed hypothesis: cap annualized 20-return volatility at 10%,
-- resize weekly, but retain immediate baseline exits and next-open entry.
strategy s
  | r7 s <= 0 || r21 s <= 0 = Just 0
  | not (invested s) || weekly s = Just (min 1 (0.10 / max 1e-8 (vol20 s)))
  | otherwise = Nothing
main = do [root] <- getArgs; run root "experiment2" strategy
