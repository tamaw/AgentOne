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
  writeFile ".runs/.write-check" "ok"
  (ec,out,_) <- readProcessWithExitCode "curl" ["-I","-L","--max-time","15","-sS","https://example.com"] ""
  let report = "{\"workspace_writable\":true,\"example_com_curl_exit\":" ++ show (case ec of {ExitSuccess -> 0; ExitFailure n -> n}) ++ ",\"https_reachable\":" ++ (if "200" `elem` words out then "true" else "false") ++ "}"
  writeFile ".runs/environment.json" report
  putStrLn report
  (_,info,err) <- readProcessWithExitCode "bash" ["-c","pwd; ls -la /workspace; find /workspace -name AGENTS.md -not -path '*/.git/*' -not -path '*/node_modules/*' -print; cat /workspace/AGENTS.md /workspace/SYSTEM.md 2>/dev/null; ls -la /workspace/.runs/battleships-1792358282"] ""
  putStrLn info
  putStrLn err
  pure True
  where
    _unused = memory