{-# LANGUAGE BangPatterns #-}
module Main where
import StrategyV1
import Data.List
import Data.Array
import Data.Time
import System.Environment
import System.Directory
import Text.Printf
import Control.Monad
import Data.Maybe
data Bar=Bar { date::String, price::Double } deriving Show
split s=case break(==',') s of (a,[])->[a]; (a,_:b)->a:split b
finite x=not(isNaN x || isInfinite x)
load path=do
 txt<-readFile path
 let rows=map split (drop 2(lines txt))
     valid r=length r>=9 && all (\x->finite x && x>0) [read(r!!3),read(r!!4),read(r!!5),read(r!!6)] && (read(r!!5)::Double)<=read(r!!6) && (read(r!!6)::Double)<=read(r!!4)
 unless (all valid rows) (error("Invalid OHLC rows: "++path))
 let bs=sortOn date [Bar (take 10(r!!1)) (read(r!!6)) | r<-rows, take 10(r!!1)<="2025-12-31"]
     ds=map date bs
 when (length(nub ds)/=length ds || null bs) (error "Duplicate dates or no data")
 let parse x=fromJust(parseTimeM True defaultTimeLocale "%Y-%m-%d" x::Maybe Day)
     gaps=[(a,b,diffDays(parse b)(parse a))|(a,b)<-zip ds(tail ds),diffDays(parse b)(parse a)/=1]
 pure(bs,gaps,length rows-length bs)
data Account=Account { cash:: !Double, units:: !Double, peak:: !Double, drawdown:: !Double, trades:: !Int, rejects:: !Int, turnover:: !Double, feesPaid:: !Double, trace:: [(String,Double,Double,Double)] }
initial=Account 1000 0 1000 0 0 0 0 0 []
equity a p=cash a+units a*p
execute mode f fee slip p a=case signal mode f (units a>0) of
 Buy -> let q=buyQuantity mode f fee slip(cash a); notional=q*p*(1+slip); cost=notional*(1+fee) in
   if q<=0 then a else if cost>cash a then a{rejects=rejects a+1} else a{cash=cash a-cost,units=q,trades=trades a+1,turnover=turnover a+notional,feesPaid=feesPaid a+notional*fee}
 Sell -> let notional=units a*p*(1-slip) in a{cash=cash a+notional*(1-fee),units=0,trades=trades a+1,turnover=turnover a+notional,feesPaid=feesPaid a+notional*fee}
 Hold -> a
mark d p a=let e=equity a p; pk=max(peak a)e in a{peak=pk,drawdown=max(drawdown a)(1-e/pk),trace=(d,e,cash a,units a):trace a}
simulate bs fs mode cadence fee slip lo hi = foldl' go initial [lo+1..hi]
 where go a i = let b=bs!i; dec=i-1; a'=if (dec-lo)`mod`cadence==0 then execute mode (fs!dec) fee slip (price b) a else a in mark (date b) (price b) a'
benchmark bs fee slip lo hi=foldl' (\a i->mark(date(bs!i))(price(bs!i))a) bought [lo+1..hi]
 where p=price(bs!(lo+1)); q=1000/(p*(1+slip)*(1+fee)); n=q*p*(1+slip); bought=initial{cash=0,units=q,trades=1,turnover=n,feesPaid=n*fee}
showResult asset label cadence mult mode bs lo hi a bh=intercalate "," [asset,label,show cadence,show mult,mode,date(bs!lo),date(bs!hi),fmt(ret a),fmt(ret bh),fmt(ret a-ret bh),fmt(drawdown a),fmt(drawdown bh),show(trades a),show(rejects a),fmt(turnover a/1000),fmt(feesPaid a),fmt(cash a),fmt(units a)]
 where ret x=equity x (price(bs!hi))/1000-1; fmt x=printf "%.10f" x
main=do
 [root]<-getArgs
 createDirectoryIfMissing True(root++"/traces")
 let header="asset,split,cadence,cost_multiplier,strategy,start_decision,end_mark,return,bh_return,excess,max_drawdown,bh_max_drawdown,trades,rejected_orders,notional_turnover_per_initial,fees,cash,units"
 writeFile(root++"/results.csv")(header++"\n")
 writeFile(root++"/data-quality.txt")""
 forM_ ["BTCUSD","ETHUSD"] $ \asset->do
  (bars,gaps,excluded)<-load(root++"/"++asset++"_daily.raw.csv")
  let n=length bars; bs=listArray(0,n-1)bars; fs=listArray(0,n-1)(zipWith (\i rev->(features(take 121 rev)){historyCount=i+1}) [0..] (tail(scanl (flip (:)) [] (map price bars))))
      ranges=[(show y++if y<2020 then "-development" else if y<2023 then "-validation" else "-holdout",show y++"-01-01",show y++"-12-31")|y<-[2015..2025]]++[("2020-2025-continuous","2020-01-01","2025-12-31"),("2023-2025-continuous","2023-01-01","2025-12-31")]
  appendFile(root++"/data-quality.txt")(show(asset,n,date(head bars),date(last bars),"excluded post2025 rows",excluded,"non-daily intervals",gaps)++"\n")
  forM_ ranges $ \(label,start,end)->do
   let ix=[i|i<-[120..n-1],date(bs!i)>=start,date(bs!i)<=end]
   unless(null ix) $ do
    let lo=head ix; hi=last ix
    forM_ [(7,1),(7,2),(1,1)] $ \(cadence,mult)->do
     let fee=0.001*mult; slip=0.0005*mult; bh=benchmark bs fee slip lo hi
     forM_ [minBound..maxBound] $ \mode->do
      let a=simulate bs fs mode cadence fee slip lo hi
      appendFile(root++"/results.csv")(showResult asset label cadence mult (show mode) bs lo hi a bh++"\n")
      when(cadence==7 && mult==1 && label=="2023-2025-continuous") $
       writeFile(root++"/traces/"++asset++"-"++show mode++".csv")("date,equity,cash,units,bh_equity\n"++unlines[printf "%s,%.10f,%.10f,%.10f,%.10f" d e c u be|((d,e,c,u),(_,be,_,_))<-zip(reverse(trace a))(reverse(trace bh))])
     appendFile(root++"/results.csv")(showResult asset label cadence mult "BuyHold" bs lo hi bh bh++"\n")
     let a=foldl' (\z i->mark(date(bs!i))(price(bs!i))z) initial [lo+1..hi]
     appendFile(root++"/results.csv")(showResult asset label cadence mult "Cash" bs lo hi a bh++"\n")
 putStrLn "Wrote complete chronological fold results and held-out daily equity traces."
