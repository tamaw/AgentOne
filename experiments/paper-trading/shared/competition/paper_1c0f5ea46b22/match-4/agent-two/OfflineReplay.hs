module Main where
import System.Environment
import System.Directory
import System.Process
import System.FilePath
import Control.Monad
import Data.List
import Text.Printf
split s = case break (== ',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v) <- xs] ++ "}"
num x = printf "%.12f" (x::Double)
avg xs = sum xs / fromIntegral (length xs)
maxDD xs = maximum (0 : zipWith (\peak x -> (peak-x)/peak) (scanl1 max xs) xs)
main = do
  [root,scratch] <- getArgs
  createDirectoryIfMissing True scratch
  raw <- readFile (root </> "public-bars.csv")
  let ls = lines raw; rows = tail ls
      ps = [read (split l !! 1)::Double | l <- rows]
      ts = [21..length ps-8]
  unless (not (null ts) && all (>0) ps) (error "Invalid public sample")
  results <- forM ["old","new"] $ \v -> do
    srcHash <- fmap (head . words) (readProcess "sha256sum" [root </> (v ++ ".hs")] "")
    cases <- forM ts $ \t -> do
      let caseDir = scratch </> (v ++ "-" ++ show t)
          input = caseDir </> "prefix.csv"
      createDirectoryIfMissing True caseDir
      writeFile input (unlines (head ls : take (t+1) rows))
      _ <- readProcess (root </> (v ++ "-strategy")) [input,caseDir,root </> (v ++ ".hs"),srcHash] ""
      orders <- readFile (caseDir </> "orders.csv")
      let os = map split (drop 1 (lines orders))
      unless (all (\r -> length r == 2 && head r == "buy") os && length os <= 1) (error "Unexpected strategy order")
      let q0 = if null os then 0 else read (head os !! 1)::Double
          fill = ps !! (t+1) * 1.0005
          spend = q0*fill*1.001
          rejected = spend > 1000 || q0 < 0 || isNaN q0 || isInfinite q0
          q = if rejected then 0 else q0
          cash = 1000-q*fill*1.001
          path = 1000 : [cash + q*p | p <- take 7 (drop (t+1) ps)]
          eq = last path
          liquid = cash + q*(ps !! (t+7))*0.9995*0.999
          bench = (ps !! (t+7))/(ps !! (t+1))-1
          paid = q*fill*0.001 + q*(fill-ps !! (t+1))
      pure (t,q>0,rejected,eq/1000-1,liquid/1000-1,maxDD path,bench,paid)
    let rs = [r | (_,_,_,r,_,_,_,_) <- cases]
        lr = [r | (_,_,_,_,r,_,_,_) <- cases]
        bs = [r | (_,_,_,_,_,_,r,_) <- cases]
        count p = show (length (filter p cases))
        perCase (t,tr,rj,r,l,d,b,c) = obj [("decision_bar",show t),("filled",if tr then "true" else "false"),("rejected",if rj then "true" else "false"),("marked_return",num r),("liquidation_return",num l),("max_marked_drawdown",num d),("benchmark_gross_return",num b),("entry_cost_dollars",num c)]
        metrics = obj [("cases",show (length cases)),("filled_cases",count (\(_,tr,_,_,_,_,_,_)->tr)),("rejected_cases",count (\(_,_,rj,_,_,_,_,_)->rj)),("mean_marked_return",num (avg rs)),("mean_liquidation_return",num (avg lr)),("worst_case_return",num (minimum rs)),("best_case_return",num (maximum rs)),("maximum_episode_drawdown",num (maximum [d | (_,_,_,_,_,d,_,_) <- cases])),("mean_final_equity",num (1000*(1+avg rs))),("profitable_cases",count (\(_,_,_,r,_,_,_,_)->r>0)),("mean_entry_cost_dollars",num (avg [c|(_,_,_,_,_,_,_,c)<-cases])),("mean_gross_buy_hold_return",num (avg bs)),("case_details","[" ++ intercalate "," (map perCase cases) ++ "]")]
    pure (v,metrics)
  let report = obj [("status",show "completed"),("cases",show (length ts)),("method",show "Paired prefix-only rolling-origin offline replay of freshly compiled preserved match4 parent and single budget250 proposal. Identical 60 public closes saved before match4 round0 outcome; origins 21..52, 22-close warmup, reset cash 1000, next-close fill, mark decision+7. Signal unchanged; only entry budget differs. With all signal gates unchanged, reducing the decision-close entry budget from 500 to 250 dollars will reduce maximum seven-bar episode marked drawdown by at least 40%, keep mean marked return no more than 0.001 below the parent, retain the same filled origins with at least three fills, and cause no additional rejected fills on the fixed public sample. Otherwise retain the parent."),("limitations",show "Small single-path sample; 32 overlapping episodes are dependent, not 32 independent market regimes. This development sample is not held out. Horizons contain only already-public observations, not match-future observations. No volume constraints or market impact; no continuous-position simulation. Liquidation return is a sensitivity metric using identical exit costs. Benchmark is frictionless fill-to-mark buy-and-hold for context, not the scoreboard benchmark path. Independent matched judge replay and independent judge verification are unavailable; this is own-source offline evidence only."),("old_metrics",snd (head results)),("new_metrics",snd (results !! 1)),("costs",obj [("initial_cash",num 1000),("old_entry_budget_at_decision_close",num 500),("new_entry_budget_at_decision_close",num 250),("fee_rate_each_side",num 0.001),("adverse_slippage_rate_each_side",num 0.0005),("primary_mark_exit_cost",num 0)]),("fill_policy",show "Fixed emitted quantity, buy at next public close * 1.0005 plus 0.001 proportional fee; all-or-none reject if cash insufficient, no quantity clipping, no shorting or leverage. Mark at decision+7 public close with no forced sale. Secondary liquidation applies 5bps adverse exit slippage and 10bps exit fee. Both versions identical."),("warmup_closes",show (22::Int)),("data_path",show (root </> "public-bars.csv")),("data_provenance",show "Copied byte-for-byte from /workspace/paper-agent-two/m4/public-bars.csv, the 60 public input closes preserved for match4 round0, before the reported outcome; not the different match3 sample. No hidden path or later market observations used."),("old_source_path",show (root </> "old.hs")),("new_source_path",show (root </> "new.hs"))]
  writeFile (root </> "test-report.json") (report ++ "\n")
  putStrLn ("Completed paired offline replay: " ++ show (length ts) ++ " cases per compiled version; report=" ++ root </> "test-report.json")
