module Replay where
import qualified Main as S
import System.Environment
import Control.Monad
import Data.List
import Text.Printf
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v) <- xs] ++ "}"
arr xs = "[" ++ intercalate "," xs ++ "]"
num x | isNaN x || isInfinite x = error "Nonfinite result" | otherwise = show (x :: Double)
jbool True = "true"
jbool False = "false"
signal prices = (edge,q,ceilingPrice)
  where
    p = last prices
    models = [S.fit (drop start prices) | start <- [7,15,20,30]]
    predictions = [(a+b*p, iterate (\x -> a+b*x) p !! 7,sd) | (a,b,sd) <- models]
    edge = sum [mark/entry-1 | (entry,mark,_) <- predictions]/4
    ceilingPrice = maximum [entry+6*sd | (entry,_,sd) <- predictions]
    q = fromIntegral (floor (1000/(ceilingPrice*1.0005*1.001)*1000000) :: Integer)/1000000 :: Double
caseRun prices t = (row, profit, bhprofit, rejected, executed, dd)
  where
    (edge,q,_) = signal (take (t+1) prices)
    fill = prices !! (t+1)
    mark = prices !! (t+7)
    wanted = edge > 0.0015 && q > 0
    cost = q*fill*1.0005*1.001
    rejected = wanted && cost > 1000
    executed = wanted && not rejected
    units = if executed then q else 0
    cash = if executed then 1000-cost else 1000
    equity = cash+units*mark
    profit = equity-1000
    bhprofit = 1000/(fill*1.0005*1.001)*mark-1000
    marks = 1000 : [cash+units*p | p <- take 7 (drop (t+1) prices)]
    dd = maximum [1-e/peak | (e,peak) <- zip marks (scanl1 max marks)]
    row = obj [("decision_t",show t),("warmup_bars",show (t+1)),("forecast_edge",num edge),("requested_quantity",num (if wanted then q else 0)),("fill_t",show (t+1)),("mark_t",show (t+7)),("fill_close",num fill),("mark_close",num mark),("rejected_insufficient_cash",jbool rejected),("executed",jbool executed),("equity",num equity),("profit",num profit),("cash_profit",num 0),("buy_hold_profit",num bhprofit),("excess_vs_buy_hold",num (profit-bhprofit)),("max_marked_drawdown",num dd)]
main = do
  args <- getArgs
  unless (length args == 1) (fail "expected public CSV path")
  csv <- readFile (head args)
  let rows = map S.split (drop 1 (lines csv))
  unless (length rows == 60 && all ((==3) . length) rows) (fail "unexpected input")
  let prices = [read (r!!1) :: Double | r <- rows]
      cs = [caseRun prices t | t <- [39..52]]
      mean xs = sum xs / fromIntegral (length xs)
      profits = [p | (_,p,_,_,_,_) <- cs]
      bhs = [b | (_,_,b,_,_,_) <- cs]
      (fullEdge,fullQ,fullCeil) = signal prices
      fullWanted = fullEdge > 0.0015 && fullQ > 0
      metrics = obj [("cases",show (length cs)),("mean_profit",num (mean profits)),("mean_return",num (mean profits/1000)),("median_profit",num ((sort profits !! 6 + sort profits !! 7)/2)),("worst_profit",num (minimum profits)),("best_profit",num (maximum profits)),("profitable_cases",show (length (filter (>0) profits))),("losing_cases",show (length (filter (<0) profits))),("cash_tie_cases",show (length (filter (==0) profits))),("mean_buy_hold_profit",num (mean bhs)),("mean_excess_vs_buy_hold",num (mean (zipWith (-) profits bhs))),("wins_vs_buy_hold",show (length (filter (>0) (zipWith (-) profits bhs)))),("rejected_cases",show (length [() | (_,_,_,True,_,_) <- cs])),("executed_cases",show (length [() | (_,_,_,_,True,_) <- cs])),("max_case_drawdown",num (maximum [d | (_,_,_,_,_,d) <- cs]))]
      full = obj [("warmup_bars","60"),("forecast_edge",num fullEdge),("quantity",num (if fullWanted then fullQ else 0)),("sizing_ceiling",num fullCeil),("future_evaluation_available","false")]
  putStrLn (obj [("metrics",metrics),("full_60_bar_signal",full),("cases",arr [r | (r,_,_,_,_,_) <- cs])])
