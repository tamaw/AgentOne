module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  (_,o,e) <- readProcessWithExitCode "sh" ["-c","cat selection.json evidence.json; printf '\\n---HELPER---\\n'; cat Compare.hs; printf '\\n---PLAYER---\\n'; cat Player.hs; printf '\\n---RULES---\\n'; cat /workspace/AGENTS.md /workspace/SYSTEM.md"] ""
  putStrLn o
  putStrLn e
  pure True