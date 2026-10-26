module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  (_,o,e) <- readProcessWithExitCode "sh" ["-c","cat feedback.json; cat Player.hs; cat evidence.json; cat Compare.hs"] ""
  putStrLn o
  putStrLn e
  pure True