module Main where
import Revision
import System.Directory
import Control.Monad
import Data.List
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
clean = filter (`notElem` ['\"','\r'])
type State = (Double,Double,Int,Int,Double,Double)
fill :: Double -> Double -> Order -> State -> (State,String)
fill sl p act s@(c,u,tr,rj,fe,turn) = case act of
  Buy q | q*p*(1+sl)*(1+fee) <= c -> ((c-q*p*(1+sl)*(1+fee),u+q,tr+1,rj,fe+q*p*(1+sl)*fee,turn+q*p),"filled")
        | otherwise -> ((c,u,tr,rj+1,fe,turn),"rejected")
  Sell q | q<=u -> ((c+q*p*(1-sl)*(1-fee),u-q,tr+1,rj,fe+q*p*(1-sl)*fee,turn+q*p),"filled")
         | otherwise -> ((c,u,tr,rj+1,fe,turn),"rejected")
  Hold -> (s,"none")
run :: [Double] -> [String] -> Int -> Int -> Model -> Double -> (State,[Double],[Double],[String])
run ps ds start end model sl = go start (1000,0,0,0,0,0) [] [] []
 where
  go t s@(c,u,_,_,_,_) es xs audit
   | t>end = (s,reverse es,reverse xs,reverse audit)
   | otherwise =
      let decision = (t-start) `mod` 7==0
          p=ps!!t
          history=take t ps
          act | model==FullHold && t==start = Buy (1000/(p*(1+sl)*(1+fee)))
              | decision = order model sl history c u (t==start)
              | otherwise = Hold
          (s'@(c',u',_,_,_,_),status) = if model==FullHold && t==start then ((0,1000/(p*(1+sl)*(1+fee)),1,0,1000*fee/(1+fee),1000/((1+sl)*(1+fee))),"benchmark_fill_notional") else fill sl p act s
          eq=c'+u'*p
          exposure=u'*p/eq
          line=printf "%s,%s,%.8f,%s,%s,%.10f,%.10f" (ds!!(t-1)) (ds!!t) p (show act) status c' u'
      in if c'<(-1e-8)||u'<0||isNaN eq||isInfinite eq then error "invalid accounting" else go (t+1) s' (eq:es) (exposure:xs) (if decision then line:audit else audit)
main :: IO ()
main = do
 raw<-readFile "stocks.csv"
 let rows=map (map clean . split) (filter (not.null) (tail (lines raw)))
     n=length rows
     ds=map (!!5) rows
     universe=zip ["MSFT","IBM","SBUX","AAPL","GSPC"] [0..4]
     folds=[("development",41,n `div` 2-1),("validation",n `div` 2,3*n `div` 4-1),("heldout",3*n `div` 4,n-1)]
     costs=[0.0005,0.0025]
     models=[minBound..maxBound]::[Model]
 when (n<500 || any ((/=6).length) rows || not (and (zipWith (<) ds (tail ds)))) (fail "Malformed or unordered historical dataset")
 createDirectoryIfMissing True "audit"
 writeFile "evaluation.csv" "asset,fold,start,end,bars,slippage_bps,model,return_pct,liquidated_return_pct,max_drawdown_pct,trades,rejections,fees,turnover_initial,mean_exposure\n"
 forM_ universe $ \(asset,col)->do
  let ps=map (read . (!!col)) rows::[Double]
  when (any (\p->p<=0||isNaN p||isInfinite p) ps) (fail "Invalid positive prices")
  forM_ folds $ \(foldName,start,end)-> forM_ costs $ \sl-> forM_ models $ \model->do
   let ((cash,units,tr,rj,fe,turn),eqs,exps,audit)=run ps ds start end model sl
       eq=last eqs
       liquid=cash+units*(ps!!end)*(1-sl)*(1-fee)
       peaks=tail (scanl max 1000 eqs)
       dd=maximum (zipWith (\e p->1-e/p) eqs peaks)
       name=asset++"-"++foldName++"-"++show (round (sl*1e4)::Int)++"-"++show model
       line=printf "%s,%s,%s,%s,%d,%.0f,%s,%.8f,%.8f,%.8f,%d,%d,%.8f,%.8f,%.8f\n" asset foldName (ds!!start) (ds!!end) (end-start+1) (sl*1e4) (show model) (100*(eq/1000-1)) (100*(liquid/1000-1)) (100*dd) tr rj fe (turn/1000) (sum exps/fromIntegral(length exps))
   appendFile "evaluation.csv" line
   writeFile ("audit/"++name++".csv") ("decision_date,fill_date,close,order,status,cash,units\n"++unlines audit)
   writeFile ("audit/"++name++"-equity.csv") ("date,equity\n"++unlines (zipWith (\d e->d++","++printf "%.10f" e) (take (end-start+1) (drop start ds)) eqs))
 putStrLn ("Evaluated "++show n++" rows from "++head ds++" to "++last ds++"; 5 assets x 3 chronological partitions x 2 costs x 6 models = 180 runs. All fixed before results; historical proxy only.")
