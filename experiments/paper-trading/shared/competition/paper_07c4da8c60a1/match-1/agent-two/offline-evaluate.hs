module Main where
import System.Environment
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import Control.Monad
import Data.List
split s = case break (== ',') s of { (a,[]) -> [a]; (a,_:b) -> a:split b }
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v)<-xs] ++ "}"
arr xs = "[" ++ intercalate "," xs ++ "]"
num x | isNaN x || isInfinite x = error "nonfinite metric" | otherwise = show (x::Double)
data R = R Int Double Bool Double Double deriving Show
profit (R _ p _ _ _) = p
metrics rs = obj [("cases",show (length rs)),("mean_profit",num (sum (map profit rs)/fromIntegral(length rs))),("min_profit",num (minimum(map profit rs))),("max_profit",num (maximum(map profit rs))),("profitable_cases",show(length(filter ((>0).profit) rs))),("rejected_cases",show(length [()|R _ _ ok _ _ <-rs,not ok])),("mean_buy_hold_profit",num (sum [b|R _ _ _ _ b<-rs]/fromIntegral(length rs))),("mean_cash_profit","0"),("mean_excess_vs_buy_hold",num (sum [p-b|R _ p _ _ b<-rs]/fromIntegral(length rs)))]
record (R t p ok q b) = obj [("decision_t",show t),("profit",num p),("feasible",if ok then "true" else "false"),("quantity",num q),("cash_profit","0"),("buy_hold_profit",num b)]
main = do
  [root] <- getArgs
  base <- makeAbsolute root
  raw <- readFile (base </> "public-bars.csv")
  let rows = lines raw
      prices = map ((read::String->Double).(!!1).split) (tail rows)
      origins = [29..length prices-8]
      factor = 1.0005*1.001
  when (length prices /= 60 || null origins) (fail "unexpected public data")
  let work = base </> "offline-replay"
  exists <- doesPathExist work
  when exists (removePathForcibly work)
  createDirectoryIfMissing True work
  results <- forM ["old-parent","candidate"] $ \version -> forM origins $ \t -> do
    let caseDir = work </> version </> show t
        prefix = caseDir </> "prefix.csv"
        dest = caseDir </> "offline-output"
        source = base </> (if version=="old-parent" then "old-parent.hs" else "candidate.hs")
    createDirectoryIfMissing True caseDir
    writeFile prefix (unlines (take (t+2) rows))
    (ec,out,err) <- readProcessWithExitCode (base </> version) [prefix,dest,source] ""
    writeFile (caseDir </> "execution.log") (show ec ++ "\n" ++ out ++ err)
    unless (ec == ExitSuccess) (fail ("strategy execution failed: " ++ caseDir))
    orders <- readFile (dest </> "orders.csv")
    let os = lines orders
    unless (length os==2 && head os=="side,quantity" && take 4 (os!!1)=="buy,") (fail "unexpected retained strategy output")
    let q = read ((split (os!!1))!!1)::Double
        fill = prices!!(t+1)
        mark = prices!!(t+7)
        cost = q*fill*factor
        ok = q>0 && not(isNaN q || isInfinite q) && cost<=1000
        p = if ok then q*mark-cost else 0
        bh = 1000/(fill*factor)*mark-1000
    pure (R t p ok q bh)
  let [old,new] = results
      disjoint rs = [r | r@(R t _ _ _ _) <-rs, (t-29) `mod` 7==0]
      same = and [a==b && x==y && q==z | (R _ a x q _,R _ b y z _) <- zip old new]
      report = obj
        [("status",show "completed"),("verification",show "AGENT-REPORTED; not independently verified improvement")
        ,("method",show "Compile and execute exact incumbent and identical retained candidate on 24 rolling public prefixes. Each independent case resets to cash 1000 and zero holdings; earliest origin t=29 gives 30-bar warmup; prefix only ends at decision t; offline evaluator alone reads already-public t+1 and t+7 closes. Separate nonoverlapping-origin sensitivity subset t=29,36,43,50. No fitting, parameter search, or candidate selection on these returns.")
        ,("limitations",show "Only 60 public bars from one series; overlapping 7-bar marks are dependent, disjoint subset only four cases. Retrospective descriptive evaluation, not holdout or future evidence. Parent actually buys unconditionally: AR forecasts cited in its original manifest were exploratory, not implemented gates. Identical retained candidate cannot demonstrate incremental improvement. No private settlement bars used. Next-close reserve cannot guarantee feasibility. Benchmark has ex-post exact-fill fractional sizing, unlike decision-time strategy. Marked equity is not liquidated, so no exit costs. Cases reset holdings and do not simulate multiple carried rounds. Generated offline-output orders are local evaluation artifacts, not submissions.")
        ,("cases",show(length origins)),("old_metrics",obj [("rolling",metrics old),("nonoverlapping",metrics(disjoint old))]),("new_metrics",obj [("rolling",metrics new),("nonoverlapping",metrics(disjoint new))])
        ,("costs",obj [("fee_bps","10"),("slippage_bps","5"),("buy_factor",num factor),("initial_cash","1000"),("exit_charge","0"),("exit_charge_reason",show "mark only; no sell simulated")])
        ,("fill_policy",show "Buy at public close[t+1] * 1.0005 with 0.001 fee on slipped notional; reject entire buy if cash insufficient. Six-decimal units emitted by actual sources. Mark remaining cash plus units*close[t+7]. Cash baseline=1000; buy-hold invests 1000 at same t+1 fill/cost and marks at t+7.")
        ,("data_path",show(base </> "public-bars.csv"))
        ,("commands",arr(map show ["cd "++base,"mkdir -p build-old build-new build-eval","ghc -O2 -outputdir build-old old-parent.hs -o old-parent","ghc -O2 -outputdir build-new candidate.hs -o candidate","ghc -O2 -outputdir build-eval offline-evaluate.hs -o offline-evaluate","./offline-evaluate ."]))
        ,("results",obj [("identical_old_new_outputs_and_metrics",if same then "true" else "false"),("old_cases",arr(map record old)),("new_cases",arr(map record new)),("execution_logs_path",show work)])]
  unless same (fail "identical-source reproducibility failed")
  writeFile (base </> "test-report.json") (report++"\n")
  putStrLn ("OLD rolling "++metrics old)
  putStrLn ("NEW rolling "++metrics new)
  putStrLn ("Nonoverlapping "++metrics(disjoint old))
  putStrLn "Completed actual OLD/NEW executions; source retained unchanged; no next-round submission."
