module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import Data.List

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  src <- readFile "Player.hs"
  let src' = unlines $ "{-# LANGUAGE FlexibleContexts #-}" : map (\l -> if l=="         l<-B.getLine" then "         l<-B.pack <$> getLine" else l) (filter (/="import Control.Exception") (lines src))
  length src' `seq` writeFile "Player.hs" src'
  copyFile "Player.hs" "Player-candidate-v1.hs"
  writeFile "Evaluate.hs" $ unlines
    [ "module Evaluate where"
    , "import qualified Main as P"
    , "import Data.List"
    , "import System.IO"
    , "import Data.Time.Clock"
    , "import Control.Exception"
    , "play :: Bool -> [[Int]] -> Int"
    , "play improved fleet=go [] where"
    , " go ss | length [()|P.Shot _ _ cs<-ss,not(null cs)]==3=length ss"
    , " go ss | length ss>=64=64"
    , " go ss=let c=P.choose improved ss; tried=c:[x|P.Shot x _ _<-ss]; ship=find (elem c) fleet; (res,cs)=case ship of Nothing->(\"miss\",[]); Just xs->if all (`elem` tried) xs then (\"sunk\",xs) else (\"hit\",[]) in if c `elem` [x|P.Shot x _ _<-ss] then error \"duplicate shot\" else go (ss++[P.Shot c res cs])"
    , "main=do"
    , " hSetBuffering stdout LineBuffering"
    , " t<-getCurrentTime"
    , " rs<-mapM (\\i->do"
    , "   let fleet=P.place (i*7919+104729) (i+1)"
    , "   a<-evaluate (play False fleet)"
    , "   b<-evaluate (play True fleet)"
    , "   print (i,a,b)"
    , "   pure (a,b)) [0..47]"
    , " end<-getCurrentTime"
    , " let avg xs=fromIntegral (sum xs)/fromIntegral (length xs)::Double"
    , " writeFile \"measurements.json\" (\"{\\\"boards\\\":48,\\\"baseline_mean_shots\\\":\"++show(avg(map fst rs))++\",\\\"candidate_mean_shots\\\":\"++show(avg(map snd rs))++\",\\\"elapsed_seconds\\\":\"++show(realToFrac(diffUTCTime end t)::Double)++\",\\\"source\\\":\\\"local deterministic generated fleets, not host hidden benchmark\\\"}\\n\")"
    ]
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player > build.log 2>&1 && stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson -main-is Evaluate Evaluate.hs Player.hs -o evaluate >>build.log 2>&1; cat build.log; if test -x player; then printf '%s\\n' '{\"phase\":\"place\",\"seed\":123,\"round\":1}' '{\"phase\":\"shoot\",\"seed\":123,\"round\":1,\"shots\":[]}' '{\"phase\":\"shoot\",\"shots\":[{\"cell\":27,\"result\":\"hit\",\"sunk\":[]}]}' | ./player | tee protocol-check.jsonl; fi"] ""
  print ec
  putStrLn o
  putStrLn e
  exists <- doesFileExist "evaluate"
  if exists then do
    _ <- createProcess (shell "./evaluate > evaluation.log 2>&1") {std_in=NoStream,std_out=NoStream,std_err=NoStream}
    _ <- readProcess "sleep" ["25"] ""
    x <- readProcess "sh" ["-c","tail -5 evaluation.log; cat measurements.json 2>/dev/null || true"] ""
    putStrLn x
    pure True
  else pure True