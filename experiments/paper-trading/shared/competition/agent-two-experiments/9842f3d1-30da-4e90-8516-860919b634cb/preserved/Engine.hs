module Engine where
import Data.List
import Data.Array
import Data.Time
import Data.Time.Calendar.WeekDate
import System.Directory
import Control.Monad
import Text.Printf

data Bar = Bar {date::String, op::Double, hi::Double, lo::Double, cl::Double} deriving Show
data Signal = Signal {r7::Double,r21::Double,vol20::Double,weekly::Bool,invested::Bool} deriving Show
type Decide = Signal -> Maybe Double
data Trade = Trade String String Double Double Double Double Double Double Double deriving Show
data DayRow = DayRow String Double Double Double Double Int Double deriving Show
data State = State {cash::Double,units::Double,rows::[DayRow],trades::[Trade],validHolds::Int,fees::Double,slips::Double} deriving Show
initial = State 100000 0 [] [] 0 0 0
fee = 0.001 :: Double
slip = 0.0005 :: Double
split [] = [""]
split (x:xs) | x == ',' = "":split xs
             | otherwise = let a:as=split xs in (x:a):as
readBars path = do
  src <- readFile path
  let ls=filter (not.null) (lines src)
  when (null ls || take 15 (head ls) /= "Date,AAPL.Open,") $ error "Unexpected CSV header"
  let parse ln = case split ln of
        (d:o:h:l:c:_:a:_) -> let [oo,hh,ll,cc,aa]=map read [o,h,l,c,a]; k=aa/cc in Bar d (oo*k) (hh*k) (ll*k) aa
        _ -> error "Malformed CSV row"
      bs=map parse (tail ls)
  when (length bs < 260) $ error "Insufficient public data"
  forM_ bs $ \b -> do
    when (length (date b)/=10 || any (\v->isNaN v || isInfinite v || v<=0) [op b,hi b,lo b,cl b]) $ error "Invalid bar"
    when (lo b > min (op b) (cl b)+1e-5 || hi b+1e-5 < max (op b) (cl b)) $ error "Invalid OHLC ordering"
  when (not (and (zipWith (<) (map date bs) (drop 1 (map date bs))))) $ error "Dates not unique and increasing"
  pure bs
week d = let (y,w,_)=toWeekDate (read d :: Day) in (y,w)
baseline s = Just (if r7 s>0 && r21 s>0 then 1 else 0)
buyHold _ = Just 1
signal arr i st =
  let c j=cl (arr!j); rs=[log (c j/c (j-1)) | j<-[i-20..i-1]]
      avg=sum rs/20; v=sqrt (252*sum [(r-avg)^2|r<-rs]/19)
  in Signal (c (i-1)/c (i-8)-1) (c (i-1)/c (i-22)-1) v (week (date (arr!i))/=week (date (arr!(i-1)))) (units st>1e-9)
execute d reason ref delta st
  | abs delta < 1e-9 = st
  | otherwise =
    let p=ref*(if delta>0 then 1+slip else 1-slip)
        f=abs delta*p*fee
        ca=cash st-delta*p-f
        un=units st+delta
        eq=ca+un*ref
        t=Trade d reason delta ref p f ca un eq
    in if ca < -1e-6 || un < -1e-8 || any (\v->isNaN v || isInfinite v) [ca,un,eq]
       then error ("Infeasible execution "++show t)
       else st {cash=max 0 ca,units=max 0 un,trades=t:trades st,fees=fees st+f,slips=slips st+abs delta*ref*slip}
rebalance d ref target st
  | target<0 || target>1 || isNaN target = error "Invalid target"
  | otherwise =
    let eq=cash st+units st*ref
        gap=target*eq-units st*ref
        cost=if gap>=0 then (1+slip)*(1+fee)-1 else 1-(1-slip)*(1-fee)
        den=ref*(if gap>=0 then 1+target*cost else 1-target*cost)
        delta=gap/den
    in execute d "signal_at_next_open" ref delta st
