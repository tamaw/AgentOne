module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import Control.Exception

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace"
  createDirectoryIfMissing True ".runs"
  (ec,out,err) <- readProcessWithExitCode "sh" ["-c","pwd; ls -la | head -25; find .. -name AGENTS.md -print 2>/dev/null | head -20; cat AGENTS.md; cat SYSTEM.md; printf '\\n---network---\\n'; curl -I -sS --max-time 12 https://example.com | head -1; printf '\\n---stack---\\n'; cat stack.yaml; cat agent-one.cabal"] ""
  writeFile ".runs/.write-check" "ok"
  writeFile ".runs/environment.json" ("{\"workspace\":\"/workspace\",\"write_ok\":true,\"inspection\":" ++ show (out ++ err) ++ "}\n")
  putStrLn out
  putStrLn err
  modifyIORef' memory (M.insert "startup" "done")
  pure True