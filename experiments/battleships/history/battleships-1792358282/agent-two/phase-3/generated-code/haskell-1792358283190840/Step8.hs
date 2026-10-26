module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Directory
import System.Process

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step _ _ = do
 setCurrentDirectory "/workspace/.runs/battleships-1792358282"
 mapM_ (\f -> readFile f >>= \s -> putStrLn (f++"\n"++s)) ["feedback.json","evidence.json","Fleet.hs","Compare.hs"]
 pure True