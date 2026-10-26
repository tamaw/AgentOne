module Main where
import System.Directory
import System.Environment
import System.FilePath
import System.Process
import System.Exit
import Control.Monad
import Data.List
import Text.Printf
q :: String -> String
q = show
obj :: [(String,String)] -> String
obj xs = "{" ++ intercalate "," [q k ++ ":" ++ v | (k,v)<-xs] ++ "}"
arr :: [String] -> String
arr xs = "[" ++ intercalate "," xs ++ "]"
split s = case break (==',') s of { (a,[]) -> [a]; (a,_:b) -> a:split b }
root = "/shared/competition/paper_33935e6cb45b_m1/round-0"
oldSource = "/workspace/paper_33935e6cb45b_m1-agent-two/StrategyV1.hs"
putCopy from to = createDirectoryIfMissing True (takeDirectory to) >> copyFile from to
inside box p = box ++ p
prepare d = do
  let box = d ++ "/sandbox"
  createDirectoryIfMissing True box
  putCopy (d++"/old-parent") (box++"/bin/old")
  putCopy (d++"/new-candidate") (box++"/bin/new")
  forM_ ["/lib/x86_64-linux-gnu/libm.so.6","/lib/x86_64-linux-gnu/libgmp.so.10","/lib/x86_64-linux-gnu/libc.so.6","/lib64/ld-linux-x86-64.so.2"] $ \p -> putCopy p (inside box p)
  putCopy (d++"/ParentV1.hs") (inside box oldSource)
  putCopy (d++"/CandidateV2.hs") (inside box (d++"/CandidateV2.hs"))
  pure box
runOne d box rows label t = do
  let dest = inside box (root++"/agent-two"); out = d++"/runs/"++label++"-t"++show t
  exists <- doesDirectoryExist dest
  when exists (removePathForcibly dest)
  createDirectoryIfMissing True (inside box root)
  writeFile (inside box (root++"/bars.csv")) (unlines (take (t+2) rows))
  (ec,stdout,stderr) <- readProcessWithExitCode "/usr/sbin/chroot" [box,"/bin/"++label,"--offline-root",root] ""
  createDirectoryIfMissing True out
  writeFile (out++"/stdout.txt") stdout
  writeFile (out++"/stderr.txt") stderr
  present <- doesFileExist (dest++"/orders.csv")
  orders <- if present then readFile (dest++"/orders.csv") else pure ""
  let ok = ec == ExitSuccess && orders == "side,quantity\n"
  when (ec == ExitSuccess && not ok) (fail "Unexpected non-cash or malformed output: stop rather than simulate an unimplemented policy")
  when (ec /= ExitSuccess && not ("This cash-only version does not submit exposure in a confirmed uptrend" `isInfixOf` stderr)) (fail ("Unexpected executable failure: "++stderr))
  when present (putCopy (dest++"/orders.csv") (out++"/orders.csv"))
  hasManifest <- doesFileExist (dest++"/manifest.json")
  when hasManifest (putCopy (dest++"/manifest.json") (out++"/manifest.json"))
  pure (ok,obj [("exit_code",show (case ec of ExitSuccess -> 0; ExitFailure n -> n)),("accepted_header_only",if ok then "true" else "false"),("net_profit", "0"),("net_return","0"),("fees_paid","0"),("slippage_paid","0"),("log_path",q out),("accounting",q (if ok then "Valid no-trade; retain initial cash" else "Executable abort: no submission; rejected by brief, initial cash unchanged. Not a successful policy decision."))])
