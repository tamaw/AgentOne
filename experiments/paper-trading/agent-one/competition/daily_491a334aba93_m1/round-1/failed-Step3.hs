module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Exit
import System.Directory
import System.FilePath
import Data.List (isPrefixOf)
import Control.Monad

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  let root = "/workspace/competition/daily_491a334aba93_m1"
      run = root </> "round-1"
      parent = root </> "round-0/strategy-v1.hs"
      source = run </> "strategy-v1.1.hs"
      dest = "/shared/competition/daily_491a334aba93_m1/round-1/agent-one"
      bars = "/shared/competition/daily_491a334aba93_m1/round-1/bars.csv"
      expectedParent = "7eb5f725e9185e607743fa170a1522ee2c217607d1f677832bbe085228fa9dd1"
  createDirectoryIfMissing True run
  let record name command = do
        writeFile (run </> name ++ ".command") (command ++ "\n")
        (ec,out,err) <- readCreateProcessWithExitCode (shell command) ""
        writeFile (run </> name ++ ".stdout") out
        writeFile (run </> name ++ ".stderr") err
        writeFile (run </> name ++ ".exit") (show ec ++ "\n")
        putStrLn (name ++ ": " ++ show ec)
        unless (null out) (putStrLn out)
        unless (null err) (putStrLn err)
        pure (ec,out)
  (pec,pout) <- record "parent-hash" ("sha256sum " ++ parent)
  unless (pec == ExitSuccess && take 64 pout == expectedParent) (fail "Parent snapshot mismatch; stopped without submission.")
  already <- doesFileExist source
  when already (fail "Round source already exists; refusing retry or repair.")
  old <- readFile parent
  let changes = "Version v1.1; source=\" ++ ref ++ \"; parent=v1 sha256:" ++ expectedParent ++ "; effective_round=1. Hypothesis unchanged: multi-horizon positive trends may persist, with volatility-limited exposure reducing risk. Actual trading-rule/parameter changes: none; retain 20/7 lookbacks, trend-score threshold 0.5, SMA20 gate, 0.01 daily-volatility budget, 0.5 exposure cap, last-observed-close sizing and fee/slippage constants. Edits are provenance and execution-status reporting only; cash=1000 and units=0 per authorized state. Adopt settled round-0 coaching and agent-two horizon tip as assessment principles: next-close fill to decision+7 is six intervals; pre-fill movement is not a tradable gain. Adopt cash plus cost-matched passive comparisons and exposure/drawdown caveats for interpretation, not as new trading signals. No walk-forward evaluation or matched replay performed; no tested improvement claimed. Reject copying peer AR parameters or increasing exposure from one favorable settlement: insufficient evidence, and KB comparative/regime evidence was unavailable. Round-0 valid hold missed benchmark upside but does not by itself disprove the filter. One build and one decision execution, no retries or repair."
      transform line
        | "     changes = " `isPrefixOf` line = "     changes = \"" ++ changes ++ "\""
        | " putStrLn \"Submission written once;" `isPrefixOf` line =
            " putStrLn (if qty>0 then \"Decision status: order submission generated successfully (not settlement).\" else \"Decision status: intentional valid hold, not execution failure.\")\n" ++ line
        | otherwise = line
  writeFile source (unlines (map transform (lines old)))
  copyFile bars (run </> "observations.csv")
  copyFile "/shared/competition/daily_491a334aba93_m1/round-0/evidence.md" (run </> "previous-evidence.md")
  copyFile "/shared/competition/daily_491a334aba93_m1/round-0/learning.json" (run </> "previous-learning.json")
  (hec,hout) <- record "source-hash" ("sha256sum " ++ source)
  unless (hec == ExitSuccess && length (takeWhile (/=' ') hout) == 64) (fail "Source hashing failed; stopped.")
  let hash = takeWhile (/=' ') hout
      ref = source ++ "#sha256=" ++ hash
  modifyIORef' memory (M.insert "btc_round1_source" ref)
  (bec,_) <- record "build" ("cd " ++ run ++ " && ghc -O2 -fforce-recomp -outputdir build strategy-v1.1.hs -o strategy-v1.1")
  if bec /= ExitSuccess
    then do
      modifyIORef' memory (M.insert "btc_round1_status" "build_failed_no_retry")
      putStrLn "Build failed; no retry, repair, or orders attempted."
      pure False
    else do
      (eec,_) <- record "execute" (run </> "strategy-v1.1" ++ " " ++ bars ++ " " ++ dest ++ " '" ++ ref ++ "'")
      if eec /= ExitSuccess
        then do
          modifyIORef' memory (M.insert "btc_round1_status" "execution_failed_no_retry"))
          putStrLn "Strategy execution failed; no retry, repair, or resubmission."
          pure False
        else do
          o <- readFile (dest </> "orders.csv")
          m <- readFile (dest </> "manifest.json")
          writeFile (run </> "orders-readback.csv") o
          writeFile (run </> "manifest-readback.json") m
          putStrLn "--- Orders readback ---"
          putStrLn o
          putStrLn "--- Manifest readback ---"
          putStrLn m
          modifyIORef' memory (M.insert "btc_round1_status" "submitted_readback_complete")
          pure True