simulate bs decide =
  let arr=listArray (0,length bs-1) bs
      ids=[i | (i,b)<-zip [0..] bs,date b>="2016-01-01",date b<="2017-02-16"]
      finalI=last ids
      advance st i =
        let b=arr!i; sg=signal arr i st
            proposed=case decide sg of Nothing->st; Just w->rebalance (date b) (op b) w st
            nOpen=length (trades proposed)-length (trades st)
            closed=if i==finalI then execute (date b) "terminal_at_close" (cl b) (negate (units proposed)) proposed else proposed
            n=length (trades closed)-length (trades st)
            eq=cash closed+units closed*cl b
            exposure=if eq>0 then units closed*cl b/eq else 0
            row=DayRow (date b) eq (cash closed) (units closed) exposure n (cl b)
        in closed {rows=row:rows st,validHolds=validHolds st+if n==0 then 1 else 0}
  in if null ids || head ids<22 then error "Missing evaluation/warmup" else foldl' advance initial ids
fmt x=printf "%.10f" (x::Double)
csv=intercalate ","
equities st=[e|DayRow _ e _ _ _ _ _<-reverse (rows st)]
drawdown es= snd $ foldl' (\(peak,dd) e->let p=max peak e in (p,max dd (1-e/p))) (100000,0) es
summaryHeader="strategy,days,trade_fills,buy_fills,sell_fills,valid_holds,hold_cash_days,hold_invested_days,pnl,return_pct,max_drawdown_pct,fees,slippage_cost,mean_exposure_pct,failures"
summary name st =
  let rs=reverse (rows st); ts=trades st; es=equities st
      buys=length [()|Trade _ _ q _ _ _ _ _ _<-ts,q>0]
      hc=length [()|DayRow _ _ _ u _ n _<-rs,n==0,u<=1e-9]
      hl=length [()|DayRow _ _ _ u _ n _<-rs,n==0,u>1e-9]
      expAvg=sum [w|DayRow _ _ _ _ w _ _<-rs]/fromIntegral (length rs)
  in csv [name,show (length rs),show (length ts),show buys,show (length ts-buys),show (validHolds st),show hc,show hl,fmt (last es-100000),fmt ((last es/100000-1)*100),fmt (100*drawdown es),fmt (fees st),fmt (slips st),fmt (100*expAvg),"0"]
writeResults dir name st = do
  let ts=reverse (trades st); rs=reverse (rows st)
  writeFile (dir++"/"++name++"-trades.csv") $ unlines $ "date,reason,signed_quantity,reference_price,slipped_fill_price,fee,cash_after,units_after,equity_at_reference":
    [csv [d,r,fmt q,fmt ref,fmt p,fmt f,fmt ca,fmt u,fmt e]|Trade d r q ref p f ca u e<-ts]
  writeFile (dir++"/"++name++"-daily.csv") $ unlines $ "date,equity,cash,units,exposure,trade_fills,valid_hold,adjusted_close":
    [csv [d,fmt e,fmt ca,fmt u,fmt w,show n,if n==0 then "1" else "0",fmt c]|DayRow d e ca u w n c<-rs]
  let ys=nub [take 4 d|DayRow d _ _ _ _ _ _<-rs]
      annual y = let tagged=zip (100000:map (\(DayRow _ e _ _ _ _ _)->e) rs) rs
                     subset=[(prior,r)| (prior,r@(DayRow d _ _ _ _ _ _))<-tagged,take 4 d==y]
                     start=fst (head subset)
                     vals=[e|(_,DayRow _ e _ _ _ _ _)<-subset]
                     dd=snd $ foldl' (\(p,z) e->let p'=max p e in (p',max z (1-e/p'))) (start,0) vals
                 in csv [y,fmt start,fmt (last vals),fmt ((last vals/start-1)*100),fmt (100*dd),show (sum [n|(_,DayRow _ _ _ _ _ n _)<-subset])]
  writeFile (dir++"/"++name++"-annual.csv") (unlines ("year,starting_equity,ending_equity,return_pct,within_year_drawdown_pct,trade_fills":map annual ys))
run root name decide = do
  bs<-readBars (root++"/data/aapl-plotly.csv")
  let out=root++"/"++name
      runs=[("baseline",simulate bs baseline),("buy-and-hold",simulate bs buyHold),("variant",simulate bs decide)]
      report=unlines (summaryHeader:[summary label st|(label,st)<-runs])
  mapM_ (uncurry (writeResults out)) runs
  writeFile (out++"/summary.csv") report
  putStrLn (name++": "++show (length bs)++" public rows validated; initialization excluded from P&L.")
  putStr report