mean xs = sum xs / fromIntegral (length xs)
main = do
  args <- getArgs
  (d,compiler) <- case args of [a,b] -> pure (a,b); _ -> fail "Usage: offline-runner ARTIFACT_DIRECTORY GHC_PATH"
  raw <- readFile (d++"/public-bars.csv")
  let rows = lines raw
  unless (head rows == "t,close,volume" && length rows == 61) (fail "Unexpected copied public data")
  let prices = [read p :: Double | row <- tail rows, [_,p,_] <- [split row]]
  box <- prepare d
  runs <- forM [28..52] $ \t -> do
    (oldOK,oldResult) <- runOne d box rows "old" t
    (newOK,newResult) <- runOne d box rows "new" t
    let fill = prices!!(t+1); mark = prices!!(t+7)
        units = 1000 / (fill*1.0005*1.001)
        equity = units*mark; ret = equity/1000-1
        path = 1000 : [units*p | p <- take 7 (drop (t+1) prices)]
        peaks = scanl1 max path
        dd = maximum (zipWith (\p high -> 1-p/high) path peaks)
        result = obj [("decision_t",show t),("history_bars",show (t+1)),("fill_t",show (t+1)),("mark_t",show (t+7)),("fill_close",show fill),("mark_close",show mark),("old",oldResult),("new",newResult),("cash_equity","1000"),("buy_hold_equity",show equity),("buy_hold_return",show ret),("buy_hold_buy_fee",show (units*fill*1.0005*0.001)),("buy_hold_buy_slippage",show (units*fill*0.0005)),("buy_hold_max_marked_drawdown",show dd)]
    pure (oldOK,newOK,ret,dd,result)
  (replayOld,_) <- runOne d box rows "old" 59
  (replayNew,_) <- runOne d box rows "new" 59
  unless (replayOld && replayNew) (fail "Original public-decision replay failed")
  let n = length runs
      oldGood = length [() | (True,_,_,_,_)<-runs]
      newGood = length [() | (_,True,_,_,_)<-runs]
      returns = [r | (_,_,r,_,_)<-runs]
      metrics good = obj [("initial_equity_each_case","1000"),("mean_terminal_equity","1000"),("mean_net_profit","0"),("mean_net_return","0"),("cash_excess_return","0"),("positive_profit_cases","0"),("valid_no_trade_cases",show good),("executable_failure_cases",show (n-good)),("trades","0"),("max_marked_drawdown","0"),("mean_excess_return_vs_buy_hold",show (negate (mean returns))),("failure_accounting",q "Rejected executable produces no orders; unchanged cash is not counted as a valid strategy decision.")]
      compileOld = unwords [q compiler,"-O2 -outputdir",q (d++"/build-old"),q (d++"/ParentV1.hs"),"-o",q (d++"/old-parent")]
      compileNew = unwords [q compiler,"-O2 -outputdir",q (d++"/build-new"),q (d++"/CandidateV2.hs"),"-o",q (d++"/new-candidate")]
      compileRunner = unwords [q compiler,"-O2 -outputdir",q (d++"/build-runner"),q (d++"/Offline.hs"),"-o",q (d++"/offline-runner")]
      invoke = unwords [q (d++"/offline-runner"),q d,q compiler]
      report = obj
        [("status",q "completed"),("verification",q "AGENT-REPORTED exploratory offline evaluation; not independently verified improvement"),
         ("method",q "Compile exact OLD parent and offline NEW candidate independently. Execute each in an isolated chroot containing only copied public prefixes, binaries, runtime libraries and own source. 25 paired expanding-history decisions t=28..52, minimum warmup 29 bars, independent initial cash 1000 and zero units per case, mark t+7. Both receive identical prefixes/arguments. Original hard-coded paths resolve only inside this sandbox, never the live competition directory. Abort yields no submission and unchanged cash under the public rejection rule, and is separately counted as executable failure. Additionally replay original t=59 decision without scoring any unavailable future returns."),
         ("limitations",arr (map q ["Only 60 already-public observations from one index path; 25 overlapping cases are dependent and are not out-of-sample proof.","Candidate chosen after observing public data; reliability revision only. Both economic policies are cash; no profitable trading alpha or economic improvement is established.","OLD aborts in confirmed uptrends; zero returns on those cases reflect rejection/cash fallback, not successful old executions. All failures retained in logs.","Next-close pricing and cost accounting exercised by the buy-hold comparator; neither own strategy emits a trade, so tests do not validate an active execution path.","No private future data, no dates, no independent verification, and no future mark available for public t=59 replay.","Reproduction requires root, Linux chroot, GHC and the four shared libraries copied by the Haskell runner. No infrastructure or engine changes." ])),
         ("cases",show n),("old_metrics",metrics oldGood),("new_metrics",metrics newGood),
         ("costs",obj [("fee_bps","10"),("slippage_bps","5"),("buy_formula",q "units = cash / (next_close * (1+0.0005) * (1+0.001))"),("sell_formula",q "net proceeds = units * next_close * (1-0.0005) * (1-0.001); no sells in this experiment"),("own_total_fees","0"),("own_total_slippage","0"),("terminal_liquidation",q "none: mark remaining units, as in public brief")]),
         ("warmup",obj [("minimum_bars","29"),("mode",q "expanding prefix through decision t only")]),
         ("fill_policy",q "Decision at t; next-close fill t+1 with fee 10 bps and adverse slippage 5 bps; long-only no leverage; mark at t+7 (six fill-to-mark intervals). Header-only no trade remains cash. Each case resets, no chained or annualized return."),
         ("data_path",q (d++"/public-bars.csv")),("commands",arr (map q ["mkdir -p "++q (d++"/build-old")++" "++q (d++"/build-new")++" "++q (d++"/build-runner"),compileOld,compileNew,compileRunner,invoke])),
         ("buy_hold_metrics",obj [("mean_net_return",show (mean returns)),("minimum_net_return",show (minimum returns)),("maximum_net_return",show (maximum returns)),("positive_profit_cases",show (length (filter (>0) returns))),("max_case_marked_drawdown",show (maximum [dd | (_,_,_,dd,_)<-runs]))]),
         ("results",obj [("paired_cases",arr [r | (_,_,_,_,r)<-runs]),("original_public_decision_replay",obj [("decision_t","59"),("old_valid_cash","true"),("new_valid_cash","true"),("future_return",q "unavailable; excluded from 25 scored cases")]),("conclusion",q "Both strategies equal cash economically, with zero profit. Candidate improves executable completion across positive-momentum histories, not return. No performance promotion or next orders submitted.")])]
  writeFile (d++"/test-report.json") (report++"\n")
  printf "Completed %d paired PUBLIC cases. OLD valid=%d failures=%d; NEW valid=%d failures=%d. Both net profit=0. Mean cost-adjusted buy-hold return=%.6f%%. No economic alpha established.\n" n oldGood (n-oldGood) newGood (n-newGood) (100*mean returns)
