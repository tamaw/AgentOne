module RequestGate (awaitSuperseded, resetIfStarted, beginExecution, finishExecution, failureFeedback, pauseIfCurrent, pauseFeedback) where
import Control.Concurrent.STM
awaitSuperseded :: TVar Bool -> TVar Int -> Int -> STM ()
awaitSuperseded paused generation expected = do
  stopped <- readTVar paused
  current <- readTVar generation
  check (stopped || current /= expected)

resetIfStarted :: TVar Bool -> IO () -> IO Bool
resetIfStarted started reset = do
  active <- readTVarIO started
  if active then reset >> pure True else pure False

beginExecution :: TVar Bool -> TVar Int -> Int -> TVar Bool -> STM Bool
beginExecution paused generation expected started = do
  stopped <- readTVar paused
  current <- readTVar generation
  if stopped || current /= expected then retry
    else writeTVar started True >> pure True

finishExecution :: TVar Bool -> STM ()
finishExecution started = writeTVar started False

failureFeedback :: Bool -> String -> String
failureFeedback pending detail =
  (if pending then "Execution failed and may have partially run:\n"
   else "Request or post-execution reporting failed; no execution is pending:\n") ++ boundedFailure detail

boundedFailure :: String -> String
boundedFailure detail
  | length (take 2401 detail) <= 2400 = detail
  | otherwise =
      take 1500 detail ++
      "\n[error detail elided; full redacted error is in this session's events.jsonl]\n" ++
      drop (max 0 (length detail - 700)) detail

pauseIfCurrent :: TVar Bool -> TVar Int -> Int -> STM Bool
pauseIfCurrent paused generation expected = do
  current <- readTVar generation
  if current == expected then writeTVar paused True >> pure True
    else pure False

pauseFeedback :: Bool -> String
pauseFeedback True = "[failure paused this request; /resume retries; /quit exits]"
pauseFeedback False = "[stale failure did not change pause state; newer user input retained]"
