module Main where
import System.Process
import System.Directory
import Control.Monad
import Data.List
import Text.Printf
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v)<-xs] ++ "}"
data Episode = E { ix::Int, profit::Double, dd::Double, signalled::Bool, rejected::Bool, bench::Double, entryCost::Double } deriving Show
metrics es = obj [("cases",show(length es)),("mean_profit",show(mean(map profit es))),("mean_return",show(mean(map profit es)/1000)),("worst_profit",show(minimum(map profit es))),("max_episode_marked_drawdown",show(maximum(map dd es))),("entry_signals",show(length(filter signalled es))),("filled_entries",show(length(filter (\e -> signalled e && not(rejected e)) es))),("rejected_fills",show(length(filter rejected es))),("mean_benchmark_profit",show(mean(map bench es))),("mean_benchmark_gap_return",show(mean(map (\e -> (profit e-bench e)/1000) es))),("total_entry_friction_dollars",show(sum(map entryCost es))),("mean_entry_friction_dollars",show(mean(map entryCost es)))]
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
        (ex,_,err) <- readProcessWithExitCode ("build/"++version++"-strategy") [prefix,tag,root++"/"++(if version=="old" then "parent-v5-match4.hs" else "candidate-v6-risk125.hs")] ""
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
        pure (E t (equity-1000) (maxdd marks) (q>0) bad benchmark (filled*f*(1.0005*1.001-1)))
  old <- mapM (run "old") [20..52]
  new <- mapM (run "new") [20..52]
  let pass=mean(map profit new)>=mean(map profit old)+0.25-1e-12 && maximum(map dd new)<=0.6*maximum(map dd old)+1e-12 && length(filter signalled old)==length(filter signalled new) && length(filter (\e -> signalled e && not(rejected e)) new)>=3 && not(any rejected new)
      report=obj [("status",show "completed"),("cases",show(length old)),("method",show "Fresh agent-run paired offline replay of separately compiled byte-exact match-4 incumbent and one risk-budget proposal on reused public development bars. Each t=20..52 passes only prefix 0..t to the actual executable, resets capital=1000 and units=0, fills at t+1, marks through t+7. Both have 21-close warmup, unchanged 10/5-bar signal, ten-decimal rounding, equal costs and all-or-none cash checks. ONLY trading parameter change is nominal budget 250 to 125. Criterion declared in hypothesis-before-replay.json before running: maximum marked drawdown <=60% of old, mean net profit improvement >=0.25 dollars, identical signal counts, at least three fills and zero rejected fills. Numerical tolerance 1e-12. One proposal, no sweep. Benchmark is fully invested at same t+1 cost and t+7 mark, computed only by evaluator from already-public bars."),("limitations",show "Only 60 previously published bars reused from match-3/agent-one/public-bars.csv, with 33 overlapping dependent episodes, not held-out evidence. Choice informed by public match-4 scoreboard and previously known negative mean profit, making half-sizing's effects on this path largely predictable. Risk reduction does not repair negative entry timing or establish positive alpha; it can worsen future bull-market benchmark gaps. Stride-seven subset has disjoint outcomes but shares history and is not independent validation. No private judge data, unseen future observations or t>59 prices used. Evaluator alone reads already-public outcome closes after decisions. No forced liquidation or terminal exit fee. Matched judge replay is unavailable: local paired testing is agent-run, not independent judge verification. The fixed 10% buffer is heuristic, not a guaranteed gap bound."),("data_path",show(root++"/public-bars.csv")),("parent_source_path",show(root++"/parent-v5-match4.hs")),("candidate_source_path",show(root++"/candidate-v6-risk125.hs")),("warmup_bars","21"),("old_metrics",metrics old),("new_metrics",metrics new),("costs",obj [("initial_cash","1000"),("fee_bps","10"),("slippage_bps","5"),("old_target_capital_fraction","0.25"),("new_target_capital_fraction","0.125"),("decision_close_buffer_multiple","1.10"),("buy_cost_multiplier","1.0015005"),("terminal_liquidation","false")]),("fill_policy",show "Next public close t+1, buy price close*1.0005 plus 0.001 fee on slipped notional. Actual emitted rounded quantity; reject entire entry if cost exceeds cash. No shorting/leverage. Terminal equity cash+units*close[t+7], no forced liquidation; costs and warmup identical. Cases reset; not a cumulative live portfolio."),("nonoverlapping_diagnostic",obj [("indices","[20,27,34,41,48]"),("old_metrics",metrics(filter (\e -> (ix e-20) `mod` 7==0) old)),("new_metrics",metrics(filter (\e -> (ix e-20) `mod` 7==0) new))]),("declared_before_this_replay_hypothesis_passed",if pass then "true" else "false"),("independent_judge_verification","false")]
  writeFile "test-report.json" (report++"\n")
  writeFile "paired-cases.csv" (unlines ("decision_t,old_profit,new_profit,old_drawdown,new_drawdown,benchmark_profit":[intercalate "," [show(ix a),show(profit a),show(profit b),show(dd a),show(dd b),show(bench a)] | (a,b)<-zip old new]))
  putStrLn ("Paired cases="++show(length old)++"; old mean="++show(mean(map profit old))++"; new mean="++show(mean(map profit new))++"; declared criterion="++show pass)
