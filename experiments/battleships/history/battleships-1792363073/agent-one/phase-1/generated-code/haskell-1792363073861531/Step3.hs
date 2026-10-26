module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace"
  e <- doesDirectoryExist ".runs/battleships-1792363073"
  putStrLn ("challengeDirectoryExists=" ++ show e)
  if e
    then do
      xs <- readProcess "sh" ["-c","find .runs/battleships-1792363073 -maxdepth 1 -type f -printf '%f\\n' | sort"] ""
      putStrLn xs
    else pure ()
  pure True