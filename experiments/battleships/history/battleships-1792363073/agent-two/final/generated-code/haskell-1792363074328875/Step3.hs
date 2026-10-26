module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
  (_,o,e) <- readProcessWithExitCode "sh"
    ["-c", "cd /workspace/.runs/battleships-1792363073 && find . -maxdepth 3 -type f -printf '%p %s\\n' | head -100; cat > Eval.hs <<'EOF'\nimport System.Process\nimport System.Exit\nimport Data.Time.Clock\nmain=do\n let q=\"{\\\"phase\\\":\\\"shoot\\\",\\\"seed\\\":123,\\\"round\\\":1,\\\"shots\\\":[{\\\"cell\\\":0,\\\"result\\\":\\\"miss\\\",\\\"sunk\\\":[]},{\\\"cell\\\":9,\\\"result\\\":\\\"hit\\\",\\\"sunk\\\":[]},{\\\"cell\\\":17,\\\"result\\\":\\\"miss\\\",\\\"sunk\\\":[]},{\\\"cell\\\":18,\\\"result\\\":\\\"miss\\\",\\\"sunk\\\":[]}]}\\n\"\n t<-getCurrentTime\n (x,a,b)<-readProcessWithExitCode \"./player\" [] q\n u<-getCurrentTime\n print (x,a,realToFrac (diffUTCTime u t)::Double,b)\nEOF\nstack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 Eval.hs -o eval && ./eval\nprintf '%s\\n' '{\"phase\":\"shoot\",\"seed\":1,\"round\":2,\"shots\":[{\"cell\":0,\"result\":\"miss\",\"sunk\":[]},{\"cell\":1,\"result\":\"sunk\",\"sunk\":[1,2]}]}' | timeout 2 ./player\n"] ""
  putStrLn (take 12000 (o ++ e))
  pure True