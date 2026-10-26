module Main where
import System.Environment
import System.Directory
import System.FilePath
import System.Process
import System.Exit
import Control.Monad
import Data.List
split s = case break (==',') s of (a,[]) -> [a]; (a,_:b) -> a:split b
obj xs = "{" ++ intercalate "," [show k ++ ":" ++ v | (k,v) <- xs] ++ "}"
arr xs = "[" ++ intercalate "," xs ++ "]"
num :: Double -> String
num = show
data R = R Int Double Double Double Double Double Bool deriving Show
equity (R _ e _ _ _ _ _) = e
profit r = equity r - 1000
fee (R _ _ _ f _ _ _) = f
slip (R _ _ _ _ s _ _) = s
traded (R _ _ q _ _ _ _) = q > 0
valid (R _ _ _ _ _ _ v) = v
bench (R _ _ _ _ _ b _) = b
row (R t e q f s b v) = obj [("decision_bar",show t),("fill_bar",show (t+1)),("mark_bar",show (t+7)),("equity",num e),("profit",num (e-1000)),("quantity",num q),("fee_paid",num f),("slippage_paid",num s),("buy_hold_equity",num b),("feasible",if v then "true" else "false")]
metrics rs = let n = fromIntegral (length rs); es = map equity rs; count p = length (filter p rs) in obj [("cases",show (length rs)),("mean_terminal_equity",num (sum es/n)),("mean_profit",num (sum (map profit rs)/n)),("mean_return",num ((sum es/n)/1000-1)),("minimum_terminal_equity",num (minimum es)),("maximum_terminal_equity",num (maximum es)),("profitable_cases",show (count ((>1000).equity))),("loss_cases",show (count ((<1000).equity))),("cash_equal_cases",show (count ((==1000).equity))),("trade_cases",show (count traded)),("infeasible_cases",show (count (not.valid))),("mean_buy_hold_equity",num (sum (map bench rs)/n)),("beats_buy_hold_cases",show (count (\r -> equity r > bench r))),("total_fee_across_independent_cases",num (sum (map fee rs))),("total_slippage_across_independent_cases",num (sum (map slip rs)))]
adapt = unlines . map (\l -> if l == "import Control.Monad" then l ++ "\nimport System.Environment (getArgs)" else if l == "main = do" then l ++ "\n  args <- getArgs" else if l == "  let base = \"/shared/competition/paper_33935e6cb45b_m1/round-0\"" then "  let base = head args" else l) . lines
run exe root ls ps t = do
  let dir = root </> show t
  createDirectoryIfMissing True dir
  writeFile (dir </> "bars.csv") (unlines (take (t+2) ls))
  (ec,o,e) <- readProcessWithExitCode exe [dir] ""
  unless (ec == ExitSuccess) (error (o++e))
  order <- readFile (dir </> "agent-one/orders.csv")
  let ors = filter (not.null) (drop 1 (lines order)); q = case ors of [] -> 0; [r] -> let [side,s] = split r in if side == "buy" then read s else error "unexpected side"; _ -> error "unexpected order count"
      fill = ps !! (t+1); mark = ps !! (t+7); sl = q*fill*0.0005; f = q*fill*1.0005*0.001; cost = q*fill + sl+f; ok = q>=0 && cost<=1000; eq = if ok then 1000-cost+q*mark else 1000; b = 1000/(fill*1.0005*1.001)*mark
  pure (R t eq q f sl b ok)
main = do
  [dest,work] <- getArgs
  createDirectoryIfMissing True work
  forM_ [("parent-source.hs","OldOffline.hs","old-offline","build-old"),("candidate-source.hs","NewOffline.hs","new-offline","build-new")] $ \(s,a,b,d) -> do
    original <- readFile (dest </> s)
    unless (length (filter (== "  let base = \"/shared/competition/paper_33935e6cb45b_m1/round-0\"") (lines original)) == 1) (error "adapter input mismatch")
    writeFile (work </> a) (adapt original)
    createDirectoryIfMissing True (work </> d)
    callProcess "ghc" ["-O2","-outputdir",work </> d,work </> a,"-o",work </> b]
  let sandbox = work </> "offline-cases"
  exists <- doesDirectoryExist sandbox
  when exists (removePathForcibly sandbox)
  txt <- readFile (dest </> "public-bars.csv")
  let ls = lines txt; ps = map (read . (!!1) . split) (tail ls) :: [Double]; ts = [28..length ps-8]
  when (null ts) (error "insufficient data")
  old <- mapM (run (work </> "old-offline") (sandbox </> "old") ls ps) ts
  new <- mapM (run (work </> "new-offline") (sandbox </> "new") ls ps) ts
  let sub rs = filter (\(R t _ _ _ _ _ _) -> (t-28) `mod` 7 == 0) rs
      results = obj [("old_cases",arr (map row old)),("new_cases",arr (map row new)),("old_nonoverlapping",metrics (sub old)),("new_nonoverlapping",metrics (sub new)),("identical_case_results",if map row old == map row new then "true" else "false"),("cash_equity_per_case","1000"),("nonoverlap_decision_bars",arr [show t | t <- ts, (t-28) `mod` 7==0])]
      report = obj [("status",show "completed"),("verification",show "AGENT-REPORTED; not independently verified improvement"),("method",show "Paired independent initial-cash historical prefix replays. Compile original parent and equal candidate via an I/O-only adapter; run both on every identical public prefix at decision bars 28..52. No parameter fitting. Warmup minimum 29 closes, expanding history; fixed 7-bar decision-to-mark horizon. Full sample includes overlapping horizons, plus a fixed stride-7 nonoverlapping subset. No portfolio compounding across cases."),("limitations",show "Only 60 public closes from one synthetic/index series. 25 overlapping windows and four nonoverlapping windows are not independent out-of-sample validation. Public history was visible at design time. Equal source implies equality, not an improvement. Original single-buy policy is not a rolling liquidation strategy. No private settlement prices or future bars used. No ending sale fee because official equity is marked without liquidation. Fees and slippage alone omit market impact and liquidity. Infeasible orders would be rejected in full; observed rejection counts are recorded. Offline executable adapters alter only base-path handling; preserved sources are untouched."),("cases",show (length ts)),("old_metrics",metrics old),("new_metrics",metrics new),("costs",obj [("fee_bps","10"),("slippage_bps","5"),("initial_cash","1000"),("buy_cost_formula",show "q * next_close * 1.0005 * 1.001"),("sizing",show "900 / (decision_close * 1.0005 * 1.001), unchanged"),("liquidation_fee_charged","false"),("infeasible_fill_policy",show "reject entire order, remain cash")]),("fill_policy",show "Decision at t using closes through t only; buy executes at t+1 close with 5bps adverse slippage and 10bps fee; mark units at raw t+7 close, six fill-to-mark intervals. Same policy both versions. Buy-hold reference invests full 1000 at t+1 including identical costs; cash remains 1000."),("data_path",show (dest </> "public-bars.csv")),("commands",arr (map show ["ghc -O2 " ++ dest </> "Offline.hs" ++ " -o " ++ work </> "offline-replay",work </> "offline-replay" ++ " " ++ dest ++ " " ++ work])),("results",results)]
  writeFile (dest </> "test-report.json") (report++"\n")
  putStrLn ("OLD "++metrics old)
  putStrLn ("NEW "++metrics new)
  putStrLn ("NONOVERLAPPING "++metrics (sub old))
