module Main where
import Engine (split,csv,fmt)
import System.Environment
import Control.Monad
import Text.Printf
main = do
  [root]<-getArgs
  reports<-forM ["experiment1","experiment2"] $ \ex -> forM ["baseline","buy-and-hold","variant"] $ \name -> do
    ts<-map split . tail . lines <$> readFile (root++"/"++ex++"/"++name++"-trades.csv")
    ds<-map split . tail . lines <$> readFile (root++"/"++ex++"/"++name++"-daily.csv")
    let number s=read s::Double
        get j r=number (r!!j)
        totalCashFlow=sum [negate (get 2 t*get 4 t)-get 5 t|t<-ts]
        endCash=get 2 (last ds); endUnits=get 3 (last ds); endEq=get 1 (last ds)
        qty=sum [get 2 t|t<-ts]
        cashResidual=100000+totalCashFlow-endCash
        pnlResidual=totalCashFlow-(endEq-100000)
        feeTotal=sum [get 5 t|t<-ts]
        slipTotal=sum [abs (get 2 t)*get 3 t*0.0005|t<-ts]
        holds=length [()|r<-ds,r!!6=="1"]
        fills=round (sum [get 5 d|d<-ds])::Int
        valid=maximum (map abs [cashResidual,pnlResidual,qty,endUnits]) < 0.01 && fills==length ts && holds+length [()|r<-ds,r!!6=="0"]==length ds
    unless valid $ error ("Ledger reconciliation failed: "++ex++"/"++name)
    pure (csv [ex,name,head (head ds),head (last ds),show (length ds),show (length ts),show holds,fmt totalCashFlow,fmt cashResidual,fmt pnlResidual,fmt qty,fmt endUnits,fmt feeTotal,fmt slipTotal,"reconciled"])
  let report=unlines ("experiment,strategy,first_date,last_date,days,fills,valid_holds,net_trade_cashflow,cash_residual,pnl_residual,quantity_residual,terminal_units,fees,slippage_cost,status":concat reports)
  writeFile (root++"/reconciliation.csv") report
  putStr report
