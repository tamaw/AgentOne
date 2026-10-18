module StepLoader (StepAction, loadStep) where
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Language.Haskell.Interpreter as H
import System.Timeout (timeout)
import System.Directory (doesFileExist)
type StepAction = IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
loadStep :: FilePath -> IO (Either H.InterpreterError StepAction)
loadStep path = do
  exists <- doesFileExist path
  result <- if exists then timeout 20000000 (compileStep path)
    else pure (Just (Left (H.UnknownError ("Step source is absent or not a regular file: " ++ show path))))
  pure $ maybe (Left (H.UnknownError "Step compilation exceeded 20-second budget")) id result

compileStep :: FilePath -> IO (Either H.InterpreterError StepAction)
compileStep path = H.runInterpreter $ do
  H.set [H.searchPath H.:= ["src", "."]]
  H.loadModules [path]
  H.setTopLevelModules ["Step"]
  H.setImports ["Prelude", "Data.IORef", "Data.Map.Strict"]
  H.interpret "Step.step" (H.as :: StepAction)
