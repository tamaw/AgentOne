module Main where
import qualified Engine as E
import Data.Array
import Data.List
import Control.Monad
import System.Environment
import System.Directory
import Text.Printf
import Data.Char
clean = filter (\c -> c /= '"' && c /= '\r')
readPublic path = do
 txt <- readFile path
 let ls = filter (not.null) (lines txt)
 when (clean (head ls) /= "MSFT,IBM,SBUX,AAPL,GSPC,Date") $ error "Unexpected public header"
 let parse l = case E.split (clean l) of
       [a,b,c,d,e,dt] -> (dt,map read [a,b,c,d,e] :: [Double])
       _ -> error "Malformed public row"
     rs = map parse (tail ls)
     dates = map fst rs
 when (length rs /= 2306 || head dates /= "2007-01-03" || last dates /= "2016-03-01") $ error "Unexpected coverage"
 when (not (and (zipWith (<) dates (tail dates)))) $ error "Nonunique or unsorted dates"
 forM_ rs $ \(dt,vs) -> when (length dt/=10 || any (\x -> isNaN x || isInfinite x || x<=0) vs) $ error "Invalid public price"
 pure [(name,[E.Bar dt (vs!!j) (vs!!j) (vs!!j) (vs!!j) | (dt,vs)<-rs]) | (j,name)<-zip [0..] ["MSFT","IBM","SBUX","AAPL","GSPC"]]
decide cyc label arr i st
 | label == "buy-and-hold" = Just 1
 | label == "baseline" = E.baseline sg
 | cyc == 1 = Just (if positive && c (i-1)>sma then 1 else 0)
 | cyc == 2 = if E.week (E.date (arr!i)) /= E.week (E.date (arr!(i-1))) then E.baseline sg else Nothing
 | cyc == 3 = Just (if not positive then 0 else if E.invested sg || c (i-1)<c (i-3) then 1 else 0)
 | otherwise = error "Unallocated cycle"
 where sg=E.signal arr i st
       positive=E.r7 sg>0 && E.r21 sg>0
       c j=E.cl (arr!j)
       sma=sum [c j | j<-[i-200..i-1]]/200
simulate cyc label bs start end atOpen =
 let arr=listArray (0,length bs-1) bs
     ids=[i | (i,b)<-zip [0..] bs,E.date b>=start,E.date b<=end]
     endI=last ids
     advance st i =
       let b=arr!i
           ref=if atOpen then E.op b else E.cl b
           sg=decide cyc label arr i st
           proposed=maybe st (\w -> E.rebalance (E.date b) ref w st) sg
           closed=if i==endI then E.execute (E.date b) "terminal_at_close" (E.cl b) (negate (E.units proposed)) proposed else proposed
           n=length (E.trades closed)-length (E.trades st)
           eq=E.cash closed+E.units closed*E.cl b
           row=E.DayRow (E.date b) eq (E.cash closed) (E.units closed) (E.units closed*E.cl b/eq) n (E.cl b)
       in closed {E.rows=row:E.rows st,E.validHolds=E.validHolds st+if n==0 then 1 else 0}
 in if null ids || head ids<200 then error "Insufficient warmup/evaluation" else foldl' advance E.initial ids
header="sample,window,strategy,days,initial_cash,pnl,return_pct,max_drawdown_pct,turnover_initial_equity,trade_fills,fees,slippage_cost,failures"
metric sample window label sts =
 let count=fromIntegral (length sts)
     initial=100000*count
     allRows=map (reverse.E.rows) sts
     dates rs=[d|E.DayRow d _ _ _ _ _ _<-rs]
     es=map sum $ transpose [[e|E.DayRow _ e _ _ _ _ _<-rs]|rs<-allRows]
     ts=concatMap E.trades sts
     turnover=sum [abs q*ref|E.Trade _ _ q ref _ _ _ _ _<-ts]/initial
     dd=snd $ foldl' (\(p,z) e -> let p'=max p e in (p',max z (1-e/p'))) (initial,0) es
 in if any ((/=dates (head allRows)).dates) (tail allRows) then error "Unmatched basket dates" else
    E.csv [sample,window,label,show (length es),E.fmt initial,E.fmt (last es-initial),E.fmt ((last es/initial-1)*100),E.fmt (dd*100),E.fmt turnover,show (length ts),E.fmt (sum (map E.fees sts)),E.fmt (sum (map E.slips sts)),"0"]
saveBasket dir label sts = do
 let rs=map (reverse.E.rows) sts
     sums=map sum $ transpose [[e|E.DayRow _ e _ _ _ _ _<-r]|r<-rs]
     ds=[d|E.DayRow d _ _ _ _ _ _<-head rs]
 writeFile (dir++"/"++label++"-basket-equity.csv") (unlines ("date,equity":zipWith (\d e->d++","++E.fmt e) ds sums))
main = do
 [root,cs] <- getArgs
 let cyc=read cs::Int
 when (cyc<1 || cyc>3) $ error "Only three cycles allocated"
 public <- readPublic (root++"/data/stockdata.csv")
 prior <- E.readBars (root++"/data/prior-aapl-plotly.csv")
 let dir=root++"/cycle"++cs
     labels=["baseline","buy-and-hold","candidate"]
     windows=("continuous","2008-01-01","2016-03-01"):[(show y,show y++"-01-01",show y++"-12-31")|y<-[2008..2016::Int]]
     full=[(sym,w,[(label,simulate cyc label bs start end False)|label<-labels])|(sym,bs)<-public,(w,start,end)<-windows]
     old=("AAPL-prior","prior-viewed",[(label,simulate cyc label prior "2016-01-01" "2017-02-16" True)|label<-labels])
     allRuns=full++[old]
     basket=[(w,[(label,[st|(sym,w',runs)<-full,w'==w,(l,st)<-runs,l==label])|label<-labels])|(w,_,_)<-windows]
     report=unlines (header:[metric sym w label [st]|(sym,w,runs)<-allRuns,(label,st)<-runs]++[metric "BASKET-5" w label sts|(w,runs)<-basket,(label,sts)<-runs])
 forM_ allRuns $ \(sym,w,runs)->do
   let out=dir++"/"++sym++"/"++w
   createDirectoryIfMissing True out
   forM_ runs $ \(label,st)->E.writeResults out label st
 forM_ basket $ \(w,runs)->do
   let out=dir++"/BASKET-5/"++w
   createDirectoryIfMissing True out
   forM_ runs $ \(label,sts)->saveBasket out label sts
 writeFile (dir++"/summary.csv") report
 writeFile (dir++"/status.json") ("{\"cycle\":"++cs++",\"completed\":true,\"simulation_failures\":0,\"parameter_search\":false,\"number_of_baseline_candidate_buyhold_comparisons\":61}\n")
 putStrLn ("Cycle "++cs++" completed; continuous public basket and previously viewed AAPL:")
 putStrLn header
 mapM_ putStrLn [r|r<-tail (lines report),let fs=E.split r,(head fs=="BASKET-5" && fs!!1=="continuous") || head fs=="AAPL-prior"]
