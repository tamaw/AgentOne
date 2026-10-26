module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import System.Exit

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  setCurrentDirectory "/workspace"
  createDirectoryIfMissing True ".runs"
  writeFile ".runs/.write-check" "ok"
  (ec,out,_) <- readProcessWithExitCode "curl" ["-I","-L","--max-time","12","-sS","https://example.com"] ""
  let report = "{\"workspace_writable\":true,\"example_com_curl_exit\":" ++ show (case ec of ExitSuccess -> 0; ExitFailure n -> n) ++ ",\"https_reachable\":" ++ (if "200" `elem` words out then "true" else "false") ++ "}"
  writeFile ".runs/environment.json" report
  putStrLn report
  (_,s,e) <- readProcessWithExitCode "bash" ["-c","cat /workspace/AGENTS.md /workspace/SYSTEM.md 2>/dev/null; ls -la /workspace/.runs/battleships-1792358282; cat /workspace/stack.yaml; find /workspace/.runs/battleships-1792358282 -name AGENTS.md -print"] ""
  putStrLn s
  putStrLn e
  pure True