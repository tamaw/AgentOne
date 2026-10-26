module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
 setCurrentDirectory "/workspace/.runs/battleships-1792358282"
 (c,o,e)<-readProcessWithExitCode "bash" ["-c","cat AGENTS.md; cat feedback.json; cat evidence.json; cat Fleet.hs; cat Evaluate.hs; ls -l"] ""
 print c
 putStrLn o
 putStrLn e
 pure True