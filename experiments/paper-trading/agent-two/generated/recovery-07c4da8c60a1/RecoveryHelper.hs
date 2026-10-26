module Main where
import System.Environment
import System.FilePath
import System.Process
import System.Exit
import System.Directory
import Control.Monad
main :: IO ()
main = do
  exe <- getExecutablePath
  let root = takeDirectory exe
      compilerDir = "/home/tama/.stack/programs/x86_64-linux/ghc-tinfo6-9.6.7/bin"
      compiler = compilerDir </> "ghc"
      cleanEnv = [("HOME","/root"),("PATH",compilerDir ++ ":/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"),("LANG","C.UTF-8"),("STACK_ROOT",root </> "stack-root"),("STACK_YAML",root </> "stack.yaml")]
      stackArgs = ["--stack-root",root </> "stack-root","--stack-yaml",root </> "stack.yaml"]
      run binary args = do
        (_,_,_,p) <- createProcess (proc binary args) { env=Just cleanEnv, cwd=Just root }
        ec <- waitForProcess p
        unless (ec==ExitSuccess) (exitWith ec)
  present <- doesFileExist compiler
  unless present (die ("Configured compiler absent: " ++ compiler))
  args <- getArgs
  case args of
    ["proof"] -> do
      run "/usr/bin/stack" (stackArgs ++ ["exec","--",compiler,"-fforce-recomp","-O0","-outputdir",root,"-o",root </> "compiler-proof",root </> "CompilerProof.hs"])
      run (root </> "compiler-proof") []
    "ghc":rest -> run "/usr/bin/stack" (stackArgs ++ ["exec","--",compiler] ++ rest)
    _ -> die "Usage: recovery-helper proof | recovery-helper ghc ARGS..."
