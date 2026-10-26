module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","cat feedback.json; printf '\\n---SOURCE---\\n'; cat Player.hs; printf '\\n---FILES---\\n'; ls -l; printf '\\n---EVIDENCE---\\n'; cat evidence.json 2>/dev/null; cat measurements.json; cat Evaluate.hs"] ""
  print ec
  putStrLn o
  putStrLn e
  pure True