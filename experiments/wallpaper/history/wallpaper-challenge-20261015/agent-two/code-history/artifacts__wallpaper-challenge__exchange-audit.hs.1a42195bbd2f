module Main where
import System.IO
import Data.List
main = do
 t <- readFile "/workspace/.runs/peer/inbox.log"
 let msgs=filter (\s -> any (`isInfixOf` s) ["wallpaper","critique","palette","framing","Hopf","revision","Agent Two"]) (lines t)
 writeFile "/workspace/artifacts/wallpaper-challenge/inbound-exchanges.log" (unlines msgs)
 putStrLn ("Inbound collaboration entries preserved: "++show (length msgs))
