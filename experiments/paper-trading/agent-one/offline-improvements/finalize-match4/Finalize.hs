{-# LANGUAGE OverloadedStrings #-}
module Main where
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Data.Aeson as J
import qualified Data.Aeson.KeyMap as K
import qualified Data.ByteString.Lazy as B
import qualified Data.Text as T
import Data.Scientific (floatingOrInteger)
import System.Directory
import System.Process
import Control.Monad
root :: FilePath
root = "/shared/competition/paper_1c0f5ea46b22/match-4/agent-one"
field :: J.Key -> J.Value -> J.Value
field k (J.Object o) = maybe J.Null id (K.lookup k o)
field _ _ = J.Null
textField :: J.Key -> J.Value -> IO String
textField k v = case field k v of
  J.String t | not (T.null (T.strip t)) -> pure (T.unpack t)
  _ -> fail ("Missing nonempty string " ++ show k)
readJSON :: FilePath -> IO J.Value
readJSON p = do
  b <- B.readFile p
  either fail pure (J.eitherDecode b)
check :: Bool -> String -> IO ()
check b m = unless b (fail m)
step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory _ = do
  let hyp = "Changing only the nominal entry budget from 250 to 125 dollars will reduce maximum episode marked drawdown to at most 60% of the parent's, improve mean net episode profit by at least 0.25 dollars on the 33 reused public episodes t=20..52, keep identical entry-signal counts with at least three fills and zero rejections. Otherwise retain the parent. This is a sizing/risk hypothesis, not a new predictive-alpha claim."
      parent = "v5-match4-metadata#sha256=8965d5a27803c110d90fcc4dc590735c0c466a645b2e3c41196bcdff989de313"
      candidate = "v6-risk125-offline#sha256=6c37d5428336223e8243e6444c5ed5f05779d15c2b4c8c6917e02685ef1377c3"
      tips =
        [ "For the other agent: distinguish benchmark outperformance from absolute capital preservation; a positive benchmark gap in a falling market can coexist with losses and does not establish a profitable entry signal."
        , "For the other agent: test a single fixed risk-budget ablation with unchanged signal, warmup, fills and cost rates; smaller positions mechanically scale both gains and losses, so reduced drawdown should not be presented as improved forecasting."
        , "For the other agent: declare acceptance thresholds before replay and label reused overlapping windows as dependent development data; known negative returns can make a sizing improvement predictable without providing held-out evidence."
        , "For the other agent: report total fee/slippage dollars as well as identical cost rates and fill counts; a sizing change alters friction dollars even when turnover counts and execution assumptions are unchanged."
        ] :: [String]
  report <- readJSON (root++"/test-report.json")
  check (field "status" report == J.String "completed") "Offline report not completed"
  case field "cases" report of
    J.Number n -> case (floatingOrInteger n :: Either Double Integer) of
      Right i -> check (i > 0) "No cases"
      _ -> fail "Noninteger cases"
    _ -> fail "Missing cases"
  forM_ ["method","limitations","fill_policy","data_path"] $ \k -> void (textField k report)
  forM_ ["old_metrics","new_metrics","costs"] $ \k -> case field k report of
    J.Object o -> check (not (K.null o)) ("Empty report object " ++ show k)
    _ -> fail ("Missing report object " ++ show k)
  check (field "declared_before_this_replay_hypothesis_passed" report == J.Bool True) "Declared criterion did not pass"
  let artifact = J.object
        [ "agent" J..= ("agent-one" :: String)
        , "review" J..= ("Match-4 public scoreboard: equity 992.8983450251793, profit -7.10165497482069, return -0.00710165497482069, one applied trade, zero failures. Benchmark equity 968.7707602879149, profit -31.229239712085132, return -0.031229239712085133. Benchmark gap +0.024127584737264444 (+2.4127584737264444 percentage points). Agent-one won this reported match but lost capital. Weaknesses: momentum can buy failed rallies; prior reused development mean is negative. Quarter-budget exposure partly shields a falling benchmark but neither proves positive alpha nor repairs entry timing. Lower exposure can exacerbate rally underparticipation; this proposal addresses loss magnitude, not forecasting." :: String)
        , "hypothesis" J..= (hyp :: String)
        , "parent_version" J..= (parent :: String)
        , "candidate_version" J..= (candidate :: String)
        , "decision" J..= ("revise" :: String)
        , "changes" J..= ("Preserved submitted match-4 parent byte-for-byte. One offline proposal only: nominal entry budget 250 -> 125 dollars. Unchanged 21-close warmup, r10>0.006 and r5>0 signal, 1.10 heuristic buffer, ten-decimal rounding, next-close fills, 10bp fee, 5bp slippage and all-or-none cash checks. Candidate manifest rewritten for truthful offline provenance; executable signal unchanged. Predeclared risk/profit criteria passed on reused public development data, so select revised OFFLINE source. No infrastructure, live trading, prior submitted source or current orders changed. This is not a claim of improved alpha." :: String)
        , "source_path" J..= (root++"/candidate-v6-risk125.hs")
        , "parent_source_path" J..= (root++"/parent-v5-match4.hs")
        , "test_report_path" J..= (root++"/test-report.json")
        , "selected_source_path" J..= (root++"/candidate-v6-risk125.hs")
        , "selected_version" J..= (candidate :: String)
        , "hypothesis_passed" J..= True
        , "result_interpretation" J..= ("33 paired dependent episodes: old/new mean net profit -0.662622092910052 / -0.3313110464643449 dollars, improvement 0.3313110464457071 dollars. Maximum marked drawdown 0.01595635695141914 / 0.0079781784760047, approximately half; worst profit -15.956356951419139 / -7.9781784760047 dollars. Both had six signals, six fills, zero rejections. Entry friction totals 2.0035503793262897 / 1.0017751896757883 dollars. Mean benchmark-relative returns -0.0005785506628508972 / -0.00024723961640519046: both still lag the episode benchmark on average. Five stride-seven outcomes: mean profits -0.8850545791014156 / -0.4425272895507078. Negative mean remains; improvement is expected exposure scaling, not timing skill. Neither 33 overlapping windows nor five diagnostic windows establish independent or future effectiveness." :: String)
        , "provenance" J..= ("Reviewed public match-4 scoreboard, exact submitted source, and own prior public-data replay before recording hypothesis-before-replay.json and compiling. Budget choice was informed by the already-known negative mean on this reused development path. Separately compiled preserved old and new Haskell programs with ghc -O2, then executed each on identical 21-or-more-close prefixes t=20..52 of copied public bars t=0..59. Evaluator alone reads already-public outcome closes; no private judge data or unseen future observations. Data copied from match-3/agent-one/public-bars.csv, previously reused from earlier matches. Matched judge replay unavailable. These are agent-run offline tests, not independent judge verification. Later adaptation is allowed with truthful provenance; no freeze implied." :: String)
        , "public_data_sha256" J..= ("26d0bf87d02f33a19f6e734ab561b025c3a1869674ee57316aa49ce170f854b5" :: String)
        , "independent_judge_verification" J..= False
        , "shared_tips" J..= tips
        ]
  B.writeFile (root++"/improvement.json") (J.encode artifact)
  readback <- readJSON (root++"/improvement.json")
  check (readback == artifact) "Improvement readback mismatch"
  forM_ ["review","hypothesis","parent_version","candidate_version","changes"] $ \k -> void (textField k readback)
  forM_ ["source_path","parent_source_path","test_report_path"] $ \k -> do
    p <- textField k readback
    check (take (length (root++"/")) p == root++"/") "Artifact outside agent directory"
    doesFileExist p >>= \b -> check b ("Missing artifact "++p)
  dataPath <- textField "data_path" report
  check (dataPath == root++"/public-bars.csv") "Incorrect public data path"
  doesFileExist dataPath >>= \b -> check b "Public data missing"
  check (not (null tips) && all (not . null) tips) "Invalid shared tips"
  old <- readFile (root++"/parent-v5-match4.hs")
  original <- readFile "/shared/competition/paper_1c0f5ea46b22_m4/round-0/agent-one/source-v5-match4-metadata.hs"
  check (old==original) "Parent not byte-exact"
  let mirror = "/workspace/offline-improvements/paper_1c0f5ea46b22-match4-agent-one"
  createDirectoryIfMissing True mirror
  (c,o,e) <- readCreateProcessWithExitCode (shell ("cd "++root++" && sha256sum parent-v5-match4.hs candidate-v6-risk125.hs public-bars.csv OfflineReplay.hs test-report.json improvement.json > artifact-sha256.txt && cp parent-v5-match4.hs candidate-v6-risk125.hs public-bars.csv OfflineReplay.hs test-report.json improvement.json hypothesis-before-replay.json paired-cases.csv artifact-sha256.txt "++mirror++"/ && cat artifact-sha256.txt")) ""
  check (show c == "ExitSuccess") ("Artifact persistence failed: "++e)
  modifyIORef' memory (M.insert "match4-improvement" (root++"/improvement.json"))
  putStrLn o
  putStrLn "Completed offline revision and readback validation: improvement.json and completed 33-case test-report.json are under match-4/agent-one. Half-budget candidate reduced maximum marked drawdown approximately 50%; mean profit improved from -0.662622 to -0.331311 dollars on reused public data. Four general tips published. Negative mean persists; no held-out or independent judge verification claimed."
  pure False
main :: IO ()
main = do
  m <- newIORef M.empty
  a <- newIORef M.empty
  _ <- step m a
  pure ()
