module Step where
import Data.IORef
import qualified Data.Map.Strict as M
import System.Process
import System.Directory
import Data.List
import Control.Monad

step :: IORef (M.Map String String) -> IORef (M.Map String (IO ())) -> IO Bool
step memory actions = do
  setCurrentDirectory "/workspace/.runs/battleships-1792358282"
  src <- readFile "Player.hs"
  length src `seq` copyFile "Player.hs" "Player-before-game2.hs"
  copyFile "player" "player-before-game2"
  writeFile "Incumbent.hs" (unlines [if l=="module Main where" then "module Incumbent where" else l | l<-lines src])
  let candidate=unlines [if "          let w=" `isPrefixOf` l then "          let w=if improved then (if m .&. hits/=0 then 1.0 else 0.85) / fromIntegral (popCount m) else 1.0" else l | l<-lines src]
  writeFile "Player.hs" candidate
  writeFile "Player-candidate-v2.hs" candidate
  writeFile "Compare.hs" $ unlines
    [ "module Compare where"
    , "import qualified Main as P"
    , "import qualified Incumbent as I"
    , "import Data.List"
    , "import System.IO"
    , "import Data.Time.Clock"
    , "import Control.Exception"
    , "import System.Directory"
    , "play :: ([P.Shot] -> Int) -> [[Int]] -> Int"
    , "play choose fleet=go [] where"
    , " go ss | length [()|P.Shot _ _ cs<-ss,not(null cs)]==3=length ss"
    , " go ss | length ss>=64=error \"did not finish\""
    , " go ss=let c=choose ss; tried=c:[x|P.Shot x _ _<-ss]; ship=find (elem c) fleet; (res,cs)=case ship of Nothing->(\"miss\",[]); Just xs->if all (`elem` tried) xs then (\"sunk\",xs) else (\"hit\",[]) in if c<0 || c>63 || c `elem` [x|P.Shot x _ _<-ss] then error \"invalid shot\" else go (ss++[P.Shot c res cs])"
    , "main=do"
    , " hSetBuffering stdout LineBuffering"
    , " t<-getCurrentTime"
    , " rs<-mapM (\\i->do"
    , "   let fleet=P.place (i*7919+104729) (i+1)"
    , "   a<-evaluate (play (I.choose True . map (\\(P.Shot c r cs)->I.Shot c r cs)) fleet)"
    , "   b<-evaluate (play (P.choose True) fleet)"
    , "   print (i,a,b)"
    , "   pure (a,b)) [0..47]"
    , " end<-getCurrentTime"
    , " let avg xs=fromIntegral (sum xs)/fromIntegral (length xs)::Double"
    , " let a=avg(map fst rs); b=avg(map snd rs); keep=b<=a"
    , " writeFile \"comparison-game2.json\" (\"{\\\"boards\\\":48,\\\"incumbent_mean\\\":\"++show a++\",\\\"candidate_mean\\\":\"++show b++\",\\\"candidate_retained\\\":\"++(if keep then \"true\" else \"false\")++\",\\\"seconds\\\":\"++show(realToFrac(diffUTCTime end t)::Double)++\",\\\"source\\\":\\\"same local generated fleets, not host hidden benchmark\\\"}\\n\")"
    , " unlessKeep keep"
    , "unlessKeep True=pure ()"
    , "unlessKeep False=do copyFile \"Player-before-game2.hs\" \"Player.hs\"; copyFile \"player-before-game2\" \"player\""
    ]
  (ec,o,e) <- readProcessWithExitCode "sh" ["-c","stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson Player.hs -o player > build-game2.log 2>&1 && stack --stack-yaml /workspace/stack.yaml --allow-different-user exec -- ghc -O2 -package aeson -main-is Compare Compare.hs Player.hs Incumbent.hs -o compare >>build-game2.log 2>&1 && ./compare > comparison-game2.log; cat build-game2.log; tail -3 comparison-game2.log; cat comparison-game2.json"] ""
  print ec
  putStrLn o
  putStrLn e
  ok <- doesFileExist "comparison-game2.json"
  unless ok $ do
    copyFile "Player-before-game2.hs" "Player.hs"
    copyFile "player-before-game2" "player"
  (pec,po,pe) <- readProcessWithExitCode "./player" [] (unlines
    ["{\"phase\":\"place\",\"seed\":123,\"round\":3}"
    ,"{\"phase\":\"shoot\",\"shots\":[]}"
    ,"{\"phase\":\"shoot\",\"shots\":[{\"cell\":18,\"result\":\"hit\",\"sunk\":[]},{\"cell\":26,\"result\":\"sunk\",\"sunk\":[18,26]}]}"
    ])
  putStrLn ("Observed protocol status "++show pec)
  putStrLn po
  putStrLn pe
  writeFile "protocol-game2.jsonl" po
  measure <- if ok then readFile "comparison-game2.json" else pure "null"
  writeFile "evidence.json" $ "{\"phase\":\"after game 2\",\"trace_observation\":\"Public round-2 trace found and sank length-2 at cells 18,26 early, followed by a run of hunt misses. No opponent fleet inspected.\",\"weakness\":\"Incumbent weights using count of untried cells rather than true ship length; this changes weights as hits accumulate, and weakly values small-ship discovery.\",\"hypothesis\":\"Weight each consistent fleet cell inversely by its actual ship length, retaining target preference and hunt lattice, to prioritize progress on small hard-to-find ships.\",\"measured\":"++measure++",\"reusable_helper\":\"Compare.hs compares independently reset incumbent/candidate policies on identical 48 legal fleets, validates shots, records means and automatically rolls back regressions.\",\"artifacts\":[\"Player-before-game2.hs\",\"player-before-game2\",\"Player-candidate-v2.hs\",\"comparison-game2.log\",\"protocol-game2.jsonl\"],\"claims\":\"Local measurements only; hidden benchmark and match outcomes are separate.\"}\n"
  writeFile "ready.json" "{\"ready\":true}\n"
  putStrLn "Ready; measured selection applied automatically, prior executable and sources preserved."
  pure False