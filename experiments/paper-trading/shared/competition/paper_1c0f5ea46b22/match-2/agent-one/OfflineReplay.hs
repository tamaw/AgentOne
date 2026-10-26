module Main where
import System.Process
import System.Directory
import Control.Monad
import Data.List
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v)<-xs] ++ "}"
data Episode = E { ix::Int, profit::Double, dd::Double, signalled::Bool, rejected::Bool, bench::Double } deriving Show
metrics es = obj [("cases",show(length es)),("mean_profit",show(mean(map profit es))),("mean_return",show(mean(map profit es)/1000)),("worst_profit",show(minimum(map profit es))),("max_episode_marked_drawdown",show(maximum(map dd es))),("entry_signals",show(length(filter signalled es))),("filled_entries",show(length(filter (\e -> signalled e && not(rejected e)) es))),("rejected_fills",show(length(filter rejected es))),("mean_benchmark_profit",show(mean(map bench es)))]
mean xs = sum xs / fromIntegral(length xs)
maxdd xs = maximum (zipWith (\hi x -> (hi-x)/hi) (scanl1 max xs) xs)
main = do
  root <- getCurrentDirectory
  csv <- readFile "public-bars.csv"
  let ls=lines csv; ps=map (read . (!!1) . split) (tail ls) :: [Double]
  unless (length ps == 60 && all (>0) ps) (fail "Unexpected public input")
  let run version t = do
        let tag="episodes/"++version++"-"++show t; prefix=tag++"/prefix.csv"
        createDirectoryIfMissing True tag
        writeFile prefix (unlines(take (t+2) ls))
        (ex,_,err) <- readProcessWithExitCode ("build/"++version++"-strategy") [prefix,tag,root++"/"++(if version=="old" then "parent-v2-match2.hs" else "candidate-v3-risk-quarter.hs")] ""
        unless (show ex=="ExitSuccess") (fail err)
        orders <- readFile (tag++"/orders.csv")
        let rows=lines orders
        unless (not(null rows) && head rows=="side,quantity" && length rows<=2) (fail "Invalid output")
        let q=if length rows==1 then 0 else read ((split(rows!!1))!!1)::Double
            f=ps!!(t+1); mark=ps!!(t+7); cost=q*f*1.0005*1.001
            bad=cost>1000 || q<0 || isNaN q || isInfinite q
            filled=if bad then 0 else q
            cash=1000-filled*f*1.0005*1.001
            equity=cash+filled*mark
            marks=1000:[cash+filled*(ps!!k) | k<-[t+1..t+7]]
            benchmark=1000/(f*1.0005*1.001)*mark-1000
        pure (E t (equity-1000) (maxdd marks) (q>0) bad benchmark)
  old <- mapM (run "old") [20..52]
  new <- mapM (run "new") [20..52]
  let pass=mean(map profit new)>mean(map profit old) && abs(minimum(map profit new))<=0.51*abs(minimum(map profit old)) && maximum(map dd new)<=0.51*maximum(map dd old) && length(filter signalled old)==length(filter signalled new) && not(any rejected new)
      report=obj [("status",show "completed"),("cases",show(length old)),("method",show "Agent-run paired public-prefix rolling-origin replay of actual independently compiled parent and candidate executables. At each t=20..52 both receive only bars 0..t, reset cash=1000 and units=0, fill at t+1 and mark at t+7. Single candidate declared before this replay on reused development data; no parameter sweep. Warmup=21 closes for both. Single declared criterion: higher mean net profit, worst loss and maximum marked drawdown at most 51% of parent, unchanged entry count, and zero candidate rejected fills. Budget is the sole algorithmic change: old 500 dollars, new 250 dollars; no parameter sweep."),("limitations",show "Reused prior-development 60 published index-price bars, 33 overlapping episodes; hypothesis informed by previous metrics and match-2 loss. Halving exposure mechanically reduces both gains and losses; no improved alpha or timing is established. Historical selection bias and reduced upside capture remain. stride-seven subset is a descriptive sensitivity check, not an independent holdout. Hypothesis formulated after scoreboard review; historical selection bias possible. No unseen observations, private judge data or t>59 prices used. Mark-to-market not liquidation; no exit fee charged because competition marks held inventory. Independent matched judge replay is unavailable; this is not judge verification or out-of-sample evidence. Equal 10% fill buffer is not a bound."),("data_path",show(root++"/public-bars.csv")),("parent_source_path",show(root++"/parent-v2-match2.hs")),("candidate_source_path",show(root++"/candidate-v3-risk-quarter.hs")),("warmup_bars","21"),("old_metrics",metrics old),("new_metrics",metrics new),("costs",obj [("initial_cash","1000"),("fee_bps","10"),("slippage_bps","5"),("old_target_capital_fraction","0.5"),("new_target_capital_fraction","0.25"),("decision_close_buffer_multiple","1.10"),("buy_cost_multiplier","1.0015005"),("terminal_liquidation","false")]),("fill_policy",show "Next public close t+1, buy price close*1.0005 plus 0.001 fee on slipped notional. Actual emitted rounded quantity; reject entire entry if cost exceeds cash. No shorting/leverage. Terminal equity cash+units*close[t+7], no forced liquidation; costs and warmup identical. Cases reset; not a cumulative live portfolio."),("nonoverlapping_diagnostic",obj [("indices","[20,27,34,41,48]"),("old_metrics",metrics(filter (\e -> (ix e-20) `mod` 7==0) old)),("new_metrics",metrics(filter (\e -> (ix e-20) `mod` 7==0) new))]),("declared_before_this_replay_hypothesis_passed",if pass then "true" else "false"),("independent_judge_verification","false")]
  writeFile "test-report.json" (report++"\n")
  writeFile "paired-cases.csv" (unlines ("decision_t,old_profit,new_profit,old_drawdown,new_drawdown,benchmark_profit":[intercalate "," [show(ix a),show(profit a),show(profit b),show(dd a),show(dd b),show(bench a)] | (a,b)<-zip old new]))
  putStrLn ("Paired cases="++show(length old)++"; old mean="++show(mean(map profit old))++"; new mean="++show(mean(map profit new))++"; declared criterion="++show pass)
