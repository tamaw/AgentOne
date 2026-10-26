module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Exit
import System.Directory
import Data.Time.Clock
import qualified Data.ByteString.Lazy.Char8 as B

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory _ = do
  createDirectoryIfMissing True "/workspace/.runs"
  w <- doesDirectoryExist "/workspace"
  (ec,_,_) <- readProcessWithExitCode "sh" ["-c","curl -L --max-time 10 -s -o /dev/null -w '%{http_code}' https://example.com"] ""
  t <- getCurrentTime
  let json = "{\"workspaceWritable\":" ++ if w then "true" else "false" ++ ",\"exampleCom\":\"" ++ show ec ++ "\",\"observedAt\":\"" ++ show t ++ "\"}\n"
  writeFile "/workspace/.runs/environment.json" json
  (ec2,out,err) <- readProcessWithExitCode "sh" ["-c","cd /workspace && cat SYSTEM.md 2>/dev/null; printf '\\n---AGENTS---\\n'; cat AGENTS.md 2>/dev/null; printf '\\n---RUN---\\n'; ls -la .runs/battleships-1792363073 2>/dev/null || true; printf '\\n---STACK---\\n'; ls stack.yaml 2>/dev/null || true"] ""
  putStrLn ("environment saved: workspace=" ++ show w ++ " network=" ++ show ec)
  putStrLn (take 12000 (out ++ err))
  modifyIORef' memory (M.insert "phase" "inspect")
  pure True